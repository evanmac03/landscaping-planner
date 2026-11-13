extends Node
## The reading size: the reader's own choice of how big the words are drawn, where the platform states none.
##
## Godot exposes no reading of Android's text-size setting - the screen queries are a size, a density and two
## scale factors, and none of them is a font scale - so the choice lives here. What is held down below: the
## answers and their factors, that none of them is smaller than the sizes this program states, the default
## for a word nobody offers, that a file nobody has written is the default rather than a fault, a choice
## surviving a round trip, and the one place the answer reaches a size at all.

const ReadingSizeScript := preload("res://scripts/reading_size.gd")
const PhoneHudScript := preload("res://scripts/phone_hud.gd")

## A file of this test's own, so the answer somebody has really chosen on this machine is never read or
## written by a test run.
const HERE := "user://reading-size-test.json"

const PHONE_DPI := 384.6
const PHONE_SCALE := 1.62


## The answer in hand, and the file, as they were found: a test that has used either says so afterwards.
func _clear() -> void:
	ReadingSizeScript.force_choice(ReadingSizeScript.DEFAULT)
	PhoneHudScript.use_reading_scale(0.0)
	if FileAccess.file_exists(HERE):
		DirAccess.remove_absolute(HERE)


## Every answer can be seen to make a difference, and none of them is smaller than the sizes the program
## states: every number in `PhoneHud` is a floor, and a reading size under one would be this program agreeing
## to be illegible rather than a person making it their own.
func test_every_answer_is_at_least_the_size_the_program_states() -> void:
	_clear()
	assert(ReadingSizeScript.CHOICES.size() >= 3, "there are answers to choose between")
	for choice: StringName in ReadingSizeScript.CHOICES:
		var factor: float = ReadingSizeScript.factor_for(choice)
		assert(factor >= 1.0, "%s is not smaller than the stated sizes: %s" % [String(choice), factor])
		assert(ReadingSizeScript.word(choice) != "", "%s has a word for a menu" % String(choice))
		assert(ReadingSizeScript.sentence(choice) != "", "and a sentence for a page")
	_clear()


## A word nobody offers is not a fourth answer: it is a program nobody has asked, which draws at the sizes
## the rest of the program states. The `String` case is the one a file needs, because a JSON round trip
## gives every value back as a `String` and never as the `StringName` an answer is written as.
func test_a_word_nobody_offers_is_the_default_and_a_string_is_taken() -> void:
	_clear()
	assert(
		ReadingSizeScript.choice_for(&"enormous") == ReadingSizeScript.DEFAULT,
		"an answer nobody offers is the default",
	)
	assert(ReadingSizeScript.choice_for(7) == ReadingSizeScript.DEFAULT, "and so is a number")
	assert(ReadingSizeScript.choice_for([]) == ReadingSizeScript.DEFAULT, "and a list")
	assert(
		ReadingSizeScript.choice_for(String(ReadingSizeScript.LARGE)) == ReadingSizeScript.LARGE,
		"while the answer a file writes back is read as itself",
	)
	_clear()


## Never having chosen and having chosen the default are the same answer, and a person who has chosen nothing
## is not told about a fault they did not cause.
func test_a_file_nobody_has_written_is_the_default_and_not_a_fault() -> void:
	_clear()
	assert(not FileAccess.file_exists(HERE), "nothing has been kept here")
	assert(ReadingSizeScript.stored(HERE) == ReadingSizeScript.DEFAULT, "so the answer is the default")
	_clear()


## A choice survives being kept and read back, through a temporary file and a rename.
func test_a_choice_survives_the_file() -> void:
	_clear()
	assert(ReadingSizeScript.choose(ReadingSizeScript.LARGEST, HERE), "the choice is kept")
	assert(ReadingSizeScript.stored(HERE) == ReadingSizeScript.LARGEST, "and read back as itself")
	assert(
		ReadingSizeScript.factor() == ReadingSizeScript.factor_for(ReadingSizeScript.LARGEST),
		"with the answer's own factor",
	)
	assert(
		ReadingSizeScript.load_kept(HERE) == ReadingSizeScript.LARGEST,
		"and the program reads it where it starts",
	)
	_clear()


## The sizes the program draws at are `PhoneHud`'s, and they are the sizes this program states until an
## answer is handed over - so nothing which asks about the size of a word reads a file.
##
## The words and the rows that hold them move **together**: a row is what a thumb hits, and growing only the
## words would leave them spilling out of the controls around them.
func test_a_reading_size_makes_the_words_and_their_rows_bigger_together() -> void:
	_clear()
	var words: int = PhoneHudScript.font_size(PHONE_SCALE, PHONE_DPI)
	var row: float = PhoneHudScript.row_height(PHONE_SCALE, PHONE_DPI)
	assert(words > 0 and row > 0.0, "the stated sizes are measured at all")
	PhoneHudScript.use_reading_scale(ReadingSizeScript.factor_for(ReadingSizeScript.LARGEST))
	assert(PhoneHudScript.font_size(PHONE_SCALE, PHONE_DPI) > words, "larger words")
	assert(PhoneHudScript.row_height(PHONE_SCALE, PHONE_DPI) > row, "and a row that can hold them")
	PhoneHudScript.use_reading_scale(0.5)
	assert(
		PhoneHudScript.font_size(PHONE_SCALE, PHONE_DPI) == words,
		"while a factor under one is refused, because these sizes are floors",
	)
	_clear()