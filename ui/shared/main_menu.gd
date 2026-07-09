# main_menu.gd
# ----------------------------------------------------------------------------
# Project Nexus - Main Menu + Multiplayer Lobby (Phase 5, step 5.4; restructured
# in Phase G).
#
# The real entry point of the game. The Phase-G restructure groups the entries
# into the player-facing shape requested by the design:
#
#   Main panel:
#     - Single Player          -> start a skirmish (desktop/mobile UI)
#     - Multiplayer            -> opens the Multiplayer sub-panel
#         - Offline (local)    -> a local hot-seat / shared-device match
#         - Online             -> opens the Online sub-panel (Host / Join)
#     - Settings               -> options screen
#     - Mod Editor             -> graphical content editor
#     - Language / Quit        -> always available
#
# The online path wires the existing, fully-tested stack together with ZERO new
# game logic: NetworkSession owns an EnetTransport and the LockstepModule, so an
# online match runs the exact same deterministic simulation as a local one --
# only the transport differs (Phase 3/4 guarantee). When a session actually
# starts (EVENT_SESSION_STARTED), we hand off to the game scene.
#
# The menu never touches the simulation directly; it only starts/stops sessions
# and changes scenes. The chosen locale is stashed in WorldState.ui_prefs so the
# game scene can pick it up across the scene change (no extra autoload needed).
#
# CODE LANGUAGE POLICY: English-only identifiers/comments. All visible labels go
# through the Localization service (English keys -> localized display text).
# ----------------------------------------------------------------------------
extends Control

const DESKTOP_SCENE: String = "res://scenes/game_desktop.tscn"
const MOBILE_SCENE: String = "res://scenes/game_main.tscn"
const OPTIONS_SCENE: String = "res://scenes/options_menu.tscn"
const MOD_EDITOR_SCENE: String = "res://scenes/mod_editor.tscn"
const MAP_EDITOR_SCENE: String = "res://scenes/map_editor.tscn"
const CUSTOM_GAMES_SCENE: String = "res://scenes/custom_games.tscn"
# P4 (R3/R4/R5): the Save / Load + Export / Import screen.
const SAVE_LOAD_SCENE: String = "res://scenes/save_load_menu.tscn"
# P2.1: the Match Setup screen (choose map / difficulty / UI style) shown before
# a single-player or local match actually starts.
const MATCH_SETUP_SCENE: String = "res://scenes/match_setup.tscn"
# P5 (R6): the LAN multiplayer lobby (host slots / team / ready, or join browse).
const LOBBY_SCENE: String = "res://scenes/lobby.tscn"

# A fixed shared seed for online matches in this simple lobby. A richer lobby
# (Phase 6+) would negotiate this; here the host's seed is authoritative and
# every peer uses the same scenario, so the deterministic core does the rest.
const ONLINE_SEED: int = 0xC0FFEE

# The three navigable panels of the menu (one visible at a time).
enum MenuPanel { MAIN, MULTIPLAYER, ONLINE }

@onready var _title_label: Label = $Center/Box/Title
@onready var _status_label: Label = $Center/Box/Status
# MB2.3 (bug 8): "Settings" is no longer a row in the main list. It now lives as
# a gear button pinned to the TOP-RIGHT corner (anchored so it stays in the
# corner at every aspect ratio). The gear glyph is drawn procedurally at _ready
# so it needs no imported texture asset (and uses an RGBA8 image, avoiding the
# RGBAFloat conversion warning from bug 28).
@onready var _gear_button: Button = $GearButton

# --- Main panel -------------------------------------------------------------
@onready var _main_panel: VBoxContainer = $Center/Box/MainPanel
@onready var _single_button: Button = $Center/Box/MainPanel/SingleButton
@onready var _multiplayer_button: Button = $Center/Box/MainPanel/MultiplayerButton
@onready var _mod_editor_button: Button = $Center/Box/MainPanel/ModEditorButton
@onready var _map_editor_button: Button = $Center/Box/MainPanel/MapEditorButton
@onready var _custom_games_button: Button = $Center/Box/MainPanel/CustomGamesButton
@onready var _save_load_button: Button = $Center/Box/MainPanel/SaveLoadButton
@onready var _lang_button: Button = $Center/Box/MainPanel/LangButton
@onready var _quit_button: Button = $Center/Box/MainPanel/QuitButton

