extends Node
## Asking a machine which models it has running, and what it would take to fetch another one.
##
## Every server here is a **handed-over transport** rather than a socket, so a machine that is running
## Ollama, a machine that is running something else, and a machine with nothing on it are all just
## dictionaries in a test - the rules can be asked without a server, a download or a network.
##
## The one real fact in this file's fixtures is the size of `qwen2.5vl:3b` (3,200,627,168 bytes), which
## is what this project's own machine reports for it. Everything else is the *shape* of an answer, kept
## deliberately plain so that nothing here can be mistaken for a table of model sizes.

const Probe := preload("res://scripts/local_model_probe.gd")
const Fit := preload("res://scripts/device_model_fit.gd")
const Choice := preload("res://scripts/plant_id_choice.gd")

const LOCAL := "http://127.0.0.1:11434"


## What this project's own Ollama answers at `/api/tags`: five models, of which exactly one can see.
func _ollama_tags() -> String:
	return JSON.stringify({
		"models": [
			{"name": "qwen3:0.6b", "size": 522640472, "capabilities": ["completion", "tools"]},
			{"name": "qwen2.5vl:3b", "size": 3200627168, "capabilities": ["completion", "vision"]},
			{"name": "llama3.2:latest", "size": 2019393189, "capabilities": ["completion", "tools"]},
			{"name": "qwen3:8b-64k", "size": 5226404720, "capabilities": ["completion", "tools"]},
			{"name": "qwen3:8b", "size": 5226404720, "capabilities": ["completion", "tools"]},
		],
	})


## A server that answers some paths and not others, which is what every real one does: a runner has
## `/v1/models` and no `/api/tags`, and Ollama has both.
func _server(answers: Dictionary) -> Callable:
	return func(request: Dictionary) -> Dictionary:
		var path: String = String(request.get("path", ""))
		if answers.has(path):
			return answers[path]
		return {"status": 0, "body": "", "why": "nothing at %s" % path}


## The answer a real runner also gives at the models door, so that a fake answers both doors the way a
## server does. A fake that answered only Ollama's own door was modelling a server nobody runs - and it
## hid the ordering rule, which is that the common door is asked first.
func _models_door(named: String) -> Dictionary:
	return {"status": 200, "body": JSON.stringify({"data": [{"id": named}]}), "why": ""}


func test_the_models_a_server_lists_are_read_from_its_own_answer() -> void:
	var models: Array[Dictionary] = Probe.models_from_tags(_ollama_tags())
	assert(models.size() == 5, "all five of them: %d" % models.size())
	var found: Dictionary = {}
	for model: Dictionary in models:
		found[String(model["id"])] = model
	assert(found.has("qwen2.5vl:3b"), "named as the server names it: %s" % str(found.keys()))
	assert(
		int((found["qwen2.5vl:3b"] as Dictionary)["size_bytes"]) == 3200627168,
		"and its size, which is the number a person weighs a download against"
	)


func test_the_servers_own_capabilities_decide_what_can_see_even_against_the_name() -> void:
	# The two directions matter equally: a model this program has never heard of that says it can see is
	# offered, and a model whose name shouts `vl` but whose server says `completion` is not.
	var body: String = JSON.stringify({"models": [
		{"name": "mystery-model-9", "capabilities": ["completion", "vision"]},
		{"name": "qwen2.5vl:3b", "capabilities": ["completion"]},
	]})
	var models: Array[Dictionary] = Probe.models_from_tags(body)
	assert(bool(models[0]["vision"]), "a model that says it can see can see")
	assert(
		String(models[0]["whence"]) == "the server's own capabilities for it",
		"and the reading says where that came from: %s" % models[0]["whence"]
	)
	assert(
		not bool(models[1]["vision"]),
		"and one whose name says vl while its server says completion cannot"
	)


