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
##
## ## The key can be narrowed to the bed the plant is going in
##
## Naming a plant is not the only thing a key is for: the other question is "what can I plant **here**",
## and the drawing already knows what the ground is like where its cursor last was. So the page can be
## handed that spot, and it will say how many of the list suit it, with a button to narrow to them and a
## button to widen back.
##
## **It never narrows itself.** A key opened to name the plant already growing in front of somebody must not
## drop that plant for not suiting the bed it is demonstrably living in - and that plant is exactly the one
## a designer most wants named. So the whole list is where the page starts, narrowing is a deliberate press,
## and the count is said out loud either way.

const KeyScript := preload("res://scripts/plant_key.gd")

signal closed()
## The species somebody settled on. The page says which; who acts on it is the HUD's business.
signal species_chosen(species_id: StringName)

## Wide enough for a question, a wrapped row of answers and the names the list cannot separate, and tall
## enough for all of it: the words, the question, the answers and four buttons.
const SIZE := Vector2i(720, 560)
## How wide a drawing of an answer is allowed to be. Small on purpose: the words are the answer and the
## drawing is what helps a person choose between them, and twelve answers each the size of a photograph is a
## page nobody reads.
const PICTURE_WIDTH := 72
## How many answers stand side by side. Enough that a question's answers are read at a glance, and few
## enough that each keeps a share of the page wide enough to say a sentence in.
const ANSWER_COLUMNS := 3
## The room the words get beneath a drawing: two lines, which is what the longest answer to a leaf question
## needs once three of them share the page. `PICTURE_WIDTH` sits on top of this.
const TWO_LINES := 48

const TITLE := "Name a plant by answering questions"
const EXPLANATION := (
	"Answer what you can see, and the list narrows until one plant is left. Nothing is looked up and "
	+ "nothing is sent anywhere: every question is answered from the plant in front of you."
)
const WORDS_CAPTION := "Where the key has got to"
const PROMPT_CAPTION := "What to answer"
const MATCHES_CAPTION := "The list cannot tell these apart"
const NO_LIST := "There is no plant list here to narrow."
## Where the list came from, when somebody else made it short: a photograph's reading.
const SHORTLIST_CAPTION := "Where this shortlist came from"
const SITE_CAPTION := "The ground where this plant is going"

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

## Narrowing the key to the bed the plant is going in, and the way back. Two buttons with words that never
## change rather than one that changes its words: what each cannot do right now is said on its tooltip, the
## same rule the three buttons of state below follow.
const SUIT_HERE := "Only the plants that suit this spot"
const EVERY_PLANT := "Every plant in the list"
const NOTHING_TO_NARROW_TO := (
	"Nothing says what the ground is like here yet, so there is nothing to narrow to. The Site menu is "
	+ "where the ground is stated."
)
const NOTHING_SUITS_HERE := "Nothing in the list suits this spot, so the key is showing the whole list."
const ALREADY_NARROWED := "The key is already only the plants that suit this spot."
const NOT_NARROWED := "The key is showing every plant in the list already."

var _catalogue: PlantCatalogue = null
## The answers, in the order they were given - which is what taking one back reads.
var _answers: Dictionary = { }
## What the key last said, as `PlantKey.state` handed it over. Recomputed by `refresh` rather than kept
## in step by hand, so the page cannot show a question that no longer follows from the answers.
var _state: Dictionary = { }
## The question and the answer each button in the row stands for, in the order they were built.
var _choices: Array[Dictionary] = []
## The spot the plant is going in, as `ZoneMap.profile_at` returns it: `{profile, zone, place, source}`.
## Empty in a scene with no drawing, which is a page with no spot to narrow to rather than a fault.
var _site: Dictionary = { }
## Whether the key is narrowed to the spot's plants. Never true when that would be impossible.
var _narrowed: bool = false
## A shortlist somebody else made - the species a photograph's reading resolved to - or empty. Kept as ids
## rather than as a catalogue so the field can be narrowed again from it by the spot as well.
var _seed: Array[StringName] = []
## What made the shortlist, in the words the line above the questions uses. A **bare noun**: `PlantKey`'s
## own sentences put the article in front of it.
var _seed_source: String = "photograph"
## The list the key is really narrowing: the whole catalogue, or the plants that suit the spot. Kept in
## step by `_rebuild_field` rather than worked out on every `refresh`.
var _field: PlantCatalogue = null
## How many of the whole list suit the spot, so the count is asked of each plant once rather than on every
## refresh. Zero when there is no list, no stated spot, or nothing that suits it.
var _suited: int = 0

