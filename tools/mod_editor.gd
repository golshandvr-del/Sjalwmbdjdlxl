# mod_editor.gd
# ----------------------------------------------------------------------------
# Project Nexus - Community Mod Editor / Validator (Phase 6, step 6.5).
#
# A small, zero-dependency, headless command-line tool that helps community
# modders create and verify mods for the data-driven pipeline that the
# ModLoader (core/mod_loader.gd) consumes. It never touches the running game or
# the simulation -- it only reads and writes files under mods/ -- so it is safe
# to run any time and stays deterministic.
#
# It supports two sub-commands:
#
#   1) validate [mods_dir]
#        Scan every mod under `mods/` (or the given dir), parse each mod.json
#        manifest, and report problems: missing/blank id, id not matching the
#        folder name, bad version, missing "provides" files on disk, dangling
#        "load_after" references, and non-object manifests. Exit code 0 when all
#        mods are valid, 1 when any problem is found. This is the same contract
#        the CODE_POLICY linter uses, so it can gate CI too.
#
#   2) scaffold <mod_id> [mods_dir]
#        Create mods/<mod_id>/ with a ready-to-edit mod.json manifest and a
#        sample unit JSON wired into "provides", so a modder has a working
#        starting point that the ModLoader will discover immediately. Refuses to
#        overwrite an existing mod. The mod_id must be a lowercase ASCII slug
#        (English-only, per docs/CODE_POLICY.md).
#
# Run it headless from the project root, for example:
#   godot --headless --path . --script res://tools/mod_editor.gd -- validate
#   godot --headless --path . --script res://tools/mod_editor.gd -- scaffold my_mod
#
# Anything after the lone "--" is passed to the tool as its own arguments.
#
# BUILD-STABILITY NOTE (MB8.3 / bug 23): This is a DEVELOPER-ONLY headless CLI
# tool. It intentionally writes into `res://mods` (the source tree) while
# authoring content on desktop, which is writable during development but is
# READ-ONLY in an exported/installed build (Android especially). It must NEVER
# be invoked at runtime inside a shipped build. The runtime, in-game authoring
# path is `ui/shared/mod_editor.gd`, which routes ALL user-content writes through
# StorageService to `user://content/` (the only writable location on every
# export target). Base/shipped content is read from `res://`; authored/imported
# content is written to and read from `user://`. Keep this separation to avoid
# the installed-build hang described in bug 23.
#
# CODE LANGUAGE POLICY: English-only identifiers/comments.
# ----------------------------------------------------------------------------
extends SceneTree

const DEFAULT_MODS_DIR: String = "res://mods"
const MANIFEST_FILE: String = "mod.json"

# Catalog keys the ModLoader understands inside a manifest's "provides" map.
const KNOWN_PROVIDES: Array = ["units", "buildings", "tech", "difficulty"]

# A valid mod id is a lowercase ASCII slug: letters, digits, and underscores,
# starting with a letter. This keeps mod folders English-only and filesystem-safe.
const ID_PATTERN: String = "^[a-z][a-z0-9_]*$"


func _init() -> void:
	print("==== Project Nexus :: Mod Editor ====")
	var args: PackedStringArray = _tool_args()
	if args.is_empty():
		_print_usage()
		quit(1)
		return
	var command: String = args[0]
	match command:
		"validate":
			var dir: String = args[1] if args.size() > 1 else DEFAULT_MODS_DIR
			quit(0 if _run_validate(dir) else 1)
		"scaffold":
			if args.size() < 2:
				printerr("scaffold requires a <mod_id> argument")
				_print_usage()
				quit(1)
				return
			var mods_dir: String = args[2] if args.size() > 2 else DEFAULT_MODS_DIR
			quit(0 if _run_scaffold(args[1], mods_dir) else 1)
		_:
			printerr("Unknown command: %s" % command)
			_print_usage()
			quit(1)


# --- validate ---------------------------------------------------------------

# Returns true when every mod is valid.
func _run_validate(mods_dir: String) -> bool:
	print("Validating mods under: %s" % mods_dir)
	var problems: Array = []
	var checked: int = 0
	var dir: DirAccess = DirAccess.open(mods_dir)
	if dir == null:
		print("  (no mods directory found -- nothing to validate)")
		print("Result: OK (0 mods)")
		return true
	var ids_seen: Dictionary = {}
	# Collect mod folders first, sorted, so output is deterministic.
	var folders: Array = []
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if dir.current_is_dir() and not entry.begins_with("."):
			folders.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	folders.sort()

	for folder in folders:
		checked += 1
		var mod_path: String = mods_dir.path_join(folder)
		problems.append_array(_validate_one(mod_path, folder, ids_seen))

	if problems.is_empty():
		print("Result: OK (%d mod(s) valid)" % checked)
		return true
	print("Result: %d problem(s) across %d mod(s):" % [problems.size(), checked])
	for p in problems:
		print("  - %s" % p)
	return false


