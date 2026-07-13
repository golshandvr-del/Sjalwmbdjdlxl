# ai_context_util.gd
# ----------------------------------------------------------------------------
# Project Nexus - AI Context Vector: a single deterministic situation summary
# (plan v4, MD7).
#
# The sixth link of the data-driven AI backbone (docs/plan_android_fix_v4.md).
# It replaces the scattered ad-hoc situation reads in the commander module
# (nearest-enemy scan, resource peeking) with ONE canonical, FIXED-POINT
# "context vector" that is the shared input of:
#   - MD6 Policy   (hard behaviour rules evaluated on these keys),
#   - MD8/MD9 Utility (unit / building scoring reads current_need from here),
#   - MD10 staged decision (state classification reads here).
#
#   plain world summary (a dictionary the MODULE builds from the world model)
#       --(HERE: build_context)-->
#   { context_key: q }  FIXED-POINT, closed & versioned key set
#
# Because the util takes a PLAIN summary dictionary (never the live world model)
# it stays pure and headlessly testable; the module owns `summarize(...)` which
# reads the world model and hands this util a snapshot (MD7.2).
#
# Design rules (Definition of Done, plan section 2 constant principles):
#   - PURE INFRASTRUCTURE: RefCounted, no scene tree / world model / RNG /
#     sim-hash dependency. Same summary in -> byte-identical dictionary out.
#   - FIXED-POINT DETERMINISM (section 2.1 golden rule): every emitted value is
#     an int. Normalised quantities are ints in [0..SCALE] (1.0 == 1000);
#     boolean-like flags are 0/1. All distances are integer Manhattan; all
#     ratios use round-half-away-from-zero integer division. No float ever
#     enters the returned dictionary, so the result is identical on any CPU.
#   - STABLE ORDER (section 2.1): every scan over the summary's entity lists
#     sorts by integer id before folding, so ties break deterministically.
#   - RESILIENCE (section 2.5): a missing HQ / no enemy / no economy yields the
#     documented SAFE DEFAULT for each key, never a crash and never a missing
#     key. build_context ALWAYS returns the full closed key set.
#   - COSMETIC vs SIMULATION (section 2.2): the vector may feed a deterministic
#     Command decision (so it MUST be deterministic, which it is) but this util
#     never writes the world model and never touches the sim hasher.
#   - English-only identifiers/comments (CODE_POLICY, pure ASCII).
# ----------------------------------------------------------------------------
class_name AiContextUtil
extends RefCounted

# Fixed-point scale (section 2.1). A normalised [0.0..1.0] quantity is an int in
# [0..SCALE]. Mirrors the SCALE used across the v4 backbone.
const SCALE: int = 1000

# The CLOSED, VERSIONED set of context keys (plan MD7.1). Consumers may index
# any of these safely; build_context always emits every one. Grouped by kind:
#   normalised (int in [0..SCALE]):
const KEY_BASE_SECURITY: String = "base_security"           # 1000 = totally safe
const KEY_ENEMY_DISTANCE: String = "enemy_distance"         # 1000 = enemy far
const KEY_ECONOMY_GAP: String = "economy_gap"               # 1000 = we are far ahead
const KEY_ARMY_RATIO: String = "army_ratio"                 # 1000 = we dominate army
const KEY_FRONTLINE_PRESSURE: String = "frontline_pressure" # 1000 = heavy pressure
#   boolean-like (0 / 1):
const KEY_UNDER_THREAT: String = "under_threat"
const KEY_HAS_ALLY: String = "has_ally"
const KEY_IN_ACTIVE_WAR: String = "in_active_war"

# The canonical key list in stable (sorted) order, so callers can iterate or
# validate completeness deterministically.
const CONTEXT_KEYS: Array = [
	KEY_ARMY_RATIO,
	KEY_BASE_SECURITY,
	KEY_ECONOMY_GAP,
	KEY_ENEMY_DISTANCE,
	KEY_FRONTLINE_PRESSURE,
	KEY_HAS_ALLY,
	KEY_IN_ACTIVE_WAR,
	KEY_UNDER_THREAT,
]

# --- Tuning references (all deterministic integer constants) ----------------

# Manhattan distance at which an approaching enemy is considered "at the base"
# (security floor) versus "far" (security ceiling). An enemy inside SAFE_NEAR is
# maximally threatening; beyond SAFE_FAR is no threat. Between them security
# scales linearly. Tuned to a typical map cell budget.
const SAFE_NEAR: int = 4
const SAFE_FAR: int = 24

# Manhattan distance mapped to KEY_ENEMY_DISTANCE via the same saturation curve
# used elsewhere: q = SCALE * d / (d + HALF). d == HALF -> SCALE/2. A larger q
# means the nearest enemy is FARTHER (safer).
const ENEMY_DISTANCE_HALF: int = 12

