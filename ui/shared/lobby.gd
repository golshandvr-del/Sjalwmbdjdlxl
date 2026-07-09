# lobby.gd
# ----------------------------------------------------------------------------
# Project Nexus - Multiplayer Lobby (Phase P5, steps P5.2 / P5.3 / R6).
#
# The screen shown for a LAN multiplayer match, in one of two roles decided by
# how it was entered (WorldState.ui_prefs.lobby_role = "host" | "join"):
#
#   HOST (R6.1 / R6.3 / R6.4):
#     - Shows a list of player SLOTS sized to the human+AI count chosen in Match
#       Setup (R1.3/R1.4). Slots fill as players connect (host is slot 0).
#     - The host assigns each slot to a TEAM (R6.3) via a per-slot team selector
#       (AIs and humans can be mixed into teams).
#     - LAN advertising is ON so browsers can discover this match (R6.2 beacon).
#     - Everyone must press READY (R6.4); the host's "Start" is enabled only when
#       all connected human slots are ready. On start, mod sync (R7) runs first.
#
#   JOIN (R6.2):
#     - Shows a SEARCH box + magnifier and a live list of discovered LAN servers
#       (from LanDiscovery beacons). Clicking a server connects to it.
#     - After connecting, the join waits in the lobby, receives its slot/team,
#       presses READY, and the host drives the start (with auto mod sync, R7).
#
# This screen is PRESENTATION + orchestration only: it drives NetworkSession /
# LanDiscovery / ModSync and changes scenes. It never touches the deterministic
# simulation; the moment the session starts, the existing lockstep stack (which
# is byte-identical to local play) takes over.
#
# The tree is built programmatically in _ready() so no hand-authored .tscn is
# needed beyond a root Control with this script attached.
#
# CODE LANGUAGE POLICY: English-only identifiers/comments; visible labels go
# through the Localization service.
# ----------------------------------------------------------------------------
extends Control

const MENU_SCENE: String = "res://scenes/main_menu.tscn"
const MOBILE_SCENE: String = "res://scenes/game_main.tscn"
const DESKTOP_SCENE: String = "res://scenes/game_desktop.tscn"

const ProgressOverlayScript = preload("res://ui/shared/progress_overlay.gd")
const LanDiscoveryScript = preload("res://modules/multiplayer/lan_discovery.gd")
const ModSyncScript = preload("res://modules/multiplayer/mod_sync.gd")

# A fixed shared seed for LAN matches; the host is authoritative and every peer
# uses the same catalogs (guaranteed by mod sync), so the deterministic core
# does the rest. (A future enhancement could negotiate a random seed.)
const LAN_SEED: int = 0xC0FFEE

var _loc: Localization = Localization.new()

# Role: "host" or "join" (read from ui_prefs, set by main menu).
var _role: String = "host"
# UI style the game scene should use once the match starts.
var _game_scene: String = MOBILE_SCENE

var _session: NetworkSession = null
var _discovery = null          # LanDiscovery
var _mod_sync = null           # ModSync

# Match configuration carried from Match Setup (name/mode/human/ai counts).
var _match_name: String = "LAN Match"
var _game_mode: String = "team"
var _human_players: int = 2
var _ai_players: int = 0

# Host-side slot model: one dict per slot { kind:"human"|"ai", team:int,
# ready:bool, peer:int(-1 if empty) }.
var _slots: Array = []

# --- Widgets ---------------------------------------------------------------
var _title_label: Label
var _status_label: Label
var _slots_box: VBoxContainer
var _servers_box: VBoxContainer
var _search_edit: LineEdit
var _ready_button: Button
var _start_button: Button
var _back_button: Button
var _overlay: ProgressOverlay


