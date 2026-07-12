# graphic_model.gd
# ----------------------------------------------------------------------------
# Project Nexus - Pixel-graphic model + image validation for the advanced Mod
# Editor (Phase E2, step E2.3).
#
# A `graphic` block describes how an authored unit / building / object LOOKS. It
# is deliberately split into two worlds so determinism is never at risk
# (golden rule #1 of docs/Nexus_ModEditor_Plan_fa.md):
#
#   * `logical_size {w,h}`  -- the LOGICAL footprint in tiles. This is the ONLY
#                              field here that the deterministic simulation reads
#                              (collision / grid). It is a small integer.
#   * `parts[]`             -- 1..3 cosmetic layers, each with a pixel size and a
#                              texture path. PURELY visual; the sim never reads it.
#
# Layer rule: `px(layer3) <= px(layer2) <= px(layer1)` (a smaller detail sits on
# top of a larger base). Validated here, not in the engine.
#
# Image validation is headless: we inspect the PNG byte signature + the IHDR
# header to read width/height WITHOUT a live Godot Image, so the rules
# (format = PNG only, 16x16 .. 512x512) are fully unit-testable.
#
# Design rules: PURE TOOLING, deterministic, English-only (CODE_POLICY).
# ----------------------------------------------------------------------------
class_name GraphicModel
extends RefCounted

const MODE_SINGLE: String = "single"
const MODE_MULTI: String = "multi"
const MAX_PARTS: int = 3

# --- MC14.3 (req16/18): facing + firing part -------------------------------
# `facing` names which way the authored unit's art points when it is at rest /
# moving forward. It is a COSMETIC hint the render layer (MC14.5) reads to align
# the sprite with the unit's movement heading; the deterministic simulation
# never reads it. The four cardinal art orientations cover every sprite an
# author can draw.
const FACING_UP: String = "up"
const FACING_DOWN: String = "down"
const FACING_LEFT: String = "left"
const FACING_RIGHT: String = "right"
const FACINGS: Array = [FACING_UP, FACING_DOWN, FACING_LEFT, FACING_RIGHT]
const DEFAULT_FACING: String = FACING_UP

# A part may be flagged as the entity's FIRING part (the piece that visually
# shoots -- e.g. a tank's barrel). Its `firing_mount` says whether that piece is
# rigidly attached to the hull (FIXED, always points where the unit faces) or is
# a rotating TURRET that tracks the target independently (MC14.5 render). An
# authored single/multi graphic may declare AT MOST ONE firing part; combining
# units in-game can raise that to two (MC14.4).
const MOUNT_FIXED: String = "fixed"
const MOUNT_TURRET: String = "turret"
const MOUNTS: Array = [MOUNT_FIXED, MOUNT_TURRET]
const DEFAULT_MOUNT: String = MOUNT_FIXED
# The authored-graphic cap on firing parts (combination logic in MC14.4 raises
# the in-game cap to MAX_COMBINED_FIRING_PARTS).
const MAX_FIRING_PARTS: int = 1

# Allowed pixel-resolution bounds (cosmetic only). Configurable per project; the
# editor shows these under the upload box.
const MIN_PX: int = 16
const MAX_PX: int = 512

# MB8.2 (bug 26): upper bound on an uploaded image file so a huge PNG cannot hang
# the installed build while decoding. Editor shows this in the upload hint.
const MAX_IMAGE_KB: int = 512

# MB8.2 (bug 26): how far an uploaded image's aspect ratio may drift from the
# entity's declared px ratio before it is rejected (5% tolerance). This stops a
# wrong-shape image (e.g. a square PNG for a 2:1 unit) from being squashed and
# looking broken / hanging the renderer.
const RATIO_TOLERANCE: float = 0.05

# Logical-size bounds (this DOES affect the sim, so keep it sane).
const MIN_LOGICAL: int = 1
const MAX_LOGICAL: int = 8

# The 8-byte PNG signature.
const PNG_SIGNATURE: Array = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]


