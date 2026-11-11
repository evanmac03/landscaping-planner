extends Node
## The page that reads the drawing's answers back, driven off-tree.
##
## No drawing, no HUD, no window server and no `popup_centered`: the page is handed a history and lists
## it, and that split is the whole of what it decides. Two claims are worth more than the rest: **the
## rows are the drawing's own sentences, newest first** - not a paraphrase, not a re-ordering - and
## **the status line is what the page last did**, while the hint is the guidance, so a page that has
## only been told what to show has not done anything yet.

const WindowScript := preload("res://scripts/status_window.gd")
const HistoryScript := preload("res://scripts/draft/status_history.gd")


# --- helpers --------------------------------------------------------------------------


func _page() -> StatusWindow:
	var page: StatusWindow = WindowScript.new()
	page.build()
	return page


## A page whose history holds these answers, oldest first, and nothing else.
func _holding(lines: Array) -> StatusWindow:
	var page := _page()
	var history: StatusHistory = HistoryScript.new()
	for line: String in lines:
		history.note(line)
	page.set_history(history)
	return page


# --- the controls it has --------------------------------------------------------------


func test_the_page_has_the_controls_a_page_of_sentences_has() -> void:
	var page := _page()
	for path: String in [
		"Column",
		"Column/Heading",
		"Column/Explanation",
		"Column/Count",
		"Column/Lines",
		"Column/Hint",
		"Column/Buttons/CloseButton",
		"Column/Status",
	]:
		assert(page.get_node_or_null(NodePath(path)) != null, "the page has a %s" % path)
	page.free()


func test_the_page_is_built_once_however_many_times_it_is_asked_for() -> void:
	var page := _page()
	var columns := 0
	for child in page.get_children():
		if child.name == "Column":
			columns += 1
	page.build()
	page.build()
	var after := 0
	for child in page.get_children():
		if child.name == "Column":
			after += 1
	assert(after == columns, "a second build does not build a second page")
	page.free()


func test_the_rows_are_built_without_a_keyboard_of_their_own() -> void:
	# Sentences to read, not a list to drive. This asserts how the page *builds* the rows; what an open page
	# does with the keyboard is the shared show's business, and is measured live rather than here.
	var page := _holding(["line added", "shape added"])
	assert(page.rows_are_keyboard_free(), "the rows are built with no focus of their own")
	page.free()


# --- what it shows --------------------------------------------------------------------


func test_a_page_with_no_history_says_so_rather_than_showing_a_blank_frame() -> void:
	var page := _page()
	assert(page.line_count() == 0, "there are no rows")
	assert(page.hint() == WindowScript.NO_DRAWING, page.hint())
	assert(page.newest() == "", "and no newest answer")
	page.free()


func test_a_drawing_that_has_said_nothing_says_that_instead() -> void:
	var page := _page()
	page.set_history(HistoryScript.new())
	assert(page.line_count() == 0, "still no rows")
	assert(page.hint() == WindowScript.NOTHING_YET, page.hint())
	assert(page.count_text() == "no answers yet", page.count_text())
	page.free()


func test_the_rows_are_the_drawings_own_sentences_newest_first() -> void:
	var page := _holding(["line added", "1 entity erased", "line added"])
	var wanted: Array[String] = ["line added", "1 entity erased", "line added"]
	assert(page.line_texts() == wanted, str(page.line_texts()))
	assert(page.line_count() == 3, "one row per answer, including the one said twice")
	assert(page.newest() == "line added", "the top row is what the plan is saying now")
	page.free()


func test_the_count_says_how_many_and_the_cap_is_said_out_loud() -> void:
	var one := _holding(["line added"])
	assert(one.count_text() == "1 answer", one.count_text())
	one.free()
	var three := _holding(["a", "b", "c"])
	assert(three.count_text() == "3 answers", three.count_text())
	three.free()
	var full_list: Array = []
	for index in HistoryScript.CAP:
		full_list.append("answer %d" % index)
	var full := _holding(full_list)
	assert(full.count_text().begins_with("the last %d answers" % HistoryScript.CAP), full.count_text())
	assert(full.count_text().contains("older ones are not kept"), full.count_text())
	full.free()


func test_the_rows_are_written_once_and_not_once_a_frame() -> void:
	# The page is refreshed on a tick while it is open, so rewriting the list has to say whether it did
	# anything: a list rebuilt every frame is a list that fights the hand scrolling it.
	var page := _holding(["line added"])
	assert(not page.show_lines(), "nothing has changed, so nothing was written")
	assert(page.show_lines() == false, "and still nothing")
	page.history().note("shape added")
	assert(page.show_lines(), "a new answer is written")
	assert(page.line_count() == 2, "and the row is there")
	assert(not page.show_lines(), "and then it settles again")
	page.free()


func test_the_hint_is_the_guidance_and_the_status_is_what_the_page_did() -> void:
	var page := _holding(["line added"])
	assert(page.said() == "", "the page has not done anything yet")
	assert(page.status_text() == "", "so its status line says nothing")
	assert(page.hint() == "the top row is what the plan is saying now, and it changes as you work.",
		page.hint())
	page.say("read back from the drawing")
	assert(page.said() == "read back from the drawing", page.said())
	assert(page.status_text() == "read back from the drawing", page.status_text())
	assert(page.hint() == "the top row is what the plan is saying now, and it changes as you work.",
		"and the guidance did not move")
	page.free()


func test_what_the_page_says_when_it_is_opened_is_the_last_thing_the_drawing_said() -> void:
	var page := _holding(["line added", "1 entity erased"])
	assert(page.opening_words() == "the drawing last said: 1 entity erased", page.opening_words())
	page.free()
	var empty := _page()
	empty.set_history(HistoryScript.new())
	assert(empty.opening_words() == WindowScript.NOTHING_YET, empty.opening_words())
	empty.free()
	var none := _page()
	assert(none.opening_words() == WindowScript.NO_DRAWING, none.opening_words())
	none.free()


# --- putting it away ------------------------------------------------------------------


func test_closing_it_puts_it_away_and_says_so_once() -> void:
	var page := _holding(["line added"])
	var heard: Array[String] = []
	page.closed.connect(func() -> void: heard.append("closed"))
	page.request_close()
	assert(not page.visible, "the page is away")
	assert(heard.size() == 1, "and it said so once")
	page.free()


func test_the_close_button_and_the_windows_own_close_are_the_same_door() -> void:
	var page := _holding(["line added"])
	var heard: Array[String] = []
	page.closed.connect(func() -> void: heard.append("closed"))
	var close_button := page.get_node_or_null(^"Column/Buttons/CloseButton") as Button
	assert(close_button != null, "there is a Close button")
	close_button.pressed.emit()
	assert(heard.size() == 1, "the button closes the page")
	assert(not page.visible, "and puts it away")
	# The window's own close button, and Escape, both arrive as `close_requested`.
	page.close_requested.emit()
	assert(heard.size() == 2, "and so does the window's own close")
	assert(not page.visible, "with the page still away")
	page.free()