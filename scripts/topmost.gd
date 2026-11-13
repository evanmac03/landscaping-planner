class_name Topmost
extends RefCounted
## What a tap would actually reach: the topmost control at a point.
##
## This is the question a person asks when something they pressed did nothing, and until now the instruments
## could not answer it. Every rectangle they measured was measured *alone* - is this one big enough, does that
## one share rows with it - and none of them ever asked which control a click at a point would land on. A button
## drawn under a page looks perfectly correct to every other one of them.
##
## The rectangles arrive **in the order they are drawn**, the furthest back first, which is what a walk of a
## tree gives: a parent before its children, an earlier sibling before a later one, and the board before the
## pages that stand over it. That order is the whole answer, because a control drawn later covers one drawn
## earlier, so the last rectangle holding the point is the one that receives the click.
##
## Two judgements are left to the walk that feeds this, because only a live tree knows them. A control that
## ignores the mouse - a plain panel under a button, a spacer - is not a thing a tap reaches, and is not handed
## over at all. A control that takes the mouse but will not answer it, a button switched off, *is* handed over,
## and named as switched off: the tap does reach it and then nothing happens, which is exactly the answer
## somebody looking for a silent button wants.


## The topmost box at a point: the last of those in drawing order that holds it, or an empty dictionary when
## nothing there takes the mouse at all. A box is `{ "name": String, "rect": Rect2i, "enabled": bool }`, and
## `enabled` may be left out when the thing answers.
static func at(point: Vector2i, boxes: Array) -> Dictionary:
	var top: Dictionary = { }
	for box: Dictionary in boxes:
		var rect: Rect2i = box["rect"]
		if rect.has_point(point):
			top = { "name": String(box["name"]), "rect": rect, "enabled": bool(box.get("enabled", true)) }
	return top


## The gap between what a tap meant to reach and what it would reach: empty when the wanted control is the one
## on top and answers, and one fault otherwise - including when nothing is there at all, and when the thing on
## top is the wanted control switched off.
static func mistake(point: Vector2i, boxes: Array, wanted: String) -> Dictionary:
	var top: Dictionary = at(point, boxes)
	if top.is_empty():
		return { "point": point, "wanted": wanted, "reached": "", "switched_off": false }
	if String(top["name"]) == wanted:
		if bool(top["enabled"]):
			return { }
		return { "point": point, "wanted": wanted, "reached": wanted, "switched_off": true }
	return { "point": point, "wanted": wanted, "reached": String(top["name"]), "switched_off": false }


## The point a control is pressed at - the middle of it, which is what a driver aims at and what a person's
## finger lands on.
static func middle(rect: Rect2i) -> Vector2i:
	return Vector2i(rect.position.x + int(rect.size.x / 2.0), rect.position.y + int(rect.size.y / 2.0))


## One mistake as a person reads it, in the words they would use to ask the question.
static func sentence(gap: Dictionary) -> String:
	var point: Vector2i = gap["point"]
	if String(gap["reached"]) == "":
		return "a tap at (%d, %d) meant for %s would reach nothing there" % [point.x, point.y, gap["wanted"]]
	if bool(gap["switched_off"]):
		return (
			"a tap at (%d, %d) does reach %s, and it is switched off, so nothing happens"
			% [point.x, point.y, gap["wanted"]]
		)
	return ("a tap at (%d, %d) meant for %s would reach %s instead" % [point.x, point.y, gap["wanted"], gap["reached"]])
