# stat_editor_util.gd
# ----------------------------------------------------------------------------
# Project Nexus - Data-driven Stat editor helper (plan v4, phase MD12.1).
#
# The Mod Editor's stat picker must be built DYNAMICALLY from the data-driven
# StatRegistry (section MD1/MD2), not from a hand-coded list of three fields.
# This PURE, headless-testable util produces the *plan* the UI renders:
#
#   catalog ("unit"/"building"/"object")
#       --StatRegistry.ids_for + per-stat metadata-->
#   a list of stat descriptors, GROUPED BY `category`, and PAGINATED so a phone
#   screen never has to show more than a fixed cap of controls at once.
#
# Design rules (Definition of Done, plan section 2 constant principles):
#   - PURE INFRASTRUCTURE: RefCounted, no SceneTree / WorldState / sim-hash
#     dependency. It only DESCRIBES what the editor should draw. The editor
#     (ui/shared/mod_editor.gd, MD12.2) turns each descriptor into a widget.
#   - DETERMINISTIC: ids are emitted in a stable order (stat ids sorted inside
#     each group; groups sorted by category id) so the same query always yields
#     byte-for-byte the same layout -- friendly to UI diffing and to tests.
#   - COSMETIC (section 2.2): the descriptors carry no simulation state and this
#     util never touches state_hasher. It reads metadata only.
#   - RESILIENCE (section 2.5): an unknown catalog / a stat missing metadata
#     never crashes -- it degrades to sensible defaults (int, category "misc").
#   - English-only identifiers/comments (CODE_POLICY); any author-facing label
#     the UI shows is resolved by the caller through Localization
#     (key `stat.<id>.name`, MD12.5) with the raw id as the fallback.
# ----------------------------------------------------------------------------
class_name StatEditorUtil
extends RefCounted

# Category id used when a stat declares no category (resilient fallback).
const MISC_CATEGORY: String = "misc"

# Default per-page cap tuned for a phone screen. The editor may pass its own cap
# (e.g. a larger one on tablets) but this is the safe mobile default.
const DEFAULT_PAGE_SIZE: int = 8


# A single stat descriptor the editor turns into one control. Everything the UI
# needs is here so the view stays thin (MD12.2). `registry` is StatRegistry (or a
# stub exposing the same static getters); may be null -> pure fallbacks apply.
static func describe_stat(id: String, registry: Object = null) -> Dictionary:
	var sid: String = str(id)
	var out: Dictionary = {
		"id": sid,
		"name_key": "stat.%s.name" % sid,
		"value_type": "int",
		"category": MISC_CATEGORY,
		"min": 0.0,
		"max": 0.0,
		"default": 0,
		"needs_value": true,
		"core": false,
	}
	if registry == null:
		return out
	if registry.has_method("value_type"):
		out["value_type"] = str(registry.call("value_type", sid))
	if registry.has_method("category"):
		var cat: String = str(registry.call("category", sid))
		out["category"] = cat if cat != "" else MISC_CATEGORY
	if registry.has_method("min_of"):
		out["min"] = float(registry.call("min_of", sid))
	if registry.has_method("max_of"):
		out["max"] = float(registry.call("max_of", sid))
	if registry.has_method("default_value"):
		out["default"] = registry.call("default_value", sid)
	if registry.has_method("needs_value"):
		out["needs_value"] = bool(registry.call("needs_value", sid))
	if registry.has_method("is_core"):
		out["core"] = bool(registry.call("is_core", sid))
	return out


# The sorted list of stat ids valid for a catalog ("unit"/"building"/"object").
# Delegates the applies_to filtering to the registry so there is one source of
# truth. Returns [] for a null registry or an unknown catalog. Deterministic.
static func stat_ids_for(catalog: String, registry: Object = null) -> Array:
	if registry == null or not registry.has_method("ids_for"):
		return []
	var ids: Array = registry.call("ids_for", str(catalog))
	if not (ids is Array):
		return []
	var out: Array = []
	for id in ids:
		out.append(str(id))
	out.sort()
	return out


# The full descriptor list for a catalog, stat ids sorted (deterministic).
static func descriptors_for(catalog: String, registry: Object = null) -> Array:
	var out: Array = []
	for id in stat_ids_for(catalog, registry):
		out.append(describe_stat(id, registry))
	return out


