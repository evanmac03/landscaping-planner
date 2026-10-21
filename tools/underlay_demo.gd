extends Node2D
## A live pass over the picture under the drawing: a scan of a site plan read in, kept beside the
## drawing and laid under everything on the plan.
##
## This is a development tool, not part of the game. It instances the **real main scene** and drives the
## **real page** through the buttons its own captions name, so the reader, the page, the HUD, the
## controller and the plan canvas are all the shipped ones, and it prints every step. What is left on
## screen is the plan with a picture over the ground and under the linework.
##
## Run `res://scenes/underlay_demo.tscn`.
##
## The picture is made here rather than shipped, and it is made to look like what it stands for - a
## photocopied site plan with a house, a lot line and a scale bar - because a demo of a tracing aid is
## only a demo if you can see the thing you are tracing.

const MAIN := preload("res://scenes/main.tscn")
const ViewScript := preload("res://scripts/view_controller.gd")
const RasterUnderlayScript := preload("res://scripts/draft/raster_underlay.gd")
const EntityScript := preload("res://scripts/draft/draft_entity.gd")
const LayerSetScript := preload("res://scripts/draft/layer_set.gd")

const PICTURE := "user://underlay-demo-scan.png"
const PAPER := Color(0.93, 0.91, 0.86, 1.0)
const INK := Color(0.12, 0.13, 0.15, 1.0)
const INK_LIGHT := Color(0.45, 0.46, 0.5, 1.0)


