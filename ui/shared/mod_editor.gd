# mod_editor.gd
# ----------------------------------------------------------------------------
# Project Nexus - Graphical Mod Editor screen (Phase P6, R8 full rebuild).
#
# This is the P6 rebuild of the Mod Editor UI. The previous version only exposed
# three sliders (hp / cost / colour) and a flat list; it never surfaced the rich
# authoring model that already lives, fully headless-tested, in `ModProject`
# (tools/mod_project.gd). This rebuild finally wires the model's real features
# into a usable screen, exactly as the user asked (STRUCTURE.md sec 4.7 / R8):
#
#   * TREE / MIND-MAP per catalog (Units / Buildings / Objects) whose centre is
#     the RAW core node. Clicking a node opens a context menu with:
#       "Rename", "Build", "Add subgroup" (add_child), "Add sibling" (add_sibling).
#     (R8.0)
#   * On "Build" a dialog offers the exclusive SINGLE-PART / MULTI-PART choice
#     with the explanatory note that single-part entities cannot be fused. (R8.1)
#   * The entity editor then shows THREE TABS:
#       Units:     Main / Upgrade / Training
#       Buildings: Main / Upgrade / Build-Tech
#       Objects:   Main (+ placement / extractable) -- object has no upgrade/train
#     (R8.2 / R8.3 / R9.1)
#   * MAIN tab: pixel dimensions + image upload (PNG 16..512, shown under the box),
#     plus a STAT PICKER where the user ticks which stats this entity/part has and
#     fills a value for the ones that need one (StatRegistry). Multi-part shows one
#     stat group per part and enforces non-overlapping groups via ModProject's
#     validate(). (R8.2 main)
#   * UPGRADE tab: trigger (kill_count / time / tech node) + effects + optional
#     visual growth (hard-capped at +15% by the model). (R8.2 upgrade)
#   * TRAINING / BUILD-TECH tab: from_building / cost / required_tech as dropdowns
#     of already-defined entities (no free text). (R8.2 training)
#
# The view stays THIN: all mutation goes through ModProject; this file only builds
# widgets, maps events onto the model, and re-renders. Saving reaches the same
# StorageService content root the game loads from, so a saved mod is immediately
# play-testable.
#
# The whole tree is built PROGRAMMATICALLY (no hand-authored .tscn beyond a root
# Control) so it can never drift from a stale scene file -- the P6 predecessor
# broke exactly because the .tscn and script disagreed.
#
# CODE LANGUAGE POLICY: English-only identifiers/comments; visible text via
# Localization (English keys -> localized display text).
# ----------------------------------------------------------------------------
extends Control

const MAIN_MENU_SCENE: String = "res://scenes/main_menu.tscn"

# Context-menu action ids (kept as ints for PopupMenu.id_pressed).
const MENU_RENAME: int = 0
const MENU_BUILD: int = 1
const MENU_ADD_CHILD: int = 2
const MENU_ADD_SIBLING: int = 3
const MENU_DELETE: int = 4

var _project: ModProject = null
var _loc: Localization = null
var _settings: GameSettings = null
var _storage: StorageService = null

# Which catalog the tree currently shows ("units" / "buildings" / "objects").
var _active_catalog: String = ModProject.UNITS_CATALOG
# The node id selected in the tree (for context actions + editing).
var _selected_id: String = ""
# The node a pending context action refers to (set when the menu opens).
var _context_id: String = ""

# --- Widgets (all created in _build_ui) ------------------------------------
var _title: Label
var _mod_id_edit: LineEdit
var _mod_name_edit: LineEdit
var _tab_buttons: Dictionary = {}      # catalog -> Button
var _tree: Tree
var _detail_host: VBoxContainer        # where the per-entity editor is rebuilt
var _status_label: Label
var _context_menu: PopupMenu
var _name_dialog: AcceptDialog
var _name_dialog_edit: LineEdit
var _build_dialog: AcceptDialog
var _file_dialog: FileDialog

# The stat-value spinboxes currently on screen, keyed by "part:<i>:<stat>" so a
# value edit can find its way back into the right part. Rebuilt every render.
var _stat_controls: Dictionary = {}
# The part index a pending image upload targets (single-part uses 0).
var _upload_part_index: int = 0


func _ready() -> void:
	UiScale.apply_from_settings(self, _world_state())
	_loc = Localization.new()
	_loc.load_all("res://localization")
	_settings = GameSettings.new(_world_state())
	_settings.load_from_file()
	_loc.set_locale(_settings.get_locale())
	_storage = StorageService.new(_settings.get_content_path())
	_storage.ensure_content_root()

	_project = ModProject.new()
	_project.new_project("new_mod", "New Mod")

	_build_ui()
	_refresh_all()


# --- UI construction --------------------------------------------------------

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg: ColorRect = ColorRect.new()
	bg.color = Color(0.09, 0.10, 0.13, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root: VBoxContainer = VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 8)
	root.offset_left = 12
	root.offset_top = 12
	root.offset_right = -12
	root.offset_bottom = -12
	add_child(root)

	_build_header(root)
	_build_body(root)
	_build_footer(root)
	_build_dialogs()


