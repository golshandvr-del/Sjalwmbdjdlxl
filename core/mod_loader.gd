# mod_loader.gd
# ----------------------------------------------------------------------------
# Project Nexus - Mod Loader (core component, Phase 3, step 3.3).
#
# The mod pipeline that fulfils the project's "moddable" promise. It scans the
# `mods/` directory, reads each mod's `mod.json` manifest, resolves load ORDER
# from declared dependencies (`load_after`), and merges each mod's data files
# into the base catalogs through the existing DataLoader. Because all content
# (units, buildings, tech, ...) is already data-driven, a mod is just a folder
# of JSON that OVERRIDES or ADDS entries -- no engine changes required.
#
# Manifest (`mods/<id>/mod.json`):
#   {
#     "id": "example_mod",            # unique mod id (English)
#     "name": "Example Mod",
#     "version": "0.1.0",
#     "author": "...",
#     "enabled": true,                # optional, default true
#     "load_after": ["other_mod"],    # optional ordering constraints
#     "provides": {                   # catalog_name -> [relative json paths]
#       "units": ["data/units/heavy_soldier.json"]
#     }
#   }
#
# Determinism + safety rules:
#   - Mods are loaded in a STABLE order: a deterministic topological sort of the
#     `load_after` graph, breaking ties by mod id. Two machines with the same
#     mod set therefore build identical catalogs -> still lockstep-safe.
#   - Later mods override earlier entries with the same id (last-writer-wins),
#     exactly like the DataLoader's base behaviour, so conflicts are predictable.
#   - A missing/broken manifest or data file is skipped with a warning rather
#     than crashing the whole load.
#
# The loader is a pure helper over the core's public surface (DataLoader); it is
# NOT a module and references no gameplay module.
#
# CODE LANGUAGE POLICY: English-only identifiers/comments.
# ----------------------------------------------------------------------------
class_name ModLoader
extends RefCounted

const DEFAULT_MODS_DIR: String = "res://mods"
const MANIFEST_FILE: String = "mod.json"


# Discover every mod under `mods_dir` and return their manifests as an Array of
# Dictionaries, each augmented with a "_dir" key (the mod's folder path). Mods
# whose manifest is missing/invalid are skipped. Order here is raw (directory
# order); call `resolve_load_order` to sort them.
static func discover_mods(data_loader: Object, mods_dir: String = DEFAULT_MODS_DIR) -> Array:
	var mods: Array = []
	var dir: DirAccess = DirAccess.open(mods_dir)
	if dir == null:
		push_warning("ModLoader: mods directory not found '%s'" % mods_dir)
		return mods
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		if dir.current_is_dir() and not name.begins_with("."):
			var mod_dir: String = mods_dir.path_join(name)
			var manifest_path: String = mod_dir.path_join(MANIFEST_FILE)
			var parsed: Variant = data_loader.load_json_file(manifest_path)
			if parsed is Dictionary:
				var manifest: Dictionary = (parsed as Dictionary).duplicate(true)
				manifest["_dir"] = mod_dir
				if str(manifest.get("id", "")) == "":
					push_warning("ModLoader: mod in '%s' has no id; skipping" % mod_dir)
				else:
					mods.append(manifest)
			else:
				push_warning("ModLoader: invalid manifest '%s'; skipping" % manifest_path)
		name = dir.get_next()
	dir.list_dir_end()
	return mods


# Deterministically order mods so every dependency in `load_after` loads first.
# Uses a stable topological sort (Kahn's algorithm) with ties broken by mod id.
# Cycles are broken deterministically (remaining nodes appended by sorted id)
# rather than aborting the whole load.
static func resolve_load_order(mods: Array) -> Array:
	# Index by id and only consider enabled mods.
	var by_id: Dictionary = {}
	for m in mods:
		if bool(m.get("enabled", true)):
			by_id[str(m["id"])] = m
	var ids: Array = by_id.keys()
	ids.sort()

	# Build dependency edges: an id depends on each present `load_after` entry.
	var remaining_deps: Dictionary = {}
	for id in ids:
		var deps: Array = []
		for dep in by_id[id].get("load_after", []):
			if by_id.has(str(dep)):  # ignore deps on absent/disabled mods
				deps.append(str(dep))
		remaining_deps[id] = deps

	var ordered: Array = []
	var placed: Dictionary = {}
	# Repeatedly place every id whose deps are all already placed, in id order.
	var progress: bool = true
	while progress and ordered.size() < ids.size():
		progress = false
		for id in ids:
			if placed.has(id):
				continue
			var ready: bool = true
			for dep in remaining_deps[id]:
				if not placed.has(dep):
					ready = false
					break
			if ready:
				ordered.append(by_id[id])
				placed[id] = true
				progress = true
	# Any leftovers (dependency cycle): append by sorted id so it stays stable.
	for id in ids:
		if not placed.has(id):
			ordered.append(by_id[id])
			placed[id] = true
	return ordered