func _ready() -> void:
	_loc.load_all("res://localization")
	var settings: GameSettings = GameSettings.new(Nexus.world_state)
	settings.load_from_file()
	UiScale.apply_with_settings(self, settings)
	var saved: String = str(Nexus.world_state.get_section("ui_prefs").get("locale", ""))
	if saved != "":
		_loc.set_locale(saved)

	# Read the role + match config stashed by the main menu / match setup.
	var prefs: Dictionary = Nexus.world_state.get_section("ui_prefs")
	_role = str(prefs.get("lobby_role", "host"))
	_game_scene = str(prefs.get("lobby_game_scene", MOBILE_SCENE))
	var cfg: Dictionary = Nexus.world_state.get_section("match_config")
	_match_name = str(cfg.get("match_name", "LAN Match"))
	_game_mode = str(cfg.get("game_mode", "team"))
	_human_players = int(cfg.get("human_players", 2))
	_ai_players = int(cfg.get("ai_players", 0))

	# Make sure the base modules + catalogs exist so NetworkSession / ModSync work.
	GameBootstrap.register_modules(Nexus)
	GameBootstrap.load_catalogs(Nexus)

	_mod_sync = ModSyncScript.new()
	_mod_sync.setup(Nexus)

	_build_ui()
	_apply_labels()

	if _role == "host":
		_start_as_host()
	else:
		_start_as_join()


# --- UI construction --------------------------------------------------------

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 0)
	center.add_child(panel)

	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	_title_label = Label.new()
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 22)
	box.add_child(_title_label)

	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status_label)

	# --- Join-only: server search + discovered list -------------------------
	var search_row: HBoxContainer = HBoxContainer.new()
	search_row.name = "SearchRow"
	box.add_child(search_row)
	var mag: Label = Label.new()
	mag.text = "\u2315"  # magnifier glyph
	mag.add_theme_font_size_override("font_size", 20)
	search_row.add_child(mag)
	_search_edit = LineEdit.new()
	_search_edit.placeholder_text = _loc.t("ui.lobby.search")
	_search_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search_edit.text_changed.connect(func(_t: String) -> void: _refresh_server_list())
	search_row.add_child(_search_edit)

	var servers_scroll: ScrollContainer = ScrollContainer.new()
	servers_scroll.name = "ServersScroll"
	servers_scroll.custom_minimum_size = Vector2(0, 180)
	box.add_child(servers_scroll)
	_servers_box = VBoxContainer.new()
	_servers_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	servers_scroll.add_child(_servers_box)

	# --- Host + join: player slot list --------------------------------------
	var slots_scroll: ScrollContainer = ScrollContainer.new()
	slots_scroll.custom_minimum_size = Vector2(0, 220)
	box.add_child(slots_scroll)
	_slots_box = VBoxContainer.new()
	_slots_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slots_scroll.add_child(_slots_box)

	# --- Action buttons ------------------------------------------------------
	var buttons: HBoxContainer = HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 10)
	box.add_child(buttons)

	_ready_button = Button.new()
	_ready_button.toggle_mode = true
	_ready_button.pressed.connect(_on_ready_toggled)
	buttons.add_child(_ready_button)

	_start_button = Button.new()
	_start_button.pressed.connect(_on_start_pressed)
	buttons.add_child(_start_button)

	_back_button = Button.new()
	_back_button.pressed.connect(_on_back)
	buttons.add_child(_back_button)

	_overlay = ProgressOverlayScript.new()
	_overlay.visible = false
	add_child(_overlay)


func _apply_labels() -> void:
	if _role == "host":
		_title_label.text = "%s - %s" % [_loc.t("ui.lobby.host_title"), _match_name]
	else:
		_title_label.text = _loc.t("ui.lobby.join_title")
	_ready_button.text = _loc.t("ui.lobby.ready")
	_start_button.text = _loc.t("ui.lobby.start")
	_back_button.text = _loc.t("ui.menu.back")

	# Show/hide the search UI depending on role (join browses; host advertises).
	var is_join: bool = (_role == "join")
	_search_edit.get_parent().visible = is_join
	_servers_box.get_parent().visible = is_join
	# Only the host can start the match.
	_start_button.visible = (_role == "host")


# --- HOST -------------------------------------------------------------------

