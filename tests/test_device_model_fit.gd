extends Node
## What a machine is, and which vision model it can carry.
##
## Every reading here is **handed over rather than taken**: the phone this project's own live checks
## were run on, a roomy desktop and a machine that will not say are all just numbers in a test, so the
## rules can be asked without saddling the runner with a device. `scan_this_device` is the one reader
## that touches the world, and it is asked only for the *shape* of its answer - which keys it has and
## whether anything in it claims a number it never read.

const Fit := preload("res://scripts/device_model_fit.gd")

const GB := 1000000000

## The phone this project was tested against, exactly as it answered: 3.37 GB of memory of which
## 0.75 GB was free, 21.8 GB of disk, eight cores and no graphics name it would give a program.
func _phone() -> Dictionary:
	return Fit.scan("Android", "SM-A166W", "erd8535", 8, 3370000000, 806637568, 22894824000, "")


## The machine this was written on: a Windows box with 31.8 GB of memory and a real graphics card.
func _desktop() -> Dictionary:
	return Fit.scan(
		"Windows", "82RF", "12th Gen Intel Core i7-12700H", 20, 31800000000, 8620000000, 472900000000,
		"NVIDIA GeForce RTX 3070"
	)


## A machine that would not say anything about itself.
func _silent() -> Dictionary:
	return Fit.scan("", "", "", -1, -1, -1, -1, "")


func test_a_machine_that_will_not_say_how_much_memory_it_has_is_unknown_and_never_zero() -> void:
	var reading: Dictionary = _silent()
	assert(reading["tier"] == Fit.TIER_UNKNOWN, "a machine nobody could read has no tier")
	var words: String = Fit.summary(reading)
	assert(
		not words.contains("0.0"),
		"nothing is printed as a size it never read, so there is no zero anywhere in it: %s" % words
	)
	assert(
		words.contains("not readable"),
		"and what could not be read is said in words instead: %s" % words
	)
	assert(
		Fit.bytes_words(Fit.UNKNOWN) == "an amount this machine did not say",
		"a size nobody stated is a sentence, not 0.0 GB"
	)


func test_the_tier_is_read_from_the_memory_the_device_reports() -> void:
	assert(Fit.tier_for(3370000000) == Fit.TIER_TIGHT, "a 3.4 GB phone is tight")
	assert(Fit.tier_for(6000000000) == Fit.TIER_WORKABLE, "6 GB is workable")
	assert(Fit.tier_for(8000000000) == Fit.TIER_COMFORTABLE, "8 GB is comfortable")
	assert(Fit.tier_for(31800000000) == Fit.TIER_ROOMY, "a workstation is roomy")
	assert(Fit.tier_for(Fit.UNKNOWN) == Fit.TIER_UNKNOWN, "and a reading nobody took has no tier")


func test_more_memory_free_than_the_machine_has_is_clamped_to_what_it_has() -> void:
	# Measured on this project's own Windows machine: `available` reported the commit limit - 57.8 GB
	# against 31.8 GB of memory - and nothing downstream may be sized against a number the box cannot
	# deliver.
	var reading: Dictionary = Fit.scan("Windows", "82RF", "cpu", 20, 31800000000, 57800000000, 1000000000, "")
	assert(
		reading["free_bytes"] == 31800000000,
		"free memory is clamped to the memory there is: %d" % int(reading["free_bytes"])
	)


func test_a_small_phone_is_sent_to_a_computer_on_the_wifi_rather_than_a_smaller_download() -> void:
	var told: Dictionary = Fit.suggest(_phone())
	assert(told["route"] == Fit.ROUTE_WIFI_COMPUTER, "the route is another machine, not a smaller model")
	assert(
		String(told["headline"]).contains("Wi-Fi"),
		"and the headline says where to put it: %s" % told["headline"]
	)
	assert(
		(told["fits"] as Array).is_empty(),
		"nothing is offered to run on this machine: %s" % str(told["fits"])
	)
	var seen: Array[String] = []
	for entry: Dictionary in Array(told["refused"]):
		seen.append(String(entry["reason"]))
	assert(
		seen.any(func(reason: String) -> bool: return reason.contains("Qwen2.5-VL 3B")),
		"and the model too big for it is refused by name with the machine's own numbers: %s" % str(seen)
	)


func test_a_model_that_fits_only_on_paper_is_offered_as_an_experiment_that_names_the_risk() -> void:
	# The phone has 0.75 GB free and 3.37 GB in the box, so the smallest model fits the spec sheet and
	# not the machine as it stands. That is worth saying out loud rather than hiding behind either
	# number.
	var told: Dictionary = Fit.suggest(_phone())
	var experiment: Dictionary = told["small_experiment"]
	assert(not experiment.is_empty(), "the smallest model is still offered as an experiment")
	assert(String(experiment["label"]) == "SmolVLM 500M", "named: %s" % experiment["label"])
	assert(
		String(experiment["warning"]).contains("stopped"),
		"with the risk it carries said out loud: %s" % experiment["warning"]
	)


func test_a_roomy_computer_is_told_the_largest_model_that_fits_rather_than_the_first_one() -> void:
	var told: Dictionary = Fit.suggest(_desktop())
	assert(told["route"] == Fit.ROUTE_THIS_DEVICE, "a desktop runs the model itself")
	var fits: Array = told["fits"]
	assert(fits.size() == Fit.MODELS.size(), "both models this program vouches for fit: %d" % fits.size())
	assert(
		String(fits[0]["label"]) == "Qwen2.5-VL 3B",
		"and the largest is the one recommended, not the first in the table: %s" % fits[0]["label"]
	)
	var headline: String = String(told["headline"])
	assert(headline.contains("Qwen2.5-VL 3B"), "the headline names it: %s" % headline)
	assert(headline.contains("3.2 GB"), "and says what it costs to fetch: %s" % headline)


