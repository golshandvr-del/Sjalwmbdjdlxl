# ai_strategy_derivation_util.gd
# ----------------------------------------------------------------------------
# Project Nexus - AI strategy derivation (Phase MC12, step 12.3, request 13).
#
# Bridges the FIXED 35-knob `AiProfile` vector (MC12.1) to the concrete
# behaviour knobs the `StrategicAiModule` already reasons about (attack army
# size, expansion cap, upgrade reserve, research-first). Historically the
# strategic AI only had three hard-coded "personality" presets
# ("economic" / "balanced" / "aggressive"); this util lets any profile's
# `strategy_bias` + `personality` vector drive those numbers instead, so the
# nine historical generals (and any user-built AI from MC14) each play
# distinctly.
#
# Design rules (the project constitution):
#   - PURE: no WorldState, no SceneTree, no RNG. Given a profile it returns a
#     plain behaviour dictionary. Same profile -> byte-identical output.
#   - DETERMINISTIC: every derived number is a fixed arithmetic function of the
#     profile knobs and is rounded/clamped into a stable integer/bool range.
#   - BACKWARD COMPATIBLE: `derive_from_name()` reproduces the three legacy
#     presets exactly, so existing scenarios and tests keep the same numbers.
#   - English-only identifiers/comments (CODE_POLICY, pure ASCII).
#
# The behaviour dictionary shape MATCHES StrategicAiModule.PERSONALITY entries:
#   { "attack_army_size": int, "expansion_cap": int,
#     "upgrade_reserve": int, "research_first": bool }
# ----------------------------------------------------------------------------
class_name AiStrategyDerivationUtil
extends RefCounted

# The legacy presets, kept verbatim so `derive_from_name()` is a drop-in for
# StrategicAiModule.PERSONALITY. New code should prefer `derive_from_profile()`.
const LEGACY_PRESETS: Dictionary = {
	"economic":   { "attack_army_size": 6, "expansion_cap": 3, "upgrade_reserve": 300, "research_first": true },
	"balanced":   { "attack_army_size": 4, "expansion_cap": 2, "upgrade_reserve": 250, "research_first": true },
	"aggressive": { "attack_army_size": 3, "expansion_cap": 1, "upgrade_reserve": 400, "research_first": false },
}

# Bounds for the derived numbers. Chosen to span the legacy values so profiles
# interpolate across the same range humans already tuned against.
const ARMY_MIN: int = 2
const ARMY_MAX: int = 8
const EXPANSION_MIN: int = 0
const EXPANSION_MAX: int = 4
const RESERVE_MIN: int = 150
const RESERVE_MAX: int = 500


# Return the legacy preset for a name, falling back to "balanced". This keeps
# older scenarios / tests that pass "economic"/"balanced"/"aggressive"
# byte-identical to the pre-MC12 behaviour.
static func derive_from_name(name: String) -> Dictionary:
	var key: String = str(name).strip_edges()
	if LEGACY_PRESETS.has(key):
		return (LEGACY_PRESETS[key] as Dictionary).duplicate(true)
	return (LEGACY_PRESETS["balanced"] as Dictionary).duplicate(true)


# Derive strategic behaviour knobs from a full AiProfile vector.
#
#   attack_army_size : a patient / economic general masses a bigger army before
#                      attacking; an aggressive / bold one commits sooner. So it
#                      grows with (patience + military + defense) and shrinks
#                      with (aggression + offense + tempo).
#   expansion_cap    : driven by the expansion + economy + greed knobs.
#   upgrade_reserve  : cautious / defensive generals keep a bigger buffer;
#                      aggressive ones spend it. Grows with (caution + defense),
#                      shrinks with aggression.
#   research_first   : a tech/economy-leaning general researches before pushing
#                      out; a tempo/offense one expands/attacks first.
static func derive_from_profile(profile) -> Dictionary:
	if profile == null:
		return derive_from_name("balanced")

	var aggression: float = _p(profile, "personality", "aggression")
	var caution: float = _p(profile, "personality", "caution")
	var patience: float = _p(profile, "personality", "patience")
	var greed: float = _p(profile, "personality", "greed")

	var economy: float = _p(profile, "strategy_bias", "economy")
	var military: float = _p(profile, "strategy_bias", "military")
	var technology: float = _p(profile, "strategy_bias", "technology")
	var expansion: float = _p(profile, "strategy_bias", "expansion")
	var defense: float = _p(profile, "strategy_bias", "defense")
	var offense: float = _p(profile, "strategy_bias", "offense")
	var tempo: float = _p(profile, "strategy_bias", "tempo")

	# --- attack_army_size: mass more when patient/defensive, less when fast. ---
	# Base 0.5 -> patience/military/defense push up, aggression/offense/tempo down.
	var army_score: float = 0.5 \
		+ 0.25 * (patience + military + defense - 1.5) \
		- 0.25 * (aggression + offense + tempo - 1.5)
	var attack_army_size: int = _scale_int(army_score, ARMY_MIN, ARMY_MAX)

	# --- expansion_cap: how many command buildings it tries to own. ---
	var expand_score: float = (expansion + economy + greed) / 3.0
	var expansion_cap: int = _scale_int(expand_score, EXPANSION_MIN, EXPANSION_MAX)

	# --- upgrade_reserve: cautious/defensive keep buffer, aggressive spend. ---
	var reserve_score: float = 0.5 + 0.5 * (caution + defense - aggression)
	var upgrade_reserve: int = _round_to(_scale_int(reserve_score, RESERVE_MIN, RESERVE_MAX), 10)

	# --- research_first: tech/economy vs tempo/offense. ---
	var research_first: bool = (technology + economy) >= (tempo + offense)

	return {
		"attack_army_size": attack_army_size,
		"expansion_cap": expansion_cap,
		"upgrade_reserve": upgrade_reserve,
		"research_first": research_first,
	}


# --- Helpers ----------------------------------------------------------------

# Read a knob from a profile if it exposes get_value(category, knob); otherwise
# neutral 0.5. Keeps this util decoupled from the concrete AiProfile type.
static func _p(profile, category: String, knob: String) -> float:
	if profile != null and profile.has_method("get_value"):
		return float(profile.get_value(category, knob))
	return 0.5


# Map a score in [0,1] to an integer in [lo, hi] deterministically, clamping
# out-of-range scores. round() gives stable half-up behaviour.
static func _scale_int(score: float, lo: int, hi: int) -> int:
	var s: float = clampf(score, 0.0, 1.0)
	return int(round(lo + s * float(hi - lo)))


# Round an integer to the nearest multiple of `step` (>=1). Deterministic.
static func _round_to(value: int, step: int) -> int:
	if step <= 1:
		return value
	return int(round(float(value) / float(step))) * step
