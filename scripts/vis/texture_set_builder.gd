class_name TextureSetBuilder
extends RefCounted
## Derives the `normal` and `orm` maps of a texture set from its albedo (§5.1).
##
## A texture set is three images, and only the first one has to be drawn. The other two
## are **measurements of the first**, which is the whole reason to derive them:
##
## * the **normal map** is the albedo's luminance read as a height field. For paving that
##   is exactly right — the joints are the dark gaps, so they become the grooves, with no
##   licence to keep track of; and for mulch it turns a photograph of chips into chips
##   that catch the light.
## * the **ORM map** is Godot's packing: occlusion in R, roughness in G, metallic in B. Its
##   occlusion is the albedo's own darkness, gently compressed, so a crevice that is dark
##   is also a crevice that receives less sky.
##
## A derived map cannot disagree with the picture it is derived from, which is the point.
## A bought normal map for an unbought albedo is a normal map of a different surface.
##
## The generation is a script in the repository rather than a step somebody ran once: the
## sets can be re-derived at a different resolution or a different strength, and
## `write_sets()` is exactly what made the files in `resources/textures/hardscape/`.

## How hard a luminance step tilts the surface. High enough that a paving joint reads as
## a groove, low enough that the speckle in a granite tile does not read as gravel.
const NORMAL_STRENGTH := 2.2
## How much of the albedo's darkness becomes occlusion. A little: an ORM map that doubles
## every shadow already in the picture makes a paving joint look like a trench.
const AMBIENT_OCCLUSION := 0.35
## Quantisation of a luminance byte, so the height field is the *image's* tones rather
## than a continuous surface invented on top of them.
const LEVELS := 255.0

const DEFAULT_DIR := "res://resources/textures/hardscape/"


## A normal map for an albedo, as an RGB8 image.
##
## Sampling wraps, so a seamless albedo makes a seamless normal map: a map derived from
## a tiling image with clamped edges gets a one-pixel seam at the border, and a seam on a
## tiled patio is a line that runs the whole length of it.
static func normal_from(albedo: Image, strength: float = NORMAL_STRENGTH) -> Image:
	if albedo == null:
		push_error("TextureSetBuilder.normal_from: no albedo")
		return null
	var width := albedo.get_width()
	var height := albedo.get_height()
	var source := albedo.get_data()
	var channels := _channels(albedo)
	var data := PackedByteArray()
	data.resize(width * height * 3)
	for y in height:
		for x in width:
			# Central difference: the step across the pixel, not from it, so a single
			# bright texel does not tilt its whole neighbourhood.
			var dx: float = _height(source, channels, width, height, x + 1, y) \
				- _height(source, channels, width, height, x - 1, y)
			var dy: float = _height(source, channels, width, height, x, y + 1) \
				- _height(source, channels, width, height, x, y - 1)
			# The green channel is negated because the image's y axis runs *down* and
			# Godot reads a normal map's green as up.
			var normal := Vector3(-dx * strength, dy * strength, 1.0).normalized()
			var at := (y * width + x) * 3
			data[at] = _byte(normal.x * 0.5 + 0.5)
			data[at + 1] = _byte(normal.y * 0.5 + 0.5)
			data[at + 2] = _byte(normal.z * 0.5 + 0.5)
	return Image.create_from_data(width, height, false, Image.FORMAT_RGB8, data)


## An ORM map for an albedo, as an RGB8 image: occlusion, roughness, metallic.
static func orm_from(albedo: Image, ambient: float = AMBIENT_OCCLUSION) -> Image:
	if albedo == null:
		push_error("TextureSetBuilder.orm_from: no albedo")
		return null
	var width := albedo.get_width()
	var height := albedo.get_height()
	var source := albedo.get_data()
	var channels := _channels(albedo)
	var data := PackedByteArray()
	data.resize(width * height * 3)
	for y in height:
		for x in width:
			var lum := _height(source, channels, width, height, x, y)
			# A dark texel is a crevice, so it receives less sky. The whole range is
			# compressed toward white: the albedo's contrast is already in the picture.
			var occlusion := 1.0 - ambient * (1.0 - lum)
			var at := (y * width + x) * 3
			data[at] = _byte(occlusion)
			# Full roughness and no metalness: the set's own `roughness` multiplies this
			# channel, and a paving that is partly shiny is a paving that is wet.
			data[at + 1] = 255
			data[at + 2] = 0
	return Image.create_from_data(width, height, false, Image.FORMAT_RGB8, data)


