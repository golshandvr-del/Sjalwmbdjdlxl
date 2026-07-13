# site_topology_util.gd
# ----------------------------------------------------------------------------
# Project Nexus - Map-grid TOPOLOGY extraction for AI building placement
# (Phase MD9, expert item 8, step MD9.3). Pure, deterministic helpers that pull
# CHOKE points and the enemy's likely ATTACK PATH out of the raw map grid, and
# that enumerate the limited set of CANDIDATE build tiles (rings around HQ plus
# nearby chokes). MD9.4 then scores those candidates.
#
# REUSE (MD9.3 requirement): the enemy attack route is estimated with the
# existing deterministic PathService.find_path (core/path_service.gd), and the
# candidate rings mirror the geometry style of PlacementPlanner. Nothing here is
# a module; it takes a PLAIN grid snapshot (flat Array of ints, index =
# y*width + x, 0 = walkable; matches PathService / MapModule) so it stays pure
# and headlessly testable. No SceneTree, no world model, no sim hasher.
#
# Determinism: every scan is over a stably-ordered set (tiles in row-major
# index order, candidates de-duplicated then sorted by (x, y)), and pathfinding
# already breaks ties by tile index. Same grid in -> byte-identical output.
#
# CODE LANGUAGE POLICY: English-only identifiers/comments (pure ASCII).
# ----------------------------------------------------------------------------
class_name SiteTopologyUtil
extends RefCounted


const SCALE: int = 1000
const GROUND: int = 0


# --- Grid helpers ------------------------------------------------------------

