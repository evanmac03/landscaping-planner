class_name DraftPdfWriter
extends RefCounted
## A minimal PDF writer: enough to plot a sheet.
##
## A page box, stroked vector geometry with line widths and dashes, and text in
## a standard font. Hand-written rather than taken as a dependency, because the
## whole point of the exporter is exactness: every coordinate comes from paper
## millimetres and nothing is rounded on the way through.
##
## The one part that must be right or the file simply will not open is the
## cross-reference table, whose entries are *byte offsets into the finished
## file*. They are taken from the bytes as they are emitted rather than computed
## from lengths that could drift, because an xref that is off by one byte is a
## file that some readers open and others reject.

## Exact: one point is 1/72 inch, and a millimetre is 25.4 mm to the inch.
const POINTS_PER_MM := 72.0 / 25.4

## Four decimals of a point is 0.35 micrometres, far below anything a printer can
## resolve. PDF also refuses exponent notation, which a fixed precision avoids.
## Godot trims trailing zeros but keeps one decimal, so 1.0 comes out as "1.0"
## rather than "1.0000"; that is a valid real to a PDF reader and smaller.
const DECIMALS := 4

var _content: PackedStringArray = PackedStringArray()
var _page_width: float = 595.276
var _page_height: float = 841.89
## The images placed on this page, in the order they were placed. Each entry is a
## name (`/Im1`) and the image itself; the object number is worked out at build time,
## because a page may place none, one, or several.
var _images: Array[Dictionary] = []


## Start a page. Geometry is in points, with the origin at the bottom-left, which
## is the PDF convention and the opposite of a screen.
func begin_page(width_points: float, height_points: float) -> void:
	_page_width = maxf(width_points, 1.0)
	_page_height = maxf(height_points, 1.0)
	_content = PackedStringArray()


func page_size() -> Vector2:
	return Vector2(_page_width, _page_height)


## The content stream, so a caller or a test can read the numbers back out.
func content() -> String:
	return "\n".join(_content)


func is_empty() -> bool:
	return _content.is_empty()


# --- graphics state -----------------------------------------------------------------


func save_state() -> void:
	_add("q")


func restore_state() -> void:
	_add("Q")


## Line width in points. Zero means the thinnest line the device can render,
## which is a hairline rather than nothing, so weights are never clamped here:
## that decision belongs to the pen table.
func set_line_width_points(width: float) -> void:
	_add("%s w" % _n(maxf(width, 0.0)))


func set_stroke_colour(colour: Color) -> void:
	_add("%s %s %s RG" % [_n(colour.r), _n(colour.g), _n(colour.b)])


func set_fill_colour(colour: Color) -> void:
	_add("%s %s %s rg" % [_n(colour.r), _n(colour.g), _n(colour.b)])


## The dash pattern in points: alternating on and off, starting on. An empty
## array is a solid line. Deliberately an untyped array, because every caller
## writes a literal `[]` for "solid" and a typed float array is not what a
## literal produces.
func set_dash(pattern_points: Array) -> void:
	if pattern_points.is_empty():
		_add("[] 0 d")
		return
	var parts := PackedStringArray()
	for length in pattern_points:
		parts.append(_n(maxf(float(length), 0.0)))
	_add("[%s] 0 d" % " ".join(parts))


# --- geometry -----------------------------------------------------------------------


func move_to(point: Vector2) -> void:
	_add("%s %s m" % [_n(point.x), _n(point.y)])


func line_to(point: Vector2) -> void:
	_add("%s %s l" % [_n(point.x), _n(point.y)])


func curve_to(control_one: Vector2, control_two: Vector2, end: Vector2) -> void:
	_add("%s %s %s %s %s %s c" % [
		_n(control_one.x), _n(control_one.y),
		_n(control_two.x), _n(control_two.y),
		_n(end.x), _n(end.y),
	])


func close_path() -> void:
	_add("h")


func rectangle(rect: Rect2) -> void:
	_add("%s %s %s %s re" % [
		_n(rect.position.x), _n(rect.position.y),
		_n(rect.size.x), _n(rect.size.y),
	])


func stroke() -> void:
	_add("S")


func fill() -> void:
	_add("f")


# --- images -------------------------------------------------------------------------


## Place a raster image to fill `rect`, in points. Returns the XObject name it was
## registered under, or "" when there is nothing to place.
##
## The image's own unit square is mapped straight onto the rectangle by the `cm`
## matrix (`width 0 0 height x y cm`), so the caller says where the picture goes and
## never touches a pixel. A PDF image is drawn with its first row at the top of that
## square, which is how `Image.get_data()` lays its rows out, so nothing is flipped.
##
## Written raw (RGB8) and deflated rather than as a PNG, because a PNG is a file and
## what a PDF wants is a stream of samples: `PackedByteArray.compress` gives exactly
## the zlib stream `/FlateDecode` expects.
func place_image(image: Image, rect: Rect2) -> String:
	if image == null or image.is_empty():
		return ""
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return ""
	var name := "/Im%d" % (_images.size() + 1)
	_images.append({"name": name, "image": image})
	_add("q %s 0 0 %s %s %s cm %s Do Q" % [
		_n(rect.size.x), _n(rect.size.y),
		_n(rect.position.x), _n(rect.position.y), name,
	])
	return name


## The images placed on this page, in order, for a caller or a test to read back.
func images() -> Array[Dictionary]:
	return _images


# --- text ---------------------------------------------------------------------------


