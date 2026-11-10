class_name PlantIdLlm
extends RefCounted
## What is asked of a vision model, what the answer looks like on the wire, and what of it can be
## believed - all of it pure, so the shape of a request can be read and judged without a service to
## send it to and without a model to answer.
##
## ## One wire format, four doors
##
## OpenAI's chat-completions shape is what this speaks, because it is the shape a photograph is
## actually sent in today and because the three places a person is likely to point this at - a local
## server (Ollama, `llama.cpp`, vLLM), a hosted service, and anything compatible with either - all
## answer it. So there is **one** request builder here rather than one per service: what differs
## between a local model and an online one is an address, a model name and whether a key is needed,
## and those are settings rather than formats.
##
## ## Everything is a request before it is a send
##
## `build_request` returns the method, the host, the port, the path, the headers and the body and
## **sends nothing**. This is the same rule the ledger adapters and the sync transport keep
## (`scripts/biz/ledger_adapter.gd`, `scripts/biz/http_transport.gd`): the part a person can get wrong
## is the shape of what leaves, and that part is testable on a machine with no network at all. Sending
## is `PlantIdentifier`'s job, and it is the only place in this subsystem that touches the world.
##
## ## The answer is a record, and the prompt says so
##
## A vision model answers in prose unless it is told not to, and prose cannot be filed. Every prompt
## here asks for one JSON object and says what has to be in it, and `parse_response` reads that object
## back - including when a model wraps it in a markdown fence or writes a sentence of its own in front
## of it, both of which happen constantly. A model that cannot tell what the plant is is told to answer
## with an empty list rather than to guess, and that answer is refused by name here rather than turned
## into a name nobody can check.
##
## ## Two small things this file does that the project would want in one place
##
## `split_url` splits an address into scheme, host, port and prefix, and `_service_refusal` turns an
## HTTP status and a body into a sentence. Both already exist, in spirit, in
## `scripts/biz/http_transport.gd` (`_split_base`, `status_reason`) - written for the sync service
## before this subsystem existed. They are rewritten here rather than reached for, because the wrong
## direction of dependency (a plant identifier calling into the business sync transport) is worse than
## the duplication.
##
## `split_url` is **public**, because the second reader of an address has arrived: something that asks
## a machine which models it has running needs the same splitter, and a second splitter is a second set
## of answers about ports and paths. `_service_refusal` stays private - it words a bad answer from a
## *model*, and a caller reading a plain models list decides for itself what a bad status means.

const FieldCaptureScript := preload("res://scripts/field_capture.gd")

## How long the longest edge of a photograph may be before it is sent. A phone photograph is twelve
## million pixels and would arrive as a JSON body of tens of megabytes; a vision model looks at 768
## pixels of leaf as well as it looks at four thousand, and the smaller the photograph the faster the
## answer on a phone.
const DEFAULT_MAX_EDGE := 768

## The smallest a caller may ask a photograph to be. Below this it is not a downscale, it is a
## thumbnail a model cannot read anything from, so the floor is what a caller asking for less gets.
const MIN_MAX_EDGE := 64

const MIME := "image/png"

## A model asked for an identification is not being asked to write, and the temperature says so.
const TEMPERATURE := 0.1

## How many plants a single-model answer is asked for. Three are enough to choose between and few
## enough that the reasons stay about the plant.
const SINGLE_CANDIDATES := 3

## The PNG signature, base64-encoded. What is sent has to be a picture, and this is how a test can say
## so without decoding anything.
const PNG_IN_BASE64 := "iVBORw0KGgo"

## How much of an unreadable answer or a service's own error page is quoted back at a person. A whole
## HTML error page on a status line is not a message, it is a wall.
const QUOTE_LIMIT := 200

