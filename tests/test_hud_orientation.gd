extends Node
## Which way up the window is asked to be, and what the HUD does when the room changes shape under a page
## that is standing on it.
##
## A HUD built off-tree with no `_ready`: no page is painted and no `DisplayServer` is asked anything, so
## what is held here is the *decision* - which shape the window is asked for, and which pages a change of
## shape has to put back where they belong. The asking and the moving themselves are a phone's, and a phone
## is where they were seen.

const HudScript := preload("res://scripts/hud.gd")
const OrientationChoiceScript := preload("res://scripts/orientation_choice.gd")

var _huds: Array[HudScript] = []


func _hud() -> HudScript:
	var hud: HudScript = HudScript.new()
	_huds.append(hud)
	return hud


func _free_huds() -> void:
	for hud: HudScript in _huds:
		hud.free()
	_huds.clear()


## The doorway is the front of the program and not a board, so while one of its two pages is up the window
## follows the phone - and the board's own answer is asked for again the moment it is over.
func test_the_window_follows_the_phone_while_either_doorway_page_is_up() -> void:
	var hud: HudScript = _hud()
	# Nobody is looking at a doorway on a HUD that has shown nothing, so the board's own answer is the one
	# asked for - set here rather than read from the file the machine running the tests happens to have.
	hud._orientation = OrientationChoiceScript.PORTRAIT
	assert(not hud.the_doorway_is_up(), "a HUD nobody has shown a page on has no doorway up")
	assert(
		hud.the_shape_for_the_window() == OrientationChoiceScript.PORTRAIT,
		"so the window is asked for the board's own answer"
	)
	hud._build_start_window()
	hud._start_window.visible = true
	assert(hud.the_doorway_is_up(), "the front door standing up is a doorway up")
	assert(
		hud.the_shape_for_the_window() == OrientationChoiceScript.DOORWAY,
		"and the window follows the phone while it stands there"
	)
	hud._build_start_drawing_window()
	hud._start_window.visible = false
	hud._start_drawing_window.visible = true
	assert(
		hud.the_doorway_is_up(),
		"the begin-a-drawing page is the doorway too, and it is the page the board choice leads to"
	)
	assert(
		hud.the_shape_for_the_window() == OrientationChoiceScript.DOORWAY,
		"so the window still follows the phone once the door has handed over to it"
	)
	hud._start_drawing_window.visible = false
	assert(
		hud.the_shape_for_the_window() == OrientationChoiceScript.PORTRAIT,
		"and the board's own answer is asked for again once the doorway is over"
	)
	_free_huds()


## A page is placed when it opens and never again, so a room that changes shape has to put the pages that
## are up back where they belong - and the front door is one of them, though it answers its own Escape and
## so is not in `pages_in_windows`.
func test_only_the_pages_that_are_up_are_the_ones_a_change_of_shape_reaches() -> void:
	var hud: HudScript = _hud()
	assert(
		hud._pages_that_are_up().is_empty(),
		"nothing is up on a HUD nobody has shown a page on"
	)
	hud._build_start_window()
	assert(
		hud._pages_that_are_up().is_empty(),
		"a page that is built and hidden is not a page a change of shape has to move"
	)
	assert(
		hud._pages_that_can_be_up().has(hud._start_window),
		"the front door is in the list a change of shape is walked over, though it is not one of the pages"
		+ " that answer Escape with a node of their own"
	)
	hud._start_window.visible = true
	assert(
		hud._pages_that_are_up().has(hud._start_window),
		"and once it is standing up it is one of the pages that is put back"
	)
	_free_huds()