extends Node
## The arithmetic that turns "a thumb needs five and a half millimetres" into a number of layout
## pixels, and the rule that a computer is given nothing at all.
##
## The densities below are the phone this was written for: 2340 by 1080, drawn at 1.2 by the window and
## then 1.35 by the phone's own scale - 1.62 in all, so the canvas is 1444 px across. When that phone was
## finally measured it reported 450 dots to the inch, which is the number these fixtures carry; the arithmetic
## reads whatever the device says, so these numbers only fix what the tests are exercised at. That is why
## a 29-pixel palette row is 2.3 mm across on a computer and a row of 61 is 5.5 mm on the phone.

const PhoneHudScript := preload("res://scripts/phone_hud.gd")
const PhoneFilesScript := preload("res://scripts/phone_files.gd")
const TouchInputScript := preload("res://scripts/touch_input.gd")
const PlannerHudScript := preload("res://scripts/hud.gd")

## The phone: its density, and the scale its canvas ends up drawn at. The density is the A16W's own reading of
## its glass, so a fixture here states the phone this program is actually aimed at.
const PHONE_DPI := 450.0
const PHONE_SCALE := 1.62


## **The HUD's own top bar was the last thing standing in the band a phone keeps.** Everything else had learned
## it - a page's contents are lifted by `PageChrome`, a page is placed inside the insets, a page's title bar is
## kept below this bar - but the bar, anchored to the top of the screen, stayed at the offset the scene drew it
## with. Measured on the A16W held upright: the three view buttons and the menus sat 81 px inside that strip with
## their middles at y 67, so a tap aimed at `Fit` was answered by the system and not by the program.
##
## The inset is **stated** here rather than read, which is the whole reason the door exists: on this desk
## `cutout_top` answers zero, and a device with a band along its top is not a thing this machine can be.
func test_the_top_bar_is_lifted_by_the_band_the_device_keeps_and_never_drifts() -> void:
	var hud: PlannerHud = PlannerHudScript.new()
	var bar := PanelContainer.new()
	bar.offset_top = 12.0
	bar.offset_bottom = 62.0
	hud.top_bar = bar
	# What the plate's own margin was before anything moved it: the assertion below is that it moved by the band,
	# rather than by a number a theme might one day change.
	var plate: StyleBox = bar.get_theme_stylebox(&"panel")
	var was: float = 0.0
	if plate is StyleBoxFlat:
		was = (plate as StyleBoxFlat).content_margin_top

	hud.lift_the_top_bar_by(100)
	assert(is_equal_approx(bar.offset_top, 12.0), "the plate keeps the top the scene drew: %s" % str(bar.offset_top))
	assert(is_equal_approx(bar.offset_bottom, 162.0), "and grows downward by the band: %s" % str(bar.offset_bottom))
	# **The words are what is lifted**, through the plate's own content margin - the thing a `PanelContainer` lays its
	# child out by, where an offset set on the child would be overwritten by the next layout. Measured on the A16W:
	# lifting the plate as well left 212 px of bare sheet above the first button, which is a bar that is not at the
	# top; the plate runs to the top now and only its row of menus is clear of the camera cutout.
	assert(plate is StyleBoxFlat, "a plate has a flat background to measure")
	var margin_now: float = (bar.get_theme_stylebox(&"panel") as StyleBoxFlat).content_margin_top
	assert(is_equal_approx(margin_now, was + 100.0), "the row inside is lifted by the band: %s" % str(margin_now))

	# **A turn re-runs the pass that does this**, so it has to answer the same thing every time: a lift that read its
	# own output back would walk the bar down the screen by a band on every rotation.
	hud.lift_the_top_bar_by(100)
	assert(is_equal_approx(bar.offset_top, 12.0), "the second pass moves nothing: %s" % str(bar.offset_top))
	assert(is_equal_approx(bar.offset_bottom, 162.0), "and its foot is where it was: %s" % str(bar.offset_bottom))
	assert(
		is_equal_approx((bar.get_theme_stylebox(&"panel") as StyleBoxFlat).content_margin_top, was + 100.0),
		"and the row is lifted once rather than twice",
	)

	# A device with nothing to clear - every desk - is given the bar the scene drew, to the pixel.
	hud.lift_the_top_bar_by(0)
	assert(is_equal_approx(bar.offset_top, 12.0), "nothing to clear puts it back: %s" % str(bar.offset_top))
	assert(is_equal_approx(bar.offset_bottom, 62.0), "both offsets, exactly: %s" % str(bar.offset_bottom))
	assert(not bar.has_theme_stylebox_override(&"panel"), "and the plate's own margin is handed back, not left lifted")

	# And the desk's own reading is the same answer: a bar not in a tree has no viewport, and a screen with no
	# safe area keeps nothing back either way.
	hud.lift_the_top_bar_clear_of_the_device()
	assert(is_equal_approx(bar.offset_top, 12.0), "a desk's own reading leaves the bar alone")

	hud.top_bar = null
	bar.free()
	hud.free()


