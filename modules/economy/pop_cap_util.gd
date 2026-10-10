# pop_cap_util.gd
# ----------------------------------------------------------------------------
# Project Nexus - population cap helper (T006 WP1 / T006B WP2).
#
# A scenario may set `rules.pop_cap` to bound how many units a player may own
# (alive units + queued items). The economy module enforces the cap when a
# build_unit command arrives; this pure helper lets the AI brains check the SAME
# rule BEFORE issuing a command, so they stop ordering at the cap instead of
# spamming doomed orders every planning pass (T006 acceptance check F07).
#
# Pure/static: reads only plain world-state dictionaries, sorted iteration, no
# SceneTree, no RNG -- deterministic and lockstep safe.
#
# CODE LANGUAGE POLICY: English-only identifiers/comments.
# ----------------------------------------------------------------------------
class_name PopCapUtil
extends RefCounted


# The scenario's pop_cap (0 = unlimited / no rules section). Reads WITHOUT
# creating the section (get_section() would add a "rules" section to vanilla
# matches and change the world hash -- A1 lock).
static func pop_cap(nexus: Object) -> int:
	if not nexus.world_state.has_section("rules"):
		return 0
	return int(nexus.world_state.get_section("rules").get("pop_cap", 0))


# Current population of `owner` = living units + items already in that owner's
# build queues (deterministic, sorted iteration).
static func population(nexus: Object, owner: int) -> int:
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


# True when `owner` is already at the scenario's population cap.
static func at_cap(nexus: Object, owner: int) -> bool:
	var cap: int = pop_cap(nexus)
	return cap > 0 and population(nexus, owner) >= cap
