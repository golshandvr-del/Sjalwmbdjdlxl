# relationship_util.gd
# ----------------------------------------------------------------------------
# Project Nexus - Dynamic diplomacy relationship model (Phase MC10.1,
# requests 11/12/17).
#
# Owners (human or AI) hold a pairwise RELATIONSHIP that changes during play:
# neutral -> suspicious -> rival -> enemy on the hostile side, and
# neutral -> negotiating -> ceasefire -> ally -> vassal on the friendly side.
# This pure, dependency-free helper owns the relationship enum + the allowed
# state transitions so the module and tests share one source of truth.
#
# Logic/Render Separation: nothing here touches WorldState or the scene tree.
# Determinism: outputs depend only on the inputs (state + transition), never on
# frame timing or unseeded randomness, so every peer/replay agrees.
#
# CODE LANGUAGE POLICY: English-only identifiers/comments.
# ----------------------------------------------------------------------------
class_name RelationshipUtil
extends RefCounted


# The relationship states, ordered from most hostile to most friendly. Stored
# as plain String tokens so they round-trip cleanly through JSON / worldstate.
const NEUTRAL: String = "neutral"
const SUSPICIOUS: String = "suspicious"
const RIVAL: String = "rival"
const ENEMY: String = "enemy"
const CEASEFIRE: String = "ceasefire"
const NEGOTIATING: String = "negotiating"
const ALLY: String = "ally"
const VASSAL: String = "vassal"


# All valid states, ordered on a hostility axis (index 0 = friendliest).
const STATES: Array = [
	VASSAL,
	ALLY,
	CEASEFIRE,
	NEGOTIATING,
	NEUTRAL,
	SUSPICIOUS,
	RIVAL,
	ENEMY,
]


# The default relationship two owners start with when nothing else is set.
const DEFAULT_STATE: String = NEUTRAL


# True when `state` is one of the known relationship tokens.
static func is_valid(state: String) -> bool:
	return STATES.has(state)


# Normalise an arbitrary/legacy value into a known state, falling back to the
# default so a malformed save can never poison the model.
static func normalize(state: String) -> String:
	return state if is_valid(state) else DEFAULT_STATE


# A relationship is HOSTILE when it sits on the enemy side of neutral. Neutral
# itself is NOT hostile (units only fire on hostiles), which keeps request 17
# ("allies must not target each other") consistent: only rival/enemy fight.
static func is_hostile(state: String) -> bool:
	var s: String = normalize(state)
	return s == RIVAL or s == ENEMY


# A relationship is FRIENDLY (shared-team candidate) when it is ally or vassal.
# These are the states the module maps onto `match.teams` so combat treats them
# as allies automatically.
static func is_friendly(state: String) -> bool:
	var s: String = normalize(state)
	return s == ALLY or s == VASSAL


# Allowed transitions: from -> Array of reachable states. A relationship can
# always stay where it is (implicit). Transitions model realistic diplomacy:
# you cannot leap straight from enemy to ally without a ceasefire first.
const TRANSITIONS: Dictionary = {
	NEUTRAL: [SUSPICIOUS, NEGOTIATING, RIVAL, ENEMY, CEASEFIRE],
	SUSPICIOUS: [NEUTRAL, RIVAL, NEGOTIATING, ENEMY],
	RIVAL: [SUSPICIOUS, ENEMY, CEASEFIRE, NEUTRAL],
	ENEMY: [CEASEFIRE, RIVAL],
	CEASEFIRE: [NEUTRAL, NEGOTIATING, RIVAL, ENEMY],
	NEGOTIATING: [NEUTRAL, CEASEFIRE, ALLY, SUSPICIOUS],
	ALLY: [VASSAL, NEUTRAL, CEASEFIRE, SUSPICIOUS, ENEMY],
	VASSAL: [ALLY, NEUTRAL, ENEMY],
}


# True when moving from `from_state` to `to_state` is a legal diplomatic step.
# Staying in the same state is always allowed. Both ends are normalised so
# unknown inputs degrade gracefully instead of asserting.
static func can_transition(from_state: String, to_state: String) -> bool:
	var a: String = normalize(from_state)
	var b: String = normalize(to_state)
	if a == b:
		return true
	if not TRANSITIONS.has(a):
		return false
	return (TRANSITIONS[a] as Array).has(b)


# Apply a transition, returning the new state when legal or the unchanged
# `from_state` when the requested move is not allowed (never throws, keeping the
# lockstep step deterministic and crash-free).
static func apply_transition(from_state: String, to_state: String) -> String:
	var a: String = normalize(from_state)
	var b: String = normalize(to_state)
	return b if can_transition(a, b) else a


# A stable, order-independent key for the unordered pair {a, b} so the module
# can store one relationship per pair instead of two mirrored entries. The two
# owners are always emitted low-high so (2,5) and (5,2) collapse to "2:5".
static func pair_key(owner_a: int, owner_b: int) -> String:
	var lo: int = min(owner_a, owner_b)
	var hi: int = max(owner_a, owner_b)
	return str(lo) + ":" + str(hi)