## A cutout is measured as each side's share of the screen, so a phone held sideways is answered on the
## side its camera is on rather than at the top alone.
##
## The display is an argument rather than a reading here, which is the whole reason the arithmetic is
## testable: on this desk the real safe area has no cutout in it, and a device with one on its side is
## not a thing this machine can be.
func test_a_cutout_is_measured_on_every_side_of_the_screen() -> void:
	var screen := Vector2i(1080, 2340)
	var room := Vector2i(1185, 2567)
	var insets: Vector4i = PhoneHudScript.cutout_insets(room, screen, Rect2i(0, 100, 1080, 2240))
	assert(insets.x == 0 and insets.z == 0, "nothing is taken off the sides in portrait")
	assert(insets.y == roundi(2567.0 * (100.0 / 2340.0)), "the top is its share of the room's own height")
	assert(insets.w == 0, "and the foot nothing, because the safe area ends where the screen does")


## The same phone on its side: the camera is on the left, so the room gives ground on the left and the
## page moves towards the side that has more of it.
func test_a_phone_held_sideways_gives_ground_where_the_camera_is() -> void:
	var insets: Vector4i = PhoneHudScript.cutout_insets(
		Vector2i(2567, 1185),
		Vector2i(2340, 1080),
		Rect2i(120, 0, 2220, 1080),
	)
	assert(insets.x == roundi(2567.0 * (120.0 / 2340.0)), "the left takes the cutout's share of the width")
	assert(insets.z == 0, "the right takes none of it")
	assert(insets.y == 0 and insets.w == 0, "and the top and foot take none, held this way")


## A display reporting no furniture, and a room nobody could state, both answer zero on all four sides:
## a cutout that is not there may not make a real screen smaller than it is.
func test_no_furniture_and_no_room_answer_zero_on_every_side() -> void:
	var safe := Rect2i(0, 0, 1080, 2340)
	var nothing: Vector4i = PhoneHudScript.cutout_insets(Vector2i(1185, 2567), Vector2i(1080, 2340), safe)
	assert(nothing == Vector4i.ZERO, "a display reporting no cutout costs a page nothing")
	var unstated: Vector4i = PhoneHudScript.cutout_insets(Vector2i.ZERO, Vector2i(1080, 2340), safe)
	assert(unstated == Vector4i.ZERO, "and neither does a room with no size to take a share of")


