# ui_skin_service.gd
# ----------------------------------------------------------------------------
# Project Nexus - UI Skin Service (GUI overhaul, engine-facing half).
#
# Resolves the active skin (base data/ui_skin/skin.json + every active mod's
# ui_skin/skin.json, merged by UiSkinUtil), builds a Godot Theme from its
# palette and applies it to the SceneTree root so EVERY screen picks it up
# without per-scene wiring. Also hands out background specs + textures for
# SkinBackground nodes.
#
# Process-wide singleton reached via `UiSkinService.current()` (lazy).
# Cosmetic only: never reads or writes WorldState gameplay sections.
#
# CODE LANGUAGE POLICY: English-only identifiers/comments (ASCII).
# ----------------------------------------------------------------------------
class_name UiSkinService
extends RefCounted

const BASE_SKIN_PATH: String = "res://data/ui_skin/skin.json"
const MOD_SKIN_REL: String = "ui_skin/skin.json"
const MODS_DIR: String = "res://mods"
const FONT_PATH: String = "res://assets/fonts/Vazirmatn-Regular.ttf"

static var _instance: UiSkinService = null

var skin: Dictionary = {}
var theme: Theme = null
var texture_service: TextureService = TextureService.new()


# The process-wide service (created on first use). `reload()` rebuilds it.
static func current() -> UiSkinService:
	if _instance == null:
		_instance = UiSkinService.new()
		_instance.reload()
	return _instance


# Rebuild the skin from disk: base file + active mods (settings.active_mods).
func reload() -> void:
	var layers: Array = []
	var base: Variant = _read_json(BASE_SKIN_PATH)
	if base is Dictionary:
		layers.append(base)
	texture_service.clear()
	for mod_dir in _active_mod_dirs():
		var raw: Variant = _read_json(str(mod_dir).path_join(MOD_SKIN_REL))
		if raw is Dictionary:
			layers.append(raw)
		# The mod root is also a texture root so "textures/ui/x.png" resolves
		# from the mod before the base game.
		texture_service.add_root(str(mod_dir))
	skin = UiSkinUtil.resolve(layers)
	theme = build_theme(skin)


# Apply the built Theme project-wide (root Window theme). Idempotent.
func apply_to_tree(tree: SceneTree) -> void:
	if tree == null or theme == null:
		return
	tree.root.theme = theme


# Resolve a skin-relative image path ("textures/ui/bg.png") to a texture, or
# null when the art has not shipped yet (callers fall back to procedural).
func image(rel_path: String) -> Texture2D:
	if rel_path == "" or not texture_service.has_texture(rel_path):
		return null
	return texture_service.get_texture(rel_path)


func background_for(screen_id: String) -> Dictionary:
	return UiSkinUtil.background_for(skin, screen_id)


func palette(name: String, fallback: Color = Color.MAGENTA) -> Color:
	return UiSkinUtil.palette_color(skin, name, fallback)


# --- Theme construction -----------------------------------------------------

