# debug_main.gd
# ----------------------------------------------------------------------------
# Project Nexus - Debug Main Scene (Phase 0, step 0.13).
#
# A minimal on-screen console that proves the central brain is alive:
#   - registers the TestModule with the Nexus,
#   - starts the simulation,
#   - displays connected modules, the current tick, and a live event log,
#   - offers buttons to pause/resume (Active Pause), step ticks, and save/load.
#
# This scene is the Phase 0 deliverable: a window showing modules connected to
# the core and exchanging events.
# ----------------------------------------------------------------------------
extends Control

@onready var _title_label: Label = $Margin/Layout/TitleLabel
@onready var _status_label: Label = $Margin/Layout/StatusLabel
@onready var _log_label: RichTextLabel = $Margin/Layout/LogPanel/LogLabel
@onready var _pause_button: Button = $Margin/Layout/Buttons/PauseButton
@onready var _step_button: Button = $Margin/Layout/Buttons/StepButton
@onready var _save_button: Button = $Margin/Layout/Buttons/SaveButton
@onready var _load_button: Button = $Margin/Layout/Buttons/LoadButton

const SAVE_PATH: String = "user://phase0_test_save.json"

var _last_logged_index: int = 0


func _ready() -> void:
	_title_label.text = "Project Nexus - Phase 0 Debug Console"

	# Turn on event logging so we can display the live event stream.
	Nexus.event_bus.set_log_enabled(true)

	# Register the demonstration module and start the simulation.
	var test_module: TestModule = TestModule.new()
	Nexus.register_module(test_module)
	Nexus.start_simulation(12345)

	# Wire up the control buttons.
	_pause_button.pressed.connect(_on_pause_pressed)
	_step_button.pressed.connect(_on_step_pressed)
	_save_button.pressed.connect(_on_save_pressed)
	_load_button.pressed.connect(_on_load_pressed)

	_append_log("[boot] Nexus online. Registered modules: %s" % str(Nexus.module_registry.get_all_ids()))


func _process(_delta: float) -> void:
	_refresh_status()
	_drain_event_log()


func _refresh_status() -> void:
	var paused_text: String = "PAUSED" if Nexus.sim_clock.is_paused() else "RUNNING"
	var test_section: Dictionary = Nexus.world_state.get_section("test")
	_status_label.text = "State: %s   |   Tick: %d   |   Modules: %d   |   TestModule ticks: %d, events: %d   |   Pending commands: %d" % [
		paused_text,
		Nexus.world_state.current_tick,
		Nexus.module_registry.count(),
		int(test_section.get("tick_count", 0)),
		int(test_section.get("events_received", 0)),
		Nexus.command_queue.pending_count(),
	]
	_pause_button.text = "Resume" if Nexus.sim_clock.is_paused() else "Pause"


# Append any new events from the EventBus log to the on-screen console.
func _drain_event_log() -> void:
	var log: Array = Nexus.event_bus.get_event_log()
	while _last_logged_index < log.size():
		var entry: Dictionary = log[_last_logged_index]
		# Skip the high-frequency tick spam to keep the console readable.
		if entry["event"] != Nexus.EVENT_TICK:
			_append_log("[event] %s  %s" % [entry["event"], str(entry["payload"])])
		_last_logged_index += 1


func _append_log(text: String) -> void:
	_log_label.append_text(text + "\n")


func _on_pause_pressed() -> void:
	Nexus.toggle_pause()


func _on_step_pressed() -> void:
	# Step a few ticks manually (works even while paused) to demonstrate
	# deterministic stepping.
	Nexus.step_ticks(1)
	_append_log("[manual] stepped 1 tick -> now at tick %d" % Nexus.world_state.current_tick)


func _on_save_pressed() -> void:
	var ok: bool = Nexus.save_system.save_to_file(SAVE_PATH)
	_append_log("[save] %s -> %s" % ["ok" if ok else "FAILED", SAVE_PATH])


func _on_load_pressed() -> void:
	var ok: bool = Nexus.save_system.load_from_file(SAVE_PATH)
	_append_log("[load] %s <- %s" % ["ok" if ok else "FAILED", SAVE_PATH])
