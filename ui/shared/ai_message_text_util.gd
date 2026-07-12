# ai_message_text_util.gd
# ----------------------------------------------------------------------------
# Project Nexus - AI diplomatic message text generation (Phase MC11.5,
# request 11).
#
# When an AI proposes / accepts / rejects a treaty or declares war, it must emit
# a human-readable line for the Messages panel. Rather than hard-coding English
# strings (which would break the CODE LANGUAGE POLICY and i18n), this pure
# helper maps a diplomatic act onto a LOCALISATION KEY plus a small argument
# Dictionary; the UI layer feeds the key + args through Localization to produce
# the final display text. This keeps all AI "voice" data-driven and translatable.
#
# Logic/Render Separation: nothing here touches WorldState, Localization or the
# scene tree; it returns a plain {"key", "args"} descriptor.
# Determinism: the chosen key depends only on the act + treaty type, never on
# unseeded randomness, so a replay reproduces the same transcript.
#
# CODE LANGUAGE POLICY: English-only identifiers/comments; the produced KEY is
# resolved to localized text by the caller.
# ----------------------------------------------------------------------------
class_name AiMessageTextUtil
extends RefCounted


# Diplomatic acts an AI can announce.
const ACT_PROPOSE: String = "propose"
const ACT_ACCEPT: String = "accept"
const ACT_REJECT: String = "reject"
const ACT_DECLARE_WAR: String = "declare_war"
const ACT_BREAK: String = "break_treaty"

const ACTS: Array = [ACT_PROPOSE, ACT_ACCEPT, ACT_REJECT, ACT_DECLARE_WAR, ACT_BREAK]


# The localisation key prefix for AI message templates.
const KEY_PREFIX: String = "ai.msg."


# True when `act` is a known diplomatic act.
static func is_valid_act(act: String) -> bool:
	return ACTS.has(act)


# The localisation key for a given act. Falls back to a generic key so an
# unknown act still resolves to something rather than an empty string.
static func message_key(act: String) -> String:
	if not is_valid_act(act):
		return KEY_PREFIX + "generic"
	return KEY_PREFIX + act


# Build a display descriptor {"key": <loc key>, "args": {...}} for an AI message
# about `treaty_type` from `sender` to `recipient`. The caller resolves the key
# through Localization with the args substituted. `treaty_type` is echoed as an
# arg so a template like "I propose {treaty}" can name the treaty.
static func describe(act: String, sender: int, recipient: int, treaty_type: String) -> Dictionary:
	return {
		"key": message_key(act),
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
	for act in ACTS:
		out.append(KEY_PREFIX + act)
	out.append(KEY_PREFIX + "generic")
	return out
