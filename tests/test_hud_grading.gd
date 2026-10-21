extends Node
## The ground's heights, joined to the Site menu and to the page.
##
## The module is tested in `test_grading.gd`, the tools and the controller in `test_grading_tools.gd`
## and the page in `test_grading_window.gd`; this is the part that only exists when they are put
## together - that the Site menu offers the levels, that the page is filled from the drawing rather
## than from itself, that pressing a tool arms it and steps the page out of the way, and that a page
## left open keeps up with a drawing that changes behind it.
##
## Neither node enters a tree, so no `_ready` runs, no dialog is built and no window is ever shown:
## `popup_centered` needs a screen and a test does not have one, which is why filling the page is its
## own function.

const HudScript := preload("res://scripts/hud.gd")
const ControllerScript := preload("res://scripts/draft/draft_controller.gd")
const DocumentScript := preload("res://scripts/draft/draft_document.gd")
const SnapScript := preload("res://scripts/draft/snap_engine.gd")
const ToolScript := preload("res://scripts/draft/draft_tool.gd")
const GradingScript := preload("res://scripts/draft/grading.gd")
const LayerSetScript := preload("res://scripts/draft/layer_set.gd")

const SPOT := GradingScript.SPOT
const CONTOUR := GradingScript.CONTOUR
const SLOPE := GradingScript.SLOPE


# --- helpers --------------------------------------------------------------------------


func _drawn() -> DraftController:
	var controller := ControllerScript.new()
	controller.document = DocumentScript.new()
	controller.document.changed.connect(controller._on_document_changed)
	controller.snap = SnapScript.new()
	controller.snap.bind(controller.document.entities())
	controller.tool = ToolScript.new()
	return controller


func _hud_for(controller: DraftController) -> Node:
	var hud := HudScript.new()
	hud._draft = controller
	return hud


## Stamp a spot level straight through the controller, which is what a *menu*, a key or a script would
## do - so the page is not the thing that put it there and has to notice on its own.
func _spot(controller: DraftController, at: Vector2, level: float) -> void:
	controller.set_grading_level(level)
	controller.begin_grading(SPOT)
	controller._commit(controller.tool.click(at))


func _arrow(controller: DraftController, from: Vector2, to: Vector2, percent: float) -> void:
	controller.set_grading_fall(percent)
	controller.begin_grading(SLOPE)
	controller.tool.click(from)
	controller._commit(controller.tool.click(to))


# --- the menu --------------------------------------------------------------------------


func test_the_site_menu_offers_the_ground_s_own_heights() -> void:
	var entries: Array[Dictionary] = HudScript.site_items()
	var page: Dictionary = {}
	var check: Dictionary = {}
	var line: Dictionary = {}
	for entry: Dictionary in entries:
		match String(entry.get("id", "")):
			"site.grading":
				line = entry
			"site.grade":
				page = entry
			"site.grade.check":
				check = entry
	assert(not line.is_empty(), "the Site menu says what is graded on this drawing")
	assert(StringName(line["kind"]) == &"info", "as a line rather than as a command")
	assert(not page.is_empty(), "and it offers the one page")
	assert(String(page["label"]) == "The ground's heights: levels, contours, slopes...", String(page["label"]))
	assert(String(page["method"]) == "_menu_grading_window", String(page["method"]))
	assert(StringName(page["needs"]) == HudScript.NEEDS_DRAFT, "which needs a drawing to grade")
	assert(not check.is_empty(), "and it offers the check on its own")
	assert(String(check["method"]) == "_menu_check_grading", String(check["method"]))
	var hud := HudScript.new()
	assert(hud.has_method("_menu_grading_window"), "and the method it names is there")
	assert(hud.has_method("_menu_check_grading"), "and so is the other")
	assert(hud.has_method("open_grading_window") and hud.has_method("is_grading_window_open"),
		"beside the pair that opens and reports on the page")
	hud.free()


func test_the_menu_line_says_what_is_graded_without_the_page_being_opened() -> void:
	var controller := _drawn()
	var hud := _hud_for(controller)
	assert(hud._grading_text() == "nothing on this drawing is graded yet", hud._grading_text())
	_spot(controller, Vector2.ZERO, 102.35)
	_spot(controller, Vector2(6.0, 0.0), 101.95)
	assert(hud._grading_text() == (
		"2 spot levels on this drawing, running from 101.95 m to 102.35 m"
	), hud._grading_text())
	# And a drawing that contradicts itself about its own heights says so on the menu rather than only
	# inside the page: a line that only reported the count would be hiding the one thing worth knowing.
	_arrow(controller, Vector2.ZERO, Vector2(6.0, 0.0), 2.5)
	assert(hud._grading_text() == (
		"2 spot levels and a slope arrow on this drawing, running from 101.95 m to 102.35 m"
		+ " - 1 the check disagrees with"
	), hud._grading_text())
	controller.free()
	hud.free()


