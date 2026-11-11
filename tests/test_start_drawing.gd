extends Node
## The model behind the begin-a-drawing page (`res://scripts/start_drawing.gd`).
##
## What is held here is that the page offers exactly the four ways to begin a drawing, that each says what it
## is and what it does, and that a drawing with no recent list is answered in words rather than with a count
## of zero. What the *page* does with these is `test_start_drawing_window.gd`'s.

const StartScript := preload("res://scripts/start_drawing.gd")


## The four ways, in the order a person meets them: the empty sheet first, because that is where a drawing
## begins, then something already made - a file, a remembered drawing, and the example.
func test_it_offers_the_four_ways_to_begin_a_drawing() -> void:
	var ids: Array[StringName] = StartScript.ids()
	assert(
		ids == [StartScript.NEW, StartScript.OPEN, StartScript.RECENT, StartScript.EXAMPLE],
		"the four ways, in the order they are met: %s" % str(ids)
	)


## Every way says what it is called and what taking it does: a button with no words, or a way nobody can
## tell the effect of, is a fourth thing offered without being offered.
func test_every_way_says_what_it_is_and_what_it_does() -> void:
	for way: Dictionary in StartScript.WAYS:
		var label := String(way.get("label", ""))
		assert(not label.is_empty(), "a way with no words on its button")
		assert(
			not String(way.get("line", "")).is_empty(),
			"%s has nothing said about what it does" % label
		)


func test_a_way_is_found_by_the_id_its_button_answers_with() -> void:
	var found: Dictionary = StartScript.way(StartScript.OPEN)
	assert(found.get("id", &"") == StartScript.OPEN, "found by its id: %s" % str(found))


func test_a_way_that_is_not_offered_is_not_found() -> void:
	assert(StartScript.way(&"print the invoice").is_empty(), "nothing here is called that")


## A remembered drawing is offered by the name a person recognises it by, and carries the path it opens.
func test_the_recent_drawings_are_named_by_the_file_they_are() -> void:
	var rows: Array[Dictionary] = StartScript.recent_rows([
		"user://drawings/rose-bed.json",
		"user://drawings/front lawn.json",
	])
	assert(rows.size() == 2, "one row each: %d" % rows.size())
	assert(rows[0]["label"] == "rose-bed", "named without the folder or the extension: %s" % rows[0]["label"])
	assert(rows[0]["path"] == "user://drawings/rose-bed.json", "and carrying the path it opens")
	assert(rows[1]["label"] == "front lawn", "the second likewise: %s" % rows[1]["label"])


## With nothing remembered there is no row at all, and the case is answered in words rather than with a
## count of zero - which is the same refusal-not-a-zero rule every other page here keeps.
func test_there_being_nothing_recent_is_said_in_words_not_a_zero() -> void:
	assert(StartScript.recent_rows([]).is_empty(), "nothing remembered, nothing offered")
	assert(not StartScript.NOTHING_RECENT.is_empty(), "and there are words for it")
	assert(not StartScript.NOTHING_RECENT.contains("0"), "rather than a count of zero: %s" % StartScript.NOTHING_RECENT)