## Text at a baseline position, in points, in the standard sans font. The font is
## one of the fourteen every reader is required to have, so nothing is embedded
## and the file stays tiny.
func draw_text(at: Vector2, text: String, size_points: float) -> void:
	if text.is_empty():
		return
	_add("BT /F1 %s Tf %s %s Td (%s) Tj ET" % [
		_n(maxf(size_points, 0.1)), _n(at.x), _n(at.y), _escape(text),
	])


## Text run along a baseline at an angle, in radians, which is what a dimension
## set against a sloping line needs. The text matrix carries the rotation, so the
## position is still the baseline origin rather than a bounding box corner.
func draw_text_rotated(at: Vector2, text: String, size_points: float, angle: float) -> void:
	if text.is_empty():
		return
	if absf(sin(angle)) < 1e-9 and cos(angle) > 0.0:
		draw_text(at, text, size_points)
		return
	_add("BT /F1 %s Tf %s %s %s %s %s %s Tm (%s) Tj ET" % [
		_n(maxf(size_points, 0.1)),
		_n(cos(angle)), _n(sin(angle)), _n(-sin(angle)), _n(cos(angle)),
		_n(at.x), _n(at.y), _escape(text),
	])


## The text every glyph is required to fit, in points, so a caller can centre or
## right-align without guessing. Helvetica's average is close enough for a label
## and the exact metrics need the font program, which is not embedded.
func text_width(text: String, size_points: float) -> float:
	return float(text.length()) * size_points * 0.5


# --- assembly -----------------------------------------------------------------------


func build() -> PackedByteArray:
	# Object numbers are fixed for the five things every page has, so a file with no
	# image is byte-for-byte the file this writer has always made. An image takes the
	# next number, and the page's resource dictionary names it.
	var resources := "/Resources << /Font << /F1 5 0 R >>"
	if not _images.is_empty():
		var refs := PackedStringArray()
		for index in _images.size():
			refs.append("%s %d 0 R" % [_images[index]["name"], 6 + index])
		resources += " /XObject << %s >>" % " ".join(refs)
	resources += " >>"
	var page := "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 %s %s] %s /Contents 4 0 R >>" % [
		_n(_page_width), _n(_page_height), resources,
	]

	var stream := content()
	var bodies: Array[PackedByteArray] = [
		_bytes("<< /Type /Catalog /Pages 2 0 R >>"),
		_bytes("<< /Type /Pages /Kids [3 0 R] /Count 1 >>"),
		_bytes(page),
		_bytes("<< /Length %d >>\nstream\n%s\nendstream" % [stream.to_utf8_buffer().size(), stream]),
		_bytes("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>"),
	]
	for entry: Dictionary in _images:
		bodies.append(image_object(entry["image"]))

	var out := PackedByteArray()
	_append(out, "%PDF-1.4\n")
	var offsets: Array[int] = []
	for index in bodies.size():
		offsets.append(out.size())
		_append(out, "%d 0 obj\n" % (index + 1))
		out.append_array(bodies[index])
		_append(out, "\nendobj\n")

	var xref_offset := out.size()
	_append(out, "xref\n0 %d\n" % (bodies.size() + 1))
	# The free entry for object zero, which is always exactly this.
	_append(out, "0000000000 65535 f \n")
	for offset: int in offsets:
		# Twenty bytes per entry, and the trailing space before the newline is
		# part of the specification rather than tidiness.
		_append(out, "%010d 00000 n \n" % offset)
	_append(out, "trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n" % [
		bodies.size() + 1, xref_offset,
	])
	return out


# --- helpers ------------------------------------------------------------------------


func _add(operator: String) -> void:
	_content.append(operator)


func _n(value: float) -> String:
	if not is_finite(value):
		value = 0.0
	return String.num(value, DECIMALS)


## A PDF literal string escapes its delimiters and its own escape character, and
## has no way to carry a byte above 126 except as an octal escape.
func _escape(text: String) -> String:
	var out := ""
	for index in text.length():
		var code := text.unicode_at(index)
		if code == 0x5C:
			out += "\\\\"
		elif code == 0x28:
			out += "\\("
		elif code == 0x29:
			out += "\\)"
		elif code < 32 or code > 126:
			if code <= 255:
				out += "\\%03o" % code
			else:
				out += "?"
		else:
			out += text[index]
	return out


func _append(buffer: PackedByteArray, text: String) -> void:
	buffer.append_array(text.to_utf8_buffer())


static func _bytes(text: String) -> PackedByteArray:
	return text.to_utf8_buffer()


## One image XObject: the samples, deflated, in a stream.
##
## Public and static so a test can read the object back without building a whole
## file's worth of offsets to find it. Raw RGB8 and zlib, which is what
## `/DeviceRGB` and `/FlateDecode` name; nothing here guesses at a colour space
## other than the one this project's images arrive in.
static func image_object(image: Image) -> PackedByteArray:
	var source := image
	if source.get_format() != Image.FORMAT_RGB8:
		# A copy converted rather than the same bytes relabelled, because rebuilding
		# an image from another format's data reinterprets every channel.
		source = Image.new()
		source.copy_from(image)
		source.convert(Image.FORMAT_RGB8)
	var deflated: PackedByteArray = source.get_data().compress(FileAccess.COMPRESSION_DEFLATE)
	var out := _bytes(
		"<< /Type /XObject /Subtype /Image /Width %d /Height %d /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /FlateDecode /Length %d >>\nstream\n" % [
			source.get_width(), source.get_height(), deflated.size(),
		]
	)
	out.append_array(deflated)
	out.append_array(_bytes("\nendstream"))
	return out