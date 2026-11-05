extends Node
## The arithmetic that turns "a thumb needs five and a half millimetres" into a number of layout
## pixels, and the rule that a computer is given nothing at all.
##
## The densities below are the phone this was written for: 2340 by 1080, drawn at 1.2 by the window and
## then 1.35 by the phone's own scale - 1.62 in all, so the canvas is 1444 px across. When that phone was
## finally measured it reported 450 dots to the inch rather than the 384.6 assumed here; the arithmetic
## reads whatever the device says, so these numbers only fix what the tests are exercised at. That is why
## a 29-pixel palette row is 2.3 mm across on a computer and a row of 61 is 5.5 mm on the phone.

const PhoneHudScript := preload("res://scripts/phone_hud.gd")
const PhoneFilesScript := preload("res://scripts/phone_files.gd")

## The phone: its density, and the scale its canvas ends up drawn at.
const PHONE_DPI := 384.6
const PHONE_SCALE := 1.62


func _reset() -> void:
	PhoneFilesScript.force(PhoneFilesScript.Device.AUTO)


## A length in millimetres, worked out through the density and back, is the length it started as - which
## is the only thing that makes the two conversions below trustworthy.
func test_a_length_in_millimetres_survives_the_round_trip_through_a_layout() -> void:
	_reset()
	for mm: float in [1.0, 5.5, 12.0]:
		var logical: float = PhoneHudScript.logical_for_mm(mm, PHONE_SCALE, PHONE_DPI)
		var back: float = PhoneHudScript.millimetres(logical, PHONE_SCALE, PHONE_DPI)
		assert(is_equal_approx(back, mm), "%s mm came back as %s mm" % [mm, back])


## A density the platform will not state is not a density of zero: nothing is worked out from it, and
## nothing is given a size worked out from nothing.
func test_a_density_nobody_can_state_works_nothing_out() -> void:
	_reset()
	PhoneFilesScript.force(PhoneFilesScript.Device.PHONE)
	assert(PhoneHudScript.millimetres(50.0, PHONE_SCALE, 0.0) == 0.0, "no density, no millimetres")
	assert(PhoneHudScript.logical_for_mm(5.5, PHONE_SCALE, 0.0) == 0.0, "and no layout length either")
	assert(PhoneHudScript.row_height(PHONE_SCALE, 0.0) == 0.0, "so no row height is imposed")
	assert(PhoneHudScript.font_size(PHONE_SCALE, 0.0) == 0, "and no font size")
	assert(PhoneHudScript.millimetres(50.0, 0.0, PHONE_DPI) == 0.0, "a scale of nothing is nothing too")


## On a phone a row of answers is as tall as a thumb needs, which is what the constant states and what
## the conversion has to deliver.
func test_on_a_phone_a_row_is_what_a_thumb_needs() -> void:
	_reset()
	PhoneFilesScript.force(PhoneFilesScript.Device.PHONE)
	var height: float = PhoneHudScript.row_height(PHONE_SCALE, PHONE_DPI)
	var measured: float = PhoneHudScript.millimetres(height, PHONE_SCALE, PHONE_DPI)
	assert(
		is_equal_approx(measured, PhoneHudScript.TOUCH_MM),
		"a row of %.1f px comes to %.2f mm, not %.2f" % [height, measured, PhoneHudScript.TOUCH_MM]
	)
	assert(height > 29.0, "and it is taller than the row a desk was drawn with: %.1f px" % height)


## On a computer no minimum of this module's is imposed at all: the HUD's own layout is the layout a
## desk was drawn for, and this feature has no business moving it.
func test_on_a_computer_nothing_is_imposed() -> void:
	_reset()
	PhoneFilesScript.force(PhoneFilesScript.Device.COMPUTER)
	assert(PhoneHudScript.row_height(PHONE_SCALE, PHONE_DPI) == 0.0, "no row height")
	assert(PhoneHudScript.font_size(PHONE_SCALE, PHONE_DPI) == 0, "no font size")
	var button: Button = Button.new()
	button.custom_minimum_size = Vector2(170.0, 0.0)
	PhoneHudScript.size_for_a_finger(button, PHONE_SCALE, PHONE_DPI)
	assert(button.custom_minimum_size == Vector2(170.0, 0.0), "and the control is as the layout left it")
	assert(not button.has_theme_font_size_override("font_size"), "with no font of its own")
	button.free()


