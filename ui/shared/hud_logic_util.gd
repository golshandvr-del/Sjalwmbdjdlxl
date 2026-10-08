# hud_logic_util.gd
# ----------------------------------------------------------------------------
# Project Nexus - Shared, headless HUD decision logic (T004, KI-7).
#
# The mobile HUD (ui/mobile/game_hud.gd) and the desktop HUD
# (ui/desktop/desktop_hud.gd) used to carry byte-identical copies of these
# decisions. They now both delegate here. Every function is static, pure and
# deterministic (sorted keys, no SceneTree, no Nexus singleton access): callers
# pass in the data they already hold, so the logic is unit-tested headlessly.
#
# Presentation (Localization lookups, node updates) stays in the HUDs.
# ----------------------------------------------------------------------------
class_name HudLogicUtil
extends RefCounted

# Simulation speed steps cycled by the Speed button: 1x -> 2x -> 4x -> 1x.
const MAX_TIME_SCALE: float = 4.0


# Id of the first building (lowest key) owned by `owner`, or -1.
# `buildings_list` is WorldState section "buildings" -> "list".
static func find_local_hq(buildings_list: Dictionary, owner: int) -> int:
	var keys: Array = buildings_list.keys()
	keys.sort()
	for key in keys:
		var b: Dictionary = buildings_list[key]
		if int(b.get("owner", -1)) == owner:
			return int(b.get("id", -1))
	return -1


# First tech node (trees by sorted id, nodes in file order) that `tech` reports
# as researchable for `owner` (research_blocked_reason == ""), or "".
# `tech_catalog` is DataLoader catalog "tech"; `tech` is the tech_tree module.
static func next_research_node(tech_catalog: Dictionary, tech: Object, owner: int) -> String:
	if tech == null:
		return ""
	var tree_ids: Array = tech_catalog.keys()
	tree_ids.sort()
	for tree_id in tree_ids:
		var tree: Dictionary = tech_catalog[tree_id]
		for node in tree.get("nodes", []):
			var node_id: String = str(node.get("id", ""))
			if node_id != "" and tech.research_blocked_reason(owner, node_id) == "":
				return node_id
	return ""


# Sorted owners of units in `units_list` for which `is_controlled.call(owner)`
# is true. Falls back to [fallback_owner] when none qualifies but the fallback
# itself is controlled. `units_list` is WorldState "units" -> "list".
static func locally_controlled_owners(units_list: Dictionary, fallback_owner: int, is_controlled: Callable) -> Array:
	var owners: Array = []
	for key in units_list.keys():
		var owner: int = int((units_list[key] as Dictionary).get("owner", -1))
		if owner >= 0 and not owners.has(owner) and bool(is_controlled.call(owner)):
			owners.append(owner)
	if owners.is_empty() and bool(is_controlled.call(fallback_owner)):
		owners.append(fallback_owner)
	owners.sort()
	return owners


# Number of owner slots to offer in message/treaty pickers: highest team key
# (or local_player) + 1, never less than 2. `teams` is WorldState "match" -> "teams".
static func owner_count(teams: Dictionary, local_player: int) -> int:
	var maxo: int = local_player
	for k in teams.keys():
		maxo = max(maxo, int(str(k)))
	return max(2, maxo + 1)


# Next simulation speed for the Speed button.
static func next_time_scale(current: float) -> float:
	if current >= MAX_TIME_SCALE:
		return 1.0
	return current * 2.0


# Localization key of a render-style label (the HUD translates it).
static func style_label_key(style_id: String) -> String:
	match style_id:
		RenderAdapter.STYLE_DETAILED:
			return "ui.game.style_detailed"
		RenderAdapter.STYLE_SPRITE:
			return "ui.game.style_sprite"
		_:
			return "ui.game.style_simple"


# --- T004 WP2: match result, chat history, mission proposal ------------------

# Localization key of the end-of-match banner for `local_player`.
static func match_result_key(winner: int, local_player: int) -> String:
	if winner == local_player:
		return "ui.game.victory"
	if winner < 0:
		return "ui.game.draw"
	return "ui.game.defeat"


# Messages to show in the chat history: everything visible to `viewer` when
# `recipient` is BROADCAST, otherwise the viewer<->recipient conversation.
static func chat_history_entries(log: Array, viewer: int, recipient: int) -> Array:
	if recipient == MessageLogUtil.BROADCAST:
		return MessageLogUtil.filter_for_owner(log, viewer)
	return MessageLogUtil.conversation(log, viewer, recipient)


# Build the mission + carrying treaty for a strategic request. Returns
# { "mission": Dictionary, "treaty": Dictionary } or {} when invalid
# (target == sender, bad type, invalid mission or treaty).
static func build_mission_proposal(sender: int, target: int, mission_type: String,
		cell_x: int, cell_y: int, commitment: int, tick: int) -> Dictionary:
	if target == sender:
		return {}
	var mission: Dictionary = MissionRequestUtil.make_mission(
		sender, target, mission_type, cell_x, cell_y, commitment)
	if not MissionRequestUtil.is_valid(mission):
		return {}
	var treaty_type: String = TreatyUtil.REQUEST_DEFENSE if mission_type == MissionRequestUtil.DEFEND else TreatyUtil.REQUEST_ATTACK
	var treaty: Dictionary = TreatyUtil.make_treaty(
		treaty_type, sender, target, { "mission": mission }, {}, 0, tick)
	if not TreatyUtil.is_valid(treaty):
		return {}
	return { "mission": mission, "treaty": treaty }


# --- T005 WP1: treaty proposal + owner pickers -------------------------------

# Build a plain treaty proposal (no mission payload). Returns the treaty, or {}
# when invalid (self-target or TreatyUtil.is_valid() false).
static func build_treaty_proposal(type_id: String, sender: int, target: int,
		duration: int, tick: int) -> Dictionary:
	if target == sender:
		return {}
	var treaty: Dictionary = TreatyUtil.make_treaty(
		type_id, sender, target, {}, {}, duration, tick)
	if not TreatyUtil.is_valid(treaty):
		return {}
	return treaty


# Owner ids for treaty/mission target pickers: 0..owner_count-1 except `local_player`.
static func target_owner_choices(owner_count: int, local_player: int) -> Array:
	var out: Array = []
	for o in range(owner_count):
		if o != local_player:
			out.append(o)
	return out
