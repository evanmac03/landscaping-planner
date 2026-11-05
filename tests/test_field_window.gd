extends Node
## The field capture page (`res://scripts/field_window.gd`), driven off-tree.
##
## The rules held here are the ones a page can get wrong by itself: which controls a person records
## with, what a name readout says about a plant the list does not have, and that a record with nothing
## in it is refused rather than written. The identity rules are `test_field_capture.gd`'s and the
## survey's are `test_field_manifest_exporter.gd`'s - this file only asks that the page hands the right
## things to both, and that it puts nothing in the real photograph folder.

const PageScript := preload("res://scripts/field_window.gd")
const IdentifierScript := preload("res://scripts/plant_identifier.gd")
const CatalogueScript := preload("res://scripts/plant_catalogue.gd")
const ExporterScript := preload("res://scripts/io/field_manifest_exporter.gd")
const CaptureScript := preload("res://scripts/field_capture.gd")

const SEED := "res://data/plants/nursery_list.json"
const SCRATCH := "user://test_field_survey.json"
const PHOTOS := "user://test_field_capture_photos"
const THYME := "thymus-serpyllum"
const THYME_NAME := "Thymus serpyllum"


func _catalogue() -> PlantCatalogue:
	var read: Dictionary = CatalogueScript.load_from(SEED)
	assert(bool(read["ok"]), "the shipped list loads: %s" % String(read["reason"]))
	return read["catalogue"]


func _clean() -> void:
	for path: String in [SCRATCH, SCRATCH + ExporterScript.TEMP_SUFFIX]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	if DirAccess.dir_exists_absolute(PHOTOS):
		for name: String in DirAccess.get_files_at(PHOTOS):
			DirAccess.remove_absolute(PHOTOS.path_join(name))
		DirAccess.remove_absolute(PHOTOS)


## A page pointed at a survey and a photograph folder of its own, so no test can read another's records
## and none of them touches the pictures somebody really took.
func _page() -> Window:
	var page: Window = PageScript.new()
	page.build()
	page.visible = true
	page.photo_folder = PHOTOS
	page.bind(_catalogue(), SCRATCH)
	return page


func _png(path: String) -> String:
	var image: Image = Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.3, 0.5, 0.2, 1.0))
	assert(image.save_png(path) == OK, "the test's own picture is written")
	return path


func test_the_page_builds_the_controls_a_person_records_with() -> void:
	var page: Window = _page()
	for control_name: String in [
		"Heading", "Explanation", "NameField", "SpeciesLine", "PartOption", "SunOption",
		"DrainageOption", "XField", "ZField", "PhotoField", "ChoosePhoto", "NoteField",
		"AddButton", "CloseButton", "SurveyLine", "Status", "PhotoHint", "HeightField", "SpreadField",
	]:
		assert(page.find_child(control_name, true, false) != null, "%s was built" % control_name)
	page.free()


func test_a_name_the_list_knows_is_read_back_as_that_plant() -> void:
	var page: Window = _page()
	page.set_name_text(THYME_NAME)
	assert(page.species_line().contains("Thymus serpyllum"), page.species_line())
	assert(
		String(page.capture()["species_id"]) == THYME,
		"and the capture is that species: %s" % String(page.capture()["species_id"])
	)
	page.free()


func test_a_name_the_list_does_not_know_is_kept_rather_than_invented() -> void:
	var page: Window = _page()
	page.set_name_text("something ferny")
	assert(page.species_line().contains("not in the list"), page.species_line())
	var made: Dictionary = page.capture()
	assert(not CaptureScript.identified(made), "no species is invented from it")
	assert(String(made["raw_taxon"]) == "something ferny", "and the name that was offered is kept")
	page.free()


func test_the_sun_and_the_drainage_are_recorded_as_the_bits_they_read_back_as() -> void:
	var page: Window = _page()
	page.set_name_text(THYME_NAME)
	assert(int(page.capture()["sun_mask"]) == 0, "nothing stated is a mask of zero, not a guess")
	assert(int(page.capture()["drainage_mask"]) == 0, "and the same for the drainage")
	assert(page.set_choice(page.sun_option(), "part shade"), "part shade is on the dropdown")
	assert(page.set_choice(page.drainage_option(), "fast-draining"), "so is fast-draining")
	assert(
		int(page.capture()["sun_mask"]) == PlantSpecies.PART_SHADE,
		"the sun is the model's own bit: %d" % int(page.capture()["sun_mask"])
	)
	assert(
		int(page.capture()["drainage_mask"]) == PlantSpecies.DRAINS_FAST,
		"and so is the drainage: %d" % int(page.capture()["drainage_mask"])
	)
	page.free()


func test_the_part_photographed_is_recorded_as_the_key_behind_the_words() -> void:
	var page: Window = _page()
	page.set_name_text(THYME_NAME)
	page.set_choice(page.part_option(), "a leaf")
	assert(
		String(page.capture()["part"]) == "leaf",
		"the record holds the key rather than the words: %s" % String(page.capture()["part"])
	)
	page.free()


func test_a_record_with_neither_a_name_nor_a_photograph_is_refused_by_name() -> void:
	var page: Window = _page()
	var result: Dictionary = page.add_capture()
	assert(not bool(result["ok"]), "it is refused")
	assert(
		page.status_text().contains("position on its own"),
		"and the page says what is missing: %s" % page.status_text()
	)
	assert(not FileAccess.file_exists(SCRATCH), "nothing was written")
	page.free()


