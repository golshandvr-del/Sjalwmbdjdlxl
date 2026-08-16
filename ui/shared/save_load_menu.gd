# save_load_menu.gd
# ----------------------------------------------------------------------------
# Project Nexus - Save / Load + Export / Import screen (Phase P4 / R3+R4+R5).
#
# The single player-facing surface over the save & portable-content stack that
# the R3/R4/R5 core components (SaveManager, ModPackManager) already implement.
# Like every other menu screen it is a thin VIEW: it never touches WorldState or
# the simulation directly, it only asks the managers to do their job and renders
# the result.
#
# What the player can do here:
#   R3 - Save the current game under a name, load a listed save, delete a save.
#   R4 - Export a single save to an arbitrary path (SD card / shared folder) and
#        import one back, so a match travels between devices.
#   R5 - Export ALL currently-active content (units / buildings / objects /
#        scenarios / tech) into one portable `.nexpack`, and import + activate
#        such a pack.
#
# Everything that can actually change the game (loading a save) hands off to the
# game scene; everything else stays on this screen and just refreshes the list
# and a status line.
#
# All node lookups use get_node_or_null so the script is robust to the scene
# being built incrementally (same defensive style as custom_games.gd). All
# visible text is routed through the Localization service (English keys ->
# localized display text); nothing is hard-coded in a human language.
#
# CODE LANGUAGE POLICY: English-only identifiers/comments.
# ----------------------------------------------------------------------------
extends Control

const MAIN_MENU_SCENE: String = "res://scenes/main_menu.tscn"
# Loading a save resumes a game scene; which one (mobile vs desktop HUD) is
# resolved from the GLOBAL ui_mode preference at load time (_resolve_game_scene),
# exactly like Match Setup does -- a fixed scene here would force the mobile HUD
# onto desktop players.
const MOBILE_SCENE: String = "res://scenes/game_main.tscn"
const DESKTOP_SCENE: String = "res://scenes/game_desktop.tscn"

# File-dialog filters for the two portable formats.
const SAVE_FILTER: String = "*.nexsave ; Nexus Save"
const PACK_FILTER: String = "*.nexpack ; Nexus Content Pack"

# What an in-progress FileDialog is doing, so one shared dialog can serve every
# export/import action without four separate dialog nodes.
enum FileMode { NONE, EXPORT_SAVE, IMPORT_SAVE, EXPORT_PACK, IMPORT_PACK }

var _loc: Localization = null
var _save_manager: SaveManager = null
var _pack_manager: ModPackManager = null

# The list of saves currently shown (parallel to the ItemList rows).
var _saves: Array = []
# What the shared FileDialog is currently doing.
var _file_mode: int = FileMode.NONE

# --- Node refs (all optional; resolved defensively) -------------------------
@onready var _title: Label = get_node_or_null("Root/Title")
@onready var _status: Label = get_node_or_null("Root/Status")

# Save list + its controls.
@onready var _list: ItemList = get_node_or_null("Root/SaveList")
@onready var _empty_label: Label = get_node_or_null("Root/EmptyLabel")
@onready var _name_edit: LineEdit = get_node_or_null("Root/SaveRow/NameEdit")
@onready var _save_button: Button = get_node_or_null("Root/SaveRow/SaveButton")
@onready var _load_button: Button = get_node_or_null("Root/Actions/LoadButton")
@onready var _delete_button: Button = get_node_or_null("Root/Actions/DeleteButton")

# R4 - per-save portability.
@onready var _export_save_button: Button = get_node_or_null("Root/Actions/ExportSaveButton")
@onready var _import_save_button: Button = get_node_or_null("Root/Actions/ImportSaveButton")

# R5 - whole-content pack portability.
@onready var _export_pack_button: Button = get_node_or_null("Root/PackRow/ExportPackButton")
@onready var _import_pack_button: Button = get_node_or_null("Root/PackRow/ImportPackButton")

