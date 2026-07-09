# units_module.gd
# ----------------------------------------------------------------------------
# Project Nexus - Units Module (Phase 1, steps 1.3 + 1.4 + 1.5).
#
# Owns all live units on the battlefield. Data-driven: unit archetypes (stats,
# cost, etc.) are loaded from data/units/*.json by the DataLoader; this module
# only spawns instances and advances their deterministic per-tick logic.
#
# Decoupling rules respected:
#   - It NEVER references MapModule directly. To move, it reads the map data
#     straight from WorldState section "map" via a tiny local helper, and it
#     asks for paths through a generic command rather than calling another
#     module. (Pathfinding requests are issued as commands and answered by the
#     map module through the event bus -- see PathService below.)
#   - Selection + move are expressed as COMMANDS, never direct mutations, so
#     they flow through the CommandQueue (Active Pause + lockstep ready).
#
# Unit instance (stored in WorldState section "units" -> "list"):
#   {
#     "id": int, "type": String, "owner": int,
#     "x": int, "y": int,            # current tile
#     "health": int, "max_health": int,
#     "attack_damage": int, "attack_range": int, "vision_range": int,
#     "move_speed": int,             # tiles per (move_speed) ticks
#     "path": Array[[x,y]...],       # remaining waypoints
#     "move_cooldown": int,          # ticks until next step
#     "target_id": int               # combat target, -1 if none
#   }
#
# CODE LANGUAGE POLICY: English-only identifiers/comments.
# ----------------------------------------------------------------------------
class_name UnitsModule
extends IModule

const SECTION: String = "units"
const CATALOG: String = "units"

# Commands this module reacts to.
const CMD_SPAWN: String = "command.spawn_unit"
const CMD_MOVE: String = "command.move_unit"
const CMD_SELECT: String = "command.select_units"

# Tech upgrades (Phase 2): listen for completed research to buff units.
const EVENT_TECH_COMPLETED: String = "tech.research_completed"

# Events this module emits.
const EVENT_UNIT_SPAWNED: String = "units.spawned"
const EVENT_UNIT_MOVED: String = "units.moved"
const EVENT_UNIT_DIED: String = "units.died"

var _next_unit_id: int = 1


func module_id() -> String:
	return "units"


func init(p_nexus: Object) -> void:
	super.init(p_nexus)
	nexus.subscribe(CMD_SPAWN, self, "_on_bus_event")
	nexus.subscribe(CMD_MOVE, self, "_on_bus_event")
	nexus.subscribe(CMD_SELECT, self, "_on_bus_event")
	# React when combat reports damage/death so we can keep our list clean.
	nexus.subscribe(EVENT_UNIT_DIED, self, "_on_bus_event")
	# React to completed research (Phase 2) to apply stat upgrades.
	nexus.subscribe(EVENT_TECH_COMPLETED, self, "_on_bus_event")
	_ensure_state()


func _ensure_state() -> void:
	var section: Dictionary = nexus.world_state.get_section(SECTION)
	if not section.has("list"):
		section["list"] = {}        # id (as String key) -> unit dict
	if not section.has("selected"):
		section["selected"] = {}    # owner (String) -> Array of unit ids
	# Per-owner, per-category permanent stat bonuses from researched tech.
	# upgrades[owner(String)][category(String)][stat(String)] -> total amount.
	if not section.has("upgrades"):
		section["upgrades"] = {}


# --- Spawning ---------------------------------------------------------------

