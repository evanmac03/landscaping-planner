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

const ChoiceScript := preload("res://scripts/plant_id_choice.gd")

const SEED := "res://data/plants/nursery_list.json"
const THYME := "thymus-serpyllum"
const THYME_NAME := "Thymus serpyllum"
const BOX := "Buxus sempervirens"

## Every request the pipeline built, and the answers to hand back in the order it asks for them.
##
## The test node is its own transport, so a machine with no model, no key and no network does a local
## model's job and a service's job through the same code path the program uses - which is what makes
## "was a request built at all" a question a test can answer.
var _asked: Array[Dictionary] = []
var _answers: Array[Dictionary] = []


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


# --- the pipeline: the four ways a photograph is read ----------------------------------------------


func _forget_questions() -> void:
	_asked.clear()
	_answers.clear()


## What the pipeline's transport is: it keeps every request it was handed and answers with the next
## answer a test lined up, or with "it never arrived" when the test lined up none.
func _transport(request: Dictionary) -> Dictionary:
	_asked.append(request)
	if _answers.is_empty():
		return {"status": 0, "body": ""}
	return _answers.pop_front()


func _settings(mode: StringName) -> Dictionary:
	var made: Dictionary = ChoiceScript.default_settings()
	made[ChoiceScript.MODE] = String(mode)
	return made


func _identifier(settings: Dictionary) -> PlantIdentifier:
	var made: PlantIdentifier = IdentifierScript.new(settings)
	made.transport = Callable(self, "_transport")
	return made


func _photo() -> Image:
	var made: Image = Image.create_empty(16, 16, false, Image.FORMAT_RGBA8)
	made.fill(Color(0.2, 0.4, 0.2))
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


func _authorisation_in(request: Dictionary) -> String:
	for header: Variant in (request["headers"] as Array):
		if String(header).begins_with("Authorization"):
			return String(header)
	return ""


func test_local_mode_turns_a_photograph_into_a_ranked_shortlist() -> void:
	_forget_questions()
	_answers.append(_answer([_plant(BOX, 0.30), _plant(THYME_NAME, 0.88)]))
	var answer: Dictionary = _identifier(_settings(ChoiceScript.LOCAL)).identify_with(
		_photo(), CaptureScript.PART_LEAF, "", _catalogue()
	)
	assert(bool(answer["ok"]), "the photograph is read: %s" % String(answer["reason"]))
	assert(String(answer["raw_taxon"]) == THYME_NAME, "and the likeliest plant is the answer")
	assert(is_equal_approx(float(answer["confidence"]), 0.88), "at the confidence the model gave it")
	var plants: Array = answer["candidates"]
	assert(plants.size() == 2, "every plant it offered travels: %d" % plants.size())
	assert(
		String(plants[0]["species_id"]) == THYME,
		"and each says which species this list makes of it: %s" % str(plants[0])
	)
	assert(String(plants[0]["reason"]) != "", "keeping the model's own reason")
	assert(_asked.size() == 1, "one model was asked once")
	assert(String(_asked[0]["host"]) == "127.0.0.1", "on this machine: %s" % String(_asked[0]["host"]))
	assert(
		_authorisation_in(_asked[0]).is_empty(),
		"and with no key, because a model on this machine is not asked for one"
	)


func test_online_mode_sends_the_key_and_files_the_plant_the_service_named() -> void:
	_forget_questions()
	var settings: Dictionary = _settings(ChoiceScript.ONLINE)
	settings[ChoiceScript.ONLINE_API_KEY] = "sk-a-key"
	_answers.append(_answer([_plant(THYME_NAME, 0.91)]))
	var answer: Dictionary = _identifier(settings).identify_with(
		_photo(), CaptureScript.PART_FLOWER, "by the gate", _catalogue()
	)
	assert(bool(answer["ok"]), "the photograph is read: %s" % String(answer["reason"]))
	assert(String(answer["raw_taxon"]) == THYME_NAME, "and names the plant")
	assert(
		String(answer["model_id"]) == ChoiceScript.DEFAULT_ONLINE_MODEL,
		"the model that was asked is on the record: %s" % String(answer["model_id"])
	)
	assert(
		_authorisation_in(_asked[0]) == "Authorization: Bearer sk-a-key",
		"and the key travels with the request: %s" % _authorisation_in(_asked[0])
	)
	assert(String(_asked[0]["body"]).contains("by the gate"), "along with the note the person wrote")
	assert(String(_asked[0]["body"]).contains("a flower"), "and which part of the plant was photographed")


