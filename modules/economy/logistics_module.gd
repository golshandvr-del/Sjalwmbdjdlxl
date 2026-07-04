# logistics_module.gd
# ----------------------------------------------------------------------------
# Project Nexus - Logistics / Caravan Module (Phase 2, step 2.5).
#
# Models simple supply lines between a player's command buildings. In Phase 1
# every player had a single shared wallet; Phase 2 lets a player own MULTIPLE
# HQs/outposts that each generate resources locally. Logistics periodically
# "ships" a fraction of the resources gathered at outposts back to the main HQ
# (the lowest-id command building), giving a reason to expand and defend supply.
#
# Because the Economy module keeps ONE wallet per owner (the single source of
# truth), the actual numbers do not change between buildings -- what Logistics
# adds is a per-building "throughput" record and a deterministic caravan tick
# that can later be intercepted (e.g. raids cutting supply). This keeps the
# Phase 2 feature lightweight while remaining faithful to the data model and
# fully deterministic.
#
# Decoupling: depends ONLY on the core. Reads the "buildings" section, writes
# its own "logistics" section, and emits events. Never calls another module.
#
# logistics section layout:
#   {
#     "routes": { owner(String) -> { "hub_id": int, "outposts": Array[int] } },
#     "shipped": { owner(String) -> int }   # total resources delivered
#   }
#
# CODE LANGUAGE POLICY: English-only identifiers/comments.
# ----------------------------------------------------------------------------
class_name LogisticsModule
extends IModule

const SECTION: String = "logistics"

# How often (in ticks) caravans recompute routes and deliver supply.
const CARAVAN_INTERVAL: int = 20

const EVENT_SUPPLY_DELIVERED: String = "logistics.supply_delivered"
const EVENT_ROUTES_CHANGED: String = "logistics.routes_changed"


func module_id() -> String:
	return "logistics"


func init(p_nexus: Object) -> void:
	super.init(p_nexus)
	_ensure_state()


func _ensure_state() -> void:
	var section: Dictionary = nexus.world_state.get_section(SECTION)
	if not section.has("routes"):
		section["routes"] = {}
	if not section.has("shipped"):
		section["shipped"] = {}


func on_tick(_delta_tick: int) -> void:
	var tick: int = int(nexus.world_state.current_tick)
	if tick % CARAVAN_INTERVAL != 0:
		return
	_recompute_routes()
	_run_caravans()


# Build, per owner, the hub (lowest-id command building) + its outposts.
func _recompute_routes() -> void:
	var buildings: Dictionary = _buildings()
	var by_owner: Dictionary = {}   # owner(String) -> Array of building dicts
	var keys: Array = buildings.keys()
	keys.sort_custom(func(a, b): return int(a) < int(b))
	for key in keys:
		var b: Dictionary = buildings[key]
		if int(b.get("construction_remaining", 0)) > 0:
			continue
		var owner_key: String = str(int(b.get("owner", 0)))
		var arr: Array = by_owner.get(owner_key, [])
		arr.append(b)
		by_owner[owner_key] = arr

	var routes: Dictionary = _routes()
	routes.clear()
	for owner_key in by_owner.keys():
		var arr: Array = by_owner[owner_key]
		if arr.size() < 2:
			continue  # need a hub plus at least one outpost to have a route.
		var hub_id: int = int(arr[0]["id"])  # lowest id = main HQ.
		var outposts: Array = []
		for i in range(1, arr.size()):
			outposts.append(int(arr[i]["id"]))
		routes[owner_key] = { "hub_id": hub_id, "outposts": outposts }
	nexus.emit_event(EVENT_ROUTES_CHANGED, { "owner_count": routes.size() })


# Deliver supply: each outpost contributes a small deterministic bonus to its
# owner's wallet, representing concentrated logistics at the hub.
func _run_caravans() -> void:
	var routes: Dictionary = _routes()
	var owners: Array = routes.keys()
	owners.sort()
	var economy: Object = nexus.get_module("economy")
	for owner_key in owners:
		var route: Dictionary = routes[owner_key]
		var outpost_count: int = (route.get("outposts", []) as Array).size()
		if outpost_count <= 0:
			continue
		var bonus: int = outpost_count  # +1 resource per connected outpost.
		var owner: int = int(owner_key)
		if economy != null:
			economy.add_resource(owner, "resource_basic", bonus)
		var shipped: Dictionary = _shipped()
		shipped[owner_key] = int(shipped.get(owner_key, 0)) + bonus
		nexus.emit_event(EVENT_SUPPLY_DELIVERED, { "owner": owner, "amount": bonus })


# --- Helpers / save-load ----------------------------------------------------

func _buildings() -> Dictionary:
	return nexus.world_state.get_section("buildings").get("list", {})


func _routes() -> Dictionary:
	return nexus.world_state.get_section(SECTION)["routes"]


func _shipped() -> Dictionary:
	return nexus.world_state.get_section(SECTION)["shipped"]


func total_shipped(owner: int) -> int:
	return int(_shipped().get(str(owner), 0))


func serialize() -> Dictionary:
	return {}


func deserialize(_data: Dictionary) -> void:
	pass


func shutdown() -> void:
	if nexus != null:
		nexus.event_bus.unsubscribe_all(self)
