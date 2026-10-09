# buildings_module.gd
# ----------------------------------------------------------------------------
# Project Nexus - Buildings Module (Phase 1, step 1.6).
#
# Owns all placed buildings (HQs, future production structures). Data-driven:
# building archetypes come from data/buildings/*.json. The first building each
# player places is normally an HQ.
#
# Responsibilities in Phase 1:
#   - Place a building on the grid (validated as walkable ground).
#   - Hold a per-building production queue for units (consumed by the Economy/
#     production loop on tick).
#   - Emit "buildings.placed" so the renderer and other modules can react.
#
# Decoupling: it never references other modules; everything goes through the
# WorldState section "buildings" and the event bus. Production of resources is
# handled by the Economy module which READS this section.
#
# Building instance (WorldState section "buildings" -> "list"):
#   {
#     "id": int, "type": String, "owner": int,
#     "x": int, "y": int, "health": int, "max_health": int,
#     "produces": Dictionary,            # resource_id -> amount per tick
#     "buildable_units": Array[String],
#     "build_queue": Array[ { "type": String, "remaining": int } ]
#   }
#
# CODE LANGUAGE POLICY: English-only identifiers/comments.
# ----------------------------------------------------------------------------
class_name BuildingsModule
extends IModule

const SECTION: String = "buildings"
const CATALOG: String = "buildings"

const CMD_PLACE: String = "command.place_building"
const CMD_QUEUE_UNIT: String = "command.queue_unit"
# Phase 2: player-driven construction (paid + timed) and upgrades.
const CMD_BUILD_BUILDING: String = "command.build_building"
const CMD_FINISH_BUILDING: String = "command.finish_building"
const CMD_UPGRADE: String = "command.upgrade_building"
# P0.2 (BUG-2): set a building's rally point so freshly produced units gather
# there instead of stacking next to the building.
const CMD_SET_RALLY: String = "command.set_rally_point"

const EVENT_PLACED: String = "buildings.placed"
const EVENT_UNIT_READY: String = "buildings.unit_ready"
const EVENT_DESTROYED: String = "buildings.destroyed"
const EVENT_UPGRADED: String = "buildings.upgraded"
const EVENT_BUILD_REJECTED: String = "buildings.build_rejected"

# Building ids live in a high, non-overlapping range so that entity ids are
# globally unique across units and buildings (combat targeting relies on this).
const BUILDING_ID_BASE: int = 1000000
var _next_building_id: int = BUILDING_ID_BASE


func module_id() -> String:
	return "buildings"


func init(p_nexus: Object) -> void:
	super.init(p_nexus)
	nexus.subscribe(CMD_PLACE, self, "_on_bus_event")
	nexus.subscribe(CMD_QUEUE_UNIT, self, "_on_bus_event")
	nexus.subscribe(CMD_BUILD_BUILDING, self, "_on_bus_event")
	nexus.subscribe(CMD_FINISH_BUILDING, self, "_on_bus_event")
	nexus.subscribe(CMD_UPGRADE, self, "_on_bus_event")
	nexus.subscribe(CMD_SET_RALLY, self, "_on_bus_event")
	# BUG-G3 (gameplay audit): CombatModule only EMITS buildings.destroyed when a
	# building's health reaches zero -- nothing ever removed the corpse. The dead
	# building kept producing resources, occupying its tile, and rendering. We now
	# own the removal: listen for the event and erase the entry.
	nexus.subscribe(EVENT_DESTROYED, self, "_on_bus_event")
	_ensure_state()


func _ensure_state() -> void:
	var section: Dictionary = nexus.world_state.get_section(SECTION)
	if not section.has("list"):
		section["list"] = {}


# --- Placement --------------------------------------------------------------

