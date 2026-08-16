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
const MAIN_MENU_SCENE: String = "res://scenes/main_menu.tscn"

# MB3.3 (bug 6): during a match the Android BACK key must NOT quit the app. The
# first BACK pauses the sim and arms a confirm ("press Back again to leave");
# only the SECOND consecutive BACK returns to the main menu. Any other action
# clears the arm so a stray press is harmless.
var _leave_armed: bool = false

@onready var _render_adapter: RenderAdapter = $WorldLayer/RenderAdapter
@onready var _resource_label: Label = $TopBar/Margin/Row/ResourceLabel
@onready var _status_label: Label = $TopBar/Margin/Row/StatusLabel
# MB4.5 (bug16): the bottom action bar is a GridContainer so it can wrap the
# buttons into several rows in landscape (short screen) instead of one long
# scrolling row. `_action_grid.columns` is re-computed on every resize.
@onready var _action_grid: GridContainer = $BottomBar/Margin/Scroll/Row
@onready var _pause_button: Button = $BottomBar/Margin/Scroll/Row/PauseButton
@onready var _build_button: Button = $BottomBar/Margin/Scroll/Row/BuildButton
@onready var _speed_button: Button = $BottomBar/Margin/Scroll/Row/SpeedButton
@onready var _research_button: Button = $BottomBar/Margin/Scroll/Row/ResearchButton
@onready var _upgrade_button: Button = $BottomBar/Margin/Scroll/Row/UpgradeButton
@onready var _fuse_button: Button = $BottomBar/Margin/Scroll/Row/FuseButton
@onready var _style_button: Button = $BottomBar/Margin/Scroll/Row/StyleButton
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
var _control_groups: Array = ControlGroupUtil.empty_groups()
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

# MC1.5 (request 1): two movement modes. In DIRECT mode a tap on empty ground
# moves the selection immediately (the long-standing behaviour). In MANUAL mode
# consecutive taps plot an ordered waypoint route; a "Confirm" issues one
# move_unit carrying the whole route (belief-aware, stitched by WaypointUtil),
# and "Cancel" discards it. All state/logic lives in the pure MoveModeUtil so the
# HUD only issues authoritative commands (no WorldState mutation here).
var _move_mode: MoveModeUtil = MoveModeUtil.new()
var _move_mode_button: Button = null
var _move_confirm_button: Button = null
var _move_cancel_button: Button = null

# MC3.3 (req 3): data-driven icon service. Loads data/ui_icons/manifest.json and
# resolves logical icon names to textures, falling back to a drawn glyph so the
# HUD never breaks when real art is missing.
var _icons: IconService = IconService.new()

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

# MC11.2/11.3/11.4 (request 11): the in-game Messages panel. A toggle button
# opens a panel with three tabs: (1) plain Chat, (2) Strategic (propose a
# structured treaty), and (3) Mission (attack/defend a point + commitment). All
# logic lives in the pure MessageLogUtil / TreatyUtil / MissionRequestUtil; the
# HUD only builds widgets and issues authoritative diplomatic Commands, so the
# simulation stays deterministic. The message log itself is a cosmetic local
# transcript (it never touches the state hash).
var _msg_button: Button = null
var _msg_panel: PanelContainer = null
var _msg_log: Array = []                 # local transcript (cosmetic)
var _msg_recipient: OptionButton = null  # chat + strategic recipient picker
var _msg_history: RichTextLabel = null   # chat transcript view
var _msg_text_edit: LineEdit = null      # chat text entry
var _treaty_type_opt: OptionButton = null
var _treaty_target_opt: OptionButton = null
var _treaty_duration: SpinBox = null
var _mission_type_opt: OptionButton = null
var _mission_target_opt: OptionButton = null
var _mission_cell_x: SpinBox = null
var _mission_cell_y: SpinBox = null
var _mission_commit: HSlider = null


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
	# Localize the static button captions (the .tscn ships English placeholders).
	_apply_static_labels()

	# P3.2/P3.3 (v0.6.0): build the minimap, zoom buttons, and control-group
	# panel programmatically so they overlay the existing HUD without touching
	# the hand-authored scene.
	_build_p3_widgets()

	# Phase A.6: show a short onboarding overlay at match start.
	_show_onboarding()


# Phase A.5: attach a localized tooltip to every HUD button.
# Localize the buttons whose captions never change at runtime. The scene file
# carries English placeholder texts; this pass replaces them with the player's
# language so the mobile HUD matches the rest of the localized UI.
func _apply_static_labels() -> void:
	_build_button.text = _local_text("ui.game.build_soldier")
	_research_button.text = _local_text("ui.game.research")
	_upgrade_button.text = _local_text("ui.game.upgrade_hq")
	_fuse_button.text = _local_text("ui.game.fuse_hero")
	_style_button.text = "%s: %s" % [_local_text("ui.game.style"), _style_label(_render_adapter.style_id)]
	_restart_button.text = _local_text("ui.game.play_again")


