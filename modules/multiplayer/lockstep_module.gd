# lockstep_module.gd
# ----------------------------------------------------------------------------
# Project Nexus - Lockstep Multiplayer Module (Phase 3, step 3.2).
#
# Deterministic LOCKSTEP netcode built ON TOP of the existing Command Queue.
# This is the model that makes RTS multiplayer cheap on bandwidth: instead of
# streaming the (huge) world state, every peer runs the SAME deterministic
# simulation and exchanges only the small list of player COMMANDS per tick.
# Same seed + same commands on every machine => identical worlds, forever.
#
# The model (classic "scheduled-turn lockstep"):
#   - The match is divided into the same ticks the SimClock already produces.
#   - A command a player issues on tick T is NOT executed on T. It is scheduled
#     to run on tick T + input_delay (a few ticks ahead). This delay gives the
#     network time to deliver everyone's commands before that tick is reached.
#   - A tick may only be SIMULATED once every peer's commands for that tick have
#     arrived (or an explicit "empty turn" confirmation). Until then the engine
#     STALLS that tick (it is "not confirmed"). This is what keeps peers in step.
#   - Periodically peers exchange a CHECKSUM of their world (via StateHasher). A
#     mismatch is a desync and is surfaced immediately as an event.
#
# Transport independence:
#   This module contains ZERO socket/ENet code. It speaks in plain serializable
#   "turn packets" (Dictionaries). A thin transport adapter (Godot
#   MultiplayerAPI / ENet for online, or a direct in-process loopback for local
#   splitscreen and for tests) feeds remote packets in via `receive_turn()` and
#   ships local packets out by listening to the "lockstep.turn_ready" event.
#   This keeps the deterministic core fully unit-testable headlessly.
#
# Decoupling rules respected:
#   - Pure module: depends only on the core. It schedules commands through
#     `nexus.issue_command` and reads/writes its own world-state section.
#   - It does NOT tick the simulation itself; the Nexus still owns tick
#     execution. This module only decides whether the NEXT tick is allowed to
#     run, by answering `can_simulate_tick()` and via the "lockstep.stall"/
#     "lockstep.resume" events the game loop listens to.
#
# CODE LANGUAGE POLICY: English-only identifiers/comments.
# ----------------------------------------------------------------------------
class_name LockstepModule
extends IModule

const SECTION: String = "lockstep"

# Default number of ticks between issuing a command and executing it. A larger
# delay tolerates higher latency at the cost of input responsiveness.
const DEFAULT_INPUT_DELAY: int = 3

# Exchange a world checksum every N confirmed ticks to catch desyncs early.
const DEFAULT_CHECKSUM_INTERVAL: int = 20

# Events emitted by this module.
const EVENT_TURN_READY: String = "lockstep.turn_ready"      # local turn ready to send
const EVENT_STALL: String = "lockstep.stall"                # waiting for a peer
const EVENT_RESUME: String = "lockstep.resume"              # all peers in; resume
const EVENT_DESYNC: String = "lockstep.desync"              # checksum mismatch
const EVENT_CHECKSUM: String = "lockstep.checksum"          # local checksum for a tick

# Local player id (which peer THIS machine controls). 0 in single-player.
var local_peer: int = 0

# All participating peer ids (including local). Sorted, deterministic.
var peers: Array = []

var input_delay: int = DEFAULT_INPUT_DELAY
var checksum_interval: int = DEFAULT_CHECKSUM_INTERVAL

# Is networked play active? When false the module is inert (single-player).
var active: bool = false

# turns[tick][peer] -> Array of command dicts that peer scheduled FOR `tick`.
# A peer key being PRESENT (even with an empty array) means "confirmed: I have
# nothing else for this tick"; absent means "still waiting".
var _turns: Dictionary = {}

# The next tick we still need confirmations for (the simulation cannot pass it
# until every peer has confirmed). Advances as ticks get confirmed + simulated.
var _confirmed_through: int = -1

# Commands the LOCAL player has accumulated this frame, to be flushed into a
# turn packet for tick (current_tick + input_delay).
var _local_pending: Array = []

# Remembered local checksums per tick, for comparison when a peer reports theirs.
var _local_checksums: Dictionary = {}

