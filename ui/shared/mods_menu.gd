# mods_menu.gd
# ----------------------------------------------------------------------------
# Project Nexus - Mods management screen (Phase MC6, step 6.3, request 7).
#
# The player-facing screen that fulfils request 7: "let me see the mods that are
# installed, turn each ENABLED on/off, and pick ONE MAIN mod -- and remember my
# choice next time." It is deliberately thin, exactly like options_menu.gd:
#
#   * DISCOVERY of what is on disk is delegated to ModLoader.discover_mods()
#     (the same path the game boots with).
#   * All list/selection LOGIC (sort, enabled flags, main resolution, toggle,
#     sanitise) is delegated to the pure, headless-tested ActiveModUtil (MC6.1).
#   * PERSISTENCE is delegated to the tested GameSettings service (MC6.2): the
#     enabled ids live in "active_mods" and the chosen main id in "main_mod".
#
# The whole list is built PROGRAMMATICALLY (no hand-authored rows in the .tscn)
# so the UI can never drift from a stale scene file -- the row count depends on
# what is discovered at run time. The root .tscn only supplies a Control plus a
# ScrollContainer host; everything inside is created here.
#
# This screen only edits a COSMETIC/content-selection preference; it never
# mutates WorldState gameplay and never feeds the deterministic simulation hash.
#
# CODE LANGUAGE POLICY: English-only identifiers/comments (ASCII); visible text
# via Localization (English keys -> localized display text).
# ----------------------------------------------------------------------------
extends Control

const MAIN_MENU_SCENE: String = "res://scenes/main_menu.tscn"
const MODS_DIR: String = "res://mods"

var _settings: GameSettings = null
var _loc: Localization = null

# The raw manifests discovered on disk (ModLoader.discover_mods output).
var _discovered: Array = []

# Programmatically-built widgets.
var _title: Label = null
var _rows_box: VBoxContainer = null
var _empty_label: Label = null
var _back_button: Button = null


func _ready() -> void:
	_settings = GameSettings.new(_world_state())
	_settings.load_from_file()

	_loc = Localization.new()
	_loc.load_all("res://localization")
	_loc.set_locale(_settings.get_locale())

	_apply_ui_scale()
	if is_inside_tree() and get_viewport() != null:
		get_viewport().size_changed.connect(_apply_ui_scale)

	_discovered = _discover_mods()
	# Reconcile the persisted selection against what is really on disk so a mod
	# deleted since last launch cannot linger in the saved list.
	_settings.set_active_mods(ActiveModUtil.sanitise_active(_settings.get_active_mods(), _discovered))
	_settings.set_main_mod(ActiveModUtil.resolve_main(_settings.get_main_mod(), _settings.get_active_mods(), _discovered))
	_persist()

	_build()
	_refresh()


# --- Discovery --------------------------------------------------------------

# Discover mods with the SAME loader the game boots with. Falls back to an empty
# list (no crash) when the mods directory is absent so the screen still opens.
func _discover_mods() -> Array:
	var data_loader: DataLoader = DataLoader.new()
	return ModLoader.discover_mods(data_loader, MODS_DIR)


# --- UI construction (programmatic) -----------------------------------------

func _build() -> void:
	# A centered column that holds the title, the (scrollable) list, and Back.
	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var box: VBoxContainer = VBoxContainer.new()
	box.custom_minimum_size = Vector2(480, 0)
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)

	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)

	# The list of discovered mods lives in a scroll host so a large mod set does
	# not overflow the screen on a phone.
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(480, 360)
	box.add_child(scroll)

	_rows_box = VBoxContainer.new()
	_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows_box.add_theme_constant_override("separation", 8)
	scroll.add_child(_rows_box)

	_empty_label = Label.new()
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_label.visible = false
	box.add_child(_empty_label)

	_back_button = Button.new()
	_back_button.pressed.connect(_on_back)
	box.add_child(_back_button)


