# deployment_util.gd
# ----------------------------------------------------------------------------
# Project Nexus - Dynamic diplomacy temporary unit deployment (Phase MC10.6,
# requests 11/12/17).
#
# "Giving units" to an ally is modelled as a TEMPORARY DEPLOYMENT / SHARED
# COMMAND, never an ownership transfer. The lending owner keeps ownership; the
# borrowing owner may command the units for a fixed number of ticks, after which
# the units automatically RETURN to their owner. This design is exploit-proof:
# you can never permanently strip an ally of their army, and a broken alliance
# recalls the loan immediately. This pure helper owns the deployment record +
# its lifecycle so the math is identical on every peer and unit-testable.
#
# Logic/Render Separation: nothing here touches WorldState or the scene tree;
# it operates on plain deployment records (Dictionaries).
# Determinism: durations are counted in ticks (never wall-clock).
#
# CODE LANGUAGE POLICY: English-only identifiers/comments.
# ----------------------------------------------------------------------------
class_name DeploymentUtil
extends RefCounted


const STATUS_ACTIVE: String = "active"
const STATUS_RETURNED: String = "returned"
const STATUS_RECALLED: String = "recalled"

const STATUSES: Array = [STATUS_ACTIVE, STATUS_RETURNED, STATUS_RECALLED]


# Build a deployment record: `owner` lends `unit_ids` to `borrower` starting at
# `start_tick` for `duration_ticks` ticks (must be > 0 - a permanent loan would
# be an ownership transfer, which this system forbids). Ownership NEVER changes:
# `owner` stays the owner; only command authority is shared for the window.
static func make_deployment(
		owner: int,
		borrower: int,
		unit_ids: Array,
		start_tick: int,
		duration_ticks: int) -> Dictionary:
	var ids: Array = []
	for uid in unit_ids:
		ids.append(int(uid))
	return {
		"owner": owner,
		"borrower": borrower,
		"unit_ids": ids,
		"start_tick": max(0, start_tick),
		# Clamp to at least 1 tick so a deployment is always temporary.
		"duration_ticks": max(1, duration_ticks),
		"status": STATUS_ACTIVE,
	}


# Validate a deployment record. Returns "" when valid, else an ASCII error token.
static func validate(dep: Dictionary) -> String:
	if not dep.has("owner") or not dep.has("borrower"):
		return "missing_party"
	if int(dep["owner"]) == int(dep["borrower"]):
		return "self_deploy"
	if int(dep["owner"]) < 0 or int(dep["borrower"]) < 0:
		return "bad_party"
	if not dep.has("unit_ids") or (dep["unit_ids"] as Array).is_empty():
		return "no_units"
	if int(dep.get("duration_ticks", 0)) < 1:
		return "bad_duration"
	return ""


static func is_valid(dep: Dictionary) -> bool:
	return validate(dep) == ""


# The absolute tick at which an active deployment returns on its own.
static func return_tick(dep: Dictionary) -> int:
	return int(dep.get("start_tick", 0)) + int(dep.get("duration_ticks", 1))


# True when the loan window has elapsed at `now_tick` (units must go home).
static func is_expired(dep: Dictionary, now_tick: int) -> bool:
	return now_tick >= return_tick(dep)


# Who currently COMMANDS a given unit under this deployment: the borrower while
# the loan is active and unexpired, otherwise the true owner. This is the single
# exploit-proof authority check - once expired/recalled, command snaps back to
# the owner no matter what the borrower does.
static func commander_of(dep: Dictionary, unit_id: int, now_tick: int) -> int:
	var owner: int = int(dep.get("owner", -1))
	if not (dep.get("unit_ids", []) as Array).has(int(unit_id)):
		return owner
	if str(dep.get("status", STATUS_ACTIVE)) != STATUS_ACTIVE:
		return owner
	if is_expired(dep, now_tick):
		return owner
	return int(dep.get("borrower", owner))


# Mark a deployment as ended (returned when it expired naturally, recalled when
# the owner or a broken alliance pulls it early). Ownership was never lost, so
# "ending" simply removes the borrower's command authority.
static func end_deployment(dep: Dictionary, recalled: bool) -> Dictionary:
	var out: Dictionary = dep.duplicate(true)
	out["status"] = STATUS_RECALLED if recalled else STATUS_RETURNED
	return out


static func to_dict(dep: Dictionary) -> Dictionary:
	return dep.duplicate(true)


static func from_dict(data: Dictionary) -> Dictionary:
	var out: Dictionary = make_deployment(
		int(data.get("owner", 0)),
		int(data.get("borrower", 1)),
		(data.get("unit_ids", []) as Array),
		int(data.get("start_tick", 0)),
		int(data.get("duration_ticks", 1)))
	var stored: String = str(data.get("status", STATUS_ACTIVE))
	if STATUSES.has(stored):
		out["status"] = stored
	return out
