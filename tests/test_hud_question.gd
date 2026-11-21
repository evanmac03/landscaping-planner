extends Node

## The program's own questions - the unsaved-changes question, the auto-simplify confirmation and the recovery
## offer - are `ConfirmationDialog`s, and no pass fitted them for a finger. Measured on the A16W, the
## unsaved-changes question was drawn at the desk's 16 px with its buttons 50 px tall while everything around it
## was a finger's: the one screen whose whole job is to be read before anything is thrown away was the hardest
## thing on the phone to read.
##
## `Hud._ask` fits a question through the one walk that fits a window's controls, and this file holds both halves
## of that decision down: the words and the buttons a thumb presses, and the title bar it deliberately leaves.
##
## **This file is the instrument for these three screens, and there is no other one.** A question is a
## `ConfirmationDialog` rather than a page: `tools/page_index.gd` does not list it, so `tools/gui_sweep.tscn` never
## opens it and `tools/page_layout_check.gd` never shows it. The live probe *does* name a question's buttons when
## it is up (`PROBE small DiscardChanges ...`, which is how the portrait fault below was found) - but only on a
## real screen, so a headless run reads nothing there. The row is therefore held here with the device's own
## numbers handed in, and the phone is only ever the confirmation.

const HudScript := preload("res://scripts/hud.gd")
const PhoneHudScript := preload("res://scripts/phone_hud.gd")

## The A16W held in landscape: 1.62 physical pixels to the logical one, at 450 dpi.
const PHONE_SCALE := 1.622

## **And the same phone held upright - the half this file did not know.** The canvas scale is the room's, so the
## same 5.5 mm row is a *bigger* layout number on the shorter side: 60.07 px lying down and 107.08 upright, and
## 97 px of screen either way. Every portrait fault therefore hides behind a landscape test - measured
## 2026-11-14, when the question's buttons were 33 px short of the floor on the phone while this file's own
## arithmetic agreed with the code that put them there.
const PHONE_SCALE_UPRIGHT := 0.91

const PHONE_DPI := 450.0


## A question's own words and its two buttons are made a finger's - the fault the probe named three times
## (`tiny`) for the words and twice (`small`) for the buttons.
func test_a_question_is_given_a_fingers_words_and_its_buttons_a_fingers_row() -> void:
	var hud: HudScript = HudScript.new()
	var question := ConfirmationDialog.new()
	question.dialog_text = "untitled drawing - unsaved changes\n\nDiscard the changes?"
	add_child(question)

	var row: float = PhoneHudScript.row_height(PHONE_SCALE, PHONE_DPI)
	var words: Label = question.get_label()
	var was: int = words.get_theme_font_size(&"font_size")

	var fitted: int = hud.fit_a_question_for_a_finger(question, PHONE_SCALE, PHONE_DPI)

	assert(fitted > 0, "the question was fitted at all: %d control(s)" % fitted)
	assert(
		words.get_theme_font_size(&"font_size") > was,
		"the question's own words are made readable: %d against the %d they were drawn at"
		% [words.get_theme_font_size(&"font_size"), was],
	)
	assert(
		is_equal_approx(question.get_ok_button().custom_minimum_size.y, row),
		"and the button that answers it is given the row a thumb needs: %s against %s"
		% [str(question.get_ok_button().custom_minimum_size.y), str(row)],
	)
	assert(
		is_equal_approx(question.get_cancel_button().custom_minimum_size.y, row),
		"and so is the button that refuses it: %s" % str(question.get_cancel_button().custom_minimum_size.y),
	)

	remove_child(question)
	question.free()
	hud.free()


