# strategic_ai_module.gd
# ----------------------------------------------------------------------------
# Project Nexus - Strategic AI Module (Phase 3, step 3.1).
#
# A HIGH-LEVEL planning brain that sits ABOVE the reactive AiCommanderModule.
# Where the AiCommander handles tactical micro (queue a soldier, march idle
# units at the nearest enemy), the StrategicAI makes the longer-horizon
# decisions a human player would: when to invest in the economy, what to
# research, when to upgrade the HQ, and -- crucially -- when to STOP trickling
# units forward and instead MASS an army before committing to a coordinated
# assault.
#
# Why a separate module (instead of bloating AiCommander)?
#   - The "constitution" wants small, single-purpose, swappable modules. Macro
#     strategy and tactical micro are genuinely different concerns; keeping them
#     apart means a modder can replace either one independently.
#   - Both can coexist: AiCommander still does the per-unit busywork; the
#     StrategicAI only intervenes on the bigger decisions and on the army-wide
#     "push" order.
#
# Design rules it obeys (the project "constitution"):
#   - Pure module: depends ONLY on the core. It READS world state and ISSUES
#     COMMANDS through the Nexus. It never mutates units/buildings directly and
#     never references another module instance.
#   - Fully deterministic: it only acts on fixed tick boundaries, iterates over
#     sorted keys, breaks ties by lowest id, and uses NO real RNG (a stable
#     tick-derived pseudo-roll only). Same world state + same tick => same plan,
#     which is what makes it lockstep-safe for Phase 3 multiplayer.
#   - Data-driven: which players it controls, their personality (economic vs
#     aggressive) and the knobs come from world state / the scenario, not from
#     hard-coded player numbers.
#
# Per controlled player, evaluated every `plan_interval` ticks, it runs a small
# prioritized plan:
#   1) RESEARCH : if nothing is being researched and a tech is affordable +
#                 unlocked, start the cheapest available one.
#   2) EXPAND   : if it can comfortably afford an outpost and owns fewer command
#                 buildings than its expansion cap, build one near its HQ.
#   3) UPGRADE  : if rich and its HQ is idle (no upgrade running), level it up.
#   4) MASS+PUSH: track the player's army size. While below the attack
#                 threshold, hold position (rally). Once the army is big enough
#                 -- or the player is under direct threat -- declare an ALL-IN:
#                 every combat unit is ordered onto the enemy HQ together.
#
# The "push" decision is exposed in world state (section "strategic_ai") so the
# HUD / debugging can observe the AI's current posture, and so it survives
# save/load deterministically.
#
# CODE LANGUAGE POLICY: English-only identifiers/comments.
# ----------------------------------------------------------------------------
class_name StrategicAiModule
extends IModule

const SECTION: String = "strategic_ai"
const RESOURCE: String = "resource_basic"

# How many simulation ticks between strategic planning passes. Deliberately
# slower than the tactical AiCommander so macro decisions are stable.
const DEFAULT_PLAN_INTERVAL: int = 30

# Personality presets. "economic" expands/researches harder and pushes later;
# "aggressive" masses a smaller army and attacks sooner; "balanced" is default.
# attack_army_size = how many combat units to gather before the all-in push.
# expansion_cap    = max command buildings (HQ + outposts) it tries to own.
# upgrade_reserve  = keep at least this much resource before spending on upgrade.
const PERSONALITY: Dictionary = {
	"economic":   { "attack_army_size": 6, "expansion_cap": 3, "upgrade_reserve": 300, "research_first": true },
	"balanced":   { "attack_army_size": 4, "expansion_cap": 2, "upgrade_reserve": 250, "research_first": true },
	"aggressive": { "attack_army_size": 3, "expansion_cap": 1, "upgrade_reserve": 400, "research_first": false },
}