# Place a fully-built building instantly (used by scenario setup and as the
# final step of timed construction). `construction` true means it begins as a
# zero-progress site that finishes via the build queue instead.
func place_building(type: String, owner: int, x: int, y: int) -> int:
	var archetype: Variant = nexus.data_loader.get_entry(CATALOG, type)
	var stats: Dictionary = {}
	var produces: Dictionary = {}
	var buildable: Array = []
	var territory_radius: int = 0
	if archetype is Dictionary:
		var a: Dictionary = archetype
		stats = a.get("stats", {})
		produces = a.get("produces", {})
		buildable = a.get("buildable_units", [])
		territory_radius = int(a.get("territory_radius", 0))
	var building_id: int = _next_building_id
	_next_building_id += 1
	var building: Dictionary = {
		"id": building_id,
		"type": type,
		"owner": owner,
		"x": x,
		"y": y,
		"health": int(stats.get("health", 500)),
		"max_health": int(stats.get("health", 500)),
		"produces": produces.duplicate(true),
		"buildable_units": buildable.duplicate(),
		"build_queue": [],
		# Phase 2: HQ/outpost upgrade level (1-based) and owned territory radius.
		"level": 1,
		"territory_radius": territory_radius,
		# When > 0, the building is still being constructed and does not yet
		# produce or fight; counted down by the build queue tick.
		"construction_remaining": 0,
	}
	# T006 WP1: defensive buildings (attack_damage > 0) carry the extra combat
	# fields. Non-attacking buildings keep EXACTLY the 13 keys above (check C18).
	if int(stats.get("attack_damage", 0)) > 0:
		building["attack_damage"] = int(stats.get("attack_damage", 0))
		building["attack_range"] = int(stats.get("attack_range", 1))
		building["attack_cooldown_ticks"] = max(1, int((archetype as Dictionary).get("attack_cooldown_ticks", 10)))
		building["attack_cooldown"] = 0
	_buildings()[str(building_id)] = building
	nexus.emit_event(EVENT_PLACED, { "id": building_id, "owner": owner, "type": type, "x": x, "y": y })
	return building_id


# Player-driven construction (Phase 2.4): pay the cost via Economy, then place
# the building as a construction site that finishes after build_time_ticks.
func build_building(type: String, owner: int, x: int, y: int) -> int:
	var archetype: Variant = nexus.data_loader.get_entry(CATALOG, type)
	if not (archetype is Dictionary):
		nexus.emit_event(EVENT_BUILD_REJECTED, { "owner": owner, "reason": "unknown_building" })
		return -1
	var a: Dictionary = archetype
	# T006 WP1: prerequisite gate -- checked BEFORE spending/placing so a
	# rejection costs nothing and places nothing (checks C11, C12).
	var missing: Array = _missing_prereqs(a, owner)
	if not missing.is_empty():
		nexus.emit_event(EVENT_BUILD_REJECTED, { "owner": owner, "reason": "missing_prerequisite", "type": type, "missing": missing })
		return -1
	# Tile must be free and walkable (read map straight from world state).
	if not _tile_free_for_build(x, y):
		nexus.emit_event(EVENT_BUILD_REJECTED, { "owner": owner, "reason": "tile_blocked" })
		return -1
	var cost: Dictionary = a.get("cost", {})
	var economy: Object = nexus.get_module("economy")
	if economy != null and not cost.is_empty():
		if not economy.try_spend(owner, cost):
			nexus.emit_event(EVENT_BUILD_REJECTED, { "owner": owner, "reason": "insufficient_resources" })
			return -1
	var building_id: int = place_building(type, owner, x, y)
	var build_time: int = int(a.get("build_time_ticks", 0))
	if build_time > 0:
		var b: Dictionary = get_building(building_id)
		b["construction_remaining"] = build_time
	return building_id


# Queue a unit for production at a building. The Economy module checks cost;
# here we only enqueue if the building is allowed to build that unit type.
func queue_unit(building_id: int, unit_type: String, build_time_ticks: int) -> bool:
	var key: String = str(building_id)
	if not _buildings().has(key):
		return false
	var building: Dictionary = _buildings()[key]
	if not (building["buildable_units"] as Array).has(unit_type):
		return false
	(building["build_queue"] as Array).append({ "type": unit_type, "remaining": max(1, build_time_ticks) })
	return true


# --- Per-tick production countdown ------------------------------------------

func on_tick(_delta_tick: int) -> void:
	var list: Dictionary = _buildings()
	var keys: Array = list.keys()
	keys.sort()
	for key in keys:
		# BUG-G3 guard: an entry can be erased mid-loop (synchronous
		# buildings.destroyed handling); never touch a removed key.
		if not list.has(key):
			continue
		var building: Dictionary = list[key]
		_advance_construction(building)
		# A building still under construction cannot produce units yet.
		if int(building.get("construction_remaining", 0)) <= 0:
			_advance_build_queue(building)
			_advance_upgrade(building)


