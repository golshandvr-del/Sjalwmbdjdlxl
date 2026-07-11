# autosave_util.gd
# ----------------------------------------------------------------------------
# Project Nexus - Editor Autosave (Phase MC5, request 6).
#
# The user asked that the map/mod editors autosave so an unexpected exit never
# loses work, and that on the NEXT entry the editor offers to recover the last
# autosaved draft.
#
# This util is split so its DECISION logic is unit-testable headlessly:
#   * The PURE half (path building, filename sanitising, envelope wrapping,
#     throttling and "should we offer recovery?" decisions) uses NO disk IO and
#     NO SceneTree, so tests can exercise it with plain dictionaries.
#   * The IO half (write_snapshot / read_snapshot / clear) is a thin wrapper
#     around FileAccess/DirAccess that simply persists what the pure half built.
#     It is skipped in the headless suite (guarded), matching how SaveManager is
#     treated elsewhere.
#
# On-disk layout (user:// is writable on every export incl. Android):
#   user://autosave/<kind>.autosave.json
# where <kind> is "map" or "mod". Only the MOST RECENT autosave per kind is
# kept (a rolling draft, not a slot list) so recovery is unambiguous.
#
# Determinism: autosave is pure tooling; it never touches WorldState or the
# state hash. The envelope timestamp is metadata only.
#
# CODE LANGUAGE POLICY: English-only identifiers/comments.
# ----------------------------------------------------------------------------
class_name AutosaveUtil
extends RefCounted

const AUTOSAVE_DIR: String = "user://autosave"
const AUTOSAVE_EXT: String = "autosave.json"

# Envelope format version so a future change can migrate old drafts.
const ENVELOPE_VERSION: int = 1

# Recognised editor kinds. Anything else is rejected by the pure helpers so a
# typo cannot silently write a stray file.
const KIND_MAP: String = "map"
const KIND_MOD: String = "mod"
const KIND_GUI: String = "gui"

# Minimum seconds between two throttled autosaves of the same editor. The editor
# may call maybe_autosave() on every edit; this keeps disk churn bounded.
const DEFAULT_MIN_INTERVAL_SEC: float = 15.0

# Per-kind timestamp (seconds) of the last accepted throttled autosave.
var _last_saved_at: Dictionary = {}
var _min_interval: float = DEFAULT_MIN_INTERVAL_SEC


func _init(min_interval_sec: float = DEFAULT_MIN_INTERVAL_SEC) -> void:
	_min_interval = max(0.0, min_interval_sec)


# --- pure helpers (no IO, fully testable) -----------------------------------

# True for a kind this util is willing to persist.
static func is_valid_kind(kind: String) -> bool:
	return kind == KIND_MAP or kind == KIND_MOD or kind == KIND_GUI


