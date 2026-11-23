class_name BoardPanel
extends Control
## The wrapper a panel that stands over the drawing is held in, so the HUD can move the panel without touching
## what is inside it: centred over the work on a desk, standing along the foot of the screen on a finger.
##
## **The engine's `CenterContainer` does the first and cannot be asked for the second**, and the readings that
## sent this file into being are worth keeping. A desk centres these panels over the board, which is right - a
## desk's room is wide and a 520 px panel leaves the work visible either side. A finger's room is a hand's width,
## so the same panel centred lands squarely over the one place a person is looking. The band along the foot was
## therefore asked for, and the band came out **exactly right** - measured at a finger's type,
## `SiteReportPanel`'s wrapper stood at `205..610` - while its 257 px page stayed at `603..870`: 398 px down a
## 405 px band, which is the panel's *desk* position to the pixel. Asking the container to sort itself again
## (`queue_sort`) said the same. **So the band moved and the panel did not, and a container that only centres
## carries no lever to ask it harder.**
##
## **This node places its page itself, on a rectangle it works out**, and that is the whole of the change. It
## extends `Control` rather than `Container` on purpose: a `Container` adds its children's minimum to its own, so
## a wrapper around a page taller than the room grows past the room however its anchors are set - measured, the
## keys wrapper came out `0..4208` in a 900 px room - and no container that inherits that rule can be a band.
## Here the minimum is one of the two things `place_the_page` decides, so the room is kept and the page is put
## in it.
##
## **The rectangle the page is given is the page's own size** - `get_combined_minimum_size`, the engine's own
## answer to "how big does this want to be" - and never a share of the room. A panel that fits is a short panel,
## as a desk draws it, and a page stretched to the room would be a second arrangement for the desk to disagree
## with. Only *where* it stands changes.
##
## **On a desk this node is the `CenterContainer` it replaced, to the pixel**, and that is deliberate: the desk
## must draw what it always drew. That means the wrapper still grows to what its page wants and still centres it,
## so a page genuinely taller than the room grows past it, as it always has. None of the eight panels it holds are
## taller than the room any more, though: each of their pages now counts the contents of its scroller, and the
## tallest of them is 618 px in a 900 px room. Both behaviours are the same few lines of arithmetic here, chosen
## by `along_the_foot`, rather than two kinds of node that could disagree about a panel.

## Which way up the page stands in the room this wrapper was given. A desk centres it; a finger stands it along
## the foot, with the band's own foot for the page's foot.
@export var along_the_foot: bool = false

## Where the page was last put - its rectangle, so both the size and the offset are in the record - and the room
## it was given. See the guard in `place_the_page`.
var _placed: Rect2 = Rect2(-1.0, -1.0, -1.0, -1.0)
var _placed_in: Vector2 = Vector2(-1.0, -1.0)


func _notification(what: int) -> void:
	# **The wrapper's own resize is the ordinary way a page is put in place**, because that is what sets the room
	# a band is: the HUD moves this node's anchors, the layout gives it a size, and the page follows. The HUD also
	# calls `place_the_page` itself where it needs the answer in the frame it asked for it.
	if what == NOTIFICATION_RESIZED:
		place_the_page()
	# **And the contents are watched, because what they want grows after the page is first placed.** A wrapped
	# caption's minimum height is only known once it has been given a width, and that is one layout pass *after*
	# this node has already placed the page: measured 2026-11-24, the site report's page was placed 85 px tall
	# while its column went on wanting 319. So the thing inside the scroller says when it has changed shape, and
	# `place_the_page`'s guard is what keeps that from being a loop.
	if what == NOTIFICATION_READY:
		var contents: Control = the_pages_contents()
		if contents != null and not contents.resized.is_connected(place_the_page):
			contents.resized.connect(place_the_page)


