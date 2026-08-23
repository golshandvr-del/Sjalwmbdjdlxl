# safe_file_util.gd
# ----------------------------------------------------------------------------
# Project Nexus - Atomic file writes (crash-safe persistence).
#
# THE PROBLEM THIS SOLVES: FileAccess.open(path, WRITE) TRUNCATES the target
# file immediately. If the process dies mid-write (Android killing a
# backgrounded app, a crash, power loss), the file on disk is left EMPTY or
# HALF-WRITTEN -- and the previous good copy is already gone. For a game save,
# the settings file, an autosave draft or a mod pack this is silent data loss.
#
# THE FIX: the classic write-to-temp-then-rename pattern.
#   1. Write the full payload to "<path>.tmp" (a sibling, same filesystem).
#   2. Verify the write succeeded (open + store + close all OK).
#   3. Atomically rename the temp over the destination. A rename within one
#      filesystem either fully happens or does not happen at all, so `path`
#      always holds either the OLD complete file or the NEW complete file --
#      never a torn mixture.
# On any failure the temp file is removed and the destination is untouched.
#
# DESIGN RULES (project constitution):
#   - PURE STATIC utility: no Nexus, no SceneTree, no state. Headless-testable.
#   - Works for user:// and res:// style virtual paths as well as absolute OS
#     paths, because it uses the same FileAccess/DirAccess virtual-path API the
#     callers already use.
#   - COSMETIC to the simulation: file IO never touches the deterministic hash.
#
# CODE LANGUAGE POLICY: English-only identifiers/comments (ASCII).
# ----------------------------------------------------------------------------
class_name SafeFileUtil
extends RefCounted

# Suffix for the sibling temp file. Kept short + hidden-ish; a stale temp left
# behind by a crash is overwritten by the next successful save.
const TMP_SUFFIX: String = ".tmp"


# Atomically replace the file at `path` with `text` (UTF-8). Returns true only
# when the payload is fully on disk under `path`. On failure `path` keeps its
# previous content (if any) and the temp file is cleaned up.
static func write_text(path: String, text: String) -> bool:
	var tmp: String = path + TMP_SUFFIX
	var f: FileAccess = FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text)
	# flush() before close() so a buffered-IO failure surfaces here, not later.
	f.flush()
	var write_ok: bool = f.get_error() == OK
	f.close()
	if not write_ok:
		_remove_quiet(tmp)
		return false
	return _replace(tmp, path)


# Atomically replace the file at `path` with raw `bytes`. Same guarantees as
# write_text.
static func write_bytes(path: String, bytes: PackedByteArray) -> bool:
	var tmp: String = path + TMP_SUFFIX
	var f: FileAccess = FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_buffer(bytes)
	f.flush()
	var write_ok: bool = f.get_error() == OK
	f.close()
	if not write_ok:
		_remove_quiet(tmp)
		return false
	return _replace(tmp, path)


# The temp path a caller should target when it must stream a file itself (e.g.
# ZIPPacker writes incrementally). After streaming, call promote() to swap the
# temp over the destination atomically.
static func temp_path_for(path: String) -> String:
	return path + TMP_SUFFIX


# Promote a fully-written temp file (created at temp_path_for(path)) over the
# destination. Returns true when `path` now holds the new content.
static func promote(path: String) -> bool:
	return _replace(path + TMP_SUFFIX, path)


# Remove a stale temp file for `path` (e.g. after an aborted streamed write).
static func discard_temp(path: String) -> void:
	_remove_quiet(path + TMP_SUFFIX)


# --- internals ----------------------------------------------------------------

# Rename `tmp` over `dest`. DirAccess.rename_absolute is atomic on POSIX and
# handles the replace on all platforms Godot targets. If the rename fails the
# temp is removed so it cannot be mistaken for a good file later.
static func _replace(tmp: String, dest: String) -> bool:
	if not FileAccess.file_exists(tmp):
		return false
	if DirAccess.rename_absolute(tmp, dest) == OK:
		return true
	_remove_quiet(tmp)
	return false


static func _remove_quiet(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
