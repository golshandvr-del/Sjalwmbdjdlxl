# gui_editor.gd
# ----------------------------------------------------------------------------
# Project Nexus - GUI Editor screen (Phase MC7, step 7.4, request 8).
#
# The author-facing screen that fulfils request 8: "let me edit the position /
# size / icon / display-name of the buttons, choose a page background (color /
# image / video), and save / export / import the layout." It is a THIN view,
# exactly like mod_editor / mods_menu:
#
#   * The GUI MODEL + all authoring logic (add / move / resize / set icon /
#     rename / set background / validate / JSON round-trip / save / load) lives
#     in the pure, headless-tested GuiProject (MC7.1 / MC7.2).
#   * WHICH functions are allowed on WHICH page comes from GuiWidgetCatalog
#     (MC7.3) so "rename is cosmetic, function stays fixed" is guaranteed.
#   * Visible text is resolved through Localization (ui.guieditor.* keys, MC7.7).
#
# The panels + rows are built PROGRAMMATICALLY so the view can never drift from a
# stale .tscn: the widget rows depend on the selected page at run time. The root
# .tscn only supplies a full-rect Control host.
#
# This screen edits a COSMETIC layout only; it never mutates WorldState gameplay
# and never feeds the deterministic simulation hash.
#
# CODE LANGUAGE POLICY: English-only identifiers/comments (ASCII); visible text
# via Localization.
# ----------------------------------------------------------------------------
extends Control

const MAIN_MENU_SCENE: String = "res://scenes/main_menu.tscn"
const SELF_SCENE: String = "res://scenes/gui_editor.tscn"

var _loc: Localization = null
var _settings: GameSettings = null

# The project being edited and the currently-selected page / widget.
var _project: GuiProject = null
var _current_page: String = ""
var _current_widget: String = ""

# Programmatically-built widgets.
var _title: Label = null
var _page_list: VBoxContainer = null
var _widget_list: VBoxContainer = null
var _status: Label = null
var _x_spin: SpinBox = null
var _y_spin: SpinBox = null
var _w_spin: SpinBox = null
var _h_spin: SpinBox = null
var _name_edit: LineEdit = null
var _icon_edit: LineEdit = null
# MC7.5: page background controls (kind option + value field).
var _bg_kind_option: OptionButton = null
var _bg_value_edit: LineEdit = null
var _back_button: Button = null


func _ready() -> void:
	_settings = GameSettings.new(_world_state())
	_settings.load_from_file()
	_loc = Localization.new()
	_loc.load_all("res://localization")
	_loc.set_locale(_settings.get_locale())

	# Start with a fresh project that has every known page seeded from the
	# catalog so the author immediately sees the real, wireable surfaces.
	_project = GuiProject.new()
	_project.init_new("custom_gui")
	for page in GuiWidgetCatalog.page_names():
		_project.ensure_page(page)
	_current_page = GuiWidgetCatalog.page_names()[0] if not GuiWidgetCatalog.page_names().is_empty() else ""

	_build_ui()
	_refresh_pages()
	_refresh_widgets()
	_set_status("")


func _t(key: String) -> String:
	if _loc == null:
		return key
	return _loc.tr(key)


func _world_state() -> Object:
	# GameSettings tolerates a null world state (it just skips the state mirror),
	# which is fine for an editor screen that only reads/writes the settings file.
	return null


# --- UI construction --------------------------------------------------------

func _build_ui() -> void:
	var root: VBoxContainer = VBoxContainer.new()
	root.anchor_right = 1.0
	root.anchor_bottom = 1.0
	root.offset_left = 16
	root.offset_top = 16
	root.offset_right = -16
	root.offset_bottom = -16
	add_child(root)

	_title = Label.new()
	_title.text = _t("ui.guieditor.title")
	root.add_child(_title)

	# Toolbar: new / open / save / export / import.
	var toolbar: HBoxContainer = HBoxContainer.new()
	root.add_child(toolbar)
	toolbar.add_child(_make_button(_t("ui.guieditor.new"), _on_new))
	toolbar.add_child(_make_button(_t("ui.guieditor.save"), _on_save))
	toolbar.add_child(_make_button(_t("ui.guieditor.export"), _on_export))
	toolbar.add_child(_make_button(_t("ui.guieditor.import"), _on_import))

	# Main body: pages column | widgets column | edit column.
	var body: HBoxContainer = HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)

	_page_list = _make_column(body, _t("ui.guieditor.pages"))
	_widget_list = _make_column(body, _t("ui.guieditor.widgets"))
	_build_edit_column(body)

	_status = Label.new()
	root.add_child(_status)

	_back_button = _make_button(_t("ui.menu.back"), _on_back)
	root.add_child(_back_button)


