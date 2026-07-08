# minimap.gd
# ----------------------------------------------------------------------------
# Project Nexus - Corner Minimap widget (Phase P3, step P3.3 / R12.3).
#
# A small, self-drawing map overview placed in a screen corner. It reads the
# live WorldState every frame and paints:
#
#   - the terrain    (walkable = dark, walls = lighter blocks)
#   - buildings      (owner-coloured squares)
#   - units          (owner-coloured dots)
#   - the camera box (the rectangle currently visible in the main view)
#
# Clicking (or dragging) on the minimap recentres the main camera on the
# corresponding world tile. It is pure presentation + a camera move: it NEVER
# touches the simulation, so it is safe for lockstep multiplayer.
#
# It is a Control that draws itself, driven by a reference to the active
# RenderAdapter (for owner colours + camera recentre) and read-only WorldState.
#
# CODE LANGUAGE POLICY: English-only identifiers/comments.
# ----------------------------------------------------------------------------
extends Control
class_name Minimap

# Owner colours (kept in sync with the render styles' palette intent).
const OWNER_COLORS: Array = [
	Color(0.30, 0.62, 1.00),   # player 0 - blue
	Color(1.00, 0.36, 0.32),   # player 1 - red
	Color(0.40, 0.85, 0.45),   # player 2 - green
	Color(0.95, 0.80, 0.30),   # player 3 - yellow
]
const NEUTRAL_COLOR: Color = Color(0.7, 0.7, 0.7)
const GROUND_COLOR: Color = Color(0.10, 0.13, 0.10)
const WALL_COLOR: Color = Color(0.32, 0.34, 0.40)
const BORDER_COLOR: Color = Color(0.239, 0.435, 0.706)
const CAMERA_BOX_COLOR: Color = Color(1, 1, 1, 0.85)

# The RenderAdapter whose camera we recentre and whose fog viewer we respect.
var render_adapter: Object = null
# The local player index (for fog: only show what this player can see). -1 = all.
var fog_viewer: int = -1


func _ready() -> void:
	custom_minimum_size = Vector2(180, 130)
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Redraw every frame so the camera box + unit dots stay live.
	set_process(true)


func _process(_delta: float) -> void:
	queue_redraw()


func _world_state() -> Object:
	var nexus: Node = get_node_or_null("/root/Nexus")
	if nexus == null:
		return null
	return nexus.world_state


func _map_section() -> Dictionary:
	var ws: Object = _world_state()
	if ws == null:
		return {}
	return ws.get_section("map")


func _draw() -> void:
	var map: Dictionary = _map_section()
	var w: int = int(map.get("width", 0))
	var h: int = int(map.get("height", 0))
	if w <= 0 or h <= 0:
		return
	var area: Vector2 = size
	# Background + border.
	draw_rect(Rect2(Vector2.ZERO, area), Color(0.02, 0.03, 0.05, 0.9), true)
	draw_rect(Rect2(Vector2.ZERO, area), BORDER_COLOR, false, 2.0)

	var cell: Vector2 = Vector2(area.x / float(w), area.y / float(h))

	# Terrain (only draw walls as blocks; ground is the background colour).
	var tiles: Array = map.get("tiles", [])
	if tiles.size() >= w * h:
		for y in range(h):
			for x in range(w):
				if int(tiles[y * w + x]) != 0:
					draw_rect(Rect2(Vector2(x, y) * cell, cell), WALL_COLOR, true)

	var ws: Object = _world_state()
	if ws == null:
		return

	# MB1.1 (bug 3): respect fog of war so the minimap never leaks enemy
	# positions. Enemy units/buildings are only drawn on tiles the fog_viewer can
	# currently SEE (same rule as the main RenderAdapter). fog_viewer < 0 shows
	# everything (spectator / fog disabled).
	var fog: Dictionary = ws.get_section("fog")

	# Buildings as owner-coloured squares.
	var buildings: Dictionary = ws.get_section("buildings").get("list", {})
	for key in buildings.keys():
		var b: Dictionary = buildings[key]
		var bx: int = int(b.get("x", 0))
		var by: int = int(b.get("y", 0))
		if not FogUtil.should_draw(fog, fog_viewer, int(b.get("owner", -1)), bx, by):
			continue
		var pos: Vector2 = Vector2(bx, by) * cell
		draw_rect(Rect2(pos, cell * 1.5), _owner_color(int(b.get("owner", -1))), true)

	# Units as owner-coloured dots.
	var units: Dictionary = ws.get_section("units").get("list", {})
	for key in units.keys():
		var u: Dictionary = units[key]
		var ux: int = int(u.get("x", 0))
		var uy: int = int(u.get("y", 0))
		if not FogUtil.should_draw(fog, fog_viewer, int(u.get("owner", -1)), ux, uy):
			continue
		var c: Vector2 = (Vector2(ux, uy) + Vector2(0.5, 0.5)) * cell
		draw_circle(c, maxf(1.5, cell.x * 0.4), _owner_color(int(u.get("owner", -1))))

	# Camera box: map the main view's visible world rect onto the minimap.
	_draw_camera_box(w, h, cell)


