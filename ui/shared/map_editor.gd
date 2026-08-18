# map_editor.gd
# ----------------------------------------------------------------------------
# Project Nexus - Graphical Map / Scenario Editor screen (Phase E, steps E.1-E.6).
#
# The view layer of the Map Editor. Like the Mod Editor (Phase D) it is THIN:
# every piece of authoring logic (resize / brush / fill / place entity / edit
# rules / build a tech node / validate / save) lives in the fully headless-tested
# `ScenarioProject` model (`tools/scenario_project.gd`). This scene only:
#   - draws the current map grid + entities on a TileGrid control,
#   - maps tool clicks + slider edits onto the model's API,
#   - resolves every visible label through the Localization service, and
#   - bundles the finished scenario into a `.nexpack` (via `ModProject`) saved to
#     the same content root the game loads from, so a saved scenario is listed in
#     Custom Games (E.7) and immediately play-testable.
#
# It uses the same /root/Nexus singleton + GameSettings the other UI scenes rely
# on and degrades gracefully when run in isolation (e.g. a headless smoke test).
#
# CODE LANGUAGE POLICY: English-only identifiers/comments; all visible text via
# Localization (English keys -> localized display text).
# ----------------------------------------------------------------------------
extends Control

const MAIN_MENU_SCENE: String = "res://scenes/main_menu.tscn"
# Playtest resolves the game scene (mobile vs desktop HUD) from the GLOBAL
# ui_mode preference, same as Match Setup -- a fixed scene would force the
# mobile HUD onto desktop players.
const MOBILE_SCENE: String = "res://scenes/game_main.tscn"
const DESKTOP_SCENE: String = "res://scenes/game_desktop.tscn"
# MB10.2 (bug 29): shared loading overlay shown while a map pack is written.
const ProgressOverlayScript = preload("res://ui/shared/progress_overlay.gd")

# The currently selected tool. One of the TOOL_* constants below.
const TOOL_WALL: String = "wall"
const TOOL_GROUND: String = "ground"
const TOOL_HQ: String = "hq"
const TOOL_UNIT: String = "unit"
const TOOL_FLAG: String = "flag"  # P7.1 (R10.5): place a CTF/HQ flag spot
const TOOL_ERASE_ENTITY: String = "erase_entity"

var _project: ScenarioProject = null
var _loc: Localization = null
var _settings: GameSettings = null
var _storage: StorageService = null
# MC5.2 (request 6): undo/redo history of full scenario snapshots. Every edit
# funnels through `_after_edit`, which records a snapshot; `ui_undo`/`ui_redo`
# (and the toolbar buttons) restore the project from a stored snapshot. The
# restore itself must NOT record a new snapshot, hence the `_restoring` guard.
var _history: EditHistoryUtil = EditHistoryUtil.new()
var _restoring: bool = false

# MC5.4 (request 6): throttled autosave of the scenario draft to
# user://autosave/map.autosave.json so an unexpected exit never loses work; on
# the next entry the editor offers to recover it. Cosmetic to the sim.
var _autosave: AutosaveUtil = AutosaveUtil.new()

var _active_tool: String = TOOL_WALL
var _active_owner: int = 0
# The unit/building type the place tools spawn (kept simple for the core editor).
var _unit_type: String = "soldier"
var _building_type: String = "hq"

# Cached node refs are resolved defensively so the controller can also run in a
# headless smoke test where the full scene tree may be absent.
var _grid: Control = null
var _status_label: Label = null
# MB10.2 (bug 29): the loading overlay, created lazily on first save.
var _overlay: ProgressOverlay = null


func _ready() -> void:
	_loc = Localization.new()
	_loc.load_all("res://localization")
	_settings = GameSettings.new(_world_state())
	_settings.load_from_file()
	_loc.set_locale(_settings.get_locale())
	# Phase G: apply the persisted GUI scale so the editor matches Options.
	UiScale.apply_with_settings(self, _settings)
	_storage = StorageService.new(_settings.get_content_path())
	_storage.ensure_content_root()

	_project = ScenarioProject.new()
	_project.new_scenario("new_scenario", "New Scenario")

	_grid = get_node_or_null("Root/Body/GridPanel/TileGrid")
	_status_label = get_node_or_null("Root/Footer/StatusLabel")
	_wire_controls()
	_refresh_all()
	# MC5.2 (request 6): seed the history with the initial (empty) scenario so the
	# very first edit has a baseline state to undo back to.
	_record_history()


# --- Control wiring (defensive: only connects nodes that exist) -------------

