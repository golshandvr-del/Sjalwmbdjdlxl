# tech_tree_module.gd
# ----------------------------------------------------------------------------
# Project Nexus - Tech Tree Module (Phase 2, steps 2.1 + 2.2).
#
# Data-driven research system. The tech graph (nodes, costs, prerequisites and
# effects) is loaded from data/tech/*.json by the DataLoader; this module only
# manages per-player research progress and announces unlocked effects.
#
# Decoupling rules respected:
#   - It depends ONLY on the core. It owns the WorldState section "tech",
#     reacts to commands, and broadcasts events. It never references another
#     module. The Economy module is asked to pay via the existing try_spend
#     bridge (looked up through Nexus.get_module by id, read-only contract),
#     OR -- to stay fully decoupled -- it emits a spend request the Economy
#     module already understands. Here we use the small, already-public
#     EconomyModule.try_spend through a generic lookup, mirroring how the
#     scenario loader talks to modules.
#   - Determinism: research advances on fixed ticks, iteration uses sorted
#     keys, no wall-clock or RNG -> lockstep safe (Phase 4).
#
# tech section layout (WorldState):
#   {
#     "players": {
#       owner(String) -> {
#         "researched": Array[String],            # completed node ids
#         "in_progress": { node_id -> remaining_ticks },
#         "veterancy_bonus": int                  # accumulated from effects
#       }
#     }
#   }
#
# Commands handled:
#   command.research_tech  { owner, node_id }
#
# Events emitted:
#   tech.research_started   { owner, node_id }
#   tech.research_completed { owner, node_id, effects }
#   tech.research_rejected  { owner, node_id, reason }
#
# CODE LANGUAGE POLICY: English-only identifiers/comments.
# ----------------------------------------------------------------------------
class_name TechTreeModule
extends IModule

const SECTION: String = "tech"
const CATALOG: String = "tech"

const CMD_RESEARCH: String = "command.research_tech"

const EVENT_STARTED: String = "tech.research_started"
const EVENT_COMPLETED: String = "tech.research_completed"
const EVENT_REJECTED: String = "tech.research_rejected"


func module_id() -> String:
	return "tech_tree"


func init(p_nexus: Object) -> void:
	super.init(p_nexus)
	nexus.subscribe(CMD_RESEARCH, self, "_on_bus_event")
	_ensure_state()


func _ensure_state() -> void:
	var section: Dictionary = nexus.world_state.get_section(SECTION)
	if not section.has("players"):
		section["players"] = {}


# --- Public API -------------------------------------------------------------

func ensure_player(owner: int) -> void:
	var players: Dictionary = _players()
	if not players.has(str(owner)):
		players[str(owner)] = {
			"researched": [],
			"in_progress": {},
			"veterancy_bonus": 0,
		}


func is_researched(owner: int, node_id: String) -> bool:
	ensure_player(owner)
	return (_player(owner)["researched"] as Array).has(node_id)


func is_in_progress(owner: int, node_id: String) -> bool:
	ensure_player(owner)
	return (_player(owner)["in_progress"] as Dictionary).has(node_id)


func get_veterancy_bonus(owner: int) -> int:
	ensure_player(owner)
	return int(_player(owner).get("veterancy_bonus", 0))


# Find the catalog node by id (the tech catalog stores ONE tree document keyed
# by its id; we flatten its "nodes" array into an id->node lookup on demand).
func get_node_def(node_id: String) -> Dictionary:
	var catalog: Dictionary = nexus.data_loader.get_catalog(CATALOG)
	for tree_id in catalog.keys():
		var tree: Dictionary = catalog[tree_id]
		for node in tree.get("nodes", []):
			if str(node.get("id", "")) == node_id:
				return node
	return {}


