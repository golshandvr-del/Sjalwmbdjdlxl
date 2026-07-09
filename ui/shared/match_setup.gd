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
# MB2.2 (bug 5): single-player AI team-grouping panel. The container holds one
# "AI N -> Team" row per AI player; `_ai_team_options` maps the AI owner index
# to its team OptionButton so _on_start can gather the explicit team overrides.
var _ai_groups_box: VBoxContainer
var _ai_groups_hint: Label
var _ai_team_options: Dictionary = {}

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
# MA7.4 (B8): whether this is the DISTINCT local hot-seat path (shared-device
# multiplayer). It still routes straight into the game like single-player, but
# opens with a hot-seat title + defaults and tags match_config.hot_seat = true.
var _is_hotseat_setup: bool = false


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
	# MA7.4 (B8): "hotseat" is the distinct local-multiplayer intent.
	var purpose: String = str(Nexus.world_state.get_section("ui_prefs").get("setup_purpose", ""))
	_is_host_setup = purpose == "host"
	_is_hotseat_setup = purpose == "hotseat"

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
	# MA7.4 (B8): hot-seat is local multiplayer, so open with >=2 humans and 0 AIs
	# by default -- a meaningfully different starting point from a solo skirmish.
	if _is_hotseat_setup:
		_humans_option.selected = 1  # option index 1 => 2 humans
		_ai_option.selected = 0      # option index 0 => 0 AIs

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

	# MB2.2 (bug 5): AI team-grouping panel. A hint line plus a dynamically-built
	# list of "AI N -> Team" rows. It mirrors the multiplayer host lobby's grouping
	# so a single-player player can ally the AIs into teams. The rows are rebuilt
	# whenever the AI count or game mode changes (they seed sensible defaults via
	# AiGroupUtil so the panel always opens on a valid layout).
	_ai_groups_hint = Label.new()
	_ai_groups_hint.set_meta("loc_key_plain", "ui.setup.ai_groups_hint")
	_ai_groups_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ai_groups_hint.add_theme_font_size_override("font_size", 13)
	box.add_child(_ai_groups_hint)

	_ai_groups_box = VBoxContainer.new()
	_ai_groups_box.add_theme_constant_override("separation", 8)
	box.add_child(_ai_groups_box)

	# Rebuild the grouping rows when the inputs that drive them change.
	_ai_option.item_selected.connect(func(_i: int) -> void: _rebuild_ai_groups())
	_mode_option.item_selected.connect(func(_i: int) -> void: _rebuild_ai_groups())
	_rebuild_ai_groups()

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


# MB2.2 (bug 5): (re)build the AI team-grouping rows. One row per AI player, each
# with a Team OptionButton pre-selected to the deterministic default for the
# current mode (via AiGroupUtil) so the panel opens already valid. Preserves the
# player's earlier team picks across a rebuild when the owner index still exists.
func _rebuild_ai_groups() -> void:
	if _ai_groups_box == null:
		return
	# Remember prior explicit picks so a rebuild (e.g. mode change) keeps them.
	var prior: Dictionary = {}
	for owner in _ai_team_options.keys():
		var opt: OptionButton = _ai_team_options[owner]
		if is_instance_valid(opt):
			prior[owner] = opt.selected
	for child in _ai_groups_box.get_children():
		child.queue_free()
	_ai_team_options.clear()

	var ai_count: int = _ai_option.selected  # option 0 => 0 AIs
	var m_idx: int = clampi(_mode_option.selected, 0, _modes.size() - 1)
	var mode: String = str(_modes[m_idx])

	# The grouping panel is only meaningful with at least two AIs to ally; hide it
	# (and its hint) otherwise to keep the setup screen compact.
	var show_panel: bool = ai_count >= 2
	_ai_groups_hint.visible = show_panel
	_ai_groups_box.visible = show_panel
	if not show_panel:
		return

	for ai_index in range(ai_count):
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		_ai_groups_box.add_child(row)

		var label: Label = Label.new()
		label.custom_minimum_size = Vector2(140, 0)
		label.text = "%s:" % (_loc.t("ui.setup.ai_player_n") % (ai_index + 1))
		row.add_child(label)

		var option: OptionButton = OptionButton.new()
		option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for team in range(AiGroupUtil.TEAM_COUNT):
			option.add_item(_loc.t("ui.setup.team_n") % (team + 1))
		# Seed selection: keep the earlier pick if this owner still exists,
		# otherwise use the deterministic default team for the mode.
		var default_team: int = AiGroupUtil.default_team(ai_index, mode)
		option.selected = int(prior.get(ai_index, default_team))
		row.add_child(option)
		_ai_team_options[ai_index] = option


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
	# MA7.4 (B8): a hot-seat setup announces itself with a distinct title so the
	# player can tell this is the local-multiplayer path, not a solo skirmish.
	_title_label.text = _loc.t("ui.setup.title_hotseat") if _is_hotseat_setup else _loc.t("ui.setup.title")
	_start_button.text = _loc.t("ui.setup.start")
	_back_button.text = _loc.t("ui.menu.back")
	# MB2.1 (bug 4): every labeled row stored its localization key on the label via
	# a "loc_key" meta. Walk the whole tree and set each such label's text so the
	# descriptive captions ("Name:", "Map:", "AI Difficulty:", ...) are always
	# visible next to their input -- previously the meta was never applied, so the
	# left column showed up blank on device. A trailing ":" makes the label read as
	# a caption for the control to its right.
	_apply_meta_labels(self)


