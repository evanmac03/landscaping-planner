class_name ModelAdvisorWindow
extends Window
## What this machine is and which vision model it can carry, as a page: the reading, the advice for
## the machine in hand, and the steps that get a model running on it.
##
## Four things are true of this page, and each of them is a decision:
##
## - **The arithmetic is not here.** `DeviceModelFit` weighs a machine against a model and words the
##   answer; this page builds controls, hands that answer to them and invents nothing. A second
##   reading of what a machine can carry would be a second answer to one question, and the two would
##   disagree the first time a model was added to either.
## - **The reading is taken here, and can be taken again**, because free memory is the one fact on
##   this page that moves while the page is open: a model has to fit into what is free, and
##   something else on the machine can take it while somebody reads. Scan again is the whole reason
##   this page has a button at all.
## - **It says what it cannot work out.** Which models a runner already holds is the runner's own
##   answer and not this machine's - that is what `LocalModelProbe` is for and what the photograph
##   page's own address is for - so the page names that edge rather than showing an empty list of
##   models, which would read as "there are none".
## - **Nothing here is written down.** No setting is changed and no model is fetched: the page
##   states, and the page that reads a photograph is where a model is pointed at. That is why every
##   sentence here is safe to read with no drawing open at all.

## A page wide enough for the longest sentence of advice and tall enough for the reading, the steps
## and a handful of refusals at once. A machine with more models refused than this fits scrolls,
## which is the page's own business rather than a reason to guess at a height.
const SIZE := Vector2i(820, 700)

## The one model this page asks, and the only thing it needs: every fact it shows is that module's.
const DeviceModelFitScript := preload("res://scripts/device_model_fit.gd")

const EXPLANATION := (
	"A vision model reads a plant off a photograph, the photograph goes to wherever that model is "
	+ "running, and this page is about whether this machine can be that place. It weighs models "
	+ "against what this machine has, and says where to put one instead when it cannot carry it."
)

## What the page says when the machine's own memory could not be read. An unknown machine is a real
## answer and a zero-memory one is not, so this names the missing reading instead of showing the zero
## - "0 GB" would read as a machine that cannot run anything, which is a different thing entirely.
const NO_READING := "this machine's memory could not be read, so there is nothing to weigh a model against"

## What the page says before anything has been read, which is the state a page built off-tree is in
## and the state a person sees for the instant before the reading arrives.
const NOTHING_READ := "no model has been weighed yet: take a reading of this machine"

## The page's honesty about its own edge, in one sentence. Which models a runner holds is asked of
## the runner, and a list left empty here would be read as a machine with no models on it.
const NOT_ASKED := (
	"This page does not ask a model runner what it already has, and does not fetch a model for you: "
	+ "which models are on the machine is the runner's own answer, and the steps below are what to "
	+ "run to get one running."
)

## What the page asks a person to do once it has an answer. It is **not** the note above: that is what
## the page does not do, and this is the one thing on it a person can do - the reading is the fact
## here that changes while somebody reads, which is why the button exists at all. A page that showed
## the same sentence as both was saying one thing twice in two places.
const TAKE_ANOTHER_READING := "scan this machine again if something else has started or stopped since"

## How the page words the module's `reason`. The field is **the chosen model's own `why`** on the route
## that runs here, and the machine's own sentence on the route that puts the model elsewhere - so the
## page asks the question both of them answer rather than claiming one shape for both, and a noun
## phrase arrives as the answer to a question instead of as a sentence that stopped halfway.
const WHY := "Why: %s"

## Asked for when the page is finished with.
signal closed

## The machine in hand, exactly as `DeviceModelFit` read it. Empty until a reading is taken.
var _reading: Dictionary = { }
## What to do about a model on this machine, exactly as `DeviceModelFit` worded it. Empty until a
## reading is taken, which is a real state and not an error.
var _advice: Dictionary = { }
## How the machine is read. Unset means the machine under this program is read - the seam is here
## because a test drives a 3.4 GB phone without being one, the same way every reading in
## `DeviceModelFit` is an argument rather than a fact about the machine running the test.
var _scanner: Callable = Callable()
var _status: String = ""
var _built: bool = false

