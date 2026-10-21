extends Node
## A picture under the drawing: the module that reads one, keeps a copy of it and describes where
## it lies.
##
## Everything here is the module alone - no controller, no scene, no window. What is tested is what
## the module promises: that it reads a picture's *header* rather than decoding it, that it refuses
## a file that is not a picture before it copies anything, that a picture keeps its own proportion
## when it is given a width on the ground, and that the record it builds survives a save and a load.
##
## Every test clears the folder of anything named `test-` before it starts and again when it ends. A
## test that throws part-way through must not leave a copy of a test scan in the app for the next
## person to find, and a copy left behind by one test must not be the reason the next one fails. The
## sweep is deliberately narrow - it never touches a picture somebody actually kept.

const RasterUnderlayScript := preload("res://scripts/draft/raster_underlay.gd")
const UnitsScript := preload("res://scripts/draft/units.gd")

const PREFIX := "test-"


# --- helpers --------------------------------------------------------------------------


## An image of a given size, so the header has something real to say. Filled rather than blank so a
## decoder cannot mistake it for a corrupt file.
func _image(width: int, height: int) -> Image:
	var image := Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.3, 0.5, 0.8, 1.0))
	image.set_pixel(0, 0, Color(1.0, 0.0, 0.0, 1.0))
	return image


## A picture on disk, under a name this file owns. Returns the path.
func _source(name: String, extension: String, width: int = 64, height: int = 32) -> String:
	RasterUnderlayScript.ensure_dir()
	var path := RasterUnderlayScript.DIR.path_join(PREFIX + name + "." + extension)
	var image := _image(width, height)
	match extension:
		"png":
			image.save_png(path)
		"jpg":
			image.save_jpg(path, 0.9)
		"webp":
			image.save_webp(path, false)
		_:
			var file := FileAccess.open(path, FileAccess.WRITE)
			if file != null:
				file.store_buffer(PackedByteArray())
				file.close()
	return path


func _text_file(name: String, text: String) -> String:
	RasterUnderlayScript.ensure_dir()
	var path := RasterUnderlayScript.DIR.path_join(PREFIX + name)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(text)
		file.close()
	return path


func _bytes_file(name: String, bytes: PackedByteArray) -> String:
	RasterUnderlayScript.ensure_dir()
	var path := RasterUnderlayScript.DIR.path_join(PREFIX + name)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_buffer(bytes)
		file.close()
	return path


func _put_u32_le(bytes: PackedByteArray, at: int, value: int) -> void:
	bytes[at] = value & 0xFF
	bytes[at + 1] = (value >> 8) & 0xFF
	bytes[at + 2] = (value >> 16) & 0xFF
	bytes[at + 3] = (value >> 24) & 0xFF


func _put_ascii(bytes: PackedByteArray, at: int, text: String) -> void:
	for index in text.length():
		bytes[at + index] = text.unicode_at(index)


## A BMP header with no pixels after it. A hand-built one on purpose: this engine can write a PNG,
## a JPEG and a WebP but not a BMP, and the reader's job is the header either way.
func _bmp_header(width: int, height: int) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(54)
	_put_ascii(bytes, 0, "BM")
	_put_u32_le(bytes, 2, 54)
	_put_u32_le(bytes, 10, 54)
	_put_u32_le(bytes, 14, 40)
	_put_u32_le(bytes, 18, width)
	_put_u32_le(bytes, 22, height)
	return bytes


## A WebP extended-container header, 1024 by 768. The container states its canvas one smaller than it
## is, in 24 bits, which is the detail worth having a test on.
func _webp_vp8x_header(width: int, height: int) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(34)
	_put_ascii(bytes, 0, "RIFF")
	_put_u32_le(bytes, 4, 26)
	_put_ascii(bytes, 8, "WEBP")
	_put_ascii(bytes, 12, "VP8X")
	_put_u32_le(bytes, 16, 10)
	_put_u32_le(bytes, 24, width - 1)
	_put_u32_le(bytes, 27, height - 1)
	return bytes