## **The band is one reading, in the display's own pixels, and a room's share of it is another.** Kept apart so that
## a figure in a block can be compared with what the phone itself is asked: the two are different numbers in
## different spaces, and reading one as the other is how the menu bar's lift was guessed at rather than measured.
func test_the_display_reports_its_band_before_any_share_of_a_room_is_taken() -> void:
	# The A16W upright: a 100 px camera cutout along the top and nothing else.
	var upright: Vector4i = PhoneHudScript.band_edges(Vector2i(1080, 2340), Rect2i(0, 100, 1080, 2240))
	assert(upright == Vector4i(0, 100, 0, 0), "the raw reading, uncut by any room: %s" % str(upright))

	# And on its side, where the same camera is on the left and the top band is gone.
	var sideways: Vector4i = PhoneHudScript.band_edges(Vector2i(2340, 1080), Rect2i(120, 0, 2220, 1080))
	assert(sideways == Vector4i(120, 0, 0, 0), "a sideways phone keeps its band on the left: %s" % str(sideways))

	# A display that promises nothing, and one with no size, both answer zero rather than a guess.
	assert(
		PhoneHudScript.band_edges(Vector2i(1080, 2340), Rect2i(0, 0, 1080, 2340)) == Vector4i.ZERO,
		"a display keeping nothing has no band",
	)
	assert(
		PhoneHudScript.band_edges(Vector2i.ZERO, Rect2i(0, 100, 0, 0)) == Vector4i.ZERO,
		"and neither does one that will not say how big it is",
	)


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
	var line: String = PlannerHudScript._hints_for(ViewController.ViewMode.PLAN_2D, hud.shows_touch_controls())
	assert(line == PlannerHudScript.HINTS_OVERHEAD_ON_A_FINGER, "so the line is a finger's: %s" % line)
	hud.free()
	PhoneHudScript.force_density(0.0)
	TouchInputScript.force(TouchInputScript.Answer.AUTO)


## A phone opens with the presentation panel put away; a computer opens with the panel the scene drew.
##
## On a phone the panel is over a third of the width with its last rows off the bottom of the screen, and it
## is the one place the site's latitude, longitude and zone are edited - so it starts out of the way and the
## Present menu's own row brings it back. What is held here is only the *start*: a person who brings it back
## on a phone keeps it, which is the whole reason the answer is settled once instead of imposed every pass.
func test_a_phone_opens_with_the_presentation_panel_put_away() -> void:
	var phone := PlannerHudScript.new()
	phone.start_the_presentation_panel_for(true)
	assert(not phone.is_presentation_panel_wanted(), "a phone starts with the panel out of the way")
	phone.set_presentation_panel_wanted(true)
	phone.start_the_presentation_panel_for(true)
	assert(phone.is_presentation_panel_wanted(), "and a person who brings it back keeps it")
	phone.free()

	var desk := PlannerHudScript.new()
	desk.start_the_presentation_panel_for(false)
	assert(desk.is_presentation_panel_wanted(), "a computer keeps the panel the scene drew for it")
	desk.free()


## A menu's **row** is what a thumb hits, and a row is the font's own line plus the separation between its
## items - so a menu whose words were grown for a phone can still hand a thumb a band shorter than the
## buttons around it, and the menus then become the smallest thing on a page to hit.
##
## Measured at the phone's own scale rather than the window's: the fitting is told the canvas it is drawn
## at, and this desk's window is neither the phone's size nor its shape.
func test_a_phones_menu_hands_a_thumb_a_row_and_not_only_legible_words() -> void:
	_reset()
	var menu := PopupMenu.new()
	menu.add_item("One")
	PhoneHudScript.size_a_windows_words_for_a_finger(menu, PHONE_SCALE, PHONE_DPI)
	var row: float = _menu_row(menu)
	var wanted: float = PhoneHudScript.row_height(PHONE_SCALE, PHONE_DPI)
	assert(row >= wanted - 0.01, "the menu's row is the row a thumb needs: %.1f px against %.1f" % [row, wanted])
	# Fitting twice is fitting once: a menu shown again is not handed a taller row every time it opens.
	var once: int = menu.get_theme_constant(&"v_separation")
	PhoneHudScript.size_a_windows_words_for_a_finger(menu, PHONE_SCALE, PHONE_DPI)
	assert(
		menu.get_theme_constant(&"v_separation") == once,
		"and a menu fitted twice keeps the row it was given: %d" % once,
	)
	menu.free()


