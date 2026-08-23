# save_system.gd
# ----------------------------------------------------------------------------
# Project Nexus - Save System (core component).
#
# Serializes and restores the entire game: the WorldState plus every module's
# state plus the pending CommandQueue. Saves are written as JSON so they remain
# human-readable, debuggable, and cross-platform.
#
# The save system has no gameplay knowledge; it only orchestrates the
# serialize()/deserialize() calls exposed by the other core components.
# ----------------------------------------------------------------------------
class_name SaveSystem
extends RefCounted

const SAVE_VERSION: int = 1

# Back-reference to the core (set up by Nexus).
var _nexus: Object = null


func setup(nexus: Object) -> void:
	_nexus = nexus


# Build a complete snapshot Dictionary of the current game.
func build_snapshot() -> Dictionary:
	if _nexus == null:
		push_error("SaveSystem: nexus not set up")
		return {}
	return {
		"save_version": SAVE_VERSION,
		"world_state": _nexus.world_state.serialize(),
		"modules": _nexus.module_registry.serialize_all(),
		"command_queue": _nexus.command_queue.serialize(),
		"sim_clock": {
			"tick_rate": _nexus.sim_clock.tick_rate,
			"total_ticks": _nexus.sim_clock.total_ticks,
		},
	}


# Restore the game from a snapshot Dictionary.
func apply_snapshot(snapshot: Dictionary) -> bool:
	if _nexus == null:
		push_error("SaveSystem: nexus not set up")
		return false
	if int(snapshot.get("save_version", -1)) != SAVE_VERSION:
		push_warning("SaveSystem: save version mismatch, attempting best-effort load")
	_nexus.world_state.deserialize(snapshot.get("world_state", {}))
	_nexus.module_registry.deserialize_all(snapshot.get("modules", {}))
	_nexus.command_queue.deserialize(snapshot.get("command_queue", {}))
	var clock_data: Dictionary = snapshot.get("sim_clock", {})
	if clock_data.has("tick_rate"):
		_nexus.sim_clock.tick_rate = int(clock_data["tick_rate"])
	if clock_data.has("total_ticks"):
		_nexus.sim_clock.total_ticks = int(clock_data["total_ticks"])
	return true


# Write the current game to a JSON file. Returns true on success.
# Atomic (temp + rename): a crash mid-write never destroys a previous save.
func save_to_file(path: String) -> bool:
	var snapshot: Dictionary = build_snapshot()
	if snapshot.is_empty():
		return false
	if not SafeFileUtil.write_text(path, JSON.stringify(snapshot, "\t")):
		push_error("SaveSystem: cannot open '%s' for writing" % path)
		return false
	return true


# Load a game from a JSON file. Returns true on success.
func load_from_file(path: String) -> bool:
	if not FileAccess.file_exists(path):
		push_error("SaveSystem: file not found '%s'" % path)
		return false
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("SaveSystem: cannot open '%s' for reading" % path)
		return false
	var text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		push_error("SaveSystem: invalid save file '%s'" % path)
		return false
	return apply_snapshot(parsed as Dictionary)