func _build_header(root: VBoxContainer) -> void:
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 24)
	root.add_child(_title)

	var meta: HBoxContainer = HBoxContainer.new()
	meta.add_theme_constant_override("separation", 8)
	root.add_child(meta)
	_mod_id_edit = LineEdit.new()
	_mod_id_edit.custom_minimum_size = Vector2(180, 0)
	_mod_id_edit.text_changed.connect(func(t: String) -> void: _project.set_manifest_field("id", ModProject.normalise_id(t)))
	meta.add_child(_mod_id_edit)
	_mod_name_edit = LineEdit.new()
	_mod_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mod_name_edit.text_changed.connect(func(t: String) -> void: _project.set_manifest_field("name", t))
	meta.add_child(_mod_name_edit)


func _build_body(root: VBoxContainer) -> void:
	# Catalog tabs (Units / Buildings / Objects).
	var tab_row: HBoxContainer = HBoxContainer.new()
	tab_row.add_theme_constant_override("separation", 6)
	root.add_child(tab_row)
	for catalog in [ModProject.UNITS_CATALOG, ModProject.BUILDINGS_CATALOG, ModProject.OBJECTS_CATALOG]:
		var b: Button = Button.new()
		b.pressed.connect(func() -> void: _set_catalog(catalog))
		tab_row.add_child(b)
		_tab_buttons[catalog] = b

	# Split: tree on the left, per-entity editor on the right.
	var split: HSplitContainer = HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.split_offset = 320
	root.add_child(split)

	_tree = Tree.new()
	_tree.custom_minimum_size = Vector2(300, 0)
	_tree.hide_root = false
	_tree.allow_rmb_select = true
	_tree.item_selected.connect(_on_tree_item_selected)
	_tree.item_mouse_selected.connect(_on_tree_item_clicked)
	split.add_child(_tree)

	var detail_scroll: ScrollContainer = ScrollContainer.new()
	detail_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(detail_scroll)
	_detail_host = VBoxContainer.new()
	_detail_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_host.add_theme_constant_override("separation", 8)
	detail_scroll.add_child(_detail_host)


func _build_footer(root: VBoxContainer) -> void:
	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_status_label)

	var footer: HBoxContainer = HBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)
	root.add_child(footer)
	var new_btn: Button = Button.new()
	new_btn.text = _loc.t("ui.modeditor.new")
	new_btn.pressed.connect(_on_new)
	footer.add_child(new_btn)
	var save_btn: Button = Button.new()
	save_btn.text = _loc.t("ui.modeditor.save")
	save_btn.pressed.connect(_on_save)
	footer.add_child(save_btn)
	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)
	var back_btn: Button = Button.new()
	back_btn.text = _loc.t("ui.options.back")
	back_btn.pressed.connect(_on_back)
	footer.add_child(back_btn)


func _build_dialogs() -> void:
	# Right-click context menu for tree nodes.
	_context_menu = PopupMenu.new()
	_context_menu.add_item(_loc.t("ui.modeditor.ctx.rename"), MENU_RENAME)
	_context_menu.add_item(_loc.t("ui.modeditor.ctx.build"), MENU_BUILD)
	_context_menu.add_item(_loc.t("ui.modeditor.ctx.add_child"), MENU_ADD_CHILD)
	_context_menu.add_item(_loc.t("ui.modeditor.ctx.add_sibling"), MENU_ADD_SIBLING)
	_context_menu.add_separator()
	_context_menu.add_item(_loc.t("ui.modeditor.ctx.delete"), MENU_DELETE)
	_context_menu.id_pressed.connect(_on_context_action)
	add_child(_context_menu)

	# Naming dialog (used by rename / add child / add sibling).
	_name_dialog = AcceptDialog.new()
	_name_dialog.title = _loc.t("ui.modeditor.ctx.name")
	_name_dialog_edit = LineEdit.new()
	_name_dialog_edit.custom_minimum_size = Vector2(280, 0)
	_name_dialog.add_child(_name_dialog_edit)
	add_child(_name_dialog)

	# Build (single/multi) dialog.
	_build_dialog = AcceptDialog.new()
	_build_dialog.title = _loc.t("ui.modeditor.ctx.build")
	add_child(_build_dialog)

	# Image upload dialog (PNG only).
	_file_dialog = FileDialog.new()
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.add_filter("*.png", "PNG")
	_file_dialog.use_native_dialog = true
	_file_dialog.file_selected.connect(_on_image_selected)
	add_child(_file_dialog)


# --- Catalog + tree ---------------------------------------------------------

func _set_catalog(catalog: String) -> void:
	_active_catalog = catalog
	_selected_id = ""
	_refresh_tree()
	_refresh_detail()
	_refresh_labels()


# Rebuild the Tree control from ModProject.build_tree(). The root row is the RAW
# core node ("Raw Unit" / "Raw Building" / object root); every authored node hangs
# under it. Each TreeItem stores its model id in metadata 0.
func _refresh_tree() -> void:
	_tree.clear()
	var model_tree: Dictionary = _project.build_tree(_active_catalog)
	var root_item: TreeItem = _tree.create_item()
	root_item.set_text(0, _root_label())
	root_item.set_metadata(0, _project.root_for(_active_catalog))
	_add_tree_children(root_item, model_tree.get("children", []))
	root_item.set_collapsed(false)


func _add_tree_children(parent_item: TreeItem, children: Array) -> void:
	for child in children:
		var node_id: String = str((child as Dictionary).get("id", ""))
		var item: TreeItem = _tree.create_item(parent_item)
		item.set_text(0, node_id)
		item.set_metadata(0, node_id)
		_add_tree_children(item, (child as Dictionary).get("children", []))


