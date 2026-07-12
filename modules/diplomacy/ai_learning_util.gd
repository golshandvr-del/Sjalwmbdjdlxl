# ai_learning_util.gd
# ----------------------------------------------------------------------------
# Project Nexus - Level-1 (in-match, short-term) AI learning (Phase MC13.2,
# request 15).
#
# The FAST, forgettable layer of AI adaptation that lives only for the duration
# of a single match. Where the personality vector (MC12) is fixed and the
# cross-match reputation store (MC13.3) is persistent, THIS layer is the
# scratch-pad the AI rewrites as the battle unfolds:
#
#   * trust:        per-opponent trust (0..100) that drops sharply after a
#                   betrayal and drifts back up slowly while at peace.
#   * threat_zones: a coarse grid of "where am I getting hit" weights, so the
#                   AI can reinforce hot sectors (reinforce attack zones).
#   * tactics:      success/attempt tallies per named tactic, so a winning
#                   tactic gets repeated more (and a losing one less).
#
# DESIGN RULES (project constitution):
#   * PURE + DETERMINISTIC: every function is a plain transform of its inputs.
#     NO WorldState, NO SceneTree, NO RNG. Same inputs -> same output, so all
#     lockstep peers learn identically (MC13.5 calls it on deterministic events).
#   * The "state" is a plain Dictionary the caller owns and persists in the
#     diplomacy module's world section; these helpers only read/return it.
#   * The learning RATE is scaled by the profile's learning_bias.in_match_rate
#     so a slow learner barely moves and a fast one snaps quickly -- but the
#     math stays deterministic (rate is a fixed number, not randomness).
#   * English-only identifiers/comments (CODE_POLICY, pure ASCII).
# ----------------------------------------------------------------------------
class_name AiLearningUtil
extends RefCounted

# Trust bounds and the neutral starting point.
const TRUST_MIN: float = 0.0
const TRUST_MAX: float = 100.0
const TRUST_START: float = 50.0

# How hard a betrayal hits trust (before rate scaling), and the passive heal
# per recovery tick while at peace.
const BETRAYAL_TRUST_DROP: float = 60.0
const PEACE_TRUST_HEAL: float = 2.0

# Threat-zone reinforcement: an attack adds this weight to the hit cell; all
# cells decay toward zero each decay step so stale hot-spots cool off.
const ZONE_HIT_WEIGHT: float = 1.0
const ZONE_DECAY: float = 0.9

# A brand-new, empty learning scratch-pad.
static func new_state() -> Dictionary:
	return {
		"trust": {},        # pair_key -> float 0..100
		"threat_zones": {}, # "zx:zy" -> float weight
		"tactics": {},      # tactic name -> { "wins": int, "tries": int }
	}


# --- Rate helper ------------------------------------------------------------

# The effective learning rate for a profile: 0.2..1.0 mapped from the
# in_match_rate knob (even a "zero" learner still nudges a little, so betrayals
# are never entirely ignored).
static func learning_rate(profile) -> float:
	var knob: float = 0.5
	if profile != null and profile.has_method("get_value"):
		knob = float(profile.get_value("learning_bias", "in_match_rate"))
	return clampf(0.2 + 0.8 * clampf(knob, 0.0, 1.0), 0.2, 1.0)


# --- Trust ------------------------------------------------------------------

static func get_trust(state: Dictionary, owner_a: int, owner_b: int) -> float:
	var key: String = RelationshipUtil.pair_key(owner_a, owner_b)
	var trust: Dictionary = state.get("trust", {})
	return float(trust.get(key, TRUST_START))


static func _set_trust(state: Dictionary, owner_a: int, owner_b: int, value: float) -> float:
	var key: String = RelationshipUtil.pair_key(owner_a, owner_b)
	if not state.has("trust"):
		state["trust"] = {}
	var clamped: float = clampf(value, TRUST_MIN, TRUST_MAX)
	state["trust"][key] = clamped
	return clamped


# Record a betrayal by `owner_b` against `owner_a`: trust collapses, scaled by
# how fast `owner_a` learns. Returns the new trust value.
static func record_betrayal(state: Dictionary, owner_a: int, owner_b: int, profile) -> float:
	var rate: float = learning_rate(profile)
	var cur: float = get_trust(state, owner_a, owner_b)
	return _set_trust(state, owner_a, owner_b, cur - BETRAYAL_TRUST_DROP * rate)


