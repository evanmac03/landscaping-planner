extends Node
## The model advisor's own rules: that the page invents nothing `DeviceModelFit` did not say, that a
## machine which cannot say how much memory it has is told so rather than shown a zero, and that a
## machine too tight to carry a model is told where to put one instead.
##
## The page is built off-tree, which is how it is asked here: a `Window` and `PageChrome` need no
## drawing, no HUD and no running program, and the machine is **stated** rather than measured - the
## same reason `DeviceModelFit` takes every one of its readings as an argument. A test drives a 32 GB
## desktop and a 2 GB netbook without being either.

const Advisor := preload("res://scripts/model_advisor_window.gd")
const Fit := preload("res://scripts/device_model_fit.gd")
const HudScript := preload("res://scripts/hud.gd")
const MenuBarPlanScript := preload("res://scripts/menu_bar_plan.gd")

## A machine with room to spare, one with none, and one in between - the three answers the module
## gives, each reached by a reading rather than by a different code path.
const ROOMY_GB := 32.0
const PLAIN_GB := 8.0
const TIGHT_GB := 2.0


## The page, holding the machine stated, and not added to any tree: what a page is built and filled
## with is answerable without a screen.
func _page(machine: Dictionary) -> Advisor:
	var page: Advisor = Advisor.new()
	page.build()
	page.bind(machine)
	return page


## What a machine is, as `DeviceModelFit` reads it: every reading an argument.
func _machine(memory_gb: float, free_gb: float) -> Dictionary:
	return Fit.scan(
		"Windows",
		"a machine under test",
		"a processor under test",
		8,
		_bytes(memory_gb),
		_bytes(free_gb),
		_bytes(120.0),
		"a graphics card under test",
	)


## A machine that was read and would not say how much memory it has: a real state, and not the same
## thing as a machine with none to spare.
func _unreadable() -> Dictionary:
	return Fit.scan("Windows", "", "", 0, 0, 0, 0, "")


func _bytes(gigabytes: float) -> int:
	return int(gigabytes * 1000000000.0)


## A control on the page by the name the page gave it, found wherever it stands - inside the scroller
## a page whose contents may be longer than itself puts its column in.
func _named(page: Node, node_name: String) -> Label:
	var found: Label = page.find_child(node_name, true, false) as Label
	assert(found != null, "the page has a %s to read" % node_name)
	return found


## Every label the page carries, so that "the page says this" can be asked of the whole page rather
## than only of the lines a test remembered to look at.
func _every_label(page: Node) -> Array[Label]:
	var out: Array[Label] = []
	for node: Node in page.find_children("*", "Label", true, false):
		out.append(node as Label)
	return out


## **A page that is up before anybody asked for it is the one thing every page in this HUD has to
## avoid**: it covers the drawing the moment the program starts.
func test_the_page_is_not_up_before_anybody_asks_for_it() -> void:
	var page: Advisor = Advisor.new()
	page.build()
	assert(not page.visible, "a page built and never opened is not on the screen")
	assert(page.title == "Find a model for this device", "and it is the page the menu names: %s" % page.title)
	page.free()


## **The page invents nothing.** What it says the machine is, is the module's own sentence for that
## reading - a second wording here would be a second answer to "what is this machine", and the two
## would disagree the first time either was touched.
func test_the_page_shows_the_machines_own_words_and_invents_none_of_its_own() -> void:
	var machine: Dictionary = _machine(PLAIN_GB, 6.0)
	var page: Advisor = _page(machine)
	assert(
		page.summary_words() == Fit.summary(machine),
		"the reading is the module's own sentence: %s" % page.summary_words(),
	)
	assert(page.summary_words().contains("32.0") == false, "for the machine in hand and not another")
	assert(page.summary_words() != Advisor.NO_READING, "and a machine that answered is not refused")
	page.free()


## **A zero and an absent reading are different answers.** The page shows the refusal naming what
## could not be read, and never a machine of no memory - which would read as one that can carry
## nothing, when the truth is that nobody was able to ask it.
func test_a_machine_that_cannot_say_how_much_memory_it_has_is_told_that_rather_than_shown_a_zero() -> void:
	var page: Advisor = _page(_unreadable())
	assert(not page.has_reading(), "a reading that did not happen is not a reading")
	assert(
		page.summary_words() == Advisor.NO_READING,
		"the page names what could not be read: %s" % page.summary_words(),
	)
	for label: Label in _every_label(page):
		assert(not label.text.contains("0 GB"), "and no line of it reports a machine of none: %s" % label.text)
	assert(page.hint() == Advisor.NO_READING, "and its guidance says the same thing")
	page.free()


