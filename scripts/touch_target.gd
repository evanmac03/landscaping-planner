class_name TouchTarget
extends RefCounted
## A control a finger is meant to press, and whether a finger could hit it.
##
## The desk's buttons are 31 px tall and that is right for a mouse, which lands on the very pixel it is aimed
## at. A finger is not aimed that precisely, and the guidance is a target of about 44 px on its shorter side.
##
## What matters is that the comparison is made in SCREEN pixels and only while the program says a finger is in
## use. This program's phone canvas scales by about 1.62, so a button it draws 31 px tall arrives under the
## thumb 50 px tall, and is perfectly reachable. Judging the desk's own 31 px buttons would name every control
## in the program for a fault the desk does not have - which is why the caller, and not this file, decides
## whether a finger is the thing being served.

## The shorter side a target a finger is meant to press should have, in screen pixels.
const LEAST := 44


## How many pixels short of that a rectangle is; 0 when it is already big enough.
static func shortfall(rect: Rect2i, least: int = LEAST) -> int:
	var shorter := mini(rect.size.x, rect.size.y)
	return maxi(least - shorter, 0)


## Whether a rectangle is a target a finger could hit.
static func fits(rect: Rect2i, least: int = LEAST) -> bool:
	return shortfall(rect, least) == 0


## Every target too small for a finger, each `{ "name", "rect", "short", "least" }`. An item is
## `{ "name", "rect" }`.
static func faults(items: Array, least: int = LEAST) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for item: Dictionary in items:
		var rect: Variant = item.get("rect")
		if not (rect is Rect2i):
			continue
		var short := shortfall(rect as Rect2i, least)
		if short == 0:
			continue
		found.append({ "name": String(item.get("name", "a control")), "rect": rect, "short": short, "least": least })
	return found


## The target furthest short of what a finger wants, which is the one to fix first.
static func worst(found: Array) -> Dictionary:
	var smallest: Dictionary = { }
	for fault: Dictionary in found:
		if smallest.is_empty() or int(fault["short"]) > int(smallest["short"]):
			smallest = fault
	return smallest


## One target as a person reads it.
static func sentence(fault: Dictionary) -> String:
	var rect := fault["rect"] as Rect2i
	return (
		"%s is %d x %d, %d px short of the %d a finger wants"
		% [fault["name"], rect.size.x, rect.size.y, fault["short"], fault["least"]]
	)
