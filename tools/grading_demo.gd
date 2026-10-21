extends Node2D
## A live pass over the ground's own heights: spot levels, a contour and a slope arrow stated on the
## plan, and the check that catches the arrow contradicting the levels under it.
##
## This is a development tool, not part of the game. It instances the **real main scene** and drives the
## **real page** through the buttons its own captions name, so the module, the page, the HUD, the
## controller and the plan canvas are all the shipped ones, and it prints every step. What is left on
## screen is a plan carrying a level and its label, a contour line, and an arrow that falls.
##
## Run `res://scenes/grading_demo.tscn`.
##
## The picks themselves are made through the controller's own click rather than by moving a mouse: a
## demonstration cannot move one. Everything *around* the picks - the level in hand, the tool, the
## page - goes through the buttons a person presses.

const MAIN := preload("res://scenes/main.tscn")
const ViewScript := preload("res://scripts/view_controller.gd")
const GradingScript := preload("res://scripts/draft/grading.gd")

const SPOT := GradingScript.SPOT
const CONTOUR := GradingScript.CONTOUR
const SLOPE := GradingScript.SLOPE

## The places the demonstration states something at, and the levels it states there. 0.40 m of fall over
## six metres is 6.7%, so an arrow drawn at 2.5% is a drawing that disagrees with itself - which is the
## thing the check exists to catch, and the reason this pass draws one.
const HIGH_AT := Vector2(0.0, 0.0)
const LOW_AT := Vector2(6.0, 0.0)
const HIGH := 102.35
const LOW := 101.95
const CONTOUR_LEVEL := 101.5
const STATED_FALL := 2.5


func _ready() -> void:
	var main: Node = MAIN.instantiate()
	add_child(main)
	var hud: Node = main.get_node_or_null(^"Hud")
	var controller: Node = main.get_node_or_null(^"DraftController")
	var canvas: Node2D = main.get_node_or_null(^"PlanLayer/PlanCanvas")
	if hud == null or controller == null or canvas == null:
		print("no HUD, no drafting controller or no plan canvas in the main scene")
		return

	# The flat plan is the view that fills its own paper and draws the drawing on it. The program opens
	# in the 3D overhead view, so the pass walks over to the plan first and lets the cross-fade settle
	# before anything is read off the screen.
	var view_controller: Node = main.get_node_or_null(^"ViewController")
	if view_controller != null:
		view_controller.show_mode(ViewScript.ViewMode.PLAN_2D)
		for _frame in 90:
			await get_tree().process_frame
	print("the view is the flat plan: ",
		view_controller != null and view_controller.mode == ViewScript.ViewMode.PLAN_2D,
		", and the plan is on screen: ", canvas.is_visible_in_tree())

	# What the plan looks like *before* anything is stated: the only honest baseline for "something was
	# drawn here" is the same pixel before it was.
	await _settle()
	var before := _shot()
	print("the drawing holds ", controller.document.count(), " shapes and ",
		controller.grading_summary())

	print("--- stating a level, as the page's buttons do ---")
	hud.open_grading_window()
	print("the page is up: ", hud.is_grading_window_open(),
		"  it says: ", hud._grading_window.report_text())
	hud._grading_window.set_level(HIGH)
	print("pressing \"Set the level\": ", _press(hud, "Set the level"),
		"  -> ", controller.last_message)
	print("pressing \"Spot level here\": ", _press(hud, "Spot level here"),
		"  -> ", controller.last_message)
	print("  and the page stepped out of the way: ", not hud.is_grading_window_open())
	_pick(controller, HIGH_AT)
	print("  ", controller.last_message)
	print("  the drawing now holds ", controller.document.count(), " shapes on ",
		controller.document.plotting_entities().size(), " plotting")

	print("--- the second level, six metres away ---")
	hud.open_grading_window()
	hud._grading_window.set_level(LOW)
	_press(hud, "Set the level")
	_press(hud, "Spot level here")
	_pick(controller, LOW_AT)
	print("  ", controller.last_message)

	print("--- a contour at 101.50 m ---")
	hud.open_grading_window()
	hud._grading_window.set_level(CONTOUR_LEVEL)
	_press(hud, "Set the level")
	_press(hud, "Draw a contour")
	# A contour collects points until it is told to stop, exactly as a polyline does.
	for point: Vector2 in [Vector2(-2.0, 3.0), Vector2(4.0, 5.0), Vector2(10.0, 3.0)]:
		controller.tool.click(point)
	_pick_finished(controller)
	print("  ", controller.last_message)

	print("--- a slope arrow stating a fall of ", STATED_FALL, "% ---")
	hud.open_grading_window()
	hud._grading_window.set_fall(STATED_FALL)
	print("pressing \"Set the fall\": ", _press(hud, "Set the fall"),
		"  -> ", controller.last_message)
	_press(hud, "Draw a slope arrow")
	_pick(controller, HIGH_AT)
	_pick(controller, LOW_AT)
	print("  ", controller.last_message)

	print("--- what the drawing holds now ---")
	print(controller.grading_summary())
	for row: Dictionary in controller.grading_rows():
		print("  ", row["kind_name"], " ", row["id"], ": ", row["text"])
	print("the drawing holds ", controller.document.count(), " shapes, ",
		controller.document.plotting_entities().size(), " of them plotting")

	print("--- and what the check makes of it ---")
	var report: Dictionary = controller.grading_report()
	print("the check agrees with it: ", report["ok"])
	for finding: String in report["findings"]:
		print("  WRONG: ", finding)
	for note: String in report["notes"]:
		print("  worth knowing: ", note)
	print("the page says the same: ", hud._grading_window.report_text().split("\n")[0])
	print("and the Site menu's own line counts it: ", hud._grading_text())

	print("--- what the plan really drew ---")
	hud.close_grading_window()
	# The checked rows are read off the framebuffer rather than assumed: a pass that says the canvas
	# holds the record has not said that anything was drawn.
	await _settle()
	var after := _shot()
	var middle: Vector2 = canvas.world_to_screen(Vector3(HIGH_AT.x, 0.0, HIGH_AT.y))
	var contour: Vector2 = canvas.world_to_screen(Vector3(4.0, 0.0, 5.0))
	var shaft: Vector2 = canvas.world_to_screen(Vector3(LOW_AT.x * 0.5, 0.0, 0.0))
	var elsewhere := Vector2(get_viewport().get_visible_rect().size.x - 200.0,
		get_viewport().get_visible_rect().size.y - 200.0)
	print("  the spot level's mark lands at screen ", middle, " and ",
		_changed_pixels(before, after, middle), " pixels of the 625 around it changed")
	print("  the label beside it: ",
		_changed_pixels(before, after, middle + Vector2(24.0, -12.0)),
		" pixels of the 625 beside it changed")
	print("  the contour at screen ", contour, ": ",
		_changed_pixels(before, after, contour), " pixels changed")
	print("  the arrow's shaft at screen ", shaft, ": ",
		_changed_pixels(before, after, shaft), " pixels changed")
	# The control, and the reason it is here: a whole frame that moved - a cross-fade, a palette
	# fading, the yard breathing - would make every count above meaningless.
	print("  and a patch nowhere near any of them changed ",
		_changed_pixels(before, after, elsewhere), " pixels, so it is the grading that moved")
	print("  the screen is ", after.get_size(), ", saved to res://preview/grading_demo.png")
	for found: Node in _every_window(main):
		var rect := Rect2i((found as Window).position, (found as Window).size)
		print("  window ", found.name, " is ", "shown" if found.visible else "put away", " at ", rect)
	DirAccess.make_dir_recursive_absolute("res://preview")
	after.save_png("res://preview/grading_demo.png")


