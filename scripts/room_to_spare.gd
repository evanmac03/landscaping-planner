class_name RoomToSpare
extends RefCounted
## A thing cut to a box smaller than the room around it had to give.
##
## Every instrument here measured rectangles, and a rectangle is always honest: a panel really is that big, a
## page really is that small. The fault this exists for is not a rectangle at all - it is a *relationship*
## between two of them. Text that scrolls, or is clipped, inside a box smaller than it needs, **while the box
## around it is bigger than it needs**, is a fault nothing here could see, because both numbers were always
## available and nothing compared them.
##
## The two numbers are the whole module. A control says the least it can be with `get_minimum_size`, so the
## room it was *given* minus the room it *wants* is its **shortfall**; and any box outwards from it knows how
## much of itself is standing empty, which is the room it could **give away**. One question joins them: was
## there, anywhere outwards, enough room to give? If there was, the box was made too small and the fault has a
## name and two numbers - "cut 40 px down, and the column around it had 300 px to give". If there was not, the
## thing is simply in a small window, and an instrument that complained would be wrong.
##
## **The room a box is using is not the least it needs.** A panel filled by a scroll container is using the
## whole of itself and has nothing to give, while its own minimum size says it needs almost none of it - and
## the first version of this measured the minimum, which named the palette's own tool scroll as a fault on the
## grounds that the panel around it had 750 px spare. It had none: the scroller was the whole of it.
##
## It decides nothing about what is *right*: a note field that scrolls is a scroller on purpose, and a person
## reading the two numbers can tell a design from an accident. This is the arithmetic of the question, so that
## the answer is worked out in one place rather than in whatever tool happens to ask.
##
## It measures nothing of its own - every number handed in came from a live control - and it needs no scene, no
## node and no file, so the whole rule is held down by `tests/test_room_to_spare.gd`.


## How much less room a thing was given than it wants, in each direction. Zero is the good answer, and a
## thing given more than it wants is short of nothing.
static func shortfall(given: Vector2, wanted: Vector2) -> Vector2:
	return Vector2(maxf(wanted.x - given.x, 0.0), maxf(wanted.y - given.y, 0.0))


## How much room a box has **standing empty** in it: its size less the room it is using. The difference is what
## it could give away without being crowded itself.
static func slack(box: Vector2, used: Vector2) -> Vector2:
	return Vector2(maxf(box.x - used.x, 0.0), maxf(box.y - used.y, 0.0))


## The first of these boxes, going **outwards** from a thing that was cut, with room to give **along the axis it
## was cut on**. Each box is `{ "name": String, "size": Vector2, "used": Vector2 }`, nearest first, which is the
## order a person reads - the smallest box that could have grown is the one worth naming.
##
## The direction is handed in rather than chosen here, and that is the whole point of the parameter: a box with
## room *down* is no use to a thing cut *across*, and accepting a box with room on either axis and then wording
## the fault with the worse one printed "cut across by 484 px, and Scroll had 0 px to give" - a sentence that
## contradicts itself, because the box was chosen for room it had on the other axis entirely.
##
## Empty when none of them had room, which is the answer for a thing that is simply in a small window.
static func first_with_room(boxes: Array, short_by: float, direction: String) -> Dictionary:
	for box: Dictionary in boxes:
		var room: Vector2 = slack(box["size"], box["used"])
		var along: float = room.x if direction == "across" else room.y
		if along >= short_by:
			return box
	return { }


## The whole rule, applied to everything a walk found. An item is `{ "name": String, "given": Vector2,
## "wanted": Vector2, "around": Array }`, and `around` is the boxes outwards from it.
##
## One fault per item that was cut **and** had a box outwards with room to give. A thing that is cut with no
## room anywhere is not a fault and is not in the answer - that is the whole difference between a box made too
## small and a window that is too small.
static func faults(items: Array) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for item: Dictionary in items:
		var given: Vector2 = item["given"]
		var wanted: Vector2 = item["wanted"]
		var short: Vector2 = shortfall(given, wanted)
		if short.x <= 0.0 and short.y <= 0.0:
			continue
		var direction: String = axis_of(short)
		var along: float = short.x if direction == "across" else short.y
		var giver: Dictionary = first_with_room(item["around"], along, direction)
		if giver.is_empty():
			continue
		found.append(
			{
				"name": String(item["name"]),
				"given": given,
				"wanted": wanted,
				"short": short,
				"axis": direction,
				"giver": giver,
				"spare": slack(giver["size"], giver["used"]),
			}
		)
	return found


## Which way a cut runs, as a word: the axis it was cut on, and the greater of the two when it was cut both
## ways - a thing too narrow *and* too short is named by the worse of them.
##
## Decided once, here, and carried on the fault: the search outwards and the sentence a person reads both ask
## this question, and two answers to it is how a fault came to name a box for room it had on the other axis.
static func axis_of(short: Vector2) -> String:
	if short.x > 0.0 and short.y <= 0.0:
		return "across"
	if short.y > 0.0 and short.x <= 0.0:
		return "down"
	return "across" if short.x >= short.y else "down"


## Which way a fault runs, as a word, as it was decided when the fault was found.
static func axis(fault: Dictionary) -> String:
	return String(fault["axis"])


## How much it was cut by, along that axis.
static func cut_by(fault: Dictionary) -> float:
	var short: Vector2 = fault["short"]
	return short.x if axis(fault) == "across" else short.y


## How much room the box that could have given had, along that same axis.
static func had_to_give(fault: Dictionary) -> float:
	var spare: Vector2 = fault["spare"]
	return spare.x if axis(fault) == "across" else spare.y


## One fault as a person reads it: what was cut, by how much, and which box around it had room to give.
static func sentence(fault: Dictionary) -> String:
	return "%s is cut %s by %d px, and %s had %d px to give" % [
		String(fault["name"]),
		axis(fault),
		roundi(cut_by(fault)),
		String((fault["giver"] as Dictionary)["name"]),
		roundi(had_to_give(fault)),
	]
