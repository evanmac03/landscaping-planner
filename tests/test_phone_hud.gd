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
const TouchInputScript := preload("res://scripts/touch_input.gd")
const PlannerHudScript := preload("res://scripts/hud.gd")

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


## The device is asked where the chrome is sized, not in `_ready`.
##
## A window that has not laid out yet does not answer for the device it will be drawn on, and the HUD's own
## pass is deferred for exactly that reason - but `call_deferred` reads its arguments where it is written, so
## handing it the reading `_ready` had just made carried an early answer into a late pass. On the phone that
## showed as a thumb-sized palette beside a foot of the screen that told that same thumb about a mouse wheel
## and W A S D. Both halves read off the glass before this was written.
func test_the_device_is_asked_where_the_chrome_is_sized_and_not_in_ready() -> void:
	var hud := PlannerHudScript.new()
	TouchInputScript.force(TouchInputScript.Answer.FINGER)
	PhoneHudScript.force_density(PHONE_DPI)
	# A HUD that never ran `_ready` still holds that early answer, which is the one a phone was actually given.
	assert(not hud.shows_touch_controls(), "the reading `_ready` took is the one that does not hold")
	# The pass that fits the chrome asks again, and everything downstream follows that single answer.
	hud._size_the_chrome_for_the_device()
	assert(hud.shows_touch_controls(), "asking where the chrome is sized gets the device right")
	# And that is the answer the foot of the screen is built from - the same switch, named as a finger's.
	var line: String = PlannerHudScript._hints_for(
		ViewController.ViewMode.PLAN_2D, hud.shows_touch_controls()
	)
	assert(line == PlannerHudScript.HINTS_OVERHEAD_ON_A_FINGER, "so the line is a finger's: %s" % line)
	hud.free()
	PhoneHudScript.force_density(0.0)
	TouchInputScript.force(TouchInputScript.Answer.AUTO)


## A phone's top bar keeps its doors and gives up everything else; a desk keeps every part of the row.
##
## The rule lives on the HUD rather than in `PhoneHud` because it is about this HUD's own row and not about a
## size: the bar holds the menu bar, the program's name, a rule, the view's name and the three view controls,
## and at a phone's legible size that is far wider than the screen. A row that cannot hold all of it gives up
## what is not a **door** - and on a device with no keyboard the view controls are the most important doors
## there are, so they are the last thing that can go. The view's name goes with the decoration because the
## controls say it themselves: the button reads "2D plan (Q)" from the 3D view and "Back to overhead (G)" from
## the ground. The four controls are stated here rather than looked up, so the test holds the decision.
func test_a_phone_gives_up_the_top_bars_decoration_and_a_desk_keeps_its_own() -> void:
	var hud := PlannerHudScript.new()
	var name_label := Label.new()
	var rule := VSeparator.new()
	var view_name := Label.new()
	hud.app_label = name_label
	hud.bar_separator = rule
	hud.mode_label = view_name
	# A computer is given nothing at all: the row stays exactly as the scene drew it.
	hud.size_for_a_finger(false)
	assert(name_label.visible, "a desk keeps the program's name in the bar")
	assert(rule.visible, "and the rule beside it")
	assert(view_name.visible, "and the name of the view it is in")
	hud.size_for_a_finger(true)
	assert(not name_label.visible, "a phone puts the program's name away")
	assert(not rule.visible, "and the rule that was only there to divide it")
	assert(not view_name.visible, "and the view's name, which the view controls say themselves")
	hud.free()
	name_label.free()
	rule.free()
	view_name.free()


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


## A device answered with a mouse is never resized. Whether a row is a thumb's is `TouchInput`'s question,
## and neither answer here moves the HUD's own layout: not a mouse, and not a density nobody could read -
## a size worked out from a number that does not exist is worse than the size it already has.
func test_a_mouse_device_and_an_unread_density_leave_the_layout_alone() -> void:
	_reset()
	TouchInputScript.force(TouchInputScript.Answer.MOUSE)
	assert(not PhoneHudScript.on_a_finger_here(), "a mouse is not a finger")
	TouchInputScript.force(TouchInputScript.Answer.AUTO)
	var button: Button = Button.new()
	button.custom_minimum_size = Vector2(170.0, 0.0)
	PhoneHudScript.size_for_a_finger(button, PHONE_SCALE, 0.0)
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


