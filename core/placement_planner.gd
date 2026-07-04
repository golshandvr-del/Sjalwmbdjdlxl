# placement_planner.gd
# ----------------------------------------------------------------------------
# Project Nexus - Placement Planner (Phase P7, R10.1 / R10.2 / R10.4).
#
# A pure, deterministic helper that decides WHERE each player's HQ (and, for
# CTF, each flag) starts on a map. It is used at match start when the chosen
# scenario does NOT already ship fixed placements for the requested number of
# players, and to auto-fill the surplus when the user only assigned some of
# them manually (R10.4).
#
# GOLDEN RULES honoured here:
#   * Determinism (rule 7): every decision comes from sorted keys + the map
#     geometry + the given seed only -- never from system RNG or real time. Two
#     machines fed the same inputs produce byte-identical placements, so this is
#     lockstep-safe.
#   * Logic-only, no side effects: this class returns plain data; it never
#     touches WorldState, modules, or the deterministic hash directly. The
#     caller (ScenarioLoader / GameBootstrap) applies the result.
#
# The planner is intentionally engine-light: it takes primitive descriptions of
# the map (width/height + a "blocked(x,y)" predicate) so it can be unit-tested
# headlessly without a live MapModule.
#
# CODE LANGUAGE POLICY: English-only identifiers/comments.
# ----------------------------------------------------------------------------
class_name PlacementPlanner
extends RefCounted

# Layout strategies (R10.2). "clustered" seats teammates near one another (good
# for team modes); "random" spreads everyone deterministically around the map.
const LAYOUT_CLUSTERED: String = "clustered"
const LAYOUT_RANDOM: String = "random"

# How far from the map edge a base is nudged, so an HQ is never jammed into a
# corner wall. Kept small; clamped to the map anyway.
const EDGE_MARGIN: int = 2


# Plan HQ positions for `slots`, an ordered Array of player descriptors, each a
# Dictionary carrying at least { "owner": int, "team": int }. Returns an Array
# (parallel to a stable, sorted view of `slots`) of:
#     { "owner": int, "team": int, "x": int, "y": int }
#
# `is_blocked` is an optional Callable(x, y) -> bool returning true for a cell a
# base may NOT sit on (a wall, sea, or an already-taken cell). When omitted,
# every in-bounds cell is considered free.
#
# The algorithm:
#   1) Sort slots by owner (determinism).
#   2) Build an ORDERED ring of candidate anchor points around the map with as
#      many stops as there are teams (clustered) or players (random).
#   3) Seat each slot at its team's anchor (clustered) or its own anchor
#      (random), then spiral out to the nearest free cell if the anchor is
#      blocked or already used.
static func plan_hqs(
		width: int,
		height: int,
		slots: Array,
		layout: String = LAYOUT_CLUSTERED,
		_seed: int = 0,
		is_blocked: Callable = Callable()) -> Array:
	var ordered: Array = slots.duplicate(true)
	ordered.sort_custom(func(a, b): return int(a.get("owner", 0)) < int(b.get("owner", 0)))

	# Determine the distinct teams in a stable, sorted order.
	var team_list: Array = []
	for s in ordered:
		var t: int = int(s.get("team", int(s.get("owner", 0))))
		if not team_list.has(t):
			team_list.append(t)
	team_list.sort()

	var used: Dictionary = {}   # "x,y" -> true (cells already claimed here)
	var out: Array = []

	if layout == LAYOUT_RANDOM:
		# One anchor per player, spread evenly around the perimeter ring, but
		# shuffled by a deterministic seed-derived permutation so it is not a
		# trivially predictable clockwise order.
		var anchors: Array = _ring_anchors(width, height, ordered.size())
		var order: Array = _seeded_order(ordered.size(), _seed)
		for i in range(ordered.size()):
			var slot: Dictionary = ordered[i]
			var anchor: Vector2i = anchors[int(order[i]) % anchors.size()]
			var cell: Vector2i = _nearest_free(width, height, anchor, used, is_blocked)
			used["%d,%d" % [cell.x, cell.y]] = true
			out.append({ "owner": int(slot.get("owner", 0)), "team": int(slot.get("team", int(slot.get("owner", 0)))), "x": cell.x, "y": cell.y })
		return out

	# CLUSTERED (default): one anchor per team; teammates seat in a small cluster
	# around their team anchor.
	var team_anchors: Dictionary = {}
	var t_anchors: Array = _ring_anchors(width, height, max(1, team_list.size()))
	for ti in range(team_list.size()):
		team_anchors[team_list[ti]] = t_anchors[ti]

	for slot in ordered:
		var team: int = int(slot.get("team", int(slot.get("owner", 0))))
		var anchor2: Vector2i = team_anchors.get(team, Vector2i(int(width / 2), int(height / 2)))
		var cell2: Vector2i = _nearest_free(width, height, anchor2, used, is_blocked)
		used["%d,%d" % [cell2.x, cell2.y]] = true
		out.append({ "owner": int(slot.get("owner", 0)), "team": team, "x": cell2.x, "y": cell2.y })
	return out


