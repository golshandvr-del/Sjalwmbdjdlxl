# economy_module.gd
# ----------------------------------------------------------------------------
# Project Nexus - Economy Module (Phase 1, step 1.7).
#
# Tracks each player's resources and runs the production tick: every building
# that "produces" resources adds them to its owner's stockpile. Also validates
# and pays for unit-production requests.
#
# Decoupling: it reads the "buildings" section to know who produces what, but
# never calls the Buildings module's methods. It owns the "economy" section.
#
# economy section layout:
#   {
#     "players": { owner(String) -> { resource_id -> amount } }
#   }
#
# CODE LANGUAGE POLICY: English-only identifiers/comments.
# ----------------------------------------------------------------------------
class_name EconomyModule
extends IModule

const SECTION: String = "economy"
const UNIT_CATALOG: String = "units"

const CMD_BUILD_UNIT: String = "command.build_unit"   # player wants to build a unit
const EVENT_RESOURCES_CHANGED: String = "economy.resources_changed"
const EVENT_BUILD_REJECTED: String = "economy.build_rejected"

# BUG-1 fix (P0.1): resource production is TIME-BASED, not per-tick. A building's
# `produces` block is applied only once every PRODUCTION_INTERVAL_TICKS ticks
# (deterministically keyed off WorldState.current_tick, never real delta), so a
# high tick_rate / time_scale can no longer cause runaway resource growth. With
# tick_rate=20 and interval=20, `produces: {resource_basic: N}` yields ~N units
# per simulated second. A building may override this with a per-archetype
# `production_interval_ticks` field.
const PRODUCTION_INTERVAL_TICKS: int = 20


func module_id() -> String:
	return "economy"


func init(p_nexus: Object) -> void:
	super.init(p_nexus)
	nexus.subscribe(CMD_BUILD_UNIT, self, "_on_bus_event")
	_ensure_state()


func _ensure_state() -> void:
	var section: Dictionary = nexus.world_state.get_section(SECTION)
	if not section.has("players"):
		section["players"] = {}


# --- Public API -------------------------------------------------------------

func ensure_player(owner: int) -> void:
	var players: Dictionary = _players()
	if not players.has(str(owner)):
		players[str(owner)] = {}


func get_resource(owner: int, resource_id: String) -> int:
	var players: Dictionary = _players()
	var wallet: Dictionary = players.get(str(owner), {})
	return int(wallet.get(resource_id, 0))


func add_resource(owner: int, resource_id: String, amount: int) -> void:
	ensure_player(owner)
	var wallet: Dictionary = _players()[str(owner)]
	wallet[resource_id] = int(wallet.get(resource_id, 0)) + amount
	nexus.emit_event(EVENT_RESOURCES_CHANGED, { "owner": owner, "resource": resource_id, "amount": int(wallet[resource_id]) })


# Try to spend a cost dictionary; returns true and deducts if affordable.
func try_spend(owner: int, cost: Dictionary) -> bool:
	ensure_player(owner)
	var wallet: Dictionary = _players()[str(owner)]
	for resource_id in cost.keys():
		if int(wallet.get(resource_id, 0)) < int(cost[resource_id]):
			return false
	for resource_id in cost.keys():
		wallet[resource_id] = int(wallet.get(resource_id, 0)) - int(cost[resource_id])
	nexus.emit_event(EVENT_RESOURCES_CHANGED, { "owner": owner, "spent": cost.duplicate() })
	return true


# --- Per-tick resource production -------------------------------------------

func on_tick(_delta_tick: int) -> void:
	# BUG-1 fix (P0.1): production is time-based + deterministic. We fire a
	# building's `produces` block only on tick boundaries (current_tick %
	# interval == 0), so the amount grows at a fixed per-second rate independent
	# of tick_rate or the 1x/2x/4x speed multiplier. current_tick is the shared,
	# lockstep-safe clock -- never the real frame delta.
	#
	# TICK CONTRACT (RISK-1 -- read before writing a new module or a test driver):
	#   This module IGNORES the `_delta_tick` argument on purpose and keys every
	#   production decision off nexus.world_state.current_tick. The PRECONDITION is
	#   that current_tick has ALREADY been advanced for this tick before on_tick is
	#   called. The real driver Nexus._run_single_tick() guarantees this (it does
	#   `current_tick += 1` and THEN module_registry.tick_all()). Any alternate
	#   driver (a test, tool, or new module) that calls on_tick() WITHOUT first
	#   advancing current_tick will silently produce nothing -- that was the exact
	#   root cause of the stale GAP-T1 test. If you must call this directly, set
	#   world_state.current_tick to an interval boundary first.
	var current_tick: int = int(nexus.world_state.current_tick)
	var buildings: Dictionary = nexus.world_state.get_section("buildings").get("list", {})
	var keys: Array = buildings.keys()
	keys.sort()
	for key in keys:
		var building: Dictionary = buildings[key]
		# Phase 2: buildings still under construction do not produce yet.
		if int(building.get("construction_remaining", 0)) > 0:
			continue
		var produces: Dictionary = building.get("produces", {})
		if produces.is_empty():
			continue
		var interval: int = max(1, int(building.get("production_interval_ticks", PRODUCTION_INTERVAL_TICKS)))
		# Only pay out on interval boundaries. current_tick == 0 is the initial
		# state before the first tick has advanced, so we skip it to avoid a
		# free payout at spawn time.
		if current_tick <= 0 or current_tick % interval != 0:
			continue
		var owner: int = int(building.get("owner", 0))
		for resource_id in produces.keys():
			add_resource(owner, str(resource_id), int(produces[resource_id]))