@onready var _back_button: Button = get_node_or_null("Root/Footer/BackButton")

# Shared file picker for export/import. Created lazily if the scene omits one.
@onready var _file_dialog: FileDialog = get_node_or_null("FileDialog")


func _ready() -> void:
	_loc = Localization.new()
	_loc.load_all("res://localization")

	# Match the rest of the UI: honour the persisted locale + GUI scale.
	var settings: GameSettings = GameSettings.new(_world_state())
	settings.load_from_file()
	_loc.set_locale(settings.get_locale())
	UiScale.apply_with_settings(self, settings)

	# Bring the core up to a known state so both managers have something to work
	# with even on a cold entry straight into this screen.
	GameBootstrap.register_modules(Nexus)
	GameBootstrap.load_catalogs(Nexus)

	_save_manager = SaveManager.new()
	_save_manager.setup(Nexus)
	_pack_manager = ModPackManager.new()
	_pack_manager.setup(Nexus)

	_ensure_file_dialog()
	_connect_signals()
	_refresh()


# --- Wiring -----------------------------------------------------------------

func _connect_signals() -> void:
	if _save_button != null:
		_save_button.pressed.connect(_on_save)
	if _load_button != null:
		_load_button.pressed.connect(_on_load)
	if _delete_button != null:
		_delete_button.pressed.connect(_on_delete)
	if _export_save_button != null:
		_export_save_button.pressed.connect(_on_export_save)
	if _import_save_button != null:
		_import_save_button.pressed.connect(_on_import_save)
	if _export_pack_button != null:
		_export_pack_button.pressed.connect(_on_export_pack)
	if _import_pack_button != null:
		_import_pack_button.pressed.connect(_on_import_pack)
	if _back_button != null:
		_back_button.pressed.connect(_on_back)
	if _list != null:
		_list.item_selected.connect(func(_i: int) -> void: _update_action_buttons())
		_list.item_activated.connect(func(_i: int) -> void: _on_load())
	if _file_dialog != null:
		_file_dialog.file_selected.connect(_on_file_selected)


# Create a usable FileDialog if the scene did not ship one, so export/import are
# always available. It is added as a direct child (a sibling of Root).
func _ensure_file_dialog() -> void:
	if _file_dialog != null:
		return
	var dialog: FileDialog = FileDialog.new()
	dialog.name = "FileDialog"
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.use_native_dialog = true
	dialog.size = Vector2i(720, 480)
	add_child(dialog)
	_file_dialog = dialog


# --- Rendering --------------------------------------------------------------

func _refresh() -> void:
	_apply_labels()
	_reload_saves()
	_update_action_buttons()


func _apply_labels() -> void:
	if _title != null:
		_title.text = _loc.t("ui.saveload.title")
	if _status != null:
		_status.text = ""
	if _name_edit != null:
		_name_edit.placeholder_text = _loc.t("ui.saveload.name_hint")
	if _save_button != null:
		_save_button.text = _loc.t("ui.saveload.save")
	if _load_button != null:
		_load_button.text = _loc.t("ui.saveload.load")
	if _delete_button != null:
		_delete_button.text = _loc.t("ui.saveload.delete")
	if _export_save_button != null:
		_export_save_button.text = _loc.t("ui.saveload.export_save")
	if _import_save_button != null:
		_import_save_button.text = _loc.t("ui.saveload.import_save")
	if _export_pack_button != null:
		_export_pack_button.text = _loc.t("ui.saveload.export_pack")
	if _import_pack_button != null:
		_import_pack_button.text = _loc.t("ui.saveload.import_pack")
	if _back_button != null:
		_back_button.text = _loc.t("ui.saveload.back")


func _reload_saves() -> void:
	_saves = _save_manager.list_saves() if _save_manager != null else []
	if _list != null:
		_list.clear()
		for entry in _saves:
			_list.add_item(_format_save_row(entry))
	var empty: bool = _saves.is_empty()
	if _empty_label != null:
		_empty_label.visible = empty
		_empty_label.text = _loc.t("ui.saveload.empty")


