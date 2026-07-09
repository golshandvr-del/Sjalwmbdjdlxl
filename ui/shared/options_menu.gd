# options_menu.gd
# ----------------------------------------------------------------------------
# Project Nexus - Options / Settings screen (Phase 6, step 6.2).
#
# A player-facing settings panel reachable from the main menu. It edits the
# persisted GameSettings (locale, render style, default difficulty, camera zoom,
# sound toggles), writes them to disk via GameSettings.save_to_file(), and
# returns to the menu. Every label is resolved through the Localization service
# so the panel itself is fully translatable.
#
# This scene is deliberately thin: all validation/persistence lives in the
# tested GameSettings service. The UI only maps button presses onto its setters
# and re-renders the current values. It uses the same /root/Nexus singleton the
# other UI scenes rely on, and degrades gracefully if run in isolation.
extends Control

const MAIN_MENU_SCENE: String = "res://scenes/main_menu.tscn"

var _settings: GameSettings = null
var _loc: Localization = null

@onready var _title: Label = $Center/Box/Title
@onready var _locale_button: Button = $Center/Box/LocaleRow/LocaleButton
@onready var _style_button: Button = $Center/Box/StyleRow/StyleButton
@onready var _difficulty_button: Button = $Center/Box/DifficultyRow/DifficultyButton
@onready var _zoom_button: Button = $Center/Box/ZoomRow/ZoomButton
@onready var _ui_scale_auto_button: Button = $Center/Box/UiScaleAutoRow/UiScaleAutoButton
@onready var _ui_scale_button: Button = $Center/Box/UiScaleRow/UiScaleButton
@onready var _sfx_button: Button = $Center/Box/SfxRow/SfxButton
@onready var _music_button: Button = $Center/Box/MusicRow/MusicButton
@onready var _content_path_button: Button = $Center/Box/ContentPathRow/ContentPathButton
@onready var _reset_button: Button = $Center/Box/ButtonRow/ResetButton
@onready var _back_button: Button = $Center/Box/ButtonRow/BackButton


func _ready() -> void:
	_settings = GameSettings.new(_world_state())
	_settings.load_from_file()

	_loc = Localization.new()
	_loc.load_all("res://localization")
	# Honour the persisted locale so the panel opens in the player's language.
	_loc.set_locale(_settings.get_locale())

	# Phase G: apply the GUI scale immediately so the options panel itself is
	# shown at the player's chosen size, and keep it live on resize.
	_apply_ui_scale()
	if is_inside_tree() and get_viewport() != null:
		get_viewport().size_changed.connect(_apply_ui_scale)

	_locale_button.pressed.connect(_on_locale)
	_style_button.pressed.connect(_on_style)
	_difficulty_button.pressed.connect(_on_difficulty)
	_zoom_button.pressed.connect(_on_zoom)
	_ui_scale_auto_button.pressed.connect(_on_ui_scale_auto)
	_ui_scale_button.pressed.connect(_on_ui_scale)
	_sfx_button.pressed.connect(_on_sfx)
	_music_button.pressed.connect(_on_music)
	_content_path_button.pressed.connect(_on_content_path)
	_reset_button.pressed.connect(_on_reset)
	_back_button.pressed.connect(_on_back)

	_refresh()


# --- Button handlers (cycle through allowed values, then re-render) ---------

func _on_locale() -> void:
	var next: String = _loc.cycle_locale()
	_settings.set_locale(next)
	_persist()
	_refresh()


func _on_style() -> void:
	var styles: Array = GameSettings.RENDER_STYLES
	_settings.set_render_style(_next_in(styles, _settings.get_render_style()))
	_persist()
	_refresh()


func _on_difficulty() -> void:
	var diffs: Array = GameSettings.DIFFICULTIES
	_settings.set_difficulty(_next_in(diffs, _settings.get_difficulty()))
	_persist()
	_refresh()


func _on_zoom() -> void:
	# Step zoom through quarter increments and wrap at the max.
	var z: float = _settings.get_camera_zoom() + 0.25
	if z > GameSettings.ZOOM_MAX:
		z = GameSettings.ZOOM_MIN
	_settings.set_camera_zoom(z)
	_persist()
	_refresh()


func _on_ui_scale_auto() -> void:
	# Toggle automatic GUI scaling. When turned ON, the manual value is ignored
	# and the scale is derived from the device/screen size.
	_settings.set_ui_scale_auto(not _settings.is_ui_scale_auto())
	_persist()
	_apply_ui_scale()
	_refresh()


