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

# T006 WP4: when a scenario sets rules.full_ai the strategic AI plays the WHOLE
# data-driven tree (research, every building tier, unit mix from all producers)
# instead of only the vanilla outpost/HQ loop. Everything below is opt-in via
# world state, so vanilla behaviour (and its golden hashes) is untouched.
const RULES_SECTION: String = "rules"

# Fallback faction prefix used when rules.full_ai is set but faction_prefix is
# empty. Keeps the AI inside its own faction content.
const DEFAULT_FACTION_PREFIX: String = "fr_"

# T006B WP3: a full-tree AI does not commit its all-in before this tick, so it has
# time to actually play the tree (late buildings, tech, late units) instead of
# trading early armies in a rush. Mirror of the personality attack timing.
const FULL_TREE_MIN_ATTACK_TICK: int = 6500
# T006 WP4: how large an army a full-tree AI masses before it commits to a push.
const FULL_TREE_ATTACK_ARMY: int = 30

# Cap on buildings the full-tree AI tries to own (keeps placement bounded and the
# match finite). The first N by the deterministic order are pursued.
const FULL_TREE_BUILDING_CAP: int = 14

# How many production buildings the full-tree AI keeps a unit queue running on at
# once (round-robin over the sorted producer ids) so its army is a real MIX.
const FULL_TREE_PRODUCER_FANOUT: int = 4

# Gold held back each pass for the next reachable building so the tree keeps
# growing; capped so unit production never stalls behind an expensive tier.
const FULL_TREE_UNIT_RESERVE: int = 60
const FULL_TREE_UNIT_RESERVE_CAP: int = 200

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
	# T006B WP2: the 4th personality. Masses the largest army and expands
	# least; its building/unit priorities live in FullTreeOrderUtil.
	"defensive":  { "attack_army_size": 8, "expansion_cap": 1, "upgrade_reserve": 350, "research_first": true },
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
	# MD10.5: consult the staged decision pipeline for the CURRENT macro priority
	# and let it choose whether research or economy is planned FIRST this pass.
	# This replaces the hard-coded research_first flag as the primary driver while
	# keeping the exact same set of Commands (build_building / research_tech /
	# upgrade_building / move). The named research_first preset remains the
	# deterministic FALLBACK whenever the pipeline yields nothing decisive
	# (empty context / no HQ), so existing strategic tests do not regress.
	var research_first: bool = _economy_or_research_first(owner, personality)
	# T006 WP4: a full_ai scenario drives the whole tree instead of the vanilla
	# outpost loop. The army posture below still runs so the AI fights.
	if _full_ai_enabled() and bool(flags.get("economy", true)):
		_plan_full_tree(owner)
		if bool(flags.get("hq_upgrade", true)):
			_plan_hq_upgrade(owner, personality)
		_plan_army_posture(owner, personality)
		return
	# Priority order is intentional: secure tech/economy first, then decide
	# whether to keep massing or to commit to the attack.
	if research_first:
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


# MD10.5: decide whether RESEARCH or ECONOMY is planned first this pass, using
# the staged decision pipeline's macro priority. The pipeline reads the same MD7
# context vector the placement selector uses, evaluates the owner's policy +
# derived weights, and returns one macro priority. We map that to the boolean
# the existing planner ordering already understands:
#   research -> research first; economy/defense/expansion -> economy first.
# When the pipeline cannot decide (no HQ / empty context), we fall back to the
# legacy named preset's research_first flag so behaviour is preserved.
func _economy_or_research_first(owner: int, personality: Dictionary) -> bool:
	var legacy_default: bool = bool(personality.get("research_first", true))
	var hq: Dictionary = _find_hq(owner)
	if hq.is_empty():
		return legacy_default
	var context: Dictionary = _placement_context(owner)
	var profile_weights: Dictionary = _pipeline_weights(owner)
	var policy: Array = _pipeline_policy(owner)
	var action: Dictionary = AiDecisionPipelineUtil.decide(context, policy, profile_weights, {}, {
		"match_seed": 0, "tick": int(nexus.world_state.current_tick), "owner": owner,
	})
	var priority: String = str(action.get("priority", ""))
	match priority:
		AiDecisionPipelineUtil.PRIORITY_RESEARCH:
			return true
		AiDecisionPipelineUtil.PRIORITY_ECONOMY, AiDecisionPipelineUtil.PRIORITY_EXPANSION, AiDecisionPipelineUtil.PRIORITY_DEFENSE:
			return false
		_:
			# Attack / diplomacy / unknown: keep the legacy preset ordering.
			return legacy_default