# Group a catalog's stats by `category`. Returns an Array of groups, each
#   { "category": String, "stats": Array<descriptor> }
# sorted by category id ASC; within each group the stats keep their sorted-id
# order. This is what the editor renders as collapsible sections. Deterministic.
static func groups_for(catalog: String, registry: Object = null) -> Array:
	var by_cat: Dictionary = {}   # category -> Array<descriptor>
	for desc in descriptors_for(catalog, registry):
		var cat: String = str((desc as Dictionary).get("category", MISC_CATEGORY))
		if not by_cat.has(cat):
			by_cat[cat] = []
		(by_cat[cat] as Array).append(desc)
	var cats: Array = by_cat.keys()
	cats.sort()
	var out: Array = []
	for cat in cats:
		out.append({ "category": str(cat), "stats": by_cat[cat] })
	return out


# The sorted list of distinct category ids present in a catalog. Deterministic.
static func categories_for(catalog: String, registry: Object = null) -> Array:
	var out: Array = []
	for group in groups_for(catalog, registry):
		out.append(str((group as Dictionary).get("category", MISC_CATEGORY)))
	return out


# Paginate a flat descriptor list for a mobile screen. `page` is 0-based; a page
# out of range yields an empty page (never crashes). `page_size` clamps to >= 1.
# Returns { "page": int, "page_count": int, "page_size": int, "total": int,
#           "stats": Array<descriptor> } so the editor can draw prev/next + a
# "page X of N" label with no extra math. Deterministic.
static func paginate(descriptors: Array, page: int, page_size: int = DEFAULT_PAGE_SIZE) -> Dictionary:
	var size: int = page_size if page_size >= 1 else 1
	var total: int = descriptors.size()
	var page_count: int = int((total + size - 1) / size) if total > 0 else 1
	var p: int = page
	if p < 0:
		p = 0
	if p >= page_count:
		p = page_count - 1
	var start: int = p * size
	var stats: Array = []
	var i: int = start
	while i < start + size and i < total:
		stats.append(descriptors[i])
		i += 1
	return {
		"page": p,
		"page_count": page_count,
		"page_size": size,
		"total": total,
		"stats": stats,
	}


# Convenience: paginate a whole catalog's flat descriptor list in one call.
static func paginate_catalog(catalog: String, registry: Object, page: int, page_size: int = DEFAULT_PAGE_SIZE) -> Dictionary:
	return paginate(descriptors_for(catalog, registry), page, page_size)


# --- MD12.2: per-stat edit logic (model-side, UI-agnostic) ------------------

# Which UI control a stat's value_type wants. The editor (MD12.2) maps this to a
# concrete widget: "switch" -> CheckBox (bool flag, no numeric value),
# "int" -> integer SpinBox, "float" -> decimal SpinBox / slider. Pure lookup.
static func control_kind(value_type: String) -> String:
	match str(value_type):
		"bool":
			return "switch"
		"float":
			return "float"
		_:
			return "int"


# Coerce a raw editor input into the value a stat should actually store, honoring
# the stat's value_type and clamping into its [min..max] band. This is the pure
# heart of MD12.2 so the edit logic is tested on the MODEL, not the UI:
#   - bool stat    -> the raw value truthiness (min/max ignored),
#   - int stat     -> rounded to the nearest integer then clamped,
#   - float stat   -> clamped as a float.
# `registry` supplies value_type/min_of/max_of; a null registry treats the stat
# as an unbounded int (safe default). Deterministic (round-half-away-from-zero).
static func coerce_value(id: String, raw: Variant, registry: Object = null) -> Variant:
	var vtype: String = "int"
	if registry != null and registry.has_method("value_type"):
		vtype = str(registry.call("value_type", str(id)))
	if vtype == "bool":
		return _to_bool(raw)
	var num: float = _to_float(raw)
	# Clamp into the declared band when the registry provides one.
	var has_bounds: bool = registry != null and registry.has_method("min_of") and registry.has_method("max_of")
	if has_bounds:
		var lo: float = float(registry.call("min_of", str(id)))
		var hi: float = float(registry.call("max_of", str(id)))
		if hi >= lo:
			if num < lo:
				num = lo
			if num > hi:
				num = hi
	if vtype == "float":
		return num
	# int: round half away from zero, deterministically.
	if num >= 0.0:
		return int(num + 0.5)
	return int(num - 0.5)


# Apply a coerced value to a stats dictionary WITHOUT mutating the input (pure):
# returns a new dictionary. When the stat is not present it is a no-op copy (the
# editor toggles presence separately via its checkbox). Used by MD12.2's
# value_changed handler and unit-tested on the model.
static func with_stat_value(stats: Dictionary, id: String, raw: Variant, registry: Object = null) -> Dictionary:
	var out: Dictionary = stats.duplicate(true)
	if not out.has(str(id)):
		return out
	out[str(id)] = coerce_value(id, raw, registry)
	return out


# --- Internals: value coercion ----------------------------------------------