static func _in_bounds(width: int, height: int, x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < width and y < height


static func _is_ground(width: int, height: int, tiles: Array, x: int, y: int) -> bool:
	if not _in_bounds(width, height, x, y):
		return false
	var idx: int = y * width + x
	if idx < 0 or idx >= tiles.size():
		return false
	return int(tiles[idx]) == GROUND


static func _open_neighbours(width: int, height: int, tiles: Array, x: int, y: int) -> int:
	var open: int = 0
	if _is_ground(width, height, tiles, x, y - 1):
		open += 1
	if _is_ground(width, height, tiles, x + 1, y):
		open += 1
	if _is_ground(width, height, tiles, x, y + 1):
		open += 1
	if _is_ground(width, height, tiles, x - 1, y):
		open += 1
	return open


# --- Choke detection ---------------------------------------------------------

# A tile is a CHOKE when it is walkable ground AND forms a 1-wide corridor:
# exactly one opposing pair of neighbours is open while the perpendicular pair
# is blocked (a vertical or horizontal pinch). Returns true for that shape.
static func is_choke(width: int, height: int, tiles: Array, x: int, y: int) -> bool:
	if not _is_ground(width, height, tiles, x, y):
		return false
	var up: bool = _is_ground(width, height, tiles, x, y - 1)
	var down: bool = _is_ground(width, height, tiles, x, y + 1)
	var left: bool = _is_ground(width, height, tiles, x - 1, y)
	var right: bool = _is_ground(width, height, tiles, x + 1, y)
	var vertical: bool = up and down and not left and not right
	var horizontal: bool = left and right and not up and not down
	return vertical or horizontal


# All choke tiles on the grid, as an Array of Vector2i in stable row-major
# order (index-ascending), so consumers get a deterministic list.
static func find_chokes(width: int, height: int, tiles: Array) -> Array:
	var out: Array = []
	if width <= 0 or height <= 0:
		return out
	for y in range(height):
		for x in range(width):
			if is_choke(width, height, tiles, x, y):
				out.append(Vector2i(x, y))
	return out


# The choke tiles that actually lie on (or immediately beside) the enemy's
# estimated attack path -- the tactically relevant ones to defend. `path` is an
# Array of Vector2i (e.g. from estimate_attack_path). A choke counts if it is a
# path cell or 4-adjacent to one. Result is stable (row-major order).
static func chokes_on_path(width: int, height: int, tiles: Array, path: Array) -> Array:
	var chokes: Array = find_chokes(width, height, tiles)
	if path.is_empty():
		return []
	# Build a fast membership set of path cells + their 4-neighbours.
	var near: Dictionary = {}
	for raw in path:
		var p: Vector2i = raw as Vector2i
		near[p] = true
		near[Vector2i(p.x, p.y - 1)] = true
		near[Vector2i(p.x + 1, p.y)] = true
		near[Vector2i(p.x, p.y + 1)] = true
		near[Vector2i(p.x - 1, p.y)] = true
	var out: Array = []
	for c in chokes:
		if near.has(c):
			out.append(c)
	return out


# --- Attack path estimation (reuses PathService) -----------------------------

# The enemy's likely attack route from `enemy` to our `hq`, as an Array of
# Vector2i (inclusive), or [] if unreachable. Thin deterministic wrapper over
# PathService.find_path so MD9 reuses the shared A* rather than duplicating it.
static func estimate_attack_path(width: int, height: int, tiles: Array, enemy: Vector2i, hq: Vector2i) -> Array:
	return PathService.find_path(width, height, tiles, enemy, hq)


# --- Candidate enumeration ---------------------------------------------------

# Enumerate a LIMITED, deterministic set of candidate build tiles: concentric
# Manhattan "rings" around the HQ (radius 1.. `max_radius`) plus the chokes on
# the enemy attack path. Only walkable ground cells are kept; the HQ cell and
# any `occupied` cell are excluded. The result is de-duplicated and stably
# sorted by (x, y) so every peer scores the same ordered candidate list.
#
#   world = { "width","height","tiles",
#             "hq": Vector2i-ish {"x","y"},
#             "enemies": Array[{"x","y"}],
#             "occupied": Array[{"x","y"}] }
static func candidate_tiles(world: Dictionary, max_radius: int = 4) -> Array:
	var width: int = int(world.get("width", 0))
	var height: int = int(world.get("height", 0))
	var tiles: Array = (world.get("tiles", []) as Array)
	var hq_d: Dictionary = (world.get("hq", {}) as Dictionary)
	var enemies: Array = (world.get("enemies", []) as Array)
	var occupied: Array = (world.get("occupied", []) as Array)
	if width <= 0 or height <= 0 or hq_d.is_empty():
		return []
	var hq: Vector2i = Vector2i(int(hq_d.get("x", 0)), int(hq_d.get("y", 0)))

	# Exclusion set: the HQ and everything already occupied.
	var blocked_set: Dictionary = {}
	blocked_set[hq] = true
	for raw in occupied:
		var od: Dictionary = raw as Dictionary
		blocked_set[Vector2i(int(od.get("x", 0)), int(od.get("y", 0)))] = true

	var found: Dictionary = {}

	# 1) Manhattan rings around HQ.
	if max_radius < 1:
		max_radius = 1
	for r in range(1, max_radius + 1):
		for dx in range(-r, r + 1):
			var dy_abs: int = r - abs(dx)
			for sy in [dy_abs, -dy_abs]:
				var cx: int = hq.x + dx
				var cy: int = hq.y + sy
				var cell: Vector2i = Vector2i(cx, cy)
				if blocked_set.has(cell):
					continue
				if _is_ground(width, height, tiles, cx, cy):
					found[cell] = true

	# 2) Chokes on the nearest enemy's attack path (defensive candidates).
	if not enemies.is_empty():
		var nearest: Dictionary = _nearest_point(hq, enemies)
		var enemy: Vector2i = Vector2i(int(nearest.get("x", hq.x)), int(nearest.get("y", hq.y)))
		var path: Array = estimate_attack_path(width, height, tiles, enemy, hq)
		for c in chokes_on_path(width, height, tiles, path):
			var cc: Vector2i = c as Vector2i
			if not blocked_set.has(cc) and _is_ground(width, height, tiles, cc.x, cc.y):
				found[cc] = true

	# De-duplicate (Dictionary keys) then stable-sort by (x, y).
	var out: Array = found.keys()
	out.sort_custom(func(a, b):
		var av: Vector2i = a as Vector2i
		var bv: Vector2i = b as Vector2i
		if av.x != bv.x:
			return av.x < bv.x
		return av.y < bv.y)
	return out


# Nearest point (by Manhattan distance) in `points` to `origin`; stable
# tie-break by (x, y). Returns {} when the list is empty.
static func _nearest_point(origin: Vector2i, points: Array) -> Dictionary:
	var best: Dictionary = {}
	var best_d: int = -1
	var sorted: Array = points.duplicate(true)
	sorted.sort_custom(func(a, b):
		var ax: int = int((a as Dictionary).get("x", 0))
		var bx: int = int((b as Dictionary).get("x", 0))
		if ax != bx:
			return ax < bx
		return int((a as Dictionary).get("y", 0)) < int((b as Dictionary).get("y", 0)))
	for raw in sorted:
		var p: Dictionary = raw as Dictionary
		var d: int = abs(origin.x - int(p.get("x", 0))) + abs(origin.y - int(p.get("y", 0)))
		if best_d < 0 or d < best_d:
			best_d = d
			best = p
	return best