# Human-readable one-line summary: "<name>  -  tick 1234  -  2024-01-15 18:30".
func _format_save_row(entry: Dictionary) -> String:
	var name: String = str(entry.get("name", entry.get("slot_id", "")))
	var tick: int = int(entry.get("tick", 0))
	var when: String = _format_time(int(entry.get("saved_at", 0)))
	return "%s  -  %s %d  -  %s" % [name, _loc.t("ui.saveload.tick"), tick, when]


func _format_time(unix: int) -> String:
	if unix <= 0:
		return "-"
	var dt: Dictionary = Time.get_datetime_dict_from_unix_time(unix)
	return "%04d-%02d-%02d %02d:%02d" % [
		int(dt.get("year", 0)), int(dt.get("month", 0)), int(dt.get("day", 0)),
		int(dt.get("hour", 0)), int(dt.get("minute", 0)),
	]


# Load / delete / export-save only make sense with a selection.
func _update_action_buttons() -> void:
	var has_selection: bool = _selected_index() >= 0
	if _load_button != null:
		_load_button.disabled = not has_selection
	if _delete_button != null:
		_delete_button.disabled = not has_selection
	if _export_save_button != null:
		_export_save_button.disabled = not has_selection


# --- R3: save / load / delete ----------------------------------------------

func _on_save() -> void:
	if _save_manager == null:
		return
	var display_name: String = ""
	if _name_edit != null:
		display_name = _name_edit.text.strip_edges()
	if display_name == "":
		display_name = _loc.t("ui.saveload.default_name")
	var slot_id: String = _save_manager.save_game(display_name)
	if slot_id == "":
		_set_status("ui.saveload.status.save_failed")
		return
	_set_status("ui.saveload.status.saved")
	_reload_saves()
	_update_action_buttons()


func _on_load() -> void:
	var entry: Dictionary = _selected_entry()
	if entry.is_empty() or _save_manager == null:
		return
	var slot_id: String = str(entry.get("slot_id", ""))
	if not _save_manager.load_game(slot_id):
		_set_status("ui.saveload.status.load_failed")
		return
	# The live game now holds the restored state; resume the game scene that
	# matches the player's interface preference (mobile vs desktop HUD).
	if _has_tree():
		get_tree().change_scene_to_file(_resolve_game_scene())


func _on_delete() -> void:
	var entry: Dictionary = _selected_entry()
	if entry.is_empty() or _save_manager == null:
		return
	if _save_manager.delete_game(str(entry.get("slot_id", ""))):
		_set_status("ui.saveload.status.deleted")
	else:
		_set_status("ui.saveload.status.delete_failed")
	_reload_saves()
	_update_action_buttons()


# --- R4 / R5: export & import (via the shared FileDialog) --------------------

func _on_export_save() -> void:
	var entry: Dictionary = _selected_entry()
	if entry.is_empty():
		return
	var suggested: String = "%s.%s" % [str(entry.get("slot_id", "save")), SaveManager.SAVE_EXT]
	_open_file_dialog(FileMode.EXPORT_SAVE, FileDialog.FILE_MODE_SAVE_FILE, SAVE_FILTER, suggested)


func _on_import_save() -> void:
	_open_file_dialog(FileMode.IMPORT_SAVE, FileDialog.FILE_MODE_OPEN_FILE, SAVE_FILTER)


func _on_export_pack() -> void:
	_open_file_dialog(FileMode.EXPORT_PACK, FileDialog.FILE_MODE_SAVE_FILE, PACK_FILTER,
		"exported_content." + StorageService.PACK_EXTENSION)


func _on_import_pack() -> void:
	_open_file_dialog(FileMode.IMPORT_PACK, FileDialog.FILE_MODE_OPEN_FILE, PACK_FILTER)