var _words: Label = null
var _prompt: Label = null
var _shortlist_caption: Label = null
var _shortlist_line: Label = null
var _site_line: Label = null
var _suit_button: Button = null
var _every_button: Button = null
var _options_row: GridContainer = null
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

	# Where the list came from, when somebody else made it short. Above the ground, because it is about the
	# list itself rather than about the bed - and **shown only when there is one**: a caption over nothing
	# is worse than no caption, and the page's own explanation already says where the list normally comes
	# from.
	_shortlist_caption = _caption(SHORTLIST_CAPTION)
	column.add_child(_shortlist_caption)
	_shortlist_line = _says(column, "Shortlist")
	_shortlist_line.add_theme_color_override("font_color", PageChrome.HINT_COLOR)

	# What the ground is like where this plant is going, and what that leaves of the list. Said before the
	# questions rather than after them: it is the context the whole key is being read in.
	column.add_child(_caption(SITE_CAPTION))
	_site_line = _says(column, "Site")
	_site_line.add_theme_color_override("font_color", PageChrome.HINT_COLOR)
	var site_row := HBoxContainer.new()
	site_row.name = "SiteButtons"
	column.add_child(site_row)
	_suit_button = _button(site_row, "SuitHere", SUIT_HERE)
	_suit_button.pressed.connect(only_the_ones_that_suit)
	_every_button = _button(site_row, "EveryPlant", EVERY_PLANT)
	_every_button.pressed.connect(show_every_plant)

	column.add_child(_caption(WORDS_CAPTION))
	_words = _says(column, "Words")
	_words.add_theme_color_override("font_color", PageChrome.HINT_COLOR)

	column.add_child(_caption(PROMPT_CAPTION))
	_prompt = _says(column, "Prompt")

	# A grid whose columns share the page, rather than a flow of buttons that keep their own width: the
	# answers to a question run from two to twelve, and an answer with a drawing beside it is a different
	# size from one without. Every cell takes an equal share and the words wrap inside it, so the row fits
	# whatever the window is. `_fit_answer` is where that is arranged.
	_options_row = GridContainer.new()
	_options_row.name = "Answers"
	_options_row.columns = ANSWER_COLUMNS
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
	if _catalogue == null:
		_narrowed = false
	_rebuild_field()
	refresh()

# --- showing what the key says -----------------------------------------------------------


## Ask the key what the answers amount to and show it: which question, what it says, the answers worth
## offering and the plants left. One call, so the three cannot come apart.
func refresh() -> void:
	if _words == null:
		return
	if _field == null:
		_state = { }
		_words.text = NO_LIST
		_prompt.text = ""
	else:
		_state = KeyScript.state(_field, _answers)
		_words.text = String(_state["words"])
		_prompt.text = String(_state["prompt"])
	_refresh_site()
	_rebuild_answers()
	_rebuild_matches()
	_refresh_buttons()


## Say what the ground is like where the plant is going, and what that leaves of the list. The sentence is
## `PlantKey.spot_words`'s, so the count on the page and the count the key narrows by are one arithmetic.
func _refresh_site() -> void:
	if _site_line == null:
		return
	_site_line.text = NO_LIST if _catalogue == null else KeyScript.spot_words(_catalogue, _profile(), _place())
	_refresh_shortlist()


## Say where a shortlist came from, and hide the line when there is none. Hiding rather than wording a
## nothing-case, because there is nothing to say: no shortlist means the list is the whole catalogue, which
## is what the page already reads as.
func _refresh_shortlist() -> void:
	if _shortlist_line == null:
		return
	var words: String = shortlist_text()
	_shortlist_line.text = words
	_shortlist_line.visible = not words.is_empty()
	if _shortlist_caption != null:
		_shortlist_caption.visible = not words.is_empty()


# --- the bed the plant is going in -----------------------------------------------------------


## Hand the page the spot the plant is going in: what the plan says the ground is like there, and the
## words for the place, as `ZoneMap.profile_at` returns them. An empty dictionary is a scene with no
## drawing, which is a page with no spot to narrow to rather than a fault.
##
## A narrowing that has just become impossible is dropped rather than kept: a spot that has been un-stated,
## or one nothing in the list suits, must not leave the key claiming to show a bed it is not.
func suit_to(spot: Dictionary) -> void:
	_site = spot
	if _narrowed and not _possible():
		_narrowed = false
	_rebuild_field()
	refresh()


