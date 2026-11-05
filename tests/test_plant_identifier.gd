extends Node
## The identification seam (`res://scripts/plant_identifier.gd`): what a classifier has to hand over, and
## what this program says while there is no classifier at all.
##
## The rules held here are the contract's own: an answer that names nothing is refused rather than
## becoming a record about nothing, a weak answer goes through the same floors every other name in this
## program goes through, and the model that answered is named on the record so a person can weigh it
## later instead of trusting it because it reached a screen.

const IdentifierScript := preload("res://scripts/plant_identifier.gd")
const CatalogueScript := preload("res://scripts/plant_catalogue.gd")
const ExporterScript := preload("res://scripts/io/field_manifest_exporter.gd")
const CaptureScript := preload("res://scripts/field_capture.gd")

const SEED := "res://data/plants/nursery_list.json"
const THYME := "thymus-serpyllum"
const THYME_NAME := "Thymus serpyllum"


func _catalogue() -> PlantCatalogue:
	var read: Dictionary = CatalogueScript.load_from(SEED)
	assert(bool(read["ok"]), "the shipped list loads: %s" % String(read["reason"]))
	return read["catalogue"]


func test_there_is_no_model_and_the_refusal_says_what_is_missing() -> void:
	# A program that quietly lacked the feature would leave somebody pressing a button that does nothing.
	assert(not IdentifierScript.installed(), "no model is installed")
	var answer: Dictionary = IdentifierScript.new().identify(null)
	assert(not bool(answer["ok"]), "and no picture can be read")
	assert(
		String(answer["reason"]).contains("no identification model"),
		"which is said by name: %s" % String(answer["reason"])
	)
	assert(IdentifierScript.model_id().is_empty(), "and no model claims to be the one that looked")


func test_a_models_answer_becomes_a_capture_naming_the_plant_and_the_model() -> void:
	var answer: Dictionary = IdentifierScript.capture_from({
		"raw_taxon": THYME_NAME,
		"confidence": 0.93,
		"model_id": "leafnet",
		"model_version": "2.1",
	}, _catalogue(), Vector3(1.0, 0.0, 2.0), "user://field_photos/ab.png", "by the gate")
	assert(bool(answer["ok"]), "it is filed: %s" % String(answer["reason"]))
	var capture: Dictionary = answer["capture"]
	assert(String(capture["species_id"]) == THYME, "as the species the name belongs to")
	assert(String(capture["model_id"]) == "leafnet", "with the model that said so")
	assert(String(capture["model_version"]) == "2.1", "and which version of it")
	assert(String(capture["photo_path"]) == "user://field_photos/ab.png", "and its photograph")


func test_a_weak_answer_is_refused_by_the_floors_every_other_name_goes_through() -> void:
	var answer: Dictionary = IdentifierScript.capture_from({
		"raw_taxon": THYME_NAME,
		"confidence": 0.1,
		"model_id": "leafnet",
	}, _catalogue())
	assert(not bool(answer["ok"]), "it is refused")
	assert(
		String(answer["reason"]).contains("confidence"),
		"and says the confidence was the trouble: %s" % String(answer["reason"])
	)
	var capture: Dictionary = answer["capture"]
	assert(not CaptureScript.identified(capture), "so no species is filed from a guess")
	assert(String(capture["raw_taxon"]) == THYME_NAME, "and the name offered is kept for a person")
	assert(String(capture["model_id"]) == "leafnet", "along with which model offered it")


func test_an_answer_that_names_nothing_is_refused_rather_than_becoming_a_record_about_nothing() -> void:
	var answer: Dictionary = IdentifierScript.capture_from({"confidence": 0.99}, _catalogue())
	assert(not bool(answer["ok"]), "it is refused")
	assert(
		String(answer["reason"]).contains("named no plant"),
		"saying what the answer lacked: %s" % String(answer["reason"])
	)
	assert(
		not CaptureScript.identified(answer["capture"]),
		"and the capture it hands back names no species"
	)


func test_the_model_that_answered_travels_with_the_record() -> void:
	var answer: Dictionary = IdentifierScript.capture_from({
		"raw_taxon": THYME_NAME,
		"confidence": 0.93,
		"model_id": "leafnet",
		"model_version": "2.1",
	}, _catalogue(), Vector3(1.0, 0.0, 2.0))
	var manifest: Dictionary = ExporterScript.to_manifest("Yard", [answer["capture"]])
	var record: Dictionary = JSON.parse_string(JSON.stringify(manifest, "  "))["features"][0]
	assert(String(record["model_id"]) == "leafnet", "the manifest carries the model's name")
	assert(String(record["model_version"]) == "2.1", "and its version")
	var read: Dictionary = CaptureScript.from_record(record)
	assert(String(read["capture"]["model_id"]) == "leafnet", "and the capture reads it back")