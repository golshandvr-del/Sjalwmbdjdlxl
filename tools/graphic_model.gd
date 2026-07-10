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
