# ai_commander_module.gd
# ----------------------------------------------------------------------------
# Project Nexus - AI Commander Module (Phase 3 head-start, steps 3.1 + 3.2 + 3.3).
#
# A simple but FULLY DETERMINISTIC computer opponent. Without it the Phase 1
# skirmish has a passive enemy that just stands still, so this module makes the
# single-player game actually playable end-to-end.
#
# Design rules it obeys (the project "constitution"):
#   - It is a normal module: it depends ONLY on the core. It reads world state
#     and issues COMMANDS through the Nexus; it never mutates units/buildings
#     directly and never references another module.
#   - It is deterministic: it only acts on fixed tick boundaries, iterates over
#     sorted keys, and breaks every tie by lowest id. Same world state + same
#     tick always produce the same decisions -> lockstep-safe (Phase 4).
#   - It is data-driven where it matters: which players are AI-controlled and
#     the difficulty knobs come from world state / scenario, not hard-code.
#
# Behaviour (per controlled player), evaluated every `think_interval` ticks:
#   1) Economy : if it can afford a soldier and its HQ build queue is short,
#                issue a build_unit command at its HQ.
#   2) Offense : every idle (path-less) combat unit is ordered to march toward
#                the nearest enemy entity (unit first, else building/HQ).
#
# Difficulty is expressed as a multiplier on how often the AI thinks and how
# aggressively it spends (read from world state section "ai").
#
# CODE LANGUAGE POLICY: English-only identifiers/comments.
# ----------------------------------------------------------------------------
class_name AiCommanderModule
extends IModule

const SECTION: String = "ai"

# How many simulation ticks between AI decision passes (overridable per match).
const DEFAULT_THINK_INTERVAL: int = 10

# Difficulty presets -> { think_interval, build_chance_pct, aggression, max_queue }.
# build_chance_pct gates production so easier AIs build more slowly; max_queue is
# the Phase 6 balance knob that lets harder AIs sustain a deeper build pipeline
# (more continuous pressure) while easier AIs keep a shallow queue. It is read
# deterministically per difficulty, so determinism is preserved.
const DIFFICULTY: Dictionary = {
	"easy":   { "think_interval": 25, "build_chance_pct": 35, "aggression": 0, "max_queue": 1 },
	"normal": { "think_interval": 15, "build_chance_pct": 70, "aggression": 1, "max_queue": 2 },
	"hard":   { "think_interval": 8,  "build_chance_pct": 100, "aggression": 1, "max_queue": 3 },
}

# Fallback queue depth when a difficulty preset omits the knob (keeps the prior
# behaviour for any custom/legacy difficulty that does not specify it).
const DEFAULT_MAX_QUEUE: int = 2

# MD8.5: default seeded difficulty-noise band (q, SCALE=1000) applied to unit
# utility scores when a difficulty preset omits its own "noise_q". Kept small so
# it only breaks near-ties, and always > 0 so even the hardest AI is imperfect
# (expert item / MC13.4). A per-difficulty "noise_q" can override this.
const DEFAULT_NOISE_Q: int = 40


func module_id() -> String:
	return "ai_commander"


func init(p_nexus: Object) -> void:
	super.init(p_nexus)
	_ensure_state()


func _ensure_state() -> void:
	var section: Dictionary = nexus.world_state.get_section(SECTION)
	if not section.has("controlled"):
		# owner(int as String) -> difficulty name. Populated by scenario setup.
		section["controlled"] = {}
	if not section.has("difficulty"):
		section["difficulty"] = "normal"


# --- Public configuration (called by scenario loader) -----------------------

# Mark a player as AI-controlled with a difficulty name.
func set_ai_player(owner: int, difficulty: String) -> void:
	var section: Dictionary = nexus.world_state.get_section(SECTION)
	(section["controlled"] as Dictionary)[str(owner)] = difficulty


# --- Deterministic think loop -----------------------------------------------

