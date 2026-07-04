# save_manager.gd
# ----------------------------------------------------------------------------
# Project Nexus - Save Manager (core component, Phase P4 / R3+R4).
#
# A thin, UI-facing layer on top of SaveSystem. SaveSystem knows HOW to
# serialize/restore a single game to/from one JSON file; SaveManager knows the
# SAVE *SLOTS*: it owns the on-disk save directory, enumerates existing saves
# with human-readable metadata (name + timestamp), and handles the portable
# export/import of a save file so a match can be shared between devices (R4).
#
# It has no gameplay knowledge and never touches WorldState directly; every
# actual save/load goes through the SaveSystem it wraps. This keeps the golden
# rule intact: tooling/UI produces or consumes data, the core owns the truth.
#
# On-disk layout (user:// is per-user, cross-platform, writable on Android):
#   user://saves/<slot_id>.nexsave      -- the JSON snapshot (SaveSystem format)
# Each snapshot additionally carries a small "meta" block (name + unix time) so
# the save-list UI can show it without loading the whole match.
#
# CODE LANGUAGE POLICY: English-only identifiers/comments.
# ----------------------------------------------------------------------------
class_name SaveManager
extends RefCounted

const SAVES_DIR: String = "user://saves"
const SAVE_EXT: String = "nexsave"

# The SaveSystem this manager drives (created lazily against a Nexus).
var _save_system: SaveSystem = null
var _nexus: Object = null


func setup(nexus: Object) -> void:
	_nexus = nexus
	_save_system = SaveSystem.new()
	_save_system.setup(nexus)


# Ensure the saves directory exists; returns true if it is ready.
func ensure_dir() -> bool:
	if DirAccess.dir_exists_absolute(SAVES_DIR):
		return true
	return DirAccess.make_dir_recursive_absolute(SAVES_DIR) == OK


# Build the absolute path for a slot id.
func _path_for(slot_id: String) -> String:
	return "%s/%s.%s" % [SAVES_DIR, _sanitise(slot_id), SAVE_EXT]


# Save the current game under a display name. A slot id is derived from the name
# (sanitised + timestamped) so re-saving the same name never clobbers by accident
# unless `slot_id` is passed explicitly (overwrite an existing slot). Returns the
# slot id on success, or "" on failure.
func save_game(display_name: String, slot_id: String = "") -> String:
	if _save_system == null:
		push_error("SaveManager: not set up")
		return ""
	if not ensure_dir():
		push_error("SaveManager: cannot create saves dir")
		return ""
	if slot_id == "":
		slot_id = "%s_%d" % [_sanitise(display_name), int(Time.get_unix_time_from_system())]
	# Build the snapshot and stamp a UI-facing meta block onto it.
	var snapshot: Dictionary = _save_system.build_snapshot()
	if snapshot.is_empty():
		return ""
	snapshot["meta"] = {
		"name": display_name,
		"saved_at": int(Time.get_unix_time_from_system()),
		"tick": int(_nexus.world_state.current_tick),
	}
	var path: String = _path_for(slot_id)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("SaveManager: cannot write '%s'" % path)
		return ""
	file.store_string(JSON.stringify(snapshot, "\t"))
	file.close()
	return slot_id


# Load a save slot into the live game. Returns true on success.
func load_game(slot_id: String) -> bool:
	if _save_system == null:
		return false
	return _save_system.load_from_file(_path_for(slot_id))


# Delete a save slot. Returns true if the file is gone afterwards.
func delete_game(slot_id: String) -> bool:
	var path: String = _path_for(slot_id)
	if not FileAccess.file_exists(path):
		return true
	return DirAccess.remove_absolute(path) == OK


# Enumerate all saves as an Array of Dictionaries sorted newest-first:
#   { "slot_id": String, "name": String, "saved_at": int, "tick": int, "path": String }
func list_saves() -> Array:
	var out: Array = []
	if not DirAccess.dir_exists_absolute(SAVES_DIR):
		return out
	var dir: DirAccess = DirAccess.open(SAVES_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.get_extension() == SAVE_EXT:
			var slot_id: String = name.get_basename()
			var meta: Dictionary = _read_meta(_path_for(slot_id))
			out.append({
				"slot_id": slot_id,
				"name": str(meta.get("name", slot_id)),
				"saved_at": int(meta.get("saved_at", 0)),
				"tick": int(meta.get("tick", 0)),
				"path": _path_for(slot_id),
			})
		name = dir.get_next()
	dir.list_dir_end()
	# Newest first.
	out.sort_custom(func(a, b): return int(a["saved_at"]) > int(b["saved_at"]))
	return out


# Read only the meta block of a save (cheap: parse then discard the rest).
func _read_meta(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return {}
	return (parsed as Dictionary).get("meta", {})


# --- R4: portable export / import -------------------------------------------

# Export a save slot to an arbitrary path (e.g. a shared folder / SD card) so it
# can be moved to another device. Returns true on success.
func export_save(slot_id: String, dest_path: String) -> bool:
	var src: String = _path_for(slot_id)
	if not FileAccess.file_exists(src):
		push_error("SaveManager: nothing to export at '%s'" % src)
		return false
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(src)
	var out: FileAccess = FileAccess.open(dest_path, FileAccess.WRITE)
	if out == null:
		push_error("SaveManager: cannot export to '%s'" % dest_path)
		return false
	out.store_buffer(bytes)
	out.close()
	return true


# Import a save file from an arbitrary path into the saves directory. Returns the
# new slot id on success, or "" on failure. The imported file is validated as a
# well-formed snapshot before being accepted (validate-before-save rule).
func import_save(src_path: String) -> String:
	if not FileAccess.file_exists(src_path):
		push_error("SaveManager: import source not found '%s'" % src_path)
		return ""
	var text: String = FileAccess.get_file_as_string(src_path)
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary) or not (parsed as Dictionary).has("world_state"):
		push_error("SaveManager: '%s' is not a valid Nexus save" % src_path)
		return ""
	if not ensure_dir():
		return ""
	var snapshot: Dictionary = parsed as Dictionary
	var meta: Dictionary = snapshot.get("meta", {})
	var display_name: String = str(meta.get("name", src_path.get_file().get_basename()))
	var slot_id: String = "%s_%d" % [_sanitise(display_name), int(Time.get_unix_time_from_system())]
	var out: FileAccess = FileAccess.open(_path_for(slot_id), FileAccess.WRITE)
	if out == null:
		return ""
	out.store_string(text)
	out.close()
	return slot_id


# Sanitise a display name into a filesystem-safe slug.
func _sanitise(name: String) -> String:
	var s: String = name.strip_edges().to_lower()
	var result: String = ""
	for c in s:
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
			result += c
		elif c == " " or c == "-" or c == "_":
			result += "_"
	if result == "":
		result = "save"
	return result
