# module_registry.gd
# ----------------------------------------------------------------------------
# Project Nexus - Module Registry (core component).
#
# Registers gameplay modules and manages their lifecycle (init / tick / event /
# shutdown). Keeps an ordered list so ticks and events are dispatched
# deterministically in registration order. Also indexes modules by module_id
# for lookups.
# ----------------------------------------------------------------------------
class_name ModuleRegistry
extends RefCounted

# Ordered list of registered IModule instances (registration order = tick order).
var _modules: Array = []

# Fast lookup: module_id (String) -> IModule.
var _by_id: Dictionary = {}

# Back-reference to the core, passed to each module on init().
var _nexus: Object = null


func setup(nexus: Object) -> void:
	_nexus = nexus


# Register a module instance. Returns false if the id is already taken.
func register(module: IModule) -> bool:
	var id: String = module.module_id()
	if _by_id.has(id):
		push_error("ModuleRegistry: duplicate module_id '%s'" % id)
		return false
	_modules.append(module)
	_by_id[id] = module
	if _nexus != null:
		module.init(_nexus)
	return true


# Look up a module by its id, or null if not present.
func get_module(module_id: String) -> IModule:
	return _by_id.get(module_id, null)


func has_module(module_id: String) -> bool:
	return _by_id.has(module_id)


func count() -> int:
	return _modules.size()


func get_all() -> Array:
	return _modules


func get_all_ids() -> Array:
	var ids: Array = []
	for m in _modules:
		ids.append(m.module_id())
	return ids


# Dispatch a tick to every module in registration order.
func tick_all(delta_tick: int) -> void:
	for m in _modules:
		m.on_tick(delta_tick)


# Forward an event to every module's handle_event in registration order.
# (Used for broadcast-style delivery; targeted delivery goes via EventBus.)
func dispatch_event_to_all(event_name: String, payload: Dictionary) -> void:
	for m in _modules:
		m.handle_event(event_name, payload)


# Serialize all modules into { module_id: state_dict }.
func serialize_all() -> Dictionary:
	var out: Dictionary = {}
	for m in _modules:
		out[m.module_id()] = m.serialize()
	return out


# Restore all modules from a { module_id: state_dict } dictionary.
func deserialize_all(data: Dictionary) -> void:
	for m in _modules:
		var id: String = m.module_id()
		if data.has(id):
			m.deserialize(data[id])


# Shut down and clear every module (reverse order for safe teardown).
func shutdown_all() -> void:
	for i in range(_modules.size() - 1, -1, -1):
		_modules[i].shutdown()
	_modules.clear()
	_by_id.clear()