func on_tick(_delta_tick: int) -> void:
	var tick: int = int(nexus.world_state.current_tick)
	var controlled: Dictionary = nexus.world_state.get_section(SECTION).get("controlled", {})
	if controlled.is_empty():
		return
	# Stable iteration over the AI-controlled players.
	var owners: Array = controlled.keys()
	owners.sort()
	for owner_key in owners:
		var owner: int = int(owner_key)
		var diff_name: String = str(controlled[owner_key])
		var diff: Dictionary = DIFFICULTY.get(diff_name, DIFFICULTY["normal"])
		var interval: int = int(diff.get("think_interval", DEFAULT_THINK_INTERVAL))
		# Phase-shift by owner so multiple AIs do not all act on the same tick.
		if (tick + owner) % interval != 0:
			continue
		_think_for_player(owner, diff)


func _think_for_player(owner: int, diff: Dictionary) -> void:
	_manage_economy(owner, diff)
	_manage_offense(owner, diff)


# --- Economy: queue soldiers at the AI HQ -----------------------------------

func _manage_economy(owner: int, diff: Dictionary) -> void:
	# Deterministic "chance": use the tick + owner as a stable pseudo-roll so
	# the decision is reproducible (no real RNG -> lockstep safe).
	var roll: int = (int(nexus.world_state.current_tick) * 31 + owner * 7) % 100
	if roll >= int(diff.get("build_chance_pct", 70)):
		return
	var hq: Dictionary = _find_hq(owner)
	if hq.is_empty():
		return
	# Do not over-queue: keep at most `max_queue` units in the build queue
	# (a difficulty-driven balance knob -- harder AIs sustain a deeper pipeline).
	var queue: Array = hq.get("build_queue", [])
	var max_queue: int = int(diff.get("max_queue", DEFAULT_MAX_QUEUE))
	if queue.size() >= max_queue:
		return
	# MD8.5: pick the best-fit unit via the utility pipeline instead of the old
	# hard-coded "soldier". Backward compatible: with a single-unit catalog (or
	# no profile) the selector returns that unit / the same defensive default.
	var unit_type: String = _choose_unit_type(owner, diff)
	nexus.issue_command("build_unit", owner, {
		"owner": owner,
		"building_id": int(hq["id"]),
		"unit_type": unit_type,
	}, 1)


# MD8.5: run the data-driven unit-selection pipeline for `owner`. Reads the live
# unit catalog + derives the AI's profile weights + the deterministic context
# vector, then delegates the pure scoring to UnitCandidateUtil. Deterministic:
# every input (catalog, seed, tick, owner, context) is stable, so all peers pick
# the same unit. Falls back to "soldier" on any missing data (resilience).
func _choose_unit_type(owner: int, diff: Dictionary) -> String:
	var catalog: Dictionary = nexus.data_loader.get_catalog("units")
	if catalog.is_empty():
		return "soldier"
	var weights: Dictionary = AiWeightDerivationUtil.derive_weights(_profile_for(owner))
	var context: Dictionary = AiContextUtil.build_context(summarize(owner), owner)
	var seed_value: int = int(nexus.world_state.random_seed)
	var tick: int = int(nexus.world_state.current_tick)
	var noise_q: int = int(diff.get("noise_q", DEFAULT_NOISE_Q))
	return UnitCandidateUtil.choose_unit(
		catalog, weights, context, seed_value, tick, owner, noise_q,
		null, null, [], "soldier")


# The AiProfile object backing `owner`, or null for a legacy named AI (in which
# case the neutral weights preserve the prior behaviour). The strategic module
# owns profile registration; the profile object is not stored in world state, so
# a legacy AI simply scores by base capabilities (backward compatible).
func _profile_for(_owner: int) -> Object:
	return null


# --- Offense: march idle units toward the nearest enemy ---------------------

