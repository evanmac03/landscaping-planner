class_name LocalModelProbe
extends RefCounted
## Asking a machine which models it has running, and what it would take to fetch another one.
##
## ## Why this is a question and not an assumption
##
## A person who has Ollama running already has a vision model on the machine, and this program has no
## way of knowing it unless it asks. Guessing - "assume the model the program's own default names" - is
## how somebody is told to install something they already have, or asked for a name they do not have.
## So the program asks, and reads the answer in whichever of the two shapes the server uses.
##
## ## The server's own answer beats this program's reading of a name
##
## Ollama says of each model whether it can see (`capabilities`), and that answer is used whenever it is
## given - in **both** directions. A model whose name says `vl` and whose capabilities say `completion`
## cannot see, and is not offered; a model this program has never heard of that says `vision` can, and
## is. Where a server says nothing, the name is read instead and the reading says so, so a page can be
## honest about which of the two it is showing. That is `DeviceModelFit.is_vision_model_id`'s job, and
## it is deliberately narrow.
##
## ## The two shapes
##
## `/api/tags` is Ollama's own door: ids together with each model's size and capabilities. `/v1/models`
## is the OpenAI-shaped one every runner answers - `llama-server` has it and has no `/api/tags` at all -
## but it carries ids only. Both are read, the richer one first, and a server that answers neither is
## refused naming the address it was asked at rather than reported as having nothing.
##
## ## What is not here
##
## This file builds a request and reads an answer; it does not *wait* for one. Stepping a request across
## frames is `HttpExchange`'s job, and it has to be, because a model being fetched is a gigabyte arriving
## over minutes - a page that waited inside a call for that would draw no frame while it happened.
## Sending one request is `PlantIdentifier.send_http`, and the address is split by the same
## `PlantIdLlm.split_url` the plant identifier uses, so a port or a path means one thing in this program.

const Llm := preload("res://scripts/plant_id_llm.gd")
const Fit := preload("res://scripts/device_model_fit.gd")
const Identifier := preload("res://scripts/plant_identifier.gd")

## How long a machine is given to say which models it has. Asking a local server answers in milliseconds
## and a server on the network in about a second; anything slower than this is not a server that is
## going to answer, and a person is waiting in front of the page.
const PROBE_SECONDS := 2.0

## The list of models a runner answers at, in the two shapes this program reads.
const MODELS_PATH := "/v1/models"
const TAGS_PATH := "/api/tags"
const PULL_PATH := "/api/pull"


## Every address a model server is likely to be at, the one a person typed first when there is one.
##
## A typed address comes first because somebody who typed one means it, and the usual two are tried
## after it rather than instead of it: a person who has just been told to install Ollama on a computer
## down the hall does not know that computer's address yet, and this program's own two guesses are how
## they find out whether anything is running on the machine in their hands.
static func candidate_bases(custom_url: String = "") -> Array[String]:
	var bases: Array[String] = []
	var typed: String = clean_base(custom_url)
	if not typed.is_empty():
		bases.append(typed)
	for runner: Dictionary in Fit.RUNNERS:
		var base: String = clean_base(String(runner.get("base_url", "")))
		if not base.is_empty() and not bases.has(base):
			bases.append(base)
	return bases


## An address without a trailing slash, so that a path can be added to it without doubling one.
static func clean_base(base_url: String) -> String:
	return base_url.strip_edges().trim_suffix("/")


## The request that asks a runner for the models it has, in the shape every runner answers.
static func models_request(base_url: String) -> Dictionary:
	return _get_request("%s%s" % [clean_base(base_url), MODELS_PATH], "the models it lists at %s" % MODELS_PATH)


## The request that asks Ollama for its own list, which is the one that carries sizes and capabilities.
static func tags_request(base_url: String) -> Dictionary:
	return _get_request("%s%s" % [clean_base(base_url), TAGS_PATH], "its list of models")


## The request that fetches a model, as Ollama builds it.
##
## `stream` is the difference between watching a download and waiting for one: streamed, Ollama sends a
## line per step (`pulling manifest`, then the byte counts, then `success`), which is what lets a page
## say how far along it is. A body that says `{"model": ..., "stream": true}` is not a gigabyte of
## answer - Ollama keeps the connection open and sends the lines as they happen.
static func pull_request(base_url: String, model_tag: String, stream: bool = true) -> Dictionary:
	var clean: String = clean_base(base_url)
	var tag: String = model_tag.strip_edges()
	if tag.is_empty():
		return {
			"ok": false, "reason": "a model to fetch has to be named, and none was given",
			"url": "", "tls": false, "host": "", "port": 0, "path": "", "method": 0,
			"headers": [] as Array, "body": "",
		}
	var request: Dictionary = _get_request("%s%s" % [clean, PULL_PATH], "the model being fetched")
	if not bool(request["ok"]):
		return request
	request["method"] = HTTPClient.METHOD_POST
	request["headers"] = ["Content-Type: application/json", "Accept: application/x-ndjson"] as Array
	request["body"] = JSON.stringify({"model": tag, "stream": stream})
	return request