func _root_label() -> String:
	match _active_catalog:
		ModProject.UNITS_CATALOG: return _loc.t("ui.modeditor.root.unit")
		ModProject.BUILDINGS_CATALOG: return _loc.t("ui.modeditor.root.building")
		ModProject.OBJECTS_CATALOG: return _loc.t("ui.modeditor.root.object")
		_: return "?"


func _on_tree_item_selected() -> void:
	var item: TreeItem = _tree.get_selected()
	if item == null:
		return
	var id: String = str(item.get_metadata(0))
	# The root row is not an editable entity.
	_selected_id = "" if id == _project.root_for(_active_catalog) else id
	_refresh_detail()


# A left OR right click on a node pops the context menu at the mouse (R8.0).
func _on_tree_item_clicked(_pos: Vector2, mouse_button: int) -> void:
	if mouse_button != MOUSE_BUTTON_RIGHT and mouse_button != MOUSE_BUTTON_LEFT:
		return
	var item: TreeItem = _tree.get_selected()
	if item == null:
		return
	_context_id = str(item.get_metadata(0))
	# Root can only receive "Add subgroup" (a first top-level node) or "Build".
	var is_root: bool = _context_id == _project.root_for(_active_catalog)
	_context_menu.set_item_disabled(_context_menu.get_item_index(MENU_RENAME), is_root)
	_context_menu.set_item_disabled(_context_menu.get_item_index(MENU_BUILD), is_root)
	_context_menu.set_item_disabled(_context_menu.get_item_index(MENU_ADD_SIBLING), is_root)
	_context_menu.set_item_disabled(_context_menu.get_item_index(MENU_DELETE), is_root)
	_context_menu.position = Vector2i(get_viewport().get_mouse_position())
	_context_menu.reset_size()
	_context_menu.popup()


# --- Context-menu actions ---------------------------------------------------

func _on_context_action(id: int) -> void:
	match id:
		MENU_RENAME:
			_open_name_dialog("rename", _context_id)
		MENU_ADD_CHILD:
			_open_name_dialog("add_child", _context_id)
		MENU_ADD_SIBLING:
			_open_name_dialog("add_sibling", _context_id)
		MENU_BUILD:
			_open_build_dialog(_context_id)
		MENU_DELETE:
			_delete_node(_context_id)


# Open the naming dialog. `_name_action` records what to do with the entered name.
var _name_action: String = ""
var _name_target: String = ""

func _open_name_dialog(action: String, target_id: String) -> void:
	_name_action = action
	_name_target = target_id
	_name_dialog_edit.text = target_id if action == "rename" else ""
	_name_dialog_edit.placeholder_text = _loc.t("ui.modeditor.new_id")
	# (Re)connect confirmed to a fresh handler each open (guard double-connect).
	if not _name_dialog.confirmed.is_connected(_on_name_confirmed):
		_name_dialog.confirmed.connect(_on_name_confirmed)
	_name_dialog.popup_centered()
	_name_dialog_edit.grab_focus()


func _on_name_confirmed() -> void:
	var raw: String = _name_dialog_edit.text
	var clean: String = ModProject.normalise_id(raw)
	if clean == "":
		_set_status(_loc.t("ui.modeditor.status.bad_id"))
		return
	var result: String = ""
	match _name_action:
		"rename":
			result = _project.rename_node(_active_catalog, _name_target, clean)
		"add_child":
			# A brand-new node is created under the target and must be BUILT next.
			result = _project.add_child(_active_catalog, _name_target, clean)
		"add_sibling":
			result = _project.add_sibling(_active_catalog, _name_target, clean)
	if result == "":
		_set_status(_loc.t("ui.modeditor.status.bad_id"))
		return
	_selected_id = result
	_set_status(_loc.t("ui.modeditor.status.added"))
	_refresh_tree()
	_refresh_detail()


# The Build dialog: exclusive single-part / multi-part choice with the note that
# single-part entities cannot be fused (R8.1).
func _open_build_dialog(target_id: String) -> void:
	_name_target = target_id
	for child in _build_dialog.get_children():
		if child is VBoxContainer:
			child.queue_free()
	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_build_dialog.add_child(box)
	var note: Label = Label.new()
	note.text = _loc.t("ui.modeditor.build.note")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(360, 0)
	box.add_child(note)
	var single_btn: Button = Button.new()
	single_btn.text = _loc.t("ui.modeditor.build.single")
	single_btn.pressed.connect(func() -> void: _apply_build(target_id, false))
	box.add_child(single_btn)
	# Objects are always single-part (they are static decorations / resources).
	if _active_catalog != ModProject.OBJECTS_CATALOG:
		var multi_btn: Button = Button.new()
		multi_btn.text = _loc.t("ui.modeditor.build.multi")
		multi_btn.pressed.connect(func() -> void: _apply_build(target_id, true))
		box.add_child(multi_btn)
	_build_dialog.popup_centered()