# MD10.5: the MD5 derived weights for the owner's decision pipeline. A
# profile-driven AI derives from its stored AiProfile id (via the reputation /
# profile lookup would go here in a full integration); today the strategic
# module has no live AiProfile handle, so it uses the neutral (all-fair) weight
# set, which is deterministic and reproduces balanced macro priorities. This
# keeps the wiring lockstep-safe until MD14 threads the full profile through.
func _pipeline_weights(_owner: int) -> Dictionary:
	return AiWeightDerivationUtil.derive_weights(null)


# MD10.5: the MD6 policy for the owner. Absent a live AiProfile the policy is
# empty, which AiPolicyUtil treats as the baseline (attacking allowed, no hard
# biases) -- i.e. exactly the current behaviour. A future phase can derive this
# from the profile / named archetype.
func _pipeline_policy(_owner: int) -> Array:
	return []


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
	# T006 WP4: skip when the HQ archetype defines no upgrade levels (avoids a
	# pointless max_level rejection every planning pass).
	var hq_archetype: Variant = nexus.data_loader.get_entry("buildings", str(hq.get("type", "")))
	if hq_archetype is Dictionary and (hq_archetype as Dictionary).get("upgrades", {}).is_empty():
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
	# T006 WP4: a full-tree AI masses a real army before committing, so the duel is a
	# build-up (not a rush) and the winner has had time to complete its tree.
	if _full_ai_enabled():
		# T006B WP2: the personality table sets how big an army must mass before
		# the all-in, so aggressive pushes sooner and defensive masses longer.
		threshold = max(threshold, FullTreeOrderUtil.full_tree_army_size(_personality_name(owner)))
	var army: Array = _combat_units(owner)
	var section: Dictionary = nexus.world_state.get_section(SECTION)
	var posture_map: Dictionary = section["posture"]

	var under_threat: bool = _enemy_near_base(owner)
	var ready_to_attack: bool = army.size() >= threshold
	# T006B WP3: full-tree AIs hold the push until the tree has matured, so the
	# duel is a build-up that reaches the late buildings/units (and lasts long
	# enough for them to matter). Vanilla AIs are unaffected.
	if _full_ai_enabled() and int(nexus.world_state.current_tick) < FULL_TREE_MIN_ATTACK_TICK:
		ready_to_attack = false
		under_threat = false

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


# P7.5 team-awareness: two owners are hostile unless they share a team (read
# from the "match" section, mirroring CombatModule._is_hostile). Without this
# the strategic all-in targeted TEAMMATE HQs in team/ctf modes and rallied
# defensively against friendly patrols. Deterministic: pure world-state read.
func _is_hostile(owner_a: int, owner_b: int) -> bool:
	if owner_a == owner_b:
		return false
	var teams: Dictionary = nexus.world_state.get_section("match").get("teams", {})
	var team_a: int = int(teams.get(str(owner_a), owner_a))
	var team_b: int = int(teams.get(str(owner_b), owner_b))
	return team_a != team_b


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
		if not _is_hostile(owner, int(b.get("owner", owner))) or int(b.get("health", 0)) <= 0:
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
		if not _is_hostile(owner, int(u.get("owner", owner))) or int(u.get("health", 0)) <= 0:
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
		if not _is_hostile(owner, int(u.get("owner", owner))) or int(u.get("health", 0)) <= 0:
			continue
		var d: int = abs(hx - int(u.get("x", 0))) + abs(hy - int(u.get("y", 0)))
		if d <= 5:
			return true
	return false


# --- T006 WP4: full-tree planner (rules.full_ai) ----------------------------

# True when the current scenario opted into full-tree AI play. Reads the "rules"
# section WITHOUT creating it (get_section() would add an empty section to vanilla
# matches and change the world hash -- the A1 lock).
func _full_ai_enabled() -> bool:
	if not nexus.world_state.has_section(RULES_SECTION):
		return false
	return bool(nexus.world_state.get_section(RULES_SECTION).get("full_ai", false))


func _faction_prefix() -> String:
	if nexus.world_state.has_section(RULES_SECTION):
		var p: String = str(nexus.world_state.get_section(RULES_SECTION).get("faction_prefix", ""))
		if p != "":
			return p
	return DEFAULT_FACTION_PREFIX