## The font a phone gets draws a capital at least as tall as the text has to be read at - measured as
## the capital, because that is the part of a letter the eye actually reads.
func test_the_font_a_phone_gets_reads_a_capital_at_the_text_size() -> void:
	_reset()
	PhoneFilesScript.force(PhoneFilesScript.Device.PHONE)
	var size: int = PhoneHudScript.font_size(PHONE_SCALE, PHONE_DPI)
	var capital: float = PhoneHudScript.millimetres(
		float(size) * PhoneHudScript.CAP_RATIO, PHONE_SCALE, PHONE_DPI
	)
	assert(size > 12, "bigger than the twelve-pixel text a desk gets: %d" % size)
	assert(
		capital >= PhoneHudScript.TEXT_MM - 0.001,
		"a capital of %.2f mm is short of the %.2f mm it has to read at" % [
			capital, PhoneHudScript.TEXT_MM,
		]
	)


## A control is given the row and the text, and keeps the width its own layout chose.
func test_a_control_keeps_its_width_and_gains_the_row_and_the_text() -> void:
	_reset()
	PhoneFilesScript.force(PhoneFilesScript.Device.PHONE)
	var button: Button = Button.new()
	button.custom_minimum_size = Vector2(170.0, 0.0)
	PhoneHudScript.size_for_a_finger(button, PHONE_SCALE, PHONE_DPI)
	assert(button.custom_minimum_size.x == 170.0, "the width is the palette's own business")
	assert(button.custom_minimum_size.y > 0.0, "and the height is the thumb's")
	assert(
		button.get_theme_font_size("font_size") == PhoneHudScript.font_size(PHONE_SCALE, PHONE_DPI),
		"and the text is the size a phone is told"
	)
	button.free()


## The scale is applied to the window on a phone, and a computer's window is left exactly as it was.
func test_the_canvas_is_drawn_up_on_a_phone_and_left_alone_on_a_computer() -> void:
	_reset()
	var window: Window = Window.new()
	PhoneFilesScript.force(PhoneFilesScript.Device.COMPUTER)
	PhoneHudScript.apply(window)
	assert(window.content_scale_factor == 1.0, "a computer's window is not scaled by this program")
	PhoneFilesScript.force(PhoneFilesScript.Device.PHONE)
	PhoneHudScript.apply(window)
	assert(
		is_equal_approx(window.content_scale_factor, PhoneHudScript.UI_SCALE),
		"a phone draws the canvas at %.2f" % window.content_scale_factor
	)
	window.free()


## A window nobody can measure is not a scale to work from.
func test_a_window_nobody_can_measure_is_not_a_scale() -> void:
	_reset()
	assert(PhoneHudScript.canvas_scale(null) == 0.0, "there is no window, so there is no scale")


## Six short words are one row on a computer and two rows of three at a finger's size - the phone's own
## numbers, where a cell is 50 px on the desk and about 100 px once the words are 26 px tall.
func test_a_row_of_six_edit_words_needs_two_rows_of_three_at_a_thumbs_size() -> void:
	var desk: Array = []
	var phone: Array = []
	for _i: int in 6:
		desk.append(50.0)
		phone.append(100.0)
	assert(
		PhoneHudScript.columns_that_fit(desk, 6, 368.0, 4.0, 3) == 6,
		"a computer's six still fit the 368 px the panel leaves them"
	)
	assert(
		PhoneHudScript.columns_that_fit(phone, 6, 368.0, 4.0, 3) == 3,
		"a phone's six do not, and three of them still do"
	)


## A palette squeezed narrower than its tools grid is a list, and a list is not a palette.
func test_a_row_is_never_squeezed_below_the_palettes_own_column_count() -> void:
	assert(
		PhoneHudScript.columns_that_fit([300.0, 300.0], 6, 368.0, 4.0, 3) == 3,
		"two cells of 300 px do not fit, and three columns is the narrowest allowed"
	)


## A panel nobody has laid out yet reports no room, and no room worked out is not a reason to re-flow.
func test_no_room_worked_out_leaves_the_row_as_it_was_built() -> void:
	assert(
		PhoneHudScript.columns_that_fit([100.0], 6, 0.0, 4.0, 3) == 6,
		"a panel that has been given no room at all is not a measurement"
	)
	assert(
		PhoneHudScript.columns_that_fit([], 6, 368.0, 4.0, 3) == 6,
		"a row with no cells in it is not re-flowed either"
	)


## A button whose font has just changed still answers its old width when asked for its minimum size, so
## the width is worked out from the words and the frame instead.
func test_a_button_is_measured_by_its_words_not_by_the_size_it_had_before() -> void:
	var made := Button.new()
	made.text = "Offset (0)"
	var before: float = PhoneHudScript.button_width(made)
	assert(before > 0.0, "a button with words on it has a width")
	made.add_theme_font_size_override("font_size", made.get_theme_font_size("font_size") * 2)
	var after: float = PhoneHudScript.button_width(made)
	assert(after > before, "twice the type is wider: %.1f against %.1f" % [after, before])
	made.free()
