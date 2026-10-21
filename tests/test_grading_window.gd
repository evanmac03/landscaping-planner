extends Node
## The grading page, driven off-tree.
##
## No drawing, no HUD, no window server and no `popup_centered`, which is what the split between a page
## and the HUD is for. Every press goes through the caption a person reads, so a test cannot keep
## passing after a caption has been changed to something nobody would recognise.
##
## The two claims worth making here are about *silence*: being told the level must not announce it (or
## the page would drive the controller in a circle), and pressing Set must announce exactly what the
## field holds.

const GradingWindowScript := preload("res://scripts/grading_window.gd")
const GradingScript := preload("res://scripts/draft/grading.gd")

const SPOT := GradingScript.SPOT
const CONTOUR := GradingScript.CONTOUR
const SLOPE := GradingScript.SLOPE

## What the page announced, in order. A member rather than a captured local, because a lambda captures
## what it is given rather than sharing it.
var _announced: Array[String] = []


# --- helpers --------------------------------------------------------------------------


func _page() -> GradingWindow:
	var window := GradingWindowScript.new()
	window.build()
	window.level_requested.connect(func(level: float) -> void: _announced.append("level:%s" % str(level)))
	window.fall_requested.connect(func(percent: float) -> void: _announced.append("fall:%s" % str(percent)))
	window.tool_requested.connect(func(kind: String) -> void: _announced.append("tool:" + kind))
	window.change_requested.connect(func(kind: String, id: int, level: float) -> void:
		_announced.append("change:%s:%d:%s" % [kind, id, str(level)]))
	window.remove_requested.connect(func(kind: String, id: int) -> void:
		_announced.append("remove:%s:%d" % [kind, id]))
	window.closed.connect(func() -> void: _announced.append("close"))
	return window


## Press a button by the caption a person reads.
func _press(window: GradingWindow, caption: String) -> bool:
	for found: Node in window.find_children("*", "Button", true, false):
		var button := found as Button
		if button.text == caption:
			button.pressed.emit()
			return true
	return false


## The one announcement a press made, or "" when the page carries no such button or announced nothing.
func _ask(window: GradingWindow, caption: String) -> String:
	var before := _announced.size()
	if not _press(window, caption):
		return ""
	if _announced.size() != before + 1:
		return ""
	return _announced[before]


## A record as the controller hands one over: what it is, which one it is, and how it reads.
func _row(kind: String, id: int, text: String) -> Dictionary:
	return {"kind": kind, "kind_name": GradingScript.kind_name(kind), "id": id, "text": text}


func _three_rows() -> Array[Dictionary]:
	return [
		_row(SPOT, 1, "102.35 m   (0, 0)"),
		_row(SPOT, 2, "101.95 m   (6, 0)"),
		_row(CONTOUR, 1, "101.50 m   2 points   6.0 m"),
	]


# --- a page nobody has opened ----------------------------------------------------------


func test_a_page_that_was_never_asked_for_is_not_over_the_drawing() -> void:
	var window := GradingWindowScript.new()
	window.build()
	assert(not window.visible, "a form nobody opened must not be in front of the drawing")
	assert(window.title == "Grading", window.title)
	assert(window.min_size == GradingWindowScript.SIZE, str(window.min_size))
	assert(window.record_texts() == [GradingWindowScript.NOTHING_YET], str(window.record_texts()))
	assert(window.report_text() == GradingWindowScript.AGREES, window.report_text())
	assert(window.chosen_kind() == "", "and nothing is chosen")
	assert(not window.change_enabled(), "so there is nothing to change")
	assert(not window.remove_enabled(), "and nothing to take off")
	window.free()


func test_building_the_page_twice_builds_it_once() -> void:
	var window := _page()
	var children := window.get_child_count()
	window.build()
	assert(window.get_child_count() == children, "a page built twice is the page it was")
	assert(children == 1, "one column holds the whole page: %d" % children)
	window.free()


