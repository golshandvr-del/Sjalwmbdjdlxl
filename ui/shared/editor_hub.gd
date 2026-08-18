# editor_hub.gd
# ----------------------------------------------------------------------------
# Project Nexus - Editor Hub screen (Phase MC8, step 8.1, request 9).
#
# One place that gathers the three content editors (Map / Mod / GUI) plus a
# fourth "Defaults" entry, exactly as requested: "put the map/mod/gui editors in
# one hub reachable from the main menu, and add a tab to pick the default
# map/mod/gui."
#
# This screen is a THIN launcher: it only changes scenes. It holds no editor
# logic of its own. BACK routing goes through NavService (MB3), so the hub
# returns to the main menu and each editor returns to the hub -- the PARENTS map
# in NavService is the single source of truth (already wired in MC8.1).
#
# The UI is built PROGRAMMATICALLY (like gui_editor / mods_menu) so the view can
# never drift from a stale .tscn; the .tscn only supplies a full-rect Control
# host. Visible text is resolved through Localization (ui.editorhub.* keys).
#
# CODE LANGUAGE POLICY: English-only identifiers/comments (ASCII); visible text
# via Localization.
# ----------------------------------------------------------------------------
extends Control

# Canonical scene paths mirror NavService (kept local so the scene is self
# contained; NavService remains the routing source of truth for BACK).
const MAIN_MENU_SCENE: String = "res://scenes/main_menu.tscn"
const MAP_EDITOR_SCENE: String = "res://scenes/map_editor.tscn"
const MOD_EDITOR_SCENE: String = "res://scenes/mod_editor.tscn"
const GUI_EDITOR_SCENE: String = "res://scenes/gui_editor.tscn"
const DEFAULTS_SCENE: String = "res://scenes/editor_defaults.tscn"

var _loc: Localization = null
var _settings: GameSettings = null


func _ready() -> void:
	_settings = GameSettings.new(null)
	_settings.load_from_file()
	_loc = Localization.new()
	_loc.load_all("res://localization")
	_loc.set_locale(_settings.get_locale())
	_build_ui()


func _t(key: String) -> String:
	if _loc == null:
		return key
	# NOTE: must be Localization.t(), NOT Object.tr() -- tr() is the engine's
	# TranslationServer lookup (empty here), which silently returns the raw key,
	# so the hub used to render "ui.editorhub.title" instead of localized text.
	return _loc.t(key)


# --- UI construction --------------------------------------------------------

func _build_ui() -> void:
	var center: CenterContainer = CenterContainer.new()
	center.anchor_right = 1.0
	center.anchor_bottom = 1.0
	add_child(center)

	var box: VBoxContainer = VBoxContainer.new()
	box.custom_minimum_size = Vector2(320, 0)
	center.add_child(box)

	var title: Label = Label.new()
	title.text = _t("ui.editorhub.title")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	box.add_child(_make_button(_t("ui.menu.map_editor"), _on_map_editor))
	box.add_child(_make_button(_t("ui.menu.mod_editor"), _on_mod_editor))
	box.add_child(_make_button(_t("ui.editorhub.gui_editor"), _on_gui_editor))
	box.add_child(_make_button(_t("ui.editorhub.defaults"), _on_defaults))
	box.add_child(_make_button(_t("ui.menu.back"), _on_back))


func _make_button(text: String, handler: Callable) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 44)
	b.pressed.connect(handler)
	return b


# --- Navigation -------------------------------------------------------------

func _on_map_editor() -> void:
	get_tree().change_scene_to_file(MAP_EDITOR_SCENE)


func _on_mod_editor() -> void:
	get_tree().change_scene_to_file(MOD_EDITOR_SCENE)


func _on_gui_editor() -> void:
	get_tree().change_scene_to_file(GUI_EDITOR_SCENE)


func _on_defaults() -> void:
	get_tree().change_scene_to_file(DEFAULTS_SCENE)


# --- Back navigation (MB3 / NavService) -------------------------------------

func _on_back() -> void:
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_on_back()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and is_inside_tree():
		get_viewport().set_input_as_handled()
		_on_back()
