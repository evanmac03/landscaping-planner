class_name MoveInput
extends RefCounted
## The movement keys, read exactly.
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


static func stick() -> Vector2:
	return Vector2(
		axis(&"move_left", &"move_right"), axis(&"move_forward", &"move_back")
	).limit_length(1.0)


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
	return Input.is_action_pressed(&"sprint", true)