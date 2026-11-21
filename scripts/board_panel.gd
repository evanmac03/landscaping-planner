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
## must draw what it always drew. That means the wrapper still grows to its page's minimum - which is why the
## four long panels (keys, water, light, hatch) overflow the room on a desk exactly as they always have - and
## still centres it. Both behaviours are the same two lines of arithmetic here, chosen by `along_the_foot`,
## rather than two kinds of node that could disagree about a panel.

## Which way up the page stands in the room this wrapper was given. A desk centres it; a finger stands it along
## the foot, with the band's own foot for the page's foot.
@export var along_the_foot: bool = false


func _notification(what: int) -> void:
	# **The wrapper's own resize is the ordinary way a page is put in place**, because that is what sets the room
	# a band is: the HUD moves this node's anchors, the layout gives it a size, and the page follows. The HUD also
	# calls `place_the_page` itself where it needs the answer in the frame it asked for it.
	if what == NOTIFICATION_RESIZED:
		place_the_page()


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
	var wanted: Vector2 = page.get_combined_minimum_size()
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
	page.position = Vector2(across, down)
	page.size = standing


## The page this wrapper holds, by the name every panel builder in `hud.gd` gives it.
func the_page() -> Control:
	return get_node_or_null(^"Page") as Control
