# stat_registry.gd
# ----------------------------------------------------------------------------
# Project Nexus - Stat / Attribute registry for the advanced Mod Editor
# (Phase E2, step E2.2).
#
# This is a PURE, headless-testable catalogue of every editable stat a unit,
# building or object can carry, plus the rules that decide which stats may live
# together. The graphical editor (Phase E3/E4) drives its dynamic property
# pickers from this registry: it lists the stats valid for the current catalog,
# and -- for a MULTI-PART entity -- disables stats whose group already exists on
# another part (the "compatibility matrix" demanded by risk R2 of the plan).
#
# Design rules (consistent with the rest of the project):
#   - PURE INFRASTRUCTURE / TOOLING: holds zero UI and never touches WorldState
#     or the deterministic sim hash. It only DESCRIBES data the editor produces.
#   - DETERMINISTIC: ids are emitted in a stable sorted order so the same query
#     always yields the same list (friendly to UI + tests).
#   - English-only identifiers/comments (CODE_POLICY); any author-facing label
#     the UI shows is resolved through Localization (key `stat.<id>.name`).
# ----------------------------------------------------------------------------
class_name StatRegistry
extends RefCounted

# Who a stat may apply to.
const APPLIES_UNIT: String = "unit"
const APPLIES_BUILDING: String = "building"
const APPLIES_BOTH: String = "both"

# Stat groups. Two parts of a multi-part entity may NOT both carry stats from
# the same group (so e.g. only one part is the "weapon", one the "engine").
const GROUP_COMBAT: String = "combat"
const GROUP_DEFENSE: String = "defense"
const GROUP_MOBILITY: String = "mobility"
const GROUP_ECONOMY: String = "economy"
const GROUP_VISION: String = "vision"

