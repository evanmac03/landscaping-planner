extends Node
## The window size class: how big a window is, in the unit Android states a size in, and where the breakpoints
## between one class and the next are.
##
## This replaces a screen *diagonal* with a table. `TouchInput.needs_zooming` used to answer "is this canvas
## worth drawing up?" by comparing a screen's long side against seven inches, which is the right answer bought
## with the wrong unit: what has no room on a phone held sideways is its *height*, not its width, and the two
## real devices below are the whole argument - the phone is 832 dp across and 384 down.

const WindowClassScript := preload("res://scripts/window_class.gd")
const PhoneHudScript := preload("res://scripts/phone_hud.gd")


## Every breakpoint is where Material puts it, and each is a floor: a window of exactly that many dp has
## reached the class it names. Asserted so that a number changed by accident is a test that fails rather than
## a window in the wrong class.
func test_the_breakpoints_are_the_ones_material_states() -> void:
	assert(WindowClassScript.class_for(0.1) == WindowClassScript.COMPACT, "an inch of window is compact")
	assert(WindowClassScript.class_for(599.0) == WindowClassScript.COMPACT, "and so is 599 dp")
	assert(WindowClassScript.class_for(600.0) == WindowClassScript.MEDIUM, "600 dp has reached medium")
	assert(WindowClassScript.class_for(839.0) == WindowClassScript.MEDIUM, "and 839 is still medium")
	assert(WindowClassScript.class_for(840.0) == WindowClassScript.EXPANDED, "840 dp has reached expanded")
	assert(WindowClassScript.class_for(1200.0) == WindowClassScript.LARGE, "1200 dp has reached large")
	assert(WindowClassScript.class_for(1600.0) == WindowClassScript.EXTRA_LARGE, "1600 dp is extra-large")


## A length nobody could read is **no class at all** rather than the smallest one: "this window is compact" is
## an answer about a window, and a number that does not exist is not one.
func test_a_length_nobody_could_read_has_no_class() -> void:
	assert(WindowClassScript.class_for(0.0) == &"", "nought dp is not a class")
	assert(WindowClassScript.class_for(-40.0) == &"", "and neither is a negative one")
	assert(not WindowClassScript.is_small(Vector2i.ZERO, 1.0, 384.6), "so no window is called small for it")
	assert(not WindowClassScript.is_small(Vector2i(1080, 2340), 0.0, 384.6), "with no scale to read it at")
	assert(not WindowClassScript.is_small(Vector2i(1080, 2340), 1.0, 0.0), "and with no density")


## The two devices this program is aimed at, in dp. **The phone is not a phone by its width**: 832 dp across is
## a medium window, which is why the class is taken from the shorter side. Its 384 dp of height is what has no
## room, and that is what says the canvas is worth drawing up.
func test_a_phone_is_compact_by_its_height_and_a_tablet_is_not_compact_at_all() -> void:
	var phone := Vector2i(2340, 1080)
	var phone_dp: Vector2 = WindowClassScript.dp_for(phone, 1.0, 450.0)
	assert(is_equal_approx(phone_dp.x, 832.0), "the phone is 832 dp across: %.0f" % phone_dp.x)
	assert(is_equal_approx(phone_dp.y, 384.0), "and 384 dp down: %.0f" % phone_dp.y)
	assert(WindowClassScript.is_small(phone, 1.0, 450.0), "so it is drawn up, on its height")

	var tablet := Vector2i(2560, 1600)
	var tablet_dp: Vector2 = WindowClassScript.dp_for(tablet, 1.0, 300.0)
	assert(is_equal_approx(tablet_dp.x, 1365.333), "the tablet is 1365 dp across: %.3f" % tablet_dp.x)
	assert(is_equal_approx(tablet_dp.y, 853.333), "and 853 dp down: %.3f" % tablet_dp.y)
	assert(not WindowClassScript.is_small(tablet, 1.0, 300.0), "so it is not drawn up - every side has room")
	assert(WindowClassScript.of(tablet, 1.0, 300.0) == WindowClassScript.EXPANDED, "and its class is expanded")


## The phone this program was measured on reports its screen in the pixels it really has, while a viewport
## reports a canvas the window draws *up*, so the same room arrives at two different scales. Both are dp by
## the same arithmetic, which is held here to the one place this project converts a length - `PhoneHud`.
func test_a_room_becomes_dp_by_the_same_arithmetic_that_makes_millimetres() -> void:
	var room := Vector2i(1185, 666)
	var scale: float = 1.35
	var density: float = 384.6
	var dp: Vector2 = WindowClassScript.dp_for(room, scale, density)
	var from_mm: Vector2 = Vector2(
		PhoneHudScript.millimetres(float(room.x), scale, density) * 160.0 / 25.4,
		PhoneHudScript.millimetres(float(room.y), scale, density) * 160.0 / 25.4,
	)
	assert(is_equal_approx(dp.x, from_mm.x), "the same length in dp: %.3f against %.3f" % [dp.x, from_mm.x])
	assert(is_equal_approx(dp.y, from_mm.y), "across and down: %.3f against %.3f" % [dp.y, from_mm.y])
