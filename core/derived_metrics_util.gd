# derived_metrics_util.gd
# ----------------------------------------------------------------------------
# Project Nexus - Derived Metrics: raw stats -> Capability vector (plan v4, MD3).
#
# This is the third link of the data-driven backbone described in
# docs/plan_android_fix_v4.md:
#
#   raw stats (data/units, data/buildings)
#       --(StatAffectsUtil affects: stat_id -> {capability_id: weight_q})-->
#   a normalised, FIXED-POINT Capability vector { capability_id: q in [0..SCALE] }
#
# The AI (MD4+) reads ONLY this vector -- never a raw stat, never a unit name.
# Because the mapping goes through the CLOSED CapabilityRegistry contract and the
# per-mod `affects` table, a brand-new modded unit produces a meaningful
# Capability card with ZERO engine code (the plan's core goal).
#
# Design rules (Definition of Done, plan section 2 + section "اصولِ ثابت"):
#   - PURE INFRASTRUCTURE: RefCounted, no SceneTree / WorldState / sim-hash
#     dependency. Headlessly unit-testable. Takes plain dictionaries in, returns
#     a plain dictionary out.
#   - FIXED-POINT DETERMINISM (section 2.1 golden rule): every value is an int in
#     units of SCALE (1.0 == 1000). No float survives into the returned vector;
#     the only floats touched are the human-authored stat min/max bounds read
#     from the registry, which are quantised immediately with deterministic
#     integer math (round-half-away-from-zero). The same input yields the same
#     byte-for-byte output on any CPU.
#   - RESILIENCE (section 2.5): a capability whose feeding stats are ALL absent
#     falls back to CapabilityRegistry.default_q -- never a crash, never a random
#     zero. A malformed entity/def yields an all-default vector.
#   - COSMETIC vs SIMULATION (section 2.2): this vector may feed a deterministic
#     Command decision (so it MUST be deterministic, which it is) but the util
#     itself never writes WorldState and never touches state_hasher.
#   - English-only identifiers/comments (CODE_POLICY).
# ----------------------------------------------------------------------------
class_name DerivedMetricsUtil
extends RefCounted

# Fixed-point scale (section 2.1). Mirrors CapabilityRegistry.SCALE and
# StatAffectsUtil.SCALE. A normalised [0.0..1.0] quantity is an int in [0..SCALE].
const SCALE: int = 1000

# Normalisation uses a DETERMINISTIC saturation curve, not a linear map to the
# registry's [min..max]. The registry min/max are *validation bounds* (how far a
# modder MAY push a stat, e.g. health up to 100000), not the typical gameplay
# range -- mapping a real health of 100 against a ceiling of 100000 would crush
# every unit to q~0 and destroy the capability signal. Instead each stat has a
# "half-saturation" reference H: the value at which its normalised contribution
# reaches SCALE/2. The curve is the rational (Hill-1) form
#
#     q = SCALE * v / (v + H)
#
# which is monotonic, bounded in [0..SCALE), needs no real max, is stable across
# CPUs (pure integer math), and gives realistic values a useful mid-range spread
# while still saturating gracefully for extreme mod values. H values are tuned to
# typical gameplay magnitudes (health ~100s, damage ~10s, speed ~single digits).
const HALF_SATURATION: Dictionary = {
	"health": 200,
	"armor": 100,
	"shield": 150,
	"attack_damage": 25,
	"fire_rate": 2,
	"attack_range": 4,
	"splash_radius": 3,
	"move_speed": 3,
	"turn_rate": 6,
	"extraction_rate": 6,
	"storage_cap": 300,
	"vision_range": 7,
	"stealth": 1,
}

# Generic half-saturation for a stat with no calibrated reference (a Free/Mod
# stat). Chosen so a "typical small integer" stat lands near the mid-range.
const DEFAULT_HALF_SATURATION: int = 10

# Half-saturation for total resource cost (used by cost_efficiency): a unit
# costing COST_HALF_SATURATION lands at the mid affordability point.
const COST_HALF_SATURATION: int = 120

# --- Public API -------------------------------------------------------------

