class_name PlantIdentifier
extends RefCounted
## The seam between a photograph and a name on a plan: which of the four ways a photograph is read, and
## the pipeline that runs the one a person chose.
##
## This is still the **contract** a classifier has to satisfy and the shape of the answer it must give,
## written down before there was anything to satisfy it - and it is still true that **this build carries
## no inference engine of its own**: `installed()` answers false, because there is no model, no weights
## and no dependency here that could run one. What has changed is that a model can now be *reached*, on
## this machine or over the internet, chosen by a person in `PlantIdChoice` and asked in the shape
## `PlantIdLlm` builds. Whether a photograph is read is therefore a question about a mode and its
## settings, which an instance answers (`can_read`) rather than a static that could only guess.
##
## ## One pipeline, one way into a record
##
## A local model, an online model and the two-stage mixed mode all end up as the same
## `{raw_taxon, confidence, model_id, model_version}` and all of them go through the same floors in
## `FieldCapture.identify`, reached through `capture_from`. A pipeline that filed its own species would
## be a second place the rules about what counts as an identification live, which is the defect this
## program spends the most effort avoiding.
##
## ## A refusal can carry plants
##
## When the online half of a mixed mode cannot be reached, the answer is not an identification and it
## **does** name the plants the local half narrowed it to. That is deliberate: the shortlist is worth
## showing a person, and dressing a first look up as a settled identification because the second half
## failed is exactly the guess this program refuses to make.
##
## The rest of this file is still the contract itself: a photograph is read by a model running somewhere
## this
## program does not control - a phone, a service, a future GDExtension - and what that model hands back
## is one of these:
##
##     {"raw_taxon": String, "confidence": float, "model_id": String, "model_version": String}
##
## `raw_taxon` is the **name the model offered**, kept as a string rather than as a species: whether this
## program's plant list knows that name is `FieldCapture`'s decision, and a model that named a plant is
## not a model that is allowed to put one on a plan. `confidence` is the model's own, and it is measured
## against `PlantIDResolver`'s floors like every other name in this program.
##
## ## Why the refusal is a sentence rather than an absence
##
## There is no inference engine in this project: no model, no weights, no dependency that could run one.
## A program that simply lacked the feature would leave somebody pressing a button that does nothing.
## `NOTHING_INSTALLED` is what a page shows where such a button would be, and it names both what is
## missing and what to do until it exists.
##
## A photograph is worth keeping without any of this: `FieldPhotoStore` keeps it beside the drawing's
## records and a person names the plant themselves, which is what the capture page is for.

const FieldCaptureScript := preload("res://scripts/field_capture.gd")
const PlantIdChoiceScript := preload("res://scripts/plant_id_choice.gd")
const PlantIdLlmScript := preload("res://scripts/plant_id_llm.gd")

## What a page says where a model would be, if there were a model.
const NOTHING_INSTALLED := (
	"A photograph is kept, not read: this program has no identification model installed, so the name "
	+ "is yours to type. Everything the photograph needs to go with it is still recorded."
)

## How long a model is given to answer, and how long the pause between looking for its answer is.
##
## **Counting polls is not waiting.** `HTTPClient.poll()` does not block, so a loop that gives up after a
## fixed number of turns goes by in a few milliseconds - which is what the first reading of a real
## photograph, against a real model, found: the model was still thinking and the program had already
## decided it never answered. A slow answer needs the clock rather than a counter, and the pause between
## looks is what stops this program spinning a processor while it waits.
##
## Three minutes is longer than a small vision model on this machine takes and short enough that a
## person waiting for a page to come back is not left there forever. When it runs out, the refusal says
## how long it waited, because "the model did not answer" and "the model did not answer *yet*" want
## different things done about them.
##
## This and `CONNECT_SECONDS` are the **pipeline's** patience, handed to `HttpExchange` rather than
## defaulted inside it: the wire has no opinion about how long a model may think, and a policy stated in
## two places is two answers to one question.
const WAIT_SECONDS := 180.0

