# stat_affects_util.gd
# ----------------------------------------------------------------------------
# Project Nexus - Stat -> Capability affects mapping (plan v4, phase MD2.2).
#
# The Capability layer (core/capability_registry.gd, MD2.1) is the CLOSED,
# VERSIONED engine contract. This util is the bridge that answers:
#
#   "which engine Capabilities does a raw stat feed, and how strongly?"
#
# i.e. a mapping  stat_id -> { capability_id: weight_q }  where every weight is
# FIXED-POINT (an integer in units of SCALE, so 1.0 == SCALE == 1000). This is
# the "affects" concept from section 2 of docs/plan_android_fix_v4.md: the AI
# never reads a raw stat directly -- it reads Capabilities, and Capabilities are
# fed by stats through exactly this table.
#
# MD2.2 provides the BUILT-IN default map for the Core Stats. MD2.3 will merge
# any mod-defined `affects` (from a stat's data definition) on top of this, so a
# mod author can wire a brand-new Free Stat to a Capability with ZERO code.
#
# Design rules (consistent with the rest of the project):
#   - PURE INFRASTRUCTURE: RefCounted, no SceneTree / WorldState / sim-hash
#     dependency. Headlessly unit-testable.
#   - FIXED-POINT DETERMINISM (section 2.1 golden rule): weights are integers in
#     [.. up to a few * SCALE], never floats. A data definition's `affects`
#     stores floats (human-authored), but the moment they cross into this layer
#     they are quantised to weight_q via `quantize_weight()`.
#   - DETERMINISTIC: every id list this util returns is stably SORTED, and merge
#     order never changes the result.
#   - Only KNOWN capability ids survive: any weight pointing at an id the
#     CapabilityRegistry does not know is dropped (validated in MD2.4).
#   - English-only identifiers/comments (CODE_POLICY).
# ----------------------------------------------------------------------------
class_name StatAffectsUtil
extends RefCounted

# Fixed-point scale (section 2.1). Mirrors CapabilityRegistry.SCALE. A weight of
# 1.0 is stored as SCALE (1000); 0.8 -> 800; 0.3 -> 300. Weights MAY exceed
# SCALE (a stat can matter "more than 1.0" to a capability) but are never floats.
const SCALE: int = 1000

# The BUILT-IN default affects map for Core Stats:
#   stat_id -> { capability_id: weight_q (fixed-point) }
#
# These mirror the human-authored floats that live in the Core Stat definitions
# (tools/stat_registry.gd STATS[...].affects and data/stats/*.json) but are the
# authoritative FIXED-POINT source for the deterministic AI pipeline. Keeping a
# dedicated integer table here (rather than reading the float `affects` at run
# time) guarantees byte-for-byte determinism regardless of float parsing.
#
# Weight intuition (section 2.3 examples):
#   armor        -> survivability strong, holding_power moderate
#   move_speed   -> mobility full, scout_power some
#   vision_range -> scout_power strong, control_value light
const BUILTIN_AFFECTS: Dictionary = {
	# --- combat ------------------------------------------------------------
	"attack_damage": { "damage_output": 1000, "siege_power": 300 },
	"fire_rate":     { "damage_output": 600 },
	"attack_range":  { "damage_output": 300, "siege_power": 500, "survivability": 200 },
	"splash_radius": { "siege_power": 700, "damage_output": 200 },
	# --- defense -----------------------------------------------------------
	"health":        { "survivability": 1000, "holding_power": 400 },
	"armor":         { "survivability": 800, "holding_power": 500 },
	"shield":        { "survivability": 700 },
	# --- mobility ----------------------------------------------------------
	"move_speed":    { "mobility": 1000, "scout_power": 400 },
	"turn_rate":     { "mobility": 400 },
	# --- economy -----------------------------------------------------------
	"extraction_rate": { "economic_value": 1000, "resource_pressure": 600 },
	"storage_cap":     { "economic_value": 400 },
	# --- vision ------------------------------------------------------------
	"vision_range":  { "scout_power": 900, "control_value": 200 },
	"stealth":       { "scout_power": 300, "survivability": 200 },
}


# Quantise a human-authored float weight (e.g. 0.8) into fixed-point (800).
# Deterministic rounding: round-half-away-from-zero via int(x + 0.5 * sign).
static func quantize_weight(w: Variant) -> int:
	var f: float = float(w)
	if f >= 0.0:
		return int(f * float(SCALE) + 0.5)
	return -int(-f * float(SCALE) + 0.5)


# The built-in fixed-point affects for a single stat, or {} if the stat has no
# built-in mapping. Returns a defensive copy so callers cannot mutate the table.
static func builtin_affects_for(stat_id: String) -> Dictionary:
	if not BUILTIN_AFFECTS.has(stat_id):
		return {}
	return (BUILTIN_AFFECTS[stat_id] as Dictionary).duplicate(true)


# All stat ids that carry a built-in affects mapping, stably sorted.
static func builtin_stat_ids() -> Array:
	var ids: Array = BUILTIN_AFFECTS.keys()
	ids.sort()
	return ids


# True if `stat_id` has a built-in affects mapping.
static func has_builtin(stat_id: String) -> bool:
	return BUILTIN_AFFECTS.has(stat_id)