## Which models a server says it has, and which of them can look at a photograph, as
## `{ok, reason, base_url, chat_url, models, vision, text_only, read_from, summary}`.
##
## The models door is asked first because every runner answers it, and because a connection that never
## happened is the end of the conversation: there is no sense putting a second question to a machine
## that is not there, and on a machine with nothing running it is the difference between one connection
## attempt and two. Ollama's own list is asked second, because it is the only one of the two that says
## whether a model can see - and a runner that is not Ollama answering 404 there is a *no*, not a fault.
static func reading_for(base_url: String, transport: Callable) -> Dictionary:
	var clean: String = clean_base(base_url)
	if clean.is_empty():
		return _refusal("no address was given to ask which models are running")
	var listed: Dictionary = _ask(models_request(clean), transport)
	if not _reached(listed):
		return _refusal(_nothing_listening(clean, listed))
	var tags: Dictionary = _ask(tags_request(clean), transport)
	var models: Array[Dictionary] = []
	var read_from: String = ""
	if _answered(tags):
		models = models_from_tags(String(tags.get("body", "")))
		if not models.is_empty():
			read_from = "the server's own list, which says of each model whether it can see"
	if models.is_empty() and _answered(listed):
		models = models_from_openai(String(listed.get("body", "")))
		if not models.is_empty():
			read_from = (
				"the ids the server lists, read for whether the name says it can see"
			)
	if models.is_empty():
		return _refusal(_nothing_found(clean, listed, tags))
	return {
		"ok": true,
		"reason": "",
		"base_url": clean,
		"chat_url": "%s/v1/chat/completions" % clean,
		"models": models,
		"vision": _ids_where(true, models),
		"text_only": _ids_where(false, models),
		"read_from": read_from,
		"summary": _reading_summary(clean, models),
	}


## Every address worth trying, the ones that answered, and for the ones that did not, why - as
## `{ok, reason, asked, readings, refusals}`.
##
## A machine with nothing running on it is the ordinary case rather than a fault, so the refusal says
## what was asked and what came back, and the page above this uses that to say where to go next.
static func probe(transport: Callable, custom_url: String = "") -> Dictionary:
	var asked: Array[String] = candidate_bases(custom_url)
	var readings: Array[Dictionary] = []
	var refusals: Array[String] = []
	for base: String in asked:
		var reading: Dictionary = reading_for(base, transport)
		if bool(reading["ok"]):
			readings.append(reading)
		else:
			refusals.append(String(reading["reason"]))
	if readings.is_empty():
		return {
			"ok": false,
			"reason": (
				"nothing answered at %s, so no model server is running there"
				% ", ".join(asked)
			),
			"asked": asked,
			"readings": readings,
			"refusals": refusals,
		}
	return {
		"ok": true,
		"reason": "",
		"asked": asked,
		"readings": readings,
		"refusals": refusals,
	}


## The first server that answered with a model able to look at a photograph, or an empty dictionary.
##
## The one a page acts on: a machine can be running several servers and only some of them carry a vision
## model, and the one to point the reading at is the one with the model rather than the first to answer.
static func first_with_vision(probed: Dictionary) -> Dictionary:
	for reading: Dictionary in Array(probed.get("readings", [])):
		if not Array(reading.get("vision", [])).is_empty():
			return reading
	return {}


## The models in Ollama's own shape: `{"models": [{"name", "size", "capabilities"}]}`.
##
## `capabilities` is passed through as it was found rather than reduced to a yes or no here, so that
## "the server said nothing" and "the server said it cannot see" stay the two different answers they are.
static func models_from_tags(raw_body: String) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var data: Variant = _json(raw_body)
	if not (data is Dictionary):
		return found
	var listed: Variant = (data as Dictionary).get("models", [])
	if not (listed is Array):
		return found
	for one: Variant in (listed as Array):
		if not (one is Dictionary):
			continue
		var record: Dictionary = one
		var named: String = String(record.get("name", record.get("model", ""))).strip_edges()
		if named.is_empty():
			continue
		found.append(_a_model(named, record.get("size", 0), record.get("capabilities", null)))
	return found