func _apply_build(target_id: String, multi: bool) -> void:
	# Preserve the node's tree position (parent/order) while swapping in a fresh
	# single/multi skeleton under the same id.
	var editor_meta: Dictionary = {}
	var existing: Dictionary = _get_entity(target_id)
	if existing.has("editor"):
		editor_meta = (existing["editor"] as Dictionary).duplicate(true)
	var def: Dictionary = {}
	match _active_catalog:
		ModProject.UNITS_CATALOG:
			def = ModProject.default_multipart_unit(target_id, 2) if multi else ModProject.default_unit(target_id)
		ModProject.BUILDINGS_CATALOG:
			def = ModProject.default_multipart_building(target_id, 2) if multi else ModProject.default_building(target_id)
		ModProject.OBJECTS_CATALOG:
			def = ModProject.default_object(target_id)
	if not editor_meta.is_empty():
		def["editor"] = editor_meta
	_set_entity(target_id, def)
	_selected_id = target_id
	_build_dialog.hide()
	_set_status(_loc.t("ui.modeditor.status.built"))
	_refresh_tree()
	_refresh_detail()


func _delete_node(target_id: String) -> void:
	match _active_catalog:
		ModProject.UNITS_CATALOG: _project.remove_unit(target_id)
		ModProject.BUILDINGS_CATALOG: _project.remove_building(target_id)
		ModProject.OBJECTS_CATALOG: _project.remove_object(target_id)
	if _selected_id == target_id:
		_selected_id = ""
	_set_status(_loc.t("ui.modeditor.status.removed"))
	_refresh_tree()
	_refresh_detail()


# --- Entity accessors (catalog-agnostic) ------------------------------------

func _get_entity(id: String) -> Dictionary:
	match _active_catalog:
		ModProject.UNITS_CATALOG: return _project.get_unit(id)
		ModProject.BUILDINGS_CATALOG: return _project.get_building(id)
		ModProject.OBJECTS_CATALOG: return _project.get_object(id)
		_: return {}


func _set_entity(id: String, def: Dictionary) -> void:
	match _active_catalog:
		ModProject.UNITS_CATALOG: _project.set_unit(id, def)
		ModProject.BUILDINGS_CATALOG: _project.set_building(id, def)
		ModProject.OBJECTS_CATALOG: _project.set_object(id, def)


func _selected_entity() -> Dictionary:
	if _selected_id == "":
		return {}
	return _get_entity(_selected_id)


func _commit(entity: Dictionary) -> void:
	_set_entity(_selected_id, entity)


func _is_multi(entity: Dictionary) -> bool:
	var g: Variant = entity.get("graphic", {})
	return g is Dictionary and str((g as Dictionary).get("mode", "")) == GraphicModel.MODE_MULTI


func _stat_scope() -> String:
	# StatRegistry.ids_for() expects "unit" / "building" / "object".
	match _active_catalog:
		ModProject.UNITS_CATALOG: return "unit"
		ModProject.BUILDINGS_CATALOG: return "building"
		ModProject.OBJECTS_CATALOG: return "object"
		_: return "unit"


# --- Detail editor (three tabs) ---------------------------------------------

func _refresh_detail() -> void:
	for child in _detail_host.get_children():
		child.queue_free()
	_stat_controls.clear()
	var entity: Dictionary = _selected_entity()
	if entity.is_empty():
		var hint: Label = Label.new()
		hint.text = _loc.t("ui.modeditor.detail.none")
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_detail_host.add_child(hint)
		return

	var heading: Label = Label.new()
	var kind: String = _loc.t("ui.modeditor.build.multi") if _is_multi(entity) else _loc.t("ui.modeditor.build.single")
	heading.text = "%s: %s  (%s)" % [_loc.t("ui.modeditor.detail.editing"), _selected_id, kind]
	heading.add_theme_font_size_override("font_size", 18)
	_detail_host.add_child(heading)

	var tabs: TabContainer = TabContainer.new()
	tabs.custom_minimum_size = Vector2(0, 420)
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_detail_host.add_child(tabs)

	# --- Main tab (graphic + stats) -----------------------------------------
	var main_tab: VBoxContainer = _make_tab(tabs, "ui.modeditor.tab.main")
	_build_main_tab(main_tab, entity)

	# Objects only need the Main tab (placement / extractable go there).
	if _active_catalog == ModProject.OBJECTS_CATALOG:
		var save_row: Button = Button.new()
		save_row.text = _loc.t("ui.modeditor.detail.save_entity")
		save_row.pressed.connect(func() -> void: _set_status(_loc.t("ui.modeditor.status.added")))
		_detail_host.add_child(save_row)
		return

	# --- Upgrade tab --------------------------------------------------------
	var upgrade_tab: VBoxContainer = _make_tab(tabs, "ui.modeditor.tab.upgrade")
	_build_upgrade_tab(upgrade_tab, entity)

	# --- Training / Build-Tech tab ------------------------------------------
	var third_key: String = "ui.modeditor.tab.training" if _active_catalog == ModProject.UNITS_CATALOG else "ui.modeditor.tab.buildtech"
	var third_tab: VBoxContainer = _make_tab(tabs, third_key)
	_build_training_tab(third_tab, entity)


func _make_tab(tabs: TabContainer, title_key: String) -> VBoxContainer:
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = _loc.t(title_key)
	tabs.add_child(scroll)
	var box: VBoxContainer = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	scroll.add_child(box)
	return box


# --- MAIN tab: graphic parts (px + upload) + stat picker --------------------