func _wallet(owner: int) -> Dictionary:
	return nexus.world_state.get_section("economy").get("players", {}).get(str(owner), {})


# The set of building types `owner` owns COMPLETED (health > 0, not a build site).
func _completed_types(owner: int) -> Array:
	return PrereqUtil.owner_completed_building_types(_buildings(), owner)


func _researched_ids(owner: int) -> Array:
	return nexus.world_state.get_section("tech").get("players", {}).get(str(owner), {}).get("researched", [])


func _in_progress_ids(owner: int) -> Array:
	var ip: Dictionary = nexus.world_state.get_section("tech").get("players", {}).get(str(owner), {}).get("in_progress", {})
	var keys: Array = ip.keys()
	keys.sort()
	return keys


func _all_tech_nodes() -> Dictionary:
	var out: Dictionary = {}
	var catalog: Dictionary = nexus.data_loader.get_catalog("tech")
	var trees: Array = catalog.keys()
	trees.sort()
	for tree_id in trees:
		var doc: Variant = catalog[tree_id]
		if not (doc is Dictionary):
			continue
		for node in (doc as Dictionary).get("nodes", []):
			if node is Dictionary and str(node.get("id", "")) != "":
				out[str(node["id"])] = node
	return out


# One full-tree planning pass: research the cheapest reachable tech, then build
# the next reachable building (economy/production/defense in tree order), then
# keep a unit queue running on its production buildings. Every order goes through
# the normal command path, so the owning module still enforces prerequisites,
# cost and pop_cap -- the AI simply never issues a doomed order.
func _plan_full_tree(owner: int) -> void:
	var completed: Array = _completed_types(owner)
	var researched: Array = _researched_ids(owner)
	# T006B WP2: the flexible personality table (FullTreeOrderUtil.PERSONALITY_PLAN)
	# biases building priority and unit mix without any branching code here.
	var name: String = _personality_name(owner)
	_full_tree_research(owner, completed, researched)
	_full_tree_build(owner, completed, researched, FullTreeOrderUtil.build_bias(name), FullTreeOrderUtil.build_avoid(name))
	_full_tree_units(owner, FullTreeOrderUtil.unit_bias(name), FullTreeOrderUtil.build_bias(name), FullTreeOrderUtil.build_avoid(name))


# T006B WP2: the effective personality name for an owner ("balanced" default).
func _personality_name(owner: int) -> String:
	return str(nexus.world_state.get_section(SECTION).get("controlled", {}).get(str(owner), "balanced"))


func _full_tree_research(owner: int, completed: Array, researched: Array) -> void:
	if not _in_progress_ids(owner).is_empty():
		return
	var nodes: Dictionary = _all_tech_nodes()
	var order: Array = FullTreeOrderUtil.tech_order(nodes, completed, researched, _in_progress_ids(owner))
	var wallet: Dictionary = _wallet(owner)
	for node_id in order:
		var node: Dictionary = nodes.get(node_id, {})
		if FullTreeOrderUtil.can_afford(node.get("cost", {}), wallet):
			nexus.issue_command("research_tech", owner, { "owner": owner, "node_id": node_id }, 1)
			return


func _full_tree_build(owner: int, completed: Array, researched: Array, bias: Array = [], avoid: Array = []) -> void:
	if completed.size() >= FULL_TREE_BUILDING_CAP:
		return
	var catalog: Dictionary = nexus.data_loader.get_catalog("buildings")
	var order: Array = FullTreeOrderUtil.building_order(catalog, _faction_prefix(), completed, researched, bias, avoid)
	if order.is_empty():
		return
	var hq: Dictionary = _find_hq(owner)
	if hq.is_empty():
		return
	var hx: int = int(hq.get("x", 0))
	var hy: int = int(hq.get("y", 0))
	var wallet: Dictionary = _wallet(owner)
	# Build the FIRST reachable building we can afford this pass; if we cannot
	# afford it yet, wait (income grows) rather than skipping ahead in the tree.
	for building_id in order:
		var entry: Dictionary = catalog.get(building_id, {})
		if not FullTreeOrderUtil.can_afford(entry.get("cost", {}), wallet):
			return
		var spot: Vector2i = _smart_build_spot(owner, building_id, hx, hy)
		if spot.x < 0:
			spot = _find_build_spot(hx, hy, owner)
		if spot.x < 0:
			return
		nexus.issue_command("build_building", owner, {
			"type": building_id, "owner": owner, "x": spot.x, "y": spot.y,
		}, 1)
		return


