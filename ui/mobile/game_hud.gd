# game_hud.gd
# ----------------------------------------------------------------------------
# Project Nexus - Mobile Game HUD + Input (Phase 1, steps 1.11 + 1.12).
#
# The touch-friendly single-player UI for the simple skirmish. It is pure
# presentation + input: it READS world state to show numbers and it turns
# player taps into COMMANDS through the Nexus. It never mutates the simulation
# directly (Logic/Render Separation + Active Pause readiness).
#
# Input model (finger-friendly):
#   - Tap a friendly unit            -> select it (multi-tap adds to selection).
#   - Tap empty ground (with sel.)   -> issue a MOVE command for the selection.
#   - "Build Soldier" button         -> issue a BUILD_UNIT command at your HQ.
#   - "Pause" button                 -> Active Pause (commands still queue).
#
# Phase 2 (Strategic Depth) controls:
#   - "Research" button   -> research the next affordable tech node.
#   - "Upgrade HQ" button -> queue the next HQ upgrade level (paid + timed).
#   - "Fuse Hero" button  -> fuse the selected squad into a hero (recipe-based).
# The HUD also drives fog of war: the RenderAdapter's fog_viewer is set to the
# local player so enemies stay hidden until scouted.
#
# All commands flow through Nexus.issue_command(), so they are queued in the
# CommandQueue and run deterministically on a tick -- exactly what lockstep
# multiplayer (Phase 4) will reuse.
#
# CODE LANGUAGE POLICY: English-only identifiers/comments.
# ----------------------------------------------------------------------------
extends Control

const LOCAL_PLAYER: int = 0

@onready var _render_adapter: RenderAdapter = $WorldLayer/RenderAdapter
@onready var _resource_label: Label = $TopBar/Margin/Row/ResourceLabel
@onready var _status_label: Label = $TopBar/Margin/Row/StatusLabel
@onready var _pause_button: Button = $BottomBar/Margin/Row/PauseButton
@onready var _build_button: Button = $BottomBar/Margin/Row/BuildButton
@onready var _speed_button: Button = $BottomBar/Margin/Row/SpeedButton
@onready var _research_button: Button = $BottomBar/Margin/Row/ResearchButton
@onready var _upgrade_button: Button = $BottomBar/Margin/Row/UpgradeButton
@onready var _fuse_button: Button = $BottomBar/Margin/Row/FuseButton
@onready var _style_button: Button = $BottomBar/Margin/Row/StyleButton
@onready var _overlay: ColorRect = $EndOverlay
@onready var _overlay_label: Label = $EndOverlay/CenterContainer/Box/ResultLabel
@onready var _restart_button: Button = $EndOverlay/CenterContainer/Box/RestartButton

var _selected_unit_ids: Array = []
var _local_hq_id: int = -1

# BUG-4 (P3.1): interactive touch camera state (pan + pinch-zoom). These are
# pure presentation; they only move the RenderAdapter camera, never WorldState.
var _active_touches: Dictionary = {}   # touch index -> last position (Vector2)
var _is_panning: bool = false
var _pan_last: Vector2 = Vector2.ZERO
var _pinch_last_dist: float = 0.0
var _press_start: Vector2 = Vector2.ZERO
var _press_moved: bool = false
const _DRAG_THRESHOLD: float = 12.0    # px before a press becomes a pan, not a tap
# Trackpad two-finger pan gestures deliver a small normalised delta; scale it up
# so a comfortable swipe moves the map a useful distance.
const _GESTURE_PAN_SPEED: float = 40.0

# P3.2 (R11): control groups. 9 slots (a 3x3 corner grid). Each slot stores a
# saved list of unit ids. A short tap RECALLS the group (selects it + centres
# the camera on it); the "Assign" toggle turns a tap into ASSIGN (store the
# current selection into that slot). Presentation-only: recall just re-issues a
# normal select_units command, so the simulation stays authoritative.
var _control_groups: Array = [[], [], [], [], [], [], [], [], []]
var _assign_mode: bool = false
var _group_buttons: Array = []
var _assign_button: Button = null
var _minimap: Control = null

# MA2 (Android): box / drag selection on touch. When _select_mode is ON a
# single-finger drag draws a selection rectangle (instead of panning the camera)
# and, on release, selects every friendly unit whose tile falls inside it. A
# toggle button flips the mode; a translucent ColorRect ("SelectionBox") shows
# the live rectangle. Two-finger pinch-zoom still works in either mode. This is
# pure presentation -> selection is still applied via the select_units command.
var _select_mode: bool = false
var _select_button: Button = null
var _selection_box: ColorRect = null
var _is_box_selecting: bool = false