## The exact shape every prompt asks for. Written once here and put into each prompt, so the schema a
## model is told to answer in and the schema `parse_response` reads cannot drift apart.
const SCHEMA := (
	"{\"candidates\": [{\"raw_taxon\": \"the name you would give it\", \"confidence\": 0.0, "
	+ "\"reason\": \"what in the photograph made you say so\"}]}"
)


# --- the photograph ---------------------------------------------------------------------------


## A photograph as something a JSON body can carry: `{ok, reason, base64, mime, width, height}`.
##
## A copy is made and shrunk, never the caller's own image: that image belongs to the page that is
## showing it, and a photograph quietly resized here would come back to that page at the size a model
## asked for. An image that is not there, has no pixels, or cannot be written out is refused by name
## rather than sent as an empty picture - a model shown nothing answers with a guess.
static func encode_image(image: Image, max_edge: int = DEFAULT_MAX_EDGE) -> Dictionary:
	if image == null:
		return _encode_refusal("there is no photograph to send")
	if image.is_empty() or image.get_width() <= 0 or image.get_height() <= 0:
		return _encode_refusal("the photograph has no pixels in it, so there is nothing to send")
	var limit: int = max_edge if max_edge >= MIN_MAX_EDGE else MIN_MAX_EDGE
	var wide: int = image.get_width()
	var tall: int = image.get_height()
	var sent: Image = Image.new()
	sent.copy_from(image)
	if sent.is_compressed():
		# A compressed image cannot be resized or written out as a picture at all, so it is unwrapped
		# first - and an unwrap that fails is refused rather than sent on as something unreadable.
		if sent.decompress() != OK:
			return _encode_refusal("the photograph could not be unpacked into pixels, so there is nothing to send")
	var longest: int = maxi(wide, tall)
	if longest > limit:
		var shrink: float = float(limit) / float(longest)
		sent.resize(
			maxi(1, roundi(float(wide) * shrink)),
			maxi(1, roundi(float(tall) * shrink)),
			Image.INTERPOLATE_LANCZOS
		)
	var bytes: PackedByteArray = sent.save_png_to_buffer()
	if bytes.is_empty():
		return _encode_refusal("the photograph could not be written out as a picture that can be sent")
	return {
		"ok": true,
		"reason": "",
		"base64": Marshalls.raw_to_base64(bytes),
		"mime": MIME,
		"width": sent.get_width(),
		"height": sent.get_height(),
	}


# --- what is asked ----------------------------------------------------------------------------


## The question a local model is asked when it is doing the narrowing: up to `limit` plants, the most
## likely one first.
static func shortlist_prompt(part: StringName, note: String, limit: int) -> String:
	return _ask_prompt(part, note, limit)


## The question asked when one model is doing the whole job, local or online.
static func single_prompt(part: StringName, note: String) -> String:
	return _ask_prompt(part, note, SINGLE_CANDIDATES)


## The question the online half of a mixed mode is asked: the same photograph, and the plants the local
## model thought it might be.
##
## The shortlist is put to it as **candidates to choose between, not as an answer to confirm** - a model
## told "pick one of these" will pick one of these even when the photograph shows none of them, which
## would make the first model's mistake the last word. It is asked to name what it actually sees, and
## told that saying none of them fit is a better answer than a wrong one.
static func refine_prompt(part: StringName, note: String, shortlist: Array) -> String:
	var lines: Array[String] = []
	lines.append("Identify the plant in this photograph. It is a photograph of %s." % _part_words(part))
	var written: String = note.strip_edges()
	if not written.is_empty():
		lines.append("The person who took it wrote: \"%s\"." % written)
	if shortlist.is_empty():
		lines.append("No shortlist was made, so answer from the photograph alone.")
	else:
		lines.append(
			"A first look at this photograph, with no second opinion, offered these as possibilities:"
		)
		for index: int in shortlist.size():
			lines.append("- %s (%d%% sure): %s" % [
				String((shortlist[index] as Dictionary).get("raw_taxon", "")),
				roundi(float((shortlist[index] as Dictionary).get("confidence", 0.0)) * 100.0),
				String((shortlist[index] as Dictionary).get("reason", "")),
			])
		lines.append(
			"Choose between them if the photograph agrees with one of them. If none of them is what you "
			+ "see, say what you see instead - a name outside that list is a better answer than the wrong "
			+ "name inside it."
		)
	lines.append("")
	lines.append(_answer_rules(shortlist.size() if not shortlist.is_empty() else SINGLE_CANDIDATES))
	return "\n".join(PackedStringArray(lines))