func test_the_page_carries_a_field_for_each_number_and_no_more() -> void:
	# The two number fields are the reason this page is a `Window` rather than a panel: a level has to
	# be typed, and anything that takes the keyboard inside the HUD takes the drawing's keys with it.
	var window := _page()
	var spins: Array[Node] = window.find_children("*", "SpinBox", true, false)
	assert(spins.size() == 2, "a level and a fall: %d" % spins.size())
	for found: Node in spins:
		assert((found as SpinBox).editable, "and both can be typed into")
	assert(window.list_is_keyboard_free(), "while nothing else on the page takes the keyboard")
	window.free()


func test_every_button_says_what_it_does() -> void:
	var window := _page()
	var captions := window.button_texts()
	for wanted: String in [
		"Set the level", "Set the fall", "Spot level here", "Draw a contour", "Draw a slope arrow",
	]:
		assert(captions.has(wanted), "%s is on the page: %s" % [wanted, str(captions)])
	assert(captions.has("Nothing chosen to take off"),
		"and the one that cannot act yet says what is missing: %s" % str(captions))
	window.free()


# --- the two numbers in hand ---------------------------------------------------------------


func test_the_two_numbers_go_in_and_come_out_as_typed() -> void:
	var window := _page()
	window.set_level(102.35)
	window.set_fall(2.5)
	assert(is_equal_approx(window.level(), 102.35), str(window.level()))
	assert(is_equal_approx(window.fall(), 2.5), str(window.fall()))
	assert(window.level_text() == "102.35 m", window.level_text())
	assert(window.fall_text() == "2.5 %", window.fall_text())
	window.free()


func test_being_told_a_number_does_not_announce_it() -> void:
	# A page that announced the state it was handed would drive the controller in a circle, and the
	# controller would overwrite what the designer is in the middle of typing.
	var window := _page()
	window.set_level(102.35)
	window.set_fall(2.5)
	assert(_announced.is_empty(), "filling the page says nothing: " + str(_announced))
	window.free()


func test_pressing_set_announces_exactly_what_the_field_holds() -> void:
	var window := _page()
	window.set_level(102.35)
	assert(_ask(window, "Set the level") == "level:102.35", str(_announced))
	window.set_fall(2.5)
	assert(_ask(window, "Set the fall") == "fall:2.5", str(_announced))
	# And the level field is read at the moment of the press rather than remembered.
	window.set_level(99.0)
	assert(_ask(window, "Set the level") == "level:99.0", str(_announced))
	window.free()


func test_each_of_the_three_tool_buttons_announces_its_own_kind() -> void:
	var window := _page()
	assert(_ask(window, "Spot level here") == "tool:spot", str(_announced))
	assert(_ask(window, "Draw a contour") == "tool:contour", str(_announced))
	assert(_ask(window, "Draw a slope arrow") == "tool:slope", str(_announced))
	window.free()


# --- the list ---------------------------------------------------------------------------------


func test_the_records_are_listed_and_the_list_is_only_written_when_it_changes() -> void:
	var window := _page()
	assert(window.show_records(_three_rows()), "a list that has moved is written")
	assert(window.record_texts() == [
		"102.35 m   (0, 0)", "101.95 m   (6, 0)", "101.50 m   2 points   6.0 m",
	], str(window.record_texts()))
	assert(not window.show_records(_three_rows()), "**and the same list again is not**: a list rebuilt "
		+ "under somebody's cursor every frame is a list they cannot click")
	var moved := _three_rows()
	moved[0]["text"] = "102.40 m   (0, 0)"
	assert(window.show_records(moved), "but a level that has changed is a row that has changed")
	assert(window.record_texts()[0] == "102.40 m   (0, 0)", str(window.record_texts()))
	assert(window.show_records([]), "and a drawing with nothing on it holds the placeholder")
	assert(window.record_texts() == [GradingWindowScript.NOTHING_YET], str(window.record_texts()))
	window.free()


