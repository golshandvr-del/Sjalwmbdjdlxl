# ai_policy_util.gd
# ----------------------------------------------------------------------------
# Project Nexus - AI Policy Profile: hard behaviour rules (plan v4, MD6).
#
# The fifth link of the data-driven AI backbone (docs/plan_android_fix_v4.md).
# Weights (MD5) tell the AI what it PREFERS; a policy tells it what it MUST /
# MUST NOT do in a situation. Two AIs with near-identical weights can play very
# differently once one carries "if base_security < 700 do not attack" and the
# other does not.
#
#   context vector (MD7, fixed-point ints)
#       --(HERE: evaluate)-->
#   { action_flag: bool }  a set of hard behaviour flags for this tick
#
# A policy is a plain, serialisable list of rules:
#   { "when": <condition_key>, "op": "lt"|"le"|"gt"|"ge", "value_q": int,
#     "then": <action_flag> }
# Each rule reads ONE context key, compares it (fixed-point) against value_q, and
# if it fires, sets its action_flag. Flags default to a documented baseline so an
# EMPTY policy reproduces today's behaviour exactly (MD6.4).
#
# Design rules (Definition of Done, plan section 2 constant principles):
#   - PURE INFRASTRUCTURE: RefCounted, no scene tree / world model / RNG /
#     sim-hash dependency. Same (policy, context) in -> identical flags out.
#   - FIXED-POINT DETERMINISM: comparisons are pure integer; value_q is an int on
#     the same [0..SCALE] scale as the context vector. No float ever enters.
#   - STABLE ORDER: rules are applied in list order; a later rule may override an
#     earlier one deterministically. The emitted flag set is the full closed set.
#   - RESILIENCE: unknown condition keys / action flags / malformed rules are
#     skipped, never crash. An empty / missing policy yields the baseline flags.
#   - CLOSED & VERSIONED: the allowed condition keys and action flags are fixed
#     lists validated here (MD6.2).
#   - English-only identifiers/comments (CODE_POLICY, pure ASCII).
# ----------------------------------------------------------------------------
class_name AiPolicyUtil
extends RefCounted

# Fixed-point scale, mirroring the context vector (MD7) and the rest of the v4
# backbone. A normalised value_q is an int in [0..SCALE].
const SCALE: int = 1000

# --- Closed condition-key set (MD6.2) ---------------------------------------
# Each must be a key the context vector (MD7) emits, so a rule can read it.
const COND_BASE_SECURITY: String = "base_security"
const COND_ENEMY_DISTANCE: String = "enemy_distance"
const COND_ECONOMY_GAP: String = "economy_gap"
const COND_ARMY_RATIO: String = "army_ratio"
const COND_FRONTLINE_PRESSURE: String = "frontline_pressure"

const CONDITION_KEYS: Array = [
	COND_ARMY_RATIO,
	COND_BASE_SECURITY,
	COND_ECONOMY_GAP,
	COND_ENEMY_DISTANCE,
	COND_FRONTLINE_PRESSURE,
]

# --- Closed action-flag set (MD6.2) -----------------------------------------
const FLAG_ALLOW_ATTACK: String = "allow_attack"
const FLAG_PREFER_STATIC_DEFENSE: String = "prefer_static_defense"
const FLAG_PREFER_TANK_WHEN_PRESSURED: String = "prefer_tank_when_pressured"
const FLAG_PREFER_ECONOMY: String = "prefer_economy"
const FLAG_AVOID_RISKY_UNITS: String = "avoid_risky_units"
const FLAG_PREFER_HARASS_WHEN_EXPOSED: String = "prefer_harass_when_exposed"

const ACTION_FLAGS: Array = [
	FLAG_ALLOW_ATTACK,
	FLAG_AVOID_RISKY_UNITS,
	FLAG_PREFER_ECONOMY,
	FLAG_PREFER_HARASS_WHEN_EXPOSED,
	FLAG_PREFER_STATIC_DEFENSE,
	FLAG_PREFER_TANK_WHEN_PRESSURED,
]

# Allowed comparison operators.
const OPS: Array = ["lt", "le", "gt", "ge"]

