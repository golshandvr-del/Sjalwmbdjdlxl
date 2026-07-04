# combat_module.gd
# ----------------------------------------------------------------------------
# Project Nexus - Combat Module (Phase 1, step 1.8).
#
# Resolves combat deterministically on every tick:
#   - For each unit, if it has no target or its target is gone, it acquires the
#     nearest enemy unit/building within vision range (deterministic tie-break).
#   - If a valid target is within attack range, it deals attack_damage.
#   - When health drops to <= 0, a death/destroyed event is emitted; the Units
#     and Buildings modules listen and remove the dead entity.
#
# Decoupling: Combat reads the "units" and "buildings" sections from WorldState
# directly (shared data) and emits events; it never calls other modules.
#
# Determinism: all iteration uses sorted keys, and target selection breaks ties
# by lowest entity id, so the same world state always produces the same result.
#
# CODE LANGUAGE POLICY: English-only identifiers/comments.
# ----------------------------------------------------------------------------
class_name CombatModule
extends IModule

const EVENT_UNIT_DIED: String = "units.died"
const EVENT_BUILDING_DESTROYED: String = "buildings.destroyed"
const EVENT_ATTACK: String = "combat.attack"
# Phase 2.14: veterancy promotion announcement.
const EVENT_PROMOTED: String = "combat.unit_promoted"

# Veterancy tuning: kills required to reach each rank, and the per-rank bonus
# applied to attack_damage and max_health. Rank caps at the last threshold.
const VETERANCY_KILL_THRESHOLDS: Array = [1, 3, 6]   # rank 1, 2, 3
const VETERANCY_DAMAGE_PER_RANK: int = 3
const VETERANCY_HEALTH_PER_RANK: int = 20


func module_id() -> String:
	return "combat"


func init(p_nexus: Object) -> void:
	super.init(p_nexus)


func on_tick(_delta_tick: int) -> void:
	var units: Dictionary = _units()
	var keys: Array = units.keys()
	keys.sort_custom(_compare_int_keys)
	# Snapshot keys so removals during the loop are safe.
	for key in keys:
		if not units.has(key):
			continue
		var unit: Dictionary = units[key]
		_resolve_unit_combat(unit)


func _resolve_unit_combat(unit: Dictionary) -> void:
	if int(unit.get("health", 0)) <= 0:
		return
	# A unit can defend itself while moving: it acquires the nearest enemy in
	# vision and, if that enemy is already within attack range this tick, it
	# fires. Movement and attacking therefore coexist (skirmish behaviour).
	var target: Dictionary = _acquire_target(unit)
	if target.is_empty():
		unit["target_id"] = -1
		return
	unit["target_id"] = int(target.get("id", -1))
	var dist: int = _manhattan(int(unit["x"]), int(unit["y"]), int(target["x"]), int(target["y"]))
	if dist <= int(unit.get("attack_range", 1)):
		# Veterancy bonus damage applies to the dealt amount (Phase 2.14).
		var base_damage: int = int(unit.get("attack_damage", 10))
		var rank: int = int(unit.get("veterancy", 0))
		var damage: int = base_damage + rank * VETERANCY_DAMAGE_PER_RANK
		_apply_damage(target, damage, unit)
		nexus.emit_event(EVENT_ATTACK, {
			"attacker": int(unit["id"]),
			"target": int(target["id"]),
			"damage": damage,
		})


# P7.5: two owners are hostile unless they share a team. Teams live in the
# "match" section (owner(str) -> team). Owners without a team entry default to
# their own one-player team (FFA behaviour is unchanged).
func _is_hostile(owner_a: int, owner_b: int) -> bool:
	if owner_a == owner_b:
		return false
	var teams: Dictionary = nexus.world_state.get_section("match").get("teams", {})
	var team_a: int = int(teams.get(str(owner_a), owner_a))
	var team_b: int = int(teams.get(str(owner_b), owner_b))
	return team_a != team_b


