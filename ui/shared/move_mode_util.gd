# move_mode_util.gd
# ----------------------------------------------------------------------------
# Project Nexus - Shared move-mode logic (Phase MC1, step MC1.5, request 1).
#
# Pure, dependency-free helper that decides what a tap on empty ground does while
# a selection is active, honouring the TWO movement modes the player can pick:
#
#   * DIRECT mode  (default): a tap on empty ground issues an immediate
#     `move_unit` toward that single tile (belief-aware A* + formation spread --
#     the long-standing behaviour).
#   * MANUAL mode            : consecutive taps ACCUMULATE ordered waypoints; the
#     unit does not move yet. A confirming action (the "commit" tap/button)
#     issues one `move_unit` carrying the whole `waypoints` array so the unit
#     travels EXACTLY through the drawn route (stitched by WaypointUtil in
#     units_module). A "cancel" clears the pending route without moving.
#
# Keeping this state machine OUT of the HUD scripts (which depend on the Nexus
# autoload, a live RenderAdapter and a running SceneTree) lets the exact
# mode/tap/commit behaviour be unit-tested headlessly, and lets the mobile HUD
# and the desktop HUD share one implementation so they never diverge.
#
# Logic/Render Separation: nothing here mutates WorldState or the HUD. The util
# only tracks the pending waypoint buffer and returns a small plan; the caller
# pushes the authoritative `move_unit` command exactly as before. The accumulated
# waypoints are a cosmetic PLANNING buffer -- they never touch the deterministic
# state hash until the caller issues the command.
#
# Determinism: waypoints are appended in tap order and forwarded verbatim; the
# resulting command is identical on every peer, and units_module resolves the
# path deterministically (WaypointUtil + belief A*).
#
# CODE LANGUAGE POLICY: English-only identifiers/comments (ASCII).
# ----------------------------------------------------------------------------
class_name MoveModeUtil
extends RefCounted


# The two selectable movement modes.
const MODE_DIRECT: String = "direct"    # tap -> immediate single-goal move
const MODE_MANUAL: String = "manual"    # taps accumulate a waypoint route

# Plan actions a ground tap / commit / cancel can resolve to.
const ACTION_NONE: String = "none"           # nothing to do
const ACTION_MOVE_DIRECT: String = "move"    # issue a single-goal move_unit
const ACTION_ADD_WAYPOINT: String = "add"    # buffered a waypoint (no command yet)
const ACTION_MOVE_PATH: String = "move_path" # issue a waypoint move_unit (commit)
const ACTION_CLEAR: String = "clear"         # cleared the pending route (cancel)


var _mode: String = MODE_DIRECT
# Pending ordered waypoint buffer (Array of Vector2i) for MANUAL mode. Consecutive
# duplicate tiles are collapsed so the route has no zero-length segments.
var _waypoints: Array = []


# --- Mode -------------------------------------------------------------------

func mode() -> String:
	return _mode


func is_manual() -> bool:
	return _mode == MODE_MANUAL


# Flip between DIRECT and MANUAL. Switching AWAY from manual discards any pending
# route so a stale half-drawn path can never leak into the next command.
func toggle_mode() -> String:
	if _mode == MODE_MANUAL:
		set_mode(MODE_DIRECT)
	else:
		set_mode(MODE_MANUAL)
	return _mode


# Set the mode explicitly. Any value other than MODE_MANUAL is treated as DIRECT.
# Leaving MANUAL clears the pending waypoints.
func set_mode(new_mode: String) -> void:
	var normalised: String = MODE_MANUAL if new_mode == MODE_MANUAL else MODE_DIRECT
	if normalised != MODE_MANUAL:
		_waypoints.clear()
	_mode = normalised


# --- Pending route ----------------------------------------------------------

# A copy of the current pending waypoint buffer (Vector2i), for the renderer to
# draw the route preview. Never returns the internal Array by reference.
func waypoints() -> Array:
	return _waypoints.duplicate()


func has_pending() -> bool:
	return not _waypoints.is_empty()


func clear() -> void:
	_waypoints.clear()


# --- Tap resolution ---------------------------------------------------------

# Resolve a tap on empty GROUND (i.e. TapSelectUtil already decided this is a
# move, not a unit toggle). `tile` is the tapped tile; `has_selection` is whether
# any friendly unit is currently selected.
#
# Returns a Dictionary:
#   {
#     "action"    : ACTION_NONE | ACTION_MOVE_DIRECT | ACTION_ADD_WAYPOINT,
#     "tile"      : Vector2i,   # the tapped tile (for a direct move)
#     "waypoints" : Array,      # pending route AFTER the tap (manual mode)
#   }
#
# DIRECT mode  -> ACTION_MOVE_DIRECT (caller issues move_unit to `tile`).
# MANUAL mode  -> ACTION_ADD_WAYPOINT, appending the tile to the buffer (unless it
#                 duplicates the previous one). No command is issued yet.
# No selection -> ACTION_NONE.
func resolve_ground_tap(tile: Vector2i, has_selection: bool) -> Dictionary:
	if not has_selection:
		return { "action": ACTION_NONE, "tile": tile, "waypoints": waypoints() }
	if _mode != MODE_MANUAL:
		return { "action": ACTION_MOVE_DIRECT, "tile": tile, "waypoints": [] }
	# Manual mode: append the waypoint (collapse consecutive duplicates).
	if _waypoints.is_empty() or _waypoints[_waypoints.size() - 1] != tile:
		_waypoints.append(tile)
	return { "action": ACTION_ADD_WAYPOINT, "tile": tile, "waypoints": waypoints() }


# Commit the pending manual route. Returns a plan:
#   { "action": ACTION_MOVE_PATH, "waypoints": [[x,y], ...] }  when there is a
#       route to issue; the waypoints are returned as [x, y] PAIRS ready for the
#       move_unit command payload. The buffer is CLEARED afterwards.
#   { "action": ACTION_NONE, "waypoints": [] }  when there is nothing pending.
func commit() -> Dictionary:
	if _waypoints.is_empty():
		return { "action": ACTION_NONE, "waypoints": [] }
	var pairs: Array = []
	for wp in _waypoints:
		pairs.append([wp.x, wp.y])
	_waypoints.clear()
	return { "action": ACTION_MOVE_PATH, "waypoints": pairs }


# Cancel the pending route without moving. Returns:
#   { "action": ACTION_CLEAR }  if something was cleared,
#   { "action": ACTION_NONE }   if the buffer was already empty.
func cancel() -> Dictionary:
	if _waypoints.is_empty():
		return { "action": ACTION_NONE }
	_waypoints.clear()
	return { "action": ACTION_CLEAR }
