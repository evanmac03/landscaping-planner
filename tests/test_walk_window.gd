extends Node
## Tests for the walk-through page.
##
## The page is a `Window` with no editor API, so everything below is driven with it never added to a
## tree and never shown - the same discipline the other pages follow. What is worth pinning is that
## the page holds no arithmetic: the stops are the route's own, the state is the director's own, and
## the only things the page adds are the button that starts the clock and the frame that steps it.

const WindowScript := preload("res://scripts/walk_window.gd")
const Route := preload("res://scripts/vis/walk_route.gd")


## A built page, never added to a tree. Every test frees it: a `Window` left behind makes the runner
## report resources still in use, which fails the verdict even when every assertion passed.
func _window() -> WalkWindow:
	var page: WalkWindow = WindowScript.new()
	page.build()
	return page


## The route the game walks: four places around a ten-by-eight garden.
func _yard_route() -> WalkRoute:
	return Route.for_yard(Rect2(0, 0, 10, 8))


func test_the_page_builds_its_controls_and_opens_saying_there_is_no_walk() -> void:
	var page := _window()
	for control_name: String in ["Summary", "Stops", "Play", "Stop", "Restart", "Close", "Status"]:
		assert(page.find_child(control_name, true, false) != null, "%s was built" % control_name)
	assert(page.stop_rows().is_empty(), "there are no stops to list")
	assert(not page.play(), "and nothing to walk")
	assert(page.summary_text().contains("no walk-through"), "the page says so: %s" % page.summary_text())
	assert(page.play_button().disabled, "so the walk button is dead")
	page.free()


func test_a_route_is_listed_with_its_places() -> void:
	var page := _window()
	var route := _yard_route()
	page.set_route(route)
	var rows: Array[String] = page.stop_rows()
	assert(rows.size() == route.count(), "one row per stop, got %d" % rows.size())
	assert(rows[0].contains("left"), "each row names its place: %s" % rows[0])
	assert(rows[0].contains("1.6"), "and stands at eye height: %s" % rows[0])
	assert(not page.play_button().disabled, "there is something to walk")
	assert(page.summary_text().contains("4 stops"), "and the state line is the route's own: %s" % page.summary_text())
	page.free()


func test_a_one_stop_route_is_refused_on_the_page() -> void:
	var page := _window()
	var route := Route.new()
	route.add_stop("somewhere", Vector3.ZERO, Vector3.FORWARD)
	page.set_route(route)
	assert(not page.play(), "one stop is not a walk-through")
	assert(page.status_text().contains("two stops"), "and it says why: %s" % page.status_text())
	assert(page.play_button().disabled, "so the button is dead")
	page.free()


func test_playing_marches_the_camera_along_the_route() -> void:
	var page := _window()
	var route := _yard_route()
	var camera := Camera3D.new()
	page.set_route(route, camera)
	var heard: Array[bool] = []
	page.walk_changed.connect(func() -> void: heard.append(true))
	assert(page.play(), "the walk started")
	assert(page.is_playing(), "and the clock is running")
	var first := Vector3.ZERO
	for step in 120:
		page._process(0.25)
		if step == 0:
			first = camera.transform.origin
	assert(not page.is_playing(), "the walk finished and stopped itself")
	var last: Vector3 = Vector3(route.stops()[route.count() - 1]["at"])
	assert(camera.transform.origin.is_equal_approx(last),
		"the camera stands at the last stop: %s" % camera.transform.origin)
	assert(camera.transform.origin != first, "and it walked there rather than jumping")
	assert(heard.size() >= 2, "starting and finishing were both announced, got %d" % heard.size())
	assert(page.status_text().contains("finished"), "and the page says so: %s" % page.status_text())
	camera.free()
	page.free()


func test_stopping_stands_the_walk_still() -> void:
	var page := _window()
	var camera := Camera3D.new()
	page.set_route(_yard_route(), camera)
	assert(page.play())
	page._process(0.25)
	page.stop()
	assert(not page.is_playing(), "the walk is standing still")
	assert(page.status_text().contains("stopped"), "and the page says where it got to: %s" % page.status_text())
	assert(page.stop_button().disabled, "the stop button is dead again")
	assert(not page.play_button().disabled, "and the walk can be started again")
	camera.free()
	page.free()


func test_every_button_on_the_page_is_built_without_a_keyboard_of_its_own() -> void:
	var page := _window()
	var checked := 0
	for found: Node in page.find_children("*", "Button", true, false):
		var button: Button = found
		assert(button.focus_mode == Control.FOCUS_NONE, "%s takes no focus" % button.name)
		checked += 1
	assert(checked >= 4, "there are buttons to check, got %d" % checked)
	page.free()


func test_closing_the_page_stops_the_walk_and_says_so() -> void:
	var page := _window()
	var camera := Camera3D.new()
	page.set_route(_yard_route(), camera)
	var heard: Array[bool] = []
	page.closed.connect(func() -> void: heard.append(true))
	assert(page.play())
	assert(page.is_playing())
	page._on_close_requested()
	assert(not page.is_playing(), "closing stands the walk still")
	assert(heard.size() == 1, "and the close was announced once, got %d" % heard.size())
	camera.free()
	page.free()


func test_a_presenter_with_no_garden_leaves_the_page_honest() -> void:
	var page := _window()
	page.bind(null)
	assert(page.stop_rows().is_empty(), "a page with no presenter has no route")
	assert(page.summary_text().contains("no walk-through"), "and it says so: %s" % page.summary_text())
	var bare := Node3D.new()
	page.bind(bare)
	assert(page.stop_rows().is_empty(), "a node with no yard gives no garden either")
	page.bind(null)
	bare.free()
	page.free()