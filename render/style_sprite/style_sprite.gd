# style_sprite.gd
# ----------------------------------------------------------------------------
# Project Nexus - Sprite (texture-driven) Render Style (Phase B, step B.4).
#
# The third drawing strategy behind the RenderAdapter. It honours the IDENTICAL
# duck-typed interface as StyleSimple / StyleDetailed (draw_tile / draw_building
# / draw_unit / owner_color) but, instead of flat shapes, it reads each entity's
# DATA-DRIVEN `visual` block and draws a TEXTURE -- the core of the "play-dough"
# idea: change a unit's look entirely from JSON, no code.
#
# A `visual` block (resolved by the RenderAdapter from the catalog) looks like:
#   { "shape": "circle|square|sprite", "color": "#4CB0F2",
#     "texture": "textures/soldier.png", "size_scale": 1.0, "outline": true }
#
# Resolution rules (all pure presentation, never touches the simulation):
#   - If a texture is present AND resolves to a real image -> draw the texture.
#   - Otherwise fall back to the `shape` + `color` (so a brand-new modded unit
#     with no art still shows up sensibly).
#   - `color` doubles as a modulate tint for the texture and as the fill color
#     for the shape fallback; an empty/invalid color falls back to owner color.
#
# Textures are fetched through a shared TextureService (lazy + cached), assigned
# by the RenderAdapter before first draw.
#
# CODE LANGUAGE POLICY: English-only identifiers/comments.
# ----------------------------------------------------------------------------
class_name StyleSprite
extends RefCounted

# Terrain palette (mirrors StyleSimple so the ground reads the same).
const COLOR_GROUND: Color = Color(0.16, 0.20, 0.16, 1.0)
const COLOR_WALL: Color = Color(0.32, 0.30, 0.28, 1.0)
const COLOR_WATER: Color = Color(0.12, 0.22, 0.38, 1.0)
const COLOR_GRID: Color = Color(0.0, 0.0, 0.0, 0.18)

const OWNER_COLORS: Array = [
	Color(0.30, 0.70, 0.95, 1.0),
	Color(0.92, 0.36, 0.32, 1.0),
	Color(0.46, 0.80, 0.38, 1.0),
	Color(0.88, 0.78, 0.30, 1.0),
]

const COLOR_SELECT: Color = Color(1.0, 1.0, 1.0, 1.0)
const COLOR_HEALTH_BG: Color = Color(0.0, 0.0, 0.0, 0.6)
const COLOR_HEALTH_FG: Color = Color(0.40, 0.85, 0.40, 1.0)

# Injected by the RenderAdapter (Phase B.2). May be null in pure-shape tests.
var texture_service: Object = null


func owner_color(owner: int) -> Color:
	if owner < 0:
		return Color(0.6, 0.6, 0.6, 1.0)
	return OWNER_COLORS[owner % OWNER_COLORS.size()]


# --- Tiles ------------------------------------------------------------------

func draw_tile(canvas, rect: Rect2, terrain_id: int) -> void:
	var color: Color = COLOR_GROUND
	match terrain_id:
		1:
			color = COLOR_WALL
		2:
			color = COLOR_WATER
		_:
			color = COLOR_GROUND
	canvas.draw_rect(rect, color, true)
	canvas.draw_rect(rect, COLOR_GRID, false, 1.0)


# --- Buildings --------------------------------------------------------------

func draw_building(canvas, rect: Rect2, building: Dictionary) -> void:
	var owner: int = int(building.get("owner", 0))
	var visual: Dictionary = building.get("visual", {})
	if not _draw_visual(canvas, rect, visual, owner, 0.9):
		# Shape fallback: a colored inset square.
		var inset: Vector2 = rect.size * 0.08
		var body: Rect2 = Rect2(rect.position + inset, rect.size - inset * 2.0)
		canvas.draw_rect(body, _fill_color(visual, owner), true)
		canvas.draw_rect(body, Color(0, 0, 0, 0.5), false, 2.0)
	_draw_health_bar(canvas, rect, building)


# --- Units ------------------------------------------------------------------

func draw_unit(canvas, rect: Rect2, unit: Dictionary, is_selected: bool) -> void:
	var owner: int = int(unit.get("owner", 0))
	var visual: Dictionary = unit.get("visual", {})
	var center: Vector2 = rect.position + rect.size * 0.5
	var radius: float = rect.size.x * 0.42
	if is_selected:
		canvas.draw_circle(center, radius + 4.0, COLOR_SELECT)
	if not _draw_visual(canvas, rect, visual, owner, 1.0):
		# Shape fallback honouring the requested shape, else a circle.
		var shape: String = str(visual.get("shape", "circle"))
		canvas.draw_circle(center, radius + 1.5, Color(0, 0, 0, 0.65))
		if shape == "square":
			var s: float = radius * 1.6
			canvas.draw_rect(Rect2(center - Vector2(s, s) * 0.5, Vector2(s, s)), _fill_color(visual, owner), true)
		else:
			canvas.draw_circle(center, radius, _fill_color(visual, owner))
	_draw_health_bar(canvas, rect, unit)


# --- Visual resolution ------------------------------------------------------

# Try to draw the texture named in `visual`. Returns true if a real texture was
# drawn, false if the caller should fall back to a shape.
func _draw_visual(canvas, rect: Rect2, visual: Dictionary, owner: int, fill: float) -> bool:
	if texture_service == null or visual.is_empty():
		return false
	var tex_path: String = str(visual.get("texture", ""))
	if tex_path == "":
		return false
	if not texture_service.has_texture(tex_path):
		return false
	var tex: Texture2D = texture_service.get_texture(tex_path)
	if tex == null:
		return false
	var scale: float = float(visual.get("size_scale", 1.0))
	var draw_size: Vector2 = rect.size * fill * scale
	var pos: Vector2 = rect.position + (rect.size - draw_size) * 0.5
	var tint: Color = _tint_color(visual, owner)
	canvas.draw_texture_rect(tex, Rect2(pos, draw_size), false, tint)
	return true


# The fill/tint color: explicit `visual.color` if valid, else the owner color.
func _fill_color(visual: Dictionary, owner: int) -> Color:
	var raw: String = str(visual.get("color", ""))
	if raw != "" and Color.html_is_valid(raw):
		return Color.html(raw)
	return owner_color(owner)


# A texture tint that blends the visual color toward white so the art keeps its
# detail but still carries a hint of faction/color identity.
func _tint_color(visual: Dictionary, owner: int) -> Color:
	var base: Color = _fill_color(visual, owner)
	return base.lerp(Color.WHITE, 0.55)


# --- Shared health bar ------------------------------------------------------

func _draw_health_bar(canvas, rect: Rect2, entity: Dictionary) -> void:
	var max_health: int = int(entity.get("max_health", 0))
	if max_health <= 0:
		return
	var health: int = clampi(int(entity.get("health", 0)), 0, max_health)
	var ratio: float = float(health) / float(max_health)
	if ratio >= 1.0:
		return
	var bar_w: float = rect.size.x * 0.8
	var bar_h: float = max(2.0, rect.size.y * 0.10)
	var bar_pos: Vector2 = rect.position + Vector2(rect.size.x * 0.1, -bar_h - 2.0)
	canvas.draw_rect(Rect2(bar_pos, Vector2(bar_w, bar_h)), COLOR_HEALTH_BG, true)
	canvas.draw_rect(Rect2(bar_pos, Vector2(bar_w * ratio, bar_h)), COLOR_HEALTH_FG, true)