func test_hybrid_mode_hands_the_local_shortlist_to_the_online_model_and_names_both() -> void:
	_forget_questions()
	var settings: Dictionary = _settings(ChoiceScript.HYBRID)
	settings[ChoiceScript.ONLINE_API_KEY] = "sk-a-key"
	_answers.append(_answer([_plant(THYME_NAME, 0.55), _plant(BOX, 0.20)]))
	_answers.append(_answer([_plant(THYME_NAME, 0.94)]))
	var answer: Dictionary = _identifier(settings).identify_with(
		_photo(), CaptureScript.PART_LEAF, "", _catalogue()
	)
	assert(bool(answer["ok"]), "the two halves together read it: %s" % String(answer["reason"]))
	assert(_asked.size() == 2, "both models were asked: %d" % _asked.size())
	assert(
		String(_asked[1]["body"]).contains(THYME_NAME) and String(_asked[1]["body"]).contains(BOX),
		"and the second is told every plant the first offered"
	)
	assert(String(answer["raw_taxon"]) == THYME_NAME, "the answer is the second model's")
	assert(
		is_equal_approx(float(answer["confidence"]), 0.94),
		"at its own confidence rather than the first look's: %f" % float(answer["confidence"])
	)
	assert(
		String(answer["model_id"]).contains(ChoiceScript.DEFAULT_LOCAL_MODEL)
				and String(answer["model_id"]).contains(ChoiceScript.DEFAULT_ONLINE_MODEL),
		"and a record of how the name was arrived at names both models: %s" % String(answer["model_id"])
	)


func test_hybrid_keeps_the_local_shortlist_when_the_online_half_cannot_be_reached() -> void:
	_forget_questions()
	var settings: Dictionary = _settings(ChoiceScript.HYBRID)
	settings[ChoiceScript.ONLINE_API_KEY] = "sk-a-key"
	_answers.append(_answer([_plant(THYME_NAME, 0.55), _plant(BOX, 0.20)]))
	_answers.append({"status": 0, "body": ""})
	var answer: Dictionary = _identifier(settings).identify_with(
		_photo(), CaptureScript.PART_LEAF, "", _catalogue()
	)
	assert(not bool(answer["ok"]), "half the work is not an identification")
	assert(
		String(answer["reason"]).contains("online model could not be reached"),
		"and the refusal says which half failed: %s" % String(answer["reason"])
	)
	var plants: Array = answer["candidates"]
	assert(plants.size() == 2, "while the plants the local half narrowed it to are still there")
	assert(String(plants[0]["raw_taxon"]) == THYME_NAME, "best first: %s" % str(plants[0]))
	assert(String(plants[0]["species_id"]) == THYME, "each with the species this list makes of it")
	assert(
		String(answer["model_id"]) == ChoiceScript.DEFAULT_LOCAL_MODEL,
		"and the model those plants came from is named, so choosing one is choosing its reading: %s"
				% String(answer["model_id"])
	)


func test_a_mode_nobody_has_chosen_refuses_without_asking_any_model() -> void:
	_forget_questions()
	var answer: Dictionary = _identifier(ChoiceScript.default_settings()).identify_with(
		_photo(), CaptureScript.PART_WHOLE, "", _catalogue()
	)
	assert(not bool(answer["ok"]), "nothing is read by a program nobody has chosen anything for")
	assert(
		String(answer["reason"]).contains("name is yours to type"),
		"and the refusal says what happens instead: %s" % String(answer["reason"])
	)
	assert(_asked.is_empty(), "no request was built at all: %d" % _asked.size())


