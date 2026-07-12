# ai_builder_util.gd
# ----------------------------------------------------------------------------
# Project Nexus - AI builder form logic (Phase MC14, step 14.1, request 16).
#
# The PURE brain behind the AI Builder screen (ui/shared/ai_builder.gd). The
# builder UI lets a player create their own AI general: name it, pick an
# archetype, slide the personality / strategy / diplomacy / learning / difficulty
# knobs, then Export / Import / Duplicate / Reset / Randomize. Rather than bury
# that behaviour in a scene (untestable, and forbidden by our logic/render
# split), all of it lives here as static operations on the pure `AiProfile`
# model. The scene is a thin shell that renders sliders and forwards edits here.
#
# DESIGN RULES (project constitution):
#   - PURE + DETERMINISTIC: no WorldState, no SceneTree, no unseeded RNG.
#     `randomize_profile()` takes an explicit integer seed and derives every
#     knob from a hash of (seed, category, knob), so the SAME seed always yields
#     the SAME profile -- reproducible and unit-testable.
#   - Operates on / returns AiProfile objects and plain dictionaries only, so
#     Export/Import round-trips through AiProfile.to_dict()/from_dict().
#   - English-only identifiers/comments (CODE_POLICY, pure ASCII).
# ----------------------------------------------------------------------------
class_name AiBuilderUtil
extends RefCounted


# The archetype presets a builder can start from. Each maps to a small set of
# knob overrides applied on top of a neutral profile; unspecified knobs stay at
# AiProfile.NEUTRAL (0.5). Cosmetic role_key/archetype are set too so the
# summary util shows something sensible immediately.
const ARCHETYPE_PRESETS: Dictionary = {
	"balanced": {
		"role_key": "ai.role.balanced",
	},
	"aggressor": {
		"role_key": "ai.role.aggressor",
		"personality": {"aggression": 0.85, "boldness": 0.75, "caution": 0.25},
		"strategy_bias": {"offense": 0.85, "military": 0.8, "defense": 0.3, "tempo": 0.75},
	},
	"defender": {
		"role_key": "ai.role.defender",
		"personality": {"aggression": 0.2, "caution": 0.85, "patience": 0.8},
		"strategy_bias": {"defense": 0.9, "offense": 0.25, "economy": 0.6},
	},
	"economist": {
		"role_key": "ai.role.balanced",
		"personality": {"greed": 0.75, "patience": 0.7},
		"strategy_bias": {"economy": 0.9, "expansion": 0.75, "military": 0.4},
	},
	"diplomat": {
		"role_key": "ai.role.diplomat",
		"personality": {"loyalty": 0.75, "aggression": 0.3},
		"diplomacy_bias": {"sociability": 0.9, "trust": 0.7, "generosity": 0.7, "deceit": 0.2},
	},
	"raider": {
		"role_key": "ai.role.raider",
		"personality": {"boldness": 0.8, "discipline": 0.4},
		"strategy_bias": {"harassment": 0.9, "scouting": 0.7, "tempo": 0.8, "focus_fire": 0.3},
	},
	"conqueror": {
		"role_key": "ai.role.conqueror",
		"personality": {"ambition": 0.9, "aggression": 0.8, "pride": 0.7},
		"strategy_bias": {"expansion": 0.85, "military": 0.8, "offense": 0.8},
	},
}

# The stable, ordered list of archetype ids the builder offers.
const ARCHETYPES: Array = [
	"balanced", "aggressor", "defender", "economist", "diplomat", "raider", "conqueror",
]


# --- Construction / presets --------------------------------------------------

# A fresh neutral profile carrying `id` (every knob = 0.5, "balanced" archetype).
static func new_profile(id: String) -> AiProfile:
	var p: AiProfile = AiProfile.new()
	p.init_new(_safe_id(id))
	apply_archetype(p, "balanced")
	return p


