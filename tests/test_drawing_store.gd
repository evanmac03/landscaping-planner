extends Node
## The drawing on disk: writing it, reading it back, and the list of what was opened recently.
##
## The document already had a file format, and its own test round-trips it through objects. These
## go through the *file* - a write, a read, and the bytes in between - because the file is where a
## drawing is lost if anything is going to be lost, and because two things about this format can
## only be found there: integer keys inside JSON, and the colours and lengths that have to survive
## being written as text.

const StoreScript := preload("res://scripts/draft/drawing_store.gd")
const DocumentScript := preload("res://scripts/draft/draft_document.gd")
const EntityScript := preload("res://scripts/draft/draft_entity.gd")
const LayerSetScript := preload("res://scripts/draft/layer_set.gd")

const SCRATCH := "user://drawings/test-scratch.json"
const SCRATCH_RECENT := "user://drawings/test-recent.json"


## A drawing with something in it, set up so that every part of the format is exercised: an
## entity, the units, the site and the dimension standard.
func _drawing() -> DraftDocument:
	var document := DocumentScript.new()
	document.units.system = document.units.System.IMPERIAL
	document.units.display_precision = 2
	document.set_site(49.25, -122.75, -8.0)
	document.dimension_style.text_decimals = 2
	# On a layer that really exists: a document given a layer name it does not know falls back to
	# a default, and a test that did not know that would prove only that some layer round-trips.
	document.add(
		EntityScript.make_line(Vector2(1.0, 2.0), Vector2(4.5, 6.25)), LayerSetScript.NEW_HARDSCAPE
	)
	document.add(EntityScript.make_circle(Vector2(9.0, 9.0), 2.5), LayerSetScript.NEW_TURF)
	return document


func _clean(extra: Array = []) -> void:
	# The folder is made first, because a test that writes a file directly rather than through the
	# store needs it to exist, and finding that out from a null FileAccess is a confusing way to
	# learn it.
	StoreScript.ensure_dir()
	for path in [SCRATCH, SCRATCH_RECENT]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	for path in extra:
		if FileAccess.file_exists(String(path)):
			DirAccess.remove_absolute(String(path))


func test_a_drawing_survives_the_file() -> void:
	# The whole chain, and then every part of it: a save that keeps the shape and loses the site
	# would still look like a save.
	_clean()
	var written: Dictionary = StoreScript.write(_drawing(), SCRATCH)
	assert(bool(written["ok"]), String(written["reason"]))
	assert(FileAccess.file_exists(SCRATCH), "the file is there")
	var read: Dictionary = StoreScript.read(SCRATCH)
	assert(bool(read["ok"]), String(read["reason"]))
	var reopened := DocumentScript.from_dict(read["data"])
	assert(reopened.count() == 2, "both entities came back")
	assert(reopened.units.system == reopened.units.System.IMPERIAL, "the units came back")
	assert(reopened.units.display_precision == 2)
	assert(is_equal_approx(reopened.site_latitude, 49.25), "the site came back")
	assert(is_equal_approx(reopened.site_longitude, -122.75))
	assert(is_equal_approx(reopened.site_utc_offset_hours, -8.0))
	assert(reopened.dimension_style.text_decimals == 2, "the dimension standard came back")
	var lines := reopened.entities_of_kind(EntityScript.Kind.LINE)
	assert(lines.size() == 1, "the line is a line")
	assert(lines[0].point(0).is_equal_approx(Vector2(1.0, 2.0)), "the line is where it was")
	assert(lines[0].point(1).is_equal_approx(Vector2(4.5, 6.25)))
	# The id and the layer travel, which is what makes an edit to a reopened drawing an edit to
	# the same drawing rather than to a copy of it.
	assert(lines[0].id > 0, "the entity kept an id")
	assert(StringName(lines[0].layer) == LayerSetScript.NEW_HARDSCAPE, "the entity kept its layer")
	var turf := reopened.entities_of_kind(EntityScript.Kind.CIRCLE)
	assert(turf.size() == 1)
	assert(StringName(turf[0].layer) == LayerSetScript.NEW_TURF, "and each entity its own")
	_clean()


func test_the_file_is_json_a_person_can_read() -> void:
	# Not a promise about the format being a standard: a promise that a drawing is legible, which
	# is what makes a backup, a diff and a bug report possible.
	_clean()
	StoreScript.write(_drawing(), SCRATCH)
	var file := FileAccess.open(SCRATCH, FileAccess.READ)
	var text := file.get_as_text()
	file.close()
	# Version 7 is the one that states what irrigation the drawing carries, on top of version 6's
	# sheets: a reader has to be able to tell "this file has no irrigation in it" from "this file's
	# irrigation is empty", and that is the same question the sheets and the ground ask.
	assert(text.contains("\"version\": 7"), "the file says what it is")
	assert(text.contains("\"sheets\""), "and which sheets the drawing goes out as")
	assert(text.contains("\"irrigation\""), "and what irrigation it carries")
	assert(text.contains("\"entities\""), "the entities are named")
	assert(text.contains(String(LayerSetScript.NEW_HARDSCAPE)), "the layer name is in the file")
	# Integer keys, which is what JSON does to them: the id is a number in the document and a
	# string in the file. Reading it back is what the document's `int(id)` is for, and this is the
	# test that would fail if that conversion were ever dropped.
	assert(text.contains("\"1\":") or text.contains("\"2\":"), "entity ids are JSON keys")
	_clean()


