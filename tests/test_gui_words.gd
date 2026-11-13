extends Node

## The rules about the words a GUI is made of: the faults that no rectangle can show - a note to the author, a
## message a compiler would write, a sentence where a name belongs, a space that pads the box.
##
## Every string here is written by hand rather than read off a control, because the rules are about words and a
## test that had to bring up a scene to state a sentence would be testing the scene. The one control built is
## for `kind_of`, and it is freed at the end of that test.

const GuiWordsScript := preload("res://scripts/gui_words.gd")

const WHERE := "the palette"


## The faults in one string, for a line of a one-line control unless a test says otherwise.
func _faults(said: String, kind: StringName = GuiWordsScript.ONE_LINE) -> Array[Dictionary]:
	return GuiWordsScript.faults(said, kind, WHERE)


func test_a_space_at_the_end_of_a_caption_is_a_fault() -> void:
	var found: Array[Dictionary] = _faults("Drawing (0) ")
	assert(found.size() == 1, "a padded caption is one fault")
	assert(String(found[0]["why"]).contains("end"), "and the end is the end the fault is on")


func test_a_clean_sentence_is_left_alone() -> void:
	assert(_faults("Design the garden").is_empty(), "plain words a person reads are not a fault")
	assert(
		_faults("The window state a report is read for", GuiWordsScript.PROSE).is_empty(),
		"and neither is a sentence on something that lays sentences out",
	)


func test_two_spaces_together_are_a_fault() -> void:
	assert(_faults("A drawing  saved").size() == 1, "a double space is a typing accident")


func test_three_spaces_are_a_gap_the_author_meant() -> void:
	assert(
		_faults("Left-drag: move a plant     Right-drag: pan", GuiWordsScript.PROSE).is_empty(),
		"the line at the foot of the screen sets its groups apart with five spaces",
	)


func test_two_spaces_before_a_key_hint_are_the_alignment_the_menus_use() -> void:
	assert(_faults("Library...  (L)").is_empty(), "the menus line a key hint up with two spaces on purpose")


func test_two_spaces_after_a_colon_set_a_reading_apart() -> void:
	assert(
		_faults("one row per item, with what is waiting on it:  nothing", GuiWordsScript.PROSE).is_empty(),
		"a colon and two spaces is how the program puts a reading beside its label",
	)
	assert(
		_faults("A drawing saved.  The plants are next", GuiWordsScript.PROSE).is_empty(),
		"and so is two spaces after a full stop",
	)


func test_a_broken_line_in_a_menu_entry_cannot_be_drawn_on_one_row() -> void:
	assert(_faults("Save\nthe file", GuiWordsScript.ONE_ROW).size() == 1, "one row cannot draw two")
	assert(
		_faults("Save\nthe file", GuiWordsScript.PROSE).is_empty(),
		"and a caption that lays lines out is where a broken line belongs",
	)
	assert(
		_faults("Line\n1").is_empty(),
		"a button draws the tool over the key that takes it, which is what the palette is built out of",
	)


func test_a_note_to_the_author_left_in_the_words_is_a_fault() -> void:
	var bare: Array[Dictionary] = _faults("TODO", GuiWordsScript.PROSE)
	assert(bare.size() == 1, "a note left where words belong is one fault")
	assert(String(bare[0]["why"]).contains("todo"), "and the note is named in the words of the fault")
	var inside: Array[Dictionary] = _faults("a todo remains", GuiWordsScript.PROSE)
	assert(inside.size() == 1, "and a note in the middle of a sentence is found too")


func test_a_word_that_is_part_of_another_word_is_not_a_note() -> void:
	assert(_faults("TODOSomething", GuiWordsScript.PROSE).is_empty(), "a name is not a note")


func test_a_word_that_says_nothing_a_person_can_use_is_a_fault() -> void:
	assert(_faults("None", GuiWordsScript.PROSE).size() == 1, "a figure that came back hollow is not words")
	assert(
		_faults("None of the figures could be read", GuiWordsScript.PROSE).is_empty(),
		"while a sentence that begins with the same word is words",
	)


func test_a_message_that_could_have_been_written_by_a_compiler_is_a_fault() -> void:
	var found: Array[Dictionary] = _faults("Error: invalid input", GuiWordsScript.PROSE)
	assert(found.size() == 1, "the message the project forbids is one fault, not one per word in it")
	assert(String(found[0]["why"]).contains("error"), "and it names the word that gives it away")


func test_a_sentence_in_a_button_is_a_fault_and_a_name_is_not() -> void:
	assert(_faults("Go").is_empty(), "a name for a thing to press fits on one line")
	var long_one: String = "State the working day the hours were worked and read the figures again"
	assert(_faults(long_one).size() == 1, "a sentence where a name belongs sets the width of the whole row")
	assert(
		_faults(long_one, GuiWordsScript.PROSE).is_empty(),
		"and the same words are fine on something that lays words out",
	)


func test_capitals_are_left_to_the_author() -> void:
	assert(
		_faults("No tax    NONE", GuiWordsScript.PROSE).is_empty(),
		"a tax code in capitals is not a shout, and telling one from the other is not a rule",
	)


func test_a_reading_in_capitals_is_left_alone() -> void:
	assert(
		_faults("3D OVERHEAD", GuiWordsScript.PROSE).is_empty(),
		"a name for a mode has no lower case in it and is not a sentence",
	)


func test_punctuation_written_twice_is_a_fault_and_an_ellipsis_is_not() -> void:
	assert(_faults("Done!!", GuiWordsScript.PROSE).size() == 1, "punctuation written twice is a fault")
	assert(
		_faults("Library...", GuiWordsScript.PROSE).is_empty(),
		"while the three dots the program uses to mean more to come are its own idiom",
	)


func test_a_fault_reads_as_where_it_stands_and_what_is_wrong_with_it() -> void:
	var found: Array[Dictionary] = _faults("Drawing (0) ")
	assert(
		GuiWordsScript.sentence(found[0]) == "%s  \"Drawing (0)\"  -  %s" % [WHERE, found[0]["why"]],
		"one row a person can read: where it stands, the words, and why",
	)


func test_the_kind_of_words_a_control_carries_comes_from_the_control() -> void:
	var button := Button.new()
	var caption := Label.new()
	var field := LineEdit.new()
	var list := ItemList.new()
	assert(GuiWordsScript.kind_of(button) == GuiWordsScript.ONE_LINE, "a button's width is its words")
	assert(GuiWordsScript.kind_of(caption) == GuiWordsScript.PROSE, "a caption lays its words out")
	assert(GuiWordsScript.kind_of(field) == GuiWordsScript.ONE_ROW, "a field draws the one row a person types")
	assert(GuiWordsScript.kind_of(list) == GuiWordsScript.OTHER, "a list holds rows rather than a sentence")
	button.free()
	caption.free()
	field.free()
	list.free()
