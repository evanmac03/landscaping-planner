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
const ChoiceScript := preload("res://scripts/plant_id_choice.gd")

const THYME := "thymus-serpyllum"
const THYME_NAME := "Thymus serpyllum"
const BOX := "Buxus sempervirens"
## The page's own place for a way of reading, so no test rewrites the choice somebody is using.
const ID_CHOICE := "user://test_field_id_choice.json"

## What the page's reader was asked, and the answers to hand back in the order it asks for them: the test
## node is the transport, so the page's whole reading path runs with no network and no model.
var _asked: Array[Dictionary] = []
var _answers: Array[Dictionary] = []


func _catalogue() -> PlantCatalogue:
	var read: Dictionary = CatalogueScript.load_from(SEED)
	assert(bool(read["ok"]), "the shipped list loads: %s" % String(read["reason"]))
	return read["catalogue"]


func _clean() -> void:
	for path: String in [SCRATCH, SCRATCH + ExporterScript.TEMP_SUFFIX, ID_CHOICE]:
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
	# The way of reading, and where it may be kept, are the test's own: the default file is the one
	# somebody is really using. It is removed first, so a mode one test chose is not the mode the next one
	# opens on - a page that remembered another test's choice would make every test depend on their order.
	if FileAccess.file_exists(ID_CHOICE):
		DirAccess.remove_absolute(ID_CHOICE)
	page.id_settings_path = ID_CHOICE
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
		"DrainageOption", "XField", "ZField", "PhotoField", "ChoosePhoto", "TakePhoto", "NoteField",
		"AddButton", "CloseButton", "SurveyLine", "Status", "PhotoHint", "HeightField", "SpreadField",
		"IdModeOption", "IdSettings", "ReadPhoto", "Candidates",
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
	# There is no inference engine in this project, and with nothing chosen the page must not imply one:
	# the sentence comes from `PlantIdentifier`, for the settings this page is holding, so a page cannot
	# promise a feature the rest of the program does not have.
	var page: Window = _page()
	assert(
		page.photo_hint() == IdentifierScript.photo_hint_for(page.id_settings()),
		"the page shows the seam's own words for the mode in force: %s" % page.photo_hint()
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


## The camera files the frame itself, through the same store this page uses, so the page's whole job is to
## take the path it hands back into the same field the picker fills: two doors, one state.
func test_what_the_camera_kept_is_the_photograph_the_record_points_at() -> void:
	var page: Window = _page()
	var field: LineEdit = page.find_child("PhotoField", true, false) as LineEdit
	var status: Label = page.find_child("Status", true, false) as Label
	page.took_photo("user://test_field_capture_photos/kept.png")
	assert(field.text == "user://test_field_capture_photos/kept.png", "the field holds it: %s" % field.text)
	assert(status.text.contains("kept it as"), "and the page says where: %s" % status.text)
	page.free()


## And a camera that kept nothing - a shutter pressed on a device with no camera, or a frame that would not
## write - leaves the field as it was, rather than emptying a photograph somebody chose a moment ago.
func test_a_camera_that_kept_nothing_leaves_the_chosen_photograph_alone() -> void:
	var page: Window = _page()
	var field: LineEdit = page.find_child("PhotoField", true, false) as LineEdit
	field.text = "user://chosen_a_moment_ago.png"
	page.took_photo("")
	assert(field.text == "user://chosen_a_moment_ago.png", "still there: %s" % field.text)
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


# --- reading the photograph --------------------------------------------------------------------------


func _forget_questions() -> void:
	_asked.clear()
	_answers.clear()


## What the page's reader sends through: every request it built is kept, and the answers a test lined up
## come back in the order they were asked for. Nothing else is ever sent.
func _transport(request: Dictionary) -> Dictionary:
	_asked.append(request)
	if _answers.is_empty():
		return {"status": 0, "body": ""}
	return _answers.pop_front()


func _reader() -> PlantIdentifier:
	var made: PlantIdentifier = IdentifierScript.new()
	made.transport = Callable(self, "_transport")
	return made


func _plant(plant_name: String, confidence: float) -> Dictionary:
	return {"raw_taxon": plant_name, "confidence": confidence, "reason": "what the photograph showed"}


## What a service answers: the model's own JSON inside the envelope a chat completion comes in.
func _answer(plants: Array) -> Dictionary:
	return {
		"status": 200,
		"body": JSON.stringify({
			"choices": [{"message": {"content": JSON.stringify({"candidates": plants})}}],
		}),
	}


func test_the_controls_a_person_reads_a_photograph_with() -> void:
	var page: Window = _page()
	page.set_id_mode(ChoiceScript.LOCAL)
	assert(page.id_field(ChoiceScript.LOCAL_URL) != null, "a model on this machine is asked where it is")
	assert(
		page.id_field(ChoiceScript.ONLINE_API_KEY) == null,
		"and is never shown a box for a key it has no use for"
	)
	page.set_id_mode(ChoiceScript.HYBRID)
	assert(page.id_field(ChoiceScript.ONLINE_API_KEY) != null, "the mixed mode does need one")
	assert(page.id_field(ChoiceScript.ONLINE_API_KEY).secret, "and masks it")
	assert(not page.id_field(ChoiceScript.LOCAL_URL).secret, "while an address is read as it is typed")
	assert(
		page.id_field(ChoiceScript.SHORTLIST_SIZE) != null,
		"and it says how long the local shortlist may be"
	)
	page.set_id_mode(ChoiceScript.NONE)
	assert(
		page.id_field(ChoiceScript.LOCAL_URL) == null,
		"and off asks for nothing at all"
	)
	page.free()


func test_the_reading_line_says_what_will_happen_to_the_photograph() -> void:
	var page: Window = _page()
	assert(page.photo_hint().contains("no identification model"), page.photo_hint())
	assert(page.set_id_mode(ChoiceScript.LOCAL), "a model on this machine can be chosen")
	assert(page.photo_hint().contains("does not leave"), page.photo_hint())
	page.set_id_mode(ChoiceScript.ONLINE)
	assert(
		page.photo_hint().contains("key"),
		"a service with no key says what it is still waiting for: %s" % page.photo_hint()
	)
	assert(
		page.set_id_field(ChoiceScript.ONLINE_API_KEY, "sk-a-key"),
		"the key can be typed"
	)
	assert(
		page.photo_hint().contains("goes to the online service"),
		"and then the line says the photograph goes there: %s" % page.photo_hint()
	)
	page.free()


func test_a_photograph_is_read_and_the_record_says_which_model_said_so() -> void:
	_clean()
	var page: Window = _page()
	page.identifier = _reader()
	page.set_id_mode(ChoiceScript.LOCAL)
	page.set_photo_path(_png("user://test_capture_shot.png"))
	_forget_questions()
	_answers.append(_answer([_plant(THYME_NAME, 0.88)]))
	var answer: Dictionary = page.identify_photo()
	assert(bool(answer["ok"]), "the photograph is read: %s" % String(answer["reason"]))
	assert(page.species_line().contains("Thymus serpyllum"), page.species_line())
	var made: Dictionary = page.capture()
	assert(
		is_equal_approx(float(made["confidence"]), 0.88),
		"and the record carries the model's own confidence rather than the page's certainty: %f"
				% float(made["confidence"])
	)
	assert(
		String(made.get("model_id", "")) == ChoiceScript.DEFAULT_LOCAL_MODEL,
		"with the model that said so on it: %s" % str(made.get("model_id", "<absent>"))
	)
	page.set_place("1.0", "1.0")
	assert(int(page.add_capture()["added"]) == 1, "and it reaches the survey")
	var record: Dictionary = ExporterScript.read_manifest(SCRATCH)["data"]["features"][0]
	assert(
		String(record.get("model_id", "")) == ChoiceScript.DEFAULT_LOCAL_MODEL,
		"still saying which model read it: %s" % str(record.get("model_id", "<absent>"))
	)
	_clean()
	page.free()


func test_a_name_the_person_edits_after_a_reading_is_their_own_name_again() -> void:
	var page: Window = _page()
	page.identifier = _reader()
	page.set_id_mode(ChoiceScript.LOCAL)
	page.set_photo_path(_png("user://test_capture_shot.png"))
	_forget_questions()
	_answers.append(_answer([_plant(THYME_NAME, 0.88)]))
	page.identify_photo()
	page.set_name_text("my own guess at it")
	var made: Dictionary = page.capture()
	assert(
		is_equal_approx(float(made["confidence"]), 1.0),
		"somebody who says a name is certain of it: %f" % float(made["confidence"])
	)
	assert(
		String(made.get("model_id", "")).is_empty(),
		"and no model is named for a name the model did not give: %s"
				% str(made.get("model_id", "<absent>"))
	)
	page.free()


func test_a_shortlist_is_a_button_per_plant_and_choosing_one_fills_the_name() -> void:
	var page: Window = _page()
	page.identifier = _reader()
	page.set_id_mode(ChoiceScript.HYBRID)
	page.set_id_field(ChoiceScript.ONLINE_API_KEY, "sk-a-key")
	page.set_photo_path(_png("user://test_capture_shot.png"))
	_forget_questions()
	_answers.append(_answer([_plant(THYME_NAME, 0.6), _plant(BOX, 0.3)]))
	_answers.append({"status": 0, "body": ""})
	var answer: Dictionary = page.identify_photo()
	assert(not bool(answer["ok"]), "half the work is not an identification")
	assert(
		page.candidate_count() == 2,
		"and both plants the first model found are on offer: %d" % page.candidate_count()
	)
	assert(page.choose_candidate(0), "one of them can be chosen")
	var made: Dictionary = page.capture()
	assert(String(made["raw_taxon"]) == THYME_NAME, "which fills the name field")
	assert(is_equal_approx(float(made["confidence"]), 0.6), "at the confidence the model gave it")
	assert(
		String(made.get("model_id", "")) == ChoiceScript.DEFAULT_LOCAL_MODEL,
		"with the model that found it named, not the one that could not be reached: %s"
				% str(made.get("model_id", "<absent>"))
	)
	page.free()


func test_reading_with_nothing_chosen_refuses_by_name_and_asks_nobody() -> void:
	var page: Window = _page()
	page.identifier = _reader()
	page.set_photo_path(_png("user://test_capture_shot.png"))
	_forget_questions()
	var answer: Dictionary = page.identify_photo()
	assert(not bool(answer["ok"]), "a program nobody has chosen anything for reads nothing")
	assert(
		String(answer["reason"]).contains("name is yours to type"),
		"and the refusal says what happens instead: %s" % String(answer["reason"])
	)
	assert(_asked.is_empty(), "no model was asked at all: %d" % _asked.size())
	page.free()


## A reading used to be waited for inside the call that asked for it, which froze the program for as long
## as a model took. The page now answers whatever the reading is *now*, and this is what it says while a
## model is still thinking: not an empty reading, and not an answer.
func test_what_the_page_answers_before_a_model_has_answered_is_a_refusal_saying_so() -> void:
	var page: Window = _page()
	assert(not page.is_reading(), "nothing is being read")
	var answer: Dictionary = page.the_reading()
	assert(not bool(answer["ok"]), "so there is no answer to read")
	assert(
		String(answer["reason"]) == PageScript.READING_NOW,
		"and the page says it is reading rather than showing a reading of nothing: %s"
			% String(answer["reason"])
	)
	page.free()


func test_the_page_is_not_reading_once_a_model_has_answered() -> void:
	var page: Window = _page()
	page.identifier = _reader()
	page.set_id_mode(ChoiceScript.LOCAL)
	page.set_photo_path(_png("user://test_capture_shot.png"))
	_forget_questions()
	_answers.append(_answer([_plant(THYME_NAME, 0.88)]))
	page.identify_photo()
	assert(
		not page.is_reading(),
		"a reading no wire is involved in is over by the time a caller asks for it"
	)
	assert(bool(page.the_reading()["ok"]), "and the page holds the answer it landed with")
	assert(
		String(page.the_reading()["raw_taxon"]) == THYME_NAME,
		"naming the plant the model gave: %s" % String(page.the_reading()["raw_taxon"])
	)
	page.free()