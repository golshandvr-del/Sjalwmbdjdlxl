# diplomacy_module.gd
# ----------------------------------------------------------------------------
# Project Nexus - Dynamic Diplomacy Module (Phase MC10.3 + MC10.4,
# requests 11/12/17).
#
# Holds the dynamic relationship + treaty + deployment state in WorldState and
# reacts to diplomatic COMMANDS (propose/respond/declare_war/break) delivered
# through the command_queue -> EventBus, so every action is deterministic and
# lockstep-safe.
#
# REQUEST 17 (allies must not target each other) is satisfied WITHOUT touching
# combat: when a treaty makes two owners allies we map them onto a shared entry
# in the "match".teams table, and CombatModule._is_hostile already treats
# same-team owners as friendly. Breaking the alliance / declaring war restores
# their distinct teams so they fight again. Alliance expiry is tick-based.
#
# GOLDEN RULE: this module never imports another module; it reads/writes shared
# WorldState sections ("diplomacy", "match") and emits events only.
#
# CODE LANGUAGE POLICY: English-only identifiers/comments.
# ----------------------------------------------------------------------------
class_name DiplomacyModule
extends IModule


# WorldState section this module owns.
const SECTION: String = "diplomacy"

# Diplomatic command event ids (command.<type>).
const CMD_PROPOSE_TREATY: String = "command.propose_treaty"
const CMD_RESPOND_TREATY: String = "command.respond_treaty"
const CMD_DECLARE_WAR: String = "command.declare_war"
const CMD_BREAK_TREATY: String = "command.break_treaty"

# Emitted events (for the message UI in MC11 and for tests).
const EVENT_TREATY_PROPOSED: String = "diplomacy.treaty_proposed"
const EVENT_TREATY_RESPONDED: String = "diplomacy.treaty_responded"
const EVENT_RELATIONSHIP_CHANGED: String = "diplomacy.relationship_changed"
const EVENT_WAR_DECLARED: String = "diplomacy.war_declared"
const EVENT_TREATY_BROKEN: String = "diplomacy.treaty_broken"
const EVENT_TREATY_EXPIRED: String = "diplomacy.treaty_expired"

# Team ids run 0..3 in the base game (see AiGroupUtil.TEAM_COUNT); alliances need
# a fresh, shared team number that never collides with those base teams.
const _ALLIANCE_TEAM_BASE: int = 100

# MC13.5: how often (in ticks) the AI diplomacy brain is polled. Phase-shifted
# per owner inside the planner via AiDifficultyUtil.should_react, so this is the
# coarse cadence at which we even bother assembling the situation.
const AI_DIPLOMACY_INTERVAL: int = 45


func module_id() -> String:
	return "diplomacy"


func init(p_nexus: Object) -> void:
	super.init(p_nexus)
	nexus.subscribe(CMD_PROPOSE_TREATY, self, "_on_bus_event")
	nexus.subscribe(CMD_RESPOND_TREATY, self, "_on_bus_event")
	nexus.subscribe(CMD_DECLARE_WAR, self, "_on_bus_event")
	nexus.subscribe(CMD_BREAK_TREATY, self, "_on_bus_event")
	_ensure_state()


# Lazily create the diplomacy section shape. `relationships` maps a pair key
# (RelationshipUtil.pair_key) -> state string; `treaties` maps a treaty id (str)
# -> treaty record (with an extra "accepted_tick"); `next_treaty_id` is a
# monotonic counter for deterministic ids; `next_alliance_team` grows so each
# alliance gets a unique shared team.
func _ensure_state() -> void:
	var section: Dictionary = nexus.world_state.get_section(SECTION)
	if not section.has("relationships"):
		section["relationships"] = {}
	if not section.has("treaties"):
		section["treaties"] = {}
	if not section.has("next_treaty_id"):
		section["next_treaty_id"] = 0
	if not section.has("next_alliance_team"):
		section["next_alliance_team"] = _ALLIANCE_TEAM_BASE


func _section() -> Dictionary:
	return nexus.world_state.get_section(SECTION)