## How long a socket is given to **connect**, as opposed to how long a model is given to answer.
##
## The two are different questions and deserve different patience: a server that is going to answer at
## all opens the connection in milliseconds, while a vision model may think for minutes. **Measured** on
## this project's own Windows machine: a live socket reaches `STATUS_CONNECTED` in about thirteen
## milliseconds, and a port nobody is listening on sat at `STATUS_CONNECTING` for the whole two seconds
## it was watched without ever becoming `STATUS_CANT_CONNECT`. So a dead address cannot be told from a
## slow one by the status alone, and only a short budget for connecting can tell them apart - which is
## the difference between a mis-typed address costing a second and a half and costing the three minutes
## a model is allowed.
const CONNECT_SECONDS := 1.5

## Which act of the pipeline a step belongs to.
##
## The names are the **acts** rather than the models, because the mixed mode asks two models while the
## single modes ask one: `READING_ONE` is one model doing the whole job, `READING_NARROW` is the mixed
## mode's first look on this machine, and `READING_REFINE` is its second, over the internet.
const READING_ONE := &"one"
const READING_NARROW := &"narrow"
const READING_REFINE := &"refine"

## How a reading is getting on, as `step_read` answers it: `WORKING` while a model is being waited for,
## `DONE` once there is an answer to read.
const WORKING := &"working"
const DONE := &"done"

## Which way a photograph is read, and everything the chosen way needs told - `PlantIdChoice`'s own
## record, so a caller hands over what a page saved rather than a second vocabulary of fields.
var settings: Dictionary = PlantIdChoiceScript.default_settings()

## How a request is sent, for a machine that has no model to send it to.
##
## Empty in the program, where `HttpExchange` does it with `HTTPClient`. A test hands over a `Callable` that
## takes a request and answers `{status, body}` - status 0 meaning it never arrived, which is the
## convention every other transport here keeps - so that a model on this machine and a service can both
## be simulated with no network, no key and no model, and the pipeline's own decisions are what is held
## down rather than `HTTPClient`'s.
var transport: Callable = Callable()

## The reading in flight: which act, what is being waited for, and what has come back.
##
## A reading is four or five short pieces of state rather than a call whose stack does the remembering,
## because a call that waits inside itself waits with the whole program. What was one nested call in
## `identify_with` - build the request, wait for a model, read its answer, decide whether to ask the
## second model - is here as `_read_stage` and the answer that has arrived for it.
var _read_stage: StringName = &""

## `WORKING` while a model is being waited for, `DONE` where there is nothing left to wait for.
var _read_verdict: StringName = DONE

## The request in flight, or null when a caller's own `transport` answers inside the step instead.
var _read_exchange: HttpExchange = null

## The request `PlantIdLlm` built for the act in flight, kept so that `step_read` can hand the very same
## one to a caller's transport.
var _read_built: Dictionary = {}

## Which model this act is asking, for the answer's own record and for reading what comes back.
var _read_model: String = ""

## The photograph, already encoded once - so that the mixed mode's second model is not sent a second
## encoding of it, and a three-gigabyte model's patience is not spent twice on the same pixels.
var _read_picture: String = ""
var _read_part: StringName = FieldCaptureScript.PART_WHOLE
var _read_note: String = ""
var _read_catalogue: PlantCatalogue = null

## What the act in flight answered, the first act's answer, and the shortlist resolved from it.
var _read_answer: Dictionary = {}
var _read_first: Dictionary = {}
var _read_shortlist: Array[Dictionary] = []

## The reading's own answer, kept once it is over.
var _read_result: Dictionary = {}


## Whether a model is **built into this program**. False, and honest about it: there is no inference
## engine here, and a caller asks this rather than assuming it, which is the whole reason the question
## has an answer instead of being absent.
##
## A model that is *reached* - one running on this machine, or a service - is not this question: it is a
## mode and its settings, and `can_read()` is what an instance answers.
static func installed() -> bool:
	return false


## Which model and which version, for a record to say what looked at the picture. Empty while there is no
## model, which is a fact rather than a blank.
static func model_id() -> String:
	return ""


static func model_version() -> String:
	return ""