func test_a_server_that_says_nothing_about_capabilities_is_read_from_the_names_it_gives() -> void:
	var body: String = JSON.stringify({"models": [{"name": "qwen2.5vl:3b"}, {"name": "qwen3:8b"}]})
	var models: Array[Dictionary] = Probe.models_from_tags(body)
	assert(bool(models[0]["vision"]), "the name that says vl is read as one that can see")
	assert(not bool(models[1]["vision"]), "and the one that does not, is not")
	assert(
		String(models[0]["whence"]) == "this program's own reading of the model's name",
		"and the reading admits it is this program's guess rather than the server's answer"
	)


func test_the_models_door_every_runner_answers_is_read_too() -> void:
	var body: String = JSON.stringify({"data": [{"id": "qwen2.5vl:3b"}, {"id": "llama3.2:latest"}]})
	var models: Array[Dictionary] = Probe.models_from_openai(body)
	assert(models.size() == 2, "both ids: %d" % models.size())
	assert(bool(models[0]["vision"]), "the one whose name says vl can see")
	assert(not bool(models[1]["vision"]), "llama3.2 without a vision tag cannot")
	assert(
		int(models[0]["size_bytes"]) == Fit.UNKNOWN,
		"and a door that states no sizes leaves them unknown rather than zero"
	)


func test_a_reading_prefers_the_servers_own_list_because_only_it_says_what_can_see() -> void:
	var server: Callable = _server({
		"/api/tags": {"status": 200, "body": _ollama_tags(), "why": ""},
		"/v1/models": {"status": 200, "body": JSON.stringify({"data": [{"id": "qwen3:8b"}]}), "why": ""},
	})
	var reading: Dictionary = Probe.reading_for(LOCAL, server)
	assert(bool(reading["ok"]), "the server answered: %s" % reading["reason"])
	assert(
		(reading["models"] as Array).size() == 5,
		"the fuller list is the one that was read, not the shorter one beside it"
	)
	assert(
		String(reading["read_from"]).contains("says of each model whether it can see"),
		"and the reading says which door it came from: %s" % reading["read_from"]
	)


func test_a_runner_with_no_ollama_door_is_read_through_the_models_door_instead() -> void:
	var server: Callable = _server({
		"/v1/models": {"status": 200, "body": JSON.stringify({"data": [{"id": "llava:7b"}]}), "why": ""},
	})
	var reading: Dictionary = Probe.reading_for("http://127.0.0.1:8080", server)
	assert(
		bool(reading["ok"]),
		"a runner that answers only the models door is still read: %s" % reading["reason"]
	)
	assert((reading["models"] as Array).size() == 1, "with the one model it has")
	assert(
		String(reading["read_from"]).contains("whether the name says"),
		"and the reading says the answer came from a name: %s" % reading["read_from"]
	)


func test_the_address_a_reading_gives_back_is_one_the_identifier_will_accept() -> void:
	# The whole point of the reading is that a person can point the reading of a photograph at what was
	# found, so the address it hands back has to be the one the identifier is already held to - checked
	# here against the same defaults a page fills its fields from.
	var server: Callable = _server({
		"/v1/models": _models_door("qwen2.5vl:3b"),
		"/api/tags": {"status": 200, "body": _ollama_tags(), "why": ""},
	})
	var reading: Dictionary = Probe.reading_for(LOCAL, server)
	assert(
		String(reading["chat_url"]) == Choice.DEFAULT_LOCAL_URL,
		"the address is the door a local model is read through: %s" % reading["chat_url"]
	)
	var settings: Dictionary = Choice.default_settings()
	settings[Choice.MODE] = String(Choice.LOCAL)
	settings[Choice.LOCAL_URL] = String(reading["chat_url"])
	settings[Choice.LOCAL_MODEL] = String((reading["vision"] as Array)[0])
	var ready: Dictionary = Choice.readiness(settings)
	assert(
		bool(ready["ok"]),
		"and settings built out of a reading are ready to use: %s" % ready["reason"]
	)