## Put the page in this wrapper's room, at its own size, where `along_the_foot` says.
func place_the_page() -> void:
	var page: Control = the_page()
	if page == null:
		return
	# **No connection to the page's own `resized`, and that is a measured decision rather than an omission.** It
	# was tried, to keep a desk's wrapper in step with a page that grows its own mind, and it ran away: placing the
	# page sets its size, which fires `resized`, which places it again - and the desk's keys wrapper came out
	# `0..17934` in a 900 px room with the check naming four real clashes against the bar and the foot line. What a
	# *band* needs it and has: `Hud._place_the_overlay_panels` runs whenever the type changes and asks for the
	# placement again, so a band follows a page that grows. A desk's wrapper is read once at the desk's own type and
	# does not change, so there is nothing left to follow.
	var wanted: Vector2 = wanted_by_the_page(page)
	# **A band takes the room it is given; a desk's wrapper is a box around its page and grows to it.** The second
	# is what this node replaced, and the `custom_minimum_size` is stated rather than left to the default so the
	# desk's own behaviour is visible here instead of inherited from a node that is no longer used.
	custom_minimum_size = Vector2.ZERO if along_the_foot else wanted
	var room: Vector2 = size
	# **A finger's page never stands taller than the room it was given, and this is the clamp that was missing.**
	# The rectangle below was the page's minimum and never a share of the room, so a page wanting more than the room
	# stood at a negative offset and hung past the foot: measured with `phone_touch_sweep` at the A16W's numbers,
	# `SiteReportPanel`'s column came out **129 px past the foot of a 1185x666 room with its own `CloseReport` button
	# off the screen altogether** - the only way out of the panel, and a finger could not reach it. The desk is
	# untouched by this: `along_the_foot` is false there, so `standing` is `wanted` to the pixel.
	#
	# **This clamp is half of one change and is worse than nothing on its own.** Capped without something to reach
	# the rest, the column is *clipped* rather than overflowing - the button still unreachable and now invisible too.
	# Each long panel's column therefore sits inside a `ScrollContainer`, which is the palette's own wrapper.
	var standing: Vector2 = Vector2(wanted.x, minf(wanted.y, room.y)) if along_the_foot else wanted
	var across: float = (room.x - standing.x) * 0.5
	var down: float = room.y - standing.y if along_the_foot else (room.y - standing.y) * 0.5
	var place: Vector2 = Vector2(across, down)
	# **The guard the first attempt at following the contents did not have, and the reason it is here.** Placing
	# the page *sizes* it, which fires `resized` all through what it holds, so a rule that follows a content's
	# resize without this places for ever: the measured runaway was the keys wrapper at `0..17934` in a 900 px
	# room, with four named clashes. Nothing to do means nothing done - the page already standing where this
	# placement would put it, at the size this placement would give it, in the room it was given.
	#
	# **The page's offset is in the record and not only its size**, because *where* a page stands is decided by
	# `along_the_foot`: a wrapper placed as a desk and then asked to stand along the foot puts the page at a
	# different offset for the very same size, and a record of size alone would skip it. Found by
	# `test_a_finger_stands_the_page_along_the_foot` on 2026-11-24, where the page stayed at its desk offset and
	# its foot came out 331 px down a 405 px band.
	if Rect2(place, standing) == _placed and room == _placed_in:
		return
	_placed = Rect2(place, standing)
	_placed_in = room
	page.position = place
	page.size = standing


## The page this wrapper holds, by the name every panel builder in `hud.gd` gives it.
func the_page() -> Control:
	return get_node_or_null(^"Page") as Control


## **What the page wants to be, which is its own minimum plus what its scroller is holding.**
##
## A page's own minimum is the honest answer for a page, and it is the wrong one for the eight panels this holds:
## all of them put their contents inside a `ScrollContainer` (`Page/Scroll`, with the `Column` inside it - the name
## every panel builder gives them), and **a `ScrollContainer` reports a minimum height of 0**, because that is
## exactly what makes it a scroller. So the page's minimum is its own frame and nothing else: measured 2026-11-24
## the site report's page stood **18 px** tall - the `PanelContainer`'s own margins - with its column 319 px below
## the fold, and the desk drew a sliver of a panel that scrolled. Four of these panels were in that state, which
## is what `gui_sweep`'s `crowded` lines named: the site report cut down by 319 px, hatch by 278, dxf and landxml
## by 120, and each of them with 432 px to give.
##
## A page with no scroller is untouched - its minimum is already the truth - and a page whose contents want more
## than the room keeps its scroll, which is what the scroller is for.
func wanted_by_the_page(page: Control) -> Vector2:
	if page == null:
		return Vector2.ZERO
	var frame: Vector2 = page.get_combined_minimum_size()
	var contents: Control = the_pages_contents()
	if contents == null:
		return frame
	return Vector2(frame.x, frame.y + contents.get_combined_minimum_size().y)


## The thing a page's scroller is holding, or null where the page has no scroller to hold anything.
func the_pages_contents() -> Control:
	var scroll: Control = get_node_or_null(^"Page/Scroll") as Control
	if scroll == null:
		return null
	for child: Node in scroll.get_children():
		var contents: Control = child as Control
		if contents != null:
			return contents
	return null