# Research order the AI prefers (cheapest / highest value first). The actual
# affordability + prerequisite checks are delegated to the tech tree via the
# research command; this is only the AI's preference list.
const RESEARCH_PRIORITY: Array = ["improved_weapons", "improved_armor", "advanced_optics", "veteran_doctrine"]

# Costs the planner reasons about (mirrors the data files; used only for
# "can I comfortably afford this?" gating, never to bypass the real spend which
# always happens inside the owning module).
const OUTPOST_COST: int = 120
const HQ_UPGRADE_COST: int = 250

# MD9.5: how far (Manhattan rings around the HQ) the smart placement selector
# enumerates candidate tiles. Kept modest so the candidate set stays small and
# the per-tick scoring cost bounded; the legacy scan looked at rings 2..3 only.
const PLACEMENT_MAX_RADIUS: int = 4

# MD9.5: fixed-point scale shared with the placement/utility/site-scoring utils.
const Q_SCALE: int = 1000

# MD9.5: capability "cards" for the building types the strategic planner can
# place. Each is a q-scaled (0..1000) capability vector consumed by
# BuildingUtilityUtil.score_building. Today only "outpost" is buildable here, so
# a modder/future phase can extend this table without touching the selector.
# The outpost is a forward COMMAND building: it extends economy/production reach
# and gives a little frontline presence, so it weights economic/production/
# frontline value and cares moderately about site quality (placement_fit).
const BUILDING_CARDS: Dictionary = {
	"outpost": {
		"caps": {
			"control_value": 500,
			"defense_value": 300,
			"economic_value": 700,
			"frontline_value": 500,
			"production_value": 600,
			"repair_value": 100,
			"tech_value": 200,
		},
		"placement_fit": 500,
	},
}


func module_id() -> String:
	return "strategic_ai"


func init(p_nexus: Object) -> void:
	super.init(p_nexus)
	_ensure_state()


func _ensure_state() -> void:
	var section: Dictionary = nexus.world_state.get_section(SECTION)
	if not section.has("controlled"):
		# owner(String) -> personality name. Populated by the scenario loader.
		section["controlled"] = {}
	if not section.has("posture"):
		# owner(String) -> "build" | "attack" (current strategic posture).
		section["posture"] = {}
	if not section.has("mode"):
		# MC9.4: owner(String) -> "main" | "rebel" (general mode). Rebels have no
		# base, so economy/research/hq-upgrade planners are disabled for them.
		section["mode"] = {}
	if not section.has("behaviour"):
		# MC12.3: owner(String) -> derived behaviour dict (attack_army_size,
		# expansion_cap, upgrade_reserve, research_first). When present it OVERRIDES
		# the legacy PERSONALITY preset, letting a full AiProfile vector drive the
		# planner. Absent -> fall back to the named preset (backward compatible).
		section["behaviour"] = {}
	if not section.has("profile_id"):
		# MC12.3: owner(String) -> the AiProfile id that produced the behaviour
		# (cosmetic / for UI + reputation lookup). Absent for legacy named AIs.
		section["profile_id"] = {}


# --- Public configuration (called by the scenario loader) -------------------

# Mark a player as strategically AI-controlled with a personality name.
func set_strategic_player(owner: int, personality: String = "balanced") -> void:
	var section: Dictionary = nexus.world_state.get_section(SECTION)
	var name: String = personality if PERSONALITY.has(personality) else "balanced"
	(section["controlled"] as Dictionary)[str(owner)] = name
	(section["posture"] as Dictionary)[str(owner)] = "build"
	if not (section["mode"] as Dictionary).has(str(owner)):
		(section["mode"] as Dictionary)[str(owner)] = AiGeneralModeUtil.MODE_MAIN
	# A named preset has no profile; drop any stale profile-derived override so
	# the legacy preset path is used deterministically.
	(section["behaviour"] as Dictionary).erase(str(owner))
	(section["profile_id"] as Dictionary).erase(str(owner))