# Count down a construction site; when finished it becomes operational.
func _advance_construction(building: Dictionary) -> void:
	var remaining: int = int(building.get("construction_remaining", 0))
	if remaining <= 0:
		return
	remaining -= 1
	building["construction_remaining"] = remaining
	if remaining <= 0:
		nexus.emit_event(EVENT_PLACED, {
			"id": int(building["id"]), "owner": int(building["owner"]),
			"type": str(building["type"]), "x": int(building["x"]), "y": int(building["y"]),
			"completed": true,
		})


# Count down an in-progress HQ/outpost upgrade and apply its effects on finish.
func _advance_upgrade(building: Dictionary) -> void:
	var up: Dictionary = building.get("upgrade_in_progress", {})
	if up.is_empty():
		return
	up["remaining"] = int(up.get("remaining", 0)) - 1
	if int(up["remaining"]) <= 0:
		_apply_upgrade_effects(building, up.get("effects", {}), str(up.get("level_key", "")))
		building.erase("upgrade_in_progress")
	else:
		building["upgrade_in_progress"] = up


func _advance_build_queue(building: Dictionary) -> void:
	var queue: Array = building.get("build_queue", [])
	if queue.is_empty():
		return
	var head: Dictionary = queue[0]
	head["remaining"] = int(head["remaining"]) - 1
	if int(head["remaining"]) <= 0:
		queue.remove_at(0)
		# BUG-2 fix (P0.2): never spawn ON the building tile (units used to stack
		# on the HQ). Find the nearest free, walkable, unoccupied tile around the
		# building via a deterministic BFS, spawn there, and -- if a rally point
		# is set -- immediately order the fresh unit to move to it.
		var spawn_tile: Vector2i = find_free_spawn_tile(building)
		nexus.issue_command("spawn_unit", int(building["owner"]), {
			"type": str(head["type"]),
			"owner": int(building["owner"]),
			"x": spawn_tile.x,
			"y": spawn_tile.y,
			# The Units module moves the fresh unit here on spawn when present.
			"rally_point": building.get("rally_point", null),
		}, 1)
		nexus.emit_event(EVENT_UNIT_READY, { "building_id": int(building["id"]), "type": str(head["type"]) })
	building["build_queue"] = queue


# BUG-2 fix (P0.2): deterministic search for the nearest walkable, unoccupied
# tile around a building. Uses a breadth-first ring scan with a stable neighbour
# order so every machine picks the SAME tile (lockstep-safe). Falls back to the
# building's own tile only if the whole nearby area is blocked (never leaves the
# unit without a home). "Occupied" = another unit or building already there.
func find_free_spawn_tile(building: Dictionary) -> Vector2i:
	var origin: Vector2i = Vector2i(int(building.get("x", 0)), int(building.get("y", 0)))
	var visited: Dictionary = {}
	var frontier: Array = [origin]
	visited[_tile_key(origin)] = true
	# Deterministic neighbour order (N, E, S, W, then diagonals).
	var offsets: Array = [
		Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0),
		Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(-1, -1),
	]
	var guard: int = 0
	while not frontier.is_empty() and guard < 4096:
		guard += 1
		var next_frontier: Array = []
		for tile in frontier:
			# The origin tile itself is never a valid spawn (it is the building).
			if tile != origin and _tile_spawnable(tile.x, tile.y):
				return tile
			for off in offsets:
				var n: Vector2i = tile + off
				var k: String = _tile_key(n)
				if visited.has(k):
					continue
				visited[k] = true
				next_frontier.append(n)
		# Keep the frontier sorted so expansion order is fully deterministic.
		next_frontier.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			if a.y != b.y:
				return a.y < b.y
			return a.x < b.x)
		frontier = next_frontier
	return origin


func _tile_key(t: Vector2i) -> String:
	return "%d,%d" % [t.x, t.y]


