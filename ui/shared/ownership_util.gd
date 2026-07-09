# ownership_util.gd
# ----------------------------------------------------------------------------
# Project Nexus - Shared "who can the local device control?" logic (Phase MB1.2).
#
# Pure, dependency-free helper that decides whether a given `owner` id is
# CONTROLLABLE by the human sitting at THIS device. This is the single source of
# truth behind Nexus.is_locally_controlled(owner) and every HUD selection path.
#
# The bug this fixes (MB1.2 / bug 1 - "teammate control leak"): on a team match
# the human shares a team with an AI teammate. Tapping / box-selecting an AI
# teammate's unit must NOT select it -- the local player only ever commands the
# units they own. Centralising the rule here (instead of scattering an ad-hoc
# `owner == LOCAL_PLAYER` check across two HUDs) means every selection path
# agrees, and the rule is unit-testable without the Nexus autoload / SceneTree.
#
# Rule set (deterministic, no engine singletons):
#   * If an explicit local_players set is provided (hot-seat / networked seat
#     ownership), an owner is controllable IFF it is in that set.
#   * Otherwise the local player is `local_player` (single-player default 0):
#     controllable IFF owner == local_player.
#   * Negative owner (-1 / no unit) is never controllable.
#
# CODE LANGUAGE POLICY: English-only identifiers/comments (ASCII).
# ----------------------------------------------------------------------------
class_name OwnershipUtil
extends RefCounted


# Return true when `owner` may be commanded by the human at this device.
#
#   owner         : the unit/building owner id under inspection.
#   local_player  : the id THIS device drives when no explicit set is given.
#   local_players : optional Array of owner ids this device controls (hot-seat /
#                   assigned seats). When non-empty it fully decides the answer.
static func is_locally_controlled(owner: int, local_player: int, local_players: Array = []) -> bool:
	if owner < 0:
		return false
	if not local_players.is_empty():
		for candidate in local_players:
			if int(candidate) == owner:
				return true
		return false
	return owner == local_player


# Resolve the set of locally controllable owner ids from a session_info-style
# dictionary. Kept pure so the HUD can pass the raw world_state section and the
# tests can pass a plain Dictionary. Falls back to [local_player] when the
# session carries no explicit seat ownership.
#
#   session : Dictionary that MAY contain "local_players" (Array of ids).
static func local_players_from_session(session: Dictionary, local_player: int) -> Array:
	var raw: Array = session.get("local_players", []) as Array
	if raw.is_empty():
		return [local_player]
	var ids: Array = []
	for candidate in raw:
		var value: int = int(candidate)
		if not ids.has(value):
			ids.append(value)
	ids.sort()
	return ids