# MC12.3: mark a player as AI-controlled by a full AiProfile vector. The
# profile's strategy_bias/personality knobs are derived (once, deterministically)
# into the same behaviour dictionary the legacy presets use, then stored in world
# state so the planner reads it every tick without re-deriving. `profile` is any
# object exposing get_value(category, knob) (an AiProfile). Falls back to the
# balanced preset when profile is null.
func set_strategic_player_profile(owner: int, profile) -> void:
	var section: Dictionary = nexus.world_state.get_section(SECTION)
	var behaviour: Dictionary = AiStrategyDerivationUtil.derive_from_profile(profile)
	# Keep a legacy-compatible name label for any code that reads "controlled".
	(section["controlled"] as Dictionary)[str(owner)] = "balanced"
	(section["posture"] as Dictionary)[str(owner)] = "build"
	if not (section["mode"] as Dictionary).has(str(owner)):
		(section["mode"] as Dictionary)[str(owner)] = AiGeneralModeUtil.MODE_MAIN
	(section["behaviour"] as Dictionary)[str(owner)] = behaviour
	var pid: String = ""
	if profile != null and profile.has_method("id"):
		pid = str(profile.id())
	(section["profile_id"] as Dictionary)[str(owner)] = pid


# MC12.3: the effective behaviour dictionary for an owner. Prefers a stored
# profile-derived override, else the legacy named preset (via derivation util
# which mirrors PERSONALITY exactly), else balanced. Deterministic.
func behaviour_for(owner: int) -> Dictionary:
	var section: Dictionary = nexus.world_state.get_section(SECTION)
	var overrides: Dictionary = section.get("behaviour", {})
	if overrides.has(str(owner)):
		return (overrides[str(owner)] as Dictionary).duplicate(true)
	var name: String = str(section.get("controlled", {}).get(str(owner), "balanced"))
	return AiStrategyDerivationUtil.derive_from_name(name)


# MC12.3: the AiProfile id backing an owner, or "" for a legacy named AI.
func profile_id(owner: int) -> String:
	return str(nexus.world_state.get_section(SECTION).get("profile_id", {}).get(str(owner), ""))


# MC9.4: set an AI owner's general mode ("main" or "rebel"). The scenario loader
# calls this for rebel factions (colours with units but no HQ).
func set_general_mode(owner: int, mode: String) -> void:
	var section: Dictionary = nexus.world_state.get_section(SECTION)
	(section["mode"] as Dictionary)[str(owner)] = AiGeneralModeUtil.normalise(mode)


func general_mode(owner: int) -> String:
	return AiGeneralModeUtil.normalise(
		str(nexus.world_state.get_section(SECTION).get("mode", {}).get(str(owner), AiGeneralModeUtil.MODE_MAIN)))


func posture(owner: int) -> String:
	return str(nexus.world_state.get_section(SECTION).get("posture", {}).get(str(owner), "build"))


func is_controlling(owner: int) -> bool:
	return nexus.world_state.get_section(SECTION).get("controlled", {}).has(str(owner))


# --- Deterministic planning loop --------------------------------------------

func on_tick(_delta_tick: int) -> void:
	var tick: int = int(nexus.world_state.current_tick)
	var controlled: Dictionary = nexus.world_state.get_section(SECTION).get("controlled", {})
	if controlled.is_empty():
		return
	var owners: Array = controlled.keys()
	owners.sort()
	for owner_key in owners:
		var owner: int = int(owner_key)
		# Phase-shift by owner so multiple AIs do not all plan on the same tick.
		if (tick + owner) % DEFAULT_PLAN_INTERVAL != 0:
			continue
		# MC12.3: effective behaviour prefers a profile-derived override, else the
		# legacy named preset. Both share the same dictionary shape.
		var personality: Dictionary = behaviour_for(owner)
		_plan_for_player(owner, personality)