func _current_tick() -> int:
	return int(nexus.world_state.current_tick)


# --- Relationship API -------------------------------------------------------

# The current relationship between two owners (order-independent), defaulting to
# neutral when nothing has been recorded yet.
func get_relationship(owner_a: int, owner_b: int) -> String:
	if owner_a == owner_b:
		return RelationshipUtil.ALLY
	var key: String = RelationshipUtil.pair_key(owner_a, owner_b)
	var rels: Dictionary = _section()["relationships"]
	return RelationshipUtil.normalize(str(rels.get(key, RelationshipUtil.DEFAULT_STATE)))


# Force a relationship to a new state IF the transition is legal, updating the
# team mapping and emitting a change event. Returns the resulting state.
func set_relationship(owner_a: int, owner_b: int, new_state: String) -> String:
	if owner_a == owner_b:
		return RelationshipUtil.ALLY
	var key: String = RelationshipUtil.pair_key(owner_a, owner_b)
	var rels: Dictionary = _section()["relationships"]
	var current: String = RelationshipUtil.normalize(str(rels.get(key, RelationshipUtil.DEFAULT_STATE)))
	var resolved: String = RelationshipUtil.apply_transition(current, new_state)
	if resolved == current:
		return current
	rels[key] = resolved
	_sync_alliance_teams()
	nexus.emit_event(EVENT_RELATIONSHIP_CHANGED, {
		"owner_a": min(owner_a, owner_b),
		"owner_b": max(owner_a, owner_b),
		"state": resolved,
	})
	return resolved


# --- Treaty API -------------------------------------------------------------

func _treaties() -> Dictionary:
	return _section()["treaties"]


func get_treaty(treaty_id: int) -> Dictionary:
	return (_treaties().get(str(treaty_id), {}) as Dictionary)


# Enqueue a diplomatic action as a deterministic command (the single entry point
# HUD/AI use). Runs on the next tick via the command_queue.
func issue_propose(proposer: int, treaty: Dictionary) -> void:
	nexus.issue_command("propose_treaty", proposer, { "treaty": treaty })


func issue_respond(responder: int, treaty_id: int, accept: bool) -> void:
	nexus.issue_command("respond_treaty", responder, { "treaty_id": treaty_id, "accept": accept })


func issue_declare_war(declarer: int, target: int) -> void:
	nexus.issue_command("declare_war", declarer, { "target": target })


func issue_break_treaty(breaker: int, treaty_id: int) -> void:
	nexus.issue_command("break_treaty", breaker, { "treaty_id": treaty_id })


# --- Event / command handling ----------------------------------------------

func _on_bus_event(event_name: String, payload: Dictionary) -> void:
	handle_event(event_name, payload)


func handle_event(event_name: String, payload: Dictionary) -> void:
	var data: Dictionary = payload.get("data", {})
	match event_name:
		CMD_PROPOSE_TREATY:
			_handle_propose(int(payload.get("issuer", 0)), data)
		CMD_RESPOND_TREATY:
			_handle_respond(int(payload.get("issuer", 0)), data)
		CMD_DECLARE_WAR:
			_handle_declare_war(int(payload.get("issuer", 0)), data)
		CMD_BREAK_TREATY:
			_handle_break_treaty(int(payload.get("issuer", 0)), data)


# Store a proposed treaty; the target must respond before it takes effect.
func _handle_propose(issuer: int, data: Dictionary) -> void:
	var raw: Dictionary = (data.get("treaty", {}) as Dictionary)
	var treaty: Dictionary = TreatyUtil.from_dict(raw)
	# The issuer is always the proposer, regardless of what the payload claimed
	# (prevents spoofing another owner's proposal in lockstep).
	treaty["proposer"] = issuer
	if not TreatyUtil.is_valid(treaty):
		return
	var section: Dictionary = _section()
	var tid: int = int(section["next_treaty_id"])
	section["next_treaty_id"] = tid + 1
	treaty["status"] = TreatyUtil.STATUS_PROPOSED
	treaty["created_tick"] = _current_tick()
	_treaties()[str(tid)] = treaty
	# Opening negotiations nudges a neutral pair toward "negotiating".
	if TreatyUtil.makes_allies(str(treaty["type"])):
		set_relationship(issuer, int(treaty["target"]), RelationshipUtil.NEGOTIATING)
	nexus.emit_event(EVENT_TREATY_PROPOSED, { "treaty_id": tid, "treaty": treaty.duplicate(true) })