# Record helpful behaviour (kept a treaty, sent aid): trust rises a little.
static func record_help(state: Dictionary, owner_a: int, owner_b: int, profile) -> float:
	var rate: float = learning_rate(profile)
	var cur: float = get_trust(state, owner_a, owner_b)
	return _set_trust(state, owner_a, owner_b, cur + PEACE_TRUST_HEAL * (1.0 + rate))


# One "peace tick": trust drifts back toward neutral start while nothing bad
# happens (grudges soften over the match). Never pushes trust past TRUST_START.
static func heal_trust(state: Dictionary, owner_a: int, owner_b: int) -> float:
	var cur: float = get_trust(state, owner_a, owner_b)
	if cur >= TRUST_START:
		return cur
	return _set_trust(state, owner_a, owner_b, minf(TRUST_START, cur + PEACE_TRUST_HEAL))


# --- Threat zones -----------------------------------------------------------

# Coarse zone key for a world tile at (tx, ty), bucketed by `zone_size`.
static func zone_key(tx: int, ty: int, zone_size: int) -> String:
	var size: int = max(1, zone_size)
	var zx: int = int(floor(float(tx) / float(size)))
	var zy: int = int(floor(float(ty) / float(size)))
	return str(zx) + ":" + str(zy)


# Register an attack at (tx, ty): the containing zone's weight grows. Returns
# the new weight for that zone.
static func reinforce_zone(state: Dictionary, tx: int, ty: int, zone_size: int) -> float:
	var key: String = zone_key(tx, ty, zone_size)
	if not state.has("threat_zones"):
		state["threat_zones"] = {}
	var zones: Dictionary = state["threat_zones"]
	var w: float = float(zones.get(key, 0.0)) + ZONE_HIT_WEIGHT
	zones[key] = w
	return w


static func zone_weight(state: Dictionary, tx: int, ty: int, zone_size: int) -> float:
	var key: String = zone_key(tx, ty, zone_size)
	var zones: Dictionary = state.get("threat_zones", {})
	return float(zones.get(key, 0.0))


# Decay all zone weights one step; drops near-zero cells to keep it tidy.
static func decay_zones(state: Dictionary) -> void:
	var zones: Dictionary = state.get("threat_zones", {})
	var dead: Array = []
	for key in zones.keys():
		var w: float = float(zones[key]) * ZONE_DECAY
		if w < 0.01:
			dead.append(key)
		else:
			zones[key] = w
	for key in dead:
		zones.erase(key)


# The hottest zone key (most-attacked sector), or "" when nothing recorded.
# Ties are broken by ascending key so the result is deterministic.
static func hottest_zone(state: Dictionary) -> String:
	var zones: Dictionary = state.get("threat_zones", {})
	var best_key: String = ""
	var best_w: float = -1.0
	var keys: Array = zones.keys()
	keys.sort()
	for key in keys:
		var w: float = float(zones[key])
		if w > best_w:
			best_w = w
			best_key = key
	return best_key


# --- Tactics ----------------------------------------------------------------

# Record the outcome of using a named tactic. Returns its updated success rate.
static func record_tactic(state: Dictionary, tactic: String, success: bool) -> float:
	if not state.has("tactics"):
		state["tactics"] = {}
	var tactics: Dictionary = state["tactics"]
	var entry: Dictionary = tactics.get(tactic, {"wins": 0, "tries": 0})
	entry["tries"] = int(entry.get("tries", 0)) + 1
	if success:
		entry["wins"] = int(entry.get("wins", 0)) + 1
	tactics[tactic] = entry
	return tactic_success_rate(state, tactic)


# Success rate 0..1 for a tactic (0.5 prior when never tried, so an unknown
# tactic is neither favoured nor shunned).
static func tactic_success_rate(state: Dictionary, tactic: String) -> float:
	var tactics: Dictionary = state.get("tactics", {})
	if not tactics.has(tactic):
		return 0.5
	var entry: Dictionary = tactics[tactic]
	var tries: int = int(entry.get("tries", 0))
	if tries <= 0:
		return 0.5
	return clampf(float(entry.get("wins", 0)) / float(tries), 0.0, 1.0)


# The best-performing tactic among a candidate list (highest success rate,
# ties broken by list order), or "" for an empty list.
static func best_tactic(state: Dictionary, candidates: Array) -> String:
	var best: String = ""
	var best_rate: float = -1.0
	for tactic in candidates:
		var name: String = str(tactic)
		var rate: float = tactic_success_rate(state, name)
		if rate > best_rate:
			best_rate = rate
			best = name
	return best
