# firing_combination_util.gd
# ----------------------------------------------------------------------------
# Project Nexus - Pure logic for COMBINING units' firing parts in-game (Phase
# MC14, step 14.4, request 18). Request 18 asks that when the player combines
# units, the resulting unit may fire from up to TWO parts (an authored graphic
# is capped at one firing part in MC14.3; fusion raises the in-game cap to two).
#
# This util owns ONLY the deterministic combination MATH -- given the source
# graphics (each with 0..1 firing part), it decides which firing parts survive
# in the combined unit and caps the total at GraphicModel.MAX_COMBINED_FIRING_
# PARTS. It performs NO simulation, NO node work, NO IO, so it is fully
# headless-testable and safe to call from the deterministic layer: the same
# inputs always yield the same firing set (source order is preserved, which is
# the caller's deterministic selection order).
#
# A combined "firing slot" is { "source": <int>, "part": <int>, "mount": <str> }
# so the render layer (MC14.5) knows which source graphic + part index a barrel
# came from and whether it is a fixed or turret mount.
#
# CODE LANGUAGE POLICY: English-only identifiers/comments (ASCII).
# ----------------------------------------------------------------------------
class_name FiringCombinationUtil
extends RefCounted


# Collect the firing slots contributed by an ordered list of source graphics,
# capped at GraphicModel.MAX_COMBINED_FIRING_PARTS. Each source may contribute at
# most one firing part (its authored firing part, if any). Slots are taken in
# source order until the cap is reached, so the result is deterministic.
static func combine_firing_slots(source_graphics: Array) -> Array:
	var slots: Array = []
	var cap: int = GraphicModel.MAX_COMBINED_FIRING_PARTS
	for source_index in range(source_graphics.size()):
		if slots.size() >= cap:
			break
		var graphic: Variant = source_graphics[source_index]
		var part_index: int = GraphicModel.first_firing_index(graphic)
		if part_index < 0:
			continue
		var parts: Array = (graphic as Dictionary).get("parts", []) as Array
		var mount: String = GraphicModel.part_mount(parts[part_index]) if part_index < parts.size() else GraphicModel.DEFAULT_MOUNT
		slots.append({
			"source": source_index,
			"part": part_index,
			"mount": mount,
		})
	return slots


# The number of firing parts a combination of the given sources would yield
# (after the cap). Handy for UI summaries and validation.
static func combined_firing_count(source_graphics: Array) -> int:
	return combine_firing_slots(source_graphics).size()


# True if a proposed combination would EXCEED the combined cap BEFORE capping --
# i.e. more sources carry a firing part than the cap allows. The UI can warn the
# player that some barrels will be dropped.
static func exceeds_cap(source_graphics: Array) -> bool:
	var wanted: int = 0
	for graphic in source_graphics:
		if GraphicModel.first_firing_index(graphic) >= 0:
			wanted += 1
	return wanted > GraphicModel.MAX_COMBINED_FIRING_PARTS


# Whether any slot in a combined firing set is a rotating turret (drives the
# MC14.5 render decision at the combined level).
static func has_turret(slots: Array) -> bool:
	for slot in slots:
		if slot is Dictionary and str((slot as Dictionary).get("mount", "")) == GraphicModel.MOUNT_TURRET:
			return true
	return false
