extends Node
## The begin-a-drawing page (`res://scripts/start_drawing_window.gd`), driven off-tree.
##
## What is held here is that the page offers exactly the four ways the model names, that taking one answers
## with its id and puts the page away, that the recent way shows the drawings to come back to rather than
## leaving, and that a way nobody offers is refused by name. What the words are is `test_start_drawing.gd`'s:
## this file only asks that the page uses them and shows nothing it invented.

const PageScript := preload("res://scripts/start_drawing_window.gd")
const StartScript := preload("res://scripts/start_drawing.gd")

const A_DRAWING := "user://drawings/rose-bed.json"


func _page() -> Window:
	var page: Window = PageScript.new()
	page.build()
	page.visible = true
	return page


## One remembered drawing, as the store gives them - a typed array, which is what `bind_recent` takes.
func _one() -> Array[String]:
	var paths: Array[String] = [A_DRAWING]
	return paths


## The page offers the four ways the model names, in the model's order, each a button a person can press.
func test_the_page_offers_the_four_ways_as_buttons() -> void:
	var page: Window = _page()
	assert(
		page.choice_buttons() == StartScript.ids(),
		"the buttons are the model's ways, in its order: %s" % str(page.choice_buttons())
	)
	for id: StringName in StartScript.ids():
		var made: Button = page.button_of(id)
		assert(made != null, "%s is a button" % String(id))
		assert(made.text == String(StartScript.way(id)["label"]), "saying %s" % made.text)
	page.free()


## Pressing a way that leaves takes it and puts the page away: the drawing board stands behind, so taking a
## way and closing the page are the same act.
func test_pressing_a_way_takes_it_and_puts_the_page_away() -> void:
	var page: Window = _page()
	var taken: Array[StringName] = []
	page.chosen.connect(func(id: StringName) -> void: taken.append(id))
	page.button_of(StartScript.NEW).pressed.emit()
	assert(taken == [StartScript.NEW], "the new sheet was taken: %s" % str(taken))
	assert(not page.visible, "and the page is put away")
	page.free()


## The recent way does not leave: it reveals the drawings to come back to, because there is still a choice
## to make, and says what to do with them.
func test_the_recent_way_reveals_the_drawings_instead_of_leaving() -> void:
	var page: Window = _page()
	var taken: Array[StringName] = []
	page.chosen.connect(func(id: StringName) -> void: taken.append(id))
	page.bind_recent(_one())
	page.button_of(StartScript.RECENT).pressed.emit()
	assert(taken.is_empty(), "nothing was taken yet: %s" % str(taken))
	assert(page.visible, "the page stays up to offer the drawings")
	assert(page.recent_buttons().size() == 1, "one drawing to come back to")
	assert(page.status_text() == StartScript.RECENT_HINT, "and it says what to do: %s" % page.status_text())
	page.free()


## Pressing one of the remembered drawings answers with its path - the file it opens - and puts the page
## away, exactly as taking a way does.
func test_pressing_a_remembered_drawing_opens_that_one_and_puts_the_page_away() -> void:
	var page: Window = _page()
	var opened: Array[String] = []
	page.recent_chosen.connect(func(path: String) -> void: opened.append(path))
	page.bind_recent(_one())
	page.choose(StartScript.RECENT)
	page.recent_buttons()[0].pressed.emit()
	assert(opened == [A_DRAWING], "that drawing: %s" % str(opened))
	assert(not page.visible, "and the page is put away")
	page.free()


## With nothing remembered, the recent way says so in words and shows no empty list.
func test_with_nothing_recent_the_page_says_so_and_shows_no_list() -> void:
	var page: Window = _page()
	var none: Array[String] = []
	page.bind_recent(none)
	page.choose(StartScript.RECENT)
	assert(
		page.status_text() == StartScript.NOTHING_RECENT,
		"the refusal is a sentence: %s" % page.status_text()
	)
	var section: Control = page.find_child("RecentSection", true, false) as Control
	assert(section != null and not section.visible, "and no empty list is shown")
	page.free()


## A way nobody offers is refused by name and takes nothing.
func test_a_way_that_is_not_offered_is_refused_by_name() -> void:
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


## The page says what it is before it asks anything, in the model's own words.
func test_the_page_says_what_it_is_before_it_asks() -> void:
	var page: Window = _page()
	assert(page.title == StartScript.TITLE, "named the way its title bar names it: %s" % page.title)
	assert(page.opening_text() == StartScript.OPENING, "and explaining itself: %s" % page.opening_text())
	assert(not page.opening_text().is_empty(), "with something to say")
	page.free()


## However the page is dismissed - its Close button, Escape turning into `close_requested`, or the title
## bar's cross - it is put away and says so once, the convention every other page here keeps.
func test_dismissing_the_page_puts_it_away_and_says_so_once() -> void:
	var page: Window = _page()
	var said: Array[bool] = []
	page.connect(&"closed", func() -> void: said.append(true))
	page.request_close()
	assert(not page.visible, "the page is put away")
	assert(said.size() == 1, "and it said so once: %d time(s)" % said.size())
	page.free()


## Building twice is the same page: a second build would offer the ways again and show two recent lists.
func test_building_twice_is_the_same_page() -> void:
	var page: Window = _page()
	page.build()
	assert(page.choice_buttons().size() == 4, "still four ways: %s" % str(page.choice_buttons()))
	var row: Control = page.find_child("CloseButton", true, false) as Control
	assert(row != null, "and still one way to close it")
	page.free()