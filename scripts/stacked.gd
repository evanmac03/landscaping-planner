class_name Stacked
extends RefCounted
## Two things of the same kind drawn in exactly the same rectangle, so that one of them is never seen.
##
## Two Buttons in one rectangle is a mistake in almost any program: only the one drawn later can be reached and
## pressed, its twin is invisible underneath it, and a person reading the screen has no way to know the other is
## there at all. Nothing else in this project looks for it - an overlap check asks what a rectangle meets, and a
## tap check asks which control a point reaches, and both of those answer "the later one" and stop.
##
## A Panel under a Label is not the same finding at all: a control standing on a panel is the design, and the
## two are different kinds. So the rule looks only for the SAME kind in the SAME rectangle, and calls it what it
## is rather than deciding whether somebody meant it.


## Every pair of the same kind sharing one rectangle, each `{ "kind", "rect", "a", "b" }`, where `a` is the one
## seen first. An item is `{ "name", "kind", "rect" }`.
static func faults(items: Array) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	var seen: Array[Dictionary] = []
	for item: Dictionary in items:
		var rect: Variant = item.get("rect")
		var kind := String(item.get("kind", ""))
		if not (rect is Rect2i) or kind.is_empty():
			continue
		var here := { "name": String(item.get("name", "a control")), "rect": rect as Rect2i, "kind": kind }
		for before: Dictionary in seen:
			if before["kind"] != kind:
				continue
			if (before["rect"] as Rect2i) != (rect as Rect2i):
				continue
			found.append({ "kind": kind, "rect": rect, "a": before["name"], "b": here["name"] })
		seen.append(here)
	return found


## One pair as a person reads it.
##
## The rectangle is phrased here rather than printed straight: `Rect2i`'s own text reads `[P: (10, 20), S: (30,
## 40)]`, which is a machine telling another machine where something is, and a reader wants to be told where to
## look and what size to look for.
static func sentence(fault: Dictionary) -> String:
	var rect := fault["rect"] as Rect2i
	return (
		"%s and %s are both %s at (%d, %d) sized %d x %d, so only the later one is ever seen"
		% [fault["a"], fault["b"], fault["kind"], rect.position.x, rect.position.y, rect.size.x, rect.size.y]
	)