func _plan_for_player(owner: int, personality: Dictionary) -> void:
	# MC9.4: gate base-building planners by general mode. A rebel faction has no
	# base, so economy/research/hq-upgrade are skipped; it only manoeuvres.
	var flags: Dictionary = AiGeneralModeUtil.planner_flags(general_mode(owner))
	# Priority order is intentional: secure tech/economy first, then decide
	# whether to keep massing or to commit to the attack.
	if bool(personality.get("research_first", true)):
		if bool(flags.get("research", true)):
			_plan_research(owner)
		if bool(flags.get("economy", true)):
			_plan_expansion(owner, personality)
	else:
		if bool(flags.get("economy", true)):
			_plan_expansion(owner, personality)
		if bool(flags.get("research", true)):
			_plan_research(owner)
	if bool(flags.get("hq_upgrade", true)):
		_plan_hq_upgrade(owner, personality)
	_plan_army_posture(owner, personality)


# --- 1) Research ------------------------------------------------------------

func _plan_research(owner: int) -> void:
	# Only one research at a time: if anything is already in progress, wait.
	# Tech state shape (see TechTreeModule.ensure_player):
	#   { "researched": Array[node_id], "in_progress": Dictionary, ... }
	var tech: Dictionary = nexus.world_state.get_section("tech").get("players", {}).get(str(owner), {})
	if not (tech.get("in_progress", {}) as Dictionary).is_empty():
		return
	# Pick the first preferred tech that is neither researched nor blocked. We
	# do not re-implement affordability/prereq logic here; we issue the command
	# and let the tech tree accept or reject it. To avoid spamming rejected
	# commands we do a light pre-check via world state for "already researched".
	var done: Array = tech.get("researched", [])
	for node_id in RESEARCH_PRIORITY:
		if done.has(node_id):
			continue
		# Affordability + prerequisite are authoritatively checked by tech_tree;
		# we only gate on a cheap resource floor to reduce pointless commands.
		if _resources(owner) < 90:
			return
		nexus.issue_command("research_tech", owner, { "owner": owner, "node_id": node_id }, 1)
		return


# --- 2) Expansion (build outposts) ------------------------------------------

func _plan_expansion(owner: int, personality: Dictionary) -> void:
	var cap: int = int(personality.get("expansion_cap", 2))
	var command_buildings: int = _count_command_buildings(owner)
	if command_buildings >= cap:
		return
	# Only expand when comfortably above the outpost cost so we do not starve
	# unit production. Require a buffer of roughly two soldiers' worth.
	if _resources(owner) < OUTPOST_COST + 100:
		return
	var hq: Dictionary = _find_hq(owner)
	if hq.is_empty():
		return
	var hx: int = int(hq.get("x", 0))
	var hy: int = int(hq.get("y", 0))
	# MD9.5: pick the site by (building value x site quality) over a limited
	# candidate set, instead of "first empty tile near HQ". If the smart selector
	# finds nothing (empty candidate set / unusual map), fall back to the legacy
	# deterministic ring scan so existing behaviour is preserved (backward-compat).
	var spot: Vector2i = _smart_build_spot(owner, "outpost", hx, hy)
	if spot.x < 0:
		spot = _find_build_spot(hx, hy, owner)
	if spot.x < 0:
		return
	nexus.issue_command("build_building", owner, {
		"type": "outpost", "owner": owner, "x": spot.x, "y": spot.y,
	}, 1)


# --- 3) HQ upgrade ----------------------------------------------------------

func _plan_hq_upgrade(owner: int, personality: Dictionary) -> void:
	var reserve: int = int(personality.get("upgrade_reserve", 250))
	if _resources(owner) < HQ_UPGRADE_COST + reserve:
		return
	var hq: Dictionary = _find_hq(owner)
	if hq.is_empty():
		return
	# Skip if an upgrade is already running or the HQ is still a build site.
	if not (hq.get("upgrade_in_progress", {}) as Dictionary).is_empty():
		return
	if int(hq.get("construction_remaining", 0)) > 0:
		return
	nexus.issue_command("upgrade_building", owner, { "building_id": int(hq.get("id", -1)) }, 1)