# Can `owner` start researching `node_id` right now? Returns "" if yes,
# otherwise a machine-readable reason string.
func research_blocked_reason(owner: int, node_id: String) -> String:
	var node: Dictionary = get_node_def(node_id)
	if node.is_empty():
		return "unknown_tech"
	if is_researched(owner, node_id):
		return "already_researched"
	if is_in_progress(owner, node_id):
		return "already_in_progress"
	for req in node.get("requires", []):
		if not is_researched(owner, str(req)):
			return "missing_prerequisite"
	# T006 WP1: building prerequisites ("requires_buildings") in addition to the
	# tech prerequisites. A missing completed building blocks research (check C15).
	var req_buildings: Array = node.get("requires_buildings", [])
	if not req_buildings.is_empty():
		var completed: Array = PrereqUtil.owner_completed_building_types(
			nexus.world_state.get_section("buildings").get("list", {}), owner)
		for rb in req_buildings:
			if not completed.has(str(rb)):
				return "missing_prerequisite"
	return ""


# --- Command handling -------------------------------------------------------

func _on_bus_event(event_name: String, payload: Dictionary) -> void:
	handle_event(event_name, payload)


func handle_event(event_name: String, payload: Dictionary) -> void:
	if event_name == CMD_RESEARCH:
		_handle_research(payload.get("data", {}))


func _handle_research(data: Dictionary) -> void:
	var owner: int = int(data.get("owner", 0))
	var node_id: String = str(data.get("node_id", ""))
	ensure_player(owner)
	var reason: String = research_blocked_reason(owner, node_id)
	if reason != "":
		nexus.emit_event(EVENT_REJECTED, { "owner": owner, "node_id": node_id, "reason": reason })
		return
	var node: Dictionary = get_node_def(node_id)
	var cost: Dictionary = node.get("cost", {})
	# Ask the Economy module to pay (read-only public contract, like the
	# scenario loader does). If unavailable, research is free (headless tests).
	var economy: Object = nexus.get_module("economy")
	if economy != null and not cost.is_empty():
		if not economy.try_spend(owner, cost):
			nexus.emit_event(EVENT_REJECTED, { "owner": owner, "node_id": node_id, "reason": "insufficient_resources" })
			return
	var time: int = max(1, int(node.get("research_time_ticks", 100)))
	(_player(owner)["in_progress"] as Dictionary)[node_id] = time
	nexus.emit_event(EVENT_STARTED, { "owner": owner, "node_id": node_id })


# --- Deterministic research progress ----------------------------------------

func on_tick(_delta_tick: int) -> void:
	var players: Dictionary = _players()
	var owners: Array = players.keys()
	owners.sort()
	for owner_key in owners:
		_advance_player(int(owner_key))


func _advance_player(owner: int) -> void:
	var in_progress: Dictionary = _player(owner)["in_progress"]
	var node_ids: Array = in_progress.keys()
	node_ids.sort()
	for node_id in node_ids:
		in_progress[node_id] = int(in_progress[node_id]) - 1
		if int(in_progress[node_id]) <= 0:
			in_progress.erase(node_id)
			_complete_research(owner, str(node_id))


func _complete_research(owner: int, node_id: String) -> void:
	(_player(owner)["researched"] as Array).append(node_id)
	var node: Dictionary = get_node_def(node_id)
	var effects: Array = node.get("effects", [])
	# Apply effects that this module owns (veterancy bonus); broadcast all
	# effects so other modules (Units) can react to stat upgrades.
	for effect in effects:
		if str(effect.get("type", "")) == "veterancy_bonus":
			_player(owner)["veterancy_bonus"] = int(_player(owner).get("veterancy_bonus", 0)) + int(effect.get("amount", 0))
	nexus.emit_event(EVENT_COMPLETED, { "owner": owner, "node_id": node_id, "effects": effects })


# --- Helpers / save-load ----------------------------------------------------

func _players() -> Dictionary:
	return nexus.world_state.get_section(SECTION)["players"]


func _player(owner: int) -> Dictionary:
	return _players()[str(owner)]


func serialize() -> Dictionary:
	return {}


func deserialize(_data: Dictionary) -> void:
	pass


func shutdown() -> void:
	if nexus != null:
		nexus.event_bus.unsubscribe_all(self)
