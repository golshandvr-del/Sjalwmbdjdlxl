# ai_weight_derivation_util.gd
# ----------------------------------------------------------------------------
# Project Nexus - AI role/metric weight derivation (plan v4, MD5).
#
# The fifth link of the data-driven backbone (docs/plan_android_fix_v4.md).
# It connects the FIXED 35-knob `AiProfile` personality to the AI's VALUES over
# ROLES and CAPABILITIES -- not just the four macro numbers the legacy
# `AiStrategyDerivationUtil` produces. A defensive general should VALUE a
# frontline_tank and DISVALUE a glass_cannon; an aggressive one the opposite.
# Crucially the personality acts on the ROLE'S VALUE, never on a unit NAME, so
# a brand-new modded unit is weighted correctly with ZERO engine code the moment
# its capability vector maps to a role (MD4).
#
#   AiProfile knobs (personality + strategy_bias)
#       --(HERE)-->  role_id     -> weight_q   (how much this AI wants each role)
#                    capability_id -> weight_q (how much it values each metric)
#
# These weights feed MD8 (unit utility) and MD9 (building utility) as the
# `profile_weights` argument.
#
# Design rules (Definition of Done, plan section 2 + "اصولِ ثابت"):
#   - PURE INFRASTRUCTURE: RefCounted, no WorldState / SceneTree / RNG / sim-hash.
#     Given a profile it returns a plain dictionary. Same profile -> byte-
#     identical output. Headlessly unit-testable.
#   - FIXED-POINT DETERMINISM (section 2.1 golden rule): the profile's [0..1]
#     floats are converted to fixed-point ONCE at the boundary
#     (q = round(f * SCALE)); every derived weight is an int in units of SCALE
#     (1.0 == 1000). No float survives into the returned weights, so the result
#     is byte-for-byte identical on any CPU (no ARM-vs-x86 desync).
#   - BACKWARD COMPATIBLE (MD5.2): this is a NEW layer ALONGSIDE
#     AiStrategyDerivationUtil, which is untouched. Existing tests keep passing.
#   - COSMETIC vs SIMULATION (section 2.2): weights may feed a deterministic
#     Command decision (so they MUST be deterministic, which they are) but this
#     util never writes WorldState and never touches state_hasher.
#   - English-only identifiers/comments (CODE_POLICY, pure ASCII).
# ----------------------------------------------------------------------------
class_name AiWeightDerivationUtil
extends RefCounted

# Fixed-point scale (section 2.1). A neutral weight is exactly 1.0 == SCALE, so
# a weight > SCALE means "value this more than neutral", < SCALE means "less".
const SCALE: int = 1000

# The neutral weight every role/capability starts from before personality tilts
# it. 1.0 in fixed-point.
const NEUTRAL_WEIGHT_Q: int = 1000

# How far a single fully-expressed knob can tilt a weight, in fixed-point. A
# knob at 1.0 (max) applied with full sensitivity moves a weight by up to this
# much; combined knobs are summed then clamped into [WEIGHT_MIN..WEIGHT_MAX].
const TILT_UNIT_Q: int = 500

# Hard bounds on any derived weight so an extreme profile can never zero out or
# blow up a role/capability. Keeps downstream utility scores well-conditioned.
const WEIGHT_MIN_Q: int = 200    # 0.2
const WEIGHT_MAX_Q: int = 2000   # 2.0

# The full closed set of unit roles this layer assigns a weight to. Mirrors
# RoleInferenceUtil.UNIT_SIGNATURES keys plus the "generic" fallback so every
# role a unit can be inferred as has a weight. Kept explicit (not read from the
# other util) so the contract is visible and versioned here.
const UNIT_ROLES: Array = [
	"anti_air", "control_unit", "economy_unit", "frontline_tank", "generic",
	"glass_cannon", "harasser", "ranged_dps", "scout", "siege_unit", "support",
]

# The building roles this layer weights (mirrors RoleInferenceUtil.BUILDING_SIGNATURES).
const BUILDING_ROLES: Array = [
	"defensive", "economic", "frontline", "production", "tech",
]

# --- Public API -------------------------------------------------------------

# Derive the full weight set for a profile:
#   {
#     "roles":        { role_id: weight_q },        # unit + building roles
#     "capabilities": { capability_id: weight_q },  # every CapabilityRegistry id
#   }
# `profile` is any object exposing get_value(category, knob) (AiProfile). null
# yields the all-neutral weight set (safe default, section 2.5).
static func derive_weights(profile) -> Dictionary:
	return {
		"roles": derive_role_weights(profile),
		"capabilities": derive_capability_weights(profile),
	}


