# style_detailed.gd
# ----------------------------------------------------------------------------
# Project Nexus - Detailed Render Style (Phase 4, step 4.1).
#
# A richer "MOWAS-style" renderer that draws the SAME world the StyleSimple
# renderer draws, but with more visual fidelity: textured-looking terrain with
# subtle per-tile shading, structures with rooftops / outlines / a small flag,
# units drawn as directional bodies with a facing marker, a turret/barrel, a
# drop shadow, a veterancy rank pip, and slimmer health bars.
#
# CRITICAL DESIGN CONSTRAINT (Logic/Render Separation, Design Philosophy #5):
#   This style implements the EXACT SAME duck-typed interface as StyleSimple --
#       draw_tile(canvas, rect, terrain_id)
#       draw_building(canvas, rect, building_dict)
#       draw_unit(canvas, rect, unit_dict, is_selected)
#   so the RenderAdapter can swap between StyleSimple and StyleDetailed at
#   runtime with ZERO changes to any game logic. The simulation is unaware that
#   the look changed; the style reads nothing from the world itself -- the
#   adapter passes it already-resolved data + pixel rects.
#
# Determinism note: the renderer is purely cosmetic and never feeds anything
# back into the simulation, so any incidental randomness here (there is none --
# all variation is derived from stable tile coordinates / entity ids) cannot
# affect lockstep. We deliberately derive every "random-looking" detail from the
# integer coordinates / ids so the picture is stable frame to frame.
#
# CODE LANGUAGE POLICY: English-only identifiers/comments.
# ----------------------------------------------------------------------------
class_name StyleDetailed
extends RefCounted

# Terrain base palette (matches MapModule TERRAIN_* ids). Detailed style adds a
# second, slightly shifted shade per tile for a subtle textured appearance.
const COLOR_GROUND_A: Color = Color(0.18, 0.24, 0.18, 1.0)
const COLOR_GROUND_B: Color = Color(0.14, 0.19, 0.14, 1.0)
const COLOR_WALL_A: Color = Color(0.38, 0.36, 0.33, 1.0)
const COLOR_WALL_B: Color = Color(0.27, 0.25, 0.23, 1.0)
const COLOR_WATER_A: Color = Color(0.13, 0.26, 0.44, 1.0)
const COLOR_WATER_B: Color = Color(0.10, 0.20, 0.36, 1.0)
const COLOR_GRID: Color = Color(0.0, 0.0, 0.0, 0.10)

# Owner colors (0 = local player, 1 = enemy, others cycle). Brighter than the
# simple style and complemented by a darker shade used for outlines/rooftops.
const OWNER_COLORS: Array = [
	Color(0.34, 0.74, 0.98, 1.0),  # player 0 - blue
	Color(0.95, 0.40, 0.34, 1.0),  # player 1 - red
	Color(0.50, 0.86, 0.42, 1.0),  # player 2 - green
	Color(0.92, 0.82, 0.34, 1.0),  # player 3 - yellow
]

const COLOR_SELECT: Color = Color(1.0, 1.0, 1.0, 1.0)
const COLOR_SHADOW: Color = Color(0.0, 0.0, 0.0, 0.30)
const COLOR_HEALTH_BG: Color = Color(0.0, 0.0, 0.0, 0.65)
const COLOR_HEALTH_FG_HIGH: Color = Color(0.42, 0.88, 0.42, 1.0)
const COLOR_HEALTH_FG_MID: Color = Color(0.92, 0.82, 0.30, 1.0)
const COLOR_HEALTH_FG_LOW: Color = Color(0.92, 0.34, 0.30, 1.0)
const COLOR_RANK_PIP: Color = Color(1.0, 0.86, 0.30, 1.0)


func owner_color(owner: int) -> Color:
	if owner < 0:
		return Color(0.62, 0.62, 0.62, 1.0)
	return OWNER_COLORS[owner % OWNER_COLORS.size()]


# A darker companion shade of an owner color (rooftops, outlines).
func _darken(color: Color, amount: float = 0.45) -> Color:
	return Color(color.r * (1.0 - amount), color.g * (1.0 - amount), color.b * (1.0 - amount), color.a)