## The advice is the module's, word for word: the page reads `suggest`'s own headline, reason and
## counts rather than deciding any of them again.
func test_the_advice_on_the_page_is_the_advice_the_module_worded() -> void:
	var machine: Dictionary = _machine(ROOMY_GB, 24.0)
	var page: Advisor = _page(machine)
	var advice: Dictionary = Fit.suggest(machine)
	assert(page.headline_words() == String(advice["headline"]), "the headline as the module put it")
	assert(page.reason_words() == String(advice["reason"]), "the reason as the module put it")
	assert(page.fitted_models().size() == (advice["fits"] as Array).size(), "and the same models fit")
	page.free()


## **A machine too tight to carry a model is not a failure - it is a different answer**, and the
## answer is a computer on the same Wi-Fi. The page reports that route and never offers a model that
## would be killed the moment it was started, which is the whole of what the module decided.
func test_a_machine_too_tight_to_carry_a_model_is_told_where_to_put_it_instead() -> void:
	var page: Advisor = _page(_machine(TIGHT_GB, 0.4))
	assert(page.needs_a_computer_beside_it(), "this machine is answered with the machine beside it")
	assert(page.fitted_models().is_empty(), "so no model is offered to run here")
	assert(not page.headline_words().is_empty(), "and the page still has an answer to show")
	assert(not page.step_lines().is_empty(), "with the steps that get the model running somewhere else")
	assert(not page.refusal_lines().is_empty(), "and the models it cannot carry, each with its reason")
	for line: String in page.refusal_lines():
		assert(line.ends_with("."), "a refusal is a sentence rather than a bare name: %s" % line)
	page.free()


## **A model that fits on paper but not in the memory that happens to be free is an experiment rather
## than a recommendation**, and the page carries the module's own warning about it instead of offering
## it like any other model. This is the one arrangement where an experiment exists at all: a machine
## with too little memory for anything, which is the machine in the test above, is offered none.
func test_a_machine_with_room_only_for_the_smallest_is_offered_it_as_an_experiment() -> void:
	var machine: Dictionary = _machine(3.5, 0.4)
	var worded: Dictionary = Fit.suggest(machine)["small_experiment"]
	assert(not worded.is_empty(), "the module offers this machine an experiment at all")
	var page: Advisor = _page(machine)
	assert(page.needs_a_computer_beside_it(), "and the answer is still the computer beside it")
	assert(page.fitted_models().is_empty(), "nothing is offered to run here as though it would survive")
	var experiment: String = page.experiment_words()
	assert(not experiment.is_empty(), "the smallest model is offered as an experiment")
	assert(
		experiment.contains(String(worded["warning"])),
		"and the page carries the module's own warning: %s" % experiment,
	)
	assert(
		experiment.contains(Fit.bytes_words(int(worded["download_bytes"]))),
		"with what it costs to fetch: %s" % experiment,
	)
	page.free()


## A machine with room is offered a model and told what it costs: the download **and** the memory, in
## the module's own words for each, because choosing between two models is choosing one against the
## other and a person cannot do that from a label alone.
func test_a_roomy_machine_is_offered_a_model_with_what_it_costs() -> void:
	var page: Advisor = _page(_machine(ROOMY_GB, 24.0))
	var lines: Array[String] = page.model_lines()
	assert(not lines.is_empty(), "a machine with room is offered at least one model")
	var first: Dictionary = page.fitted_models()[0]
	assert(
		lines[0].contains(Fit.bytes_words(int(first["download_bytes"]))),
		"the line says what the download is: %s" % lines[0],
	)
	assert(
		lines[0].contains(Fit.bytes_words(int(first["ram_needed_bytes"]))),
		"and what running it takes: %s" % lines[0],
	)
	page.free()


## The steps keep the module's order and are numbered, because they are followed in that order: fetch
## the model, then point the reading at it.
func test_every_step_is_numbered_in_the_order_the_module_gave_them() -> void:
	var machine: Dictionary = _machine(ROOMY_GB, 24.0)
	var page: Advisor = _page(machine)
	var steps: Array[String] = page.step_lines()
	var worded: Array = Fit.suggest(machine)["steps"]
	assert(steps.size() == worded.size(), "every step the module worded is on the page")
	for at: int in range(steps.size()):
		assert(steps[at].begins_with("%d. " % (at + 1)), "step %d is numbered in order: %s" % [at + 1, steps[at]])
		assert(steps[at].contains(String(worded[at])), "and it is the module's own sentence: %s" % steps[at])
	page.free()


## **The page says which question it does not ask.** Which models a runner already holds is the
## runner's answer and not this machine's, so the page names that edge: an empty list of models found
## would be read as "there are none on this machine", which is a different claim entirely.
func test_the_page_says_which_question_it_does_not_ask() -> void:
	var page: Advisor = _page(_machine(PLAIN_GB, 6.0))
	var note: Label = _named(page, "NotAsked")
	assert(note.text == Advisor.NOT_ASKED, "the page's own edge is written on the page")
	assert(note.text.contains("runner"), "and it names who would be asked: %s" % note.text)
	page.free()


