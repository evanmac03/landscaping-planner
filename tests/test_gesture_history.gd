extends Node
## Tests for the gesture history: the labels that make undo readable, and the serial that a named
## revision is counted from.
##
## The states here are dictionaries rather than drawings, on purpose: the history deals in opaque
## snapshots and knows nothing about a document, so what there is to test is the bookkeeping around
## them - what a gesture is called, and how many of them there have been.
##
## The one rule that is not bookkeeping is the serial. It is the number a revision is taken at, so a
## history that reset it when the oldest gesture fell off the end would tell a revision that gestures
## had *un*happened - and nothing else in the project would notice.

const History := preload("res://scripts/draft/gesture_history.gd")


func test_a_new_history_can_undo_nothing() -> void:
	var history := History.new()
	assert(not history.can_undo())
	assert(not history.can_redo())
	assert(history.depth() == 0 and history.redo_depth() == 0)
	assert(history.undo({}).is_empty())
	assert(history.redo({}).is_empty())
	assert(history.undo_label() == "", "and there is no gesture to name")
	assert(history.redo_label() == "")
	assert(history.serial() == 0, "a drawing nothing has happened to has been through nothing")
	assert(history.labels().is_empty())


func test_every_gesture_is_numbered_from_one() -> void:
	var history := History.new()
	assert(history.push({"value": 1}, "drawing a new line") == 1)
	assert(history.push({"value": 2}, "trimming") == 2)
	assert(history.push({"value": 3}, "erasing") == 3)
	assert(history.serial() == 3)
	assert(history.depth() == 3)


func test_an_act_nobody_labelled_is_called_an_edit() -> void:
	var history := History.new()
	history.push({"value": 1})
	assert(history.undo_label() == History.UNNAMED)
	assert(History.UNNAMED == "an edit", "and that is what the buttons say: %s" % History.UNNAMED)


func test_a_label_is_trimmed_and_a_blank_one_is_not_a_label() -> void:
	var history := History.new()
	history.push({"value": 1}, "   trimming   ")
	assert(history.undo_label() == "trimming")
	history.push({"value": 2}, "   ")
	assert(history.undo_label() == History.UNNAMED, "a blank label is no label")


func test_the_label_of_the_gesture_undo_would_undo_is_the_one_it_was_given() -> void:
	var history := History.new()
	history.push({"value": 1}, "first")
	history.push({"value": 2}, "second")
	assert(history.undo_label() == "second", "the last thing done")
	history.undo({"value": 3})
	assert(history.undo_label() == "first", "and after that, the one before it")
	assert(history.redo_label() == "second")


func test_an_undone_gesture_keeps_its_name_for_the_redo() -> void:
	var history := History.new()
	history.push({"value": 1}, "erasing")
	history.undo({"value": 2})
	assert(history.redo_label() == "erasing", "redoing it is that gesture happening again")
	assert(history.undo_label() == "", "and there is nothing left to undo")


func test_the_states_handed_back_are_the_states_that_went_in() -> void:
	var history := History.new()
	history.push({"value": 1}, "first")
	history.push({"value": 2}, "second")
	var undone: Dictionary = history.undo({"value": 3})
	assert(int(undone["value"]) == 2, "undo hands back the state before the last gesture")
	var redone: Dictionary = history.redo({"value": 1})
	assert(int(redone["value"]) == 3, "and redo hands back the one it was undone from")


func test_trimming_the_oldest_gestures_does_not_reset_the_serial() -> void:
	var history := History.new()
	history.limit = 2
	for index in 5:
		history.push({"value": index}, "gesture %d" % index)
	assert(history.depth() == 2, "the stack is still capped")
	assert(history.serial() == 5, "but the drawing has been through five gestures: %d" % history.serial())
	assert(", ".join(history.labels()) == "gesture 3, gesture 4", "the oldest are the ones forgotten")


func test_clearing_the_history_forgets_the_gestures_but_not_the_serial() -> void:
	var history := History.new()
	history.push({"value": 1}, "drawing a new line")
	history.push({"value": 2}, "erasing")
	history.clear()
	assert(not history.can_undo() and not history.can_redo())
	assert(history.undo_label() == "")
	assert(history.serial() == 2, "what happened to the drawing does not unhappen because it was forgotten")


func test_the_gestures_that_can_be_undone_read_oldest_first() -> void:
	var history := History.new()
	history.push({}, "drawing a new line")
	history.push({}, "trimming")
	history.push({}, "erasing")
	assert(", ".join(history.labels()) == "drawing a new line, trimming, erasing")
	history.undo({})
	assert(", ".join(history.labels()) == "drawing a new line, trimming", "and what is undone comes off the end")


func test_a_new_gesture_clears_what_could_be_redone() -> void:
	var history := History.new()
	history.push({}, "first")
	history.undo({})
	assert(history.can_redo())
	history.push({}, "something else")
	assert(not history.can_redo(), "the branch that was undone is gone")
	assert(history.redo_label() == "")