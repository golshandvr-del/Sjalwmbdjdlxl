# game_bootstrap.gd
# ----------------------------------------------------------------------------
# Project Nexus - Game Bootstrap (Phase 1).
#
# Central place that assembles a playable match: it registers all Phase 1
# gameplay modules with the Nexus in a fixed, deterministic order, loads a
# scenario from data, and starts the simulation. Both the playable scene and
# the integration test use this so they exercise the exact same setup.
#
# Module registration ORDER matters for tick determinism (registration order =
# tick order). The chosen order is:
#   map -> economy -> buildings -> units -> ai_commander -> combat -> victory
# (terrain first, then resources, then structures produce, then units move,
#  then the AI issues its orders, then combat resolves on the resulting
#  positions, and finally victory checks the outcome).
#
# This is a static helper, not a module. It only uses the Nexus public API.
#
# CODE LANGUAGE POLICY: English-only identifiers/comments.
# ----------------------------------------------------------------------------
class_name GameBootstrap
extends RefCounted

const SCENARIO_PATH: String = "res://data/scenarios/skirmish_basic.json"


# Register all gameplay modules (idempotent: skips already-registered ids).
#
# Tick order (registration order) for Phase 2 + 3:
#   difficulty -> map -> economy -> logistics -> buildings -> tech_tree ->
#   units -> hero_fusion -> strategic_ai -> ai_commander -> combat ->
#   fog_of_war -> victory
# (difficulty configures knobs first; logistics ships supply after economy
#  produces; tech upgrades resolve before units spawn; the strategic AI plans
#  macro posture, then the tactical AiCommander issues per-unit orders; fog
#  recomputes after all positions are final this tick; victory checks last.)
static func register_modules(nexus: Object) -> void:
	if nexus.get_module("difficulty") == null:
		nexus.register_module(DifficultyModule.new())
	if nexus.get_module("map") == null:
		nexus.register_module(MapModule.new())
	if nexus.get_module("economy") == null:
		nexus.register_module(EconomyModule.new())
	if nexus.get_module("logistics") == null:
		nexus.register_module(LogisticsModule.new())
	if nexus.get_module("buildings") == null:
		nexus.register_module(BuildingsModule.new())
	if nexus.get_module("tech_tree") == null:
		nexus.register_module(TechTreeModule.new())
	if nexus.get_module("units") == null:
		nexus.register_module(UnitsModule.new())
	if nexus.get_module("hero_fusion") == null:
		nexus.register_module(HeroFusionModule.new())
	# Phase 3: the strategic (macro) brain plans BEFORE the tactical commander
	# (micro) acts, so high-level posture/expansion/research decisions are made
	# first and the AiCommander then fills in the per-unit busywork.
	if nexus.get_module("strategic_ai") == null:
		nexus.register_module(StrategicAiModule.new())
	if nexus.get_module("ai_commander") == null:
		nexus.register_module(AiCommanderModule.new())
	# MC10: dynamic diplomacy runs BEFORE combat so any alliance change this tick
	# is mapped onto match.teams before CombatModule._is_hostile reads it (so
	# freshly-allied owners stop firing on each other the same tick - request 17).
	if nexus.get_module("diplomacy") == null:
		nexus.register_module(DiplomacyModule.new())
	if nexus.get_module("combat") == null:
		nexus.register_module(CombatModule.new())
	if nexus.get_module("fog_of_war") == null:
		nexus.register_module(FogOfWarModule.new())
	if nexus.get_module("victory") == null:
		nexus.register_module(VictoryModule.new())
	# Phase 3: the lockstep multiplayer module. It is INERT in single-player
	# (active == false) and only does real work once start_session() is called,
	# so registering it always is safe and keeps the module set uniform between
	# single-player and networked matches.
	if nexus.get_module("multiplayer") == null:
		nexus.register_module(LockstepModule.new())


# Load the catalogs that the modules need (units + buildings + tech + difficulty),
# then layer any installed mods on top (Phase 3.3). Mods can add new entries or
# override base ones; later mods win, in a deterministic load order.
static func load_catalogs(nexus: Object) -> void:
	nexus.data_loader.load_catalog("units", "res://data/units")
	nexus.data_loader.load_catalog("buildings", "res://data/buildings")
	nexus.data_loader.load_catalog("tech", "res://data/tech")
	nexus.data_loader.load_catalog("difficulty", "res://data/difficulty_presets")
	# Phase E (E.7): load the base scenarios into a catalog too, so the main menu
	# can list both shipped scenarios AND any authored ones a mod/.nexpack adds
	# (Custom Games). This is data-only; the deterministic core is untouched.
	nexus.data_loader.load_catalog("scenarios", "res://data/scenarios")
	# MD1.5 (plan v4): load the data-driven Stat catalog so every stat is a data
	# asset (metadata + affects) rather than a hard-coded constant. The built-in
	# Core Stats remain the backward-compatible fallback; these definitions merge
	# on top. Loaded BEFORE mods so a mod's Free Stats can still override/extend.
	nexus.data_loader.load_catalog("stats", "res://data/stats")
	StatRegistry.reset_definitions()
	StatRegistry.load_definitions(nexus.data_loader.get_catalog("stats"))
	# Apply mods AFTER the base catalogs so mod entries override base ones.
	load_mods(nexus)
	# Re-merge any Stat definitions a mod contributed on top of the base catalog.
	StatRegistry.load_definitions(nexus.data_loader.get_catalog("stats"))