## The rules every prompt ends with: the shape of the answer, how many plants, and what to do when the
## model is not sure.
##
## **"Not sure" and "no plant in the photograph" are two different answers, and the first version of
## these rules ran them together.** It said "if the photograph does not show enough to name the plant,
## answer with an empty list, because not knowing is a real answer and a guess is not" - which is true,
## and which the first reading of a real photograph against a real model showed a small model taking as
## the easy way out: asked about a clear photograph of one boxwood, `qwen2.5vl:3b` answered
## `{"candidates": []}` in **0.2 seconds**, twice, without appearing to look at it. The same photograph,
## the same prompt with this one sentence changed, and it answered in **2.7 seconds** with
## `Buxus sempervirens` at 0.9 - the species this program's own list has - and `Buxus microphylla` at
## 0.8 behind it.
##
## So the empty list is still here and still honest, and it now means the narrower thing it says: a
## photograph with no plant in it. An uncertain name is asked for **as an uncertain name**, because the
## program already knows what to do with one: the confidence travels with it, `FieldCapture`'s floors
## decide whether that counts as an identification, and a name below them is kept as "a name that was
## offered" rather than thrown away. An empty list throws that evidence away; a low number does not.
static func _answer_rules(limit: int) -> String:
	return (
		"Answer with JSON only: no sentence before it, no sentence after it, and no text outside the "
		+ "JSON. Answer in exactly this shape:\n%s\n"
		+ "Give up to %d plants, the one you are most sure of first. The confidence is your own, from "
		+ "0 to 1. When you are not sure which plant it is, name the plant it most resembles anyway and "
		+ "say so with a low confidence: a name you are unsure of, marked as unsure, is worth more than "
		+ "no name. Answer with an empty list only when the photograph shows no plant at all."
	) % [SCHEMA, maxi(limit, 1)]


static func _ask_prompt(part: StringName, note: String, limit: int) -> String:
	var lines: Array[String] = []
	lines.append("Identify the plant in this photograph. It is a photograph of %s." % _part_words(part))
	var written: String = note.strip_edges()
	if not written.is_empty():
		lines.append("The person who took it wrote: \"%s\"." % written)
	lines.append("")
	lines.append(_answer_rules(limit))
	return "\n".join(PackedStringArray(lines))


## Which part of the plant is in the photograph, in the model's terms - `FieldCapture`'s own words,
## because a classifier told which part it is looking at is being asked a much easier question, and a
## part this program has no word for is not described as one.
static func _part_words(part: StringName) -> String:
	var named: String = String(FieldCaptureScript.PART_NAMES.get(part, ""))
	if named.is_empty():
		return "the plant"
	return named


# --- the request ------------------------------------------------------------------------------


