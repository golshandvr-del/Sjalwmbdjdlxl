# treaty_util.gd
# ----------------------------------------------------------------------------
# Project Nexus - Dynamic diplomacy treaty / contract model (Phase MC10.2,
# requests 11/12/17).
#
# A TREATY is a structured proposal between two owners: a type, the two parties,
# what the proposer GIVES, what it WANTS, a validity duration (in ticks) and an
# optional cancel condition. This pure, dependency-free helper owns the treaty
# schema, its constructors, validation and (de)serialisation so the module,
# the diplomatic Commands and the tests all agree on one shape.
#
# Logic/Render Separation: nothing here touches WorldState or the scene tree.
# Determinism: outputs depend only on the inputs; durations are counted in
# ticks (never wall-clock), so every peer/replay agrees on expiry.
#
# CODE LANGUAGE POLICY: English-only identifiers/comments.
# ----------------------------------------------------------------------------
class_name TreatyUtil
extends RefCounted


# --- Treaty types --------------------------------------------------------
const CEASEFIRE: String = "ceasefire"
const NON_AGGRESSION: String = "non_aggression"
const ALLIANCE_TEMP: String = "alliance_temp"
const ALLIANCE_FULL: String = "alliance_full"
const DECLARE_WAR: String = "declare_war"
const TRADE_RESOURCE: String = "trade_resource"
const DEPLOY_UNITS: String = "deploy_units"
const REQUEST_ATTACK: String = "request_attack"
const REQUEST_DEFENSE: String = "request_defense"
const MILITARY_ACCESS: String = "military_access"
const TRIBUTE: String = "tribute"
const ESPIONAGE: String = "espionage"
const BETRAYAL: String = "betrayal"

const TYPES: Array = [
	CEASEFIRE,
	NON_AGGRESSION,
	ALLIANCE_TEMP,
	ALLIANCE_FULL,
	DECLARE_WAR,
	TRADE_RESOURCE,
	DEPLOY_UNITS,
	REQUEST_ATTACK,
	REQUEST_DEFENSE,
	MILITARY_ACCESS,
	TRIBUTE,
	ESPIONAGE,
	BETRAYAL,
]


# --- Treaty status -------------------------------------------------------
const STATUS_PROPOSED: String = "proposed"
const STATUS_ACCEPTED: String = "accepted"
const STATUS_REJECTED: String = "rejected"
const STATUS_EXPIRED: String = "expired"
const STATUS_CANCELLED: String = "cancelled"

const STATUSES: Array = [
	STATUS_PROPOSED,
	STATUS_ACCEPTED,
	STATUS_REJECTED,
	STATUS_EXPIRED,
	STATUS_CANCELLED,
]


# A duration of 0 means "no expiry" (permanent until broken).
const DURATION_PERMANENT: int = 0


# True when `type_id` is a known treaty type.
static func is_valid_type(type_id: String) -> bool:
	return TYPES.has(type_id)


# Types that (when accepted) make the two parties ALLIES: the module maps these
# onto `match.teams` so combat treats them as friendly (request 17).
static func makes_allies(type_id: String) -> bool:
	return type_id == ALLIANCE_TEMP or type_id == ALLIANCE_FULL


# Types that (when accepted) make the two parties HOSTILE toward each other.
static func makes_hostile(type_id: String) -> bool:
	return type_id == DECLARE_WAR or type_id == BETRAYAL


# Build a fresh treaty proposal as a plain Dictionary. `gives` / `wants` are
# free-form Dictionaries (e.g. {"gold": 100} or {"units": [12, 13]}); the cancel
# condition is a free-form Dictionary too so callers can encode arbitrary
# triggers without changing this schema.
static func make_treaty(
		type_id: String,
		proposer: int,
		target: int,
		gives: Dictionary,
		wants: Dictionary,
		duration_ticks: int,
		created_tick: int,
		cancel_condition: Dictionary = {}) -> Dictionary:
	return {
		"type": type_id,
		"proposer": proposer,
		"target": target,
		"gives": gives.duplicate(true),
		"wants": wants.duplicate(true),
		"duration_ticks": max(0, duration_ticks),
		"created_tick": max(0, created_tick),
		"cancel_condition": cancel_condition.duplicate(true),
		"status": STATUS_PROPOSED,
	}


# Validate a treaty Dictionary. Returns "" when valid, otherwise a short
# machine-readable error token (kept ASCII so it can be a localisation key).
static func validate(treaty: Dictionary) -> String:
	if not treaty.has("type") or not is_valid_type(str(treaty["type"])):
		return "bad_type"
	if not treaty.has("proposer") or not treaty.has("target"):
		return "missing_party"
	var proposer: int = int(treaty["proposer"])
	var target: int = int(treaty["target"])
	if proposer == target:
		return "self_treaty"
	if proposer < 0 or target < 0:
		return "bad_party"
	if int(treaty.get("duration_ticks", 0)) < 0:
		return "bad_duration"
	if treaty.has("status") and not STATUSES.has(str(treaty["status"])):
		return "bad_status"
	return ""


# True when `treaty` passes validation.
static func is_valid(treaty: Dictionary) -> bool:
	return validate(treaty) == ""


# The absolute tick at which an accepted treaty expires, or -1 when permanent.
# Only meaningful once accepted; `accepted_tick` is when it took effect.
static func expiry_tick(treaty: Dictionary, accepted_tick: int) -> int:
	var dur: int = int(treaty.get("duration_ticks", DURATION_PERMANENT))
	if dur <= DURATION_PERMANENT:
		return -1
	return max(0, accepted_tick) + dur


# True when an accepted treaty has expired at `now_tick`. Permanent treaties
# (duration 0) never expire on their own.
static func is_expired(treaty: Dictionary, accepted_tick: int, now_tick: int) -> bool:
	var exp: int = expiry_tick(treaty, accepted_tick)
	if exp < 0:
		return false
	return now_tick >= exp


# Serialise to a JSON-safe Dictionary (already plain), duplicating nested
# containers so callers cannot mutate stored state by reference.
static func to_dict(treaty: Dictionary) -> Dictionary:
	return treaty.duplicate(true)


# Rebuild a treaty from a stored/JSON Dictionary, normalising missing fields to
# safe defaults so a partial/legacy record still loads. Preserves the stored
# status (proposed/accepted/...) when present so round-trips are lossless.
static func from_dict(data: Dictionary) -> Dictionary:
	var out: Dictionary = make_treaty(
		str(data.get("type", CEASEFIRE)),
		int(data.get("proposer", 0)),
		int(data.get("target", 1)),
		(data.get("gives", {}) as Dictionary),
		(data.get("wants", {}) as Dictionary),
		int(data.get("duration_ticks", DURATION_PERMANENT)),
		int(data.get("created_tick", 0)),
		(data.get("cancel_condition", {}) as Dictionary))
	var stored_status: String = str(data.get("status", STATUS_PROPOSED))
	if STATUSES.has(stored_status):
		out["status"] = stored_status
	return out