# Accept or reject a proposed treaty. Only the treaty's target may respond.
func _handle_respond(issuer: int, data: Dictionary) -> void:
	var tid: int = int(data.get("treaty_id", -1))
	var accept: bool = bool(data.get("accept", false))
	var treaties: Dictionary = _treaties()
	if not treaties.has(str(tid)):
		return
	var treaty: Dictionary = treaties[str(tid)]
	if str(treaty.get("status", "")) != TreatyUtil.STATUS_PROPOSED:
		return
	if int(treaty.get("target", -1)) != issuer:
		return
	if accept:
		treaty["status"] = TreatyUtil.STATUS_ACCEPTED
		treaty["accepted_tick"] = _current_tick()
		_apply_accepted_treaty(treaty)
	else:
		treaty["status"] = TreatyUtil.STATUS_REJECTED
	nexus.emit_event(EVENT_TREATY_RESPONDED, {
		"treaty_id": tid,
		"accepted": accept,
		"treaty": treaty.duplicate(true),
	})


# Apply the relationship consequence of an accepted treaty.
func _apply_accepted_treaty(treaty: Dictionary) -> void:
	var a: int = int(treaty["proposer"])
	var b: int = int(treaty["target"])
	var type_id: String = str(treaty["type"])
	if TreatyUtil.makes_allies(type_id):
		set_relationship(a, b, RelationshipUtil.ALLY)
	elif type_id == TreatyUtil.CEASEFIRE:
		set_relationship(a, b, RelationshipUtil.CEASEFIRE)
	elif type_id == TreatyUtil.NON_AGGRESSION:
		# A neutral pair stays neutral (non-hostile); a hostile pair de-escalates
		# through ceasefire first (relationship transition rules enforce this).
		set_relationship(a, b, RelationshipUtil.CEASEFIRE)


# Declare war: force the pair to the enemy state (via the allowed path) and drop
# any active alliance between them.
func _handle_declare_war(issuer: int, data: Dictionary) -> void:
	var target: int = int(data.get("target", -1))
	if target < 0 or target == issuer:
		return
	# From ally/vassal, war is a betrayal: transitions go ally -> enemy directly.
	set_relationship(issuer, target, RelationshipUtil.ENEMY)
	nexus.emit_event(EVENT_WAR_DECLARED, { "declarer": issuer, "target": target })


# Break an accepted treaty early (recalls its alliance/team mapping).
func _handle_break_treaty(issuer: int, data: Dictionary) -> void:
	var tid: int = int(data.get("treaty_id", -1))
	var treaties: Dictionary = _treaties()
	if not treaties.has(str(tid)):
		return
	var treaty: Dictionary = treaties[str(tid)]
	# Only a party to the treaty may break it.
	if issuer != int(treaty.get("proposer", -1)) and issuer != int(treaty.get("target", -1)):
		return
	if str(treaty.get("status", "")) != TreatyUtil.STATUS_ACCEPTED:
		return
	treaty["status"] = TreatyUtil.STATUS_CANCELLED
	# Breaking an alliance drops the pair back to neutral (or suspicious).
	if TreatyUtil.makes_allies(str(treaty["type"])):
		var a: int = int(treaty["proposer"])
		var b: int = int(treaty["target"])
		# Force via the allowed ally -> suspicious step.
		set_relationship(a, b, RelationshipUtil.SUSPICIOUS)
	nexus.emit_event(EVENT_TREATY_BROKEN, { "treaty_id": tid, "breaker": issuer })


# --- Tick: expire accepted treaties -----------------------------------------