func _build_main_tab(box: VBoxContainer, entity: Dictionary) -> void:
	var graphic: Dictionary = entity.get("graphic", {}) as Dictionary
	var parts: Array = graphic.get("parts", []) as Array
	var multi: bool = _is_multi(entity)

	# One graphic block per part; single-part has exactly one.
	for i in range(parts.size()):
		var part_box: VBoxContainer = VBoxContainer.new()
		part_box.add_theme_constant_override("separation", 4)
		box.add_child(part_box)
		var part_title: Label = Label.new()
		if multi:
			part_title.text = "%s %d" % [_loc.t("ui.modeditor.part"), i + 1]
		else:
			part_title.text = _loc.t("ui.modeditor.graphic")
		part_title.add_theme_font_size_override("font_size", 15)
		part_box.add_child(part_title)
		_build_part_graphic_row(part_box, entity, i)
		# Per-part stats for multi-part; single-part uses the top-level stats.
		if multi:
			_build_stat_picker(part_box, entity, i)

	# Single-part stats live in the main stats dict (part index -1 marker).
	if not multi:
		var stats_label: Label = Label.new()
		stats_label.text = _loc.t("ui.modeditor.stats")
		stats_label.add_theme_font_size_override("font_size", 15)
		box.add_child(stats_label)
		_build_stat_picker(box, entity, -1)

	# Object-only extras: placement + extractable + yields (R9.1).
	if _active_catalog == ModProject.OBJECTS_CATALOG:
		_build_object_extras(box, entity)


# A "px width x height + upload PNG" row for one graphic part.
func _build_part_graphic_row(parent: VBoxContainer, entity: Dictionary, part_index: int) -> void:
	var graphic: Dictionary = entity.get("graphic", {}) as Dictionary
	var parts: Array = graphic.get("parts", []) as Array
	if part_index >= parts.size():
		return
	var part: Dictionary = parts[part_index] as Dictionary
	var px: Dictionary = part.get("px", {}) as Dictionary

	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)

	var w_label: Label = Label.new()
	w_label.text = _loc.t("ui.modeditor.px_w")
	row.add_child(w_label)
	var w_spin: SpinBox = SpinBox.new()
	w_spin.min_value = GraphicModel.MIN_PX
	w_spin.max_value = GraphicModel.MAX_PX
	w_spin.value = clampf(int(px.get("w", 64)), GraphicModel.MIN_PX, GraphicModel.MAX_PX)
	w_spin.value_changed.connect(func(v: float) -> void: _set_part_px(part_index, "w", int(v)))
	row.add_child(w_spin)

	var h_label: Label = Label.new()
	h_label.text = _loc.t("ui.modeditor.px_h")
	row.add_child(h_label)
	var h_spin: SpinBox = SpinBox.new()
	h_spin.min_value = GraphicModel.MIN_PX
	h_spin.max_value = GraphicModel.MAX_PX
	h_spin.value = clampf(int(px.get("h", 64)), GraphicModel.MIN_PX, GraphicModel.MAX_PX)
	h_spin.value_changed.connect(func(v: float) -> void: _set_part_px(part_index, "h", int(v)))
	row.add_child(h_spin)

	var upload: Button = Button.new()
	var tex: String = str(part.get("texture", ""))
	upload.text = _loc.t("ui.modeditor.upload") if tex == "" else tex.get_file()
	upload.pressed.connect(func() -> void:
		_upload_part_index = part_index
		_file_dialog.popup_centered_ratio(0.7))
	parent.add_child(upload)

	# The allowed-format hint, shown under the upload box (R8.2 requirement).
	var hint: Label = Label.new()
	hint.text = _loc.t("ui.modeditor.image_hint")
	hint.add_theme_font_size_override("font_size", 11)
	hint.modulate = Color(0.7, 0.7, 0.7)
	parent.add_child(hint)


func _set_part_px(part_index: int, axis: String, value: int) -> void:
	var entity: Dictionary = _selected_entity()
	var graphic: Dictionary = (entity.get("graphic", {}) as Dictionary).duplicate(true)
	var parts: Array = (graphic.get("parts", []) as Array).duplicate(true)
	if part_index < 0 or part_index >= parts.size():
		return
	var part: Dictionary = (parts[part_index] as Dictionary).duplicate(true)
	var px: Dictionary = (part.get("px", {}) as Dictionary).duplicate(true)
	px[axis] = value
	part["px"] = px
	parts[part_index] = part
	graphic["parts"] = parts
	entity["graphic"] = graphic
	_commit(entity)


# A checkbox-per-stat picker; ticking one reveals a value spinbox when the stat
# needs a value. Writes into part_stats[part_index] (multi) or stats (single).
func _build_stat_picker(parent: VBoxContainer, entity: Dictionary, part_index: int) -> void:
	var current: Dictionary = _stats_dict_for(entity, part_index)
	for stat_id in StatRegistry.ids_for(_stat_scope()):
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		parent.add_child(row)
		var check: CheckBox = CheckBox.new()
		check.text = stat_id
		check.button_pressed = current.has(stat_id)
		check.custom_minimum_size = Vector2(150, 0)
		check.toggled.connect(func(on: bool) -> void: _toggle_stat(part_index, stat_id, on))
		row.add_child(check)
		if StatRegistry.needs_value(stat_id):
			var spin: SpinBox = SpinBox.new()
			spin.min_value = 0
			spin.max_value = 100000
			spin.step = 1
			spin.value = float(current.get(stat_id, StatRegistry.default_value(stat_id)))
			spin.editable = current.has(stat_id)
			spin.value_changed.connect(func(v: float) -> void: _set_stat_value(part_index, stat_id, v))
			row.add_child(spin)
			_stat_controls["%d:%s" % [part_index, stat_id]] = spin


