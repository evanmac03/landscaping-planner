extends Node
## The field capture (`res://scripts/field_capture.gd`): what one observation is, and which of them
## this program is allowed to believe.
##
## The rules held here are the ones that stop an observation becoming something nobody claimed: a name
## read too weakly is carried as unidentified rather than filed, a record that does not say where the
## plant is never reaches the plan, and a stated bit the model has no meaning for is refused by name.

const CaptureScript := preload("res://scripts/field_capture.gd")
const CatalogueScript := preload("res://scripts/plant_catalogue.gd")
const ResolverScript := preload("res://scripts/plant_id_resolver.gd")
const ExporterScript := preload("res://scripts/io/field_manifest_exporter.gd")
const SpeciesScript := preload("res://scripts/plant_species.gd")

const SEED := "res://data/plants/nursery_list.json"
const THYME := "thymus-serpyllum"
## A name the resolver places by botanical name, which is the path a confidence floor applies to: an
## id that was read exactly is taken as read and never measured against a floor.
const THYME_NAME := "Thymus serpyllum"


func _catalogue() -> PlantCatalogue:
	var read: Dictionary = CatalogueScript.load_from(SEED)
	assert(bool(read["ok"]), "the shipped list loads: %s" % String(read["reason"]))
	return read["catalogue"]


func test_a_name_read_too_weakly_is_carried_as_unidentified_rather_than_filed() -> void:
	# A third of a chance that it is a thyme is not a thyme. The capture keeps what the classifier
	# offered so a person can accept it, and carries no species, so nothing gets planted on a guess.
	var answer: Dictionary = CaptureScript.identify(
			THYME_NAME, ResolverScript.CONFIDENCE_FUZZY - 0.05, _catalogue())
	assert(not bool(answer["ok"]), "it is refused rather than filed")
	assert(
		String(answer["reason"]).contains("confidence"),
		"and the reason says the confidence was the trouble: %s" % String(answer["reason"])
	)
	var capture: Dictionary = answer["capture"]
	assert(not CaptureScript.identified(capture), "the capture names no species")
	assert(String(capture["raw_taxon"]) == THYME_NAME, "and keeps the name that was offered")


func test_a_name_read_with_enough_confidence_is_filed_as_that_species() -> void:
	var answer: Dictionary = CaptureScript.identify(THYME_NAME, 0.92, _catalogue())
	assert(bool(answer["ok"]), "it is filed: %s" % String(answer["reason"]))
	var capture: Dictionary = answer["capture"]
	assert(CaptureScript.identified(capture), "and it names a species")
	assert(String(capture["species_id"]) == THYME, "the one the name belongs to")
	assert(is_equal_approx(float(capture["confidence"]), 0.92), "at the confidence it was read at")
	assert(bool(CaptureScript.validate(capture)["ok"]), "and it is a valid capture")


func test_a_capture_nobody_could_identify_keeps_where_it_was_and_what_it_looked_like() -> void:
	# The person on site knew three things and did not know the fourth. Three is worth keeping.
	var capture: Dictionary = CaptureScript.unidentified(
			Vector3(3.25, 0.0, -1.5), "user://field_photos/ab12.png", "by the gate",
			CaptureScript.PART_LEAF)
	assert(not CaptureScript.identified(capture), "it names no species")
	assert(bool(CaptureScript.validate(capture)["ok"]), "and it is still a capture")
	assert(capture["position"] == Vector3(3.25, 0.0, -1.5), "it keeps where it was seen")
	assert(String(capture["photo_path"]) == "user://field_photos/ab12.png", "and its photograph")
	assert(String(capture["notes"]) == "by the gate", "and the note")
	assert(String(capture["part"]) == "leaf", "and which part was photographed")


func test_a_capture_survives_the_file_and_comes_back_the_way_it_went_in() -> void:
	# Through the writer, which is the only thing that knows how to put a place on the world into a
	# JSON file: a capture stringified on its own loses its position, silently, because a `Vector3`
	# does not survive JSON.
	var answer: Dictionary = CaptureScript.identify(
			THYME_NAME, 0.8, _catalogue(), Vector3(1.0, 0.0, 2.0), "user://field_photos/ab12.png",
			"by the gate", CaptureScript.PART_FLOWER)
	var manifest: Dictionary = ExporterScript.to_manifest("Yard", [answer["capture"]])
	var record: Dictionary = JSON.parse_string(JSON.stringify(manifest, "  "))["features"][0]
	assert(record["position"] is Dictionary, "the writer put the place in a shape a file can hold")
	var read: Dictionary = CaptureScript.from_record(record)
	assert(bool(read["ok"]), "the record reads back: %s" % String(read["reason"]))
	var capture: Dictionary = read["capture"]
	assert(CaptureScript.identified(capture), "still identified")
	assert(String(capture["species_id"]) == THYME, "as the same species")
	assert(capture["position"] == Vector3(1.0, 0.0, 2.0), "in the same place: %s" % str(capture["position"]))
	assert(is_equal_approx(float(capture["confidence"]), 0.8), "at the same confidence")
	assert(String(capture["part"]) == "flower", "of the same part")
	assert(String(capture["photo_path"]) == "user://field_photos/ab12.png", "with its photograph")