# Build a safe default single-part graphic with a 1x1 logical footprint.
static func default_graphic(texture: String = "") -> Dictionary:
	return {
		"mode": MODE_SINGLE,
		"logical_size": { "w": 1, "h": 1 },
		"parts": [
			{ "layer": 1, "px": { "w": 64, "h": 64 }, "texture": texture },
		],
	}


static func default_part(layer: int, px_w: int = 64, px_h: int = 64, texture: String = "") -> Dictionary:
	return { "layer": int(layer), "px": { "w": int(px_w), "h": int(px_h) }, "texture": texture }


# --- MC14.3 (req16/18): facing + firing-part helpers ------------------------

# Coerce an arbitrary value to a valid facing, falling back to DEFAULT_FACING for
# anything unknown. Keeps authored data honest without ever raising.
static func normalise_facing(value: Variant) -> String:
	var f: String = str(value).strip_edges().to_lower()
	return f if FACINGS.has(f) else DEFAULT_FACING


# Coerce an arbitrary value to a valid firing mount, defaulting to MOUNT_FIXED.
static func normalise_mount(value: Variant) -> String:
	var m: String = str(value).strip_edges().to_lower()
	return m if MOUNTS.has(m) else DEFAULT_MOUNT


# Read a graphic's facing (defaulting when absent/invalid). Null-safe.
static func get_facing(graphic: Variant) -> String:
	if not (graphic is Dictionary):
		return DEFAULT_FACING
	return normalise_facing((graphic as Dictionary).get("facing", DEFAULT_FACING))


# Return a copy of `graphic` with its facing set to a normalised value. Never
# mutates the input (authoring stays snapshot-friendly for undo/redo).
static func set_facing(graphic: Variant, value: Variant) -> Dictionary:
	var g: Dictionary = (graphic as Dictionary).duplicate(true) if graphic is Dictionary else default_graphic()
	g["facing"] = normalise_facing(value)
	return g


# True if a single part dictionary is flagged as a firing part.
static func part_is_firing(part: Variant) -> bool:
	return part is Dictionary and bool((part as Dictionary).get("is_firing_part", false))


# The firing mount of a single part (defaults to FIXED). Null-safe.
static func part_mount(part: Variant) -> String:
	if not (part is Dictionary):
		return DEFAULT_MOUNT
	return normalise_mount((part as Dictionary).get("firing_mount", DEFAULT_MOUNT))


# Count how many parts of a graphic are flagged as firing parts.
static func count_firing_parts(graphic: Variant) -> int:
	if not (graphic is Dictionary):
		return 0
	var parts: Variant = (graphic as Dictionary).get("parts", [])
	if not (parts is Array):
		return 0
	var n: int = 0
	for part in (parts as Array):
		if part_is_firing(part):
			n += 1
	return n


# The index of the first firing part, or -1 when the graphic has none.
static func first_firing_index(graphic: Variant) -> int:
	if not (graphic is Dictionary):
		return -1
	var parts: Variant = (graphic as Dictionary).get("parts", [])
	if not (parts is Array):
		return -1
	var arr: Array = parts as Array
	for i in arr.size():
		if part_is_firing(arr[i]):
			return i
	return -1


# Return a copy of `graphic` where exactly the part at `part_index` is the firing
# part (with the given mount) and every other part's firing flag is cleared. This
# enforces the authored cap of one firing part (MAX_FIRING_PARTS) by construction.
# `part_index` < 0 clears ALL firing flags (no firing part).
static func set_firing_part(graphic: Variant, part_index: int, mount: Variant = DEFAULT_MOUNT) -> Dictionary:
	var g: Dictionary = (graphic as Dictionary).duplicate(true) if graphic is Dictionary else default_graphic()
	var parts: Array = (g.get("parts", []) as Array).duplicate(true) if g.get("parts", []) is Array else []
	var wanted_mount: String = normalise_mount(mount)
	for i in parts.size():
		if not (parts[i] is Dictionary):
			continue
		var p: Dictionary = (parts[i] as Dictionary).duplicate(true)
		if i == part_index:
			p["is_firing_part"] = true
			p["firing_mount"] = wanted_mount
		else:
			p.erase("is_firing_part")
			p.erase("firing_mount")
		parts[i] = p
	g["parts"] = parts
	return g


