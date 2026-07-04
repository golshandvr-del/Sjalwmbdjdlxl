# event_bus.gd
# ----------------------------------------------------------------------------
# Project Nexus - Event Bus (core component).
#
# A simple, deterministic publish/subscribe system. Modules communicate ONLY
# through this bus so they never depend directly on one another (Loose Coupling).
#
# Determinism note: listeners for a given event are invoked in the exact order
# they subscribed. We never use unordered containers for dispatch.
# ----------------------------------------------------------------------------
class_name EventBus
extends RefCounted

# Maps event_name (String) -> Array of listener entries.
# Each entry is a Dictionary: { "target": Object, "method": String }.
var _listeners: Dictionary = {}

# Optional in-memory log of emitted events (used by the debug screen).
var _log_enabled: bool = false
var _event_log: Array = []
const MAX_LOG_SIZE: int = 200


# Subscribe `target.method(event_name, payload)` to an event.
func subscribe(event_name: String, target: Object, method: String) -> void:
	if not _listeners.has(event_name):
		_listeners[event_name] = []
	# Avoid duplicate subscriptions of the same target+method.
	for entry in _listeners[event_name]:
		if entry["target"] == target and entry["method"] == method:
			return
	_listeners[event_name].append({ "target": target, "method": method })


# Remove a specific subscription.
func unsubscribe(event_name: String, target: Object, method: String) -> void:
	if not _listeners.has(event_name):
		return
	var arr: Array = _listeners[event_name]
	for i in range(arr.size() - 1, -1, -1):
		var entry: Dictionary = arr[i]
		if entry["target"] == target and entry["method"] == method:
			arr.remove_at(i)
	if arr.is_empty():
		_listeners.erase(event_name)


# Remove every subscription belonging to a given target (e.g. on shutdown).
func unsubscribe_all(target: Object) -> void:
	for event_name in _listeners.keys():
		var arr: Array = _listeners[event_name]
		for i in range(arr.size() - 1, -1, -1):
			if arr[i]["target"] == target:
				arr.remove_at(i)
		if arr.is_empty():
			_listeners.erase(event_name)


# Broadcast an event to all subscribers, in subscription order.
func emit(event_name: String, payload: Dictionary = {}) -> void:
	if _log_enabled:
		_push_log(event_name, payload)
	if not _listeners.has(event_name):
		return
	# Iterate over a copy so listeners may safely (un)subscribe during dispatch.
	var snapshot: Array = _listeners[event_name].duplicate()
	for entry in snapshot:
		var target: Object = entry["target"]
		if is_instance_valid(target) and target.has_method(entry["method"]):
			target.call(entry["method"], event_name, payload)


# Returns how many listeners are registered for an event (useful for tests).
func listener_count(event_name: String) -> int:
	if not _listeners.has(event_name):
		return 0
	return _listeners[event_name].size()


# --- Debug logging helpers --------------------------------------------------

func set_log_enabled(enabled: bool) -> void:
	_log_enabled = enabled


func get_event_log() -> Array:
	return _event_log


func clear_log() -> void:
	_event_log.clear()


func _push_log(event_name: String, payload: Dictionary) -> void:
	_event_log.append({ "event": event_name, "payload": payload })
	if _event_log.size() > MAX_LOG_SIZE:
		_event_log.remove_at(0)