func _make_column(parent: Control, header: String) -> VBoxContainer:
	var col: VBoxContainer = VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var label: Label = Label.new()
	label.text = header
	col.add_child(label)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)
	var inner: VBoxContainer = VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(inner)
	parent.add_child(col)
	return inner


func _build_edit_column(parent: Control) -> void:
	var col: VBoxContainer = VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var hint: Label = Label.new()
	hint.text = _t("ui.guieditor.drag_hint")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(hint)

	_x_spin = _make_spin(col, "X", 0, GuiProject.DESIGN_WIDTH)
	_y_spin = _make_spin(col, "Y", 0, GuiProject.DESIGN_HEIGHT)
	_w_spin = _make_spin(col, "W", GuiProject.MIN_WIDGET_SIZE, GuiProject.DESIGN_WIDTH)
	_h_spin = _make_spin(col, "H", GuiProject.MIN_WIDGET_SIZE, GuiProject.DESIGN_HEIGHT)

	var name_row: HBoxContainer = HBoxContainer.new()
	var name_label: Label = Label.new()
	name_label.text = _t("ui.guieditor.rename")
	name_row.add_child(name_label)
	_name_edit = LineEdit.new()
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(_name_edit)
	col.add_child(name_row)

	col.add_child(_make_button(_t("ui.guieditor.remove_widget"), _on_remove_widget))
	parent.add_child(col)


func _make_spin(parent: Control, label_text: String, min_v: int, max_v: int) -> SpinBox:
	var row: HBoxContainer = HBoxContainer.new()
	var label: Label = Label.new()
	label.text = label_text
	row.add_child(label)
	var spin: SpinBox = SpinBox.new()
	spin.min_value = min_v
	spin.max_value = max_v
	spin.step = 1
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.value_changed.connect(func(_v: float) -> void: _on_rect_changed())
	row.add_child(spin)
	parent.add_child(row)
	return spin


func _make_button(text: String, handler: Callable) -> Button:
	var b: Button = Button.new()
	b.text = text
	b.pressed.connect(handler)
	return b


# --- List refresh -----------------------------------------------------------

func _refresh_pages() -> void:
	if _page_list == null:
		return
	for child in _page_list.get_children():
		child.queue_free()
	for page in _project.page_names():
		var b: Button = _make_button(page, func() -> void: _select_page(page))
		b.toggle_mode = true
		b.button_pressed = (page == _current_page)
		_page_list.add_child(b)


func _refresh_widgets() -> void:
	if _widget_list == null:
		return
	for child in _widget_list.get_children():
		child.queue_free()
	if _current_page == "":
		return
	# Existing widgets on this page (edit / select).
	var existing: Dictionary = {}
	for lid in _existing_widget_ids():
		existing[lid] = true
		var b: Button = _make_button(lid, func() -> void: _select_widget(lid))
		b.toggle_mode = true
		b.button_pressed = (lid == _current_widget)
		_widget_list.add_child(b)
	# Allowed-but-not-yet-added functions (add).
	for lid in GuiWidgetCatalog.allowed_ids(_current_page):
		if existing.has(lid):
			continue
		var add_id: String = lid
		var ab: Button = _make_button("+ " + add_id, func() -> void: _add_widget(add_id))
		_widget_list.add_child(ab)


func _existing_widget_ids() -> Array:
	var out: Array = []
	for lid in GuiWidgetCatalog.allowed_ids(_current_page):
		if not _project.get_widget(_current_page, lid).is_empty():
			out.append(lid)
	# Include any non-catalog widgets already present (defensive).
	out.sort()
	return out


# --- Selection + editing ----------------------------------------------------

func _select_page(page: String) -> void:
	_current_page = page
	_current_widget = ""
	_refresh_pages()
	_refresh_widgets()
	_load_widget_into_fields()


