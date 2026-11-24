extends Node

## Two readings of the screen's words: what moved, what appeared, what went, and what held still while the rest
## of the page moved - which is where a stale caption hides.

const CaptionLedgerScript := preload("res://scripts/caption_ledger.gd")


func test_nothing_moved_when_the_same_words_come_back() -> void:
	var one := { "ToolLabel": "Line (1)", "FootLabel": "Specify the first point" }
	var changes: Dictionary = CaptionLedgerScript.changes(one, one.duplicate())
	assert((changes["moved"] as Array).is_empty(), "nothing moved")
	assert((changes["held"] as Array).size() == 2, "and both captions held still")


func test_a_caption_whose_words_changed_has_moved() -> void:
	var changes: Dictionary = CaptionLedgerScript.changes({ "ToolLabel": "Line (1)" }, { "ToolLabel": "Circle (4)" })
	var moved: Array = changes["moved"]
	assert(moved.size() == 1, "one caption moved")
	assert(moved[0]["path"] == "ToolLabel", "named by where it stands")
	assert(moved[0]["was"] == "Line (1)" and moved[0]["now"] == "Circle (4)", "with both things it said")


func test_a_caption_that_was_not_there_before_has_appeared() -> void:
	var changes: Dictionary = CaptionLedgerScript.changes({ }, { "BoxLabel": "Line (1)" })
	assert((changes["appeared"] as Array) == ["BoxLabel"], "a page opened a box that was not there")
	assert((changes["moved"] as Array).is_empty(), "and nothing moved, because nothing was there to move")


func test_a_caption_that_is_gone_has_vanished() -> void:
	var changes: Dictionary = CaptionLedgerScript.changes({ "BoxLabel": "Line (1)" }, { })
	assert((changes["vanished"] as Array) == ["BoxLabel"], "the box was put away")


func test_a_caption_that_held_still_while_the_rest_of_the_page_moved_is_listed_as_holding() -> void:
	var before := { "ToolLabel": "Line (1)", "BoxLabel": "Line (1) - a straight segment", "FootLabel": "" }
	var after := {
		"ToolLabel": "Circle (4)",
		"BoxLabel": "Line (1) - a straight segment",
		"FootLabel": "Centre (x, y)",
	}
	var changes: Dictionary = CaptionLedgerScript.changes(before, after)
	assert((changes["held"] as Array) == ["BoxLabel"], "the box is the suspect, and the reader is handed it")


func test_the_box_beside_the_plan_is_caught_by_a_caption_that_held() -> void:
	# The defect this instrument was built for: the tool changes, the box does not.
	var before := { "the box": "Line (1)", "the foot line": "Specify the first point" }
	var after := { "the box": "Line (1)", "the foot line": "Centre (x, y)" }
	var changes: Dictionary = CaptionLedgerScript.changes(before, after)
	assert((changes["held"] as Array) == ["the box"], "a caption that should have followed and did not")
	assert((changes["moved"] as Array).size() == 1, "while the caption that did follow is named too")


func test_a_moved_caption_reads_as_what_it_said_and_what_it_says_now() -> void:
	var changes: Dictionary = CaptionLedgerScript.changes({ "ToolLabel": "Line (1)" }, { "ToolLabel": "Circle (4)" })
	assert(
		CaptionLedgerScript.sentence(changes["moved"][0]) == "ToolLabel  \"Line (1)\"  ->  \"Circle (4)\"",
		CaptionLedgerScript.sentence(changes["moved"][0]),
	)


func test_the_summary_counts_every_kind_of_change() -> void:
	var before := { "one": "a", "two": "b", "three": "c" }
	var after := { "one": "a", "two": "B", "four": "d" }
	var changes: Dictionary = CaptionLedgerScript.changes(before, after)
	assert(
		CaptionLedgerScript.summary(changes) == "1 caption(s) moved, 1 appeared, 1 gone, 1 held still",
		CaptionLedgerScript.summary(changes),
	)