# (Re)build the per-mod rows from the current discovery + persisted selection.
func _refresh() -> void:
	_title.text = _loc.t("ui.mods.title")
	_back_button.text = _loc.t("ui.mods.back")

	# Clear the previous rows.
	for child in _rows_box.get_children():
		child.queue_free()

	var rows: Array = ActiveModUtil.list_mods(_discovered, _settings.get_active_mods(), _settings.get_main_mod())
	_empty_label.visible = rows.is_empty()
	if rows.is_empty():
		_empty_label.text = _loc.t("ui.mods.empty")
		return

	for row in rows:
		_rows_box.add_child(_make_row(row as Dictionary))


# Build a single mod row: [ name ] [ Enabled: on/off ] [ Main: yes/- ].
func _make_row(row: Dictionary) -> HBoxContainer:
	var id: String = str(row.get("id", ""))
	var line: HBoxContainer = HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)

	var name_label: Label = Label.new()
	name_label.text = _mod_display_name(row)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(name_label)

	var enable_button: Button = Button.new()
	enable_button.text = "%s: %s" % [_loc.t("ui.mods.enabled"), _on_off(bool(row.get("enabled", false)))]
	enable_button.pressed.connect(_on_toggle.bind(id))
	line.add_child(enable_button)

	var main_button: Button = Button.new()
	main_button.text = "%s: %s" % [_loc.t("ui.mods.main"), _yes_dash(bool(row.get("is_main", false)))]
	main_button.pressed.connect(_on_pick_main.bind(id))
	line.add_child(main_button)

	return line


# --- Handlers (mutate the persisted selection through ActiveModUtil) ---------

func _on_toggle(id: String) -> void:
	var next: Array = ActiveModUtil.toggle(_settings.get_active_mods(), id, _discovered)
	_settings.set_active_mods(next)
	# If the main mod was just disabled it can no longer be main -- re-resolve so
	# the persisted main never points at a disabled mod.
	_settings.set_main_mod(ActiveModUtil.resolve_main(_settings.get_main_mod(), next, _discovered))
	_persist()
	_refresh()


func _on_pick_main(id: String) -> void:
	# Picking main on the current main toggles it OFF (clears the choice); picking
	# a different (enabled) mod makes it main. resolve_main enforces "must be
	# enabled + present", so a non-enabled pick simply clears to "".
	var current_main: String = _settings.get_main_mod()
	var wanted: String = "" if id == current_main else id
	# Choosing a mod as main implies it must be enabled; enable it first so the
	# pick is not silently dropped by resolve_main.
	if wanted != "" and not ActiveModUtil.is_active(_settings.get_active_mods(), wanted, _discovered):
		_settings.set_active_mods(ActiveModUtil.toggle(_settings.get_active_mods(), wanted, _discovered))
	_settings.set_main_mod(ActiveModUtil.resolve_main(wanted, _settings.get_active_mods(), _discovered))
	_persist()
	_refresh()


func _on_back() -> void:
	_persist()
	if _has_tree():
		get_tree().change_scene_to_file(MAIN_MENU_SCENE)


# MB3.2 (bug 6): Android BACK / ESC / gamepad-B all return to the parent screen
# (NavService: main menu), never quit the app.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_on_back()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _has_tree():
			get_viewport().set_input_as_handled()
		_on_back()


# --- Display helpers --------------------------------------------------------

# A mod's shown name: prefer a localized display key, else the raw id verbatim.
func _mod_display_name(row: Dictionary) -> String:
	var key: String = str(row.get("name_key", ""))
	if key == "":
		return str(row.get("id", ""))
	var shown: String = _loc.t(key)
	# Localization returns the key unchanged when it has no entry; in that case
	# show the raw id/key so the row is never blank.
	if shown == key:
		return key
	return shown


func _on_off(value: bool) -> String:
	return _loc.t("ui.mods.on") if value else _loc.t("ui.mods.off")


func _yes_dash(value: bool) -> String:
	return _loc.t("ui.mods.yes") if value else "-"


# --- Infrastructure ---------------------------------------------------------

func _persist() -> void:
	_settings.save_to_file()


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
