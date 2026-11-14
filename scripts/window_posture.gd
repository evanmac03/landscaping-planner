class_name WindowPosture
## Which way up a window's own shape is, and the honest limit of what can be said about a fold.
##
## Android's guidance has a third idea beside its size classes, and that is **posture**: a foldable standing
## half-open on a table wants the controls in the half nearest the hands, and one folded like a book wants a
## page kept clear of the crease. Both of those want the fold itself - whether the device is folded at all, and
## where the hinge lies - and **nothing Godot exposes answers that**. `DisplayServer`'s whole vocabulary about
## a screen is its size, its density, its scale, its orientation, its usable rectangle and whether it has a
## touchscreen; there is no fold, no hinge and no posture among them.
##
## So this is the smaller and true claim instead: the **shape of the window a fold leaves behind**. It is
## worth naming because it is what everything here is laid out in - the room a page lands in, and the length
## `WindowClass` is taken from - and because it is the one part of the posture question that is not a guess. A
## window as tall as it is wide, or taller, **stands**; one wider than it is tall **lies along**. A phone
## upright stands and the same phone on its side lies along, and a foldable's halves read as whichever of
## those the window's shape is: the fold is invisible in either case, which is exactly why this file stops at
## the shape rather than claiming a posture.
##
## **What that leaves undone, in words rather than in a guess.** Keeping a paragraph clear of a crease needs
## the crease's position, and a page narrowed to sit in the left half of a standing window would be narrowed
## wrongly on every phone and every tablet held upright - a wrong answer of the kind this project spends its
## effort avoiding. Where a control sits is the HUD's own layout answer rather than this file's, and a shape
## does not move it. So a foldable is served here by everything else being honest about *size*: it is sized
## for a finger and measured afresh every time, like any other window.

extends RefCounted

const STANDING := &"standing"
const LYING := &"lying"

const SHAPES: Array[StringName] = [STANDING, LYING]


## Which way up a room is, from its own two lengths - the arithmetic, with no device read in it.
##
## A room as tall as it is wide, or taller, **stands**: a phone held upright, a tablet propped up, a stand. One
## wider than it is tall **lies along**: the same phone on its side. A room nobody could read - either length
## nought or less - has no shape, which is not the same answer as lying along.
static func of(room: Vector2i) -> StringName:
	if room.x <= 0 or room.y <= 0:
		return &""
	if room.y >= room.x:
		return STANDING
	return LYING


## How a shape is written in a sentence, for a report to print rather than a menu to squeeze in - the same
## kind of wording `ReadingSize.sentence` and `WindowClass.word` are.
static func word(shape: StringName) -> String:
	match shape:
		STANDING:
			return "standing up"
		LYING:
			return "lying along"
	return "a shape nobody could read"