# Compute the FIXED-POINT Capability vector for one entity definition.
#
# `entity_def` : the loaded unit/building dictionary (has a "stats" sub-dict, and
#                optionally "cost" / "build_time_ticks"). Raw stat values may be
#                int, float or bool (bool -> 0/1).
# `stat_registry` : StatRegistry (or a stub exposing min_of/max_of/has_stat).
#                Used to normalise each raw stat against its declared [min..max].
#                May be null -> only the higher_is_better flag defaults apply.
# `affects` : the resolved  stat_id -> { capability_id: weight_q }  map (from
#                StatAffectsUtil.resolve_affects). May be null/empty -> the
#                built-in map is used so callers can pass nothing and still work.
#
# Returns { capability_id: q_value }  covering EVERY capability in the registry
# (so consumers can index any id safely); capabilities with no feeding stat get
# their CapabilityRegistry.default_q. Keys iterate in sorted order via all_ids().
static func compute_capabilities(entity_def: Variant, stat_registry: Object = null, affects: Variant = null) -> Dictionary:
	var stats: Dictionary = _stats_of(entity_def)
	var aff: Dictionary = _affects_map(affects)

	# Accumulate, per capability, the weighted sum of its feeding stats and the
	# total weight, so we can produce a weighted-average normalised contribution.
	var weighted_sum: Dictionary = {}   # capability_id -> int (q * weight, scaled)
	var weight_total: Dictionary = {}   # capability_id -> int (sum of weights)

	# Iterate stats in sorted order for determinism.
	var stat_ids: Array = stats.keys()
	stat_ids.sort()
	for raw_stat_id in stat_ids:
		var stat_id: String = str(raw_stat_id)
		if not aff.has(stat_id):
			continue
		var norm_q: int = _normalise_stat_q(stat_id, stats[raw_stat_id], stat_registry)
		var caps: Dictionary = aff[stat_id] as Dictionary
		var cap_ids: Array = caps.keys()
		cap_ids.sort()
		for raw_cap_id in cap_ids:
			var cap_id: String = str(raw_cap_id)
			if not CapabilityRegistry.has_capability(cap_id):
				continue
			var weight_q: int = int(caps[raw_cap_id])
			if weight_q == 0:
				continue
			# Contribution = normalised stat (q) * weight (q) / SCALE, so a stat at
			# full (SCALE) with weight 1.0 (SCALE) contributes exactly SCALE.
			var contrib: int = _mul_div_round(norm_q, weight_q, SCALE)
			weighted_sum[cap_id] = int(weighted_sum.get(cap_id, 0)) + contrib * weight_q
			weight_total[cap_id] = int(weight_total.get(cap_id, 0)) + weight_q

	# Emit a full vector: every capability, sorted, weighted-average normalised.
	var out: Dictionary = {}
	for cap_id in CapabilityRegistry.all_ids():
		if weight_total.has(cap_id) and int(weight_total[cap_id]) > 0:
			var avg: int = _div_round(int(weighted_sum[cap_id]), int(weight_total[cap_id]))
			out[cap_id] = _clamp_q(avg)
		else:
			# Resilience (section 2.5): no feeding stat -> safe default.
			out[cap_id] = CapabilityRegistry.default_q(cap_id)

	# MD3.2 special derived capabilities that depend on cost / build time rather
	# than a single stat's affects. Computed AFTER the affects pass so they can
	# read the already-normalised combat/survival capabilities.
	_apply_cost_efficiency(out, entity_def)
	_apply_resource_pressure(out, stats, stat_registry)
	return out


# MD3.3: a DETERMINISTIC cache key for an entity definition. The Capability card
# is a pure function of the entity's raw stats + cost + build time, all of which
# are FIXED between matches, so a card can be memoised per (id + shape) key. The
# key folds the id together with a stable, sorted serialisation of the stats and
# cost so two defs with identical numbers share a card while any change busts it.
static func cache_key(entity_def: Variant) -> String:
	if not (entity_def is Dictionary):
		return "|"
	var d: Dictionary = entity_def as Dictionary
	var id: String = str(d.get("id", ""))
	var parts: Array = [id]
	parts.append(_stable_pairs(_stats_of(entity_def)))
	parts.append(_stable_pairs(d.get("cost", {}) if d.get("cost", {}) is Dictionary else {}))
	parts.append("bt=" + str(int(d.get("build_time_ticks", 0))))
	return "|".join(parts)


