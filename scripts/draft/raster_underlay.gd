class_name RasterUnderlay
extends RefCounted
## A picture under the drawing: a scan of a surveyor's plan, a marked-up print, an aerial
## photograph, the consultant's rendered concept.
##
## Three readers in this app turn a *vector* file into linework - a DXF (`DxfFile`), an
## OpenStreetMap extract (`OsmFile`) and a LandXML plat (`LandXmlFile`) - and all three land
## their shapes on 950-UNDERLAY, the layer that does not plot. This is the fourth, for the file
## that has no linework in it to read at all: there is nothing in a photograph to become an
## entity.
##
## ## A picture is not linework
##
## So it is not placed as geometry. It is *kept* beside the drawing and drawn underneath
## everything, and the three consequences are the whole design:
##
## * **it never plots.** A sheet reads the document's entities, and a picture is not one. A
##   tracing aid that turned up on the drawing that goes to a client would be a defect in the
##   deliverable rather than a convenience.
## * **it never snaps, measures or takes off.** The snap engine, the takeoff and the plant
##   schedule all walk the drawing's entities, so a picture cannot be picked, dimensioned
##   against or bought by the square metre.
## * **it lies over the ground and under every line**. The yard's own flat lawn, house and
##   paving are scenery the picture covers, and every plant standing on the ground and every
##   line the designer draws stays on top of it. A tracing aid you cannot see through is not a
##   tracing aid, which is why the opacity starts below one.
##
## ## The copy
##
## The picture is copied into the app's own folder rather than referred to where somebody found
## it. A drawing is a document people send each other, and a drawing that points at
## `D:\scans\site-plan.png` is a drawing that is broken on every other machine. This is the same
## reason a recovery copy lives in `user://recovery` rather than beside the file it came from,
## and the same reason the recent list is not the only record of where a drawing is.
##
## ## Reading the header, not the pixels
##
## `sniff` reads the first few kilobytes and works out the format and the pixel size from the
## header alone. Two reasons. A 12000 x 9000 scan is 400 MB decoded, and the only thing this app
## needs to know about it before it can be drawn is its proportion - width to height. And Godot's
## own loader *prints an error* when it is handed something that is not an image, which in a
## project whose house style is "a warning is an error" is a reason never to hand it anything
## unread. `decode` therefore only ever sees bytes whose header has already been understood, and
## the format it is told is the one `sniff` established - so a `.png` that is really a JPEG
## draws rather than being refused for its name.
##
## The record the drawing keeps is a plain Dictionary, like the irrigation and lighting records:
## the module does the reading and the arithmetic, and the document only holds the records.

const UnitsScript := preload("res://scripts/draft/units.gd")

## Where the drawing's own pictures are kept. The drawing's folder, not the picture's: see the
## header on why a drawing that points outside the app's own folder is a drawing that breaks.
const DIR := "user://underlays"

## The formats `sniff` understands, by file extension. Not the list Godot can decode - the list
## this reader can *read the size of*, because a format this cannot measure is one it cannot
## place at a real size on the ground.
const EXTENSIONS := ["png", "jpg", "jpeg", "webp", "bmp"]
const FORMATS := "PNG, JPEG, WebP or BMP"

## How see-through a picture starts. A tracing aid is for tracing over, so the linework above it
## has to win; a picture laid on at full strength is a picture that has hidden the drawing.
const DEFAULT_OPACITY := 0.65
const MIN_OPACITY := 0.0
const MAX_OPACITY := 1.0

## How far across the ground a picture starts when there is nothing to measure it against - a drawing
## with no geometry on it yet, which is exactly the drawing somebody traces a scan onto. A number on a
## form that gets changed rather than a refusal, because "how big is your site" has no right answer
## this app could know.
const SUGGESTED_WIDTH := 20.0

## How much of a file is read to work out what it is. Every header in the list above ends well
## inside this, and none of it is a pixel.
const HEAD_BYTES := 65536

