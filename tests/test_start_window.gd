extends Node
## The front door page (`res://scripts/start_window.gd`), driven off-tree.
##
## What is held here is that the door offers exactly the two choices the model names, that pressing one
## takes that one, and that closing it lands in the drawing board rather than on a dark screen. What the
## words are is `test_start_choices.gd`'s: this file only asks that the page uses them and shows nothing it
## invented.

const PageScript := preload("res://scripts/start_window.gd")
const StartScript := preload("res://scripts/start_choices.gd")


func _page() -> Window:
	var page: Window = PageScript.new()
	page.build()
	page.visible = true
	return page


## The door offers the two things the program is for, in the model's order, and each is a button a person can
## press rather than a line of text.
func test_the_door_offers_the_two_choices_as_buttons() -> void:
	var page: Window = _page()
	assert(
		page.choice_buttons() == StartScript.ids(),
		"the buttons are the model's choices, in its order: %s" % str(page.choice_buttons())
	)
	for id: StringName in StartScript.ids():
		var made: Button = page.button_of(id)
		assert(made != null, "%s is a button" % String(id))
		assert(made.text == String(StartScript.CHOICES[StartScript.ids().find(id)]["label"]), "saying %s" % made.text)
		assert(made.visible, "and it is on the page")
	page.free()


## Pressing a button takes that choice and no other: the page answers with the id its button was made for.
func test_pressing_a_button_takes_that_choice() -> void:
	var page: Window = _page()
	var taken: Array[StringName] = []
	page.chosen.connect(func(id: StringName) -> void: taken.append(id))
	page.button_of(StartScript.CAMERA).pressed.emit()
	assert(taken == [StartScript.CAMERA], "the camera was taken: %s" % str(taken))
	page.free()


## The drawing board choice puts the door away, because there is nothing to open: the drawing is already
## behind the page. This is the half a mode would have got wrong, and the half a demo caught first.
func test_the_drawing_choice_puts_the_door_away() -> void:
	var page: Window = _page()
	page.button_of(StartScript.DESIGN).pressed.emit()
	assert(not page.visible, "the door is put away")
	page.free()


## However the door is dismissed - its Close button, Escape turning into `close_requested`, or the title
## bar's cross - it is put away and says so once, which is the convention every other page here keeps.
func test_dismissing_the_door_puts_it_away_and_says_so_once() -> void:
	var page: Window = _page()
	var said: Array[bool] = []
	page.connect(&"closed", func() -> void: said.append(true))
	page.request_close()
	assert(not page.visible, "the door is put away")
	assert(said.size() == 1, "and it said so once: %d time(s)" % said.size())
	page.free()


## And closing means the drawing board rather than nothing at all - the model's answer, which the page reads
## instead of deciding for itself which button happens to be the way out.
func test_closing_the_door_means_the_drawing_board() -> void:
	assert(
		StartScript.dismissed() == StartScript.DESIGN,
		"a dismissed front door is the drawing, not a dark screen: %s" % StartScript.dismissed()
	)


## A choice nobody offers is refused by name and takes nothing: a door that answered a third id by doing
## something would be offering a third thing.
func test_a_choice_that_is_not_on_the_door_is_refused_by_name() -> void:
	var page: Window = _page()
	var taken: Array[StringName] = []
	page.chosen.connect(func(id: StringName) -> void: taken.append(id))
	page.choose(&"print the invoice")
	assert(taken.is_empty(), "nothing was taken: %s" % str(taken))
	assert(
		page.status_text().contains("print the invoice"),
		"and the page names what it does not have: %s" % page.status_text()
	)
	page.free()


## The page says what the program is before it asks anything, in the model's own words.
func test_the_door_says_what_the_program_is_before_it_asks() -> void:
	var page: Window = _page()
	assert(page.title == StartScript.TITLE, "named the way its title bar names it: %s" % page.title)
	assert(page.opening_text() == StartScript.OPENING, "and explaining itself: %s" % page.opening_text())
	assert(not page.opening_text().is_empty(), "with something to say")
	page.free()


## Building twice is the same door: a page that added its buttons again on a second build would offer four
## choices and press one of them twice.
func test_building_twice_is_the_same_door() -> void:
	var page: Window = _page()
	page.build()
	assert(page.choice_buttons().size() == 2, "still two choices: %s" % str(page.choice_buttons()))
	var row: Control = page.find_child("CloseButton", true, false) as Control
	assert(row != null, "and still one way to close it")
	page.free()