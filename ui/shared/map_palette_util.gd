# map_palette_util.gd
# ----------------------------------------------------------------------------
# Project Nexus - Fixed 16-colour owner/team palette for the Map Editor
# (Phase MB7.3, bug 21a: the editor only offered a single owner colour; the user
# asked for a 16-colour palette so flags/HQ/units can belong to any of 16
# owners/teams).
#
# Pure, dependency-free (no Nexus, no SceneTree, no Color allocation required for
# the mapping itself) so the palette + owner<->colour mapping is unit-testable
# headlessly and reused by both the editor scene and any preview.
#
# The palette is DETERMINISTIC and STABLE: owner index N always maps to the same
# colour, so a saved map re-opens with identical owner colours on every machine.
# Colours are stored as "RRGGBB" hex strings (ASCII, CODE_POLICY-safe); the UI
# turns them into Color via Color.html() where it actually needs to draw.
#
# CODE LANGUAGE POLICY: English-only identifiers/comments (ASCII).
# ----------------------------------------------------------------------------
class_name MapPaletteUtil
extends RefCounted


# Number of distinct owner/team slots the editor palette exposes.
const SLOT_COUNT: int = 16

# 16 visually distinct, colour-blind-friendlier hex colours (no leading '#').
# Index == owner id. Order is fixed forever; appending is fine, reordering is not
# (it would recolour existing saved maps).
const COLORS: Array = [
	"e6194b", "3cb44b", "ffe119", "4363d8",
	"f58231", "911eb4", "46f0f0", "f032e6",
	"bcf60c", "fabebe", "008080", "e6beff",
	"9a6324", "fffac8", "800000", "aaffc3",
]


# Clamp an arbitrary owner id into the valid palette range [0, SLOT_COUNT - 1].
static func clamp_slot(owner: int) -> int:
	if owner < 0:
		return 0
	if owner >= SLOT_COUNT:
		return SLOT_COUNT - 1
	return owner


# Hex "RRGGBB" colour string for an owner id (clamped into range).
static func color_hex(owner: int) -> String:
	return str(COLORS[clamp_slot(owner)])


# All palette colours in order (defensive copy) so a UI can build 16 swatches.
static func all_hex() -> Array:
	return COLORS.duplicate()