## Narrow the key to the plants that suit the spot, which is the question "what can I plant here".
##
## Off, and saying why, when there is nothing to narrow to: a spot nobody has described, a list nothing in
## it suits, or a key already narrowed. Each of those is answered in words rather than by leaving the button
## looking broken.
func only_the_ones_that_suit() -> bool:
	if not can_narrow():
		_say(_why_not_narrow())
		return false
	_narrowed = true
	_rebuild_field()
	_say("The key is now only the plants that suit this spot.")
	refresh()
	return true


## Whether the key is narrowed to the spot's plants.
func is_narrowed() -> bool:
	return _narrowed


## Whether the key is narrowed to a shortlist somebody else made - the plants a photograph offered.
##
## **Whether it is really narrowing**, not whether somebody asked: a reading the list cannot place leaves
## every plant in the key, and a button offering to widen that key again would be a button that does nothing.
func is_from_a_shortlist() -> bool:
	return not _seed.is_empty() and _field != null and _field != _catalogue


## Narrow the key to a shortlist somebody else made: the species a photograph's reading resolved to.
##
## **The page takes ids, not names.** Turning what a model said into a species is `PlantIDResolver`'s
## business, and it is the caller - the capture page, which has the reading in hand - that asks it. A second
## join here would be a second answer to the same question, which is the defect this program is arranged
## against.
##
## An id the list does not have is left out by `PlantKey.among`, so a shortlist the catalogue cannot answer
## leaves the whole key rather than emptying it, and the line above says so.
func from_a_shortlist(ids: Array, source: String = "photograph") -> void:
	_seed.clear()
	for raw: Variant in ids:
		var wanted: StringName = StringName(raw) if raw is String or raw is StringName else &""
		if not wanted.is_empty():
			_seed.append(wanted)
	_seed_source = source
	if _narrowed and not _possible():
		_narrowed = false
	_rebuild_field()
	refresh()


## What the line above the questions says about a shortlist, or "" when there is none.
func shortlist_text() -> String:
	if _seed.is_empty():
		return ""
	return KeyScript.shortlist_words(_catalogue, _seed, _seed_source)


## Widen the key back to the whole plant list. **The way out is as reachable as the way in**: somebody who
## narrowed the key and then wants to name the plant actually in front of them is not left with a key that
## cannot name it. This drops **both** kinds of narrowing, because it says every plant, and that is what it
## has to mean.
func show_every_plant() -> bool:
	if not is_from_a_shortlist() and not _narrowed:
		_say(NOT_NARROWED)
		return false
	_narrowed = false
	_seed.clear()
	_rebuild_field()
	_say("The key is showing every plant in the list again.")
	refresh()
	return true


## Whether the key can be narrowed to the spot at all: there is a list, the plan says what the ground is
## like, and something in the list suits it.
func can_narrow() -> bool:
	return not _narrowed and _possible()


## How many of the whole list suit the spot - zero when there is no list, no stated spot, or nothing that
## suits it.
func suited_count() -> int:
	return _suited


func _possible() -> bool:
	return _catalogue != null and _suited > 0


## The catalogue the key is really narrowing, and how many of the whole list suit the spot.
##
## Worked out here rather than in `refresh`, because it is one suitability check per plant and `refresh`
## runs on every answer. The four callers - `bind`, `suit_to`, `only_the_ones_that_suit` and
## `show_every_plant` - are the only things that can change what it should be.
func _rebuild_field() -> void:
	_field = _catalogue
	_suited = 0
	if _catalogue == null:
		_seed.clear()
		return
	# A shortlist narrows the list first, and the spot narrows what is left of it: a photograph says which
	# plants it could be, and the bed says which of those will live here. Both are the same mechanism, so
	# neither can undo the other.
	var from: PlantCatalogue = _catalogue
	if not _seed.is_empty():
		var shortlist: PlantCatalogue = KeyScript.among(_catalogue, _seed)
		# **A shortlist the list cannot answer leaves the whole key standing.** A key of no plants is not a
		# narrowed key, it is a broken page - and a model naming something this catalogue does not stock is
		# an ordinary thing to happen. `shortlist_words` is what tells the person.
		if shortlist.count() > 0:
			from = shortlist
	_field = from
	var profile: TerrainProfile = _profile()
	if not KeyScript.states_the_ground(profile):
		return
	_suited = KeyScript.suiting(from, profile).size()
	if _narrowed and _suited > 0:
		_field = KeyScript.for_the_spot(from, profile)


