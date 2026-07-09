# formation_util.gd
# ----------------------------------------------------------------------------
# Project Nexus - Shared multi-unit FORMATION helper (Phase MB1.3).
#
# Pure, dependency-free geometry that spreads a group of units ordered to the
# SAME tile onto distinct, walkable destination tiles clustered around the
# requested goal -- so units never stack on one block (the reported Android
# bug 2). Kept OUT of the units module (which needs the Nexus autoload + live
# WorldState) so it can be unit-tested headlessly.
#
# WHY A SHARED SET OF ALREADY-RESERVED TILES?
#   The MA1 fix already spread a SINGLE move command into a formation. But in
#   PAUSE the player queues several SEPARATE one-unit move commands all aimed at
#   the same tile X; each command independently picked X, so the units still
#   stacked. The fix: the caller passes the tiles already claimed by OTHER units'
#   pending move goals as `reserved`, and the ring-out skips them. That makes
#   destinations unique ACROSS independent commands too.
#
# DETERMINISM
#   The BFS expands with a fixed 4-neighbour order (N, E, S, W) and sorts each
#   ring by (y, x), so every lockstep peer computes byte-identical destinations.
#
# Logic/Render Separation: nothing here mutates WorldState; the caller writes the
# returned tiles onto units' paths/goals through the normal command flow.
# ----------------------------------------------------------------------------
class_name FormationUtil
extends RefCounted


# Stable 4-neighbour expansion order (N, E, S, W).
const OFFSETS: Array = [
	Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0),
]


# Encode a tile as a stable dictionary key.
static func key(tile: Vector2i) -> String:
	return "%d,%d" % [tile.x, tile.y]


# Pick `count` UNIQUE destination tiles clustered around `center`.
#
#   - `is_walkable`   : Callable(int x, int y) -> bool. Tiles failing this are
#                       never chosen (walls / off-map / buildings).
#   - `reserved`      : Dictionary used as a set of "x,y" -> true for tiles that
#                       are ALREADY claimed by other units (their pending move
#                       goals). These are skipped so destinations stay unique
#                       across independent commands (the pause-stacking fix).
#
# Returns a list of Vector2i of length `count`. If the map cannot supply enough
# unique tiles it pads with `center` (rare; tiny/blocked maps) so the caller
# always receives exactly `count` entries. A single unit (count == 1) keeps the
# exact requested tile ONLY when it is free; otherwise it too gets the nearest
# free tile so two separate single-unit orders to one tile don't collide.
static func plan_goals(center: Vector2i, count: int, is_walkable: Callable, reserved: Dictionary = {}) -> Array:
	var goals: Array = []
	if count <= 0:
		return goals
	var taken: Dictionary = {}
	var visited: Dictionary = {}
	var frontier: Array = [center]
	visited[key(center)] = true
	var guard: int = 0
	while goals.size() < count and not frontier.is_empty() and guard < 8192:
		guard += 1
		var next_frontier: Array = []
		for tile in frontier:
			var tk: String = key(tile)
			if is_walkable.call(tile.x, tile.y) and not taken.has(tk) and not reserved.has(tk):
				taken[tk] = true
				goals.append(tile)
				if goals.size() >= count:
					break
			for off in OFFSETS:
				var n: Vector2i = tile + off
				var nk: String = key(n)
				if visited.has(nk):
					continue
				visited[nk] = true
				next_frontier.append(n)
		# Sort the next ring by (y, x) so the fill order is stable + predictable.
		next_frontier.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			if a.y != b.y:
				return a.y < b.y
			return a.x < b.x)
		frontier = next_frontier
	# Pad if the map ran out of unique tiles (very small / heavily blocked maps).
	while goals.size() < count:
		goals.append(center)
	return goals
