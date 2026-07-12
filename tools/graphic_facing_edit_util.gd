# graphic_facing_edit_util.gd
# ----------------------------------------------------------------------------
# Project Nexus - Pure edit logic for the mod editor's FACING + FIRING-PART
# controls (Phase MC14, step 14.6, requests 16 & 18). The mod editor UI is a
# thin view: when the author picks a facing, flags a part as the firing part, or
# chooses a fixed/turret mount, it delegates the actual entity mutation to this
# util. Keeping the logic here means it is headless-testable and it cannot drift
# from the authored-graphic rules enforced by GraphicModel (at most ONE firing
# part per authored graphic; mount is fixed/turret).
#
# Every mutator takes an ENTITY dictionary ({ "graphic": { "facing", "parts" } })
# and returns a fresh copy -- the input is never mutated, matching the defensive
# copy-on-write style used across the editor utils. Bad input degrades to a safe
# copy rather than raising, so the UI can call these freely.
#
# This util does NO node work, NO IO, NO simulation; it is a pure data mapper.
#
# CODE LANGUAGE POLICY: English-only identifiers/comments (ASCII).
# ----------------------------------------------------------------------------
class_name GraphicFacingEditUtil
extends RefCounted


# The list of facing choices the UI should offer (logical ids). Order is stable
# so the UI's option list is deterministic.
static func facing_choices() -> Array:
	return GraphicModel.FACINGS.duplicate()


# The list of firing-mount choices the UI should offer (fixed / turret).
static func mount_choices() -> Array:
	return GraphicModel.MOUNTS.duplicate()


# Read the entity's current facing (defaulting when absent/invalid). Null-safe.
static func get_entity_facing(entity: Variant) -> String:
	if not (entity is Dictionary):
		return GraphicModel.DEFAULT_FACING
	return GraphicModel.get_facing((entity as Dictionary).get("graphic", {}))


# Return a copy of `entity` whose graphic facing is set to a normalised value.
static func set_entity_facing(entity: Variant, value: Variant) -> Dictionary:
	var e: Dictionary = _copy_entity(entity)
	e["graphic"] = GraphicModel.set_facing(e.get("graphic", {}), value)
	return e


# The index of the entity's firing part, or -1 when it has none. Null-safe.
static func firing_part_index(entity: Variant) -> int:
	if not (entity is Dictionary):
		return -1
	return GraphicModel.first_firing_index((entity as Dictionary).get("graphic", {}))


# The mount of the entity's firing part (fixed by default; fixed when none).
static func firing_part_mount(entity: Variant) -> String:
	var index: int = firing_part_index(entity)
	if index < 0:
		return GraphicModel.DEFAULT_MOUNT
	var graphic: Dictionary = (entity as Dictionary).get("graphic", {}) as Dictionary
	var parts: Array = graphic.get("parts", []) as Array
	if index >= parts.size():
		return GraphicModel.DEFAULT_MOUNT
	return GraphicModel.part_mount(parts[index])


# True when the entity currently has a firing part.
static func has_firing_part(entity: Variant) -> bool:
	return firing_part_index(entity) >= 0


# Return a copy of `entity` where exactly `part_index` becomes the firing part
# with the given mount, clearing any other firing flags (enforces the authored
# single-firing-part cap by construction). `part_index` < 0 clears all firing
# flags. Out-of-range indices clear all flags (safe no-op selection).
static func set_firing_part(entity: Variant, part_index: int, mount: Variant = GraphicModel.DEFAULT_MOUNT) -> Dictionary:
	var e: Dictionary = _copy_entity(entity)
	e["graphic"] = GraphicModel.set_firing_part(e.get("graphic", {}), part_index, mount)
	return e


# Toggle the firing flag of `part_index`: if it is already the firing part,
# clear it; otherwise make it the firing part with the given mount. Returns a
# fresh entity copy.
static func toggle_firing_part(entity: Variant, part_index: int, mount: Variant = GraphicModel.DEFAULT_MOUNT) -> Dictionary:
	if firing_part_index(entity) == part_index and part_index >= 0:
		return set_firing_part(entity, -1, mount)
	return set_firing_part(entity, part_index, mount)


# Change ONLY the mount of the existing firing part (no-op copy when the entity
# has no firing part). Keeps whichever part is currently flagged.
static func set_firing_mount(entity: Variant, mount: Variant) -> Dictionary:
	var index: int = firing_part_index(entity)
	if index < 0:
		return _copy_entity(entity)
	return set_firing_part(entity, index, mount)


# The number of parts a multi-part entity has (1 for single-part / unknown).
static func part_count(entity: Variant) -> int:
	if not (entity is Dictionary):
		return 0
	var graphic: Variant = (entity as Dictionary).get("graphic", {})
	if not (graphic is Dictionary):
		return 0
	var parts: Variant = (graphic as Dictionary).get("parts", [])
	return (parts as Array).size() if parts is Array else 0


# Defensive deep copy of an entity dictionary; non-dicts collapse to {}.
static func _copy_entity(entity: Variant) -> Dictionary:
	if entity is Dictionary:
		return (entity as Dictionary).duplicate(true)
	return {}
