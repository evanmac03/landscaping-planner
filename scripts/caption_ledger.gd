class_name CaptionLedger
extends RefCounted
## What every caption on the screen said, so that the same question can be asked twice.
##
## A stale caption is the quietest fault in a GUI and the one with no rule: whether "Line (1)" SHOULD have
## become "Circle (4)" is not something arithmetic can know, because it turns on what the page promised when it
## handed that label its words. That promise lives in the page and nowhere else, and any rule here would have to
## be told it.
##
## What can be had without guessing is the other half. Take the screen's words down twice, before an action and
## after it, and say which of them moved. A caption that held still while everything around it moved is the
## suspect list - which is worth having precisely because the answer is a judgement and the list is not. This is
## how the box beside the plan was found: it said the same thing whichever tool was in hand.
##
## The taking-down itself is a walk of the tree and belongs with the other walks, in `hud_probe`; what is here is
## the comparison of two readings, which is arithmetic about two dictionaries.


## What differs between two readings, as `{ "moved", "appeared", "vanished", "held" }`.
##
## `moved` is a list of `{ "path", "was", "now" }`; `appeared`, `vanished` and `held` are lists of paths. A path
## present both times with new words has moved; one only in the later reading has appeared; one only in the
## earlier has vanished; and every path whose words are unchanged has held still. A path in `held` is not
## thereby a fault - most of the screen should hold still - it is where a reader looks for one.
static func changes(before: Dictionary, after: Dictionary) -> Dictionary:
	var moved: Array[Dictionary] = []
	var appeared: Array[String] = []
	var held: Array[String] = []
	for path: Variant in after:
		var now := String(after[path])
		if not before.has(path):
			appeared.append(String(path))
			continue
		if String(before[path]) == now:
			held.append(String(path))
			continue
		moved.append({ "path": String(path), "was": String(before[path]), "now": now })
	var vanished: Array[String] = []
	for path: Variant in before:
		if not after.has(path):
			vanished.append(String(path))
	return { "moved": moved, "appeared": appeared, "vanished": vanished, "held": held }


## One caption that moved, as a person reads it.
static func sentence(change: Dictionary) -> String:
	return "%s  \"%s\"  ->  \"%s\"" % [change["path"], change["was"], change["now"]]


## The whole reading in one line, which is the shape a check wants.
static func summary(reading: Dictionary) -> String:
	return (
		"%d caption(s) moved, %d appeared, %d gone, %d held still"
		% [
			(reading["moved"] as Array).size(),
			(reading["appeared"] as Array).size(),
			(reading["vanished"] as Array).size(),
			(reading["held"] as Array).size(),
		]
	)
