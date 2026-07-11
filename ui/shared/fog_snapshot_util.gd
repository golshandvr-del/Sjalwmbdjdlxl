# fog_snapshot_util.gd
# ----------------------------------------------------------------------------
# Project Nexus - Fog "last-image" snapshot util (Phase MC2, request 2).
#
# The user asked for a THREE-state map:
#   * HIDDEN   -> solid black (never seen).
#   * VISIBLE  -> fully lit, live truth.
#   * EXPLORED -> dimmed, showing the LAST IMAGE the player saw (the enemy base
#                 as it looked when last in sight), NOT the live current state.
#
# Rendering the live enemy state on an EXPLORED tile would leak information the
# player should not have (e.g. that a building was destroyed after they lost
# sight of it). The correct RTS behaviour is a frozen "memory" of the last thing
# seen on each tile. This util maintains exactly that memory.
#
# COSMETIC / DETERMINISM: this snapshot is a pure RENDER aid. It is derived from
# the (already deterministic) fog grid + entity positions, but it is NEVER fed
# back into the simulation and NEVER touches the deterministic state hash. Two
# peers may keep different snapshots (they see different things) without breaking
# lockstep, because the snapshot only affects what is DRAWN, not what is
# simulated. It therefore lives in ui/shared (render side), not in modules/.
#
# It is a plain RefCounted with no SceneTree/autoload dependency so the memory
# logic (observe -> remember -> serve) is unit-testable headlessly.
#
# CODE LANGUAGE POLICY: English-only identifiers/comments (ASCII).
# ----------------------------------------------------------------------------
class_name FogSnapshotUtil
extends RefCounted

# Fog cell states (kept identical to FogOfWarModule / RenderAdapter).
const FOG_HIDDEN: int = 0
const FOG_EXPLORED: int = 1
const FOG_VISIBLE: int = 2

# Remembered entity kinds stored per tile.
const KIND_NONE: String = "none"
const KIND_BUILDING: String = "building"
const KIND_UNIT: String = "unit"

# Per-tile memory: tile_key ("x,y") -> Dictionary {kind, owner, type}. Only tiles
# the viewer has ever seen an entity on are stored; empty seen tiles are pruned
# so a razed building's stale image does not linger once its tile is re-seen
# empty.
var _memory: Dictionary = {}


# Build a stable string key for a tile.
static func tile_key(x: int, y: int) -> String:
	return "%d,%d" % [x, y]


# Ingest one render frame: for every tile currently VISIBLE to `viewer`, refresh
# the memory to the entity now standing there (or clear it when the tile is seen
# empty). Tiles that are HIDDEN or EXPLORED are left untouched so their last
# image is preserved.
#
# `fog_section` is the world "fog" section: { width, height, visible: { "<viewer>": [ints] } }.
# `buildings` / `units` are the section "list" dictionaries (id -> entity).
func observe(viewer: int, fog_section: Dictionary, buildings: Dictionary, units: Dictionary) -> void:
	var w: int = int(fog_section.get("width", 0))
	var h: int = int(fog_section.get("height", 0))
	if w <= 0 or h <= 0:
		return
	var grid: Array = fog_section.get("visible", {}).get(str(viewer), [])
	if grid.size() != w * h:
		return
	# Index the entities that occupy each tile (buildings take precedence over
	# units so a base image is remembered rather than a passing scout).
	var occupied: Dictionary = _index_entities(buildings, units)
	for y in range(h):
		for x in range(w):
			if int(grid[y * w + x]) != FOG_VISIBLE:
				continue
			var key: String = tile_key(x, y)
			if occupied.has(key):
				_memory[key] = occupied[key]
			else:
				# Seen empty now -> forget any stale image on this tile.
				_memory.erase(key)


# Return the remembered entity descriptor for a tile, or an empty Dictionary if
# nothing was ever seen there. Callers use this to draw the dimmed "last image"
# on EXPLORED tiles.
func remembered(x: int, y: int) -> Dictionary:
	var key: String = tile_key(x, y)
	if _memory.has(key):
		return (_memory[key] as Dictionary).duplicate()
	return {}


func has_memory(x: int, y: int) -> bool:
	return _memory.has(tile_key(x, y))


# Resolve what to draw for a tile given its current fog state:
#   VISIBLE  -> { "layer": "visible" }              (draw live, no dim)
#   HIDDEN   -> { "layer": "hidden" }               (solid black cover)
#   EXPLORED -> { "layer": "explored", "memory": {...} } (dimmed last image)
# This keeps the render-layer decision in one tested place.
func layer_for(state: int, x: int, y: int) -> Dictionary:
	if state == FOG_VISIBLE:
		return { "layer": "visible" }
	if state == FOG_HIDDEN:
		return { "layer": "hidden" }
	return { "layer": "explored", "memory": remembered(x, y) }


func clear() -> void:
	_memory.clear()


func size() -> int:
	return _memory.size()


# --- internals --------------------------------------------------------------

# Map "x,y" -> descriptor for the top entity on each tile. Buildings win over
# units on the same tile so the remembered image is the more permanent one.
static func _index_entities(buildings: Dictionary, units: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for uk in units.keys():
		var u: Dictionary = units[uk]
		var key: String = tile_key(int(u.get("x", 0)), int(u.get("y", 0)))
		out[key] = {
			"kind": KIND_UNIT,
			"owner": int(u.get("owner", -1)),
			"type": str(u.get("type", u.get("unit_type", ""))),
		}
	for bk in buildings.keys():
		var b: Dictionary = buildings[bk]
		var key2: String = tile_key(int(b.get("x", 0)), int(b.get("y", 0)))
		out[key2] = {
			"kind": KIND_BUILDING,
			"owner": int(b.get("owner", -1)),
			"type": str(b.get("type", b.get("building_type", ""))),
		}
	return out