# The single source of truth for CORE stats: id -> full metadata record.
# `needs_value` = the editor must collect a numeric value for it; a few stats are
# pure flags (needs_value=false). `default` seeds the field when first enabled.
#
# MD1 (plan v4): every core stat now carries the full data-asset metadata the AI
# pipeline needs (`value_type`, `category`, `min`, `max`, `higher_is_better`,
# `ai_importance`, `affects`). These built-ins are the backward-compatible
# fallback: the same values also live in `data/stats/*.json`, and
# `load_definitions()` merges the data catalog (and mods) ON TOP of these, so
# removing a data file never breaks a Core Stat (section 2.4). All core stats
# have `core=true`; merged-in definitions that are not built-in are `free`.
const STATS: Dictionary = {
	# combat
	"attack_damage":   { "needs_value": true,  "applies_to": "both",     "group": "combat",   "default": 10,  "value_type": "int",   "category": "combat",   "min": 0,    "max": 100000, "higher_is_better": true, "ai_importance": 0.9, "affects": { "damage_output": 1.0, "siege_power": 0.3 } },
	"fire_rate":       { "needs_value": true,  "applies_to": "both",     "group": "combat",   "default": 1,   "value_type": "float", "category": "combat",   "min": 0.01, "max": 100.0,  "higher_is_better": true, "ai_importance": 0.7, "affects": { "damage_output": 0.6 } },
	"attack_range":    { "needs_value": true,  "applies_to": "both",     "group": "combat",   "default": 1,   "value_type": "int",   "category": "combat",   "min": 0,    "max": 1000,   "higher_is_better": true, "ai_importance": 0.6, "affects": { "damage_output": 0.3, "siege_power": 0.5, "survivability": 0.2 } },
	"splash_radius":   { "needs_value": true,  "applies_to": "both",     "group": "combat",   "default": 0,   "value_type": "int",   "category": "combat",   "min": 0,    "max": 100,    "higher_is_better": true, "ai_importance": 0.4, "affects": { "siege_power": 0.7, "damage_output": 0.2 } },
	# defense
	"health":          { "needs_value": true,  "applies_to": "both",     "group": "defense",  "default": 100, "value_type": "int",   "category": "defense",  "min": 1,    "max": 100000, "higher_is_better": true, "ai_importance": 0.9, "affects": { "survivability": 1.0, "holding_power": 0.4 } },
	"armor":           { "needs_value": true,  "applies_to": "both",     "group": "defense",  "default": 0,   "value_type": "int",   "category": "defense",  "min": 0,    "max": 1000,   "higher_is_better": true, "ai_importance": 0.7, "affects": { "survivability": 0.8, "holding_power": 0.5 } },
	"shield":          { "needs_value": true,  "applies_to": "both",     "group": "defense",  "default": 0,   "value_type": "int",   "category": "defense",  "min": 0,    "max": 100000, "higher_is_better": true, "ai_importance": 0.6, "affects": { "survivability": 0.7 } },
	# mobility (units only)
	"move_speed":      { "needs_value": true,  "applies_to": "unit",     "group": "mobility", "default": 2,   "value_type": "int",   "category": "mobility", "min": 0,    "max": 1000,   "higher_is_better": true, "ai_importance": 0.6, "affects": { "mobility": 1.0, "scout_power": 0.4 } },
	"turn_rate":       { "needs_value": true,  "applies_to": "unit",     "group": "mobility", "default": 4,   "value_type": "int",   "category": "mobility", "min": 0,    "max": 1000,   "higher_is_better": true, "ai_importance": 0.3, "affects": { "mobility": 0.4 } },
	# economy (buildings + extractable parts)
	"extraction_rate": { "needs_value": true,  "applies_to": "building", "group": "economy",  "default": 2,   "value_type": "int",   "category": "economy",  "min": 0,    "max": 10000,  "higher_is_better": true, "ai_importance": 0.6, "affects": { "economic_value": 1.0, "resource_pressure": 0.6 } },
	"storage_cap":     { "needs_value": true,  "applies_to": "building", "group": "economy",  "default": 100, "value_type": "int",   "category": "economy",  "min": 0,    "max": 1000000,"higher_is_better": true, "ai_importance": 0.3, "affects": { "economic_value": 0.4 } },
	# vision
	"vision_range":    { "needs_value": true,  "applies_to": "both",     "group": "vision",   "default": 5,   "value_type": "int",   "category": "vision",   "min": 0,    "max": 1000,   "higher_is_better": true, "ai_importance": 0.5, "affects": { "scout_power": 0.9, "control_value": 0.2 } },
	"stealth":         { "needs_value": false, "applies_to": "unit",     "group": "vision",   "default": true,"value_type": "bool",  "category": "vision",   "min": 0,    "max": 1,      "higher_is_better": true, "ai_importance": 0.4, "affects": { "scout_power": 0.3, "survivability": 0.2 } },
}


# All stat ids, sorted (deterministic).
static func all_ids() -> Array:
	var ids: Array = STATS.keys()
	ids.sort()
	return ids


static func has_stat(id: String) -> bool:
	return STATS.has(id)


static func definition(id: String) -> Dictionary:
	if STATS.has(id):
		return (STATS[id] as Dictionary).duplicate(true)
	return {}


static func needs_value(id: String) -> bool:
	return bool((STATS.get(id, {}) as Dictionary).get("needs_value", true))


static func group_of(id: String) -> String:
	return str((STATS.get(id, {}) as Dictionary).get("group", ""))


static func default_value(id: String) -> Variant:
	return (STATS.get(id, {}) as Dictionary).get("default", 0)


# ---------------------------------------------------------------------------
# MD1.2/MD1.3 (plan v4): data-driven definition layer.
#
# The built-in `STATS` above is the backward-compatible fallback (Core Stats the
# engine always knows). `load_definitions()` merges a catalog of data/mod stat
# definitions ON TOP of the built-ins into a process-wide `_merged` store. Once
# populated, `all_ids()` and every getter consult `_merged` first; if a stat is
# absent there they fall back to `STATS`, so a Free Stat never shadows a Core
# Stat's guaranteed contract. `_merged` is purely descriptive (editor/AI facing)
# and never touches the deterministic sim hash.
# ---------------------------------------------------------------------------
static var _merged: Dictionary = {}