func test_the_choice_survives_the_list_being_written_again() -> void:
	var window := _page()
	window.show_records(_three_rows())
	assert(window.choose_record(2), "the third row is chosen")
	assert(window.chosen_kind() == CONTOUR, window.chosen_kind())
	assert(window.chosen_id() == 1, str(window.chosen_id()))
	window.show_records(_three_rows())
	assert(window.chosen_id() == 1, "and it is still chosen after the page is filled again")
	assert(window.remove_enabled(), "so the buttons that act on it are live")
	# A record that has gone cannot stay chosen: the page is not allowed to act on something the
	# drawing no longer holds.
	window.show_records([_row(SPOT, 1, "102.35 m   (0, 0)")])
	assert(window.chosen_kind() == "", "the contour is no longer on the drawing, so nothing is chosen")
	assert(not window.remove_enabled(), "and the button goes off again")
	assert(not window.choose_record(9), "and a row that is not there cannot be chosen")
	window.free()


func test_change_announces_the_chosen_record_and_the_level_in_the_field() -> void:
	var window := _page()
	window.show_records(_three_rows())
	window.choose_record(1)
	window.set_level(103.0)
	assert(_ask(window, "Change the level") == "change:spot:2:103.0", str(_announced))
	# With nothing chosen there is nothing to announce, and the button is off. Pressing it by hand is
	# something only a test can do, and even then the page says nothing.
	window.show_records([])
	assert(not window.change_chosen(), "nothing chosen, nothing changed")
	assert(not window.change_enabled(), "so the button is switched off")
	assert(_ask(window, "Change the level") == "", str(_announced))
	window.free()


func test_remove_announces_the_chosen_record() -> void:
	var window := _page()
	window.show_records(_three_rows())
	window.choose_record(2)
	assert(_ask(window, "Take it off the drawing") == "remove:contour:1", str(_announced))
	window.show_records([])
	assert(not window.remove_chosen(), "nothing chosen, nothing taken off")
	window.free()


# --- the report -------------------------------------------------------------------------------


func test_the_report_reads_findings_first_and_then_what_is_worth_knowing() -> void:
	var window := _page()
	window.set_report({
		"ok": false,
		"findings": ["the arrow at (0, 0) says falling 2.5% (1 in 40) and the levels at its ends say "
			+ "falling 6.7% (1 in 15)"],
		"notes": ["the levels run from 101.95 m to 102.35 m, 0.4 m apart"],
	})
	assert(window.report_text().begins_with("- the arrow at (0, 0) says falling 2.5%"),
		window.report_text())
	assert(window.report_text().contains("\nthe levels run from"), "and the note follows it")
	window.set_report({"ok": true, "findings": [], "notes": ["nothing to say"]})
	assert(window.report_text() == "%s\nnothing to say" % GradingWindowScript.AGREES,
		window.report_text())
	window.set_report({})
	assert(window.report_text() == GradingWindowScript.AGREES, window.report_text())
	window.free()


func test_what_the_page_says_about_itself_is_the_controller_s_words() -> void:
	var window := _page()
	assert(window.said() == "", "it has said nothing")
	window.say("102.35 m at (0, 0) is on the drawing, with 2 marks")
	assert(window.status_text() == "102.35 m at (0, 0) is on the drawing, with 2 marks",
		window.status_text())
	assert(window.said() == window.status_text(), "and the status line is where it went")
	window.show_records([])
	window.say("")
	assert(window.status_text() == GradingWindowScript.NOTHING_YET, window.status_text())
	window.show_records(_three_rows())
	window.say("")
	assert(window.status_text() == "3 records on this drawing", window.status_text())
	window.free()


# --- closing -----------------------------------------------------------------------------------


func test_closing_the_page_by_the_button_or_by_the_x_announces_the_same_thing() -> void:
	var window := _page()
	assert(_ask(window, "Close") == "close", str(_announced))
	var before := _announced.size()
	window.close_requested.emit()
	assert(_announced.size() == before + 1 and _announced[before] == "close",
		"the X on the frame is the same act as the button: " + str(_announced))
	window.free()