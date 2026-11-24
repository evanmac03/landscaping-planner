class_name InView
extends RefCounted
## A control the room cannot hold: something drawn past the edge of the screen.
##
## Every other instrument here compares a control with **another control** - this one over that one, this one
## too small for what it holds, these two sharing rows - and not one of them ever put a control beside the
## *room* it is standing in. So the one fault a person can do nothing about went unseen: a button drawn past the
## edge of the screen is not merely ugly, it cannot be pressed at all. The phone's own view buttons were drawn
## off the side of it, and that was found by eye.
##
## It is deliberately only arithmetic about two rectangles. What it cannot know is which of the two ways of
## being past the edge a control is there by: a tool in a scroll is above the visible part of it and is meant to
## be. The walk that feeds this leaves those out - a control something is clipping is not handed over - and what
## arrives here is a control nothing is clipping, for which being off the screen means a person can never reach
## it.
##
## The room is given in the same direction order as everywhere else in this program: `x` is the left edge,
## `y` the top, `z` the right and `w` the foot, so a `Vector4i` of zeroes is the good answer in all of them.


## How far a rectangle leaves the room on each side, in pixels. Zeroes are the good answer, and a room that is
## not there at all - a viewport of no size, which is what a headless run has - holds nothing and so reports
## nothing: nothing is outside a room that does not exist.
static func off_the_edge(rect: Rect2i, room: Vector2i) -> Vector4i:
	if room.x <= 0 or room.y <= 0:
		return Vector4i.ZERO
	return Vector4i(
		maxi(-rect.position.x, 0),
		maxi(-rect.position.y, 0),
		maxi(rect.position.x + rect.size.x - room.x, 0),
		maxi(rect.position.y + rect.size.y - room.y, 0),
	)


## Whether a rectangle is entirely within the room: touching an edge is being inside it, because a control
## flush with the side of the screen is exactly where a person would put one.
static func fits(rect: Rect2i, room: Vector2i) -> bool:
	return off_the_edge(rect, room) == Vector4i.ZERO


## Whether **none** of a rectangle is in the room at all, which is the worse fault of the two: a control a
## little past the edge is tight, and a control wholly outside it is one nobody can reach.
static func wholly_outside(rect: Rect2i, room: Vector2i) -> bool:
	if room.x <= 0 or room.y <= 0:
		return false
	var shown: Rect2i = Rect2i(0, 0, room.x, room.y).intersection(rect)
	return shown.size.x <= 0 or shown.size.y <= 0


## Everything handed in that the room cannot hold. An item is `{ "name": String, "rect": Rect2i,
## "room": Vector2i }`, and one fault comes back per item that leaves the room - none for a control that fits,
## and none for anything at all when the room is not there.
static func faults(items: Array) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for item: Dictionary in items:
		var rect: Rect2i = item["rect"]
		var room: Vector2i = item["room"]
		var over: Vector4i = off_the_edge(rect, room)
		if over == Vector4i.ZERO:
			continue
		found.append(
			{
				"name": String(item["name"]),
				"rect": rect,
				"room": room,
				"off": over,
				"gone": wholly_outside(rect, room),
			}
		)
	return found


## How far the worst of the four sides reaches, which is the one number worth reading first: a control 4 px
## past the edge is tight and one 400 px past it is invisible.
static func worst(fault: Dictionary) -> int:
	var over: Vector4i = fault["off"]
	return maxi(maxi(over.x, over.y), maxi(over.z, over.w))


## One fault as a person reads it: what it is, which edges it has left, and whether any of it is still there.
static func sentence(fault: Dictionary) -> String:
	var room: Vector2i = fault["room"]
	var past: String = _past_words(fault["off"])
	if fault["gone"]:
		return "%s is off the screen altogether - %s of a %d x %d room" % [fault["name"], past, room.x, room.y]
	return "%s is %s of a %d x %d room, and part of it can never be seen" % [fault["name"], past, room.x, room.y]


## The edges a rectangle has left, each with how far past it goes, in the order a person would say them.
static func _past_words(over: Vector4i) -> String:
	var said := PackedStringArray()
	if over.x > 0:
		said.append("%d px past the left edge" % over.x)
	if over.y > 0:
		said.append("%d px past the top edge" % over.y)
	if over.z > 0:
		said.append("%d px past the right edge" % over.z)
	if over.w > 0:
		said.append("%d px past the foot" % over.w)
	return ", and ".join(said)