func _on_ui_scale() -> void:
	# Step the manual GUI scale through quarter increments and wrap at the max.
	# Turning the manual slider implicitly switches off auto so the choice sticks.
	if _settings.is_ui_scale_auto():
		_settings.set_ui_scale_auto(false)
	var s: float = _settings.get_ui_scale() + 0.25
	if s > GameSettings.UI_SCALE_MAX:
		s = GameSettings.UI_SCALE_MIN
	_settings.set_ui_scale(s)
	_persist()
	_apply_ui_scale()
	_refresh()


func _on_sfx() -> void:
	_settings.set_sfx_enabled(not _settings.is_sfx_enabled())
	_persist()
	_refresh()


func _on_music() -> void:
	_settings.set_music_enabled(not _settings.is_music_enabled())
	_persist()
	_refresh()


func _on_content_path() -> void:
	# Cycle through a small set of platform-portable content roots. The default
	# (user://content) works everywhere; the alternates illustrate that the path
	# is configurable (e.g. a shared external folder). The StorageService
	# normalises + creates whichever is chosen, and the pack pipeline reads it.
	var choices: Array = [
		GameSettings.DEFAULT_CONTENT_PATH,
		"user://nexus_content",
		"user://mods_external",
	]
	_settings.set_content_path(_next_in(choices, _settings.get_content_path()))
	_persist()
	_refresh()


func _on_reset() -> void:
	_settings.reset_to_defaults()
	_loc.set_locale(_settings.get_locale())
	_persist()
	_apply_ui_scale()
	_refresh()


func _on_back() -> void:
	_persist()
	if _has_tree():
		get_tree().change_scene_to_file(MAIN_MENU_SCENE)


# MB3.2 (bug 6): the Android BACK button / gesture arrives as
# NOTIFICATION_WM_GO_BACK_REQUEST; ESC / gamepad-B arrive as the "ui_cancel"
# action. Both must return to the parent screen (NavService says: main menu),
# never quit the app.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_on_back()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _has_tree():
			get_viewport().set_input_as_handled()
		_on_back()


# --- Rendering --------------------------------------------------------------

func _refresh() -> void:
	_title.text = _loc.t("ui.options.title")
	_locale_button.text = "%s: %s" % [_loc.t("ui.game.language"), _settings.get_locale()]
	_style_button.text = "%s: %s" % [_loc.t("ui.game.style"), _style_label(_settings.get_render_style())]
	_difficulty_button.text = "%s: %s" % [_loc.t("ui.options.difficulty"), _settings.get_difficulty()]
	_zoom_button.text = "%s: %.2fx" % [_loc.t("ui.options.zoom"), _settings.get_camera_zoom()]
	_ui_scale_auto_button.text = "%s: %s" % [_loc.t("ui.options.ui_scale_auto"), _on_off(_settings.is_ui_scale_auto())]
	# In auto mode the manual slider is informational; show "Auto" so it is clear
	# the value is being computed from the screen size.
	if _settings.is_ui_scale_auto():
		_ui_scale_button.text = "%s: %s" % [_loc.t("ui.options.ui_scale"), _loc.t("ui.options.ui_scale_auto_value")]
	else:
		_ui_scale_button.text = "%s: %.2fx" % [_loc.t("ui.options.ui_scale"), _settings.get_ui_scale()]
	_sfx_button.text = "%s: %s" % [_loc.t("ui.options.sfx"), _on_off(_settings.is_sfx_enabled())]
	_music_button.text = "%s: %s" % [_loc.t("ui.options.music"), _on_off(_settings.is_music_enabled())]
	_content_path_button.text = "%s: %s" % [_loc.t("ui.options.content_path"), _settings.get_content_path()]
	_reset_button.text = _loc.t("ui.options.reset")
	_back_button.text = _loc.t("ui.options.back")


func _style_label(style_id: String) -> String:
	if style_id == "detailed":
		return _loc.t("ui.game.style_detailed")
	return _loc.t("ui.game.style_simple")


func _on_off(value: bool) -> String:
	return _loc.t("ui.options.on") if value else _loc.t("ui.options.off")


# --- Helpers ----------------------------------------------------------------

func _next_in(values: Array, current: Variant) -> Variant:
	var idx: int = values.find(current)
	if idx < 0:
		return values[0]
	return values[(idx + 1) % values.size()]


func _persist() -> void:
	_settings.save_to_file()


# Apply the current GUI-scale preference to the live window so the change is
# visible immediately (cosmetic-only; never touches the simulation).
func _apply_ui_scale() -> void:
	if _settings != null:
		UiScale.apply_with_settings(self, _settings)


func _world_state() -> WorldState:
	var nexus: Node = get_node_or_null("/root/Nexus")
	if nexus != null and nexus.get("world_state") != null:
		return nexus.world_state
	return null


func _has_tree() -> bool:
	return is_inside_tree() and get_tree() != null