# Build a complete flat Theme from the skin palette. Every control the game
# uses gets a consistent look (buttons, panels, popups, fields, tabs, lists,
# scrollbars, sliders, option buttons, tooltips).
static func build_theme(s: Dictionary) -> Theme:
	var t: Theme = Theme.new()
	var btn: Dictionary = s.get("button", {})
	var pnl: Dictionary = s.get("panel", {})
	var radius: int = UiSkinUtil.int_of(btn, "corner_radius", 6, 0, 64)
	var border: int = UiSkinUtil.int_of(btn, "border_width", 1, 0, 8)
	var min_h: int = UiSkinUtil.int_of(btn, "min_height", 44, 24, 200)
	var font_size: int = UiSkinUtil.int_of(btn, "font_size", 16, 8, 64)
	var p_radius: int = UiSkinUtil.int_of(pnl, "corner_radius", 10, 0, 64)
	var p_border: int = UiSkinUtil.int_of(pnl, "border_width", 1, 0, 8)

	var accent: Color = UiSkinUtil.palette_color(s, "accent", Color("#3d6fb4"))
	var hover: Color = UiSkinUtil.palette_color(s, "accent_hover", Color("#4d84d4"))
	var pressed: Color = UiSkinUtil.palette_color(s, "accent_pressed", Color("#2c5290"))
	var disabled: Color = UiSkinUtil.palette_color(s, "accent_disabled", Color("#2a3140"))
	var panel: Color = UiSkinUtil.palette_color(s, "panel", Color("#161c27"))
	var panel_border: Color = UiSkinUtil.palette_color(s, "panel_border", Color("#2a3446"))
	var text: Color = UiSkinUtil.palette_color(s, "text", Color("#e0e8f2"))
	var text_dim: Color = UiSkinUtil.palette_color(s, "text_dim", Color("#9aa7ba"))
	var field: Color = UiSkinUtil.palette_color(s, "field", Color("#0b0f16"))

	if ResourceLoader.exists(FONT_PATH):
		var font: Variant = load(FONT_PATH)
		if font is Font:
			t.default_font = font
	t.default_font_size = font_size

	# Buttons (Button / OptionButton / CheckButton share the same boxes).
	for cls in ["Button", "OptionButton", "MenuButton", "CheckButton", "CheckBox"]:
		t.set_stylebox("normal", cls, _box(accent, accent.lightened(0.12), radius, border, 12, 8))
		t.set_stylebox("hover", cls, _box(hover, hover.lightened(0.15), radius, border, 12, 8))
		t.set_stylebox("pressed", cls, _box(pressed, pressed.lightened(0.1), radius, border, 12, 8))
		t.set_stylebox("focus", cls, _outline(hover.lightened(0.3), radius, 2))
		t.set_stylebox("disabled", cls, _box(disabled, disabled.lightened(0.05), radius, border, 12, 8))
		t.set_color("font_color", cls, text)
		t.set_color("font_hover_color", cls, Color.WHITE)
		t.set_color("font_pressed_color", cls, text)
		t.set_color("font_focus_color", cls, Color.WHITE)
		t.set_color("font_disabled_color", cls, text_dim.darkened(0.2))
		t.set_color("icon_normal_color", cls, text)
		t.set_color("icon_hover_color", cls, Color.WHITE)
		t.set_color("icon_pressed_color", cls, text)
		t.set_color("icon_disabled_color", cls, text_dim.darkened(0.2))
		t.set_constant("h_separation", cls, 8)

	# Panels and popups.
	t.set_stylebox("panel", "PanelContainer", _box(panel, panel_border, p_radius, p_border, 12, 12))
	t.set_stylebox("panel", "Panel", _box(panel, panel_border, p_radius, p_border, 12, 12))
	t.set_stylebox("panel", "PopupPanel", _box(panel.lightened(0.03), panel_border, p_radius, p_border, 14, 14))
	t.set_stylebox("panel", "PopupMenu", _box(panel.lightened(0.03), panel_border, p_radius, p_border, 6, 6))
	t.set_stylebox("hover", "PopupMenu", _box(hover, hover, 4, 0, 6, 4))
	t.set_color("font_color", "PopupMenu", text)
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	t.set_stylebox("panel", "AcceptDialog", _box(panel, panel_border, p_radius, p_border, 14, 14))
	t.set_stylebox("panel", "TooltipPanel", _box(field, panel_border, 4, 1, 8, 6))
	t.set_color("font_color", "TooltipLabel", text)

	# Text fields.
	for cls in ["LineEdit", "TextEdit", "SpinBox"]:
		t.set_stylebox("normal", cls, _box(field, panel_border, radius, 1, 10, 8))
		t.set_stylebox("focus", cls, _box(field, hover, radius, 2, 10, 8))
		t.set_stylebox("read_only", cls, _box(field.lightened(0.02), panel_border, radius, 1, 10, 8))
		t.set_color("font_color", cls, text)
		t.set_color("font_placeholder_color", cls, text_dim.darkened(0.15))
		t.set_color("caret_color", cls, hover)
		t.set_color("selection_color", cls, accent.darkened(0.2))

	# Labels.
	t.set_color("font_color", "Label", text)

	# Tabs.
	t.set_stylebox("tab_selected", "TabContainer", _box(panel.lightened(0.08), hover, radius, 1, 12, 8))
	t.set_stylebox("tab_unselected", "TabContainer", _box(field, panel_border, radius, 1, 12, 8))
	t.set_stylebox("tab_hovered", "TabContainer", _box(panel.lightened(0.05), panel_border, radius, 1, 12, 8))
	t.set_stylebox("panel", "TabContainer", _box(panel, panel_border, p_radius, p_border, 8, 8))
	t.set_color("font_selected_color", "TabContainer", Color.WHITE)
	t.set_color("font_unselected_color", "TabContainer", text_dim)
	t.set_color("font_hovered_color", "TabContainer", text)

	# Lists / trees.
	t.set_stylebox("panel", "ItemList", _box(field, panel_border, radius, 1, 6, 6))
	t.set_stylebox("selected", "ItemList", _box(accent.darkened(0.15), accent, 4, 0, 4, 2))
	t.set_stylebox("selected_focus", "ItemList", _box(accent.darkened(0.1), hover, 4, 1, 4, 2))
	t.set_stylebox("hovered", "ItemList", _box(panel.lightened(0.06), panel.lightened(0.06), 4, 0, 4, 2))
	t.set_color("font_color", "ItemList", text)
	t.set_color("font_selected_color", "ItemList", Color.WHITE)
	t.set_stylebox("panel", "Tree", _box(field, panel_border, radius, 1, 6, 6))
	t.set_color("font_color", "Tree", text)

	# Scroll bars / sliders.
	for cls in ["HScrollBar", "VScrollBar"]:
		t.set_stylebox("scroll", cls, _box(Color(0, 0, 0, 0.25), Color(0, 0, 0, 0), 4, 0, 0, 0))
		t.set_stylebox("grabber", cls, _box(panel_border.lightened(0.2), panel_border, 4, 0, 0, 0))
		t.set_stylebox("grabber_highlight", cls, _box(hover, hover, 4, 0, 0, 0))
		t.set_stylebox("grabber_pressed", cls, _box(pressed, pressed, 4, 0, 0, 0))
	for cls in ["HSlider", "VSlider"]:
		t.set_stylebox("slider", cls, _box(field, panel_border, 4, 1, 0, 0))
		t.set_stylebox("grabber_area", cls, _box(accent, accent, 4, 0, 0, 0))
		t.set_stylebox("grabber_area_highlight", cls, _box(hover, hover, 4, 0, 0, 0))

	# Progress bars.
	t.set_stylebox("background", "ProgressBar", _box(field, panel_border, 4, 1, 2, 2))
	t.set_stylebox("fill", "ProgressBar", _box(accent, accent, 4, 0, 0, 0))

	# Reach the minimum tap-target height through the button's content margins.
	var normal_box: StyleBox = t.get_stylebox("normal", "Button")
	if normal_box is StyleBoxFlat:
		var needed: float = float(min_h) - float(font_size) - 8.0
		if needed > 0.0:
			(normal_box as StyleBoxFlat).content_margin_top = maxf(8.0, needed * 0.5)
			(normal_box as StyleBoxFlat).content_margin_bottom = maxf(8.0, needed * 0.5)
	return t


