# custom_games.gd
# ----------------------------------------------------------------------------
# Project Nexus - Custom Games / Installed Scenarios picker (Phase E, step E.7).
#
# Lists every scenario installed in the `scenarios` catalog -- both the shipped
# base scenarios AND any an authored mod / `.nexpack` added (they all merge into
# the same catalog, Phase C/E.6) -- and launches the chosen one. Picking a
# scenario stashes its id in WorldState so the game scene loads it instead of the
# default skirmish (the game scene reads `editor.playtest_scenario`).
#
# Like the other menu screens it is a thin VIEW over data: discovery lives in
# `ScenarioLoader.list_scenarios` (headless-testable), this scene only renders
# the list and changes scenes.
#
# CODE LANGUAGE POLICY: English-only identifiers/comments; visible text via
# Localization.
# ----------------------------------------------------------------------------
extends Control

const MAIN_MENU_SCENE: String = "res://scenes/main_menu.tscn"
# The game scene (mobile vs desktop HUD) is resolved from the GLOBAL ui_mode
# preference at play time (_resolve_game_scene), same as Match Setup -- a fixed
# scene here would force the mobile HUD onto desktop players.
const MOBILE_SCENE: String = "res://scenes/game_main.tscn"
const DESKTOP_SCENE: String = "res://scenes/game_desktop.tscn"

var _loc: Localization = null
var _scenarios: Array = []

@onready var _title: Label = get_node_or_null("Root/Title")
@onready var _list: ItemList = get_node_or_null("Root/ScenarioList")
@onready var _empty_label: Label = get_node_or_null("Root/EmptyLabel")
@onready var _play_button: Button = get_node_or_null("Root/Footer/PlayButton")
@onready var _back_button: Button = get_node_or_null("Root/Footer/BackButton")


func _ready() -> void:
	_loc = Localization.new()
	_loc.load_all("res://localization")
	var settings: GameSettings = GameSettings.new(_world_state())
	settings.load_from_file()
	_loc.set_locale(settings.get_locale())
	# Phase G: apply the persisted GUI scale so the screen matches Options.
	UiScale.apply_with_settings(self, settings)

	# Ensure the catalogs (incl. base + installed scenarios) are loaded so the
	# list is complete even on a cold entry straight into this screen.
	GameBootstrap.register_modules(Nexus)
	GameBootstrap.load_catalogs(Nexus)
	_scenarios = ScenarioLoader.list_scenarios(Nexus)

	if _play_button != null:
		_play_button.pressed.connect(_on_play)
	if _back_button != null:
		_back_button.pressed.connect(_on_back)
	if _list != null:
		_list.item_activated.connect(func(_i): _on_play())

	_refresh()


func _refresh() -> void:
	if _title != null:
		_title.text = _loc.t("ui.custom.title")
	if _play_button != null:
		_play_button.text = _loc.t("ui.custom.play")
	if _back_button != null:
		_back_button.text = _loc.t("ui.custom.back")
	if _list != null:
		_list.clear()
		for s in _scenarios:
			var label: String = str(s.get("display_name", ""))
			if label == "":
				label = _loc.t(str(s.get("display_name_key", "")))
			if label == "" or label == str(s.get("display_name_key", "")):
				label = str(s.get("id", ""))
			_list.add_item("%s  (%d %s)" % [label, int(s.get("players", 0)), _loc.t("ui.custom.players")])
	var empty: bool = _scenarios.is_empty()
	if _empty_label != null:
		_empty_label.visible = empty
		_empty_label.text = _loc.t("ui.custom.empty")
	if _play_button != null:
		_play_button.disabled = empty


func _on_play() -> void:
	if _list == null or _scenarios.is_empty():
		return
	var idx: int = _list.get_selected_items()[0] if not _list.get_selected_items().is_empty() else 0
	if idx < 0 or idx >= _scenarios.size():
		return
	var scenario_id: String = str(_scenarios[idx].get("id", ""))
	var ws: WorldState = _world_state()
	if ws != null:
		ws.get_section("editor")["playtest_scenario"] = scenario_id
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


func _world_state() -> WorldState:
	var nexus: Node = get_node_or_null("/root/Nexus")
	if nexus != null and nexus.get("world_state") != null:
		return nexus.world_state
	return null


func _has_tree() -> bool:
	return is_inside_tree() and get_tree() != null


# Pick the game scene from the global ui_mode preference (same logic as Match
# Setup): "desktop"/"mobile" are honoured directly; "auto" resolves from the
# device profile so the chosen scenario opens with the right HUD everywhere.
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