func _draw_camera_box(map_w: int, map_h: int, cell: Vector2) -> void:
	if render_adapter == null:
		return
	var tile_size: float = float(render_adapter.get("tile_size"))
	var zoom: float = float(render_adapter.get("zoom"))
	var offset: Vector2 = render_adapter.get("camera_offset")
	if tile_size <= 0.0 or zoom <= 0.0:
		return
	var view: Vector2 = get_viewport_rect().size
	# Screen (0,0) and (view) map back to world tiles via the adapter transform.
	var top_left_tile: Vector2 = (-offset) / (tile_size * zoom)
	var bottom_right_tile: Vector2 = (view - offset) / (tile_size * zoom)
	var box_pos: Vector2 = Vector2(
		clampf(top_left_tile.x, 0.0, float(map_w)),
		clampf(top_left_tile.y, 0.0, float(map_h))) * cell
	var box_end: Vector2 = Vector2(
		clampf(bottom_right_tile.x, 0.0, float(map_w)),
		clampf(bottom_right_tile.y, 0.0, float(map_h))) * cell
	draw_rect(Rect2(box_pos, box_end - box_pos), CAMERA_BOX_COLOR, false, 1.5)


func _owner_color(owner: int) -> Color:
	if owner < 0:
		return NEUTRAL_COLOR
	return OWNER_COLORS[owner % OWNER_COLORS.size()]


# --- Input: click/drag to recentre the main camera --------------------------

func _gui_input(event: InputEvent) -> void:
	var do_center: bool = false
	var local_pos: Vector2 = Vector2.ZERO
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		do_center = true
		local_pos = event.position
	elif event is InputEventScreenTouch and event.pressed:
		do_center = true
		local_pos = event.position
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
		do_center = true
		local_pos = event.position
	elif event is InputEventScreenDrag:
		do_center = true
		local_pos = event.position
	if not do_center:
		return
	_center_camera_on(local_pos)
	accept_event()


func _center_camera_on(local_pos: Vector2) -> void:
	if render_adapter == null:
		return
	var map: Dictionary = _map_section()
	var w: int = int(map.get("width", 0))
	var h: int = int(map.get("height", 0))
	if w <= 0 or h <= 0:
		return
	# Convert the click position on the minimap into a world tile.
	var tx: int = int(clampf(local_pos.x / size.x * float(w), 0.0, float(w - 1)))
	var ty: int = int(clampf(local_pos.y / size.y * float(h), 0.0, float(h - 1)))
	if render_adapter.has_method("center_camera_on"):
		render_adapter.center_camera_on(Vector2i(tx, ty), get_viewport_rect().size)
	if render_adapter.has_method("clamp_camera"):
		render_adapter.clamp_camera(get_viewport_rect().size)