# Strip a kind down to a safe filename token (defensive; kinds are constants but
# callers may pass raw strings). Keeps ASCII letters/digits/underscore only.
static func sanitise_kind(kind: String) -> String:
	var out: String = ""
	for i in range(kind.length()):
		var c: String = kind[i]
		if (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") \
				or (c >= "0" and c <= "9") or c == "_":
			out += c
	return out.to_lower()


# Absolute user:// path for a kind's rolling autosave file. Returns "" for an
# invalid/empty kind so a bad call cannot address a file at all.
static func path_for(kind: String) -> String:
	var safe: String = sanitise_kind(kind)
	if safe.is_empty() or not is_valid_kind(safe):
		return ""
	return "%s/%s.%s" % [AUTOSAVE_DIR, safe, AUTOSAVE_EXT]


# Wrap a project snapshot in the on-disk envelope: {version, kind, saved_at,
# snapshot}. `saved_at` is a caller-supplied unix time so the pure builder stays
# deterministic and testable (IO half passes Time.get_unix_time_from_system()).
static func build_envelope(kind: String, snapshot: Variant, saved_at: int) -> Dictionary:
	return {
		"version": ENVELOPE_VERSION,
		"kind": sanitise_kind(kind),
		"saved_at": int(saved_at),
		"snapshot": _deep_copy(snapshot),
	}


# Validate a loaded envelope and return { ok, kind, saved_at, snapshot }. On any
# structural problem `ok` is false so the editor never restores garbage.
static func parse_envelope(raw: Variant) -> Dictionary:
	var fail: Dictionary = { "ok": false, "kind": "", "saved_at": 0, "snapshot": null }
	if not (raw is Dictionary):
		return fail
	var env: Dictionary = raw as Dictionary
	if int(env.get("version", -1)) != ENVELOPE_VERSION:
		return fail
	var kind: String = sanitise_kind(str(env.get("kind", "")))
	if not is_valid_kind(kind):
		return fail
	if not env.has("snapshot"):
		return fail
	return {
		"ok": true,
		"kind": kind,
		"saved_at": int(env.get("saved_at", 0)),
		"snapshot": _deep_copy(env.get("snapshot")),
	}


# Decide whether the editor should OFFER to recover from a parsed envelope. We
# only offer when: the envelope parsed ok, its kind matches the editor being
# opened, and its snapshot is non-empty (there is actually something to restore).
static func should_offer_recovery(parsed: Dictionary, opening_kind: String) -> bool:
	if not bool(parsed.get("ok", false)):
		return false
	if sanitise_kind(str(parsed.get("kind", ""))) != sanitise_kind(opening_kind):
		return false
	var snap: Variant = parsed.get("snapshot")
	if snap is Dictionary:
		return not (snap as Dictionary).is_empty()
	if snap is Array:
		return not (snap as Array).is_empty()
	return snap != null


# Throttle decision: given the current time (seconds), return true if enough time
# has elapsed since the last accepted autosave of this kind. Records the new time
# when it returns true. `now` is injected so tests need no real clock.
func should_autosave_now(kind: String, now: float) -> bool:
	var safe: String = sanitise_kind(kind)
	if not is_valid_kind(safe):
		return false
	var last: float = float(_last_saved_at.get(safe, -1.0e30))
	if now - last < _min_interval:
		return false
	_last_saved_at[safe] = now
	return true


# Reset the throttle clock (e.g. after a manual save or on editor close).
func reset_throttle(kind: String = "") -> void:
	if kind.is_empty():
		_last_saved_at.clear()
	else:
		_last_saved_at.erase(sanitise_kind(kind))


# --- IO half (thin wrapper; skipped in headless tests) ----------------------

# Ensure the autosave directory exists; returns true when ready.
static func ensure_dir() -> bool:
	if DirAccess.dir_exists_absolute(AUTOSAVE_DIR):
		return true
	return DirAccess.make_dir_recursive_absolute(AUTOSAVE_DIR) == OK


# Persist a snapshot for `kind`. Builds the envelope with the real clock and
# writes pretty JSON. Returns true on success.
func write_snapshot(kind: String, snapshot: Variant) -> bool:
	var path: String = path_for(kind)
	if path.is_empty():
		return false
	if not ensure_dir():
		return false
	var saved_at: int = int(Time.get_unix_time_from_system())
	var env: Dictionary = build_envelope(kind, snapshot, saved_at)
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(env, "\t"))
	f.close()
	return true


# Throttled convenience: only writes when should_autosave_now() allows it. `now`
# defaults to the real clock but is injectable for tests.
func maybe_autosave(kind: String, snapshot: Variant, now: float = -1.0) -> bool:
	var t: float = now if now >= 0.0 else Time.get_unix_time_from_system()
	if not should_autosave_now(kind, t):
		return false
	return write_snapshot(kind, snapshot)


# Read + parse the rolling autosave for `kind`. Returns the parse_envelope()
# result (ok=false when the file is missing or malformed).
func read_snapshot(kind: String) -> Dictionary:
	var fail: Dictionary = { "ok": false, "kind": "", "saved_at": 0, "snapshot": null }
	var path: String = path_for(kind)
	if path.is_empty() or not FileAccess.file_exists(path):
		return fail
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		return fail
	var text: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	return parse_envelope(parsed)


# Delete the autosave draft for `kind` (e.g. after the user declines recovery or
# saves for real). Returns true when the file is gone afterwards.
func clear_snapshot(kind: String) -> bool:
	var path: String = path_for(kind)
	if path.is_empty():
		return false
	if not FileAccess.file_exists(path):
		return true
	return DirAccess.remove_absolute(path) == OK


# --- internals --------------------------------------------------------------

static func _deep_copy(value: Variant) -> Variant:
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	if value is Array:
		return (value as Array).duplicate(true)
	return value
