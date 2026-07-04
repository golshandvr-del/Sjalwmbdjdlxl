# storage_service.gd
# ----------------------------------------------------------------------------
# Project Nexus - Storage Service (Phase C, step C.1).
#
# A small, self-contained service that owns the ONE question every later
# content system (mods, .nexpack packages, the Mod Editor in Phase D) needs an
# answer to: "where on disk does installed/authored content live?".
#
# Why this exists:
#   - Phases A/B proved the data-driven + cosmetic-visual layers. Phase C builds
#     the portable-content plumbing on top of them. Before a PackReader can open
#     a `.nexpack` or a PackWriter can save one, both need a single, agreed,
#     *configurable* content root that works identically on desktop and Android.
#   - Godot's `user://` is the only writable location guaranteed on every export
#     platform (it maps to the app's private data dir on Android, AppData on
#     Windows, ~/.local/share on Linux, etc.), so the DEFAULT content root is
#     `user://content/`. The player may override it (e.g. an SD-card path) and
#     the override is persisted by GameSettings (step C.2).
#
# Design rules (consistent with the rest of the project):
#   - PURE INFRASTRUCTURE: nothing here ever touches the simulation/WorldState
#     or the deterministic hash. A storage path is not gameplay.
#   - SAFE: every path is normalised and the content root is created on demand;
#     a bad/empty configured path falls back to the documented default instead
#     of crashing. Listing a missing directory returns an empty array.
#   - HEADLESS-TESTABLE: the root can be injected, so tests can point it at a
#     throwaway `user://test_content_*` directory with no autoload involved.
#   - English-only identifiers/comments (CODE_POLICY).
# ----------------------------------------------------------------------------
class_name StorageService
extends RefCounted

# The platform-portable default content root. `user://` is writable on every
# export target; `content/` keeps installed packages out of the save namespace.
const DEFAULT_CONTENT_ROOT: String = "user://content"

# Canonical extension for a portable Project Nexus content package (step C.3).
const PACK_EXTENSION: String = "nexpack"

# The active content root (always normalised: no trailing slash).
var _content_root: String = DEFAULT_CONTENT_ROOT


# Construct with an explicit root (tests) or fall back to the default. An empty
# or whitespace-only root is rejected in favour of the documented default so the
# service can never be put into an unusable state.
func _init(content_root: String = DEFAULT_CONTENT_ROOT) -> void:
	set_content_root(content_root)


# Set (and normalise) the content root. An empty/whitespace path resets to the
# default. Returns the effective root actually applied.
func set_content_root(path: String) -> String:
	var clean: String = path.strip_edges()
	if clean.is_empty():
		clean = DEFAULT_CONTENT_ROOT
	_content_root = _normalise(clean)
	return _content_root


# The current content root (no trailing slash).
func get_content_root() -> String:
	return _content_root


# Ensure the content root directory exists, creating it (recursively) if needed.
# Returns true when the directory exists afterwards.
func ensure_content_root() -> bool:
	return _ensure_dir(_content_root)


# Resolve a path INSIDE the content root (e.g. a pack file name) to a full path.
func resolve(relative: String) -> String:
	var rel: String = relative.strip_edges().trim_prefix("/")
	if rel.is_empty():
		return _content_root
	return _content_root + "/" + rel


# Whether the given pack name/path exists under the content root. A bare name
# (no extension) is resolved with the canonical `.nexpack` extension.
func has_pack(name_or_path: String) -> bool:
	return FileAccess.file_exists(resolve_pack(name_or_path))


# Resolve a pack name to a full path, appending the canonical extension when the
# caller passed a bare id (e.g. "my_mod" -> "<root>/my_mod.nexpack").
func resolve_pack(name_or_path: String) -> String:
	var rel: String = name_or_path.strip_edges()
	if not rel.to_lower().ends_with("." + PACK_EXTENSION):
		rel += "." + PACK_EXTENSION
	return resolve(rel)


# List every `.nexpack` file in the content root, returned as full paths sorted
# by file name for determinism. A missing root yields an empty array (not an
# error: a fresh install simply has no content yet).
func list_packs() -> Array:
	var packs: Array = []
	var dir: DirAccess = DirAccess.open(_content_root)
	if dir == null:
		return packs
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.to_lower().ends_with("." + PACK_EXTENSION):
			packs.append(_content_root + "/" + file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	packs.sort()
	return packs


# --- Internals --------------------------------------------------------------

# Strip a single trailing slash so joins are predictable. Leaves the `user://`
# or `res://` scheme prefix intact.
func _normalise(path: String) -> String:
	var p: String = path
	while p.length() > 1 and p.ends_with("/") and not p.ends_with("://"):
		p = p.substr(0, p.length() - 1)
	return p


# Create a directory (recursively) if it does not already exist. Handles both
# `user://`-rooted absolute paths and relative ones. Returns true if it exists.
func _ensure_dir(path: String) -> bool:
	if DirAccess.dir_exists_absolute(path):
		return true
	var err: int = DirAccess.make_dir_recursive_absolute(path)
	if err != OK:
		push_error("StorageService: cannot create content root '%s' (err %d)" % [path, err])
		return DirAccess.dir_exists_absolute(path)
	return true