# --- Single-player sub-choice (desktop vs mobile UI) ------------------------
@onready var _single_panel: VBoxContainer = $Center/Box/SinglePanel
@onready var _single_desktop_button: Button = $Center/Box/SinglePanel/SingleDesktopButton
@onready var _single_mobile_button: Button = $Center/Box/SinglePanel/SingleMobileButton
@onready var _single_back_button: Button = $Center/Box/SinglePanel/SingleBackButton

# --- Multiplayer panel (offline / online) -----------------------------------
@onready var _mp_panel: VBoxContainer = $Center/Box/MultiplayerPanel
@onready var _mp_offline_button: Button = $Center/Box/MultiplayerPanel/OfflineButton
@onready var _mp_online_button: Button = $Center/Box/MultiplayerPanel/OnlineButton
@onready var _mp_back_button: Button = $Center/Box/MultiplayerPanel/MpBackButton

# --- Online panel (host / join) ---------------------------------------------
@onready var _online_panel: VBoxContainer = $Center/Box/OnlinePanel
@onready var _host_button: Button = $Center/Box/OnlinePanel/HostButton
@onready var _join_button: Button = $Center/Box/OnlinePanel/JoinButton
@onready var _address_edit: LineEdit = $Center/Box/OnlinePanel/AddressEdit
@onready var _online_back_button: Button = $Center/Box/OnlinePanel/OnlineBackButton

var _loc: Localization = Localization.new()
var _session: NetworkSession = null
var _next_scene: String = DESKTOP_SCENE
var _panel: int = MenuPanel.MAIN
# MB3.2 (bug 6): the main menu is the navigation ROOT. A BACK press while in a
# sub-panel returns to the MAIN panel; a BACK press already at MAIN must NOT quit
# instantly -- it arms a confirm and only the SECOND consecutive BACK quits.
var _quit_armed: bool = false


func _ready() -> void:
	_loc.load_all("res://localization")
	# Load persisted player settings (locale, style, GUI scale...) from disk so
	# the menu opens in the player's chosen language AND at the right size.
	var settings: GameSettings = GameSettings.new(Nexus.world_state)
	settings.load_from_file()
	# Phase G: apply the persisted GUI scale and keep it in sync on resize.
	UiScale.apply_with_settings(self, settings)
	get_viewport().size_changed.connect(_on_viewport_resized)
	var saved: String = _read_saved_locale()
	if saved != "":
		_loc.set_locale(saved)

	# Main panel.
	_single_button.pressed.connect(_on_single)
	_multiplayer_button.pressed.connect(func() -> void: _show_panel(MenuPanel.MULTIPLAYER))
	_gear_button.pressed.connect(_on_options)
	_setup_gear_icon()
	_mod_editor_button.pressed.connect(_on_mod_editor)
	_map_editor_button.pressed.connect(_on_map_editor)
	_custom_games_button.pressed.connect(_on_custom_games)
	_save_load_button.pressed.connect(_on_save_load)
	_lang_button.pressed.connect(_on_lang)
	_quit_button.pressed.connect(_on_quit)

	# Single-player sub-panel.
	_single_desktop_button.pressed.connect(_on_single_desktop)
	_single_mobile_button.pressed.connect(_on_single_mobile)
	_single_back_button.pressed.connect(func() -> void: _show_panel(MenuPanel.MAIN))

	# Multiplayer sub-panel.
	_mp_offline_button.pressed.connect(_on_offline)
	_mp_online_button.pressed.connect(func() -> void: _show_panel(MenuPanel.ONLINE))
	_mp_back_button.pressed.connect(func() -> void: _show_panel(MenuPanel.MAIN))

	# Online sub-panel.
	_host_button.pressed.connect(_on_host)
	_join_button.pressed.connect(_on_join)
	_online_back_button.pressed.connect(func() -> void: _show_panel(MenuPanel.MULTIPLAYER))

	_address_edit.placeholder_text = "127.0.0.1"
	_apply_labels()
	_show_panel(MenuPanel.MAIN)