# Recursively localize every Label that carries a "loc_key" meta (see
# _add_labeled_option / _add_labeled_line_edit). Kept generic so any future
# labeled row is localized automatically.
func _apply_meta_labels(node: Node) -> void:
	for child in node.get_children():
		if child is Label and (child as Label).has_meta("loc_key"):
			var key: String = str((child as Label).get_meta("loc_key"))
			(child as Label).text = "%s:" % _loc.t(key)
		# MB2.2: some captions (e.g. the AI-grouping hint) are full sentences that
		# must NOT get a trailing ":" -- they carry a "loc_key_plain" meta instead.
		if child is Label and (child as Label).has_meta("loc_key_plain"):
			var plain_key: String = str((child as Label).get_meta("loc_key_plain"))
			(child as Label).text = _loc.t(plain_key)
		_apply_meta_labels(child)


# --- Actions ----------------------------------------------------------------

func _on_back() -> void:
	get_tree().change_scene_to_file(MENU_SCENE)


# MB3.2 (bug 6): Android BACK / ESC returns to the main menu instead of quitting.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if is_inside_tree():
			_on_back()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and is_inside_tree():
		get_viewport().set_input_as_handled()
		_on_back()


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
	# MB2.2 (bug 5): gather the explicit AI -> team choices into match_config so
	# GameBootstrap._resolve_team honours them. Only recorded when the grouping
	# panel is active (>= 2 AIs); otherwise the engine uses per-mode defaults.
	# The panel is keyed by the 0-based AI index (AI 1, AI 2, ...), but the engine
	# seats humans first (owners 0..humans-1) then AIs, so we remap each AI index
	# onto its real owner seat: owner = human_players + ai_index.
	var humans: int = _humans_option.selected + 1
	var team_overrides: Dictionary = {}
	for ai_index in _ai_team_options.keys():
		var opt: OptionButton = _ai_team_options[ai_index]
		if is_instance_valid(opt):
			var owner_seat: int = humans + int(ai_index)
			team_overrides[owner_seat] = AiGroupUtil.clamp_team(opt.selected)
	config["team_overrides"] = team_overrides
	# MA7.4 (B8): tag a shared-device hot-seat session so the game scene can adapt
	# (e.g. show a "local multiplayer" banner / per-turn hand-off later). It is a
	# pure UI hint -- the deterministic core treats every human player the same.
	config["hot_seat"] = _is_hotseat_setup

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

	# Single-player / local (incl. hot-seat): consume the intent so a later visit
	# starts clean, then show the shared progress overlay while the (fast) build
	# runs, then enter the game scene.
	prefs["setup_purpose"] = ""
	var overlay = ProgressOverlayScript.new()
	add_child(overlay)
	overlay.begin(_loc.t("ui.setup.starting"), _loc.t("ui.setup.loading_catalogs"))
	overlay.set_progress(0.6, _loc.t("ui.setup.building_match"))

	# Give the overlay one frame to paint before the (synchronous) scene swap.
	await get_tree().process_frame
	overlay.set_progress(1.0)
	get_tree().change_scene_to_file(game_scene)
