# tap_select_util.gd
# ----------------------------------------------------------------------------
# Project Nexus - Shared single-tap selection logic (Phase MA6).
#
# Pure, dependency-free helpers that decide what a SINGLE finger tap should do in
# the mobile (and desktop) HUD: select a friendly unit, toggle it out of the
# current squad, or -- when empty ground is tapped with units already selected --
# issue a MOVE for the selection.
#
# Keeping this decision OUT of the HUD script (which depends on the `Nexus`
# autoload, a live RenderAdapter, and a running SceneTree) lets the exact tap
# behaviour be unit-tested headlessly, and lets the scene-based MA6 integration
# test assert that the real input path produces the same decision.
#
# Logic/Render Separation: nothing here mutates WorldState or the HUD. The caller
# takes the returned plan and pushes it through the authoritative commands
# (`select_units` / `move_unit`), exactly as before. Determinism: the resulting
# selection list is returned in the caller's tap order (append/erase), matching
# the long-standing touch behaviour where repeated taps build a squad.
#
# CODE LANGUAGE POLICY: English-only identifiers/comments (ASCII).
# ----------------------------------------------------------------------------
class_name TapSelectUtil
extends RefCounted


# Action kinds a tap can resolve to.
const ACTION_NONE: String = "none"        # empty ground, nothing selected -> no-op
const ACTION_SELECT: String = "select"    # (re)issue select_units with the new set
const ACTION_MOVE: String = "move"        # issue move_unit for the current selection


# Resolve a tap into a concrete plan.
#
#   current_selection : the HUD's current list of selected unit ids (ints).
#   tapped_unit_id    : id of a friendly unit under the tap, or -1 for empty ground.
#
# Returns a Dictionary:
#   {
#     "action"    : ACTION_SELECT | ACTION_MOVE | ACTION_NONE,
#     "selection" : Array[int]  # the selection AFTER applying the tap
#   }
#
# Rules (identical to the shipped touch model, now centralised + testable):
#   * Tap a friendly unit NOT in the selection  -> add it (ACTION_SELECT).
#   * Tap a friendly unit ALREADY selected       -> remove it / toggle off (ACTION_SELECT).
#   * Tap empty ground WITH a selection          -> ACTION_MOVE (selection unchanged).
#   * Tap empty ground with NOTHING selected     -> ACTION_NONE (selection unchanged).
static func resolve_tap(current_selection: Array, tapped_unit_id: int) -> Dictionary:
	var selection: Array = current_selection.duplicate()
	if tapped_unit_id != -1:
		# A friendly unit was tapped: toggle it in/out of the squad.
		if selection.has(tapped_unit_id):
			selection.erase(tapped_unit_id)
		else:
			selection.append(tapped_unit_id)
		return { "action": ACTION_SELECT, "selection": selection }
	# Empty ground: move the current selection there, or do nothing if empty.
	if not selection.is_empty():
		return { "action": ACTION_MOVE, "selection": selection }
	return { "action": ACTION_NONE, "selection": selection }


# Convenience: given a tile, the world units list and an owner filter, return the
# id of the first matching unit standing on that tile, or -1 if none. Ids are
# scanned in ascending order so the pick is deterministic when two units share a
# tile (which should not normally happen after the MA1 formation fix, but the
# stable order keeps every peer in agreement regardless).
#
# `units` is the WorldState units list dictionary (id-string -> unit dict).
static func unit_at_tile(units: Dictionary, tile: Vector2i, owner_filter: int) -> int:
	var keys: Array = units.keys()
	keys.sort_custom(func(a, b): return int(a) < int(b))
	for key in keys:
		var u: Dictionary = units[key]
		if int(u.get("x", -2147483648)) == tile.x and int(u.get("y", -2147483648)) == tile.y:
			if owner_filter < 0 or int(u.get("owner", -1)) == owner_filter:
				return int(u.get("id", -1))
	return -1