# Merge a catalog of stat definitions (id -> def dict, e.g. from
# `data/stats/*.json` or a mod) onto the built-in Core Stats. Idempotent per id:
# later calls override earlier merged values for the same id, but Core built-ins
# always remain queryable via the STATS fallback even if a merged def is partial.
# Returns the number of definitions merged. Deterministic: iteration order does
# not affect the final map, and `all_ids()` stays sorted.
static func load_definitions(catalog: Dictionary) -> int:
	if _merged.is_empty():
		# Seed from the built-in Core Stats so merged queries see them too.
		for cid in STATS.keys():
			_merged[cid] = (STATS[cid] as Dictionary).duplicate(true)
	var count: int = 0
	var ids: Array = catalog.keys()
	ids.sort()
	for id in ids:
		var incoming: Variant = catalog[id]
		if not (incoming is Dictionary):
			continue
		var def: Dictionary = (incoming as Dictionary).duplicate(true)
		def["id"] = str(id)
		# A merged definition that is not a built-in Core Stat is a Free Stat.
		if not STATS.has(str(id)):
			def["core"] = bool(def.get("core", false))
		else:
			def["core"] = true
		if _merged.has(str(id)):
			# Overlay incoming fields on top of the existing record so a partial
			# data file (e.g. only tweaking `ai_importance`) keeps the rest.
			var base: Dictionary = _merged[str(id)] as Dictionary
			for k in def.keys():
				base[k] = def[k]
			_merged[str(id)] = base
		else:
			_merged[str(id)] = def
		count += 1
	return count


# Reset the merged store (tests + fresh loads). After this, queries again see
# only the built-in Core Stats until load_definitions() is called.
static func reset_definitions() -> void:
	_merged.clear()


# The effective record for an id: merged first, else the built-in STATS.
static func _record(id: String) -> Dictionary:
	if _merged.has(id):
		return _merged[id] as Dictionary
	return STATS.get(id, {}) as Dictionary


# The effective set of all ids (merged if populated, else built-ins), sorted.
static func all_definition_ids() -> Array:
	var src: Dictionary = _merged if not _merged.is_empty() else STATS
	var ids: Array = src.keys()
	ids.sort()
	return ids


# --- MD1.2 metadata getters (read merged record, fall back to built-in) -----

static func higher_is_better(id: String) -> bool:
	return bool(_record(id).get("higher_is_better", true))


static func ai_importance(id: String) -> float:
	return float(_record(id).get("ai_importance", 0.0))


static func affects(id: String) -> Dictionary:
	return (_record(id).get("affects", {}) as Dictionary).duplicate(true)


static func value_type(id: String) -> String:
	# Fall back to inferring from needs_value when a legacy def lacks value_type.
	var rec: Dictionary = _record(id)
	if rec.has("value_type"):
		return str(rec["value_type"])
	return "int" if bool(rec.get("needs_value", true)) else "bool"


static func category(id: String) -> String:
	var rec: Dictionary = _record(id)
	if rec.has("category"):
		return str(rec["category"])
	# Legacy fallback: the old `group` field doubled as a category.
	return str(rec.get("group", ""))


static func min_of(id: String) -> float:
	return float(_record(id).get("min", 0.0))


static func max_of(id: String) -> float:
	return float(_record(id).get("max", 0.0))


# --- MD1.3 core/free classification -----------------------------------------

# A Core Stat is one the engine guarantees (present in the built-in STATS).
static func is_core(id: String) -> bool:
	return STATS.has(id)


# A Free Stat is any merged definition that is NOT a built-in Core Stat.
static func is_free(id: String) -> bool:
	return _merged.has(id) and not STATS.has(id)


# --- MD1.4 definition validation --------------------------------------------