# Keep a unit queue running on up to FULL_TREE_PRODUCER_FANOUT production
# buildings, round-robin by owner so the army is a real mix. Choice of unit is
# data-driven (UnitCandidateUtil) restricted to the producer buildable_units.
func _full_tree_units(owner: int, unit_bias: Array = [], build_bias: Array = [], build_avoid: Array = []) -> void:
	var producers: Array = _production_buildings(owner)
	if producers.is_empty():
		return
	var catalog: Dictionary = nexus.data_loader.get_catalog("units")
	var prefix: String = _faction_prefix()
	var completed: Array = _completed_types(owner)
	var researched: Array = _researched_ids(owner)
	var used: int = 0
	var tick: int = int(nexus.world_state.current_tick)
	# While the tree is still growing, hold back enough gold for the next reachable
	# building so the AI does not pour every coin into units. Capped so unit
	# production never stalls behind an expensive tier.
	var reserve: int = 0
	if completed.size() < FULL_TREE_BUILDING_CAP:
		reserve = min(_next_building_cost(owner, completed, researched, build_bias, build_avoid), FULL_TREE_UNIT_RESERVE_CAP)
	# Unit types the owner has already fielded (or has queued): used to prefer a
	# NEW type from each producer so the army is a real mix, not one unit spam.
	var fielded: Dictionary = _fielded_unit_types(owner)
	# Rotate which producers get a turn each pass so every production building is
	# eventually used (the army becomes a mix, not one building spamming a unit).
	var start: int = int(tick / DEFAULT_PLAN_INTERVAL + owner) % producers.size()
	for i in range(producers.size()):
		if used >= FULL_TREE_PRODUCER_FANOUT:
			break
		var b: Dictionary = producers[(start + i) % producers.size()]
		var allowed: Array = []
		for uid in b.get("buildable_units", []):
			var uid_s: String = str(uid)
			if prefix != "" and not uid_s.begins_with(prefix):
				continue
			if not catalog.has(uid_s):
				continue
			if not PrereqUtil.missing((catalog[uid_s] as Dictionary).get("requires", {}), completed, researched).is_empty():
				continue
			var unit_cost: Dictionary = (catalog[uid_s] as Dictionary).get("cost", {})
			if not FullTreeOrderUtil.can_afford(unit_cost, _wallet(owner)):
				continue
			if _gold(owner) - FullTreeOrderUtil.total_cost(catalog[uid_s] as Dictionary) < reserve:
				continue
			allowed.append(uid_s)
		if allowed.is_empty():
			continue
		# T006B WP2: order the buildable types by the personality's unit bias, so
		# each personality fields a different mix from the same building.
		_sort_by_bias(allowed, unit_bias)
		var queue: Array = b.get("build_queue", [])
		if queue.size() >= 1:
			used += 1
			continue
		# Diversity first: build a type this owner has not fielded yet; otherwise let
		# the data-driven utility chooser decide (it may reinforce an existing type).
		var unit_type: String = ""
		for uid2 in allowed:
			if not fielded.has(uid2):
				unit_type = uid2
				break
		if unit_type == "":
			unit_type = _full_tree_pick_unit(catalog, allowed, owner, tick)
		if unit_type == "":
			continue
		nexus.issue_command("build_unit", owner, {
			"owner": owner, "building_id": int(b.get("id", -1)), "unit_type": unit_type,
		}, 1)
		fielded[unit_type] = true
		used += 1


# Unit types the owner currently has alive OR queued in a building (the "mix" the
# full-tree AI is trying to broaden). Deterministic, sorted iteration.
func _fielded_unit_types(owner: int) -> Dictionary:
	var out: Dictionary = {}
	var units: Dictionary = _units()
	var ukeys: Array = units.keys()
	ukeys.sort_custom(func(a, b): return int(a) < int(b))
	for key in ukeys:
		var u: Dictionary = units[key]
		if int(u.get("owner", -1)) == owner and int(u.get("health", 0)) > 0:
			out[str(u.get("type", ""))] = true
	var buildings: Dictionary = _buildings()
	var bkeys: Array = buildings.keys()
	bkeys.sort_custom(func(a, b): return int(a) < int(b))
	for key in bkeys:
		var b: Dictionary = buildings[key]
		if int(b.get("owner", -1)) != owner:
			continue
		for item in b.get("build_queue", []):
			out[str((item as Dictionary).get("type", ""))] = true
	return out


