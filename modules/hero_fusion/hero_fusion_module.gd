# hero_fusion_module.gd
# ----------------------------------------------------------------------------
# Project Nexus - Hero Fusion Module (Phase 2, steps 2.12 + 2.13).
#
# Implements the signature "fuse forces -> hero" feature. A player selects a
# group of their units and, if those units satisfy a data-defined RECIPE
# (data/tech/hero_fusion.json), the ingredient units are consumed and a single
# powerful HERO unit is produced at their location, inheriting a veterancy
# bonus.
#
# Design rules obeyed:
#   - Depends ONLY on the core. It reads "units" from world state and drives the
#     world purely through COMMANDS (spawn the hero, remove ingredients) so the
#     Units module stays the sole owner of unit lifecycle -> decoupled.
#   - Data-driven: recipes come from the data catalog, not hard-code.
#   - Deterministic: ingredient matching iterates over sorted ids and consumes
#     the lowest ids first -> reproducible (lockstep safe).
#
# Commands handled:
#   command.fuse_units { owner, unit_ids: Array[int], recipe_id (optional) }
#
# Events emitted:
#   hero_fusion.completed { owner, hero_type, consumed: Array[int] }
#   hero_fusion.rejected  { owner, reason }
#
# CODE LANGUAGE POLICY: English-only identifiers/comments.
# ----------------------------------------------------------------------------
class_name HeroFusionModule
extends IModule

const CATALOG: String = "tech"   # recipes live in the tech catalog document.

const CMD_FUSE: String = "command.fuse_units"

const EVENT_COMPLETED: String = "hero_fusion.completed"
const EVENT_REJECTED: String = "hero_fusion.rejected"


func module_id() -> String:
	return "hero_fusion"


func init(p_nexus: Object) -> void:
	super.init(p_nexus)
	nexus.subscribe(CMD_FUSE, self, "_on_bus_event")


# --- Recipe lookup ----------------------------------------------------------

func all_recipes() -> Array:
	var catalog: Dictionary = nexus.data_loader.get_catalog(CATALOG)
	for doc_id in catalog.keys():
		var doc: Dictionary = catalog[doc_id]
		if doc.has("recipes"):
			return doc["recipes"]
	return []


func get_recipe(recipe_id: String) -> Dictionary:
	for r in all_recipes():
		if str(r.get("id", "")) == recipe_id:
			return r
	return {}


# --- Command handling -------------------------------------------------------

func _on_bus_event(event_name: String, payload: Dictionary) -> void:
	handle_event(event_name, payload)


func handle_event(event_name: String, payload: Dictionary) -> void:
	if event_name == CMD_FUSE:
		_handle_fuse(payload.get("data", {}))


func _handle_fuse(data: Dictionary) -> void:
	var owner: int = int(data.get("owner", 0))
	var unit_ids: Array = data.get("unit_ids", [])
	var requested_recipe: String = str(data.get("recipe_id", ""))

	# Gather the selected units that actually belong to this owner.
	var units: Dictionary = _units()
	var selected: Array = []
	for raw_id in unit_ids:
		var key: String = str(int(raw_id))
		# Gameplay audit: only LIVING units are valid ingredients. A unit whose
		# health hit zero this tick (corpse not yet removed) could otherwise be
		# fused, effectively resurrecting its value into a hero.
		if units.has(key) and int(units[key].get("owner", -1)) == owner and int(units[key].get("health", 0)) > 0:
			selected.append(units[key])
	if selected.is_empty():
		nexus.emit_event(EVENT_REJECTED, { "owner": owner, "reason": "no_valid_units" })
		return

	# Choose the recipe: the requested one, or the first matching recipe.
	var recipe: Dictionary = {}
	if requested_recipe != "":
		recipe = get_recipe(requested_recipe)
		if recipe.is_empty() or not _matches(recipe, selected):
			nexus.emit_event(EVENT_REJECTED, { "owner": owner, "reason": "recipe_not_satisfied" })
			return
	else:
		recipe = _first_matching_recipe(selected)
		if recipe.is_empty():
			nexus.emit_event(EVENT_REJECTED, { "owner": owner, "reason": "no_matching_recipe" })
			return

	_perform_fusion(owner, recipe, selected)


