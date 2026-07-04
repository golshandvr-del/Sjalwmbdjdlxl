# lan_discovery.gd
# ----------------------------------------------------------------------------
# Project Nexus - LAN Discovery over UDP broadcast (Phase P5, step P5.1 / R6.2).
#
# The piece that makes "Join" work WITHOUT typing an IP address: a host
# periodically BROADCASTS a tiny UDP beacon on the local network describing its
# match (name, current/expected players, game mode, mod fingerprint, TCP/ENet
# port). A joining client opens a UDP listener on the same discovery port and
# collects those beacons into a live server list; clicking a discovered server
# hands its address+port straight to NetworkSession.join().
#
# WHY UDP BROADCAST (and not a central lobby server):
#   The design is "LAN first". A broadcast beacon needs no internet, no server
#   infrastructure, and no configuration -- every device already on the same
#   Wi-Fi/switch sees it. This class is PRESENTATION/discovery ONLY; it carries
#   no gameplay and never touches WorldState or the deterministic core. It just
#   turns "there is a host over there" into a clickable row.
#
# THE TWO ROLES (a single instance is used as one or the other):
#   - Advertiser (host side):  start_advertising(info) -> emits a beacon every
#     BEACON_INTERVAL seconds until stop(). Update the live info (e.g. player
#     count) with set_info() so the beacon always reflects the lobby.
#   - Browser (join side):     start_browsing() -> listens for beacons and emits
#     EVENT_SERVER_FOUND / keeps a deduplicated `servers()` list. Stale servers
#     (not seen for SERVER_TIMEOUT seconds) are pruned so the list stays live.
#
# Determinism note: none. Discovery is entirely out-of-band; the moment a client
# actually connects, the existing deterministic lockstep stack takes over.
#
# CODE LANGUAGE POLICY: English-only identifiers/comments.
# ----------------------------------------------------------------------------
class_name LanDiscovery
extends Node

# The UDP port beacons are broadcast on. Distinct from the ENet game port so the
# two never collide. Every device browsing must listen on the SAME port.
const DISCOVERY_PORT: int = 24546

# A short magic string so we ignore unrelated UDP traffic on this port.
const BEACON_MAGIC: String = "NEXUS_LAN_V1"

# How often the host re-broadcasts its beacon (seconds).
const BEACON_INTERVAL: float = 1.0

# A discovered server is dropped from the list if not heard from for this long.
const SERVER_TIMEOUT: float = 4.0

# Broadcast address for the local subnet. 255.255.255.255 reaches the whole LAN.
const BROADCAST_ADDRESS: String = "255.255.255.255"

# Presentation events on the LOCAL event bus (never fed to the simulation).
const EVENT_SERVER_FOUND: String = "lan.server_found"       # a new/updated server
const EVENT_SERVER_LOST: String = "lan.server_lost"         # a server timed out
const EVENT_SERVERS_CHANGED: String = "lan.servers_changed" # any list change

var _event_bus: Object = null

# UDP sockets. We use one for advertising (send) and one for browsing (receive);
# a single instance only ever plays one role at a time, but keeping them separate
# keeps the send/recv paths clean.
var _advertiser: PacketPeerUDP = null
var _browser: PacketPeerUDP = null

# Host-side: the live match info broadcast in every beacon.
var _info: Dictionary = {}

# Join-side: discovered servers keyed by "address:port" -> { info, last_seen }.
var _servers: Dictionary = {}

# Seconds since the last beacon send (host) -- drives BEACON_INTERVAL.
var _advertise_accum: float = 0.0

# Monotonic clock (seconds) used for last-seen timestamps; from Time.
var _now: float = 0.0

# RISK-3: a per-instance unique session id. It is stamped into every beacon this
# instance sends, and the browser drops any beacon carrying its OWN session id.
# This prevents self-discovery when a single device both hosts and browses (UDP
# broadcast is delivered back to the sender), which is more robust than "the host
# must not browse" (that assumption breaks for spectator / re-listing flows).
# Filtering by session id (not IP) is correct under NAT/loopback where the IP is
# misleading.
var _session_id: String = ""


func _generate_session_id() -> String:
	# Non-deterministic on purpose: discovery is out-of-band and never feeds the
	# simulation, so using system randomness here cannot cause desync.
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return "%08x%08x" % [rng.randi(), rng.randi()]


func setup(event_bus: Object) -> void:
	_event_bus = event_bus


# --- Host side: advertise a match ------------------------------------------

# Start broadcasting a beacon describing `info`. `info` is a plain Dictionary,
# typically: { name, players, max_players, mode, mod_hash, port }.
func start_advertising(info: Dictionary) -> int:
	stop()
	if _session_id == "":
		_session_id = _generate_session_id()
	_info = info.duplicate(true)
	_advertiser = PacketPeerUDP.new()
	_advertiser.set_broadcast_enabled(true)
	# Bind to an ephemeral port; destination is the broadcast address:port.
	_advertiser.set_dest_address(BROADCAST_ADDRESS, DISCOVERY_PORT)
	_advertise_accum = BEACON_INTERVAL  # send immediately on the first tick
	set_process(true)
	return OK


