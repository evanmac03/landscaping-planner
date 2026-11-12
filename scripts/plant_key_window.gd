class_name PlantKeyWindow
extends Window
## Naming a plant by answering questions about it: the page a person opens when they are standing in
## front of something they cannot name and have nobody to ask.
##
## A `Window`, like every other page here, and it is the **person's** half of identification: it asks
## what they can see, one question at a time, and the field of candidates comes down until one plant is
## left. The questions, the arithmetic that chooses between them and the wording of every outcome are
## `PlantKey`'s; this page shows them and keeps the answers while it is open, and decides nothing itself.
##
## ## The same list, and the same way of choosing a plant
##
## The catalogue it narrows is the HUD's own `plant_list()`, handed over on `bind`, so the key and the
## library are looking at the same entries. When one plant is left and somebody presses Use this plant,
## the page says which species it is and closes; the HUD arms it, which is the door the library and the
## palette already go through. **Naming a plant is not a second way of choosing one.**
##
## ## The answers are kept, and taken back one at a time
##
## They live while the page is open and are deliberately **not** cleared by `bind`, because somebody who
## closed the key to go and look at the plant again wants to carry on where they were. An answer that
## turns out to have been wrong comes back one at a time, newest first, and the page offers that as soon
## as there is anything to take back. Starting again is the other door, and it is the one somebody wants
## when they realise the first answer was wrong and everything after it followed from it.

const KeyScript := preload("res://scripts/plant_key.gd")

signal closed()
## The species somebody settled on. The page says which; who acts on it is the HUD's business.
signal species_chosen(species_id: StringName)

## Wide enough for a question, a wrapped row of answers and the names the list cannot separate, and tall
## enough for all of it: the words, the question, the answers and four buttons.
const SIZE := Vector2i(720, 560)

const TITLE := "Name a plant by answering questions"
const EXPLANATION := (
	"Answer what you can see, and the list narrows until one plant is left. Nothing is looked up and "
	+ "nothing is sent anywhere: every question is answered from the plant in front of you."
)
const WORDS_CAPTION := "Where the key has got to"
const PROMPT_CAPTION := "What to answer"
const MATCHES_CAPTION := "The list cannot tell these apart"
const NO_LIST := "There is no plant list here to narrow."

## The buttons' words never change: what a button cannot do right now is said on its tooltip, so a
## person reading the row is not left wondering whether the control they remember has gone.
const TAKE_BACK := "Take the last answer back"
const NOTHING_TO_TAKE_BACK := "There is nothing to take back yet - a key with no answers is the whole list."
const START_AGAIN := "Start again"
const NOTHING_TO_START_OVER := "Nothing has been answered yet, so there is nothing to start over."
const USE_THIS_PLANT := "Use this plant"
const ONLY_WHEN_NAMED := "This is offered once the answers have narrowed the list to one plant."
const NOT_SURE := "Not sure - leave this out"
const NOTHING_TO_LEAVE_OUT := "There is no question to leave out right now."
const CLOSE := "Close"

var _catalogue: PlantCatalogue = null
## The answers, in the order they were given - which is what taking one back reads.
var _answers: Dictionary = { }
## What the key last said, as `PlantKey.state` handed it over. Recomputed by `refresh` rather than kept
## in step by hand, so the page cannot show a question that no longer follows from the answers.
var _state: Dictionary = { }
## The question and the answer each button in the row stands for, in the order they were built.
var _choices: Array[Dictionary] = []

var _words: Label = null
var _prompt: Label = null
var _options_row: HFlowContainer = null
var _matches: VBoxContainer = null
var _back_button: Button = null
var _again_button: Button = null
var _use_button: Button = null
var _status: Label = null


func _init() -> void:
	title = TITLE
	min_size = SIZE
	exclusive = false
	close_requested.connect(request_close)


func _ready() -> void:
	if _words == null:
		build()

# --- building ---------------------------------------------------------------------------


## Build the whole page by hand, idempotent, and callable off-tree so a test drives the same controls
## the program shows. The column scrolls, so a question with a long row of answers under it - or a small
## screen - brings the rest into view rather than cutting it off.
func build() -> void:
	if _words != null:
		return
	var column := PageChrome.scrolling_column(self, 6)

	column.add_child(PageChrome.heading(TITLE))

	var explanation := PageChrome.note(EXPLANATION)
	explanation.name = "Explanation"
	column.add_child(explanation)

	column.add_child(_caption(WORDS_CAPTION))
	_words = _says(column, "Words")
	_words.add_theme_color_override("font_color", PageChrome.HINT_COLOR)

	column.add_child(_caption(PROMPT_CAPTION))
	_prompt = _says(column, "Prompt")

	# A flow rather than a row: the answers to a question run from two to ten, and a row too wide for
	# its page is a fault this page has no excuse for.
	_options_row = HFlowContainer.new()
	_options_row.name = "Answers"
	_options_row.add_theme_constant_override("h_separation", 6)
	_options_row.add_theme_constant_override("v_separation", 4)
	column.add_child(_options_row)

	column.add_child(_caption(MATCHES_CAPTION))
	_matches = VBoxContainer.new()
	_matches.name = "Matches"
	_matches.add_theme_constant_override("separation", 2)
	column.add_child(_matches)

	var buttons := HBoxContainer.new()
	buttons.name = "Buttons"
	buttons.alignment = BoxContainer.ALIGNMENT_END
	column.add_child(buttons)
	_back_button = _button(buttons, "TakeBack", TAKE_BACK)
	_back_button.pressed.connect(take_back)
	_again_button = _button(buttons, "StartAgain", START_AGAIN)
	_again_button.pressed.connect(start_again)
	_use_button = _button(buttons, "UsePlant", USE_THIS_PLANT)
	_use_button.pressed.connect(use_this_plant)
	var close_button := _button(buttons, "CloseButton", CLOSE)
	close_button.pressed.connect(request_close)

	_status = _says(column, "Status")

	refresh()