# The complete built-in map with only KNOWN capability ids retained, weights in
# fixed-point. Deterministic (stat ids and capability ids both sorted on emit).
# Unknown capability ids (should never happen for built-ins) are dropped so the
# result is always consistent with the current CapabilityRegistry contract.
static func builtin_map() -> Dictionary:
	var out: Dictionary = {}
	for stat_id in builtin_stat_ids():
		var caps: Dictionary = BUILTIN_AFFECTS[stat_id] as Dictionary
		var kept: Dictionary = {}
		var cap_ids: Array = caps.keys()
		cap_ids.sort()
		for cap_id in cap_ids:
			if CapabilityRegistry.has_capability(str(cap_id)):
				kept[str(cap_id)] = int(caps[cap_id])
		if not kept.is_empty():
			out[stat_id] = kept
	return out


# ---------------------------------------------------------------------------
# MD2.3: resolve the EFFECTIVE affects map for a StatRegistry (or any object
# exposing the same static getters -- passed by name via `stat_registry`, which
# we accept as a Script/Object so tests can inject a stub).
#
# Semantics (deterministic, section 2):
#   1. Start from the built-in fixed-point map (Core Stats).
#   2. For every stat the registry knows, read its data-defined `affects` (the
#      human-authored float map from a stat's JSON / mod definition), quantise it
#      to fixed-point, keep only KNOWN capability ids, and OVERLAY it on top of
#      the built-in entry for that stat. Overlay = per-capability override: a mod
#      that sets `armor.affects.survivability = 0.9` replaces the built-in 0.8,
#      but capabilities the mod does NOT mention keep their built-in weight.
#   3. A brand-new Free Stat (no built-in entry) is wired to Capabilities purely
#      by its data-defined `affects` -- ZERO engine code, the plan's core goal.
#
# The result is  stat_id -> { capability_id: weight_q }  with every weight an
# int, every capability id known, and both id levels stably sorted on emit.
#
# `stat_registry` must expose:  all_definition_ids() -> Array,  affects(id) ->
# Dictionary. StatRegistry (tools/stat_registry.gd) satisfies this. When null,
# only the built-in map is returned.
# ---------------------------------------------------------------------------
static func resolve_affects(stat_registry: Object) -> Dictionary:
	var out: Dictionary = builtin_map()
	if stat_registry == null:
		return out
	if not (stat_registry.has_method("all_definition_ids") and stat_registry.has_method("affects")):
		return out
	var ids: Array = stat_registry.call("all_definition_ids")
	ids.sort()
	for raw_id in ids:
		var stat_id: String = str(raw_id)
		var declared: Variant = stat_registry.call("affects", stat_id)
		if not (declared is Dictionary):
			continue
		var caps: Dictionary = declared as Dictionary
		if caps.is_empty():
			continue
		# Overlay quantised, known-only weights on top of any built-in entry.
		var merged: Dictionary = (out.get(stat_id, {}) as Dictionary).duplicate(true)
		var cap_ids: Array = caps.keys()
		cap_ids.sort()
		for cap_id in cap_ids:
			var cid: String = str(cap_id)
			if not CapabilityRegistry.has_capability(cid):
				continue
			merged[cid] = quantize_weight(caps[cap_id])
		if not merged.is_empty():
			out[stat_id] = merged
	return out


# ---------------------------------------------------------------------------
# MD2.4: validate a data-defined `affects` dictionary before it reaches the AI
# pipeline. Returns an array of human-readable problem strings (empty => valid).
#
# Checks:
#   - the value is a Dictionary at all;
#   - every key is a KNOWN engine capability (unknown ids rejected -- the engine
#     never grows its capability list from a mod, section 2 architecture note);
#   - every weight is numeric (int or float, not a string / bool / dict);
#   - every weight is within a sane bound. `affects` is one-directional
#     (stat -> capability), so a cycle is structurally impossible; the only
#     failure modes are unknown capability and out-of-range weight. The bound is
#     expressed in FLOAT space (author-facing) as [MIN_WEIGHT..MAX_WEIGHT].
#
# Problem strings are emitted in a DETERMINISTIC order (capability ids sorted).
# ---------------------------------------------------------------------------
# Author-facing weight bounds (float space). A weight of 0 is allowed (an author
# may explicitly zero a built-in link). Negative weights are permitted so a stat
# can DETRACT from a capability, but must stay within a sane magnitude.
const MIN_WEIGHT: float = -10.0
const MAX_WEIGHT: float = 10.0


static func validate_affects(affects: Variant) -> Array:
	var problems: Array = []
	if not (affects is Dictionary):
		problems.append("affects is not a dictionary")
		return problems
	var d: Dictionary = affects as Dictionary
	var cap_ids: Array = d.keys()
	cap_ids.sort()
	for cap_id in cap_ids:
		var cid: String = str(cap_id)
		if not CapabilityRegistry.has_capability(cid):
			problems.append("unknown capability: %s" % cid)
			continue
		var w: Variant = d[cap_id]
		if not (w is int or w is float):
			problems.append("weight for %s is not numeric" % cid)
			continue
		var f: float = float(w)
		if f < MIN_WEIGHT or f > MAX_WEIGHT:
			problems.append("weight for %s out of [%s..%s]: %s" % [cid, str(MIN_WEIGHT), str(MAX_WEIGHT), str(f)])
	return problems
