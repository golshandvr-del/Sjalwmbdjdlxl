# editor_defaults_util.gd
# ----------------------------------------------------------------------------
# Project Nexus - Editor "Defaults" tab logic (Phase MC8, step 8.3, request 9).
#
# Pure, dependency-free helper for the Defaults screen where the player picks a
# default MAP / MOD / GUI. Discovery (scanning disk) and persistence (GameSettings)
# live in the thin editor_defaults.gd screen; ALL selection/validation LOGIC is
# here so it can be unit-tested headlessly with plain dictionaries -- no
# SceneTree, no autoload, no file IO.
#
# A "choice list" is an Array of { "id": String, "name": String } rows, already
# sorted by id for a stable, deterministic display order. `resolve_default`
# guarantees the stored default id always refers to something that still exists:
# a stale id (its map/mod/gui was deleted) collapses to "" (no default) instead
# of dangling.
#
# This screen only edits a CONTENT-SELECTION preference; nothing here touches
# WorldState gameplay or the deterministic simulation hash.
#
# CODE LANGUAGE POLICY: English-only identifiers/comments (ASCII).
# ----------------------------------------------------------------------------
class_name EditorDefaultsUtil
extends RefCounted

# The three default categories.
const KIND_MAP: String = "map"
const KIND_MOD: String = "mod"
const KIND_GUI: String = "gui"


# Normalise a raw discovery Array (each entry either a String id or a Dictionary
# carrying "id" and an optional display "name"/"name_key") into a stable, sorted
# choice list of { id, name } rows. Blank ids are dropped; duplicate ids collapse
# to the first seen. Deterministic (sorted by id).
static func build_choices(discovered: Array) -> Array:
	var seen: Dictionary = {}
	var rows: Array = []
	for raw in discovered:
		var id: String = ""
		var name: String = ""
		if raw is String:
			id = (raw as String).strip_edges()
			name = id
		elif raw is Dictionary:
			var d: Dictionary = raw
			id = str(d.get("id", "")).strip_edges()
			name = str(d.get("name", d.get("name_key", id))).strip_edges()
			if name == "":
				name = id
		if id == "" or seen.has(id):
			continue
		seen[id] = true
		rows.append({ "id": id, "name": name })
	rows.sort_custom(func(a, b): return str(a["id"]) < str(b["id"]))
	return rows


# True when `id` is present in a choice list produced by build_choices.
static func has_choice(choices: Array, id: String) -> bool:
	for row in choices:
		if str((row as Dictionary).get("id", "")) == id:
			return true
	return false


# Resolve the persisted default id against the current choice list: keep it when
# it still exists, otherwise collapse to "" (no default). "" is always valid
# (means "use the built-in default").
static func resolve_default(stored_id: String, choices: Array) -> String:
	var id: String = stored_id.strip_edges()
	if id == "":
		return ""
	if has_choice(choices, id):
		return id
	return ""


# The display name for a chosen id, or a caller-supplied fallback (e.g. the
# localized "(none)") when the id is blank / not found.
static func display_name(choices: Array, id: String, none_text: String) -> String:
	if id.strip_edges() == "":
		return none_text
	for row in choices:
		var d: Dictionary = row
		if str(d.get("id", "")) == id:
			return str(d.get("name", id))
	return none_text