## Every kept picture this file made, so a test can say what it started with and what it must end
## with. Narrow on purpose: a picture a person actually kept is not this file's to remove.
func _mine() -> Array[String]:
	var out: Array[String] = []
	for path: String in RasterUnderlayScript.list():
		if path.get_file().begins_with(PREFIX):
			out.append(path)
	return out


func _clean() -> void:
	for path: String in _mine():
		DirAccess.remove_absolute(path)


func _record(width_m: float = 10.0, name: String = "png") -> Dictionary:
	var kept: Dictionary = RasterUnderlayScript.keep(_source(name, "png"), PREFIX + name)
	assert(bool(kept["ok"]), String(kept["reason"]))
	return RasterUnderlayScript.from_kept(kept, width_m)


# --- what kind of file is this ---------------------------------------------------------


func test_a_file_is_judged_by_its_extension_before_anything_is_read() -> void:
	_clean()
	assert(RasterUnderlayScript.is_image("C:/scans/site-plan.PNG"), "case does not matter")
	assert(RasterUnderlayScript.is_image("a/b/c.jpeg"), "jpeg is a png's sibling")
	assert(not RasterUnderlayScript.is_image("plan.dxf"), "a DXF is what the DXF reader is for")
	assert(not RasterUnderlayScript.is_image("site-plan"), "no extension is no claim")
	assert(RasterUnderlayScript.extension_of("site.plan.png") == "png", RasterUnderlayScript.extension_of("site.plan.png"))
	assert(RasterUnderlayScript.extension_of("no-extension") == "", "and no extension reads as none")
	var filter := RasterUnderlayScript.dialog_filter()
	assert(filter.ends_with(" ; Pictures"), filter)
	assert(filter.contains("*.png") and filter.contains("*.webp"), filter)
	assert(RasterUnderlayScript.formats_text() == "PNG, JPEG, WebP or BMP", RasterUnderlayScript.formats_text())
	_clean()


func test_a_name_is_boiled_down_to_something_a_file_system_keeps() -> void:
	_clean()
	assert(RasterUnderlayScript.slug("Backyard Scan (2024).png") == "backyard-scan-2024-png", RasterUnderlayScript.slug("Backyard Scan (2024).png"))
	assert(RasterUnderlayScript.slug("site_plan--north") == "site-plan-north", RasterUnderlayScript.slug("site_plan--north"))
	assert(RasterUnderlayScript.slug("   ") == "picture", "a name of nothing still needs a name")
	assert(RasterUnderlayScript.slug("///") == "picture", "separators alone are nothing")
	var long := RasterUnderlayScript.slug("a".repeat(200))
	assert(long.length() == RasterUnderlayScript.NAME_LIMIT, str(long.length()))
	_clean()


# --- reading the header ----------------------------------------------------------------


func test_a_pictures_size_is_read_from_its_header_and_not_by_decoding_it() -> void:
	_clean()
	var info: Dictionary = RasterUnderlayScript.sniff(_source("png", "png", 64, 32))
	assert(bool(info["ok"]), String(info["reason"]))
	assert(String(info["format"]) == "PNG", String(info["format"]))
	assert(int(info["width_px"]) == 64, str(info["width_px"]))
	assert(int(info["height_px"]) == 32, str(info["height_px"]))
	_clean()