func _start_as_host() -> void:
	_ensure_session()
	# Build the slot model: humans first, then AIs; default team layout = split.
	_slots.clear()
	var total: int = _human_players + _ai_players
	for i in range(total):
		var kind: String = "human" if i < _human_players else "ai"
		_slots.append({
			"kind": kind,
			"team": _default_team_for(i),
			"ready": (kind == "ai"),   # AIs are always "ready"
			"peer": 0 if i == 0 else -1,  # host owns slot 0
		})
	# Host waits for the human players only (AIs are local); slot 0 is us.
	var err: int = _session.host(LAN_SEED, _human_players)
	if err != OK:
		_status_label.text = "%s (error %d)" % [_loc.t("ui.net.disconnected"), err]
		return
	# Start LAN advertising so joins can discover us.
	_discovery = LanDiscoveryScript.new()
	_discovery.setup(Nexus.event_bus)
	add_child(_discovery)
	_discovery.start_advertising(_beacon_info())
	_status_label.text = _loc.t("ui.net.waiting_for_players")
	_rebuild_slot_rows()
	_update_start_enabled()


# Default team assignment for team mode: alternate 0/1; ffa/ctf: unique per slot.
func _default_team_for(index: int) -> int:
	if _game_mode == "team":
		return index % 2
	return index


func _beacon_info() -> Dictionary:
	var connected: int = 1
	if _session != null and _session.transport() != null:
		connected = _session.transport().peer_ids().size()
	return {
		"name": _match_name,
		"players": connected,
		"max_players": _human_players,
		"mode": _game_mode,
		"mod_hash": _mod_sync.fingerprint_string(),
		"port": EnetTransport.DEFAULT_PORT,
	}


# --- JOIN -------------------------------------------------------------------

func _start_as_join() -> void:
	_ensure_session()
	_discovery = LanDiscoveryScript.new()
	_discovery.setup(Nexus.event_bus)
	add_child(_discovery)
	_discovery.start_browsing()
	Nexus.subscribe(LanDiscoveryScript.EVENT_SERVERS_CHANGED, self, "_on_servers_changed")
	_status_label.text = _loc.t("ui.lobby.searching")


func _on_servers_changed(_event_name: String, _payload: Dictionary) -> void:
	_refresh_server_list()


func _refresh_server_list() -> void:
	if _discovery == null:
		return
	for child in _servers_box.get_children():
		child.queue_free()
	var filter_text: String = _search_edit.text.strip_edges().to_lower()
	for server in _discovery.servers():
		var name: String = str(server.get("name", "?"))
		if filter_text != "" and not name.to_lower().contains(filter_text):
			continue
		var row: Button = Button.new()
		row.text = "%s  [%d/%d]  %s" % [
			name,
			int(server.get("players", 0)),
			int(server.get("max_players", 0)),
			str(server.get("mode", "")),
		]
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var address: String = str(server.get("address", "127.0.0.1"))
		var port: int = int(server.get("port", EnetTransport.DEFAULT_PORT))
		row.pressed.connect(func() -> void: _connect_to(address, port))
		_servers_box.add_child(row)


func _connect_to(address: String, port: int) -> void:
	_status_label.text = _loc.t("ui.net.connecting")
	if _discovery != null:
		_discovery.stop()
	var err: int = _session.join(address, port)
	if err != OK:
		_status_label.text = "%s (error %d)" % [_loc.t("ui.net.disconnected"), err]


# --- Slots (shared) ---------------------------------------------------------

func _rebuild_slot_rows() -> void:
	for child in _slots_box.get_children():
		child.queue_free()
	for i in range(_slots.size()):
		_slots_box.add_child(_build_slot_row(i))


