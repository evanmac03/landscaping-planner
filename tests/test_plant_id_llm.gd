## What is asked of a vision model, what the answer looks like on the wire, and what of it can be
## believed - held down without a server, a model or a network.
##
## The rules held here are the ones that decide whether a photograph can be sent at all and whether
## what comes back is worth filing: the picture is shrunk without the page's own copy being touched, a
## local model is asked without a key and an online one with it, a markdown fence does not hide an
## answer, the model's own confidences decide the order, and a model that says it cannot tell is
## refused rather than pressed for a guess.
extends Node

const LlmScript := preload("res://scripts/plant_id_llm.gd")

const THYME := "Thymus serpyllum"
const BOX := "Buxus sempervirens"
const LOCAL_URL := "http://127.0.0.1:11434/v1/chat/completions"
const LOCAL_MODEL := "llava:7b"
const ONLINE_URL := "https://api.openai.com/v1/chat/completions"
const ONLINE_MODEL := "gpt-4o-mini"


# --- the things a test needs ---------------------------------------------------------------


## A photograph the size of a phone's, and green, so that what is encoded is a real picture of real
## pixels rather than an empty one that would be refused before anything was built.
func _photo(wide: int = 1200, tall: int = 800) -> Image:
	var made: Image = Image.create_empty(wide, tall, false, Image.FORMAT_RGBA8)
	made.fill(Color(0.18, 0.42, 0.20))
	return made


func _encoded() -> String:
	return String(LlmScript.encode_image(_photo(), 128)["base64"])


func _candidate(taxon: String, confidence: float, reason: String = "") -> Dictionary:
	return {"raw_taxon": taxon, "confidence": confidence, "reason": reason}


func _answer_of(candidates: Array) -> String:
	return JSON.stringify({"candidates": candidates})


## What a service's answer looks like: the model's own words nested in the envelope around them.
func _envelope(answer: String, served: String = "") -> String:
	var record: Dictionary = {"choices": [{"message": {"content": answer}}]}
	if not served.is_empty():
		record["model"] = served
	return JSON.stringify(record)


func _header_named(headers: Array, prefix: String) -> String:
	for header: Variant in headers:
		if String(header).begins_with(prefix):
			return String(header)
	return ""


# --- the photograph ------------------------------------------------------------------------


func test_an_image_that_is_not_there_is_refused_before_anything_is_built() -> void:
	var missing: Dictionary = LlmScript.encode_image(null)
	assert(not bool(missing["ok"]), "there is nothing to send")
	assert(
		String(missing["reason"]).contains("no photograph"),
		"and the refusal says what is missing: %s" % String(missing["reason"])
	)

	var blank: Dictionary = LlmScript.encode_image(Image.new())
	assert(not bool(blank["ok"]), "an image with no pixels in it is not a photograph")
	assert(
		String(blank["reason"]).contains("no pixels"),
		"and the refusal says which: %s" % String(blank["reason"])
	)

	# And the request builder refuses an unencoded photograph rather than sending a body with nothing in
	# it, which a model would answer with a guess about nothing.
	var request: Dictionary = LlmScript.build_request(LOCAL_URL, LOCAL_MODEL, "", "what is this?", "")
	assert(not bool(request["ok"]), "there is nothing to send with the question either")
	assert(String(request["reason"]).contains("photograph"), "and it says so: %s" % String(request["reason"]))


func test_a_large_photograph_is_shrunk_for_sending_and_the_one_on_the_page_is_left_alone() -> void:
	var photo: Image = _photo(1200, 800)
	var encoded: Dictionary = LlmScript.encode_image(photo)
	assert(bool(encoded["ok"]), "a photograph is encoded: %s" % String(encoded["reason"]))
	assert(int(encoded["width"]) == 768, "shrunk to the longest edge it is allowed: %d" % int(encoded["width"]))
	assert(int(encoded["height"]) == 512, "with its shape kept: %d" % int(encoded["height"]))
	assert(String(encoded["mime"]) == "image/png", "and sent as a picture")
	# Not just "some bytes": the signature proves what was encoded is really a PNG.
	assert(
		String(encoded["base64"]).begins_with(LlmScript.PNG_IN_BASE64),
		"and what is encoded begins with the signature of a PNG"
	)
	# The image the page is showing is the page's, and a photograph shrunk underneath it would come
	# back smaller than the person left it.
	assert(photo.get_width() == 1200 and photo.get_height() == 800, "while the page's own copy is untouched")