# The threat radius for KEY_UNDER_THREAT: any live enemy entity within this
# Manhattan distance of our HQ flips the flag on.
const THREAT_RADIUS: int = SAFE_FAR

# Frontline pressure half-saturation: number of enemy units near our HQ at which
# pressure reaches SCALE/2.
const PRESSURE_HALF: int = 3

# --- Public API -------------------------------------------------------------

# Build the FIXED-POINT context vector for `owner` from a plain world summary.
#
# `world_summary` : a plain dictionary the MODULE produced (see summarize() in
#   the commander module). Recognised (all optional -> safe defaults):
#     "hq"            : { "x": int, "y": int } | {}      our headquarters cell
#     "own_units"     : Array[{ "id", "x", "y", "health" }]
#     "enemy_units"   : Array[{ "id", "x", "y", "health" }]
#     "enemy_buildings": Array[{ "id", "x", "y", "health" }]
#     "own_economy"   : int   our stored/production score
#     "enemy_economy" : int   summed enemy economy score
#     "own_army"      : int   our army power score (count or strength)
#     "enemy_army"    : int   summed enemy army power score
#     "has_ally"      : bool
#     "in_active_war" : bool
# `owner` : the AI player id (used only for documentation / determinism; the
#   summary is already owner-relative, built by the module).
#
# Returns the full CONTEXT_KEYS set, every value an int (normalised in
# [0..SCALE] or a 0/1 flag). Deterministic and resilient.
static func build_context(world_summary: Variant, _owner: int = -1) -> Dictionary:
	var s: Dictionary = world_summary as Dictionary if world_summary is Dictionary else {}

	var hq: Dictionary = _dict_of(s.get("hq", {}))
	var own_units: Array = _list_of(s.get("own_units", []))
	var enemy_units: Array = _list_of(s.get("enemy_units", []))
	var enemy_buildings: Array = _list_of(s.get("enemy_buildings", []))

	var nearest: int = _nearest_enemy_distance(hq, enemy_units, enemy_buildings)
	var near_count: int = _enemy_count_within(hq, enemy_units, THREAT_RADIUS)

	var out: Dictionary = {}
	out[KEY_BASE_SECURITY] = _base_security_q(hq, nearest)
	out[KEY_ENEMY_DISTANCE] = _enemy_distance_q(hq, nearest)
	out[KEY_ECONOMY_GAP] = _gap_q(int(s.get("own_economy", 0)), int(s.get("enemy_economy", 0)))
	out[KEY_ARMY_RATIO] = _gap_q(int(s.get("own_army", 0)), int(s.get("enemy_army", 0)))
	out[KEY_FRONTLINE_PRESSURE] = _pressure_q(near_count)
	out[KEY_UNDER_THREAT] = 1 if (not hq.is_empty() and nearest <= THREAT_RADIUS) else 0
	out[KEY_HAS_ALLY] = 1 if bool(s.get("has_ally", false)) else 0
	out[KEY_IN_ACTIVE_WAR] = 1 if bool(s.get("in_active_war", false)) else 0
	return out


# The closed context key set (sorted). Consumers use this for completeness
# checks and to iterate deterministically.
static func context_keys() -> Array:
	return CONTEXT_KEYS.duplicate()


# True if `key` is a recognised context key.
static func has_context_key(key: String) -> bool:
	return CONTEXT_KEYS.has(key)


# A resilient, all-safe-default context (as if no HQ / no enemy / no economy).
# Handy for callers that must score something before any world data exists.
static func safe_default_context() -> Dictionary:
	return build_context({}, -1)


# --- Internals: per-key computation -----------------------------------------

# base_security in [0..SCALE]: 1000 == totally safe. With no HQ we are, by
# convention, maximally insecure is misleading; instead treat "no base" as a
# neutral-safe SCALE (nothing to defend). With an HQ, security rises with the
# nearest enemy distance between SAFE_NEAR (0 security) and SAFE_FAR (full).
static func _base_security_q(hq: Dictionary, nearest_dist: int) -> int:
	if hq.is_empty():
		return SCALE
	if nearest_dist >= SAFE_FAR:
		return SCALE
	if nearest_dist <= SAFE_NEAR:
		return 0
	# Linear ramp between SAFE_NEAR and SAFE_FAR.
	var span: int = SAFE_FAR - SAFE_NEAR
	return _clamp_q(_mul_div_round(nearest_dist - SAFE_NEAR, SCALE, span))