func test_the_models_that_cannot_see_are_listed_apart_rather_than_hidden() -> void:
	var server: Callable = _server({
		"/v1/models": _models_door("qwen2.5vl:3b"),
		"/api/tags": {"status": 200, "body": _ollama_tags(), "why": ""},
	})
	var reading: Dictionary = Probe.reading_for(LOCAL, server)
	var vision: Array = reading["vision"]
	var text_only: Array = reading["text_only"]
	assert(vision.size() == 1 and String(vision[0]) == "qwen2.5vl:3b", "one can see: %s" % str(vision))
	assert(
		text_only.size() == 4,
		"and the four that only read text are named rather than dropped: %s" % str(text_only)
	)
	var summary: String = String(reading["summary"])
	assert(summary.contains("qwen2.5vl:3b"), "the summary says which can see: %s" % summary)
	assert(summary.contains("4 more"), "and how many cannot: %s" % summary)


func test_a_server_with_no_vision_model_says_so_rather_than_reporting_nothing() -> void:
	var body: String = JSON.stringify({"models": [{"name": "qwen3:8b", "capabilities": ["completion"]}]})
	var server: Callable = _server({
		"/v1/models": _models_door("qwen3:8b"),
		"/api/tags": {"status": 200, "body": body, "why": ""},
	})
	var reading: Dictionary = Probe.reading_for(LOCAL, server)
	assert(bool(reading["ok"]), "the server did answer, so there is a reading to show")
	assert((reading["vision"] as Array).is_empty(), "with no model that can look at a photograph")
	assert(
		String(reading["summary"]).contains("not one of them"),
		"and the reading says that in words rather than as an empty list: %s" % reading["summary"]
	)
	assert(
		Probe.first_with_vision({"readings": [reading]}).is_empty(),
		"so there is nothing in it for a page to point a photograph at"
	)


func test_a_server_that_is_not_there_is_refused_at_the_address_it_was_asked_at() -> void:
	var nowhere: Callable = _server({})
	var reading: Dictionary = Probe.reading_for(LOCAL, nowhere)
	assert(not bool(reading["ok"]), "nothing there is a refusal and not a reading of nothing")
	assert(
		String(reading["reason"]).contains(LOCAL),
		"and the refusal names the address that was asked: %s" % reading["reason"]
	)
	assert(
		String(reading["reason"]).contains("could not be asked"),
		"and the refusal is about the connection rather than about a slow server: %s" % reading["reason"]
	)


func test_an_address_that_answers_404_is_refused_with_the_number_it_answered() -> void:
	var server: Callable = _server({
		"/api/tags": {"status": 404, "body": "404 page not found", "why": ""},
		"/v1/models": {"status": 404, "body": "", "why": ""},
	})
	var reading: Dictionary = Probe.reading_for("http://127.0.0.1:9999", server)
	assert(not bool(reading["ok"]), "a page that is not a models list is not a models list")
	assert(
		String(reading["reason"]).contains("404"),
		"and the refusal says what the server answered: %s" % reading["reason"]
	)


func test_a_typed_address_is_tried_first_and_the_usual_two_after_it() -> void:
	var bases: Array[String] = Probe.candidate_bases("http://192.168.1.20:11434/")
	assert(
		bases[0] == "http://192.168.1.20:11434",
		"the address somebody typed comes first, and without a doubled slash: %s" % bases[0]
	)
	assert(bases.has(LOCAL), "and the machine in their hands is still asked")
	assert(
		bases.has("http://127.0.0.1:8080"),
		"and so is the other thing a model is likely to be served by: %s" % str(bases)
	)
	var plain: Array[String] = Probe.candidate_bases("")
	assert(
		plain.size() == 2,
		"with nothing typed there are the two this program knows about: %s" % str(plain)
	)