func _manage_offense(owner: int, _diff: Dictionary) -> void:
	var units: Dictionary = _units()
	var keys: Array = units.keys()
	keys.sort_custom(func(a, b): return int(a) < int(b))
	for key in keys:
		var unit: Dictionary = units[key]
		if int(unit.get("owner", -1)) != owner:
			continue
		if int(unit.get("health", 0)) <= 0:
			continue
		# Only redirect idle units (those without a current path).
		if not (unit.get("path", []) as Array).is_empty():
			continue
		var target: Dictionary = _nearest_enemy(unit, owner)
		if target.is_empty():
			continue
		nexus.issue_command("move_unit", owner, {
			"unit_ids": [int(unit["id"])],
			"x": int(target["x"]),
			"y": int(target["y"]),
		}, 1)


# --- Target / HQ lookup helpers ---------------------------------------------

# P7.5 team-awareness: two owners are hostile unless they share a team (read
# from the "match" section, mirroring CombatModule._is_hostile). Without this
# the AI marched on TEAMMATES in team/ctf modes and then never fought them.
# Owners without a team entry default to their own one-player team (FFA
# behaviour unchanged). Deterministic: pure world-state read.
func _is_hostile(owner_a: int, owner_b: int) -> bool:
	if owner_a == owner_b:
		return false
	var teams: Dictionary = nexus.world_state.get_section("match").get("teams", {})
	var team_a: int = int(teams.get(str(owner_a), owner_a))
	var team_b: int = int(teams.get(str(owner_b), owner_b))
	return team_a != team_b


func _nearest_enemy(unit: Dictionary, owner: int) -> Dictionary:
	var ux: int = int(unit["x"])
	var uy: int = int(unit["y"])
	var best: Dictionary = {}
	var best_dist: int = 1 << 30
	var best_id: int = 1 << 30

	# Enemy units first.
	var units: Dictionary = _units()
	var ukeys: Array = units.keys()
	ukeys.sort_custom(func(a, b): return int(a) < int(b))
	for key in ukeys:
		var other: Dictionary = units[key]
		if not _is_hostile(owner, int(other.get("owner", owner))):
			continue
		if int(other.get("health", 0)) <= 0:
			continue
		var d: int = abs(ux - int(other["x"])) + abs(uy - int(other["y"]))
		var oid: int = int(other["id"])
		if d < best_dist or (d == best_dist and oid < best_id):
			best = other
			best_dist = d
			best_id = oid
	if not best.is_empty():
		return best

	# Otherwise march on the nearest enemy building (their HQ).
	var buildings: Dictionary = _buildings()
	var bkeys: Array = buildings.keys()
	bkeys.sort_custom(func(a, b): return int(a) < int(b))
	for key in bkeys:
		var b: Dictionary = buildings[key]
		if not _is_hostile(owner, int(b.get("owner", owner))):
			continue
		if int(b.get("health", 0)) <= 0:
			continue
		var d2: int = abs(ux - int(b["x"])) + abs(uy - int(b["y"]))
		var bid: int = int(b["id"])
		if d2 < best_dist or (d2 == best_dist and bid < best_id):
			best = b
			best_dist = d2
			best_id = bid
	return best


func _find_hq(owner: int) -> Dictionary:
	var buildings: Dictionary = _buildings()
	var keys: Array = buildings.keys()
	keys.sort_custom(func(a, b): return int(a) < int(b))
	for key in keys:
		var b: Dictionary = buildings[key]
		if int(b.get("owner", -1)) == owner:
			return b
	return {}


# --- MD7.2: world summary for the deterministic Context Vector --------------