func test_a_photograph_that_is_not_there_is_refused_before_a_model_is_asked() -> void:
	_forget_questions()
	_answers.append(_answer([_plant(THYME_NAME, 0.9)]))
	var answer: Dictionary = _identifier(_settings(ChoiceScript.LOCAL)).identify_with(
		null, CaptureScript.PART_WHOLE, "", _catalogue()
	)
	assert(not bool(answer["ok"]), "there is nothing to send")
	assert(
		String(answer["reason"]).contains("no photograph"),
		"and the refusal says so: %s" % String(answer["reason"])
	)
	assert(_asked.is_empty(), "so no model was asked: %d" % _asked.size())


func test_the_hint_says_what_will_happen_to_the_photograph() -> void:
	var off: String = IdentifierScript.photo_hint_for(ChoiceScript.default_settings())
	assert(
		off.contains("no identification model"),
		"the off mode keeps the sentence this program has always said: %s" % off
	)
	var local: String = IdentifierScript.photo_hint_for(_settings(ChoiceScript.LOCAL))
	assert(local.contains("does not leave"), "a local model says the photograph stays: %s" % local)
	var waiting: String = IdentifierScript.photo_hint_for(_settings(ChoiceScript.ONLINE))
	assert(waiting.contains("key"), "a service with no key says what it is waiting for: %s" % waiting)
	var ready: Dictionary = _settings(ChoiceScript.ONLINE)
	ready[ChoiceScript.ONLINE_API_KEY] = "sk-a-key"
	assert(
		IdentifierScript.photo_hint_for(ready).contains("goes to the online service"),
		"and a service that is ready says the photograph goes to it"
	)


# --- how long a socket is given, and why it is not how long a model is given ------------------------
#
# The measurement, taken on this project's own Windows machine: a live socket reaches `STATUS_CONNECTED`
# in about thirteen milliseconds, while a port nobody is listening on **never leaves
# `STATUS_CONNECTING`** - `poll()` keeps answering OK and the status never becomes `STATUS_CANT_CONNECT`.
# So a dead address cannot be told from a slow server by the status alone, and only a shorter budget for
# connecting can tell them apart. Without it a mis-typed address costs the whole three minutes a model is
# allowed to think for, and the person is told their model was too slow.
#
# What the wire then *says* about each way it can fail is `HttpExchange`'s, and is tested in
# `tests/test_http_exchange.gd` along with the rest of the machine.


func test_a_socket_is_given_far_less_time_to_connect_than_a_model_is_given_to_answer() -> void:
	assert(
		IdentifierScript.CONNECT_SECONDS < IdentifierScript.WAIT_SECONDS,
		"connecting is a different question from answering: %.1f against %.1f"
		% [IdentifierScript.CONNECT_SECONDS, IdentifierScript.WAIT_SECONDS]
	)
	assert(
		IdentifierScript.CONNECT_SECONDS <= 5.0,
		"and short enough that a typo is not a wait: %.1f seconds" % IdentifierScript.CONNECT_SECONDS
	)

# --- the same pipeline, advanced one act at a time --------------------------------------------------


## A program must not freeze while a model thinks, so the pipeline can be driven one act at a time
## instead of being waited for inside one call. This is the machine `identify_with` drives, and it is the
## same machine a page's frame steps: the answer is the same, one step closer each time it is asked.
func test_a_reading_can_be_stepped_a_frame_at_a_time_and_answers_the_same_thing() -> void:
	var reader: PlantIdentifier = _identifier(_settings(ChoiceScript.LOCAL))
	_forget_questions()
	_answers.append(_answer([_plant(THYME_NAME, 0.88)]))
	var started: StringName = reader.begin_read(
		_photo(), CaptureScript.PART_LEAF, "by the gate", _catalogue()
	)
	assert(
		started == IdentifierScript.WORKING,
		"a reading with a model to ask is in flight: %s" % String(started)
	)
	assert(reader.reading_in_flight(), "and a page can see that it is")
	assert(
		_asked.is_empty(),
		"nothing has been asked yet, because beginning a reading is not doing one: %d" % _asked.size()
	)
	assert(
		String(reader.read_result()["reason"]).contains("has not been read"),
		"and a reading that has not finished refuses in words rather than inventing an answer: %s"
			% String(reader.read_result()["reason"])
	)
	assert(
		reader.step_read() == IdentifierScript.DONE,
		"one step finishes a reading that has no wire in it"
	)
	assert(not reader.reading_in_flight(), "with nothing left to wait for")
	var answer: Dictionary = reader.read_result()
	assert(bool(answer["ok"]), "and the answer is there: %s" % String(answer["reason"]))
	assert(
		String(answer["raw_taxon"]) == THYME_NAME,
		"naming the plant the model gave: %s" % String(answer["raw_taxon"])
	)


