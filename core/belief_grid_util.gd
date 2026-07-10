# belief_grid_util.gd
# ----------------------------------------------------------------------------
# Project Nexus - Belief Grid Util (Phase MC1, request 1).
#
# Pure, deterministic helper that builds a player's "belief grid" from the real
# map grid plus that player's fog-of-war visibility grid. This resolves the
# fog/pathfinding contradiction the user reported: units must NOT pathfind using
# knowledge of walls they have never discovered (that is effectively cheating).
#
# Belief rule (per tile):
#   - VISIBLE / EXPLORED tile  -> use its REAL value (the player has seen it).
#   - HIDDEN   tile            -> ASSUME walkable (GROUND). The player has no
#                                 knowledge there, so they plan optimistically
#                                 and only discover obstacles by walking into
#                                 sight of them (see units_module replan-on-
#                                 contact in MC1.3).
#
# Determinism: the belief grid is a pure function of (map tiles, fog grid), both
# of which are already deterministic in the sim. Feeding it to the existing
# deterministic PathService keeps pathfinding (and any replan) fully lockstep-
# safe: every peer derives the same belief grid and therefore the same path.
#
# This is intentionally NOT a module: it holds no state and touches no
# WorldState. Callers pass snapshots so the same inputs always produce the same
# output (unit-testable headlessly).
#
# CODE LANGUAGE POLICY: English-only identifiers/comments.
# ----------------------------------------------------------------------------
class_name BeliefGridUtil
extends RefCounted

# Grid encoding matches MapModule / PathService: 0 == walkable ground; anything
# else == blocked. Index = y * width + x.
const GROUND: int = 0

# Fog cell states (kept identical to FogUtil / FogOfWarModule).
const FOG_HIDDEN: int = 0
const FOG_EXPLORED: int = 1
const FOG_VISIBLE: int = 2


# Build a belief grid (flat Array of ints, length width*height) for `viewer`.
#
#   width, height : map dimensions.
#   tiles         : the REAL map grid (flat Array, index = y*width + x).
#   fog           : the WorldState "fog" section dictionary (as read by FogUtil).
#   viewer        : the player whose knowledge we model. When viewer < 0 fog is
#                   disabled and the real grid is returned verbatim (full
#                   knowledge -- e.g. a spectator / no-fog match).
#
# Returns a NEW array (never mutates `tiles`). On malformed input returns an
# all-ground grid of the requested size so callers never crash.
static func build_belief_grid(width: int, height: int, tiles: Array, fog: Dictionary, viewer: int) -> Array:
	var out: Array = []
	if width <= 0 or height <= 0:
		return out
	out.resize(width * height)
	for i in range(out.size()):
		out[i] = GROUND
	# viewer < 0 -> no fog: mirror the real grid (clamped to size).
	if viewer < 0:
		for i in range(out.size()):
			out[i] = int(tiles[i]) if i < tiles.size() else GROUND
		return out
	for y in range(height):
		for x in range(width):
			var idx: int = y * width + x
			var state: int = _fog_state(fog, viewer, x, y, width, height)
			if state == FOG_HIDDEN:
				# Unknown territory: assume walkable so the plan is optimistic.
				out[idx] = GROUND
			else:
				# Seen at least once: trust the real value.
				out[idx] = int(tiles[idx]) if idx < tiles.size() else GROUND
	return out


# Is tile (x,y) known-blocked in the viewer's belief (i.e. seen AND blocked)?
# A HIDDEN tile is never "known blocked" (the player does not know yet).
static func is_known_blocked(width: int, height: int, tiles: Array, fog: Dictionary, viewer: int, x: int, y: int) -> bool:
	if width <= 0 or height <= 0 or x < 0 or y < 0 or x >= width or y >= height:
		return true
	var state: int = _fog_state(fog, viewer, x, y, width, height) if viewer >= 0 else FOG_VISIBLE
	if state == FOG_HIDDEN:
		return false
	var idx: int = y * width + x
	if idx < 0 or idx >= tiles.size():
		return false
	return int(tiles[idx]) != GROUND


# --- Internals --------------------------------------------------------------

# Read a viewer's fog state at (x,y) from the fog section. Mirrors FogUtil but is
# inlined here so BeliefGridUtil stays dependency-free (loadable on its own).
static func _fog_state(fog: Dictionary, viewer: int, x: int, y: int, width: int, height: int) -> int:
	if x < 0 or y < 0 or x >= width or y >= height:
		return FOG_HIDDEN
	var grid: Array = fog.get("visible", {}).get(str(viewer), [])
	var idx: int = y * width + x
	if idx < 0 or idx >= grid.size():
		return FOG_HIDDEN
	return int(grid[idx])