func test_every_format_in_the_list_states_its_own_size() -> void:
	_clean()
	var jpeg: Dictionary = RasterUnderlayScript.sniff(_source("jpg", "jpg", 80, 20))
	assert(bool(jpeg["ok"]), String(jpeg["reason"]))
	assert(String(jpeg["format"]) == "JPEG", String(jpeg["format"]))
	assert(int(jpeg["width_px"]) == 80 and int(jpeg["height_px"]) == 20, str(jpeg))
	var webp: Dictionary = RasterUnderlayScript.sniff(_source("webp", "webp", 48, 24))
	assert(bool(webp["ok"]), String(webp["reason"]))
	assert(int(webp["width_px"]) == 48 and int(webp["height_px"]) == 24, str(webp))
	var bmp: Dictionary = RasterUnderlayScript.sniff(_bytes_file("bmp.bmp", _bmp_header(800, 600)))
	assert(bool(bmp["ok"]), String(bmp["reason"]))
	assert(String(bmp["format"]) == "BMP", String(bmp["format"]))
	assert(int(bmp["width_px"]) == 800 and int(bmp["height_px"]) == 600, str(bmp))
	var extended: Dictionary = RasterUnderlayScript.sniff(
		_bytes_file("vp8x.webp", _webp_vp8x_header(1024, 768))
	)
	assert(bool(extended["ok"]), String(extended["reason"]))
	assert(String(extended["format"]) == "WebP", String(extended["format"]))
	assert(int(extended["width_px"]) == 1024 and int(extended["height_px"]) == 768, str(extended))
	_clean()


func test_a_file_that_is_not_a_picture_is_refused_and_told_so() -> void:
	_clean()
	var missing: Dictionary = RasterUnderlayScript.sniff(RasterUnderlayScript.DIR.path_join("test-nowhere.png"))
	assert(not bool(missing["ok"]), "a file that is not there is not read")
	assert(String(missing["reason"]).contains("no file at"), String(missing["reason"]))
	var empty: Dictionary = RasterUnderlayScript.sniff(_bytes_file("empty.png", PackedByteArray()))
	assert(not bool(empty["ok"]), "a file of no bytes has no header")
	assert(String(empty["reason"]).contains("too short"), String(empty["reason"]))
	var text: Dictionary = RasterUnderlayScript.sniff(
		_text_file("lied.png", "this is a text file wearing a png extension, and it is long enough")
	)
	assert(not bool(text["ok"]), "a text file renamed is still a text file")
	assert(String(text["reason"]).contains("is not a picture this can read"), String(text["reason"]))
	assert(String(text["reason"]).contains("PNG"), "and it names what can be read: " + String(text["reason"]))
	assert(String(RasterUnderlayScript.sniff("").get("reason", "")) == "no file was named", "and nothing named is its own answer")
	_clean()


# --- taking one on ---------------------------------------------------------------------


func test_keeping_a_picture_copies_it_into_the_drawings_own_folder() -> void:
	_clean()
	var source := _source("scan", "png", 64, 32)
	var kept: Dictionary = RasterUnderlayScript.keep(source, PREFIX + "sunny-bed")
	assert(bool(kept["ok"]), String(kept["reason"]))
	var path := String(kept["path"])
	assert(path == RasterUnderlayScript.DIR.path_join(PREFIX + "sunny-bed.png"), path)
	assert(FileAccess.file_exists(path), "the copy is on disk")
	assert(
		FileAccess.get_file_as_bytes(path) == FileAccess.get_file_as_bytes(source),
		"and it is the picture, byte for byte"
	)
	assert(String(kept["name"]) == PREFIX + "sunny-bed", String(kept["name"]))
	_clean()


func test_two_pictures_of_the_same_name_do_not_replace_each_other() -> void:
	_clean()
	var source := _source("again", "png")
	var first: Dictionary = RasterUnderlayScript.keep(source, PREFIX + "same")
	var second: Dictionary = RasterUnderlayScript.keep(source, PREFIX + "same")
	assert(bool(first["ok"]) and bool(second["ok"]), "both are kept")
	assert(String(first["path"]) != String(second["path"]), "the second does not write over the first")
	assert(String(second["path"]).contains("-2"), String(second["path"]))
	assert(FileAccess.file_exists(String(first["path"])), "and the first is still there")
	var copies := 0
	for path: String in _mine():
		if path.get_file().begins_with(PREFIX + "same"):
			copies += 1
	assert(copies == 2, str(copies))
	_clean()


