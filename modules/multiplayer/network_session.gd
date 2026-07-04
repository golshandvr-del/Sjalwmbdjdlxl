# network_session.gd
# ----------------------------------------------------------------------------
# Project Nexus - Network Session Coordinator (Phase 4, step 4.4).
#
# A small, UI-facing helper that turns "host a match" / "join a match" into a
# running lockstep session. It is the glue between:
#   - the EnetTransport (the socket layer),
#   - the LockstepModule (the deterministic turn scheduler), and
#   - the GameBootstrap (which builds the actual match from a scenario).
#
# It is NOT a gameplay module: it owns no world state and ticks nothing. It just
# orchestrates connection + session start so the scene code stays tiny. Because
# it builds on the SAME LockstepModule the loopback/local path uses, an online
# match and a local match run byte-for-byte identical simulations -- only the
# transport differs.
#
# Lifecycle:
#   host(port)            -> create server, wait for the lobby to fill, then
#                            begin_session() starts lockstep with all peers.
#   join(address, port)   -> connect to a host; on connect the host triggers the
#                            session start (the host is authoritative for the
#                            agreed seed + peer set, broadcast as the first turn).
#
# The actual scenario load + seed agreement is intentionally simple here: the
# host decides the seed and everyone uses the same scenario file, so the
# deterministic core does the rest. A richer lobby (map pick, ready-checks) is a
# pure-UI concern that can sit on top without touching this coordinator.
#
# CODE LANGUAGE POLICY: English-only identifiers/comments.
# ----------------------------------------------------------------------------
class_name NetworkSession
extends Node

# Emitted (on the local event bus) when the lockstep session has actually begun.
const EVENT_SESSION_STARTED: String = "net.session_started"

# The Nexus this session drives.
var _nexus: Object = null

# The transport we own. Normally an EnetTransport (a child Node), but typed as
# Object so any conforming transport (incl. a test stub) can be injected -- the
# session only ever calls the transport-agnostic surface (peer_ids /
# local_peer_id / is_host / host / join / close).
var _transport: Object = null

# The lockstep module (looked up from the Nexus; registered by GameBootstrap).
var _lockstep: Object = null

# Match parameters agreed across peers.
var _seed: int = 0
var _input_delay: int = LockstepModule.DEFAULT_INPUT_DELAY

# How many peers the host waits for before starting (host count INCLUDES host).
var _expected_peers: int = 2


func setup(nexus: Object) -> void:
	_nexus = nexus
	_lockstep = nexus.get_module("multiplayer")
	_transport = EnetTransport.new()
	_transport.name = "EnetTransport"
	add_child(_transport)
	_transport.attach(_lockstep, nexus.event_bus)
	# React to membership changes so the host can auto-start when the lobby fills.
	nexus.event_bus.subscribe(EnetTransport.EVENT_PEER_CONNECTED, self, "_on_peer_connected")
	nexus.event_bus.subscribe(EnetTransport.EVENT_CONNECTED, self, "_on_connected")


# --- Public API -------------------------------------------------------------

# Host a match. `expected_peers` is the total player count (including the host);
# the lockstep session begins automatically once that many peers are present.
func host(seed_value: int, expected_peers: int = 2, port: int = EnetTransport.DEFAULT_PORT, input_delay: int = LockstepModule.DEFAULT_INPUT_DELAY) -> int:
	_seed = seed_value
	_expected_peers = max(1, expected_peers)
	_input_delay = max(1, input_delay)
	var err: int = _transport.host(port)
	if err != OK:
		return err
	# A solo host (expected_peers == 1) can start immediately.
	_maybe_begin()
	return OK


# Join a hosted match. The host drives the actual session start; we just connect.
func join(address: String, port: int = EnetTransport.DEFAULT_PORT) -> int:
	return _transport.join(address, port)


# Tear everything down.
func close() -> void:
	if _lockstep != null and _lockstep.active:
		_lockstep.end_session()
	if _transport != null:
		_transport.close()


# --- Session start ----------------------------------------------------------

# Begin the deterministic lockstep session across the CURRENT peer set. Idempotent.
func begin_session() -> void:
	if _lockstep == null or _lockstep.active:
		return
	var peers: Array = _transport.peer_ids()
	if peers.is_empty():
		peers = [_transport.local_peer_id()]
	var local: int = _transport.local_peer_id()
	_nexus.world_state.random_seed = _seed
	_lockstep.start_session(peers, local, _input_delay)
	_nexus.emit_event(EVENT_SESSION_STARTED, {
		"peers": peers.duplicate(),
		"local": local,
		"seed": _seed,
		"input_delay": _input_delay,
	})


# Host-side auto-start once the lobby is full.
func _maybe_begin() -> void:
	if not _transport.is_host():
		return
	if _transport.peer_ids().size() >= _expected_peers:
		begin_session()


# --- Transport callbacks ----------------------------------------------------

func _on_peer_connected(_event_name: String, _payload: Dictionary) -> void:
	# Only the host counts the lobby and starts the match.
	_maybe_begin()


func _on_connected(_event_name: String, _payload: Dictionary) -> void:
	# A client that has connected does nothing here; it will begin its session
	# when it receives the host's first scheduled turn (the transport delivers
	# turns and the lockstep module gates ticks until everyone has confirmed).
	# For the simple "everyone uses the same seed + scenario" flow we begin the
	# client session immediately so its clock is ready to receive turns.
	begin_session()


# --- Accessors --------------------------------------------------------------

func transport() -> Object:
	return _transport


func is_host() -> bool:
	return _transport != null and _transport.is_host()
