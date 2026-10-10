# map_module.gd
# ----------------------------------------------------------------------------
# Project Nexus - Map Module (Phase 1, steps 1.1 + 1.2).
#
# Owns the battlefield grid and pathfinding. Like every gameplay module it
# depends ONLY on the core (Nexus): it stores all of its data inside the
# WorldState section "map" and never references another module directly.
#
# Grid model:
#   - width x height tiles, each tile has a terrain type and a passable flag.
#   - Tiles are addressed by (x, y) with x in [0, width) and y in [0, height).
#   - A tile index is encoded as (y * width + x) so the grid stays a flat,
#     fully serializable Array (determinism + save/load friendly).
#
# Pathfinding:
#   - Deterministic A* on the 4-neighbour grid (no diagonal movement in the
#     simple Phase 1 style; can be extended later without touching the core).
#   - Tie-breaking is fully deterministic (by encoded tile index) so the same
#     seed/map always yields the same path -> ready for lockstep multiplayer.
#
# CODE LANGUAGE POLICY: English-only identifiers/comments.
# ----------------------------------------------------------------------------
class_name MapModule
extends IModule

const SECTION: String = "map"

# Terrain ids (English string constants stored as ints in the grid for speed).
const TERRAIN_GROUND: int = 0
const TERRAIN_WALL: int = 1
const TERRAIN_WATER: int = 2
# T006 WP1: forest. Not walkable and not buildable (like rock/wall), but it is a
# distinct terrain id so the renderer/minimap can draw real tree art.
const TERRAIN_FOREST: int = 3

# Default grid dimensions if no scenario configures the map.
var _width: int = 0
var _height: int = 0

# Flat terrain array of length width*height (ints, see TERRAIN_*).
var _tiles: PackedInt32Array = PackedInt32Array()


func module_id() -> String:
	return "map"


func init(p_nexus: Object) -> void:
	super.init(p_nexus)
	# A scenario loader will call configure(); we still publish an empty section
	# so other modules can rely on it always existing.
	_write_state()


# --- Public construction API (called by scenario / map generators) ----------

# Create an all-ground grid of the given size.
func create_grid(width: int, height: int) -> void:
	_width = max(1, width)
	_height = max(1, height)
	_tiles = PackedInt32Array()
	_tiles.resize(_width * _height)
	for i in range(_tiles.size()):
		_tiles[i] = TERRAIN_GROUND
	_write_state()


func width() -> int:
	return _width


func height() -> int:
	return _height


func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < _width and y < _height


func tile_index(x: int, y: int) -> int:
	return y * _width + x


func get_terrain(x: int, y: int) -> int:
	if not in_bounds(x, y):
		return TERRAIN_WALL
	return _tiles[tile_index(x, y)]


func set_terrain(x: int, y: int, terrain: int) -> void:
	if not in_bounds(x, y):
		return
	_tiles[tile_index(x, y)] = terrain
	_write_state()


# A tile is walkable if it is in bounds and is ground.
func is_walkable(x: int, y: int) -> bool:
	return in_bounds(x, y) and _tiles[tile_index(x, y)] == TERRAIN_GROUND


# --- Pathfinding (deterministic A*, 4-neighbour) ----------------------------

# Returns an Array of Vector2i tiles from start to goal (inclusive), or an
# empty Array if no path exists. Delegates to the shared, stateless
# PathService so that EVERY consumer (Units, AI, etc.) gets an identical,
# deterministic result from the same grid snapshot.
func find_path(start: Vector2i, goal: Vector2i) -> Array:
	return PathService.find_path(_width, _height, _tiles_to_array(), start, goal)


# --- World state mirroring + save/load --------------------------------------

func _write_state() -> void:
	if nexus == null:
		return
	var section: Dictionary = nexus.world_state.get_section(SECTION)
	section["width"] = _width
	section["height"] = _height
	section["tiles"] = _tiles_to_array()


func _tiles_to_array() -> Array:
	var out: Array = []
	out.resize(_tiles.size())
	for i in range(_tiles.size()):
		out[i] = _tiles[i]
	return out


func serialize() -> Dictionary:
	return {
		"width": _width,
		"height": _height,
		"tiles": _tiles_to_array(),
	}


func deserialize(data: Dictionary) -> void:
	_width = int(data.get("width", 0))
	_height = int(data.get("height", 0))
	var tiles: Variant = data.get("tiles", [])
	_tiles = PackedInt32Array()
	if tiles is Array:
		_tiles.resize((tiles as Array).size())
		for i in range((tiles as Array).size()):
			_tiles[i] = int((tiles as Array)[i])
	_write_state()


func shutdown() -> void:
	if nexus != null:
		nexus.event_bus.unsubscribe_all(self)
