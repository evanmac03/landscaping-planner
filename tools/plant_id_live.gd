extends Node
## A dev tool: **one whole reading**, through the page a person uses, against a model on this machine.
##
##     res://tools/plant_id_live.tscn
##
## Every other proof of this subsystem hands `PlantIdentifier` a simulated transport. That proves what
## this program decides - the request it builds, what it does with a shortlist, what a refusal carries -
## and proves nothing about whether a model answers in the shape `PlantIdLlm` reads. This tool asks a
## real one: it builds the real page, points it at a real photograph, presses Read the photograph, and
## then records the plant in a survey file of its own and reads the record back.
##
## It reads **twice**, on purpose. The first is with the model the program offers by default, which this
## machine may not have installed: that is the refusal a person would meet, and it is worth reading.
## The second is with the model this machine does have, named in `MODEL` below.
##
## Nothing here is shipped, and nothing here touches what somebody is using: the way of reading, the
## photograph folder and the survey are all the tool's own, under `user://`.

const FieldPageScript := preload("res://scripts/field_window.gd")
const ChoiceScript := preload("res://scripts/plant_id_choice.gd")
const CatalogueScript := preload("res://scripts/plant_catalogue.gd")
const ExporterScript := preload("res://scripts/io/field_manifest_exporter.gd")
const CaptureScript := preload("res://scripts/field_capture.gd")
const LlmScript := preload("res://scripts/plant_id_llm.gd")

const LIST := "res://data/plants/nursery_list.json"
## A photograph of one small boxwood in a bed of mulch. The model reads it as `Buxus microphylla`, which is
## **not** what this list stocks - the list carries `Buxus sempervirens`, "Common boxwood" - so this
## photograph comes back `not_in_catalogue`. What makes it worth reading anyway is the candidate behind
## the name: `Buxus sempervirens` at 0.8, which **is** a species here. That is the shortlist a refusal
## carries, and it is the reason a refusal is not a dead end.
const PHOTOGRAPH := "res://assets/generated/boxwood_reading_test.png"
## The vision model this machine actually has. The program's own offer is `llava:7b`, which is what the
## first reading is for.
const MODEL := "qwen2.5vl:3b"

const SURVEY := "user://plant_id_live_survey.json"
const CHOICE_FILE := "user://plant_id_live_choice.json"
const PHOTOS := "user://plant_id_live_photos"


func _ready() -> void:
	print("=== A WHOLE READING ===")
	_clean()
	var read: Dictionary = CatalogueScript.load_from(LIST)
	if not bool(read["ok"]):
		print("the plant list will not load, so there is nothing to read a name against: ", read["reason"])
		get_tree().quit()
		return
	print("the list loads: ", read["catalogue"].describe())

	var page: FieldCaptureWindow = FieldPageScript.new()
	page.build()
	page.visible = true
	# The tool's own choice file, photograph folder and survey: a run of this cannot change the program
	# somebody is using, and cannot read their choice either.
	page.id_settings_path = CHOICE_FILE
	page.photo_folder = PHOTOS
	page.bind(read["catalogue"], SURVEY, "A whole reading")
	# **In the tree, because that is where a page lives.** A reading is now stepped by the page's own frame
	# rather than waited for inside `identify_photo`, so a page that is never added never advances - and
	# this tool exists to prove what a page really does with a real model.
	add_child(page)
	page.set_place("2.5", "-1.0")
	page.set_note("a whole reading, taken by tools/plant_id_live.gd")

	print("--- the photograph ---")
	var kept: Dictionary = page.keep_photo(PHOTOGRAPH)
	print("  kept: ", str(kept))
	if not bool(kept["ok"]):
		print("there is no photograph to read, so the reading stops here")
		get_tree().quit()
		return
	var shot: Image = Image.load_from_file(page.photo_path())
	var encoded: Dictionary = LlmScript.encode_image(shot)
	print("  read back as pixels: ", shot.get_size(), ", encoded to ", String(encoded["base64"]).length(),
		" characters of base64")

	print("--- reading with the model the program offers by default ---")
	page.set_id_mode(ChoiceScript.LOCAL)
	print("  which is: ", page.id_field(ChoiceScript.LOCAL_MODEL).text)
	var first: Dictionary = await _read_and_wait(page)
	print("  ok: ", first["ok"])
	print("  the reason, when it is not: ", first["reason"])
	print("  the page says: ", page.photo_hint())

	print("--- reading with the model this machine has: %s ---" % MODEL)
	page.set_id_field(ChoiceScript.LOCAL_MODEL, MODEL)
	print("  which is now: ", page.id_field(ChoiceScript.LOCAL_MODEL).text)
	var answer: Dictionary = await _read_and_wait(page)
	print("  ok: ", answer["ok"])
	print("  the reason, when it is not: ", answer["reason"])
	print("  the name it gave: ", answer["raw_taxon"], " at ", answer["confidence"])
	print("  the model it names: ", answer["model_id"], " ", answer["model_version"])
	print("  the model's own words: ", answer["answer"])
	for offered: Variant in (answer["candidates"] as Array):
		var candidate: Dictionary = offered
		print("    offered: ", candidate["raw_taxon"], " at ", candidate["confidence"],
			"  -> species: ", candidate["species_id"], "  because: ", candidate["reason"])
	print("  the page now says: ", page.photo_hint())

	print("--- the record the page would file ---")
	var made: Dictionary = page.capture()
	print("  species: ", made["species_id"], "  at ", made["confidence"],
		"  from ", made.get("model_id", "<no model>"))
	print("  in words: ", CaptureScript.words(made, read["catalogue"]))
	var appended: Dictionary = page.add_capture()
	print("  appended: ", str(appended))
	var back: Dictionary = ExporterScript.read_manifest(SURVEY)
	if bool(back["ok"]):
		var features: Array = (back["data"] as Dictionary)["features"]
		print("  the survey holds ", features.size(), " record(s)")
		for feature: Variant in features:
			print("  read back: ", str(feature))
	_clean()
	print("=== END OF THE READING ===")
	get_tree().quit()


## Press Read the photograph and wait for the answer **by frames**, which is how a page does it now.
##
## **The frame count is the point of this tool.** A reading used to be waited for inside the call that asked
## for it, so a model thinking for a minute drew no frame at all for that minute and the program looked
## hung. The page's own frame steps the reading instead, so what is counted here is the proof: this many
## frames were drawn while the model was thinking about the photograph.
func _read_and_wait(page: FieldCaptureWindow) -> Dictionary:
	var started: int = Time.get_ticks_msec()
	var frames: int = 0
	page.identify_photo()
	while page.is_reading():
		await get_tree().process_frame
		frames += 1
	print(
		"  answered after %.1f s, with %d frames drawn while it was waited for"
			% [float(Time.get_ticks_msec() - started) / 1000.0, frames]
	)
	return page.the_reading()


## The tool's own files, removed before and after: a second run reports the same thing as the first
## rather than appending to what the last one left.
func _clean() -> void:
	for path: String in [SURVEY, SURVEY + ExporterScript.TEMP_SUFFIX, CHOICE_FILE]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	if DirAccess.dir_exists_absolute(PHOTOS):
		for file_name: String in DirAccess.get_files_at(PHOTOS):
			DirAccess.remove_absolute(PHOTOS.path_join(file_name))
		DirAccess.remove_absolute(PHOTOS)
