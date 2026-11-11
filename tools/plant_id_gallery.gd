extends Node
## A dev tool: **every reading-test photograph, read in one pass**, through the page a person uses.
##
##     res://tools/plant_id_gallery.tscn
##
## `plant_id_live.gd` proves one whole reading with a real model, a real photograph and a real answer,
## and prints every figure it found. This tool does the same thing for the photographs in
## `assets/generated/` whose name ends `_reading_test` - the fixtures a reading is tried against - and
## adds the one figure that tool leaves to the reader: **whether the name that came back is a plant this
## program's list actually has**.
##
## `PlantIDResolver.resolve_identification` is asked directly for its verdict, so each photograph ends
## with a word - `exact_match`, `fuzzy_match`, `not_in_catalogue` - rather than a name to compare by eye.
## That word is the whole chain in one line: pixels, then a model, then a name, then **the species this
## program will price, draw and plant**. A photograph of a plant the list has never heard of can only
## ever end `not_in_catalogue`, which is why the tomato in the pinterest photograph proved the reading
## and not the joining-up.
##
## Adding a photograph is all a person does to try another plant: this tool finds them by name rather
## than being told about them.
##
## Nothing here is shipped, and nothing here touches what somebody is using: the choice file, the
## photograph folder and the survey are all the tool's own, under `user://`.

const FieldPageScript := preload("res://scripts/field_window.gd")
const ChoiceScript := preload("res://scripts/plant_id_choice.gd")
const CatalogueScript := preload("res://scripts/plant_catalogue.gd")
const ResolverScript := preload("res://scripts/plant_id_resolver.gd")
const LlmScript := preload("res://scripts/plant_id_llm.gd")
const CaptureScript := preload("res://scripts/field_capture.gd")

const LIST := "res://data/plants/nursery_list.json"
## Where the reading-test photographs live, and how their names end.
const FOLDER := "res://assets/generated"
const SUFFIX := "_reading_test.png"
## The vision model this machine has. The program offers `llava:7b`, which is not installed here, and
## which `plant_id_live.gd` already reads for the refusal it gives.
const MODEL := "qwen2.5vl:3b"

const SURVEY := "user://plant_id_gallery_survey.json"
const CHOICE_FILE := "user://plant_id_gallery_choice.json"
const PHOTOS := "user://plant_id_gallery_photos"


func _ready() -> void:
	print("=== EVERY READING-TEST PHOTOGRAPH ===")
	_clean()
	var read: Dictionary = CatalogueScript.load_from(LIST)
	if not bool(read["ok"]):
		print("the plant list will not load, so there is nothing to read a name against: ", read["reason"])
		get_tree().quit()
		return
	var catalogue: PlantCatalogue = read["catalogue"]
	print("the list loads: ", catalogue.describe())

	var photographs: PackedStringArray = _photographs()
	if photographs.is_empty():
		print("no photograph in %s ends %s, so there is nothing to read" % [FOLDER, SUFFIX])
		get_tree().quit()
		return
	print("photographs to read: ", photographs.size())

	var page: FieldCaptureWindow = FieldPageScript.new()
	page.build()
	page.visible = true
	# The tool's own choice file, photograph folder and survey, so a run of this can neither change nor
	# read what somebody is using.
	page.id_settings_path = CHOICE_FILE
	page.photo_folder = PHOTOS
	page.bind(catalogue, SURVEY, "Every reading-test photograph")
	# **In the tree, because that is where a page lives.** A reading is stepped by the page's own frame
	# rather than waited for inside `identify_photo`, so a page that is never added never advances.
	add_child(page)
	page.set_id_mode(ChoiceScript.LOCAL)
	page.set_id_field(ChoiceScript.LOCAL_MODEL, MODEL)
	page.set_place("2.5", "-1.0")

	var resolver := ResolverScript.new(catalogue)
	var joined: int = 0
	for path: String in photographs:
		if await _read_one(page, resolver, catalogue, path):
			joined += 1

	print("--- the pass ---")
	print("  of %d photograph(s), %d came back as a plant this list has" % [photographs.size(), joined])
	_clean()
	print("=== END OF THE PASS ===")
	get_tree().quit()


## Read one photograph and say, in the program's own words, what it turned out to be.
##
## Returns whether the name that came back is a plant the list has - the figure this tool exists for.
## The photograph goes in through `keep_photo`, the same door a person's chosen file goes through, so
## nothing here bypasses the page.
func _read_one(
	page: FieldCaptureWindow, resolver: PlantIDResolver, catalogue: PlantCatalogue, path: String
) -> bool:
	print("--- %s ---" % path.get_file())
	var kept: Dictionary = page.keep_photo(path)
	if not bool(kept["ok"]):
		print("  the photograph could not be kept: ", kept["reason"])
		return false
	var shot: Image = Image.load_from_file(page.photo_path())
	if shot == null:
		print("  the kept photograph will not read back as pixels, so the reading stops here")
		return false
	var encoded: Dictionary = LlmScript.encode_image(shot)
	print("  read back as pixels: ", shot.get_size(), ", encoded to ", String(encoded["base64"]).length(),
		" characters of base64")

	var started: int = Time.get_ticks_msec()
	page.identify_photo()
	while page.is_reading():
		await get_tree().process_frame
	var answer: Dictionary = page.the_reading()
	print("  answered after %.1f s" % (float(Time.get_ticks_msec() - started) / 1000.0))
	if not bool(answer["ok"]):
		print("  the reading did not arrive: ", answer["reason"])
		print("  the page says: ", page.photo_hint())
		return false
	print("  the model says: ", answer["raw_taxon"], " at ", answer["confidence"],
		"  (", answer["model_id"], " ", answer["model_version"], ")")
	print("  in its own words: ", answer["answer"])

	var verdict: Dictionary = resolver.resolve_identification(
		String(answer["raw_taxon"]), float(answer["confidence"])
	)
	var species: PlantSpecies = verdict["species"]
	print("  the list calls that: ", verdict["status"], " (", verdict["match_type"], ")")
	if species != null:
		print("  which is: ", species.common_name, " / ", species.botanical_name, "  id: ", species.id)
	for offered: Variant in (answer["candidates"] as Array):
		var candidate: Dictionary = offered
		print("    offered: ", candidate["raw_taxon"], " at ", candidate["confidence"],
			"  -> species: ", candidate["species_id"], "  because: ", candidate["reason"])

	var made: Dictionary = page.capture()
	print("  the record the page would file: species ", made["species_id"], " at ", made["confidence"])
	print("  in words: ", CaptureScript.words(made, catalogue))
	print("  the page now says: ", page.photo_hint())
	return species != null


## Every reading-test photograph, in name order, so a pass reads in the same order twice.
func _photographs() -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	for file_name: String in DirAccess.get_files_at(FOLDER):
		if file_name.ends_with(SUFFIX):
			found.append(FOLDER.path_join(file_name))
	found.sort()
	return found


## The tool's own files, removed before and after: a second run reports the same thing as the first
## rather than appending to what the last one left.
func _clean() -> void:
	for path: String in [SURVEY, SURVEY + ".tmp", CHOICE_FILE]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	if DirAccess.dir_exists_absolute(PHOTOS):
		for file_name: String in DirAccess.get_files_at(PHOTOS):
			DirAccess.remove_absolute(PHOTOS.path_join(file_name))
		DirAccess.remove_absolute(PHOTOS)