# A tile is spawnable when it is inside the map, walkable ground, and not already
# occupied by a unit or another building.
func _tile_spawnable(x: int, y: int) -> bool:
	var map_section: Dictionary = nexus.world_state.get_section("map")
	var w: int = int(map_section.get("width", 0))
	var h: int = int(map_section.get("height", 0))
	if w > 0 and h > 0:
		if x < 0 or y < 0 or x >= w or y >= h:
			return false
		var tiles: Array = map_section.get("tiles", [])
		var idx: int = y * w + x
		if idx < 0 or idx >= tiles.size() or int(tiles[idx]) != 0:
			return false
	# No building on this tile.
	for key in _buildings().keys():
		var b: Dictionary = _buildings()[key]
		if int(b.get("x", -1)) == x and int(b.get("y", -1)) == y:
			return false
	# No unit on this tile.
	var units: Dictionary = nexus.world_state.get_section("units").get("list", {})
	for key in units.keys():
		var u: Dictionary = units[key]
		if int(u.get("x", -1)) == x and int(u.get("y", -1)) == y:
			return false
	return true


# --- Event handling ---------------------------------------------------------

func _on_bus_event(event_name: String, payload: Dictionary) -> void:
	handle_event(event_name, payload)


func handle_event(event_name: String, payload: Dictionary) -> void:
	match event_name:
		CMD_PLACE:
			var d: Dictionary = payload.get("data", {})
			place_building(str(d.get("type", "hq")), int(d.get("owner", 0)), int(d.get("x", 0)), int(d.get("y", 0)))
		CMD_QUEUE_UNIT:
			var q: Dictionary = payload.get("data", {})
			queue_unit(int(q.get("building_id", -1)), str(q.get("unit_type", "")), int(q.get("build_time_ticks", 60)))
		CMD_BUILD_BUILDING:
			var bb: Dictionary = payload.get("data", {})
			build_building(str(bb.get("type", "outpost")), int(bb.get("owner", 0)), int(bb.get("x", 0)), int(bb.get("y", 0)))
		CMD_UPGRADE:
			var ub: Dictionary = payload.get("data", {})
			upgrade_building(int(ub.get("building_id", -1)))
		CMD_SET_RALLY:
			var rp: Dictionary = payload.get("data", {})
			set_rally_point(int(rp.get("building_id", -1)), int(rp.get("x", 0)), int(rp.get("y", 0)))
		EVENT_DESTROYED:
			# BUG-G3: remove the destroyed building from the world. Uses the
			# no-echo eraser so the event is not re-emitted (loop guard).
			_remove_destroyed(int(payload.get("id", -1)))


# P0.2 (BUG-2): store a rally point on a building. New units produced there will
# be ordered to move to it right after spawning (handled in the Units module).
func set_rally_point(building_id: int, x: int, y: int) -> void:
	var key: String = str(building_id)
	if not _buildings().has(key):
		return
	_buildings()[key]["rally_point"] = [x, y]


# --- HQ / Outpost upgrade tree (Phase 2.3) ----------------------------------

# Start the next-level upgrade on a building (paid + timed). Returns true if
# the upgrade was successfully queued.
func upgrade_building(building_id: int) -> bool:
	var key: String = str(building_id)
	if not _buildings().has(key):
		return false
	var building: Dictionary = _buildings()[key]
	if not building.get("upgrade_in_progress", {}).is_empty():
		nexus.emit_event(EVENT_BUILD_REJECTED, { "owner": int(building.get("owner", 0)), "reason": "already_upgrading" })
		return false
	var archetype: Variant = nexus.data_loader.get_entry(CATALOG, str(building["type"]))
	if not (archetype is Dictionary):
		return false
	var upgrades: Dictionary = (archetype as Dictionary).get("upgrades", {})
	var current_level: int = int(building.get("level", 1))
	var next_def: Dictionary = _find_next_upgrade(upgrades, current_level)
	if next_def.is_empty():
		nexus.emit_event(EVENT_BUILD_REJECTED, { "owner": int(building.get("owner", 0)), "reason": "max_level" })
		return false
	var owner: int = int(building.get("owner", 0))
	var cost: Dictionary = next_def["def"].get("cost", {})
	var economy: Object = nexus.get_module("economy")
	if economy != null and not cost.is_empty():
		if not economy.try_spend(owner, cost):
			nexus.emit_event(EVENT_BUILD_REJECTED, { "owner": owner, "reason": "insufficient_resources" })
			return false
	building["upgrade_in_progress"] = {
		"level_key": str(next_def["key"]),
		"target_level": current_level + 1,
		"remaining": max(1, int(next_def["def"].get("upgrade_time_ticks", 100))),
		"effects": next_def["def"].get("effects", {}),
	}
	return true