# Does the selection satisfy a recipe's ingredient counts and veterancy floor?
func _matches(recipe: Dictionary, selected: Array) -> bool:
	# Count selected units by type.
	var counts: Dictionary = {}
	var vet_total: int = 0
	for u in selected:
		var t: String = str(u.get("type", ""))
		counts[t] = int(counts.get(t, 0)) + 1
		vet_total += int(u.get("veterancy", 0))
	if vet_total < int(recipe.get("min_veterancy_total", 0)):
		return false
	for ing in recipe.get("ingredients", []):
		var need_type: String = str(ing.get("type", ""))
		var need_count: int = int(ing.get("count", 0))
		if int(counts.get(need_type, 0)) < need_count:
			return false
	return true


func _first_matching_recipe(selected: Array) -> Dictionary:
	var recipes: Array = all_recipes()
	# Deterministic: sort recipe ids and pick the first that matches.
	recipes.sort_custom(func(a, b): return str(a.get("id", "")) < str(b.get("id", "")))
	for r in recipes:
		if _matches(r, selected):
			return r
	return {}


# Consume the ingredient units (lowest ids first, deterministically) and spawn
# the resulting hero at the position of the first consumed unit.
func _perform_fusion(owner: int, recipe: Dictionary, selected: Array) -> void:
	# Sort the selected units by id for deterministic consumption.
	selected.sort_custom(func(a, b): return int(a.get("id", 0)) < int(b.get("id", 0)))

	var to_consume: Array = []
	var remaining_need: Dictionary = {}
	for ing in recipe.get("ingredients", []):
		remaining_need[str(ing.get("type", ""))] = int(ing.get("count", 0))
	for u in selected:
		var t: String = str(u.get("type", ""))
		if int(remaining_need.get(t, 0)) > 0:
			to_consume.append(int(u.get("id", -1)))
			remaining_need[t] = int(remaining_need[t]) - 1

	# Guard against malformed MODDED recipes: a recipe whose ingredients list is
	# empty (or all counts are 0) matches any selection but consumes nothing --
	# indexing to_consume[0] below would crash. Reject it cleanly instead so a
	# bad mod pack can never take the game down (mod-safety contract).
	if to_consume.is_empty():
		nexus.emit_event(EVENT_REJECTED, { "owner": owner, "reason": "recipe_consumes_nothing" })
		return

	# Position of the hero = position of the first consumed unit.
	var first_unit: Dictionary = _units().get(str(to_consume[0]), {})
	var hx: int = int(first_unit.get("x", 0))
	var hy: int = int(first_unit.get("y", 0))

	# Remove the ingredient units via the standard death channel so every
	# listener (Units, FogOfWar, Victory) stays consistent.
	for uid in to_consume:
		nexus.emit_event("units.died", { "id": int(uid), "owner": owner, "fused": true })

	# Spawn the hero through a command so the Units module owns its creation.
	var result: Dictionary = recipe.get("result", {})
	var hero_type: String = str(result.get("type", "hero"))
	nexus.issue_command("spawn_unit", owner, {
		"type": hero_type,
		"owner": owner,
		"x": hx,
		"y": hy,
		"veterancy_bonus": int(result.get("veterancy_bonus", 0)),
	}, 1)

	nexus.emit_event(EVENT_COMPLETED, {
		"owner": owner,
		"hero_type": hero_type,
		"consumed": to_consume,
	})


# --- Helpers / save-load ----------------------------------------------------

func _units() -> Dictionary:
	return nexus.world_state.get_section("units").get("list", {})


func serialize() -> Dictionary:
	return {}


func deserialize(_data: Dictionary) -> void:
	pass


func shutdown() -> void:
	if nexus != null:
		nexus.event_bus.unsubscribe_all(self)
