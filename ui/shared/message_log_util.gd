# message_log_util.gd
# ----------------------------------------------------------------------------
# Project Nexus - In-game message / chat log model (Phase MC11.1, request 11).
#
# The in-game "Messages" panel keeps a HISTORY of messages exchanged between
# owners (human or AI): each entry records the sender, the recipient, the text
# and the tick it was sent. This pure, dependency-free helper owns the log
# structure, the append/filter/recipient-selection logic and (de)serialisation
# so the HUD panel and the tests share one source of truth.
#
# A recipient of BROADCAST (-1) means "all players" (an open announcement); any
# non-negative recipient is a private conversation with that owner.
#
# Logic/Render Separation: nothing here touches WorldState or the scene tree; it
# operates on plain message records (Dictionaries) and Arrays.
# Determinism: entries are appended in call order and never reordered; filtering
# preserves insertion order, so every peer/replay renders the same transcript.
#
# CODE LANGUAGE POLICY: English-only identifiers/comments.
# ----------------------------------------------------------------------------
class_name MessageLogUtil
extends RefCounted


# A recipient of BROADCAST means the message went to everyone.
const BROADCAST: int = -1

# Message "channel": plain chat vs a structured strategic/diplomatic message.
const CHANNEL_CHAT: String = "chat"
const CHANNEL_STRATEGIC: String = "strategic"

const CHANNELS: Array = [CHANNEL_CHAT, CHANNEL_STRATEGIC]


# Build one message record. `channel` defaults to plain chat; `meta` is a
# free-form Dictionary the strategic tab uses to stash a treaty/mission payload
# without changing this schema. Text is kept verbatim (callers sanitise).
static func make_message(
		sender: int,
		recipient: int,
		text: String,
		tick: int,
		channel: String = CHANNEL_CHAT,
		meta: Dictionary = {}) -> Dictionary:
	return {
		"sender": sender,
		"recipient": recipient,
		"text": text,
		"tick": max(0, tick),
		"channel": channel if CHANNELS.has(channel) else CHANNEL_CHAT,
		"meta": meta.duplicate(true),
	}


# Append a message to `log` and return the SAME array (mutated in place) so the
# caller can chain. Never reorders existing entries.
static func append_message(log: Array, message: Dictionary) -> Array:
	log.append(message.duplicate(true))
	return log


# True when a message involves `owner` either as sender or recipient (a
# broadcast involves everyone).
static func involves(message: Dictionary, owner: int) -> bool:
	var sender: int = int(message.get("sender", 0))
	var recipient: int = int(message.get("recipient", BROADCAST))
	if recipient == BROADCAST:
		return true
	return sender == owner or recipient == owner


# True when `message` belongs to the private conversation between owners `a` and
# `b` (either direction), OR is a broadcast (broadcasts show in every thread).
static func in_conversation(message: Dictionary, a: int, b: int) -> bool:
	var sender: int = int(message.get("sender", 0))
	var recipient: int = int(message.get("recipient", BROADCAST))
	if recipient == BROADCAST:
		return true
	return (sender == a and recipient == b) or (sender == b and recipient == a)


# Return, in insertion order, every message that involves `owner`.
static func filter_for_owner(log: Array, owner: int) -> Array:
	var out: Array = []
	for m in log:
		if involves(m as Dictionary, owner):
			out.append(m)
	return out


# Return, in insertion order, the transcript of the conversation between `a`
# and `b` (used by the chat tab when a recipient is selected).
static func conversation(log: Array, a: int, b: int) -> Array:
	var out: Array = []
	for m in log:
		if in_conversation(m as Dictionary, a, b):
			out.append(m)
	return out


# Return only messages on a given channel (chat vs strategic), in order.
static func filter_by_channel(log: Array, channel: String) -> Array:
	var out: Array = []
	for m in log:
		if str((m as Dictionary).get("channel", CHANNEL_CHAT)) == channel:
			out.append(m)
	return out


# The distinct set of owners `viewer` can pick as a recipient: every OTHER
# owner in [0, owner_count) plus BROADCAST, returned sorted (BROADCAST first)
# for a deterministic recipient dropdown.
static func recipient_choices(owner_count: int, viewer: int) -> Array:
	var out: Array = [BROADCAST]
	for o in range(max(0, owner_count)):
		if o != viewer:
			out.append(o)
	return out


# The most recent `count` messages involving `owner`, oldest-first (so the panel
# can append them top-to-bottom). count <= 0 returns the full filtered list.
static func recent_for_owner(log: Array, owner: int, count: int) -> Array:
	var filtered: Array = filter_for_owner(log, owner)
	if count <= 0 or filtered.size() <= count:
		return filtered
	return filtered.slice(filtered.size() - count, filtered.size())


# Serialise the whole log to a JSON-safe Array (deep-copied so stored state
# cannot be mutated by reference).
static func to_array(log: Array) -> Array:
	var out: Array = []
	for m in log:
		out.append((m as Dictionary).duplicate(true))
	return out


# Rebuild a log from a stored/JSON Array, normalising each entry through
# make_message so partial/legacy records still load safely.
static func from_array(data: Array) -> Array:
	var out: Array = []
	for raw in data:
		var d: Dictionary = raw as Dictionary
		out.append(make_message(
			int(d.get("sender", 0)),
			int(d.get("recipient", BROADCAST)),
			str(d.get("text", "")),
			int(d.get("tick", 0)),
			str(d.get("channel", CHANNEL_CHAT)),
			(d.get("meta", {}) as Dictionary)))
	return out