func test_a_model_whose_whole_size_is_not_known_here_is_named_rather_than_offered() -> void:
	# Half a size is not a size: telling somebody "1 GB" who then needs a second file has told them
	# something false rather than something incomplete.
	var half_known: Dictionary = {
		"id": "half", "label": "Half a Model", "weights_bytes": 1000000000,
		"needs_mmproj": true, "projector_bytes": 0,
	}
	assert(Fit.download_bytes(half_known) == Fit.UNKNOWN, "the files together are not known")
	var why: String = Fit.skip_reason(half_known, _desktop())
	assert(why.contains("does not know the whole size"), "and it says which field is missing: %s" % why)
	assert(why.contains("Half a Model"), "and names the model: %s" % why)


func test_a_model_that_would_not_fit_the_disk_is_refused_over_the_disk_it_names() -> void:
	var huge: Dictionary = {
		"id": "huge", "label": "A Huge Model", "weights_bytes": 500000000000,
		"needs_mmproj": false, "projector_bytes": 0,
	}
	var why: String = Fit.skip_reason(huge, _phone())
	assert(why.contains("disk"), "the refusal is about the disk: %s" % why)
	assert(why.contains("21.8 GB") or why.contains("22.9 GB"), "and quotes what is free: %s" % why)


func test_what_a_model_needs_in_memory_is_its_files_plus_room_rather_than_a_number_written_down() -> void:
	var model: Dictionary = {"id": "m", "weights_bytes": 1000000000, "needs_mmproj": false}
	assert(
		Fit.ram_needed_bytes(model) == int(1000000000.0 * Fit.MODEL_HEADROOM) + Fit.RUNTIME_BYTES,
		"the arithmetic is the files plus the room they need: %d" % Fit.ram_needed_bytes(model)
	)
	var bigger: Dictionary = {"id": "b", "weights_bytes": 4000000000, "needs_mmproj": false}
	assert(
		Fit.ram_needed_bytes(bigger) > Fit.ram_needed_bytes(model),
		"a model of four times the size needs more memory, by the same rule"
	)


func test_a_text_only_model_is_not_offered_as_something_that_can_read_a_photograph() -> void:
	# This machine's own Ollama carries four text models and one vision model, and handing somebody
	# qwen3:8b as a plant reader wastes their afternoon.
	assert(not Fit.is_vision_model_id("qwen3:8b"), "a text model is not a vision model")
	assert(not Fit.is_vision_model_id("llama3.2:latest"), "nor is llama3.2 without its vision tag")
	assert(not Fit.is_vision_model_id(""), "and nothing named is nothing")
	assert(Fit.is_vision_model_id("qwen2.5vl:3b"), "the one that read the test photograph is one")
	assert(Fit.is_vision_model_id("llava:7b"), "and so is llava")
	assert(Fit.is_vision_model_id("llama3.2-vision:11b"), "and llama3.2's vision build")


func test_every_model_this_program_will_suggest_says_where_its_size_came_from() -> void:
	for model: Dictionary in Fit.MODELS:
		var label: String = String(model.get("label", model.get("id", "?")))
		assert(Fit.download_bytes(model) > 0, "%s has a size this program can vouch for" % label)
		assert(
			not String(model.get("size_whence", "")).strip_edges().is_empty(),
			"%s says where its size came from rather than asserting it" % label
		)
		assert(
			not String(model.get("why", "")).strip_edges().is_empty(),
			"and says in plain words what it is for: %s" % label
		)
		if bool(model.get("needs_mmproj", false)):
			assert(
				int(model.get("projector_bytes", 0)) > 0,
				"%s serves vision with two files and both sizes are known" % label
			)


func test_every_reader_this_program_offers_says_whether_vision_needs_a_second_file() -> void:
	for runner: Dictionary in Fit.RUNNERS:
		var label: String = String(runner.get("label", runner.get("id", "?")))
		assert(
			typeof(runner.get("two_files_needed")) == TYPE_BOOL,
			"%s answers the two-file question with a yes or a no" % label
		)
		assert(
			not String(runner.get("models_url", "")).is_empty(),
			"%s says the address a model list is read from" % label
		)
		assert(
			not String(runner.get("base_url", "")).is_empty(),
			"%s says where it answers in general" % label
		)


func test_the_summary_says_the_numbers_of_a_machine_in_the_words_a_person_would_use() -> void:
	var words: String = Fit.summary(_desktop())
	assert(words.contains("31.8 GB"), "the memory a person recognises: %s" % words)
	assert(words.contains("20 processors"), "and the processors: %s" % words)
	assert(words.contains("RTX 3070"), "and the card, when there is one: %s" % words)
	assert(
		Fit.summary(_phone()).contains("3.4 GB"),
		"a phone is described the same way: %s" % Fit.summary(_phone())
	)


func test_the_reading_the_world_gives_is_ipso_facto_a_reading_the_rules_accept() -> void:
	# The one reader that touches a machine has to hand back the shape the rest of this file expects,
	# or every rule above is being asked about a dictionary nobody will ever build.
	var reading: Dictionary = Fit.scan_this_device()
	for key: String in [
		"platform", "model_name", "cpu_name", "cores", "physical_bytes", "free_bytes",
		"disk_free_bytes", "gpu_name", "tier",
	]:
		assert(reading.has(key), "the live reading carries %s" % key)
	var told: Dictionary = Fit.suggest(reading)
	assert(told.has("headline"), "and a machine that can be read gets an answer, not a crash")
	assert(not String(told["headline"]).is_empty(), "and it is a sentence: %s" % told["headline"])