# P3.5 (R12.1/R12.2): references to the P3 overlay containers so the responsive
# layout pass can reposition them for portrait vs landscape. In landscape the
# action controls hug the left/right edges (thumb-reachable); in portrait they
# stack near the bottom. Purely cosmetic (does not touch WorldState).
var _zoom_col: VBoxContainer = null
var _control_group_panel: PanelContainer = null

# P3.4 (R12.4): a selection detail panel. When one or more friendly units are
# selected it shows a compact summary (count, type breakdown, total/avg HP). It
# is read-only and refreshed every frame from the selection + world state.
var _selection_panel: PanelContainer = null
var _selection_label: RichTextLabel = null


func _ready() -> void:
	# BUG-FIX (mobile zoom + move): the root HUD Control defaults to
	# MOUSE_FILTER_STOP, which would SWALLOW every tap/drag in the GUI pass so it
	# never reaches _unhandled_input (where world input now lives). Set it to
	# IGNORE so pointer events fall through to _unhandled_input, while the child
	# Buttons (bottom bar, zoom +/-, control groups) keep their own STOP filter
	# and still receive their taps first. This is what makes both moving units
	# and pinch-zoom work on a real device.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Make sure this node processes unhandled input even if a parent paused it.
	set_process_unhandled_input(true)
	# Phase G: apply the persisted GUI scale so the in-game HUD buttons match the
	# size chosen in Options. This scales the interface layer; the world fit below
	# reads the post-scale viewport size, so the map still frames correctly.
	UiScale.apply_from_settings(self, Nexus.world_state)
	Nexus.event_bus.set_log_enabled(true)
	GameBootstrap.setup_skirmish()
	_local_hq_id = _find_local_hq()
	# Render the world through the local player's fog of war (Phase 2.7).
	_render_adapter.fog_viewer = LOCAL_PLAYER
	# P1.2 (v0.6.0): honour the persisted render style (defaults to the richer
	# texture-driven "sprite" look now) so the game opens looking like a game.
	var settings: GameSettings = GameSettings.new(Nexus.world_state)
	settings.load_from_file()
	_render_adapter.set_style(settings.get_render_style())
	# Phase A.2: fit the WHOLE map to the screen first (the fix for the tiny
	# square in the corner), then center on the local HQ within that framing.
	_render_adapter.fit_map_to_viewport(get_viewport_rect().size)
	var hq: Dictionary = Nexus.get_module("buildings").get_building(_local_hq_id)
	if not hq.is_empty():
		_render_adapter.center_camera_on(Vector2i(int(hq["x"]), int(hq["y"])), get_viewport_rect().size)
		# Re-fit after centering so the full map stays visible (center is only a
		# hint; fit wins so the whole battlefield is readable on every device).
		_render_adapter.fit_map_to_viewport(get_viewport_rect().size)
	# Phase A.3: re-fit whenever the screen size changes (device rotation,
	# window resize, split-screen) so the map is never cut off.
	get_viewport().size_changed.connect(_on_viewport_resized)

	_pause_button.pressed.connect(_on_pause_pressed)
	_build_button.pressed.connect(_on_build_pressed)
	_speed_button.pressed.connect(_on_speed_pressed)
	_research_button.pressed.connect(_on_research_pressed)
	_upgrade_button.pressed.connect(_on_upgrade_pressed)
	_fuse_button.pressed.connect(_on_fuse_pressed)
	_style_button.pressed.connect(_on_style_pressed)
	_restart_button.pressed.connect(_on_restart_pressed)

	# Listen for the end of the match to show the result overlay.
	Nexus.subscribe(VictoryModule.EVENT_MATCH_OVER, self, "_on_match_over")
	_overlay.visible = false

	# Phase A.5: localized tooltips so each button's purpose is clear.
	_apply_tooltips()

	# P3.2/P3.3 (v0.6.0): build the minimap, zoom buttons, and control-group
	# panel programmatically so they overlay the existing HUD without touching
	# the hand-authored scene.
	_build_p3_widgets()

	# Phase A.6: show a short onboarding overlay at match start.
	_show_onboarding()


# Phase A.5: attach a localized tooltip to every HUD button.
func _apply_tooltips() -> void:
	_build_button.tooltip_text = _local_text("ui.game.tip.build")
	_research_button.tooltip_text = _local_text("ui.game.tip.research")
	_upgrade_button.tooltip_text = _local_text("ui.game.tip.upgrade")
	_fuse_button.tooltip_text = _local_text("ui.game.tip.fuse")
	_pause_button.tooltip_text = _local_text("ui.game.tip.pause")
	_speed_button.tooltip_text = _local_text("ui.game.tip.speed")
	_style_button.tooltip_text = _local_text("ui.game.tip.style")


