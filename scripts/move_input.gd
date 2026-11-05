class_name MoveInput
extends RefCounted
## The movement, read exactly: the keys, and a thumb on glass.
##
## `Input.get_vector` matches a binding whatever modifiers are held, so a command on Ctrl also
## moves: Ctrl+S is `move_back` as well as *save*, and saving a drawing in the ground view would
## take a step backwards at the same moment. It is the same trap the drawing tools met from the
## other side - `D` arms the tools and also means move-right, which is why the overhead panning
## stands down while a tool is armed.
##
## These reads ask for the *exact* binding instead: a movement key answers to its own binding and
## not to that binding plus a modifier. That makes Ctrl a command modifier everywhere it is used,
## and means no command has to be kept off a letter the camera walks with.
##
## `.limit_length(1.0)` is what `get_vector` does to a diagonal, and dropping it would make
## walking north-east 1.4 times as fast as walking north - the oldest bug in the book.


## A virtual stick, for a device with a screen and no keyboard.
##
## Held here rather than read from the on-screen control's own state, because the walker above reads one
## number: `stick()` is the keys *plus* whatever a thumb is asking for, so the player never has to know
## which device asked. It composes rather than replaces - a laptop with a touchscreen has both, and a
## stick that overrode the keys would make W do nothing.
##
## Analogue on purpose. `axis` above is whole numbers because a key is held or it is not, and a thumb
## stick routed through those same actions would arrive as full speed or nothing; these are the numbers
## before that flattening.
static var _touch_stick: Vector2 = Vector2.ZERO
static var _touch_sprint: bool = false


## What a virtual stick is asking for at this moment. Called by whatever draws one - the HUD's touch pad -
## and by nothing else, and a zero vector is a thumb that has let go.
static func set_touch_stick(asked: Vector2, sprint: bool) -> void:
	_touch_stick = asked.limit_length(1.0)
	_touch_sprint = sprint


static func stick() -> Vector2:
	var keys := Vector2(
		axis(&"move_left", &"move_right"), axis(&"move_forward", &"move_back")
	)
	return (keys + _touch_stick).limit_length(1.0)


## One axis, from -1 to 1. Whole numbers because these are keyboard actions: a key is held or it
## is not, and an analogue stick bound to them would simply arrive as either.
static func axis(negative: StringName, positive: StringName) -> float:
	var value := 0.0
	if Input.is_action_pressed(positive, true):
		value += 1.0
	if Input.is_action_pressed(negative, true):
		value -= 1.0
	return value


## Whether the person is asking to run, read the same exact way.
static func sprinting() -> bool:
	return _touch_sprint or Input.is_action_pressed(&"sprint", true)