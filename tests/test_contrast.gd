extends Node

## The contrast ratio itself, the pairs that are refused rather than guessed at, and the sentence a reader
## gets.

const ContrastScript := preload("res://scripts/contrast.gd")


func test_white_on_black_is_the_widest_contrast_there_is() -> void:
	assert(
		is_equal_approx(ContrastScript.ratio(Color.WHITE, Color.BLACK), 21.0),
		"the standard's own ceiling is 21 to 1",
	)


func test_a_colour_on_itself_has_no_contrast_at_all() -> void:
	assert(is_equal_approx(ContrastScript.ratio(Color(0.4, 0.6, 0.2), Color(0.4, 0.6, 0.2)), 1.0))


func test_the_ratio_is_the_same_whichever_colour_is_the_ink() -> void:
	var one := ContrastScript.ratio(Color.BLACK, Color.WHITE)
	var other := ContrastScript.ratio(Color.WHITE, Color.BLACK)
	assert(is_equal_approx(one, other), "which of the two is written on the other does not matter")


func test_the_grey_that_just_passes_on_white_is_the_one_the_standard_names() -> void:
	var passes := ContrastScript.ratio(Color.html("767676"), Color.WHITE)
	var fails := ContrastScript.ratio(Color.html("777777"), Color.WHITE)
	assert(passes >= ContrastScript.LEAST, "767676 is the darkest grey still readable on white")
	assert(fails < ContrastScript.LEAST, "and one step lighter is not")


func test_a_caption_that_cannot_be_read_is_named_with_both_its_colours() -> void:
	var found := ContrastScript.faults(
		[{ "name": "the status line", "ink": Color.html("3a3a3a"), "paper": Color.html("404040") }]
	)
	assert(found.size() == 1, "one pair that cannot be read")
	assert(
		ContrastScript.sentence(found[0])
		== "the status line is #3a3a3a on #404040, a ratio of 1.10 where 4.5 is wanted",
		ContrastScript.sentence(found[0]),
	)


func test_a_pair_at_the_least_is_left_alone() -> void:
	assert(ContrastScript.faults([{ "name": "the menu", "ink": Color.html("767676"), "paper": Color.WHITE }]).is_empty(), "readable is readable, however narrowly")


func test_a_pair_that_is_not_two_colours_is_left_out() -> void:
	var found := ContrastScript.faults(
		[{ "name": "a caption with no ink" }, { "name": "a caption with no paper", "ink": Color.BLACK }]
	)
	assert(found.is_empty(), "nothing is invented about a pair that was not fully stated")


func test_a_see_through_ink_is_left_out() -> void:
	var found := ContrastScript.faults(
		[{ "name": "a caption over the plan", "ink": Color(1, 1, 1, 0.5), "paper": Color.BLACK }]
	)
	assert(found.is_empty(), "its real paper is the one it gets composited against, which is the glass's business")


func test_the_hardest_pair_to_read_is_the_one_named_first() -> void:
	var found := ContrastScript.faults(
		[
			{ "name": "the second worst", "ink": Color.html("505050"), "paper": Color.html("606060") },
			{ "name": "the worst", "ink": Color.html("3c3c3c"), "paper": Color.html("404040") },
		]
	)
	var worst: Dictionary = ContrastScript.worst(found)
	assert(worst["name"] == "the worst", "a reader wants the one at the bottom of the list")


func test_a_heading_may_have_less_contrast_than_a_body_of_text() -> void:
	# A grey that is too faint for a sentence and quite enough for a large title.
	var heading := Color.html("949494")
	assert(ContrastScript.faults([{ "name": "a title", "ink": heading, "paper": Color.WHITE }]).size() == 1, "too faint for body text")
	assert(ContrastScript.faults([{ "name": "a title", "ink": heading, "paper": Color.WHITE }], ContrastScript.LEAST_LARGE).is_empty(), "and enough for a heading")
