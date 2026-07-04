# tile_grid.gd
# ----------------------------------------------------------------------------
# Project Nexus - Editable tile grid widget for the Map Editor (Phase E, E.1).
#
# A tiny, self-contained Control that DRAWS a `ScenarioProject`'s map (ground /
# walls / placed buildings + units) and turns a click into a `cell_clicked(x, y)`
# signal the editor acts on. It is a pure VIEW: it never mutates the model and
# never touches WorldState or the deterministic hash -- it only reads a project
# snapshot the editor hands it.
#
# It deliberately uses the same flat-shape vocabulary as `StyleSimple` so the
# editor preview looks like the in-game simple renderer without depending on it
# (keeping the editor decoupled). A real live preview reusing the RenderAdapter
# is the remaining Phase D.6 polish; this widget already proves the data path.
#
# CODE LANGUAGE POLICY: English-only identifiers/comments.
# ----------------------------------------------------------------------------
extends Control

signal cell_clicked(x: int, y: int)

# A neutral palette (cosmetic only). Owner colors mirror the simple style's
# friend/foe convention (0 = blue local, 1 = red, others cycle).
const COLOR_GROUND: Color = Color(0.16, 0.18, 0.22)
const COLOR_WALL: Color = Color(0.45, 0.45, 0.5)
const COLOR_GRID: Color = Color(0.25, 0.27, 0.32)
const OWNER_COLORS: Array = [
	Color(0.30, 0.69, 0.95),  # 0 - blue
	Color(0.89, 0.33, 0.24),  # 1 - red
	Color(0.36, 0.75, 0.42),  # 2 - green
	Color(0.89, 0.71, 0.25),  # 3 - amber
]

var _project: Object = null
# Pixel size of one tile, recomputed on resize so the whole map always fits.
var _tile_px: float = 16.0
var _origin: Vector2 = Vector2.ZERO


func set_scenario(project: Object) -> void:
	_project = project
	queue_redraw()


func _ready() -> void:
	resized.connect(queue_redraw)


func _gui_input(event: InputEvent) -> void:
	if _project == null:
		return
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var cell: Vector2i = _pixel_to_cell((event as InputEventMouseButton).position)
		if cell.x >= 0:
			cell_clicked.emit(cell.x, cell.y)


func _pixel_to_cell(p: Vector2) -> Vector2i:
	if _project == null or _tile_px <= 0.0:
		return Vector2i(-1, -1)
	var x: int = int((p.x - _origin.x) / _tile_px)
	var y: int = int((p.y - _origin.y) / _tile_px)
	if x < 0 or y < 0 or x >= int(_project.width) or y >= int(_project.height):
		return Vector2i(-1, -1)
	return Vector2i(x, y)


func _recompute_layout() -> void:
	if _project == null:
		return
	var w: int = int(_project.width)
	var h: int = int(_project.height)
	if w <= 0 or h <= 0:
		return
	var avail: Vector2 = size
	var tile_w: float = avail.x / float(w)
	var tile_h: float = avail.y / float(h)
	_tile_px = max(2.0, min(tile_w, tile_h))
	# Centre the grid in the available space.
	var grid_w: float = _tile_px * float(w)
	var grid_h: float = _tile_px * float(h)
	_origin = Vector2((avail.x - grid_w) * 0.5, (avail.y - grid_h) * 0.5)


func _draw() -> void:
	if _project == null:
		return
	_recompute_layout()
	var w: int = int(_project.width)
	var h: int = int(_project.height)
	# Ground + walls.
	for y in range(h):
		for x in range(w):
			var r: Rect2 = Rect2(_origin + Vector2(x, y) * _tile_px, Vector2(_tile_px, _tile_px))
			var fill: Color = COLOR_WALL if _project.is_wall(x, y) else COLOR_GROUND
			draw_rect(r, fill, true)
			draw_rect(r, COLOR_GRID, false, 1.0)
	# Buildings (squares) + units (circles), tinted by owner.
	for b in _project.buildings:
		_draw_entity(int(b.get("x", 0)), int(b.get("y", 0)), int(b.get("owner", 0)), true)
	for u in _project.units:
		_draw_entity(int(u.get("x", 0)), int(u.get("y", 0)), int(u.get("owner", 0)), false)
	# P7.1 (R10.5): flags drawn as diamonds tinted by team so authors see them.
	if "flags" in _project:
		for f in _project.flags:
			_draw_flag(int(f.get("x", 0)), int(f.get("y", 0)), int(f.get("team", 0)))


func _draw_entity(x: int, y: int, owner: int, is_building: bool) -> void:
	var col: Color = OWNER_COLORS[owner % OWNER_COLORS.size()]
	var top_left: Vector2 = _origin + Vector2(x, y) * _tile_px
	var centre: Vector2 = top_left + Vector2(_tile_px, _tile_px) * 0.5
	if is_building:
		var pad: float = _tile_px * 0.15
		draw_rect(Rect2(top_left + Vector2(pad, pad), Vector2(_tile_px - 2.0 * pad, _tile_px - 2.0 * pad)), col, true)
	else:
		draw_circle(centre, _tile_px * 0.35, col)


# A flag marker: a small diamond (rotated square) tinted by team, with a white
# outline so it reads on top of any terrain.
func _draw_flag(x: int, y: int, team: int) -> void:
	var col: Color = OWNER_COLORS[team % OWNER_COLORS.size()]
	var centre: Vector2 = _origin + Vector2(x, y) * _tile_px + Vector2(_tile_px, _tile_px) * 0.5
	var r: float = _tile_px * 0.4
	var points: PackedVector2Array = PackedVector2Array([
		centre + Vector2(0, -r),
		centre + Vector2(r, 0),
		centre + Vector2(0, r),
		centre + Vector2(-r, 0),
	])
	draw_colored_polygon(points, col)
	draw_polyline(PackedVector2Array([points[0], points[1], points[2], points[3], points[0]]), Color.WHITE, 1.5)
