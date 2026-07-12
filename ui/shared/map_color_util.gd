# map_color_util.gd
# ----------------------------------------------------------------------------
# Project Nexus - Map colour -> team extraction (Phase MC9, step 9.1, request 10).
#
# Request 10 asks that teams be derived from the colours ACTUALLY USED on a map,
# not from where the HQs happen to be. A map places entities (buildings, units,
# flags, players) that each carry an `owner` index into the fixed 16-colour
# palette (see MapPaletteUtil). This PURE, dependency-free helper scans a
# scenario/map Dictionary and reports which of the 16 owner colours are in use.
#
# Match Setup (MC9.2) then offers only those colours as selectable "team
# numbers", so a 4-colour map yields exactly 4 team slots regardless of HQ
# placement, and a colour that only appears on loose units (no HQ -- a "rebel"
# faction, MC9.3) still counts as a team.
#
# DETERMINISM: output depends only on the input dictionary; used_owners() always
# returns a sorted Array so every peer/replay agrees. Nothing here touches
# WorldState or the simulation hash.
#
# CODE LANGUAGE POLICY: English-only identifiers/comments (ASCII).
# ----------------------------------------------------------------------------
class_name MapColorUtil
extends RefCounted

# The entity arrays in a scenario/map dict that carry an `owner` index.
const OWNER_ARRAYS: Array = ["players", "buildings", "units"]


# Collect the SET of owner indices actually used by a scenario/map dictionary,
# returned as a sorted Array of ints in the valid palette range [0, 15].
#
# Sources scanned:
#   - players[].owner, buildings[].owner, units[].owner
#   - flags[].team (flags store their team under "team", not "owner")
# Out-of-range / non-int owners are clamped into range (mirrors the editor,
# which clamps the active owner) so a slightly malformed map never yields a
# colour index the palette cannot draw.
static func used_owners(scenario: Dictionary) -> Array:
	var seen: Dictionary = {}
	for key in OWNER_ARRAYS:
		var arr: Variant = scenario.get(key, [])
		if arr is Array:
			for entry in arr:
				if entry is Dictionary and (entry as Dictionary).has("owner"):
					var owner: int = MapPaletteUtil.clamp_slot(int((entry as Dictionary)["owner"]))
					seen[owner] = true
	# Flags carry a team id under "team".
	var flags: Variant = scenario.get("flags", [])
	if flags is Array:
		for f in flags:
			if f is Dictionary and (f as Dictionary).has("team"):
				var team: int = MapPaletteUtil.clamp_slot(int((f as Dictionary)["team"]))
				seen[team] = true
	var owners: Array = seen.keys()
	owners.sort()
	return owners


# How many distinct owner colours the map uses (== the number of team slots
# Match Setup should offer for this map).
static func team_count(scenario: Dictionary) -> int:
	return used_owners(scenario).size()


# The hex "RRGGBB" palette colour for each used owner, in the same sorted order
# as used_owners, so a UI can build one swatch per team. Pure.
static func used_color_hexes(scenario: Dictionary) -> Array:
	var hexes: Array = []
	for owner in used_owners(scenario):
		hexes.append(MapPaletteUtil.color_hex(int(owner)))
	return hexes


# True when owner colour `owner` is used somewhere on the map.
static func is_owner_used(scenario: Dictionary, owner: int) -> bool:
	return used_owners(scenario).has(MapPaletteUtil.clamp_slot(owner))


# The subset of `requested` owner ids that are actually valid team choices for
# this map (i.e. present in used_owners), preserving sorted order and dropping
# duplicates / unused colours. Match Setup uses this to reject a stale team
# selection when the player switches to a map that lacks that colour.
static func restrict_choices(scenario: Dictionary, requested: Array) -> Array:
	var used: Array = used_owners(scenario)
	var out: Array = []
	for owner in used:
		if requested.has(owner) and not out.has(owner):
			out.append(owner)
	return out


# --- MC9.3 (request 10): rebel / faction detection --------------------------
# The type name that marks a "headquarters" building. A colour with at least one
# HQ is a "main" faction (can build/expand); a colour that has units but NO HQ
# is a "rebel" faction (units only, no base). This lets a team exist purely as
# loose units, independent of HQ placement.
const HQ_TYPE: String = "hq"


# The set of owner colours that own at least one HQ building. Sorted, in range.
static func owners_with_hq(scenario: Dictionary) -> Array:
	var seen: Dictionary = {}
	var buildings: Variant = scenario.get("buildings", [])
	if buildings is Array:
		for b in buildings:
			if b is Dictionary and str((b as Dictionary).get("type", HQ_TYPE)) == HQ_TYPE:
				seen[MapPaletteUtil.clamp_slot(int((b as Dictionary).get("owner", 0)))] = true
	var owners: Array = seen.keys()
	owners.sort()
	return owners


# The set of owner colours that are used on the map but own NO HQ = rebel
# factions (units only). Sorted, in range.
static func rebel_owners(scenario: Dictionary) -> Array:
	var with_hq: Array = owners_with_hq(scenario)
	var out: Array = []
	for owner in used_owners(scenario):
		if not with_hq.has(owner):
			out.append(owner)
	return out


# True when owner `owner` is a rebel faction on this map (used, but no HQ).
static func is_rebel(scenario: Dictionary, owner: int) -> bool:
	return rebel_owners(scenario).has(MapPaletteUtil.clamp_slot(owner))
