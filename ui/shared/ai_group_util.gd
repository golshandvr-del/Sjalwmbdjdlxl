# ai_group_util.gd
# ----------------------------------------------------------------------------
# Project Nexus - Shared AI / player team-grouping helpers (Phase MB2, bug 5).
#
# Single-player Match Setup lets the player put AIs (and humans) into TEAMS the
# same way the multiplayer host lobby does. This pure, dependency-free helper
# owns the "who is on which team" logic so it can be unit-tested headlessly and
# reused by both Match Setup (single-player) and the lobby if desired.
#
# A "team override" is an explicit owner -> team map the player builds in the UI.
# When present it wins over the automatic per-mode assignment; when absent the
# caller falls back to the deterministic default (GameBootstrap._team_for).
#
# Logic/Render Separation: nothing here touches WorldState or the scene tree.
# Determinism: outputs depend only on the inputs (counts + mode + overrides),
# never on frame timing or unseeded randomness, so every peer/replay agrees.
#
# CODE LANGUAGE POLICY: English-only identifiers/comments.
# ----------------------------------------------------------------------------
class_name AiGroupUtil
extends RefCounted


# How many distinct teams the grouping UI offers (matches the lobby's selector).
const TEAM_COUNT: int = 4


# The deterministic DEFAULT team for a player, mirroring
# GameBootstrap._team_for so single-player setup and the engine agree when the
# player makes no explicit choice. "team"/"ctf" alternate two sides; "ffa" gives
# each player their own team.
static func default_team(owner: int, mode: String) -> int:
	if mode == "team" or mode == "ctf":
		return owner % 2
	return owner


# Build the initial owner -> team override table for `total` players under
# `mode`, seeded with the deterministic defaults so the UI opens on a sensible,
# already-valid layout the player can then tweak.
static func default_overrides(total: int, mode: String) -> Dictionary:
	var out: Dictionary = {}
	for owner in range(max(0, total)):
		out[owner] = default_team(owner, mode)
	return out


# Clamp a chosen team into the valid [0, TEAM_COUNT) range so a malformed UI /
# saved value can never produce an out-of-range team.
static func clamp_team(team: int) -> int:
	return clampi(team, 0, TEAM_COUNT - 1)


# Resolve the FINAL team for one owner: an explicit, in-range override wins;
# otherwise fall back to the deterministic default for the mode. `overrides`
# keys may be ints or their string forms (JSON/section round-trips stringify
# dictionary keys), so both are accepted.
static func resolve_team(owner: int, mode: String, overrides: Dictionary) -> int:
	if overrides.has(owner):
		return clamp_team(int(overrides[owner]))
	if overrides.has(str(owner)):
		return clamp_team(int(overrides[str(owner)]))
	return default_team(owner, mode)


# Group owners by their resolved team: returns team -> sorted Array of owners.
# Handy for validation ("is anyone alone?", "are there >= 2 teams?") and for a
# compact summary label in the UI. Deterministic ordering throughout.
static func teams_to_members(total: int, mode: String, overrides: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for owner in range(max(0, total)):
		var team: int = resolve_team(owner, mode, overrides)
		if not out.has(team):
			out[team] = []
		(out[team] as Array).append(owner)
	# Keep each member list sorted ascending for stable output.
	for team in out.keys():
		(out[team] as Array).sort()
	return out


# Count how many DISTINCT teams are actually in use. A "team" mode match with
# everyone on one side is degenerate; callers can warn on < 2.
static func distinct_team_count(total: int, mode: String, overrides: Dictionary) -> int:
	return teams_to_members(total, mode, overrides).size()


# --- MC9.2 (request 10): map-colour-driven team choices ---------------------
# Instead of the fixed TEAM_COUNT selector, Match Setup derives the SELECTABLE
# team numbers from the colours ACTUALLY used on the chosen map. This returns
# the sorted list of owner-colour slots the map uses (== the team numbers the
# player may pick). Falls back to the default [0..TEAM_COUNT) when the map has
# no colour info (e.g. a blank/undefined scenario).
static func color_team_choices(scenario: Dictionary) -> Array:
	var used: Array = MapColorUtil.used_owners(scenario)
	if used.is_empty():
		var out: Array = []
		for t in range(TEAM_COUNT):
			out.append(t)
		return out
	return used


# Resolve a team choice CONSTRAINED to the map's colours: if the requested team
# is one of the map colours use it, otherwise snap to the FIRST available map
# colour so a stale selection (from a previous map) can never point at a colour
# this map does not have. Deterministic.
static func resolve_team_on_map(scenario: Dictionary, requested: int) -> int:
	var choices: Array = color_team_choices(scenario)
	if choices.has(requested):
		return requested
	return int(choices[0]) if not choices.is_empty() else clamp_team(requested)


# Rebuild an owner -> team override table so every value is a valid map colour.
# Any override pointing at an unused colour is snapped to the first map colour.
# Used when the player switches maps mid-setup. Deterministic.
static func restrict_overrides_to_map(scenario: Dictionary, overrides: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key in overrides.keys():
		out[key] = resolve_team_on_map(scenario, int(overrides[key]))
	return out