func test_probing_looks_at_every_address_and_keeps_the_one_that_answered() -> void:
	var server: Callable = func(request: Dictionary) -> Dictionary:
		if int(request.get("port", 0)) == 11434:
			if String(request.get("path", "")) == "/api/tags":
				return {"status": 200, "body": _ollama_tags(), "why": ""}
			return {"status": 200, "body": JSON.stringify({"data": [{"id": "qwen2.5vl:3b"}]}), "why": ""}
		return {"status": 0, "body": "", "why": "nothing there"}
	var probed: Dictionary = Probe.probe(server)
	assert(bool(probed["ok"]), "one of them answered: %s" % probed["reason"])
	assert(
		(probed["asked"] as Array).size() == 2,
		"both of the usual places were tried: %s" % str(probed["asked"])
	)
	assert((probed["readings"] as Array).size() == 1, "and only the one that answered is a reading")
	var found: Dictionary = Probe.first_with_vision(probed)
	assert(
		String(found.get("base_url", "")) == LOCAL,
		"the server to point a photograph at is the one with a model that can see: %s" % str(found)
	)


func test_no_server_anywhere_is_refused_naming_everywhere_that_was_tried() -> void:
	var probed: Dictionary = Probe.probe(_server({}))
	assert(not bool(probed["ok"]), "nothing running is the ordinary case, and still a refusal")
	for base: String in Probe.candidate_bases(""):
		assert(
			String(probed["reason"]).contains(base),
			"the refusal names %s so a person can see where was looked: %s" % [base, probed["reason"]]
		)
	assert(
		(probed["refusals"] as Array).size() == 2,
		"and each address's own reason is kept rather than merged into one"
	)


func test_the_fetch_a_person_asks_for_names_the_model_and_the_server() -> void:
	var request: Dictionary = Probe.pull_request(LOCAL, "qwen2.5vl:3b")
	assert(bool(request["ok"]), "a named model at a named server is a request: %s" % request["reason"])
	assert(int(request["method"]) == HTTPClient.METHOD_POST, "fetching is something a server is asked to do")
	assert(String(request["path"]) == "/api/pull", "at the door Ollama fetches models at")
	assert(int(request["port"]) == 11434, "and at the port of the server that was named")
	var reader: JSON = JSON.new()
	assert(reader.parse(String(request["body"])) == OK, "the body a request carries is JSON")
	var sent: Dictionary = reader.data
	assert(String(sent.get("model", "")) == "qwen2.5vl:3b", "which names the model: %s" % request["body"])
	assert(
		bool(sent.get("stream", false)),
		"and asks for the answer in steps, which is what lets a page show how far along it is"
	)


func test_a_fetch_with_no_model_named_is_refused_rather_than_sent() -> void:
	var request: Dictionary = Probe.pull_request(LOCAL, "   ")
	assert(not bool(request["ok"]), "there is nothing to fetch")
	assert(String(request["reason"]).contains("named"), "and the refusal names the field: %s" % request["reason"])
	assert(String(request["path"]).is_empty(), "nothing was built to send anywhere")


func test_a_download_line_is_read_as_progress_and_as_the_end_of_it() -> void:
	var starting: Dictionary = Probe.parse_pull_line(JSON.stringify({"status": "pulling manifest"}))
	assert(not bool(starting["done"]), "pulling the manifest is not yet having the model")
	assert(String(starting["words"]) == "pulling manifest", "it reads as the server worded it: %s" % starting["words"])
	var going: Dictionary = Probe.parse_pull_line(
		JSON.stringify({"status": "downloading", "total": 2000, "completed": 500})
	)
	assert(not bool(going["done"]), "a download in progress is not finished")
	assert(int(going["completed_bytes"]) == 500, "and it says how much has arrived")
	assert(
		String(going["words"]).contains("25%"),
		"and how far along that is, which is the only part a person reads: %s" % going["words"]
	)
	var finished: Dictionary = Probe.parse_pull_line(JSON.stringify({"status": "success"}))
	assert(bool(finished["done"]), "success is the end of it")
	assert(bool(finished["ok"]), "and not a refusal")
	var broken: Dictionary = Probe.parse_pull_line(
		JSON.stringify({"error": "pull model manifest: file does not exist"})
	)
	assert(not bool(broken["ok"]), "an error is a refusal")
	assert(not bool(broken["done"]), "and not the end of a download that worked")
	assert(
		String(broken["words"]).contains("does not exist"),
		"in the server's own words rather than in this program's: %s" % broken["words"]
	)


