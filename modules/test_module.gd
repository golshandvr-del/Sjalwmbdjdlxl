# test_module.gd
# ----------------------------------------------------------------------------
# Project Nexus - Test Module (Phase 0, step 0.12).
#
# A throwaway demonstration module that PROVES the architecture works:
#   - it registers with the Nexus through the standard IModule contract,
#   - it subscribes to a core event via the EventBus,
#   - it reacts on every simulation tick,
#   - it writes its own state into the WorldState,
#   - it issues a command through the CommandQueue,
#   - it serializes / deserializes itself.
#
# It depends on NO other module - only on the core. This is the canonical
# example of how every future gameplay module should be written.
# ----------------------------------------------------------------------------
class_name TestModule
extends IModule

# Local mirror of state; the source of truth lives in WorldState section "test".
var _tick_count: int = 0
var _events_received: int = 0


func module_id() -> String:
	return "test_module"


func init(p_nexus: Object) -> void:
	super.init(p_nexus)
	# Subscribe to the core tick and command events through the bus.
	nexus.subscribe(nexus.EVENT_TICK, self, "_on_bus_event")
	nexus.subscribe("command.test_ping", self, "_on_bus_event")
	# Initialize our section in the single source of truth.
	var section: Dictionary = nexus.world_state.get_section("test")
	section["tick_count"] = 0
	section["events_received"] = 0


# Deterministic per-tick logic. On tick 3 it fires a demo command, proving the
# CommandQueue path works end to end.
func on_tick(_delta_tick: int) -> void:
	_tick_count += 1
	var section: Dictionary = nexus.world_state.get_section("test")
	section["tick_count"] = _tick_count
	if _tick_count == 3:
		nexus.issue_command("test_ping", 0, { "note": "hello_from_test_module" }, 1)


# Single handler for every event we subscribed to.
func _on_bus_event(event_name: String, payload: Dictionary) -> void:
	handle_event(event_name, payload)


func handle_event(event_name: String, _payload: Dictionary) -> void:
	_events_received += 1
	var section: Dictionary = nexus.world_state.get_section("test")
	section["events_received"] = _events_received
	section["last_event"] = event_name


func serialize() -> Dictionary:
	return {
		"tick_count": _tick_count,
		"events_received": _events_received,
	}


func deserialize(data: Dictionary) -> void:
	_tick_count = int(data.get("tick_count", 0))
	_events_received = int(data.get("events_received", 0))


func shutdown() -> void:
	if nexus != null:
		nexus.event_bus.unsubscribe_all(self)