# role_id -> weight_q for every unit and building role. Deterministic, fixed-point.
static func derive_role_weights(profile) -> Dictionary:
	var k: Dictionary = _knobs_q(profile)
	var out: Dictionary = {}

	# --- Unit roles: personality/strategy tilts the VALUE of each role. -------
	# Rationale is documented per role (MD5.3: "why this knob on this role").

	# A defensive/patient AI values the tank; an aggressive/offense one values
	# it less (it would rather commit fragile hitters).
	out["frontline_tank"] = _weight(k, [
		["defense", 1], ["patience", 1], ["caution", 1],
		["aggression", -1], ["offense", -1],
	])
	# Glass cannon: prized by aggressive/offense/focus_fire; shunned by cautious.
	out["glass_cannon"] = _weight(k, [
		["aggression", 1], ["offense", 1], ["focus_fire", 1],
		["caution", -1], ["defense", -1],
	])
	# Ranged DPS: solid all-round damage; military/focus_fire favour it.
	out["ranged_dps"] = _weight(k, [
		["military", 1], ["offense", 1], ["focus_fire", 1],
	])
	# Siege: offense + patience (siege pays off in a planned push) + military.
	out["siege_unit"] = _weight(k, [
		["offense", 1], ["military", 1], ["patience", 1],
	])
	# Scout: scouting + adaptability; disvalued by pure military mass.
	out["scout"] = _weight(k, [
		["scouting", 1], ["adaptability", 1], ["tempo", 1],
		["military", -1],
	])
	# Support: economy/technology-leaning, patient armies use support well.
	out["support"] = _weight(k, [
		["technology", 1], ["discipline", 1], ["patience", 1],
		["aggression", -1],
	])
	# Anti-air: defensive insurance; defense + caution + military.
	out["anti_air"] = _weight(k, [
		["defense", 1], ["caution", 1], ["military", 1],
	])
	# Harasser: harassment + tempo + boldness; shunned by patient/defensive.
	out["harasser"] = _weight(k, [
		["harassment", 1], ["tempo", 1], ["boldness", 1],
		["patience", -1], ["defense", -1],
	])
	# Economy unit: economy + greed + expansion.
	out["economy_unit"] = _weight(k, [
		["economy", 1], ["greed", 1], ["expansion", 1],
	])
	# Control unit: discipline + technology + caution (crowd control is a
	# planned, methodical tool).
	out["control_unit"] = _weight(k, [
		["discipline", 1], ["technology", 1], ["caution", 1],
	])
	# Generic: neutral -- the AI has no special opinion about an unclassifiable unit.
	out["generic"] = NEUTRAL_WEIGHT_Q

	# --- Building roles -------------------------------------------------------
	out["defensive"] = _weight(k, [
		["defense", 1], ["caution", 1], ["aggression", -1],
	])
	out["economic"] = _weight(k, [
		["economy", 1], ["greed", 1], ["expansion", 1],
	])
	out["production"] = _weight(k, [
		["military", 1], ["tempo", 1],
	])
	out["tech"] = _weight(k, [
		["technology", 1], ["patience", 1], ["discipline", 1],
	])
	out["frontline"] = _weight(k, [
		["offense", 1], ["defense", 1], ["expansion", 1],
	])
	return out


# capability_id -> weight_q for every capability in the CLOSED registry.
# Deterministic, fixed-point, iterates all_ids() in sorted order.
static func derive_capability_weights(profile) -> Dictionary:
	var k: Dictionary = _knobs_q(profile)
	# capability_id -> list of [knob_id, sign] contributions. Only ids present in
	# CapabilityRegistry are emitted; unknown mappings are simply skipped.
	var recipe: Dictionary = {
		"survivability":     [["defense", 1], ["caution", 1], ["aggression", -1]],
		"damage_output":     [["offense", 1], ["aggression", 1], ["military", 1]],
		"mobility":          [["tempo", 1], ["harassment", 1], ["scouting", 1]],
		"holding_power":     [["defense", 1], ["patience", 1]],
		"siege_power":       [["offense", 1], ["patience", 1]],
		"scout_power":       [["scouting", 1], ["adaptability", 1]],
		"support_power":     [["technology", 1], ["discipline", 1]],
		"cost_efficiency":   [["economy", 1], ["greed", 1], ["caution", 1]],
		"anti_air_power":    [["defense", 1], ["military", 1]],
		"resource_pressure": [["economy", 1], ["expansion", 1], ["greed", 1]],
		"defense_value":     [["defense", 1], ["caution", 1]],
		"production_value":  [["military", 1], ["tempo", 1]],
		"tech_value":        [["technology", 1], ["patience", 1]],
		"economic_value":    [["economy", 1], ["greed", 1], ["expansion", 1]],
		"frontline_value":   [["offense", 1], ["defense", 1]],
		"repair_value":      [["defense", 1], ["discipline", 1]],
		"control_value":     [["discipline", 1], ["technology", 1]],
	}
	var out: Dictionary = {}
	for cap_id in CapabilityRegistry.all_ids():
		if recipe.has(cap_id):
			out[cap_id] = _weight(k, recipe[cap_id] as Array)
		else:
			out[cap_id] = NEUTRAL_WEIGHT_Q
	return out