## How much of a file name is kept. Long enough to hold a scan's date and a room, short enough
## that the folder listing stays readable.
const NAME_LIMIT := 48


# --- what kind of file is this -------------------------------------------------------


static func formats_text() -> String:
	return FORMATS


static func extension_of(path: String) -> String:
	var dot := path.rfind(".")
	if dot < 0 or dot >= path.length() - 1:
		return ""
	return path.substr(dot + 1).to_lower()


## Whether a file *claims* to be a picture by its name. A claim, not a fact: `sniff` is what
## establishes the fact, and the file dialog offers what this lets through so that a person
## naming a scan is not stopped by the app guessing wrong.
static func is_image(path: String) -> bool:
	return EXTENSIONS.has(extension_of(path))


## A file dialog filter line for the formats this reads, so the dialog offers exactly what the
## reader accepts - a dialog offering a format it will refuse is a dialog that lies.
static func dialog_filter() -> String:
	var patterns: Array[String] = []
	for extension: String in EXTENSIONS:
		patterns.append("*." + extension)
	return "%s ; Pictures" % ", ".join(PackedStringArray(patterns))


## Strip a name down to something both a file system and a person can live with: lower case,
## no separators that mean something else on another machine, and never empty.
static func slug(text: String) -> String:
	var out := ""
	var pending_dash := false
	for index in text.length():
		var code := text.unicode_at(index)
		var alnum := (
			(code >= 97 and code <= 122) or (code >= 65 and code <= 90) or (code >= 48 and code <= 57)
		)
		if alnum:
			if pending_dash and not out.is_empty():
				out += "-"
			pending_dash = false
			out += String.chr(code).to_lower()
		else:
			pending_dash = true
	if out.length() > NAME_LIMIT:
		out = out.substr(0, NAME_LIMIT)
	out = out.rstrip("-")
	return out if not out.is_empty() else "picture"


# --- reading the file ----------------------------------------------------------------


## Read a picture's header: what format it is and how many pixels it is, without decoding it.
## Returns `{ok, reason, format, width_px, height_px}`. A refusal names why - "not a picture this
## can read" is the answer for a text file renamed to `.png`, and being told so is the point.
static func sniff(path: String) -> Dictionary:
	if path.strip_edges().is_empty():
		return _refused("no file was named")
	if not FileAccess.file_exists(path):
		return _refused("there is no file at %s" % path)
	var bytes := _head(path)
	if bytes.size() < 16:
		return _refused("%s is too short to be a picture" % path.get_file())
	var info := _read_header(bytes)
	if info.is_empty():
		return _refused("%s is not a picture this can read (%s)" % [path.get_file(), FORMATS])
	return info


static func _refused(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "format": "", "width_px": 0, "height_px": 0}


static func _head(path: String) -> PackedByteArray:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return PackedByteArray()
	var count := mini(HEAD_BYTES, file.get_length())
	var bytes := file.get_buffer(count)
	file.close()
	return bytes


## The format and the pixel size from the header bytes alone. An empty Dictionary when the header
## is not one this reads - so the caller has exactly one thing to test.
static func _read_header(bytes: PackedByteArray) -> Dictionary:
	if _matches(bytes, 0, [0x89, 0x50, 0x4E, 0x47]):
		# PNG: the IHDR chunk is always first, so the size is at a fixed offset.
		if bytes.size() < 24 or not _matches(bytes, 12, [0x49, 0x48, 0x44, 0x52]):
			return {}
		return _size("PNG", _u32_be(bytes, 16), _u32_be(bytes, 20))
	if _matches(bytes, 0, [0xFF, 0xD8]):
		return _jpeg_size(bytes)
	if _matches(bytes, 0, [0x42, 0x4D]):
		# BMP: a signed height here means the rows run top-down; the size is the height either way.
		if bytes.size() < 26:
			return {}
		return _size("BMP", _i32_le(bytes, 18), absi(_i32_le(bytes, 22)))
	if _matches(bytes, 0, [0x52, 0x49, 0x46, 0x46]) and _matches(bytes, 8, [0x57, 0x45, 0x42, 0x50]):
		return _webp_size(bytes)
	return {}