## The spot's own conditions, or null when the page was handed no spot.
func _profile() -> TerrainProfile:
	var found: Variant = _site.get("profile", null)
	return found if found is TerrainProfile else null


## What the spot is called, in the words `ZoneMap` gave it.
func _place() -> String:
	return String(_site.get("place", ""))


## Why the key cannot narrow to the spot, in the words of the thing that is missing.
func _why_not_narrow() -> String:
	if _narrowed:
		return ALREADY_NARROWED
	if _catalogue == null:
		return NO_LIST
	if not KeyScript.states_the_ground(_profile()):
		return NOTHING_TO_NARROW_TO
	return NOTHING_SUITS_HERE


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
		var option_key: StringName = StringName(option["key"])
		_choices.append({ "question": question, "option": option_key })
		var button := PageChrome.button(_answer_words(option))
		button.name = "Answer%d" % index
		# The drawing of the answer, where one has been made. It is offered **beside** the words rather than
		# instead of them, and an answer nobody has drawn is a button exactly like this one without it.
		var picture: String = KeyScript.picture_for(question, option_key)
		if picture != "":
			button.icon = ResourceLoader.load(picture)
			button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
			button.add_theme_constant_override("icon_max_width", PICTURE_WIDTH)
		_fit_answer(button, picture != "")
		button.pressed.connect(choose.bind(index))
		_options_row.add_child(button)
	# "Not sure" comes after the answers because it is not one of them: it is a way past a question somebody
	# cannot answer. It is offered only while there is a question to pass, and it is kept as an answer, so
	# the key moves on rather than asking the same thing again.
	if question != &"":
		var unsure := PageChrome.button(NOT_SURE)
		unsure.name = "NotSure"
		_fit_answer(unsure, false)
		unsure.pressed.connect(skip)
		_options_row.add_child(unsure)
	if _options_row.get_child_count() > 0:
		# Buttons built while the page is open: somebody who reached the page with the keyboard has to be
		# able to reach these too.
		PageChrome.takes_the_keyboard_if_up(self)


## Let an answer's button be narrower than its own words, and wrap them instead.
##
## A `Button` is by default exactly as wide as the sentence on it, and that is what ran a row of twelve
## answers off the side of the page: "oval and widest below the middle  (1 plant)" is 339 pixels on its own,
## and no two of those fit beside each other in a 720 pixel page. Allowing the text to be clipped is what
## lets the button be narrower than its text; allowing it to wrap is what stops that from being a sentence
## cut in half. The height is then the page's to state, because the words take two lines now.
func _fit_answer(button: Button, drawn: bool) -> void:
	button.clip_text = true
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.custom_minimum_size.y = (PICTURE_WIDTH if drawn else 0) + TWO_LINES


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
	var possible: bool = can_narrow()
	if _suit_button != null:
		_suit_button.disabled = not possible
		_suit_button.tooltip_text = SUIT_HERE if possible else _why_not_narrow()
	if _every_button != null:
		var narrowed_at_all: bool = _narrowed or is_from_a_shortlist()
		_every_button.disabled = not narrowed_at_all
		_every_button.tooltip_text = EVERY_PLANT if narrowed_at_all else NOT_NARROWED

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


## The drawing on an answer's button, or null when nobody has drawn that answer.
func option_picture(index: int) -> Texture2D:
	if _options_row == null or index < 0 or index >= _options_row.get_child_count():
		return null
	return (_options_row.get_child(index) as Button).icon


## One of the page's own buttons, by the name it was built with, so a test reads whether a button can act
## from the button itself rather than from a second reading of the state. `owned` is false because these
## are built in code and have no owner.
func the_button(node_name: String) -> Button:
	return find_child(node_name, true, false) as Button


func match_count() -> int:
	return _matches.get_child_count() if _matches != null else 0


## What the page says about the ground where the plant is going.
func site_text() -> String:
	return _site_line.text if _site_line != null else ""


## How many plants the key is really narrowing right now - the whole list, or the ones that suit the spot.
func field_count() -> int:
	return _field.count() if _field != null else 0


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