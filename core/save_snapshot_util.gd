# save_snapshot_util.gd
# ----------------------------------------------------------------------------
# Project Nexus - Save snapshot validation (T003, KI-13).
#
# Pure, static shape check of a save snapshot Dictionary BEFORE it is applied.
# SaveSystem.apply_snapshot must be all-or-nothing: a malformed or hostile file
# (e.g. an imported save) must be rejected without touching the live game.
# Returns "" when the snapshot is acceptable, otherwise a short ASCII reason.
# ----------------------------------------------------------------------------
class_name SaveSnapshotUtil
extends RefCounted


static func validate(snapshot: Variant, current_version: int) -> String:
	if not (snapshot is Dictionary):
		return "not_a_dictionary"
	var s: Dictionary = snapshot as Dictionary
	if not s.has("world_state"):
		return "missing_world_state"
	var version: Variant = s.get("save_version", null)
	if not (version is int or version is float):
		return "bad_save_version"
	if int(version) > current_version:
		return "newer_save_version"
	var ws: Variant = s["world_state"]
	if not (ws is Dictionary):
		return "bad_world_state"
	var sections: Variant = (ws as Dictionary).get("sections", {})
	if not (sections is Dictionary):
		return "bad_world_state_sections"
	for key in ["modules", "command_queue", "sim_clock"]:
		if s.has(key) and not (s[key] is Dictionary):
			return "bad_" + key
	var pending: Variant = (s.get("command_queue", {}) as Dictionary).get("pending", [])
	if not (pending is Array):
		return "bad_command_queue_pending"
	var clock: Dictionary = s.get("sim_clock", {})
	for key in ["tick_rate", "total_ticks"]:
		if clock.has(key) and not (clock[key] is int or clock[key] is float):
			return "bad_sim_clock_" + key
	if clock.has("tick_rate") and int(clock["tick_rate"]) <= 0:
		return "bad_sim_clock_tick_rate"
	return ""