func _wire_controls() -> void:
	_connect_button("Root/Body/Tools/WallTool", func(): _set_tool(TOOL_WALL))
	_connect_button("Root/Body/Tools/GroundTool", func(): _set_tool(TOOL_GROUND))
	_connect_button("Root/Body/Tools/HqTool", func(): _set_tool(TOOL_HQ))
	_connect_button("Root/Body/Tools/UnitTool", func(): _set_tool(TOOL_UNIT))
	_connect_button("Root/Body/Tools/FlagTool", func(): _set_tool(TOOL_FLAG))
	_connect_button("Root/Body/Tools/EraseEntityTool", func(): _set_tool(TOOL_ERASE_ENTITY))
	_connect_button("Root/Body/Tools/FillButton", _on_fill)
	_connect_button("Root/Body/Tools/BorderButton", func(): _project.paint_border(); _after_edit("painted"))
	_connect_button("Root/Body/Tools/ClearButton", func(): _project.clear_walls(); _after_edit("painted"))
	_connect_button("Root/Footer/NewButton", _on_new)
	_connect_button("Root/Footer/SaveButton", _on_save)
	_connect_button("Root/Footer/PlaytestButton", _on_playtest)
	_connect_button("Root/Footer/BackButton", _on_back)
	# MC5.2 (request 6): optional toolbar undo/redo buttons (present when the scene
	# provides them; the keyboard actions below work regardless).
	_connect_button("Root/Body/Tools/UndoButton", _do_undo)
	_connect_button("Root/Body/Tools/RedoButton", _do_redo)
	if _grid != null and _grid.has_signal("cell_clicked"):
		_grid.connect("cell_clicked", Callable(self, "_on_cell_clicked"))


func _connect_button(path: String, cb: Callable) -> void:
	var b: Button = get_node_or_null(path)
	if b != null:
		b.pressed.connect(cb)


# --- Tools ------------------------------------------------------------------

func _set_tool(tool: String) -> void:
	_active_tool = tool
	_refresh_labels()


func _on_cell_clicked(x: int, y: int) -> void:
	match _active_tool:
		TOOL_WALL:
			_project.paint_cell(x, y, ScenarioProject.TERRAIN_WALL)
			_after_edit("painted")
		TOOL_GROUND:
			_project.paint_cell(x, y, ScenarioProject.TERRAIN_GROUND)
			_after_edit("painted")
		TOOL_HQ:
			_project.place_building(_building_type, _active_owner, x, y)
			_after_edit("placed")
		TOOL_UNIT:
			_project.place_unit(_unit_type, _active_owner, x, y)
			_after_edit("placed")
		TOOL_FLAG:
			# P7.1 (R10.5): flags carry a stable index + the active owner's team id.
			# Clicking an existing flag cell removes it (toggle), otherwise the next
			# free index is placed there for the active owner.
			if not (_project.flag_at(x, y) as Dictionary).is_empty():
				_project.remove_flag_at(x, y)
				_after_edit("flag_removed")
			elif _project.place_flag(_project.next_flag_index(), x, y, _active_owner):
				_after_edit("flag_placed")
		TOOL_ERASE_ENTITY:
			_project.remove_entity_at(x, y)
			_after_edit("placed")


func _on_fill() -> void:
	# Fill the whole map with the current terrain (wall tool -> walls, else clears).
	var terrain: String = ScenarioProject.TERRAIN_WALL if _active_tool == TOOL_WALL else ScenarioProject.TERRAIN_GROUND
	_project.fill_rect(0, 0, _project.width - 1, _project.height - 1, terrain)
	_after_edit("painted")


func set_active_owner(owner_id: int) -> void:
	_active_owner = max(0, owner_id)
	_refresh_labels()


# --- Lifecycle / save / play-test (E.6 / E.7) -------------------------------

func _on_new() -> void:
	_project.new_scenario("new_scenario", "New Scenario")
	_set_status(_loc.t("ui.mapeditor.status.new"))
	_refresh_all()
	# MC5.2 (request 6): a fresh scenario resets the undo history to a new baseline.
	_history.clear()
	_record_history()


func _on_save() -> void:
	var problems: Array = _project.validate()
	if not problems.is_empty():
		_set_status("%s: %s" % [_loc.t("ui.mapeditor.status.invalid"), str(problems[0])])
		return
	# MB10.2 (bug 29): writing the .nexpack can block briefly, so drive the shared
	# ProgressOverlay through the OP_SAVE_MAP stage plan (Saving... -> Saved) so
	# the editor never looks frozen during the write.
	_begin_overlay(LoadingStages.OP_SAVE_MAP)
	# Bundle the scenario (and any authored tech) into a .nexpack so it loads
	# through the SAME ModLoader the game uses (E.6).
	var pack: ModProject = build_pack()
	var out_path: String = _storage.resolve_pack(pack.get_id())
	var ok: bool = pack.save_pack(out_path)
	_finish_overlay()
	if ok:
		_set_status("%s %s" % [_loc.t("ui.mapeditor.status.saved"), out_path])
	else:
		_set_status(_loc.t("ui.mapeditor.status.save_failed"))


