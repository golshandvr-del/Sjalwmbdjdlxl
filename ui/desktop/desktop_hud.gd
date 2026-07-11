# desktop_hud.gd
# ----------------------------------------------------------------------------
# Project Nexus - Desktop Game HUD + Input (Phase 5, step 5.3).
#
# The keyboard + mouse counterpart to ui/mobile/game_hud.gd. It drives the SAME
# simulation through the SAME commands (Logic/Render Separation): it only READS
# world state to show numbers and turns desktop input into COMMANDS via the
# Nexus. It never mutates the simulation directly.
#
# Desktop input model:
#   - Left click on a friendly unit   -> select it (single).
#   - Left click + drag                -> box-select all friendly units inside.
#   - Shift + left click               -> add/remove a unit from the selection.
#   - Right click on ground            -> MOVE the selection there.
#   - WASD / arrow keys                -> pan the camera.
#   - Mouse wheel                      -> zoom in / out.
#   - Hotkeys: Space=Pause, B=Build, R=Research, U=Upgrade HQ, F=Fuse,
#              Tab=cycle Speed, V=toggle render style, L=cycle language.
#
# Because every action becomes a CommandQueue command, the desktop UI is fully
# compatible with lockstep multiplayer exactly like the mobile UI.
#
# CODE LANGUAGE POLICY: English-only identifiers/comments. All visible labels go
# through the Localization service (English keys -> localized text).
# ----------------------------------------------------------------------------
extends Control

const LOCAL_PLAYER: int = 0

# Camera pan speed in pixels per second (scaled by zoom).
const PAN_SPEED: float = 600.0
# Trackpad two-finger pan gestures deliver a small normalised delta; scale it up
# so a comfortable swipe moves the map a useful distance.
const GESTURE_PAN_SPEED: float = 40.0
# Zoom limits/steps are owned by RenderAdapter.zoom_by (anchored zoom); the HUD
# just requests a zoom factor around the cursor.

@onready var _render_adapter: RenderAdapter = $WorldLayer/RenderAdapter
@onready var _resource_label: Label = $TopBar/Margin/Row/ResourceLabel
@onready var _status_label: Label = $TopBar/Margin/Row/StatusLabel
@onready var _hint_label: Label = $TopBar/Margin/Row/HintLabel
@onready var _pause_button: Button = $BottomBar/Margin/Row/PauseButton
@onready var _build_button: Button = $BottomBar/Margin/Row/BuildButton
@onready var _speed_button: Button = $BottomBar/Margin/Row/SpeedButton
@onready var _research_button: Button = $BottomBar/Margin/Row/ResearchButton
@onready var _upgrade_button: Button = $BottomBar/Margin/Row/UpgradeButton
@onready var _fuse_button: Button = $BottomBar/Margin/Row/FuseButton
@onready var _style_button: Button = $BottomBar/Margin/Row/StyleButton
@onready var _lang_button: Button = $BottomBar/Margin/Row/LangButton
@onready var _menu_button: Button = $BottomBar/Margin/Row/MenuButton
@onready var _selection_box: ColorRect = $SelectionBox
@onready var _overlay: ColorRect = $EndOverlay
@onready var _overlay_label: Label = $EndOverlay/CenterContainer/Box/ResultLabel
@onready var _restart_button: Button = $EndOverlay/CenterContainer/Box/RestartButton
@onready var _menu_overlay_button: Button = $EndOverlay/CenterContainer/Box/MenuButton

var _loc: Localization = Localization.new()
var _selected_unit_ids: Array = []
var _local_hq_id: int = -1

# Box-select drag state.
var _dragging: bool = false
var _drag_start: Vector2 = Vector2.ZERO

