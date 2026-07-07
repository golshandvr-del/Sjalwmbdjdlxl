# nexus.gd
# ----------------------------------------------------------------------------
# Project Nexus - The Central Brain (core orchestrator).
#
# Registered as an Autoload singleton (see project.godot). The Nexus has NO
# gameplay of its own; it is purely a coordinator that wires together the core
# components and drives the simulation:
#
#   EventBus        - decoupled module communication
#   WorldState      - single source of truth
#   ModuleRegistry  - module lifecycle
#   SimClock        - deterministic tick + active pause
#   CommandQueue    - player/AI commands (lockstep basis)
#   DataLoader      - data-driven content
#   SaveSystem      - serialize / restore the whole game
#
# Each frame, Nexus asks the SimClock how many ticks to run, then for each tick:
#   1) dispatches all commands due on that tick,
#   2) advances every module's on_tick(),
#   3) emits a "core.tick" event.
# ----------------------------------------------------------------------------
extends Node

# Core component instances.
var event_bus: EventBus
var world_state: WorldState
var module_registry: ModuleRegistry
var sim_clock: SimClock
var command_queue: CommandQueue
var data_loader: DataLoader
var save_system: SaveSystem

# Standard core event names (English ids, used across the project).
const EVENT_BOOT: String = "core.boot"
const EVENT_TICK: String = "core.tick"
const EVENT_PAUSED: String = "core.paused"
const EVENT_RESUMED: String = "core.resumed"
const EVENT_COMMAND: String = "core.command"


func _ready() -> void:
	_build_core()
	# Process every frame to drive the simulation clock.
	set_process(true)
	event_bus.emit(EVENT_BOOT, { "tick_rate": sim_clock.tick_rate })


# Construct and wire all core components.
func _build_core() -> void:
	event_bus = EventBus.new()
	world_state = WorldState.new()
	sim_clock = SimClock.new()
	command_queue = CommandQueue.new()
	data_loader = DataLoader.new()

	module_registry = ModuleRegistry.new()
	module_registry.setup(self)

	save_system = SaveSystem.new()
	save_system.setup(self)


# Register a gameplay module with the core. Returns true on success.
func register_module(module: IModule) -> bool:
	return module_registry.register(module)


func get_module(module_id: String) -> IModule:
	return module_registry.get_module(module_id)


# Convenience pass-throughs to the EventBus.
func subscribe(event_name: String, target: Object, method: String) -> void:
	event_bus.subscribe(event_name, target, method)


func emit_event(event_name: String, payload: Dictionary = {}) -> void:
	event_bus.emit(event_name, payload)


# Enqueue a command. By default it runs on the next tick after the current one.
func issue_command(type: String, issuer: int, data: Dictionary = {}, delay_ticks: int = 1) -> int:
	var target_tick: int = world_state.current_tick + max(1, delay_ticks)
	var cmd_id: int = command_queue.enqueue(type, issuer, target_tick, data)
	event_bus.emit(EVENT_COMMAND, { "type": type, "issuer": issuer, "tick": target_tick })
	return cmd_id


# --- Simulation lifecycle ---------------------------------------------------

func start_simulation(seed_value: int = 0) -> void:
	world_state.random_seed = seed_value
	sim_clock.start()


func stop_simulation() -> void:
	sim_clock.stop()


func set_paused(value: bool) -> void:
	if value:
		sim_clock.pause()
		event_bus.emit(EVENT_PAUSED, {})
	else:
		sim_clock.resume()
		event_bus.emit(EVENT_RESUMED, {})


func toggle_pause() -> void:
	set_paused(not sim_clock.is_paused())


# Godot main loop: convert real time into discrete simulation ticks.
#
# Two paths:
#   * Single-player / inactive lockstep: run every tick the clock produced.
#   * Networked lockstep (session active): run ticks under the lockstep GATE so
#     all peers stay in step (MA7.1 / B11). See _run_networked_ticks().
func _process(delta: float) -> void:
	var ticks_to_run: int = sim_clock.advance(delta)
	if ticks_to_run <= 0:
		return
	var lockstep: Object = _active_lockstep()
	if lockstep == null:
		for _i in range(ticks_to_run):
			_run_single_tick()
	else:
		_run_networked_ticks(lockstep, ticks_to_run)


# Return the multiplayer/lockstep module IFF it exists AND a session is active;
# otherwise null so the fast single-player path is used. Kept tiny + allocation
# free so it is cheap to call every frame.
func _active_lockstep() -> Object:
	var m: Object = module_registry.get_module("multiplayer")
	if m != null and m.has_method("can_simulate_tick") and bool(m.get("active")):
		return m
	return null


# Networked tick loop (MA7.1). The flush/gate/inject/simulate ORDERING is the
# pure, headless-tested policy in LockstepGateUtil; here we just bind the real
# lockstep + tick callbacks to it and translate the report into bus events (the
# util stays free of any engine singletons). Per tick it:
#   1) flushes THIS peer's local turn for (current + input_delay) so other peers
#      can confirm the tick we are about to gate on,
#   2) STALLS (emits lockstep.stall) if the next tick is not fully confirmed,
#   3) otherwise injects that tick's commands and simulates exactly it.
func _run_networked_ticks(lockstep: Object, ticks_to_run: int) -> void:
	var gate: Dictionary = {
		"flush": func() -> void:
			if lockstep.has_method("flush_local_turn"):
				lockstep.flush_local_turn(),
		"can_simulate": func() -> bool:
			return lockstep.can_simulate_tick(),
		"inject": func(next_tick: int) -> void:
			if lockstep.has_method("inject_commands_for_tick"):
				lockstep.inject_commands_for_tick(next_tick),
		"simulate": func() -> void:
			_run_single_tick(),
		"current_tick": func() -> int:
			return world_state.current_tick,
	}
	var report: Dictionary = LockstepGateUtil.run_frame(gate, ticks_to_run)
	if bool(report.get("stalled", false)):
		emit_event(LockstepModule.EVENT_STALL, { "tick": int(report.get("stall_tick", world_state.current_tick + 1)) })
	elif int(report.get("simulated", 0)) > 0:
		emit_event(LockstepModule.EVENT_RESUME, { "tick": world_state.current_tick })


# Run exactly one deterministic simulation tick.
func _run_single_tick() -> void:
	world_state.current_tick += 1
	var tick: int = world_state.current_tick

	# 1) Dispatch all commands scheduled for this tick.
	# Each command is delivered EXACTLY ONCE, via the EventBus, to the modules
	# that subscribed to its "command.<type>" event. We deliberately do NOT also
	# broadcast it through ModuleRegistry.dispatch_event_to_all(): every command
	# handler already subscribes through the bus, so broadcasting as well would
	# process the command twice (double-spending resources, duplicating spawns,
	# stacking tech effects, etc.).
	var due: Array = command_queue.collect_due(tick)
	for command in due:
		event_bus.emit("command." + str(command["type"]), command)

	# 2) Advance module logic.
	module_registry.tick_all(1)

	# 3) Broadcast the tick.
	event_bus.emit(EVENT_TICK, { "tick": tick })


# Public helper for tests / step-debugging: run N ticks immediately,
# ignoring the real-time clock and the pause flag.
func step_ticks(num_ticks: int) -> void:
	for _i in range(num_ticks):
		_run_single_tick()
	sim_clock.step(num_ticks)


# Tear down the whole simulation (e.g. returning to main menu).
func shutdown_simulation() -> void:
	sim_clock.stop()
	module_registry.shutdown_all()
	command_queue.clear()
	world_state.clear()
