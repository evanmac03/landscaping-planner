extends Node

## Words against the box they were given: the width the caller measured, the few pixels a font rounds away, and
## the caption the phone's own screen showed with a word cut off.

const ClippedWordsScript := preload("res://scripts/clipped_words.gd")


func test_words_that_fit_are_left_alone() -> void:
	var item := { "name": "the foot line", "said": "Pinch: zoom", "wanted": 300.0, "given": 320.0 }
	assert(ClippedWordsScript.fits(item), "the box is wider than the words")
	assert(ClippedWordsScript.faults([item]).is_empty(), "and there is nothing to say about it")


func test_a_caption_the_phone_showed_cut_mid_word_is_named() -> void:
	# Measured on the phone: the board's foot line is given a box 231 px narrower than the words in it, and the
	# glass showed "Pinch: zoo". The walk that measures a control against the room only knew the *box* was past
	# an edge, which is a different fault with a different cure.
	var item := { "name": "the board  HintsLabel", "said": "Left-drag: move a plant", "wanted": 754.0, "given": 523.0 }
	var found := ClippedWordsScript.faults([item])
	assert(found.size() == 1, "the words want more room than they were given")
	assert(found[0]["short"] == 231, "by 231 px: %d" % found[0]["short"])
	assert(
		ClippedWordsScript.sentence(found[0]).contains("231 px of its words are not shown"),
		ClippedWordsScript.sentence(found[0]),
	)


func test_a_caption_inside_the_rounding_of_a_font_is_not_a_fault() -> void:
	# Every font rounds, and a box two pixels narrower than the measured width of its words is not a caption
	# anybody can see anything wrong with.
	assert(ClippedWordsScript.fits({ "wanted": 402.0, "given": 400.0 }), "two pixels is a rounding difference")
	assert(not ClippedWordsScript.fits({ "wanted": 408.0, "given": 400.0 }), "eight pixels is a cut word")
	assert(ClippedWordsScript.faults([{ "wanted": 402.0, "given": 400.0 }]).is_empty(), "and only one is named")


func test_the_floor_can_be_lowered_by_the_caller() -> void:
	# The one word the difference is decided by is a judgement, so it is the caller's to make, exactly as the
	# finger's floor is in `TouchTarget`.
	var item := { "wanted": 405.0, "given": 400.0 }
	assert(ClippedWordsScript.faults([item]).is_empty(), "five px is under the default floor")
	assert(ClippedWordsScript.faults([item], 1).size() == 1, "and over a floor the caller lowered")


func test_words_that_are_given_more_room_than_they_need_are_never_named() -> void:
	var found := ClippedWordsScript.faults(
		[
			{ "name": "roomy", "said": "Fit", "wanted": 40.0, "given": 400.0 },
			{ "name": "tight", "said": "Ground view (G)", "wanted": 300.0, "given": 90.0 },
		]
	)
	assert(found.size() == 1, "only the tight one")
	assert(found[0]["name"] == "tight", "and it is the one whose words do not fit")


func test_a_caption_with_no_words_at_all_is_not_named() -> void:
	# An empty box is not a box with something cut out of it: there are no words to lose.
	assert(ClippedWordsScript.faults([{ "name": "an empty label", "said": "", "wanted": 0.0, "given": 12.0 }]).is_empty())


func test_the_caption_losing_most_is_the_one_named_first() -> void:
	var found := ClippedWordsScript.faults(
		[
			{ "name": "a little cut", "wanted": 210.0, "given": 200.0 },
			{ "name": "mostly gone", "wanted": 400.0, "given": 200.0 },
		]
	)
	assert(found.size() == 2)
	assert(ClippedWordsScript.worst(found)["name"] == "mostly gone", "200 px of it is not shown")


func test_an_item_that_never_said_what_it_needs_is_skipped() -> void:
	assert(ClippedWordsScript.faults([{ "name": "no measurement" }]).is_empty(), "nothing was measured")
	assert(ClippedWordsScript.shortfall({ "given": 100.0 }) == 0, "and nothing wanted is nothing lost")
