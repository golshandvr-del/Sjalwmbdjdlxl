# path_service.gd
# ----------------------------------------------------------------------------
# Project Nexus - Path Service (shared deterministic pathfinding utility).
#
# A STATELESS, side-effect-free A* implementation that operates on a flat grid
# array. It is intentionally NOT a module: it holds no state and touches no
# WorldState. Both the Map module (authoritative grid owner) and any consumer
# (e.g. Units, AI) can call it with a grid snapshot to get the SAME result,
# which is exactly what determinism / lockstep multiplayer requires.
#
# Grid encoding (matches MapModule): a flat Array of ints, length width*height,
# index = y * width + x. Value 0 == walkable ground; anything else == blocked.
#
# Determinism: open-set ordering breaks ties by encoded tile index, and
# neighbour expansion uses a fixed order (up, right, down, left). The same
# inputs always produce the identical path.
#
# CODE LANGUAGE POLICY: English-only identifiers/comments.
# ----------------------------------------------------------------------------
class_name PathService
extends RefCounted

const GROUND: int = 0


# Returns an Array of Vector2i from start to goal inclusive, or [] if no path.
static func find_path(width: int, height: int, tiles: Array, start: Vector2i, goal: Vector2i) -> Array:
	if width <= 0 or height <= 0:
		return []
	if not _in_bounds(width, height, start) or not _in_bounds(width, height, goal):
		return []
	if not _walkable(width, height, tiles, goal.x, goal.y):
		return []
	if start == goal:
		return [start]

	var start_idx: int = start.y * width + start.x
	var goal_idx: int = goal.y * width + goal.x

	var came_from: Dictionary = {}
	var g_cost: Dictionary = { start_idx: 0 }
	var open: Array = [{ "idx": start_idx, "f": _heuristic(start, goal) }]

	while not open.is_empty():
		open.sort_custom(_compare_open)
		var current: Dictionary = open.pop_front()
		var current_idx: int = int(current["idx"])
		if current_idx == goal_idx:
			return _reconstruct(width, came_from, current_idx)

		var cx: int = current_idx % width
		var cy: int = current_idx / width
		for neighbour in _neighbours(cx, cy):
			var nx: int = neighbour.x
			var ny: int = neighbour.y
			if not _walkable(width, height, tiles, nx, ny):
				continue
			var n_idx: int = ny * width + nx
			var tentative_g: int = int(g_cost[current_idx]) + 1
			if not g_cost.has(n_idx) or tentative_g < int(g_cost[n_idx]):
				came_from[n_idx] = current_idx
				g_cost[n_idx] = tentative_g
				var f: int = tentative_g + _heuristic(Vector2i(nx, ny), goal)
				_push_open(open, n_idx, f)
	return []


# MC1.2 (request 1): find a path on the viewer's BELIEF grid instead of the real
# grid. HIDDEN tiles are assumed walkable, so the unit plans without cheating
# through undiscovered walls; when it later walks into sight of a real obstacle
# the caller replans (units_module, MC1.3). Deterministic: the belief grid is a
# pure function of (tiles, fog, viewer), and A* is already deterministic, so all
# peers compute the identical path.
static func find_path_on_belief(width: int, height: int, tiles: Array, fog: Dictionary, viewer: int, start: Vector2i, goal: Vector2i) -> Array:
	var belief: Array = BeliefGridUtil.build_belief_grid(width, height, tiles, fog, viewer)
	return find_path(width, height, belief, start, goal)


static func _in_bounds(width: int, height: int, p: Vector2i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < width and p.y < height


static func _walkable(width: int, height: int, tiles: Array, x: int, y: int) -> bool:
	if x < 0 or y < 0 or x >= width or y >= height:
		return false
	var idx: int = y * width + x
	if idx < 0 or idx >= tiles.size():
		return false
	return int(tiles[idx]) == GROUND


static func _heuristic(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)


static func _neighbours(x: int, y: int) -> Array:
	return [
		Vector2i(x, y - 1),
		Vector2i(x + 1, y),
		Vector2i(x, y + 1),
		Vector2i(x - 1, y),
	]


static func _compare_open(a: Dictionary, b: Dictionary) -> bool:
	if a["f"] == b["f"]:
		return a["idx"] < b["idx"]
	return a["f"] < b["f"]


static func _push_open(open: Array, idx: int, f: int) -> void:
	for i in range(open.size()):
		if int(open[i]["idx"]) == idx:
			if f < int(open[i]["f"]):
				open[i]["f"] = f
			return
	open.append({ "idx": idx, "f": f })


static func _reconstruct(width: int, came_from: Dictionary, current_idx: int) -> Array:
	var path: Array = []
	var idx: int = current_idx
	while true:
		var x: int = idx % width
		var y: int = idx / width
		path.push_front(Vector2i(x, y))
		if not came_from.has(idx):
			break
		idx = int(came_from[idx])
	return path