# MC1.5 (request 1): two-mode movement shared with the mobile HUD via the pure
# MoveModeUtil. DIRECT = right-click issues an immediate belief-aware move;
# MANUAL = right-clicks accumulate an ordered waypoint route that a "confirm"
# (Enter) commits as one move_unit, and "cancel" (Escape) discards. The toggle
# lives on a programmatically-built button (M hotkey) so the desktop and mobile
# HUDs never diverge and the exact logic is unit-tested headlessly.
var _move_mode: MoveModeUtil = MoveModeUtil.new()
var _move_mode_button: Button = null


func _ready() -> void:
	# Phase G: apply the persisted GUI scale so the desktop HUD matches Options.
	UiScale.apply_from_settings(self, Nexus.world_state)
	_loc.load_all("res://localization")
	# Honour a locale chosen on the main menu, if any.
	var chosen: String = str(_get_meta_locale())
	if chosen != "":
		_loc.set_locale(chosen)

	Nexus.event_bus.set_log_enabled(true)
	GameBootstrap.setup_skirmish()
	_local_hq_id = _find_local_hq()
	_render_adapter.fog_viewer = LOCAL_PLAYER
	# Phase A.2: fit the whole map to the viewport first (fixes the tiny-map bug),
	# then bias the camera toward the local HQ.
	_render_adapter.fit_map_to_viewport(get_viewport_rect().size)
	var hq: Dictionary = Nexus.get_module("buildings").get_building(_local_hq_id)
	if not hq.is_empty():
		_render_adapter.center_camera_on(Vector2i(int(hq["x"]), int(hq["y"])), get_viewport_rect().size)
		_render_adapter.fit_map_to_viewport(get_viewport_rect().size)
	# Phase A.3: re-fit on resize (window resize / fullscreen toggle).
	get_viewport().size_changed.connect(_on_viewport_resized)

	_pause_button.pressed.connect(_on_pause_pressed)
	_build_button.pressed.connect(_on_build_pressed)
	_speed_button.pressed.connect(_on_speed_pressed)
	_research_button.pressed.connect(_on_research_pressed)
	_upgrade_button.pressed.connect(_on_upgrade_pressed)
	_fuse_button.pressed.connect(_on_fuse_pressed)
	_style_button.pressed.connect(_on_style_pressed)
	_lang_button.pressed.connect(_on_lang_pressed)
	_menu_button.pressed.connect(_on_menu_pressed)
	_restart_button.pressed.connect(_on_restart_pressed)
	_menu_overlay_button.pressed.connect(_on_menu_pressed)

	Nexus.subscribe(VictoryModule.EVENT_MATCH_OVER, self, "_on_match_over")
	_overlay.visible = false
	_selection_box.visible = false
	_build_move_mode_widget()
	_apply_static_labels()


# MC1.5 (request 1): a toggle button in the bottom Row to flip DIRECT/MANUAL move
# mode. Confirm (Enter) and cancel (Escape) are keyboard-driven on desktop, so a
# single toggle button suffices; its label shows the pending-waypoint count in
# MANUAL mode. Built programmatically so the scene file needs no change.
func _build_move_mode_widget() -> void:
	_move_mode_button = Button.new()
	_move_mode_button.name = "MoveModeButton"
	_move_mode_button.toggle_mode = true
	_move_mode_button.tooltip_text = _loc.t("ui.move.toggle_hint")
	_move_mode_button.pressed.connect(_on_move_mode_pressed)
	var row: Node = get_node_or_null("BottomBar/Margin/Row")
	if row != null:
		row.add_child(_move_mode_button)
	else:
		add_child(_move_mode_button)
	_update_move_mode_button()


func _process(delta: float) -> void:
	_render_adapter.selected_unit_ids = _selected_unit_ids
	_handle_camera_pan(delta)
	_refresh_top_bar()


# Phase A.3: keep the whole map fitted when the window is resized.
func _on_viewport_resized() -> void:
	if _render_adapter != null:
		_render_adapter.fit_map_to_viewport(get_viewport_rect().size)


# --- Localized static labels ------------------------------------------------