# --- 4) Army posture: mass, then push ---------------------------------------

func _plan_army_posture(owner: int, personality: Dictionary) -> void:
	var threshold: int = int(personality.get("attack_army_size", 4))
	var army: Array = _combat_units(owner)
	var section: Dictionary = nexus.world_state.get_section(SECTION)
	var posture_map: Dictionary = section["posture"]

	var under_threat: bool = _enemy_near_base(owner)
	var ready_to_attack: bool = army.size() >= threshold

	if ready_to_attack or under_threat:
		posture_map[str(owner)] = "attack"
		_order_all_in(owner, army)
	else:
		posture_map[str(owner)] = "build"
		# While building up, keep the army rallied near the HQ so it does not
		# trickle forward and get picked off piecemeal. We only issue a rally
		# move for units that have wandered away and are currently idle.
		_rally_army(owner, army)


# Order every combat unit onto the single nearest enemy command building (its
# HQ) so the army strikes as one coordinated wave.
func _order_all_in(owner: int, army: Array) -> void:
	var target: Dictionary = _nearest_enemy_building(owner)
	if target.is_empty():
		# No enemy building visible: fall back to nearest enemy unit cluster.
		target = _nearest_enemy_unit_anchor(owner)
	if target.is_empty():
		return
	var ids: Array = []
	for unit in army:
		ids.append(int(unit.get("id", -1)))
	if ids.is_empty():
		return
	nexus.issue_command("move_unit", owner, {
		"unit_ids": ids, "x": int(target.get("x", 0)), "y": int(target.get("y", 0)),
	}, 1)


# Keep idle, far-flung units near the HQ while massing.
func _rally_army(owner: int, army: Array) -> void:
	var hq: Dictionary = _find_hq(owner)
	if hq.is_empty():
		return
	var hx: int = int(hq.get("x", 0))
	var hy: int = int(hq.get("y", 0))
	var stragglers: Array = []
	for unit in army:
		# Only rally idle units (no current path) that have strayed far.
		if not (unit.get("path", []) as Array).is_empty():
			continue
		var dist: int = abs(int(unit.get("x", 0)) - hx) + abs(int(unit.get("y", 0)) - hy)
		if dist > 3:
			stragglers.append(int(unit.get("id", -1)))
	if stragglers.is_empty():
		return
	nexus.issue_command("move_unit", owner, {
		"unit_ids": stragglers, "x": hx, "y": hy,
	}, 1)


# --- World-state reading helpers (sorted + deterministic) -------------------

func _resources(owner: int) -> int:
	return int(nexus.world_state.get_section("economy").get("players", {}).get(str(owner), {}).get(RESOURCE, 0))


func _units() -> Dictionary:
	return nexus.world_state.get_section("units").get("list", {})


func _buildings() -> Dictionary:
	return nexus.world_state.get_section("buildings").get("list", {})


# All living combat units owned by `owner`, in stable id order.
func _combat_units(owner: int) -> Array:
	var out: Array = []
	var units: Dictionary = _units()
	var keys: Array = units.keys()
	keys.sort_custom(func(a, b): return int(a) < int(b))
	for key in keys:
		var u: Dictionary = units[key]
		if int(u.get("owner", -1)) != owner:
			continue
		if int(u.get("health", 0)) <= 0:
			continue
		out.append(u)
	return out


func _count_command_buildings(owner: int) -> int:
	var n: int = 0
	var buildings: Dictionary = _buildings()
	for key in buildings.keys():
		var b: Dictionary = buildings[key]
		if int(b.get("owner", -1)) != owner:
			continue
		if int(b.get("health", 0)) <= 0:
			continue
		n += 1
	return n