## What a page should say about reading a photograph. One sentence, written once, so no page has to
## decide for itself how to word the absence of a feature - and so the day a model arrives is one line
## in one file rather than an audit of every page.
static func photo_hint() -> String:
	if not installed():
		return NOTHING_INSTALLED
	return "A photograph can be read by %s %s." % [model_id(), model_version()]


## What a page should say about reading a photograph, given what a person has chosen.
##
## The sentence is always true of the record it is handed: a mode that cannot be used says what it is
## still missing, and a mode that can says what will happen to the photograph. A page wording this for
## itself would come to describe a mode that is not the one in force.
static func photo_hint_for(chosen: Dictionary) -> String:
	if PlantIdChoiceScript.mode_of(chosen) == PlantIdChoiceScript.NONE:
		return NOTHING_INSTALLED
	var ready: Dictionary = PlantIdChoiceScript.readiness(chosen)
	if not bool(ready["ok"]):
		return String(ready["reason"])
	return PlantIdChoiceScript.sentence(PlantIdChoiceScript.mode_of(chosen))


## An identifier for one way of reading photographs, handed the record that way is described by.
##
## Handed nothing it is the off mode - `settings` starts as the defaults and what a caller hands over is
## laid on top of them, so a record that states a little is given the rest rather than refused for the
## keys it does not have. This is why a caller who has never heard of any of this still gets a
## `PlantIdentifier` that behaves exactly as it did before there were modes: it sends nothing.
func _init(given: Dictionary = {}) -> void:
	for key: Variant in given.keys():
		settings[String(key)] = given[key]


## Which way a photograph is read here.
func mode() -> StringName:
	return PlantIdChoiceScript.mode_of(settings)


## Whether a photograph can be read at all right now, and what is missing when it cannot - as
## `{ok, reason}`.
##
## Asked before anything is encoded or sent, so a mode nobody has finished setting up refuses without
## touching the photograph. `ok` is false for the off mode as well, because there genuinely is nothing
## to send: a caller shows the mode's own sentence rather than treating it as a fault.
func can_read() -> Dictionary:
	return PlantIdChoiceScript.readiness(settings)


## No model can look at a picture, and this says so by name rather than answering with an empty result a
## caller could read as "the picture shows nothing".
##
## Kept beside `identify_with` rather than replaced by it, because they are two different questions:
## this is "can anything in this build read a photograph at all", which is answered by the build, and
## that one is "read **this** photograph, **this** way".
func identify(_image: Image) -> Dictionary:
	return {
		"ok": false,
		"reason": NOTHING_INSTALLED,
		"raw_taxon": "",
		"confidence": 0.0,
		"model_id": "",
		"model_version": "",
	}


## Read a photograph the way the chosen mode says to, and answer with the plants that came back.
##
##     identifier.settings = PlantIdChoice.stored()
##     var answer: Dictionary = identifier.identify_with(photo, FieldCapture.PART_LEAF, note, catalogue)
##     if bool(answer["ok"]):
##         filed = PlantIdentifier.capture_from(answer, catalogue, spot, path)
##
## The answer is `{ok, reason, raw_taxon, confidence, candidates, answer, model_id, model_version}` - a
## shape `capture_from` takes exactly as it stands, so a page converts nothing - and `candidates` is
## every plant that was offered, best first, each `{raw_taxon, confidence, reason, species_id}`, which
## is what a page builds its buttons from.
##
## **A refusal can carry candidates**, and that is the one case where a page shows both a reason and
## something to choose: the mixed mode's local half succeeded and its online half did not. See the note
## at the top of this file for why that is a refusal rather than a quiet fallback.
##
## **This waits inside itself, and it is now the only caller that has to.** It is nothing but `begin_read`
## and `step_read` driven to completion - the same machine a page steps one frame at a time - so the
## rules about stages, clocks and refusals live in one place rather than in a waiting loop here and a
## stepping loop there. A page, which has to keep drawing frames, calls `begin_read` and `step_read`.
func identify_with(
	image: Image,
	part: StringName = FieldCaptureScript.PART_WHOLE,
	note: String = "",
	catalogue: PlantCatalogue = null
) -> Dictionary:
	begin_read(image, part, note, catalogue)
	while step_read(HttpExchange.PAUSE_MS) == WORKING:
		pass
	return read_result()