func test_a_download_that_has_completed_nothing_says_zero_rather_than_saying_nothing() -> void:
	# Zero is a reading here and not an absence: a download that has started has completed nothing yet,
	# which is a different thing from a line that did not say.
	var step: Dictionary = Probe.parse_pull_line(
		JSON.stringify({"status": "downloading", "total": 2000, "completed": 0})
	)
	assert(int(step["completed_bytes"]) == 0, "nothing completed yet: %d" % int(step["completed_bytes"]))
	assert(int(step["total_bytes"]) == 2000, "of a known whole")
	var unstated: Dictionary = Probe.parse_pull_line(JSON.stringify({"status": "pulling manifest"}))
	assert(
		int(unstated["completed_bytes"]) == Fit.UNKNOWN,
		"and a line that said nothing about bytes is unknown rather than zero"
	)


func test_a_line_that_is_not_json_is_a_refusal_rather_than_a_crash() -> void:
	var step: Dictionary = Probe.parse_pull_line("<html>a proxy said no</html>")
	assert(not bool(step["ok"]), "something that is not a step is a refusal")
	assert(
		String(step["reason"]).contains("could not be read"),
		"said in words, quoting what arrived: %s" % step["reason"]
	)
	assert(not bool(step["done"]), "and it is certainly not the end of a finished download")


func test_a_machine_that_cannot_be_reached_is_not_asked_a_second_question() -> void:
	# A connection that never happened is the end of the conversation. This is not only a saving on a
	# machine with nothing running: asking a second question of an address that answered nothing is how a
	# refusal comes to name the wrong thing.
	var asked: Array[String] = []
	var server: Callable = func(request: Dictionary) -> Dictionary:
		asked.append(String(request.get("path", "")))
		return {"status": 0, "body": "", "why": "no connection could be made to 127.0.0.1:8080"}
	var reading: Dictionary = Probe.reading_for("http://127.0.0.1:8080", server)
	assert(not bool(reading["ok"]), "nothing there is a refusal")
	assert(
		asked.size() == 1,
		"and exactly one question was put to a machine that is not there: %s" % str(asked)
	)
	assert(
		String(reading["reason"]).contains("no connection could be made"),
		"the refusal carries what actually happened rather than a timeout: %s" % reading["reason"]
	)


func test_a_machine_that_answers_is_asked_for_its_own_list_as_well() -> void:
	# The common door first so that a dead address costs one attempt, then the richer door, because the
	# common one does not say whether a model can see.
	var asked: Array[String] = []
	var server: Callable = func(request: Dictionary) -> Dictionary:
		var path: String = String(request.get("path", ""))
		asked.append(path)
		if path == "/api/tags":
			return {"status": 200, "body": _ollama_tags(), "why": ""}
		return {"status": 200, "body": JSON.stringify({"data": [{"id": "qwen3:8b"}]}), "why": ""}
	var reading: Dictionary = Probe.reading_for(LOCAL, server)
	assert(bool(reading["ok"]), "a machine that answers is read: %s" % reading["reason"])
	assert(asked.size() == 2, "both doors are asked of it: %s" % str(asked))
	assert(
		asked[0] == Probe.MODELS_PATH,
		"the door every runner answers comes first: %s" % str(asked)
	)
	assert(
		asked[1] == Probe.TAGS_PATH,
		"and the one only Ollama has comes second: %s" % str(asked)
	)
	assert(
		(reading["models"] as Array).size() == 5,
		"and the richer door is the one the reading was built from"
	)