## JPEG is the one format here with no fixed offset for the size: the header is a chain of
## segments and the frame header can sit anywhere in it. So the chain is walked.
static func _jpeg_size(bytes: PackedByteArray) -> Dictionary:
	var at := 2
	while at + 8 < bytes.size():
		if bytes[at] != 0xFF:
			return {}
		var marker := bytes[at + 1]
		# A marker with no body of its own, so the next marker follows immediately.
		if marker == 0x01 or (marker >= 0xD0 and marker <= 0xD7):
			at += 2
			continue
		var length := _u16_be(bytes, at + 2)
		if length < 2:
			return {}
		# SOF0 through SOF15, minus the three in that range that are not frame headers: DHT, JPG
		# and DAC. This is the segment that states the picture's size.
		var frame_header := (
			marker >= 0xC0 and marker <= 0xCF
			and marker != 0xC4 and marker != 0xC8 and marker != 0xCC
		)
		if frame_header:
			return _size("JPEG", _u16_be(bytes, at + 7), _u16_be(bytes, at + 5))
		at += 2 + length
	return {}


## WebP has three shapes, and older files use the older two: a lossy frame, a lossless frame, and
## the extended container that can hold either.
static func _webp_size(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < 30:
		return {}
	if _matches(bytes, 12, [0x56, 0x50, 0x38, 0x58]):
		# VP8X: the canvas size is stored as one less than it is, in 24 bits.
		return _size("WebP", _u24_le(bytes, 24) + 1, _u24_le(bytes, 27) + 1)
	if _matches(bytes, 12, [0x56, 0x50, 0x38, 0x4C]):
		# VP8L: 14 bits of width and 14 bits of height, packed into one little-endian word.
		var bits := _u32_le(bytes, 21)
		return _size("WebP", (bits & 0x3FFF) + 1, ((bits >> 14) & 0x3FFF) + 1)
	if _matches(bytes, 12, [0x56, 0x50, 0x38, 0x20]):
		# VP8 (lossy): fourteen bits each, below the frame tag and the start code.
		if not _matches(bytes, 23, [0x9D, 0x01, 0x2A]):
			return {}
		return _size("WebP", _u16_le(bytes, 26) & 0x3FFF, _u16_le(bytes, 28) & 0x3FFF)
	return {}


static func _size(format: String, width_px: int, height_px: int) -> Dictionary:
	if width_px <= 0 or height_px <= 0:
		return {}
	return {
		"ok": true, "reason": "", "format": format,
		"width_px": width_px, "height_px": height_px,
	}


static func _matches(bytes: PackedByteArray, at: int, signature: Array) -> bool:
	if at < 0 or at + signature.size() > bytes.size():
		return false
	for index in signature.size():
		if bytes[at + index] != int(signature[index]):
			return false
	return true


static func _u16_le(bytes: PackedByteArray, at: int) -> int:
	return bytes[at] | (bytes[at + 1] << 8)


static func _u16_be(bytes: PackedByteArray, at: int) -> int:
	return (bytes[at] << 8) | bytes[at + 1]


static func _u24_le(bytes: PackedByteArray, at: int) -> int:
	return bytes[at] | (bytes[at + 1] << 8) | (bytes[at + 2] << 16)


static func _u32_le(bytes: PackedByteArray, at: int) -> int:
	return bytes[at] | (bytes[at + 1] << 8) | (bytes[at + 2] << 16) | (bytes[at + 3] << 24)


static func _i32_le(bytes: PackedByteArray, at: int) -> int:
	var raw := _u32_le(bytes, at)
	if raw >= 0x80000000:
		return raw - 0x100000000
	return raw


static func _u32_be(bytes: PackedByteArray, at: int) -> int:
	return (bytes[at] << 24) | (bytes[at + 1] << 16) | (bytes[at + 2] << 8) | bytes[at + 3]


## Turn a picture's bytes into an image, told which format it is by the header that was already
## read. Never handed bytes whose header was not understood, so it is never a place an error is
## printed for a file that is simply not a picture.
static func decode(bytes: PackedByteArray, format: String) -> Image:
	if bytes.is_empty():
		return null
	# The `load_*_from_buffer` family are instance methods in this engine version, not statics, and
	# they answer with an Error rather than with an image - so the image is made first and the
	# answer decides whether it is worth returning.
	var image := Image.new()
	var failed := ERR_UNAVAILABLE
	match format:
		"PNG":
			failed = image.load_png_from_buffer(bytes)
		"JPEG":
			failed = image.load_jpg_from_buffer(bytes)
		"WebP":
			failed = image.load_webp_from_buffer(bytes)
		"BMP":
			failed = image.load_bmp_from_buffer(bytes)
		_:
			return null
	return image if failed == OK else null


## The texture to draw for a picture this app kept, or null when it cannot be drawn. Read once per
## file by the caller: a plan repaints every frame and the disk is not asked twice.
static func texture_of(path: String) -> ImageTexture:
	if not FileAccess.file_exists(path):
		return null
	var bytes := FileAccess.get_file_as_bytes(path)
	var info := _read_header(bytes)
	if info.is_empty():
		return null
	var image := decode(bytes, String(info["format"]))
	if image == null:
		return null
	return ImageTexture.create_from_image(image)


# --- taking one on -------------------------------------------------------------------


## Copy a picture into the drawing's own folder, so a drawing that is sent to somebody else still
## has its pictures. Returns `{ok, reason, path, name, info}` - the kept path, the name it was
## given, and what `sniff` read. A file that is not a picture is refused **before** anything is
## copied, so a folder of tracing aids cannot collect files the app cannot draw.
static func keep(source: String, wanted_name: String = "") -> Dictionary:
	var empty := {"ok": false, "reason": "", "path": "", "name": "", "info": {}}
	var info := sniff(source)
	if not bool(info.get("ok", false)):
		empty["reason"] = String(info.get("reason", ""))
		empty["info"] = info
		return empty
	if not ensure_dir():
		empty["reason"] = "the folder the drawing's own pictures live in could not be made"
		empty["info"] = info
		return empty
	var base := slug(wanted_name if not wanted_name.strip_edges().is_empty() else source.get_file().get_basename())
	var target := _free_path(base, extension_of(source))
	if DirAccess.copy_absolute(source, target) != OK:
		empty["reason"] = "%s could not be copied into the drawing's own folder" % source.get_file()
		empty["info"] = info
		return empty
	return {"ok": true, "reason": "", "path": target, "name": base, "info": info}


## A path in the drawing's folder that is not taken yet, so keeping two scans of the same room
## does not silently replace the first.
static func _free_path(base: String, extension: String) -> String:
	var suffix := ("." + extension) if not extension.is_empty() else ""
	var candidate := DIR.path_join(base + suffix)
	var number := 2
	while FileAccess.file_exists(candidate):
		candidate = DIR.path_join("%s-%d%s" % [base, number, suffix])
		number += 1
	return candidate


## The whole act: copy the picture in and build the record the drawing keeps. `at` is the centre
## on the ground, in world XZ metres, and `width_m` is how wide across the ground it lies.
## Returns `{ok, reason, record}`.
static func place(source: String, width_m: float, at: Vector2 = Vector2.ZERO,
		wanted_name: String = "") -> Dictionary:
	var kept := keep(source, wanted_name)
	if not bool(kept.get("ok", false)):
		return {"ok": false, "reason": String(kept.get("reason", "")), "record": {}}
	var record := from_kept(kept, width_m, at)
	if record.is_empty():
		return {"ok": false, "reason": "a picture has to be more than nothing across", "record": {}}
	return {"ok": true, "reason": "", "record": record}


## The record for a picture already kept. Returns an empty Dictionary when the width says nothing,
## which is the one number the record cannot invent: every other field is a fact about the file or
## a presentation choice, and this one is how big the site is.
static func from_kept(kept: Dictionary, width_m: float, at: Vector2 = Vector2.ZERO) -> Dictionary:
	var info: Dictionary = kept.get("info", {})
	if not bool(kept.get("ok", false)) or not is_finite(width_m) or width_m <= 0.0:
		return {}
	return {
		"id": 0,
		"name": String(kept.get("name", "picture")),
		"path": String(kept.get("path", "")),
		"format": String(info.get("format", "")),
		"width_px": int(info.get("width_px", 0)),
		"height_px": int(info.get("height_px", 0)),
		"x": at.x,
		"z": at.y,
		"width_m": width_m,
		"rotation_deg": 0.0,
		"opacity": DEFAULT_OPACITY,
		"visible": true,
	}


static func ensure_dir() -> bool:
	if DirAccess.dir_exists_absolute(DIR):
		return true
	return DirAccess.make_dir_recursive_absolute(DIR) == OK


## Every picture this app is keeping, wherever it is referred to from. For a report that can
## answer "what is taking up room in here", and for a test that has to leave nothing behind.
static func list() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(DIR)
	if dir == null:
		return out
	for file: String in dir.get_files():
		out.append(DIR.path_join(file))
	out.sort()
	return out


static func forget_all() -> int:
	var removed := 0
	for path: String in list():
		if DirAccess.remove_absolute(path) == OK:
			removed += 1
	return removed


# --- what the record is worth ---------------------------------------------------------


## The proportion of the picture: height over width. The one number carried from the pixels to
## the ground, because a picture is placed by how wide it lies and must keep its own shape.
static func aspect_of(record: Dictionary) -> float:
	var width_px := int(record.get("width_px", 0))
	if width_px <= 0:
		return 1.0
	return float(int(record.get("height_px", 0))) / float(width_px)


## How deep it lies on the ground, from the width and the picture's own proportion.
static func height_of(record: Dictionary) -> float:
	return float(record.get("width_m", 0.0)) * aspect_of(record)


## The four corners on the ground, in world XZ, in the picture's own order: top-left, top-right,
## bottom-right, bottom-left. **World +z is south**, the way the plan is drawn.
static func corners_of(record: Dictionary) -> PackedVector2Array:
	var half_width := float(record.get("width_m", 0.0)) * 0.5
	var half_height := height_of(record) * 0.5
	var centre := centre_of(record)
	var turn := deg_to_rad(float(record.get("rotation_deg", 0.0)))
	var out := PackedVector2Array()
	for corner: Vector2 in [
		Vector2(-half_width, -half_height),
		Vector2(half_width, -half_height),
		Vector2(half_width, half_height),
		Vector2(-half_width, half_height),
	]:
		out.append(centre + corner.rotated(turn))
	return out


static func centre_of(record: Dictionary) -> Vector2:
	return Vector2(float(record.get("x", 0.0)), float(record.get("z", 0.0)))


## The upright box the picture occupies, for fitting a view to everything on the drawing.
static func bounds_of(record: Dictionary) -> Rect2:
	var corners := corners_of(record)
	if corners.is_empty():
		return Rect2()
	var low := corners[0]
	var high := corners[0]
	for point: Vector2 in corners:
		low = low.min(point)
		high = high.max(point)
	return Rect2(low, high - low)


## Whether a point on the ground is under the picture - the test a click would use, kept here so
## the answer cannot differ between the plan and anything else that ever asks.
static func contains(record: Dictionary, point: Vector2) -> bool:
	var half_width := float(record.get("width_m", 0.0)) * 0.5
	var half_height := height_of(record) * 0.5
	var turn := deg_to_rad(float(record.get("rotation_deg", 0.0)))
	var local := (point - centre_of(record)).rotated(-turn)
	return absf(local.x) <= half_width and absf(local.y) <= half_height


# --- changing one --------------------------------------------------------------------


## How wide it lies across the ground. Every other size follows from this one and the picture's own
## proportion, so this is the only size there is to set.
static func set_width(record: Dictionary, width_m: float) -> bool:
	if not is_finite(width_m) or width_m <= 0.0:
		return false
	record["width_m"] = width_m
	return true


## A turn about the picture's own centre, in degrees. Kept in one revolution so a report and a
## file never disagree about which way round "370 degrees" is.
static func set_rotation(record: Dictionary, degrees: float) -> bool:
	if not is_finite(degrees):
		return false
	record["rotation_deg"] = wrapf(degrees, -180.0, 180.0)
	return true


## How see-through it is, clamped rather than refused: this is a knob, and a knob that refuses a
## value from its own slider is a knob nobody believes.
static func set_opacity(record: Dictionary, value: float) -> bool:
	if not is_finite(value):
		return false
	record["opacity"] = clampf(value, MIN_OPACITY, MAX_OPACITY)
	return true


static func move_to(record: Dictionary, x: float, z: float) -> bool:
	if not is_finite(x) or not is_finite(z):
		return false
	record["x"] = x
	record["z"] = z
	return true


static func move_by(record: Dictionary, dx: float, dz: float) -> bool:
	return move_to(record, float(record.get("x", 0.0)) + dx, float(record.get("z", 0.0)) + dz)


static func set_visible(record: Dictionary, on: bool) -> void:
	record["visible"] = on


# --- saying what it is ---------------------------------------------------------------


## What is wrong with the record, or "" when nothing is. **One function**, so the window, the
## controller and the plan cannot disagree about whether a picture can be drawn - the usual cause
## of a *not* drawable one is a file somebody has since moved or deleted.
static func describe_problem(record: Dictionary) -> String:
	if record.is_empty():
		return "no picture has been read"
	var path := String(record.get("path", ""))
	if path.is_empty():
		return "the picture has no file"
	if not FileAccess.file_exists(path):
		return "the picture's file is no longer at %s" % path
	if int(record.get("width_px", 0)) <= 0 or int(record.get("height_px", 0)) <= 0:
		return "the picture's size was never read"
	if float(record.get("width_m", 0.0)) <= 0.0:
		return "the picture has no width on the ground"
	return ""


static func is_usable(record: Dictionary) -> bool:
	return describe_problem(record).is_empty()


## The picture in words, for the status line and the report. A length in the drawing's own units,
## worded by the one function that words lengths, so an imperial drawing does not measure its
## underlay in metres.
static func describe(record: Dictionary, units: UnitsScript = null) -> String:
	var words: UnitsScript = UnitsScript.or_default(units)
	if record.is_empty():
		return "no picture"
	var pieces: Array[String] = [
		"%s, %s across" % [String(record.get("name", "picture")), words.format_length(float(record.get("width_m", 0.0)))],
	]
	var turn := float(record.get("rotation_deg", 0.0))
	if not is_zero_approx(turn):
		pieces.append("turned %s degrees" % String.num(turn, 1))
	if not bool(record.get("visible", true)):
		pieces.append("hidden")
	else:
		pieces.append("%d%% opaque" % int(round(float(record.get("opacity", 1.0)) * 100.0)))
	return ", ".join(PackedStringArray(pieces))


## Everything the window's report says about what was read: the file, the pixels, where the copy
## is, and anything wrong with it.
static func report_lines(record: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	if record.is_empty():
		lines.append("no picture has been read")
		return lines
	lines.append("%s - %s, %d x %d pixels" % [
		String(record.get("name", "picture")),
		String(record.get("format", "?")),
		int(record.get("width_px", 0)),
		int(record.get("height_px", 0)),
	])
	lines.append("copied into the drawing's own folder as %s" % String(record.get("path", "")))
	var problem := describe_problem(record)
	lines.append(problem if not problem.is_empty() else "ready to go under the drawing")
	return lines