## Start reading a photograph, and answer whether there is anything to wait for.
##
## `WORKING` means a model is being asked and `step_read` is what advances it; `DONE` means the whole
## reading is already over, because a way that cannot be used, a photograph that cannot be encoded and a
## request that could not be built all refuse **here** rather than waiting on a model that was never asked.
##
## Readiness and encoding are settled once, here, and the encoding is kept: the mixed mode's second model
## is sent the very picture the first one was, so a slow machine is not asked to read the same pixels
## twice.
func begin_read(
	image: Image,
	part: StringName = FieldCaptureScript.PART_WHOLE,
	note: String = "",
	catalogue: PlantCatalogue = null
) -> StringName:
	_read_stage = &""
	_read_verdict = DONE
	_read_exchange = null
	_read_built = {}
	_read_model = ""
	_read_picture = ""
	_read_part = part
	_read_note = note
	_read_catalogue = catalogue
	_read_answer = {}
	_read_first = {}
	_read_shortlist = []
	_read_result = {}
	var ready: Dictionary = can_read()
	if not bool(ready["ok"]):
		return _finished(_refusal(String(ready["reason"])))
	var encoded: Dictionary = PlantIdLlmScript.encode_image(image)
	if not bool(encoded["ok"]):
		return _finished(_refusal(String(encoded["reason"])))
	_read_picture = String(encoded["base64"])
	match mode():
		PlantIdChoiceScript.LOCAL:
			return _start(
				READING_ONE, PlantIdChoiceScript.LOCAL, PlantIdLlmScript.single_prompt(part, note)
			)
		PlantIdChoiceScript.ONLINE:
			return _start(
				READING_ONE, PlantIdChoiceScript.ONLINE, PlantIdLlmScript.single_prompt(part, note)
			)
		PlantIdChoiceScript.HYBRID:
			var size: Dictionary = PlantIdChoiceScript.shortlist_size(settings)
			if not bool(size["ok"]):
				return _finished(_refusal(String(size["reason"])))
			return _start(
				READING_NARROW,
				PlantIdChoiceScript.LOCAL,
				PlantIdLlmScript.shortlist_prompt(part, note, int(size["size"]))
			)
	return _finished(_refusal(PlantIdChoiceScript.NOTHING_SENT))


## Look at the reading once and do what it is waiting for, answering `WORKING` until a model has answered.
##
## **The one method a page's frame calls**, and the reason a reading cannot freeze the program: a model
## that thinks for three minutes costs three minutes of frames rather than three minutes of a window that
## draws nothing at all. A caller that does have to wait inside a single call passes
## `HttpExchange.PAUSE_MS`; a caller stepping this from a frame passes nothing, because the frame is
## already the pause, and sleeping inside one is how a program comes to feel sluggish while it waits.
func step_read(pause_ms: int = 0) -> StringName:
	if _read_verdict != WORKING:
		return _read_verdict
	if _read_exchange != null:
		if _read_exchange.step(pause_ms) == HttpExchange.WORKING:
			return WORKING
		_read_answer = _read_the_wire(_read_exchange.result())
	elif transport.is_valid():
		# A caller's own transport answers inside the step, so there is no socket to look at and no clock
		# to watch - which is what lets a whole reading be held down by a test with no network and no
		# model.
		_read_answer = _read_the_wire(transport.call(_read_built))
	else:
		return _finished(_refusal("no reading was ever begun, so there is nothing to wait for"))
	return _decide()


## Whether a model is being waited for right now. A page asks this rather than remembering it, so that the
## button it disabled and the pipeline it is stepping cannot come to disagree.
func reading_in_flight() -> bool:
	return _read_verdict == WORKING


