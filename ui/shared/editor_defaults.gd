# editor_defaults.gd
# ----------------------------------------------------------------------------
# Project Nexus - Editor "Defaults" screen (Phase MC8, step 8.3, request 9).
#
# GUI audit (BUG-G8): this screen was referenced by the Editor Hub, NavService
# and the localization tables, had a fully unit-tested logic helper
# (EditorDefaultsUtil) and persisted settings (GameSettings.default_map /
# default_gui / main_mod) -- but the scene + script were never written. Pressing
# "Defaults" in the hub failed to load a non-existent scene (blank screen, no
# way back). This is the missing thin view.
#
# Three OptionButtons let the player pick a default MAP (scenario id), MOD
# (main mod id) and GUI (custom .nexgui project, when one exists). Discovery of
# what exists and persistence live here; selection/validation logic is in
# EditorDefaultsUtil so it stays headless-testable. Selections are saved
# immediately (no separate Save button on a phone) and echoed in a status line.
#
# Consumers: Match Setup pre-selects `default_map`; the Mods menu keeps
# `main_mod`; the GUI runtime resolves `default_gui`.
#
# UI is built PROGRAMMATICALLY (like editor_hub / mods_menu) so it can never
# drift from a stale .tscn; the .tscn only supplies a full-rect host.
#
# CODE LANGUAGE POLICY: English-only identifiers/comments (ASCII); visible text
# via Localization (ui.editordefaults.* keys).
# ----------------------------------------------------------------------------
extends Control

const EDITOR_HUB_SCENE: String = "res://scenes/editor_hub.tscn"
const MODS_DIR: String = "res://mods"
const SCENARIOS_DIR: String = "res://data/scenarios"
const GUI_DIR: String = "user://"

var _loc: Localization = null
var _settings: GameSettings = null

# Choice lists (Array of { id, name }) per kind, produced by EditorDefaultsUtil.
var _choices: Dictionary = {}
# OptionButton per kind.
var _options: Dictionary = {}
var _status_label: Label = null


func _ready() -> void:
	_settings = GameSettings.new(null)
	_settings.load_from_file()
	_loc = Localization.new()
	_loc.load_all("res://localization")
	_loc.set_locale(_settings.get_locale())
	_discover_all()
	_build_ui()


func _t(key: String) -> String:
	if _loc == null:
		return key
	return _loc.t(key)


# --- Discovery --------------------------------------------------------------

func _discover_all() -> void:
	_choices[EditorDefaultsUtil.KIND_MAP] = EditorDefaultsUtil.build_choices(_discover_maps())
	_choices[EditorDefaultsUtil.KIND_MOD] = EditorDefaultsUtil.build_choices(_discover_mods())
	_choices[EditorDefaultsUtil.KIND_GUI] = EditorDefaultsUtil.build_choices(_discover_guis())


# Scenario ids: base catalog + any installed .nexpack scenarios (via the live
# Nexus catalog when available, else a direct scan of the shipped folder).
func _discover_maps() -> Array:
	var out: Array = []
	var nexus: Object = _live_nexus()
	if nexus != null and nexus.get("data_loader") != null:
		GameBootstrap.load_packs(nexus)
		for entry in ScenarioLoader.list_scenarios(nexus):
			var e: Dictionary = entry
			var name_key: String = str(e.get("display_name_key", ""))
			var label: String = _t(name_key) if name_key != "" else str(e.get("id", ""))
			out.append({ "id": str(e.get("id", "")), "name": label })
		return out
	var loader: DataLoader = DataLoader.new()
	loader.load_catalog("scenarios", SCENARIOS_DIR)
	var catalog: Dictionary = loader.get_catalog("scenarios")
	for id in catalog.keys():
		var entry: Dictionary = catalog[id]
		var key: String = str(entry.get("display_name_key", "scenario.%s.name" % str(id)))
		out.append({ "id": str(id), "name": _t(key) })
	return out


