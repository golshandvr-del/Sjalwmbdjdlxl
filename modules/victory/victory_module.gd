# victory_module.gd
# ----------------------------------------------------------------------------
# Project Nexus - Victory / Defeat Module.
#
# Watches the battlefield and decides when the match is over. It is fully
# data-driven over three game modes (Phase P7, R1.5 / P7.5):
#
#   * "ffa"  (free-for-all): every player is their own side. A player is
#     ELIMINATED when they own zero command buildings (HQs). Last player with an
#     HQ wins. (This is the classic Phase-1 rule.)
#
#   * "team": players are grouped by a "team" id. A player is still eliminated
#     when they lose their last HQ, but the MATCH ends when only one team has any
#     living member -- that team wins together. Teammates never "win" against
#     each other.
#
#   * "ctf" (capture the flag): in addition to elimination, a team wins by
#     capturing every flag NOT belonging to it. A flag at cell (x, y) is captured
#     for a team once one of that team's units has stood on the flag cell for
#     `capture_ticks` consecutive-progress ticks (deterministic, tick-driven --
#     never real time). Capturing all rival flags ends the match immediately.
#
# Like every module it depends ONLY on the core: it reads WorldState sections
# ("buildings", "units", "map"), listens for "buildings.destroyed" + the sim
# tick, and announces the result by emitting "match.over". The UI listens to
# that event to show the end screen; the module never touches presentation.
#
# Determinism: evaluation is pure over the current world state (sorted owners /
# sorted teams / sorted flag indices), so it is replay/lockstep safe.
#
# CODE LANGUAGE POLICY: English-only identifiers/comments.
# ----------------------------------------------------------------------------
class_name VictoryModule
extends IModule

const SECTION: String = "match"

const EVENT_BUILDING_DESTROYED: String = "buildings.destroyed"
const EVENT_PLAYER_ELIMINATED: String = "match.player_eliminated"
const EVENT_TEAM_ELIMINATED: String = "match.team_eliminated"
const EVENT_FLAG_CAPTURED: String = "match.flag_captured"
const EVENT_MATCH_OVER: String = "match.over"

# Modes (kept as constants so callers/tests can reference them).
const MODE_FFA: String = "ffa"
const MODE_TEAM: String = "team"
const MODE_CTF: String = "ctf"

# Default consecutive-progress ticks a unit must hold a flag to capture it.
const DEFAULT_CAPTURE_TICKS: int = 30


func module_id() -> String:
	return "victory"


func init(p_nexus: Object) -> void:
	super.init(p_nexus)
	nexus.subscribe(EVENT_BUILDING_DESTROYED, self, "_on_bus_event")
	_ensure_state()


func _ensure_state() -> void:
	var section: Dictionary = nexus.world_state.get_section(SECTION)
	if not section.has("over"):
		section["over"] = false
	if not section.has("winner"):
		section["winner"] = -1          # winning owner (ffa) OR -1
	if not section.has("winning_team"):
		section["winning_team"] = -1     # winning team id (team/ctf) OR -1
	if not section.has("eliminated"):
		section["eliminated"] = []       # Array of owner ints
	if not section.has("mode"):
		section["mode"] = MODE_FFA
	if not section.has("teams"):
		section["teams"] = {}            # owner(str) -> team(int)
	if not section.has("flags"):
		section["flags"] = {}            # index(str) -> { x, y, team, progress, holder_team }
	if not section.has("capture_ticks"):
		section["capture_ticks"] = DEFAULT_CAPTURE_TICKS


# --- Configuration (called by ScenarioLoader / GameBootstrap) ---------------

# Register a player that takes part, so we know who can still lose. `team`
# defaults to the owner id (its own one-player team, i.e. FFA).
func register_player(owner: int, team: int = -1) -> void:
	_ensure_state()
	var section: Dictionary = nexus.world_state.get_section(SECTION)
	var players: Array = section.get("players", [])
	if not players.has(owner):
		players.append(owner)
	section["players"] = players
	var teams: Dictionary = section.get("teams", {})
	teams[str(owner)] = team if team >= 0 else owner
	section["teams"] = teams