var _heading: Label = null
var _explanation: Label = null
var _summary_label: Label = null
var _headline_label: Label = null
var _reason_label: Label = null
var _models_label: Label = null
var _models: Label = null
var _refused_label: Label = null
var _refused: Label = null
var _experiment_label: Label = null
var _steps_label: Label = null
var _steps: Label = null
var _not_asked_label: Label = null
var _hint_label: Label = null
var _scan_button: Button = null
var _close_button: Button = null
var _status_label: Label = null

# --- building -------------------------------------------------------------------------


## Build the controls, once. Idempotent, and callable off-tree, so a test drives the same controls
## the program shows.
func build() -> void:
	if _built:
		return
	_built = true
	title = "Find a model for this device"
	# A window that has never been shown still defaults to visible, and a page that is up before
	# anybody asked for it is the one thing every page in this HUD has to avoid.
	hide()
	size = SIZE
	close_requested.connect(_on_close_requested)

	# Longer than a short screen: what does not fit scrolls into view rather than being cut off at
	# the foot of the page.
	var column: VBoxContainer = PageChrome.scrolling_column(self, 6, Vector2(16.0, 12.0))

	_heading = PageChrome.heading("Find a model for this device")
	_heading.name = "Heading"
	column.add_child(_heading)

	_explanation = PageChrome.note(EXPLANATION)
	_explanation.name = "Explanation"
	column.add_child(_explanation)

	_summary_label = PageChrome.text()
	_summary_label.name = "Summary"
	_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_summary_label)

	_headline_label = PageChrome.text()
	_headline_label.name = "Headline"
	_headline_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_headline_label)

	_reason_label = PageChrome.text()
	_reason_label.name = "Reason"
	_reason_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_reason_label)

	_models_label = PageChrome.subheading("Models this machine can carry")
	_models_label.name = "ModelsLabel"
	column.add_child(_models_label)

	_models = PageChrome.text()
	_models.name = "Models"
	_models.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_models)

	_refused_label = PageChrome.subheading("Models it cannot")
	_refused_label.name = "RefusedLabel"
	column.add_child(_refused_label)

	_refused = PageChrome.text()
	_refused.name = "Refused"
	_refused.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_refused)

	_experiment_label = PageChrome.text()
	_experiment_label.name = "Experiment"
	_experiment_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_experiment_label)

	_steps_label = PageChrome.subheading("Getting one running")
	_steps_label.name = "StepsLabel"
	column.add_child(_steps_label)

	_steps = PageChrome.text()
	_steps.name = "Steps"
	_steps.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_steps)

	_hint_label = PageChrome.hint()
	_hint_label.name = "Hint"
	column.add_child(_hint_label)

	# The caveat comes after the guidance on purpose: what to do next is the page's own business, and
	# what the page does not do qualifies it. Read the other way round it is a caveat about nothing.
	_not_asked_label = PageChrome.note(NOT_ASKED)
	_not_asked_label.name = "NotAsked"
	column.add_child(_not_asked_label)

	var buttons: HBoxContainer = PageChrome.button_row()
	_scan_button = PageChrome.button("Scan this machine again")
	_scan_button.name = "ScanButton"
	_scan_button.tooltip_text = "Read this machine's memory again, which is the one fact here that changes"
	_scan_button.pressed.connect(_on_scan_pressed)
	buttons.add_child(_scan_button)
	_close_button = PageChrome.button("Close")
	_close_button.name = "CloseButton"
	_close_button.pressed.connect(request_close)
	buttons.add_child(_close_button)
	column.add_child(buttons)

	_status_label = PageChrome.status()
	_status_label.name = "Status"
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status_label)

	# A page with nothing in it yet is still a page: it says what it is waiting for rather than
	# showing an empty table that reads as a machine which can carry nothing.
	_refresh()

# --- the reading ----------------------------------------------------------------------


