# loopback_transport.gd
# ----------------------------------------------------------------------------
# Project Nexus - Loopback Lockstep Transport (Phase 3, step 3.2).
#
# The transport layer is the ONLY part of multiplayer that knows about "the
# network". The LockstepModule is deliberately transport-agnostic: it produces
# turn packets (plain Dictionaries) and consumes peer packets through
# `receive_turn()` / `receive_checksum()`. This class is a concrete transport
# that wires several LockstepModule instances together IN PROCESS.
#
# Two real uses:
#   1) LOCAL multiplayer (same device, e.g. hot-seat / split control): all peers
#      live in one process, so a loopback is literally the production transport.
#   2) TESTS / deterministic replays: spin up N peers, feed them the same seed,
#      drive them in lockstep, and assert their world hashes stay identical.
#
# For ONLINE play, a sibling transport (e.g. an ENetTransport using Godot's
# MultiplayerAPI) would implement the same two methods -- `broadcast_turn` and
# `broadcast_checksum` -- by sending bytes over a socket and calling the remote
# peers' `receive_*` on arrival. Because the LockstepModule core is identical,
# online and local share 100% of the deterministic logic; only this thin shim
# changes.
#
# CODE LANGUAGE POLICY: English-only identifiers/comments.
# ----------------------------------------------------------------------------
class_name LoopbackTransport
extends RefCounted

# peer_id (int) -> LockstepModule instance for that peer.
var _peers: Dictionary = {}

# MA7.2 (B10): peer_id (int) -> that peer's own EventBus, captured in attach().
# Used by send_control() to re-publish a control message on every OTHER peer's
# bus, mirroring EnetTransport.send_control() in a single process so the lobby /
# session-orchestration code behaves identically for local and online play.
const EVENT_CONTROL: String = "net.control"
var _buses: Dictionary = {}


# Register a peer's lockstep module with the shared loopback bus.
func add_peer(peer_id: int, lockstep: Object) -> void:
	_peers[peer_id] = lockstep


# Deliver a turn packet to EVERY peer except its author (the author already
# recorded its own turn when it flushed). Deterministic: peers iterated in
# ascending id order.
func broadcast_turn(packet: Dictionary) -> void:
	var author: int = int(packet.get("peer", -1))
	var ids: Array = _peers.keys()
	ids.sort()
	for pid in ids:
		if int(pid) == author:
			continue
		(_peers[pid] as Object).receive_turn(packet.duplicate(true))


# Deliver a checksum report to every other peer for desync detection.
func broadcast_checksum(tick: int, author: int, hash_value: int) -> void:
	var ids: Array = _peers.keys()
	ids.sort()
	for pid in ids:
		if int(pid) == author:
			continue
		(_peers[pid] as Object).receive_checksum(tick, author, hash_value)


# Convenience: hook a peer's lockstep events to this transport so that when a
# peer flushes a turn or emits a checksum it is automatically broadcast. The
# `event_bus` is the peer's own bus.
func attach(peer_id: int, lockstep: Object, event_bus: Object) -> void:
	add_peer(peer_id, lockstep)
	_buses[peer_id] = event_bus
	event_bus.subscribe(LockstepModule.EVENT_TURN_READY, self, "_on_turn_ready")
	event_bus.subscribe(LockstepModule.EVENT_CHECKSUM, self, "_on_checksum")


# --- Control channel (MA7.2 / B10) ------------------------------------------
# Re-publish a control message on every OTHER peer's bus. `sender` must be the
# id of the peer sending it (the lobby stamps this); receivers use it to trust
# only the host. Deterministic: peers iterated in ascending id order.
func send_control(sender: int, msg: Dictionary) -> void:
	var out: Dictionary = msg.duplicate(true)
	out["sender"] = sender
	var ids: Array = _buses.keys()
	ids.sort()
	for pid in ids:
		if int(pid) == sender:
			continue
		(_buses[pid] as Object).emit(EVENT_CONTROL, out.duplicate(true))


func _on_turn_ready(_event_name: String, payload: Dictionary) -> void:
	broadcast_turn(payload)


func _on_checksum(_event_name: String, payload: Dictionary) -> void:
	broadcast_checksum(int(payload.get("tick", 0)), int(payload.get("peer", 0)), int(payload.get("hash", 0)))
