class_name HeldOrientation
extends RefCounted
## How the phone is being held, and which way a camera's picture has to be turned to stand the same way.
##
## This program follows the device rather than locking it - `window/handheld/orientation` is `SCREEN_SENSOR` -
## so turning the phone turns the window, and every page is drawn in a canvas whose shape has changed under
## it. What does *not* turn with it is a camera: the sensor is bolted to the phone's body, so a picture taken
## while the phone is on its side arrives on its side, and the only thing that knows which way that is is the
## device's own answer. This file is the two things a page needs from that answer - how many quarter turns
## stand a picture up again, and how to say how the phone is being held in words.
##
## The device's answer is an argument rather than a reading taken inside these functions, so a test can ask
## what a phone held upright would be told without being one. `TouchInput.force` is the same door asked of a
## different question, and this file has no `force` of its own because it has no state to force.

## The quarter turns clockwise to give a camera's picture so that it stands the way the phone is held.
##
## A phone's sensor is mounted for the phone held upright, and Android turns the window to follow the device,
## so the canvas has been turned *away* from the sensor by exactly this much - which is what has to be undone.
## A device that says nothing is the landscape case, which is the shape every phone camera's frame arrives in
## anyway, so the answer for a reading nobody could make is to leave the picture alone.
static func quarter_turns(
	screen: int, _landscape: int, portrait: int, reverse_landscape: int, reverse_portrait: int
) -> int:
	if screen == portrait:
		return 1
	if screen == reverse_landscape:
		return 2
	if screen == reverse_portrait:
		return 3
	return 0


## Whether the screen is taller than it is wide - the question anything that has to *fit* the screen asks,
## and the one a page laid out for a 1600 by 900 desk has never had to answer before.
static func stands_up(screen: int, portrait: int, reverse_portrait: int) -> bool:
	return screen == portrait or screen == reverse_portrait


## How the phone is being held, as a few words to put in a sentence. Four ways, four answers, and the one a
## device cannot answer for reads as the landscape case rather than as an error.
static func words_for(
	screen: int, _landscape: int, portrait: int, reverse_landscape: int, reverse_portrait: int
) -> String:
	if screen == portrait:
		return "held upright"
	if screen == reverse_landscape:
		return "held the other way round"
	if screen == reverse_portrait:
		return "held upside down"
	return "held on its side"