# Discover + apply every enabled mod under mods/ onto the catalogs, then layer
# any portable `.nexpack` packages found in the configurable content root on top
# (Phase C, step C.5). Returns the loader info ({ loaded: [ids], entries_merged:
# int }). Safe to call with no mods/packs present (returns empty result). Kept
# separate so tests can opt out.
static func load_mods(nexus: Object) -> Dictionary:
	var info: Dictionary = ModLoader.load_all(nexus.data_loader, "res://mods")
	var loaded: Array = info.get("loaded", [])
	var merged: int = int(info.get("entries_merged", 0))
	# Layer installed .nexpack packages from the content root after folder mods,
	# so a shipped package can override base/folder entries (last-writer-wins).
	var pack_info: Dictionary = load_packs(nexus)
	loaded.append_array(pack_info.get("loaded", []))
	merged += int(pack_info.get("entries_merged", 0))
	# Stash the result in world state so the UI/debug console can show it.
	nexus.world_state.get_section("mods")["loaded"] = loaded
	return { "loaded": loaded, "entries_merged": merged }


# Discover + apply every `.nexpack` package in the player's configurable content
# root (Phase C). The root comes from persisted GameSettings (defaulting to
# `user://content`). Textures shipped inside a pack are registered with the
# Nexus texture service when one is available. Safe (and a no-op) when the
# content folder is empty or absent.
static func load_packs(nexus: Object) -> Dictionary:
	var settings: GameSettings = GameSettings.new(nexus.world_state)
	settings.load_from_file()
	var storage: StorageService = StorageService.new(settings.get_content_path())
	storage.ensure_content_root()
	var tex_service: Object = nexus.get("texture_service") if nexus.has_method("get") else null
	return ModLoader.load_packs(nexus.data_loader, storage, tex_service)


# Full setup for a skirmish on the global Nexus autoload. If a scenario id has
# been selected (Custom Games / Map Editor play-test, Phase E), that scenario is
# loaded from the catalog; otherwise the default shipped skirmish is used. The
# one-shot selection is consumed so a later plain "Play" returns to the default.
static func setup_skirmish() -> void:
	var nexus: Object = Engine.get_main_loop().root.get_node("Nexus")
	register_modules(nexus)
	load_catalogs(nexus)
	var editor_section: Dictionary = nexus.world_state.get_section("editor")
	# P2.3: the Match Setup screen writes the player's chosen scenario + default
	# AI difficulty into a UI-only `match_config` section. It takes priority over
	# nothing (a Map-Editor play-test still wins) but is preferred over the
	# hard-coded default scenario. Both one-shot selections are consumed so a
	# later plain "Play" falls back to the shipped default.
	var match_config: Dictionary = nexus.world_state.get_section("match_config")
	var chosen: String = str(editor_section.get("playtest_scenario", ""))
	var config_scenario: String = str(match_config.get("scenario_id", ""))
	var loaded: bool = false
	if chosen != "":
		# A Map-Editor play-test always uses its authored scenario verbatim.
		loaded = ScenarioLoader.load_scenario_from_catalog(nexus, chosen)
		editor_section.erase("playtest_scenario")  # consume the one-shot selection
	elif config_scenario != "":
		# P7: the Match Setup screen may request a different player count / game
		# mode / team layout than the base scenario ships. Fetch the base entry,
		# reshape its player set + mode to match the request (deterministic,
		# auto-placed by the ScenarioLoader), and apply the result.
		var base_entry: Variant = nexus.data_loader.get_entry("scenarios", config_scenario)
		if base_entry is Dictionary:
			var shaped: Dictionary = _apply_match_config_to_scenario(base_entry as Dictionary, match_config)
			ScenarioLoader.apply_scenario(nexus, shaped)
			loaded = true
	if not loaded:
		ScenarioLoader.load_scenario(nexus, SCENARIO_PATH)
	# Apply the chosen default AI difficulty (if any) after the scenario loaded,
	# then consume the config so it does not leak into the next match.
	_apply_match_difficulty(nexus, str(match_config.get("difficulty", "")))
	# MA7.4 (B8): before clearing the one-shot match_config, carry the session-
	# level facts the running game may want to surface (hot-seat local MP flag +
	# human count) into a persistent `session_info` section. match_config is a
	# transient setup hand-off; session_info survives for the whole match so a HUD
	# can, e.g., show a "local multiplayer" banner without re-reading setup data.
	carry_session_info(nexus.world_state)
	match_config.clear()
	nexus.start_simulation(nexus.world_state.random_seed)