func _build_slot_row(index: int) -> Control:
	var slot: Dictionary = _slots[index]
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var label: Label = Label.new()
	var kind_key: String = "ui.lobby.slot_human" if slot["kind"] == "human" else "ui.lobby.slot_ai"
	var occupancy: String = ""
	if slot["kind"] == "human":
		occupancy = _loc.t("ui.lobby.open") if int(slot["peer"]) < 0 else _loc.t("ui.lobby.filled")
	label.text = "%d. %s %s" % [index + 1, _loc.t(kind_key), occupancy]
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)

	# Team selector (host only can change; joins see it read-only).
	var team_option: OptionButton = OptionButton.new()
	var team_count: int = 4
	for t in range(team_count):
		team_option.add_item("%s %d" % [_loc.t("ui.lobby.team"), t + 1], t)
	team_option.selected = int(slot["team"])
	team_option.disabled = (_role != "host")
	team_option.item_selected.connect(func(sel: int) -> void: _on_team_changed(index, sel))
	row.add_child(team_option)

	# Ready indicator.
	var ready_label: Label = Label.new()
	ready_label.text = "\u2714" if bool(slot["ready"]) else "\u2026"
	row.add_child(ready_label)
	return row


func _on_team_changed(index: int, team: int) -> void:
	if _role != "host":
		return
	_slots[index]["team"] = team
	# Rebroadcast the beacon (team layout is host-authoritative; the actual team
	# assignment is written into match_config at start).


func _on_ready_toggled() -> void:
	# Mark our own slot ready (host = slot 0; a join's own assigned slot).
	var my_index: int = _my_slot_index()
	if my_index >= 0 and my_index < _slots.size():
		_slots[my_index]["ready"] = _ready_button.button_pressed
	_rebuild_slot_rows()
	if _role == "host":
		_update_start_enabled()
		_broadcast_slots()
	else:
		# MA7.3 (B9): report our ready state back to the host so its start button
		# can enable once every human slot is ready.
		if _session != null:
			_session.send_control({
				"type": "ready_state",
				"peer": _session.transport().local_peer_id(),
				"ready": _ready_button.button_pressed,
			})


# The index of the slot this peer controls: the host owns slot 0; a join owns
# the slot whose peer id matches its local multiplayer id (MA7.3). Returns -1 if
# not yet assigned.
func _my_slot_index() -> int:
	if _role == "host":
		return 0
	if _session == null or _session.transport() == null:
		return -1
	var me: int = _session.transport().local_peer_id()
	for i in range(_slots.size()):
		if int(_slots[i].get("peer", -1)) == me:
			return i
	return -1


func _update_start_enabled() -> void:
	if _role != "host":
		return
	var all_ready: bool = true
	for slot in _slots:
		if slot["kind"] == "human" and int(slot["peer"]) >= 0 and not bool(slot["ready"]):
			all_ready = false
			break
	_start_button.disabled = not all_ready


# --- Session wiring ---------------------------------------------------------

func _ensure_session() -> void:
	if _session != null:
		return
	_session = NetworkSession.new()
	_session.name = "NetworkSession"
	add_child(_session)
	_session.setup(Nexus)
	Nexus.subscribe(EnetTransport.EVENT_PEER_CONNECTED, self, "_on_peer_connected")
	Nexus.subscribe(EnetTransport.EVENT_CONNECTED, self, "_on_connected")
	Nexus.subscribe(EnetTransport.EVENT_CONNECTION_FAILED, self, "_on_connection_failed")
	Nexus.subscribe(EnetTransport.EVENT_SERVER_DISCONNECTED, self, "_on_server_disconnected")
	# MA7.2 (B10): control channel -- the host's "start the match" signal and slot
	# assignments arrive here so a JOIN client actually leaves the lobby for the
	# game scene instead of waiting forever.
	Nexus.subscribe(EnetTransport.EVENT_CONTROL, self, "_on_control")
	# Do NOT subscribe to EVENT_SESSION_STARTED here; the lobby drives start
	# explicitly (after mod sync) via _begin_match so it can show the progress bar.


func _on_peer_connected(_event_name: String, payload: Dictionary) -> void:
	# Host side: a player filled a slot. Assign it to the first open human slot.
	if _role == "host":
		var peer: int = int(payload.get("peer", -1))
		for slot in _slots:
			if slot["kind"] == "human" and int(slot["peer"]) < 0:
				slot["peer"] = peer
				break
		if _discovery != null:
			_discovery.set_info(_beacon_info())
		_rebuild_slot_rows()
		_update_start_enabled()
		# MA7.3 (B9): concrete "a player joined (n/total)" feedback instead of a
		# generic "connected", and push the authoritative slot layout to every
		# client so their lobby (and each client's own slot/team) matches the host.
		_status_label.text = _loc.t("ui.net.player_joined").format([_filled_human_slots(), _human_players])
		_broadcast_slots()