func _apply_static_labels() -> void:
	_build_button.text = _loc.t("ui.game.build_soldier")
	_research_button.text = _loc.t("ui.game.research")
	_upgrade_button.text = _loc.t("ui.game.upgrade_hq")
	_fuse_button.text = _loc.t("ui.game.fuse_hero")
	_menu_button.text = _loc.t("ui.menu.title")
	_menu_overlay_button.text = _loc.t("ui.menu.title")
	_restart_button.text = _loc.t("ui.game.play_again")
	_lang_button.text = "%s: %s" % [_loc.t("ui.game.language"), _loc.active_locale()]
	_hint_label.text = _loc.t("ui.game.desktop_hint")


func _refresh_top_bar() -> void:
	var economy: Object = Nexus.get_module("economy")
	var gold: int = economy.get_resource(LOCAL_PLAYER, "resource_basic") if economy != null else 0
	_resource_label.text = "%s: %d" % [_loc.t("ui.game.resources"), gold]
	var paused: bool = Nexus.sim_clock.is_paused()
	var units: int = Nexus.get_module("units").count()
	var tech: Object = Nexus.get_module("tech_tree")
	var researched: int = 0
	if tech != null:
		tech.ensure_player(LOCAL_PLAYER)
		researched = (Nexus.world_state.get_section("tech").get("players", {})
			.get(str(LOCAL_PLAYER), {}).get("researched", []) as Array).size()
	_status_label.text = "%s   |   Tick: %d   |   %s: %d   |   %s: %d   |   %s: %d" % [
		_loc.t("ui.game.paused") if paused else _loc.t("ui.game.running"),
		Nexus.world_state.current_tick,
		_loc.t("unit.soldier.name"), units,
		_loc.t("ui.game.selected"), _selected_unit_ids.size(),
		_loc.t("ui.game.tech"), researched,
	]
	_pause_button.text = _loc.t("ui.game.resume") if paused else _loc.t("ui.game.pause")
	_speed_button.text = "%s x%.0f" % [_loc.t("ui.game.speed"), Nexus.sim_clock.time_scale]
	_fuse_button.disabled = _selected_unit_ids.is_empty()


# --- Keyboard input ---------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE:
				_on_pause_pressed()
			KEY_B:
				_on_build_pressed()
			KEY_R:
				_on_research_pressed()
			KEY_U:
				_on_upgrade_pressed()
			KEY_F:
				_on_fuse_pressed()
			KEY_TAB:
				_on_speed_pressed()
			KEY_V:
				_on_style_pressed()
			KEY_L:
				_on_lang_pressed()
			KEY_M:
				# MC1.5 (request 1): toggle DIRECT <-> MANUAL move mode.
				_on_move_mode_pressed()
			KEY_ENTER, KEY_KP_ENTER:
				# MC1.5: commit the plotted MANUAL waypoint route.
				_on_move_confirm()
			KEY_ESCAPE:
				# MC1.5: a pending route is cancelled first; otherwise clear the
				# selection (the long-standing Escape behaviour).
				if _move_mode.has_pending():
					_on_move_cancel()
				else:
					_selected_unit_ids.clear()
					_push_selection()


func _handle_camera_pan(delta: float) -> void:
	var pan: Vector2 = Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		pan.x += 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		pan.x -= 1.0
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		pan.y += 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		pan.y -= 1.0
	if pan != Vector2.ZERO:
		_render_adapter.camera_offset += pan.normalized() * PAN_SPEED * delta


# --- Mouse input ------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	# Trackpad two-finger pinch = zoom (a gesture, NOT two mouse events), anchored
	# under the gesture point. Without this, "two-finger zoom" did nothing on
	# laptops/desktops. factor > 1 spreads (in), < 1 pinches (out).
	if event is InputEventMagnifyGesture:
		_render_adapter.zoom_at(event.factor, event.position)
		_render_adapter.clamp_camera(get_viewport_rect().size)
		accept_event()
		return
	# Trackpad two-finger scroll = pan.
	if event is InputEventPanGesture:
		_render_adapter.pan_by_screen(-event.delta * GESTURE_PAN_SPEED)
		_render_adapter.clamp_camera(get_viewport_rect().size)
		accept_event()
		return
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion and _dragging:
		_update_selection_box(event.position)