func on_tick(_delta_tick: int) -> void:
	var now: int = _current_tick()
	var treaties: Dictionary = _treaties()
	var keys: Array = treaties.keys()
	keys.sort()
	var expired_any: bool = false
	for key in keys:
		var treaty: Dictionary = treaties[key]
		if str(treaty.get("status", "")) != TreatyUtil.STATUS_ACCEPTED:
			continue
		var accepted_tick: int = int(treaty.get("accepted_tick", 0))
		if TreatyUtil.is_expired(treaty, accepted_tick, now):
			treaty["status"] = TreatyUtil.STATUS_EXPIRED
			expired_any = true
			if TreatyUtil.makes_allies(str(treaty["type"])):
				var a: int = int(treaty["proposer"])
				var b: int = int(treaty["target"])
				set_relationship(a, b, RelationshipUtil.NEUTRAL)
			nexus.emit_event(EVENT_TREATY_EXPIRED, { "treaty_id": int(str(key)) })
	if expired_any:
		_sync_alliance_teams()


# --- Alliance -> match.teams mapping (request 17) ---------------------------

# Rebuild the shared-team assignment for allied owners so CombatModule sees them
# as friendly. We union owners that are currently allies (ally/vassal) into a
# connected component and give every member of a component the same fresh team
# id, written into the "match".teams table. Non-allied owners keep whatever base
# team they had (their own team by default). Fully deterministic.
func _sync_alliance_teams() -> void:
	var match_section: Dictionary = nexus.world_state.get_section("match")
	if not match_section.has("teams"):
		match_section["teams"] = {}
	var teams: Dictionary = match_section["teams"]
	# Collect all owners mentioned by a relationship plus any already teamed.
	var owners: Dictionary = {}
	var rels: Dictionary = _section()["relationships"]
	for key in rels.keys():
		var parts: PackedStringArray = str(key).split(":")
		if parts.size() == 2:
			owners[int(parts[0])] = true
			owners[int(parts[1])] = true
	# Union-find over allied pairs.
	var parent: Dictionary = {}
	for o in owners.keys():
		parent[o] = o
	for key in rels.keys():
		if not RelationshipUtil.is_friendly(str(rels[key])):
			continue
		var parts: PackedStringArray = str(key).split(":")
		if parts.size() != 2:
			continue
		_union(parent, int(parts[0]), int(parts[1]))
	# Assign each allied component a fresh shared team; singletons keep their own.
	var component_members: Dictionary = {}
	for o in owners.keys():
		var root: int = _find(parent, o)
		if not component_members.has(root):
			component_members[root] = []
		(component_members[root] as Array).append(o)
	var section: Dictionary = _section()
	for root in component_members.keys():
		var members: Array = component_members[root]
		if members.size() < 2:
			# A lone owner is no longer allied: restore its own team.
			var solo: int = int(members[0])
			teams[str(solo)] = solo
			continue
		members.sort()
		var team_id: int = int(section["next_alliance_team"])
		section["next_alliance_team"] = team_id + 1
		for m in members:
			teams[str(int(m))] = team_id


func _find(parent: Dictionary, x: int) -> int:
	var root: int = x
	while int(parent.get(root, root)) != root:
		root = int(parent[root])
	# Path compression for stability.
	var cur: int = x
	while int(parent.get(cur, cur)) != root:
		var nxt: int = int(parent[cur])
		parent[cur] = root
		cur = nxt
	return root


func _union(parent: Dictionary, a: int, b: int) -> void:
	var ra: int = _find(parent, a)
	var rb: int = _find(parent, b)
	if ra == rb:
		return
	# Attach higher root under lower for deterministic, stable roots.
	if ra < rb:
		parent[rb] = ra
	else:
		parent[ra] = rb


# --- Save / load ------------------------------------------------------------

func serialize() -> Dictionary:
	return _section().duplicate(true)


func deserialize(data: Dictionary) -> void:
	var section: Dictionary = _section()
	section.clear()
	for key in data.keys():
		section[key] = data[key]
	_ensure_state()
	_sync_alliance_teams()