func _apply_tooltips() -> void:
	_build_button.tooltip_text = _local_text("ui.game.tip.build")
	_research_button.tooltip_text = _local_text("ui.game.tip.research")
	_upgrade_button.tooltip_text = _local_text("ui.game.tip.upgrade")
	_fuse_button.tooltip_text = _local_text("ui.game.tip.fuse")
	_pause_button.tooltip_text = _local_text("ui.game.tip.pause")
	_speed_button.tooltip_text = _local_text("ui.game.tip.speed")
	_style_button.tooltip_text = _local_text("ui.game.tip.style")


# Phase A.3 + MA5 (B6): keep everything correct on every viewport size change --
# crucially including DEVICE ROTATION, where the window's width/height swap.
func _on_viewport_resized() -> void:
	# MA5: re-resolve the GUI content scale for the NEW screen size/orientation.
	# Without this the auto scale stays frozen at the value computed for the
	# launch orientation, so after a portrait<->landscape flip the HUD renders at
	# the wrong scale and the responsive math (which reads the post-scale viewport
	# rect) places widgets off-screen. Re-applying keeps the scale honest.
	UiScale.apply_from_settings(self, Nexus.world_state)
	if _render_adapter != null:
		_render_adapter.fit_map_to_viewport(get_viewport_rect().size)
	# P3.5/MA5: re-flow the overlay widgets for the new orientation/size.
	_apply_responsive_layout()


# P3.5 (R12.1/R12.2) + MA5 (B6): reposition the floating overlay widgets for
# portrait vs landscape so the game is comfortably playable in either
# orientation and NOTHING ever leaves the screen or sits under the top/bottom
# bars (the MA5 bug: hard-coded anchor offsets pushed widgets off-screen on some
# aspect ratios / after rotation).
#
#   - Portrait  (tall): minimap top-right, zoom buttons docked bottom-right,
#     control groups bottom-left (both stacked above the bottom action bar).
#   - Landscape (wide): zoom hugs the RIGHT edge and control groups the LEFT
#     edge, both vertically centred so each thumb reaches one, keeping the
#     centre clear for the map.
#
# All geometry is computed by the pure, headless-tested ResponsiveLayoutUtil in
# ABSOLUTE viewport pixels; every widget is anchored TOP_LEFT and positioned
# from the clamped result, so there is one testable source of truth. This is
# presentation-only: it moves Control nodes, never WorldState.
func _apply_responsive_layout() -> void:
	var vp: Vector2 = get_viewport_rect().size
	_apply_action_grid_columns(vp)
	if _minimap != null:
		_minimap.set_anchors_preset(Control.PRESET_TOP_LEFT)
		_minimap.position = ResponsiveLayoutUtil.minimap_pos(vp, _widget_size(_minimap))
	if _zoom_col != null:
		_zoom_col.set_anchors_preset(Control.PRESET_TOP_LEFT)
		_zoom_col.position = ResponsiveLayoutUtil.zoom_col_pos(vp, _widget_size(_zoom_col))
	var group_pos: Vector2 = Vector2.ZERO
	var group_size: Vector2 = Vector2.ZERO
	if _control_group_panel != null:
		group_size = _widget_size(_control_group_panel)
		group_pos = ResponsiveLayoutUtil.control_group_pos(vp, group_size)
		_control_group_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
		_control_group_panel.position = group_pos
	if _select_button != null:
		# MA2/MA5: keep the Select toggle just above the control-group panel in
		# both orientations so it is always thumb-reachable and never off-screen.
		_select_button.set_anchors_preset(Control.PRESET_TOP_LEFT)
		_select_button.position = ResponsiveLayoutUtil.select_button_pos(
			vp, _widget_size(_select_button), group_pos, group_size)


# MB4.5 (bug16): pick the number of columns for the bottom action grid. Portrait
# keeps every button in a single row (wide screen). Landscape wraps them into a
# compact grid of the widest count that fits the usable width, so the row never
# overflows / needs horizontal scrolling on a short landscape screen. The widest
# button's minimum width drives the geometric fit so no caption is clipped.
func _apply_action_grid_columns(vp: Vector2) -> void:
	if _action_grid == null:
		return
	var count: int = _action_grid.get_child_count()
	if count <= 0:
		return
	# Widest button min-width (buttons carry custom_minimum_size in the scene).
	var widest: float = 1.0
	for child in _action_grid.get_children():
		if child is Control:
			widest = maxf(widest, (child as Control).get_combined_minimum_size().x)
	var sep: float = float(_action_grid.get_theme_constant("h_separation"))
	var cols: int = ResponsiveLayoutUtil.action_columns(vp, count, widest, sep)
	_action_grid.columns = cols


# Best-effort measured size of a floating widget. `size` is authoritative once
# the node has been laid out; before that (or for auto-sizing containers) fall
# back to the combined minimum size so the responsive math still has real
# dimensions to clamp against.
func _widget_size(node: Control) -> Vector2:
	var s: Vector2 = node.size
	if s.x <= 0.0 or s.y <= 0.0:
		s = node.get_combined_minimum_size()
	return s


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
# The Localization instance is cached: building it re-reads every JSON file from
# disk, which is far too expensive to repeat (some callers run every frame).
var _loc_cache: Localization = null


