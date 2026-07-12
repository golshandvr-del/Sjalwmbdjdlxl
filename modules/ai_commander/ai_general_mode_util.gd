# ai_general_mode_util.gd
# ----------------------------------------------------------------------------
# Project Nexus - AI general mode (main vs rebel) helper (Phase MC9, step 9.4,
# request 10).
#
# Request 10 introduces a "rebel" faction that owns units but NO base. The
# strategic AI must adapt: a "main" AI builds/expands/upgrades a base, while a
# "rebel" AI has NO buildings, so its economy/expansion/HQ-upgrade planners are
# meaningless and are DISABLED -- it focuses purely on manoeuvre and attack.
#
# This pure, dependency-free helper answers "given this AI's mode, which
# strategic planners should run?" so the decision is unit-testable headlessly
# and the module (strategic_ai_module) stays a thin dispatcher.
#
# DETERMINISM: mode is derived from map data (MapColorUtil.is_rebel) or an
# explicit assignment; the gating here is a pure function of the mode string.
# Nothing touches WorldState directly or uses randomness.
#
# CODE LANGUAGE POLICY: English-only identifiers/comments (ASCII).
# ----------------------------------------------------------------------------
class_name AiGeneralModeUtil
extends RefCounted

# The two general modes an AI commander can operate under.
const MODE_MAIN: String = "main"     # base builder: full economy/tech/expansion
const MODE_REBEL: String = "rebel"   # units only: no base, manoeuvre + attack


# Normalise an arbitrary mode string to one of the known modes; unknown values
# default to MODE_MAIN (the safe, full-featured behaviour).
static func normalise(mode: String) -> String:
	return MODE_REBEL if mode == MODE_REBEL else MODE_MAIN


# Derive the mode for an owner from map data: a rebel colour (units, no HQ) is
# MODE_REBEL, otherwise MODE_MAIN. Deterministic (mirrors MapColorUtil).
static func mode_for_owner(scenario: Dictionary, owner: int) -> String:
	return MODE_REBEL if MapColorUtil.is_rebel(scenario, owner) else MODE_MAIN


# Whether the ECONOMY/expansion planner should run for this mode. Rebels have no
# base to expand, so it is disabled.
static func plans_economy(mode: String) -> bool:
	return normalise(mode) == MODE_MAIN


# Whether the RESEARCH/tech planner should run. Rebels have no tech buildings.
static func plans_research(mode: String) -> bool:
	return normalise(mode) == MODE_MAIN


# Whether the HQ-UPGRADE planner should run. Rebels have no HQ.
static func plans_hq_upgrade(mode: String) -> bool:
	return normalise(mode) == MODE_MAIN


# Whether the ARMY/attack posture planner should run. BOTH modes manoeuvre and
# attack, so this is always true -- a rebel simply does ONLY this.
static func plans_army(_mode: String) -> bool:
	return true


# Convenience: the full set of enabled planners for a mode, as a Dictionary of
# flags. Lets the module iterate/gate uniformly and a test assert the whole
# gate at once.
static func planner_flags(mode: String) -> Dictionary:
	var m: String = normalise(mode)
	return {
		"economy": plans_economy(m),
		"research": plans_research(m),
		"hq_upgrade": plans_hq_upgrade(m),
		"army": plans_army(m),
	}
