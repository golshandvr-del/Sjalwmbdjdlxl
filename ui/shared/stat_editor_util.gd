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
