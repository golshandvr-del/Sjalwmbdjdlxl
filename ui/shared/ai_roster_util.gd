# ai_roster_util.gd
# ----------------------------------------------------------------------------
# Project Nexus - AI roster selection for match setup (Phase MC14, step 14.2,
# request 16).
#
# The PURE brain behind "which AI generals take part in this match". Match setup
# shows a roster that combines:
#   * the nine BUILT-IN historical generals (AiProfileCatalog.DEFAULT_IDS), and
#   * the player's OWN custom-built AIs (saved by the AI Builder, MC14.1).
# The player ticks the ones they want; each roster row carries a compact summary
# card (role / style / danger / tags) from AiProfileSummaryUtil (MC12.4).
#
# This is a THIN, testable model exactly like CatalogListUtil: it takes plain
# data in (a list of built-in ids + a map of custom-profile dicts) and returns a
# deterministic, id-sorted Array of small row dictionaries, plus helpers to
# resolve a user selection into the AiProfile objects match setup will seat.
#
# DESIGN RULES (project constitution):
#   - PURE + DETERMINISTIC: no WorldState, no SceneTree, no unseeded RNG. Same
#     inputs -> same rows (rows sorted: built-ins first, then custom, each block
#     id-sorted, so the UI is stable across machines / runs).
#   - COSMETIC: the roster only PICKS inputs to the AI; it never touches the
#     deterministic hash. Determinism of the sim comes later, in the AI itself.
#   - English-only identifiers/comments (CODE_POLICY, pure ASCII).
# ----------------------------------------------------------------------------
class_name AiRosterUtil
extends RefCounted

# Row "source" tags so the UI can badge built-in vs. user-made generals.
const SOURCE_BUILTIN: String = "builtin"
const SOURCE_CUSTOM: String = "custom"


# Build the full, ordered roster. `builtin_ids` is a list of built-in profile ids
# (defaults to AiProfileCatalog.DEFAULT_IDS when empty); `custom_profiles` maps a
# custom id -> its plain profile dictionary (as exported by the AI Builder).
# `reader` (optional) is a DataLoader-like object exposing load_json_file(); when
# given it is used to load the built-in JSON so rows carry a real summary. When
# null, built-ins fall back to a neutral summary card (still valid + listable).
#
# Returns an Array of rows, each:
#   { id, name_key, source, role_key, style_key, danger_index, danger_key, tags }
# Built-in rows come first (id-sorted), then custom rows (id-sorted). A custom id
# that collides with a built-in id is treated as custom and still listed, so a
# user override is never silently dropped.
static func build_roster(builtin_ids: Array, custom_profiles: Dictionary, reader: Object = null) -> Array:
	var out: Array = []
	var b_ids: Array = builtin_ids.duplicate() if not builtin_ids.is_empty() else AiProfileCatalog.ids()
	b_ids.sort()
	for id in b_ids:
		var p: AiProfile = AiProfileCatalog.load_profile(str(id), reader)
		out.append(_row_for(p, SOURCE_BUILTIN))
	var c_ids: Array = custom_profiles.keys()
	c_ids.sort()
	for id in c_ids:
		var data: Variant = custom_profiles[id]
		var cp: AiProfile = AiProfile.from_dict(data) if data is Dictionary else AiProfile.default_profile()
		out.append(_row_for(cp, SOURCE_CUSTOM))
	return out


# The subset of a roster whose ids are in `selected_ids`. Preserves roster order
# (built-ins first, then custom, each id-sorted) so a seated line-up is stable.
static func selected_rows(roster: Array, selected_ids: Array) -> Array:
	var want: Dictionary = {}
	for sid in selected_ids:
		want[str(sid)] = true
	var out: Array = []
	for row in roster:
		if row is Dictionary and want.has(str((row as Dictionary).get("id", ""))):
			out.append(row)
	return out


# Toggle one id in a selection list, returning a NEW sorted, de-duplicated list
# (the caller's array is never mutated). Used by the tick-boxes in match setup.
static func toggle_selection(selected_ids: Array, id: String) -> Array:
	var clean: String = str(id).strip_edges()
	var set: Dictionary = {}
	for sid in selected_ids:
		var s: String = str(sid).strip_edges()
		if not s.is_empty():
			set[s] = true
	if clean.is_empty():
		return _sorted_keys(set)
	if set.has(clean):
		set.erase(clean)
	else:
		set[clean] = true
	return _sorted_keys(set)


# Resolve a selection into the AiProfile objects match setup will seat, in roster
# order. Built-ins are loaded via `reader`; custom ids come from `custom_profiles`.
# Unknown ids are skipped. Never returns null entries.
static func resolve_profiles(selected_ids: Array, custom_profiles: Dictionary, reader: Object = null) -> Array:
	var want: Array = []
	var seen: Dictionary = {}
	for sid in selected_ids:
		var s: String = str(sid).strip_edges()
		if not s.is_empty() and not seen.has(s):
			seen[s] = true
			want.append(s)
	want.sort()
	var out: Array = []
	# Custom overrides a built-in of the same id (the user's own wins).
	for id in want:
		if custom_profiles.has(id):
			var data: Variant = custom_profiles[id]
			out.append(AiProfile.from_dict(data) if data is Dictionary else AiProfile.default_profile())
		elif AiProfileCatalog.ids().has(id):
			out.append(AiProfileCatalog.load_profile(id, reader))
	return out


# True when a roster has at least one row (there is always >=1 built-in general).
static func has_any(roster: Array) -> bool:
	return not roster.is_empty()


# --- Helpers ----------------------------------------------------------------

# Build one roster row from an AiProfile + its source tag.
static func _row_for(profile: AiProfile, source: String) -> Dictionary:
	var summary: Dictionary = AiProfileSummaryUtil.summarize(profile)
	summary["source"] = source
	return summary


static func _sorted_keys(set: Dictionary) -> Array:
	var out: Array = set.keys()
	out.sort()
	return out
