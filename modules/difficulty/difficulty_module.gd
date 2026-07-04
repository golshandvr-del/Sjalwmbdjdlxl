# difficulty_module.gd
# ----------------------------------------------------------------------------
# Project Nexus - Difficulty Module (Phase 2, steps 2.8 + 2.9 + 2.10 + 2.11).
#
# Data-driven difficulty system. Built-in presets (easy/normal/hard) live in
# data/difficulty_presets/*.json. Players may also define CUSTOM presets at
# runtime (step 2.10) which can be saved and reloaded (step 2.11) through the
# SaveSystem-friendly serialize()/deserialize() contract -- custom presets are
# stored in the "difficulty" world-state section so they round-trip with the
# rest of the game.
#
# The module exposes the active preset's knobs to the rest of the game by
# writing them into the "ai" world-state section that the AiCommander reads, so
# difficulty actually changes AI behaviour without the two modules referencing
# each other (decoupled through shared world state).
#
# difficulty section layout:
#   {
#     "active": String,                     # active preset id
#     "custom": { id -> preset_dict },      # user-defined presets (savable)
#   }
#
# CODE LANGUAGE POLICY: English-only identifiers/comments.
# ----------------------------------------------------------------------------
class_name DifficultyModule
extends IModule

const SECTION: String = "difficulty"
const CATALOG: String = "difficulty"

const CMD_SET_DIFFICULTY: String = "command.set_difficulty"
const CMD_DEFINE_CUSTOM: String = "command.define_custom_difficulty"

const EVENT_CHANGED: String = "difficulty.changed"
const EVENT_CUSTOM_DEFINED: String = "difficulty.custom_defined"


func module_id() -> String:
	return "difficulty"


func init(p_nexus: Object) -> void:
	super.init(p_nexus)
	nexus.subscribe(CMD_SET_DIFFICULTY, self, "_on_bus_event")
	nexus.subscribe(CMD_DEFINE_CUSTOM, self, "_on_bus_event")
	_ensure_state()


func _ensure_state() -> void:
	var section: Dictionary = nexus.world_state.get_section(SECTION)
	if not section.has("active"):
		section["active"] = "normal"
	if not section.has("custom"):
		section["custom"] = {}


# --- Public API -------------------------------------------------------------

# Resolve a preset by id, checking custom presets first then the data catalog.
func get_preset(preset_id: String) -> Dictionary:
	var section: Dictionary = nexus.world_state.get_section(SECTION)
	var custom: Dictionary = section.get("custom", {})
	if custom.has(preset_id):
		return custom[preset_id]
	var entry: Variant = nexus.data_loader.get_entry(CATALOG, preset_id)
	if entry is Dictionary:
		return entry
	return {}


func active_preset_id() -> String:
	return str(nexus.world_state.get_section(SECTION).get("active", "normal"))


func active_preset() -> Dictionary:
	return get_preset(active_preset_id())


# Set the active difficulty preset and broadcast the resolved knobs so the AI
# commander (and economy bonuses) can react.
func set_active(preset_id: String) -> bool:
	var preset: Dictionary = get_preset(preset_id)
	if preset.is_empty():
		return false
	var section: Dictionary = nexus.world_state.get_section(SECTION)
	section["active"] = preset_id
	_publish_to_ai(preset)
	nexus.emit_event(EVENT_CHANGED, { "preset": preset_id })
	return true


# Define (or overwrite) a custom preset (step 2.10). The id must be English.
func define_custom(preset_id: String, knobs: Dictionary) -> void:
	var section: Dictionary = nexus.world_state.get_section(SECTION)
	var custom: Dictionary = section.get("custom", {})
	var preset: Dictionary = knobs.duplicate(true)
	preset["id"] = preset_id
	preset["custom"] = true
	custom[preset_id] = preset
	section["custom"] = custom
	nexus.emit_event(EVENT_CUSTOM_DEFINED, { "preset": preset_id })


# Resolve the starting resources for a player under the active preset, applying
# the human/AI multiplier. Used by the scenario loader.
func starting_resources_for(is_human: bool) -> int:
	var preset: Dictionary = active_preset()
	var base: int = int(preset.get("starting_resources", 150))
	var mult: float = 1.0
	if is_human:
		mult = float(preset.get("player_resource_multiplier", 1.0))
	else:
		mult = float(preset.get("ai_resource_multiplier", 1.0))
	return int(round(base * mult))


# Map the active preset to the named AI difficulty bucket the AiCommander uses.
func ai_difficulty_name() -> String:
	var preset: Dictionary = active_preset()
	# A custom preset still carries the three core knobs; choose the closest
	# named bucket so the AiCommander (which keys on names) behaves accordingly.
	var interval: int = int(preset.get("ai_think_interval", 15))
	if interval <= 10:
		return "hard"
	elif interval <= 18:
		return "normal"
	return "easy"


# --- Event handling ---------------------------------------------------------

func _on_bus_event(event_name: String, payload: Dictionary) -> void:
	handle_event(event_name, payload)


func handle_event(event_name: String, payload: Dictionary) -> void:
	match event_name:
		CMD_SET_DIFFICULTY:
			set_active(str(payload.get("data", {}).get("preset", "normal")))
		CMD_DEFINE_CUSTOM:
			var d: Dictionary = payload.get("data", {})
			define_custom(str(d.get("preset", "custom")), d.get("knobs", {}))


# Mirror the active preset's AI knobs into the "ai" section. The AiCommander
# reads named difficulty per controlled player; here we also expose raw knobs
# for any future fine-grained tuning, keeping the modules decoupled.
func _publish_to_ai(preset: Dictionary) -> void:
	var ai_section: Dictionary = nexus.world_state.get_section("ai")
	ai_section["active_knobs"] = {
		"think_interval": int(preset.get("ai_think_interval", 15)),
		"build_chance_pct": int(preset.get("ai_build_chance_pct", 70)),
		"aggression": int(preset.get("ai_aggression", 1)),
		"max_queue": int(preset.get("ai_max_queue", 2)),
	}


# --- Save / load (step 2.11) ------------------------------------------------
#
# Custom presets and the active selection live in the world-state section, so
# the SaveSystem already round-trips them. We additionally expose them here so
# they can be persisted independently of a running match (e.g. a settings file).

func serialize() -> Dictionary:
	var section: Dictionary = nexus.world_state.get_section(SECTION)
	return {
		"active": str(section.get("active", "normal")),
		"custom": (section.get("custom", {}) as Dictionary).duplicate(true),
	}


func deserialize(data: Dictionary) -> void:
	var section: Dictionary = nexus.world_state.get_section(SECTION)
	section["active"] = str(data.get("active", "normal"))
	section["custom"] = (data.get("custom", {}) as Dictionary).duplicate(true)


func shutdown() -> void:
	if nexus != null:
		nexus.event_bus.unsubscribe_all(self)
