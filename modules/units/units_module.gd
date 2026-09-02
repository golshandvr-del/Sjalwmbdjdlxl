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
#
# BUG-G1 (gameplay audit): the requested tile is VALIDATED before use. A unit
# spawned off-map or inside a wall could never move again (A* refuses blocked
# starts) -- the historical "spawned but stuck forever" bug. A unit spawned on
# top of another unit/building started permanently stacked. When the requested
# tile is unusable we deterministically relocate to the nearest free tile
# (stable BFS, lockstep-safe). Maps with no grid configured (headless test
# harnesses) keep the exact requested coordinates.
func spawn_unit(type: String, owner: int, x: int, y: int, veterancy_bonus: int = 0) -> int:
	var map_section: Dictionary = nexus.world_state.get_section("map")
	if int(map_section.get("width", 0)) > 0 and not _tile_spawn_free(x, y):
		var relocated: Vector2i = _nearest_spawn_free(Vector2i(x, y))
		x = relocated.x
		y = relocated.y
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
		# MC1.3 (request 1): "replan on contact". The unit planned this step on its
		# BELIEF grid (HIDDEN tiles assumed walkable). It just walked into sight of a
		# real obstacle that is now blocked. Instead of silently giving up, recompute
		# the path on the freshly-updated belief grid toward the SAME goal, exactly
		# like a human who says "did not know there was a wall, I will go around".
		# Deterministic: belief is derived from the (deterministic) fog grid, so every
		# lockstep peer replans identically. If no route is found the path clears.
		if not _replan_unit(unit):
			unit["path"] = []
		return
	# BUG-G5 (gameplay audit): the FINAL step must not land on a tile another
	# living unit is already standing on (it may have arrived there after this
	# path was planned -- the last remaining stacking window). Retarget to the
	# nearest free tile; if none exists, stop cleanly one tile short.
	# Mid-path tiles are exempt on purpose: passing through is transient.
	if path.size() == 1 and _tile_occupied_by_other(nx, ny, int(unit["id"])):
		var new_goal: Vector2i = _nearest_spawn_free(Vector2i(nx, ny))
		if new_goal == Vector2i(nx, ny) or new_goal == Vector2i(int(unit["x"]), int(unit["y"])):
			unit["path"] = []
			unit.erase("move_goal")
			return
		unit["move_goal"] = [new_goal.x, new_goal.y]
		if not _replan_unit(unit):
			unit["path"] = []
			unit.erase("move_goal")
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
	# MC1.4 (request 1): "manual path" mode. When the command carries an ordered
	# `waypoints` array the unit(s) travel EXACTLY through those tiles in order
	# (belief-aware A* between consecutive waypoints, stitched by WaypointUtil)
	# rather than taking a single direct route to one goal. This is the mode a
	# strategic AI planner or a player drawing a route uses. Falls back to the
	# normal single-goal formation move when no waypoints are given.
	var waypoints: Array = WaypointUtil.normalize(data.get("waypoints", null))
	if not waypoints.is_empty():
		_handle_waypoint_move(ids, waypoints)
		return
	var gx: int = int(data.get("x", 0))
	var gy: int = int(data.get("y", 0))
	# BUG-3 fix (P0.3): if the requested goal tile is not walkable (wall / off
	# map / occupied by a building), retarget to the NEAREST reachable walkable
	# tile so the move never silently fails and the unit still heads that way.
	# BUG-G4 (gameplay audit): a DESTINATION additionally excludes building
	# tiles (buildings do not alter terrain, so _map_walkable alone let units
	# park on top of the HQ).
	var goal: Vector2i = Vector2i(gx, gy)
	if not _goal_walkable(goal.x, goal.y):
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
	var goals: Array = FormationUtil.plan_goals(goal, valid_ids.size(), Callable(self, "_goal_walkable"), reserved)
	for i in range(valid_ids.size()):
		var key: String = str(valid_ids[i])
		var unit: Dictionary = _units()[key]
		var my_goal: Vector2i = goals[i] if i < goals.size() else goal
		var path: Array = _compute_path(Vector2i(int(unit["x"]), int(unit["y"])), my_goal, int(unit.get("owner", -1)))
		# Drop the first node (current tile) so the unit steps forward.
		if path.size() > 0:
			path.remove_at(0)
		unit["path"] = _path_to_pairs(path)
		unit["target_id"] = -1
		# Record the move goal so the renderer can draw a destination marker
		# (cosmetic feedback for BUG-3). Cleared implicitly when the path empties.
		unit["move_goal"] = [my_goal.x, my_goal.y]