# --- Event handling ---------------------------------------------------------

func _on_bus_event(event_name: String, payload: Dictionary) -> void:
	handle_event(event_name, payload)


func handle_event(event_name: String, payload: Dictionary) -> void:
	if event_name == CMD_BUILD_UNIT:
		_handle_build_unit(payload.get("data", {}))


# A player asks a building to build a unit: check cost from the unit archetype,
# spend it, then enqueue production at the building (via a command).
func _handle_build_unit(data: Dictionary) -> void:
	var owner: int = int(data.get("owner", 0))
	var building_id: int = int(data.get("building_id", -1))
	var unit_type: String = str(data.get("unit_type", ""))
	var archetype: Variant = nexus.data_loader.get_entry(UNIT_CATALOG, unit_type)
	if not (archetype is Dictionary):
		nexus.emit_event(EVENT_BUILD_REJECTED, { "owner": owner, "reason": "unknown_unit" })
		return
	var a: Dictionary = archetype
	# BUG-G6 (gameplay audit): validate the WHOLE order BEFORE spending. The old
	# flow charged the cost first and only then issued queue_unit; when queueing
	# failed (building gone, wrong owner, unit not in the building's
	# buildable_units) the money silently burned with no unit and no refund.
	var building: Dictionary = _building_record(building_id)
	if building.is_empty():
		nexus.emit_event(EVENT_BUILD_REJECTED, { "owner": owner, "reason": "unknown_building" })
		return
	if int(building.get("owner", -1)) != owner:
		# Paying for units that would spawn under ANOTHER owner is never a
		# legitimate order (it was also a resource-drain exploit vector).
		nexus.emit_event(EVENT_BUILD_REJECTED, { "owner": owner, "reason": "not_owner" })
		return
	if not (building.get("buildable_units", []) as Array).has(unit_type):
		nexus.emit_event(EVENT_BUILD_REJECTED, { "owner": owner, "reason": "not_buildable_here" })
		return
	# T006 WP1: unit prerequisites -- reject BEFORE spending (check C14).
	var requires: Variant = a.get("requires", {})
	if requires is Dictionary and not (requires as Dictionary).is_empty():
		var completed: Array = PrereqUtil.owner_completed_building_types(
			nexus.world_state.get_section("buildings").get("list", {}), owner)
		var researched: Array = nexus.world_state.get_section("tech").get("players", {}).get(str(owner), {}).get("researched", [])
		var missing: Array = PrereqUtil.missing(requires, completed, researched)
		if not missing.is_empty():
			nexus.emit_event(EVENT_BUILD_REJECTED, { "owner": owner, "reason": "missing_prerequisite", "unit_type": unit_type, "missing": missing })
			return
	# T006 WP1: rules.pop_cap -- alive units + queued items at the cap rejects
	# production (check C21). Vanilla scenarios have no "rules" section, so this
	# is a no-op for them.
	var pop_cap: int = _pop_cap()
	if pop_cap > 0 and _population(owner) >= pop_cap:
		nexus.emit_event(EVENT_BUILD_REJECTED, { "owner": owner, "reason": "pop_cap" })
		return
	var cost: Dictionary = a.get("cost", {})
	var build_time: int = int(a.get("build_time_ticks", 60))
	if not try_spend(owner, cost):
		nexus.emit_event(EVENT_BUILD_REJECTED, { "owner": owner, "reason": "insufficient_resources" })
		return
	nexus.issue_command("queue_unit", owner, {
		"building_id": building_id,
		"unit_type": unit_type,
		"build_time_ticks": build_time,
	}, 1)


# BUG-G6: read a building record straight from WorldState (no module coupling).
func _building_record(building_id: int) -> Dictionary:
	var list: Dictionary = nexus.world_state.get_section("buildings").get("list", {})
	return list.get(str(building_id), {})


# T006 WP1: the scenario's pop_cap rule (0 = unlimited / no rules section).
func _pop_cap() -> int:
	# Read WITHOUT get_section(): get_section() CREATES an empty section, which would
	# add a "rules" section to vanilla matches and change the world hash (A1 lock).
	if not nexus.world_state.has_section("rules"):
		return 0
	return int(nexus.world_state.get_section("rules").get("pop_cap", 0))


# T006 WP1: current population of `owner` = living units + items already in that
# owner's build queues (deterministic, sorted iteration).
func _population(owner: int) -> int:
	var n: int = 0
	var units: Dictionary = nexus.world_state.get_section("units").get("list", {})
	var ukeys: Array = units.keys()
	ukeys.sort()
	for key in ukeys:
		var u: Dictionary = units[key]
		if int(u.get("owner", -1)) == owner and int(u.get("health", 0)) > 0:
			n += 1
	var buildings: Dictionary = nexus.world_state.get_section("buildings").get("list", {})
	var bkeys: Array = buildings.keys()
	bkeys.sort()
	for key in bkeys:
		var b: Dictionary = buildings[key]
		if int(b.get("owner", -1)) == owner:
			n += (b.get("build_queue", []) as Array).size()
	return n


# --- Helpers / save-load ----------------------------------------------------

func _players() -> Dictionary:
	return nexus.world_state.get_section(SECTION)["players"]


func serialize() -> Dictionary:
	return {}


func deserialize(_data: Dictionary) -> void:
	pass


func shutdown() -> void:
	if nexus != null:
		nexus.event_bus.unsubscribe_all(self)
