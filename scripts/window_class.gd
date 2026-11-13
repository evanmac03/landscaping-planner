class_name WindowClass
## What class a window is, in the breakpoints Android states for one, worked out from the room it has.
##
## Android replaced "phone or tablet" with a table of **window size classes**, so that a program changes
## *shape* at a breakpoint rather than at a guessed diagonal: a compact window is a phone upright, a medium one
## is a small tablet or a foldable open, an expanded one is a tablet in landscape, and large and extra-large
## are the desktop-shaped ones. This is that table, and it is where this program asks the one question it used
## to ask of a screen's diagonal - whether the canvas is worth drawing up on top of being sized for a finger.
##
## **The class is of the window's *shorter* side**, and that is the point rather than a detail. A phone held
## sideways - which is how this program's board is held - is 832 dp across and 384 dp down, so Android itself
## calls it a medium-width, **compact-height** window: by width it is not a phone at all. The side with no room
## is the side the question is about, and asking the wider one would answer that a phone has room it does not
## have. A tablet in landscape is 1365 by 853 dp, so both of its sides have room and neither is compact.
##
## **A dp is 1/160 inch**, the unit Android states a size in: what a window is, in the unit the class is about,
## rather than in the pixels one particular screen happens to have. Android's own numbers are below, and they
## are Material's - this file states them rather than inventing its own, because a breakpoint everybody else
## has is one a person can be told about.

extends RefCounted

const COMPACT := &"compact"
const MEDIUM := &"medium"
const EXPANDED := &"expanded"
const LARGE := &"large"
const EXTRA_LARGE := &"extra_large"

const CLASSES: Array[StringName] = [COMPACT, MEDIUM, EXPANDED, LARGE, EXTRA_LARGE]

## Where one class ends and the next begins, in dp. Each is a floor: a window of exactly this many dp has
## reached the class it names.
const MEDIUM_DP := 600.0
const EXPANDED_DP := 840.0
const LARGE_DP := 1200.0
const EXTRA_LARGE_DP := 1600.0


## What a room comes to in dp, across and down - the arithmetic, with no device read in it.
##
## `scale` is how many physical pixels one of the room's pixels is drawn at: `PhoneHud.canvas_scale` for a
## viewport, and 1.0 for a screen the platform reports in the pixels it really has. A room, a scale or a
## density nobody could read comes back as zeroes, which `class_for` refuses rather than guessing at.
static func dp_for(room: Vector2i, scale: float, density: float) -> Vector2:
	if room.x <= 0 or room.y <= 0 or scale <= 0.0 or density <= 0.0:
		return Vector2.ZERO
	return Vector2(
		float(room.x) * scale / density * 160.0,
		float(room.y) * scale / density * 160.0,
	)


## The class a length in dp has, or **no class at all** for a length nobody could read.
##
## An empty answer rather than the smallest class, deliberately: "this window is compact" is an answer about a
## window, and a number that does not exist is not one. Every caller here reads the empty answer as "no".
static func class_for(dp: float) -> StringName:
	if dp <= 0.0:
		return &""
	if dp < MEDIUM_DP:
		return COMPACT
	if dp < EXPANDED_DP:
		return MEDIUM
	if dp < LARGE_DP:
		return EXPANDED
	if dp < EXTRA_LARGE_DP:
		return LARGE
	return EXTRA_LARGE


## The class a room is, from its **shorter side**.
static func of(room: Vector2i, scale: float, density: float) -> StringName:
	var dp: Vector2 = dp_for(room, scale, density)
	if dp.x <= 0.0 or dp.y <= 0.0:
		return &""
	return class_for(minf(dp.x, dp.y))


## Whether a window is small enough that drawing the whole canvas up, on top of sizing everything for a
## finger, is worth what it costs. This is the question `TouchInput.needs_zooming` used to answer from a
## screen's diagonal, and it is asked of the class now because the class is what the answer is about.
##
## A window nobody could measure is not small: a canvas drawn up from a number that does not exist is worse
## than one left at the scale the platform already gave it.
static func is_small(room: Vector2i, scale: float, density: float) -> bool:
	return of(room, scale, density) == COMPACT


## How a class is written in a sentence, for a report or a demonstration to print rather than a menu to
## squeeze in - the same kind of wording `ReadingSize.sentence` and `OrientationChoice.sentence` are.
static func word(kind: StringName) -> String:
	match kind:
		COMPACT:
			return "a compact window"
		MEDIUM:
			return "a medium window"
		EXPANDED:
			return "an expanded window"
		LARGE:
			return "a large window"
		EXTRA_LARGE:
			return "an extra-large window"
	return "a window whose size nobody could read"