## The level in hand and the tool out, then one click where the level belongs.
func _pick(controller: Node, at: Vector2) -> void:
	controller._commit(controller.tool.click(at))


## A contour's last pick, which is Enter rather than a click.
func _pick_finished(controller: Node) -> void:
	controller._commit(controller.tool.finish())


## Two frames and a drawn frame, so a capture is of a settled screen.
func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw


func _shot() -> Image:
	return get_viewport().get_texture().get_image()


## How many pixels of the square around a place on the plan changed between two captures. A mark's own
## line is a pixel wide and can be lost to rounding, so a count over a square is the honest reading of
## "something was drawn here".
func _changed_pixels(before: Image, after: Image, at: Vector2, half: int = 12) -> int:
	var changed := 0
	for dy in range(-half, half + 1):
		for dx in range(-half, half + 1):
			var x := clampi(int(at.x) + dx, 0, after.get_width() - 1)
			var y := clampi(int(at.y) + dy, 0, after.get_height() - 1)
			if not before.get_pixel(x, y).is_equal_approx(after.get_pixel(x, y)):
				changed += 1
	return changed


## Every `Window` under a node, however deep, because the ones that matter here are built in code and
## hang off the HUD rather than sitting in the scene file.
func _every_window(under: Node) -> Array[Window]:
	var found: Array[Window] = []
	for child: Node in under.get_children():
		if child is Window:
			found.append(child as Window)
		found.append_array(_every_window(child))
	return found


## Press a button on the grading page by the caption a person reads, so the pass goes through the same
## signal the program does rather than calling the handler behind it.
func _press(hud: Node, caption: String) -> bool:
	var window: Node = hud._grading_window
	if window == null:
		return false
	for found: Node in window.find_children("*", "Button", true, false):
		var button := found as Button
		if button.text == caption:
			button.pressed.emit()
			return true
	return false