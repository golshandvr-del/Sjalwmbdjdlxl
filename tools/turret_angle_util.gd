# turret_angle_util.gd
# ----------------------------------------------------------------------------
# Project Nexus - Pure angle math for the COSMETIC firing-part render layer
# (Phase MC14, step 14.5, requests 16/18). Two visual behaviours are needed:
#
#   1. A "turret" firing part (firing_mount == turret) must point at its TARGET
#      independently of the way the unit is moving -- e.g. a tank driving north
#      whose barrel tracks an enemy to the east. A "fixed" mount instead always
#      points where the unit faces.
#   2. A defensive building sitting in its READY (idle) state slowly rotates on
#      the spot so it reads as "scanning" until it engages.
#
# CRITICAL determinism note: this layer is PURELY COSMETIC. Every function here
# takes only values the render layer already has (positions, the unit's heading,
# a wall-clock-ish time for idle spin) and returns an angle in RADIANS. NONE of
# it feeds the deterministic simulation or the state hasher: rotating a sprite
# never changes a command, a tick, or a hash. Turret AIM at a target is derived
# from the target POSITION (which the sim owns deterministically), so two peers
# draw the same barrel angle, but even if they did not it would not desync the
# lockstep -- it is draw-only.
#
# All maths is closed-form and dependency-free, so it is fully headless-testable.
#
# CODE LANGUAGE POLICY: English-only identifiers/comments (ASCII).
# ----------------------------------------------------------------------------
class_name TurretAngleUtil
extends RefCounted

# How fast a defensive building spins while idle (radians per second). A gentle
# scan speed; cosmetic only.
const IDLE_SPIN_RADIANS_PER_SEC: float = 0.6

# The screen-space angle (radians) each authored facing points toward, using
# Godot's convention (0 = +x/right, +y is down, so angles grow clockwise).
const FACING_ANGLE: Dictionary = {
	"right": 0.0,
	"down": PI / 2.0,
	"left": PI,
	"up": -PI / 2.0,
}


# The angle (radians) from a firing part's world position toward its target. This
# is what a TURRET mount uses: it aims at the target regardless of unit heading.
static func aim_angle(from_pos: Vector2, target_pos: Vector2) -> float:
	var delta: Vector2 = target_pos - from_pos
	if delta.length_squared() == 0.0:
		return 0.0
	return delta.angle()


# The angle a FIXED-mount firing part draws at: it simply matches the unit's
# movement/facing heading, ignoring the target. `heading` is the unit's current
# facing angle in radians (the render layer already tracks it).
static func fixed_angle(heading: float) -> float:
	return wrap_angle(heading)


# Resolve the angle a firing part should draw at for a given mount. TURRET aims
# at the target; anything else (FIXED) uses the unit heading. Keeps the render
# call-site a single branch-free lookup.
static func firing_part_angle(mount: String, heading: float, from_pos: Vector2, target_pos: Vector2, has_target: bool) -> float:
	if mount == GraphicModel.MOUNT_TURRET and has_target:
		return aim_angle(from_pos, target_pos)
	return fixed_angle(heading)


# The idle-scan angle of a defensive building at a given time. Deterministic in
# its inputs (a phase offset lets several buildings scan out of sync without any
# random state). Cosmetic only.
static func idle_spin_angle(time_seconds: float, phase_offset: float = 0.0) -> float:
	return wrap_angle(time_seconds * IDLE_SPIN_RADIANS_PER_SEC + phase_offset)


# Convert an authored facing ("up"/"down"/"left"/"right") to a draw angle. Used
# to seed a unit's initial heading from its authored facing.
static func facing_to_angle(facing: String) -> float:
	var f: String = GraphicModel.normalise_facing(facing)
	return float(FACING_ANGLE.get(f, 0.0))


# Smoothly step `current` toward `target` by at most `max_step` radians, taking
# the shortest path around the circle. Lets a turret swing to its aim angle over
# several frames instead of snapping. Cosmetic tween helper.
static func step_toward(current: float, target: float, max_step: float) -> float:
	var diff: float = wrap_angle(target - current)
	if absf(diff) <= max_step:
		return wrap_angle(target)
	return wrap_angle(current + signf(diff) * max_step)


# Normalise any angle into the (-PI, PI] range so comparisons/tweens are stable.
static func wrap_angle(angle: float) -> float:
	var a: float = fmod(angle + PI, TAU)
	if a < 0.0:
		a += TAU
	return a - PI