## A page whose buttons hold the keyboard takes the drawing's own keys with it, so every button here
## is one the HUD's own pass has to give a Tab to rather than one that helps itself.
func test_no_control_on_the_page_can_take_the_drawings_keyboard() -> void:
	var page: Advisor = _page(_machine(PLAIN_GB, 6.0))
	var buttons: Array[Node] = page.find_children("*", "Button", true, false)
	assert(buttons.size() >= 2, "the page has the controls a person acts with: %d" % buttons.size())
	for node: Node in buttons:
		var press: Button = node as Button
		assert(press.focus_mode == Control.FOCUS_NONE, "%s does not take the keyboard by itself" % press.name)
	page.free()


## **The reading can be taken again**, which is the one reason this page has a button: free memory is
## the fact that moves while somebody reads. The scanner is the seam a test drives - and reading twice
## replaces what was there rather than adding to it.
func test_scanning_again_reads_the_machine_again() -> void:
	var page: Advisor = Advisor.new()
	page.build()
	page.set_scanner(
		func() -> Dictionary:
			return _machine(PLAIN_GB, 6.0),
	)
	assert(page.scan(), "the first reading is taken")
	var first: String = page.summary_words()
	page.set_scanner(
		func() -> Dictionary:
			return _machine(ROOMY_GB, 24.0),
	)
	assert(page.scan(), "and so is the second")
	assert(page.summary_words() != first, "which is not the reading that was there before")
	assert(page.summary_words() == Fit.summary(_machine(ROOMY_GB, 24.0)), "but the machine that was just read")
	page.free()


## The guidance follows the state the page is in: what it is waiting for before anything is read, and
## what it does not do once it has an answer - which is why the two are two sentences and not one.
func test_the_hint_changes_from_waiting_to_asking_for_another_reading() -> void:
	var page: Advisor = Advisor.new()
	page.build()
	assert(page.hint() == Advisor.NOTHING_READ, "a page nobody has read a machine for waits for one: %s" % page.hint())
	assert(page.summary_words() == Advisor.NOTHING_READ, "and says the same about the machine")
	page.bind(_machine(PLAIN_GB, 6.0))
	assert(
		page.hint() == Advisor.TAKE_ANOTHER_READING,
		"and once it has an answer it asks for another reading: %s" % page.hint(),
	)
	page.free()


## **A page in a `Window` takes the keyboard into its own viewport**, so Escape only reaches it if the
## HUD's own pass walks it - and a page built and left off that list is a page Escape silently stops
## working on, which is the fault the list is read against the HUD's own members to catch.
func test_the_hud_walks_the_page_with_its_own_escape_pass() -> void:
	var hud: HudScript = HudScript.new()
	hud._build_model_advisor_window()
	assert(hud.pages_in_windows().has(hud._model_advisor_window), "the page is on the list the pass walks")
	hud._let_escape_close_pages()
	assert(hud._model_advisor_window.get_node_or_null(^"PageEscape") != null, "and it can be escaped from")
	hud.free()


## The door itself: the HUD has the methods the menu names, and a HUD with no drawing open reports the
## page closed rather than failing - the page needs nothing of the plan.
func test_the_hud_has_the_door_the_menu_calls() -> void:
	var hud: HudScript = HudScript.new()
	assert(hud.has_method("open_model_advisor"), "the menu's entry reaches a method the HUD has")
	assert(hud.has_method("close_model_advisor"), "and so does closing it")
	assert(not hud.is_model_advisor_open(), "a HUD with no drawing has nothing open")
	hud.close_model_advisor()
	hud.free()


## The menu says a door exists, and it names a method the HUD really has: an entry whose method is
## missing does nothing when it is pressed, silently, which is the fault this pair of assertions is for.
func test_the_plant_menu_offers_the_page_and_names_a_real_method() -> void:
	var found: Dictionary = { }
	for entry: Dictionary in MenuBarPlanScript.plant_items():
		if String(entry.get("id", "")) == "plant.model":
			found = entry
	assert(not found.is_empty(), "the Plant menu offers the page")
	assert(
		StringName(found.get("method", &"")) == &"_menu_model_advisor",
		"and names the HUD's own method: %s" % str(found.get("method")),
	)
	assert(
		StringName(found.get("needs", &"x")) == &"",
		"which needs nothing of the drawing, so it opens in an empty scene: %s" % str(found.get("needs")),
	)
	var hud: HudScript = HudScript.new()
	assert(hud.has_method(String(found["method"])), "and the method it names is one the HUD has")
	hud.free()