func _handle_mouse_button(event: InputEventMouseButton) -> void:
	# BUG-4/BUG-5: zoom around the CURSOR (anchored) via zoom_at, which converts
	# the raw event position into canvas space through content_scale_factor. The
	# old code multiplied by get_global_transform_with_canvas() (identity under
	# the canvas_items stretch mode), so the anchor drifted on scaled windows.
	if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
		_render_adapter.zoom_at(1.15, event.position)
		_render_adapter.clamp_camera(get_viewport_rect().size)
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
		_render_adapter.zoom_at(1.0 / 1.15, event.position)
		_render_adapter.clamp_camera(get_viewport_rect().size)
	elif event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = true
			_drag_start = event.position
			_selection_box.visible = false
		else:
			_dragging = false
			_finish_drag(event.position, event.shift_pressed)
	elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_issue_move(event.position)


func _update_selection_box(current: Vector2) -> void:
	var top_left: Vector2 = Vector2(minf(_drag_start.x, current.x), minf(_drag_start.y, current.y))
	var size: Vector2 = (current - _drag_start).abs()
	# Only show the box once the drag is meaningfully large (else it is a click).
	if size.length() < 6.0:
		_selection_box.visible = false
		return
	_selection_box.visible = true
	_selection_box.position = top_left
	_selection_box.size = size


func _finish_drag(release_pos: Vector2, additive: bool) -> void:
	_selection_box.visible = false
	var drag_size: Vector2 = (release_pos - _drag_start).abs()
	if drag_size.length() < 6.0:
		# It was a click, not a drag: single-select / toggle the unit under it.
		_click_select(release_pos, additive)
		return
	# Box-select every friendly unit whose tile falls inside the rectangle.
	var top_left_tile: Vector2i = _render_adapter.screen_to_tile(Vector2(
		minf(_drag_start.x, release_pos.x), minf(_drag_start.y, release_pos.y)))
	var bottom_right_tile: Vector2i = _render_adapter.screen_to_tile(Vector2(
		maxf(_drag_start.x, release_pos.x), maxf(_drag_start.y, release_pos.y)))
	if not additive:
		_selected_unit_ids.clear()
	var units: Dictionary = Nexus.world_state.get_section("units").get("list", {})
	# MB1.2 (bug 1 - teammate control leak): only sweep locally controllable owners.
	var owners: Array = _locally_controlled_owners()
	var keys: Array = units.keys()
	keys.sort()
	for key in keys:
		var u: Dictionary = units[key]
		if not owners.has(int(u.get("owner", -1))):
			continue
		var ux: int = int(u["x"])
		var uy: int = int(u["y"])
		if ux >= top_left_tile.x and ux <= bottom_right_tile.x and uy >= top_left_tile.y and uy <= bottom_right_tile.y:
			var uid: int = int(u["id"])
			if not _selected_unit_ids.has(uid):
				_selected_unit_ids.append(uid)
	_push_selection()


func _click_select(screen_pos: Vector2, additive: bool) -> void:
	var tile: Vector2i = _render_adapter.screen_to_tile(screen_pos)
	var tapped_unit: int = _unit_at_tile(tile, LOCAL_PLAYER)
	if tapped_unit == -1:
		if not additive:
			_selected_unit_ids.clear()
			_push_selection()
		return
	if additive:
		if _selected_unit_ids.has(tapped_unit):
			_selected_unit_ids.erase(tapped_unit)
		else:
			_selected_unit_ids.append(tapped_unit)
	else:
		_selected_unit_ids = [tapped_unit]
	_push_selection()