# Validate a single mod folder; returns an array of human-readable problems.
func _validate_one(mod_path: String, folder: String, ids_seen: Dictionary) -> Array:
	var problems: Array = []
	var manifest_path: String = mod_path.path_join(MANIFEST_FILE)
	if not FileAccess.file_exists(manifest_path):
		problems.append("%s: missing %s" % [folder, MANIFEST_FILE])
		return problems
	var text: String = FileAccess.get_file_as_string(manifest_path)
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		problems.append("%s: %s is not a JSON object" % [folder, MANIFEST_FILE])
		return problems
	var manifest: Dictionary = parsed

	# id checks.
	var id: String = str(manifest.get("id", "")).strip_edges()
	if id.is_empty():
		problems.append("%s: manifest has a missing/blank 'id'" % folder)
	else:
		var re: RegEx = RegEx.new()
		re.compile(ID_PATTERN)
		if re.search(id) == null:
			problems.append("%s: id '%s' is not a lowercase ASCII slug" % [folder, id])
		if id != folder:
			problems.append("%s: id '%s' does not match its folder name" % [folder, id])
		if ids_seen.has(id):
			problems.append("%s: duplicate id '%s'" % [folder, id])
		ids_seen[id] = true

	# version is recommended.
	if str(manifest.get("version", "")).strip_edges().is_empty():
		problems.append("%s: manifest has no 'version'" % folder)

	# enabled must be a bool when present.
	if manifest.has("enabled") and not (manifest["enabled"] is bool):
		problems.append("%s: 'enabled' must be true/false" % folder)

	# load_after must be an array of strings when present.
	if manifest.has("load_after") and not (manifest["load_after"] is Array):
		problems.append("%s: 'load_after' must be an array" % folder)

	# provides: every listed file must exist on disk and use a known catalog key.
	var provides: Variant = manifest.get("provides", {})
	if not (provides is Dictionary):
		problems.append("%s: 'provides' must be an object" % folder)
	else:
		var keys: Array = (provides as Dictionary).keys()
		keys.sort()
		for key in keys:
			if not KNOWN_PROVIDES.has(key):
				problems.append("%s: 'provides' has unknown catalog '%s'" % [folder, key])
			var files: Variant = (provides as Dictionary)[key]
			if not (files is Array):
				problems.append("%s: provides['%s'] must be an array" % [folder, key])
				continue
			for rel in files:
				var full: String = mod_path.path_join(str(rel))
				if not FileAccess.file_exists(full):
					problems.append("%s: provides file missing on disk: %s" % [folder, str(rel)])
	return problems


# --- scaffold ---------------------------------------------------------------

# Returns true on success.
func _run_scaffold(mod_id: String, mods_dir: String) -> bool:
	var re: RegEx = RegEx.new()
	re.compile(ID_PATTERN)
	if re.search(mod_id) == null:
		printerr("Invalid mod id '%s' -- use a lowercase ASCII slug (e.g. my_mod)" % mod_id)
		return false
	var mod_path: String = mods_dir.path_join(mod_id)
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(mod_path)) or _res_dir_exists(mod_path):
		printerr("Mod '%s' already exists at %s -- refusing to overwrite" % [mod_id, mod_path])
		return false

	var unit_rel: String = "data/units/%s_unit.json" % mod_id
	var made_units: Error = DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(mod_path.path_join("data/units")))
	if made_units != OK:
		printerr("Could not create directories under %s" % mod_path)
		return false

	# Sample unit definition.
	var unit: Dictionary = {
		"id": "%s_unit" % mod_id,
		"display_name_key": "unit.%s_unit.name" % mod_id,
		"category": "infantry",
		"stats": {
			"health": 120,
			"move_speed": 2,
			"attack_damage": 12,
			"attack_range": 1,
			"vision_range": 5,
		},
		"cost": { "resource_basic": 60 },
		"build_time_ticks": 70,
	}
	if not _write_json(mod_path.path_join(unit_rel), unit):
		return false

	# Manifest wiring the sample unit into the units catalog.
	var manifest: Dictionary = {
		"id": mod_id,
		"name": mod_id,
		"version": "0.1.0",
		"author": "unknown",
		"description": "A new mod scaffolded by tools/mod_editor.gd.",
		"enabled": true,
		"load_after": [],
		"provides": { "units": [unit_rel] },
	}
	if not _write_json(mod_path.path_join(MANIFEST_FILE), manifest):
		return false

	print("Scaffolded mod '%s' at %s" % [mod_id, mod_path])
	print("  - %s" % MANIFEST_FILE)
	print("  - %s" % unit_rel)
	print("Edit the JSON, then run 'validate' to check it.")
	return true


# --- helpers ----------------------------------------------------------------

func _write_json(res_path: String, data: Dictionary) -> bool:
	var file: FileAccess = FileAccess.open(res_path, FileAccess.WRITE)
	if file == null:
		printerr("Could not write %s" % res_path)
		return false
	file.store_string(JSON.stringify(data, "  "))
	file.store_string("\n")
	file.close()
	return true


func _res_dir_exists(res_path: String) -> bool:
	return DirAccess.open(res_path) != null


# Extract the tool's own arguments: everything after a lone "--", or, if none is
# present, every non-engine argument we recognise.
func _tool_args() -> PackedStringArray:
	var raw: PackedStringArray = OS.get_cmdline_user_args()
	if not raw.is_empty():
		return raw
	# Fallback: scan the full command line for our known sub-commands.
	var out: PackedStringArray = PackedStringArray()
	var collecting: bool = false
	for a in OS.get_cmdline_args():
		if collecting:
			out.append(a)
		elif a == "validate" or a == "scaffold":
			collecting = true
			out.append(a)
	return out


func _print_usage() -> void:
	print("Usage (run after a lone '--'):")
	print("  validate [mods_dir]        Validate every mod manifest under mods/")
	print("  scaffold <mod_id> [dir]    Create a new mod skeleton under mods/")
