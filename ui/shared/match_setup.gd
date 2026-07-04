# match_setup.gd
# ----------------------------------------------------------------------------
# Project Nexus - Match Setup screen (Phase P2, steps P2.1 + P2.3).
#
# The screen shown after the player picks "Single Player" (or "Offline") in the
# main menu. It lets the player configure the skirmish before it starts:
#
#   - Scenario / map   (any scenario installed in the `scenarios` catalog:
#                       shipped ones + anything a mod or .nexpack added)
#   - AI difficulty    (easy / normal / hard)  -- the DEFAULT for AI players
#   - UI style         (desktop keyboard/mouse HUD vs mobile touch HUD)
#
# On "Start", the chosen configuration is written into a UI-only WorldState
# section (`match_config`) that GameBootstrap.setup_skirmish reads, a shared
# ProgressOverlay is shown while the match is built, and the game scene is
# entered. Nothing here touches the deterministic simulation directly -- it only
# records intent and changes scenes (same pattern as the main menu).
#
# The scene tree is built programmatically in _ready(), so this screen needs no
# hand-authored .tscn beyond a root Control with this script attached.
#
# CODE LANGUAGE POLICY: English-only identifiers/comments; visible labels go
# through the Localization service.
# ----------------------------------------------------------------------------
extends Control

const DESKTOP_SCENE: String = "res://scenes/game_desktop.tscn"
const MOBILE_SCENE: String = "res://scenes/game_main.tscn"
const MENU_SCENE: String = "res://scenes/main_menu.tscn"
# P5 (R6): when hosting, Match Setup routes to the LAN lobby instead of a match.
const LOBBY_SCENE: String = "res://scenes/lobby.tscn"

const ProgressOverlayScript = preload("res://ui/shared/progress_overlay.gd")

var _loc: Localization = Localization.new()

var _scenario_option: OptionButton
var _difficulty_option: OptionButton
var _style_option: OptionButton
# R1 fields: match name, human/AI counts, and game mode.
var _name_edit: LineEdit
var _humans_option: OptionButton
var _ai_option: OptionButton
var _mode_option: OptionButton
var _layout_option: OptionButton
var _start_button: Button
var _back_button: Button
var _title_label: Label

# Parallel list of scenario ids matching the OptionButton item order.
var _scenario_ids: Array = []
# The three shipped difficulties (kept in a fixed order for a stable index).
var _difficulties: Array = ["easy", "normal", "hard"]
# R1.5 game modes (data-extensible; the fixed order gives a stable index).
var _modes: Array = ["team", "ffa", "ctf"]
# R10.2 team layout options (clustered = teammates near each other; random).
var _layouts: Array = ["clustered", "random"]
# Whether this setup screen is configuring a LAN host (routes to the lobby) or a
# single-player / local match (routes straight into the game). Read in _ready.
var _is_host_setup: bool = false


func _ready() -> void:
	_loc.load_all("res://localization")
	var settings: GameSettings = GameSettings.new(Nexus.world_state)
	settings.load_from_file()
	UiScale.apply_with_settings(self, settings)
	var saved: String = str(Nexus.world_state.get_section("ui_prefs").get("locale", ""))
	if saved != "":
		_loc.set_locale(saved)

	# P5 (R6): if the main menu entered here via "Host", the final button hosts a
	# LAN match (routes to the lobby) instead of starting a single-player match.
	_is_host_setup = str(Nexus.world_state.get_section("ui_prefs").get("setup_purpose", "")) == "host"

	# The scenario catalog must exist before we can list maps; loading the base
	# catalogs is cheap and idempotent (GameBootstrap guards re-registration).
	GameBootstrap.register_modules(Nexus)
	GameBootstrap.load_catalogs(Nexus)

	_build_ui()
	_populate_scenarios()
	_populate_difficulties(settings.get_difficulty())
	_apply_labels()


# --- UI construction --------------------------------------------------------

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = Vector2(420, 0)
	center.add_child(panel)

	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)

	_title_label = Label.new()
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 24)
	box.add_child(_title_label)

	# R1.1: match name (a plain text field row).
	_name_edit = _add_labeled_line_edit(box, "ui.setup.match_name", _loc.t("ui.setup.match_name_hint"))

	_scenario_option = _add_labeled_option(box, "ui.setup.map")
	_difficulty_option = _add_labeled_option(box, "ui.setup.difficulty")
	_style_option = _add_labeled_option(box, "ui.setup.ui_style")

	# R1.3 / R1.4: human + AI player counts (1..8 humans, 0..7 AIs).
	_humans_option = _add_labeled_option(box, "ui.setup.humans")
	for h in range(1, 9):
		_humans_option.add_item(str(h))
	_humans_option.selected = 0
	_ai_option = _add_labeled_option(box, "ui.setup.ai_players")
	for a in range(0, 8):
		_ai_option.add_item(str(a))
	_ai_option.selected = 3  # a sensible default: 3 AIs for single-player

	# R1.5: game mode (team / ffa / ctf; data-extensible later).
	_mode_option = _add_labeled_option(box, "ui.setup.game_mode")
	for mode in _modes:
		_mode_option.add_item(_loc.t("ui.setup.mode_%s" % mode))
	_mode_option.selected = 0

	# R10.2: team layout (clustered teammates vs. deterministic random spread).
	_layout_option = _add_labeled_option(box, "ui.setup.team_layout")
	for layout in _layouts:
		_layout_option.add_item(_loc.t("ui.setup.layout_%s" % layout))
	_layout_option.selected = 0

	# UI style choices: desktop first (index 0), mobile second (index 1).
	_style_option.add_item(_loc.t("ui.menu.single_desktop"))
	_style_option.add_item(_loc.t("ui.menu.single_mobile"))
	_style_option.selected = 0

	var buttons: HBoxContainer = HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	box.add_child(buttons)

	_back_button = Button.new()
	_back_button.custom_minimum_size = Vector2(120, 0)
	_back_button.pressed.connect(_on_back)
	buttons.add_child(_back_button)

	_start_button = Button.new()
	_start_button.custom_minimum_size = Vector2(160, 0)
	_start_button.pressed.connect(_on_start)
	buttons.add_child(_start_button)