## Everything that would be sent to a vision model, and **nothing sent**: `{ok, reason, method, url,
## host, port, tls, path, headers, body}`.
##
## The key travels as a bearer header and only when one is stated, which is what makes one builder
## serve both halves: a local server on this machine is asked without a key and an online service is
## asked with one, and neither is asked for something it does not use.
static func build_request(
	url: String, model: String, api_key: String, prompt: String, image_base64: String
) -> Dictionary:
	var address: Dictionary = split_url(url)
	if not bool(address["ok"]):
		return _request_refusal(String(address["reason"]))
	var named: String = model.strip_edges()
	if named.is_empty():
		return _request_refusal("no model was named to ask, so there is nothing to ask it")
	if prompt.strip_edges().is_empty():
		return _request_refusal("nothing was asked about the photograph, so there is no request to build")
	if image_base64.strip_edges().is_empty():
		return _request_refusal("the photograph was not encoded, so there is nothing to send with the question")
	var headers: Array[String] = ["Content-Type: application/json", "Accept: application/json"]
	var key: String = api_key.strip_edges()
	if not key.is_empty():
		headers.append("Authorization: Bearer " + key)
	var body: Dictionary = {
		"model": named,
		"temperature": TEMPERATURE,
		"messages": [{
			"role": "user",
			"content": [
				{"type": "text", "text": prompt},
				{"type": "image_url", "image_url": {"url": "data:%s;base64,%s" % [MIME, image_base64]}},
			],
		}],
	}
	return {
		"ok": true,
		"reason": "",
		"method": HTTPClient.METHOD_POST,
		"url": String(address["url"]),
		"host": String(address["host"]),
		"port": int(address["port"]),
		"tls": bool(address["tls"]),
		"path": String(address["path"]),
		"headers": headers,
		"body": JSON.stringify(body),
	}


## An address as a client needs it: `{ok, reason, url, tls, host, port, path}`.
##
## The awkward addresses are the ones worth settling here rather than at a deployment: a port, a path,
## no scheme at all, or a scheme and nothing after it.
##
## Public because it is not only a model's address that has to be split: whoever asks a machine which
## models it has splits the same shape of address, and the path is carried through untouched - so
## `http://127.0.0.1:11434/api/tags` comes back with `/api/tags` as its path and needs no second rule.
static func split_url(address: String) -> Dictionary:
	var raw: String = address.strip_edges()
	var tls: bool = raw.begins_with("https://")
	if tls:
		raw = raw.substr(8)
	elif raw.begins_with("http://"):
		raw = raw.substr(7)
	else:
		return _url_refusal(
			"the address of a model has to begin http:// or https://, and \"%s\" does not" % address
		)
	var without_slash: String = raw.trim_suffix("/")
	if without_slash.is_empty():
		return _url_refusal("the address \"%s\" names no host to send a photograph to" % address)
	var slash: int = without_slash.find("/")
	var authority: String = without_slash if slash < 0 else without_slash.substr(0, slash)
	var path: String = "/" if slash < 0 else without_slash.substr(slash)
	var host: String = authority
	var port: int = 443 if tls else 80
	var colon: int = authority.rfind(":")
	if colon > 0:
		host = authority.substr(0, colon)
		port = int(authority.substr(colon + 1))
	if host.is_empty():
		return _url_refusal("the address \"%s\" names no host to send a photograph to" % address)
	return {"ok": true, "reason": "", "url": address, "tls": tls, "host": host, "port": port, "path": path}


# --- the answer -------------------------------------------------------------------------------


