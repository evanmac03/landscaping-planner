class_name Stillness
extends RefCounted
## What changed between two frames of the same screen, which is the one thing a single picture can never show.
##
## Every instrument in this project looks at **one** picture of the program, or at the tree that draws it, and
## not one of them can tell a screen that is holding still from one being redrawn sixty times a second. That is
## a whole family of faults with no other witness: a caption rewritten every frame with the same words, a panel
## that jitters by a pixel, a control re-laid-out on every tick, a caret blinking in a field nobody is typing
## into. Each is invisible in a still picture, each costs frames, and a person feels the sum of them as a window
## that will not settle.
##
## The arithmetic here is about **two images** and nothing else: which rows differ, how far across, and how much
## of any one row. Whether the movement is a *fault* is deliberately not decided - a caret blinking is an
## animation doing its job, and a progress line moving is a screen working - so what this hands back is named
## and not judged, the same way the crowding and the words are.
##
## Two frames that are not the same shape are not the same screen, and subtracting them would invent a change
## along the whole of the shorter one, so that pair answers with nothing at all.


## Which rows of the screen changed, grouped into runs of adjacent rows, from the top down.
##
## Each band is `{ "top", "bottom", "left", "right", "across", "worst" }`: the first and last row in it, the
## first and last column that moved anywhere in it, how wide that span is, and the count of pixels that moved
## in its busiest single row. An image that cannot be read, or a pair that is not one screen, gives back nothing
## rather than a made-up answer.
static func bands(before: Image, after: Image) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	if not same_shape(before, after):
		return found
	var width := before.get_width()
	var height := before.get_height()
	if width <= 0 or height <= 0:
		return found
	var one: PackedByteArray = before.get_data()
	var other: PackedByteArray = after.get_data()
	if one.is_empty() or other.size() != one.size():
		return found
	# How many bytes describe one pixel, worked out from what is there rather than assumed from a format: every
	# format an `Image` can be in stores its pixels contiguously, so the division is exact for all of them.
	var stride := int(one.size() / float(width * height))
	if stride <= 0:
		return found
	var top := -1
	var bottom := -1
	var left := width
	var right := -1
	var worst := 0
	for y in height:
		var start := y * width * stride
		var moved := 0
		var first := -1
		var last := -1
		for x in width:
			if _moved(one, other, start + x * stride, stride):
				moved += 1
				if first < 0:
					first = x
				last = x
		if moved == 0:
			if top >= 0:
				found.append(_band(top, bottom, left, right, worst))
				top = -1
			continue
		if top < 0:
			top = y
			left = width
			right = -1
			worst = 0
		bottom = y
		left = mini(left, first)
		right = maxi(right, last)
		worst = maxi(worst, moved)
	if top >= 0:
		found.append(_band(top, bottom, left, right, worst))
	return found


## Whether two images are the same shape at all, which is the first thing that has to be true of two frames of
## one screen.
static func same_shape(before: Image, after: Image) -> bool:
	if before == null or after == null:
		return false
	return before.get_width() == after.get_width() and before.get_height() == after.get_height()


## One band as a person reads it: the rows that moved, the columns they moved in, and how much of any one row.
static func sentence(band: Dictionary) -> String:
	var rows := "row %d" % band["top"]
	if int(band["bottom"]) != int(band["top"]):
		rows = "rows %d..%d" % [band["top"], band["bottom"]]
	return (
		"%s moved, at columns %d..%d, and at its widest %d px in one row"
		% [rows, band["left"], band["right"], band["worst"]]
	)


## How much of a screen moved across every band, as a fraction of its height: one number for whether a screen
## is holding still rather than four figures of rows.
static func moved_share(found: Array, height: int) -> float:
	if height <= 0:
		return 0.0
	var rows := 0
	for band: Dictionary in found:
		rows += int(band["bottom"]) - int(band["top"]) + 1
	return float(rows) / float(height)


## One pixel's worth of bytes, differing anywhere in it - the channels are not looked at one by one, because
## every way a pixel can differ is a change to that pixel.
static func _moved(one: PackedByteArray, other: PackedByteArray, at: int, stride: int) -> bool:
	for index in stride:
		if one[at + index] != other[at + index]:
			return true
	return false


static func _band(top: int, bottom: int, left: int, right: int, worst: int) -> Dictionary:
	return { "top": top, "bottom": bottom, "left": left, "right": right, "across": right - left + 1, "worst": worst }
