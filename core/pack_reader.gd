# pack_reader.gd
# ----------------------------------------------------------------------------
# Project Nexus - .nexpack Package Reader (Phase C, step C.4).
#
# Opens a portable `.nexpack` ZIP with Godot's built-in `ZIPReader` and exposes
# its contents WITHOUT extracting the whole archive to disk: the manifest, the
# provided data JSON, and the textures are read on demand straight from the ZIP.
# This is what lets a player drop a single file into their content folder and
# have the game load it directly (fast, no scratch space, works on Android).
#
# Lifecycle:
#   var reader := PackReader.new()
#   if reader.open("user://content/my_mod.nexpack"):
#       var manifest := reader.read_manifest()
#       var unit := reader.read_json("data/units/x.json")
#       var png  := reader.read_bytes("textures/x.png")
#       reader.close()
#
# Design rules:
#   - SAFE: a missing file, a corrupt ZIP, or a bad manifest never crashes; the
#     reader reports failure (open() -> false, read_* -> null/empty) and the
#     caller skips the pack, exactly like ModLoader skips a broken mod folder.
#   - PURE INFRASTRUCTURE: nothing here touches WorldState / the sim hash.
#   - The entry layout it understands is defined ONCE in PackFormat (C.3), so the
#     reader and writer can never disagree about where things live.
#
# CODE LANGUAGE POLICY: English-only identifiers/comments.
# ----------------------------------------------------------------------------
class_name PackReader
extends RefCounted

var _zip: ZIPReader = null
var _path: String = ""


# Open a `.nexpack` for reading. Returns true on success. Safe to call open() on
# a fresh reader; call close() when done (or just drop the reference).
func open(path: String) -> bool:
	close()
	if not FileAccess.file_exists(path):
		push_warning("PackReader: pack not found '%s'" % path)
		return false
	var zip: ZIPReader = ZIPReader.new()
	var err: int = zip.open(path)
	if err != OK:
		push_warning("PackReader: cannot open pack '%s' (err %d)" % [path, err])
		return false
	_zip = zip
	_path = path
	return true


func close() -> void:
	if _zip != null:
		_zip.close()
		_zip = null
	_path = ""


func is_open() -> bool:
	return _zip != null


# Every entry path inside the pack (forward-slash, sorted for determinism).
func list_entries() -> Array:
	if _zip == null:
		return []
	var names: Array = Array(_zip.get_files())
	names.sort()
	return names


# Whether an entry exists in the pack.
func has_entry(entry_path: String) -> bool:
	if _zip == null:
		return false
	return _zip.file_exists(entry_path)


# Read a raw entry as bytes. Returns an empty PackedByteArray if absent.
func read_bytes(entry_path: String) -> PackedByteArray:
	if _zip == null or not _zip.file_exists(entry_path):
		return PackedByteArray()
	return _zip.read_file(entry_path)


# Read an entry as UTF-8 text. Returns "" if absent.
func read_text(entry_path: String) -> String:
	var bytes: PackedByteArray = read_bytes(entry_path)
	if bytes.is_empty():
		return ""
	return bytes.get_string_from_utf8()


# Read + parse an entry as JSON. Returns null on missing/invalid.
func read_json(entry_path: String) -> Variant:
	var text: String = read_text(entry_path)
	if text == "":
		return null
	return JSON.parse_string(text)


# Read + validate the pack manifest (`manifest.json`). Returns the manifest
# Dictionary augmented with a "_pack" key (this pack's path, used as a texture
# root by the loader), or null if it is missing/invalid.
func read_manifest() -> Variant:
	var parsed: Variant = read_json(PackFormat.MANIFEST_NAME)
	if not PackFormat.is_manifest_valid(parsed):
		push_warning("PackReader: invalid manifest in '%s'" % _path)
		return null
	var manifest: Dictionary = (parsed as Dictionary).duplicate(true)
	manifest["_pack"] = _path
	return manifest


# Load every data file the manifest `provides`, grouped by catalog name:
#   { "buildings": { "<id>": {entry...} }, "units": {...} }
# Entries without an "id" are skipped with a warning. This is the shape the
# DataLoader.merge_into_catalog() consumes, so the loader (C.5) can apply a pack
# the same way it applies an unpacked mod.
func read_catalogs() -> Dictionary:
	var out: Dictionary = {}
	var manifest: Variant = read_manifest()
	if manifest == null:
		return out
	var provides: Variant = (manifest as Dictionary).get("provides", {})
	if not (provides is Dictionary):
		return out
	var catalog_names: Array = (provides as Dictionary).keys()
	catalog_names.sort()
	for catalog_name in catalog_names:
		var paths: Variant = (provides as Dictionary)[catalog_name]
		if not (paths is Array):
			continue
		var entries: Dictionary = {}
		for rel_path in (paths as Array):
			var parsed: Variant = read_json(str(rel_path))
			if parsed is Dictionary:
				var entry_id: String = str((parsed as Dictionary).get("id", ""))
				if entry_id == "":
					push_warning("PackReader: entry without id at '%s'" % str(rel_path))
					continue
				entries[entry_id] = parsed
			else:
				push_warning("PackReader: cannot read provided '%s'" % str(rel_path))
		if not entries.is_empty():
			out[str(catalog_name)] = entries
	return out