# Gold currently in the owner's wallet.
func _gold(owner: int) -> int:
	return int(_wallet(owner).get(RESOURCE, 0))


# Total gold cost of the next reachable building (0 when the tree is done/blocked).
func _next_building_cost(owner: int, completed: Array, researched: Array, bias: Array = [], avoid: Array = []) -> int:
	var catalog: Dictionary = nexus.data_loader.get_catalog("buildings")
	var order: Array = FullTreeOrderUtil.building_order(catalog, _faction_prefix(), completed, researched, bias, avoid)
	if order.is_empty():
		return 0
	return FullTreeOrderUtil.total_cost(catalog.get(order[0], {}))


# Production buildings the owner has finished, id-sorted, that can build units.
func _production_buildings(owner: int) -> Array:
	var out: Array = []
	var list: Dictionary = _buildings()
	var keys: Array = list.keys()
	keys.sort_custom(func(a, b): return int(a) < int(b))
	for key in keys:
		var b: Dictionary = list[key]
		if int(b.get("owner", -1)) != owner:
			continue
		if int(b.get("health", 0)) <= 0 or int(b.get("construction_remaining", 0)) > 0:
			continue
		if (b.get("buildable_units", []) as Array).is_empty():
			continue
		out.append(b)
	# T006B WP2: once real producers exist, drop the HQ from the unit queue. The
	# citadel builds militia/scout, and letting it spam adds the SAME type for every
	# personality, flattening the unit mix the personality table is meant to vary.
	# Early game (HQ is the only producer) it still produces, so nobody stalls.
	if out.size() > 1:
		var hq: Dictionary = _find_hq(owner)
		var hq_id: int = int(hq.get("id", -1))
		var filtered: Array = []
		for b2 in out:
			if int(b2.get("id", -1)) != hq_id:
				filtered.append(b2)
		if not filtered.is_empty():
			out = filtered
	return out


# T006B WP2: stable-sort ids so the ones listed in `bias` (in bias order) come
# first; the rest keep their existing order. Deterministic.
func _sort_by_bias(ids: Array, bias: Array) -> void:
	if bias.is_empty():
		return
	var rank: Dictionary = {}
	for i in range(bias.size()):
		rank[str(bias[i])] = i
	ids.sort_custom(func(a, b):
		var ra: int = int(rank.get(str(a), 1 << 30))
		var rb: int = int(rank.get(str(b), 1 << 30))
		if ra != rb:
			return ra < rb
		return str(a) < str(b))


func _full_tree_pick_unit(catalog: Dictionary, allowed: Array, owner: int, tick: int) -> String:
	if allowed.is_empty():
		return ""
	var weights: Dictionary = AiWeightDerivationUtil.derive_weights(null)
	var context: Dictionary = AiContextUtil.build_context(_full_tree_summary(owner), owner)
	var seed_value: int = int(nexus.world_state.random_seed)
	return UnitCandidateUtil.choose_unit(
		catalog, weights, context, seed_value, tick, owner, 0,
		null, null, allowed, str(allowed[0]))


# A minimal deterministic world summary for the unit chooser (the same shape
# AiContextUtil expects). Kept small: enough to bias toward a mixed army.
func _full_tree_summary(owner: int) -> Dictionary:
	var hq: Dictionary = _find_hq(owner)
	var own: Array = []
	var enemy: Array = []
	var units: Dictionary = _units()
	var ukeys: Array = units.keys()
	ukeys.sort_custom(func(a, b): return int(a) < int(b))
	for key in ukeys:
		var u: Dictionary = units[key]
		if int(u.get("health", 0)) <= 0:
			continue
		var rec: Dictionary = { "id": int(u.get("id", 0)), "x": int(u.get("x", 0)), "y": int(u.get("y", 0)), "health": int(u.get("health", 0)) }
		if int(u.get("owner", -1)) == owner:
			own.append(rec)
		else:
			enemy.append(rec)
	return {
		"hq": {} if hq.is_empty() else { "x": int(hq.get("x", 0)), "y": int(hq.get("y", 0)) },
		"own_units": own,
		"enemy_units": enemy,
		"enemy_buildings": [],
		"own_economy": _resources(owner),
		"enemy_economy": 0,
		"own_army": own.size(),
		"enemy_army": enemy.size(),
	}

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