# --- MC4.2 (request 5): optional animation sprites --------------------------
# An entity may OPTIONALLY carry an `animation` block describing the cosmetic
# art the AnimationEventUtil layer plays. This is PURELY visual (out of the
# deterministic hash) and every field is optional -- an entity with no
# animation block falls back to the simple programmatic animation (MC4.3).
#
#   animation: {
#     projectile: { texture, px: {w,h} },     # the flying shot sprite
#     explosion:  { texture, frames, fps, px: {w,h} },  # death spritesheet
#   }
#
# `frames`/`fps` describe how to read the explosion spritesheet (horizontal
# strip of `frames` cells) at the given playback rate.
const ANIM_MIN_FRAMES: int = 1
const ANIM_MAX_FRAMES: int = 64
const ANIM_MIN_FPS: int = 1
const ANIM_MAX_FPS: int = 60


# A safe default animation block: no textures yet (programmatic fallback), with
# sane frame/fps defaults for the explosion spritesheet.
static func default_animation() -> Dictionary:
	return {
		"projectile": { "texture": "", "px": { "w": 16, "h": 16 } },
		"explosion": { "texture": "", "frames": 8, "fps": 12, "px": { "w": 64, "h": 64 } },
	}


# True if a graphic carries a usable (non-empty texture) projectile sprite.
static func has_projectile_sprite(graphic: Variant) -> bool:
	if not (graphic is Dictionary):
		return false
	var anim: Variant = (graphic as Dictionary).get("animation", {})
	if not (anim is Dictionary):
		return false
	var proj: Variant = (anim as Dictionary).get("projectile", {})
	return proj is Dictionary and str((proj as Dictionary).get("texture", "")) != ""


# True if a graphic carries a usable (non-empty texture) explosion spritesheet.
static func has_explosion_sprite(graphic: Variant) -> bool:
	if not (graphic is Dictionary):
		return false
	var anim: Variant = (graphic as Dictionary).get("animation", {})
	if not (anim is Dictionary):
		return false
	var expl: Variant = (anim as Dictionary).get("explosion", {})
	return expl is Dictionary and str((expl as Dictionary).get("texture", "")) != ""


# Validate an OPTIONAL animation block. Absent -> valid (empty problems). When
# present, validates px bounds + frames/fps ranges. Textures may be empty
# (programmatic fallback) but if given must be non-blank strings.
static func validate_animation(animation: Variant) -> Array:
	var problems: Array = []
	if animation == null:
		return problems
	if not (animation is Dictionary):
		return ["graphic.animation is not a dictionary"]
	var a: Dictionary = animation as Dictionary

	if a.has("projectile"):
		var proj: Variant = a["projectile"]
		if not (proj is Dictionary):
			problems.append("animation.projectile is not a dictionary")
		else:
			problems.append_array(_validate_anim_px(proj as Dictionary, "projectile"))

	if a.has("explosion"):
		var expl: Variant = a["explosion"]
		if not (expl is Dictionary):
			problems.append("animation.explosion is not a dictionary")
		else:
			var e: Dictionary = expl as Dictionary
			problems.append_array(_validate_anim_px(e, "explosion"))
			var frames: int = int(e.get("frames", ANIM_MIN_FRAMES))
			if frames < ANIM_MIN_FRAMES or frames > ANIM_MAX_FRAMES:
				problems.append("animation.explosion.frames out of bounds (%d..%d)" % [ANIM_MIN_FRAMES, ANIM_MAX_FRAMES])
			var fps: int = int(e.get("fps", ANIM_MIN_FPS))
			if fps < ANIM_MIN_FPS or fps > ANIM_MAX_FPS:
				problems.append("animation.explosion.fps out of bounds (%d..%d)" % [ANIM_MIN_FPS, ANIM_MAX_FPS])
	return problems


