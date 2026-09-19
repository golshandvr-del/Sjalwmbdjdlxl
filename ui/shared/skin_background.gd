# skin_background.gd
# ----------------------------------------------------------------------------
# Project Nexus - Skinnable screen BACKGROUND (GUI overhaul).
#
# Drop-in replacement for the flat ColorRect every screen used to carry. It
# asks UiSkinService for the background spec of its screen (derived from the
# owning scene's file name, or `screen_id` when set explicitly) and draws:
#
#   1. a vertical gradient (top -> bottom palette colours)      [always]
#   2. the skin image, if the art file exists (cover-fit, centred)  [optional]
#   3. a faint tactical grid                                     [optional]
#   4. an overlay texture (e.g. scanlines / noise)               [optional]
#   5. a vignette (darkened edges) for focus on the centre        [optional]
#
# Everything is data-driven from the skin JSON so a mod can restyle every
# screen (or one screen) without touching code. Fully procedural when no art
# has shipped, so the game never looks broken.
#
# CODE LANGUAGE POLICY: English-only identifiers/comments (ASCII).
# ----------------------------------------------------------------------------
class_name SkinBackground
extends Control

# Explicit screen id; when empty the owner scene's file stem is used.
@export var screen_id: String = ""

var _spec: Dictionary = {}
var _image: Texture2D = null
var _overlay: Texture2D = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_resolve()
	resized.connect(queue_redraw)


func _resolve() -> void:
	var id: String = screen_id
	if id == "":
		var owner_node: Node = owner if owner != null else get_parent()
		if owner_node != null and owner_node.scene_file_path != "":
			id = UiSkinUtil.screen_id_for(owner_node.scene_file_path)
	var svc: UiSkinService = UiSkinService.current()
	_spec = svc.background_for(id)
	_image = svc.image(str(_spec.get("image", "")))
	_overlay = svc.image(str(_spec.get("overlay", "")))
	queue_redraw()


func _draw() -> void:
	var rect: Rect2 = Rect2(Vector2.ZERO, size)
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return
	var top: Color = UiSkinUtil.color(_spec.get("top", ""), Color("#141a26"))
	var bottom: Color = UiSkinUtil.color(_spec.get("bottom", ""), Color("#090c12"))
	# 1) Gradient (two triangles via draw_polygon with per-vertex colours).
	var pts: PackedVector2Array = PackedVector2Array([
		rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)])
	var cols: PackedColorArray = PackedColorArray([top, top, bottom, bottom])
	draw_polygon(pts, cols)
	# 2) Skin image (cover fit).
	if _image != null:
		var tex_size: Vector2 = _image.get_size()
		if tex_size.x > 0.0 and tex_size.y > 0.0:
			var scale: float = maxf(rect.size.x / tex_size.x, rect.size.y / tex_size.y)
			var draw_size: Vector2 = tex_size * scale
			var pos: Vector2 = (rect.size - draw_size) * 0.5
			draw_texture_rect(_image, Rect2(pos, draw_size), false)
	# 3) Tactical grid.
	var grid: int = UiSkinUtil.int_of(_spec, "grid", 48, 0, 512)
	var grid_alpha: float = UiSkinUtil.float_of(_spec, "grid_alpha", 0.06)
	if grid > 0 and grid_alpha > 0.0:
		var line: Color = Color(1, 1, 1, grid_alpha)
		var x: float = 0.0
		while x <= rect.size.x:
			draw_line(Vector2(x, 0), Vector2(x, rect.size.y), line, 1.0)
			x += float(grid)
		var y: float = 0.0
		while y <= rect.size.y:
			draw_line(Vector2(0, y), Vector2(rect.size.x, y), line, 1.0)
			y += float(grid)
	# 4) Overlay texture (tiled).
	if _overlay != null:
		draw_texture_rect(_overlay, rect, true)
	# 5) Vignette: four soft edge bands.
	var vignette: float = UiSkinUtil.float_of(_spec, "vignette", 0.55)
	if vignette > 0.0:
		var band: float = minf(rect.size.x, rect.size.y) * 0.35
		var dark: Color = Color(0, 0, 0, vignette)
		var clear: Color = Color(0, 0, 0, 0)
		# Left
		draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(band, 0), Vector2(band, rect.size.y), Vector2(0, rect.size.y)]),
			PackedColorArray([dark, clear, clear, dark]))
		# Right
		draw_polygon(PackedVector2Array([Vector2(rect.size.x - band, 0), Vector2(rect.size.x, 0), rect.size, Vector2(rect.size.x - band, rect.size.y)]),
			PackedColorArray([clear, dark, dark, clear]))
		# Top
		draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(rect.size.x, 0), Vector2(rect.size.x, band), Vector2(0, band)]),
			PackedColorArray([dark, dark, clear, clear]))
		# Bottom
		draw_polygon(PackedVector2Array([Vector2(0, rect.size.y - band), Vector2(rect.size.x, rect.size.y - band), rect.size, Vector2(0, rect.size.y)]),
			PackedColorArray([clear, clear, dark, dark]))