# --- Baseline flags (MD6.4) -------------------------------------------------
# The default value of each flag when NO rule sets it. Chosen so an empty policy
# reproduces the current AI: attacking is allowed by default; every "prefer/
# avoid" bias is off (the weights alone drive choices until a rule fires).
const BASELINE_FLAGS: Dictionary = {
	"allow_attack": true,
	"avoid_risky_units": false,
	"prefer_economy": false,
	"prefer_harass_when_exposed": false,
	"prefer_static_defense": false,
	"prefer_tank_when_pressured": false,
}


# --- Public API -------------------------------------------------------------

# The baseline flag set (a fresh copy). An empty policy evaluates to exactly
# this, so the current behaviour is preserved when no rules exist (MD6.4).
static func baseline_flags() -> Dictionary:
	return BASELINE_FLAGS.duplicate(true)


static func condition_keys() -> Array:
	return CONDITION_KEYS.duplicate()


static func action_flags() -> Array:
	return ACTION_FLAGS.duplicate()


static func is_condition_key(key: String) -> bool:
	return CONDITION_KEYS.has(key)


static func is_action_flag(flag: String) -> bool:
	return ACTION_FLAGS.has(flag)


static func is_op(op: String) -> bool:
	return OPS.has(op)


# Build one well-formed rule dictionary (helper for presets / editors).
static func make_rule(when_key: String, op: String, value_q: int, then_flag: String) -> Dictionary:
	return { "when": when_key, "op": op, "value_q": int(value_q), "then": then_flag }


# True when a single rule dictionary is structurally valid: known condition key,
# known op, integer value_q in [0..SCALE], known action flag.
static func is_valid_rule(rule: Variant) -> bool:
	if not (rule is Dictionary):
		return false
	var r: Dictionary = rule as Dictionary
	if not is_condition_key(str(r.get("when", ""))):
		return false
	if not is_op(str(r.get("op", ""))):
		return false
	if not is_action_flag(str(r.get("then", ""))):
		return false
	var vq: int = int(r.get("value_q", -1))
	return vq >= 0 and vq <= SCALE


# Validate a whole policy (an Array of rules). Returns an Array of problem
# strings (empty == valid). A non-array or empty policy is valid (MD6.4).
static func validate_policy(policy: Variant) -> Array:
	var problems: Array = []
	if policy == null:
		return problems
	if not (policy is Array):
		return ["policy is not an array"]
	var idx: int = 0
	for rule in policy as Array:
		if not is_valid_rule(rule):
			problems.append("rule %d is invalid" % idx)
		idx += 1
	return problems


# Evaluate a policy against a fixed-point context vector, returning the full
# closed flag set. Rules are applied in order; a later rule overrides an earlier
# one. Invalid rules and unknown context keys are skipped (resilient). An empty
# policy returns the baseline (MD6.4).
static func evaluate(policy: Variant, context: Variant) -> Dictionary:
	var flags: Dictionary = baseline_flags()
	var ctx: Dictionary = context as Dictionary if context is Dictionary else {}
	if not (policy is Array):
		return flags
	for rule in policy as Array:
		if not is_valid_rule(rule):
			continue
		var r: Dictionary = rule as Dictionary
		var key: String = str(r["when"])
		if not ctx.has(key):
			continue
		var lhs: int = int(ctx[key])
		var rhs: int = int(r["value_q"])
		if _compare(lhs, str(r["op"]), rhs):
			flags[str(r["then"])] = true
	return flags


# --- MD6.3: archetype presets -----------------------------------------------
# Recognised archetype tags (mirror the AiProfile archetype tags used by the 9
# default profiles). Unknown tags fall back to an empty (baseline) policy.
const ARCHETYPE_DEFENSIVE: String = "defensive"
const ARCHETYPE_AGGRESSIVE: String = "aggressive"
const ARCHETYPE_ECONOMIC: String = "economic"
const ARCHETYPE_DECEPTIVE: String = "deceptive"