# Spawn a unit directly (used by scenario setup). Returns the new unit id.
# `veterancy_bonus` lets producers (e.g. Hero Fusion) grant a starting rank.
func spawn_unit(type: String, owner: int, x: int, y: int, veterancy_bonus: int = 0) -> int:
	var archetype: Variant = nexus.data_loader.get_entry(CATALOG, type)
	var stats: Dictionary = {}
	var category: String = "infantry"
	if archetype is Dictionary:
		stats = (archetype as Dictionary).get("stats", {})
		category = str((archetype as Dictionary).get("category", "infantry"))
	var unit_id: int = _next_unit_id
	_next_unit_id += 1
	# Base stats, then add any researched tech upgrades for this owner+category.
	var max_health: int = int(stats.get("health", 100)) + _upgrade_amount(owner, category, "max_health")
	var unit: Dictionary = {
		"id": unit_id,
		"type": type,
		"category": category,
		"owner": owner,
		"x": x,
		"y": y,
		"health": max_health,
		"max_health": max_health,
		"attack_damage": int(stats.get("attack_damage", 10)) + _upgrade_amount(owner, category, "attack_damage"),
		"attack_range": int(stats.get("attack_range", 1)) + _upgrade_amount(owner, category, "attack_range"),
		"vision_range": int(stats.get("vision_range", 5)) + _upgrade_amount(owner, category, "vision_range"),
		"move_speed": max(1, int(stats.get("move_speed", 2))),
		"path": [],
		"move_cooldown": 0,
		"target_id": -1,
		# Veterancy (Phase 2, step 2.14): rank gained from kills/experience.
		"veterancy": max(0, veterancy_bonus),
		"kills": 0,
	}
	# A starting veterancy bonus (e.g. from fusion) also toughens the unit.
	if veterancy_bonus > 0:
		var hp_bonus: int = veterancy_bonus * 20  # mirrors CombatModule rank HP.
		unit["max_health"] = int(unit["max_health"]) + hp_bonus
		unit["health"] = int(unit["health"]) + hp_bonus
	_units()[str(unit_id)] = unit
	nexus.emit_event(EVENT_UNIT_SPAWNED, { "id": unit_id, "owner": owner, "type": type, "x": x, "y": y })
	return unit_id


# --- Deterministic per-tick movement ----------------------------------------

func on_tick(_delta_tick: int) -> void:
	var list: Dictionary = _units()
	# Iterate over a stable, sorted key order for determinism.
	var keys: Array = list.keys()
	keys.sort()
	for key in keys:
		var unit: Dictionary = list[key]
		_advance_movement(unit)


func _advance_movement(unit: Dictionary) -> void:
	var path: Array = unit.get("path", [])
	if path.is_empty():
		return
	# Move at most one tile every `move_speed` ticks (slower speed = bigger gap;
	# we invert so higher move_speed means more frequent steps).
	if int(unit["move_cooldown"]) > 0:
		unit["move_cooldown"] = int(unit["move_cooldown"]) - 1
		return
	var next_tile: Variant = path[0]
	var nx: int = int(next_tile[0])
	var ny: int = int(next_tile[1])
	# Re-validate walkability against the live map (terrain may have changed).
	if not _map_walkable(nx, ny):
		# Blocked: clear the path; a higher-level system can re-plan.
		unit["path"] = []
		return
	unit["x"] = nx
	unit["y"] = ny
	path.remove_at(0)
	unit["path"] = path
	# BUG-3 (P0.3): once the unit reaches its goal, drop the destination marker.
	if path.is_empty():
		unit.erase("move_goal")
	# Cooldown so movement speed is data-driven and frame-rate independent.
	unit["move_cooldown"] = max(0, 3 - int(unit["move_speed"]))
	nexus.emit_event(EVENT_UNIT_MOVED, { "id": int(unit["id"]), "x": nx, "y": ny })


# --- Command / event handling -----------------------------------------------

func _on_bus_event(event_name: String, payload: Dictionary) -> void:
	handle_event(event_name, payload)


func handle_event(event_name: String, payload: Dictionary) -> void:
	match event_name:
		CMD_SPAWN:
			var d: Dictionary = payload.get("data", {})
			var new_id: int = spawn_unit(str(d.get("type", "soldier")), int(d.get("owner", 0)), int(d.get("x", 0)), int(d.get("y", 0)), int(d.get("veterancy_bonus", 0)))
			# P0.2 (BUG-2): if the producing building carried a rally point, order
			# the freshly spawned unit to march there so units gather instead of
			# stacking around the spawn tile. Deterministic (path via A*).
			var rally: Variant = d.get("rally_point", null)
			if rally != null and new_id != -1:
				var rx: int = int(rally[0])
				var ry: int = int(rally[1])
				_handle_move_command({ "unit_ids": [new_id], "x": rx, "y": ry })
		CMD_MOVE:
			_handle_move_command(payload.get("data", {}))
		CMD_SELECT:
			_handle_select_command(payload.get("data", {}))
		EVENT_UNIT_DIED:
			_remove_unit(int(payload.get("id", -1)))
		EVENT_TECH_COMPLETED:
			_apply_tech_effects(int(payload.get("owner", -1)), payload.get("effects", []))