# MB10.2 (bug 29): show the shared overlay for a determinate operation described
# by LoadingStages, starting at its first stage. Created lazily and kept alive
# (finished with keep=true) so it can be reused for the next save.
func _begin_overlay(op: String) -> void:
	if not _has_tree():
		return
	if _overlay == null:
		_overlay = ProgressOverlayScript.new()
		add_child(_overlay)
	_overlay.begin(_loc.t(LoadingStages.title_key(op)), _loc.t(LoadingStages.stage_key(op, 0)))


func _finish_overlay() -> void:
	if _overlay != null:
		_overlay.finish(true)
		_overlay.visible = false


# Assemble the editor's scenario + tech into a ModProject ready to write. Kept
# public + side-effect-free so a headless test can build + inspect it directly.
func build_pack() -> ModProject:
	var pack: ModProject = ModProject.new()
	pack.new_project(_project.scenario_id, _project.display_name)
	pack.set_scenario(_project.scenario_id, _project.to_scenario())
	for tid in _project.tech.keys():
		pack.set_tech(str(tid), _project.tech[tid])
	return pack


func _on_playtest() -> void:
	# Save then launch the playable scene with this scenario selected (D.8-style
	# one-click test). The save guarantees it is loadable through the pipeline; we
	# stash the chosen id so the game scene can pick it up.
	_on_save()
	if not _project.is_valid():
		return
	var ws: WorldState = _world_state()
	if ws != null:
		ws.get_section("editor")["playtest_scenario"] = _project.scenario_id
	if _has_tree():
		get_tree().change_scene_to_file(_resolve_game_scene())


func _on_back() -> void:
	if _has_tree():
		get_tree().change_scene_to_file(MAIN_MENU_SCENE)


# MB3.2 (bug 6): the Android BACK button / gesture arrives as
# NOTIFICATION_WM_GO_BACK_REQUEST; ESC / gamepad-B arrive as the "ui_cancel"
# action. Both must return to the main menu (NavService parent), never quit the
# app.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and is_inside_tree():
		_on_back()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and is_inside_tree():
		get_viewport().set_input_as_handled()
		_on_back()
		return
	# MC5.2 (request 6): keyboard undo/redo (Ctrl+Z / Ctrl+Y or Ctrl+Shift+Z).
	if event.is_action_pressed("ui_undo") and is_inside_tree():
		get_viewport().set_input_as_handled()
		_do_undo()
		return
	if event.is_action_pressed("ui_redo") and is_inside_tree():
		get_viewport().set_input_as_handled()
		_do_redo()


# --- Rendering --------------------------------------------------------------

func _after_edit(status_key: String) -> void:
	_set_status(_loc.t("ui.mapeditor.status." + status_key))
	_refresh_grid()
	# MC5.2 (request 6): capture the post-edit state so it can be undone. Skipped
	# while we are restoring a snapshot to avoid recording the restore itself.
	_record_history()
	# MC5.4 (request 6): throttled autosave of the current draft (no-op while
	# restoring, and rate-limited so rapid edits do not thrash the disk).
	_maybe_autosave()


# --- Autosave (MC5.4, request 6) --------------------------------------------

# Persist the current scenario as the rolling "map" autosave draft, throttled by
# AutosaveUtil so a burst of edits writes at most once per interval. No-op during
# a restore (undo/redo should not overwrite the recovery draft with itself).
func _maybe_autosave() -> void:
	if _restoring or _project == null:
		return
	_autosave.maybe_autosave(AutosaveUtil.KIND_MAP, _project.to_scenario())


# Offer to recover a previous autosave draft if one is present and non-empty.
# Returns the recovered scenario snapshot (Dictionary) or an empty Dictionary
# when there is nothing to recover. The caller decides whether to apply it.
func peek_autosave_recovery() -> Dictionary:
	var parsed: Dictionary = _autosave.read_snapshot(AutosaveUtil.KIND_MAP)
	if not AutosaveUtil.should_offer_recovery(parsed, AutosaveUtil.KIND_MAP):
		return {}
	return parsed.get("snapshot", {}) as Dictionary


# Apply a recovered scenario snapshot into the project (used after the recovery
# prompt is accepted). Seeds history so the recovered state is undoable.
func apply_autosave_recovery(snapshot: Dictionary) -> void:
	if snapshot.is_empty() or _project == null:
		return
	_restore_snapshot(snapshot)
	_history.clear()
	_record_history()


