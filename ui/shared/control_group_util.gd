# control_group_util.gd
# ----------------------------------------------------------------------------
# Project Nexus - Shared control-group (unit grouping) helpers (Phase MA3).
#
# Pure, dependency-free helpers for the 3x3 control-group grid shared by the
# mobile HUD. Keeping this logic OUT of the HUD script (which depends on the
# `Nexus` autoload and a live SceneTree) lets it be unit-tested headlessly.
#
# A control group is just a saved list of unit ids bound to a slot (0..8). The
# player ASSIGNs the current selection into a slot and later RECALLs it. Because
# units die between assign and recall, recall must first PRUNE ids that no
# longer exist in the world before selecting what remains.
#
# Logic/Render Separation: nothing here mutates WorldState. Callers take the
# returned id list and push it through the authoritative `select_units` command.
# Determinism: recall returns ids in a stable ascending order so every peer
# resolves the same selection.
# ----------------------------------------------------------------------------
class_name ControlGroupUtil
extends RefCounted


# How many control-group slots exist (a 3x3 corner grid).
const SLOT_COUNT: int = 9


# Return a fresh, empty control-group table: SLOT_COUNT empty id lists.
static func empty_groups() -> Array:
	var groups: Array = []
	for _i in range(SLOT_COUNT):
		groups.append([])
	return groups


# True when `slot` is a valid index into a control-group table.
static func is_valid_slot(slot: int) -> bool:
	return slot >= 0 and slot < SLOT_COUNT


# Normalise an arbitrary id list into a sorted, de-duplicated Array of ints.
# Assigning through this guarantees a deterministic, clean group regardless of
# how the incoming selection was ordered or whether it held duplicates.
static func normalise_ids(ids: Array) -> Array:
	var seen: Dictionary = {}
	for raw in ids:
		seen[int(raw)] = true
	var out: Array = seen.keys()
	out.sort()
	return out


# Return the subset of `group` whose ids still exist in the live `units` list
# (WorldState units section: id-string -> unit dict). The result is sorted
# ascending so recall is deterministic. Ids are matched against the units
# dictionary using their STRING form, because WorldState keys units by string.
static func prune_living(group: Array, units: Dictionary) -> Array:
	var out: Array = []
	for raw in group:
		var uid: int = int(raw)
		if units.has(str(uid)):
			out.append(uid)
	out.sort()
	return out


# Build the label text for a control-group button. Slot `i` (0-based) shows its
# 1-based number, plus a "(count)" suffix on a second line when the group holds
# units, so the player can see at a glance which slots are populated.
static func button_label(slot_index: int, count: int) -> String:
	if count > 0:
		return "%d\n(%d)" % [slot_index + 1, count]
	return str(slot_index + 1)
