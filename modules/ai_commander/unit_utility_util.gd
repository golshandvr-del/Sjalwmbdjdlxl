# unit_utility_util.gd
# ----------------------------------------------------------------------------
# Project Nexus - Utility scoring for AI unit PRODUCTION (Phase MD8, expert
# item 7). THE critical phase: instead of always producing "soldier", the AI
# scores every buildable unit and picks the best fit for its personality and
# the current battlefield context.
#
# The score is a fixed-point weighted sum over a unit's CAPABILITY card
# (DerivedMetricsUtil, MD3) times the AI's PROFILE capability weights
# (AiWeightDerivationUtil.derive_capability_weights, MD5), nudged by ROLE fit
# (RoleInferenceUtil, MD4), current battlefield NEED (derived from the MD7
# Context vector) and a small seeded difficulty noise (MD8.3 / MC13.4).
#
# Everything is q-scaled (SCALE = 1000) integer math so it is byte-identical on
# every peer/replay -- utility scoring feeds unit production, which is part of
# the lockstep simulation, so it MUST be deterministic.
#
# Logic/Render Separation: nothing here touches the world model or the scene
# tree; it consumes plain Dictionaries (caps / weights / context) built elsewhere.
#
# CODE LANGUAGE POLICY: English-only identifiers/comments.
# ----------------------------------------------------------------------------
class_name UnitUtilityUtil
extends RefCounted


# Fixed-point scale shared with the capability / weight layers.
const SCALE: int = 1000


# The capability dimensions that feed a unit's combat/production utility. Each
# is read from the capability card (q 0..SCALE) and multiplied by the matching
# profile weight (q around SCALE). Kept as an explicit, sorted list so the dot
# product is deterministic and easy to test.
const SCORED_CAPS: Array = [
	"survivability",
	"damage_output",
	"mobility",
	"holding_power",
	"siege_power",
	"anti_air_power",
	"scout_power",
	"support_power",
	"cost_efficiency",
]


# --- Fixed-point helpers -----------------------------------------------------

static func _mul_div_round(a: int, b: int, c: int) -> int:
	if c == 0:
		return 0
	var num: int = a * b
	var half: int = c / 2
	if num >= 0:
		return (num + half) / c
	return -((-num + half) / c)


# The weighted-capability component: sum over SCORED_CAPS of cap_q * weight_q,
# folded back to q by dividing one SCALE out. A neutral profile (all weights =
# SCALE) reproduces the plain sum of capabilities.
static func capability_component(caps: Dictionary, weights: Dictionary) -> int:
	var total: int = 0
	for cap_id in SCORED_CAPS:
		var cap_q: int = int(caps.get(cap_id, 0))
		var w_q: int = int(weights.get(cap_id, SCALE))
		total += _mul_div_round(cap_q, w_q, SCALE)
	return total


# The role-fit component: if the unit's primary role is one the profile prefers
# (present in preferred_roles), add a bonus proportional to how strongly the
# profile favours that role. `role_weights` maps role_id -> weight_q.
static func role_fit_component(primary_role: String, role_weights: Dictionary) -> int:
	var w_q: int = int(role_weights.get(primary_role, SCALE))
	# Express as a deviation from neutral so a disliked role can subtract.
	return w_q - SCALE


# The current-need component (MD8.2): derived from the MD7 Context vector so the
# AI leans toward what the battlefield demands right now. All context values are
# q-scaled 0..SCALE. Under threat -> value survivability/holding; frontline
# pressure -> value damage; weak economy -> value cost efficiency.
static func current_need(caps: Dictionary, context: Dictionary) -> int:
	var under_threat: int = int(context.get("under_threat", 0))
	var frontline: int = int(context.get("frontline_pressure", 0))
	var economy_gap: int = int(context.get("economy_gap", 0))
	var need: int = 0
	# When under threat, durable/holding units satisfy the need.
	need += _mul_div_round(int(caps.get("survivability", 0)) + int(caps.get("holding_power", 0)), under_threat, SCALE * 2)
	# When the frontline is under pressure, raw damage satisfies the need.
	need += _mul_div_round(int(caps.get("damage_output", 0)), frontline, SCALE)
	# When the economy is weak, cheap/efficient units satisfy the need.
	need += _mul_div_round(int(caps.get("cost_efficiency", 0)), economy_gap, SCALE)
	return need


# MD8.3: deterministic difficulty noise on a candidate's score. Uses the shared
# seeded hash (AiDifficultyUtil.seeded_unit) so the SAME (seed, tick, owner,
# unit) always yields the SAME nudge -- never unseeded randomness. `strength_q`
# is how large the noise band is (q); even the hardest AI keeps it > 0.
static func difficulty_noise(match_seed: int, tick: int, owner: int, unit_salt: int, strength_q: int) -> int:
	if strength_q <= 0:
		return 0
	var unit: float = AiDifficultyUtil.seeded_unit(match_seed, tick, owner, unit_salt)
	# Map [0,1) -> [-strength_q, +strength_q].
	var signed: int = int(round((unit * 2.0 - 1.0) * float(strength_q)))
	return signed


# The full utility of one unit candidate. Combines the four components plus the
# seeded noise. `profile_weights` bundles {"capabilities": {...}, "roles": {...}}
# as produced by AiWeightDerivationUtil.derive_weights.
static func score_unit(
		caps: Dictionary,
		primary_role: String,
		profile_weights: Dictionary,
		context: Dictionary,
		match_seed: int,
		tick: int,
		owner: int,
		unit_salt: int,
		noise_strength_q: int) -> int:
	var cap_weights: Dictionary = (profile_weights.get("capabilities", {}) as Dictionary)
	var role_weights: Dictionary = (profile_weights.get("roles", {}) as Dictionary)
	var score: int = 0
	score += capability_component(caps, cap_weights)
	score += role_fit_component(primary_role, role_weights)
	score += current_need(caps, context)
	score += difficulty_noise(match_seed, tick, owner, unit_salt, noise_strength_q)
	return score


# MD8.4: choose the best candidate from a list. Each candidate is a Dictionary
# {"id", "caps", "primary_role"}. Scores every candidate, picks the maximum with
# a STABLE tie-break on id (lexicographic) so every peer agrees. Returns the
# chosen id, or "" when there are no candidates. Backward compatible: a
# single-candidate list ("soldier" only) always returns that candidate.
static func select_best(
		candidates: Array,
		profile_weights: Dictionary,
		context: Dictionary,
		match_seed: int,
		tick: int,
		owner: int,
		noise_strength_q: int) -> String:
	var best_id: String = ""
	var best_score: int = -2147483648
	# Iterate in id-sorted order for a deterministic scan.
	var sorted: Array = candidates.duplicate()
	sorted.sort_custom(func(a, b): return str((a as Dictionary).get("id", "")) < str((b as Dictionary).get("id", "")))
	for raw in sorted:
		var cand: Dictionary = raw as Dictionary
		var id: String = str(cand.get("id", ""))
		if id == "":
			continue
		var salt: int = abs(id.hash())
		var s: int = score_unit(
			(cand.get("caps", {}) as Dictionary),
			str(cand.get("primary_role", RoleInferenceUtil.GENERIC_ROLE)),
			profile_weights,
			context,
			match_seed, tick, owner, salt, noise_strength_q)
		if s > best_score:
			best_score = s
			best_id = id
	return best_id
