extends Node
## Tests for the revision window: what it lists, what it says about a revision, and the two acts it
## announces.
##
## Built with `RevisionWindow.new()` and never added to a tree, as the sheet window and the hatch panel
## are: the window owns no drawing, so there is nothing to hold down with it. `build()` is idempotent and
## callable off-tree, and the acts are the same methods the controls call.

const WindowScript := preload("res://scripts/revision_window.gd")


func _rows() -> Array[Dictionary]:
	return [
		{
			"index": 0,
			"message": "sent to the client",
			"author": "evan",
			"when": "2026-10-20 18:40:31",
			"shapes": 12,
			"description": "rev 1  sent to the client  (evan, 2026-10-20 18:40:31)  12 shapes",
			"change": "",
		},
		{
			"index": 1,
			"message": "client asked for more lawn",
			"author": "evan",
			"when": "2026-10-22 09:02:10",
			"shapes": 15,
			"description": "rev 2  client asked for more lawn  (evan, 2026-10-22 09:02:10)  15 shapes",
			"change": "3 added  (added: #13, #14, #15)",
		},
	]


func _window():
	var window = WindowScript.new()
	window.build()
	window.set_identity("Russian sage", 0)
	window.set_revisions(_rows())
	return window


# --- what it lists --------------------------------------------------------------------


func test_the_rows_the_controller_describes_are_the_rows_listed() -> void:
	var window = _window()
	assert(window.row_count() == 2)
	# The list answers "which one": who made it, when and how big are in the pane beside it.
	assert(window.list_texts() == [
		"rev 1  sent to the client",
		"rev 2  client asked for more lawn",
	], str(window.list_texts()))
	assert(window.selected_index() == 0, "the oldest is where a history starts reading")
	assert(window.description_text() ==
		"rev 1  sent to the client  (evan, 2026-10-20 18:40:31)  12 shapes", window.description_text())
	window.free()


func test_the_selected_revision_says_what_it_changed() -> void:
	var window = _window()
	# The first revision has nothing before it, so there is no change to report - which is not the same
	# as reporting that nothing changed.
	assert(window.selected_row()["message"] == "sent to the client")
	assert(window.change_text() == "", "nothing before the first revision")
	assert(window.select(1))
	assert(window.change_text() == "3 added  (added: #13, #14, #15)", window.change_text())
	assert(window.description_text().begins_with("rev 2"))
	window.free()


func test_a_window_with_no_history_says_so_rather_than_failing() -> void:
	var window = WindowScript.new()
	window.build()
	window.set_revisions([])
	assert(window.row_count() == 0)
	assert(window.list_texts().is_empty())
	assert(window.selected_row().is_empty())
	assert(window.change_text() == "")
	assert(window.status_text() == "nothing has been recorded against this drawing yet",
		window.status_text())
	assert(not window.select(0), "there is no row to select")
	assert(not window.restore(), "and nothing a restore could be about")
	window.free()


func test_the_life_of_a_history_is_counted_and_the_dropped_ones_are_admitted() -> void:
	var window = _window()
	assert(window.status_text() == "2 revisions kept", window.status_text())
	assert(window.identity()["drawing"] == "Russian sage")
	# "These are all the revisions" and "these are the last of them" are different claims, and only one
	# of them is true once the log has let some go.
	window.set_identity("Russian sage", 3)
	assert(window.status_text() == "2 revisions kept, and 3 older ones let go", window.status_text())
	# A single revision is one revision, not one revisions.
	window.set_revisions([_rows()[0]])
	assert(window.status_text() == "1 revision kept, and 3 older ones let go", window.status_text())
	window.free()


func test_a_line_said_outranks_the_count() -> void:
	var window = _window()
	assert(not window.said().is_empty() == false)
	window.say("restored rev 1  sent to the client  (evan, 2026-10-20 18:40:31)  12 shapes")
	assert(window.status_text().begins_with("restored rev 1"), window.status_text())
	assert(window.said().begins_with("restored rev 1"))
	window.say("")
	assert(window.status_text() == "2 revisions kept")
	window.free()


# --- what a person did ----------------------------------------------------------------


func test_recording_announces_the_message_and_empties_the_box() -> void:
	var window = _window()
	var heard: Array[String] = []
	window.revision_recorded.connect(func(message: String) -> void: heard.append(message))
	assert(window.type_message("client asked for more lawn"))
	assert(window.message_text() == "client asked for more lawn")
	assert(window.record())
	assert(heard == ["client asked for more lawn"], str(heard))
	# The next revision is a new message: a box still holding the last one is a lie about the next.
	assert(window.message_text() == "")
	window.free()


func test_a_revision_can_be_recorded_with_no_message_at_all() -> void:
	var window = _window()
	var heard: Array[String] = []
	window.revision_recorded.connect(func(message: String) -> void: heard.append(message))
	assert(window.type_message(""))
	assert(window.record())
	assert(heard == [""], str(heard))
	# The log has a word for it; refusing here would make a checkpoint something a person cannot take.
	assert(true)
	window.free()


func test_restoring_announces_the_revision_that_was_picked() -> void:
	var window = _window()
	var heard: Array[int] = []
	window.restore_requested.connect(func(index: int) -> void: heard.append(index))
	assert(window.restore())
	assert(heard == [0], str(heard))
	assert(window.select(1))
	assert(window.restore())
	assert(heard == [0, 1], str(heard))
	window.free()


func test_the_selection_survives_the_rows_being_replaced() -> void:
	var window = _window()
	assert(window.select(1))
	# Recording a revision re-lists the history; the person reading revision 2 stays on it.
	window.set_revisions(_rows())
	assert(window.selected_index() == 1, "the selection stays where it was")
	# And when the row is gone - the log let it go - the selection lands on a row that exists.
	window.set_revisions([_rows()[1]])
	assert(window.selected_index() == 0)
	assert(window.selected_row()["message"] == "client asked for more lawn")
	window.free()