# Validate a stat definition dictionary. Returns an array of human-readable
# problem strings (empty => valid). Used by the mod editor and loaders to reject
# malformed definitions before they reach the AI pipeline.
const VALID_VALUE_TYPES: Array = ["int", "float", "bool"]


static func validate_definition(def: Variant) -> Array:
	var problems: Array = []
	if not (def is Dictionary):
		problems.append("definition is not a dictionary")
		return problems
	var d: Dictionary = def as Dictionary
	var id: String = str(d.get("id", ""))
	if id == "":
		problems.append("missing id")
	# Unknown top-level keys (typo guard for mod authors).
	var known: Array = [
		"id", "value_type", "category", "min", "max", "default",
		"higher_is_better", "ai_importance", "affects", "core",
		"display_name_key", "needs_value", "applies_to", "group",
	]
	for k in d.keys():
		if not (str(k) in known):
			problems.append("unknown key: %s" % str(k))
	# value_type must be one of the allowed set (when present).
	if d.has("value_type") and not (str(d["value_type"]) in VALID_VALUE_TYPES):
		problems.append("invalid value_type: %s" % str(d["value_type"]))
	# min/max sanity.
	if d.has("min") and d.has("max"):
		if float(d["min"]) > float(d["max"]):
			problems.append("min (%s) > max (%s)" % [str(d["min"]), str(d["max"])])
	# ai_importance range [0..1].
	if d.has("ai_importance"):
		var imp: float = float(d["ai_importance"])
		if imp < 0.0 or imp > 1.0:
			problems.append("ai_importance out of [0..1]: %s" % str(imp))
	# affects must be a dict of capability_id -> number.
	if d.has("affects"):
		if not (d["affects"] is Dictionary):
			problems.append("affects is not a dictionary")
		else:
			for cap in (d["affects"] as Dictionary).keys():
				var w: Variant = (d["affects"] as Dictionary)[cap]
				if not (w is float or w is int):
					problems.append("affects[%s] is not numeric" % str(cap))
	return problems


# Stats valid for a given catalog ("unit" / "building" / "object"). Objects are
# treated like buildings for stat purposes (they can be extractable resources).
static func ids_for(catalog: String) -> Array:
	var want: String = catalog
	if catalog == "object":
		want = APPLIES_BUILDING
	var out: Array = []
	for id in all_ids():
		var ap: String = str((STATS[id] as Dictionary).get("applies_to", APPLIES_BOTH))
		if ap == APPLIES_BOTH or ap == want:
			out.append(id)
	return out


# The set of groups present in a stats dictionary (keys are stat ids).
static func groups_present(stats: Dictionary) -> Dictionary:
	var groups: Dictionary = {}
	for id in stats.keys():
		var g: String = group_of(str(id))
		if g != "":
			groups[g] = true
	return groups


# Compatibility check between two parts of a multi-part entity. Two parts are
# compatible only if they share NO stat group (defense is the sole exception --
# every building part is REQUIRED to carry hp+armor in Phase E4, so both parts
# legitimately have the `defense` group). Returns true when they may coexist.
static func compatible(part_a_stats: Dictionary, part_b_stats: Dictionary, allow_shared_defense: bool = true) -> bool:
	var ga: Dictionary = groups_present(part_a_stats)
	var gb: Dictionary = groups_present(part_b_stats)
	for g in ga.keys():
		if gb.has(g):
			if g == GROUP_DEFENSE and allow_shared_defense:
				continue
			return false
	return true


# Human-readable reasons two parts conflict (for editor tooltips / tests).
static func conflicts(part_a_stats: Dictionary, part_b_stats: Dictionary, allow_shared_defense: bool = true) -> Array:
	var ga: Dictionary = groups_present(part_a_stats)
	var gb: Dictionary = groups_present(part_b_stats)
	var out: Array = []
	for g in ga.keys():
		if gb.has(g) and not (g == GROUP_DEFENSE and allow_shared_defense):
			out.append(g)
	out.sort()
	return out