func _discover_mods() -> Array:
	var out: Array = []
	var loader: DataLoader = DataLoader.new()
	for manifest in ModLoader.discover_mods(loader, MODS_DIR):
		var m: Dictionary = manifest
		out.append({ "id": str(m.get("id", "")), "name": str(m.get("name", m.get("id", ""))) })
	return out


# Custom GUI projects: every *.nexgui file in the user folder (id = file stem).
func _discover_guis() -> Array:
	var out: Array = []
	var dir: DirAccess = DirAccess.open(GUI_DIR)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.get_extension() == GuiProject.GUI_EXTENSION:
			var stem: String = name.get_basename()
			out.append({ "id": stem, "name": stem })
		name = dir.get_next()
	dir.list_dir_end()
	return out


func _live_nexus() -> Object:
	if not is_inside_tree():
		return null
	var root: Node = get_tree().root
	return root.get_node_or_null("Nexus")


# --- UI construction --------------------------------------------------------

func _build_ui() -> void:
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var box: VBoxContainer = VBoxContainer.new()
	box.custom_minimum_size = Vector2(420, 0)
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)

	var title: Label = Label.new()
	title.text = _t("ui.editordefaults.title")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	_add_row(box, EditorDefaultsUtil.KIND_MAP, "ui.editordefaults.map_tab", _settings.get_default_map())
	_add_row(box, EditorDefaultsUtil.KIND_MOD, "ui.editordefaults.mod_tab", _settings.get_main_mod())
	_add_row(box, EditorDefaultsUtil.KIND_GUI, "ui.editordefaults.gui_tab", _settings.get_default_gui())

	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.text = ""
	box.add_child(_status_label)

	var back: Button = Button.new()
	back.text = _t("ui.menu.back")
	back.custom_minimum_size = Vector2(0, 44)
	back.pressed.connect(_on_back)
	box.add_child(back)


# One labeled OptionButton row. Item 0 is always "(none)" (id ""), followed by
# the sorted choices. The stored id is resolved against the list so a deleted
# map/mod/gui collapses to "(none)" instead of dangling.
func _add_row(parent: VBoxContainer, kind: String, label_key: String, stored_id: String) -> void:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)

	var label: Label = Label.new()
	label.custom_minimum_size = Vector2(120, 0)
	label.text = _t(label_key)
	row.add_child(label)

	var option: OptionButton = OptionButton.new()
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	option.add_item(_t("ui.editordefaults.none"))
	var choices: Array = _choices.get(kind, [])
	for choice in choices:
		option.add_item(str((choice as Dictionary).get("name", "")))
	var resolved: String = EditorDefaultsUtil.resolve_default(stored_id, choices)
	option.selected = _index_of(choices, resolved) + 1
	option.item_selected.connect(func(index: int) -> void: _on_selected(kind, index))
	row.add_child(option)
	_options[kind] = option
	# A stale stored id is healed on open so settings never dangle.
	if resolved != stored_id:
		_persist(kind, resolved)


func _index_of(choices: Array, id: String) -> int:
	if id == "":
		return -1
	for i in range(choices.size()):
		if str((choices[i] as Dictionary).get("id", "")) == id:
			return i
	return -1


# --- Selection / persistence ------------------------------------------------

func _on_selected(kind: String, index: int) -> void:
	var choices: Array = _choices.get(kind, [])
	var id: String = ""
	if index >= 1 and index - 1 < choices.size():
		id = str((choices[index - 1] as Dictionary).get("id", ""))
	_persist(kind, id)
	if _status_label != null:
		_status_label.text = _t("ui.editordefaults.saved")


func _persist(kind: String, id: String) -> void:
	match kind:
		EditorDefaultsUtil.KIND_MAP:
			_settings.set_default_map(id)
		EditorDefaultsUtil.KIND_MOD:
			_settings.set_main_mod(id)
		EditorDefaultsUtil.KIND_GUI:
			_settings.set_default_gui(id)
	_settings.save_to_file()


# --- Back navigation (MB3 / NavService) -------------------------------------

func _on_back() -> void:
	get_tree().change_scene_to_file(EDITOR_HUB_SCENE)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_on_back()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and is_inside_tree():
		get_viewport().set_input_as_handled()
		_on_back()
