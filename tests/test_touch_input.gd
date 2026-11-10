extends Node
## Whether a device is answered with a finger, and the two ways the answer is "no".
##
## The densities below are the devices this was written for: a phone at 450 dots to the inch, a tablet at
## 300, a touchscreen laptop at 150 and a desk monitor at 96. The row being measured is the desk's own
## palette row, `TouchInput.DESK_ROW_PX`, so the question each test asks is the real one: on this screen,
## is the row this program already draws a thumb's target or a mouse's?

const TouchInputScript := preload("res://scripts/touch_input.gd")
const PhoneHudScript := preload("res://scripts/phone_hud.gd")


## Every test starts from "answer for the machine this is running on", so one test cannot lend another
## its device.
func _reset() -> void:
	TouchInputScript.force(TouchInputScript.Answer.AUTO)


## The phone this whole feature was measured on: 450 dots to the inch, and a 29 px row is 1.6 mm there.
func test_a_phones_row_is_a_thumbs_target() -> void:
	_reset()
	var row_mm: float = PhoneHudScript.millimetres(TouchInputScript.DESK_ROW_PX, 1.0, 450.0)
	assert(
		TouchInputScript.answered_by_a_thumb(true, 450.0, row_mm),
		"a %.2f mm row is a thumb's target" % row_mm
	)


## A tablet is the device this was widened for: a finger's target, and a screen held rather than sat at.
func test_a_tablets_row_is_a_thumbs_target_too() -> void:
	_reset()
	var row_mm: float = PhoneHudScript.millimetres(TouchInputScript.DESK_ROW_PX, 1.0, 300.0)
	assert(
		TouchInputScript.answered_by_a_thumb(true, 300.0, row_mm),
		"a %.2f mm row on a tablet is a thumb's target" % row_mm
	)


## This desk's own monitor reports a touchscreen and 144 dots to the inch, and it is still a desk: being
## touched does not make a screen something you hold.
func test_a_touchscreen_desk_is_still_a_desk() -> void:
	_reset()
	var row_mm: float = PhoneHudScript.millimetres(TouchInputScript.DESK_ROW_PX, 1.0, 144.0)
	assert(
		not TouchInputScript.answered_by_a_thumb(true, 144.0, row_mm),
		"a %.2f mm row on a 144 dpi screen is a mouse's, touchscreen or not" % row_mm
	)
	var coarse: float = PhoneHudScript.millimetres(TouchInputScript.DESK_ROW_PX, 1.0, 96.0)
	assert(
		not TouchInputScript.answered_by_a_thumb(true, 96.0, coarse),
		"and a 96 dpi screen is further still from being held"
	)


## A dense touchscreen laptop is between the two, and is a laptop: it has a trackpad, and the layout it was
## bought for is the desk's until somebody states otherwise.
func test_a_plain_touchscreen_laptop_keeps_the_desk_layout() -> void:
	_reset()
	var row_mm: float = PhoneHudScript.millimetres(TouchInputScript.DESK_ROW_PX, 1.0, 150.0)
	assert(
		not TouchInputScript.answered_by_a_thumb(true, 150.0, row_mm),
		"a %.2f mm row on a 150 dpi screen is a laptop's" % row_mm
	)


## No touchscreen is a desk however dense the screen is - a 4K panel held to a plate of glass is not a
## phone.
func test_no_touchscreen_is_a_desk_however_dense_the_screen() -> void:
	_reset()
	var row_mm: float = PhoneHudScript.millimetres(TouchInputScript.DESK_ROW_PX, 1.0, 450.0)
	assert(
		not TouchInputScript.answered_by_a_thumb(false, 450.0, row_mm),
		"nothing to touch, nothing to size for"
	)


## A density that could not be read resizes nothing: the layout keeps the size it was built at rather than
## a size worked out from a number that does not exist.
func test_a_density_nobody_could_read_resizes_nothing() -> void:
	_reset()
	assert(
		not TouchInputScript.answered_by_a_thumb(true, 0.0, 0.0),
		"no millimetres worked out is not a small row"
	)
	assert(
		not TouchInputScript.answered_by_a_thumb(true, 450.0, 1.6, 0.0),
		"and a thumb of no size is not a measurement either"
	)


## The door a demonstration or a test uses answers for the device it was told, and `AUTO` puts the real
## machine's own reading back.
func test_the_force_door_answers_for_a_device_and_auto_reads_the_machine() -> void:
	_reset()
	TouchInputScript.force(TouchInputScript.Answer.FINGER)
	assert(TouchInputScript.has_a_touchscreen(), "a forced finger is a touchscreen")
	TouchInputScript.force(TouchInputScript.Answer.MOUSE)
	assert(not TouchInputScript.has_a_touchscreen(), "and a forced mouse is not")
	TouchInputScript.force(TouchInputScript.Answer.AUTO)
	assert(
		TouchInputScript.has_a_touchscreen()
			== DisplayServer.is_touchscreen_available(),
		"asking the machine is what auto does"
	)
	_reset()


## A phone is drawn up as well as sized: its 2340 px across is 5.2 inches at 450 dots to the inch, and at
## that width the canvas has to give something up to the panels.
func test_a_phone_is_drawn_up_and_a_tablet_is_not() -> void:
	_reset()
	var phone: float = 2340.0 / 450.0
	var tablet: float = 2560.0 / 300.0
	assert(TouchInputScript.needs_zooming(phone), "a %.1f inch wide screen is drawn up" % phone)
	assert(not TouchInputScript.needs_zooming(tablet), "a %.1f inch wide one is not" % tablet)


## A screen nobody could measure is not drawn up: the canvas keeps the scale it already has rather than one
## worked out from a number that does not exist.
func test_a_screen_nobody_could_measure_is_not_drawn_up() -> void:
	_reset()
	assert(not TouchInputScript.needs_zooming(0.0), "no inches worked out is not a small screen")
	assert(not TouchInputScript.needs_zooming(5.2, 0.0), "and a threshold of nothing is not one either")