# How many recent checksum entries to retain. A peer's report always concerns a
# recent tick (network latency is bounded by the stall gate), so anything older
# is dead weight: without a cap this map grew UNBOUNDED for the whole match
# (one entry per checksum interval, forever) -- a slow leak on long sessions.
const _MAX_CHECKSUM_HISTORY: int = 64

# Latched desync info (null until a mismatch is detected).
var _desync: Dictionary = {}


func module_id() -> String:
	return "multiplayer"


func init(p_nexus: Object) -> void:
	super.init(p_nexus)
	_ensure_state()
	# Listen for locally-issued commands so we can route them into lockstep turns
	# instead of executing them immediately. The game issues commands by emitting
	# "core.command"; we capture the intent here. (In single-player / when
	# inactive we do nothing and the normal path applies.)
	nexus.subscribe("core.tick", self, "_on_bus_event")


func _ensure_state() -> void:
	var section: Dictionary = nexus.world_state.get_section(SECTION)
	if not section.has("active"):
		section["active"] = false
	if not section.has("confirmed_through"):
		section["confirmed_through"] = -1


# --- Session setup ----------------------------------------------------------

# Begin a networked lockstep session. `all_peers` is the full sorted set of
# participating peer ids; `local` is which one this machine drives.
func start_session(all_peers: Array, local: int, p_input_delay: int = DEFAULT_INPUT_DELAY) -> void:
	peers = all_peers.duplicate()
	peers.sort()
	local_peer = local
	input_delay = max(1, p_input_delay)
	active = true
	_turns.clear()
	_local_pending.clear()
	_local_checksums.clear()
	_desync.clear()
	_confirmed_through = int(nexus.world_state.current_tick)
	var section: Dictionary = nexus.world_state.get_section(SECTION)
	section["active"] = true
	section["peers"] = peers.duplicate()
	section["local_peer"] = local_peer
	section["input_delay"] = input_delay


func end_session() -> void:
	active = false
	nexus.world_state.get_section(SECTION)["active"] = false


# --- Local input: schedule a command through lockstep -----------------------

# The game calls THIS (instead of nexus.issue_command directly) when networked.
# The command is buffered and will be packed into the local turn for the tick
# `current_tick + input_delay`, then executed on every peer at that same tick.
func submit_local_command(type: String, data: Dictionary = {}) -> void:
	if not active:
		# Not networked: fall back to the normal immediate scheduling.
		nexus.issue_command(type, local_peer, data, 1)
		return
	_local_pending.append({ "type": type, "issuer": local_peer, "data": data })


# Pack everything the local player queued this frame into a turn packet for the
# target tick and emit it for the transport to broadcast. Also records it
# locally (a peer must include its own commands in its own simulation).
func flush_local_turn() -> Dictionary:
	var target_tick: int = int(nexus.world_state.current_tick) + input_delay
	var packet: Dictionary = {
		"tick": target_tick,
		"peer": local_peer,
		"commands": _local_pending.duplicate(true),
	}
	_local_pending.clear()
	_record_turn(packet)
	nexus.emit_event(EVENT_TURN_READY, packet)
	return packet


# Emit an EMPTY-but-explicit turn confirmation for a SPECIFIC tick. In lockstep
# a peer with nothing to do on a tick must still tell everyone "I have no
# commands for this tick" so the others are not stalled waiting on it. The game
# loop calls this for every tick it locally simulates that carried no local
# input; tests use it to fast-forward confirmations. It records locally and
# broadcasts via the same EVENT_TURN_READY path as flush_local_turn.
func flush_empty_turn_for(tick: int) -> Dictionary:
	var packet: Dictionary = { "tick": tick, "peer": local_peer, "commands": [] }
	_record_turn(packet)
	nexus.emit_event(EVENT_TURN_READY, packet)
	return packet


# --- Remote input: a peer's turn packet arrives -----------------------------

func receive_turn(packet: Dictionary) -> void:
	if not active:
		return
	_record_turn(packet)


func _record_turn(packet: Dictionary) -> void:
	var tick: int = int(packet.get("tick", -1))
	var peer: int = int(packet.get("peer", -1))
	if tick < 0 or peer < 0:
		return
	if not _turns.has(tick):
		_turns[tick] = {}
	(_turns[tick] as Dictionary)[peer] = (packet.get("commands", []) as Array).duplicate(true)