# --- the request ---------------------------------------------------------------------------


func test_a_request_to_a_model_on_this_machine_carries_no_key_and_is_built_for_its_host() -> void:
	var request: Dictionary = LlmScript.build_request(
		LOCAL_URL, LOCAL_MODEL, "", LlmScript.single_prompt(&"leaf", ""), _encoded()
	)
	assert(bool(request["ok"]), "the request is built: %s" % String(request["reason"]))
	assert(int(request["method"]) == HTTPClient.METHOD_POST, "a photograph is posted")
	assert(String(request["host"]) == "127.0.0.1", "to the host the address names: %s" % String(request["host"]))
	assert(int(request["port"]) == 11434, "on the port it names: %d" % int(request["port"]))
	assert(not bool(request["tls"]), "and not over TLS, because it is a plain local address")
	assert(
		String(request["path"]) == "/v1/chat/completions",
		"at the path it names: %s" % String(request["path"])
	)
	assert(
		_header_named(request["headers"], "Authorization").is_empty(),
		"a model on this machine is asked without a key: %s" % str(request["headers"])
	)
	var body: String = String(request["body"])
	assert(body.contains(LOCAL_MODEL), "the body names the model to ask")
	assert(body.contains("data:image/png;base64,"), "and carries the photograph as a data URL")
	assert(body.contains("Identify the plant"), "along with the question")


func test_a_request_to_a_service_carries_the_key_it_was_given() -> void:
	var request: Dictionary = LlmScript.build_request(
		ONLINE_URL, ONLINE_MODEL, "  sk-a-key  ", LlmScript.single_prompt(&"whole", ""), _encoded()
	)
	assert(bool(request["ok"]), "the request is built: %s" % String(request["reason"]))
	assert(String(request["host"]) == "api.openai.com", "to the host the address names")
	assert(int(request["port"]) == 443, "on the port a secure address defaults to")
	assert(bool(request["tls"]), "over TLS")
	assert(
		_header_named(request["headers"], "Authorization") == "Authorization: Bearer sk-a-key",
		"and the key travels as a bearer header, without the spaces a person typed round it: %s"
				% _header_named(request["headers"], "Authorization")
	)


func test_an_address_that_is_not_one_is_refused_by_name() -> void:
	for wrong: String in ["127.0.0.1:11434", "localhost", "", "   ", "ftp://example.test/v1"]:
		var request: Dictionary = LlmScript.build_request(
			wrong, LOCAL_MODEL, "", LlmScript.single_prompt(&"whole", ""), _encoded()
		)
		assert(not bool(request["ok"]), "\"%s\" is not an address a photograph is sent to" % wrong)
		assert(
			String(request["reason"]).contains("http://"),
			"and the refusal says what an address has to look like: %s" % String(request["reason"])
		)


# --- what is asked -------------------------------------------------------------------------


func test_the_shortlist_the_local_model_offered_is_named_back_to_the_online_model() -> void:
	var shortlist: Array = [
		_candidate(THYME, 0.62, "small opposite leaves, creeping habit"),
		_candidate(BOX, 0.20, "small leaves, could be clipped"),
	]
	var prompt: String = LlmScript.refine_prompt(&"leaf", "by the gate", shortlist)
	assert(prompt.contains(THYME), "every candidate the first look offered is named: %s" % prompt)
	assert(prompt.contains(BOX), "including the second one")
	assert(prompt.contains("62%"), "with the confidence the first look put on it")
	assert(prompt.contains("by the gate"), "and the note the person wrote")
	assert(prompt.contains("a leaf"), "and which part of the plant is in the photograph")
	# A model told "pick one of these" picks one of these even when the photograph shows none of them.
	assert(
		prompt.contains("outside that list is a better answer"),
		"and it is allowed to name a plant the list does not have: %s" % prompt
	)


func test_a_model_that_says_it_cannot_tell_is_refused_rather_than_guessed_for() -> void:
	var nothing: Dictionary = LlmScript.parse_response(
		200, _envelope(_answer_of([])), LOCAL_MODEL
	)
	assert(not bool(nothing["ok"]), "an empty list is not an identification")
	assert(
		String(nothing["reason"]).contains("could not tell"),
		"and the refusal gives the model its own honesty back: %s" % String(nothing["reason"])
	)