# MD3.3: a cached wrapper around compute_capabilities. `cache` is a plain
# Dictionary the caller owns (so the util stays stateless / pure): key ->
# capability vector. Guarantees byte-for-byte the SAME result as the uncached
# path (tested in MD3.3). The cache is purely computational and never touches
# the simulation hash (section 2.6 mobile budget).
static func compute_capabilities_cached(entity_def: Variant, stat_registry: Object, affects: Variant, cache: Dictionary) -> Dictionary:
	var key: String = cache_key(entity_def)
	if cache.has(key):
		return (cache[key] as Dictionary).duplicate(true)
	var result: Dictionary = compute_capabilities(entity_def, stat_registry, affects)
	cache[key] = result.duplicate(true)
	return result


# --- Internals: normalisation ------------------------------------------------

# Normalise one raw stat value into fixed-point [0..SCALE] with a deterministic
# saturation curve  q = SCALE * v / (v + H)  where H is the stat's
# half-saturation reference (see HALF_SATURATION). Pure integer math so the
# result is byte-for-byte identical on any CPU. A `higher_is_better == false`
# stat is inverted so "more capability" always means a larger q. The registry is
# consulted ONLY for the higher_is_better flag (and to honour a Free Stat's
# declared range if it is tighter than the reference); it never drives the curve
# ceiling, so an absurd validation max can no longer crush the signal.
static func _normalise_stat_q(stat_id: String, raw_value: Variant, stat_registry: Object) -> int:
	var v: float = _to_number(raw_value)
	var higher_better: bool = true
	if stat_registry != null and stat_registry.has_method("has_stat") and bool(stat_registry.call("has_stat", stat_id)):
		if stat_registry.has_method("higher_is_better"):
			higher_better = bool(stat_registry.call("higher_is_better", stat_id))
	# Quantise the value to an int immediately so no float enters the ratio.
	var val_i: int = int(v + (0.5 if v >= 0.0 else -0.5))
	if val_i < 0:
		val_i = 0
	var half: int = _half_saturation(stat_id)
	# Saturation curve: q = SCALE * v / (v + half). v == half -> SCALE/2; v >>
	# half -> approaches SCALE; v == 0 -> 0. Deterministic integer division.
	var q: int = _mul_div_round(val_i, SCALE, val_i + half)
	if not higher_better:
		q = SCALE - q
	return _clamp_q(q)


# The half-saturation reference for a stat: its calibrated value, else the
# generic default (Free/Mod stats). Always >= 1 so the curve never divides by 0.
static func _half_saturation(stat_id: String) -> int:
	var h: int = int(HALF_SATURATION.get(stat_id, DEFAULT_HALF_SATURATION))
	return h if h >= 1 else 1


# --- Internals: MD3.2 cost-derived capabilities ------------------------------

# cost_efficiency = (combat+survival power) / cost. A cheap unit that still hits
# hard/survives scores high; an expensive one scores low. Uses the ALREADY
# normalised damage_output + survivability from the vector so it is comparable
# across mods, divided by a normalised cost. Deterministic integer math.
static func _apply_cost_efficiency(vector: Dictionary, entity_def: Variant) -> void:
	if not CapabilityRegistry.has_capability("cost_efficiency"):
		return
	var power: int = int(vector.get("damage_output", 0)) + int(vector.get("survivability", 0))
	# Average of the two so power stays in [0..SCALE].
	power = _div_round(power, 2)
	var cost: int = _total_cost(entity_def)
	if cost <= 0:
		# A free unit (hero, build_time 0) is maximally cost-efficient by power.
		vector["cost_efficiency"] = _clamp_q(power)
		return
	# Normalise cost with the same saturation curve used for stats (half-
	# saturation COST_HALF_SATURATION), so a very expensive unit saturates toward
	# 0 efficiency. cost_q in [0..SCALE): larger cost -> larger cost_q.
	var cost_q: int = _mul_div_round(cost, SCALE, cost + COST_HALF_SATURATION)
	# efficiency = power * (1 - cost_q/SCALE): high power + low cost -> high q.
	var affordability: int = SCALE - cost_q
	vector["cost_efficiency"] = _clamp_q(_mul_div_round(power, affordability, SCALE))


