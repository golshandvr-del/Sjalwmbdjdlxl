# enet_transport.gd
# ----------------------------------------------------------------------------
# Project Nexus - ENet Online Lockstep Transport (Phase 4, step 4.3).
#
# The ONLINE sibling of LoopbackTransport. It carries the SAME plain-Dictionary
# turn/checksum packets that the deterministic LockstepModule produces, but it
# ships them over a real network using Godot's high-level MultiplayerAPI on top
# of an ENetMultiplayerPeer (UDP).
#
# THE WHOLE POINT (Design Philosophy: deterministic core, swappable transport):
#   The LockstepModule and the entire simulation are transport-agnostic. They
#   speak only `broadcast_turn(packet)` / `broadcast_checksum(tick, peer, hash)`
#   on the way out and `receive_turn(packet)` / `receive_checksum(...)` on the
#   way in. LoopbackTransport implements those two `broadcast_*` methods in
#   process (local multiplayer + tests); THIS class implements the EXACT SAME
#   two methods over a socket. Because the core is byte-for-byte identical,
#   online and local share 100% of the deterministic logic -- only this thin
#   shim changes. Same seed + same commands => identical worlds on every
#   machine, with tiny bandwidth (commands only, never the world state).
#
# Why it is a Node (unlike LoopbackTransport which is a RefCounted):
#   The high-level MultiplayerAPI dispatches @rpc calls onto a Node that lives in
#   the SceneTree and owns a `multiplayer` peer. So the transport is a Node you
#   add to the tree, point at a LockstepModule + its EventBus, and then call
#   host()/join(). It auto-broadcasts whenever its peer's lockstep emits a turn
#   or a checksum (same wiring contract as LoopbackTransport.attach()).
#
# Determinism / safety:
#   - We NEVER send world state, only commands + periodic checksums. A desync is
#     surfaced by the LockstepModule's checksum comparison, not "fixed" by state
#     transfer (that would defeat the determinism guarantee and is left to a
#     future resync/rollback layer).
#   - Packets are sent reliably + ordered so no turn is ever dropped or
#     reordered; lockstep correctness depends on every peer seeing every turn.
#   - Peer ids used by the lockstep layer are the Godot multiplayer unique ids,
#     so they are stable for the lifetime of the connection and sortable.
#
# CODE LANGUAGE POLICY: English-only identifiers/comments.
# ----------------------------------------------------------------------------
class_name EnetTransport
extends Node

# Default UDP port for a Project Nexus match.
const DEFAULT_PORT: int = 24545

# Maximum simultaneous remote clients a host accepts (excluding the host).
const DEFAULT_MAX_CLIENTS: int = 7

# Events this transport emits on the LOCAL event bus so the UI/session layer can
# react (show "waiting", "connected", a peer list, etc.). These are presentation
# signals only -- they never feed the simulation.
const EVENT_PEER_CONNECTED: String = "net.peer_connected"
const EVENT_PEER_DISCONNECTED: String = "net.peer_disconnected"
const EVENT_CONNECTED: String = "net.connected"            # we joined a host
const EVENT_CONNECTION_FAILED: String = "net.connection_failed"
const EVENT_SERVER_DISCONNECTED: String = "net.server_disconnected"
# MA7.2 (B10): a lobby/control message arrived from a peer (typically the host's
# "start the match / switch to the game scene" signal, or a slot assignment).
# This is a PRESENTATION / session-orchestration channel, NOT a simulation
# channel: it never carries game state or commands (those travel only in the
# deterministic turn packets), so it can never cause a desync. The payload is a
# plain, small, serializable Dictionary understood by the lobby/session layer.
const EVENT_CONTROL: String = "net.control"

# The lockstep module this transport feeds (set via attach()).
var _lockstep: Object = null

# The local event bus we publish presentation events on (set via attach()).
var _event_bus: Object = null

# All known peer ids INCLUDING ourselves, kept sorted + deterministic. This is
# the authoritative peer set the lockstep session is started with.
var _peers: Array = []

# Are we the authoritative host (server)?
var _is_host: bool = false


# --- Wiring -----------------------------------------------------------------

# Hook this transport to a peer's lockstep module + bus, exactly like
# LoopbackTransport.attach(). After this, any locally-flushed turn or emitted
# checksum is automatically broadcast to the network.
func attach(lockstep: Object, event_bus: Object) -> void:
	_lockstep = lockstep
	_event_bus = event_bus
	event_bus.subscribe(LockstepModule.EVENT_TURN_READY, self, "_on_turn_ready")
	event_bus.subscribe(LockstepModule.EVENT_CHECKSUM, self, "_on_checksum")


# --- Session bring-up -------------------------------------------------------

# Become the host of a new match on `port`. Returns OK (0) on success.
func host(port: int = DEFAULT_PORT, max_clients: int = DEFAULT_MAX_CLIENTS) -> int:
	var peer := ENetMultiplayerPeer.new()
	var err: int = peer.create_server(port, max_clients)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	_is_host = true
	_connect_multiplayer_signals()
	_peers = [multiplayer.get_unique_id()]
	_peers.sort()
	return OK