func _on_viewport_resized() -> void:
	# Re-resolve the GUI scale when the window changes size (matters mostly in
	# auto mode, where the scale is derived from the current screen size).
	UiScale.apply_from_settings(self, Nexus.world_state)


func _apply_labels() -> void:
	_title_label.text = _loc.t("ui.menu.title")
	_status_label.text = ""
	# Main panel.
	_single_button.text = _loc.t("ui.menu.single")
	_multiplayer_button.text = _loc.t("ui.menu.multiplayer")
	# MB2.3 (bug 8): the gear carries no text label (icon only) but exposes a
	# localized tooltip so its purpose stays discoverable.
	_gear_button.tooltip_text = _loc.t("ui.menu.settings_gear")
	_mod_editor_button.text = _loc.t("ui.menu.mod_editor")
	_map_editor_button.text = _loc.t("ui.menu.map_editor")
	_custom_games_button.text = _loc.t("ui.menu.custom_games")
	_save_load_button.text = _loc.t("ui.menu.save_load")
	_lang_button.text = "%s: %s" % [_loc.t("ui.game.language"), _loc.active_locale()]
	_quit_button.text = _loc.t("ui.menu.quit")
	# Single-player sub-panel.
	_single_desktop_button.text = _loc.t("ui.menu.single_desktop")
	_single_mobile_button.text = _loc.t("ui.menu.single_mobile")
	_single_back_button.text = _loc.t("ui.menu.back")
	# Multiplayer sub-panel.
	_mp_offline_button.text = _loc.t("ui.menu.mp_offline")
	_mp_online_button.text = _loc.t("ui.menu.mp_online")
	_mp_back_button.text = _loc.t("ui.menu.back")
	# Online sub-panel.
	_host_button.text = _loc.t("ui.net.host")
	_join_button.text = _loc.t("ui.net.join")
	_online_back_button.text = _loc.t("ui.menu.back")


# --- Panel navigation -------------------------------------------------------

func _show_panel(panel: int) -> void:
	_panel = panel
	_main_panel.visible = (panel == MenuPanel.MAIN)
	_single_panel.visible = false
	_mp_panel.visible = (panel == MenuPanel.MULTIPLAYER)
	_online_panel.visible = (panel == MenuPanel.ONLINE)
	# The single-player UI sub-choice is a separate transient panel reached only
	# via _on_single (so it never shows alongside the others).
	if panel == MenuPanel.MAIN:
		_status_label.text = ""


# --- Single-player ----------------------------------------------------------

func _on_single() -> void:
	# P2.1: go to the Match Setup screen where the player picks map / difficulty /
	# UI style before the skirmish is built. (The old desktop/mobile sub-panel is
	# now folded into that screen's "UI style" option.)
	# MA7.4: clear any lingering purpose (host/hotseat) so single-player opens with
	# its own solo defaults even if the player previously visited another path.
	_store_locale()
	Nexus.world_state.get_section("ui_prefs")["setup_purpose"] = ""
	get_tree().change_scene_to_file(MATCH_SETUP_SCENE)


func _on_single_desktop() -> void:
	_store_locale()
	get_tree().change_scene_to_file(DESKTOP_SCENE)


func _on_single_mobile() -> void:
	_store_locale()
	get_tree().change_scene_to_file(MOBILE_SCENE)


# --- Multiplayer: offline (local) -------------------------------------------

