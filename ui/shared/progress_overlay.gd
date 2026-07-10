# progress_overlay.gd
# ----------------------------------------------------------------------------
# Project Nexus - Shared Progress Overlay widget (Phase P2, step P2.2).
#
# A small, self-building full-screen overlay that shows a title, a percentage
# progress bar, and a status line. It is used everywhere the game does a short
# multi-step operation the player should see progress for:
#
#   - starting a skirmish       (Match Setup -> "Building match...")
#   - hosting / joining online  (loading catalogs / syncing the mod pack)
#   - loading a saved game      (Phase P4)
#
# It is deliberately UI-only and carries NO game logic: callers drive it with
# begin() / set_progress() / finish(), so the same widget works for any staged
# task without knowing what the stages mean.
#
# Usage:
#     var ov := ProgressOverlay.new()
#     add_child(ov)
#     ov.begin("Starting match")
#     ov.set_progress(0.5, "Loading catalogs...")
#     ov.finish()                       # fades out and frees itself
#
# CODE LANGUAGE POLICY: English-only identifiers/comments; visible strings are
# passed in by the caller (already localized) so this widget needs no locale.
# ----------------------------------------------------------------------------
extends Control
class_name ProgressOverlay

var _panel: PanelContainer
var _title: Label
var _status: Label
var _bar: ProgressBar
var _built: bool = false


func _ready() -> void:
	_build()


# Build the overlay tree programmatically so callers can `ProgressOverlay.new()`
# and add it to any scene without needing a matching .tscn. Idempotent.
func _build() -> void:
	if _built:
		return
	_built = true
	# Cover the whole screen and eat input while visible (modal feel).
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var dim: ColorRect = ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.05, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var center: CenterContainer = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(360, 0)
	center.add_child(_panel)

	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	_panel.add_child(box)

	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 20)
	box.add_child(_title)

	_bar = ProgressBar.new()
	_bar.min_value = 0.0
	_bar.max_value = 100.0
	_bar.value = 0.0
	_bar.custom_minimum_size = Vector2(0, 20)
	box.add_child(_bar)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)


# Start a task: sets the title, resets the bar to 0, shows the overlay.
func begin(title_text: String, status_text: String = "") -> void:
	_build()
	_title.text = title_text
	_status.text = status_text
	_bar.indeterminate = false
	_bar.value = 0.0
	visible = true


# MB10.1 (bug 29): start an INDETERMINATE task -- an operation whose total length
# is unknown (e.g. a LAN scan or image validation). The bar animates without a
# meaningful percentage so the player sees the game is busy, not frozen. Callers
# that later learn a real ratio can simply call set_progress(), which switches
# the bar back to determinate mode.
func begin_indeterminate(title_text: String, status_text: String = "") -> void:
	_build()
	_title.text = title_text
	_status.text = status_text
	_bar.indeterminate = true
	visible = true


# Update the bar. `ratio` is 0.0..1.0; `status_text` (optional) replaces the
# status line so the player sees which stage is running.
func set_progress(ratio: float, status_text: String = "") -> void:
	_build()
	# A real ratio always switches the bar back to determinate mode, so a task
	# that began indeterminate (unknown length) can report progress once known.
	_bar.indeterminate = false
	_bar.value = clampf(ratio, 0.0, 1.0) * 100.0
	if status_text != "":
		_status.text = status_text


# Convenience for stepped tasks: "step X of total".
func set_step(step_index: int, total_steps: int, status_text: String = "") -> void:
	var total: int = max(1, total_steps)
	set_progress(float(step_index) / float(total), status_text)


# Complete the task: fill the bar, then fade out and free (unless keep=true).
func finish(keep: bool = false) -> void:
	_build()
	_bar.indeterminate = false
	_bar.value = 100.0
	if keep:
		return
	# Fade out over a short moment, then remove ourselves from the tree.
	var tween: Tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.25)
	tween.tween_callback(queue_free)


# --- Introspection (used by tests and callers that adapt their UI) ----------

# The current bar ratio in 0.0..1.0 (100% -> 1.0). Meaningless while
# indeterminate, but still safe to read.
func get_progress() -> float:
	_build()
	return _bar.value / 100.0


# Whether the overlay is currently animating an unknown-length task.
func is_indeterminate() -> bool:
	_build()
	return _bar.indeterminate