func _find_hq(owner: int) -> Dictionary:
	var buildings: Dictionary = _buildings()
	var keys: Array = buildings.keys()
	keys.sort_custom(func(a, b): return int(a) < int(b))
	for key in keys:
		var b: Dictionary = buildings[key]
		if int(b.get("owner", -1)) == owner and int(b.get("health", 0)) > 0:
			return b
	return {}


# Find a free, walkable tile a couple of rings out from the HQ, scanning in a
# fixed deterministic order (closest ring first, then by clockwise offset).
func _find_build_spot(hx: int, hy: int, _owner: int) -> Vector2i:
	var map_section: Dictionary = nexus.world_state.get_section("map")
	var w: int = int(map_section.get("width", 0))
	var h: int = int(map_section.get("height", 0))
	var tiles: Array = map_section.get("tiles", [])
	if w <= 0 or h <= 0 or tiles.is_empty():
		return Vector2i(-1, -1)
	# Deterministic offset order: rings 2 and 3 around the HQ.
	var offsets: Array = []
	for ring in [2, 3]:
		for dy in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				if abs(dx) == ring or abs(dy) == ring:
					offsets.append(Vector2i(dx, dy))
	for off in offsets:
		var x: int = hx + off.x
		var y: int = hy + off.y
		if x < 0 or y < 0 or x >= w or y >= h:
			continue
		var idx: int = y * w + x
		if idx < 0 or idx >= tiles.size():
			continue
		if int(tiles[idx]) != 0:
			continue  # not ground
		if _tile_occupied(x, y):
			continue
		return Vector2i(x, y)
	return Vector2i(-1, -1)


# --- MD9.5: smart building placement (value x site quality) -----------------
#
# Choose a build site for `building_type` using the pure MD9 utilities:
#   SiteTopologyUtil (candidates) -> SiteScoringUtil (quality) ->
#   BuildingUtilityUtil (value) -> BuildingPlacementUtil (argmax).
# Returns Vector2i(-1,-1) when nothing scores (caller falls back to legacy).
# Everything handed to the utils is a PLAIN snapshot the module reads from the
# world model here, so the utils stay pure and the choice stays deterministic.
func _smart_build_spot(owner: int, building_type: String, hx: int, hy: int) -> Vector2i:
	var card: Dictionary = BUILDING_CARDS.get(building_type, {})
	if card.is_empty():
		return Vector2i(-1, -1)
	var world: Dictionary = _placement_world_snapshot(owner, hx, hy)
	if int(world.get("width", 0)) <= 0 or int(world.get("height", 0)) <= 0:
		return Vector2i(-1, -1)
	var context: Dictionary = _placement_context(owner)
	var caps: Dictionary = (card.get("caps", {}) as Dictionary)
	var fit: int = int(card.get("placement_fit", 500))
	var choice: Dictionary = BuildingPlacementUtil.plan_placement(
		caps, context, world, PLACEMENT_MAX_RADIUS, fit)
	if not bool(choice.get("found", false)):
		return Vector2i(-1, -1)
	var cx: int = int(choice.get("x", -1))
	var cy: int = int(choice.get("y", -1))
	if cx < 0 or cy < 0:
		return Vector2i(-1, -1)
	# Guard against a candidate that is no longer buildable this tick (a building
	# may have appeared since the snapshot); defer to the legacy scan if so.
	if _tile_occupied(cx, cy):
		return Vector2i(-1, -1)
	return Vector2i(cx, cy)