## The scale is applied to a window on a device answered with a finger, and every other window is left
## exactly as it was.
func test_the_canvas_is_drawn_up_for_a_finger_and_left_alone_for_a_mouse() -> void:
	_reset()
	var window: Window = Window.new()
	PhoneHudScript.apply_if(window, false)
	assert(window.content_scale_factor == 1.0, "a mouse's window is not scaled by this program")
	PhoneHudScript.apply_if(window, true)
	assert(
		is_equal_approx(window.content_scale_factor, PhoneHudScript.UI_SCALE),
		"a finger draws the canvas at %.2f" % window.content_scale_factor
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


## A palette button carries two lines - its word and its key under it - and the width it asks for is the
## width of the longer of them, not of the two run together.
func test_a_two_line_button_is_as_wide_as_its_longest_line() -> void:
	var button := Button.new()
	button.text = "Extend"
	var one_line: float = PhoneHudScript.button_width(button)
	button.text = "Extend\nX"
	var two_lines: float = PhoneHudScript.button_width(button)
	assert(
		is_equal_approx(one_line, two_lines),
		"a key under the word does not widen it: %.1f against %.1f" % [two_lines, one_line]
	)
	button.text = "Move\nLONGKEY"
	assert(
		PhoneHudScript.button_width(button) > two_lines,
		"but a key longer than the word is what the button is measured by"
	)
	button.free()


## What a thumb presses is given the flat size its caption is drawn at, and what it reads is grown from the
## size the surface laid it out with: a title stays bigger than the sentence under it rather than every line
## coming out one size.
func test_a_finger_gets_the_row_for_what_it_presses_and_a_grown_size_for_what_it_reads() -> void:
	_reset()
	var button: Button = Button.new()
	var line: Label = Label.new()
	line.add_theme_font_size_override("font_size", 20)

	assert(PhoneHudScript.fit_for_a_finger(button, PHONE_SCALE, PHONE_DPI), "a button is fitted")
	assert(button.custom_minimum_size.y > 29.0, "in the row a thumb needs to hit")
	assert(
		button.get_theme_font_size("font_size") == PhoneHudScript.font_size(PHONE_SCALE, PHONE_DPI),
		"with its caption at the one flat size a phone is told"
	)

	assert(PhoneHudScript.fit_for_a_finger(line, PHONE_SCALE, PHONE_DPI), "a line is fitted too")
	var legible: int = PhoneHudScript.font_size(PHONE_SCALE, PHONE_DPI)
	assert(
		line.get_theme_font_size("font_size") > legible,
		"and a line the surface drew bigger than its body is still the bigger of the two: %d against %d"
			% [line.get_theme_font_size("font_size"), legible]
	)
	button.free()
	line.free()


## A control that neither shows words nor is pressed is left exactly as it is - a size worked out for a
## container or a spacer is a size worked out for nothing.
func test_a_control_with_no_words_and_nothing_to_press_is_left_alone() -> void:
	_reset()
	var patch: ColorRect = ColorRect.new()
	var box: VBoxContainer = VBoxContainer.new()
	assert(not PhoneHudScript.fit_for_a_finger(patch, PHONE_SCALE, PHONE_DPI), "a colour patch is not fitted")
	assert(not PhoneHudScript.fit_for_a_finger(box, PHONE_SCALE, PHONE_DPI), "nor is a container")
	assert(not box.has_theme_font_size_override("font_size"), "and neither of them was given a font")
	patch.free()
	box.free()


## A panel fitted every time it is shown is not a panel that grows every time it is shown. The size a
## control was laid out with is remembered on it, because Godot keeps only the answer that replaced it.
func test_fitting_a_control_twice_grows_it_once() -> void:
	_reset()
	var line: Label = Label.new()
	line.add_theme_font_size_override("font_size", 20)
	PhoneHudScript.fit_for_a_finger(line, PHONE_SCALE, PHONE_DPI)
	var once: int = line.get_theme_font_size("font_size")
	PhoneHudScript.fit_for_a_finger(line, PHONE_SCALE, PHONE_DPI)
	assert(
		line.get_theme_font_size("font_size") == once,
		"a control fitted twice is left at the size it was grown to: %d, was %d"
			% [line.get_theme_font_size("font_size"), once]
	)
	line.free()


## A surface's own chrome is fitted, and a page inside it is not: a page answers for its own controls where a
## page is shown. A menu is a pop-up rather than a page, and is fitted with the control that owns it - a menu
## that opened at a desk's size on a phone is the very defect this exists to stop.
func test_a_huds_own_chrome_is_fitted_and_a_page_inside_it_is_left_to_the_page() -> void:
	_reset()
	var hud: PlannerHudScript = PlannerHudScript.new()
	var toolbar: Button = Button.new()
	hud.add_child(toolbar)
	var menu: PopupMenu = PopupMenu.new()
	hud.add_child(menu)
	var page: Window = Window.new()
	var in_page: Button = Button.new()
	page.add_child(in_page)
	hud.add_child(page)

	var fitted: int = hud.fit_the_chrome_for_a_finger(PHONE_SCALE, PHONE_DPI)
	assert(fitted == 2, "the HUD's own button and its menu were fitted: %d" % fitted)
	assert(toolbar.custom_minimum_size.y > 0.0, "the HUD's own button is a thumb's size")
	assert(menu.get_theme_font_size("font_size") > 12, "and the menu's items are drawn legibly")
	assert(
		in_page.custom_minimum_size == Vector2.ZERO and
			not in_page.has_theme_font_size_override("font_size"),
		"while the button inside the page is still exactly as the page left it"
	)
	hud.free()


## A computer's HUD is left exactly as the scene drew it: the answer is handed in, so what a desk would be
## given can be held without there being a desk - the same door `PhoneHud.apply_if` keeps.
func test_a_computers_hud_is_left_exactly_as_the_scene_drew_it() -> void:
	_reset()
	var hud: PlannerHudScript = PlannerHudScript.new()
	var line: Label = Label.new()
	line.add_theme_font_size_override("font_size", 20)
	hud.add_child(line)

	assert(hud.size_for_a_finger(false) == 0, "nothing is fitted for a mouse")
	assert(line.get_theme_font_size("font_size") == 20, "and the line keeps the size it was drawn with")
	hud.free()