## Whether what the reading is waiting on is a **socket** rather than something that answers inside a step.
##
## This is what tells the two callers apart, and it is asked rather than guessed at: a caller stepping this
## from a frame can always make progress by looking at the socket once, while a reading being answered by a
## `transport` a caller handed over - or one that refuses before anybody is asked - is over in as many
## steps as it has acts. A caller that wants an answer *now*, like a page whose model is a simulated one,
## steps everything that is not on the wire and waits only where it has to.
func waiting_on_the_wire() -> bool:
	return _read_verdict == WORKING and _read_exchange != null


## What the reading answered, in the shape `identify_with` has always answered with.
##
## A reading that has not finished answers a refusal **saying so**, rather than a half-built record that a
## caller could read as "the model found nothing".
func read_result() -> Dictionary:
	if _read_verdict != DONE or _read_result.is_empty():
		return _refusal("the photograph has not been read yet")
	return _read_result


## Begin one act: build the request `PlantIdLlm` describes for this half, and hand it to the wire - or to a
## caller's own transport, which answers inside the step rather than through an exchange.
##
## A request that could not be built is **not waited for**: it becomes the act's answer straight away, in
## the same shape a model's own failure has, so that what the pipeline does next is decided in one place
## whatever went wrong.
func _start(stage: StringName, half: StringName, prompt: String) -> StringName:
	_read_stage = stage
	var local: bool = half == PlantIdChoiceScript.LOCAL
	var address: String = String(settings.get(
		PlantIdChoiceScript.LOCAL_URL if local else PlantIdChoiceScript.ONLINE_URL, ""
	))
	_read_model = String(settings.get(
		PlantIdChoiceScript.LOCAL_MODEL if local else PlantIdChoiceScript.ONLINE_MODEL, ""
	))
	var key: String = "" if local else String(settings.get(PlantIdChoiceScript.ONLINE_API_KEY, ""))
	_read_built = PlantIdLlmScript.build_request(address, _read_model, key, prompt, _read_picture)
	_read_verdict = WORKING
	if not bool(_read_built["ok"]):
		_read_answer = _empty_answer(String(_read_built["reason"]), _read_model)
		return _decide()
	if transport.is_valid():
		# Kept null so that `step_read` calls the transport, rather than here where a reading would begin
		# with an answer already in hand and a step with nothing to do.
		_read_exchange = null
		return WORKING
	_read_exchange = HttpExchange.new()
	_read_exchange.begin(_read_built, WAIT_SECONDS, CONNECT_SECONDS)
	return WORKING


## Read what the wire answered, in `PlantIdLlm`'s shape.
##
## A simulated answer and a real one go through one reader and one set of rules, and a sender that could
## not reach the model has its own reason passed through - so a refusal names the host or the clock rather
## than the generic "it never reached the model".
func _read_the_wire(sent: Dictionary) -> Dictionary:
	return PlantIdLlmScript.parse_response(
		int(sent.get("status", 0)),
		String(sent.get("body", "")),
		_read_model,
		String(sent.get("why", ""))
	)


## What the pipeline does now that an act has come back: answer, or ask the mixed mode's second model.
##
## The mixed mode is the whole of the branch below. Its first act narrows the photograph to a shortlist on
## this machine, resolved against the list **before it travels**, so the second model sees the names this
## garden can actually plant beside the names the first one offered.
func _decide() -> StringName:
	match _read_stage:
		READING_ONE:
			return _finished(_from_answer(_read_answer, _read_catalogue))
		READING_NARROW:
			if not bool(_read_answer["ok"]):
				return _finished(_refusal(
					"the local model could not make a shortlist: %s" % String(_read_answer["reason"])
				))
			_read_first = _read_answer
			_read_shortlist = _annotated(_read_answer["candidates"], _read_catalogue)
			return _start(
				READING_REFINE,
				PlantIdChoiceScript.ONLINE,
				PlantIdLlmScript.refine_prompt(_read_part, _read_note, _read_shortlist)
			)
		READING_REFINE:
			return _finished(_from_the_two(_read_answer))
	return _finished(_refusal(PlantIdChoiceScript.NOTHING_SENT))


## The reading is over: keep its answer, let go of the request only needed while it was in flight, and say
## so. A page reads `reading_in_flight` and `read_result` off this and nothing else.
func _finished(result: Dictionary) -> StringName:
	_read_result = result
	_read_verdict = DONE
	_read_stage = &""
	_read_exchange = null
	_read_built = {}
	return DONE