static func _validate_anim_px(block: Dictionary, label: String) -> Array:
	var problems: Array = []
	var px: Variant = block.get("px", {})
	if not (px is Dictionary):
		problems.append("animation.%s has no px size" % label)
		return problems
	var pw: int = int((px as Dictionary).get("w", 0))
	var ph: int = int((px as Dictionary).get("h", 0))
	if pw < MIN_PX or pw > MAX_PX or ph < MIN_PX or ph > MAX_PX:
		problems.append("animation.%s px out of bounds (%d..%d)" % [label, MIN_PX, MAX_PX])
	return problems


# --- Validation -------------------------------------------------------------

# Validate the whole graphic block. Returns an Array of problem strings; empty
# means valid.
static func validate(graphic: Variant) -> Array:
	var problems: Array = []
	if not (graphic is Dictionary):
		return ["graphic is not a dictionary"]
	var g: Dictionary = graphic as Dictionary

	var mode: String = str(g.get("mode", MODE_SINGLE))
	if mode != MODE_SINGLE and mode != MODE_MULTI:
		problems.append("graphic.mode must be 'single' or 'multi'")

	# Logical size.
	var ls: Variant = g.get("logical_size", {})
	if not (ls is Dictionary):
		problems.append("graphic.logical_size missing")
	else:
		var lw: int = int((ls as Dictionary).get("w", 0))
		var lh: int = int((ls as Dictionary).get("h", 0))
		if lw < MIN_LOGICAL or lw > MAX_LOGICAL or lh < MIN_LOGICAL or lh > MAX_LOGICAL:
			problems.append("graphic.logical_size out of bounds (%d..%d)" % [MIN_LOGICAL, MAX_LOGICAL])

	# Parts.
	var parts: Variant = g.get("parts", [])
	if not (parts is Array) or (parts as Array).is_empty():
		problems.append("graphic.parts must have at least one layer")
		return problems
	var pa: Array = parts as Array
	if mode == MODE_SINGLE and pa.size() != 1:
		problems.append("single-part graphic must have exactly one layer")
	if pa.size() > MAX_PARTS:
		problems.append("graphic.parts exceeds %d layers" % MAX_PARTS)

	for i in pa.size():
		if not (pa[i] is Dictionary):
			problems.append("part %d is not a dictionary" % i)
			continue
		var part: Dictionary = pa[i] as Dictionary
		var px: Variant = part.get("px", {})
		if not (px is Dictionary):
			problems.append("part %d has no px size" % i)
			continue
		var pw: int = int((px as Dictionary).get("w", 0))
		var ph: int = int((px as Dictionary).get("h", 0))
		if pw < MIN_PX or pw > MAX_PX or ph < MIN_PX or ph > MAX_PX:
			problems.append("part %d px out of bounds (%d..%d)" % [i, MIN_PX, MAX_PX])

	problems.append_array(validate_layer_sizes(pa))

	# MC14.3 (req16/18): optional facing + firing-part flags (cosmetic; absent ->
	# no problems). Facing, when present, must be one of the cardinal art
	# orientations; an authored graphic may declare AT MOST one firing part, and
	# each firing part's mount must be fixed/turret.
	if g.has("facing"):
		var f: String = str(g.get("facing", "")).strip_edges().to_lower()
		if not FACINGS.has(f):
			problems.append("graphic.facing must be one of up/down/left/right")
	var firing_count: int = 0
	for i in pa.size():
		if not (pa[i] is Dictionary):
			continue
		var fpart: Dictionary = pa[i] as Dictionary
		if bool(fpart.get("is_firing_part", false)):
			firing_count += 1
			var mnt: String = str(fpart.get("firing_mount", DEFAULT_MOUNT)).strip_edges().to_lower()
			if not MOUNTS.has(mnt):
				problems.append("part %d firing_mount must be fixed or turret" % i)
	if firing_count > MAX_FIRING_PARTS:
		problems.append("graphic declares %d firing parts (max %d)" % [firing_count, MAX_FIRING_PARTS])

	# MC4.2: optional animation block (cosmetic; absent -> no problems).
	if g.has("animation"):
		problems.append_array(validate_animation(g["animation"]))
	return problems


