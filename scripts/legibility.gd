class_name Legibility
extends RefCounted
## Whether words are drawn big enough for the screen they land on.
##
## **The floor is not stated here.** It is `PhoneHud`'s own reading - a capital letter `TEXT_MM` tall at arm's
## length, turned into a font size for the device's density - and a second copy of that number in this file could
## disagree with the sizes the program actually draws at. What lives here is the judgement about one control's
## font, against the number the program already obeys.
##
## A desk is not judged, and does not need to be: its 12 px body text is exactly the size this program was laid
## out at. The same 12 px on a phone is unreadable, which is why `PhoneHud.text_size_for_a_finger` grows a page's
## text wherever a finger presses the controls. So the device is stated by the caller - a canvas scale and a
## density - and **a device that has not said what it is judges nothing**: `PhoneHud.font_size` answers 0 for a
## density it could not read, and 0 is no floor rather than a floor of nothing.
##
## `ReadingSize` is a different question, and a person's: how much *bigger* than this floor the reader has asked
## for. It multiplies the floor - `PhoneHud` applies it to every size it works out - and it never lowers it.

const PhoneHudScript := preload("res://scripts/phone_hud.gd")


## How far a font size falls short of what the screen needs; 0 when it is big enough, and 0 when there is no
## floor to compare against or the control states no size of its own.
static func shortfall(size: int, scale: float, density: float) -> int:
	var least: int = PhoneHudScript.font_size(scale, density)
	if least <= 0 or size <= 0:
		return 0
	return maxi(least - size, 0)


## Whether a font size is big enough for the screen it lands on.
static func fits(size: int, scale: float, density: float) -> bool:
	return shortfall(size, scale, density) == 0


## Every control whose words are too small for the screen it is on, each
## `{ "name", "size", "least", "short" }`. An item is `{ "name", "font", "scale", "density" }`.
static func faults(items: Array) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for item: Dictionary in items:
		var size: Variant = item.get("font")
		if not (size is int) and not (size is float):
			continue
		var scale: float = float(item.get("scale", 0.0))
		var density: float = float(item.get("density", 0.0))
		var short := shortfall(int(size), scale, density)
		if short == 0:
			continue
		found.append(
			{
				"name": String(item.get("name", "a caption")),
				"size": int(size),
				"least": PhoneHudScript.font_size(scale, density),
				"short": short,
			}
		)
	return found


## The words furthest below what the screen needs, which is the one to fix first.
static func worst(found: Array) -> Dictionary:
	var smallest: Dictionary = { }
	for fault: Dictionary in found:
		if smallest.is_empty() or int(fault["short"]) > int(smallest["short"]):
			smallest = fault
	return smallest


## One caption as a person reads it.
static func sentence(fault: Dictionary) -> String:
	return ("%s is drawn at %d px where this screen needs %d" % [fault["name"], fault["size"], fault["least"]])