func _on_offline() -> void:
	# MA7.4 (B8): a local hot-seat / shared-device match is now a DISTINCT path,
	# not a silent alias of single-player. It runs the very same deterministic
	# core (so no new game logic) but Match Setup detects the "hotseat" intent and
	# opens with a hot-seat title + sensible defaults (>=2 humans, 0 AIs) and
	# stamps match_config.hot_seat = true so the game scene knows this is a shared-
	# device multiplayer session rather than a solo skirmish.
	_store_locale()
	var prefs: Dictionary = Nexus.world_state.get_section("ui_prefs")
	prefs["setup_purpose"] = "hotseat"
	get_tree().change_scene_to_file(MATCH_SETUP_SCENE)


# --- Multiplayer: online (host / join) --------------------------------------

func _ensure_session() -> void:
	if _session != null:
		return
	# The multiplayer (lockstep) module lives on the Nexus autoload; make sure the
	# base modules exist so NetworkSession can find "multiplayer".
	GameBootstrap.register_modules(Nexus)
	_session = NetworkSession.new()
	_session.name = "NetworkSession"
	add_child(_session)
	_session.setup(Nexus)
	Nexus.subscribe(NetworkSession.EVENT_SESSION_STARTED, self, "_on_session_started")
	Nexus.subscribe(EnetTransport.EVENT_CONNECTION_FAILED, self, "_on_connection_failed")
	Nexus.subscribe(EnetTransport.EVENT_SERVER_DISCONNECTED, self, "_on_server_disconnected")


func _on_host() -> void:
	# P5 (R6.1): hosting first goes through Match Setup (map / players / mode) and
	# then into the LAN lobby, where the host sees player slots, assigns teams, and
	# starts once everyone is ready. We stash the intent so Match Setup's final
	# button reads "Host" and routes to the lobby instead of straight into a match.
	_store_locale()
	var prefs: Dictionary = Nexus.world_state.get_section("ui_prefs")
	prefs["setup_purpose"] = "host"
	get_tree().change_scene_to_file(MATCH_SETUP_SCENE)


func _on_join() -> void:
	# P5 (R6.2): joining opens the lobby in "join" mode, which browses the LAN for
	# hosted matches (search box + magnifier) and connects on click -- no IP typing.
	_store_locale()
	var prefs: Dictionary = Nexus.world_state.get_section("ui_prefs")
	prefs["lobby_role"] = "join"
	prefs["lobby_game_scene"] = MOBILE_SCENE
	get_tree().change_scene_to_file(LOBBY_SCENE)


func _on_session_started(_event_name: String, payload: Dictionary) -> void:
	# The deterministic lockstep session is live across all peers; hand off to the
	# game. The seed has already been written to WorldState by NetworkSession.
	_status_label.text = _loc.t("ui.net.connected")
	# Build the actual match on top of the agreed seed, then enter the game scene.
	var seed_value: int = int(payload.get("seed", ONLINE_SEED))
	Nexus.world_state.random_seed = seed_value
	get_tree().change_scene_to_file(_next_scene)


func _on_connection_failed(_event_name: String, _payload: Dictionary) -> void:
	_status_label.text = _loc.t("ui.net.disconnected")
	_set_buttons_enabled(true)


func _on_server_disconnected(_event_name: String, _payload: Dictionary) -> void:
	_status_label.text = _loc.t("ui.net.disconnected")
	_set_buttons_enabled(true)


# --- Language + quit --------------------------------------------------------

func _on_lang() -> void:
	_loc.cycle_locale()
	_apply_labels()


func _on_options() -> void:
	_store_locale()
	get_tree().change_scene_to_file(OPTIONS_SCENE)


func _on_mod_editor() -> void:
	_store_locale()
	get_tree().change_scene_to_file(MOD_EDITOR_SCENE)


func _on_map_editor() -> void:
	_store_locale()
	get_tree().change_scene_to_file(MAP_EDITOR_SCENE)


func _on_custom_games() -> void:
	_store_locale()
	get_tree().change_scene_to_file(CUSTOM_GAMES_SCENE)


