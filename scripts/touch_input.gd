class_name TouchInput
extends RefCounted
## Whether this device is answered with a finger.
##
## The operating system is not the question, and on its own it gets the answer wrong in both directions: a
## Windows tablet and an Android tablet are the same device with the same density, and both deserve a
## palette a thumb can hit; a desktop with a touchscreen in the monitor is a desk, and giving it a phone's
## palette would cost it half its drawing area for nothing. What decides it is two things together - the
## device has a touchscreen at all, and the controls this program already draws are, *on this screen*,
## smaller than a finger. Asking the millimetres instead of `OS.has_feature("android")` is what makes a
## tablet the same device whichever platform it is running.

## Which answer to give, so a demonstration or a test can ask what a phone, a tablet or a desk would be
## told without being one. `AUTO` reads the machine it is running on.
enum Answer { AUTO, FINGER, MOUSE }

## The height a row of answers has on a desk, in logical pixels, and the size a finger needs: the two
## numbers the whole question is a comparison between. A row this tall is 1.6 mm on a phone's screen and
## 5.1 mm on this desk's, which is the same row being a thumb's target and a mouse's.
const DESK_ROW_PX := 29.0
const THUMB_MM := 5.5

## Where a screen stops being sat at and starts being held.
##
## Needed because a touchscreen alone does not tell the two apart: this desk answers
## `DisplayServer.is_touchscreen_available()` with true, and its touchscreen is in the monitor. The density
## does tell them apart, and only because the two platforms report it differently and honestly: Windows
## reports the *logical* density its scaling produces - 96, 120, 144, 192 - while Android reports the panel's
## physical 450. 200 is above every Windows scaling step and below every phone and tablet, so it separates
## the two without having to work out an inch, which Windows cannot do: its 144 is 1920 px across 1.5x, not
## a 13-inch panel.
const HELD_DPI := 200.0

static var _answer: Answer = Answer.AUTO


## Answer for a device rather than for the one this program is running on.
##
## For demonstrations and tests only - nothing in the program calls it - and `Answer.AUTO` puts the
## reading back. It is the same door `PhoneFiles.force` is, asked of a different question.
static func force(answer: Answer) -> void:
	_answer = answer


## Whether this device has a touchscreen at all.
static func has_a_touchscreen() -> bool:
	match _answer:
		Answer.FINGER:
			return true
		Answer.MOUSE:
			return false
		_:
			return DisplayServer.is_touchscreen_available()


## Whether a device is answered with a finger.
##
## Four ways to the answer, and three of them are "no" for different reasons. No touchscreen is a desk,
## however dense its screen. A screen below `HELD_DPI` is a screen being sat at, however it is touched -
## this desk's own monitor reports a touchscreen and 144 dots to the inch. And a density that could not be
## read resizes nothing at all: a size worked out from a number that does not exist is worse than the size
## the program already drew, so an unread density leaves the layout exactly as it was built.
static func answered_by_a_thumb(
	has_touchscreen: bool, density: float, desk_row_mm: float, thumb_mm: float = THUMB_MM
) -> bool:
	if not has_touchscreen:
		return false
	if density <= 0.0 or desk_row_mm <= 0.0 or thumb_mm <= 0.0:
		return false
	if density < HELD_DPI:
		return false
	return desk_row_mm < thumb_mm


## How much screen, edge to edge, is a phone's and not a tablet's.
##
## Sizing for a finger and drawing the canvas up are two different answers and a tablet needs only the
## first: a ten-inch screen has the room for a finger-sized palette at its own scale, and drawing it up by
## a third would put a tablet's drawing behind the same panels a phone has, for no gain. Seven inches
## across is a 6-inch phone in landscape (5.2) and clear of a 10-inch tablet (8.5).
const PHONE_ACROSS_INCHES := 7.0


## Whether the canvas should be drawn up as well as sized for a finger - which is only true of a screen
## held in one hand. A screen nobody could measure is not drawn up: the canvas keeps the scale it has.
static func needs_zooming(
	across_inches: float, phone_across_inches: float = PHONE_ACROSS_INCHES
) -> bool:
	if across_inches <= 0.0 or phone_across_inches <= 0.0:
		return false
	return across_inches < phone_across_inches