# Find the upgrade definition whose requires_level == current_level.
func _find_next_upgrade(upgrades: Dictionary, current_level: int) -> Dictionary:
	var keys: Array = upgrades.keys()
	keys.sort()
	for k in keys:
		var def: Dictionary = upgrades[k]
		if int(def.get("requires_level", 0)) == current_level:
			return { "key": k, "def": def }
	return {}


func _apply_upgrade_effects(building: Dictionary, effects: Dictionary, _level_key: String) -> void:
	building["level"] = int(building.get("level", 1)) + 1
	var hp_add: int = int(effects.get("max_health_add", 0))
	if hp_add != 0:
		building["max_health"] = int(building.get("max_health", 0)) + hp_add
		building["health"] = int(building.get("health", 0)) + hp_add
	var produces_add: Dictionary = effects.get("produces_add", {})
	if not produces_add.is_empty():
		var produces: Dictionary = building.get("produces", {})
		for res in produces_add.keys():
			produces[res] = int(produces.get(res, 0)) + int(produces_add[res])
		building["produces"] = produces
	var add_units: Array = effects.get("buildable_units_add", [])
	if not add_units.is_empty():
		var buildable: Array = building.get("buildable_units", [])
		for u in add_units:
			if not buildable.has(u):
				buildable.append(u)
		building["buildable_units"] = buildable
	nexus.emit_event(EVENT_UPGRADED, {
		"id": int(building["id"]), "owner": int(building.get("owner", 0)),
		"level": int(building["level"]),
	})


# Is the tile empty (no building) and walkable on the live map?
func _tile_free_for_build(x: int, y: int) -> bool:
	var map_section: Dictionary = nexus.world_state.get_section("map")
	var w: int = int(map_section.get("width", 0))
	var h: int = int(map_section.get("height", 0))
	if w <= 0 or h <= 0:
		return true  # no map configured (tests) -> allow.
	if x < 0 or y < 0 or x >= w or y >= h:
		return false
	var tiles: Array = map_section.get("tiles", [])
	var idx: int = y * w + x
	if idx < 0 or idx >= tiles.size() or int(tiles[idx]) != 0:
		return false
	for key in _buildings().keys():
		var b: Dictionary = _buildings()[key]
		if int(b.get("x", -1)) == x and int(b.get("y", -1)) == y:
			return false
	return true


# --- Helpers / save-load ----------------------------------------------------

func _buildings() -> Dictionary:
	return nexus.world_state.get_section(SECTION)["list"]


# T006 WP1: the unmet prerequisites of an archetype for `owner`, using the
# shared PrereqUtil. Returns [] when the archetype has no `requires` block.
func _missing_prereqs(archetype: Dictionary, owner: int) -> Array:
	var requires: Variant = archetype.get("requires", {})
	if not (requires is Dictionary) or (requires as Dictionary).is_empty():
		return []
	var completed: Array = PrereqUtil.owner_completed_building_types(_buildings(), owner)
	return PrereqUtil.missing(requires, completed, _researched(owner))


# T006 WP1: the tech node ids `owner` has completed (read-only WorldState read).
func _researched(owner: int) -> Array:
	return nexus.world_state.get_section("tech").get("players", {}).get(str(owner), {}).get("researched", [])


func get_building(building_id: int) -> Dictionary:
	return _buildings().get(str(building_id), {})


func count() -> int:
	return _buildings().size()


# BUG-G3: erase a building that combat reported destroyed. Unlike
# destroy_building() this does NOT emit EVENT_DESTROYED again (the event that
# triggered us already announced it -- re-emitting would loop).
func _remove_destroyed(building_id: int) -> void:
	_buildings().erase(str(building_id))


func destroy_building(building_id: int) -> void:
	var key: String = str(building_id)
	if _buildings().has(key):
		var b: Dictionary = _buildings()[key]
		_buildings().erase(key)
		nexus.emit_event(EVENT_DESTROYED, { "id": building_id, "owner": int(b.get("owner", 0)) })


func serialize() -> Dictionary:
	return { "next_building_id": _next_building_id }


func deserialize(data: Dictionary) -> void:
	_next_building_id = int(data.get("next_building_id", BUILDING_ID_BASE))


func shutdown() -> void:
	if nexus != null:
		nexus.event_bus.unsubscribe_all(self)