func test_the_line_is_in_the_snapshot_every_menu_refresh_is_drawn_from() -> void:
	var controller := _drawn()
	var hud := _hud_for(controller)
	var world: Dictionary = hud.menu_world()
	assert(world.has("grading"), "the snapshot carries the grading")
	assert(String(world["grading"]) == hud._grading_text(), "and it is the same line")
	_spot(controller, Vector2.ZERO, 1.0)
	assert(String(hud.menu_world()["grading"]) != String(world["grading"]),
		"so a level stamped on the drawing moves the menu")
	controller.free()
	hud.free()


func test_a_scene_with_no_drawing_still_has_a_line_to_show() -> void:
	var hud := HudScript.new()
	assert(hud._grading_text() == "there is no drawing to grade", hud._grading_text())
	assert(hud._grading_rows().is_empty(), "and no records to list")
	hud._build_grading_window()
	assert(hud._grading_window != null, "though the page is built")
	hud._fill_grading_window()
	assert(hud._grading_window.report_text() == "the grading agrees with itself", "with nothing wrong")
	hud.free()


# --- the page --------------------------------------------------------------------------


func test_the_page_is_built_and_filled_without_a_window_server() -> void:
	var controller := _drawn()
	var hud := _hud_for(controller)
	hud._build_grading_window()
	assert(hud._grading_window != null, "the page is built")
	assert(not hud.is_grading_window_open(), "and not shown: a form nobody opened is not over the drawing")
	hud._fill_grading_window()
	assert(hud._grading_window.record_texts() == [HudScript.GradingWindowScript.NOTHING_YET],
		str(hud._grading_window.record_texts()))
	# What the page shows for the level is the controller's level in hand, so a page opened twice shows
	# the number the designer put in it the first time.
	controller.set_grading_level(102.35)
	controller.set_grading_fall(4.0)
	hud._fill_grading_window()
	assert(hud._grading_window.level_text() == "102.35 m", hud._grading_window.level_text())
	assert(hud._grading_window.fall_text() == "4.0 %", hud._grading_window.fall_text())
	# And once there is something on the drawing, the page lists it.
	_spot(controller, Vector2(3.0, 4.0), 102.35)
	hud._fill_grading_window()
	assert(hud._grading_window.record_texts() == ["102.35 m   (3, 4)"],
		str(hud._grading_window.record_texts()))
	hud._grading_window.choose_record(0)
	assert(hud._grading_window.chosen_kind() == SPOT, hud._grading_window.chosen_kind())
	assert(hud._grading_window.remove_enabled(), "and it can be taken off from here")
	controller.free()
	hud.free()


func test_pressing_set_and_a_tool_reaches_the_controller() -> void:
	var controller := _drawn()
	var hud := _hud_for(controller)
	hud._build_grading_window()
	hud.state_grading_level(102.35)
	assert(is_equal_approx(controller.grading_level, 102.35), str(controller.grading_level))
	assert(String(hud._grading_window.said()).contains("a level of 102.35 m"), hud._grading_window.said())
	hud.state_grading_fall(4.0)
	assert(is_equal_approx(controller.grading_fall_percent, 4.0), str(controller.grading_fall_percent))
	assert(String(hud._grading_window.said()).contains("slope arrows are drawn falling 4%"),
		hud._grading_window.said())
	hud.arm_grading_tool(SPOT)
	assert(controller.tool.kind == ToolScript.Kind.GRADE_SPOT, "the tool is out")
	assert(is_equal_approx(controller.grading_level, 102.35), "with the level in hand it was given")
	assert(not hud.is_grading_window_open(), "**and the page has stepped out of the way**")
	assert(String(controller.last_message) == "a spot level at 102.35 m", controller.last_message)
	controller.free()
	hud.free()


func test_a_tool_with_nothing_to_draw_on_is_refused_and_the_page_says_so() -> void:
	var hud := HudScript.new()
	hud._build_grading_window()
	hud.arm_grading_tool(SPOT)
	assert(String(hud._grading_window.said()).contains("there is no drawing"), hud._grading_window.said())
	var controller := _drawn()
	hud._draft = controller
	hud.arm_grading_tool("something else")
	assert(String(hud._grading_window.said()) == "that is not a kind of grading",
		hud._grading_window.said())
	controller.free()
	hud.free()