## Found by reading four real photographs off a phone against a real model: three of them came back as a
## **bare `[]`**, which is the shape the prompt's own words invite for a photograph with no plant in it -
## and the reader called it `what the model answered could not be read as JSON: []`.
##
## `[]` is JSON this program reads perfectly well, and a bare empty list is the *same answer* as
## `{"candidates": []}`: the model saying it cannot name the plant. Blaming its formatting turns a
## correct, believable answer into a message about syntax that a person can do nothing with - and it
## throws away the one thing the model did do right.
func test_a_bare_empty_list_is_the_model_saying_it_cannot_tell_not_unreadable_json() -> void:
	var bare: Dictionary = LlmScript.parse_response(200, _envelope("[]"), LOCAL_MODEL)
	assert(not bool(bare["ok"]), "a bare empty list is not an identification")
	assert(
		String(bare["reason"]).contains("could not tell"),
		"it is the model's own honesty: %s" % String(bare["reason"])
	)
	assert(
		not String(bare["reason"]).contains("could not be read as JSON"),
		"and it must not be blamed for its formatting, because `[]` was read perfectly well"
	)


## Found by a whole reading of a real photograph against a real model, **twice over**.
##
## The first wording offered the empty list to a model that was merely unsure - "if the photograph does not
## show enough to name the plant, answer with an empty list, because not knowing is a real answer and a
## guess is not" - and `qwen2.5vl:3b`, asked about a clear photograph of one boxwood, answered
## `{"candidates": []}` in 0.2 seconds without appearing to look at it. That sentence went, and a gentler
## one took its place: the empty list kept, but reserved for a photograph with no plant in it.
##
## **The gentler one was still an escape hatch, and a small model does not weigh a permission - it takes
## it.** Asked about a photograph of ripe tomatoes on the vine, the least ambiguous plant photograph there
## is, it answered `{"candidates": []}` in **0.3 seconds**; with that one sentence deleted and nothing else
## changed it answered `Solanum lycopersicum` at 0.9, **twice**, in 2.0 and 1.1 seconds. So the empty list
## is not offered at all now, and an unsure model is asked for a name and a low confidence - which is what
## this program wanted in the first place, and already knows how to read: `FieldCapture`'s floors decide
## whether a low number counts as an identification, and a name below them is kept as "a name that was
## offered" rather than thrown away.
##
## Nothing is lost by not asking, because a model that answers the empty list anyway is still understood:
## `parse_response` was taught that a bare `[]` is the model saying it cannot tell rather than unreadable
## JSON, which is held next door.
func test_the_prompt_asks_for_a_name_and_never_offers_the_model_an_empty_list() -> void:
	var asked: String = LlmScript.single_prompt(&"whole", "")
	assert(
		asked.contains("name the plant it most resembles"),
		"an unsure model is asked for a name and a low confidence: %s" % asked
	)
	assert(
		not asked.contains("empty list"),
		"and the empty list is never put in front of it, because that is the shape a small model takes: %s"
			% asked
	)
	assert(
		not asked.contains("does not show enough to name the plant"),
		"neither is the first sentence that talked a small model out of looking"
	)
	assert(
		LlmScript.refine_prompt(&"leaf", "", []).contains("name the plant it most resembles"),
		"the mixed mode's own question carries the same rule, because both come from one place"
	)
	assert(
		not LlmScript.refine_prompt(&"leaf", "", []).contains("empty list"),
		"and the mixed mode's question offers no escape hatch either"
	)

	var prose: Dictionary = LlmScript.parse_response(
		200, _envelope("It looks like a kind of thyme, I think."), LOCAL_MODEL
	)
	assert(not bool(prose["ok"]), "prose that is not an answer is not filed as one")
	assert(
		String(prose["reason"]).contains("could not be read as JSON"),
		"and the refusal says what was wrong: %s" % String(prose["reason"])
	)
	assert(
		String(prose["answer"]).contains("thyme"),
		"while the model's own words are kept for a person to read: %s" % String(prose["answer"])
	)


# --- the answer ----------------------------------------------------------------------------