func _stats_dict_for(entity: Dictionary, part_index: int) -> Dictionary:
	if part_index < 0:
		return entity.get("stats", {}) as Dictionary
	var ps: Array = entity.get("part_stats", []) as Array
	if part_index < ps.size() and ps[part_index] is Dictionary:
		return ps[part_index] as Dictionary
	return {}


func _toggle_stat(part_index: int, stat_id: String, on: bool) -> void:
	var entity: Dictionary = _selected_entity()
	var stats: Dictionary = _stats_dict_for(entity, part_index).duplicate(true)
	if on:
		stats[stat_id] = StatRegistry.default_value(stat_id) if StatRegistry.needs_value(stat_id) else true
	else:
		stats.erase(stat_id)
	_write_stats(entity, part_index, stats)
	_commit(entity)
	# Re-render so the value box enables/disables and conflicts surface.
	_refresh_detail()


func _set_stat_value(part_index: int, stat_id: String, value: float) -> void:
	var entity: Dictionary = _selected_entity()
	var stats: Dictionary = _stats_dict_for(entity, part_index).duplicate(true)
	if not stats.has(stat_id):
		return
	stats[stat_id] = int(value)
	_write_stats(entity, part_index, stats)
	_commit(entity)


func _write_stats(entity: Dictionary, part_index: int, stats: Dictionary) -> void:
	if part_index < 0:
		entity["stats"] = stats
		return
	var ps: Array = (entity.get("part_stats", []) as Array).duplicate(true)
	while ps.size() <= part_index:
		ps.append({})
	ps[part_index] = stats
	entity["part_stats"] = ps


# --- Object-only extras (placement / extractable / yields) ------------------

func _build_object_extras(box: VBoxContainer, entity: Dictionary) -> void:
	var sep: HSeparator = HSeparator.new()
	box.add_child(sep)

	var place_row: HBoxContainer = HBoxContainer.new()
	place_row.add_theme_constant_override("separation", 6)
	box.add_child(place_row)
	var place_label: Label = Label.new()
	place_label.text = _loc.t("ui.modeditor.placement")
	place_row.add_child(place_label)
	var place_opt: OptionButton = OptionButton.new()
	var placements: Array = ["land", "sea", "both"]
	for p in placements:
		place_opt.add_item(_loc.t("ui.modeditor.placement_%s" % p))
	place_opt.selected = maxi(0, placements.find(str(entity.get("placement", "land"))))
	place_opt.item_selected.connect(func(idx: int) -> void:
		var e: Dictionary = _selected_entity()
		e["placement"] = placements[idx]
		_commit(e))
	place_row.add_child(place_opt)

	var extract_check: CheckBox = CheckBox.new()
	extract_check.text = _loc.t("ui.modeditor.extractable")
	extract_check.button_pressed = bool(entity.get("extractable", false))
	extract_check.toggled.connect(func(on: bool) -> void:
		var e: Dictionary = _selected_entity()
		e["extractable"] = on
		if on and not (e.get("yields", {}) as Dictionary).has("material"):
			e["yields"] = { "material": "resource_basic", "rate": 2 }
		_commit(e)
		_refresh_detail())
	box.add_child(extract_check)

	if bool(entity.get("extractable", false)):
		var yields: Dictionary = entity.get("yields", {}) as Dictionary
		var y_row: HBoxContainer = HBoxContainer.new()
		y_row.add_theme_constant_override("separation", 6)
		box.add_child(y_row)
		var mat_label: Label = Label.new()
		mat_label.text = _loc.t("ui.modeditor.yield_material")
		y_row.add_child(mat_label)
		var mat_edit: LineEdit = LineEdit.new()
		mat_edit.text = str(yields.get("material", "resource_basic"))
		mat_edit.custom_minimum_size = Vector2(160, 0)
		mat_edit.text_changed.connect(func(t: String) -> void:
			var e: Dictionary = _selected_entity()
			var yy: Dictionary = (e.get("yields", {}) as Dictionary).duplicate(true)
			yy["material"] = t.strip_edges()
			e["yields"] = yy
			_commit(e))
		y_row.add_child(mat_edit)
		var rate_label: Label = Label.new()
		rate_label.text = _loc.t("ui.modeditor.yield_rate")
		y_row.add_child(rate_label)
		var rate_spin: SpinBox = SpinBox.new()
		rate_spin.min_value = 1
		rate_spin.max_value = 1000
		rate_spin.value = float(yields.get("rate", 2))
		rate_spin.value_changed.connect(func(v: float) -> void:
			var e: Dictionary = _selected_entity()
			var yy: Dictionary = (e.get("yields", {}) as Dictionary).duplicate(true)
			yy["rate"] = int(v)
			e["yields"] = yy
			_commit(e))
		y_row.add_child(rate_spin)


# --- UPGRADE tab ------------------------------------------------------------