func _local_text(key: String) -> String:
	if _loc_cache == null:
		_loc_cache = Localization.new()
		_loc_cache.load_all("res://localization")
		var ui: Dictionary = Nexus.world_state.get_section("ui_prefs")
		var locale: String = str(ui.get("locale", ""))
		if locale != "":
			_loc_cache.set_locale(locale)
	return _loc_cache.t(key)


func _process(_delta: float) -> void:
	_render_adapter.selected_unit_ids = _selected_unit_ids
	_refresh_top_bar()
	_refresh_selection_panel()


func _refresh_top_bar() -> void:
	var economy: Object = Nexus.get_module("economy")
	var gold: int = economy.get_resource(LOCAL_PLAYER, "resource_basic") if economy != null else 0
	_resource_label.text = "%s: %d" % [_local_text("ui.game.resources"), gold]
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
		_local_text("ui.game.paused") if paused else _local_text("ui.game.running"),
		Nexus.world_state.current_tick,
		units,
		_selected_unit_ids.size(),
		researched,
	]
	_pause_button.text = _local_text("ui.game.resume") if paused else _local_text("ui.game.pause")
	_speed_button.text = "%s x%.0f" % [_local_text("ui.game.speed"), Nexus.sim_clock.time_scale]
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
	# MB3.3 (bug 6): Android BACK / ESC / gamepad-B arrive as "ui_cancel". In a
	# match this must pause + confirm-leave, never quit the app.
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_back_in_game()
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
			# Begin a pinch: remember the initial finger distance. A second finger
			# cancels any in-progress box selection (pinch-zoom takes priority).
			_pinch_last_dist = _touch_distance()
			if _is_box_selecting:
				_is_box_selecting = false
				if _selection_box != null:
					_selection_box.visible = false
	else:
		_active_touches.erase(event.index)
		# MA2: finishing a box-selection drag (select mode ON, single finger).
		if _is_box_selecting and _active_touches.is_empty():
			if _selection_box != null:
				_selection_box.visible = false
			_apply_box_selection(_press_start, event.position)
			_is_box_selecting = false
			_press_moved = false
			return
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
	elif _select_mode:
		# MA2: single-finger drag in Select mode = draw a box-selection rectangle
		# (never pans the camera). A pinch (two fingers) above still takes over.
		if _is_box_selecting or event.position.distance_to(_press_start) > _DRAG_THRESHOLD:
			_press_moved = true
			_is_box_selecting = true
			_update_selection_box(event.position)
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
	# MA6: route the tap decision through the shared, headless-tested TapSelectUtil
	# so the mobile HUD, the desktop HUD, and the unit tests all agree on exactly
	# what a single tap does (select / toggle / move). The util is pure; it only
	# returns a plan -- we still issue the authoritative commands here.
	#
	#   * Tap a friendly unit           -> toggle it in/out of the squad (repeated
	#                                       taps build a squad, needed by Hero Fusion).
	#   * Tap empty ground with a squad -> MOVE the selection to that tile.
	var plan: Dictionary = TapSelectUtil.resolve_tap(_selected_unit_ids, tapped_unit)
	match str(plan.get("action", TapSelectUtil.ACTION_NONE)):
		TapSelectUtil.ACTION_SELECT:
			_selected_unit_ids = (plan.get("selection", []) as Array).duplicate()
			Nexus.issue_command("select_units", LOCAL_PLAYER, {
				"owner": LOCAL_PLAYER,
				"unit_ids": _selected_unit_ids.duplicate(),
			}, 1)
		TapSelectUtil.ACTION_MOVE:
			# MC1.5 (request 1): a ground tap now runs through MoveModeUtil so the
			# same tap either moves immediately (DIRECT) or plots a waypoint route
			# (MANUAL). The util is pure; we still issue the authoritative commands.
			var move_plan: Dictionary = _move_mode.resolve_ground_tap(tile, not _selected_unit_ids.is_empty())
			match str(move_plan.get("action", MoveModeUtil.ACTION_NONE)):
				MoveModeUtil.ACTION_MOVE_DIRECT:
					# Simulation command -> route through player_command so it is
					# lockstep scheduled when a networked session is active (MA7.1).
					Nexus.player_command("move_unit", {
						"unit_ids": _selected_unit_ids.duplicate(),
						"x": tile.x,
						"y": tile.y,
					}, 1)
				MoveModeUtil.ACTION_ADD_WAYPOINT:
					# Route plotting: no command yet, just refresh the mode buttons
					# so Confirm/Cancel reflect the pending route.
					_update_move_mode_buttons()
				_:
					pass
		_:
			pass


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


# --- MC1.5 (request 1): direct / manual move-mode controls ------------------

# Toggle DIRECT <-> MANUAL. Switching modes discards any half-plotted route
# (handled inside MoveModeUtil.toggle_mode).
func _on_move_mode_pressed() -> void:
	_move_mode.toggle_mode()
	_update_move_mode_buttons()


