class_name HeldOrientation
extends RefCounted
## How the phone is being held, and which way a camera's picture has to be turned to stand the same way.
##
## This program follows the device rather than locking it - `window/handheld/orientation` is `SCREEN_SENSOR` -
## so turning the phone turns the window, and every page is drawn in a canvas whose shape has changed under
## it. What does *not* turn with it is a camera: the sensor is bolted to the phone's body, so a picture taken
## while the phone is on its side arrives on its side, and something has to undo that before the picture can
## be looked at.
##
## What it is worked out *from* is the shape of the room the page is drawn in - taller than it is wide, or not
## - and deliberately **not** `DisplayServer.screen_get_orientation()`. On Android that call answers with the
## orientation the program *asked for*: `SCREEN_SENSOR` while the window is told to follow the device, or a
## pinned landscape while a plan is on the screen. A request is not a fact about the phone, and it read as
## neither portrait nor reverse-portrait, so a picture taken with the phone held upright was left in the
## sensor's landscape frame while the page it was taken from was drawn portrait. How big the room is cannot
## answer "follow".
##
## It is also simply the right question here: the photograph is a grab of the *drawn page*, so the turn needed
## is the one that stands the picture the way the page stands - and a plan deliberately pinned to landscape is
## then correctly left alone.
##
## The room is an argument rather than a reading taken inside these functions, so a test can ask what a phone
## held upright would be told without being one. `TouchInput.force` is the same door asked of a different
## question, and this file has no `force` of its own because it has no state to force.

## Whether the room stands up: taller than it is wide.
##
## The question a page that has to *fit* asks, and the one the camera's turn asks of the same room - asked
## once, here, so there is one answer rather than two that can disagree. A room nobody measured does not stand
## up, because there is nothing to stand up by.
static func stands_up(room: Vector2i) -> bool:
	if room.x <= 0 or room.y <= 0:
		return false
	return room.y > room.x


## The quarter turns clockwise to give a camera's picture so that it stands the way the page does.
##
## A phone's sensor is mounted for the phone held upright, so its frames arrive in landscape: a room that
## stands up needs one quarter turn, and a room on its side - which is the shape the sensor's frame already
## has - needs none.
##
## A shape can say standing up from on its side and *cannot* say which end is up, so a phone held upside down
## gets the same single turn as one held upright. That is the honest answer to the question actually being
## asked: stand the picture on the page. Which way up the person's own eyes would put it is not something a
## rectangle can know.
static func turns_for_a_room(room: Vector2i) -> int:
	return 1 if stands_up(room) else 0


## How the room stands, as a few words to put in a sentence.
##
## Two answers, because two is all a shape knows: it cannot see which end is up, so a line that claimed an
## upside-down phone would be inventing one. The line this replaced said "held on its side" over a portrait
## window, which is how the fault it came from was found.
static func words_for_a_room(room: Vector2i) -> String:
	return "held upright" if stands_up(room) else "held on its side"