# Apply one mod's `provides` map into the DataLoader catalogs. Each provided
# file must be a JSON object with an "id"; it overrides any existing entry with
# that id (last-writer-wins). Returns the number of entries merged.
static func apply_mod(data_loader: Object, manifest: Dictionary) -> int:
	var mod_dir: String = str(manifest.get("_dir", ""))
	var provides: Dictionary = manifest.get("provides", {})
	var merged: int = 0
	# Iterate catalogs in sorted name order for determinism.
	var catalog_names: Array = provides.keys()
	catalog_names.sort()
	for catalog_name in catalog_names:
		var entries: Dictionary = {}
		for rel_path in provides[catalog_name]:
			var full_path: String = mod_dir.path_join(str(rel_path))
			var parsed: Variant = data_loader.load_json_file(full_path)
			if parsed is Dictionary:
				var entry: Dictionary = parsed as Dictionary
				var entry_id: String = str(entry.get("id", ""))
				if entry_id == "":
					push_warning("ModLoader: provided file '%s' has no id; skipping" % full_path)
					continue
				entries[entry_id] = entry
				merged += 1
			else:
				push_warning("ModLoader: cannot load provided file '%s'" % full_path)
		if not entries.is_empty():
			data_loader.merge_into_catalog(str(catalog_name), entries)
	return merged


# Full pipeline: discover -> order -> apply. Returns an info Dictionary with the
# applied mod ids (in load order) and the total entries merged, which the
# bootstrap can log or surface in the UI.
static func load_all(data_loader: Object, mods_dir: String = DEFAULT_MODS_DIR) -> Dictionary:
	var mods: Array = discover_mods(data_loader, mods_dir)
	var ordered: Array = resolve_load_order(mods)
	var applied: Array = []
	var total: int = 0
	for manifest in ordered:
		total += apply_mod(data_loader, manifest)
		applied.append(str(manifest.get("id", "")))
	return { "loaded": applied, "entries_merged": total }


# --- Portable .nexpack packages (Phase C, step C.5) -------------------------
#
# Discover every `.nexpack` under the StorageService content root, read each
# pack's manifest, resolve the SAME deterministic load order as folder mods, and
# merge each pack's catalogs into the DataLoader. Packs are treated exactly like
# unpacked mods: a `.nexpack` and a `mods/<id>/` folder are interchangeable.
#
# When a `texture_service` is supplied, each loaded pack's textures are extracted
# once into `<content_root>/.cache/<id>/textures/` and that folder is registered
# as a texture root, so `visual.texture` paths inside a pack resolve normally.
#
# Returns { loaded: [ids in order], entries_merged: int }.
static func load_packs(data_loader: Object, storage: Object, texture_service: Object = null) -> Dictionary:
	var applied: Array = []
	var total: int = 0
	# Read every pack manifest first (each augmented with a "_pack" path).
	var manifests: Array = []
	var readers: Dictionary = {}  # mod id -> PackReader (kept open while applying)
	for pack_path in storage.list_packs():
		var pack_reader: PackReader = PackReader.new()
		if not pack_reader.open(str(pack_path)):
			continue
		var pack_manifest: Variant = pack_reader.read_manifest()
		if pack_manifest == null:
			pack_reader.close()
			continue
		var pack_id: String = str((pack_manifest as Dictionary).get("id", ""))
		manifests.append(pack_manifest)
		readers[pack_id] = pack_reader
	# Same deterministic ordering + enabled filtering as folder mods.
	var ordered: Array = resolve_load_order(manifests)
	for ordered_manifest in ordered:
		var mod_id: String = str(ordered_manifest.get("id", ""))
		var reader: PackReader = readers.get(mod_id, null)
		if reader == null:
			continue
		var catalogs: Dictionary = reader.read_catalogs()
		var catalog_names: Array = catalogs.keys()
		catalog_names.sort()
		for catalog_name in catalog_names:
			var entries: Dictionary = catalogs[catalog_name]
			data_loader.merge_into_catalog(str(catalog_name), entries)
			total += entries.size()
		if texture_service != null:
			_extract_pack_textures(reader, mod_id, storage, texture_service)
		applied.append(mod_id)
	# Close every reader now that catalogs + textures are materialised.
	for r in readers.values():
		r.close()
	return { "loaded": applied, "entries_merged": total }


# Extract a pack's `textures/` entries into a per-pack cache folder under the
# content root and register that folder as a (front-most) texture root so the
# pack's textures override/extend the base set. Idempotent across reloads.
static func _extract_pack_textures(reader: Object, mod_id: String, storage: Object, texture_service: Object) -> void:
	var cache_root: String = storage.resolve(".cache/" + mod_id)
	var tex_out: String = cache_root + "/" + PackFormat.TEXTURES_DIR
	DirAccess.make_dir_recursive_absolute(tex_out)
	var prefix: String = PackFormat.TEXTURES_DIR + "/"
	for entry_path in reader.list_entries():
		if str(entry_path).begins_with(prefix):
			var bytes: PackedByteArray = reader.read_bytes(str(entry_path))
			if bytes.is_empty():
				continue
			var out_path: String = cache_root + "/" + str(entry_path)
			var parent: String = out_path.get_base_dir()
			if not DirAccess.dir_exists_absolute(parent):
				DirAccess.make_dir_recursive_absolute(parent)
			var f: FileAccess = FileAccess.open(out_path, FileAccess.WRITE)
			if f != null:
				f.store_buffer(bytes)
				f.close()
	# The pack root holds `textures/<name>`, matching how visual.texture is
	# written ("textures/x.png"), so register the cache root itself.
	texture_service.add_root(cache_root)
