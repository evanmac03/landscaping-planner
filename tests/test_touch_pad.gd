extends Node
## The thumb controls a phone walks and looks with, and the numbers behind them.
##
## The control itself is proved live, by `tools/touch_walk_demo.gd`, because a Control's own input arrives
## through a viewport and cannot be pushed through the test runner. What is here is the part with an answer
## that can be wrong: where a thumb's offset points, how it composes with the keys, and which way a drag
## turns the head.

const HudScript := preload("res://scripts/hud.gd")
const TouchPadScript := preload("res://scripts/touch_pad.gd")
const MoveInputScript := preload("res://scripts/move_input.gd")
const PlayerScript := preload("res://scripts/player.gd")

## The reach and dead zone the arithmetic below is stated in - the same three numbers the pad uses.
const REACH := 90.0
const DEAD_ZONE := 0.12


# --- where a thumb points ----------------------------------------------------------------


## A thumb dragged up walks forward and right walks right. The stick answers in the movement keys' own
## convention - x is right minus left, y is back minus forward - and a screen's y grows downwards, so "up"
## has to arrive as a negative number.
func test_a_thumb_dragged_up_walks_forward_and_right_walks_right() -> void:
	var up: Vector2 = TouchPadScript.drag_stick(Vector2(0.0, -REACH), REACH, DEAD_ZONE)
	assert(is_equal_approx(up.y, -1.0), "up is forward, which is negative: %s" % str(up))
	assert(is_equal_approx(up.x, 0.0))
	var right: Vector2 = TouchPadScript.drag_stick(Vector2(REACH, 0.0), REACH, DEAD_ZONE)
	assert(is_equal_approx(right.x, 1.0), "right is positive: %s" % str(right))


## A thumb that has barely moved asks for nothing, because a finger held still on glass is never quite
## still - without the dead zone the walk creeps whenever the thumb rests.
func test_a_thumb_inside_the_dead_zone_asks_for_nothing() -> void:
	var resting: Vector2 = TouchPadScript.drag_stick(Vector2(4.0, -3.0), REACH, DEAD_ZONE)
	assert(resting == Vector2.ZERO, "inside the dead zone: %s" % str(resting))
	var walking: Vector2 = TouchPadScript.drag_stick(Vector2(0.0, -REACH * 0.2), REACH, DEAD_ZONE)
	assert(walking != Vector2.ZERO, "outside it, the walk begins")


## The length is the thumb's own and is not clamped here: past the rim is how the caller knows to run.
func test_a_thumb_pushed_past_the_rim_is_left_longer_than_one() -> void:
	var pushed: Vector2 = TouchPadScript.drag_stick(Vector2(0.0, -REACH * 2.0), REACH, DEAD_ZONE)
	assert(pushed.length() > 1.0, "past the rim: %s" % str(pushed))
	assert(
		pushed.length() >= TouchPadScript.RUN_AT,
		"and far enough past it to be a run: %f" % pushed.length()
	)


## A rim of no width cannot divide, so it asks for nothing rather than for infinity.
func test_a_rim_of_no_width_asks_for_nothing() -> void:
	assert(TouchPadScript.drag_stick(Vector2(30.0, 10.0), 0.0, DEAD_ZONE) == Vector2.ZERO)


# --- and how that composes with the keys -------------------------------------------------


## The thumb and the keys are one number. A thumb asking for forward walks forward, and a key beside it
## still counts - a laptop with a touchscreen has both, and neither may silence the other - but together
## they are a direction and a speed rather than two speeds, so they cannot add up to more than full.
func test_the_thumb_and_the_keys_are_added_together_without_beating_full_speed() -> void:
	MoveInputScript.set_touch_stick(Vector2(0.0, -1.0), false)
	assert(is_equal_approx(MoveInputScript.stick().y, -1.0), "the thumb alone walks forward")

	Input.action_press(&"move_right")
	var both: Vector2 = MoveInputScript.stick()
	Input.action_release(&"move_right")

	assert(both.x > 0.5, "the key beside it turned the walk to the right: %s" % str(both))
	assert(both.y < 0.0, "and the thumb still has it going forward: %s" % str(both))
	assert(both.length() <= 1.0001, "the two cannot add up to more than full speed: %s" % str(both))

	MoveInputScript.set_touch_stick(Vector2.ZERO, false)
	assert(MoveInputScript.stick() == Vector2.ZERO, "a thumb that has let go asks for nothing")


## Running is the thumb pushed past the rim, and it stops being a run the moment the thumb comes back.
func test_the_thumb_past_the_rim_is_what_asks_to_run() -> void:
	MoveInputScript.set_touch_stick(Vector2.ZERO, true)
	assert(MoveInputScript.sprinting(), "the thumb asked to run")
	MoveInputScript.set_touch_stick(Vector2(0.0, -0.5), false)
	assert(not MoveInputScript.sprinting(), "and now it did not")
	MoveInputScript.set_touch_stick(Vector2.ZERO, false)


# --- and which way a drag turns the head -------------------------------------------------


## Dragging right looks right, which is a smaller yaw because the body turns anticlockwise about +Y, and
## dragging down looks down, which is a smaller pitch. The sensitivity is the player's own, so a phone and
## a mouse cannot disagree.
func test_a_drag_turns_the_head_the_way_the_finger_went() -> void:
	var looked: Vector2 = PlayerScript.look_after_drag(
		0.0, 0.0, Vector2(100.0, 40.0), 0.0022, 88.0
	)
	assert(looked.x < 0.0, "dragged right, so the yaw fell: %f" % looked.x)
	assert(looked.y < 0.0, "dragged down, so the pitch fell: %f" % looked.y)
	assert(is_equal_approx(looked.x, -0.22), "100 px at the player's own sensitivity: %f" % looked.x)


## A finger that keeps pulling does not tip the world over: the pitch stops at the limit, both ways.
func test_a_finger_that_keeps_pulling_stops_at_the_look_limit() -> void:
	var down: Vector2 = PlayerScript.look_after_drag(
		0.0, 0.0, Vector2(0.0, 100000.0), 0.0022, 88.0
	)
	assert(is_equal_approx(down.y, -deg_to_rad(88.0)), "held at the limit: %f" % down.y)
	var up: Vector2 = PlayerScript.look_after_drag(
		0.0, 0.0, Vector2(0.0, -100000.0), 0.0022, 88.0
	)
	assert(is_equal_approx(up.y, deg_to_rad(88.0)), "and the other way: %f" % up.y)


# --- and when they are offered at all ----------------------------------------------------


## A machine with no touchscreen offers the thumb controls only when something has forced them on, which is
## how a desktop is shown the ground view's controls without a phone in hand.
func test_the_thumb_controls_are_offered_on_a_touchscreen_or_when_forced() -> void:
	var hud := HudScript.new()
	assert(not hud.shows_touch_controls(), "a desktop test runner has no touchscreen")
	hud.force_touch_controls(true)
	assert(hud.shows_touch_controls(), "forced on, it offers them")
	hud.free()