# Phase A.3: keep the whole map fitted on every viewport size change.
func _on_viewport_resized() -> void:
	if _render_adapter != null:
		_render_adapter.fit_map_to_viewport(get_viewport_rect().size)
	# P3.5: re-flow the P3 overlay widgets for the new orientation/size.
	_apply_responsive_layout()


# P3.5 (R12.1/R12.2): reposition the P3 overlay widgets for portrait vs
# landscape so the game is comfortably playable in either orientation.
#
#   - Portrait  (tall): minimap top-right, zoom buttons on the right edge,
#     control groups bottom-left (stacked above the bottom action bar).
#   - Landscape (wide): controls hug the LEFT and RIGHT edges so both thumbs
#     can reach them and the centre of the screen stays clear for the map.
#
# This is presentation-only: it moves Control nodes, never WorldState.
func _apply_responsive_layout() -> void:
	var vp: Vector2 = get_viewport_rect().size
	var landscape: bool = vp.x >= vp.y
	if _minimap != null:
		# Minimap always top-right; nudge it in a little on very wide screens.
		_minimap.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		_minimap.position = Vector2(-_minimap.size.x - 16, 64)
	if _zoom_col != null:
		if landscape:
			# Right edge, vertically centred (right thumb).
			_zoom_col.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
			_zoom_col.position = Vector2(-64, -40)
		else:
			# Portrait: tuck the zoom buttons above the bottom bar on the right.
			_zoom_col.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
			_zoom_col.position = Vector2(-64, -240)
	if _control_group_panel != null:
		if landscape:
			# Left edge, vertically centred (left thumb).
			_control_group_panel.set_anchors_preset(Control.PRESET_CENTER_LEFT)
			_control_group_panel.position = Vector2(12, -110)
		else:
			# Portrait: bottom-left, above the bottom action bar.
			_control_group_panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
			_control_group_panel.position = Vector2(12, -220)


# Phase A.6: a tiny "what am I looking at" overlay so a first-time player is not
# lost. Three lines + a Close button; localized via the existing string keys.
func _show_onboarding() -> void:
	var help: ColorRect = ColorRect.new()
	help.name = "OnboardingOverlay"
	help.color = Color(0, 0, 0, 0.72)
	help.set_anchors_preset(Control.PRESET_FULL_RECT)
	help.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(help)
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	help.add_child(center)
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 18)
	center.add_child(box)
	var lines: Array = [
		"ui.onboarding.title",
		"ui.onboarding.you",
		"ui.onboarding.move",
		"ui.onboarding.win",
	]
	for i in range(lines.size()):
		var lbl: Label = Label.new()
		lbl.text = _local_text(lines[i])
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 30 if i == 0 else 20)
		box.add_child(lbl)
	var close_btn: Button = Button.new()
	close_btn.text = _local_text("ui.onboarding.close")
	close_btn.custom_minimum_size = Vector2(220, 56)
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(close_btn)
	close_btn.pressed.connect(func() -> void: help.queue_free())


# Resolve a localization key through the shared service, falling back to the key.
func _local_text(key: String) -> String:
	var loc: Localization = Localization.new()
	loc.load_all("res://localization")
	var ui: Dictionary = Nexus.world_state.get_section("ui_prefs")
	var locale: String = str(ui.get("locale", ""))
	if locale != "":
		loc.set_locale(locale)
	return loc.t(key)


func _process(_delta: float) -> void:
	_render_adapter.selected_unit_ids = _selected_unit_ids
	_refresh_top_bar()
	_refresh_selection_panel()


func _refresh_top_bar() -> void:
	var economy: Object = Nexus.get_module("economy")
	var gold: int = economy.get_resource(LOCAL_PLAYER, "resource_basic") if economy != null else 0
	_resource_label.text = "Resources: %d" % gold
	var paused: bool = Nexus.sim_clock.is_paused()
	var units: int = Nexus.get_module("units").count()
	# Phase 2: surface researched-tech count so the player sees progress.
	var tech: Object = Nexus.get_module("tech_tree")
	var researched: int = 0
	if tech != null:
		tech.ensure_player(LOCAL_PLAYER)
		researched = (Nexus.world_state.get_section("tech").get("players", {})
			.get(str(LOCAL_PLAYER), {}).get("researched", []) as Array).size()
	_status_label.text = "%s   |   Tick: %d   |   Units: %d   |   Sel: %d   |   Tech: %d" % [
		"PAUSED" if paused else "RUNNING",
		Nexus.world_state.current_tick,
		units,
		_selected_unit_ids.size(),
		researched,
	]
	_pause_button.text = "Resume" if paused else "Pause"
	_speed_button.text = "Speed x%.0f" % Nexus.sim_clock.time_scale
	# The Fuse button is only meaningful with units selected.
	_fuse_button.disabled = _selected_unit_ids.is_empty()