## A caption **above** the thing it names, which is this page's own shape: the shared chrome's own
## body size and colour, and one line, so it does not report the width of its longest word.
func _caption(words: String) -> Label:
	var label := PageChrome.text(words, false)
	label.name = "Caption"
	return label


## A line the page says, wrapping, named by the page: the names are what the page's own test holds it by.
func _says(parent: Node, node_name: String) -> Label:
	var label := PageChrome.text("")
	label.name = node_name
	parent.add_child(label)
	return label


## A button from the shared chrome and named by the page. The chrome is also what gives it a keyboard of
## its own to give back, which is the one thing a control built here may not keep.
func _button(parent: Node, node_name: String, words: String) -> Button:
	var button := PageChrome.button(words)
	button.name = node_name
	parent.add_child(button)
	return button

# --- what it is pointed at ---------------------------------------------------------------


## Hand the page the one plant list. The answers are left alone: a person who closed the key and came
## back to it wants to carry on, and clearing them here would throw that away every time.
func bind(catalogue: PlantCatalogue) -> void:
	_catalogue = catalogue
	refresh()

# --- showing what the key says -----------------------------------------------------------


## Ask the key what the answers amount to and show it: which question, what it says, the answers worth
## offering and the plants left. One call, so the three cannot come apart.
func refresh() -> void:
	if _words == null:
		return
	if _catalogue == null:
		_state = { }
		_words.text = NO_LIST
		_prompt.text = ""
	else:
		_state = KeyScript.state(_catalogue, _answers)
		_words.text = String(_state["words"])
		_prompt.text = String(_state["prompt"])
	_rebuild_answers()
	_rebuild_matches()
	_refresh_buttons()


## Put the answers worth offering on the page, one button each, replacing whatever was there.
##
## The buttons are **freed rather than queued**, for the same reason the field page's candidate buttons
## are: a queued free happens a frame later, and a test that answered a question never reaches that
## frame, so the page would be showing the last question's answers beside this one's.
func _rebuild_answers() -> void:
	if _options_row == null:
		return
	for child in _options_row.get_children():
		_options_row.remove_child(child)
		child.free()
	_choices.clear()
	var question: StringName = StringName(_state.get("question", &""))
	var options: Array = _state.get("options", [])
	for option: Dictionary in options:
		var index: int = _choices.size()
		_choices.append({ "question": question, "option": StringName(option["key"]) })
		var button := PageChrome.button(_answer_words(option))
		button.name = "Answer%d" % index
		button.pressed.connect(choose.bind(index))
		_options_row.add_child(button)
	# "Not sure" comes after the answers because it is not one of them: it is a way past a question somebody
	# cannot answer. It is offered only while there is a question to pass, and it is kept as an answer, so
	# the key moves on rather than asking the same thing again.
	if question != &"":
		var unsure := PageChrome.button(NOT_SURE)
		unsure.name = "NotSure"
		unsure.pressed.connect(skip)
		_options_row.add_child(unsure)
	if _options_row.get_child_count() > 0:
		# Buttons built while the page is open: somebody who reached the page with the keyboard has to be
		# able to reach these too.
		PageChrome.takes_the_keyboard_if_up(self)


## What an answer's button says: the words `PlantKey` gives it, and how many plants it would leave -
## because "a conifer" tells you nothing about whether it is worth pressing and "a conifer (1 plant)"
## tells you everything.
func _answer_words(option: Dictionary) -> String:
	return "%s  (%s)" % [String(option["label"]), KeyScript.count_text(int(option["leaves"]))]


## Show the plants the list cannot separate.
##
## Only then, and deliberately: one plant is already named in the words above, and a row of twenty names
## while twelve questions still stand would be a list nobody reads.
func _rebuild_matches() -> void:
	if _matches == null:
		return
	for child in _matches.get_children():
		_matches.remove_child(child)
		child.free()
	if StringName(_state.get("verdict", KeyScript.NONE)) != KeyScript.SEVERAL:
		return
	var plants: Array = _state.get("matches", [])
	for plant: PlantSpecies in plants:
		var label := PageChrome.text(plant.display_name())
		label.name = "Match"
		_matches.add_child(label)


