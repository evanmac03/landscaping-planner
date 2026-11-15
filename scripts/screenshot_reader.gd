class_name ScreenshotReader
extends RefCounted
## A picture of the screen read as numbers, for the questions rectangles cannot answer.
##
## Every other instrument here reads a node: a control's rectangle, a page's position, the strip a page is held
## below. Those are all *statements* by the program about itself, and twice now a fault has lived exactly where
## no statement existed - a page's title bar is drawn by Godot above the rectangle the page reports, and a phone
## draws that bar taller than the theme says it is. The only thing that knows what is actually on the glass is
## the glass, so this reads the framebuffer: the rows each colour runs down, and any region handed back doubled
## so a person can look at it.
##
## Two measurements, and they are the two a driver actually needs. `bands_down` walks one column and says where
## each colour starts and ends, which is how a bar's drawn height is found without asking anyone. `doubled`
## blows a small region up so that two title bars standing in the same rows - words drawn over words - are
## legible to a person reading the picture, which is the only way that fault was ever settled.
##
## Nothing here decides anything. It takes an `Image` and gives back rows and colours, and the file helpers
## around it are only there so a caller does not have to remember which of Godot's fifty `Image` statics it
## wanted; a picture that is not there, a column outside it, or a region that runs off it are answered with
## nothing or with what there is, never with an error.


## One run of one colour down a column: `from` and `to` are inclusive rows, so a band from 193 to 228 is 36
## pixels of glass - which is the arithmetic every reader of this wants and is easy to get wrong by one.
static func _band(from: int, to: int, colour: Color) -> Dictionary:
	return { "from": from, "to": to, "colour": colour }


## Every run of one colour down column `x`, top to bottom. A column outside the picture, or no picture at all,
## is answered with nothing: a caller that asked about a column that is not there has nothing to report.
static func bands_down(image: Image, x: int) -> Array[Dictionary]:
	var bands: Array[Dictionary] = []
	if image == null or x < 0 or x >= image.get_width():
		return bands
	var from := 0
	var colour: Color = image.get_pixel(x, 0)
	for y in range(1, image.get_height()):
		var here: Color = image.get_pixel(x, y)
		if here == colour:
			continue
		bands.append(_band(from, y - 1, colour))
		from = y
		colour = here
	bands.append(_band(from, image.get_height() - 1, colour))
	return bands


## The whole run of the colour at `(x, y)`, however far it reaches up and down. This is how a page's title bar
## is measured on the glass: ask for the row just above the page's own top edge at its centre column, and the
## band that comes back is the bar as it was drawn - the theme's own answer and the drawn one are allowed to
## disagree, and on a phone they do.
static func band_containing(image: Image, x: int, y: int) -> Dictionary:
	if image == null or x < 0 or x >= image.get_width() or y < 0 or y >= image.get_height():
		return { }
	var colour: Color = image.get_pixel(x, y)
	var top := y
	while top > 0 and image.get_pixel(x, top - 1) == colour:
		top -= 1
	var bottom := y
	while bottom < image.get_height() - 1 and image.get_pixel(x, bottom + 1) == colour:
		bottom += 1
	return _band(top, bottom, colour)


## How many rows a band covers. Stated here rather than left to the caller, because "193 to 228 is 36" is the
## off-by-one every reader of a band has to get right exactly once.
static func rows(band: Dictionary) -> int:
	if band.is_empty():
		return 0
	return int(band["to"]) - int(band["from"]) + 1


## A band as a person reads it: where it runs, how tall it is, and its colour.
static func sentence(band: Dictionary) -> String:
	if band.is_empty():
		return "nothing to read"
	return "rows %d..%d (%d px) of %s" % [
		int(band["from"]),
		int(band["to"]),
		rows(band),
		(band["colour"] as Color).to_html(false),
	]


## One region of the picture, twice as big, with each pixel kept square. `RESIZE_NEAREST` is the whole point:
## a smooth enlargement invents colours between two neighbouring pixels and a driver reading a letter off the
## result is reading the enlargement's guess. A region that runs off the picture is clamped to what is there.
static func doubled(image: Image, region: Rect2i) -> Image:
	if image == null:
		return null
	var inside := region.intersection(Rect2i(0, 0, image.get_width(), image.get_height()))
	if inside.size.x <= 0 or inside.size.y <= 0:
		return null
	var cut: Image = image.get_region(inside)
	cut.resize(inside.size.x * 2, inside.size.y * 2, Image.INTERPOLATE_NEAREST)
	return cut


## A rectangle marked on the picture as an outline, in the colour given, `thickness` pixels wide - so that a
## rectangle a program *claims* can be looked at against the pixels it is standing on, in one picture.
##
## Clamped to the picture, because a rectangle reaching past the edge has no pixel out there and asking an `Image`
## for one is an error rather than a drawing; a rectangle wholly off it is nothing to draw. Blended, so what is
## underneath is still read through the mark - **the colour's own alpha is how much of it is laid on**, so an opaque
## colour hides what it marks. A thickness as wide as the rectangle is tall fills it, which is how a dot at a centre
## is drawn without a second painter.
static func outline(image: Image, rect: Rect2i, colour: Color, thickness: int) -> void:
	if image == null or thickness <= 0:
		return
	var inside := rect.intersection(Rect2i(0, 0, image.get_width(), image.get_height()))
	if inside.size.x <= 0 or inside.size.y <= 0:
		return
	for y: int in range(inside.position.y, inside.position.y + inside.size.y):
		for x: int in range(inside.position.x, inside.position.x + inside.size.x):
			# How far this pixel is from the nearest edge of the rectangle: a pixel whose nearest edge is further
			# than the thickness is inside it, and the outline is everything else.
			var along: int = mini(x - inside.position.x, inside.position.x + inside.size.x - 1 - x)
			var down: int = mini(y - inside.position.y, inside.position.y + inside.size.y - 1 - y)
			if mini(along, down) >= thickness:
				continue
			image.set_pixel(x, y, image.get_pixel(x, y).blend(colour))


## A picture from a file, or nothing when there is no file there or it is not a picture this can read.
##
## Read as **bytes rather than as a file**, which is the difference between a Python script's picture and one a
## program is allowed to open: `Image.load_from_file` prints a warning saying so - "this will not work on export" -
## every time it is called, and the PNGs a tool pulls off a phone are never imported resources. Whatever came out of
## a `screencap` or a `save_png` is a PNG, so the buffer is read as one and a file that is not is answered with
## nothing rather than with a picture of nonsense.
static func read(path: String) -> Image:
	if not FileAccess.file_exists(path):
		return null
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return null
	var image := Image.new()
	if image.load_png_from_buffer(bytes) != OK:
		return null
	return image


## A picture written to a file, through a temporary file and a rename, so a write that fails never leaves a
## half-written picture where a good one was. Returns OK, or the error that stopped it.
static func write(image: Image, to: String) -> Error:
	if image == null:
		return ERR_INVALID_PARAMETER
	var temporary := to + ".writing"
	var failed: Error = image.save_png(temporary)
	if failed != OK:
		return failed
	return DirAccess.rename_absolute(temporary, to)
