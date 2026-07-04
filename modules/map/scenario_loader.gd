# scenario_loader.gd
# ----------------------------------------------------------------------------
# Project Nexus - Scenario Loader (Phase 1, step 1.13).
#
# Builds a single-player skirmish entirely from a data file (Data-Driven
# principle). It is NOT a module: it is a one-shot setup helper invoked by the
# game scene after the modules are registered. It only touches the core's
# public surface (data_loader, world_state, module lookups, commands), so it
# stays decoupled.
#
# Steps it performs from a scenario JSON:
#   1) set the deterministic random seed,
#   2) build the map grid + walls (via the registered MapModule),
#   3) initialise each player's resources (via the EconomyModule),
#   4) place starting buildings (via the BuildingsModule),
#   5) spawn starting units (via the UnitsModule).
#
# CODE LANGUAGE POLICY: English-only identifiers/comments.
# ----------------------------------------------------------------------------
class_name ScenarioLoader
extends RefCounted


# Load and apply a scenario JSON file from `path`. Returns true on success.
static func load_scenario(nexus: Object, path: String) -> bool:
	var parsed: Variant = nexus.data_loader.load_json_file(path)
	if not (parsed is Dictionary):
		push_error("ScenarioLoader: invalid scenario '%s'" % path)
		return false
	var scenario: Dictionary = parsed
	apply_scenario(nexus, scenario)
	return true


# Phase E (E.7): load + apply a scenario already present in the DataLoader's
# `scenarios` catalog by id (shipped base scenarios OR ones a mod/.nexpack added,
# since both merge into the same catalog). Returns true on success. This is what
# the main-menu "Custom Games" list uses to launch any installed scenario.
static func load_scenario_from_catalog(nexus: Object, scenario_id: String) -> bool:
	var entry: Variant = nexus.data_loader.get_entry("scenarios", scenario_id)
	if not (entry is Dictionary):
		push_error("ScenarioLoader: scenario '%s' not found in catalog" % scenario_id)
		return false
	apply_scenario(nexus, entry as Dictionary)
	return true


# Phase E (E.7): list every scenario installed in the catalog as a small UI-ready
# Array of { id, display_name_key, players } Dictionaries, in deterministic id
# order. The menu uses this to populate its Custom Games / scenario picker.
static func list_scenarios(nexus: Object) -> Array:
	var catalog: Dictionary = nexus.data_loader.get_catalog("scenarios")
	var ids: Array = catalog.keys()
	ids.sort()
	var out: Array = []
	for id in ids:
		var entry: Dictionary = catalog[id]
		out.append({
			"id": str(id),
			"display_name_key": str(entry.get("display_name_key", "scenario.%s.name" % str(id))),
			"display_name": str(entry.get("display_name", "")),
			"players": (entry.get("players", []) as Array).size(),
		})
	return out


static func apply_scenario(nexus: Object, scenario: Dictionary) -> void:
	# 1) Deterministic seed.
	nexus.world_state.random_seed = int(scenario.get("random_seed", 0))

	# 1b) Difficulty (Phase 2): set the match-wide active preset BEFORE players
	# are configured so resource grants can use the difficulty multipliers. A
	# scenario may name a built-in or custom preset via "difficulty".
	var difficulty: Object = nexus.get_module("difficulty")
	if difficulty != null and scenario.has("difficulty"):
		difficulty.set_active(str(scenario.get("difficulty", "normal")))

	# 2) Map + walls.
	var map_data: Dictionary = scenario.get("map", {})
	var map_module: Object = nexus.get_module("map")
	if map_module != null:
		map_module.create_grid(int(map_data.get("width", 20)), int(map_data.get("height", 14)))
		for wall in map_data.get("walls", []):
			map_module.set_terrain(int(wall[0]), int(wall[1]), MapModule.TERRAIN_WALL)
		# Phase E6: sea cells become water terrain (blocks land pathing/placement).
		for cell in map_data.get("sea", []):
			if cell is Array and (cell as Array).size() >= 2:
				map_module.set_terrain(int(cell[0]), int(cell[1]), MapModule.TERRAIN_WATER)

	# 2b) Phase P7 (R10): resolve HQ placements. If the scenario ships explicit
	# HQ buildings for every player they are used verbatim; otherwise the
	# deterministic PlacementPlanner seats the remaining players (auto-fill,
	# R10.4) using the requested team layout (R10.2).
	var victory: Object = nexus.get_module("victory")
	var game_mode: String = str(scenario.get("game_mode", "ffa"))
	if victory != null:
		victory.set_mode(game_mode)
	var players: Array = scenario.get("players", [])
	var resolved_hqs: Array = _resolve_hqs(scenario, players, map_module)

	# 3) Player resources + AI / victory / fog registration.
	var economy: Object = nexus.get_module("economy")
	var ai: Object = nexus.get_module("ai_commander")
	var strategic_ai: Object = nexus.get_module("strategic_ai")
	var fog: Object = nexus.get_module("fog_of_war")
	for player in players:
		var owner: int = int(player.get("owner", 0))
		var is_human: bool = bool(player.get("is_human", false))
		var team: int = int(player.get("team", owner))
		if economy != null:
			economy.ensure_player(owner)
			var start_res: Dictionary = player.get("start_resources", {})
			for resource_id in start_res.keys():
				economy.add_resource(owner, str(resource_id), int(start_res[resource_id]))
		# Every player that has an HQ can be eliminated -> register for victory
		# together with the team it belongs to (P7.5).
		if victory != null:
			victory.register_player(owner, team)
		# Human players get a tracked fog-of-war map (Phase 2, step 2.6/2.7).
		if fog != null and is_human:
			fog.register_viewer(owner)
		# Non-human players are driven by the AI commander at a given difficulty.
		if ai != null and not is_human:
			ai.set_ai_player(owner, str(player.get("difficulty", "normal")))
		# Phase 3: a non-human player may additionally run the high-level
		# strategic brain. Opt in with "smart": true (and optionally a
		# "personality": economic | balanced | aggressive). The tactical
		# AiCommander still handles per-unit micro underneath it.
		if strategic_ai != null and not is_human and bool(player.get("smart", false)):
			strategic_ai.set_strategic_player(owner, str(player.get("personality", "balanced")))

	# 4) Buildings (the resolved HQ set, then any extra non-HQ buildings).
	var buildings: Object = nexus.get_module("buildings")
	if buildings != null:
		for b in resolved_hqs:
			buildings.place_building(str(b.get("type", "hq")), int(b.get("owner", 0)), int(b.get("x", 0)), int(b.get("y", 0)))
		for b in scenario.get("buildings", []):
			if str(b.get("type", "hq")) != "hq":
				buildings.place_building(str(b.get("type", "hq")), int(b.get("owner", 0)), int(b.get("x", 0)), int(b.get("y", 0)))

	# 5) Units.
	var units: Object = nexus.get_module("units")
	if units != null:
		for u in scenario.get("units", []):
			units.spawn_unit(str(u.get("type", "soldier")), int(u.get("owner", 0)), int(u.get("x", 0)), int(u.get("y", 0)))

	# 6) Phase P7 (R10.5 / P7.5): CTF flags. Explicit flags are used as-is;
	# otherwise (CTF mode with no authored flags) one flag per team is planned.
	if victory != null and game_mode == "ctf":
		_resolve_flags(nexus, scenario, players, map_module, victory)