# Set the active game mode ("ffa" | "team" | "ctf"). Unknown values fall back to
# FFA so a bad scenario never leaves the match unresolvable.
func set_mode(mode: String) -> void:
	_ensure_state()
	var clean: String = mode.strip_edges().to_lower()
	if clean != MODE_TEAM and clean != MODE_CTF:
		clean = MODE_FFA
	nexus.world_state.get_section(SECTION)["mode"] = clean


# Register a CTF flag owned by `team` at cell (x, y). Ignored unless CTF.
func register_flag(index: int, x: int, y: int, team: int) -> void:
	_ensure_state()
	var section: Dictionary = nexus.world_state.get_section(SECTION)
	var flags: Dictionary = section.get("flags", {})
	flags[str(index)] = {
		"x": int(x), "y": int(y), "team": int(team),
		"progress": 0, "holder_team": int(team),
	}
	section["flags"] = flags


func mode() -> String:
	return str(nexus.world_state.get_section(SECTION).get("mode", MODE_FFA))


func team_of(owner: int) -> int:
	var teams: Dictionary = nexus.world_state.get_section(SECTION).get("teams", {})
	return int(teams.get(str(owner), owner))


# --- Tick (CTF flag capture) ------------------------------------------------

func on_tick(_tick: int) -> void:
	var section: Dictionary = nexus.world_state.get_section(SECTION)
	if bool(section.get("over", false)):
		return
	if str(section.get("mode", MODE_FFA)) == MODE_CTF:
		_advance_flag_capture(section)
	# Elimination is normally event-driven, but a tick re-check is cheap and
	# guarantees a mode change / late registration still resolves.
	_evaluate()


# For each flag, if exactly one team occupies its cell, that team makes capture
# progress; when progress reaches capture_ticks the flag flips to that team.
# Progress resets when the cell is empty or contested (deterministic).
func _advance_flag_capture(section: Dictionary) -> void:
	var flags: Dictionary = section.get("flags", {})
	var capture_ticks: int = int(section.get("capture_ticks", DEFAULT_CAPTURE_TICKS))
	var units: Dictionary = nexus.world_state.get_section("units").get("list", {})
	var indices: Array = flags.keys()
	indices.sort()
	for key in indices:
		var flag: Dictionary = flags[key]
		var occupier_team: int = _sole_team_on_cell(units, int(flag.get("x", 0)), int(flag.get("y", 0)))
		if occupier_team < 0 or occupier_team == int(flag.get("holder_team", -1)):
			flag["progress"] = 0
		else:
			flag["progress"] = int(flag.get("progress", 0)) + 1
			if int(flag["progress"]) >= capture_ticks:
				flag["holder_team"] = occupier_team
				flag["progress"] = 0
				nexus.emit_event(EVENT_FLAG_CAPTURED, {
					"index": int(str(key)), "team": occupier_team,
				})
		flags[key] = flag
	section["flags"] = flags


# The single team standing on (x, y), or -1 if empty or contested by >1 team.
func _sole_team_on_cell(units: Dictionary, x: int, y: int) -> int:
	var seen_team: int = -1
	var unit_keys: Array = units.keys()
	unit_keys.sort()
	for uk in unit_keys:
		var u: Dictionary = units[uk]
		if int(u.get("x", -999)) == x and int(u.get("y", -999)) == y and int(u.get("health", 0)) > 0:
			var t: int = team_of(int(u.get("owner", -1)))
			if seen_team < 0:
				seen_team = t
			elif seen_team != t:
				return -1
	return seen_team


# --- Event handling ---------------------------------------------------------

func _on_bus_event(event_name: String, payload: Dictionary) -> void:
	handle_event(event_name, payload)


func handle_event(event_name: String, _payload: Dictionary) -> void:
	if event_name == EVENT_BUILDING_DESTROYED:
		_evaluate()