# Plan `count` flag positions for CTF (R10.5 fallback / auto-fill). Flags are
# spread on the ring just like random anchors so they are spatially fair, then
# nudged to the nearest free cell. Returns an Array of { "index": int, "x", "y" }.
static func plan_flags(
		width: int,
		height: int,
		count: int,
		_seed: int = 0,
		is_blocked: Callable = Callable()) -> Array:
	var anchors: Array = _ring_anchors(width, height, max(1, count))
	var used: Dictionary = {}
	var out: Array = []
	for i in range(count):
		var anchor: Vector2i = anchors[i % anchors.size()]
		var cell: Vector2i = _nearest_free(width, height, anchor, used, is_blocked)
		used["%d,%d" % [cell.x, cell.y]] = true
		out.append({ "index": i, "x": cell.x, "y": cell.y })
	return out


# --- Internals --------------------------------------------------------------

# Build `n` evenly spaced anchor points on the perimeter ring (inset by
# EDGE_MARGIN), in a deterministic clockwise order starting from the left edge.
static func _ring_anchors(width: int, height: int, n: int) -> Array:
	var out: Array = []
	if n <= 0:
		return out
	var left: int = clampi(EDGE_MARGIN, 0, max(0, width - 1))
	var right: int = clampi(width - 1 - EDGE_MARGIN, 0, max(0, width - 1))
	var top: int = clampi(EDGE_MARGIN, 0, max(0, height - 1))
	var bottom: int = clampi(height - 1 - EDGE_MARGIN, 0, max(0, height - 1))
	# Special small-count layouts read better than a raw perimeter walk.
	if n == 1:
		return [Vector2i(int(width / 2), int(height / 2))]
	if n == 2:
		return [Vector2i(left, int(height / 2)), Vector2i(right, int(height / 2))]
	if n <= 4:
		var corners: Array = [
			Vector2i(left, top), Vector2i(right, bottom),
			Vector2i(right, top), Vector2i(left, bottom),
		]
		return corners.slice(0, n)
	# General case: walk the perimeter and sample n points evenly.
	var perimeter: Array = _perimeter_cells(left, top, right, bottom)
	if perimeter.is_empty():
		perimeter = [Vector2i(int(width / 2), int(height / 2))]
	for i in range(n):
		var idx: int = int(round(float(i) * float(perimeter.size()) / float(n))) % perimeter.size()
		out.append(perimeter[idx])
	return out


# Ordered list of the rectangle's border cells (clockwise from top-left).
static func _perimeter_cells(left: int, top: int, right: int, bottom: int) -> Array:
	var out: Array = []
	if right < left or bottom < top:
		return out
	for x in range(left, right + 1):
		out.append(Vector2i(x, top))
	for y in range(top + 1, bottom + 1):
		out.append(Vector2i(right, y))
	for x in range(right - 1, left - 1, -1):
		out.append(Vector2i(x, bottom))
	for y in range(bottom - 1, top, -1):
		out.append(Vector2i(left, y))
	return out


# A deterministic permutation of [0, n) derived from `seed` (no system RNG). Uses
# a simple FNV-derived key per index, then sorts by that key -- stable & portable.
static func _seeded_order(n: int, seed_value: int) -> Array:
	var keyed: Array = []
	for i in range(n):
		var h: int = _mix(seed_value, i)
		keyed.append({ "i": i, "k": h })
	keyed.sort_custom(func(a, b):
		if int(a["k"]) == int(b["k"]):
			return int(a["i"]) < int(b["i"])
		return int(a["k"]) < int(b["k"]))
	var out: Array = []
	for e in keyed:
		out.append(int(e["i"]))
	return out


# Small integer mix (FNV-1a style, 32-bit wrap) for deterministic ordering.
static func _mix(a: int, b: int) -> int:
	var h: int = 2166136261
	for v in [a, b]:
		h = (h ^ (v & 0xffffffff)) & 0xffffffff
		h = (h * 16777619) & 0xffffffff
	return h


# Spiral outward from `origin` (clamped in-bounds) to the nearest cell that is
# neither already used here nor rejected by `is_blocked`. Deterministic BFS-ish
# ring expansion. Falls back to the origin if nothing is free (never returns
# out-of-bounds).
static func _nearest_free(width: int, height: int, origin: Vector2i, used: Dictionary, is_blocked: Callable) -> Vector2i:
	var start: Vector2i = Vector2i(clampi(origin.x, 0, max(0, width - 1)), clampi(origin.y, 0, max(0, height - 1)))
	var max_radius: int = width + height
	for radius in range(0, max_radius + 1):
		# Collect every cell at Chebyshev distance == radius, in a deterministic
		# order (row-major over the ring's bounding box, filtered to the ring).
		var candidates: Array = []
		var x0: int = start.x - radius
		var x1: int = start.x + radius
		var y0: int = start.y - radius
		var y1: int = start.y + radius
		for yy in range(y0, y1 + 1):
			for xx in range(x0, x1 + 1):
				var on_ring: bool = (xx == x0 or xx == x1 or yy == y0 or yy == y1)
				if not on_ring:
					continue
				if xx < 0 or yy < 0 or xx >= width or yy >= height:
					continue
				candidates.append(Vector2i(xx, yy))
		for c in candidates:
			var key: String = "%d,%d" % [c.x, c.y]
			if used.has(key):
				continue
			if is_blocked.is_valid() and bool(is_blocked.call(c.x, c.y)):
				continue
			return c
	return start