func _handle_move_command(data: Dictionary) -> void:
	var ids: Array = data.get("unit_ids", [])
	var gx: int = int(data.get("x", 0))
	var gy: int = int(data.get("y", 0))
	# BUG-3 fix (P0.3): if the requested goal tile is not walkable (wall / off
	# map / occupied by a building), retarget to the NEAREST reachable walkable
	# tile so the move never silently fails and the unit still heads that way.
	var goal: Vector2i = Vector2i(gx, gy)
	if not _map_walkable(goal.x, goal.y):
		goal = _nearest_walkable(goal)
	# BUG-MA1 / MB1.3 fix (Android): when units are ordered to the same tile do NOT
	# send them all to the identical goal (that stacks every unit into one block --
	# the reported bug 2). Instead spread the group into a FORMATION: assign each
	# unit its own unique, walkable destination tile clustered around the requested
	# goal. MB1.3 also fixes the PAUSE case where several SEPARATE one-unit move
	# commands all target the same tile X: we reserve the destination tiles already
	# claimed by OTHER units' pending move goals so this command's destinations stay
	# unique ACROSS independent commands too. Fully deterministic (units sorted by
	# id, stable BFS ring-out) so lockstep peers compute identical results.
	var valid_ids: Array = _sorted_living_ids(ids)
	var reserved: Dictionary = _reserved_goal_tiles(valid_ids)
	var goals: Array = FormationUtil.plan_goals(goal, valid_ids.size(), _map_walkable, reserved)
	for i in range(valid_ids.size()):
		var key: String = str(valid_ids[i])
		var unit: Dictionary = _units()[key]
		var my_goal: Vector2i = goals[i] if i < goals.size() else goal
		var path: Array = _compute_path(Vector2i(int(unit["x"]), int(unit["y"])), my_goal)
		# Drop the first node (current tile) so the unit steps forward.
		if path.size() > 0:
			path.remove_at(0)
		unit["path"] = _path_to_pairs(path)
		unit["target_id"] = -1
		# Record the move goal so the renderer can draw a destination marker
		# (cosmetic feedback for BUG-3). Cleared implicitly when the path empties.
		unit["move_goal"] = [my_goal.x, my_goal.y]


# BUG-MA1: return the requested unit ids that still exist, sorted ascending by
# id so the formation assignment below is deterministic (lockstep-safe).
func _sorted_living_ids(ids: Array) -> Array:
	var out: Array = []
	for raw_id in ids:
		var uid: int = int(raw_id)
		if _units().has(str(uid)):
			out.append(uid)
	out.sort()
	return out


# MB1.3 (bug 2): collect the destination tiles ALREADY claimed by units that are
# NOT part of this command (their pending `move_goal`). FormationUtil skips these
# so a fresh command's destinations stay unique across independent pause commands
# instead of every one-unit order picking the same tile X. Keys are "x,y" strings
# matching FormationUtil.key(); the iteration order does not affect the result
# (it is a set), so this stays deterministic/lockstep-safe.
func _reserved_goal_tiles(exclude_ids: Array) -> Dictionary:
	var reserved: Dictionary = {}
	var excluded: Dictionary = {}
	for uid in exclude_ids:
		excluded[str(uid)] = true
	var list: Dictionary = _units()
	for key in list.keys():
		if excluded.has(key):
			continue
		var unit: Dictionary = list[key]
		var mg: Variant = unit.get("move_goal", null)
		if mg == null:
			continue
		reserved["%d,%d" % [int(mg[0]), int(mg[1])]] = true
	return reserved


# BUG-3 fix (P0.3): deterministic BFS out from a blocked goal to the closest
# walkable tile. Stable neighbour order keeps it lockstep-safe. Returns the
# original tile if nothing walkable is found within the search budget.
func _nearest_walkable(goal: Vector2i) -> Vector2i:
	var visited: Dictionary = {}
	var frontier: Array = [goal]
	visited["%d,%d" % [goal.x, goal.y]] = true
	var offsets: Array = [
		Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0),
	]
	var guard: int = 0
	while not frontier.is_empty() and guard < 4096:
		guard += 1
		var next_frontier: Array = []
		for tile in frontier:
			if _map_walkable(tile.x, tile.y):
				return tile
			for off in offsets:
				var n: Vector2i = tile + off
				var k: String = "%d,%d" % [n.x, n.y]
				if visited.has(k):
					continue
				visited[k] = true
				next_frontier.append(n)
		next_frontier.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			if a.y != b.y:
				return a.y < b.y
			return a.x < b.x)
		frontier = next_frontier
	return goal