# Confirm the plotted route: issue ONE move_unit carrying the whole waypoint
# array. units_module stitches the belief-aware path (WaypointUtil), so the unit
# travels exactly through the drawn tiles. Routed through player_command so it is
# lockstep-scheduled in a networked session (MA7.1), else applied immediately.
func _on_move_confirm_pressed() -> void:
	var plan: Dictionary = _move_mode.commit()
	if str(plan.get("action", "")) == MoveModeUtil.ACTION_MOVE_PATH and not _selected_unit_ids.is_empty():
		Nexus.player_command("move_unit", {
			"unit_ids": _selected_unit_ids.duplicate(),
			"waypoints": plan.get("waypoints", []),
		}, 1)
	_update_move_mode_buttons()


# Cancel the plotted route without moving.
func _on_move_cancel_pressed() -> void:
	_move_mode.cancel()
	_update_move_mode_buttons()


# Refresh the move-mode buttons: the toggle shows the active mode; Confirm/Cancel
# are visible only in MANUAL mode and enabled only when a route is pending.
func _update_move_mode_buttons() -> void:
	if _move_mode_button != null:
		_move_mode_button.button_pressed = _move_mode.is_manual()
		var mode_key: String = "ui.move.mode_manual" if _move_mode.is_manual() else "ui.move.mode_direct"
		_move_mode_button.text = _local_text(mode_key)
	var manual: bool = _move_mode.is_manual()
	var has_pending: bool = _move_mode.has_pending()
	if _move_confirm_button != null:
		_move_confirm_button.visible = manual
		_move_confirm_button.disabled = not has_pending
	if _move_cancel_button != null:
		_move_cancel_button.visible = manual
		_move_cancel_button.disabled = not has_pending


# Return the ids of every unit owned by `owner_filter` whose tile lies inside the
# screen-space rectangle defined by the two corner points. Thin wrapper that
# reads the live world state + adapter, then delegates to the shared, pure
# SelectionUtil helper (which the headless tests exercise directly).
func _units_in_screen_rect(p1: Vector2, p2: Vector2, owner_filter: int) -> Array:
	if _render_adapter == null:
		return []
	# MB1.2 (bug 1): restrict the box to the locally controllable owner set so AI
	# teammates are never swept in. owner_filter kept for signature compatibility.
	var units: Dictionary = Nexus.world_state.get_section("units").get("list", {})
	return SelectionUtil.units_in_screen_rect_owned_by(_render_adapter, units, p1, p2, _locally_controlled_owners())


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
	# A manual pause/resume clears any armed "leave" confirm so it cannot linger.
	_leave_armed = false
	Nexus.toggle_pause()


# MB3.3 (bug 6): the Android BACK button / gesture arrives as
# NOTIFICATION_WM_GO_BACK_REQUEST while in a match. Route it through the same
# pause-then-confirm-leave flow as ui_cancel so it never quits the app.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and is_inside_tree():
		_on_back_in_game()


# In-game BACK handling. First press pauses the sim and arms a confirm; the
# second consecutive press leaves to the main menu. Never quits the app.
func _on_back_in_game() -> void:
	if _leave_armed:
		_leave_armed = false
		_leave_to_main_menu()
		return
	_leave_armed = true
	# Pause so the match is frozen while the player decides.
	if Nexus != null and Nexus.sim_clock != null and not Nexus.sim_clock.is_paused():
		Nexus.sim_clock.pause()
	if _status_label != null:
		_status_label.text = _local_text("ui.game.confirm_leave")


