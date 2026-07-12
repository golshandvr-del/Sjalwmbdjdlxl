# ai_diplomacy_planner.gd
# ----------------------------------------------------------------------------
# Project Nexus - AI diplomacy planning glue (Phase MC13, step 13.5,
# requests 14/15).
#
# This is the PURE layer that ties the diplomacy pieces together for one
# planning pass. It does NOT touch the world state or the engine; the diplomacy
# module (the impure caller) gathers a plain "situation" dictionary, hands it
# here, and receives back an ordered list of deterministic diplomacy commands to
# enqueue. Keeping this pure is what lets the integration be unit-tested and
# stay lockstep-safe.
#
# The pipeline for each (self, other) pair an AI considers:
#   1. Build a brain context from the situation summary.
#   2. AiDiplomacyBrain.decide(...) -> a clean best-effort action + score.
#   3. AiDifficultyUtil.apply(...) -> perturb the score / inject a seeded
#      unforced error based on the AI's difficulty profile.
#   4. Emit a command (propose_treaty / respond_treaty / declare_war /
#      break_treaty) when the (post-difficulty) action warrants it.
#
# DESIGN RULES (project constitution):
#   * PURE + DETERMINISTIC: a function of its inputs only. Same situation +
#     seed + tick -> identical command list on every peer.
#   * The reaction cadence (who acts this tick) is decided by
#     AiDifficultyUtil.should_react so different AIs are phase-shifted and slow
#     AIs act less often -- all deterministically.
#   * English-only identifiers/comments (CODE_POLICY, pure ASCII).
# ----------------------------------------------------------------------------
class_name AiDiplomacyPlanner
extends RefCounted

# Command tokens mirror DiplomacyModule's CMD_* so the caller can map 1:1.
const CMD_PROPOSE: String = "propose_treaty"
const CMD_RESPOND: String = "respond_treaty"
const CMD_DECLARE_WAR: String = "declare_war"
const CMD_BREAK_TREATY: String = "break_treaty"

# Map a brain action -> the treaty type it proposes (when it is a proposal).
const ACTION_TREATY_TYPE: Dictionary = {
	"propose_peace": "ceasefire",
	"propose_alliance": "alliance_temp",
}


# Plan diplomacy commands for a single tick.
#
# `situation` shape (all plain, engine-free):
#   {
#     "match_seed": int,
#     "tick": int,
#     "actors": [               # the AI owners that may act this tick
#       {
#         "owner": int,
#         "profile": <AiProfile-like or null>,
#         "targets": [          # each other player this actor evaluates
#           {
#             "owner": int,
#             "relationship": String,
#             "trust": float,       # 0..100
#             "reputation": float,  # -1..1
#             "my_strength": float,
#             "their_strength": float,
#             "threat": float,      # 0..1
#             "shared_enemy": bool,
#             "current_allies": int,
#             "at_war_count": int,
#             "incoming_offer": "",       # treaty type awaiting our response
#             "incoming_treaty_id": int,  # id to respond to (-1 if none)
#           }, ...
#         ],
#       }, ...
#     ],
#   }
#
# Returns an ordered Array of command dictionaries:
#   { "cmd": <CMD_*>, "issuer": int, ... action-specific fields }
static func plan(situation: Dictionary) -> Array:
	var commands: Array = []
	var match_seed: int = int(situation.get("match_seed", 0))
	var tick: int = int(situation.get("tick", 0))
	var actors: Array = situation.get("actors", [])
	# Iterate actors in a stable order (by owner) so the command list is
	# deterministic regardless of dictionary ordering.
	var sorted_actors: Array = actors.duplicate()
	sorted_actors.sort_custom(func(a, b): return int(a.get("owner", 0)) < int(b.get("owner", 0)))
	for actor in sorted_actors:
		var owner: int = int(actor.get("owner", 0))
		var profile = actor.get("profile", null)
		# Cadence gate: only some AIs act on a given tick (slow ones less often).
		if not AiDifficultyUtil.should_react(profile, tick, owner):
			continue
		var targets: Array = actor.get("targets", [])
		var sorted_targets: Array = targets.duplicate()
		sorted_targets.sort_custom(func(a, b): return int(a.get("owner", 0)) < int(b.get("owner", 0)))
		for target in sorted_targets:
			var cmd: Dictionary = _plan_one(owner, profile, target, match_seed, tick)
			if not cmd.is_empty():
				commands.append(cmd)
	return commands


# Evaluate ONE (self -> other) relationship and return a single command (or {}).
static func _plan_one(owner: int, profile, target: Dictionary, match_seed: int, tick: int) -> Dictionary:
	var other: int = int(target.get("owner", 0))
	if other == owner:
		return {}
	var context: Dictionary = {
		"profile": profile,
		"relationship": str(target.get("relationship", "neutral")),
		"trust": float(target.get("trust", 50.0)),
		"reputation": float(target.get("reputation", 0.0)),
		"my_strength": float(target.get("my_strength", 1.0)),
		"their_strength": float(target.get("their_strength", 1.0)),
		"threat": float(target.get("threat", 0.0)),
		"shared_enemy": bool(target.get("shared_enemy", false)),
		"current_allies": int(target.get("current_allies", 0)),
		"at_war_count": int(target.get("at_war_count", 0)),
		"incoming_offer": str(target.get("incoming_offer", "")),
	}
	var clean: Dictionary = AiDiplomacyBrain.decide(context)
	# Difficulty layer: perturb score / possibly commit an unforced error. Salt
	# the tick with the target owner so different pairs error independently.
	var perturbed: Dictionary = AiDifficultyUtil.apply(clean, profile, match_seed, tick, owner * 31 + other)
	var action: String = str(perturbed.get("action", "none"))
	return _action_to_command(action, owner, other, target)


# Translate a (post-difficulty) brain action into a concrete command dict.
static func _action_to_command(action: String, owner: int, other: int, target: Dictionary) -> Dictionary:
	match action:
		"none":
			return {}
		"accept", "reject":
			var tid: int = int(target.get("incoming_treaty_id", -1))
			if tid < 0:
				return {}
			return {
				"cmd": CMD_RESPOND, "issuer": owner,
				"treaty_id": tid, "accept": action == "accept",
			}
		"declare_war":
			return { "cmd": CMD_DECLARE_WAR, "issuer": owner, "target": other }
		"betray":
			# A betrayal is modelled as breaking the alliance treaty then war.
			# The caller resolves the concrete treaty id; we signal intent here.
			return {
				"cmd": CMD_BREAK_TREATY, "issuer": owner, "target": other,
				"betrayal": true,
			}
		"send_aid":
			return {
				"cmd": CMD_PROPOSE, "issuer": owner, "target": other,
				"treaty_type": "trade_resource",
			}
		"propose_peace", "propose_alliance":
			return {
				"cmd": CMD_PROPOSE, "issuer": owner, "target": other,
				"treaty_type": str(ACTION_TREATY_TYPE.get(action, "ceasefire")),
			}
		_:
			return {}