func _issue_move(screen_pos: Vector2) -> void:
	if _selected_unit_ids.is_empty():
		return
	var tile: Vector2i = _render_adapter.screen_to_tile(screen_pos)
	# MC1.5 (request 1): route the right-click through MoveModeUtil so DIRECT vs
	# MANUAL is decided by the shared pure state machine. In DIRECT mode this
	# issues the immediate single-goal move exactly as before; in MANUAL mode it
	# only buffers a waypoint (no command yet) until the player confirms.
	var plan: Dictionary = _move_mode.resolve_ground_tap(tile, not _selected_unit_ids.is_empty())
	match str(plan.get("action", MoveModeUtil.ACTION_NONE)):
		MoveModeUtil.ACTION_MOVE_DIRECT:
			# Simulation command -> lockstep when networked (MA7.1), immediate otherwise.
			Nexus.player_command("move_unit", {
				"unit_ids": _selected_unit_ids.duplicate(),
				"x": tile.x,
				"y": tile.y,
			}, 1)
		MoveModeUtil.ACTION_ADD_WAYPOINT:
			# Buffered a waypoint; reflect the pending route on the toggle button.
			_update_move_mode_button()


# MC1.5 (request 1): toggle DIRECT <-> MANUAL. Switching away from manual clears
# any half-drawn route (handled inside MoveModeUtil.set_mode).
func _on_move_mode_pressed() -> void:
	_move_mode.toggle_mode()
	_update_move_mode_button()


# Commit the plotted MANUAL route: issue ONE move_unit carrying the whole waypoint
# array so units_module stitches an exact belief-aware path (WaypointUtil).
func _on_move_confirm() -> void:
	var plan: Dictionary = _move_mode.commit()
	if str(plan.get("action", "")) == MoveModeUtil.ACTION_MOVE_PATH and not _selected_unit_ids.is_empty():
		Nexus.player_command("move_unit", {
			"unit_ids": _selected_unit_ids.duplicate(),
			"waypoints": plan.get("waypoints", []),
		}, 1)
	_update_move_mode_button()


# Cancel the pending MANUAL route without moving.
func _on_move_cancel() -> void:
	_move_mode.cancel()
	_update_move_mode_button()


# Reflect the current mode + pending route on the toggle button label.
func _update_move_mode_button() -> void:
	if _move_mode_button == null:
		return
	_move_mode_button.button_pressed = _move_mode.is_manual()
	var mode_key: String = "ui.move.mode_manual" if _move_mode.is_manual() else "ui.move.mode_direct"
	var label: String = _loc.t(mode_key)
	if _move_mode.is_manual() and _move_mode.has_pending():
		label += " (%d)" % _move_mode.waypoints().size()
	_move_mode_button.text = label


func _push_selection() -> void:
	Nexus.issue_command("select_units", LOCAL_PLAYER, {
		"owner": LOCAL_PLAYER,
		"unit_ids": _selected_unit_ids.duplicate(),
	}, 1)


# --- Buttons (shared command logic with the mobile HUD) ---------------------

func _on_pause_pressed() -> void:
	Nexus.toggle_pause()


func _on_build_pressed() -> void:
	Nexus.player_command("build_unit", {
		"owner": LOCAL_PLAYER,
		"building_id": _local_hq_id,
		"unit_type": "soldier",
	}, 1)


func _on_speed_pressed() -> void:
	var s: float = Nexus.sim_clock.time_scale
	if s >= 4.0:
		Nexus.sim_clock.time_scale = 1.0
	else:
		Nexus.sim_clock.time_scale = s * 2.0


func _on_research_pressed() -> void:
	var tech: Object = Nexus.get_module("tech_tree")
	if tech == null:
		return
	var node_id: String = _next_research_node(tech)
	if node_id == "":
		return
	Nexus.player_command("research_tech", {
		"owner": LOCAL_PLAYER,
		"node_id": node_id,
	}, 1)


func _on_upgrade_pressed() -> void:
	Nexus.player_command("upgrade_building", {
		"building_id": _local_hq_id,
	}, 1)