# Update the advertised info in place (e.g. when a player joins the lobby) so the
# NEXT beacon reflects the change. No-op if not advertising.
func set_info(info: Dictionary) -> void:
	if _advertiser != null:
		_info = info.duplicate(true)


# --- Join side: browse for matches -----------------------------------------

# Start listening for beacons. Discovered servers accumulate in `servers()` and
# fire EVENT_SERVER_FOUND / EVENT_SERVERS_CHANGED.
func start_browsing() -> int:
	stop()
	if _session_id == "":
		_session_id = _generate_session_id()
	_browser = PacketPeerUDP.new()
	var err: int = _browser.bind(DISCOVERY_PORT, "*")
	if err != OK:
		_browser = null
		return err
	_servers.clear()
	set_process(true)
	return OK


# The current, de-duplicated list of discovered servers (each the beacon's info
# augmented with "address" + "port"). Sorted by name for a stable UI order.
func servers() -> Array:
	var out: Array = []
	var keys: Array = _servers.keys()
	keys.sort()
	for key in keys:
		out.append((_servers[key]["info"] as Dictionary).duplicate(true))
	return out


# --- Lifecycle --------------------------------------------------------------

func stop() -> void:
	if _advertiser != null:
		_advertiser.close()
		_advertiser = null
	if _browser != null:
		_browser.close()
		_browser = null
	set_process(false)


func _process(delta: float) -> void:
	_now += delta
	if _advertiser != null:
		_advertise_accum += delta
		if _advertise_accum >= BEACON_INTERVAL:
			_advertise_accum = 0.0
			_send_beacon()
	if _browser != null:
		_poll_beacons()
		_prune_stale()


# --- Beacon send (host) -----------------------------------------------------

func _send_beacon() -> void:
	var beacon: Dictionary = {
		"magic": BEACON_MAGIC,
		"session": _session_id,
		"info": _info,
	}
	var bytes: PackedByteArray = JSON.stringify(beacon).to_utf8_buffer()
	_advertiser.put_packet(bytes)


# --- Beacon receive (join) --------------------------------------------------

func _poll_beacons() -> void:
	while _browser.get_available_packet_count() > 0:
		var bytes: PackedByteArray = _browser.get_packet()
		var sender_ip: String = _browser.get_packet_ip()
		_ingest_beacon(bytes, sender_ip)


func _ingest_beacon(bytes: PackedByteArray, sender_ip: String) -> void:
	var text: String = bytes.get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return
	var beacon: Dictionary = parsed
	if str(beacon.get("magic", "")) != BEACON_MAGIC:
		return
	# RISK-3: ignore our own beacon (self-discovery). We compare session ids, not
	# IPs, so this also works over loopback and behind NAT.
	if _session_id != "" and str(beacon.get("session", "")) == _session_id:
		return
	var info: Dictionary = beacon.get("info", {})
	if not (info is Dictionary):
		return
	# The advertised port is the ENet game port; the address is the real sender IP
	# (a host cannot know its own routable LAN IP reliably, so we trust the source).
	var port: int = int(info.get("port", EnetTransport.DEFAULT_PORT))
	var key: String = "%s:%d" % [sender_ip, port]
	var enriched: Dictionary = (info as Dictionary).duplicate(true)
	enriched["address"] = sender_ip
	enriched["port"] = port
	var is_new: bool = not _servers.has(key)
	_servers[key] = { "info": enriched, "last_seen": _now }
	if _event_bus != null:
		_event_bus.emit(EVENT_SERVER_FOUND, enriched.duplicate(true))
		if is_new:
			_event_bus.emit(EVENT_SERVERS_CHANGED, { "servers": servers() })


func _prune_stale() -> void:
	# RISK-2: use an explicit "collect then erase" pattern instead of erasing
	# while iterating. Dictionary.keys() already returns a copy in Godot 4 (so
	# the old loop was technically safe), but separating the passes makes the
	# intent obvious and stays correct if this is ever refactored to iterate the
	# dictionary directly.
	var expired: Array = []
	for key in _servers.keys():
		if _now - float(_servers[key]["last_seen"]) > SERVER_TIMEOUT:
			expired.append(key)
	for key in expired:
		var lost: Dictionary = (_servers[key]["info"] as Dictionary).duplicate(true)
		_servers.erase(key)
		if _event_bus != null:
			_event_bus.emit(EVENT_SERVER_LOST, lost)
	if not expired.is_empty() and _event_bus != null:
		_event_bus.emit(EVENT_SERVERS_CHANGED, { "servers": servers() })
