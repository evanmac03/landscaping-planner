extends Node
## The window's own shape, and the guard that this program does not claim a fold it cannot see.
##
## The claim this file holds is mostly a **negative** one, and that negative is the whole content of
## "posture" here: a hinge is not readable through anything Godot exposes, so there is no answer that says
## "folded". The guard below fails if somebody adds one, which is the thing worth failing over.

const WindowPostureScript := preload("res://scripts/window_posture.gd")


## The two lengths and nothing else: a room that is as tall as it is wide stands, and one wider than it is
## tall lies along. The three rooms are this program's own devices, which is why they are the cases here.
func test_a_room_as_tall_as_it_is_wide_stands_and_a_wider_one_lies_along() -> void:
	assert(WindowPostureScript.of(Vector2i(1080, 2340)) == WindowPostureScript.STANDING, "a phone upright stands")
	assert(WindowPostureScript.of(Vector2i(1000, 1000)) == WindowPostureScript.STANDING, "so does a square window")
	assert(
		WindowPostureScript.of(Vector2i(2340, 1080)) == WindowPostureScript.LYING,
		"and the same phone on its side lies along",
	)
	assert(WindowPostureScript.of(Vector2i(2560, 1600)) == WindowPostureScript.LYING, "so does a tablet in landscape")
	assert(
		WindowPostureScript.of(Vector2i(1600, 2560)) == WindowPostureScript.STANDING,
		"and the same tablet standing up does not",
	)


## A room nobody could read has no shape, and that is **not** the same answer as lying along: a window of
## nought pixels is not a window whose far side is further away than its near one, and a report that read one
## as the other would be stating a shape it had not measured.
func test_a_room_nobody_could_read_has_no_shape() -> void:
	assert(WindowPostureScript.of(Vector2i.ZERO) == &"", "no window is no shape")
	assert(WindowPostureScript.of(Vector2i(-10, 400)) == &"", "and neither is a negative one")
	assert(
		WindowPostureScript.word(&"") != WindowPostureScript.word(WindowPostureScript.LYING),
		"and it does not read as lying along",
	)


## **The guard for the thing that cannot be known.** `DisplayServer` reports a screen's size, density, scale,
## orientation, usable rectangle and whether it has a touchscreen - and nothing about a fold: no hinge, no
## half-opened state, no posture. So an answer here saying "folded" would be a guess dressed as a reading, and
## what this file has is exactly the two shapes a window's own lengths can show.
func test_there_is_no_answer_that_claims_a_fold() -> void:
	assert(WindowPostureScript.SHAPES.size() == 2, "two shapes and no third: %s" % str(WindowPostureScript.SHAPES))
	for shape: StringName in WindowPostureScript.SHAPES:
		var words: String = WindowPostureScript.word(shape)
		assert(words != "", "%s reads as something" % shape)
		assert(
			not words.contains("fold") and not words.contains("hinge"),
			"%s is not worded as a fold: \"%s\"" % [shape, words],
		)
