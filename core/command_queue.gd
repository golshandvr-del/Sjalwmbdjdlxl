# command_queue.gd
# ----------------------------------------------------------------------------
# Project Nexus - Command Queue (core component).
#
# All player AND AI actions are expressed as "commands" and pushed into this
# queue rather than mutating the world directly. Commands are scheduled to
# execute on a specific simulation tick. This is the basis for:
#   - Active Pause (queue commands while paused, run them on resume)
#   - Deterministic Lockstep multiplayer (Phase 4): exchange commands per tick
#
# A command is a plain Dictionary, e.g.:
#   { "type": "move_unit", "issuer": 0, "tick": 42, "data": { ... } }
# Keeping commands as plain data keeps them serializable and network-friendly.
# ----------------------------------------------------------------------------
class_name CommandQueue
extends RefCounted

# Pending commands not yet executed. Kept sorted by their target tick.
var _pending: Array = []

# Monotonic id assigned to each command (for stable ordering / debugging).
var _next_command_id: int = 0


# Enqueue a command to run on (or after) `target_tick`.
# `type` is an English string id; `data` is an arbitrary payload Dictionary.
func enqueue(type: String, issuer: int, target_tick: int, data: Dictionary = {}) -> int:
	var command: Dictionary = {
		"id": _next_command_id,
		"type": type,
		"issuer": issuer,
		"tick": target_tick,
		"data": data,
	}
	_next_command_id += 1
	_pending.append(command)
	# Sort by target tick, then by id for a fully deterministic order.
	_pending.sort_custom(_compare_commands)
	return command["id"]


func _compare_commands(a: Dictionary, b: Dictionary) -> bool:
	if a["tick"] == b["tick"]:
		return a["id"] < b["id"]
	return a["tick"] < b["tick"]


# Pop and return all commands scheduled to run at or before `current_tick`,
# in deterministic order. The Nexus dispatches these each tick.
func collect_due(current_tick: int) -> Array:
	var due: Array = []
	var remaining: Array = []
	for command in _pending:
		if command["tick"] <= current_tick:
			due.append(command)
		else:
			remaining.append(command)
	_pending = remaining
	return due


func pending_count() -> int:
	return _pending.size()


func clear() -> void:
	_pending.clear()


# Serialize the queue (for multiplayer save / replay).
func serialize() -> Dictionary:
	return {
		"next_command_id": _next_command_id,
		"pending": _pending.duplicate(true),
	}


func deserialize(data: Dictionary) -> void:
	_next_command_id = int(data.get("next_command_id", 0))
	var pending: Variant = data.get("pending", [])
	_pending = (pending as Array).duplicate(true) if pending is Array else []