# --- Touch / click input ----------------------------------------------------

# BUG-FIX (mobile zoom + move): world input is handled in _unhandled_input, NOT
# _gui_input. Two reasons this matters and is the correct pattern:
#
#   1. MULTI-TOUCH / PINCH: Control._gui_input only routes the finger under the
#      GUI focus point, so the SECOND finger of a pinch never reliably arrives
#      (Godot issue #29525). _unhandled_input receives every InputEventScreen
#      touch/drag with its own index, so two-finger pinch-zoom works.
#
#   2. UI BUTTONS FIRST: GUI Controls (the bottom-bar Buttons, zoom +/- buttons,
#      control-group grid, onboarding overlay) consume their events in the GUI
#      pass BEFORE _unhandled_input runs. So a tap on a button no longer leaks
#      through as a "move to that tile" command, and a tap on empty ground still
#      reaches us here. This is exactly what a mobile RTS needs.
#
# All positions in _unhandled_input are already in VIEWPORT space, which is what
# RenderAdapter.screen_to_tile() expects (it undoes the canvas transform + camera
# pan/zoom internally). So we pass event.position straight through -- no extra
# get_global_transform_with_canvas() multiply (that was for _gui_input's
# control-local coordinates and caused taps to land on the wrong tile).
func _unhandled_input(event: InputEvent) -> void:
	# BUG-FIX (double-tap / cannot move). This project enables BOTH emulation
	# directions:
	#   * emulate_touch_from_mouse = true  -> on DESKTOP a real mouse click also
	#     spawns a synthetic InputEventScreenTouch.
	#   * emulate_mouse_from_touch (default true) -> on MOBILE a real finger tap
	#     also spawns a synthetic InputEventMouseButton.
	# If we processed both the real event and its synthetic twin, every tap ran
	# twice: it selected a unit and then immediately toggled it back off (or
	# cancelled the move), which is exactly why units could not be moved -- on the
	# phone AND on the desktop editor.
	#
	# The clean, version-independent rule: SYNTHETIC events are flagged by the
	# engine with device == InputEvent.DEVICE_ID_EMULATION (-1). We drop every
	# emulated event (whether it is a fake touch or a fake mouse) and act only on
	# the ORIGINAL event, whichever kind the hardware actually produced. That
	# guarantees each physical tap is handled exactly once on every platform.
	if _is_emulated(event):
		return
	# Trackpad / touchscreen gesture zoom (two fingers). On laptops and desktops a
	# two-finger pinch produces an InputEventMagnifyGesture, NOT two touch points,
	# so without this branch "two-finger zoom" did nothing. factor > 1 spreads
	# (zoom in), < 1 pinches (zoom out); the gesture position is the anchor.
	if event is InputEventMagnifyGesture:
		_render_adapter.zoom_at(event.factor, event.position)
		_render_adapter.clamp_camera(get_viewport_rect().size)
		get_viewport().set_input_as_handled()
		return
	# Two-finger pan gesture (trackpad) scrolls the map.
	if event is InputEventPanGesture:
		_render_adapter.pan_by_screen(-event.delta * _GESTURE_PAN_SPEED)
		_render_adapter.clamp_camera(get_viewport_rect().size)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventScreenTouch:
		_handle_touch(event)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		_handle_drag(event)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)


# True when a pointer event (touch OR mouse) was SYNTHESISED by the engine from
# the other kind, via emulate_touch_from_mouse / emulate_mouse_from_touch. Such
# events must be ignored so a single physical tap is not processed twice (once as
# the real event, once as its emulated twin) -- the reason units could not be
# moved on both phone and desktop.
#
# The engine marks EVERY emulated pointer event with
# device == InputEvent.DEVICE_ID_EMULATION (-1). This is reliable across Godot
# versions (4.2 / 4.3 / 4.4 / 4.7) and, unlike is_emulated(), actually exists on
# InputEventMouse (verified at runtime: InputEventMouse has NO is_emulated()
# method in 4.3). A genuine hardware touch/mouse always has device >= 0.
func _is_emulated(event: InputEvent) -> bool:
	if event is InputEventFromWindow or event is InputEventMouse or event is InputEventScreenTouch or event is InputEventScreenDrag:
		return event.device == InputEvent.DEVICE_ID_EMULATION
	return false


# --- Touch (mobile) camera + tap handling -----------------------------------

func _handle_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		_active_touches[event.index] = event.position
		if _active_touches.size() == 1:
			_press_start = event.position
			_press_moved = false
			_is_panning = false
			_pan_last = event.position
		elif _active_touches.size() == 2:
			# Begin a pinch: remember the initial finger distance.
			_pinch_last_dist = _touch_distance()
	else:
		_active_touches.erase(event.index)
		# A quick, non-moving single-finger release is a TAP -> command.
		# In _unhandled_input the position is already in viewport space, which is
		# exactly what screen_to_tile() expects, so pass it straight through.
		if _active_touches.is_empty() and not _press_moved:
			_handle_tap(event.position)
		if _active_touches.size() < 2:
			_pinch_last_dist = 0.0
		if _active_touches.is_empty():
			_is_panning = false


