class_name SafeArea
extends RefCounted
## Whether a target is standing somewhere the device keeps for itself.
##
## A phone's edges belong to the system before they belong to the program. A swipe up from the bottom is the way
## home, a swipe in from either side is the way back, and the strip at the top is the notification shade. A button
## drawn under one of those answers the system instead of the finger, and from inside the program it looks exactly
## like every other button.
##
## **The device's numbers are not restated here.** What the platform promises to leave alone is `PhoneHud`'s own
## reading - `PhoneHud.cutout_here` answers it in the room's pixels - and the caller hands it in, in screen
## pixels. What lives here is the judgement about one rectangle, which is the comparison every instrument in this
## project makes: a rectangle against a place it has to stand in.
##
## A device that has promised nothing is a device with nothing to judge. A safe area of no size gives back no
## insets at all, and names nothing, because every control in the program is outside a place that is not there.


## How far a rectangle reaches past each edge of what the device promised, x=left, y=top, z=right, w=foot - the
## same order the room's own insets are worded in.
static func insets(rect: Rect2i, safe: Rect2i) -> Vector4i:
	if safe.size.x <= 0 or safe.size.y <= 0:
		return Vector4i.ZERO
	var left := maxi(safe.position.x - rect.position.x, 0)
	var top := maxi(safe.position.y - rect.position.y, 0)
	var right := maxi(rect.end.x - safe.end.x, 0)
	var foot := maxi(rect.end.y - safe.end.y, 0)
	return Vector4i(left, top, right, foot)


## Whether a rectangle stands wholly where the device will leave it alone.
static func inside(rect: Rect2i, safe: Rect2i) -> bool:
	return insets(rect, safe) == Vector4i.ZERO


## Every target standing in a band the device keeps, each `{ "name", "insets", "worst", "safe" }`. An item is
## `{ "name", "rect", "safe" }`.
static func faults(items: Array) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for item: Dictionary in items:
		var rect: Variant = item.get("rect")
		var safe: Variant = item.get("safe")
		if not (rect is Rect2i) or not (safe is Rect2i):
			continue
		var reaches := insets(rect as Rect2i, safe as Rect2i)
		if reaches == Vector4i.ZERO:
			continue
		found.append(
			{
				"name": String(item.get("name", "a control")),
				"insets": reaches,
				"worst": maxi(maxi(reaches.x, reaches.y), maxi(reaches.z, reaches.w)),
				"safe": safe,
			}
		)
	return found


## The target that reaches furthest into a band the device keeps, which is the one to fix first.
static func worst(found: Array) -> Dictionary:
	var deepest: Dictionary = { }
	for fault: Dictionary in found:
		if deepest.is_empty() or int(fault["worst"]) > int(deepest["worst"]):
			deepest = fault
	return deepest


## The bands a rectangle reaches into, in a person's words - "the top band", "the foot" - so that a reader knows
## which edge of the screen to look at without working it out from four numbers.
static func words(reaches: Vector4i) -> String:
	var bands: Array[String] = []
	if reaches.y > 0:
		bands.append("%d px into the top band" % reaches.y)
	if reaches.w > 0:
		bands.append("%d px into the foot" % reaches.w)
	if reaches.x > 0:
		bands.append("%d px into the left band" % reaches.x)
	if reaches.z > 0:
		bands.append("%d px into the right band" % reaches.z)
	if bands.is_empty():
		return "inside the area the device leaves alone"
	return " and ".join(bands)


## One target as a person reads it.
static func sentence(fault: Dictionary) -> String:
	return ("%s stands %s, which the device keeps for itself" % [fault["name"], words(fault["insets"] as Vector4i)])


## Whether a finger landing on the middle of a rectangle lands in a band the device keeps.
##
## **This is the sharper of the two questions about a band, and the phone is what taught it.** `insets` says how
## far a rectangle *reaches* past an edge, which is the right answer for a control that is mostly under the band -
## but a finger does not land where a control reaches, it lands where it was aimed, and what a person aims at is
## the middle. The board's three view buttons on the device each reach 81 px into the top band, and their middles
## are at y=68: the reach is how far the band and the button overlap, while the middle inside it is why the press
## goes to the system. The same reading clears a large button that merely overlaps an edge, whose middle and most
## of its area are perfectly reachable.
##
## A safe area of no size is a device that has promised nothing, and names nothing here either.
static func covers_centre(rect: Rect2i, safe: Rect2i) -> bool:
	if safe.size.x <= 0 or safe.size.y <= 0:
		return false
	return not safe.has_point(rect.get_center())


## Every target whose middle is in a band the device keeps, each `{ "name", "rect", "centre", "safe" }`. An item
## is `{ "name", "rect", "safe" }`. Nothing is reported for a device that has promised nothing.
static func centre_faults(items: Array) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for item: Dictionary in items:
		var rect: Variant = item.get("rect")
		var safe: Variant = item.get("safe")
		if not (rect is Rect2i) or not (safe is Rect2i):
			continue
		if not covers_centre(rect as Rect2i, safe as Rect2i):
			continue
		found.append(
			{
				"name": String(item.get("name", "a control")),
				"rect": rect,
				"centre": (rect as Rect2i).get_center(),
				"safe": safe,
			}
		)
	return found


## The target whose middle is deepest in a band, which is the one a finger is least likely to reach.
static func deepest_centre(found: Array) -> Dictionary:
	var deepest: Dictionary = { }
	for fault: Dictionary in found:
		var centre: Vector2i = fault["centre"]
		var safe: Rect2i = fault["safe"]
		var reach := maxi(
			maxi(safe.position.x - centre.x, centre.x - safe.end.x),
			maxi(safe.position.y - centre.y, centre.y - safe.end.y),
		)
		if deepest.is_empty() or reach > int(deepest["reach"]):
			deepest = fault.duplicate()
			deepest["reach"] = reach
	return deepest


## One target whose middle is in a band, as a person reads it.
static func centre_sentence(fault: Dictionary) -> String:
	var centre: Vector2i = fault["centre"]
	return (
		"%s takes a finger at its middle, (%d, %d), which is inside the band the device keeps for itself"
		% [fault["name"], centre.x, centre.y]
	)