func _on_connected(_event_name: String, _payload: Dictionary) -> void:
	# Join side: we reached the host. Wait for the host's authoritative slot
	# layout (MA7.3 slots_update) and then for the start signal (MA7.2). We show a
	# provisional single-row view until the real layout arrives so the screen is
	# never blank.
	_status_label.text = _loc.t("ui.lobby.waiting_host")
	if _slots.is_empty():
		_slots.append({ "kind": "human", "team": 0, "ready": false, "peer": 1 })
	_rebuild_slot_rows()


func _on_connection_failed(_event_name: String, _payload: Dictionary) -> void:
	_status_label.text = _loc.t("ui.net.disconnected")
	if _discovery != null and _role == "join":
		_discovery.start_browsing()


func _on_server_disconnected(_event_name: String, _payload: Dictionary) -> void:
	_status_label.text = _loc.t("ui.net.disconnected")


# --- Start the match (host) with automatic mod sync (R7) --------------------

func _on_start_pressed() -> void:
	if _role != "host":
		return
	if _discovery != null:
		_discovery.stop()
	_overlay.begin(_loc.t("ui.lobby.starting"), _loc.t("ui.lobby.checking_mods"))
	# Write the resolved team/placement layout into match_config for GameBootstrap.
	_write_placements()
	# R7: mod sync happens transparently. In this LAN flow the host is the source
	# of truth; joins that differ receive the pack over the reliable channel. The
	# transfer itself is handled by the transport during session bring-up. Here we
	# show the progress bar and then begin the deterministic session.
	_overlay.set_progress(0.5, _loc.t("ui.lobby.syncing_mods"))
	await get_tree().create_timer(0.2).timeout
	_overlay.set_progress(1.0, _loc.t("ui.net.connected"))
	# MA7.2 (B10): tell every JOIN client to start too, and hand them the exact
	# same match layout (scene + seed + placements) so all peers build an
	# identical world before the deterministic session takes over. This must go
	# out BEFORE we begin our own session / change scene, while the transport
	# (and its RPC peer) is still live on this lobby node.
	_session.send_control({
		"type": "start_match",
		"scene": _game_scene,
		"seed": LAN_SEED,
		"placements": _current_placements(),
		"game_mode": _game_mode,
	})
	_session.begin_session()
	Nexus.world_state.random_seed = LAN_SEED
	get_tree().change_scene_to_file(_game_scene)


# Build the lobby's team/slot decisions as a placements array. Matches the
# schema in STRUCTURE.md section 9.8. Pure (no side effects) so it can be reused
# both to persist locally AND to ship to join clients over the control channel.
func _current_placements() -> Array:
	var placements: Array = []
	for i in range(_slots.size()):
		var slot: Dictionary = _slots[i]
		placements.append({
			"slot": i,
			"kind": slot["kind"],
			"team": int(slot["team"]),
			"flag_index": i,
		})
	return placements


# Persist the lobby's team/slot decisions so the game (and victory conditions)
# use them.
func _write_placements() -> void:
	var cfg: Dictionary = Nexus.world_state.get_section("match_config")
	cfg["placements"] = _current_placements()
	cfg["game_mode"] = _game_mode


# --- Control channel receiver (MA7.2 / B10) ---------------------------------