## Read the machine and put it on the page. Returns whether a reading was taken, so a caller that
## asked for one can tell a reading from a click that did nothing.
##
## The reading is taken by `scan_this_device` unless a scanner was set, which is the only seam this
## page has and the only way to drive it against a machine that is not the one running the test.
func scan() -> bool:
	if _scanner.is_valid():
		bind(_scanner.call())
	else:
		bind(DeviceModelFitScript.scan_this_device())
	return has_reading()


## Take the reading in hand, as `DeviceModelFit` gives it, and work out what to do about it. Empty
## means there is nothing to weigh a model against, which the page says rather than fails on.
##
## The parameter is named for what it is rather than `reading`, because **a function and a parameter
## may not share a name in this project**: the collision is a session error, and a single-file test
## run reports nothing at all. Measured live 2026-11-25 - `The local function parameter "reading" is
## shadowing an already-declared function` - and only the running program said so.
func bind(taken: Dictionary) -> void:
	_reading = taken.duplicate()
	_advice = (DeviceModelFitScript.suggest(_reading) if has_reading() else { })
	_refresh()


## How the machine is read from now on. A `Callable` that returns a reading, so a test states a
## machine; an invalid `Callable` puts the real machine back.
func set_scanner(scanner: Callable) -> void:
	_scanner = scanner


## The machine in hand, as a copy, so a caller cannot edit the page's own reading by accident.
func reading() -> Dictionary:
	return _reading.duplicate()


## What to do about a model on this machine, as a copy. Empty until a reading is taken.
func advice() -> Dictionary:
	return _advice.duplicate()


## Whether the machine's own memory was read at all. A machine whose memory could not be read is a
## real answer - the page says so - and is not the same thing as a machine with none to spare.
func has_reading() -> bool:
	if _reading.is_empty():
		return false
	return not int(_reading.get("physical_bytes", DeviceModelFitScript.UNKNOWN)) <= 0


## The machine in a person's words, or the refusal naming what could not be read.
##
## **Two refusals, because there are two ways to have nothing**: a machine nobody has read yet, and a
## machine that was read and would not say how much memory it has. The first is not a failure - the
## reading has simply not been taken - and showing the second's sentence for it would say something
## about a machine that had not been asked.
func summary_words() -> String:
	if _reading.is_empty():
		return NOTHING_READ
	if not has_reading():
		return NO_READING
	return DeviceModelFitScript.summary(_reading)

# --- the advice -----------------------------------------------------------------------


## The sentence that answers the machine in hand: what to run, and where.
func headline_words() -> String:
	return String(_advice.get("headline", ""))


## Why that is the answer for this machine. Always something: the reason is what turns a suggestion
## into something a person can argue with.
func reason_words() -> String:
	return String(_advice.get("reason", ""))


## The models that fit this machine, one line each, with what each costs to get and to run. A person
## choosing between two is choosing a download against memory, so both are stated.
func model_lines() -> Array[String]:
	var out: Array[String] = []
	for fit: Dictionary in fitted_models():
		var room: String = (
			"and there is room for it now"
			if bool(fit.get("runs_from_what_is_free_now", false))
			else (
				"and only %s of memory is free just now, so start nothing else first"
				% DeviceModelFitScript.bytes_words(int(_reading.get("free_bytes", DeviceModelFitScript.UNKNOWN)))
			)
		)
		out.append(
			"%s - %s to download, about %s to run, %s."
			% [
				String(fit.get("label", "")),
				DeviceModelFitScript.bytes_words(int(fit.get("download_bytes", DeviceModelFitScript.UNKNOWN))),
				DeviceModelFitScript.bytes_words(int(fit.get("ram_needed_bytes", DeviceModelFitScript.UNKNOWN))),
				room,
			]
		)
	return out


## The models this machine cannot carry, one line each, with the reason - which names the field to
## change rather than the feature that is missing.
func refusal_lines() -> Array[String]:
	var out: Array[String] = []
	for refused: Dictionary in refused_models():
		out.append("%s - %s." % [String(refused.get("label", "")), String(refused.get("reason", ""))])
	return out


