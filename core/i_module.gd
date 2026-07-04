# i_module.gd
# ----------------------------------------------------------------------------
# Project Nexus - Module Contract (Section 3.3 of the design document).
#
# Every gameplay module MUST extend this base class. It defines the standard
# lifecycle interface through which the Nexus core talks to a module.
#
# GOLDEN RULE: No module directly imports/references another module.
# Everything goes through `nexus.event_bus` and `nexus.world_state`.
#
# CODE LANGUAGE POLICY: English-only identifiers/comments (see docs/CODE_POLICY.md).
# ----------------------------------------------------------------------------
class_name IModule
extends RefCounted

# A back-reference to the central brain, assigned during init().
# Typed loosely as Object to avoid a hard cyclic class dependency.
var nexus: Object = null


# Unique identifier for this module. Must be overridden.
# Returns a stable, English, snake_case string (e.g. "units", "economy").
func module_id() -> String:
	push_error("IModule.module_id() must be overridden")
	return "undefined_module"


# Called once when the module is registered. Use it to connect to the core:
# subscribe to events, read initial world state, etc.
func init(p_nexus: Object) -> void:
	nexus = p_nexus


# Deterministic logical update. Called once per simulation tick by the SimClock.
# Must NOT read wall-clock time or use uncontrolled randomness (determinism).
func on_tick(_delta_tick: int) -> void:
	pass


# React to an event broadcast on the EventBus.
# `event_name` is an English string id; `payload` is a Dictionary.
func handle_event(_event_name: String, _payload: Dictionary) -> void:
	pass


# Serialize this module's state into a plain Dictionary for saving.
func serialize() -> Dictionary:
	return {}


# Restore this module's state from a previously serialized Dictionary.
func deserialize(_data: Dictionary) -> void:
	pass


# Cleanup: unsubscribe from events, free resources, etc.
func shutdown() -> void:
	pass