func _handle_drag(event: InputEventScreenDrag) -> void:
	_active_touches[event.index] = event.position
	if _active_touches.size() >= 2:
		# Pinch-zoom around the midpoint of the two fingers.
		var dist: float = _touch_distance()
		if _pinch_last_dist > 0.0 and dist > 0.0:
			var factor: float = dist / _pinch_last_dist
			var mid: Vector2 = _touch_midpoint()
			# mid is a raw viewport/physical position; zoom_at converts it into
			# canvas space so the pinch stays anchored on scaled windows (BUG-5).
			_render_adapter.zoom_at(factor, mid)
			_render_adapter.clamp_camera(get_viewport_rect().size)
		_pinch_last_dist = dist
		_press_moved = true
	else:
		# Single-finger drag = pan once past the drag threshold.
		if event.position.distance_to(_press_start) > _DRAG_THRESHOLD:
			_press_moved = true
			_is_panning = true
			if _is_panning:
				_render_adapter.pan_by_screen(event.position - _pan_last)
				_render_adapter.clamp_camera(get_viewport_rect().size)
			_pan_last = event.position


func _touch_distance() -> float:
	var pts: Array = _active_touches.values()
	if pts.size() < 2:
		return 0.0
	return (pts[0] as Vector2).distance_to(pts[1] as Vector2)


func _touch_midpoint() -> Vector2:
	var pts: Array = _active_touches.values()
	if pts.size() < 2:
		return _press_start
	return ((pts[0] as Vector2) + (pts[1] as Vector2)) * 0.5


# --- Mouse (desktop-in-mobile-scene) camera + tap handling ------------------

func _handle_mouse_button(event: InputEventMouseButton) -> void:
	# In _unhandled_input, event.position is raw viewport/physical space;
	# screen_to_tile / zoom_at / pan_by_screen convert it internally.
	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_press_start = event.position
			_press_moved = false
			_pan_last = event.position
		else:
			if not _press_moved:
				_handle_tap(event.position)
			_is_panning = false
	elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
		_render_adapter.zoom_at(1.15, event.position)
		_render_adapter.clamp_camera(get_viewport_rect().size)
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
		_render_adapter.zoom_at(1.0 / 1.15, event.position)
		_render_adapter.clamp_camera(get_viewport_rect().size)


func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	# Middle-button (or left-drag past threshold) pans the camera.
	if event.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
		_render_adapter.pan_by_screen(event.relative)
		_render_adapter.clamp_camera(get_viewport_rect().size)
	elif event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		if event.position.distance_to(_press_start) > _DRAG_THRESHOLD:
			_press_moved = true
			_is_panning = true
		if _is_panning:
			_render_adapter.pan_by_screen(event.relative)
			_render_adapter.clamp_camera(get_viewport_rect().size)


func _handle_tap(screen_pos: Vector2) -> void:
	var tile: Vector2i = _render_adapter.screen_to_tile(screen_pos)
	var tapped_unit: int = _unit_at_tile(tile, LOCAL_PLAYER)
	if tapped_unit != -1:
		# Tapping an already-selected unit toggles it off; otherwise add it to the
		# selection. Holding Shift/Ctrl is not assumed (touch-friendly): repeated
		# taps build a squad, which is exactly what Hero Fusion needs.
		if _selected_unit_ids.has(tapped_unit):
			_selected_unit_ids.erase(tapped_unit)
		else:
			_selected_unit_ids.append(tapped_unit)
		Nexus.issue_command("select_units", LOCAL_PLAYER, {
			"owner": LOCAL_PLAYER,
			"unit_ids": _selected_unit_ids.duplicate(),
		}, 1)
	elif not _selected_unit_ids.is_empty():
		# Move the current selection to the tapped tile.
		Nexus.issue_command("move_unit", LOCAL_PLAYER, {
			"unit_ids": _selected_unit_ids.duplicate(),
			"x": tile.x,
			"y": tile.y,
		}, 1)


# --- MA2: box / drag selection (mobile) -------------------------------------

# Toggle the "Select" mode. While ON a single-finger drag draws a selection
# rectangle instead of panning; a tap still works as before.
func _on_select_mode_pressed() -> void:
	_select_mode = not _select_mode
	_update_select_button()


func _update_select_button() -> void:
	if _select_button == null:
		return
	_select_button.button_pressed = _select_mode
	# Keep the label stable; a pressed/toggled look communicates the state.
	_select_button.text = _local_text("ui.game.select_mode")


