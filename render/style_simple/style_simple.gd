# style_simple.gd
# ----------------------------------------------------------------------------
# Project Nexus - Simple Render Style (Phase 1, step 1.10).
#
# A "Mindustry-style" minimalist renderer: tiles, buildings, and units are
# drawn as flat colored shapes. It is a pure presentation strategy used by the
# RenderAdapter; it reads nothing from the simulation itself -- the adapter
# passes it already-resolved data + rects.
#
# In Phase 6 a `style_detailed` implementing the SAME method signatures can
# replace this one with zero changes to game logic (Logic/Render Separation).
#
# Required interface (duck-typed by RenderAdapter):
#   draw_tile(canvas, rect, terrain_id)
#   draw_building(canvas, rect, building_dict)
#   draw_unit(canvas, rect, unit_dict, is_selected)
#
# CODE LANGUAGE POLICY: English-only identifiers/comments.
# ----------------------------------------------------------------------------
class_name StyleSimple
extends RefCounted

# Terrain palette (matches MapModule TERRAIN_* ids).
const COLOR_GROUND: Color = Color(0.16, 0.20, 0.16, 1.0)
const COLOR_WALL: Color = Color(0.32, 0.30, 0.28, 1.0)
const COLOR_WATER: Color = Color(0.12, 0.22, 0.38, 1.0)
const COLOR_GRID: Color = Color(0.0, 0.0, 0.0, 0.18)

# Owner colors (0 = local player, 1 = enemy, others cycle).
const OWNER_COLORS: Array = [
	Color(0.30, 0.70, 0.95, 1.0),  # player 0 - blue
	Color(0.92, 0.36, 0.32, 1.0),  # player 1 - red
	Color(0.46, 0.80, 0.38, 1.0),  # player 2 - green
	Color(0.88, 0.78, 0.30, 1.0),  # player 3 - yellow
]

const COLOR_SELECT: Color = Color(1.0, 1.0, 1.0, 1.0)
const COLOR_HEALTH_BG: Color = Color(0.0, 0.0, 0.0, 0.6)
const COLOR_HEALTH_FG: Color = Color(0.40, 0.85, 0.40, 1.0)


func owner_color(owner: int) -> Color:
	if owner < 0:
		return Color(0.6, 0.6, 0.6, 1.0)
	return OWNER_COLORS[owner % OWNER_COLORS.size()]


# --- Tiles ------------------------------------------------------------------
#
# NOTE: `canvas` is intentionally UNTYPED (duck-typed). The renderer only ever
# calls the standard CanvasItem draw_* primitives on it, so any object that
# exposes those methods works -- the live RenderAdapter (a Node2D) in the game,
# and a lightweight recorder in the headless tests. This is the Logic/Render
# Separation contract: a style never assumes a concrete canvas class.

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
	# Thin grid outline for readability.
	canvas.draw_rect(rect, COLOR_GRID, false, 1.0)


# --- Buildings --------------------------------------------------------------

func draw_building(canvas, rect: Rect2, building: Dictionary) -> void:
	var owner: int = int(building.get("owner", 0))
	var inset: Vector2 = rect.size * 0.08
	var body: Rect2 = Rect2(rect.position + inset, rect.size - inset * 2.0)
	canvas.draw_rect(body, owner_color(owner), true)
	# Dark border to read as a structure.
	canvas.draw_rect(body, Color(0, 0, 0, 0.5), false, 2.0)
	_draw_health_bar(canvas, rect, building)


# --- Units ------------------------------------------------------------------

func draw_unit(canvas, rect: Rect2, unit: Dictionary, is_selected: bool) -> void:
	# Phase A.4: bigger, clearer units. A dark ownership ring around a brighter
	# body makes friend/foe instantly readable even at small zoom; a white
	# selection ring sits outside it. Still flat shapes (no textures yet).
	var owner: int = int(unit.get("owner", 0))
	var center: Vector2 = rect.position + rect.size * 0.5
	var radius: float = rect.size.x * 0.42
	if is_selected:
		canvas.draw_circle(center, radius + 4.0, COLOR_SELECT)
	# Ownership ring (dark outline) for contrast against the ground.
	canvas.draw_circle(center, radius + 1.5, Color(0, 0, 0, 0.65))
	canvas.draw_circle(center, radius, owner_color(owner))
	_draw_health_bar(canvas, rect, unit)


# --- Shared health bar ------------------------------------------------------

func _draw_health_bar(canvas, rect: Rect2, entity: Dictionary) -> void:
	var max_health: int = int(entity.get("max_health", 0))
	if max_health <= 0:
		return
	var health: int = clampi(int(entity.get("health", 0)), 0, max_health)
	var ratio: float = float(health) / float(max_health)
	if ratio >= 1.0:
		return  # hide full-health bars to reduce clutter
	var bar_w: float = rect.size.x * 0.8
	var bar_h: float = max(2.0, rect.size.y * 0.10)
	var bar_pos: Vector2 = rect.position + Vector2(rect.size.x * 0.1, -bar_h - 2.0)
	canvas.draw_rect(Rect2(bar_pos, Vector2(bar_w, bar_h)), COLOR_HEALTH_BG, true)
	canvas.draw_rect(Rect2(bar_pos, Vector2(bar_w * ratio, bar_h)), COLOR_HEALTH_FG, true)