# resource_pressure = how strongly this entity drives the economy. Driven by the
# economy stats (extraction_rate / storage_cap) already mapped through affects
# into economic_value; here we surface it as the dedicated pressure capability
# when those stats are present, else leave the affects/default value intact.
static func _apply_resource_pressure(vector: Dictionary, stats: Dictionary, stat_registry: Object) -> void:
	if not CapabilityRegistry.has_capability("resource_pressure"):
		return
	# Only override when an economy stat actually feeds it; otherwise the affects
	# pass (extraction_rate -> resource_pressure) or the default already stands.
	if not (stats.has("extraction_rate") or stats.has("storage_cap")):
		return
	var extraction: int = 0
	if stats.has("extraction_rate"):
		extraction = _normalise_stat_q("extraction_rate", stats["extraction_rate"], stat_registry)
	var storage: int = 0
	if stats.has("storage_cap"):
		storage = _normalise_stat_q("storage_cap", stats["storage_cap"], stat_registry)
	# Extraction dominates pressure; storage is a lighter contributor.
	var pressure: int = _mul_div_round(extraction, 700, SCALE) + _mul_div_round(storage, 300, SCALE)
	vector["resource_pressure"] = _clamp_q(pressure)


# --- Internals: helpers ------------------------------------------------------

# The entity's raw stats sub-dictionary (empty when absent/malformed).
static func _stats_of(entity_def: Variant) -> Dictionary:
	if not (entity_def is Dictionary):
		return {}
	var s: Variant = (entity_def as Dictionary).get("stats", {})
	return s as Dictionary if s is Dictionary else {}


# Resolve the affects map to use: the caller's when a non-empty Dictionary, else
# the built-in fixed-point map (so passing null "just works").
static func _affects_map(affects: Variant) -> Dictionary:
	if affects is Dictionary and not (affects as Dictionary).is_empty():
		return affects as Dictionary
	return StatAffectsUtil.builtin_map()


# The total resource cost of an entity (sum of every cost line). 0 when absent.
static func _total_cost(entity_def: Variant) -> int:
	if not (entity_def is Dictionary):
		return 0
	var c: Variant = (entity_def as Dictionary).get("cost", {})
	if not (c is Dictionary):
		return 0
	var total: int = 0
	for k in (c as Dictionary).keys():
		total += int(_to_number((c as Dictionary)[k]))
	return total


# Coerce a stat/cost value (int/float/bool) to a float number. bool -> 1.0/0.0.
static func _to_number(v: Variant) -> float:
	if v is bool:
		return 1.0 if v else 0.0
	if v is int or v is float:
		return float(v)
	return 0.0


# Stable "k=v" serialisation of a numeric dictionary, keys sorted, for cache keys.
static func _stable_pairs(d: Variant) -> String:
	if not (d is Dictionary):
		return ""
	var keys: Array = (d as Dictionary).keys()
	keys.sort()
	var parts: Array = []
	for k in keys:
		parts.append("%s=%s" % [str(k), str((d as Dictionary)[k])])
	return ",".join(parts)


# Deterministic (a * b) / c with round-half-away-from-zero. c must be > 0.
static func _mul_div_round(a: int, b: int, c: int) -> int:
	if c == 0:
		return 0
	return _div_round(a * b, c)


# Deterministic integer division with round-half-away-from-zero. Works for any
# sign of `num`; `den` is expected positive (all call sites pass a positive
# divisor). The sign of the result follows `num`.
static func _div_round(num: int, den: int) -> int:
	if den == 0:
		return 0
	var d: int = den if den > 0 else -den
	var half: int = d / 2
	if num >= 0:
		return (num + half) / d
	return -(((-num) + half) / d)


# Clamp a fixed-point value into [0..SCALE].
static func _clamp_q(q: int) -> int:
	if q < 0:
		return 0
	if q > SCALE:
		return SCALE
	return q