func test_a_file_that_is_not_a_picture_is_refused_before_anything_is_copied() -> void:
	_clean()
	var kept: Dictionary = RasterUnderlayScript.keep(
		_text_file("not-a-picture.txt", "a notes file somebody picked by mistake, long enough to read"),
		PREFIX + "hopeful"
	)
	assert(not bool(kept["ok"]), "a notes file is not a picture")
	assert(String(kept["reason"]).contains("is not a picture this can read"), String(kept["reason"]))
	for path: String in _mine():
		assert(
			not path.get_file().begins_with(PREFIX + "hopeful"),
			"and nothing reached the drawing's own folder: " + path
		)
	_clean()


func test_a_picture_given_a_width_keeps_its_own_proportion() -> void:
	_clean()
	var wide := _record(20.0, "wide")
	assert(float(wide["width_m"]) == 20.0, str(wide["width_m"]))
	assert(is_equal_approx(RasterUnderlayScript.aspect_of(wide), 0.5), str(RasterUnderlayScript.aspect_of(wide)))
	assert(is_equal_approx(RasterUnderlayScript.height_of(wide), 10.0), str(RasterUnderlayScript.height_of(wide)))
	assert(float(wide["opacity"]) == RasterUnderlayScript.DEFAULT_OPACITY, str(wide["opacity"]))
	assert(bool(wide["visible"]), "and it goes on visible")
	assert(int(wide["width_px"]) == 64 and int(wide["height_px"]) == 32, str(wide))
	assert(String(wide["format"]) == "PNG", String(wide["format"]))
	assert(RasterUnderlayScript.is_usable(wide), RasterUnderlayScript.describe_problem(wide))
	_clean()


func test_a_width_of_nothing_is_refused_rather_than_guessed_at() -> void:
	_clean()
	var record := _record(10.0, "nothing-across")
	assert(not RasterUnderlayScript.set_width(record, 0.0), "a picture of no width is not a picture")
	assert(not RasterUnderlayScript.set_width(record, -5.0), "and neither is a negative one")
	assert(not RasterUnderlayScript.set_width(record, NAN), "nor one that is not a number")
	assert(is_equal_approx(float(record["width_m"]), 10.0), "so the width it had stands")
	var refused: Dictionary = RasterUnderlayScript.place(_source("zero", "png"), 0.0)
	assert(not bool(refused["ok"]), "and taking one on at no width is refused")
	assert(String(refused["reason"]) == "a picture has to be more than nothing across", String(refused["reason"]))
	_clean()


func test_a_turn_is_kept_within_one_revolution() -> void:
	_clean()
	var record := _record(10.0, "turned")
	assert(RasterUnderlayScript.set_rotation(record, 370.0), "a turn of 370 is a turn")
	assert(is_equal_approx(float(record["rotation_deg"]), 10.0), str(record["rotation_deg"]))
	assert(RasterUnderlayScript.set_rotation(record, -370.0), "and so is -370")
	assert(is_equal_approx(float(record["rotation_deg"]), -10.0), str(record["rotation_deg"]))
	assert(not RasterUnderlayScript.set_rotation(record, NAN), "but a turn that is not a number is not a turn")
	_clean()


func test_where_it_lies_on_the_ground() -> void:
	_clean()
	var record := _record(10.0, "corners")
	assert(RasterUnderlayScript.move_to(record, 4.0, -2.0), "a picture is put where it is put")
	assert(RasterUnderlayScript.centre_of(record) == Vector2(4.0, -2.0), str(RasterUnderlayScript.centre_of(record)))
	var corners := RasterUnderlayScript.corners_of(record)
	assert(corners.size() == 4, str(corners.size()))
	# 10 across and, at this picture's own proportion of 1:2, 5 deep: a quarter of ten by half of
	# five, either side of the centre.
	assert(corners[0].is_equal_approx(Vector2(-1.0, -4.5)), str(corners[0]))
	assert(corners[2].is_equal_approx(Vector2(9.0, 0.5)), str(corners[2]))
	var box := RasterUnderlayScript.bounds_of(record)
	assert(box.position.is_equal_approx(Vector2(-1.0, -4.5)), str(box.position))
	assert(box.size.is_equal_approx(Vector2(10.0, 5.0)), str(box.size))
	assert(RasterUnderlayScript.contains(record, Vector2(4.0, -2.0)), "the middle is inside")
	assert(not RasterUnderlayScript.contains(record, Vector2(12.0, -2.0)), "and off the edge is out")
	_clean()