## What the three buttons of state can do right now. A button that cannot act is disabled rather than
## hidden, and says on its tooltip what it is waiting for.
func _refresh_buttons() -> void:
	var no_answers: bool = _answers.is_empty()
	if _back_button != null:
		_back_button.disabled = no_answers
		_back_button.tooltip_text = NOTHING_TO_TAKE_BACK if no_answers else TAKE_BACK
	if _again_button != null:
		_again_button.disabled = no_answers
		_again_button.tooltip_text = NOTHING_TO_START_OVER if no_answers else START_AGAIN
	var named: bool = StringName(_state.get("verdict", KeyScript.NONE)) == KeyScript.IDENTIFIED
	if _use_button != null:
		_use_button.disabled = not named
		_use_button.tooltip_text = ONLY_WHEN_NAMED if not named else USE_THIS_PLANT

# --- answering --------------------------------------------------------------------------


## Take one of the answers the page is offering. An index the page is not offering does nothing rather
## than answering something nobody chose.
func choose(index: int) -> bool:
	if index < 0 or index >= _choices.size():
		return false
	var choice: Dictionary = _choices[index]
	var question: StringName = StringName(choice["question"])
	var option: StringName = StringName(choice["option"])
	_answers = KeyScript.with_answer(_answers, question, option)
	_say("Answered %s." % KeyScript.option_text(question, option))
	refresh()
	return true


## Take the most recent answer back, and say which one went. Nothing to take back is said plainly rather
## than done silently.
func take_back() -> bool:
	if _answers.is_empty():
		_say(NOTHING_TO_TAKE_BACK)
		return false
	var answered: Array[StringName] = KeyScript.asked(_answers)
	var question: StringName = answered[answered.size() - 1]
	var option: StringName = StringName(_answers[question])
	_answers = KeyScript.without_last(_answers)
	_say("Took back %s." % KeyScript.option_text(question, option))
	refresh()
	return true


## Empty the key and start over, which is what somebody wants when the first answer was wrong.
func start_again() -> void:
	_answers.clear()
	_say("Starting again.")
	refresh()


## Leave the question the page is asking out, without answering it.
##
## Somebody standing in front of a plant very often cannot answer one of these - a leaf's veins, a colour
## they cannot put a name to - and the alternative to this is a guess, which is the one thing a key must not
## take. Nothing is said about the plant, so nothing is narrowed; the only change is that the key asks
## something else. `PlantKey.with_unsure` is where that rule lives.
func skip() -> bool:
	var question: StringName = StringName(_state.get("question", &""))
	if _catalogue == null or question == &"":
		_say(NOTHING_TO_LEAVE_OUT)
		return false
	_answers = KeyScript.with_unsure(_answers, question)
	_say("Left that question out - it will not be asked again.")
	refresh()
	return true

# --- settling on a plant -----------------------------------------------------------------


## Take the one plant the answers have narrowed to: say which, and close. The page names the species and
## nothing else; arming it is the HUD's business, and it is the door the library already uses.
##
## Off, and saying why, when the key has not narrowed to one plant: a button that named a plant out of
## three the list cannot separate would be inventing the answer.
func use_this_plant() -> bool:
	if StringName(_state.get("verdict", KeyScript.NONE)) != KeyScript.IDENTIFIED:
		_say(ONLY_WHEN_NAMED)
		return false
	var plants: Array = _state.get("matches", [])
	if plants.is_empty():
		return false
	var plant: PlantSpecies = plants[0]
	species_chosen.emit(plant.id)
	request_close()
	return true

# --- putting it away, and what a test reads ---------------------------------------------


## Put the page away and say so once, however it was asked for - the window's own close button, the Close
## button, or Escape (which `PageEscape` turns into `close_requested`).
func request_close() -> void:
	hide()
	closed.emit()


func the_state() -> Dictionary:
	return _state


func answer_count() -> int:
	return _answers.size()


func answers() -> Dictionary:
	return _answers


## How many answers the page is offering right now.
func option_count() -> int:
	return _choices.size()


func option_words(index: int) -> String:
	if index < 0 or index >= _options_row.get_child_count():
		return ""
	return (_options_row.get_child(index) as Button).text


## One of the page's own buttons, by the name it was built with, so a test reads whether a button can act
## from the button itself rather than from a second reading of the state. `owned` is false because these
## are built in code and have no owner.
func the_button(node_name: String) -> Button:
	return find_child(node_name, true, false) as Button


func match_count() -> int:
	return _matches.get_child_count() if _matches != null else 0


func words_text() -> String:
	return _words.text if _words != null else ""


func prompt_text() -> String:
	return _prompt.text if _prompt != null else ""


func status_text() -> String:
	return _status.text if _status != null else ""


## The species the key has narrowed to, or the empty id when it has not narrowed to one.
func identified_id() -> StringName:
	if StringName(_state.get("verdict", KeyScript.NONE)) != KeyScript.IDENTIFIED:
		return &""
	var plants: Array = _state.get("matches", [])
	if plants.is_empty():
		return &""
	return (plants[0] as PlantSpecies).id


func _say(line: String) -> void:
	if _status != null:
		_status.text = line