# Build the PLAIN map/coordinate snapshot the MD9 utilities consume. It merges
# the topology keys (width/height/tiles/hq/enemies/occupied) with the scoring
# keys (resources/existing) into one dictionary, all read deterministically from
# the world model. Coordinate lists are id-sorted for a stable candidate order.
func _placement_world_snapshot(owner: int, hx: int, hy: int) -> Dictionary:
	var map_section: Dictionary = nexus.world_state.get_section("map")
	var w: int = int(map_section.get("width", 0))
	var h: int = int(map_section.get("height", 0))
	var tiles: Array = map_section.get("tiles", [])

	var enemies: Array = []
	var occupied: Array = []
	var existing: Array = []
	var buildings: Dictionary = _buildings()
	var bkeys: Array = buildings.keys()
	bkeys.sort_custom(func(a, b): return int(a) < int(b))
	for key in bkeys:
		var b: Dictionary = buildings[key]
		if int(b.get("health", 0)) <= 0:
			continue
		var bx: int = int(b.get("x", 0))
		var by: int = int(b.get("y", 0))
		occupied.append({ "x": bx, "y": by })
		if int(b.get("owner", -1)) == owner:
			existing.append({ "x": bx, "y": by })
		else:
			enemies.append({ "x": bx, "y": by })

	# Enemy UNITS also count as threat anchors for frontline/vulnerability axes.
	var units: Dictionary = _units()
	var ukeys: Array = units.keys()
	ukeys.sort_custom(func(a, b): return int(a) < int(b))
	for key in ukeys:
		var u: Dictionary = units[key]
		if int(u.get("health", 0)) <= 0:
			continue
		if int(u.get("owner", -1)) == owner:
			continue
		enemies.append({ "x": int(u.get("x", 0)), "y": int(u.get("y", 0)) })

	# Resource nodes (economy section) give the resource_access axis something to
	# weigh; absent -> empty list (axis degrades to 0, still deterministic).
	var resources: Array = _resource_nodes()

	return {
		"width": w,
		"height": h,
		"tiles": tiles,
		"hq": { "x": hx, "y": hy },
		"enemies": enemies,
		"occupied": occupied,
		"existing": existing,
		"resources": resources,
	}


# Resource-node coordinates from the world model, if the scenario exposes them
# under the "map" section (key "resource_nodes": Array[{"x","y"}]). Missing ->
# empty (safe). Kept small + sorted for determinism.
func _resource_nodes() -> Array:
	var raw: Array = nexus.world_state.get_section("map").get("resource_nodes", [])
	var out: Array = []
	for r in raw:
		if r is Dictionary:
			out.append({ "x": int((r as Dictionary).get("x", 0)), "y": int((r as Dictionary).get("y", 0)) })
	out.sort_custom(func(a, b):
		if int(a.get("x", 0)) != int(b.get("x", 0)):
			return int(a.get("x", 0)) < int(b.get("x", 0))
		return int(a.get("y", 0)) < int(b.get("y", 0)))
	return out


# The MD7 context vector for placement need-derivation, built from a plain,
# owner-relative world summary. Reuses AiContextUtil so the needs the building
# utility derives match the rest of the AI backbone. Deterministic.
func _placement_context(owner: int) -> Dictionary:
	var hq: Dictionary = _find_hq(owner)
	var hq_xy: Dictionary = {}
	if not hq.is_empty():
		hq_xy = { "x": int(hq.get("x", 0)), "y": int(hq.get("y", 0)) }

	var own_units: Array = []
	var enemy_units: Array = []
	var units: Dictionary = _units()
	var ukeys: Array = units.keys()
	ukeys.sort_custom(func(a, b): return int(a) < int(b))
	for key in ukeys:
		var u: Dictionary = units[key]
		if int(u.get("health", 0)) <= 0:
			continue
		var rec: Dictionary = {
			"id": int(u.get("id", int(key))),
			"x": int(u.get("x", 0)), "y": int(u.get("y", 0)),
			"health": int(u.get("health", 1)),
		}
		if int(u.get("owner", -1)) == owner:
			own_units.append(rec)
		else:
			enemy_units.append(rec)

	var enemy_buildings: Array = []
	var buildings: Dictionary = _buildings()
	var bkeys: Array = buildings.keys()
	bkeys.sort_custom(func(a, b): return int(a) < int(b))
	for key in bkeys:
		var b: Dictionary = buildings[key]
		if int(b.get("health", 0)) <= 0:
			continue
		if int(b.get("owner", -1)) == owner:
			continue
		enemy_buildings.append({
			"id": int(b.get("id", int(key))),
			"x": int(b.get("x", 0)), "y": int(b.get("y", 0)),
			"health": int(b.get("health", 1)),
		})

	var summary: Dictionary = {
		"hq": hq_xy,
		"own_units": own_units,
		"enemy_units": enemy_units,
		"enemy_buildings": enemy_buildings,
		"own_economy": _resources(owner),
		"enemy_economy": 0,
		"own_army": own_units.size(),
		"enemy_army": enemy_units.size(),
	}
	return AiContextUtil.build_context(summary, owner)