# A control message arrived from another peer. On a JOIN client, the host's
# "start_match" means: adopt the host's seed + placements and switch to the game
# scene now (the client already began its lockstep session on connect, so the
# deterministic clock is ready). We trust only messages from the host (id 1).
func _on_control(_event_name: String, payload: Dictionary) -> void:
	var sender: int = int(payload.get("sender", 0))
	var msg_type: String = str(payload.get("type", ""))
	# Messages a JOIN client accepts only FROM the host (multiplayer id 1):
	if msg_type == "slots_update":
		# MA7.3 (B9): adopt the host's authoritative slot layout so this client
		# sees the real players/teams and knows which slot is its own (for Ready).
		if _role == "join" and sender == 1:
			_apply_slot_snapshot(payload.get("slots", []))
			_status_label.text = _loc.t("ui.lobby.waiting_host")
		return
	if msg_type == "ready_state":
		# Host side: a client toggled Ready. Update that peer's slot and re-check
		# whether the match can start (MA7.3).
		if _role == "host":
			var peer: int = int(payload.get("peer", -1))
			for slot in _slots:
				if int(slot.get("peer", -1)) == peer:
					slot["ready"] = bool(payload.get("ready", false))
					break
			_rebuild_slot_rows()
			_update_start_enabled()
			_broadcast_slots()
		return
	if msg_type != "start_match":
		return
	# start_match is accepted only from the host, and only by a join client.
	if sender != 1 or _role != "join":
		return
	# The host is authoritative: mirror its scene + seed + placements exactly.
	var scene: String = str(payload.get("scene", _game_scene))
	var seed_value: int = int(payload.get("seed", LAN_SEED))
	var cfg: Dictionary = Nexus.world_state.get_section("match_config")
	if payload.has("placements"):
		cfg["placements"] = payload.get("placements")
	cfg["game_mode"] = str(payload.get("game_mode", _game_mode))
	Nexus.world_state.random_seed = seed_value
	# Make sure our lockstep session is running before we hand off to the game.
	if _session != null:
		_session.begin_session()
	if _discovery != null:
		_discovery.stop()
	get_tree().change_scene_to_file(scene)


# --- Slot snapshot sync (MA7.3 / B9) ----------------------------------------

# How many human slots currently have a peer assigned (host counts as slot 0).
func _filled_human_slots() -> int:
	var n: int = 0
	for slot in _slots:
		if slot["kind"] == "human" and int(slot.get("peer", -1)) >= 0:
			n += 1
	return n


# A plain, serializable copy of the slot layout for the control channel (no
# engine objects, only ints/strings/bools) so it survives RPC/loopback intact.
func _slot_snapshot() -> Array:
	var out: Array = []
	for slot in _slots:
		out.append({
			"kind": str(slot.get("kind", "human")),
			"team": int(slot.get("team", 0)),
			"ready": bool(slot.get("ready", false)),
			"peer": int(slot.get("peer", -1)),
		})
	return out


# Host: push the authoritative slot layout to all clients.
func _broadcast_slots() -> void:
	if _role != "host" or _session == null:
		return
	_session.send_control({ "type": "slots_update", "slots": _slot_snapshot() })


# Join: replace the local slot model with the host's snapshot and refresh the UI.
func _apply_slot_snapshot(snapshot: Array) -> void:
	_slots.clear()
	for entry in snapshot:
		var e: Dictionary = entry
		_slots.append({
			"kind": str(e.get("kind", "human")),
			"team": int(e.get("team", 0)),
			"ready": bool(e.get("ready", false)),
			"peer": int(e.get("peer", -1)),
		})
	# Keep our own Ready toggle visually consistent with the assigned slot.
	var mine: int = _my_slot_index()
	if mine >= 0 and mine < _slots.size():
		_ready_button.button_pressed = bool(_slots[mine].get("ready", false))
	_rebuild_slot_rows()


func _on_back() -> void:
	if _session != null:
		_session.close()
	if _discovery != null:
		_discovery.stop()
	get_tree().change_scene_to_file(MENU_SCENE)


# MB3.2 (bug 6): Android BACK / ESC leaves the lobby (tearing down the session +
# discovery via _on_back) instead of quitting the app. This also guards the
# re-join bug (MB5.4): every exit path runs the same clean teardown.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if is_inside_tree():
			_on_back()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and is_inside_tree():
		get_viewport().set_input_as_handled()
		_on_back()