# A ready-made policy for a named archetype, per the expert examples. Returns a
# fresh Array of rule dictionaries; an unknown archetype yields an empty policy
# (baseline behaviour, MD6.4).
static func preset_for_archetype(archetype: String) -> Array:
	match archetype:
		ARCHETYPE_DEFENSIVE:
			# Hold ground: do not attack while the base is unsafe; fortify and
			# bring out tanks when pressured.
			return [
				make_rule(COND_BASE_SECURITY, "lt", 700, FLAG_PREFER_STATIC_DEFENSE),
				make_rule(COND_FRONTLINE_PRESSURE, "ge", 500, FLAG_PREFER_TANK_WHEN_PRESSURED),
			]
		ARCHETYPE_AGGRESSIVE:
			# Press hard: attack whenever the army is not clearly losing; do not
			# hoard economy.
			return [
				make_rule(COND_ARMY_RATIO, "ge", 400, FLAG_ALLOW_ATTACK),
				make_rule(COND_ENEMY_DISTANCE, "le", 600, FLAG_PREFER_HARASS_WHEN_EXPOSED),
			]
		ARCHETYPE_ECONOMIC:
			# Grow first: prefer economy while safe, avoid risky units.
			return [
				make_rule(COND_BASE_SECURITY, "ge", 600, FLAG_PREFER_ECONOMY),
				make_rule(COND_ARMY_RATIO, "lt", 500, FLAG_AVOID_RISKY_UNITS),
			]
		ARCHETYPE_DECEPTIVE:
			# Harass and pick fights on favourable terms; avoid risky commitments
			# when behind.
			return [
				make_rule(COND_ENEMY_DISTANCE, "le", 500, FLAG_PREFER_HARASS_WHEN_EXPOSED),
				make_rule(COND_ARMY_RATIO, "lt", 450, FLAG_AVOID_RISKY_UNITS),
			]
		_:
			return []


# Derive a policy from an AiProfile's knob vectors for a BESPOKE AI (no preset).
# `profile` is any object exposing get_value(category, knob) -> float in [0,1]
# (the AiProfile model). High/low knob values enable the matching hard rules.
# Deterministic: knob thresholds are fixed, comparisons fixed-point.
static func derive_from_profile(profile: Object) -> Array:
	if profile == null or not profile.has_method("get_value"):
		return []
	var rules: Array = []
	var caution: float = float(profile.get_value("personality", "caution"))
	var aggression: float = float(profile.get_value("personality", "aggression"))
	var economy: float = float(profile.get_value("strategy_bias", "economy"))
	var defense: float = float(profile.get_value("strategy_bias", "defense"))
	var harassment: float = float(profile.get_value("strategy_bias", "harassment"))
	# Cautious AIs refuse to attack from a weak base.
	if caution >= 0.6:
		rules.append(make_rule(COND_BASE_SECURITY, "lt", 700, FLAG_PREFER_STATIC_DEFENSE))
	# Aggressive AIs attack once the army is roughly even or better.
	if aggression >= 0.6:
		rules.append(make_rule(COND_ARMY_RATIO, "ge", 400, FLAG_ALLOW_ATTACK))
	# Economy-focused AIs prefer economy while the base is safe.
	if economy >= 0.6:
		rules.append(make_rule(COND_BASE_SECURITY, "ge", 600, FLAG_PREFER_ECONOMY))
	# Defensive AIs bring tanks out under pressure.
	if defense >= 0.6:
		rules.append(make_rule(COND_FRONTLINE_PRESSURE, "ge", 500, FLAG_PREFER_TANK_WHEN_PRESSURED))
	# Harass-oriented AIs strike exposed enemies.
	if harassment >= 0.6:
		rules.append(make_rule(COND_ENEMY_DISTANCE, "le", 500, FLAG_PREFER_HARASS_WHEN_EXPOSED))
	return rules


# --- Internals --------------------------------------------------------------

static func _compare(lhs: int, op: String, rhs: int) -> bool:
	match op:
		"lt":
			return lhs < rhs
		"le":
			return lhs <= rhs
		"gt":
			return lhs > rhs
		"ge":
			return lhs >= rhs
		_:
			return false
