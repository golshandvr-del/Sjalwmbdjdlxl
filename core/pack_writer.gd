# pack_writer.gd
# ----------------------------------------------------------------------------
# Project Nexus - .nexpack Package Writer (Phase C, step C.6).
#
# Serialises a mod / custom game into a single portable `.nexpack` ZIP, using
# Godot's built-in `ZIPPacker`. This is the SAVE ENGINE that the graphical Mod
# Editor (Phase D) will call: the editor holds the manifest + data + textures in
# memory (or on disk under a project folder) and asks this writer to bundle them.
#
# Two complementary entry points:
#   - write_from_dir():  pack an existing unpacked mod folder (e.g. `mods/<id>/`)
#                        into a `.nexpack`. Lets us turn every shipped mod into a
#                        portable pack and round-trip it back (proven by C.7).
#   - write_from_data(): pack an in-memory manifest + {entry path -> bytes/text}
#                        map. This is what the Mod Editor uses, since it builds
#                        content live and never needs a scratch folder.
#
# Determinism + safety:
#   - Entries are written in a STABLE sorted order so the same input always
#     produces the same archive layout (friendly to diffing / caching).
#   - The manifest is validated through PackFormat before anything is written;
#     an invalid manifest is refused (returns false) rather than producing a
#     broken pack.
#   - PURE INFRASTRUCTURE: never touches WorldState / the simulation hash.
#
# CODE LANGUAGE POLICY: English-only identifiers/comments.
# ----------------------------------------------------------------------------
class_name PackWriter
extends RefCounted


# Pack an unpacked mod folder into `out_path` (.nexpack). The folder must contain
# a `mod.json`; it is rewritten into the ZIP as `manifest.json` (the pack name)
# and every file it `provides`, plus any `textures/` it ships, is included.
# Returns true on success.
static func write_from_dir(mod_dir: String, out_path: String) -> bool:
	var manifest_path: String = mod_dir.path_join("mod.json")
	var parsed: Variant = _read_json(manifest_path)
	if not PackFormat.is_manifest_valid(parsed):
		push_error("PackWriter: invalid/missing manifest in '%s'" % mod_dir)
		return false
	var manifest: Dictionary = parsed as Dictionary

	# Gather entries: manifest + every provided data file + every texture.
	var entries: Dictionary = {}
	entries[PackFormat.MANIFEST_NAME] = JSON.stringify(manifest, "\t")
	for rel_path in PackFormat.provided_data_paths(manifest):
		var full: String = mod_dir.path_join(rel_path)
		var text: String = _read_text(full)
		if text != "":
			entries[rel_path] = text
		else:
			push_warning("PackWriter: provided file missing/empty '%s'" % full)
	# Include the textures directory verbatim (binary-safe).
	var tex_dir: String = mod_dir.path_join(PackFormat.TEXTURES_DIR)
	for rel_tex in _list_files_recursive(tex_dir, PackFormat.TEXTURES_DIR):
		entries[rel_tex] = _read_bytes(mod_dir.path_join(rel_tex))

	return write_entries(out_path, entries)


# Pack an in-memory manifest + content map into `out_path`. `files` maps a ZIP
# entry path (e.g. "data/units/x.json" or "textures/y.png") to either a String
# (written as UTF-8) or a PackedByteArray (written verbatim). The manifest is
# added automatically as `manifest.json`; do NOT include it in `files`.
# Returns true on success.
static func write_from_data(manifest: Variant, files: Dictionary, out_path: String) -> bool:
	if not PackFormat.is_manifest_valid(manifest):
		push_error("PackWriter: refusing to write an invalid manifest")
		return false
	var entries: Dictionary = {}
	entries[PackFormat.MANIFEST_NAME] = JSON.stringify(manifest as Dictionary, "\t")
	for entry_path in files.keys():
		if str(entry_path) == PackFormat.MANIFEST_NAME:
			continue  # manifest is owned by us
		entries[str(entry_path)] = files[entry_path]
	return write_entries(out_path, entries)


# Low-level: write a map of {zip entry path -> String|PackedByteArray} to a ZIP
# at `out_path`. Entries are sorted for a deterministic archive. Returns true on
# success. Public so tests (and future tools) can drive it directly.
static func write_entries(out_path: String, entries: Dictionary) -> bool:
	_ensure_parent_dir(out_path)
	var packer: ZIPPacker = ZIPPacker.new()
	var err: int = packer.open(out_path)
	if err != OK:
		push_error("PackWriter: cannot open '%s' for writing (err %d)" % [out_path, err])
		return false
	var paths: Array = entries.keys()
	paths.sort()
	for entry_path in paths:
		packer.start_file(str(entry_path))
		var value: Variant = entries[entry_path]
		var bytes: PackedByteArray
		if value is PackedByteArray:
			bytes = value as PackedByteArray
		else:
			bytes = str(value).to_utf8_buffer()
		packer.write_file(bytes)
		packer.close_file()
	packer.close()
	return FileAccess.file_exists(out_path)


# --- Internals --------------------------------------------------------------

static func _read_json(path: String) -> Variant:
	var text: String = _read_text(path)
	if text == "":
		return null
	return JSON.parse_string(text)


static func _read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text: String = file.get_as_text()
	file.close()
	return text


static func _read_bytes(path: String) -> PackedByteArray:
	if not FileAccess.file_exists(path):
		return PackedByteArray()
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return PackedByteArray()
	var bytes: PackedByteArray = file.get_buffer(file.get_length())
	file.close()
	return bytes


# List every file under `dir`, returning paths PREFIXED with `prefix` and using
# forward slashes, sorted for determinism. Returns [] when the dir is absent.
static func _list_files_recursive(dir_path: String, prefix: String) -> Array:
	var out: Array = []
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		if not name.begins_with("."):
			if dir.current_is_dir():
				out.append_array(_list_files_recursive(dir_path.path_join(name), prefix + "/" + name))
			else:
				out.append(prefix + "/" + name)
		name = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out


static func _ensure_parent_dir(path: String) -> void:
	var parent: String = path.get_base_dir()
	if parent != "" and not DirAccess.dir_exists_absolute(parent):
		DirAccess.make_dir_recursive_absolute(parent)
