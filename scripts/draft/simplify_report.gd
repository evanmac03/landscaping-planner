class_name SimplifyReport
extends RefCounted
## What a simplification pass would do, and what it refused to do.
##
## A report rather than a mutation: the pass is worked out first and applied second, so
## the refusal rule - a shape may not be simplified in a way that detaches it from
## another shape - is decided against the drawing as it is, and a person can read the
## answer before it is committed. `DraftSimplify.plan` builds it; `DraftSimplify.apply`
## carries it out. It holds no document and does no arithmetic of its own.

## The tolerance the pass was run at, in model metres.
var tolerance: float = 0.0

## One entry per simplifiable shape, as a Dictionary:
##   {"id": int, "layer": StringName, "before": int, "after": int, "removed": int,
##    "points": PackedVector2Array}
## A shape that was considered and left alone still gets an entry, with `removed` zero:
## "there was nothing to take out" is an answer, not a silence.
var entries: Array[Dictionary] = []

## One entry per refusal, as {"id": int, "reason": String}. A refusal is not a failure of
## the pass: it is a shape the pass may not touch without breaking a connection, named so
## it can be dealt with by hand.
var refusals: Array[Dictionary] = []


## How many shapes the pass would actually change.
func changed_count() -> int:
	var total := 0
	for entry in entries:
		if int(entry["removed"]) > 0:
			total += 1
	return total


## How many vertices the pass would take out, across every shape.
func removed_count() -> int:
	var total := 0
	for entry in entries:
		total += int(entry["removed"])
	return total


func refused_count() -> int:
	return refusals.size()


## Every shape the pass looked at, whether it changed it or refused it.
func considered_count() -> int:
	return entries.size() + refusals.size()


## Whether there is nothing to say: no shape changes and none was refused. A pass that
## refused something is not a no-op - it has a reason to give.
func is_noop() -> bool:
	return changed_count() == 0 and refusals.is_empty()


## A line for the status bar or a dialog: what would happen, in words.
func describe() -> String:
	if considered_count() == 0:
		return "nothing to simplify"
	if changed_count() == 0:
		if refusals.is_empty():
			return "already as simple as it goes"
		return "no shape can be simplified; %d left alone" % refusals.size()
	var text := "%d shape%s simplified, %d point%s removed" % [
		changed_count(), "" if changed_count() == 1 else "s",
		removed_count(), "" if removed_count() == 1 else "s",
	]
	if not refusals.is_empty():
		text += "; %d left alone" % refusals.size()
	return text


## The plan as data, skipping the points themselves - a report is read by a person, and a
## vertex list is not a thing to print.
func to_dict() -> Dictionary:
	var rows: Array = []
	for entry in entries:
		rows.append({
			"id": int(entry["id"]),
			"layer": String(entry["layer"]),
			"before": int(entry["before"]),
			"after": int(entry["after"]),
			"removed": int(entry["removed"]),
		})
	return {
		"tolerance": tolerance,
		"entries": rows,
		"refused": refusals.duplicate(true),
	}