## The models in the OpenAI shape: `{"data": [{"id"}]}`, which every runner answers and which says
## nothing about seeing.
static func models_from_openai(raw_body: String) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var data: Variant = _json(raw_body)
	if not (data is Dictionary):
		return found
	var listed: Variant = (data as Dictionary).get("data", [])
	if not (listed is Array):
		return found
	for one: Variant in (listed as Array):
		if not (one is Dictionary):
			continue
		var record: Dictionary = one
		var named: String = String(record.get("id", "")).strip_edges()
		if named.is_empty():
			continue
		found.append(_a_model(named, record.get("size", 0), record.get("capabilities", null)))
	return found


## One line of Ollama's streamed answer to a fetch, as
## `{ok, reason, done, status, completed_bytes, total_bytes, error, words}`.
##
## The lines arrive one per step and mean three different things: a status on its own ("pulling
## manifest"), a status with byte counts ("downloading"), and the last line ("success"). A line that
## says `error` is a refusal in the server's own words, and one that is not JSON at all is a refusal
## rather than a crash - a server that has started sending something else is worth saying so about.
##
## A completed count of **zero** is a real reading here rather than an absence: a download that has
## started has completed nothing yet, and that is different from a line that did not say.
static func parse_pull_line(line: String) -> Dictionary:
	var trimmed: String = line.strip_edges()
	if trimmed.is_empty():
		return _pull_step("", Fit.UNKNOWN, Fit.UNKNOWN, "")
	var data: Variant = _json(trimmed)
	if not (data is Dictionary):
		return {
			"ok": false,
			"reason": "the download answered with something that could not be read: %s" % trimmed,
			"done": false,
			"status": "",
			"completed_bytes": Fit.UNKNOWN,
			"total_bytes": Fit.UNKNOWN,
			"error": "",
			"words": "",
		}
	var record: Dictionary = data
	var error: String = String(record.get("error", "")).strip_edges()
	var status: String = String(record.get("status", "")).strip_edges()
	var completed: int = int(record.get("completed", Fit.UNKNOWN))
	var total: int = int(record.get("total", Fit.UNKNOWN))
	return _pull_step(status, completed, total, error)


## One server's reading in the words a person would say it in: what can see, and how much cannot.
static func reading_words(reading: Dictionary) -> String:
	return String(reading.get("summary", ""))


## One model from a server, with where the answer about whether it can see came from.
##
## The two provenances are kept apart on purpose: "the server said it can see" and "this program read its
## name" are worth different amounts, and a page that showed them as the same fact would be claiming
## more than it knows.
static func _a_model(named: String, size_bytes: Variant, capabilities: Variant) -> Dictionary:
	var size: int = int(size_bytes) if int(size_bytes) > 0 else Fit.UNKNOWN
	if capabilities is Array:
		var can_see: bool = false
		for one: Variant in (capabilities as Array):
			if String(one).to_lower() == "vision":
				can_see = true
		return {
			"id": named, "size_bytes": size, "vision": can_see,
			"whence": "the server's own capabilities for it",
		}
	return {
		"id": named, "size_bytes": size, "vision": Fit.is_vision_model_id(named),
		"whence": "this program's own reading of the model's name",
	}


## A pull line as one step of a download.
static func _pull_step(status: String, completed: int, total: int, error: String) -> Dictionary:
	var done: bool = error.is_empty() and (
		status == "success" or (total != Fit.UNKNOWN and completed != Fit.UNKNOWN and completed >= total)
	)
	return {
		"ok": error.is_empty(),
		"reason": error,
		"done": done,
		"status": status,
		"completed_bytes": completed,
		"total_bytes": total,
		"error": error,
		"words": _pull_words(status, completed, total, error),
	}


## What a step of a download reads as on a status line.
static func _pull_words(status: String, completed: int, total: int, error: String) -> String:
	if not error.is_empty():
		return error
	if status == "success":
		return "the model is fetched and ready to use"
	var counted: bool = (
		total != Fit.UNKNOWN and total > 0 and completed != Fit.UNKNOWN and completed >= 0
	)
	if counted:
		var percent: int = int(float(completed) / float(total) * 100.0)
		return "%s: %s of %s, %d%%" % [
			status if not status.is_empty() else "downloading",
			Fit.bytes_words(completed),
			Fit.bytes_words(total),
			percent,
		]
	if not status.is_empty():
		return status
	return "the download has started"