func test_a_turned_picture_occupies_the_box_it_really_occupies() -> void:
	_clean()
	# 20 across and 10 deep, turned a quarter turn: it now occupies 10 across and 20 deep. A
	# click test that only knew the un-turned box would answer for a picture that is not there.
	var record := _record(20.0, "quarter-turn")
	RasterUnderlayScript.set_rotation(record, 90.0)
	var box := RasterUnderlayScript.bounds_of(record)
	assert(is_equal_approx(box.size.x, 10.0), str(box.size))
	assert(is_equal_approx(box.size.y, 20.0), str(box.size))
	assert(RasterUnderlayScript.contains(record, Vector2(0.0, 9.0)), "well up the page is still on it")
	assert(not RasterUnderlayScript.contains(record, Vector2(9.0, 0.0)), "and well east of it is not")
	_clean()


func test_how_see_through_it_is_clamps_rather_than_refuses() -> void:
	_clean()
	var record := _record(10.0, "opacity")
	assert(RasterUnderlayScript.set_opacity(record, 1.5), "a knob past the end is still a turn")
	assert(float(record["opacity"]) == RasterUnderlayScript.MAX_OPACITY, str(record["opacity"]))
	RasterUnderlayScript.set_opacity(record, -1.0)
	assert(float(record["opacity"]) == RasterUnderlayScript.MIN_OPACITY, str(record["opacity"])
	)
	assert(not RasterUnderlayScript.set_opacity(record, NAN), "but a knob that is not a number is not a knob")
	var hidden := _record(10.0, "hidden")
	RasterUnderlayScript.set_visible(hidden, false)
	assert(not bool(hidden["visible"]), "and a picture can be put away")
	_clean()


# --- what it is worth ------------------------------------------------------------------


func test_a_record_says_what_is_wrong_with_it_or_nothing_at_all() -> void:
	_clean()
	assert(
		RasterUnderlayScript.describe_problem({}) == "no picture has been read",
		RasterUnderlayScript.describe_problem({})
	)
	var record := _record(10.0, "problem")
	assert(RasterUnderlayScript.describe_problem(record) == "", RasterUnderlayScript.describe_problem(record))
	assert(RasterUnderlayScript.is_usable(record), "so it can be drawn")
	# A file that was moved after the drawing was saved: the record is still there and the picture
	# is not, which is a thing to say rather than a thing to crash on.
	DirAccess.remove_absolute(String(record["path"]))
	assert(not RasterUnderlayScript.is_usable(record), "a picture whose file is gone cannot be drawn")
	assert(
		RasterUnderlayScript.describe_problem(record).contains("no longer at"),
		RasterUnderlayScript.describe_problem(record)
	)
	var without: Dictionary = record.duplicate()
	without["path"] = ""
	assert(
		RasterUnderlayScript.describe_problem(without) == "the picture has no file",
		RasterUnderlayScript.describe_problem(without)
	)
	_clean()