# MA7.4 (B8): copy the session-level facts from the transient `match_config` into
# the persistent `session_info` section. Extracted as a pure static helper so it
# is unit-testable without the full autoload/scene stack, and so any other entry
# path (tests, tools) can produce the same session_info deterministically.
static func carry_session_info(world_state: Object) -> void:
	var match_config: Dictionary = world_state.get_section("match_config")
	var session_info: Dictionary = world_state.get_section("session_info")
	session_info["hot_seat"] = bool(match_config.get("hot_seat", false))
	session_info["human_players"] = int(match_config.get("human_players", 1))


# P7 (R1.3/R1.4/R1.5/R10.2): reshape a base scenario to honour the Match Setup
# choices. The returned scenario keeps the base map + resources but rebuilds the
# player list to the requested human/AI counts, tags each player with a team
# (assigned per game mode), sets the game mode + team layout, and -- crucially --
# drops the base HQ buildings so the deterministic PlacementPlanner seats every
# player fresh for the new count (R10.1). If the config carries no counts the
# base scenario is returned essentially unchanged.
static func _apply_match_config_to_scenario(base: Dictionary, config: Dictionary) -> Dictionary:
	var scenario: Dictionary = base.duplicate(true)
	var humans: int = int(config.get("human_players", 0))
	var ais: int = int(config.get("ai_players", 0))
	var mode: String = str(config.get("game_mode", scenario.get("game_mode", "ffa")))
	var layout: String = str(config.get("team_layout", scenario.get("team_layout", "clustered")))
	var difficulty: String = str(config.get("difficulty", "normal"))
	scenario["game_mode"] = mode
	scenario["team_layout"] = layout

	# No explicit counts -> just stamp the mode/layout onto the base scenario.
	if humans <= 0 and ais <= 0:
		return scenario

	var total: int = max(2, humans + ais)
	# Default start resources copied from the base's first player (fallback 150).
	var start_res: Dictionary = { "resource_basic": 150 }
	var base_players: Array = scenario.get("players", [])
	if base_players.size() > 0 and (base_players[0] as Dictionary).has("start_resources"):
		start_res = (base_players[0] as Dictionary).get("start_resources", start_res)

	# MB2.2 (bug 5): the single-player Match Setup (and the host lobby) may hand us
	# an explicit owner -> team map so the player can group AIs/humans into custom
	# teams. When an in-range override exists it wins; otherwise we fall back to
	# the deterministic per-mode default. Keys may be ints or their string forms
	# because a WorldState/JSON round-trip stringifies dictionary keys.
	var team_overrides: Dictionary = config.get("team_overrides", {})

	var players: Array = []
	for owner in range(total):
		var is_human: bool = owner < humans
		var team: int = _resolve_team(owner, total, mode, team_overrides)
		var entry: Dictionary = {
			"owner": owner,
			"is_human": is_human,
			"team": team,
			"start_resources": start_res.duplicate(true),
		}
		if not is_human:
			entry["difficulty"] = difficulty
		players.append(entry)
	scenario["players"] = players
	# Force fresh placement for the new player set (R10.1): remove authored HQs
	# and starting units that referenced the old owner ids.
	scenario["buildings"] = []
	scenario["units"] = []
	return scenario


# Team assignment per mode. "team" splits players into two balanced sides;
# "ffa"/"ctf" default to one team per player (each their own side). A CTF match
# still benefits from two teams, so CTF also splits into two.
static func _team_for(owner: int, total: int, mode: String) -> int:
	if mode == "team" or mode == "ctf":
		# Alternate sides so a 4-player team match is 2v2, etc.
		return owner % 2
	return owner  # ffa: own team


# MB2.2 (bug 5): final team for a player, honouring an explicit override map
# (owner -> team) from the setup UI before falling back to _team_for. Overrides
# are clamped to a sane range so a malformed value can never crash placement.
const _MAX_TEAMS: int = 4
static func _resolve_team(owner: int, total: int, mode: String, overrides: Dictionary) -> int:
	if overrides.has(owner):
		return clampi(int(overrides[owner]), 0, _MAX_TEAMS - 1)
	if overrides.has(str(owner)):
		return clampi(int(overrides[str(owner)]), 0, _MAX_TEAMS - 1)
	return _team_for(owner, total, mode)


# P2.3: override the difficulty of every AI player with the value chosen in the
# Match Setup screen. Empty string = keep whatever the scenario declared. The
# AiCommander stores AI players as `controlled: { owner -> difficulty }` in its
# world-state section, so we simply re-assign each already-registered AI player
# to the chosen difficulty via the module's public setter (deterministic).
static func _apply_match_difficulty(nexus: Object, difficulty: String) -> void:
	if difficulty == "":
		return
	var ai: Object = nexus.get_module("ai_commander")
	if ai == null:
		return
	var section: Dictionary = nexus.world_state.get_section("ai_commander")
	var controlled: Dictionary = section.get("controlled", {})
	for owner_key in controlled.keys():
		ai.set_ai_player(int(owner_key), difficulty)


# Setup variant for headless tests: takes an explicit nexus-like object and
# applies a scenario Dictionary directly (no autoload, no real-time clock).
static func setup_for_test(nexus: Object, scenario: Dictionary) -> void:
	register_modules(nexus)
	load_catalogs(nexus)
	ScenarioLoader.apply_scenario(nexus, scenario)