func test_a_write_leaves_no_half_file_behind() -> void:
	# The write goes through a temporary name and a rename: a save that fails must not be a way to
	# lose the drawing that was already there.
	_clean()
	StoreScript.write(_drawing(), SCRATCH)
	var first: String = _text_of(SCRATCH)
	var smaller := DocumentScript.new()
	smaller.add(EntityScript.make_line(Vector2.ZERO, Vector2.ONE), &"100-NEW-LOT")
	StoreScript.write(smaller, SCRATCH)
	assert(not FileAccess.file_exists(SCRATCH + StoreScript.TEMP_SUFFIX), "the temporary is gone")
	assert(_text_of(SCRATCH) != first, "the second write replaced the first")
	var read: Dictionary = StoreScript.read(SCRATCH)
	var reopened := DocumentScript.from_dict(read["data"])
	assert(reopened.count() == 1, "and the file holds the second drawing")
	_clean()


func test_a_missing_or_unreadable_file_is_refused_with_a_reason() -> void:
	_clean()
	var missing: Dictionary = StoreScript.read(SCRATCH)
	assert(not bool(missing["ok"]))
	assert(String(missing["reason"]).contains("no drawing called"), String(missing["reason"]))

	var not_json := SCRATCH
	var file := FileAccess.open(not_json, FileAccess.WRITE)
	file.store_string("this is not a drawing, it is a sentence")
	file.close()
	var rubbish: Dictionary = StoreScript.read(not_json)
	assert(not bool(rubbish["ok"]))
	# The sentence says what is wrong and where, which is more use than "it did not open".
	assert(String(rubbish["reason"]).contains("not readable as a drawing"))
	assert(String(rubbish["reason"]).contains("line 0"))

	# JSON, but not a drawing: an array of numbers has no version and no entities.
	file = FileAccess.open(not_json, FileAccess.WRITE)
	file.store_string("[1, 2, 3]")
	file.close()
	assert(not bool(StoreScript.read(not_json)["ok"]))

	# An object with no version is not this format, whatever else it holds.
	file = FileAccess.open(not_json, FileAccess.WRITE)
	file.store_string("{\"entities\": {}}")
	file.close()
	var versionless: Dictionary = StoreScript.read(not_json)
	assert(not bool(versionless["ok"]))
	assert(String(versionless["reason"]).contains("is not a drawing"))
	_clean()


func test_writing_without_a_name_is_refused_rather_than_invented() -> void:
	# The refusal that New and Save lean on: a program that invents "untitled-3.json" has made a
	# file nobody will find again.
	var no_name: Dictionary = StoreScript.write(_drawing(), "")
	assert(not bool(no_name["ok"]))
	assert(String(no_name["reason"]).contains("no file name"))
	var nothing: Dictionary = StoreScript.write(null, SCRATCH)
	assert(not bool(nothing["ok"]))
	assert(String(nothing["reason"]).contains("no drawing"))


func test_a_name_is_made_safe_without_becoming_unrecognisable() -> void:
	assert(StoreScript.sanitise("Backyard Design") == "Backyard Design")
	assert(StoreScript.sanitise("Front: 123/45?") == "Front- 123-45-")
	assert(StoreScript.sanitise("  spaces  ") == "spaces")
	assert(StoreScript.sanitise("") == StoreScript.DEFAULT_NAME)
	assert(StoreScript.sanitise("///") == "---")
	var long_name := "x".repeat(200)
	assert(StoreScript.sanitise(long_name).length() == StoreScript.MAX_NAME)
	assert(StoreScript.path_for("Backyard Design") == StoreScript.DIR + "/Backyard Design.json")
	assert(StoreScript.display_name("user://drawings/Backyard Design.json") == "Backyard Design")
	assert(StoreScript.display_name("") == "")


func test_the_recent_list_is_newest_first_and_holds_each_drawing_once() -> void:
	_clean()
	# Write before remembering: the list only keeps drawings that are there, so a path remembered
	# before it exists would be dropped on the next read.
	var names: Array[String] = []
	for name in ["one", "two", "three"]:
		var path := StoreScript.DIR.path_join("test-%s.json" % name)
		names.append(path)
		StoreScript.write(_drawing(), path)
		StoreScript.remember(path, SCRATCH_RECENT)
	var recent: Array[String] = StoreScript.read_recent(SCRATCH_RECENT)
	assert(recent.size() == 3)
	assert(recent[0] == names[2], "the newest drawing is first")
	assert(recent[2] == names[0], "the oldest is last")
	# Opening one again moves it to the front rather than adding it twice.
	StoreScript.remember(names[0], SCRATCH_RECENT)
	recent = StoreScript.read_recent(SCRATCH_RECENT)
	assert(recent.size() == 3, "still three")
	assert(recent[0] == names[0])
	_clean(names)