func test_a_picture_is_described_in_the_drawings_own_units() -> void:
	_clean()
	var record := _record(24.0, "words")
	RasterUnderlayScript.set_rotation(record, 12.0)
	var metric := RasterUnderlayScript.describe(record)
	# How a length is worded is `DraftUnits`' business, not this module's, so the test asks for the
	# unit and the number rather than for a particular number of decimal places.
	assert(metric.contains(" m across"), metric)
	assert(metric.contains("24"), metric)
	assert(metric.contains("turned 12.0 degrees"), metric)
	assert(metric.contains("65% opaque"), metric)
	var imperial := UnitsScript.new()
	imperial.system = UnitsScript.System.IMPERIAL
	var words := RasterUnderlayScript.describe(record, imperial)
	assert(words.contains("ft across"), words)
	assert(not words.contains(" m across"), "an imperial drawing does not measure its underlay in metres: " + words)
	assert(RasterUnderlayScript.describe({}) == "no picture", RasterUnderlayScript.describe({}))
	_clean()


func test_the_report_says_what_was_read_and_where_the_copy_is() -> void:
	_clean()
	var record := _record(10.0, "report")
	var lines := RasterUnderlayScript.report_lines(record)
	assert(lines.size() >= 2, str(lines))
	assert(lines[0].contains("PNG") and lines[0].contains("64 x 32"), lines[0])
	assert(lines[1].contains(RasterUnderlayScript.DIR), lines[1])
	assert(lines[lines.size() - 1].contains("ready to go under the drawing"), lines[lines.size() - 1])
	var nothing := RasterUnderlayScript.report_lines({})
	assert(nothing == ["no picture has been read"], str(nothing))
	_clean()


func test_the_texture_the_plan_draws_is_the_picture() -> void:
	_clean()
	var record := _record(10.0, "texture")
	var texture: Texture2D = RasterUnderlayScript.texture_of(String(record["path"]))
	assert(texture != null, "a picture this app kept draws")
	assert(texture.get_width() == 64 and texture.get_height() == 32, str(texture.get_size()))
	assert(
		RasterUnderlayScript.texture_of(RasterUnderlayScript.DIR.path_join("test-absent.png")) == null,
		"and one that is not there is nothing to draw"
	)
	assert(
		RasterUnderlayScript.texture_of(_text_file("texture-lied.png", "not a picture at all, honestly")) == null,
		"and neither is a file that only claims to be one"
	)
	_clean()


func test_a_record_survives_a_save_and_a_load() -> void:
	_clean()
	var record := _record(24.0, "round-trip")
	RasterUnderlayScript.set_rotation(record, 33.5)
	RasterUnderlayScript.set_opacity(record, 0.4)
	var text := JSON.stringify(record)
	var loaded: Variant = JSON.parse_string(text)
	assert(loaded is Dictionary, "the record is plain data, so a file can hold it")
	var back: Dictionary = loaded
	assert(String(back["path"]) == String(record["path"]), String(back["path"]))
	assert(is_equal_approx(float(back["width_m"]), 24.0), str(back["width_m"]))
	assert(is_equal_approx(float(back["rotation_deg"]), 33.5), str(back["rotation_deg"]))
	assert(is_equal_approx(RasterUnderlayScript.height_of(back), 12.0), str(RasterUnderlayScript.height_of(back)))
	assert(int(back["width_px"]) == 64 and int(back["height_px"]) == 32, str(back))
	assert(
		RasterUnderlayScript.corners_of(back)[2].is_equal_approx(RasterUnderlayScript.corners_of(record)[2]),
		"and it lies in the same place it did before it was written down"
	)
	_clean()


func test_what_is_kept_here_can_be_listed_and_forgotten() -> void:
	_clean()
	assert(_mine().is_empty(), "and it starts with nothing of this file's")
	_source("listed", "png")
	var kept: Dictionary = RasterUnderlayScript.keep(
		RasterUnderlayScript.DIR.path_join(PREFIX + "listed.png"), PREFIX + "listed-again"
	)
	assert(bool(kept["ok"]), String(kept["reason"]))
	assert(_mine().size() == 2, str(_mine().size()))
	_clean()
	assert(_mine().is_empty(), "and the sweep leaves nothing of this file's behind")