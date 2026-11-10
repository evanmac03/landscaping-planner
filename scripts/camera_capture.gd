class_name CameraCapture
extends RefCounted
## Whether this device can take a photograph, which camera to use, and why there is nothing to show.
##
## A camera is four separate refusals away from a picture, and each of them has to be told apart from the
## others, because they are four different things for a person to do: this device has no camera at all;
## this program was not allowed it; the camera is allowed but has not answered yet; and the frame could not
## be written. A page that showed a black rectangle for all four would be a page nobody can use.
##
## The device's own answers are arguments, never assumptions, so every decision below can be held down by a
## test on the day the machine it is running on has neither a camera nor a permission to ask for.

## The permission Android gates the camera behind, spelled the way the platform spells it.
const ANDROID_CAMERA := "android.permission.CAMERA"

## Where a frame is written before it is kept. `FieldPhotoStore.add` takes a *path*, sniffs the format and
## hashes the bytes to name the file it keeps, so the frame has to land somewhere first - and this is the
## one place it does, under `user://` so nothing outside the program can take it away mid-write.
const FRAME_PATH := "user://camera_frame.png"


## Whether there is a picture to be had here.
static func usable(feed_count: int, permission_granted: bool) -> bool:
	return feed_count > 0 and permission_granted


## What to tell a person about a camera that cannot be used, in a sentence naming what is missing. Empty
## when there is nothing wrong.
##
## The permission comes first even when there are no feeds yet, because "no camera" on a phone whose camera
## has not been allowed is a lie about the device: the feeds only appear *after* the permission is granted,
## so the honest answer for a phone nobody has asked is about the permission.
static func refusal(feed_count: int, permission_granted: bool) -> String:
	if not permission_granted:
		return "This program has not been allowed the camera. Say yes to the camera when the phone asks."
	if feed_count <= 0:
		return "This device has no camera, or the camera has not answered yet."
	return ""


## Which feed to show, out of the positions the device reports: the back camera when there is one, because
## that is the one pointed at the plant, and otherwise the first.
##
## The position to prefer is an argument rather than `CameraFeed.FEED_BACK`, so this file does not have to
## guess at an enum and a test does not have to know it either.
static func choose(positions: Array, back: int) -> int:
	if positions.is_empty():
		return -1
	for i: int in positions.size():
		if int(positions[i]) == back:
			return i
	return 0


## What to call the camera in use, for a line that says which one is showing.
static func position_word(position: int, back: int, front: int) -> String:
	if position == back:
		return "the back camera"
	if position == front:
		return "the front camera"
	return "a camera"


## How many textures a feed needs to be drawn, and none at all when it has no picture to give yet.
##
## The three shapes are the device's, not this program's. A feed that arrives as a picture is one texture
## drawn as it is; one that carries brightness in red and colour in green and blue - which is what an
## Android camera hands over - is also one texture, but it has to be *decoded* before it is drawn, or the
## colour is shown as if it were brightness and a plant comes out a magenta cloud; and one that hands the
## two over in separate textures is two.
static func planes_for(datatype: int, rgb: int, ycbcr: int, ycbcr_separated: int) -> int:
	if datatype == rgb or datatype == ycbcr:
		return 1
	if datatype == ycbcr_separated:
		return 2
	return 0


## How big a picture is once it has been given a count of quarter turns.
##
## One turn or three swap its sides and two leaves them as they were, which is the whole of what a rectangle
## needs to know when the phone has been turned: a rectangle cannot keep the proportions of a picture that is
## being turned on its own, so it is told what shape the picture has come out.
static func turned_size(picture: Vector2, quarter_turns: int) -> Vector2:
	if absi(quarter_turns) % 2 == 1:
		return Vector2(picture.y, picture.x)
	return picture


## How much of a turned picture a rectangle covers, so that the picture fills the rectangle while keeping its
## own proportions: all of it apiece when they already agree, less than all of it on the axis where the
## picture runs past the rectangle, and never more than all of it - a rectangle is filled by the middle of the
## picture rather than by a stretched one.
static func cover_scale(turned: Vector2, rect: Vector2) -> Vector2:
	if turned.x <= 0.0 or turned.y <= 0.0 or rect.x <= 0.0 or rect.y <= 0.0:
		return Vector2.ONE
	var grown: float = maxf(rect.x / turned.x, rect.y / turned.y)
	return Vector2(rect.x / (turned.x * grown), rect.y / (turned.y * grown))


## Whether the texture has to be put back together by a shader rather than drawn as it stands.
static func needs_decoding(datatype: int, rgb: int) -> bool:
	return datatype != rgb


## Whether the frame has to be read as brightness in one texture and colour in another, whatever shape the
## device says it is handing over.
##
## On a machine with a rendering device the engine puts a camera's frame together for us and only the shapes
## that are genuinely split need a shader - which is what `needs_decoding` answers. The renderer this program
## draws with everywhere, including on a phone, does *not*, and it does not say so in the frame: measured on
## the glass, the picture arrives in red with green and blue at exactly zero across a third of a million
## pixels, which drawn as it stands is a crimson rectangle with a legible silhouette in it. So there, every
## frame is read the way the camera really made it - brightness in one place, colour in the other.
##
## The machine's own answer is an argument, never an assumption, which is what lets this be held down by a
## test on a computer that has a camera and a rendering device both.
static func reads_apart(has_rendering_device: bool, datatype: int, ycbcr_separated: int) -> bool:
	if not has_rendering_device:
		return true
	return datatype == ycbcr_separated


## How the device is handing the picture over, in the words the page shows beside which camera it is.
##
## This is on the page because it was needed on the glass: the two ways a camera can hand a picture over need
## *different* shaders - one texture carrying brightness and colour together, or two carrying them apart - and
## a page that shows a red or magenta rectangle with no way to tell which case it is in has nothing to say
## about what went wrong. Four states, four sentences, and nothing invented when the feed has not answered.
static func datatype_word(datatype: int, rgb: int, ycbcr: int, ycbcr_separated: int) -> String:
	if datatype == rgb:
		return "a picture as it comes"
	if datatype == ycbcr:
		return "brightness and colour together"
	if datatype == ycbcr_separated:
		return "brightness and colour apart"
	return "a picture that has not arrived yet"


## The part of a drawn frame to keep, given where the live picture sits in the layout.
##
## A page's rectangle is in layout pixels and a viewport's image is in the pixels the frame is actually
## drawn at, which differ by the scale the canvas is drawn up by. Rounded *out* rather than in, so the
## picture is never a hair smaller than the rectangle it was asked for, and never empty.
static func frame_region(rect: Rect2, drawn_at: float) -> Rect2i:
	var factor: float = drawn_at if drawn_at > 0.0 else 1.0
	var left: int = int(floorf(rect.position.x * factor))
	var top: int = int(floorf(rect.position.y * factor))
	var right: int = int(ceilf((rect.position.x + rect.size.x) * factor))
	var bottom: int = int(ceilf((rect.position.y + rect.size.y) * factor))
	return Rect2i(left, top, maxi(right - left, 1), maxi(bottom - top, 1))