# enemy_distance in [0..SCALE]: larger == enemy farther (safer). Saturation
# curve q = SCALE * d / (d + HALF). With no HQ or no enemy, the enemy is
# effectively infinitely far -> SCALE.
static func _enemy_distance_q(hq: Dictionary, nearest_dist: int) -> int:
	if hq.is_empty() or nearest_dist >= (1 << 30):
		return SCALE
	return _clamp_q(_mul_div_round(nearest_dist, SCALE, nearest_dist + ENEMY_DISTANCE_HALF))


# A symmetric "gap" ratio in [0..SCALE] for (ours vs theirs): 500 == parity,
# 1000 == we dominate (they are 0), 0 == they dominate (we are 0). Defined as
#   q = SCALE * own / (own + enemy)
# which is monotonic, bounded, and pure integer. With both zero -> parity 500.
static func _gap_q(own: int, enemy: int) -> int:
	var a: int = own if own > 0 else 0
	var b: int = enemy if enemy > 0 else 0
	var total: int = a + b
	if total <= 0:
		return SCALE / 2
	return _clamp_q(_mul_div_round(a, SCALE, total))


# frontline_pressure in [0..SCALE]: rises with the count of enemy units near our
# HQ via the saturation curve q = SCALE * n / (n + HALF). n == 0 -> 0.
static func _pressure_q(near_count: int) -> int:
	var n: int = near_count if near_count > 0 else 0
	if n == 0:
		return 0
	return _clamp_q(_mul_div_round(n, SCALE, n + PRESSURE_HALF))


# --- Internals: deterministic scans -----------------------------------------

# The integer Manhattan distance from the HQ to the nearest LIVE enemy entity
# (units first, then buildings). Ties are broken by lower id via a stable scan.
# Returns a huge sentinel (1<<30) when there is no HQ or no live enemy.
static func _nearest_enemy_distance(hq: Dictionary, enemy_units: Array, enemy_buildings: Array) -> int:
	if hq.is_empty():
		return 1 << 30
	var hx: int = int(hq.get("x", 0))
	var hy: int = int(hq.get("y", 0))
	var best: int = 1 << 30
	var best_id: int = 1 << 30
	# Scan units then buildings, each id-sorted for determinism.
	for entity in _sorted_by_id(enemy_units):
		if int(entity.get("health", 1)) <= 0:
			continue
		var d: int = abs(hx - int(entity.get("x", 0))) + abs(hy - int(entity.get("y", 0)))
		var eid: int = int(entity.get("id", 0))
		if d < best or (d == best and eid < best_id):
			best = d
			best_id = eid
	for entity in _sorted_by_id(enemy_buildings):
		if int(entity.get("health", 1)) <= 0:
			continue
		var d2: int = abs(hx - int(entity.get("x", 0))) + abs(hy - int(entity.get("y", 0)))
		var bid: int = int(entity.get("id", 0))
		if d2 < best or (d2 == best and bid < best_id):
			best = d2
			best_id = bid
	return best


# The number of LIVE enemy units within `radius` Manhattan of the HQ. 0 when no
# HQ. Deterministic (order does not affect a count, but we still guard health).
static func _enemy_count_within(hq: Dictionary, enemy_units: Array, radius: int) -> int:
	if hq.is_empty():
		return 0
	var hx: int = int(hq.get("x", 0))
	var hy: int = int(hq.get("y", 0))
	var count: int = 0
	for entity in enemy_units:
		if not (entity is Dictionary):
			continue
		if int((entity as Dictionary).get("health", 1)) <= 0:
			continue
		var d: int = abs(hx - int((entity as Dictionary).get("x", 0))) + abs(hy - int((entity as Dictionary).get("y", 0)))
		if d <= radius:
			count += 1
	return count


# Return a NEW array of the dictionary entities sorted ascending by integer id
# (stable, deterministic). Non-dictionary elements are dropped.
static func _sorted_by_id(list: Array) -> Array:
	var out: Array = []
	for e in list:
		if e is Dictionary:
			out.append(e)
	out.sort_custom(func(a, b): return int((a as Dictionary).get("id", 0)) < int((b as Dictionary).get("id", 0)))
	return out


# --- Internals: coercion + integer math -------------------------------------

# Coerce a value to a Dictionary (empty when not one).
static func _dict_of(v: Variant) -> Dictionary:
	return v as Dictionary if v is Dictionary else {}


# Coerce a value to an Array (empty when not one).
static func _list_of(v: Variant) -> Array:
	return v as Array if v is Array else []


# Deterministic (a * b) / c with round-half-away-from-zero. c must be > 0.
static func _mul_div_round(a: int, b: int, c: int) -> int:
	if c == 0:
		return 0
	return _div_round(a * b, c)


# Deterministic integer division with round-half-away-from-zero. `den` positive.
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
