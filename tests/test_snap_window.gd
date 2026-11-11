extends Node
## Tests for the snapping page.
##
## The page is a `Window` with no editor API, so everything below is driven with it never added to a
## tree and never shown - the same discipline the other pages follow. What is worth pinning is that
## the page holds no state: every control it shows comes from the controller's own settings, and
## every switch it works goes back through the controller's own setters, so a keyboard toggle and the
## page can never disagree.

const WindowScript := preload("res://scripts/snap_window.gd")
const ControllerScript := preload("res://scripts/draft/draft_controller.gd")
const SnapScript := preload("res://scripts/draft/snap_engine.gd")


## A built page, never added to a tree. Every test frees it: a `Window` left behind makes the runner
## report resources still in use, which fails the verdict even when every assertion passed.
func _page() -> SnapWindow:
	var page: SnapWindow = WindowScript.new()
	page.build()
	return page


## A controller with an engine and no scene around it.
func _controller() -> DraftController:
	var controller := ControllerScript.new()
	controller.snap = SnapScript.new()
	return controller


func test_the_page_builds_a_switch_for_everything_it_can_set() -> void:
	var page := _page()
	for control_name: String in ["SnapToggle", "Ortho", "Polar", "PolarStep", "GridSnap", "GridStep",
			"Close", "Status"]:
		assert(page.find_child(control_name, true, false) != null, "%s was built" % control_name)
	# One checkbox per object snap, named after the engine's own label for it.
	for mode: int in WindowScript.mode_order():
		var box: CheckBox = page.mode_button(mode)
		assert(box != null, "the %s snap has a switch" % WindowScript.mode_label(mode))
		assert(box.text == WindowScript.mode_label(mode), "labelled as the engine labels it")
	page.free()


func test_a_page_with_no_controller_says_so_and_switches_nothing() -> void:
	var page := _page()
	assert(page.master_button().disabled, "there is nothing to switch")
	assert(page.status_text().contains("nothing here to snap"), page.status_text())
	for mode: int in WindowScript.mode_order():
		assert(page.mode_button(mode).disabled, "and every snap switch is dead")
	page.free()


func test_binding_a_controller_shows_its_settings() -> void:
	var page := _page()
	var controller := _controller()
	page.bind(controller)
	assert(page.master_button().button_pressed, "snapping is on to begin with")
	assert(not page.ortho_button().button_pressed, "ortho is off")
	assert(not page.grid_button().button_pressed, "and grid snapping")
	assert(is_equal_approx(page.grid_step_field().value, controller.grid_step()), "the grid pitch is shown")
	assert(page.status_text().contains("8 object snaps live"), page.status_text())
	controller.free()
	page.free()


func test_a_switch_writes_through_to_the_controller() -> void:
	var page := _page()
	var controller := _controller()
	page.bind(controller)
	# Pressing a checkbox is what a person does; the page must not keep the answer to itself.
	page.mode_button(SnapScript.Mode.NEAREST).button_pressed = false
	assert(not controller.is_snap_mode(SnapScript.Mode.NEAREST), "the catch-all snap was turned off")
	page.ortho_button().button_pressed = true
	assert(controller.is_ortho(), "and ortho was turned on")
	page.grid_button().button_pressed = true
	assert(controller.is_grid_snap())
	# A `Range`'s `value` set from code emits nothing (a person typing in the box does), so the test
	# proves the field is wired and then calls the method the signal calls - the off-tree discipline
	# the other page tests follow.
	assert(
		page.grid_step_field().value_changed.is_connected(page._on_grid_step_changed),
		"the grid pitch field is wired to the page"
	)
	page._on_grid_step_changed(2.0)
	assert(is_equal_approx(controller.grid_step(), 2.0), "a typed grid pitch reaches the drawing")
	page.master_button().button_pressed = false
	assert(not controller.is_snapping(), "and the master switch turns snapping off")
	controller.free()
	page.free()


func test_the_master_switch_off_dims_the_modes() -> void:
	var page := _page()
	var controller := _controller()
	page.bind(controller)
	page.master_button().button_pressed = false
	assert(not controller.is_snapping())
	for mode: int in WindowScript.mode_order():
		assert(page.mode_button(mode).disabled, "a dormant snap does not look live")
	assert(page.status_text().contains("Snapping is off"), page.status_text())
	page.master_button().button_pressed = true
	for mode: int in WindowScript.mode_order():
		assert(not page.mode_button(mode).disabled, "and they come back with it")
	controller.free()
	page.free()


func test_a_setting_changed_elsewhere_moves_the_page() -> void:
	var page := _page()
	var controller := _controller()
	page.bind(controller)
	# A keyboard toggle, or the menu, moves the setting: the page follows it rather than going stale.
	controller.set_polar(true)
	controller.set_polar_step_degrees(15.0)
	assert(page.polar_button().button_pressed, "the page shows polar on")
	assert(page.polar_step_field().selected == 0, "and the increment the setting now holds")
	assert(page.status_text().contains("polar every 15"), page.status_text())
	controller.free()
	page.free()


func test_closing_the_page_says_so() -> void:
	var page := _page()
	var heard: Array[bool] = []
	page.closed.connect(func() -> void: heard.append(true))
	page._on_close_requested()
	assert(heard.size() == 1, "the close was announced once, got %d" % heard.size())
	assert(not page.visible, "and the window is put away")
	page.free()


func test_the_page_builds_its_switches_without_a_keyboard_of_their_own() -> void:
	var page := _page()
	var checked := 0
	for found: Node in page.find_children("*", "Button", true, false):
		var button: Button = found
		assert(button.focus_mode == Control.FOCUS_NONE, "%s takes no focus" % button.name)
		checked += 1
	assert(checked >= 9, "there are switches to check, got %d" % checked)
	page.free()