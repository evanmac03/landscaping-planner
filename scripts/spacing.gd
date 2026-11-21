class_name Spacing
extends RefCounted
## How far apart two targets are, when a finger is the thing that has to choose between them.
##
## A control of the right size is still the wrong control if its neighbour is a pixel away. A thumb lands over an
## area about a centimetre across, so two targets closer together than the finger's own aim are one target as far
## as the person pressing is concerned - and which of the two answers the tap is decided by the order the engine
## draws them in, not by where the finger landed. The floor for the clear space between two targets is about
## 8 px.
##
## Only pairs a finger has to choose between are judged, which is the caller's business: this is handed things a
## tap would stop at, never a plate a button stands on. Three pairs are left out here as well. Two controls in
## *exactly* the same rectangle are `Stacked`'s finding, and they would read here as a gap of nothing - one
## defect named twice. A rectangle that contains another is a control on a plate rather than a neighbour. And a
## pair that overlaps *without* being identical is not left out at all: an overlap is the worst gap there is, and
## a tap at the seam is the one that goes astray.

## The clear space two targets a finger chooses between should have, in screen pixels.
const LEAST := 8


## How far apart two rectangles are: 0 when they touch or overlap, and otherwise the distance on the axis they
## are separated along. A pair apart on both axes is as far away as its nearer axis, because that is the gap a
## finger at the corner sees.
static func gap_between(a: Rect2i, b: Rect2i) -> int:
	var across := maxi(maxi(a.position.x - b.end.x, b.position.x - a.end.x), 0)
	var down := maxi(maxi(a.position.y - b.end.y, b.position.y - a.end.y), 0)
	return maxi(across, down)


## Every pair of targets a finger could not tell apart, each `{ "a", "b", "gap", "least" }`. An item is
## `{ "name", "rect" }`.
static func faults(items: Array, least: int = LEAST) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var seen: Array[Dictionary] = []
	for item: Dictionary in items:
		var rect: Variant = item.get("rect")
		if not (rect is Rect2i):
			continue
		var here := rect as Rect2i
		for before: Dictionary in seen:
			var other := before["rect"] as Rect2i
			if other == here:
				continue
			if other.encloses(here) or here.encloses(other):
				continue
			var gap := gap_between(other, here)
			if gap >= least:
				continue
			found.append(
				{ "a": String(before["name"]), "b": String(item.get("name", "a control")), "gap": gap, "least": least }
			)
		seen.append({ "name": String(item.get("name", "a control")), "rect": here })
	return found


## The pair closest together, which is the one a person would fix first.
static func closest(found: Array) -> Dictionary:
	var tightest: Dictionary = { }
	for fault: Dictionary in found:
		if tightest.is_empty() or int(fault["gap"]) < int(tightest["gap"]):
			tightest = fault
	return tightest


## One pair as a person reads it. An overlap is worded as what it is rather than as a distance of nothing,
## because "0 px apart" leaves a reader to work out which of the two answers a tap.
static func sentence(fault: Dictionary) -> String:
	if int(fault["gap"]) == 0:
		return (
			"%s and %s overlap, so a tap at the seam reaches whichever the engine draws later"
			% [fault["a"], fault["b"]]
		)
	return (
		"%s and %s are %d px apart where a finger wants %d" % [fault["a"], fault["b"], fault["gap"], fault["least"]]
	)