static func _to_bool(v: Variant) -> bool:
	if v is bool:
		return v
	if v is int or v is float:
		return float(v) != 0.0
	if v is String:
		var s: String = str(v).to_lower()
		return s == "true" or s == "1" or s == "yes" or s == "on"
	return false


static func _to_float(v: Variant) -> float:
	if v is bool:
		return 1.0 if v else 0.0
	if v is int or v is float:
		return float(v)
	if v is String and str(v).is_valid_float():
		return str(v).to_float()
	return 0.0


# --- MD12.3: cosmetic "capability card" feedback ----------------------------
#
# As the modder edits stats, the editor shows a LIVE card: the entity's
# Capability vector (MD3) and its inferred primary/ranked roles (MD4), so the
# author sees the effect of a change immediately. This is COSMETIC feedback
# (section 2.2) -- it drives no Command and never touches the sim hash -- so it
# lives here as a pure display builder the editor renders read-only.
#
# `entity_def` : the unit/building dict being edited (has a "stats" sub-dict).
# `stat_registry` : StatRegistry (or a stub) for normalisation metadata.
# `target` : "unit" | "building" | "auto" for role inference.
# Returns:
#   {
#     "capabilities": Array< { id, name_key, q, percent } > sorted by id,
#     "primary_role": String,
#     "roles": Array< { role, score_q, percent } > (ranked, from infer_roles),
#   }
# `percent` is an integer 0..100 (q * 100 / SCALE, rounded) purely for display.
# Deterministic; never crashes on an empty/malformed entity (MD3/MD4 resilience).
static func capability_card(entity_def: Variant, stat_registry: Object = null, target: String = "auto") -> Dictionary:
	var vector: Dictionary = DerivedMetricsUtil.compute_capabilities(entity_def, stat_registry, null)
	var scale: int = DerivedMetricsUtil.SCALE
	var caps: Array = []
	var ids: Array = vector.keys()
	ids.sort()
	for cid in ids:
		var q: int = int(vector[cid])
		caps.append({
			"id": str(cid),
			"name_key": CapabilityRegistry.name_key(str(cid)),
			"q": q,
			"percent": _q_to_percent(q, scale),
		})
	var ranked_in: Array = RoleInferenceUtil.infer_roles(vector, target)
	var roles: Array = []
	for r in ranked_in:
		var rd: Dictionary = r as Dictionary
		var score: int = int(rd.get("score_q", 0))
		roles.append({
			"role": str(rd.get("role", "")),
			"score_q": score,
			"percent": _q_to_percent(score, scale),
		})
	return {
		"capabilities": caps,
		"primary_role": RoleInferenceUtil.primary_role(vector, target),
		"roles": roles,
	}


# Convert a fixed-point q in [0..scale] to an integer percent 0..100 (rounded).
static func _q_to_percent(q: int, scale: int) -> int:
	if scale <= 0:
		return 0
	var num: int = q * 100
	var half: int = scale / 2
	if num >= 0:
		return (num + half) / scale
	return -(((-num) + half) / scale)


# --- MD12.4: define a NEW Free Stat in the mod editor -----------------------
#
# The mod editor lets an author invent a brand-new stat (a Free Stat, section
# 2.4) by giving it a name/category/type/min/max/default and a set of `affects`
# weights onto the CLOSED Capability contract (section 2.3). A Free Stat may
# ONLY reach gameplay through those `affects` weights -- it never wires into the
# engine's combat/economy logic -- so building one here is a pure, model-side
# operation with no simulation side effects.
#
# This block produces the MD1 definition dictionary such an author edits, in the
# exact shape `StatRegistry.load_definitions()` merges and `validate_definition`
# checks. It stays PURE (RefCounted static, no SceneTree / sim hash): the editor
# collects fields, calls build_free_stat_definition(), validates with
# validate_free_stat(), and on success hands the dict to the project model +
# StatRegistry.load_definitions(). Deterministic: `affects` keys are emitted in
# sorted order so the same input yields byte-for-byte the same definition.

# Allowed value types for a Free Stat (mirrors StatRegistry.VALID_VALUE_TYPES;
# duplicated here so the editor can validate without a registry instance).
const FREE_STAT_VALUE_TYPES: Array = ["int", "float", "bool"]

# Catalogs a Free Stat may apply to (matches StatRegistry.APPLIES_*).
const FREE_STAT_APPLIES: Array = ["unit", "building", "both"]