# Find the nearest enemy (unit first, then building) within vision range.
func _acquire_target(unit: Dictionary) -> Dictionary:
	var owner: int = int(unit.get("owner", 0))
	var ux: int = int(unit["x"])
	var uy: int = int(unit["y"])
	var vision: int = int(unit.get("vision_range", 5))
	var best: Dictionary = {}
	var best_dist: int = 1 << 30
	var best_id: int = 1 << 30

	# Enemy units.
	var units: Dictionary = _units()
	var ukeys: Array = units.keys()
	ukeys.sort_custom(_compare_int_keys)
	for key in ukeys:
		var other: Dictionary = units[key]
		if not _is_hostile(owner, int(other.get("owner", 0))):
			continue
		if int(other.get("health", 0)) <= 0:
			continue
		var d: int = _manhattan(ux, uy, int(other["x"]), int(other["y"]))
		if d <= vision:
			var oid: int = int(other["id"])
			if d < best_dist or (d == best_dist and oid < best_id):
				best = other
				best_dist = d
				best_id = oid

	# Enemy buildings (only if no enemy unit found, simple priority).
	if best.is_empty():
		var buildings: Dictionary = _buildings()
		var bkeys: Array = buildings.keys()
		bkeys.sort_custom(_compare_int_keys)
		for key in bkeys:
			var b: Dictionary = buildings[key]
			if not _is_hostile(owner, int(b.get("owner", 0))):
				continue
			if int(b.get("health", 0)) <= 0:
				continue
			var d2: int = _manhattan(ux, uy, int(b["x"]), int(b["y"]))
			if d2 <= vision:
				var bid: int = int(b["id"])
				if d2 < best_dist or (d2 == best_dist and bid < best_id):
					best = b
					best_dist = d2
					best_id = bid
	return best


func _apply_damage(target: Dictionary, amount: int, attacker: Dictionary = {}) -> void:
	var was_alive: bool = int(target.get("health", 0)) > 0
	target["health"] = int(target.get("health", 0)) - amount
	if was_alive and int(target["health"]) <= 0:
		# Distinguish unit vs building by which section currently holds the id.
		var tid: int = int(target.get("id", -1))
		if _units().has(str(tid)):
			# Credit the kill to the attacker and check for promotion.
			if not attacker.is_empty():
				_credit_kill(attacker)
			nexus.emit_event(EVENT_UNIT_DIED, { "id": tid, "owner": int(target.get("owner", 0)) })
		elif _buildings().has(str(tid)):
			nexus.emit_event(EVENT_BUILDING_DESTROYED, { "id": tid, "owner": int(target.get("owner", 0)) })


# Award a kill to the attacker and promote it if it crosses a veterancy
# threshold. Promotions permanently raise the unit's combat power (Phase 2.14).
func _credit_kill(attacker: Dictionary) -> void:
	attacker["kills"] = int(attacker.get("kills", 0)) + 1
	var kills: int = int(attacker["kills"])
	var new_rank: int = 0
	for i in range(VETERANCY_KILL_THRESHOLDS.size()):
		if kills >= int(VETERANCY_KILL_THRESHOLDS[i]):
			new_rank = i + 1
	var old_rank: int = int(attacker.get("veterancy", 0))
	if new_rank > old_rank:
		var gained: int = new_rank - old_rank
		attacker["veterancy"] = new_rank
		# Each gained rank toughens the unit; reflect it in max/current health.
		var hp_bonus: int = gained * VETERANCY_HEALTH_PER_RANK
		attacker["max_health"] = int(attacker.get("max_health", 0)) + hp_bonus
		attacker["health"] = int(attacker.get("health", 0)) + hp_bonus
		nexus.emit_event(EVENT_PROMOTED, {
			"id": int(attacker.get("id", -1)),
			"owner": int(attacker.get("owner", 0)),
			"rank": new_rank,
		})


# --- Helpers ----------------------------------------------------------------

func _manhattan(ax: int, ay: int, bx: int, by: int) -> int:
	return abs(ax - bx) + abs(ay - by)


func _compare_int_keys(a: String, b: String) -> bool:
	return int(a) < int(b)


func _units() -> Dictionary:
	return nexus.world_state.get_section("units").get("list", {})


func _buildings() -> Dictionary:
	return nexus.world_state.get_section("buildings").get("list", {})


func serialize() -> Dictionary:
	return {}


func deserialize(_data: Dictionary) -> void:
	pass


func shutdown() -> void:
	if nexus != null:
		nexus.event_bus.unsubscribe_all(self)