# Pure helper (headless-testable): return the ids of every unit owned by
# `owner_filter` whose tile lies inside the screen-space rectangle defined by the
# two corner points. Corners may be given in any order. Ids are returned sorted
# ascending so the resulting selection is deterministic.
func _units_in_screen_rect(p1: Vector2, p2: Vector2, owner_filter: int) -> Array:
	var out: Array = []
	if _render_adapter == null:
		return out
	var tl: Vector2i = _render_adapter.screen_to_tile(Vector2(minf(p1.x, p2.x), minf(p1.y, p2.y)))
	var br: Vector2i = _render_adapter.screen_to_tile(Vector2(maxf(p1.x, p2.x), maxf(p1.y, p2.y)))
	var min_x: int = mini(tl.x, br.x)
	var max_x: int = maxi(tl.x, br.x)
	var min_y: int = mini(tl.y, br.y)
	var max_y: int = maxi(tl.y, br.y)
	var units: Dictionary = Nexus.world_state.get_section("units").get("list", {})
	var keys: Array = units.keys()
	keys.sort_custom(func(a, b): return int(a) < int(b))
	for key in keys:
		var u: Dictionary = units[key]
		if int(u.get("owner", -1)) != owner_filter:
			continue
		var ux: int = int(u["x"])
		var uy: int = int(u["y"])
		if ux >= min_x and ux <= max_x and uy >= min_y and uy <= max_y:
			out.append(int(u["id"]))
	return out


# Apply a box selection: replace the current selection with everything inside the
# screen rectangle and push it through the authoritative select_units command.
func _apply_box_selection(p1: Vector2, p2: Vector2) -> void:
	_selected_unit_ids = _units_in_screen_rect(p1, p2, LOCAL_PLAYER)
	Nexus.issue_command("select_units", LOCAL_PLAYER, {
		"owner": LOCAL_PLAYER,
		"unit_ids": _selected_unit_ids.duplicate(),
	}, 1)


func _update_selection_box(current: Vector2) -> void:
	if _selection_box == null:
		return
	var top_left: Vector2 = Vector2(minf(_press_start.x, current.x), minf(_press_start.y, current.y))
	var size: Vector2 = (current - _press_start).abs()
	_selection_box.visible = true
	_selection_box.position = top_left
	_selection_box.size = size


# --- Buttons ----------------------------------------------------------------

func _on_pause_pressed() -> void:
	Nexus.toggle_pause()


func _on_build_pressed() -> void:
	# Ask the economy to build a soldier at the local HQ (cost-checked there).
	Nexus.issue_command("build_unit", LOCAL_PLAYER, {
		"owner": LOCAL_PLAYER,
		"building_id": _local_hq_id,
		"unit_type": "soldier",
	}, 1)


func _on_speed_pressed() -> void:
	# Cycle simulation speed: 1x -> 2x -> 4x -> 1x.
	var s: float = Nexus.sim_clock.time_scale
	if s >= 4.0:
		Nexus.sim_clock.time_scale = 1.0
	else:
		Nexus.sim_clock.time_scale = s * 2.0


func _on_style_pressed() -> void:
	# Phase 4.2: flip the render look between the simple (Mindustry-style) and
	# detailed (MOWAS-style) renderers. This is purely cosmetic -- the swap never
	# touches the simulation (Logic/Render Separation).
	var active: String = _render_adapter.toggle_style()
	_style_button.text = "Style: %s" % _style_label(active)


# Map a render-style id to a short human label for the Style button.
func _style_label(style_id: String) -> String:
	match style_id:
		RenderAdapter.STYLE_DETAILED:
			return "Detailed"
		RenderAdapter.STYLE_SPRITE:
			return "Sprite"
		_:
			return "Simple"


# --- Phase 2 controls -------------------------------------------------------

func _on_research_pressed() -> void:
	# Research the first affordable, not-yet-started tech node for the player.
	var tech: Object = Nexus.get_module("tech_tree")
	if tech == null:
		return
	var node_id: String = _next_research_node(tech)
	if node_id == "":
		return
	Nexus.issue_command("research_tech", LOCAL_PLAYER, {
		"owner": LOCAL_PLAYER,
		"node_id": node_id,
	}, 1)


func _on_upgrade_pressed() -> void:
	# Queue the next HQ upgrade level (cost + time checked by the module).
	Nexus.issue_command("upgrade_building", LOCAL_PLAYER, {
		"building_id": _local_hq_id,
	}, 1)


func _on_fuse_pressed() -> void:
	# Fuse the currently selected units into a hero (recipe matched in module).
	if _selected_unit_ids.is_empty():
		return
	Nexus.issue_command("fuse_units", LOCAL_PLAYER, {
		"owner": LOCAL_PLAYER,
		"unit_ids": _selected_unit_ids.duplicate(),
	}, 1)