func _ready() -> void:
	var main: Node = MAIN.instantiate()
	add_child(main)
	var hud: Node = main.get_node_or_null(^"Hud")
	var controller: Node = main.get_node_or_null(^"DraftController")
	var canvas: Node2D = main.get_node_or_null(^"PlanLayer/PlanCanvas")
	if hud == null or controller == null or canvas == null:
		print("no HUD, no drafting controller or no plan canvas in the main scene")
		return

	# The flat plan is the only view that draws a picture: it is the one that fills its own paper,
	# draws the yard's ground flat and then lays the picture over that ground. The program opens in the
	# 3D overhead view, so the pass walks over to the plan first and lets the cross-fade settle before
	# anything is read off the screen.
	var view_controller: Node = main.get_node_or_null(^"ViewController")
	if view_controller != null:
		view_controller.show_mode(ViewScript.ViewMode.PLAN_2D)
		for _frame in 90:
			await get_tree().process_frame
	print("the view is the flat plan: ",
		view_controller != null and view_controller.mode == ViewScript.ViewMode.PLAN_2D,
		", and the plan is on screen: ", canvas.is_visible_in_tree())

	print("--- a scan of a site plan ---")
	_make_picture(PICTURE)
	print("written to ", ProjectSettings.globalize_path(PICTURE))
	# The design first, so the picture has something to go under: a house pad and a bed outline.
	_draw_a_small_design(controller)
	print("the drawing holds ", controller.document.count(), " shapes before the picture")

	print("--- choosing it, as the button does ---")
	hud.open_underlay_window()
	_press(hud, "Choose a picture...")
	# The chooser is a file dialog, and a file dialog is a modal surface: it is put away here, because
	# what this pass is for is the picture on the plan and a dialog left over it hides the subject.
	hud._underlay_dialog.hide()
	hud._on_underlay_chosen(PICTURE)
	for line: String in hud._underlay_window.report_text().split("\n"):
		print("  ", line)

	print("--- placing it, as the button does ---")
	_press(hud, "Put it under the drawing")
	print("status: ", controller.last_message)
	print("the drawing holds ", controller.underlays().size(), " picture(s)")
	var picture: Dictionary = controller.underlays()[0]
	print("  ", RasterUnderlayScript.describe(picture, controller.document.units))
	print("  it lies ", snappedf(picture["x"], 0.01), ", ", snappedf(picture["z"], 0.01),
		" - the middle of the drawing's own extent")
	print("  across ", snappedf(picture["width_m"], 0.01), " m and deep ",
		snappedf(RasterUnderlayScript.height_of(picture), 0.01), " m, from its own pixel proportion")

	print("--- what the drawing thinks of it ---")
	print("shapes on the drawing: ", controller.document.count(),
		"  (a picture is not geometry)")
	print("of which plotting: ", controller.document.plotting_entities().size(),
		"  (a picture never plots)")
	print("the drawing's own extent: ", controller.document.bounds(),
		"  (a picture does not move it)")
	print("what is under the drawing: ", controller.underlay_summary())

	print("--- what the plan canvas will draw ---")
	var texture: Texture2D = canvas._underlay_texture(String(picture["path"]))
	print("the canvas read the picture: ", texture != null,
		"  ", (str(texture.get_size()) if texture != null else ""))
	print("the plan shows it: ", canvas.document != null and canvas.document.visible_underlays().size() == 1)

	print("--- and it can be changed and taken off again ---")
	var id := int(picture["id"])
	print("a quarter turn: ", controller.change_underlay(id, {"rotation_deg": 0.0, "opacity": 0.5}))
	print("taking it off: ", controller.remove_underlay(id),
		"  leaving ", controller.underlays().size(), " under the drawing")
	print("and undo puts it back: ", controller.document.undo_last(),
		"  ", controller.underlay_summary())

	print("--- what is left on screen ---")
	print("the page is up: ", hud.is_underlay_window_open(),
		", the drawing holds ", controller.underlays().size(), " picture(s) and ",
		controller.document.count(), " shapes")
	# And the page is put away so the plan underneath it can be seen: a page left over the drawing
	# hides the thing this pass was about.
	hud.close_underlay_window()
	print("page closed: ", not hud.is_underlay_window_open())

	# What the plan actually put on screen, read off the framebuffer rather than assumed: a
	# demonstration that says "the canvas has the texture" has not said that anything was drawn.
	print("--- what the plan really drew ---")
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var shot := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("res://preview")
	var live: Dictionary = controller.underlays()[0]
	var corners: PackedVector2Array = RasterUnderlayScript.corners_of(live)
	for index in corners.size():
		var corner: Vector2 = canvas.world_to_screen(Vector3(corners[index].x, 0.0, corners[index].y))
		print("  corner ", index, " of the picture is at screen ", corner)
	var middle: Vector2 = canvas.world_to_screen(Vector3(0.0, 0.0, 0.0))
	var with_it := _pixel_at(shot, middle)
	print("  the middle of the picture is at screen ", middle, " and the screen there reads ", with_it)
	# The decisive check, and the only honest one: the same pixel with the picture put away. A
	# demonstration that the canvas *holds* the texture has not said that anything was drawn.
	RasterUnderlayScript.set_visible(live, false)
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var without := _pixel_at(get_viewport().get_texture().get_image(), middle)
	RasterUnderlayScript.set_visible(live, true)
	print("  the same pixel with the picture put away reads ", without)
	print("  so the plan really draws it: ", not with_it.is_equal_approx(without))
	print("  the screen is ", shot.get_size(), ", saved to res://preview/underlay_demo.png")
	# And what else is on screen, because a rectangle that is not the picture in the captured frame
	# would otherwise be mistaken for one: every window in the scene, and where it sits.
	for found: Node in _every_window(main):
		var rect: Rect2i = Rect2i(found.position, found.size)
		print("  window ", found.name, " is ", "shown" if found.visible else "put away", " at ", rect)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://preview/underlay_demo.png")


## One pixel of a screen, with the edges held in so a corner of the picture cannot fall off it.
func _pixel_at(screen: Image, at: Vector2) -> Color:
	return screen.get_pixel(
		clampi(int(at.x), 0, screen.get_width() - 1), clampi(int(at.y), 0, screen.get_height() - 1)
	)


## Every `Window` under a node, however deep, because the ones that matter here are built in code and
## hang off the HUD rather than sitting in the scene file.
func _every_window(under: Node) -> Array[Window]:
	var found: Array[Window] = []
	for child: Node in under.get_children():
		if child is Window:
			found.append(child as Window)
		found.append_array(_every_window(child))
	return found