func _build_upgrade_tab(box: VBoxContainer, entity: Dictionary) -> void:
	var upgrade: Dictionary = entity.get("upgrade", {}) as Dictionary
	var enable: CheckBox = CheckBox.new()
	enable.text = _loc.t("ui.modeditor.upgrade.enable")
	enable.button_pressed = not upgrade.is_empty()
	enable.toggled.connect(func(on: bool) -> void:
		var e: Dictionary = _selected_entity()
		if on:
			e["upgrade"] = ModProject.default_unit_upgrade("kill_count", 50)
		else:
			e.erase("upgrade")
		_commit(e)
		_refresh_detail())
	box.add_child(enable)

	if upgrade.is_empty():
		return

	var trigger: Dictionary = upgrade.get("trigger", {}) as Dictionary
	var t_row: HBoxContainer = HBoxContainer.new()
	t_row.add_theme_constant_override("separation", 6)
	box.add_child(t_row)
	var t_label: Label = Label.new()
	t_label.text = _loc.t("ui.modeditor.upgrade.trigger")
	t_row.add_child(t_label)
	var t_opt: OptionButton = OptionButton.new()
	var triggers: Array = ["kill_count", "time_ticks", "tech_node"]
	for tg in triggers:
		t_opt.add_item(_loc.t("ui.modeditor.upgrade.trigger_%s" % tg))
	t_opt.selected = maxi(0, triggers.find(str(trigger.get("type", "kill_count"))))
	t_opt.item_selected.connect(func(idx: int) -> void:
		var e: Dictionary = _selected_entity()
		var up: Dictionary = (e.get("upgrade", {}) as Dictionary).duplicate(true)
		var tr: Dictionary = (up.get("trigger", {}) as Dictionary).duplicate(true)
		tr["type"] = triggers[idx]
		up["trigger"] = tr
		e["upgrade"] = up
		_commit(e))
	t_row.add_child(t_opt)

	var v_row: HBoxContainer = HBoxContainer.new()
	v_row.add_theme_constant_override("separation", 6)
	box.add_child(v_row)
	var v_label: Label = Label.new()
	v_label.text = _loc.t("ui.modeditor.upgrade.value")
	v_row.add_child(v_label)
	var v_spin: SpinBox = SpinBox.new()
	v_spin.min_value = 0
	v_spin.max_value = 100000
	v_spin.value = float(trigger.get("value", 50))
	v_spin.value_changed.connect(func(v: float) -> void:
		var e: Dictionary = _selected_entity()
		var up: Dictionary = (e.get("upgrade", {}) as Dictionary).duplicate(true)
		var tr: Dictionary = (up.get("trigger", {}) as Dictionary).duplicate(true)
		tr["value"] = int(v)
		up["trigger"] = tr
		e["upgrade"] = up
		_commit(e))
	v_row.add_child(v_spin)

	var cap_note: Label = Label.new()
	cap_note.text = _loc.t("ui.modeditor.upgrade.cap_note")
	cap_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cap_note.add_theme_font_size_override("font_size", 11)
	cap_note.modulate = Color(0.7, 0.7, 0.7)
	box.add_child(cap_note)


# --- TRAINING / BUILD-TECH tab ----------------------------------------------

func _build_training_tab(box: VBoxContainer, entity: Dictionary) -> void:
	var buildable: Dictionary = entity.get("buildable", {}) as Dictionary
	if buildable.is_empty():
		buildable = ModProject.default_buildable("")

	# from_building: dropdown of already-defined buildings (no free text, R8.2).
	var b_row: HBoxContainer = HBoxContainer.new()
	b_row.add_theme_constant_override("separation", 6)
	box.add_child(b_row)
	var b_label: Label = Label.new()
	b_label.text = _loc.t("ui.modeditor.train.from_building")
	b_row.add_child(b_label)
	var b_opt: OptionButton = OptionButton.new()
	b_opt.add_item(_loc.t("ui.modeditor.train.none"))
	var building_ids: Array = _project.buildings.keys()
	building_ids.sort()
	for bid in building_ids:
		b_opt.add_item(str(bid))
	var cur_building: String = str(buildable.get("from_building", ""))
	var found: int = building_ids.find(cur_building)
	b_opt.selected = found + 1 if found >= 0 else 0
	b_opt.item_selected.connect(func(idx: int) -> void:
		var e: Dictionary = _selected_entity()
		var bl: Dictionary = (e.get("buildable", {}) as Dictionary).duplicate(true)
		bl["from_building"] = "" if idx == 0 else str(building_ids[idx - 1])
		e["buildable"] = bl
		_commit(e))
	b_row.add_child(b_opt)

	# cost (single resource for simplicity).
	var c_row: HBoxContainer = HBoxContainer.new()
	c_row.add_theme_constant_override("separation", 6)
	box.add_child(c_row)
	var c_label: Label = Label.new()
	c_label.text = _loc.t("ui.modeditor.train.cost")
	c_row.add_child(c_label)
	var c_spin: SpinBox = SpinBox.new()
	c_spin.min_value = 0
	c_spin.max_value = 100000
	c_spin.value = float((buildable.get("cost", {}) as Dictionary).get("resource_basic", 50))
	c_spin.value_changed.connect(func(v: float) -> void:
		var e: Dictionary = _selected_entity()
		var bl: Dictionary = (e.get("buildable", {}) as Dictionary).duplicate(true)
		bl["cost"] = { "resource_basic": int(v) }
		e["buildable"] = bl
		_commit(e))
	c_row.add_child(c_spin)

	# required_tech: dropdown of defined tech nodes (or none).
	var tech_row: HBoxContainer = HBoxContainer.new()
	tech_row.add_theme_constant_override("separation", 6)
	box.add_child(tech_row)
	var tech_label: Label = Label.new()
	tech_label.text = _loc.t("ui.modeditor.train.required_tech")
	tech_row.add_child(tech_label)
	var tech_opt: OptionButton = OptionButton.new()
	tech_opt.add_item(_loc.t("ui.modeditor.train.none"))
	var tech_ids: Array = _project.tech.keys()
	tech_ids.sort()
	for tid in tech_ids:
		tech_opt.add_item(str(tid))
	var cur_tech: String = str(buildable.get("required_tech", ""))
	var tfound: int = tech_ids.find(cur_tech)
	tech_opt.selected = tfound + 1 if tfound >= 0 else 0
	tech_opt.item_selected.connect(func(idx: int) -> void:
		var e: Dictionary = _selected_entity()
		var bl: Dictionary = (e.get("buildable", {}) as Dictionary).duplicate(true)
		bl["required_tech"] = "" if idx == 0 else str(tech_ids[idx - 1])
		e["buildable"] = bl
		_commit(e))
	tech_row.add_child(tech_opt)

	# Ensure the buildable block is stored even before the user changes anything.
	if not entity.has("buildable"):
		var e: Dictionary = _selected_entity()
		e["buildable"] = buildable
		_commit(e)