# Pick the first tech node the player can legally start right now.
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


func _on_restart_pressed() -> void:
	# Tear the match down and reload the scene for a fresh skirmish.
	Nexus.shutdown_simulation()
	get_tree().reload_current_scene()


# --- Match end --------------------------------------------------------------

func _on_match_over(_event_name: String, payload: Dictionary) -> void:
	var winner: int = int(payload.get("winner", -1))
	var text: String = ""
	if winner == LOCAL_PLAYER:
		text = "VICTORY"
	elif winner < 0:
		text = "DRAW"
	else:
		text = "DEFEAT"
	_overlay_label.text = text
	_overlay.visible = true
	# Stop the simulation so nothing moves behind the overlay.
	Nexus.sim_clock.pause()


# --- Helpers ----------------------------------------------------------------

func _unit_at_tile(tile: Vector2i, owner_filter: int) -> int:
	var units: Dictionary = Nexus.world_state.get_section("units").get("list", {})
	var keys: Array = units.keys()
	keys.sort()
	for key in keys:
		var u: Dictionary = units[key]
		if int(u["x"]) == tile.x and int(u["y"]) == tile.y:
			if owner_filter < 0 or int(u["owner"]) == owner_filter:
				return int(u["id"])
	return -1


func _selected_squad_size() -> int:
	return _selected_unit_ids.size()


func _find_local_hq() -> int:
	var buildings: Dictionary = Nexus.world_state.get_section("buildings").get("list", {})
	var keys: Array = buildings.keys()
	keys.sort()
	for key in keys:
		var b: Dictionary = buildings[key]
		if int(b["owner"]) == LOCAL_PLAYER:
			return int(b["id"])
	return -1


# --- P3.2 + P3.3: minimap, zoom buttons, control-group panel ----------------

# Build the P3 overlay widgets on top of the existing HUD. Everything here is
# pure presentation: the minimap reads world state, the zoom buttons move the
# RenderAdapter camera, and control groups just re-issue select commands.
func _build_p3_widgets() -> void:
	_build_minimap()
	_build_zoom_buttons()
	_build_control_group_panel()
	_build_selection_panel()
	# Apply the initial responsive placement for the current orientation.
	_apply_responsive_layout()


# P3.3 (R12.3): a corner minimap. Anchored bottom-right, above the bottom bar.
func _build_minimap() -> void:
	var MinimapScript = load("res://ui/shared/minimap.gd")
	_minimap = MinimapScript.new()
	_minimap.name = "Minimap"
	_minimap.render_adapter = _render_adapter
	_minimap.fog_viewer = LOCAL_PLAYER
	# Anchor to the top-right corner so it never fights the bottom action bar.
	_minimap.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_minimap.position = Vector2(-196, 64)
	_minimap.size = Vector2(180, 130)
	add_child(_minimap)


# P3.1 (BUG-4): on-screen +/- zoom buttons for players without a mouse wheel or
# pinch. They zoom around the viewport centre and clamp the camera.
func _build_zoom_buttons() -> void:
	var col: VBoxContainer = VBoxContainer.new()
	col.name = "ZoomButtons"
	col.add_theme_constant_override("separation", 6)
	col.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	col.position = Vector2(-64, -40)
	add_child(col)
	_zoom_col = col

	var zoom_in: Button = Button.new()
	zoom_in.text = "+"
	zoom_in.custom_minimum_size = Vector2(48, 48)
	zoom_in.pressed.connect(func() -> void:
		_render_adapter.zoom_step(true, get_viewport_rect().size)
		_render_adapter.clamp_camera(get_viewport_rect().size))
	col.add_child(zoom_in)

	var zoom_out: Button = Button.new()
	zoom_out.text = "-"
	zoom_out.custom_minimum_size = Vector2(48, 48)
	zoom_out.pressed.connect(func() -> void:
		_render_adapter.zoom_step(false, get_viewport_rect().size)
		_render_adapter.clamp_camera(get_viewport_rect().size))
	col.add_child(zoom_out)