## What a model answered, as something this program can use: `{ok, reason, raw_taxon, confidence,
## candidates, model_id, model_version, answer}`.
##
## **`http_status` 0 means the request never arrived**, which is the project's own convention and a
## different thing from a service that answered badly: one is worth trying again and the other is not.
## Where the sender said *why* it never arrived - the transport's own `why`, naming the host or the
## clock - that sentence is the refusal, because "cannot reach 127.0.0.1" and "it did not answer within
## 180 seconds" want different things done about them and only the sender knows which happened.
##
## The order of the candidates is decided by their own confidences rather than by the order they were
## written in. The prompt asks for the likeliest first, but a prompt is not something a model is
## obliged to follow, and the first candidate is the one a capture is filed as - so the numbers, which
## are the model's own ranking, are what the order is read from.
static func parse_response(
	http_status: int, raw_body: String, model_label: String = "", transport_reason: String = ""
) -> Dictionary:
	if http_status == 0:
		var why: String = transport_reason.strip_edges()
		if not why.is_empty():
			return _answer_refusal(why)
		return _answer_refusal("the request never reached the model, so there is no answer to read")
	if http_status < 200 or http_status > 299:
		return _answer_refusal(_service_refusal(http_status, raw_body))
	var answered: Dictionary = _model_answer(raw_body)
	var answer: String = String(answered["text"])
	var record: Dictionary = _find_record(answer)
	if record.is_empty():
		return _answer_refusal(
			"what the model answered could not be read as JSON: %s" % _quote(answer), answer, model_label
		)
	var candidates: Array[Dictionary] = _candidates_of(record)
	if candidates.is_empty():
		if record.has("candidates"):
			return _answer_refusal(
				"the model could not tell what the plant is, and said so rather than guessing",
				answer,
				model_label
			)
		return _answer_refusal(
			"the model's answer named no plant, so there is nothing to look up: %s" % _quote(answer),
			answer,
			model_label
		)
	# The envelope's build first, then the answer's own if it named one: a server that says nothing
	# about which build it served has no version invented for it.
	var served: String = String(answered["model"]).strip_edges()
	if served.is_empty():
		served = String(record.get("model", "")).strip_edges()
	var configured: String = model_label.strip_edges()
	return {
		"ok": true,
		"reason": "",
		"raw_taxon": String(candidates[0]["raw_taxon"]),
		"confidence": float(candidates[0]["confidence"]),
		"candidates": candidates,
		"model_id": configured if not configured.is_empty() else served,
		"model_version": served if (not served.is_empty() and served != configured) else "",
		"answer": answer,
	}


## The model's own words, and which build of the model the service says served them: `{text, model}`.
##
## A service answers `{"choices":[{"message":{"content":"..."}}]}` and the model's answer is the
## content. A body that is not that shape is treated as the answer itself, so a server that returns the
## JSON the prompt asked for - which plenty of local ones do - comes through the same door.
##
## The two travel together because they arrive together and **from different places**: the words are
## inside the content, and the build that served them is a field of the envelope around it. Looking for
## the build inside the answer would never find it, which is how this was written the first time.
static func _model_answer(raw_body: String) -> Dictionary:
	var reader: JSON = JSON.new()
	if reader.parse(raw_body) != OK:
		return {"text": raw_body, "model": ""}
	var data: Variant = reader.data
	if not (data is Dictionary):
		return {"text": raw_body, "model": ""}
	var envelope: Dictionary = data
	var served: String = String(envelope.get("model", "")).strip_edges()
	var choices: Variant = envelope.get("choices", null)
	if not (choices is Array) or (choices as Array).is_empty():
		return {"text": raw_body, "model": served}
	var first: Variant = (choices as Array)[0]
	if not (first is Dictionary):
		return {"text": raw_body, "model": served}
	var message: Variant = (first as Dictionary).get("message", null)
	if not (message is Dictionary):
		return {"text": raw_body, "model": served}
	var content: Variant = (message as Dictionary).get("content", null)
	if content is String:
		return {"text": content, "model": served}
	return {"text": raw_body, "model": served}


## The JSON object inside an answer, wherever the model put it.
##
## From the first `{` to the last `}` rather than from the start of the text, which is what lets a
## markdown fence, a "Here is the answer:" and a trailing sentence all be ignored by one rule instead
## of three.
static func _find_record(answer: String) -> Dictionary:
	var opened: int = answer.find("{")
	var closed: int = answer.rfind("}")
	if opened < 0 or closed <= opened:
		return {}
	var reader: JSON = JSON.new()
	if reader.parse(answer.substr(opened, closed - opened + 1)) != OK:
		return {}
	var data: Variant = reader.data
	if data is Dictionary:
		return data
	return {}


