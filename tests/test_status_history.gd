extends Node
## What the drawing has said, kept.
##
## The status line under the plan is one line, and the next thing written over it is gone. The history
## is the same answers kept, and this checks the three rules that make it a history rather than a cache:
## **the newest is at the front**, **the same words said twice are two answers** (erasing a shape twice
## says "1 entity erased" twice, and quietly dropping the second would be wrong about what happened),
## and **an empty message is not an answer at all** (the line is cleared when a tool is put away).
##
## The last two tests are the join: the drawing feeds it through the one setter every message passes
## through, and a drawing that is replaced does not inherit the last one's answers.

const HistoryScript := preload("res://scripts/draft/status_history.gd")
const ControllerScript := preload("res://scripts/draft/draft_controller.gd")
const DocumentScript := preload("res://scripts/draft/draft_document.gd")


# --- the list itself ------------------------------------------------------------------


func test_a_history_nobody_has_told_anything_says_nothing() -> void:
	var history: StatusHistory = HistoryScript.new()
	assert(history.is_empty(), "nothing has been said")
	assert(history.count() == 0, "so there is nothing in it")
	assert(history.latest() == "", "and no last thing")
	assert(history.oldest() == "", "and no first thing")
	assert(history.lines().is_empty(), "and no rows")


func test_the_newest_answer_is_at_the_front() -> void:
	var history: StatusHistory = HistoryScript.new()
	assert(history.note("line added"), "a message is kept")
	assert(history.note("1 entity erased"), "and the next one too")
	assert(history.latest() == "1 entity erased", "the newest is what was said last")
	assert(history.oldest() == "line added", "and the first thing said is still there")
	var wanted: Array[String] = ["1 entity erased", "line added"]
	assert(history.lines() == wanted, "newest first, as the page lists them")


func test_the_same_words_twice_are_two_answers() -> void:
	var history: StatusHistory = HistoryScript.new()
	history.note("1 entity erased")
	history.note("1 entity erased")
	assert(history.count() == 2, "the same sentence is two answers, because it was two acts")
	var wanted: Array[String] = ["1 entity erased", "1 entity erased"]
	assert(history.lines() == wanted, "and both are kept, in the order they were said")


func test_nothing_said_is_not_an_answer() -> void:
	var history: StatusHistory = HistoryScript.new()
	assert(not history.note(""), "the cleared line is not an answer")
	assert(not history.note("   "), "nor is whitespace")
	assert(not history.note("\n\t"), "nor is a line break")
	assert(history.is_empty(), "so nothing was kept")
	assert(history.note("erased"), "a real message still is")
	assert(history.count() == 1, "and only it")


func test_only_the_newest_are_kept_and_the_rest_fall_off_the_end() -> void:
	var history: StatusHistory = HistoryScript.new()
	for index in HistoryScript.CAP + 5:
		history.note("answer %d" % index)
	assert(history.count() == HistoryScript.CAP, "the list is capped")
	assert(history.latest() == "answer %d" % (HistoryScript.CAP + 4), "the newest is still at the front")
	assert(history.oldest() == "answer 5", "and the oldest kept is the one that just fitted")
	assert(not history.lines().has("answer 4"), "while the ones before it are gone")


func test_the_rows_it_hands_out_are_a_copy() -> void:
	var history: StatusHistory = HistoryScript.new()
	history.note("line added")
	var rows: Array[String] = history.lines()
	rows.append("something nobody said")
	assert(history.count() == 1, "the history is the only thing that decides what is in it")


func test_forgetting_leaves_nothing_behind() -> void:
	var history: StatusHistory = HistoryScript.new()
	history.note("line added")
	history.clear()
	assert(history.is_empty(), "nothing is left")
	assert(history.latest() == "", "and it does not remember the last thing")
	assert(history.note("shape added"), "and the next answer is kept")
	var wanted: Array[String] = ["shape added"]
	assert(history.lines() == wanted, "as the only one")


# --- the drawing that says it ---------------------------------------------------------


## A controller with a document under it and nothing else: `new_drawing` and the file doors all reach
## for a scene, so the binding is done the way `open_drawing` does it.
func _drawing() -> DraftController:
	var controller: DraftController = ControllerScript.new()
	controller._bind_document(DocumentScript.new())
	return controller


func test_the_drawing_keeps_what_it_says() -> void:
	var controller := _drawing()
	controller.last_message = "line added"
	controller.last_message = "1 entity erased"
	var wanted: Array[String] = ["1 entity erased", "line added"]
	assert(controller.said.lines() == wanted, str(controller.said.lines()))
	controller.free()


func test_a_message_set_twice_is_two_answers() -> void:
	# The number is bumped by the setter, so there is nothing to compare and nothing to miss: two acts
	# that happen to read the same are two entries.
	var controller := _drawing()
	controller.last_message = "1 entity erased"
	controller.last_message = "1 entity erased"
	assert(controller.said.count() == 2, str(controller.said.count()))
	controller.free()


func test_a_tool_put_away_says_nothing_rather_than_an_empty_answer() -> void:
	var controller := _drawing()
	controller.last_message = "line added"
	controller.last_message = ""
	assert(controller.said.count() == 1, "the cleared line was not kept")
	assert(controller.said.latest() == "line added", "so the last real answer is still the last one")
	controller.free()


func test_a_drawing_that_is_replaced_does_not_inherit_what_the_last_one_said() -> void:
	var controller := _drawing()
	controller.last_message = "line added"
	controller._bind_document(DocumentScript.new())
	assert(controller.said.is_empty(), "the answers belonged to the drawing that is gone")
	controller.last_message = "shape added"
	var wanted: Array[String] = ["shape added"]
	assert(controller.said.lines() == wanted, "and this one starts its own")
	controller.free()