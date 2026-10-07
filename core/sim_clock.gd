# sim_clock.gd
# ----------------------------------------------------------------------------
# Project Nexus - Simulation Clock (core component).
#
# A deterministic, tick-based clock. Real frame time is accumulated and
# converted into a fixed number of discrete simulation ticks. This decouples
# game logic from frame rate, which is the foundation for:
#   - Hybrid RTS + Turn-based "Active Pause"
#   - Determinism (same ticks -> same result)
#   - Lockstep multiplayer (Phase 4)
#
# The clock does NOT advance the world by itself; it tells the Nexus how many
# ticks to run. The Nexus owns the actual tick execution.
# ----------------------------------------------------------------------------
class_name SimClock
extends RefCounted

# How many simulation ticks happen per simulated second.
var tick_rate: int = 20

# Time-scale multiplier (1.0 = normal, 2.0 = fast-forward, etc.).
var time_scale: float = 1.0

# Active Pause flag. When true, no ticks advance but commands may still queue.
var paused: bool = false

# Whether the clock is running at all (false before a match starts).
var running: bool = false

# Total ticks elapsed since start.
var total_ticks: int = 0

# Internal accumulator of real time (seconds) not yet converted to ticks.
var _accumulator: float = 0.0

# Upper bound (seconds) of real time a single advance() call may consume.
const MAX_FRAME_DELTA: float = 0.5


func start() -> void:
	running = true
	paused = false
	_accumulator = 0.0


func stop() -> void:
	running = false
	_accumulator = 0.0


func reset() -> void:
	total_ticks = 0
	_accumulator = 0.0
	paused = false
	running = false


# --- Active Pause controls --------------------------------------------------

func pause() -> void:
	paused = true


func resume() -> void:
	paused = false


func toggle_pause() -> void:
	paused = not paused


func is_paused() -> bool:
	return paused


# Seconds-per-tick derived from the tick rate.
func seconds_per_tick() -> float:
	return 1.0 / float(tick_rate)


# Advance real time by `real_delta` seconds and return how many simulation
# ticks should be executed this frame. Returns 0 while paused/stopped.
# The Nexus calls this every frame and runs the returned number of ticks.
func advance(real_delta: float) -> int:
	if not running or paused:
		return 0
	# Clamp one frame's real time so a huge delta (Android app resumed from the
	# background, debugger break, long load hitch) cannot trigger a burst of
	# hundreds of catch-up ticks in a single frame ("spiral of death").
	_accumulator += minf(maxf(real_delta, 0.0), MAX_FRAME_DELTA) * time_scale
	var spt: float = seconds_per_tick()
	# Small epsilon guards against floating-point accumulation error (e.g.
	# 0.05 + 0.05 landing a hair below 0.1). Without it the tick count would
	# depend on float rounding, which breaks determinism.
	const EPSILON: float = 1e-6
	var ticks_to_run: int = 0
	while _accumulator + EPSILON >= spt:
		_accumulator -= spt
		ticks_to_run += 1
	total_ticks += ticks_to_run
	return ticks_to_run


# Deterministic single step (for tests / step-debugging), ignores real time.
func step(num_ticks: int = 1) -> int:
	total_ticks += num_ticks
	return num_ticks
