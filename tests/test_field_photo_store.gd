extends Node
## The field photo store (`res://scripts/field_photo_store.gd`): what a captured photograph is kept
## as, and in whose words it is refused.
##
## The rules held here are about identity rather than storage: the same picture sent twice is one file,
## two different pictures never collide, and a file that only claims to be a picture is refused in the
## words the rest of the program uses. Nothing here re-tests the header reader - that is
## `test_raster_underlay.gd`'s job, and this file asks only that the store goes through it.

const StoreScript := preload("res://scripts/field_photo_store.gd")
const UnderlayScript := preload("res://scripts/draft/raster_underlay.gd")

const SCRATCH := "user://test_field_photos"


func _clean() -> void:
	if not DirAccess.dir_exists_absolute(SCRATCH):
		return
	for name: String in DirAccess.get_files_at(SCRATCH):
		DirAccess.remove_absolute(SCRATCH.path_join(name))
	DirAccess.remove_absolute(SCRATCH)


## A real PNG, written by the engine rather than pasted as bytes: a test that invents a header is a
## test that agrees with itself.
func _png(path: String, colour: Color = Color(0.2, 0.6, 0.3, 1.0)) -> String:
	var image: Image = Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(colour)
	assert(image.save_png(path) == OK, "the test's own picture is written")
	return path


func _text(path: String, words: String) -> String:
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null, "the test's own text file is written")
	file.store_string(words)
	file.close()
	return path


func test_a_photograph_is_kept_under_a_name_made_from_its_own_bytes() -> void:
	_clean()
	var source: String = _png("user://test_capture_one.png")
	var kept: Dictionary = StoreScript.add(source, SCRATCH)
	assert(bool(kept["ok"]), "it is kept: %s" % String(kept["reason"]))
	assert(not bool(kept["duplicate"]), "and it is not reported as one already there")
	var path: String = String(kept["path"])
	assert(path.begins_with(SCRATCH + "/"), "it lands in the store's own folder: %s" % path)
	assert(FileAccess.file_exists(path), "and it is really there")
	assert(
		not path.get_file().begins_with("test_capture_one"),
		"under a name made from its bytes rather than the name it arrived with: %s" % path.get_file()
	)
	assert(path.ends_with(".png"), "with the extension of the format it really is")
	_clean()


func test_the_same_photograph_arriving_twice_is_kept_once() -> void:
	# Two phones, two names, one photograph. The second is the first, and the store says so rather
	# than making a copy that a manifest could then point at either of.
	_clean()
	var first: String = _png("user://test_capture_a.png")
	var again: String = _png("user://test_capture_b.png")
	var one: Dictionary = StoreScript.add(first, SCRATCH)
	var two: Dictionary = StoreScript.add(again, SCRATCH)
	assert(bool(two["ok"]), "the second arrival is accepted: %s" % String(two["reason"]))
	assert(String(one["path"]) == String(two["path"]), "at the file the first one made")
	assert(bool(two["duplicate"]), "and it says these exact bytes were already kept")
	assert(DirAccess.get_files_at(SCRATCH).size() == 1, "so the folder holds one photograph")
	_clean()


func test_two_different_photographs_are_two_files() -> void:
	_clean()
	var first: String = _png("user://test_capture_one.png", Color(0.1, 0.2, 0.3, 1.0))
	var second: String = _png("user://test_capture_two.png", Color(0.9, 0.8, 0.7, 1.0))
	var one: Dictionary = StoreScript.add(first, SCRATCH)
	var two: Dictionary = StoreScript.add(second, SCRATCH)
	assert(String(one["path"]) != String(two["path"]), "different bytes are different files")
	assert(DirAccess.get_files_at(SCRATCH).size() == 2, "and both are kept")
	_clean()


func test_a_photograph_whose_name_lies_about_its_format_is_kept_as_what_it_is() -> void:
	# A JPEG with a `.png` name is a real thing a phone does. The header decides, which is the whole
	# reason this goes through `RasterUnderlay.sniff` rather than trusting an extension.
	_clean()
	var image: Image = Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.4, 0.4, 0.4, 1.0))
	var lying: String = "user://test_capture.jpg"
	assert(image.save_png(lying) == OK, "a PNG written under a `.jpg` name")
	var kept: Dictionary = StoreScript.add(lying, SCRATCH)
	assert(bool(kept["ok"]), "it is kept: %s" % String(kept["reason"]))
	assert(
		String(kept["path"]).ends_with(".png"),
		"as the format its header says, not the one its name claims: %s" % String(kept["path"])
	)
	_clean()


func test_a_file_that_is_not_a_picture_is_refused_in_the_words_the_rest_of_the_app_uses() -> void:
	_clean()
	var bytes_file: String = _text("user://test_capture_lies.png", "this is not a picture at all")
	var kept: Dictionary = StoreScript.add(bytes_file, SCRATCH)
	assert(not bool(kept["ok"]), "it is refused")
	var reason: String = String(kept["reason"])
	assert(reason.contains("is not a picture this can read"), "in the reader's own sentence: %s" % reason)
	assert(
		reason.contains(UnderlayScript.formats_text()),
		"naming the formats this program does read: %s" % reason
	)
	assert(not DirAccess.dir_exists_absolute(SCRATCH), "and nothing was written")
	_clean()


func test_a_photograph_that_is_not_there_is_refused_by_name() -> void:
	_clean()
	var kept: Dictionary = StoreScript.add("user://test_capture_missing.png", SCRATCH)
	assert(not bool(kept["ok"]), "it is refused")
	assert(
		String(kept["reason"]).contains("user://test_capture_missing.png"),
		"naming the file that is not there: %s" % String(kept["reason"])
	)
	_clean()


func test_a_page_offers_the_photographs_in_words_and_names_the_one_it_cannot_open() -> void:
	# A proposal page is looked at by a client, so a photograph is captioned with what it shows rather than
	# with the name the camera gave it - and a photograph that has since been moved is a sentence on the
	# page, not a picture that quietly vanished from a client's proposal.
	var source: String = _png("user://test_capture_page.png")
	var here: Dictionary = {
		"species_id": "thymus_serpyllum",
		"raw_taxon": "Thymus serpyllum",
		"confidence": 0.9,
		"part": "leaf",
		"photo_path": source,
	}
	var gone: Dictionary = {
		"species_id": "", "raw_taxon": "something ferny", "part": "leaf",
		"photo_path": "user://test_capture_gone.png",
	}
	var made: Dictionary = StoreScript.for_page([here, gone], null)
	assert(bool(made["ok"]), "the photograph that is there is offered: %s" % String(made["reason"]))
	var photos: Array = made["photos"]
	assert(photos.size() == 1, "one of the two could be opened")
	var caption := String((photos[0] as Dictionary)["caption"])
	assert(caption.contains("leaf"), "the caption says which part was photographed: %s" % caption)
	assert(
		not caption.contains(".png") and not caption.contains("user://"),
		"and it never shows a file name: %s" % caption
	)
	var missing: Array = made["missing"]
	assert(missing.size() == 1, "the one that is gone is named")
	assert(
		String(missing[0]).contains("user://test_capture_gone.png"),
		"by the path that is not there: %s" % String(missing[0])
	)