# MC1.4 (request 1): manual-path move. Each unit follows the SAME ordered
# waypoint list exactly (no formation spread -- the caller chose the route). The
# per-segment paths use the unit's belief grid so undiscovered walls are assumed
# walkable and replan-on-contact (MC1.3) still applies mid-route. The unit's
# move_goal is the final waypoint so the destination marker + replanner behave.
# Deterministic: WaypointUtil + belief A* are both deterministic.
func _handle_waypoint_move(ids: Array, waypoints: Array) -> void:
	var valid_ids: Array = _sorted_living_ids(ids)
	var final_goal: Vector2i = waypoints[waypoints.size() - 1]
	for uid in valid_ids:
		var key: String = str(uid)
		var unit: Dictionary = _units()[key]
		var owner: int = int(unit.get("owner", -1))
		var start: Vector2i = Vector2i(int(unit["x"]), int(unit["y"]))
		var solver: Callable = func(a: Vector2i, b: Vector2i) -> Array:
			return _compute_path(a, b, owner)
		var path: Array = WaypointUtil.stitch_path(start, waypoints, solver)
		# Drop the first node (current tile) so the unit steps forward.
		if path.size() > 0:
			path.remove_at(0)
		unit["path"] = _path_to_pairs(path)
		unit["target_id"] = -1
		unit["move_goal"] = [final_goal.x, final_goal.y]


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
		if mg != null:
			reserved["%d,%d" % [int(mg[0]), int(mg[1])]] = true
			continue
		# BUG-G2 (gameplay audit): a unit that already ARRIVED loses its
		# move_goal, so its tile was NOT reserved and the next command could
		# plant a fresh goal directly on top of it (stacking bug reopened).
		# An idle unit's CURRENT tile is therefore reserved too. Units that are
		# still travelling are not reserved by position (they will leave).
		if (unit.get("path", []) as Array).is_empty():
			reserved["%d,%d" % [int(unit.get("x", 0)), int(unit.get("y", 0))]] = true
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
			if _goal_walkable(tile.x, tile.y):
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

func _compute_path(start: Vector2i, goal: Vector2i, owner: int = -1) -> Array:
	var map_section: Dictionary = nexus.world_state.get_section("map")
	var w: int = int(map_section.get("width", 0))
	var h: int = int(map_section.get("height", 0))
	var tiles: Array = map_section.get("tiles", [])
	if w <= 0 or h <= 0 or tiles.is_empty():
		return [start]
	# MC1.2/MC1.3 (request 1): plan on the OWNER's belief grid so undiscovered
	# walls are assumed walkable (no cheating). owner < 0 means "no fog / full
	# knowledge" and BeliefGridUtil returns the real grid verbatim, so existing
	# no-fog callers (and tests) keep the previous behaviour exactly.
	var fog: Dictionary = nexus.world_state.get_section("fog")
	return PathService.find_path_on_belief(w, h, tiles, fog, owner, start, goal)


# MC1.3 (request 1): recompute a moving unit's path on its belief grid toward its
# recorded move_goal after it contacted a newly-revealed obstacle. Returns true
# if a fresh non-trivial path was set, false otherwise (caller clears the path).
# Deterministic: belief grid + A* are both deterministic, so peers agree.
func _replan_unit(unit: Dictionary) -> bool:
	var goal_raw: Variant = unit.get("move_goal", null)
	if goal_raw == null:
		return false
	var goal: Vector2i = Vector2i(int(goal_raw[0]), int(goal_raw[1]))
	var start: Vector2i = Vector2i(int(unit["x"]), int(unit["y"]))
	if start == goal:
		return false
	var owner: int = int(unit.get("owner", -1))
	var path: Array = _compute_path(start, goal, owner)
	# Drop the first node (current tile) so the unit steps forward.
	if path.size() > 0:
		path.remove_at(0)
	if path.is_empty():
		return false
	unit["path"] = _path_to_pairs(path)
	return true


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


# BUG-G4 (gameplay audit): a valid movement DESTINATION must be walkable ground
# AND free of buildings (buildings never alter terrain, so map walkability alone
# let goals land on the HQ tile). Used for formation goals + nearest-walkable
# retargeting. Deterministic: pure read of WorldState.
func _goal_walkable(x: int, y: int) -> bool:
	return _map_walkable(x, y) and not _building_on_tile(x, y)


# Is any building standing on tile (x, y)?
func _building_on_tile(x: int, y: int) -> bool:
	var buildings: Dictionary = nexus.world_state.get_section("buildings").get("list", {})
	for key in buildings.keys():
		var b: Dictionary = buildings[key]
		if int(b.get("x", -1)) == x and int(b.get("y", -1)) == y:
			return true
	return false


# BUG-G5 (gameplay audit): is a LIVING unit other than `self_id` standing on
# tile (x, y)? Used by the final-step arrival check in _advance_movement.
func _tile_occupied_by_other(x: int, y: int, self_id: int) -> bool:
	var list: Dictionary = _units()
	for key in list.keys():
		var u: Dictionary = list[key]
		if int(u.get("id", -1)) == self_id:
			continue
		if int(u.get("x", -1)) == x and int(u.get("y", -1)) == y and int(u.get("health", 1)) > 0:
			return true
	return false


# BUG-G1 (gameplay audit): is tile (x, y) valid for SPAWNING a unit? It must be
# walkable ground with no building and no LIVING unit already standing there.
func _tile_spawn_free(x: int, y: int) -> bool:
	if not _goal_walkable(x, y):
		return false
	var list: Dictionary = _units()
	for key in list.keys():
		var u: Dictionary = list[key]
		if int(u.get("x", -1)) == x and int(u.get("y", -1)) == y and int(u.get("health", 1)) > 0:
			return false
	return true


# BUG-G1: deterministic BFS from a bad spawn tile to the nearest spawn-free
# tile (stable ring order, lockstep-safe). Returns the original tile if the
# whole search budget is exhausted (pathological maps) so the caller never
# crashes -- the unit may be stuck, but the sim state stays consistent.
func _nearest_spawn_free(origin: Vector2i) -> Vector2i:
	var visited: Dictionary = {}
	var frontier: Array = [origin]
	visited["%d,%d" % [origin.x, origin.y]] = true
	var offsets: Array = [
		Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0),
	]
	var guard: int = 0
	while not frontier.is_empty() and guard < 4096:
		guard += 1
		var next_frontier: Array = []
		for tile in frontier:
			if _tile_spawn_free(tile.x, tile.y):
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
	return origin


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