## The ids of the models that can, or cannot, look at a photograph.
static func _ids_where(can_see: bool, models: Array[Dictionary]) -> Array[String]:
	var ids: Array[String] = []
	for model: Dictionary in models:
		if bool(model.get("vision", false)) == can_see:
			ids.append(String(model["id"]))
	return ids


static func _reading_summary(clean: String, models: Array[Dictionary]) -> String:
	var vision: Array[String] = _ids_where(true, models)
	var text: Array[String] = _ids_where(false, models)
	if vision.is_empty():
		return "at %s there are %d models and not one of them can look at a photograph" % [
			clean, models.size(),
		]
	if text.is_empty():
		return "at %s, %s can look at a photograph" % [clean, ", ".join(vision)]
	return "at %s, %s can look at a photograph, and %d more can only read text" % [
		clean, ", ".join(vision), text.size(),
	]


## Whether a request got as far as the machine at all.
##
## A transport that says so is believed, and one that does not is read from its status - which is the
## convention every transport in this program keeps: status 0 means the request never arrived.
static func _reached(sent: Dictionary) -> bool:
	return bool(sent.get("reached", int(sent.get("status", 0)) != 0))


## Why an address could not even be asked, in the sender's own words.
##
## Nothing listening and nothing answering are different faults with different fixes, and this is the
## half that can say which: a connection that was never made is a server that is not running, and the
## sentence names the address rather than reporting a slow machine.
static func _nothing_listening(clean: String, sent: Dictionary) -> String:
	return "%s could not be asked: %s" % [
		clean, String(sent.get("why", "the connection was never made")),
	]


## Why an address answered without anything this program could read as a list of models.
static func _nothing_found(clean: String, listed: Dictionary, tags: Dictionary) -> String:
	return "nothing at %s answered with a list of models (%s, and %s)" % [
		clean,
		_one_reason(clean, listed, MODELS_PATH),
		_one_reason(clean, tags, "its own list"),
	]


static func _one_reason(clean: String, sent: Dictionary, what: String) -> String:
	var status: int = int(sent.get("status", 0))
	if status == 0:
		return String(sent.get("why", "nothing answered"))
	return "%s answered %d for %s" % [clean, status, what]


## One request, answered by the transport a caller handed over or by this subsystem's own sender.
static func _ask(request: Dictionary, transport: Callable) -> Dictionary:
	if not bool(request.get("ok", false)):
		return {"status": 0, "body": "", "why": String(request.get("reason", ""))}
	if transport.is_valid():
		return transport.call(request)
	return Identifier.send_http(request, PROBE_SECONDS)


static func _answered(sent: Dictionary) -> bool:
	var status: int = int(sent.get("status", 0))
	return status >= 200 and status <= 299


## A GET for one path, in the request shape `PlantIdentifier.send_http` takes.
##
## The address is split by `PlantIdLlm.split_url`, so a host, a port and a path mean the same thing here
## as they do when a photograph is sent - and an address nobody can split is refused here rather than
## sent at a machine that will never answer.
static func _get_request(url: String, what: String) -> Dictionary:
	var address: Dictionary = Llm.split_url(url)
	if not bool(address["ok"]):
		return {
			"ok": false, "reason": String(address["reason"]), "url": url, "tls": false,
			"host": "", "port": 0, "path": "", "method": HTTPClient.METHOD_GET,
			"headers": [] as Array, "body": "",
		}
	return {
		"ok": true,
		"reason": "",
		"url": url,
		"tls": bool(address["tls"]),
		"host": String(address["host"]),
		"port": int(address["port"]),
		"path": String(address["path"]),
		"method": HTTPClient.METHOD_GET,
		"headers": ["Accept: application/json"] as Array,
		"body": what,
	}


static func _refusal(reason: String) -> Dictionary:
	return {
		"ok": false,
		"reason": reason,
		"base_url": "",
		"chat_url": "",
		"models": [] as Array[Dictionary],
		"vision": [] as Array[String],
		"text_only": [] as Array[String],
		"read_from": "",
		"summary": "",
	}


## Parsed JSON, or nothing - by `JSON.new().parse` and never `JSON.parse_string`, because a caller that
## cannot tell a failure from an empty answer cannot say which happened.
static func _json(raw_body: String) -> Variant:
	var reader: JSON = JSON.new()
	if reader.parse(raw_body) != OK:
		return null
	return reader.data