# MD5.4: a COSMETIC display summary of the roles this AI most prefers, for the
# AI builder / roster UI. Returns the top `count` unit roles by weight, sorted
# by (weight DESC, role ASC), as [ { role, weight_q } ]. Never feeds the sim.
static func preferred_roles(profile, count: int = 3) -> Array:
	var role_weights: Dictionary = derive_role_weights(profile)
	var items: Array = []
	for role_id in UNIT_ROLES:
		if role_id == "generic":
			continue
		items.append({ "role": role_id, "weight_q": int(role_weights.get(role_id, NEUTRAL_WEIGHT_Q)) })
	items.sort_custom(Callable(AiWeightDerivationUtil, "_pref_sort"))
	if count < 0:
		count = 0
	return items.slice(0, count)


# --- Internals ---------------------------------------------------------------

# Comparator for preferred_roles: weight DESC then role id ASC (stable).
static func _pref_sort(a: Dictionary, b: Dictionary) -> bool:
	var wa: int = int(a.get("weight_q", 0))
	var wb: int = int(b.get("weight_q", 0))
	if wa != wb:
		return wa > wb
	return str(a.get("role", "")) < str(b.get("role", ""))


# Compute one weight from NEUTRAL_WEIGHT_Q plus the summed tilt of the listed
# [knob_id, sign] contributions. Each knob's tilt is centred on the neutral 0.5
# knob value: (knob_q - SCALE/2) scaled by TILT_UNIT_Q, times the sign. So a
# knob at 1.0 with sign +1 adds +TILT_UNIT_Q/2 fully; a knob at 0.0 subtracts.
# Result clamped to [WEIGHT_MIN_Q..WEIGHT_MAX_Q]. Pure integer math.
static func _weight(knobs_q: Dictionary, contributions: Array) -> int:
	var w: int = NEUTRAL_WEIGHT_Q
	for c in contributions:
		var knob_id: String = str((c as Array)[0])
		var sign_i: int = int((c as Array)[1])
		var knob_q: int = int(knobs_q.get(knob_id, SCALE / 2))
		# Centred value in [-SCALE/2 .. +SCALE/2].
		var centred: int = knob_q - (SCALE / 2)
		# Tilt = centred * TILT_UNIT_Q / (SCALE/2)  -> full knob == +/- TILT_UNIT_Q.
		var tilt: int = _mul_div_round(centred, TILT_UNIT_Q, SCALE / 2)
		w += sign_i * tilt
	return _clamp_weight(w)


# Convert the profile's [0..1] float knobs to fixed-point [0..SCALE] ONCE, for
# every knob this util reads. Reads via get_value so it stays decoupled from the
# concrete AiProfile type. A null profile -> all knobs neutral (SCALE/2).
static func _knobs_q(profile) -> Dictionary:
	var out: Dictionary = {}
	# The personality + strategy_bias knobs this util's recipes reference.
	var wanted: Dictionary = {
		"personality": ["aggression", "caution", "patience", "greed", "boldness", "adaptability", "discipline", "ambition"],
		"strategy_bias": ["economy", "military", "technology", "expansion", "defense", "offense", "tempo", "scouting", "harassment", "focus_fire"],
	}
	for category in wanted.keys():
		for knob in (wanted[category] as Array):
			out[str(knob)] = _to_q(profile, str(category), str(knob))
	return out


# Read one knob and quantise it to fixed-point [0..SCALE]. Neutral 0.5 when the
# profile is null or lacks get_value. round-half-away-from-zero on the boundary.
static func _to_q(profile, category: String, knob: String) -> int:
	var f: float = 0.5
	if profile != null and profile.has_method("get_value"):
		f = float(profile.get_value(category, knob))
	if f < 0.0:
		f = 0.0
	if f > 1.0:
		f = 1.0
	var q: int = int(f * float(SCALE) + 0.5)
	if q < 0:
		q = 0
	if q > SCALE:
		q = SCALE
	return q


# Deterministic (a * b) / c with round-half-away-from-zero.
static func _mul_div_round(a: int, b: int, c: int) -> int:
	if c == 0:
		return 0
	var num: int = a * b
	var d: int = c if c > 0 else -c
	var half: int = d / 2
	if num >= 0:
		return (num + half) / d
	return -(((-num) + half) / d)


# Clamp a weight into [WEIGHT_MIN_Q..WEIGHT_MAX_Q].
static func _clamp_weight(w: int) -> int:
	if w < WEIGHT_MIN_Q:
		return WEIGHT_MIN_Q
	if w > WEIGHT_MAX_Q:
		return WEIGHT_MAX_Q
	return w