## A scan of a site plan: paper, a heavy lot line, a house, a driveway, a tree ring and a scale bar.
## Made by hand because a demonstration that needs a file shipped with it is a demonstration that
## breaks the day somebody moves it.
func _make_picture(path: String) -> void:
	var image := Image.create_empty(640, 480, false, Image.FORMAT_RGBA8)
	image.fill(PAPER)
	_rule(image, Rect2i(6, 6, 628, 468), 4, INK)
	_rule(image, Rect2i(24, 24, 592, 432), 1, INK_LIGHT)
	# A house, its garage, a driveway, a shed and a tree.
	image.fill_rect(Rect2i(96, 120, 224, 168), INK_LIGHT)
	_rule(image, Rect2i(96, 120, 224, 168), 3, INK)
	image.fill_rect(Rect2i(336, 140, 128, 96), INK_LIGHT)
	_rule(image, Rect2i(336, 140, 128, 96), 3, INK)
	_rule(image, Rect2i(96, 296, 368, 40), 2, INK)
	image.fill_rect(Rect2i(430, 330, 96, 72), INK_LIGHT)
	_rule(image, Rect2i(430, 330, 96, 72), 3, INK)
	# A circle is drawn as a ring by walking the pixels, which is enough to read as a tree at this size.
	var centre := Vector2(520.0, 140.0)
	for step in 720:
		var angle := TAU * float(step) / 720.0
		var at := centre + Vector2(cos(angle), sin(angle)) * 54.0
		_pixel(image, int(at.x), int(at.y), 3, INK)
	# A scale bar, so the picture says what it is worth the way a real one does.
	image.fill_rect(Rect2i(96, 424, 300, 8), INK)
	for tick in [96, 246, 396]:
		_rule(image, Rect2i(tick, 414, 3, 20), 1, INK)
	RasterUnderlay.ensure_dir()
	var failed := image.save_png(path)
	print("a ", image.get_size(), " scan was written: ", failed == OK)


## A few pixels of line at a point, so a one-pixel ring is not lost to rounding.
func _pixel(image: Image, x: int, y: int, size: int, colour: Color) -> void:
	image.fill_rect(Rect2i(x, y, size, size), colour)


func _rule(image: Image, rect: Rect2i, thickness: int, colour: Color) -> void:
	image.fill_rect(Rect2i(rect.position.x, rect.position.y, rect.size.x, thickness), colour)
	image.fill_rect(
		Rect2i(rect.position.x, rect.position.y + rect.size.y - thickness, rect.size.x, thickness), colour
	)
	image.fill_rect(Rect2i(rect.position.x, rect.position.y, thickness, rect.size.y), colour)
	image.fill_rect(
		Rect2i(rect.position.x + rect.size.x - thickness, rect.position.y, thickness, rect.size.y), colour
	)


func _draw_a_small_design(controller: Node) -> void:
	var document: Object = controller.document
	document.begin_gesture("laying out a pad")
	document.add(
		EntityScript.make_polyline(
			PackedVector2Array([
				Vector2(-6.0, -4.0), Vector2(3.0, -4.0), Vector2(3.0, 3.0), Vector2(-6.0, 3.0),
			]),
			true
		),
		LayerSetScript.NEW_HARDSCAPE
	)
	document.add(
		EntityScript.make_polyline(
			PackedVector2Array([Vector2(0.0, 5.0), Vector2(10.0, 5.0), Vector2(10.0, 9.0), Vector2(0.0, 9.0)]),
			true
		),
		LayerSetScript.NEW_BED
	)


## Press a button on the page by the caption a person reads, so the demonstration goes through the
## same signal the program does rather than calling the handler behind it.
func _press(hud: Node, caption: String) -> bool:
	var window: Node = hud._underlay_window
	if window == null:
		return false
	for found: Node in window.find_children("*", "Button", true, false):
		var button := found as Button
		if button.text == caption:
			button.pressed.emit()
			return true
	return false