# Layer rule: px area must be non-increasing from layer 1 upward (a top detail is
# never bigger than the layer beneath it). Parts are sorted by `layer` first.
static func validate_layer_sizes(parts: Array) -> Array:
	var problems: Array = []
	var sorted_parts: Array = parts.duplicate(true)
	sorted_parts.sort_custom(func(a, b): return int(a.get("layer", 0)) < int(b.get("layer", 0)))
	var prev_area: int = -1
	for i in sorted_parts.size():
		var part: Dictionary = sorted_parts[i] as Dictionary
		var px: Dictionary = part.get("px", {}) as Dictionary
		var area: int = int(px.get("w", 0)) * int(px.get("h", 0))
		if prev_area >= 0 and area > prev_area:
			problems.append("layer %d is larger than the layer beneath it" % int(part.get("layer", i + 1)))
		prev_area = area
	return problems


# --- Image (PNG) inspection -------------------------------------------------

# Validate raw image bytes. Returns an Array of problems; empty means valid.
# `min_px`/`max_px` default to the model bounds but the editor may pass tighter
# limits. Format is restricted to PNG (golden-rule-friendly: deterministic decode
# and the one format TextureService loads everywhere).
static func validate_image(bytes: PackedByteArray, min_px: int = MIN_PX, max_px: int = MAX_PX) -> Array:
	var problems: Array = []
	if not is_png(bytes):
		problems.append("image is not a valid PNG")
		return problems
	var dims: Vector2i = png_dimensions(bytes)
	if dims.x <= 0 or dims.y <= 0:
		problems.append("could not read PNG dimensions")
		return problems
	if dims.x < min_px or dims.y < min_px:
		problems.append("image smaller than %dx%d" % [min_px, min_px])
	if dims.x > max_px or dims.y > max_px:
		problems.append("image larger than %dx%d" % [max_px, max_px])
	return problems


# MB8.2 (bug 26): validate an uploaded image AGAINST a target px size so only an
# image with the SAME aspect ratio (within RATIO_TOLERANCE) and a sane file size
# is accepted. This is what the mod editor calls once the user has set a part's
# logical px (e.g. 20x10 -> only ~2:1 images pass). Returns problem strings.
#   - `target_w`/`target_h` : the part's declared px size (defines the ratio).
#   - `min_px`/`max_px`     : dimension bounds (default to model bounds).
#   - `max_kb`              : file-size cap in KiB (default MAX_IMAGE_KB).
static func validate_image_for_ratio(bytes: PackedByteArray, target_w: int, target_h: int, min_px: int = MIN_PX, max_px: int = MAX_PX, max_kb: int = MAX_IMAGE_KB) -> Array:
	# Reuse the base checks (PNG, dimension bounds) first.
	var problems: Array = validate_image(bytes, min_px, max_px)
	# File-size guard (protects the installed build from a huge decode).
	var kb: int = int(ceil(float(bytes.size()) / 1024.0))
	if kb > max_kb:
		problems.append("image file too large (%d KB > %d KB)" % [kb, max_kb])
	# Aspect-ratio guard (only when we could read valid dimensions + a target).
	if target_w > 0 and target_h > 0 and not problems.has("could not read PNG dimensions"):
		var dims: Vector2i = png_dimensions(bytes)
		if dims.x > 0 and dims.y > 0:
			var want: float = float(target_w) / float(target_h)
			var got: float = float(dims.x) / float(dims.y)
			if absf(got - want) > want * RATIO_TOLERANCE:
				problems.append("image aspect ratio %s does not match required %s" % [ratio_label(dims.x, dims.y), ratio_label(target_w, target_h)])
	return problems


# MB8.2: human-readable "W:H" ratio in lowest terms, for hint text + messages.
static func ratio_label(w: int, h: int) -> String:
	if w <= 0 or h <= 0:
		return "?:?"
	var g: int = _gcd(w, h)
	return "%d:%d" % [w / g, h / g]