func _on_save_load() -> void:
	_store_locale()
	get_tree().change_scene_to_file(SAVE_LOAD_SCENE)


func _on_quit() -> void:
	get_tree().quit()


# --- MB3.2 (bug 6): Android BACK key / ui_cancel ---------------------------
#
# The Android hardware/gesture BACK button arrives as
# NOTIFICATION_WM_GO_BACK_REQUEST; ESC / gamepad-B arrive as the "ui_cancel"
# action. On the main menu (the navigation root) BACK must never quit the app
# outright. Instead:
#   * in a sub-panel (single / multiplayer / online) -> return to its parent
#     panel, mirroring the on-screen "Back" buttons;
#   * already at the MAIN panel -> arm a confirm and show a hint; only a SECOND
#     consecutive BACK actually quits.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and is_inside_tree():
		_go_back()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and is_inside_tree():
		get_viewport().set_input_as_handled()
		_go_back()


func _go_back() -> void:
	# The single-player UI sub-choice is a transient panel: treat its BACK the
	# same as its own "Back" button (return to MAIN).
	if _single_panel.visible:
		_quit_armed = false
		_show_panel(MenuPanel.MAIN)
		return
	match _panel:
		MenuPanel.ONLINE:
			_quit_armed = false
			_show_panel(MenuPanel.MULTIPLAYER)
		MenuPanel.MULTIPLAYER:
			_quit_armed = false
			_show_panel(MenuPanel.MAIN)
		_:
			# At the root MAIN panel: confirm before quitting (press BACK twice).
			if _quit_armed:
				_on_quit()
			else:
				_quit_armed = true
				_status_label.text = _loc.t("ui.menu.confirm_quit")


# --- MB2.3 (bug 8): procedural gear icon ------------------------------------
#
# Draw a simple gear glyph into an RGBA8 image and hand it to the button as an
# icon (no imported texture asset needed, so nothing to break in an exported
# build). RGBA8 is GL-Compatibility friendly, so this never triggers the
# "RGBAFloat not supported" conversion warning (bug 28).
func _setup_gear_icon() -> void:
	var size: int = 40
	var img: Image = Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cx: float = float(size) * 0.5
	var cy: float = float(size) * 0.5
	var r_outer: float = float(size) * 0.42
	var r_inner: float = float(size) * 0.30
	var r_hole: float = float(size) * 0.13
	var teeth: int = 8
	var gear_color: Color = Color(0.882353, 0.745098, 0.341176, 1)
	for y in range(size):
		for x in range(size):
			var dx: float = float(x) - cx + 0.5
			var dy: float = float(y) - cy + 0.5
			var dist: float = sqrt(dx * dx + dy * dy)
			if dist <= r_hole:
				continue
			# Teeth: modulate the effective outer radius by the angle so the rim
			# alternates between r_outer (tooth) and r_inner (gap).
			var ang: float = atan2(dy, dx)
			var wave: float = cos(ang * float(teeth))
			var rim: float = r_inner
			if wave > 0.0:
				rim = r_outer
			if dist <= rim:
				img.set_pixel(x, y, gear_color)
	var tex: ImageTexture = ImageTexture.create_from_image(img)
	_gear_button.icon = tex
	# Icon-only button: hide the placeholder "*" glyph baked into the scene.
	_gear_button.text = ""
	_gear_button.expand_icon = true


# --- Helpers ----------------------------------------------------------------

func _set_buttons_enabled(enabled: bool) -> void:
	_host_button.disabled = not enabled
	_join_button.disabled = not enabled
	_online_back_button.disabled = not enabled


# Persist the chosen locale into a UI-only WorldState section so the game scene
# (a different scene) can read it without an extra autoload singleton.
func _store_locale() -> void:
	Nexus.world_state.get_section("ui_prefs")["locale"] = _loc.active_locale()


func _read_saved_locale() -> String:
	return str(Nexus.world_state.get_section("ui_prefs").get("locale", ""))