# Join an existing host at `address`:`port`. Returns OK (0) when the connect
# attempt is launched (success/failure arrives via the connected/failed events).
func join(address: String, port: int = DEFAULT_PORT) -> int:
	var peer := ENetMultiplayerPeer.new()
	var err: int = peer.create_client(address, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	_is_host = false
	_connect_multiplayer_signals()
	return OK


# Tear the connection down cleanly.
func close() -> void:
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	_peers.clear()


func _connect_multiplayer_signals() -> void:
	# Guard against double-connecting if host()/join() is called more than once.
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
	if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	if not multiplayer.connected_to_server.is_connected(_on_connected_to_server):
		multiplayer.connected_to_server.connect(_on_connected_to_server)
	if not multiplayer.connection_failed.is_connected(_on_connection_failed):
		multiplayer.connection_failed.connect(_on_connection_failed)
	if not multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.connect(_on_server_disconnected)


# --- The transport contract (identical to LoopbackTransport) ----------------
# These are the ONLY two methods the lockstep core calls on the way out. They
# are kept method-for-method compatible with LoopbackTransport so the two are
# fully interchangeable.

func broadcast_turn(packet: Dictionary) -> void:
	# Reliable + ordered so no turn is dropped or reordered (lockstep needs every
	# turn from every peer). Sent to everyone except us; we already recorded our
	# own turn locally when we flushed it.
	_rpc_receive_turn.rpc(packet)


func broadcast_checksum(tick: int, author: int, hash_value: int) -> void:
	_rpc_receive_checksum.rpc(tick, author, hash_value)


# --- Control channel (MA7.2 / B10) ------------------------------------------
# Send a lobby/session control message to every OTHER peer. Used by the host to
# tell clients "the match is starting -- switch to the game scene now", and for
# slot assignments (MA7.3). It is deliberately separate from the turn channel:
# it carries no simulation data, so ordering relative to turns does not matter
# and it can never affect determinism. Delivered reliably so it is never lost.
func send_control(msg: Dictionary) -> void:
	_rpc_receive_control.rpc(msg)


# --- Incoming RPCs ----------------------------------------------------------
# `call_remote` so we never deliver to ourselves; `reliable` for ordered, lossless
# delivery; `any_peer` so both host->client and client->host flow.

@rpc("any_peer", "call_remote", "reliable")
func _rpc_receive_turn(packet: Dictionary) -> void:
	if _lockstep != null:
		_lockstep.receive_turn(packet)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_receive_checksum(tick: int, author: int, hash_value: int) -> void:
	if _lockstep != null:
		_lockstep.receive_checksum(tick, author, hash_value)


# Control messages are re-published on the LOCAL event bus so the lobby/session
# layer (not the simulation) can react. `sender` is stamped from the RPC context
# so receivers can tell who sent it (e.g. trust only the host id 1).
@rpc("any_peer", "call_remote", "reliable")
func _rpc_receive_control(msg: Dictionary) -> void:
	var out: Dictionary = msg.duplicate(true)
	out["sender"] = multiplayer.get_remote_sender_id()
	_emit(EVENT_CONTROL, out)


# --- Local lockstep -> network bridge ---------------------------------------

func _on_turn_ready(_event_name: String, payload: Dictionary) -> void:
	broadcast_turn(payload)


func _on_checksum(_event_name: String, payload: Dictionary) -> void:
	broadcast_checksum(int(payload.get("tick", 0)), int(payload.get("peer", 0)), int(payload.get("hash", 0)))


# --- Network membership -----------------------------------------------------

func _on_peer_connected(id: int) -> void:
	if not _peers.has(id):
		_peers.append(id)
		_peers.sort()
	_emit(EVENT_PEER_CONNECTED, { "peer": id, "peers": _peers.duplicate() })


func _on_peer_disconnected(id: int) -> void:
	_peers.erase(id)
	_emit(EVENT_PEER_DISCONNECTED, { "peer": id, "peers": _peers.duplicate() })


func _on_connected_to_server() -> void:
	# As a client we now know our own id and the host's (id 1).
	var me: int = multiplayer.get_unique_id()
	if not _peers.has(me):
		_peers.append(me)
	if not _peers.has(1):
		_peers.append(1)
	_peers.sort()
	_emit(EVENT_CONNECTED, { "self": me, "peers": _peers.duplicate() })


func _on_connection_failed() -> void:
	_emit(EVENT_CONNECTION_FAILED, {})
	close()


func _on_server_disconnected() -> void:
	_emit(EVENT_SERVER_DISCONNECTED, {})
	close()


# --- Accessors --------------------------------------------------------------

func is_host() -> bool:
	return _is_host


func local_peer_id() -> int:
	if multiplayer.multiplayer_peer == null:
		return 0
	return multiplayer.get_unique_id()


# The full, sorted, deterministic peer set to hand to LockstepModule.start_session.
func peer_ids() -> Array:
	return _peers.duplicate()


func _emit(event_name: String, payload: Dictionary) -> void:
	if _event_bus != null:
		_event_bus.emit(event_name, payload)