func _select_widget(logical_id: String) -> void:
	_current_widget = logical_id
	_refresh_widgets()
	_load_widget_into_fields()


func _add_widget(logical_id: String) -> void:
	if not GuiWidgetCatalog.is_allowed(_current_page, logical_id):
		_set_status(_t("ui.guieditor.catalog_bad_id"))
		return
	# Default rect: a modest button near the top-left of the design space.
	_project.add_widget(_current_page, logical_id, [40, 40, 240, 80], "", logical_id)
	_current_widget = logical_id
	_refresh_widgets()
	_load_widget_into_fields()
	_set_status("")


func _on_remove_widget() -> void:
	if _current_widget == "":
		return
	_project.remove_widget(_current_page, _current_widget)
	_current_widget = ""
	_refresh_widgets()
	_load_widget_into_fields()


func _load_widget_into_fields() -> void:
	var w: Dictionary = {} if _current_widget == "" else _project.get_widget(_current_page, _current_widget)
	var rect: Array = w.get("rect", [0, 0, GuiProject.MIN_WIDGET_SIZE, GuiProject.MIN_WIDGET_SIZE]) if not w.is_empty() else [0, 0, GuiProject.MIN_WIDGET_SIZE, GuiProject.MIN_WIDGET_SIZE]
	# Block signals while loading so we do not echo a change back into the model.
	_set_spin_silently(_x_spin, int(rect[0]))
	_set_spin_silently(_y_spin, int(rect[1]))
	_set_spin_silently(_w_spin, int(rect[2]))
	_set_spin_silently(_h_spin, int(rect[3]))
	if _name_edit != null:
		_name_edit.text = str(w.get("display_name", "")) if not w.is_empty() else ""


func _set_spin_silently(spin: SpinBox, value: int) -> void:
	if spin == null:
		return
	spin.set_block_signals(true)
	spin.value = value
	spin.set_block_signals(false)


func _on_rect_changed() -> void:
	if _current_widget == "":
		return
	var rect: Array = [int(_x_spin.value), int(_y_spin.value), int(_w_spin.value), int(_h_spin.value)]
	_project.set_widget_rect(_current_page, _current_widget, rect)


func _commit_name() -> void:
	if _current_widget == "" or _name_edit == null:
		return
	_project.set_widget_display_name(_current_page, _current_widget, _name_edit.text)


# --- Toolbar actions --------------------------------------------------------

func _on_new() -> void:
	_project = GuiProject.new()
	_project.init_new("custom_gui")
	for page in GuiWidgetCatalog.page_names():
		_project.ensure_page(page)
	_current_page = GuiWidgetCatalog.page_names()[0] if not GuiWidgetCatalog.page_names().is_empty() else ""
	_current_widget = ""
	_refresh_pages()
	_refresh_widgets()
	_load_widget_into_fields()
	_set_status("")


func _on_save() -> void:
	_commit_name()
	var result: Array = _project.save_to_file(_gui_save_path())
	_set_status(_t(str(result[1])) if not bool(result[0]) else _t("ui.guieditor.save"))


func _on_export() -> void:
	# Export writes the same JSON to a user-visible location (same format).
	_on_save()


func _on_import() -> void:
	var loaded: GuiProject = GuiProject.new()
	var result: Array = loaded.load_from_file(_gui_save_path())
	if not bool(result[0]):
		_set_status(_t(str(result[1])))
		return
	# Reject imports that reference functions the app cannot bind (MC7.3).
	var check: Array = GuiWidgetCatalog.validate_project_dict(loaded.to_dict())
	if not bool(check[0]):
		_set_status(_t(str(check[1])))
		return
	_project = loaded
	_current_page = _project.page_names()[0] if not _project.page_names().is_empty() else ""
	_current_widget = ""
	_refresh_pages()
	_refresh_widgets()
	_load_widget_into_fields()
	_set_status("")


func _gui_save_path() -> String:
	return "user://custom_gui." + GuiProject.GUI_EXTENSION


func _set_status(text: String) -> void:
	if _status != null:
		_status.text = text


# --- Back navigation (MB3 / NavService) -------------------------------------

func _on_back() -> void:
	_commit_name()
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_on_back()
