# ai_brain_action_text_util.gd
# ----------------------------------------------------------------------------
# Project Nexus - AI diplomacy brain -> readable message bridge (Phase MC13.6,
# requests 14/15).
#
# AiDiplomacyBrain (MC13.1) returns fine-grained ACTION tokens
# ("propose_peace", "propose_alliance", "accept", "reject", "declare_war",
# "betray", "send_aid", "none"). MC11.5's AiMessageTextUtil only knows the
# coarse treaty verbs (propose/accept/reject/declare_war/break_treaty), so it
# cannot voice a betrayal or an aid offer. This pure helper maps EACH brain
# action onto its own localisation key ("ai.brain.<action>") plus a small
# argument Dictionary, so the Messages panel can show what the AI just decided
# in the player's language.
#
# DESIGN RULES (project constitution):
#   - PURE + DETERMINISTIC: a plain function of its inputs. NO WorldState, NO
#     Localization, NO SceneTree, NO RNG. Same action -> same descriptor, so a
#     replay reproduces the same transcript.
#   - Returns a {"key", "args"} descriptor; the UI layer resolves the key via
#     Localization. This keeps all AI "voice" data-driven and translatable.
#   - English-only identifiers/comments (CODE_POLICY, pure ASCII).
# ----------------------------------------------------------------------------
class_name AiBrainActionTextUtil
extends RefCounted


# The localisation key prefix for brain-action message templates.
const KEY_PREFIX: String = "ai.brain."

# Brain actions that carry a readable message. "none" is intentionally excluded
# from ACTS because a "do nothing" tick produces no message, but message_key()
# still resolves it (to the generic fallback) so callers never crash.
const ACTS: Array = [
	AiDiplomacyBrain.ACTION_PROPOSE_PEACE,
	AiDiplomacyBrain.ACTION_PROPOSE_ALLIANCE,
	AiDiplomacyBrain.ACTION_ACCEPT,
	AiDiplomacyBrain.ACTION_REJECT,
	AiDiplomacyBrain.ACTION_DECLARE_WAR,
	AiDiplomacyBrain.ACTION_BETRAY,
	AiDiplomacyBrain.ACTION_SEND_AID,
]


# True when `action` has a dedicated readable message (excludes "none").
static func is_message_action(action: String) -> bool:
	return ACTS.has(action)


# The localisation key for a brain action. Unknown actions or "none" fall back
# to a generic key so resolution never yields an empty string.
static func message_key(action: String) -> String:
	if not is_message_action(action):
		return KEY_PREFIX + "generic"
	return KEY_PREFIX + action


# Build a display descriptor {"key": <loc key>, "args": {...}} for a brain
# action taken by `sender` toward `recipient`. `treaty_type` is echoed as an arg
# so a template like "I propose a {treaty}" can name the subject; it may be "".
static func describe(action: String, sender: int, recipient: int, treaty_type: String = "") -> Dictionary:
	return {
		"key": message_key(action),
		"args": {
			"sender": sender,
			"recipient": recipient,
			"treaty": treaty_type,
		},
	}


# All localisation keys this util can ever emit, so the i18n parity test can
# assert every one is present in every locale.
static func all_keys() -> Array:
	var out: Array = []
	for a in ACTS:
		out.append(KEY_PREFIX + a)
	out.append(KEY_PREFIX + "generic")
	return out