# MB8.2 (bug 26): the hint shown under the upload box for a given part px size.
# Updates live as the user changes the entity's dimensions, e.g.
#   "PNG with 2:1 ratio, 16..512 px per side, max 512 KB".
static func upload_hint(target_w: int, target_h: int, min_px: int = MIN_PX, max_px: int = MAX_PX, max_kb: int = MAX_IMAGE_KB) -> String:
	return "PNG with %s ratio, %d..%d px per side, max %d KB" % [ratio_label(target_w, target_h), min_px, max_px, max_kb]


static func _gcd(a: int, b: int) -> int:
	a = absi(a)
	b = absi(b)
	while b != 0:
		var t: int = b
		b = a % b
		a = t
	return maxi(a, 1)


# True if the bytes start with the PNG signature.
static func is_png(bytes: PackedByteArray) -> bool:
	if bytes.size() < 8:
		return false
	for i in 8:
		if bytes[i] != PNG_SIGNATURE[i]:
			return false
	return true


# Read width/height from the PNG IHDR chunk. The IHDR is always the first chunk:
# bytes 8..11 = chunk length, 12..15 = "IHDR", 16..19 = width, 20..23 = height
# (big-endian). Returns Vector2i.ZERO when it cannot be read.
static func png_dimensions(bytes: PackedByteArray) -> Vector2i:
	if bytes.size() < 24 or not is_png(bytes):
		return Vector2i.ZERO
	# Confirm the IHDR tag.
	if bytes[12] != 0x49 or bytes[13] != 0x48 or bytes[14] != 0x44 or bytes[15] != 0x52:
		return Vector2i.ZERO
	var w: int = (bytes[16] << 24) | (bytes[17] << 16) | (bytes[18] << 8) | bytes[19]
	var h: int = (bytes[20] << 24) | (bytes[21] << 16) | (bytes[22] << 8) | bytes[23]
	return Vector2i(w, h)


# Build a header-only PNG byte stream of the given dimensions, intended ONLY for
# this project's lightweight validators (is_png / png_dimensions), NOT for real
# decoding. BUG-D4 note: it writes a real 8-byte signature and a correct IHDR
# body, but the IHDR CRC is a placeholder (0) and there is NO IDAT chunk (IEND
# follows IHDR directly). is_png/png_dimensions ignore the CRC and only read the
# signature + IHDR, so this passes them; a real decoder such as
# Image.load_png_from_buffer() will REJECT these bytes. Do not feed this output
# to Godot's texture loader -- use a genuine PNG asset for that.
static func make_test_png(width: int, height: int) -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	for b in PNG_SIGNATURE:
		out.append(int(b))
	# IHDR chunk: length=13, type="IHDR", data(13), crc(4).
	var ihdr: PackedByteArray = PackedByteArray()
	ihdr.append_array(_be32(13))
	var ihdr_body: PackedByteArray = PackedByteArray()
	ihdr_body.append_array("IHDR".to_ascii_buffer())
	ihdr_body.append_array(_be32(width))
	ihdr_body.append_array(_be32(height))
	ihdr_body.append(8)   # bit depth
	ihdr_body.append(6)   # colour type RGBA
	ihdr_body.append(0)   # compression
	ihdr_body.append(0)   # filter
	ihdr_body.append(0)   # interlace
	ihdr.append_array(ihdr_body)
	ihdr.append_array(_be32(0))  # placeholder CRC (validation does not check it)
	out.append_array(ihdr)
	# IEND chunk.
	out.append_array(_be32(0))
	out.append_array("IEND".to_ascii_buffer())
	out.append_array(_be32(0))
	return out


static func _be32(value: int) -> PackedByteArray:
	var b: PackedByteArray = PackedByteArray()
	b.append((value >> 24) & 0xFF)
	b.append((value >> 16) & 0xFF)
	b.append((value >> 8) & 0xFF)
	b.append(value & 0xFF)
	return b