func test_changing_and_taking_off_from_the_page_is_one_gesture_each() -> void:
	var controller := _drawn()
	var hud := _hud_for(controller)
	_spot(controller, Vector2.ZERO, 102.35)
	hud._fill_grading_window()
	var before: int = controller.document.gesture_serial()
	hud.change_grading_level(SPOT, 1, 103.0)
	assert(controller.document.gesture_serial() == before + 1, "one gesture")
	assert(String(hud._grading_window.said()) == "spot level is 103.0 m", hud._grading_window.said())
	assert(hud._grading_window.record_texts() == ["103.0 m   (0, 0)"],
		"and the page has caught up: " + str(hud._grading_window.record_texts()))
	hud.remove_grading_record(SPOT, 1)
	assert(controller.grading_spots().is_empty(), "the record is off the drawing")
	assert(controller.document.count() == 0, "and its marks with it")
	assert(hud._grading_window.record_texts() == [HudScript.GradingWindowScript.NOTHING_YET],
		"and the page has caught up with that too")
	assert(String(hud._grading_window.said()) == "spot level off the drawing, with 2 marks",
		hud._grading_window.said())
	controller.free()
	hud.free()


func test_a_refusal_is_said_on_the_page_rather_than_thrown() -> void:
	var controller := _drawn()
	var hud := _hud_for(controller)
	hud._build_grading_window()
	hud.change_grading_level(CONTOUR, 7, 100.0)
	assert(String(hud._grading_window.said()) == "there is no contour 7 on this drawing",
		hud._grading_window.said())
	hud.remove_grading_record(CONTOUR, 7)
	assert(String(hud._grading_window.said()) == "there is no contour 7 on this drawing",
		hud._grading_window.said())
	assert(controller.document.count() == 0, "and nothing reached the drawing")
	controller.free()
	hud.free()


func test_the_check_is_on_the_page_and_is_what_the_menu_counts() -> void:
	var controller := _drawn()
	var hud := _hud_for(controller)
	_spot(controller, Vector2.ZERO, 102.35)
	_spot(controller, Vector2(6.0, 0.0), 101.95)
	_arrow(controller, Vector2.ZERO, Vector2(6.0, 0.0), 2.5)
	hud._fill_grading_window()
	var report: Dictionary = controller.grading_report()
	assert(int((report["findings"] as Array).size()) == 1, str(report["findings"]))
	assert(hud._grading_window.report_text().begins_with("- the arrow at (0, 0) says falling 2.5%"),
		hud._grading_window.report_text())
	assert(hud._grading_window.report_text().contains("the levels run from 101.95 m to 102.35 m"),
		"and what is worth knowing follows it: " + hud._grading_window.report_text())
	assert(hud._grading_text().ends_with("1 the check disagrees with"), hud._grading_text())
	controller.free()
	hud.free()


func test_a_page_left_open_keeps_up_with_a_drawing_that_changes_behind_it() -> void:
	# An undo does not come past the HUD, so the page reads the drawing again whenever its grading has
	# moved - a list still showing a level that is no longer on the drawing would not be an old answer,
	# it would be a wrong one.
	var controller := _drawn()
	var hud := _hud_for(controller)
	hud._build_grading_window()
	hud._fill_grading_window()
	assert(hud._grading_window.record_texts() == [HudScript.GradingWindowScript.NOTHING_YET], "empty")
	_spot(controller, Vector2.ZERO, 102.35)
	hud._tick_grading_window()
	assert(hud._grading_window.record_texts() == [HudScript.GradingWindowScript.NOTHING_YET],
		"a page that is not up is not read again")
	hud._grading_window.visible = true
	hud._tick_grading_window()
	assert(hud._grading_window.record_texts() == ["102.35 m   (0, 0)"],
		"but one that is up catches up: " + str(hud._grading_window.record_texts()))
	assert(controller.document.undo_last(), "now undo the level from outside the HUD")
	hud._tick_grading_window()
	assert(hud._grading_window.record_texts() == [HudScript.GradingWindowScript.NOTHING_YET],
		"and the page lets the level go: " + str(hud._grading_window.record_texts()))
	hud._grading_window.visible = false
	controller.free()
	hud.free()


func test_a_level_that_is_not_a_number_is_refused_on_the_page_too() -> void:
	var controller := _drawn()
	var hud := _hud_for(controller)
	hud._build_grading_window()
	controller.set_grading_level(101.0)
	hud.state_grading_level(INF)
	assert(is_equal_approx(controller.grading_level, 101.0), "the level in hand is untouched")
	assert(String(hud._grading_window.said()) == "a level is a number", hud._grading_window.said())
	hud.state_grading_fall(400.0)
	assert(is_equal_approx(controller.grading_fall_percent, 2.0), "and so is the fall")
	assert(String(hud._grading_window.said()).contains("100"), hud._grading_window.said())
	controller.free()
	hud.free()