static func _box(bg: Color, border_color: Color, radius: int, border: int, mx: float, my: float) -> StyleBoxFlat:
	var b: StyleBoxFlat = StyleBoxFlat.new()
	b.bg_color = bg
	b.border_color = border_color
	b.set_border_width_all(border)
	b.set_corner_radius_all(radius)
	b.content_margin_left = mx
	b.content_margin_right = mx
	b.content_margin_top = my
	b.content_margin_bottom = my
	b.anti_aliasing = true
	return b


static func _outline(color: Color, radius: int, width: int) -> StyleBoxFlat:
	var b: StyleBoxFlat = StyleBoxFlat.new()
	b.bg_color = Color(0, 0, 0, 0)
	b.border_color = color
	b.set_border_width_all(width)
	b.set_corner_radius_all(radius)
	b.draw_center = false
	return b


# --- Internals --------------------------------------------------------------

func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var text: String = FileAccess.get_file_as_string(path)
	return JSON.parse_string(text)


# Directories of the ACTIVE mods in a stable order (settings.active_mods
# order; falls back to every discovered mod sorted by id when no preference
# exists). Mods that are disabled never contribute skin layers.
func _active_mod_dirs() -> Array:
	var settings: GameSettings = GameSettings.new(null)
	settings.load_from_file()
	var loader: DataLoader = DataLoader.new()
	var discovered: Array = ModLoader.discover_mods(loader, MODS_DIR)
	var by_id: Dictionary = {}
	for manifest in discovered:
		var m: Dictionary = manifest
		by_id[str(m.get("id", ""))] = str(m.get("_dir", ""))
	var active: Array = settings.get_active_mods()
	if active.is_empty():
		active = by_id.keys()
		active.sort()
	var out: Array = []
	for id in active:
		var dir: String = str(by_id.get(str(id), ""))
		if dir != "":
			out.append(dir)
	return out
