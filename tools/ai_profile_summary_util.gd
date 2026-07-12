# ai_profile_summary_util.gd
# ----------------------------------------------------------------------------
# Project Nexus - AI profile summary / tags (Phase MC12, step 12.4, request 13).
#
# A PURE presentation helper that turns a 35-knob `AiProfile` vector into a
# short, human-readable summary for the UI (match setup cards, the AI builder
# preview in MC14): a ROLE, a play STYLE, a DANGER rating, and a small set of
# descriptive TAGS. This is the "at a glance, who is this general?" layer.
#
# Everything here is COSMETIC: it never touches WorldState or the simulation and
# never affects the deterministic hash. It is a deterministic pure function of
# the profile alone, so tests can assert exact tags/ratings for a given vector.
#
# The returned tokens are i18n KEYS (not display text): callers pass them
# through the localization layer. The keys live under "ai.tag.*" / "ai.role.*"
# / "ai.style.*" / "ai.danger.*" (added to en/fa in MC12.5).
#
# CODE LANGUAGE POLICY: English-only identifiers/comments (pure ASCII).
# ----------------------------------------------------------------------------
class_name AiProfileSummaryUtil
extends RefCounted

# Danger ratings, lowest -> highest. Derived from difficulty + aggression.
const DANGER_LEVELS: Array = ["harmless", "mild", "moderate", "dangerous", "lethal"]

# The threshold at/above which a knob is considered "high" for tagging.
const HIGH: float = 0.66
# The threshold at/below which a knob is considered "low" for tagging.
const LOW: float = 0.34


# The i18n role key for a profile. Prefers the profile's explicit role_key;
# otherwise falls back to an archetype-derived key so a hand-built AI (which may
# omit role_key) still shows something sensible.
static func role_key(profile) -> String:
	if profile != null and profile.has_method("role_key"):
		var rk: String = str(profile.role_key())
		if not rk.is_empty():
			return rk
	return "ai.role.%s" % _archetype_of(profile)


# The i18n play-style key: the dominant strategic leaning of the vector.
# Deterministic tie-break by the fixed order of the candidate list.
static func style_key(profile) -> String:
	var offense: float = _s(profile, "offense")
	var defense: float = _s(profile, "defense")
	var economy: float = _s(profile, "economy")
	var technology: float = _s(profile, "technology")
	var harassment: float = _s(profile, "harassment")
	var expansion: float = _s(profile, "expansion")
	# Ordered candidates: (key, score). First max wins (stable).
	var candidates: Array = [
		["ai.style.aggressive", offense],
		["ai.style.defensive", defense],
		["ai.style.economic", economy],
		["ai.style.technological", technology],
		["ai.style.harasser", harassment],
		["ai.style.expansionist", expansion],
	]
	var best_key: String = str(candidates[0][0])
	var best_val: float = float(candidates[0][1])
	for i in range(1, candidates.size()):
		if float(candidates[i][1]) > best_val:
			best_val = float(candidates[i][1])
			best_key = str(candidates[i][0])
	return best_key


# A danger index in [0, DANGER_LEVELS.size()-1] combining raw skill (difficulty)
# with aggression, so a highly-skilled but passive AI is less "dangerous-feeling"
# than a highly-skilled aggressive one. Deterministic.
static func danger_index(profile) -> int:
	var analysis: float = _d(profile, "analysis_quality")
	var reaction: float = _d(profile, "reaction_speed")
	var execution: float = _d(profile, "execution")
	var aggression: float = _p(profile, "aggression")
	# Weight skill (3 knobs, 0.7) over aggression (0.3).
	var skill: float = (analysis + reaction + execution) / 3.0
	var score: float = clampf(0.7 * skill + 0.3 * aggression, 0.0, 1.0)
	var last: int = DANGER_LEVELS.size() - 1
	return int(round(score * float(last)))


# The i18n danger key for a profile.
static func danger_key(profile) -> String:
	return "ai.danger.%s" % DANGER_LEVELS[danger_index(profile)]


# A deterministic, ordered list of descriptive i18n tag keys ("ai.tag.*"). Only
# notably-high / notably-low knobs earn a tag, so the set is compact. Order is
# fixed (evaluation order below) so the UI is stable.
static func tags(profile) -> Array:
	var out: Array = []
	# Personality-driven tags.
	if _p(profile, "aggression") >= HIGH:
		out.append("ai.tag.aggressive")
	if _p(profile, "caution") >= HIGH:
		out.append("ai.tag.cautious")
	if _p(profile, "patience") >= HIGH:
		out.append("ai.tag.patient")
	if _p(profile, "boldness") >= HIGH:
		out.append("ai.tag.bold")
	if _p(profile, "greed") >= HIGH:
		out.append("ai.tag.greedy")
	# Diplomacy-driven tags.
	if _dip(profile, "trust") >= HIGH:
		out.append("ai.tag.trusting")
	if _dip(profile, "deceit") >= HIGH:
		out.append("ai.tag.treacherous")
	if _dip(profile, "vengeance") >= HIGH:
		out.append("ai.tag.vengeful")
	if _dip(profile, "generosity") >= HIGH:
		out.append("ai.tag.generous")
	if _dip(profile, "sociability") <= LOW:
		out.append("ai.tag.reclusive")
	# Strategy-driven tags.
	if _s(profile, "technology") >= HIGH:
		out.append("ai.tag.techie")
	if _s(profile, "harassment") >= HIGH:
		out.append("ai.tag.raider")
	if _s(profile, "economy") >= HIGH:
		out.append("ai.tag.economist")
	return out


# One-call summary bundle for the UI. All fields are i18n keys / integers, safe
# to render directly after localization.
static func summarize(profile) -> Dictionary:
	return {
		"id": _id_of(profile),
		"name_key": _name_key_of(profile),
		"role_key": role_key(profile),
		"style_key": style_key(profile),
		"danger_index": danger_index(profile),
		"danger_key": danger_key(profile),
		"tags": tags(profile),
	}


# --- Helpers ----------------------------------------------------------------

static func _p(profile, knob: String) -> float:
	if profile != null and profile.has_method("get_value"):
		return float(profile.get_value("personality", knob))
	return 0.5


static func _s(profile, knob: String) -> float:
	if profile != null and profile.has_method("get_value"):
		return float(profile.get_value("strategy_bias", knob))
	return 0.5


static func _dip(profile, knob: String) -> float:
	if profile != null and profile.has_method("get_value"):
		return float(profile.get_value("diplomacy_bias", knob))
	return 0.5


static func _d(profile, knob: String) -> float:
	if profile != null and profile.has_method("get_value"):
		return float(profile.get_value("difficulty", knob))
	return 0.5


static func _archetype_of(profile) -> String:
	if profile != null and profile.has_method("archetype"):
		var a: String = str(profile.archetype())
		if not a.is_empty():
			return a
	return "balanced"


static func _id_of(profile) -> String:
	if profile != null and profile.has_method("id"):
		return str(profile.id())
	return ""


static func _name_key_of(profile) -> String:
	if profile != null and profile.has_method("display_name_key"):
		var k: String = str(profile.display_name_key())
		if not k.is_empty():
			return k
	return "ai.profile.balanced.name"