func _handle_select_command(data: Dictionary) -> void:
	var owner: int = int(data.get("owner", 0))
	var ids: Array = data.get("unit_ids", [])
	var selected: Dictionary = nexus.world_state.get_section(SECTION).get("selected", {})
	selected[str(owner)] = ids.duplicate()


# --- Pathfinding bridge (no direct module reference) ------------------------
#
# We compute the path locally using the SAME deterministic A* as the map
# module, reading the grid straight from WorldState. This keeps modules
# decoupled (Units does not import MapModule) while staying deterministic.

func _compute_path(start: Vector2i, goal: Vector2i) -> Array:
	var map_section: Dictionary = nexus.world_state.get_section("map")
	var w: int = int(map_section.get("width", 0))
	var h: int = int(map_section.get("height", 0))
	var tiles: Array = map_section.get("tiles", [])
	if w <= 0 or h <= 0 or tiles.is_empty():
		return [start]
	return PathService.find_path(w, h, tiles, start, goal)


func _map_walkable(x: int, y: int) -> bool:
	var map_section: Dictionary = nexus.world_state.get_section("map")
	var w: int = int(map_section.get("width", 0))
	var h: int = int(map_section.get("height", 0))
	if x < 0 or y < 0 or x >= w or y >= h:
		return false
	var tiles: Array = map_section.get("tiles", [])
	var idx: int = y * w + x
	if idx < 0 or idx >= tiles.size():
		return false
	return int(tiles[idx]) == 0  # 0 == ground


func _path_to_pairs(path: Array) -> Array:
	var out: Array = []
	for p in path:
		out.append([p.x, p.y])
	return out


# --- Tech upgrades (Phase 2) ------------------------------------------------
#
# When research completes, record the permanent per-owner/per-category stat
# bonus AND apply it to that owner's already-living units of that category, so
# the upgrade is felt immediately and also baked into future spawns.

func _apply_tech_effects(owner: int, effects: Array) -> void:
	if owner < 0:
		return
	for effect in effects:
		if str(effect.get("type", "")) != "unit_stat_add":
			continue
		var category: String = str(effect.get("category", "infantry"))
		var stat: String = str(effect.get("stat", ""))
		var amount: int = int(effect.get("amount", 0))
		if stat == "":
			continue
		_add_upgrade(owner, category, stat, amount)
		_apply_stat_to_living(owner, category, stat, amount)


func _upgrades() -> Dictionary:
	return nexus.world_state.get_section(SECTION)["upgrades"]


func _add_upgrade(owner: int, category: String, stat: String, amount: int) -> void:
	var up: Dictionary = _upgrades()
	var o: Dictionary = up.get(str(owner), {})
	var c: Dictionary = o.get(category, {})
	c[stat] = int(c.get(stat, 0)) + amount
	o[category] = c
	up[str(owner)] = o


func _upgrade_amount(owner: int, category: String, stat: String) -> int:
	var up: Dictionary = _upgrades()
	var o: Dictionary = up.get(str(owner), {})
	var c: Dictionary = o.get(category, {})
	return int(c.get(stat, 0))


func _apply_stat_to_living(owner: int, category: String, stat: String, amount: int) -> void:
	var list: Dictionary = _units()
	var keys: Array = list.keys()
	keys.sort()
	for key in keys:
		var unit: Dictionary = list[key]
		if int(unit.get("owner", -1)) != owner:
			continue
		if str(unit.get("category", "infantry")) != category:
			continue
		unit[stat] = int(unit.get(stat, 0)) + amount
		# Raising max_health also heals by the same amount (full upgrade value).
		if stat == "max_health":
			unit["health"] = int(unit.get("health", 0)) + amount


# --- Helpers ----------------------------------------------------------------

func _units() -> Dictionary:
	return nexus.world_state.get_section(SECTION)["list"]


func get_unit(unit_id: int) -> Dictionary:
	return _units().get(str(unit_id), {})


func _remove_unit(unit_id: int) -> void:
	var list: Dictionary = _units()
	list.erase(str(unit_id))


func count() -> int:
	return _units().size()


# --- Save / load ------------------------------------------------------------

func serialize() -> Dictionary:
	return { "next_unit_id": _next_unit_id }


func deserialize(data: Dictionary) -> void:
	_next_unit_id = int(data.get("next_unit_id", 1))


func shutdown() -> void:
	if nexus != null:
		nexus.event_bus.unsubscribe_all(self)