## A `MenuBar` owns its menus as children of its own, and a rebuild makes new ones at the size a desk draws
## them - so a bar whose menus were fitted once hands a thumb a desk's row again the moment the room changes.
##
## Found live on the SM-A166W rather than by reading: the File and Edit menus on the board opened with rows of
## **44.5 px - 2.51 mm**, against this program's 5.5 mm floor, because the fold rebuilt the bar *after* the
## chrome had been fitted and nothing put the fitting back. This holds the half that needs no HUD: the walk
## reaches a bar's own menus, and a second pass keeps the row it gave them.
func test_a_menu_bars_own_menus_are_fitted_for_a_finger_and_raised_once() -> void:
	_reset()
	var bar := MenuBar.new()
	var file := PopupMenu.new()
	file.title = "File"
	bar.add_child(file)
	file.add_item("Open a drawing")
	file.add_item("Save the drawing")
	var desk_font: int = file.get_theme_font_size(&"font_size")
	var fitted: int = PhoneHudScript.fit_the_chrome_for_a_finger(bar, PHONE_SCALE, PHONE_DPI)
	assert(fitted > 0, "walking the bar reaches the menu it owns")
	var grown: int = file.get_theme_font_size(&"font_size")
	assert(grown > desk_font, "and its words are grown: %d against the desk's %d" % [grown, desk_font])
	var row: float = _menu_row(file)
	var wanted: float = PhoneHudScript.row_height(PHONE_SCALE, PHONE_DPI)
	assert(row >= wanted - 0.01, "and the row a thumb hits is the row it needs: %.1f px against %.1f" % [row, wanted])
	var once: int = file.get_theme_constant(&"v_separation")
	PhoneHudScript.fit_the_chrome_for_a_finger(bar, PHONE_SCALE, PHONE_DPI)
	assert(
		file.get_theme_constant(&"v_separation") == once,
		"a second pass keeps the row it was given, so refitting a rebuilt bar cannot ratchet: %d" % once,
	)
	bar.free()


## The row a menu's items are drawn in, from the engine's own two readings for it: the line its font draws
## at that size, and the separation the theme puts between items. Held against menus that were really
## rendered - 27 px at a 16 px font, 69 px at 47 - and both are exactly this sum.
func _menu_row(menu: PopupMenu) -> float:
	var font: Font = menu.get_theme_font(&"font")
	if font == null:
		return 0.0
	return (font.get_height(menu.get_theme_font_size(&"font_size")) + float(menu.get_theme_constant(&"v_separation")))


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
		"a row of %.1f px comes to %.2f mm, not %.2f" % [height, measured, PhoneHudScript.TOUCH_MM],
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
	var capital: float = PhoneHudScript.millimetres(float(size) * PhoneHudScript.CAP_RATIO, PHONE_SCALE, PHONE_DPI)
	assert(size > 12, "bigger than the twelve-pixel text a desk gets: %d" % size)
	assert(
		capital >= PhoneHudScript.TEXT_MM - 0.001,
		"a capital of %.2f mm is short of the %.2f mm it has to read at" % [capital, PhoneHudScript.TEXT_MM],
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
		"and the text is the size a phone is told",
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
		"a finger draws the canvas at %.2f" % window.content_scale_factor,
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
		"a computer's six still fit the 368 px the panel leaves them",
	)
	assert(
		PhoneHudScript.columns_that_fit(phone, 6, 368.0, 4.0, 3) == 3,
		"a phone's six do not, and three of them still do",
	)


## A palette squeezed narrower than its tools grid is a list, and a list is not a palette.
func test_a_row_is_never_squeezed_below_the_palettes_own_column_count() -> void:
	assert(
		PhoneHudScript.columns_that_fit([300.0, 300.0], 6, 368.0, 4.0, 3) == 3,
		"two cells of 300 px do not fit, and three columns is the narrowest allowed",
	)