## The smallest model offered as an experiment, when the machine is too tight for anything better:
## one line, and it carries the module's own warning about what that experiment costs. Empty when
## there is no experiment to offer.
func experiment_words() -> String:
	var experiment: Dictionary = _advice.get("small_experiment", { })
	if experiment.is_empty():
		return ""
	return "%s - %s %s" % [
		String(experiment.get("label", "")),
		DeviceModelFitScript.bytes_words(int(experiment.get("download_bytes", DeviceModelFitScript.UNKNOWN))),
		String(experiment.get("warning", "")),
	]


## The steps that get a model running on this machine or on one beside it, numbered in the order the
## module worded them.
func step_lines() -> Array[String]:
	var out: Array[String] = []
	var number: int = 1
	for step: String in _advice.get("steps", []):
		out.append("%d. %s" % [number, step])
		number += 1
	return out


## Whether the answer to this machine is to put the model somewhere else - a computer on the same
## Wi-Fi - which is a route and not a failure.
func needs_a_computer_beside_it() -> bool:
	return StringName(_advice.get("route", &"")) == DeviceModelFitScript.ROUTE_WIFI_COMPUTER


func fitted_models() -> Array:
	return _advice.get("fits", [])


func refused_models() -> Array:
	return _advice.get("refused", [])

# --- what the page says ----------------------------------------------------------------


## The guidance: what the page is waiting for, or what to do with what it has.
##
## The status line is a different thing and is written only by `say`: the status is what the page
## last *did*, and this is what it is asking for.
func hint() -> String:
	if _reading.is_empty():
		return NOTHING_READ
	if not has_reading():
		return NO_READING
	return TAKE_ANOTHER_READING


func say(text: String) -> void:
	_status = text
	if _status_label != null:
		_status_label.text = text


func said() -> String:
	return _status


## What a person reads on the page, as the page's own lines: the reading, the advice, the models
## that fit, the ones that do not, and the steps. Here rather than in a test's own reading of the
## labels, so that a test and a person are looking at the same page.
func shown_lines() -> Array[String]:
	var out: Array[String] = []
	if _summary_label != null:
		out.append(_summary_label.text)
	out.append(headline_words())
	if _reason_label != null:
		out.append(_reason_label.text)
	for line: String in model_lines():
		out.append(line)
	for line: String in refusal_lines():
		out.append(line)
	var experiment: String = experiment_words()
	if experiment != "":
		out.append(experiment)
	for line: String in step_lines():
		out.append(line)
	return out


func request_close() -> void:
	hide()
	closed.emit()

# --- the refresh, and what the buttons ask for -----------------------------------------


## Re-read the reading in hand and put it on the page. Touches the guidance and never the status.
func _refresh() -> void:
	if not _built:
		return
	_summary_label.text = summary_words()
	_headline_label.text = headline_words()
	_reason_label.text = (WHY % reason_words() if not reason_words().is_empty() else "")
	_reason_label.visible = not _reason_label.text.is_empty()
	var models: Array[String] = model_lines()
	_models.text = "\n".join(PackedStringArray(models))
	_models_label.visible = not models.is_empty()
	_models.visible = not models.is_empty()
	var refused: Array[String] = refusal_lines()
	_refused.text = "\n".join(PackedStringArray(refused))
	_refused_label.visible = not refused.is_empty()
	_refused.visible = not refused.is_empty()
	_experiment_label.text = experiment_words()
	_experiment_label.visible = not _experiment_label.text.is_empty()
	var steps: Array[String] = step_lines()
	_steps.text = "\n".join(PackedStringArray(steps))
	_steps_label.visible = not steps.is_empty()
	_steps.visible = not steps.is_empty()
	_hint_label.text = hint()


func _on_scan_pressed() -> void:
	if scan():
		say("read this machine again")
		return
	say(NO_READING)


func _on_close_requested() -> void:
	request_close()
