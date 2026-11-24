@tool
extends Control
## The glass's own corners and bands, drawn over the phone's furniture in the 2D workspace - **the shape a person
## looks at, beside the numbers a person reads.**
##
## **What this is, and what it is not.** `tools/phone_workspace.tscn` runs the whole program in a window of the
## phone's own size, which is the only way to see the arrangement the device makes. This draws the shape *around*
## `tools/touch_hud_workspace.tscn`, whose furniture is the phone's but whose room is whatever the view is. The two
## are the two halves of one question - that one is the program, this one is the outline - and neither stands for the
## other: **the room here is the view's, so what is drawn is the phone's own share of this room rather than a phone's
## pixels.**
##
## **Which way up the phone is, is the room's own answer** - a view wider than it is tall is a phone held lying, and
## one taller than it is wide is a phone held standing. That is the device's own rule, the rotation following its
## display, and asking it this way means the glass and its camera are read from `PhoneHud.MEASURED_SCREENS`, the one
## statement of what this phone is, instead of being written down a fourth time. Measured the other way first: a
## frame that stated the standing glass beside a landscape room drew a 175 px corner on a 900 px screen (the corner
## is a share of the glass's own *width*, 118 of 1080, and a landscape room is not scaled from that side) - four
## wedges twice the size a phone's corner is, which is what asking the wrong way up looks like.
##
## **Every figure is asked of `PhoneHud`, and every question asked is one that takes the device as an argument.** The
## four cuts are `corners_cut_out`'s, the bands are `cutout_insets`'s and `foot_share`'s, and the corner written in
## the band is `corner_share`'s - the same arithmetic the running program's own bar and plates are placed by, so the
## corner cut out of the glass here and the corner the bar's plate is rounded with are one figure and cannot come
## out as two curves. Nothing below states a radius, a band or a colour of the glass's own; a room a display rounds
## nothing on draws nothing at all.
##
## **The device reaches those calls as an argument rather than through the doors that read it**, which is the same
## trade `TouchFurniture.stated_density` makes and for the same measured reason: an editor hands a plain script a
## separate copy of itself with its own statics, so a device stated through `PhoneHud.force_display` by one script has
## been read back as the desk by another. It cost this frame its first afternoon - a stated 450 dpi beside a screen
## that never arrived - and the halves that take the screen are why it cannot happen again.
##
## **It is drawn in a `CanvasLayer` above the HUD's own, and the mouse passes through it.** A frame a person could
## not press through would take the furniture out of their hands, and the furniture is the point of the view it
## frames; the layer above is what makes a corner land over the bar rather than under it, which is the way round the
## display itself is.

const PhoneHudScript := preload("res://scripts/phone_hud.gd")


## Whether a room is one a phone is held lying in or standing in: **wider than it is tall is lying**, and that is the
## device's own rule rather than a choice made here. The shape's word is the one the block prints (`shape=lying`), so
## a person reading a log and a person looking at this read one vocabulary.
static func shape_for(room: Vector2i) -> String:
	return "lying" if room.x >= room.y else "standing"


## **What is drawn where the glass is not.** A display physically takes its corners away, so a person looking at this
## must see the corner cut rather than the furniture underneath it. Opaque, because it stands for the display's own
## bezel rather than for a shade drawn over the program.
const OUTSIDE := Color(0.02, 0.02, 0.025, 1.0)

## The band the camera is cut into, and the band the system keeps along the foot: a wash rather than a cut, because
## what a person needs to see there is *where the device's own furniture is*, not what is under it.
const CAMERA_WASH := Color(1.0, 0.78, 0.36, 0.2)
const FOOT_WASH := Color(0.45, 0.8, 1.0, 0.18)

## The size this was last drawn at. **The frame follows the view being resized rather than redrawing on every frame
## an editor runs**: a `@tool` control's `_draw` happens when it is asked for, and the one moment its answer can
## differ is a change of size.
var _drawn_at: Vector2 = Vector2.ZERO


