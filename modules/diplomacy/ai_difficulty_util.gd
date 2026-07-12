# ai_difficulty_util.gd
# ----------------------------------------------------------------------------
# Project Nexus - Difficulty as QUALITY OF ANALYSIS, not error removal
# (Phase MC13, step 13.4, request 15).
#
# The plan (section 1.d) is explicit: difficulty must NOT be "the AI stops
# making mistakes". Instead the three difficulty knobs (MC12 profile) shape:
#
#   * analysis_quality : how much the clean cost/benefit score (from
#                        AiDiplomacyBrain) is trusted vs. perturbed. A low
#                        quality AI evaluates the board sloppily, so its score
#                        drifts more from the ideal.
#   * reaction_speed   : how often the AI is allowed to act (cadence gate). A
#                        slow AI only re-evaluates every few opportunities.
#   * execution        : the inverse of the unforced-error tendency. Even at
#                        execution == 1.0 the error floor is > 0, so the very
#                        best AI still occasionally fumbles a decision.
#
# DESIGN RULES (project constitution):
#   * PURE + DETERMINISTIC: every "random" value comes from a SEEDED hash of
#     (match_seed, tick, owner, salt). NO RNG object, NO WorldState, NO
#     SceneTree. Same inputs -> same jitter, so every lockstep peer computes the
#     identical "mistake". This is the ONLY way error can be introduced without
#     breaking determinism.
#   * The brain (MC13.1) stays a clean best-effort evaluator; THIS util is the
#     deterministic perturbation layer the consumer (MC13.5) wraps around it.
#   * English-only identifiers/comments (CODE_POLICY, pure ASCII).
# ----------------------------------------------------------------------------
class_name AiDifficultyUtil
extends RefCounted

# The unforced-error rate NEVER reaches zero: even a flawless (execution == 1.0)
# AI misfires this fraction of the time. Enforces plan rule "error > 0 always".
const MIN_UNFORCED_ERROR: float = 0.02
# The clumsiest (execution == 0.0) AI errs at most this often, so it is still
# playable rather than purely random.
const MAX_UNFORCED_ERROR: float = 0.30

# How far a low-analysis AI's evaluation score can drift from the clean value
# (at analysis_quality == 0.0). At quality == 1.0 the drift shrinks toward zero.
const MAX_SCORE_JITTER: float = 0.30

# Reaction cadence: the slowest AI (reaction_speed == 0.0) acts once every this
# many opportunities; the fastest (1.0) acts every opportunity.
const MAX_REACTION_PERIOD: int = 6


# --- Deterministic seeded noise ---------------------------------------------

# A stable 0..1 value derived purely from the (seed, tick, owner, salt) tuple.
# This is the single source of "randomness" in the difficulty layer; because it
# is a hash of integers it is identical on every peer for the same inputs.
static func seeded_unit(match_seed: int, tick: int, owner: int, salt: int) -> float:
	# Mix the inputs into one string, hash it, and fold into [0, 1). String
	# hashing is stable across runs/platforms in Godot for the same string.
	var key: String = "%d|%d|%d|%d" % [match_seed, tick, owner, salt]
	var h: int = abs(key.hash())
	# 1000003 is a prime modulus giving a fine-grained fraction in [0, 1).
	return float(h % 1000003) / 1000003.0


# --- Difficulty-derived thresholds ------------------------------------------

# The unforced-error probability for a profile, mapped from its `execution`
# knob. execution 1.0 -> MIN_UNFORCED_ERROR, execution 0.0 -> MAX_UNFORCED_ERROR.
static func unforced_error_rate(profile) -> float:
	var execution: float = _diff(profile, "execution")
	var rate: float = lerpf(MAX_UNFORCED_ERROR, MIN_UNFORCED_ERROR, clampf(execution, 0.0, 1.0))
	# Guard the floor even if a bad profile pushed execution above 1.0.
	return maxf(MIN_UNFORCED_ERROR, rate)


# How many opportunities pass between actions for a profile (>= 1). A fast AI
# (reaction_speed 1.0) returns 1 (acts every chance); a slow one waits longer.
static func reaction_period(profile) -> int:
	var speed: float = clampf(_diff(profile, "reaction_speed"), 0.0, 1.0)
	var period: float = lerpf(float(MAX_REACTION_PERIOD), 1.0, speed)
	return int(max(1, round(period)))


# True when this owner is allowed to act on `tick` given its reaction cadence.
# Phase-shifted by owner so different AIs do not all fire on the same tick.
static func should_react(profile, tick: int, owner: int) -> bool:
	var period: int = reaction_period(profile)
	if period <= 1:
		return true
	return ((tick + owner) % period) == 0


# --- Applying difficulty to a brain decision --------------------------------

# Perturb a clean brain score with analysis-quality jitter. A low-quality AI's
# score wanders (in both directions) by up to MAX_SCORE_JITTER; a high-quality
# AI stays close to the clean value. Deterministic via seeded_unit.
static func perturb_score(score: float, profile, match_seed: int, tick: int, owner: int) -> float:
	var quality: float = clampf(_diff(profile, "analysis_quality"), 0.0, 1.0)
	var span: float = MAX_SCORE_JITTER * (1.0 - quality)
	# Map the seeded unit [0,1) into a symmetric [-span, +span] offset.
	var noise: float = (seeded_unit(match_seed, tick, owner, 7) * 2.0 - 1.0) * span
	return clampf(score + noise, 0.0, 1.0)


# True when this decision is an unforced error (the AI should fumble it). Purely
# a function of the seeded noise vs. the profile's error rate, so it is the same
# on every peer. Uses a distinct salt from perturb_score to stay independent.
static func is_unforced_error(profile, match_seed: int, tick: int, owner: int) -> bool:
	var rate: float = unforced_error_rate(profile)
	return seeded_unit(match_seed, tick, owner, 13) < rate


# Convenience wrapper: given the brain's clean output dictionary, return a
# possibly-perturbed copy reflecting this AI's difficulty. On an unforced error
# the action is downgraded to "none" (the AI hesitates / misplays); otherwise the
# score is jittered by analysis quality. Never mutates the input.
static func apply(decision: Dictionary, profile, match_seed: int, tick: int, owner: int) -> Dictionary:
	var out: Dictionary = decision.duplicate(true)
	if is_unforced_error(profile, match_seed, tick, owner):
		out["action"] = "none"
		out["unforced_error"] = true
		return out
	var clean: float = 0.0
	if out.has("score"):
		clean = float(out["score"])
	out["score"] = perturb_score(clean, profile, match_seed, tick, owner)
	out["unforced_error"] = false
	return out


# --- Helpers ----------------------------------------------------------------

static func _diff(profile, knob: String) -> float:
	if profile != null and profile.has_method("get_value"):
		return float(profile.get_value("difficulty", knob))
	# No profile -> a middling difficulty.
	return 0.5