func test_a_position_that_is_not_a_number_is_refused_in_words() -> void:
	var page: Window = _page()
	page.set_name_text(THYME_NAME)
	page.set_place("west", "0.0")
	var result: Dictionary = page.add_capture()
	assert(not bool(result["ok"]), "it is refused")
	assert(
		page.status_text().contains("east-west"),
		"naming which number is the trouble: %s" % page.status_text()
	)
	page.free()


func test_adding_a_capture_writes_it_into_the_survey() -> void:
	_clean()
	var page: Window = _page()
	page.set_name_text(THYME_NAME)
	page.set_place("2.5", "-1.0")
	page.set_note("by the gate")
	var result: Dictionary = page.add_capture()
	assert(bool(result["ok"]), "it is recorded: %s" % String(result["reason"]))
	assert(int(result["added"]) == 1, "one record")
	assert(int(result["total"]) == 1, "in a survey of one")
	var read: Dictionary = ExporterScript.read_manifest(SCRATCH)
	var record: Dictionary = read["data"]["features"][0]
	assert(String(record["species_id"]) == THYME, "the species the name belongs to")
	assert(is_equal_approx(float(record["position"]["x"]), 2.5), "where it was said to be")
	assert(is_equal_approx(float(record["position"]["z"]), -1.0), "in both directions")
	assert(String(record["notes"]) == "by the gate", "with the note")
	assert(not String(record["instance_id"]).is_empty(), "and an id the survey can keep it by")
	_clean()
	page.free()


func test_pressing_add_twice_records_one_plant() -> void:
	_clean()
	var page: Window = _page()
	page.set_name_text(THYME_NAME)
	page.set_place("1.0", "1.0")
	assert(int(page.add_capture()["added"]) == 1, "the first press records it")
	var again: Dictionary = page.add_capture()
	assert(int(again["added"]) == 0, "the second adds nothing")
	assert(int(again["total"]) == 1, "because it is the same plant in the same place")
	assert(page.status_text().contains("already in the survey"), page.status_text())
	_clean()
	page.free()


func test_the_survey_line_says_how_many_records_are_kept() -> void:
	_clean()
	var page: Window = _page()
	assert(page.survey_line().contains("empty"), page.survey_line())
	page.set_name_text(THYME_NAME)
	page.add_capture()
	page.refresh()
	assert(page.survey_line().contains("1 record"), page.survey_line())
	_clean()
	page.free()


func test_the_page_says_what_the_seam_says_about_reading_a_photograph() -> void:
	# There is no inference engine in this project, and the page must not imply one: the sentence comes
	# from `PlantIdentifier`, so a page cannot promise a feature the rest of the program does not have.
	var page: Window = _page()
	assert(
		page.photo_hint() == IdentifierScript.photo_hint(),
		"the page shows the seam's own words: %s" % page.photo_hint()
	)
	assert(page.photo_hint().contains("no identification model"), page.photo_hint())
	page.free()


func test_a_measurement_typed_on_the_page_reaches_the_record() -> void:
	# The one thing on this page a person adds with a tape measure. Nought is the honest default and
	# means "I did not measure it", so the two numbers have to travel exactly as they were typed.
	_clean()
	var page: Window = _page()
	page.set_name_text(THYME_NAME)
	page.set_place("1.0", "1.0")
	page.set_measured_size("0.35", "0.4")
	var made: Dictionary = page.capture()
	assert(is_equal_approx(float(made["measured_height_m"]), 0.35), "the height that was measured")
	assert(is_equal_approx(float(made["measured_spread_m"]), 0.4), "and the spread")
	page.add_capture()
	var record: Dictionary = ExporterScript.read_manifest(SCRATCH)["data"]["features"][0]
	assert(
		is_equal_approx(float(record["measured_spread_m"]), 0.4),
		"which reaches the survey: %s" % str(record.get("measured_spread_m", "<absent>"))
	)
	_clean()
	page.free()


func test_a_measurement_that_is_not_a_number_is_refused_in_words() -> void:
	var page: Window = _page()
	page.set_name_text(THYME_NAME)
	page.set_measured_size("about knee height", "0.4")
	var result: Dictionary = page.add_capture()
	assert(not bool(result["ok"]), "it is refused")
	assert(
		page.status_text().contains("number of metres"),
		"and the page says what a measurement has to be: %s" % page.status_text()
	)
	page.free()


func test_a_photograph_is_kept_and_the_record_points_at_it() -> void:
	_clean()
	var page: Window = _page()
	var source: String = _png("user://test_capture_shot.png")
	var kept: Dictionary = page.keep_photo(source)
	assert(bool(kept["ok"]), "the photograph is kept: %s" % String(kept["reason"]))
	assert(page.photo_path() == String(kept["path"]), "and the page points at the kept copy")
	assert(
		String(page.capture()["photo_path"]) == String(kept["path"]),
		"which is what the record will carry"
	)
	assert(
		String(kept["path"]).begins_with(PHOTOS),
		"kept in the page's own folder: %s" % String(kept["path"])
	)
	_clean()
	page.free()


func test_a_photograph_that_is_not_a_picture_is_refused_and_nothing_is_kept() -> void:
	_clean()
	var page: Window = _page()
	var file := FileAccess.open("user://test_capture_not_a_picture.png", FileAccess.WRITE)
	file.store_string("this is not a picture")
	file.close()
	var kept: Dictionary = page.keep_photo("user://test_capture_not_a_picture.png")
	assert(not bool(kept["ok"]), "it is refused")
	assert(page.photo_path().is_empty(), "and the record points at no photograph")
	assert(
		page.status_text().contains("is not a picture this can read"),
		"in the reader's own words: %s" % page.status_text()
	)
	_clean()
	page.free()