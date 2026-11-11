extends Node
## The front door, driven: whether it stands at startup, where each of its two buttons leads, and that
## neither of them is a mode (specification §2).
##
## A development tool rather than part of the game. Nothing outside an embedded `Window` can click inside it
## - not a test runner's injected key, not a scripted tap - so a page has to be driven by the signals its own
## buttons emit, from a tool that has instanced the game. That is this.
##
## Run `scenes/start_door_demo.tscn` and read the console:
##
##     at startup       the front door stands: yes
##     at startup       shapes on the drawing: 0
##     the opening       the door's own screen: yes, covering 1600 by 900
##     it offers        design, camera
##     Design the garden  the door is away: yes, and the board asks how to begin: yes
##     the begin page    it offers new, open, recent, example, and its screen is still up: yes
##     New drawing        the page is away: yes, and nothing was opened: yes
##     Take a photograph  the camera opened: yes, the door still behind it: yes
##     the camera says  ...
##     the studio's door  the camera opened from the drawing: yes
##     FRONT DOOR: two ways in, neither of them a mode, and the board asks how a drawing begins
##
## Two of those lines are about what the *opening* is, and they are the two a person notices at once. The
## drawing line says the program starts with nothing drawn: the example garden - the little backyard under
## File > Examples - is something a person asks for and never something loaded on their behalf. The screen
## line says the drawing board is not shown at all until a choice is made: the furnished yard, the palette
## and the panels are the design suite's room, and this is the doorway rather than the room. Both lines are
## here so that the day either changes, this tool says so out loud.
##
## The last camera reading is whatever this machine's camera makes of the request - a picture on a computer
## with a webcam, and a sentence naming what is missing on one without. It is printed rather than judged,
## because the page is right either way.

const StartChoicesScript := preload("res://scripts/start_choices.gd")
const StartDrawingScript := preload("res://scripts/start_drawing.gd")

var _app: Node = null
var _hud: Node = null
var _failed: Array[String] = []


func _ready() -> void:
	_app = load("res://scenes/main.tscn").instantiate()
	_app.name = "App"
	add_child(_app)
	for i in 5:
		await get_tree().process_frame

	_hud = _find_scripted(_app, "hud.gd")
	var page: Node = null if _hud == null else _hud.find_child("StartWindow", true, false)
	if _hud == null or page == null:
		print("FRONT DOOR: there is no front door in main.tscn")
		get_tree().quit(1)
		return

	# 1. The door stands, because a launch has nothing behind it.
	var stood: bool = bool(_hud.call("is_front_door_open"))
	print("at startup       the front door stands: %s" % _yes(stood))
	_check(stood, "the door did not stand at startup")

	# 1b. And behind it: a drawing with nothing on it. This is the promise that the opening is *only* the
	#     choice - the example garden is under the File menu, and a person has to ask for it.
	var drawn: int = _shapes_on_the_drawing()
	print("at startup       shapes on the drawing: %d" % drawn)
	_check(drawn == 0, "the program started with %d shape(s) already on the drawing" % drawn)

	# 1c. And the sheet it stands on. The garden and the tool palette live behind this, and a person who has
	#     not yet said what they came here to do should be looking at the choice instead.
	var sheet: ColorRect = _door_screen()
	var covers: Vector2 = Vector2.ZERO if sheet == null else sheet.size
	var wanted: Vector2 = _app.get_viewport().get_visible_rect().size
	print("the opening       the door's own screen: %s, covering %s" % [
		_yes(sheet != null and sheet.visible), _sizes(covers),
	])
	_check(sheet != null and sheet.visible, "the door stood with the drawing board showing behind it")
	_check(
		covers.is_equal_approx(wanted),
		"the door's screen covers %s where the window is %s" % [_sizes(covers), _sizes(wanted)]
	)

	var offers: Array = page.call("choice_buttons")
	var names: Array[String] = []
	for id: StringName in offers:
		names.append(String(id))
	print("it offers        %s" % ", ".join(PackedStringArray(names)))
	_check(
		PackedStringArray(names) == PackedStringArray(["design", "camera"]),
		"the door offers %s rather than the drawing and the camera" % ", ".join(PackedStringArray(names))
	)

	# 2. The drawing board: the door is put away and the begin-a-drawing page takes its place, because the
	#    board is asked what the drawing should start as before a person is at it. This is the case a mode
	#    would get wrong - there is nothing to switch on - and the question belongs to the doorway, not the
	#    board.
	_press(page, StartChoicesScript.DESIGN)
	await get_tree().process_frame
	var door_gone: bool = not bool(_hud.call("is_front_door_open"))
	var begin_up: bool = bool(_hud.call("is_start_drawing_window_open"))
	print("Design the garden  the door is away: %s, and the board asks how to begin: %s" % [
		_yes(door_gone), _yes(begin_up),
	])
	_check(door_gone and begin_up, "the drawing board choice did not ask how the drawing should start")

	var begin_page: Node = _hud.find_child("StartDrawingWindow", true, false)
	var ways: Array[String] = []
	if begin_page != null:
		for id: StringName in begin_page.call("choice_buttons"):
			ways.append(String(id))
	print("the begin page    it offers %s, and its screen is still up: %s" % [
		", ".join(PackedStringArray(ways)), _yes(_sheet_is_up()),
	])
	_check(
		PackedStringArray(ways) == PackedStringArray(["new", "open", "recent", "example"]),
		"the begin page offers %s rather than the four ways to start" % ", ".join(PackedStringArray(ways))
	)
	_check(_sheet_is_up(), "the begin page stood with the drawing board showing behind it")

	# 2b. Taking the first way: the page is away and the sheet goes with it, and nothing else was opened -
	#     the drawing behind is the one that was already there.
	if begin_page != null:
		_press(begin_page, StartDrawingScript.NEW)
	await get_tree().process_frame
	var begin_gone: bool = not bool(_hud.call("is_start_drawing_window_open"))
	var nothing_opened: bool = not bool(_hud.call("is_camera_window_open"))
	print("New drawing        the page is away: %s, and nothing was opened: %s" % [
		_yes(begin_gone), _yes(nothing_opened),
	])
	_check(begin_gone and nothing_opened, "taking a way to begin left something open")
	_check(not _sheet_is_up(), "the sheet stayed up after the begin page went")
	# And the first way leaves an empty drawing rather than an example: the yard standing behind the board is
	# scenery, not shapes on the plan, so the count is the honest answer to "is this a new sheet".
	var after_new: int = _shapes_on_the_drawing()
	print("New drawing        shapes on the drawing: %d" % after_new)
	_check(after_new == 0, "a new drawing was not empty: %d shape(s) on it" % after_new)

	# 3. The camera: opened *over* the door rather than instead of it, which is what makes closing it come
	#    back to a screen that was already standing.
	_hud.call("open_the_front_door")
	await get_tree().process_frame
	_press(page, StartChoicesScript.CAMERA)
	for i in 20:
		await get_tree().process_frame
	var camera_up: bool = bool(_hud.call("is_camera_window_open"))
	var door_behind: bool = bool(_hud.call("is_front_door_open"))
	print("Take a photograph  the camera opened: %s, the door still behind it: %s" % [
		_yes(camera_up), _yes(door_behind),
	])
	_check(camera_up, "the camera choice did not open the camera")
	_check(door_behind, "the camera replaced the door instead of standing over it")

	var camera_page: Node = _hud.find_child("CameraWindow", true, false)
	if camera_page != null:
		# The summary is the line that says what the camera can do here; the status line is only the
		# instruction it opened with.
		print("the camera says  %s" % String(camera_page.call("summary_text")))
		var shutter: Button = camera_page.call("shutter_button") as Button
		print("its shutter      %s" % (
			"ready" if shutter != null and not shutter.disabled else "not ready on this machine"
		))

	# 4. And the other way round: the drawing's own door onto the same camera, which is the entry the Site
	#    menu runs. Closing the camera first, so this is the drawing opening it rather than the door.
	_hud.call("close_camera_window")
	await get_tree().process_frame
	var closed: bool = not bool(_hud.call("is_camera_window_open"))
	_hud.call("open_camera_window")
	for i in 3:
		await get_tree().process_frame
	var reopened: bool = bool(_hud.call("is_camera_window_open"))
	print("the studio's door  the camera opened from the drawing: %s (after closing it: %s)" % [
		_yes(reopened), _yes(closed),
	])
	_check(closed and reopened, "the camera from the drawing did not open, or did not close")

	print("FRONT DOOR: %s" % (
		"two ways in, neither of them a mode, and the board asks how a drawing begins"
		if _failed.is_empty() else "WRONG: %s" % "; ".join(_failed)
	))
	await get_tree().process_frame
	get_tree().quit(0 if _failed.is_empty() else 1)


