# lobby_state_util.gd
# ----------------------------------------------------------------------------
# Project Nexus - Lobby State Utilities (Phase MB5, bugs 9, 10, 11, 13, 14).
#
# A PURE, dependency-free helper for the multiplayer lobby's slot model. It owns
# no engine state: every function takes plain Arrays/Dictionaries and returns
# new plain values, so the tricky host<->client sync rules (who is ready, which
# bots are visible, which slot a peer owns, whether the match can start) can be
# unit-tested headlessly without a live transport.
#
# The lobby scene (ui/shared/lobby.gd) delegates its decisions here so the two
# never drift. Slots are dictionaries of the shape:
#   { kind:"human"|"ai", team:int, ready:bool, peer:int(-1 if empty) }
#
# CODE LANGUAGE POLICY: English-only identifiers/comments.
# ----------------------------------------------------------------------------
class_name LobbyStateUtil
extends RefCounted

const KIND_HUMAN: String = "human"
const KIND_AI: String = "ai"


# Build the initial host-side slot model: `human_players` human slots followed by
# `ai_players` AI slots. Slot 0 is the host (peer 0). AI slots are always ready.
# `team_mode` == "team" alternates teams 0/1; otherwise each slot gets a unique
# team (ffa / ctf). Pure: returns a fresh Array of fresh Dictionaries.
static func build_host_slots(human_players: int, ai_players: int, team_mode: String) -> Array:
	var slots: Array = []
	var total: int = max(0, human_players) + max(0, ai_players)
	for i in range(total):
		var kind: String = KIND_HUMAN if i < human_players else KIND_AI
		slots.append({
			"kind": kind,
			"team": _default_team_for(i, team_mode),
			"ready": (kind == KIND_AI),
			"peer": (0 if i == 0 else -1),
		})
	return slots


static func _default_team_for(index: int, team_mode: String) -> int:
	if team_mode == "team":
		return index % 2
	return index


# Assign a newly-connected peer to the first OPEN human slot (peer < 0). Mutates
# `slots` in place and returns the slot index chosen, or -1 if the lobby is full.
static func assign_peer_to_open_slot(slots: Array, peer: int) -> int:
	for i in range(slots.size()):
		var slot: Dictionary = slots[i]
		if str(slot.get("kind", "")) == KIND_HUMAN and int(slot.get("peer", -1)) < 0:
			slot["peer"] = peer
			return i
	return -1


# Find the slot a given peer id controls, or -1. The host owns slot 0 by
# convention, but this resolves by peer id so it works for host and client alike.
static func slot_index_for_peer(slots: Array, peer: int) -> int:
	for i in range(slots.size()):
		if int((slots[i] as Dictionary).get("peer", -1)) == peer:
			return i
	return -1


# Count human slots that currently have a peer assigned (occupied seats).
static func filled_human_slots(slots: Array) -> int:
	var n: int = 0
	for slot in slots:
		if str((slot as Dictionary).get("kind", "")) == KIND_HUMAN and int((slot as Dictionary).get("peer", -1)) >= 0:
			n += 1
	return n


# The match can start only when every OCCUPIED human slot is ready. Empty human
# slots and AI slots never block the start (AIs are always ready). An all-AI /
# solo-host lobby is therefore startable immediately.
static func can_start(slots: Array) -> bool:
	for slot in slots:
		var s: Dictionary = slot
		if str(s.get("kind", "")) == KIND_HUMAN and int(s.get("peer", -1)) >= 0 and not bool(s.get("ready", false)):
			return false
	return true


# Set the ready flag on the slot owned by `peer`. Mutates `slots`; returns true
# if a matching slot was found. Used by the host when a client's ready_state
# control message arrives (bugs 9 / 14).
static func set_ready_for_peer(slots: Array, peer: int, ready: bool) -> bool:
	var idx: int = slot_index_for_peer(slots, peer)
	if idx < 0:
		return false
	(slots[idx] as Dictionary)["ready"] = ready
	return true


# A plain, serializable snapshot of the slot layout for the control channel:
# only ints/strings/bools so it survives RPC / loopback intact. INCLUDES AI
# slots so a joining client sees the bots too (bug 10).
static func snapshot(slots: Array) -> Array:
	var out: Array = []
	for slot in slots:
		var s: Dictionary = slot
		out.append({
			"kind": str(s.get("kind", KIND_HUMAN)),
			"team": int(s.get("team", 0)),
			"ready": bool(s.get("ready", false)),
			"peer": int(s.get("peer", -1)),
		})
	return out


# Rebuild a slot model from a snapshot (client side). Pure: returns a fresh Array.
static func from_snapshot(snapshot_in: Array) -> Array:
	var out: Array = []
	for entry in snapshot_in:
		var e: Dictionary = entry
		out.append({
			"kind": str(e.get("kind", KIND_HUMAN)),
			"team": int(e.get("team", 0)),
			"ready": bool(e.get("ready", false)),
			"peer": int(e.get("peer", -1)),
		})
	return out


# Build the placements array (STRUCTURE.md 9.8) from the slot model. Pure so it
# can be reused to persist locally AND to ship to clients over the control
# channel, guaranteeing both sides build an identical world.
static func placements(slots: Array) -> Array:
	var out: Array = []
	for i in range(slots.size()):
		var s: Dictionary = slots[i]
		out.append({
			"slot": i,
			"kind": str(s.get("kind", KIND_HUMAN)),
			"team": int(s.get("team", 0)),
			"flag_index": i,
		})
	return out