# Re-evaluate elimination + victory. Works for all three modes.
func _evaluate() -> void:
	var section: Dictionary = nexus.world_state.get_section(SECTION)
	if bool(section.get("over", false)):
		return

	var players: Array = section.get("players", [])
	if players.size() < 2:
		return
	var eliminated: Array = section.get("eliminated", [])

	# 1) Update elimination (per player), announce newly-eliminated players.
	var sorted_players: Array = players.duplicate()
	sorted_players.sort()
	for owner in sorted_players:
		if not _has_command_building(int(owner)) and not eliminated.has(int(owner)):
			eliminated.append(int(owner))
			nexus.emit_event(EVENT_PLAYER_ELIMINATED, { "owner": int(owner) })
	section["eliminated"] = eliminated

	# 2) Which TEAMS still have a living member?
	var alive_teams: Array = []
	for owner in sorted_players:
		if _has_command_building(int(owner)):
			var t: int = team_of(int(owner))
			if not alive_teams.has(t):
				alive_teams.append(t)
	alive_teams.sort()

	# 3) CTF flag-sweep win: a still-alive team that holds every flag not
	# originally theirs wins immediately.
	if str(section.get("mode", MODE_FFA)) == MODE_CTF:
		var ctf_winner: int = _ctf_winning_team(section, alive_teams)
		if ctf_winner >= 0:
			_finish(section, ctf_winner)
			return

	# 4) Elimination win: only one team left standing.
	if alive_teams.size() == 1:
		_finish(section, int(alive_teams[0]))
	elif alive_teams.size() == 0:
		# Mutual destruction on the same tick -> draw.
		section["over"] = true
		section["winner"] = -1
		section["winning_team"] = -1
		nexus.emit_event(EVENT_MATCH_OVER, { "winner": -1, "team": -1 })


# A team wins CTF if it is alive and now holds every flag whose ORIGINAL team is
# not itself (i.e. it captured all rival flags) -- and there is at least one such
# rival flag. Returns the winning team id or -1.
func _ctf_winning_team(section: Dictionary, alive_teams: Array) -> int:
	var flags: Dictionary = section.get("flags", {})
	if flags.is_empty():
		return -1
	for team in alive_teams:
		var rival_flags: int = 0
		var held_rivals: int = 0
		for key in flags.keys():
			var flag: Dictionary = flags[key]
			if int(flag.get("team", -1)) == int(team):
				continue  # own flag: not a capture target
			rival_flags += 1
			if int(flag.get("holder_team", -1)) == int(team):
				held_rivals += 1
		if rival_flags > 0 and held_rivals == rival_flags:
			return int(team)
	return -1


# Record a team win. In FFA the "winner" owner is the sole surviving player of
# the winning team (there is exactly one); in team/ctf we also report the team.
func _finish(section: Dictionary, winning_team: int) -> void:
	section["over"] = true
	section["winning_team"] = winning_team
	var winner_owner: int = -1
	var players: Array = section.get("players", [])
	var sorted_players: Array = players.duplicate()
	sorted_players.sort()
	for owner in sorted_players:
		if team_of(int(owner)) == winning_team and _has_command_building(int(owner)):
			winner_owner = int(owner)
			break
	section["winner"] = winner_owner
	nexus.emit_event(EVENT_MATCH_OVER, { "winner": winner_owner, "team": winning_team })


# A "command building" keeps a player alive: any owned building with health > 0.
func _has_command_building(owner: int) -> bool:
	var buildings: Dictionary = nexus.world_state.get_section("buildings").get("list", {})
	for key in buildings.keys():
		var b: Dictionary = buildings[key]
		if int(b.get("owner", -1)) == owner and int(b.get("health", 0)) > 0:
			return true
	return false


func is_over() -> bool:
	return bool(nexus.world_state.get_section(SECTION).get("over", false))


func winner() -> int:
	return int(nexus.world_state.get_section(SECTION).get("winner", -1))


func winning_team() -> int:
	return int(nexus.world_state.get_section(SECTION).get("winning_team", -1))


# --- Save / load ------------------------------------------------------------

func serialize() -> Dictionary:
	return {}


func deserialize(_data: Dictionary) -> void:
	pass


func shutdown() -> void:
	if nexus != null:
		nexus.event_bus.unsubscribe_all(self)