# --- driving it ---------------------------------------------------------------------------------


## Press one of the door's buttons, the way the button itself does: by emitting the signal its press emits.
func _press(page: Node, id: StringName) -> void:
	var button: Button = page.call("button_of", id) as Button
	if button == null:
		_check(false, "the door has no button for %s" % String(id))
		return
	button.pressed.emit()


func _check(right: bool, complaint: String) -> void:
	if not right:
		_failed.append(complaint)


func _yes(answer: bool) -> String:
	return "yes" if answer else "no"


func _sizes(size: Vector2) -> String:
	return "%d by %d" % [roundi(size.x), roundi(size.y)]


## The sheet the front door stands on, asked of the HUD by the name the HUD gives it - so that a door that
## lost its screen is a door this tool notices rather than one it assumes.
func _door_screen() -> ColorRect:
	if _hud == null:
		return null
	return _hud.find_child("StartBackdrop", true, false) as ColorRect


## Whether the doorway's sheet is on screen, which it should be exactly while one of the two doorway pages
## - the front door or the begin-a-drawing page - is standing.
func _sheet_is_up() -> bool:
	var sheet: ColorRect = _door_screen()
	return sheet != null and sheet.visible


## The first node under the app carrying a given script, found by the script rather than by a node path a
## scene edit would move out from under this tool.
func _find_scripted(root: Node, file: String) -> Node:
	for node: Node in root.find_children("*", "", true, false):
		var script: Script = node.get_script()
		if script != null and String(script.resource_path).ends_with(file):
			return node
	return null


## How many shapes are on the drawing the program is holding, asked of the drawing itself so that the answer
## is what the design suite would plot and not what some label happens to say.
func _shapes_on_the_drawing() -> int:
	var controller: Node = _find_scripted(_app, "draft_controller.gd")
	if controller == null:
		return -1
	var document: Object = controller.get("document") as Object
	if document == null or not document.has_method("plotting_entities"):
		return -1
	var shapes: Array = document.call("plotting_entities") as Array
	return shapes.size()