func test_an_answer_wrapped_in_a_markdown_fence_still_gives_up_its_candidates() -> void:
	var fenced: String = "Here is the answer:\n```json\n" + _answer_of([
		_candidate(THYME, 0.81, "creeping, small leaves"),
	]) + "\n```\n"
	var answer: Dictionary = LlmScript.parse_response(200, _envelope(fenced), LOCAL_MODEL)
	assert(bool(answer["ok"]), "a fence and a sentence in front of the answer do not hide it: %s"
			% String(answer["reason"]))
	assert(String(answer["raw_taxon"]) == THYME, "the plant is read")
	assert(is_equal_approx(float(answer["confidence"]), 0.81), "with the confidence the model gave")

	# A local server that simply returns the JSON the prompt asked for, with no envelope at all, goes
	# through the same door.
	var bare: Dictionary = LlmScript.parse_response(200, _answer_of([_candidate(THYME, 0.9)]))
	assert(bool(bare["ok"]), "an answer with no envelope around it is read too")
	assert(String(bare["raw_taxon"]) == THYME, "and names the same plant")


func test_the_plants_are_ordered_by_the_confidences_the_model_itself_gave() -> void:
	var answer: Dictionary = LlmScript.parse_response(200, _envelope(_answer_of([
		_candidate(BOX, 0.40, "second best"),
		_candidate(THYME, 0.90, "best"),
		_candidate("Acer rubrum", 0.10, "unlikely"),
	])), LOCAL_MODEL)
	var candidates: Array = answer["candidates"]
	assert(candidates.size() == 3, "every plant the model named is kept")
	# The first candidate is the one a capture is filed as, so the order cannot be whatever order the
	# model happened to write them in - the numbers it gave them are its own ranking.
	assert(String(candidates[0]["raw_taxon"]) == THYME, "the likeliest is first: %s" % str(candidates[0]))
	assert(String(answer["raw_taxon"]) == THYME, "and is the plant the answer names")
	assert(is_equal_approx(float(answer["confidence"]), 0.90), "at the confidence it was given")
	assert(String(candidates[2]["raw_taxon"]) == "Acer rubrum", "and the least likely is last")

	# A plant named twice is one candidate: a shortlist handed on with a duplicate, and a row of
	# buttons built from it, would both be lying about how many plants there are.
	var repeated: Dictionary = LlmScript.parse_response(200, _answer_of([
		_candidate(THYME, 0.9), _candidate("thymus serpyllum", 0.8),
	]))
	assert((repeated["candidates"] as Array).size() == 1, "the same plant twice is one plant")


func test_the_model_that_actually_answered_is_recorded_beside_the_one_that_was_asked_for() -> void:
	var answer: Dictionary = LlmScript.parse_response(
		200, _envelope(_answer_of([_candidate(THYME, 0.9)]), "gpt-4o-mini-2024-07-18"), ONLINE_MODEL
	)
	assert(
		String(answer["model_id"]) == ONLINE_MODEL,
		"the record says which model was asked for: %s" % String(answer["model_id"])
	)
	assert(
		String(answer["model_version"]) == "gpt-4o-mini-2024-07-18",
		"and which build of it actually answered: %s" % String(answer["model_version"])
	)

	var unstated: Dictionary = LlmScript.parse_response(
		200, _answer_of([_candidate(THYME, 0.9)]), LOCAL_MODEL
	)
	assert(
		String(unstated["model_version"]).is_empty(),
		"a service that does not say which build it served has no version invented for it"
	)


func test_a_service_that_refuses_is_refused_in_its_own_words() -> void:
	var refused: Dictionary = LlmScript.parse_response(
		429, "{\"error\": {\"message\": \"rate limited, try again later\"}}", ONLINE_MODEL
	)
	assert(not bool(refused["ok"]), "a refusal from the service is a refusal here")
	assert(String(refused["reason"]).contains("429"), "and names the status: %s" % String(refused["reason"]))
	assert(
		String(refused["reason"]).contains("rate limited"),
		"in the service's own words rather than in this program's: %s" % String(refused["reason"])
	)

	var never: Dictionary = LlmScript.parse_response(0, "")
	assert(not bool(never["ok"]), "a request that never arrived is not an answer either")
	assert(
		String(never["reason"]).contains("never reached"),
		"and is a different thing from a service that answered: %s" % String(never["reason"])
	)

	var silent: Dictionary = LlmScript.parse_response(HTTPClient.RESPONSE_UNAUTHORIZED, "")
	assert(not bool(silent["ok"]), "a service that refuses and says nothing still refuses")
	assert(
		String(silent["reason"]).contains("401"),
		"and the status is all it has to go on: %s" % String(silent["reason"])
	)