# Add a "label + OptionButton" row and return the OptionButton. The label text
# key is stored on the label via meta so _apply_labels can re-localize it.
func _add_labeled_option(parent: VBoxContainer, label_key: String) -> OptionButton:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)

	var label: Label = Label.new()
	label.custom_minimum_size = Vector2(140, 0)
	label.set_meta("loc_key", label_key)
	row.add_child(label)

	var option: OptionButton = OptionButton.new()
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(option)
	return option


# Add a "label + LineEdit" row and return the LineEdit (used for the match name).
func _add_labeled_line_edit(parent: VBoxContainer, label_key: String, placeholder: String) -> LineEdit:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)

	var label: Label = Label.new()
	label.custom_minimum_size = Vector2(140, 0)
	label.set_meta("loc_key", label_key)
	row.add_child(label)

	var edit: LineEdit = LineEdit.new()
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.placeholder_text = placeholder
	row.add_child(edit)
	return edit


# --- Population -------------------------------------------------------------

func _populate_scenarios() -> void:
	_scenario_option.clear()
	_scenario_ids.clear()
	var scenarios: Array = ScenarioLoader.list_scenarios(Nexus)
	if scenarios.is_empty():
		# Fallback: at least offer the default shipped skirmish id.
		_scenario_ids.append("skirmish_basic")
		_scenario_option.add_item("skirmish_basic")
		return
	for entry in scenarios:
		var id: String = str(entry.get("id", ""))
		if id == "":
			continue
		var name_key: String = str(entry.get("display_name_key", ""))
		var label: String = _loc.t(name_key) if name_key != "" else id
		_scenario_ids.append(id)
		_scenario_option.add_item(label)
	if _scenario_option.item_count > 0:
		_scenario_option.selected = 0


func _populate_difficulties(default_difficulty: String) -> void:
	_difficulty_option.clear()
	for i in range(_difficulties.size()):
		var diff: String = str(_difficulties[i])
		_difficulty_option.add_item(_loc.t("difficulty.%s.name" % diff))
		if diff == default_difficulty:
			_difficulty_option.selected = i


func _apply_labels() -> void:
	_title_label.text = _loc.t("ui.setup.title")
	_start_button.text = _loc.t("ui.setup.start")
	_back_button.text = _loc.t("ui.menu.back")


# --- Actions ----------------------------------------------------------------

func _on_back() -> void:
	get_tree().change_scene_to_file(MENU_SCENE)


func _on_start() -> void:
	# Record the chosen configuration into a UI-only WorldState section that
	# GameBootstrap.setup_skirmish (and the lobby) consume when building the match.
	var config: Dictionary = Nexus.world_state.get_section("match_config")
	var s_idx: int = clampi(_scenario_option.selected, 0, _scenario_ids.size() - 1)
	config["scenario_id"] = str(_scenario_ids[s_idx]) if _scenario_ids.size() > 0 else ""
	var d_idx: int = clampi(_difficulty_option.selected, 0, _difficulties.size() - 1)
	config["difficulty"] = str(_difficulties[d_idx])
	# R1 fields.
	var typed_name: String = _name_edit.text.strip_edges()
	config["match_name"] = typed_name if typed_name != "" else _loc.t("ui.setup.match_name_default")
	config["human_players"] = _humans_option.selected + 1  # option 0 => 1 human
	config["ai_players"] = _ai_option.selected             # option 0 => 0 AIs
	var m_idx: int = clampi(_mode_option.selected, 0, _modes.size() - 1)
	config["game_mode"] = str(_modes[m_idx])
	var l_idx: int = clampi(_layout_option.selected, 0, _layouts.size() - 1)
	config["team_layout"] = str(_layouts[l_idx])

	var game_scene: String = MOBILE_SCENE if _style_option.selected == 1 else DESKTOP_SCENE

	# Persist locale for the next scene, exactly like the main menu does.
	var prefs: Dictionary = Nexus.world_state.get_section("ui_prefs")
	prefs["locale"] = _loc.active_locale()

	# P5 (R6.1): hosting routes to the LAN lobby (slots / teams / ready) rather
	# than starting a match immediately.
	if _is_host_setup:
		prefs["setup_purpose"] = ""          # consume the intent
		prefs["lobby_role"] = "host"
		prefs["lobby_game_scene"] = game_scene
		get_tree().change_scene_to_file(LOBBY_SCENE)
		return

	# Single-player / local: show the shared progress overlay while the (fast)
	# build runs, then enter the game scene.
	var overlay = ProgressOverlayScript.new()
	add_child(overlay)
	overlay.begin(_loc.t("ui.setup.starting"), _loc.t("ui.setup.loading_catalogs"))
	overlay.set_progress(0.6, _loc.t("ui.setup.building_match"))

	# Give the overlay one frame to paint before the (synchronous) scene swap.
	await get_tree().process_frame
	overlay.set_progress(1.0)
	get_tree().change_scene_to_file(game_scene)
