# waypoint_util.gd
# ----------------------------------------------------------------------------
# Project Nexus - Waypoint Util (Phase MC1, request 1, manual-path mode).
#
# Pure, deterministic helper for the "manual path" movement mode: the user (or a
# strategic AI planner) supplies an ORDERED list of waypoints and the unit must
# travel through them in sequence. This util stitches the per-segment paths
# (start -> wp0 -> wp1 -> ... -> wpN) into one continuous tile path.
#
# It does NOT do pathfinding itself; the caller passes a `segment_solver`
# Callable that returns a tile path (Array of Vector2i, inclusive of both ends)
# for a single segment. Keeping the solver injected lets units_module reuse its
# belief-aware PathService while this util stays a dependency-free, headlessly
# unit-testable pure function.
#
# Determinism: the output is a pure function of (start, waypoints, segment_solver
# output). As long as the solver is deterministic (PathService is), the stitched
# path is deterministic and lockstep-safe.
#
# CODE LANGUAGE POLICY: English-only identifiers/comments.
# ----------------------------------------------------------------------------
class_name WaypointUtil
extends RefCounted


# Normalise a raw waypoints value (from a command payload) into a clean Array of
# Vector2i. Accepts entries shaped as [x, y] pairs or Vector2i. Consecutive
# duplicates are collapsed so the stitched path has no zero-length segments.
static func normalize(raw: Variant) -> Array:
	var out: Array = []
	if not (raw is Array):
		return out
	for entry in (raw as Array):
		var p: Vector2i
		if entry is Vector2i:
			p = entry
		elif entry is Array and (entry as Array).size() >= 2:
			p = Vector2i(int(entry[0]), int(entry[1]))
		else:
			continue
		if out.is_empty() or out[out.size() - 1] != p:
			out.append(p)
	return out


# Build the full tile path from `start` through every waypoint in order.
#
#   start          : the unit's current tile (Vector2i).
#   waypoints      : ORDERED Array of Vector2i (already normalized) to visit.
#   segment_solver : Callable(from: Vector2i, to: Vector2i) -> Array[Vector2i]
#                    returning an inclusive path for a single segment, or [] if
#                    that segment is unreachable.
#
# Returns a single Array of Vector2i starting at `start` and ending at the last
# reachable waypoint. Segment joins are de-duplicated so the shared tile between
# two consecutive segments is not repeated. If a segment is unreachable the path
# stops at the last reachable point (partial travel is better than none, and the
# unit can replan/re-order later). Returns [start] when there are no waypoints.
static func stitch_path(start: Vector2i, waypoints: Array, segment_solver: Callable) -> Array:
	var full: Array = [start]
	var cursor: Vector2i = start
	for wp in waypoints:
		if not (wp is Vector2i):
			continue
		if wp == cursor:
			continue
		var seg: Array = segment_solver.call(cursor, wp)
		if seg == null or seg.is_empty():
			# Unreachable segment: stop here with whatever we have so far.
			break
		# Skip seg[0] (== cursor, already the tail of `full`) to avoid a repeat.
		for i in range(1, seg.size()):
			full.append(seg[i])
		cursor = wp
	return full