## The candidates of an answer, cleaned: one entry per plant as `{raw_taxon, confidence, reason}`.
##
## An entry naming nothing is dropped, because a candidate with no name cannot be looked up and cannot
## be chosen. The same plant offered twice is one candidate, because a shortlist handed on with a
## duplicate in it and a row of buttons built from it would both be lying about how many there are.
static func _candidates_of(record: Dictionary) -> Array[Dictionary]:
	var raw: Variant = record.get("candidates", [])
	if not (raw is Array):
		var nothing: Array[Dictionary] = []
		return nothing
	var seen: Dictionary = {}
	var found: Array[Dictionary] = []
	for item: Variant in (raw as Array):
		if not (item is Dictionary):
			continue
		var taxon: String = String((item as Dictionary).get("raw_taxon", "")).strip_edges()
		if taxon.is_empty():
			continue
		var key: String = taxon.to_lower()
		if seen.has(key):
			continue
		seen[key] = true
		found.append({
			"raw_taxon": taxon,
			"confidence": _confidence((item as Dictionary).get("confidence", 0.0)),
			"reason": String((item as Dictionary).get("reason", "")).strip_edges(),
		})
	found.sort_custom(_likelier_first)
	return found


## The model's own numbers decide the order, highest first.
static func _likelier_first(left: Dictionary, right: Dictionary) -> bool:
	return float(left["confidence"]) > float(right["confidence"])


## A confidence as a number between nothing and certain.
##
## A model that said 1.2 means "certain" and is read as certain rather than refused: the number is a
## degree of belief, and a degree outside its range is still a degree rather than a broken answer. What
## is *not* readable is a confidence that is not a number at all, and that reads as no confidence -
## which the resolver will refuse downstream on its own floors, rather than this file deciding for it.
static func _confidence(raw: Variant) -> float:
	if raw is float or raw is int:
		return clampf(float(raw), 0.0, 1.0)
	return 0.0


## A service's own refusal, in its own words where it gave any.
static func _service_refusal(status: int, raw_body: String) -> String:
	var said: String = _error_sentence(raw_body)
	if said.is_empty():
		said = _quote(raw_body)
	if said.is_empty():
		return "the model's service answered %d and said nothing about why" % status
	return "the model's service answered %d: %s" % [status, said]


## The sentence a service put in its error body, if it put one there.
static func _error_sentence(raw_body: String) -> String:
	var reader: JSON = JSON.new()
	if reader.parse(raw_body) != OK:
		return ""
	var data: Variant = reader.data
	if not (data is Dictionary):
		return ""
	var error: Variant = (data as Dictionary).get("error", null)
	if error is String:
		return (error as String).strip_edges()
	if error is Dictionary:
		var message: Variant = (error as Dictionary).get("message", null)
		if message is String:
			return (message as String).strip_edges()
	return ""


## A short piece of something a person has to read on a status line.
static func _quote(text: String) -> String:
	var trimmed: String = text.strip_edges()
	if trimmed.length() <= QUOTE_LIMIT:
		return trimmed
	return trimmed.substr(0, QUOTE_LIMIT) + " ..."


# --- the shapes of a refusal -------------------------------------------------------------------


static func _encode_refusal(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "base64": "", "mime": "", "width": 0, "height": 0}


static func _url_refusal(reason: String) -> Dictionary:
	return {
		"ok": false, "reason": reason, "url": "", "tls": false, "host": "", "port": 0, "path": "",
	}


static func _request_refusal(reason: String) -> Dictionary:
	var headers: Array[String] = []
	return {
		"ok": false,
		"reason": reason,
		"method": 0,
		"url": "",
		"host": "",
		"port": 0,
		"tls": false,
		"path": "",
		"headers": headers,
		"body": "",
	}


static func _answer_refusal(reason: String, answer: String = "", model_label: String = "") -> Dictionary:
	var none: Array[Dictionary] = []
	return {
		"ok": false,
		"reason": reason,
		"raw_taxon": "",
		"confidence": 0.0,
		"candidates": none,
		"model_id": model_label,
		"model_version": "",
		"answer": answer,
	}