## **Asked on every frame and not only once**, for the reason the workspace beside this file gives in as many words: a
## size is not known until the node has laid out, and an editor lays a scene out over the frames after it is opened. A
## guard that drew once in `_ready` would draw the frame at whatever size the node had before anybody had given it
## one - and this node's first size is read in an editor, which is where the whole view is looked at.
func _process(_delta: float) -> void:
	if size != _drawn_at:
		_drawn_at = size
		queue_redraw()
		_say_the_room(Vector2i(size))


## The glass, in the room this view has.
func _draw() -> void:
	var room := Vector2i(size)
	var glass: Vector2i = PhoneHudScript.measured_glass(shape_for(room))
	var usable: Rect2i = PhoneHudScript.measured_usable(shape_for(room))
	if glass == Vector2i.ZERO:
		return
	for cut: PackedVector2Array in PhoneHudScript.corners_cut_out(room, glass):
		draw_colored_polygon(cut, OUTSIDE)

	# **The camera is one band along one edge, and it turns with the phone**: lying, the A16W keeps the room's first
	# 62 px to its left; standing, the top 62 px. Four candidates are built and the three with no extent are nothing
	# at all, because which edge it is on is the device's answer rather than something to work out here.
	var band: Vector4i = PhoneHudScript.cutout_insets(room, glass, usable)
	for side: Dictionary in [
		{ "size": Vector2i(band.x, room.y), "at": Vector2i(0, 0) },
		{ "size": Vector2i(room.x, band.y), "at": Vector2i(0, 0) },
		{ "size": Vector2i(band.z, room.y), "at": Vector2i(room.x - band.z, 0) },
		{ "size": Vector2i(room.x, band.w), "at": Vector2i(0, room.y - band.w) },
	]:
		var extent: Vector2i = side["size"]
		if extent.x > 0 and extent.y > 0:
			draw_rect(Rect2(Vector2(side["at"]), Vector2(extent)), CAMERA_WASH, true)

	var foot: int = PhoneHudScript.foot_share(room, glass)
	if foot > 0:
		draw_rect(Rect2(Vector2(0.0, float(room.y - foot)), Vector2(float(room.x), float(foot))), FOOT_WASH, true)

	_say_the_figures(room, glass, band, foot)


## **The numbers, said in the console as well as drawn in the band.** A frame that came out invisible would otherwise
## be a silence about which figure it came out of - the shape, a band, or a device the table does not name - and this
## is the same reason the workspace beside this file prints a line on every attempt it makes.
func _say_the_room(room: Vector2i) -> void:
	var shape: String = shape_for(room)
	var glass: Vector2i = PhoneHudScript.measured_glass(shape)
	var usable: Rect2i = PhoneHudScript.measured_usable(shape)
	if glass == Vector2i.ZERO:
		print("PHONE FRAME: %s is not a shape this project has measured, so there is no glass to draw" % shape)
		return
	print(
		(
			"PHONE FRAME: a %s room of %d x %d - the glass %d x %d, camera %s, foot %d, corner %d, 4 corners cut"
			% [
				shape,
				room.x,
				room.y,
				glass.x,
				glass.y,
				str(PhoneHudScript.cutout_insets(room, glass, usable)),
				PhoneHudScript.foot_share(room, glass),
				PhoneHudScript.corner_share(room, glass),
			]
		)
	)


## The figures, written in the foot band - **the one strip of the screen the program itself keeps clear** - so that
## what is written lands where nothing is meant to be pressed, and shows by standing there where that strip is.
func _say_the_figures(room: Vector2i, glass: Vector2i, band: Vector4i, foot: int) -> void:
	var font: Font = get_theme_default_font()
	if font == null or foot <= 0:
		return
	var type_px: int = maxi(mini(int(float(foot) * 0.7), 24), 8)
	var words: String = (
		"the glass %d x %d - camera %s px of this room, foot %d, corner %d, each asked of PhoneHud for this room"
		% [glass.x, glass.y, str(band), foot, PhoneHudScript.corner_share(room, glass)]
	)
	draw_string(
		font,
		Vector2(6.0, float(room.y) - float(foot) + float(type_px)),
		words,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		type_px,
		Color(0.92, 0.95, 1.0, 0.95),
	)
