# edit_history_util.gd
# ----------------------------------------------------------------------------
# Project Nexus - Undo/Redo History (Phase MC5, request 6).
#
# A PURE, dependency-free undo/redo stack over opaque project SNAPSHOTS. It owns
# no editor state and touches neither the SceneTree nor WorldState: the caller
# (map editor / mod editor) hands it a plain snapshot (a Dictionary produced by
# ScenarioProject.to_scenario() / ModProject serialisation) after every edit, and
# this util keeps a bounded history so the user can step back and forward.
#
# Model (classic linear history):
#   - `push(snapshot)` records a new state. Anything that had been undone (the
#     "redo tail") is discarded, because a fresh edit forks a new future.
#   - `undo()` moves the cursor back one step and returns that older snapshot,
#     or an empty result if there is nothing to undo.
#   - `redo()` moves the cursor forward one step (only possible right after an
#     undo, before any new push).
#   - The history is capped at `max_depth`; the oldest entries are dropped when
#     it overflows so a long editing session cannot grow memory without bound.
#
# Determinism: not simulation-related at all (pure tooling). Snapshots are
# deep-duplicated on the way in AND out so the caller can never accidentally
# mutate a stored history entry (or have a stored entry mutated under it).
#
# CODE LANGUAGE POLICY: English-only identifiers/comments.
# ----------------------------------------------------------------------------
class_name EditHistoryUtil
extends RefCounted

# Default maximum number of snapshots retained (current + past). Generous enough
# for a real editing session, bounded enough to keep memory sane.
const DEFAULT_MAX_DEPTH: int = 100

# The ordered list of snapshots. Index 0 is the oldest; `_cursor` points at the
# CURRENT state. Entries after the cursor are the "redo tail".
var _stack: Array = []
var _cursor: int = -1
var _max_depth: int = DEFAULT_MAX_DEPTH


func _init(max_depth: int = DEFAULT_MAX_DEPTH) -> void:
	_max_depth = max(1, max_depth)


# Record a new state. Drops any redo tail (a new edit forks the future) and
# enforces the depth cap by discarding the oldest entries. `snapshot` is
# deep-duplicated so the stored copy is independent of the caller's object.
func push(snapshot: Variant) -> void:
	# Discard everything after the cursor (the redo tail).
	if _cursor < _stack.size() - 1:
		_stack.resize(_cursor + 1)
	_stack.append(_deep_copy(snapshot))
	_cursor = _stack.size() - 1
	# Enforce the depth cap by trimming from the front (oldest first).
	if _stack.size() > _max_depth:
		var overflow: int = _stack.size() - _max_depth
		_stack = _stack.slice(overflow)
		_cursor -= overflow
		if _cursor < 0:
			_cursor = 0


# True when there is a previous state to return to.
func can_undo() -> bool:
	return _cursor > 0


# True when a previously-undone state can be re-applied.
func can_redo() -> bool:
	return _cursor >= 0 and _cursor < _stack.size() - 1


# Step back one state and return a fresh copy of it. Returns null when there is
# nothing to undo (the caller should check can_undo() or handle null).
func undo() -> Variant:
	if not can_undo():
		return null
	_cursor -= 1
	return _deep_copy(_stack[_cursor])


# Step forward one state (only meaningful right after an undo) and return a copy.
# Returns null when there is nothing to redo.
func redo() -> Variant:
	if not can_redo():
		return null
	_cursor += 1
	return _deep_copy(_stack[_cursor])


# A fresh copy of the current state, or null if the history is empty.
func current() -> Variant:
	if _cursor < 0 or _cursor >= _stack.size():
		return null
	return _deep_copy(_stack[_cursor])


# Number of stored snapshots (current + past + any redo tail).
func size() -> int:
	return _stack.size()


# Position of the cursor within the history (0-based), or -1 when empty.
func cursor() -> int:
	return _cursor


# Discard the entire history.
func clear() -> void:
	_stack.clear()
	_cursor = -1


# Deep-duplicate a snapshot so history entries are fully isolated. Dictionaries
# and Arrays duplicate recursively; scalars pass through unchanged.
func _deep_copy(value: Variant) -> Variant:
	if value is Dictionary:
		return (value as Dictionary).duplicate(true)
	if value is Array:
		return (value as Array).duplicate(true)
	return value