## What the page's frame asks before it decides to finish a reading in the calling frame or to wait: is
## this on a wire? A caller's own transport answers inside a step, so a reading driven by one is never
## something a page has to wait for.
func test_a_reading_that_answers_inside_a_step_is_not_put_on_a_wire() -> void:
	var reader: PlantIdentifier = _identifier(_settings(ChoiceScript.HYBRID))
	assert(not reader.waiting_on_the_wire(), "a reading that has not begun is not on a wire")
	reader.settings[ChoiceScript.ONLINE_API_KEY] = "sk-a-key"
	_forget_questions()
	_answers.append(_answer([_plant(THYME_NAME, 0.6)]))
	_answers.append(_answer([_plant(THYME_NAME, 0.9)]))
	reader.begin_read(_photo(), CaptureScript.PART_WHOLE, "", _catalogue())
	assert(
		not reader.waiting_on_the_wire(),
		"and one the caller's own transport answers is not either, however many acts it has"
	)
	var first: StringName = reader.step_read()
	assert(
		first == IdentifierScript.WORKING,
		"the mixed mode's first act answers and its second is begun: %s" % String(first)
	)
	assert(reader.step_read() == IdentifierScript.DONE, "and the second finishes the reading")
	var answer: Dictionary = reader.read_result()
	assert(bool(answer["ok"]), "with both models' answer: %s" % String(answer["reason"]))
	assert(
		String(answer["model_id"]).contains(", then "),
		"and both of them named: %s" % String(answer["model_id"])
	)


## The driver is nothing but the machine driven to completion, and this is where that is held: stepping a
## reading by hand and waiting for it inside one call are one answer, not two.
func test_driving_the_reading_by_hand_answers_what_identify_with_answers() -> void:
	_forget_questions()
	# Two readings are driven below and the transport hands out one answer each, so the lined-up answers
	# are the pair: what is being compared is how the machine is driven, not how many models answered.
	_answers.append(_answer([_plant(THYME_NAME, 0.88)]))
	_answers.append(_answer([_plant(THYME_NAME, 0.88)]))
	var called: Dictionary = _identifier(_settings(ChoiceScript.LOCAL)).identify_with(
		_photo(), CaptureScript.PART_LEAF, "by the gate", _catalogue()
	)
	var reader: PlantIdentifier = _identifier(_settings(ChoiceScript.LOCAL))
	reader.begin_read(_photo(), CaptureScript.PART_LEAF, "by the gate", _catalogue())
	while reader.step_read() == IdentifierScript.WORKING:
		pass
	var stepped: Dictionary = reader.read_result()
	assert(
		String(stepped["raw_taxon"]) == String(called["raw_taxon"]),
		"the same plant: %s against %s" % [String(stepped["raw_taxon"]), String(called["raw_taxon"])]
	)
	assert(
		is_equal_approx(float(stepped["confidence"]), float(called["confidence"])),
		"at the same confidence"
	)
	assert(
		String(stepped["model_id"]) == String(called["model_id"]),
		"naming the same model: %s against %s" % [String(stepped["model_id"]), String(called["model_id"])]
	)
	assert(bool(stepped["ok"]) == bool(called["ok"]), "and agreeing about whether it was read at all")
