# mod_choice_util.gd
# ----------------------------------------------------------------------------
# Project Nexus - Pure helpers for the mod editor's "which mod do you want to
# edit?" chooser (Phase MC6, step 6.4, request 7). When the mod editor opens it
# must ask the author which existing mod to edit, or offer to start a brand-new
# one. This util owns only the deterministic LIST/CHOICE logic; the editor scene
# (mod_editor.gd) owns the widgets and the actual pack IO.
#
# Design (consistent with ActiveModUtil / CatalogListUtil):
#   - PURE + dependency-free: no Nexus autoload, no SceneTree, no file IO. It
#     takes the plain Array of .nexpack full paths that StorageService.list_packs
#     returns and turns it into a stable, id-sorted list of editable choices.
#   - DETERMINISTIC: choices are sorted by mod id so the dialog and any test are
#     stable across machines. This tooling never touches the simulation hash.
#   - FAIL-SAFE: blank/duplicate/dir-only paths are dropped; a choice index that
#     is out of range resolves to the "new mod" sentinel so the editor can never
#     open a path that does not exist.
#
# A "choice" row is { "id", "path" }: `id` is the pack file's base name (without
# the .nexpack extension) shown to the author, `path` is the full pack path the
# editor opens. The "new mod" option is NOT a row here -- the editor renders it
# as a separate button so it never collides with a real mod id.
#
# CODE LANGUAGE POLICY: English-only identifiers/comments (ASCII).
# ----------------------------------------------------------------------------
class_name ModChoiceUtil
extends RefCounted

# The .nexpack extension, mirrored from StorageService so this util stays pure
# (no dependency on the service just to strip the suffix).
const PACK_EXTENSION: String = "nexpack"


# Turn StorageService.list_packs() output (full .nexpack paths) into a stable,
# UI-ready Array of { "id", "path" } dictionaries. Blank paths, non-.nexpack
# paths, and duplicate ids are dropped; the result is sorted by id.
static func list_choices(pack_paths: Array) -> Array:
	var seen: Dictionary = {}
	var rows: Array = []
	for raw in pack_paths:
		var path: String = str(raw).strip_edges()
		if path == "":
			continue
		var id: String = mod_id_for(path)
		if id == "" or seen.has(id):
			continue
		seen[id] = true
		rows.append({ "id": id, "path": path })
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["id"]) < str(b["id"]))
	return rows


# The mod id for a pack path: its base file name with the .nexpack suffix
# removed. Returns "" for a blank path or a path with no file component.
static func mod_id_for(path: String) -> String:
	var file: String = str(path).strip_edges().get_file()
	if file == "":
		return ""
	var lower: String = file.to_lower()
	var suffix: String = "." + PACK_EXTENSION
	if lower.ends_with(suffix):
		file = file.substr(0, file.length() - suffix.length())
	return file


# Whether any editable mod exists on disk. When false the editor should skip the
# chooser entirely and just start a fresh project.
static func has_choices(pack_paths: Array) -> bool:
	return not list_choices(pack_paths).is_empty()


# Resolve a selected row index against the choice list. A valid index returns
# that row's { "id", "path" }; any out-of-range index (including the "new mod"
# option) returns the empty dictionary so the editor starts a new project.
static func resolve_choice(pack_paths: Array, index: int) -> Dictionary:
	var rows: Array = list_choices(pack_paths)
	if index < 0 or index >= rows.size():
		return {}
	return (rows[index] as Dictionary).duplicate(true)
