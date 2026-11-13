class_name BlankPicture
extends RefCounted
## A picture that shows nothing.
##
## A `TextureRect` with no texture, one given no size to be seen in, or one whose texture is a single flat
## colour is a place where a person was meant to see something and sees nothing. The check looks at EVERY byte
## of the picture: a sampled grid has twice missed a real feature in this project - a thin border, and a small
## mark in an otherwise empty field - so a picture is only called flat once every pixel in it has been compared
## against the first one.
##
## A flat picture is not automatically a fault: a person may have chosen a plain colour for a plate. What this
## hands back is named and not judged, and the name says what the picture is, so that a reader can tell the
## choice from the accident.


## Whether a picture has nothing in it: none at all, none with any size, or one colour from corner to corner.
static func is_blank(image: Image) -> bool:
	if image == null:
		return true
	var width := image.get_width()
	var height := image.get_height()
	if width <= 0 or height <= 0:
		return true
	var data: PackedByteArray = image.get_data()
	var stride := int(data.size() / float(width * height))
	if stride <= 0:
		return true
	# Every pixel's bytes against the first pixel's, one pixel at a time: the one difference that matters - a
	# mark in the corner - is the one a sample would step over.
	for at in range(0, data.size(), stride):
		for channel in stride:
			if data[at + channel] != data[channel]:
				return false
	return true


## Why a picture shows nothing, in a sentence, or the empty string when it shows something.
static func why(image: Image) -> String:
	if image == null:
		return "there is no picture here at all"
	if image.get_width() <= 0 or image.get_height() <= 0:
		return "the picture has been given no size to be seen in"
	if is_blank(image):
		return "the picture is one colour everywhere, %d x %d" % [image.get_width(), image.get_height()]
	return ""


## Every picture with nothing in it, each `{ "name", "why" }`. An item is `{ "name", "image" }`.
static func faults(items: Array) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for item: Dictionary in items:
		var image: Variant = item.get("image")
		if image != null and not (image is Image):
			continue
		var reason := why(image as Image)
		if reason.is_empty():
			continue
		found.append({ "name": String(item.get("name", "a picture")), "why": reason })
	return found


## One picture as a person reads it.
static func sentence(fault: Dictionary) -> String:
	return "%s - %s" % [fault["name"], fault["why"]]