func _tile_occupied(x: int, y: int) -> bool:
	var buildings: Dictionary = _buildings()
	for key in buildings.keys():
		var b: Dictionary = buildings[key]
		if int(b.get("x", -999)) == x and int(b.get("y", -999)) == y:
			return true
	return false


func _nearest_enemy_building(owner: int) -> Dictionary:
	var hq: Dictionary = _find_hq(owner)
	var ax: int = int(hq.get("x", 0))
	var ay: int = int(hq.get("y", 0))
	var best: Dictionary = {}
	var best_dist: int = 1 << 30
	var best_id: int = 1 << 30
	var buildings: Dictionary = _buildings()
	var keys: Array = buildings.keys()
	keys.sort_custom(func(a, b): return int(a) < int(b))
	for key in keys:
		var b: Dictionary = buildings[key]
		if int(b.get("owner", owner)) == owner or int(b.get("health", 0)) <= 0:
			continue
		var d: int = abs(ax - int(b.get("x", 0))) + abs(ay - int(b.get("y", 0)))
		var bid: int = int(b.get("id", 0))
		if d < best_dist or (d == best_dist and bid < best_id):
			best = b
			best_dist = d
			best_id = bid
	return best


func _nearest_enemy_unit_anchor(owner: int) -> Dictionary:
	var hq: Dictionary = _find_hq(owner)
	var ax: int = int(hq.get("x", 0))
	var ay: int = int(hq.get("y", 0))
	var best: Dictionary = {}
	var best_dist: int = 1 << 30
	var best_id: int = 1 << 30
	var units: Dictionary = _units()
	var keys: Array = units.keys()
	keys.sort_custom(func(a, b): return int(a) < int(b))
	for key in keys:
		var u: Dictionary = units[key]
		if int(u.get("owner", owner)) == owner or int(u.get("health", 0)) <= 0:
			continue
		var d: int = abs(ax - int(u.get("x", 0))) + abs(ay - int(u.get("y", 0)))
		var uid: int = int(u.get("id", 0))
		if d < best_dist or (d == best_dist and uid < best_id):
			best = u
			best_dist = d
			best_id = uid
	return best


# Is an enemy combat unit within a small radius of the player's HQ? (Triggers a
# defensive all-in even if the army has not reached the attack threshold.)
func _enemy_near_base(owner: int) -> bool:
	var hq: Dictionary = _find_hq(owner)
	if hq.is_empty():
		return false
	var hx: int = int(hq.get("x", 0))
	var hy: int = int(hq.get("y", 0))
	var units: Dictionary = _units()
	for key in units.keys():
		var u: Dictionary = units[key]
		if int(u.get("owner", owner)) == owner or int(u.get("health", 0)) <= 0:
			continue
		var d: int = abs(hx - int(u.get("x", 0))) + abs(hy - int(u.get("y", 0)))
		if d <= 5:
			return true
	return false


# --- Save / load ------------------------------------------------------------
# State lives entirely in world_state (section "strategic_ai"), so module-level
# serialize is empty -- the WorldState snapshot already carries it.

func serialize() -> Dictionary:
	return {}


func deserialize(_data: Dictionary) -> void:
	pass


func shutdown() -> void:
	if nexus != null:
		nexus.event_bus.unsubscribe_all(self)