func _on_fuse_pressed() -> void:
	if _selected_unit_ids.is_empty():
		return
	Nexus.player_command("fuse_units", {
		"owner": LOCAL_PLAYER,
		"unit_ids": _selected_unit_ids.duplicate(),
	}, 1)


func _on_style_pressed() -> void:
	var active: String = _render_adapter.toggle_style()
	var label: String = _loc.t("ui.game.style_detailed") if active == RenderAdapter.STYLE_DETAILED else _loc.t("ui.game.style_simple")
	_style_button.text = "%s: %s" % [_loc.t("ui.game.style"), label]


func _on_lang_pressed() -> void:
	var locale: String = _loc.cycle_locale()
	_apply_static_labels()
	_lang_button.text = "%s: %s" % [_loc.t("ui.game.language"), locale]


func _on_menu_pressed() -> void:
	Nexus.shutdown_simulation()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _on_restart_pressed() -> void:
	Nexus.shutdown_simulation()
	get_tree().reload_current_scene()


# --- Match end --------------------------------------------------------------

func _on_match_over(_event_name: String, payload: Dictionary) -> void:
	var winner: int = int(payload.get("winner", -1))
	var text: String = ""
	if winner == LOCAL_PLAYER:
		text = _loc.t("ui.game.victory")
	elif winner < 0:
		text = "DRAW"
	else:
		text = _loc.t("ui.game.defeat")
	_overlay_label.text = text
	_overlay.visible = true
	Nexus.sim_clock.pause()


# --- Helpers ----------------------------------------------------------------

func _next_research_node(tech: Object) -> String:
	var catalog: Dictionary = Nexus.data_loader.get_catalog("tech")
	var tree_ids: Array = catalog.keys()
	tree_ids.sort()
	for tree_id in tree_ids:
		var tree: Dictionary = catalog[tree_id]
		for node in tree.get("nodes", []):
			var node_id: String = str(node.get("id", ""))
			if node_id != "" and tech.research_blocked_reason(LOCAL_PLAYER, node_id) == "":
				return node_id
	return ""


func _unit_at_tile(tile: Vector2i, owner_filter: int) -> int:
	# MB1.2 (bug 1 - teammate control leak): gate through the locally controllable
	# owner set (single source of truth Nexus.is_locally_controlled) so an AI
	# teammate's unit is never selectable. owner_filter kept for compatibility.
	var units: Dictionary = Nexus.world_state.get_section("units").get("list", {})
	return TapSelectUtil.unit_at_tile_owned_by(units, tile, _locally_controlled_owners())


# MB1.2 (bug 1): owner ids the human at THIS device may command, derived from
# Nexus.is_locally_controlled. Parallels the mobile HUD helper so both agree.
func _locally_controlled_owners() -> Array:
	var owners: Array = []
	var units: Dictionary = Nexus.world_state.get_section("units").get("list", {})
	for key in units.keys():
		var owner: int = int((units[key] as Dictionary).get("owner", -1))
		if owner >= 0 and not owners.has(owner) and Nexus.is_locally_controlled(owner):
			owners.append(owner)
	if owners.is_empty() and Nexus.is_locally_controlled(LOCAL_PLAYER):
		owners.append(LOCAL_PLAYER)
	owners.sort()
	return owners


func _find_local_hq() -> int:
	var buildings: Dictionary = Nexus.world_state.get_section("buildings").get("list", {})
	var keys: Array = buildings.keys()
	keys.sort()
	for key in keys:
		var b: Dictionary = buildings[key]
		if int(b["owner"]) == LOCAL_PLAYER:
			return int(b["id"])
	return -1


# Read a locale chosen on the main menu (stored on the Nexus world state under a
# UI-only meta section, so it survives the scene change without an autoload).
func _get_meta_locale() -> String:
	if not _has_nexus():
		return ""
	var ui: Dictionary = Nexus.world_state.get_section("ui_prefs")
	return str(ui.get("locale", ""))


func _has_nexus() -> bool:
	return get_node_or_null("/root/Nexus") != null