# --- Image upload -----------------------------------------------------------

func _on_image_selected(path: String) -> void:
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		_set_status(_loc.t("ui.modeditor.status.save_failed"))
		return
	var problems: Array = []
	var base_name: String = _project.unique_texture_name(path.get_file())
	var entry: String = _project.add_texture_validated(base_name, bytes, problems)
	if entry == "":
		_set_status("%s: %s" % [_loc.t("ui.modeditor.status.invalid"), str(problems[0]) if not problems.is_empty() else "?"])
		return
	# Point the target part's texture at the stored entry + adopt its px size.
	var entity: Dictionary = _selected_entity()
	var graphic: Dictionary = (entity.get("graphic", {}) as Dictionary).duplicate(true)
	var parts: Array = (graphic.get("parts", []) as Array).duplicate(true)
	if _upload_part_index < parts.size():
		var part: Dictionary = (parts[_upload_part_index] as Dictionary).duplicate(true)
		part["texture"] = entry
		var dims: Vector2i = GraphicModel.png_dimensions(bytes)
		if dims.x > 0 and dims.y > 0:
			part["px"] = { "w": clampi(dims.x, GraphicModel.MIN_PX, GraphicModel.MAX_PX), "h": clampi(dims.y, GraphicModel.MIN_PX, GraphicModel.MAX_PX) }
		parts[_upload_part_index] = part
		graphic["parts"] = parts
		entity["graphic"] = graphic
		_commit(entity)
	_set_status(_loc.t("ui.modeditor.status.image_added"))
	_refresh_detail()


# --- Project lifecycle ------------------------------------------------------

func _on_new() -> void:
	_project.new_project("new_mod", "New Mod")
	_selected_id = ""
	_set_status(_loc.t("ui.modeditor.status.new"))
	_refresh_all()


func _on_save() -> void:
	var problems: Array = _project.validate()
	if not problems.is_empty():
		_set_status("%s: %s" % [_loc.t("ui.modeditor.status.invalid"), str(problems[0])])
		return
	var out_path: String = _storage.resolve_pack(_project.get_id())
	if _project.save_pack(out_path):
		_set_status("%s %s" % [_loc.t("ui.modeditor.status.saved"), out_path])
	else:
		_set_status(_loc.t("ui.modeditor.status.save_failed"))


func _on_back() -> void:
	if _has_tree():
		get_tree().change_scene_to_file(MAIN_MENU_SCENE)


# --- Rendering --------------------------------------------------------------

func _refresh_all() -> void:
	_mod_id_edit.text = _project.get_id()
	_mod_name_edit.text = str(_project.manifest.get("name", ""))
	_refresh_tree()
	_refresh_detail()
	_refresh_labels()


func _refresh_labels() -> void:
	_title.text = _loc.t("ui.modeditor.title")
	_mod_id_edit.placeholder_text = _loc.t("ui.modeditor.mod_id")
	_mod_name_edit.placeholder_text = _loc.t("ui.modeditor.mod_name")
	_tab_buttons[ModProject.UNITS_CATALOG].text = _loc.t("ui.modeditor.tab.units")
	_tab_buttons[ModProject.BUILDINGS_CATALOG].text = _loc.t("ui.modeditor.tab.buildings")
	_tab_buttons[ModProject.OBJECTS_CATALOG].text = _loc.t("ui.modeditor.tab.objects")
	# Highlight the active catalog tab by disabling its button.
	for catalog in _tab_buttons.keys():
		(_tab_buttons[catalog] as Button).disabled = (catalog == _active_catalog)


func _set_status(text: String) -> void:
	_status_label.text = text


# --- Helpers ----------------------------------------------------------------

func _world_state() -> WorldState:
	var nexus: Node = get_node_or_null("/root/Nexus")
	if nexus != null and nexus.get("world_state") != null:
		return nexus.world_state
	return null


func _has_tree() -> bool:
	return is_inside_tree() and get_tree() != null