# --- Tiles ------------------------------------------------------------------
#
# NOTE: `canvas` is intentionally UNTYPED (duck-typed) -- identical contract to
# StyleSimple. The style calls only standard CanvasItem draw_* primitives, so it
# works against the live RenderAdapter and any test recorder alike. A detailed
# style is a drop-in replacement for the simple one (Logic/Render Separation).

func draw_tile(canvas, rect: Rect2, terrain_id: int) -> void:
	# A stable checkerboard pattern derived from the tile's pixel position gives
	# a subtle textured look without any per-frame randomness.
	var checker: bool = (int(rect.position.x / max(1.0, rect.size.x)) + int(rect.position.y / max(1.0, rect.size.y))) % 2 == 0
	var color: Color
	match terrain_id:
		1:
			color = COLOR_WALL_A if checker else COLOR_WALL_B
		2:
			color = COLOR_WATER_A if checker else COLOR_WATER_B
		_:
			color = COLOR_GROUND_A if checker else COLOR_GROUND_B
	canvas.draw_rect(rect, color, true)
	# Walls get a small highlighted top edge to read as raised blocks.
	if terrain_id == 1:
		var top: Rect2 = Rect2(rect.position, Vector2(rect.size.x, max(1.0, rect.size.y * 0.18)))
		canvas.draw_rect(top, Color(1, 1, 1, 0.10), true)
	# Faint grid for readability (lighter than the simple style).
	canvas.draw_rect(rect, COLOR_GRID, false, 1.0)


# --- Buildings --------------------------------------------------------------

func draw_building(canvas, rect: Rect2, building: Dictionary) -> void:
	var owner: int = int(building.get("owner", 0))
	var base: Color = owner_color(owner)
	# Drop shadow for depth.
	var shadow_off: Vector2 = rect.size * 0.06
	var inset: Vector2 = rect.size * 0.10
	var body: Rect2 = Rect2(rect.position + inset, rect.size - inset * 2.0)
	canvas.draw_rect(Rect2(body.position + shadow_off, body.size), COLOR_SHADOW, true)
	# Main body.
	canvas.draw_rect(body, base, true)
	# Rooftop strip (darker companion shade) for a built look.
	var roof: Rect2 = Rect2(body.position, Vector2(body.size.x, body.size.y * 0.34))
	canvas.draw_rect(roof, _darken(base, 0.40), true)
	# Outline.
	canvas.draw_rect(body, Color(0, 0, 0, 0.55), false, 2.0)
	# A small flag pole + flag on top, tinted to the owner, marks command posts.
	var pole_x: float = body.position.x + body.size.x * 0.5
	var pole_top: Vector2 = Vector2(pole_x, body.position.y - body.size.y * 0.28)
	canvas.draw_line(Vector2(pole_x, body.position.y), pole_top, Color(0, 0, 0, 0.7), 2.0)
	var flag: PackedVector2Array = PackedVector2Array([
		pole_top,
		pole_top + Vector2(body.size.x * 0.30, body.size.y * 0.06),
		pole_top + Vector2(0, body.size.y * 0.14),
	])
	canvas.draw_colored_polygon(flag, base)
	# Construction / level readout: draw small "level pips" along the bottom.
	var level: int = int(building.get("level", 1))
	_draw_level_pips(canvas, body, level)
	_draw_health_bar(canvas, rect, building)


func _draw_level_pips(canvas, body: Rect2, level: int) -> void:
	if level <= 1:
		return
	var pip_r: float = max(1.5, body.size.x * 0.06)
	var spacing: float = pip_r * 2.6
	var start_x: float = body.position.x + body.size.x * 0.5 - spacing * float(level - 1) * 0.5
	var y: float = body.position.y + body.size.y - pip_r * 1.6
	for i in range(level):
		canvas.draw_circle(Vector2(start_x + spacing * float(i), y), pip_r, Color(1, 1, 1, 0.85))


# --- Units ------------------------------------------------------------------