## A panel nobody has laid out yet reports no room, and no room worked out is not a reason to re-flow.
func test_no_room_worked_out_leaves_the_row_as_it_was_built() -> void:
	assert(
		PhoneHudScript.columns_that_fit([100.0], 6, 0.0, 4.0, 3) == 6,
		"a panel that has been given no room at all is not a measurement",
	)
	assert(
		PhoneHudScript.columns_that_fit([], 6, 368.0, 4.0, 3) == 6,
		"a row with no cells in it is not re-flowed either",
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
		"a key under the word does not widen it: %.1f against %.1f" % [two_lines, one_line],
	)
	button.text = "Move\nLONGKEY"
	assert(
		PhoneHudScript.button_width(button) > two_lines,
		"but a key longer than the word is what the button is measured by",
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
		"with its caption at the one flat size a phone is told",
	)

	assert(PhoneHudScript.fit_for_a_finger(line, PHONE_SCALE, PHONE_DPI), "a line is fitted too")
	var legible: int = PhoneHudScript.font_size(PHONE_SCALE, PHONE_DPI)
	assert(
		line.get_theme_font_size("font_size") > legible,
		"and a line the surface drew bigger than its body is still the bigger of the two: %d against %d"
		% [line.get_theme_font_size("font_size"), legible],
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
		% [line.get_theme_font_size("font_size"), once],
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
		in_page.custom_minimum_size == Vector2.ZERO and not in_page.has_theme_font_size_override("font_size"),
		"while the button inside the page is still exactly as the page left it",
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


## A button the layout gave **no width of its own** has only its own words to be measured by, and a word is
## narrower than a thumb. The bar's `Fit` is the worked example: measured on the A16W it came out **56 x 97**
## against the **107 px** this device's own 5.5 mm row asks for - 51 px short of what the program demands of
## every other target on the screen, and it passed the desk's own 44 px floor for three phone passes before the
## device's floor was asked of it. The width is raised to the same row, and **a width the layout did state is
## left exactly as it was** - which is the promise the palette's own cells rest on.
func test_a_button_with_no_width_of_its_own_is_given_the_row_a_thumb_needs() -> void:
	_reset()
	PhoneFilesScript.force(PhoneFilesScript.Device.PHONE)
	var row: float = PhoneHudScript.row_height(PHONE_SCALE, PHONE_DPI)

	var word: Button = Button.new()
	word.text = "Fit"
	PhoneHudScript.size_for_a_finger(word, PHONE_SCALE, PHONE_DPI)
	assert(
		is_equal_approx(word.custom_minimum_size.x, row),
		"a word narrower than a thumb is given the row: %.1f against %.1f" % [word.custom_minimum_size.x, row],
	)
	assert(is_equal_approx(word.custom_minimum_size.y, row), "and the row is its height as well")
	word.free()

	# A stated width is the layout's own business, exactly as it was before this rule existed.
	var cell: Button = Button.new()
	cell.custom_minimum_size = Vector2(170.0, 0.0)
	PhoneHudScript.size_for_a_finger(cell, PHONE_SCALE, PHONE_DPI)
	assert(cell.custom_minimum_size.x == 170.0, "a width the layout stated is left exactly as it was")
	assert(is_equal_approx(cell.custom_minimum_size.y, row), "and the height is still the thumb's")
	cell.free()


## A dialog's own two buttons are the engine's, and it takes their minimum away the moment the dialog is shown -
## so their row is asked for through the **frame** instead, which is the engine's own arithmetic for a button's
## height: its font plus its stylebox. Measured on the A16W held upright, the unsaved-changes question's buttons
## came out `254 x 64, 33 px short of the 97 a finger wants` while the fit set a minimum the engine then threw
## away; the frame is what the engine leaves alone, and the font override surviving it is the proof.
##
## Three things are held here, because each of them is a way to make the whole program worse: **only** a dialog's
## own button is touched, the stylebox is **copied** before it is grown, and a second pass grows nothing.
func test_a_dialogs_own_button_is_given_the_row_through_its_frame_and_only_that_button() -> void:
	_reset()
	PhoneFilesScript.force(PhoneFilesScript.Device.PHONE)
	var row: float = PhoneHudScript.row_height(PHONE_SCALE, PHONE_DPI)

	# A button of the program's own, outside any dialog, is given the minimum it always was and no frame at all:
	# a frame grown here as well would be the same row counted twice, and the chrome would grow by a row a turn.
	var toolbar: Button = Button.new()
	PhoneHudScript.size_for_a_finger(toolbar, PHONE_SCALE, PHONE_DPI)
	assert(is_equal_approx(toolbar.custom_minimum_size.y, row), "the HUD's own button keeps the row it was given")
	assert(
		not toolbar.has_theme_stylebox_override(&"normal"),
		"and its frame is left alone, or the row would be asked for twice",
	)

	var question := ConfirmationDialog.new()
	question.dialog_text = "untitled drawing - unsaved changes\n\nDiscard the changes?"
	add_child(question)
	var answer: Button = question.get_ok_button()
	# The stylebox the theme hands out, taken before anything is fitted: growing **this** would move every button
	# in the program that draws with it.
	var theirs: StyleBox = answer.get_theme_stylebox(&"normal")
	var margin_was: float = theirs.get_content_margin(SIDE_TOP)

	PhoneHudScript.size_for_a_finger(answer, PHONE_SCALE, PHONE_DPI)
	assert(
		answer.has_theme_stylebox_override(&"normal"),
		"a dialog's own button is given a frame that asks for the row",
	)
	assert(
		answer.get_theme_stylebox(&"normal") != theirs,
		"and it draws from a frame of its own rather than from the theme's own stylebox",
	)
	assert(
		is_equal_approx(theirs.get_content_margin(SIDE_TOP), margin_was),
		(
			"so the theme's own frame is left exactly as it was: %.1f against %.1f"
			% [theirs.get_content_margin(SIDE_TOP), margin_was]
		),
	)

	# What showing the dialog does to it, done by hand: the minimum goes and the frame stays.
	answer.custom_minimum_size = Vector2.ZERO
	assert(
		answer.get_combined_minimum_size().y >= row - 0.5,
		(
			"and the row is still there without the minimum: %.2f against the %.2f the device asks for"
			% [answer.get_combined_minimum_size().y, row]
		),
	)

	# Growing it twice is growing it once: the frame already asks for the row the second time, which is what keeps
	# a question shown twice in a session from growing a row each time.
	var grown: float = answer.get_theme_stylebox(&"normal").get_minimum_size().y
	PhoneHudScript.size_for_a_finger(answer, PHONE_SCALE, PHONE_DPI)
	assert(
		is_equal_approx(answer.get_theme_stylebox(&"normal").get_minimum_size().y, grown),
		(
			"and a second pass adds nothing to it: %.1f against %.1f"
			% [answer.get_theme_stylebox(&"normal").get_minimum_size().y, grown]
		),
	)

	remove_child(question)
	question.free()
	toolbar.free()


## The palette is held between the top bar above it and the foot line below it, each read off that thing's own
## rectangle - and **a second pass moves nothing**.
##
## That second half is the trap this shares with the bar's lift: the pass runs again on every change of the room's
## shape, so a placement measured from its own output would walk the palette up the screen one turn at a time.
## `_palette_offsets_as_drawn` exists for it, and this is what holds it down.
##
## The scene's own numbers are the floor: where the bar's foot is 62 and the plate's top is 846 on a 900-tall
## room, a desk is given back exactly the offsets the scene drew. A phone's taller bar and wrapped plate are what
## move it - measured on the A16W, where they put the palette over the menu bar's own titles and the plate over
## the palette's last rows.
func test_the_palette_is_placed_between_the_bar_and_the_foot_line_and_never_drifts() -> void:
	var hud: PlannerHud = PlannerHudScript.new()
	# A plain `Control` and not a container: a container would lay these three out itself, and what is being
	# asked is where *this HUD* puts the palette from the rectangles its two neighbours report.
	var room := Control.new()
	room.size = Vector2(1600.0, 900.0)
	add_child(room)
	var bar := PanelContainer.new()
	bar.position = Vector2(0.0, 12.0)
	bar.size = Vector2(1000.0, 50.0)
	var palette := PanelContainer.new()
	palette.offset_left = 12.0
	palette.offset_top = 70.0
	palette.offset_right = 404.0
	palette.offset_bottom = -62.0
	var foot := PanelContainer.new()
	foot.position = Vector2(0.0, 846.0)
	room.add_child(bar)
	room.add_child(palette)
	room.add_child(foot)
	hud.top_bar = bar
	hud.palette = palette
	hud.hints = foot

	# A desk: the bar's foot is 62 and the plate's top is 846, which is exactly what the scene's offsets already
	# clear. Both ends are floors, so nothing moves.
	hud.place_the_left_column_for_a_device()
	assert(is_equal_approx(palette.offset_top, 70.0), "a desk keeps the palette's top: %s" % str(palette.offset_top))
	assert(is_equal_approx(palette.offset_bottom, -62.0), "and its foot: %s" % str(palette.offset_bottom))

	# A phone: the bar is far taller and the wrapped plate's top is far higher, so both ends move - the top below
	# the bar's foot, the foot above the plate's top, each leaving the 8 px gap the scene itself keeps.
	bar.size = Vector2(1000.0, 250.0)
	foot.position = Vector2(0.0, 700.0)
	hud.place_the_left_column_for_a_device()
	assert(is_equal_approx(palette.offset_top, 270.0), "the top clears the bar's foot: %s" % str(palette.offset_top))
	assert(
		is_equal_approx(palette.offset_bottom, -208.0),
		"and the foot clears the plate: %s" % str(palette.offset_bottom),
	)

	# And it is a floor, not a step: the pass runs again on every turn.
	hud.place_the_left_column_for_a_device()
	assert(is_equal_approx(palette.offset_top, 270.0), "a second pass moves nothing: %s" % str(palette.offset_top))
	assert(
		is_equal_approx(palette.offset_bottom, -208.0),
		"and its foot is where it was: %s" % str(palette.offset_bottom),
	)

	remove_child(room)
	room.free()
	# The HUD itself is a node this test made and never added, so it is freed here as every node a test makes
	# must be: the runner counts what is left in use and fails the run for it.
	hud.free()


## The palette is held between the top bar above it and the hint plate below it, and each end is **read off the
## thing it must clear** rather than restated - because on a phone both grow and the scene's two numbers are a
## desk's alone. Measured on the A16W held upright: the palette was drawn *over* the menu bar's own titles, so
## `File` and `View` could not be pressed at all, and the wrapped foot line was drawn over the palette's last
## rows. No instrument named either one, so the numbers are pinned here.
##
## The device is an argument, as it is for every other door here: what a phone would be told is held without
## being one.
func test_the_palette_is_held_between_the_bar_above_it_and_the_foot_line_below_it() -> void:
	# A desk, at its own numbers: the bar's foot is 62, the plate's top is 846, the canvas is 900 tall, and the
	# scene drew the palette at 70 with its foot 62 px above the canvas's foot. Both ends are floors, so a desk
	# - where the scene's numbers still agree with the two things they must clear - is given exactly that
	# rectangle, to the pixel.
	var desk: Vector2 = PlannerHudScript.offsets_for_the_left_column(62.0, 846.0, Vector2(70.0, -62.0), 900.0, 31.0)
	assert(is_equal_approx(desk.x, 70.0), "a desk keeps the palette's top: %s" % str(desk.x))
	assert(is_equal_approx(desk.y, -62.0), "and its foot, exactly: %s" % str(desk.y))

	# A phone, at the numbers measured there: the bar's foot is 290 (a 107 px row below a cutout), the wrapped
	# plate's top is 2267, and the canvas is 2567 tall.
	var phone: Vector2 = PlannerHudScript.offsets_for_the_left_column(
		290.0,
		2267.0,
		Vector2(70.0, -62.0),
		2567.0,
		107.0,
	)
	assert(is_equal_approx(phone.x, 298.0), "the palette's top clears the bar's foot: %s" % str(phone.x))
	assert(is_equal_approx(phone.y, -308.0), "and its foot clears the plate's top: %s" % str(phone.y))
	assert(
		is_equal_approx((2567.0 + phone.y) - phone.x, 1961.0),
		"so the two ends leave the gap the scene keeps at both: %s" % str((2567.0 + phone.y) - phone.x),
	)

	# A palette is never squeezed to nothing: where the bar and the plate leave less than one of its own rows,
	# it keeps the row and the plate meets it - the lesser of the two faults, and the one a person can still
	# work around by scrolling.
	var squeezed: Vector2 = PlannerHudScript.offsets_for_the_left_column(
		2380.0,
		2400.0,
		Vector2(70.0, -62.0),
		2567.0,
		107.0,
	)
	assert(is_equal_approx(squeezed.x, 2388.0), "it still clears the bar: %s" % str(squeezed.x))
	assert(
		is_equal_approx((2567.0 + squeezed.y) - squeezed.x, 107.0),
		"and stands exactly one of its own rows tall: %s" % str((2567.0 + squeezed.y) - squeezed.x),
	)


## **The placement is asked for when the plate's height changes, and not once before the plate has been laid
## out.** The arithmetic above was already right; what was wrong was the moment it was asked for. The words were
## assigned and the column placed again in the same breath, but the plate has not been laid out at that point - so
## the placement read the height the plate was about to leave, and the palette kept a foot that belonged to the
## shorter line.
##
## Measured on the A16W held upright: the foot line wrapped from one row onto three, the palette's own box stayed
## where the one-row plate had put it, and its last rows - `Layer` and the plant list's group headers - were drawn
## across the plate's words. Every rule was silent, because words drawn over words by the layout are not a meeting
## a rectangle of a control can report.
##
## A height is what the placement actually reads, so a height is what the rule watches. This holds the answers
## down: the first frame places, because the column has been nowhere yet; a plate that held still asks for
## nothing; and a plate that grew - by whatever it grew - asks exactly once.
func test_the_column_is_placed_again_when_the_plate_at_the_foot_changes_height() -> void:
	var hud: PlannerHud = PlannerHudScript.new()

	# Nothing has been placed yet, so the first height the rule is told is a move whatever the number is.
	assert(hud._the_plate_moved(42.0), "the first height the rule is told is always a move")
	assert(
		is_equal_approx(hud._plate_height_as_placed, 42.0),
		"and it is the height in hand: %s" % str(hud._plate_height_as_placed),
	)

	# The sixty frames a second that find the same line in hand ask for nothing.
	assert(not hud._the_plate_moved(42.0), "a plate that held still has not moved")
	assert(not hud._the_plate_moved(42.0), "nor has it on the frame after that")
	assert(
		is_equal_approx(hud._plate_height_as_placed, 42.0),
		"and the height in hand is unchanged: %s" % str(hud._plate_height_as_placed),
	)

	# A line that wrapped onto another row is a move, and it is asked for once rather than every frame after.
	assert(hud._the_plate_moved(107.0), "a plate that grew by a row has moved")
	assert(not hud._the_plate_moved(107.0), "and asks for the column once, not on every frame after")
	assert(
		is_equal_approx(hud._plate_height_as_placed, 107.0),
		"the taller height is the one in hand: %s" % str(hud._plate_height_as_placed),
	)

	# The other way too: the plate is shorter under a bare view, and that moves the column back down as well.
	assert(hud._the_plate_moved(42.0), "a plate that went back to one row has moved too")
	assert(not hud._the_plate_moved(42.0), "once, again")

	hud.free()