## What the mixed mode answers once its second act has come back: the online model's reading when it named
## something, and otherwise **a refusal that carries the shortlist** the first act narrowed.
##
## A second half that could not be reached is a refusal rather than a quiet fallback to the first model's
## answer, because half the work is not an identification - and the refusal names the model that did the
## half that worked, since a person choosing one of those plants is choosing that model's reading.
func _from_the_two(second: Dictionary) -> Dictionary:
	if not bool(second["ok"]):
		return _refusal(
			(
				"%d plants were narrowed down on this machine, but the online model could not be "
				+ "reached: %s"
			) % [_read_shortlist.size(), String(second["reason"])],
			_read_shortlist,
			String(_read_first["model_id"]),
			String(_read_first["model_version"])
		)
	return {
		"ok": true,
		"reason": "",
		"raw_taxon": String(second["raw_taxon"]),
		"confidence": float(second["confidence"]),
		"candidates": _annotated(second["candidates"], _read_catalogue),
		# Both models are named, because two of them answered and a record claiming one had would tell a
		# person less than the truth about how the name was arrived at.
		"model_id": "%s, then %s" % [String(_read_first["model_id"]), String(second["model_id"])],
		"model_version": String(second["model_version"]),
		"answer": String(second["answer"]),
	}


## Send one request to a model's service and read the answer: `{status, body, why, reached}`, with status
## 0 meaning it never arrived and `why` the sentence saying so.
##
## **This is the only place in this subsystem that sends anything**, and it is shared deliberately: the
## plant identifier sends a photograph and the device scan asks a machine which models it has running,
## and those are the same act.
##
## It is also **nothing but `HttpExchange` driven to completion**. The machine - the stages, the three
## clocks, reading a body as it arrives, and wording each way it can fail - lives there, in one place, so
## that a caller that must not block a frame can step that same machine instead of calling this. A second
## `HTTPClient` loop here would be a second place the "counting polls is not waiting" fault could come
## back, and that fault has already cost this project one whole reading.
##
## Failing to reach a model is a refusal that says so rather than an exception or a silence - the same
## rule the sync transport keeps for its service, kept here for the same reason: a pipeline that
## reported nothing the matter when nothing was ever sent is the one failure a person cannot see for
## themselves.
##
## `seconds` is a parameter because the two callers want different patience: a vision model thinking about
## a photograph is given minutes, while asking a machine what it has answers at once or not at all.
## Connecting gets `CONNECT_SECONDS` rather than `seconds`, for the reason measured there.
static func send_http(request: Dictionary, seconds: float = WAIT_SECONDS) -> Dictionary:
	var exchange: HttpExchange = HttpExchange.new()
	if exchange.begin(request, seconds, CONNECT_SECONDS) == HttpExchange.WORKING:
		while exchange.step(HttpExchange.PAUSE_MS) == HttpExchange.WORKING:
			pass
	return exchange.result()


## Where the wire work went, and why it is not here.
##
## Connecting, waiting, reading a body as it arrives, and wording every way that can fail is
## `HttpExchange`'s now, in one place, because a caller that must not block a frame needs to do that same
## act one step at a time. What stays here is the **policy** - how patient the pipeline is
## (`WAIT_SECONDS`, `CONNECT_SECONDS`) - and the driver that runs the machine to completion
## (`send_http`). `connect_refusal` and `refusal_words` went with the rest of the wording.


## A single model's answer, in this pipeline's own shape.
##
## The plants are resolved against the list on the way through rather than by whoever asked: which of
## the names a model offered this garden can actually plant is the same question for every caller, and a
## page answering it for itself is the second place the answer would live.
func _from_answer(answer: Dictionary, catalogue: PlantCatalogue) -> Dictionary:
	var plants: Array[Dictionary] = _annotated(answer.get("candidates", []), catalogue)
	if not bool(answer["ok"]):
		return {
			"ok": false,
			"reason": String(answer["reason"]),
			"raw_taxon": "",
			"confidence": 0.0,
			"candidates": plants,
			"answer": String(answer.get("answer", "")),
			"model_id": String(answer.get("model_id", "")),
			"model_version": String(answer.get("model_version", "")),
		}
	return {
		"ok": true,
		"reason": "",
		"raw_taxon": String(answer["raw_taxon"]),
		"confidence": float(answer["confidence"]),
		"candidates": plants,
		"answer": String(answer.get("answer", "")),
		"model_id": String(answer.get("model_id", "")),
		"model_version": String(answer.get("model_version", "")),
	}