# Apply an archetype preset ON TOP of the current profile. Unknown archetype ids
# are treated as "balanced". Returns the same profile for chaining. Only the
# knobs named in the preset change; the id is preserved.
static func apply_archetype(profile: AiProfile, archetype: String) -> AiProfile:
	if profile == null:
		return profile
	var key: String = archetype if ARCHETYPE_PRESETS.has(archetype) else "balanced"
	var preset: Dictionary = ARCHETYPE_PRESETS[key]
	# Cosmetic metadata is set via the profile's own dict round-trip so the
	# archetype tag / role key travel with an export.
	var d: Dictionary = profile.to_dict()
	d["archetype"] = key
	if preset.has("role_key"):
		d["role_key"] = preset["role_key"]
	for category in AiProfile.CATEGORIES:
		if not (preset.get(category, null) is Dictionary):
			continue
		var overrides: Dictionary = preset[category]
		var vec: Dictionary = d.get(category, {})
		for knob in overrides.keys():
			vec[knob] = float(overrides[knob])
		d[category] = vec
	profile.load(d)
	return profile


# --- Editing -----------------------------------------------------------------

# Set the profile's display-name key (cosmetic). The builder stores the raw name
# a user types under a synthesised key; the scene handles the localization side.
static func set_display_name_key(profile: AiProfile, name_key: String) -> void:
	if profile == null:
		return
	var d: Dictionary = profile.to_dict()
	d["display_name_key"] = str(name_key).strip_edges()
	profile.load(d)


# Set one knob (clamped by AiProfile). Thin pass-through so the UI has one entry
# point for every slider. Returns the stored (clamped) value.
static func set_knob(profile: AiProfile, category: String, knob: String, value: float) -> float:
	if profile == null:
		return AiProfile.NEUTRAL
	return profile.set_value(category, knob, value)


# Reset every numeric knob back to neutral (0.5) while KEEPING the id, display
# name and archetype. Used by the builder's "Reset" button.
static func reset_knobs(profile: AiProfile) -> AiProfile:
	if profile == null:
		return profile
	for category in AiProfile.CATEGORIES:
		for knob in AiProfile.keys_for(category):
			profile.set_value(category, knob, AiProfile.NEUTRAL)
	return profile


# --- Duplicate / Randomize ---------------------------------------------------

# A deep, independent copy of `profile` under a new id. Editing the copy never
# touches the original (verified by tests).
static func duplicate_profile(profile: AiProfile, new_id: String) -> AiProfile:
	if profile == null:
		return new_profile(new_id)
	var d: Dictionary = profile.to_dict()
	d["id"] = _safe_id(new_id)
	return AiProfile.from_dict(d)


# A fully deterministic "surprise me" profile: every knob is derived from a hash
# of (seed, category, knob), so the SAME seed reproduces the SAME profile. The id
# and archetype are preserved (archetype defaults to "balanced" for a fresh id).
# This keeps Randomize testable and replay-safe.
static func randomize_profile(id: String, seed_value: int) -> AiProfile:
	var p: AiProfile = new_profile(id)
	for category in AiProfile.CATEGORIES:
		for knob in AiProfile.keys_for(category):
			p.set_value(category, knob, _seeded_unit(seed_value, category, knob))
	return p


# --- Export / Import ---------------------------------------------------------

# Serialise a profile to a plain, deterministic dictionary for a .nexai export.
static func export_dict(profile: AiProfile) -> Dictionary:
	if profile == null:
		return {}
	return profile.to_dict()


# Rebuild a profile from an imported dictionary. Invalid / id-less payloads yield
# a neutral fallback that still validates, so an import never crashes the UI.
# Returns { "profile": AiProfile, "ok": bool, "reason": String }.
static func import_dict(data: Dictionary) -> Dictionary:
	var p: AiProfile = AiProfile.from_dict(data)
	var reason: String = p.validate()
	if not reason.is_empty():
		var fallback: AiProfile = new_profile("imported")
		return { "profile": fallback, "ok": false, "reason": reason }
	return { "profile": p, "ok": true, "reason": "" }


# --- Helpers -----------------------------------------------------------------

# A stable per-knob value in [0,1] from a seed. Uses a simple integer hash of the
# combined string so the same (seed, category, knob) always maps to the same
# float, with no engine RNG involved.
static func _seeded_unit(seed_value: int, category: String, knob: String) -> float:
	var basis: String = "%d|%s|%s" % [seed_value, category, knob]
	var h: int = int(hash(basis)) & 0x7fffffff
	return float(h % 1000) / 999.0


# Normalise a requested id: trimmed, non-empty; falls back to "custom_ai".
static func _safe_id(id: String) -> String:
	var s: String = str(id).strip_edges()
	if s.is_empty():
		return "custom_ai"
	return s