# Resolve the final HQ placement Array ({ type, owner, x, y }). Any player that
# the scenario already gives an HQ keeps it (manual placement, R10.3); the rest
# are seated by the deterministic PlacementPlanner honouring the team layout
# ("clustered" | "random", R10.2) and avoiding walls / taken cells (R10.1).
static func _resolve_hqs(scenario: Dictionary, players: Array, map_module: Object) -> Array:
	var out: Array = []
	var placed_owners: Dictionary = {}
	for b in scenario.get("buildings", []):
		if str(b.get("type", "hq")) == "hq":
			out.append({ "type": "hq", "owner": int(b.get("owner", 0)), "x": int(b.get("x", 0)), "y": int(b.get("y", 0)) })
			placed_owners[int(b.get("owner", 0))] = Vector2i(int(b.get("x", 0)), int(b.get("y", 0)))

	# Which players still need an HQ?
	var need: Array = []
	for p in players:
		if not placed_owners.has(int(p.get("owner", 0))):
			need.append({ "owner": int(p.get("owner", 0)), "team": int(p.get("team", int(p.get("owner", 0)))) })
	if need.is_empty() or map_module == null:
		return out

	var width: int = map_module.width()
	var height: int = map_module.height()
	var taken: Dictionary = {}
	for owner_key in placed_owners.keys():
		var pos: Vector2i = placed_owners[owner_key]
		taken["%d,%d" % [pos.x, pos.y]] = true
	var is_blocked: Callable = func(x: int, y: int) -> bool:
		if not map_module.is_walkable(x, y):
			return true
		return taken.has("%d,%d" % [x, y])

	var layout: String = str(scenario.get("team_layout", PlacementPlanner.LAYOUT_CLUSTERED))
	var planned: Array = PlacementPlanner.plan_hqs(width, height, need, layout, int(scenario.get("random_seed", 0)), is_blocked)
	for entry in planned:
		out.append({ "type": "hq", "owner": int(entry.get("owner", 0)), "x": int(entry.get("x", 0)), "y": int(entry.get("y", 0)) })
		taken["%d,%d" % [int(entry.get("x", 0)), int(entry.get("y", 0))]] = true
	return out


# Register CTF flags with the VictoryModule. Explicit `flags` in the scenario win
# (R10.3); otherwise one flag per distinct team is auto-placed (R10.4).
static func _resolve_flags(nexus: Object, scenario: Dictionary, players: Array, map_module: Object, victory: Object) -> void:
	var explicit: Array = scenario.get("flags", [])
	if not explicit.is_empty():
		for f in explicit:
			victory.register_flag(int(f.get("index", 0)), int(f.get("x", 0)), int(f.get("y", 0)), int(f.get("team", f.get("index", 0))))
		return
	if map_module == null:
		return
	# One flag per distinct team.
	var teams: Array = []
	for p in players:
		var t: int = int(p.get("team", int(p.get("owner", 0))))
		if not teams.has(t):
			teams.append(t)
	teams.sort()
	var is_blocked: Callable = func(x: int, y: int) -> bool:
		return not map_module.is_walkable(x, y)
	var planned: Array = PlacementPlanner.plan_flags(map_module.width(), map_module.height(), teams.size(), int(scenario.get("random_seed", 0)), is_blocked)
	for i in range(teams.size()):
		var cell: Dictionary = planned[i]
		victory.register_flag(i, int(cell.get("x", 0)), int(cell.get("y", 0)), int(teams[i]))


# Store useful scenario metadata into world state for the UI / win-checks.
static func store_meta(nexus: Object, scenario: Dictionary) -> void:
	var section: Dictionary = nexus.world_state.get_section("scenario")
	section["id"] = str(scenario.get("id", ""))
	var humans: Array = []
	for player in scenario.get("players", []):
		if bool(player.get("is_human", false)):
			humans.append(int(player.get("owner", 0)))
	section["human_players"] = humans
