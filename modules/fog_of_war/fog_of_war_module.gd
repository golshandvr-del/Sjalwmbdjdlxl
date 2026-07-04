# fog_of_war_module.gd
# ----------------------------------------------------------------------------
# Project Nexus - Fog of War Module (Phase 2, steps 2.6 + 2.7).
#
# Maintains a per-player visibility grid over the map. Each tick (throttled) it
# recomputes, for every registered "viewer" player, which tiles are currently
# VISIBLE (an owned unit/building sees them) and which are EXPLORED (seen at
# least once). The RenderAdapter reads this section to dim/hide enemy entities
# in unseen tiles (step 2.7) without the fog module knowing anything about
# rendering.
#
# Visibility model (deterministic):
#   - state per tile: 0 = hidden (never seen), 1 = explored (seen before, not
#     now), 2 = visible (in sight this tick).
#   - A unit reveals all tiles within Manhattan distance <= vision_range.
#   - Recompute every `refresh_interval` ticks for performance.
#
# Decoupling: depends ONLY on the core. Reads "map", "units", "buildings";
# owns the "fog" section; emits "fog.updated". Never references another module.
#
# fog section layout:
#   {
#     "viewers": Array[int],                         # players who own a fog map
#     "visible":  { owner(String) -> PackedByteArray-like Array of tile states },
#     "width": int, "height": int
#   }
#
# CODE LANGUAGE POLICY: English-only identifiers/comments.
# ----------------------------------------------------------------------------
class_name FogOfWarModule
extends IModule

const SECTION: String = "fog"

const HIDDEN: int = 0
const EXPLORED: int = 1
const VISIBLE: int = 2

# Recompute fog every N ticks (visibility does not need per-tick precision).
const REFRESH_INTERVAL: int = 4

const EVENT_UPDATED: String = "fog.updated"


func module_id() -> String:
	return "fog_of_war"


func init(p_nexus: Object) -> void:
	super.init(p_nexus)
	_ensure_state()


func _ensure_state() -> void:
	var section: Dictionary = nexus.world_state.get_section(SECTION)
	if not section.has("viewers"):
		section["viewers"] = []
	if not section.has("visible"):
		section["visible"] = {}


# Register a player whose fog of war we track (usually the human players).
func register_viewer(owner: int) -> void:
	var section: Dictionary = nexus.world_state.get_section(SECTION)
	var viewers: Array = section.get("viewers", [])
	if not viewers.has(owner):
		viewers.append(owner)
	section["viewers"] = viewers


func on_tick(_delta_tick: int) -> void:
	var tick: int = int(nexus.world_state.current_tick)
	if tick % REFRESH_INTERVAL != 0:
		return
	_recompute()


func _recompute() -> void:
	var map_section: Dictionary = nexus.world_state.get_section("map")
	var w: int = int(map_section.get("width", 0))
	var h: int = int(map_section.get("height", 0))
	if w <= 0 or h <= 0:
		return
	var section: Dictionary = nexus.world_state.get_section(SECTION)
	section["width"] = w
	section["height"] = h
	var viewers: Array = section.get("viewers", [])
	var sorted_viewers: Array = viewers.duplicate()
	sorted_viewers.sort()
	for owner in sorted_viewers:
		_recompute_for(int(owner), w, h)
	nexus.emit_event(EVENT_UPDATED, { "tick": int(nexus.world_state.current_tick) })


func _recompute_for(owner: int, w: int, h: int) -> void:
	var section: Dictionary = nexus.world_state.get_section(SECTION)
	var visible_map: Dictionary = section["visible"]
	var grid: Array = visible_map.get(str(owner), [])
	if grid.size() != w * h:
		grid = []
		grid.resize(w * h)
		for i in range(grid.size()):
			grid[i] = HIDDEN
	# Demote any currently-visible tile to explored before re-revealing.
	for i in range(grid.size()):
		if int(grid[i]) == VISIBLE:
			grid[i] = EXPLORED

	# Reveal around each owned unit and building.
	_reveal_from(grid, w, h, owner, nexus.world_state.get_section("units").get("list", {}), "vision_range", 5)
	_reveal_from(grid, w, h, owner, nexus.world_state.get_section("buildings").get("list", {}), "vision_range", 8)

	visible_map[str(owner)] = grid


func _reveal_from(grid: Array, w: int, h: int, owner: int, entities: Dictionary, vision_key: String, default_vision: int) -> void:
	var keys: Array = entities.keys()
	keys.sort_custom(func(a, b): return int(a) < int(b))
	for key in keys:
		var e: Dictionary = entities[key]
		if int(e.get("owner", -1)) != owner:
			continue
		if int(e.get("health", 1)) <= 0:
			continue
		var ex: int = int(e.get("x", 0))
		var ey: int = int(e.get("y", 0))
		var vision: int = int(e.get(vision_key, default_vision))
		var min_y: int = max(0, ey - vision)
		var max_y: int = min(h - 1, ey + vision)
		for ty in range(min_y, max_y + 1):
			var dy: int = abs(ty - ey)
			var span: int = vision - dy
			if span < 0:
				continue
			var min_x: int = max(0, ex - span)
			var max_x: int = min(w - 1, ex + span)
			for tx in range(min_x, max_x + 1):
				grid[ty * w + tx] = VISIBLE


# --- Query API (used by the RenderAdapter, step 2.7) ------------------------

func tile_state(owner: int, x: int, y: int) -> int:
	var section: Dictionary = nexus.world_state.get_section(SECTION)
	var w: int = int(section.get("width", 0))
	var h: int = int(section.get("height", 0))
	if w <= 0 or x < 0 or y < 0 or x >= w or y >= h:
		return HIDDEN
	var grid: Array = section.get("visible", {}).get(str(owner), [])
	var idx: int = y * w + x
	if idx < 0 or idx >= grid.size():
		return HIDDEN
	return int(grid[idx])


func is_visible(owner: int, x: int, y: int) -> bool:
	return tile_state(owner, x, y) == VISIBLE


func is_explored(owner: int, x: int, y: int) -> bool:
	return tile_state(owner, x, y) >= EXPLORED


# --- Save / load ------------------------------------------------------------

func serialize() -> Dictionary:
	return {}


func deserialize(_data: Dictionary) -> void:
	pass


func shutdown() -> void:
	if nexus != null:
		nexus.event_bus.unsubscribe_all(self)