func test_the_recent_list_is_capped_and_forgets_on_request() -> void:
	_clean()
	var made: Array[String] = []
	for index in StoreScript.RECENT_MAX + 3:
		var path := StoreScript.DIR.path_join("test-cap-%d.json" % index)
		made.append(path)
		StoreScript.write(_drawing(), path)
		StoreScript.remember(path, SCRATCH_RECENT)
	var recent: Array[String] = StoreScript.read_recent(SCRATCH_RECENT)
	assert(recent.size() == StoreScript.RECENT_MAX, "the list is capped at %d" % StoreScript.RECENT_MAX)
	assert(recent[0] == made[made.size() - 1], "the newest survived")
	assert(not recent.has(made[0]), "the oldest was dropped")
	StoreScript.forget(recent[0], SCRATCH_RECENT)
	assert(not StoreScript.read_recent(SCRATCH_RECENT).has(recent[0]), "and forgotten on request")
	_clean(made)


func test_a_recent_drawing_that_is_gone_is_not_offered() -> void:
	# A menu entry for a file that is not there is a command that cannot work, so the list drops
	# it rather than showing it and failing when it is chosen.
	_clean()
	var path := StoreScript.DIR.path_join("test-vanish.json")
	StoreScript.write(_drawing(), path)
	StoreScript.remember(path, SCRATCH_RECENT)
	assert(StoreScript.read_recent(SCRATCH_RECENT).has(path))
	DirAccess.remove_absolute(path)
	assert(not StoreScript.read_recent(SCRATCH_RECENT).has(path), "gone means gone")
	_clean()


func test_a_recent_list_that_is_rubbish_is_not_a_crash() -> void:
	# The recent file is small and boring and nobody will ever look at it, which is exactly the
	# kind of file that ends up half-written.
	_clean()
	assert(StoreScript.read_recent(SCRATCH_RECENT).is_empty(), "absent is empty")
	var file := FileAccess.open(SCRATCH_RECENT, FileAccess.WRITE)
	file.store_string("not json at all")
	file.close()
	assert(StoreScript.read_recent(SCRATCH_RECENT).is_empty(), "rubbish is empty")
	file = FileAccess.open(SCRATCH_RECENT, FileAccess.WRITE)
	file.store_string("{\"not\": \"a list\"}")
	file.close()
	assert(StoreScript.read_recent(SCRATCH_RECENT).is_empty(), "an object is not a list")
	file = FileAccess.open(SCRATCH_RECENT, FileAccess.WRITE)
	file.store_string("[\"\", \"user://nothing-here.json\", 7]")
	file.close()
	assert(StoreScript.read_recent(SCRATCH_RECENT).is_empty(), "only real drawings count")
	_clean()


func test_the_folder_is_made_before_it_is_written_to() -> void:
	assert(StoreScript.ensure_dir(), "the drawings folder can be made")
	assert(DirAccess.open(StoreScript.DIR) != null, "and is there")
	# Only drawings are listed as drawings. The recent list is kept outside this folder now, but a
	# build from before it was left a `recent.json` in here, and offering that as a drawing would
	# be offering the one file the app must never open as one.
	var legacy := StoreScript.DIR.path_join("recent.json")
	var file := FileAccess.open(legacy, FileAccess.WRITE)
	file.store_string("[]")
	file.close()
	assert(not StoreScript.list_drawings().has(legacy), "the recent list is not a drawing")
	assert(
		not FileAccess.file_exists(legacy),
		"and does not stay in the folder a Save dialog opens on"
	)
	StoreScript.write(_drawing(), SCRATCH)
	assert(StoreScript.list_drawings().has(SCRATCH), "a written drawing is listed")
	DirAccess.remove_absolute(legacy)
	_clean()


func test_a_drawing_somebody_named_recent_is_a_drawing() -> void:
	# The file name is not the evidence. The recent list is a JSON array of paths and a drawing is
	# a JSON object, so a person who names a drawing "recent" keeps it: a housekeeping rule that
	# went by the name alone would delete a drawing to tidy the folder.
	_clean()
	var path := StoreScript.DIR.path_join(StoreScript.LEGACY_RECENT_NAME)
	StoreScript.write(_drawing(), path)
	assert(StoreScript.ensure_dir(), "the folder is there")
	assert(FileAccess.file_exists(path), "a drawing called recent is left where it is")
	assert(StoreScript.list_drawings().has(path), "and is offered as one")
	DirAccess.remove_absolute(path)
	_clean()


func _text_of(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text