func _leave_to_main_menu() -> void:
	# Resume the clock so the next match/menu is not stuck paused, then hand off.
	if Nexus != null and Nexus.sim_clock != null and Nexus.sim_clock.is_paused():
		Nexus.sim_clock.resume()
	if is_inside_tree() and get_tree() != null:
		get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func _on_build_pressed() -> void:
	# Ask the economy to build a soldier at the local HQ (cost-checked there).
	Nexus.player_command("build_unit", {
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
	_style_button.text = "%s: %s" % [_local_text("ui.game.style"), _style_label(active)]


# Map a render-style id to a short localized label for the Style button.
func _style_label(style_id: String) -> String:
	match style_id:
		RenderAdapter.STYLE_DETAILED:
			return _local_text("ui.game.style_detailed")
		RenderAdapter.STYLE_SPRITE:
			return _local_text("ui.game.style_sprite")
		_:
			return _local_text("ui.game.style_simple")


# --- Phase 2 controls -------------------------------------------------------

func _on_research_pressed() -> void:
	# Research the first affordable, not-yet-started tech node for the player.
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
	# Queue the next HQ upgrade level (cost + time checked by the module).
	Nexus.player_command("upgrade_building", {
		"building_id": _local_hq_id,
	}, 1)


func _on_fuse_pressed() -> void:
	# Fuse the currently selected units into a hero (recipe matched in module).
	if _selected_unit_ids.is_empty():
		return
	Nexus.player_command("fuse_units", {
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
		text = _local_text("ui.game.victory")
	elif winner < 0:
		text = _local_text("ui.game.draw")
	else:
		text = _local_text("ui.game.defeat")
	_overlay_label.text = text
	_overlay.visible = true
	# Stop the simulation so nothing moves behind the overlay.
	Nexus.sim_clock.pause()


# --- Helpers ----------------------------------------------------------------

func _unit_at_tile(tile: Vector2i, owner_filter: int) -> int:
	# MA6: delegate to the shared, headless-tested helper so tile hit-testing is
	# identical everywhere and deterministic when two units share a tile.
	# MB1.2 (bug 1): gate through the locally controllable owner set so an AI
	# teammate's unit on the same tile can never be selected. `owner_filter` is
	# retained for signature compatibility; the authoritative gate is
	# Nexus.is_locally_controlled (via _locally_controlled_owners()).
	var units: Dictionary = Nexus.world_state.get_section("units").get("list", {})
	return TapSelectUtil.unit_at_tile_owned_by(units, tile, _locally_controlled_owners())


# MB1.2 (bug 1 - teammate control leak): the set of owner ids the human at THIS
# device may command, derived from the single source of truth
# Nexus.is_locally_controlled. Scans the current player roster so hot-seat /
# assigned seats work; falls back to LOCAL_PLAYER when no roster is present.
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
	_build_select_mode_widgets()
	_build_move_mode_widgets()
	_build_message_panel()
	# Apply the initial responsive placement for the current orientation.
	_apply_responsive_layout()


# MA2: build the "Select" toggle button and the translucent selection rectangle.
# The button sits with the control-group panel (bottom-left, thumb-reachable);
# the SelectionBox is a full-screen overlay child drawn only while dragging.
func _build_select_mode_widgets() -> void:
	# The selection rectangle overlay (hidden until a box drag starts).
	_selection_box = ColorRect.new()
	_selection_box.name = "SelectionBox"
	_selection_box.color = Color(0.3, 0.8, 1.0, 0.25)
	_selection_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_selection_box.visible = false
	add_child(_selection_box)

	# The Select-mode toggle button. Placed just above the control-group panel.
	_select_button = Button.new()
	_select_button.name = "SelectModeButton"
	_select_button.text = _local_text("ui.game.select_mode")
	_select_button.tooltip_text = _local_text("ui.game.select_mode_hint")
	_select_button.toggle_mode = true
	_select_button.custom_minimum_size = Vector2(0, 34)
	_select_button.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_select_button.position = Vector2(12, -260)
	_select_button.pressed.connect(_on_select_mode_pressed)
	add_child(_select_button)


# MC1.5 (request 1): build the move-mode toggle plus the Confirm/Cancel buttons
# used while plotting a manual route. Placed just above the Select button
# (bottom-left, thumb-reachable). Confirm/Cancel start hidden and only appear in
# MANUAL mode with a pending route (see _update_move_mode_buttons).
func _build_move_mode_widgets() -> void:
	# MC3.3 (req 3): load the icon manifest once; apply_to_button below resolves
	# logical names with a safe fallback glyph.
	_icons.load_manifest()

	_move_mode_button = Button.new()
	_move_mode_button.name = "MoveModeButton"
	_move_mode_button.text = _local_text("ui.move.mode_direct")
	_move_mode_button.tooltip_text = _local_text("ui.move.toggle_hint")
	_move_mode_button.toggle_mode = true
	_move_mode_button.custom_minimum_size = Vector2(0, 34)
	_move_mode_button.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_move_mode_button.position = Vector2(12, -300)
	_move_mode_button.pressed.connect(_on_move_mode_pressed)
	_icons.apply_to_button(_move_mode_button, "move")
	add_child(_move_mode_button)

	_move_confirm_button = Button.new()
	_move_confirm_button.name = "MoveConfirmButton"
	_move_confirm_button.text = _local_text("ui.move.confirm_path")
	_move_confirm_button.custom_minimum_size = Vector2(0, 34)
	_move_confirm_button.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_move_confirm_button.position = Vector2(130, -300)
	_move_confirm_button.pressed.connect(_on_move_confirm_pressed)
	_icons.apply_to_button(_move_confirm_button, "play")
	add_child(_move_confirm_button)

	_move_cancel_button = Button.new()
	_move_cancel_button.name = "MoveCancelButton"
	_move_cancel_button.text = _local_text("ui.move.cancel_path")
	_move_cancel_button.custom_minimum_size = Vector2(0, 34)
	_move_cancel_button.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_move_cancel_button.position = Vector2(248, -300)
	_move_cancel_button.pressed.connect(_on_move_cancel_pressed)
	_icons.apply_to_button(_move_cancel_button, "back")
	add_child(_move_cancel_button)

	_update_move_mode_buttons()


# MC11.2/11.3/11.4 (request 11): build the "Messages" toggle button plus the
# hidden Messages panel (three tabs). The panel is built once and toggled; all
# its controls only issue authoritative diplomatic Commands via the diplomacy
# module (no WorldState mutation here), so the simulation stays deterministic.
func _build_message_panel() -> void:
	_msg_button = Button.new()
	_msg_button.name = "MessagesButton"
	_msg_button.text = _local_text("ui.msg.title")
	_msg_button.custom_minimum_size = Vector2(0, 34)
	_msg_button.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_msg_button.position = Vector2(12, -340)
	_msg_button.pressed.connect(_on_messages_pressed)
	_icons.apply_to_button(_msg_button, "message")
	add_child(_msg_button)

	_msg_panel = PanelContainer.new()
	_msg_panel.name = "MessagesPanel"
	_msg_panel.visible = false
	_msg_panel.set_anchors_preset(Control.PRESET_CENTER)
	_msg_panel.custom_minimum_size = Vector2(360, 400)
	add_child(_msg_panel)

	var tabs: TabContainer = TabContainer.new()
	tabs.name = "MessageTabs"
	_msg_panel.add_child(tabs)

	var chat_tab: Control = _build_chat_tab()
	chat_tab.name = _local_text("ui.msg.tab_chat")
	tabs.add_child(chat_tab)

	var strat_tab: Control = _build_strategic_tab()
	strat_tab.name = _local_text("ui.msg.strategic_tab")
	tabs.add_child(strat_tab)

	var mission_tab: Control = _build_mission_tab()
	mission_tab.name = _local_text("ui.msg.mission_tab")
	tabs.add_child(mission_tab)


# MC11.2: the plain "Chat" tab -- pick a recipient, read the transcript, type a
# line and Send. Sending appends a cosmetic local message (the transport of chat
# text between peers is presentation-only and out of the state hash).
func _build_chat_tab() -> Control:
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)

	var row: HBoxContainer = HBoxContainer.new()
	var to_label: Label = Label.new()
	to_label.text = _local_text("ui.msg.recipient")
	row.add_child(to_label)
	_msg_recipient = OptionButton.new()
	_populate_recipient_options(_msg_recipient)
	_msg_recipient.item_selected.connect(func(_i: int) -> void: _refresh_chat_history())
	row.add_child(_msg_recipient)
	box.add_child(row)

	_msg_history = RichTextLabel.new()
	_msg_history.custom_minimum_size = Vector2(340, 260)
	_msg_history.bbcode_enabled = false
	box.add_child(_msg_history)

	var send_row: HBoxContainer = HBoxContainer.new()
	_msg_text_edit = LineEdit.new()
	_msg_text_edit.placeholder_text = _local_text("ui.msg.text_hint")
	_msg_text_edit.custom_minimum_size = Vector2(260, 0)
	send_row.add_child(_msg_text_edit)
	var send_btn: Button = Button.new()
	send_btn.text = _local_text("ui.msg.send")
	send_btn.pressed.connect(_on_chat_send_pressed)
	send_row.add_child(send_btn)
	box.add_child(send_row)

	_refresh_chat_history()
	return box


# MC11.3: the "Strategic" tab -- pick a treaty type + target + duration and
# Propose. This issues a deterministic propose_treaty command through the
# diplomacy module (the single lockstep-safe entry point).
func _build_strategic_tab() -> Control:
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)

	var type_row: HBoxContainer = HBoxContainer.new()
	var t_label: Label = Label.new()
	t_label.text = _local_text("ui.msg.treaty_type")
	type_row.add_child(t_label)
	_treaty_type_opt = OptionButton.new()
	for type_id in TreatyUtil.TYPES:
		_treaty_type_opt.add_item(str(type_id))
	type_row.add_child(_treaty_type_opt)
	box.add_child(type_row)

	var target_row: HBoxContainer = HBoxContainer.new()
	var tg_label: Label = Label.new()
	tg_label.text = _local_text("ui.msg.recipient")
	target_row.add_child(tg_label)
	_treaty_target_opt = OptionButton.new()
	_populate_owner_options(_treaty_target_opt)
	target_row.add_child(_treaty_target_opt)
	box.add_child(target_row)

	var dur_row: HBoxContainer = HBoxContainer.new()
	var d_label: Label = Label.new()
	d_label.text = _local_text("ui.msg.treaty_duration")
	dur_row.add_child(d_label)
	_treaty_duration = SpinBox.new()
	_treaty_duration.min_value = 0
	_treaty_duration.max_value = 100000
	_treaty_duration.value = 0
	dur_row.add_child(_treaty_duration)
	box.add_child(dur_row)

	var propose_btn: Button = Button.new()
	propose_btn.text = _local_text("ui.msg.treaty_propose")
	propose_btn.pressed.connect(_on_propose_treaty_pressed)
	box.add_child(propose_btn)
	return box


# MC11.4: the "Mission" tab -- ask an ally (or self) to act on a MAP POINT:
# a target owner, a mission type, a target cell, and a commitment percentage.
# The request is validated by the pure MissionRequestUtil and carried on a
# REQUEST_ATTACK/REQUEST_DEFENSE treaty proposal (deterministic command).
func _build_mission_tab() -> Control:
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)

	var mtype_row: HBoxContainer = HBoxContainer.new()
	var mt_label: Label = Label.new()
	mt_label.text = _local_text("ui.msg.mission_tab")
	mtype_row.add_child(mt_label)
	_mission_type_opt = OptionButton.new()
	for m in MissionRequestUtil.TYPES:
		_mission_type_opt.add_item(_local_text("ui.msg.mission_" + str(m)))
	mtype_row.add_child(_mission_type_opt)
	box.add_child(mtype_row)

	var mtarget_row: HBoxContainer = HBoxContainer.new()
	var mtg_label: Label = Label.new()
	mtg_label.text = _local_text("ui.msg.recipient")
	mtarget_row.add_child(mtg_label)
	_mission_target_opt = OptionButton.new()
	_populate_owner_options(_mission_target_opt)
	mtarget_row.add_child(_mission_target_opt)
	box.add_child(mtarget_row)

	var cell_row: HBoxContainer = HBoxContainer.new()
	var c_label: Label = Label.new()
	c_label.text = _local_text("ui.msg.mission_cell")
	cell_row.add_child(c_label)
	_mission_cell_x = SpinBox.new()
	_mission_cell_x.min_value = 0
	_mission_cell_x.max_value = 100000
	cell_row.add_child(_mission_cell_x)
	_mission_cell_y = SpinBox.new()
	_mission_cell_y.min_value = 0
	_mission_cell_y.max_value = 100000
	cell_row.add_child(_mission_cell_y)
	box.add_child(cell_row)

	var commit_row: HBoxContainer = HBoxContainer.new()
	var cm_label: Label = Label.new()
	cm_label.text = _local_text("ui.msg.commitment")
	commit_row.add_child(cm_label)
	_mission_commit = HSlider.new()
	_mission_commit.min_value = MissionRequestUtil.COMMIT_MIN
	_mission_commit.max_value = MissionRequestUtil.COMMIT_MAX
	_mission_commit.value = MissionRequestUtil.COMMIT_DEFAULT
	_mission_commit.custom_minimum_size = Vector2(200, 0)
	commit_row.add_child(_mission_commit)
	box.add_child(commit_row)

	var send_btn: Button = Button.new()
	send_btn.text = _local_text("ui.msg.mission_send")
	send_btn.pressed.connect(_on_mission_send_pressed)
	box.add_child(send_btn)
	return box


# Fill an OptionButton with recipient choices from MessageLogUtil (BROADCAST +
# every other owner). Each item stores its owner id as metadata.
func _populate_recipient_options(opt: OptionButton) -> void:
	opt.clear()
	var choices: Array = MessageLogUtil.recipient_choices(_owner_count(), LOCAL_PLAYER)
	for owner in choices:
		var oid: int = int(owner)
		var label: String = _owner_label(oid)
		opt.add_item(label)
		opt.set_item_metadata(opt.item_count - 1, oid)


# Fill an OptionButton with every OTHER owner (no BROADCAST) -- used for treaty /
# mission targets, which must name a single counterpart.
func _populate_owner_options(opt: OptionButton) -> void:
	opt.clear()
	for o in range(_owner_count()):
		if o == LOCAL_PLAYER:
			continue
		opt.add_item(_owner_label(o))
		opt.set_item_metadata(opt.item_count - 1, o)


# A localized label for an owner id (BROADCAST => "Everyone").
func _owner_label(owner: int) -> String:
	if owner == MessageLogUtil.BROADCAST:
		return _local_text("ui.msg.broadcast")
	return _local_text("ui.msg.player").replace("{id}", str(owner))


# The number of owners/seats in the current match, derived from match.teams
# (deterministic world state). Falls back to 2 so the panel is always usable.
func _owner_count() -> int:
	var teams: Dictionary = Nexus.world_state.get_section("match").get("teams", {})
	var maxo: int = LOCAL_PLAYER
	for k in teams.keys():
		maxo = max(maxo, int(str(k)))
	return max(2, maxo + 1)


# Return the owner id currently selected in an OptionButton (its metadata), or a
# fallback when nothing is selected.
func _selected_owner(opt: OptionButton, fallback: int) -> int:
	if opt == null or opt.selected < 0:
		return fallback
	var meta = opt.get_item_metadata(opt.selected)
	return int(meta) if meta != null else fallback


# Toggle the Messages panel open/closed.
func _on_messages_pressed() -> void:
	if _msg_panel == null:
		return
	_msg_panel.visible = not _msg_panel.visible
	if _msg_panel.visible:
		_refresh_chat_history()


# MC11.2: append the typed line to the local transcript and refresh the view.
# Chat text is cosmetic transport, so it does NOT go through the state hash.
func _on_chat_send_pressed() -> void:
	if _msg_text_edit == null:
		return
	var text: String = _msg_text_edit.text.strip_edges()
	if text == "":
		return
	var recipient: int = _selected_owner(_msg_recipient, MessageLogUtil.BROADCAST)
	var msg: Dictionary = MessageLogUtil.make_message(
		LOCAL_PLAYER, recipient, text, int(Nexus.world_state.current_tick))
	MessageLogUtil.append_message(_msg_log, msg)
	_msg_text_edit.text = ""
	_refresh_chat_history()


# Rebuild the chat transcript view for the currently selected recipient.
func _refresh_chat_history() -> void:
	if _msg_history == null:
		return
	var recipient: int = _selected_owner(_msg_recipient, MessageLogUtil.BROADCAST)
	var shown: Array
	if recipient == MessageLogUtil.BROADCAST:
		shown = MessageLogUtil.filter_for_owner(_msg_log, LOCAL_PLAYER)
	else:
		shown = MessageLogUtil.conversation(_msg_log, LOCAL_PLAYER, recipient)
	if shown.is_empty():
		_msg_history.text = _local_text("ui.msg.no_messages")
		return
	var lines: Array = []
	for m in shown:
		var md: Dictionary = m as Dictionary
		lines.append("[%d] %s -> %s: %s" % [
			int(md.get("tick", 0)),
			_owner_label(int(md.get("sender", 0))),
			_owner_label(int(md.get("recipient", MessageLogUtil.BROADCAST))),
			str(md.get("text", "")),
		])
	_msg_history.text = "\n".join(lines)


# MC11.3: build a treaty from the strategic tab and issue a deterministic
# propose_treaty command through the diplomacy module.
func _on_propose_treaty_pressed() -> void:
	var diplomacy: Object = Nexus.get_module("diplomacy")
	if diplomacy == null:
		return
	var type_id: String = str(TreatyUtil.TYPES[max(0, _treaty_type_opt.selected)])
	var target: int = _selected_owner(_treaty_target_opt, LOCAL_PLAYER)
	if target == LOCAL_PLAYER:
		return
	var duration: int = int(_treaty_duration.value)
	var treaty: Dictionary = TreatyUtil.make_treaty(
		type_id, LOCAL_PLAYER, target, {}, {}, duration,
		int(Nexus.world_state.current_tick))
	if not TreatyUtil.is_valid(treaty):
		return
	diplomacy.issue_propose(LOCAL_PLAYER, treaty)
	# Echo a cosmetic line into the transcript so the player sees what was sent.
	MessageLogUtil.append_message(_msg_log, MessageLogUtil.make_message(
		LOCAL_PLAYER, target,
		_local_text("ui.msg.treaty_propose") + ": " + type_id,
		int(Nexus.world_state.current_tick),
		MessageLogUtil.CHANNEL_STRATEGIC, { "treaty": treaty }))


# MC11.4: build a mission request from the mission tab, validate it with the
# pure MissionRequestUtil, and carry it as a REQUEST_ATTACK/REQUEST_DEFENSE
# treaty proposal (deterministic command). Unknown mission types map to attack.
func _on_mission_send_pressed() -> void:
	var diplomacy: Object = Nexus.get_module("diplomacy")
	if diplomacy == null:
		return
	var target: int = _selected_owner(_mission_target_opt, LOCAL_PLAYER)
	if target == LOCAL_PLAYER:
		return
	var mtype: String = str(MissionRequestUtil.TYPES[max(0, _mission_type_opt.selected)])
	var mission: Dictionary = MissionRequestUtil.make_mission(
		LOCAL_PLAYER, target, mtype,
		int(_mission_cell_x.value), int(_mission_cell_y.value),
		int(_mission_commit.value))
	if not MissionRequestUtil.is_valid(mission):
		return
	var treaty_type: String = TreatyUtil.REQUEST_DEFENSE if mtype == MissionRequestUtil.DEFEND else TreatyUtil.REQUEST_ATTACK
	var treaty: Dictionary = TreatyUtil.make_treaty(
		treaty_type, LOCAL_PLAYER, target, { "mission": mission }, {}, 0,
		int(Nexus.world_state.current_tick))
	if not TreatyUtil.is_valid(treaty):
		return
	diplomacy.issue_propose(LOCAL_PLAYER, treaty)
	MessageLogUtil.append_message(_msg_log, MessageLogUtil.make_message(
		LOCAL_PLAYER, target,
		_local_text("ui.msg.mission_send") + ": " + mtype,
		int(Nexus.world_state.current_tick),
		MessageLogUtil.CHANNEL_STRATEGIC, { "mission": mission }))


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
	if not ControlGroupUtil.is_valid_slot(slot) or slot >= _control_groups.size():
		return
	if _assign_mode:
		# Store the current selection as a clean, sorted, de-duplicated group so
		# recall is deterministic (MA3).
		_control_groups[slot] = ControlGroupUtil.normalise_ids(_selected_unit_ids)
		_refresh_control_group_labels()
		# One-shot assign: turn the toggle back off for convenience.
		_assign_mode = false
		if _assign_button != null:
			_assign_button.button_pressed = false
		return
	# Recall: drop any units that no longer exist, then select + focus.
	var units: Dictionary = Nexus.world_state.get_section("units").get("list", {})
	var living: Array = ControlGroupUtil.prune_living(_control_groups[slot], units)
	_control_groups[slot] = living
	# Keep the slot's count label in sync after pruning dead units (MA3 fix:
	# previously the label went stale once units in a group died).
	_refresh_control_group_labels()
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
		_group_buttons[i].text = ControlGroupUtil.button_label(i, count)


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
		total_hp += int(u.get("health", 0))
		total_max_hp += int(u.get("max_health", u.get("health", 0)))
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
