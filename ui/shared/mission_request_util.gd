# mission_request_util.gd
# ----------------------------------------------------------------------------
# Project Nexus - Strategic "attack/defend a point" mission request model
# (Phase MC11.4, request 11).
#
# When a player asks an ally (or orders itself) to act on a MAP POINT, the
# request carries: a target cell, a mission TYPE (attack / defend / occupy /
# raid / scout), and a COMMITMENT level (how much force to devote, 0..100%).
# This pure, dependency-free helper owns the mission schema + validation +
# (de)serialisation so the mini-map UI, the diplomatic Command and the tests
# all agree on one shape.
#
# Logic/Render Separation: nothing here touches WorldState or the scene tree.
# Determinism: pure arithmetic on the inputs only (cells are integer grid
# coords), so every peer/replay agrees.
#
# CODE LANGUAGE POLICY: English-only identifiers/comments.
# ----------------------------------------------------------------------------
class_name MissionRequestUtil
extends RefCounted


# --- Mission types -------------------------------------------------------
const ATTACK: String = "attack"
const DEFEND: String = "defend"
const OCCUPY: String = "occupy"
const RAID: String = "raid"
const SCOUT: String = "scout"

const TYPES: Array = [ATTACK, DEFEND, OCCUPY, RAID, SCOUT]


# Commitment is a whole percentage 0..100 of the sender's fielded force.
const COMMIT_MIN: int = 0
const COMMIT_MAX: int = 100
const COMMIT_DEFAULT: int = 50


# True when `type_id` is a known mission type.
static func is_valid_type(type_id: String) -> bool:
	return TYPES.has(type_id)


# Clamp a raw commitment value into 0..100.
static func clamp_commitment(value: int) -> int:
	return clampi(value, COMMIT_MIN, COMMIT_MAX)


# Build a mission request record. Cell coords are stored as ints; commitment is
# clamped; an out-of-range/unknown type falls back to ATTACK so a malformed
# request can never crash the deterministic step.
static func make_mission(
		requester: int,
		target_owner: int,
		type_id: String,
		cell_x: int,
		cell_y: int,
		commitment: int) -> Dictionary:
	return {
		"requester": requester,
		"target_owner": target_owner,
		"type": type_id if is_valid_type(type_id) else ATTACK,
		"cell_x": cell_x,
		"cell_y": cell_y,
		"commitment": clamp_commitment(commitment),
	}


# Validate a mission record. Returns "" when valid, else an ASCII error token.
static func validate(mission: Dictionary) -> String:
	if not mission.has("type") or not is_valid_type(str(mission["type"])):
		return "bad_type"
	if not mission.has("cell_x") or not mission.has("cell_y"):
		return "missing_cell"
	if int(mission["cell_x"]) < 0 or int(mission["cell_y"]) < 0:
		return "bad_cell"
	var c: int = int(mission.get("commitment", COMMIT_DEFAULT))
	if c < COMMIT_MIN or c > COMMIT_MAX:
		return "bad_commitment"
	return ""


static func is_valid(mission: Dictionary) -> bool:
	return validate(mission) == ""


# The target cell as a Vector2i (convenience for the mini-map renderer).
static func cell_of(mission: Dictionary) -> Vector2i:
	return Vector2i(int(mission.get("cell_x", 0)), int(mission.get("cell_y", 0)))


static func to_dict(mission: Dictionary) -> Dictionary:
	return mission.duplicate(true)


static func from_dict(data: Dictionary) -> Dictionary:
	return make_mission(
		int(data.get("requester", 0)),
		int(data.get("target_owner", MessageLogUtil.BROADCAST)),
		str(data.get("type", ATTACK)),
		int(data.get("cell_x", 0)),
		int(data.get("cell_y", 0)),
		int(data.get("commitment", COMMIT_DEFAULT)))
