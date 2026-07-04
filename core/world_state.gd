# world_state.gd
# ----------------------------------------------------------------------------
# Project Nexus - World State (core component).
#
# The single source of truth about the entire game. Organized into named
# "sections" (e.g. "units", "economy", "map"). Modules read and write their
# section here so that save/load and deterministic multiplayer are possible.
#
# IMPORTANT: This is plain data. No module logic lives here. Keeping the world
# state serializable (Dictionaries/Arrays/primitives) is what enables
# deterministic save/load and lockstep networking later.
# ----------------------------------------------------------------------------
class_name WorldState
extends RefCounted

# section_name (String) -> Dictionary of that section's data.
var _sections: Dictionary = {}

# The current simulation tick counter (advanced by SimClock).
var current_tick: int = 0

# Shared deterministic random seed (set when a match starts).
var random_seed: int = 0


# Get a section, creating an empty one if it does not exist.
func get_section(section_name: String) -> Dictionary:
	if not _sections.has(section_name):
		_sections[section_name] = {}
	return _sections[section_name]


# Replace an entire section's data.
func set_section(section_name: String, data: Dictionary) -> void:
	_sections[section_name] = data


func has_section(section_name: String) -> bool:
	return _sections.has(section_name)


func get_all_section_names() -> Array:
	return _sections.keys()


# Convenience getters/setters for a single key inside a section.
func get_value(section_name: String, key: String, default_value: Variant = null) -> Variant:
	var section: Dictionary = get_section(section_name)
	return section.get(key, default_value)


func set_value(section_name: String, key: String, value: Variant) -> void:
	var section: Dictionary = get_section(section_name)
	section[key] = value


# Reset the whole world (e.g. when starting a new match).
func clear() -> void:
	_sections.clear()
	current_tick = 0
	random_seed = 0


# Serialize the full world state for saving.
func serialize() -> Dictionary:
	return {
		"current_tick": current_tick,
		"random_seed": random_seed,
		"sections": _sections.duplicate(true),
	}


# Restore the full world state from a saved dictionary.
func deserialize(data: Dictionary) -> void:
	current_tick = int(data.get("current_tick", 0))
	random_seed = int(data.get("random_seed", 0))
	var sections: Variant = data.get("sections", {})
	if sections is Dictionary:
		_sections = (sections as Dictionary).duplicate(true)
	else:
		_sections = {}