## The plants a model offered, each with the species this program's list makes of it.
##
## **The list does not get a vote on what the model saw.** A name the list has never heard of is kept
## exactly as the model wrote it, so that a person can read it and disagree with it; the list is asked
## only which of these it can actually plant, and `species_id` is empty where the answer is none.
func _annotated(candidates: Variant, catalogue: PlantCatalogue) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	if not (candidates is Array):
		return found
	var resolver: PlantIDResolver = null
	if catalogue != null:
		resolver = PlantIDResolver.new(catalogue)
	for item: Variant in (candidates as Array):
		if not (item is Dictionary):
			continue
		var entry: Dictionary = (item as Dictionary).duplicate()
		entry["species_id"] = ""
		if resolver != null:
			var species: PlantSpecies = resolver.resolve(String(entry.get("raw_taxon", "")))
			if species != null:
				entry["species_id"] = String(species.id)
		found.append(entry)
	return found


## An answer that was never made, in the shape every caller reads: a reason, and no plants.
static func _empty_answer(reason: String, model: String) -> Dictionary:
	return {
		"ok": false,
		"reason": reason,
		"raw_taxon": "",
		"confidence": 0.0,
		"candidates": [],
		"answer": "",
		"model_id": model,
		"model_version": "",
	}


## This pipeline's refusal: a sentence saying what could not be done, the plants that are still worth
## showing a person when there are any, and who found them when somebody did.
##
## A refusal that carries a shortlist **has to name the model that found it**: those plants are that
## model's own answer, and a person choosing one of them is choosing a model's reading. A record that
## named nobody would say less than the truth about where the name came from - and the model's name is
## read from the answer *before* it is replaced, so it cannot be lost on the way.
static func _refusal(
	reason: String,
	candidates: Array[Dictionary] = [],
	who: String = "",
	who_version: String = ""
) -> Dictionary:
	return {
		"ok": false,
		"reason": reason,
		"raw_taxon": "",
		"confidence": 0.0,
		"candidates": candidates,
		"answer": "",
		"model_id": who,
		"model_version": who_version,
	}


## A capture from a classifier's answer - **the one path there is** from a model naming a plant to a
## record on this side. The name goes through `FieldCapture.identify`, so a weak reading is refused by
## the same floors every other name is refused by, and an answer that names nothing is refused by name
## rather than becoming a capture about nothing.
##
## Which model answered travels with the record, so a person reading it later can weigh the answer
## instead of trusting it because it appeared on a screen.
static func capture_from(
	identification: Dictionary,
	catalogue: PlantCatalogue = null,
	position: Vector3 = Vector3.ZERO,
	photo_path: String = "",
	note: String = "",
	part: StringName = FieldCaptureScript.PART_WHOLE
) -> Dictionary:
	var offered: String = String(identification.get("raw_taxon", "")).strip_edges()
	if offered.is_empty():
		return {
			"ok": false,
			"reason": "the identification named no plant, so there is nothing to look up",
			"capture": FieldCaptureScript.unidentified(position, photo_path, note, part),
		}
	var answer: Dictionary = FieldCaptureScript.identify(
		offered,
		float(identification.get("confidence", 0.0)),
		catalogue,
		position,
		photo_path,
		note,
		part
	)
	var capture: Dictionary = answer["capture"]
	capture["model_id"] = String(identification.get("model_id", ""))
	capture["model_version"] = String(identification.get("model_version", ""))
	return {
		"ok": bool(answer["ok"]),
		"reason": String(answer["reason"]),
		"capture": capture,
	}