# P3.2 (R11): a 3x3 control-group grid in the bottom-left corner plus an
# "Assign" toggle. Tap a slot to recall its group; enable Assign and tap a slot
# to store the current selection there.
func _build_control_group_panel() -> void:
	var panel: PanelContainer = PanelContainer.new()
	panel.name = "ControlGroups"
	panel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	panel.position = Vector2(12, -220)
	add_child(panel)
	_control_group_panel = panel

	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)

	_assign_button = Button.new()
	_assign_button.text = _local_text("ui.game.assign")
	_assign_button.toggle_mode = true
	_assign_button.custom_minimum_size = Vector2(0, 34)
	_assign_button.toggled.connect(func(pressed: bool) -> void: _assign_mode = pressed)
	box.add_child(_assign_button)

	var grid: GridContainer = GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	box.add_child(grid)

	_group_buttons.clear()
	for i in range(9):
		var b: Button = Button.new()
		b.text = str(i + 1)
		b.custom_minimum_size = Vector2(40, 40)
		var slot: int = i
		b.pressed.connect(func() -> void: _on_control_group_pressed(slot))
		grid.add_child(b)
		_group_buttons.append(b)


# Handle a control-group slot tap: assign the current selection (Assign mode) or
# recall the stored group (normal mode).
func _on_control_group_pressed(slot: int) -> void:
	if slot < 0 or slot >= _control_groups.size():
		return
	if _assign_mode:
		_control_groups[slot] = _selected_unit_ids.duplicate()
		_refresh_control_group_labels()
		# One-shot assign: turn the toggle back off for convenience.
		_assign_mode = false
		if _assign_button != null:
			_assign_button.button_pressed = false
		return
	# Recall: drop any units that no longer exist, then select + focus.
	var group: Array = _control_groups[slot]
	var living: Array = []
	var units: Dictionary = Nexus.world_state.get_section("units").get("list", {})
	for uid in group:
		if units.has(str(int(uid))):
			living.append(int(uid))
	_control_groups[slot] = living
	if living.is_empty():
		return
	_selected_unit_ids = living.duplicate()
	Nexus.issue_command("select_units", LOCAL_PLAYER, {
		"owner": LOCAL_PLAYER,
		"unit_ids": _selected_unit_ids.duplicate(),
	}, 1)
	# Centre the camera on the first unit of the recalled group.
	var first: Dictionary = units.get(str(living[0]), {})
	if not first.is_empty():
		_render_adapter.center_camera_on(Vector2i(int(first["x"]), int(first["y"])), get_viewport_rect().size)
		_render_adapter.clamp_camera(get_viewport_rect().size)


# Show a small count on each control-group button so the player can see which
# slots hold a squad and how big it is.
func _refresh_control_group_labels() -> void:
	for i in range(_group_buttons.size()):
		var count: int = (_control_groups[i] as Array).size()
		if count > 0:
			_group_buttons[i].text = "%d\n(%d)" % [i + 1, count]
		else:
			_group_buttons[i].text = str(i + 1)


# --- P3.4: selection detail panel -------------------------------------------

# Build the (initially hidden) selection detail panel, anchored bottom-centre.
func _build_selection_panel() -> void:
	_selection_panel = PanelContainer.new()
	_selection_panel.name = "SelectionPanel"
	_selection_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_selection_panel.position = Vector2(0, -150)
	_selection_panel.custom_minimum_size = Vector2(0, 90)
	_selection_panel.visible = false
	# Do not eat taps meant for the world underneath the (thin) panel.
	_selection_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_selection_panel)

	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	_selection_panel.add_child(margin)

	_selection_label = RichTextLabel.new()
	_selection_label.bbcode_enabled = true
	_selection_label.fit_content = true
	_selection_label.scroll_active = false
	_selection_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(_selection_label)


# Refresh the selection panel from the current selection + world state. Shows a
# type breakdown and aggregate HP; hides itself when nothing is selected.
func _refresh_selection_panel() -> void:
	if _selection_panel == null:
		return
	if _selected_unit_ids.is_empty():
		_selection_panel.visible = false
		return
	var units: Dictionary = Nexus.world_state.get_section("units").get("list", {})
	var by_type: Dictionary = {}
	var total_hp: int = 0
	var total_max_hp: int = 0
	var alive: int = 0
	for uid in _selected_unit_ids:
		var u: Dictionary = units.get(str(int(uid)), {})
		if u.is_empty():
			continue
		alive += 1
		var t: String = str(u.get("type", "unit"))
		by_type[t] = int(by_type.get(t, 0)) + 1
		total_hp += int(u.get("hp", 0))
		total_max_hp += int(u.get("max_hp", u.get("hp", 0)))
	if alive == 0:
		_selection_panel.visible = false
		return
	# Build a compact "type xN" list.
	var type_keys: Array = by_type.keys()
	type_keys.sort()
	var parts: Array = []
	for t in type_keys:
		parts.append("%s x%d" % [t, int(by_type[t])])
	var hp_text: String = "%d/%d" % [total_hp, total_max_hp] if total_max_hp > 0 else str(total_hp)
	_selection_label.text = "[b]%s: %d[/b]   %s\nHP: %s" % [
		_local_text("ui.game.selected"), alive, "  ".join(parts), hp_text]
	_selection_panel.visible = true