# --- Undo / redo (MC5.2, request 6) -----------------------------------------

# Push a snapshot of the current scenario onto the history stack. No-op while a
# restore is in progress (the `_restoring` guard) so undo/redo do not fork the
# future.
func _record_history() -> void:
	if _restoring:
		return
	_history.push(_project.to_scenario())


# Step back one edit, restoring the scenario to its previous state.
func _do_undo() -> void:
	if not _history.can_undo():
		_set_status(_loc.t("ui.mapeditor.status.undo_none"))
		return
	var snap: Variant = _history.undo()
	_restore_snapshot(snap)
	_set_status(_loc.t("ui.mapeditor.status.undo"))


# Re-apply an undone edit.
func _do_redo() -> void:
	if not _history.can_redo():
		_set_status(_loc.t("ui.mapeditor.status.redo_none"))
		return
	var snap: Variant = _history.redo()
	_restore_snapshot(snap)
	_set_status(_loc.t("ui.mapeditor.status.redo"))


# Load a stored snapshot back into the project without recording a new history
# entry (guarded so `_after_edit` -> `_record_history` becomes a no-op).
func _restore_snapshot(snapshot: Variant) -> void:
	if not (snapshot is Dictionary):
		return
	_restoring = true
	_project.from_scenario(snapshot)
	_restoring = false
	_refresh_all()


func _refresh_all() -> void:
	_refresh_grid()
	_refresh_labels()


func _refresh_grid() -> void:
	if _grid != null and _grid.has_method("set_scenario"):
		_grid.call("set_scenario", _project)


func _refresh_labels() -> void:
	_set_text("Root/Header/Title", _loc.t("ui.mapeditor.title"))
	_set_text("Root/Body/Tools/WallTool", _loc.t("ui.mapeditor.tool.wall"))
	_set_text("Root/Body/Tools/GroundTool", _loc.t("ui.mapeditor.tool.ground"))
	_set_text("Root/Body/Tools/HqTool", _loc.t("ui.mapeditor.tool.hq"))
	_set_text("Root/Body/Tools/UnitTool", _loc.t("ui.mapeditor.tool.unit"))
	_set_text("Root/Body/Tools/FlagTool", _loc.t("ui.mapeditor.tool.flag"))
	_set_text("Root/Body/Tools/EraseEntityTool", _loc.t("ui.mapeditor.tool.erase_entity"))
	_set_text("Root/Body/Tools/FillButton", _loc.t("ui.mapeditor.tool.fill"))
	_set_text("Root/Body/Tools/BorderButton", _loc.t("ui.mapeditor.tool.border"))
	_set_text("Root/Body/Tools/ClearButton", _loc.t("ui.mapeditor.tool.clear"))
	_set_text("Root/Body/Tools/UndoButton", _loc.t("ui.mapeditor.tool.undo"))
	_set_text("Root/Body/Tools/RedoButton", _loc.t("ui.mapeditor.tool.redo"))
	_set_text("Root/Footer/NewButton", _loc.t("ui.mapeditor.new"))
	_set_text("Root/Footer/SaveButton", _loc.t("ui.mapeditor.save"))
	_set_text("Root/Footer/PlaytestButton", _loc.t("ui.mapeditor.playtest"))
	_set_text("Root/Footer/BackButton", _loc.t("ui.custom.back"))


func _set_text(path: String, value: String) -> void:
	var n: Node = get_node_or_null(path)
	if n != null and ("text" in n):
		n.text = value


func _set_status(text: String) -> void:
	if _status_label != null:
		_status_label.text = text


# --- Helpers ----------------------------------------------------------------

func _world_state() -> WorldState:
	var nexus: Node = get_node_or_null("/root/Nexus")
	if nexus != null and nexus.get("world_state") != null:
		return nexus.world_state
	return null


func _has_tree() -> bool:
	return is_inside_tree() and get_tree() != null


# Pick the game scene from the global ui_mode preference (same logic as Match
# Setup) so a play-test opens with the right HUD on every device.
func _resolve_game_scene() -> String:
	var setting: String = _settings.get_ui_mode() if _settings != null else "auto"
	var is_mobile: bool = OS.has_feature("mobile")
	var has_touch: bool = DisplayServer.is_touchscreen_available()
	var short_edge: float = 0.0
	var vp: Viewport = get_viewport()
	if vp != null:
		var vs: Vector2 = vp.get_visible_rect().size
		short_edge = minf(vs.x, vs.y)
	var resolved: String = GameSettings.resolve_ui_mode_for(setting, is_mobile, has_touch, short_edge)
	return MOBILE_SCENE if resolved == "mobile" else DESKTOP_SCENE
