# lockstep_gate_util.gd
# ----------------------------------------------------------------------------
# Project Nexus - Pure lockstep tick-gating policy (Phase MA7.1 / B11).
#
# WHY THIS EXISTS:
# The deterministic lockstep MODEL already lives in LockstepModule (flush / gate
# / inject / desync). What was missing (bug B11) was WIRING it into the main
# tick loop so a networked session actually stays in step. That wiring is a tiny
# but critical policy: for each tick the clock wants to advance, in what ORDER do
# we flush our local turn, ask the gate, inject commands, and simulate?
#
# Rather than bury that ordering inside Nexus._process (where it cannot be tested
# without an autoload + a real-time clock), we express it here as ONE pure static
# function driven entirely by callbacks. Nexus passes real callbacks; tests pass
# fakes. Same policy, fully headless-testable -- matching the project's util
# style (SelectionUtil, ControlGroupUtil, TapSelectUtil).
#
# THE POLICY, per tick, up to `ticks_to_run` times:
#   1) flush   -> ship this peer's local turn for (current + input_delay) so the
#                 other peers can confirm the tick we are about to gate on.
#   2) can_sim -> if the NEXT tick is NOT fully confirmed by every peer, STALL:
#                 record a "stall" step and STOP advancing this frame.
#   3) inject  -> schedule the confirmed tick's commands from all peers.
#   4) simulate-> run exactly that one tick.
#   5) resume  -> record a "resume" step (all peers were in; we advanced).
#
# The callbacks are grouped in a small Dictionary so the signature stays stable:
#   gate.flush.call()                      -> void   (flush_local_turn)
#   gate.can_simulate.call()  -> bool                (can_simulate_tick)
#   gate.inject.call(next_tick:int) -> void          (inject_commands_for_tick)
#   gate.simulate.call()      -> void                (run one tick)
#   gate.current_tick.call()  -> int                 (world_state.current_tick)
#
# Returns a small report: how many ticks were simulated and whether it stalled.
# The caller emits the stall/resume EVENTS (they need the event bus); this util
# stays free of any engine singletons.
#
# CODE LANGUAGE POLICY: English-only identifiers/comments.
# ----------------------------------------------------------------------------
class_name LockstepGateUtil
extends RefCounted


# Run the gated tick loop for one frame. `gate` is a Dictionary of Callables
# (see the header). Returns { "simulated": int, "stalled": bool,
# "stall_tick": int } -- stall_tick is the tick we were waiting on (only
# meaningful when stalled is true).
static func run_frame(gate: Dictionary, ticks_to_run: int) -> Dictionary:
	var simulated: int = 0
	var stalled: bool = false
	var stall_tick: int = -1
	for _i in range(max(0, ticks_to_run)):
		# (1) Ship local input for the future tick before gating.
		if gate.has("flush"):
			(gate["flush"] as Callable).call()
		# (2) Gate on the NEXT tick.
		if not bool((gate["can_simulate"] as Callable).call()):
			stalled = true
			stall_tick = int((gate["current_tick"] as Callable).call()) + 1
			break
		# (3) Inject the confirmed tick's commands.
		var next_tick: int = int((gate["current_tick"] as Callable).call()) + 1
		if gate.has("inject"):
			(gate["inject"] as Callable).call(next_tick)
		# (4) Simulate exactly that one tick.
		(gate["simulate"] as Callable).call()
		simulated += 1
	return { "simulated": simulated, "stalled": stalled, "stall_tick": stall_tick }