# Build the PLAIN, owner-relative world summary that AiContextUtil.build_context
# consumes. This lives in the MODULE (not the pure util) so the util stays free
# of any world-model dependency and remains headlessly testable: the module
# reads the live world model here and hands the util a flat snapshot.
#
# The summary is deterministic (every list is folded from id-sorted section
# keys) and contains only the fields the context vector documents. Returns a
# plain Dictionary suitable to pass straight to AiContextUtil.build_context.
func summarize(owner: int) -> Dictionary:
	var hq: Dictionary = _find_hq(owner)
	var own_units: Array = []
	var enemy_units: Array = []
	var enemy_buildings: Array = []
	var own_army: int = 0
	var enemy_army: int = 0

	var units: Dictionary = _units()
	var ukeys: Array = units.keys()
	ukeys.sort_custom(func(a, b): return int(a) < int(b))
	for key in ukeys:
		var u: Dictionary = units[key]
		if int(u.get("health", 0)) <= 0:
			continue
		var entry: Dictionary = {
			"id": int(u.get("id", 0)),
			"x": int(u.get("x", 0)),
			"y": int(u.get("y", 0)),
			"health": int(u.get("health", 0)),
		}
		if int(u.get("owner", -1)) == owner:
			own_units.append(entry)
			own_army += 1
		else:
			enemy_units.append(entry)
			enemy_army += 1

	var buildings: Dictionary = _buildings()
	var bkeys: Array = buildings.keys()
	bkeys.sort_custom(func(a, b): return int(a) < int(b))
	for key in bkeys:
		var b: Dictionary = buildings[key]
		if int(b.get("health", 0)) <= 0:
			continue
		if int(b.get("owner", -1)) != owner:
			enemy_buildings.append({
				"id": int(b.get("id", 0)),
				"x": int(b.get("x", 0)),
				"y": int(b.get("y", 0)),
				"health": int(b.get("health", 0)),
			})

	var econ: Dictionary = nexus.world_state.get_section("economy")
	var own_economy: int = int(_economy_for(econ, owner))
	var enemy_economy: int = int(_enemy_economy(econ, owner))

	return {
		"hq": hq if hq.is_empty() else { "x": int(hq.get("x", 0)), "y": int(hq.get("y", 0)) },
		"own_units": own_units,
		"enemy_units": enemy_units,
		"enemy_buildings": enemy_buildings,
		"own_economy": own_economy,
		"enemy_economy": enemy_economy,
		"own_army": own_army,
		"enemy_army": enemy_army,
		"has_ally": false,
		"in_active_war": enemy_army > 0 or enemy_buildings.size() > 0,
	}


# The stored economy score for one owner (resilient: 0 when absent). The economy
# section stores per-owner WALLETS under "players": owner(str) -> { resource_id
# -> amount }. Resource ids are data-driven (mods may add their own), so the
# score is the deterministic SUM over the wallet's sorted keys -- never a
# hard-coded id. Legacy flat shapes ("balances", plain int, "gold"/"stored")
# are still honoured for old saves/tests.
func _economy_for(econ: Dictionary, owner: int) -> int:
	var players: Variant = econ.get("players", econ.get("balances", {}))
	if players is Dictionary and (players as Dictionary).has(str(owner)):
		var rec: Variant = (players as Dictionary)[str(owner)]
		if rec is Dictionary:
			return _wallet_total(rec as Dictionary)
		return int(rec)
	return int(econ.get("gold", 0))


# Deterministic total of a wallet dictionary (resource_id -> amount). Sorted
# keys keep the fold order stable; legacy "gold"/"stored" keys are just wallet
# entries and sum naturally.
func _wallet_total(wallet: Dictionary) -> int:
	var total: int = 0
	var keys: Array = wallet.keys()
	keys.sort()
	for key in keys:
		total += int(wallet[key])
	return total


# Summed economy score of every non-owner player (0 when none / absent).
func _enemy_economy(econ: Dictionary, owner: int) -> int:
	var players: Variant = econ.get("players", econ.get("balances", {}))
	if not (players is Dictionary):
		return 0
	var total: int = 0
	var keys: Array = (players as Dictionary).keys()
	keys.sort()
	for key in keys:
		if int(key) == owner:
			continue
		var rec: Variant = (players as Dictionary)[key]
		if rec is Dictionary:
			total += _wallet_total(rec as Dictionary)
		else:
			total += int(rec)
	return total


func _units() -> Dictionary:
	return nexus.world_state.get_section("units").get("list", {})


func _buildings() -> Dictionary:
	return nexus.world_state.get_section("buildings").get("list", {})


# --- Save / load ------------------------------------------------------------

func serialize() -> Dictionary:
	return {}


func deserialize(_data: Dictionary) -> void:
	pass


func shutdown() -> void:
	if nexus != null:
		nexus.event_bus.unsubscribe_all(self)