func draw_unit(canvas, rect: Rect2, unit: Dictionary, is_selected: bool) -> void:
	var owner: int = int(unit.get("owner", 0))
	var base: Color = owner_color(owner)
	var center: Vector2 = rect.position + rect.size * 0.5
	var radius: float = rect.size.x * 0.32
	# Heroes are drawn noticeably larger so they read as elite units.
	if str(unit.get("category", "")) == "hero" or str(unit.get("type", "")) == "hero":
		radius = rect.size.x * 0.42

	# Drop shadow (offset down-right) for depth.
	canvas.draw_circle(center + rect.size * 0.06, radius, COLOR_SHADOW)

	# Selection ring underneath the body.
	if is_selected:
		canvas.draw_arc(center, radius + 4.0, 0.0, TAU, 24, COLOR_SELECT, 2.0)

	# Body.
	canvas.draw_circle(center, radius, base)
	# Inner rim (darker) for a hull look.
	canvas.draw_arc(center, radius, 0.0, TAU, 24, _darken(base, 0.5), 2.0)

	# Facing marker: a short barrel pointing toward the unit's movement target if
	# present, otherwise to the right. Derived purely from world data (no RNG).
	var facing: Vector2 = _facing_vector(unit)
	canvas.draw_line(center, center + facing * (radius + rect.size.x * 0.18), _darken(base, 0.25), max(2.0, rect.size.x * 0.10))

	# Veterancy rank pips (Phase 2 veterancy): small dots above the unit.
	var rank: int = int(unit.get("veterancy", unit.get("rank", 0)))
	_draw_rank_pips(canvas, rect, rank)

	_draw_health_bar(canvas, rect, unit)


# Compute a stable facing direction from the unit's path / target, if any.
func _facing_vector(unit: Dictionary) -> Vector2:
	var ux: float = float(unit.get("x", 0))
	var uy: float = float(unit.get("y", 0))
	# A "target_x/target_y" or a non-empty "path" lets us face the destination.
	if unit.has("target_x") and unit.has("target_y"):
		var dir: Vector2 = Vector2(float(unit["target_x"]) - ux, float(unit["target_y"]) - uy)
		if dir.length() > 0.001:
			return dir.normalized()
	var path: Array = unit.get("path", [])
	if path.size() > 0:
		var step: Variant = path[0]
		if step is Array and (step as Array).size() >= 2:
			var dir2: Vector2 = Vector2(float(step[0]) - ux, float(step[1]) - uy)
			if dir2.length() > 0.001:
				return dir2.normalized()
	return Vector2.RIGHT


func _draw_rank_pips(canvas, rect: Rect2, rank: int) -> void:
	if rank <= 0:
		return
	var pip_r: float = max(1.5, rect.size.x * 0.06)
	var spacing: float = pip_r * 2.4
	var count: int = mini(rank, 3)
	var start_x: float = rect.position.x + rect.size.x * 0.5 - spacing * float(count - 1) * 0.5
	var y: float = rect.position.y - pip_r * 1.4
	for i in range(count):
		canvas.draw_circle(Vector2(start_x + spacing * float(i), y), pip_r, COLOR_RANK_PIP)


# --- Shared health bar ------------------------------------------------------

func _draw_health_bar(canvas, rect: Rect2, entity: Dictionary) -> void:
	var max_health: int = int(entity.get("max_health", 0))
	if max_health <= 0:
		return
	var health: int = clampi(int(entity.get("health", 0)), 0, max_health)
	var ratio: float = float(health) / float(max_health)
	if ratio >= 1.0:
		return  # hide full-health bars to reduce clutter
	var bar_w: float = rect.size.x * 0.82
	var bar_h: float = max(2.0, rect.size.y * 0.09)
	var bar_pos: Vector2 = rect.position + Vector2(rect.size.x * 0.09, -bar_h - 2.0)
	canvas.draw_rect(Rect2(bar_pos, Vector2(bar_w, bar_h)), COLOR_HEALTH_BG, true)
	var fg: Color = COLOR_HEALTH_FG_HIGH
	if ratio < 0.33:
		fg = COLOR_HEALTH_FG_LOW
	elif ratio < 0.66:
		fg = COLOR_HEALTH_FG_MID
	canvas.draw_rect(Rect2(bar_pos, Vector2(bar_w * ratio, bar_h)), fg, true)
	# Thin outline around the bar.
	canvas.draw_rect(Rect2(bar_pos, Vector2(bar_w, bar_h)), Color(0, 0, 0, 0.5), false, 1.0)