# --- Tick gating: may the simulation run the next tick? ---------------------

# True if every peer has confirmed their commands for `tick`. An absent tick
# entry means nobody has confirmed yet -> not ready.
func is_tick_confirmed(tick: int) -> bool:
	if not active:
		return true
	var entry: Dictionary = _turns.get(tick, {})
	for peer in peers:
		if not entry.has(peer):
			return false
	return true


# The game loop asks this before running the NEXT tick. While it returns false
# the loop must stall (and may show a "waiting for players" indicator).
func can_simulate_tick() -> bool:
	if not active:
		return true
	return is_tick_confirmed(int(nexus.world_state.current_tick) + 1)


# Called by the game loop the moment BEFORE a confirmed tick is simulated: it
# injects that tick's commands (from all peers, in deterministic peer+order)
# into the real Command Queue so the Nexus dispatches them on exactly that tick.
func inject_commands_for_tick(tick: int) -> int:
	if not active:
		return 0
	var entry: Dictionary = _turns.get(tick, {})
	var injected: int = 0
	# Deterministic order: ascending peer id, then submission order within peer.
	var ordered_peers: Array = entry.keys()
	ordered_peers.sort()
	for peer in ordered_peers:
		for command in entry[peer]:
			# Schedule to run on exactly `tick` (delay relative to current tick).
			var delay: int = tick - int(nexus.world_state.current_tick)
			if delay < 1:
				delay = 1
			nexus.issue_command(str(command.get("type", "")), int(command.get("issuer", peer)), command.get("data", {}), delay)
			injected += 1
	_confirmed_through = max(_confirmed_through, tick)
	nexus.world_state.get_section(SECTION)["confirmed_through"] = _confirmed_through
	# Free memory for ticks we no longer need.
	_turns.erase(tick)
	return injected


# --- Checksum exchange / desync detection -----------------------------------

func _on_bus_event(event_name: String, payload: Dictionary) -> void:
	if event_name == "core.tick":
		_maybe_emit_checksum(int(payload.get("tick", 0)))


func _maybe_emit_checksum(tick: int) -> void:
	if not active:
		return
	if checksum_interval <= 0 or tick % checksum_interval != 0:
		return
	var h: int = StateHasher.hash_world(nexus.world_state)
	_local_checksums[tick] = h
	# Trim ancient entries so a long match cannot grow this map without bound.
	# Local bookkeeping only -- never part of the hashed world state.
	if _local_checksums.size() > _MAX_CHECKSUM_HISTORY:
		var ticks: Array = _local_checksums.keys()
		ticks.sort()
		while ticks.size() > _MAX_CHECKSUM_HISTORY:
			_local_checksums.erase(ticks.pop_front())
	nexus.emit_event(EVENT_CHECKSUM, { "tick": tick, "peer": local_peer, "hash": h })


# A peer reports its checksum for a tick; compare to ours. If we have a local
# checksum for that tick and it differs, flag a desync.
func receive_checksum(tick: int, peer: int, remote_hash: int) -> void:
	if not active:
		return
	if not _local_checksums.has(tick):
		return
	var local_hash: int = int(_local_checksums[tick])
	if local_hash != remote_hash:
		_desync = { "tick": tick, "peer": peer, "local_hash": local_hash, "remote_hash": remote_hash }
		nexus.emit_event(EVENT_DESYNC, _desync.duplicate())


func has_desync() -> bool:
	return not _desync.is_empty()


func desync_info() -> Dictionary:
	return _desync.duplicate()


func confirmed_through() -> int:
	return _confirmed_through


# --- Save / load ------------------------------------------------------------
# A lockstep session is inherently live network state; we persist only the
# lightweight flags so a reload knows whether it was networked. The turn buffer
# itself is rebuilt from the live transport on reconnect.

func serialize() -> Dictionary:
	return {
		"active": active,
		"input_delay": input_delay,
		"confirmed_through": _confirmed_through,
	}


func deserialize(data: Dictionary) -> void:
	active = bool(data.get("active", false))
	input_delay = int(data.get("input_delay", DEFAULT_INPUT_DELAY))
	_confirmed_through = int(data.get("confirmed_through", -1))


func shutdown() -> void:
	if nexus != null:
		nexus.event_bus.unsubscribe_all(self)