func _open_file_dialog(mode: int, file_mode: int, filter: String, suggested_name: String = "") -> void:
	if _file_dialog == null:
		_set_status("ui.saveload.status.no_dialog")
		return
	_file_mode = mode
	_file_dialog.file_mode = file_mode
	_file_dialog.clear_filters()
	_file_dialog.add_filter(filter)
	if suggested_name != "":
		_file_dialog.current_file = suggested_name
	_file_dialog.popup_centered()


func _on_file_selected(path: String) -> void:
	match _file_mode:
		FileMode.EXPORT_SAVE:
			_do_export_save(path)
		FileMode.IMPORT_SAVE:
			_do_import_save(path)
		FileMode.EXPORT_PACK:
			_do_export_pack(path)
		FileMode.IMPORT_PACK:
			_do_import_pack(path)
		_:
			pass
	_file_mode = FileMode.NONE


func _do_export_save(dest_path: String) -> void:
	var entry: Dictionary = _selected_entry()
	if entry.is_empty() or _save_manager == null:
		return
	if _save_manager.export_save(str(entry.get("slot_id", "")), dest_path):
		_set_status("ui.saveload.status.exported")
	else:
		_set_status("ui.saveload.status.export_failed")


func _do_import_save(src_path: String) -> void:
	if _save_manager == null:
		return
	var slot_id: String = _save_manager.import_save(src_path)
	if slot_id == "":
		_set_status("ui.saveload.status.import_failed")
		return
	_set_status("ui.saveload.status.imported")
	_reload_saves()
	_update_action_buttons()


func _do_export_pack(dest_path: String) -> void:
	if _pack_manager == null:
		return
	if _pack_manager.export_active(dest_path):
		_set_status("ui.saveload.status.pack_exported")
	else:
		_set_status("ui.saveload.status.pack_export_failed")


func _do_import_pack(src_path: String) -> void:
	if _pack_manager == null:
		return
	if _pack_manager.import_pack(src_path):
		_set_status("ui.saveload.status.pack_imported")
	else:
		_set_status("ui.saveload.status.pack_import_failed")


# --- Helpers ----------------------------------------------------------------

func _selected_index() -> int:
	if _list == null:
		return -1
	var selected: PackedInt32Array = _list.get_selected_items()
	if selected.is_empty():
		return -1
	var idx: int = selected[0]
	if idx < 0 or idx >= _saves.size():
		return -1
	return idx


func _selected_entry() -> Dictionary:
	var idx: int = _selected_index()
	if idx < 0:
		return {}
	return _saves[idx]


# Show a localized status message (key -> display text). Empty key clears it.
func _set_status(key: String) -> void:
	if _status == null:
		return
	_status.text = _loc.t(key) if key != "" else ""


func _world_state() -> WorldState:
	var nexus: Node = get_node_or_null("/root/Nexus")
	if nexus != null and nexus.get("world_state") != null:
		return nexus.world_state
	return null


# Pick the game scene from the global ui_mode preference (same logic as Match
# Setup): "desktop"/"mobile" are honoured directly; "auto" resolves from the
# device profile so a loaded save opens with the right HUD on every device.
func _resolve_game_scene() -> String:
	var settings: GameSettings = GameSettings.new(_world_state())
	settings.load_from_file()
	var setting: String = settings.get_ui_mode()
	var is_mobile: bool = OS.has_feature("mobile")
	var has_touch: bool = DisplayServer.is_touchscreen_available()
	var short_edge: float = 0.0
	var vp: Viewport = get_viewport()
	if vp != null:
		var vs: Vector2 = vp.get_visible_rect().size
		short_edge = minf(vs.x, vs.y)
	var resolved: String = GameSettings.resolve_ui_mode_for(setting, is_mobile, has_touch, short_edge)
	return MOBILE_SCENE if resolved == "mobile" else DESKTOP_SCENE


func _has_tree() -> bool:
	return is_inside_tree() and get_tree() != null


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