func test_a_record_that_does_not_say_where_the_plant_is_never_reaches_the_plan() -> void:
	# The alternative is a zero, which would be believed as a real place and would plant a stranger at
	# the origin of the drawing.
	var read: Dictionary = CaptureScript.from_record({"species_id": THYME, "confidence": 0.9})
	assert(not bool(read["ok"]), "it is refused")
	assert(
		String(read["reason"]).contains("where the plant is"),
		"and the reason says what is missing: %s" % String(read["reason"])
	)


func test_a_bit_that_is_not_a_light_level_is_refused_naming_the_mask() -> void:
	var read: Dictionary = CaptureScript.from_record({
		"species_id": THYME,
		"confidence": 0.9,
		"position": {"x": 0.0, "y": 0.0, "z": 0.0},
		"sun_mask": 16,
	})
	assert(not bool(read["ok"]), "a bit nobody has a meaning for is refused")
	assert(
		String(read["reason"]).contains("16"),
		"naming the mask: %s" % String(read["reason"])
	)


func test_a_confidence_that_runs_past_a_hundred_per_cent_is_refused() -> void:
	var read: Dictionary = CaptureScript.from_record({
		"species_id": THYME,
		"confidence": 1.5,
		"position": {"x": 0.0, "y": 0.0, "z": 0.0},
	})
	assert(not bool(read["ok"]), "a confidence of 150% is not a confidence")
	assert(
		String(read["reason"]).contains("confidence"),
		"and the reason says so: %s" % String(read["reason"])
	)


func test_a_part_of_a_plant_nobody_has_heard_of_is_refused_rather_than_kept() -> void:
	# A part is a closed vocabulary the two sides of the manifest agree on. A word outside it means
	# they disagree about the format, which is worth saying rather than quietly discarding.
	var read: Dictionary = CaptureScript.from_record({
		"species_id": THYME,
		"confidence": 0.9,
		"position": {"x": 0.0, "y": 0.0, "z": 0.0},
		"part": "seed",
	})
	assert(not bool(read["ok"]), "it is refused")
	assert(
		String(read["reason"]).contains("seed"),
		"naming the word it could not read: %s" % String(read["reason"])
	)


func test_a_size_somebody_measured_is_used_and_says_it_was_stated() -> void:
	var species: PlantSpecies = _catalogue().get_species(StringName(THYME))
	var capture: Dictionary = CaptureScript.unidentified(Vector3.ZERO)
	capture["measured_spread_m"] = 1.2
	var size: Dictionary = CaptureScript.size_of(capture, species)
	assert(bool(size["ok"]), "there is a size: %s" % String(size["reason"]))
	assert(is_equal_approx(float(size["spread_m"]), 1.2), "the one that was measured")
	assert(String(size["source"]) == CaptureScript.SIZE_STATED, "and the record says it was measured")


func test_a_plant_nobody_measured_is_the_size_the_list_states() -> void:
	var species: PlantSpecies = _catalogue().get_species(StringName(THYME))
	var size: Dictionary = CaptureScript.size_of(CaptureScript.unidentified(Vector3.ZERO), species)
	assert(bool(size["ok"]), "the list's own mature size is a size: %s" % String(size["reason"]))
	assert(String(size["source"]) == CaptureScript.SIZE_CATALOGUE, "and it says where it came from")
	assert(is_equal_approx(float(size["spread_m"]), species.spread_m()), "which is the list's number")


func test_a_plant_the_list_does_not_size_is_refused_rather_than_given_a_zero() -> void:
	# A zero would be read as a plant of no size and drawn as a dot on the plan. Nothing saying how big
	# something is is a different fact from something being nothing across.
	var unknown: PlantSpecies = SpeciesScript.from_dict({
		"id": "unknown-thing",
		"botanical_name": "Unknown",
		"common_name": "Unknown",
	})
	var size: Dictionary = CaptureScript.size_of(CaptureScript.unidentified(Vector3.ZERO), unknown)
	assert(not bool(size["ok"]), "there is no size to be had")
	assert(
		String(size["reason"]).contains("nobody measured it"),
		"and the refusal says why: %s" % String(size["reason"])
	)


func test_a_capture_reads_as_a_line_naming_the_plant_and_the_confidence() -> void:
	var catalogue: PlantCatalogue = _catalogue()
	var filed: Dictionary = (CaptureScript.identify(
			THYME_NAME, 0.9, catalogue, Vector3(2.0, 0.0, 4.0))["capture"] as Dictionary)
	var line: String = CaptureScript.words(filed, catalogue)
	assert(line.contains("Thymus serpyllum"), "it names the plant: %s" % line)
	assert(line.contains("90%"), "and how sure the reading was: %s" % line)
	var loose: Dictionary = CaptureScript.unidentified(Vector3.ZERO)
	assert(
		CaptureScript.words(loose).begins_with("not identified"),
		"and an unplaced capture says exactly that: %s" % CaptureScript.words(loose)
	)
	var offered: Dictionary = CaptureScript.identify("something ferny", 0.1, catalogue)["capture"]
	assert(
		CaptureScript.words(offered).contains("something ferny"),
		"while showing the name that was offered: %s" % CaptureScript.words(offered)
	)