# Normalise a raw author-typed id into a safe stat id: lower-case, ASCII letters
# / digits / underscore only, leading digits stripped, collapsed underscores.
# Returns "" when nothing usable remains (the editor then shows an error). Pure.
static func normalise_stat_id(raw: String) -> String:
	var lower: String = str(raw).strip_edges().to_lower()
	var out: String = ""
	var prev_us: bool = false
	for i in range(lower.length()):
		var ch: String = lower.substr(i, 1)
		var code: int = ch.unicode_at(0)
		var is_digit: bool = code >= 48 and code <= 57
		var is_alpha: bool = code >= 97 and code <= 122
		if is_alpha or (is_digit and out != ""):
			out += ch
			prev_us = false
		elif is_digit and out == "":
			# Leading digit: skip until the first letter so ids stay valid.
			continue
		else:
			# Any separator collapses to a single underscore (never leading).
			if out != "" and not prev_us:
				out += "_"
				prev_us = true
	# Trim a trailing underscore.
	while out.ends_with("_"):
		out = out.substr(0, out.length() - 1)
	return out


# Build a Free Stat definition dictionary from the fields the editor collects.
# `affects` maps capability_id -> weight (float/int); it is copied with keys in
# sorted order for determinism. The result carries `core=false` (it is a Free
# Stat) and a `display_name_key` of `stat.<id>.name` (MD12.5 i18n). This is a
# pure builder: it does NOT validate (call validate_free_stat separately) and it
# does NOT touch the registry -- the caller merges it via load_definitions().
static func build_free_stat_definition(
		id: String,
		value_type: String,
		category: String,
		min_value: float,
		max_value: float,
		default_value: Variant,
		affects: Dictionary = {},
		applies_to: String = "both") -> Dictionary:
	var sid: String = normalise_stat_id(id)
	var vtype: String = str(value_type)
	if not (vtype in FREE_STAT_VALUE_TYPES):
		vtype = "int"
	var apply: String = str(applies_to)
	if not (apply in FREE_STAT_APPLIES):
		apply = "both"
	# Deterministic affects: copy in sorted-key order, numbers only.
	var clean_affects: Dictionary = {}
	var cap_ids: Array = affects.keys()
	cap_ids.sort()
	for cap in cap_ids:
		var w: Variant = affects[cap]
		if w is float or w is int:
			clean_affects[str(cap)] = w
	var cat: String = str(category).strip_edges()
	if cat == "":
		cat = MISC_CATEGORY
	return {
		"id": sid,
		"value_type": vtype,
		"category": cat,
		"min": float(min_value),
		"max": float(max_value),
		"default": default_value,
		"affects": clean_affects,
		"applies_to": apply,
		"needs_value": vtype != "bool",
		"higher_is_better": true,
		"ai_importance": 0.5,
		"core": false,
		"display_name_key": "stat.%s.name" % sid,
	}


# Validate a Free Stat definition before it is merged. Returns an Array of
# human-readable problem strings (empty => valid). Layers the editor-specific
# Free Stat rules ON TOP of StatRegistry.validate_definition (the shared schema
# check): a Free Stat additionally must have a usable id, MUST NOT collide with a
# reserved Core Stat, its `applies_to` must be known, and EVERY `affects` key
# must name a real Capability in the closed contract (section 2.3). `registry`
# is StatRegistry (or a stub) for the collision/schema checks; `capability_reg`
# is CapabilityRegistry (or a stub) for the affects-target check. Both may be
# null -> the corresponding checks are skipped (still returns the id/type rules).
static func validate_free_stat(def: Variant, registry: Object = null, capability_reg: Object = null) -> Array:
	var problems: Array = []
	if not (def is Dictionary):
		problems.append("definition is not a dictionary")
		return problems
	var d: Dictionary = def as Dictionary
	# Shared schema validation (min/max, value_type, ai_importance, affects type).
	if registry != null and registry.has_method("validate_definition"):
		for p in registry.call("validate_definition", d):
			problems.append(str(p))
	# Free-Stat-specific rules.
	var id: String = str(d.get("id", ""))
	if id == "":
		problems.append("free stat needs a non-empty id")
	elif normalise_stat_id(id) != id:
		problems.append("id is not a normalised stat id: %s" % id)
	# Must not shadow a reserved Core Stat.
	if id != "" and registry != null and registry.has_method("is_core"):
		if bool(registry.call("is_core", id)):
			problems.append("id collides with a reserved core stat: %s" % id)
	# applies_to must be one of the known catalogs.
	if d.has("applies_to") and not (str(d["applies_to"]) in FREE_STAT_APPLIES):
		problems.append("invalid applies_to: %s" % str(d["applies_to"]))
	# Every affects target must be a real Capability (closed contract).
	if capability_reg != null and capability_reg.has_method("has_capability"):
		var affects: Dictionary = (d.get("affects", {}) as Dictionary)
		var cap_ids: Array = affects.keys()
		cap_ids.sort()
		for cap in cap_ids:
			if not bool(capability_reg.call("has_capability", str(cap))):
				problems.append("affects unknown capability: %s" % str(cap))
	return problems
