# data_loader.gd
# ----------------------------------------------------------------------------
# Project Nexus - Data Loader (core component).
#
# Loads all game content from external data files (JSON). This is the key to
# the Data-Driven principle and to moddability: units, buildings, tech, and
# difficulty presets are defined in data, NOT hardcoded.
#
# In Phase 0 this is intentionally minimal: load a JSON file and load every
# JSON file in a directory into an id-keyed catalog. Mod overriding is
# expanded in Phase 5.
# ----------------------------------------------------------------------------
class_name DataLoader
extends RefCounted

# Loaded catalogs: catalog_name (String) -> { entry_id: entry_dict }.
var _catalogs: Dictionary = {}


# Load and parse a single JSON file. Returns the parsed Variant, or null.
func load_json_file(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		push_error("DataLoader: file not found '%s'" % path)
		return null
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("DataLoader: cannot open '%s'" % path)
		return null
	var text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null:
		push_error("DataLoader: failed to parse JSON in '%s'" % path)
	return parsed


# Load every *.json file in `dir_path` into a catalog named `catalog_name`.
# Each file must contain an object with an "id" field (English string).
# Returns the number of entries loaded.
func load_catalog(catalog_name: String, dir_path: String) -> int:
	var catalog: Dictionary = _catalogs.get(catalog_name, {})
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		push_warning("DataLoader: directory not found '%s'" % dir_path)
		_catalogs[catalog_name] = catalog
		return 0
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			var full_path: String = dir_path.path_join(file_name)
			var parsed: Variant = load_json_file(full_path)
			if parsed is Dictionary:
				var entry: Dictionary = parsed as Dictionary
				var entry_id: String = str(entry.get("id", ""))
				if entry_id == "":
					push_warning("DataLoader: entry without 'id' in '%s'" % full_path)
				else:
					# Later files override earlier ones (mod support hook).
					catalog[entry_id] = entry
		file_name = dir.get_next()
	dir.list_dir_end()
	_catalogs[catalog_name] = catalog
	return catalog.size()


# Get a whole catalog (id -> entry).
func get_catalog(catalog_name: String) -> Dictionary:
	return _catalogs.get(catalog_name, {})


# Get a single entry by catalog + id, or null if missing.
func get_entry(catalog_name: String, entry_id: String) -> Variant:
	var catalog: Dictionary = _catalogs.get(catalog_name, {})
	return catalog.get(entry_id, null)


# Merge/override entries into a catalog (used when mods load on top of base).
func merge_into_catalog(catalog_name: String, entries: Dictionary) -> void:
	var catalog: Dictionary = _catalogs.get(catalog_name, {})
	for entry_id in entries.keys():
		catalog[entry_id] = entries[entry_id]
	_catalogs[catalog_name] = catalog


func clear() -> void:
	_catalogs.clear()