## Writes the normal and ORM maps for one set, reading its albedo from disk.
##
## Returns the two project paths it wrote, so a caller can report what it did rather
## than assume it worked. An empty array means the albedo was not there.
static func write_set(set_name: String, directory: String = DEFAULT_DIR) -> Array[String]:
	var out: Array[String] = []
	var albedo_path := directory + set_name + "_albedo.png"
	if not FileAccess.file_exists(albedo_path):
		push_error("TextureSetBuilder.write_set: no albedo at %s" % albedo_path)
		return out
	var albedo := Image.load_from_file(albedo_path)
	if albedo == null:
		push_error("TextureSetBuilder.write_set: %s is not an image" % albedo_path)
		return out
	albedo.convert(Image.FORMAT_RGB8)
	for pair: Array in [
		["normal", normal_from(albedo)],
		["orm", orm_from(albedo)],
	]:
		var image: Image = pair[1]
		if image == null:
			continue
		var path := directory + set_name + "_" + String(pair[0]) + ".png"
		var error := image.save_png(path)
		if error != OK:
			push_error("TextureSetBuilder.write_set: could not write %s (%d)" % [path, error])
			continue
		out.append(path)
	return out


## Writes every set in the hardscape catalog. Returns what it wrote, for a report.
static func write_sets(catalog, directory: String = DEFAULT_DIR) -> Array[String]:
	var out: Array[String] = []
	for set_name: String in catalog.set_names():
		out.append_array(write_set(set_name, directory))
	return out


## Whether a normal map actually carries a surface: a flat map is one uniform colour, and
## a set whose normal map is flat is a set whose relief does nothing.
##
## **Every byte is read, not a grid of samples** — which looks like overkill for a
## question a 7-pixel grid answers. It is not: a grid steps over exactly the thing being
## looked for. A map derived from an albedo that is flat everywhere except one seam is a
## map whose every *sampled* texel is the same colour and whose seam is real, and the
## first version of this function reported it as flat. The still exporter's blank-render
## guard was written the same way for the same reason; this is the second time in this
## project that a sample stood in for the whole picture and got the answer wrong.
static func looks_flat(image: Image) -> bool:
	if image == null or image.get_width() < 2 or image.get_height() < 2:
		return true
	var data := image.get_data()
	if data.size() < 8:
		return true
	var first_red := data[0]
	var first_green := data[1]
	var first_blue := data[2]
	for at in range(0, data.size() - 2, 3):
		if data[at] != first_red or data[at + 1] != first_green or data[at + 2] != first_blue:
			return false
	return true


static func _channels(image: Image) -> int:
	match image.get_format():
		Image.FORMAT_RGB8:
			return 3
		Image.FORMAT_RGBA8:
			return 4
		_:
			# Anything else is converted by the caller; three is the format the byte
			# reader below assumes and the one every albedo here is stored in.
			return 3


## The luminance at a texel, wrapping at the edges so the derivation tiles.
static func _height(
	source: PackedByteArray, channels: int, width: int, height: int, x: int, y: int
) -> float:
	var at := (wrapi(y, 0, height) * width + wrapi(x, 0, width)) * channels
	return (0.2126 * source[at] + 0.7152 * source[at + 1] + 0.0722 * source[at + 2]) / LEVELS


## A byte from a 0..1 value, rounded rather than truncated.
##
## Rounded because a truncated encode is biased: every value lands a whole level low, and
## a level surface encodes as 127 rather than the 128 that means "this way out". On a
## normal map that bias is a whole surface leaning the same way.
static func _byte(value: float) -> int:
	return roundi(clampf(value, 0.0, 1.0) * LEVELS)