## **The row is the screen's, not the layout's** - which is the whole reason a portrait fault hides behind a
## landscape test. The same 5.5 mm row is 60.07 layout px lying down and 107.08 upright, and it comes out 97 px
## of screen either way: the scale and the row move in opposite directions, so what a finger is given does not
## change with the phone's shape even though the numbers written down do. Measured 2026-11-14: the question's
## buttons were 64 px of screen against that 97 on the A16W held upright, while every number this file knew
## agreed with the code.
func test_the_row_a_question_is_given_is_the_screens_whichever_way_up_the_phone_is_held() -> void:
	var hud: HudScript = HudScript.new()
	var question := ConfirmationDialog.new()
	question.dialog_text = "untitled drawing - unsaved changes\n\nDiscard the changes?"
	add_child(question)

	for scale: float in [PHONE_SCALE, PHONE_SCALE_UPRIGHT]:
		var row: float = PhoneHudScript.row_height(scale, PHONE_DPI)
		var fitted: int = hud.fit_a_question_for_a_finger(question, scale, PHONE_DPI)
		assert(fitted > 0, "the question was fitted at scale %s: %d control(s)" % [str(scale), fitted])
		assert(
			is_equal_approx(question.get_ok_button().custom_minimum_size.y, row),
			(
				"the button that answers it is given the row at scale %s: %s against %s"
				% [str(scale), str(question.get_ok_button().custom_minimum_size.y), str(row)]
			),
		)

	var lying: float = PhoneHudScript.row_height(PHONE_SCALE, PHONE_DPI) * PHONE_SCALE
	var upright: float = PhoneHudScript.row_height(PHONE_SCALE_UPRIGHT, PHONE_DPI) * PHONE_SCALE_UPRIGHT
	assert(
		is_equal_approx(lying, upright),
		"the row comes out the same size on the screen either way up: %.2f against %.2f" % [lying, upright],
	)
	assert(lying >= 90.0, "and it is the finger's own row rather than a desk's 44 px: %.1f px of screen" % lying)

	remove_child(question)
	question.free()
	hud.free()


## **The row survives the engine taking the minimum away**, which is the whole of this question's story. A
## `ConfirmationDialog`'s own buttons are the engine's, and it clears their `custom_minimum_size` the moment the
## dialog is shown - measured on the desk with the phone's own numbers handed in: `(107.078, 107.078)` before
## the popup, `(0, 0)` after it, with the font override left in place. So the row is asked for through the
## button's **frame** as well, and this holds that down the way the engine does it: take the minimum away, and
## the row is still what the button asks for. Before this, the A16W held upright measured
## `Button "Keep editing" is 254 x 64, 33 px short of the 97 a finger wants`.
func test_the_row_survives_the_engine_taking_the_minimum_away() -> void:
	var hud: HudScript = HudScript.new()
	var question := ConfirmationDialog.new()
	question.dialog_text = "untitled drawing - unsaved changes\n\nDiscard the changes?"
	add_child(question)

	var row: float = PhoneHudScript.row_height(PHONE_SCALE_UPRIGHT, PHONE_DPI)
	hud.fit_a_question_for_a_finger(question, PHONE_SCALE_UPRIGHT, PHONE_DPI)
	for button: Button in [question.get_ok_button(), question.get_cancel_button()]:
		assert(
			button.custom_minimum_size.y > 0.0,
			"the fit gives the button a minimum as it always did: %s" % str(button.custom_minimum_size.y),
		)
		# What showing the dialog does to it, done by hand.
		button.custom_minimum_size = Vector2.ZERO
		assert(
			button.get_combined_minimum_size().y >= row - 0.5,
			(
				"and the row is still there without it: %.2f against the %.2f the device asks for"
				% [button.get_combined_minimum_size().y, row]
			),
		)

	remove_child(question)
	question.free()
	hud.free()


## The title bar is the half that is deliberately left alone, and the reason is measured rather than tidy.
##
## A page's title is grown *and* its bar with it, and that is meant: a page's title hangs above the page's own
## panel onto the sheet one of the doorway pages stands on, and on that dark sheet the theme's own light ink
## reads. A question has no sheet behind it - it floats over the board - so growing the bar pushed its title out
## of the filled band it had been legible in and onto the bright board, where the light ink could not be read at
## all. The bar left as the theme drew it keeps the title inside the fill, and there a person can read it.
func test_a_questions_title_bar_is_left_exactly_as_the_theme_drew_it() -> void:
	var hud: HudScript = HudScript.new()
	var question := ConfirmationDialog.new()
	add_child(question)

	var height_was: int = question.get_theme_constant(&"title_height")
	var fitted: int = hud.fit_a_question_for_a_finger(question, PHONE_SCALE, PHONE_DPI)

	assert(fitted > 0, "the question was fitted at all: %d control(s)" % fitted)
	assert(
		question.get_theme_constant(&"title_height") == height_was,
		"the title bar stays the bar the theme drew: %d against %d"
		% [question.get_theme_constant(&"title_height"), height_was],
	)

	remove_child(question)
	question.free()
	hud.free()
