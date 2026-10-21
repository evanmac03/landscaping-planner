extends Node2D
## A live pass over Escape on the pages that live in a `Window`.
##
## This is a development tool, not part of the game. It instances the **real main scene**, opens every
## page through the HUD's own door, and sends a **real Escape key** through the running program's input
## pipeline - because which node ever sees the key while a page has the keyboard cannot be answered by
## reading a script, and because "every page the HUD holds is on the list" is a claim about the scene
## the program really builds rather than about the list itself.
##
## Run `res://scenes/page_escape_demo.tscn`.
##
## The first version of this pass was a probe: it put one node inside a page and one beside the HUD and
## pressed the key once. The node inside saw it; the node beside the HUD saw nothing; and the page
## stayed open. That is why the closer in `scripts/page_escape.gd` has to live inside each page, and
## this pass is what replaced the probe.

const MAIN := preload("res://scenes/main.tscn")

## Every page this HUD opens that lives in a `Window`: what to call it, and the door that opens it. Read
## from the page's own `visible` rather than from a predicate per page, so a page that is up is a page
## that is up whatever it is called.
const PAGES: Array = [
	["the manual", "open_help_window"],
	["the plant library", "open_plant_browser"],
	["the command palette", "open_command_palette"],
	["the ground under the garden", "open_ground_window"],
	["the sheet set", "open_sheet_window"],
	["the revisions", "open_revision_window"],
	["the site map", "open_osm_window"],
	["the picture under the drawing", "open_underlay_window"],
	["the ground's own heights", "open_grading_window"],
	["the nursery order", "open_plant_order_window"],
	["the sun and the shadows", "open_sun_window"],
	["the estimate", "open_estimate_window"],
	["the pipeline", "open_pipeline_board"],
	["the schedule", "open_schedule_board"],
	["job costing", "open_cost_window"],
	["billing", "open_billing_window"],
	["the ledger", "open_ledger_window"],
	["the figures", "open_analytics_window"],
]

var _hud: Node = null


func _ready() -> void:
	var main: Node = MAIN.instantiate()
	add_child(main)
	_hud = main.get_node_or_null(^"Hud")
	if _hud == null:
		print("no HUD")
		return
	await _settle()

	print("--- every window the HUD holds is one it lets Escape close ---")
	var held: Array[Window] = _every_window(_hud)
	var listed: Array[Window] = _hud.pages_in_windows()
	for page: Window in held:
		print("  ", page.name, ": on the list ", listed.has(page),
			", has a closer inside it ", page.get_node_or_null(^"PageEscape") != null)
	print("  the HUD holds ", held.size(), " windows and names ", listed.size(),
		" of them; every one that is held must be named, or Escape silently stops working on it")

	print("--- one real Escape at each page ---")
	for pair: Array in PAGES:
		await _page_away(String(pair[0]), String(pair[1]))

	print("--- a page whose field has the keyboard ---")
	await _field_first()

	print("--- with nothing up ---")
	print("  the HUD's own ladder answers for nothing: ", _hud.escape_puts_away())
	print("  and no page is left up: ", _windows_up().is_empty())


## Open a page through its own door, take a real Escape at it, and report both halves.
func _page_away(title: String, opener: String) -> void:
	if not _hud.has_method(opener):
		print("  ", title, ": this HUD has no door called ", opener, " any more")
		return
	var before: Array[Window] = _windows_up()
	_hud.call(opener)
	await _settle()
	var page: Window = _newly_up(before)
	if page == null:
		print("  ", title, ": it did not come up, so there is nothing to test")
		return
	# What has the keyboard *inside the page* is asked of the page's own viewport: a subwindow is a
	# viewport of its own, and the root one knows nothing about its focus.
	var focused: Control = page.gui_get_focus_owner()
	await _press_escape()
	var once: bool = page.visible
	if page.visible:
		await _press_escape()
	print("  ", title, ": up -> Escape -> up: ", once, " after one, ", page.visible, " after two",
		"   (", page.name, ", its own focus: ", focused != null, ", the window is focused: ",
		page.has_focus(), ")")


## A page with a text field in it: the field has the keyboard, and the question is whether the key still
## reaches the page. It is a different fact from whether the page answers Escape at all, and worth
## seeing either way.
func _field_first() -> void:
	var before: Array[Window] = _windows_up()
	_hud.open_help_window()
	await _settle()
	var page: Window = _newly_up(before)
	if page == null:
		print("  the manual did not come up, so there is nothing to test")
		return
	var fields: Array[Node] = page.find_children("*", "LineEdit", true, false)
	if fields.is_empty():
		print("  the manual has no field in it any more")
		return
	var field: LineEdit = fields[0] as LineEdit
	field.grab_focus()
	await _settle()
	print("  the field has the keyboard: ", page.gui_get_focus_owner() == field)
	await _press_escape(false)
	print("  up -> Escape -> up: ", page.visible, " after one")
	if page.visible:
		await _press_escape(false)
		print("  and after two: ", page.visible)


## The key, as the keyboard sends it: a real `InputEventKey` through the root viewport, which routes it
## to whichever window has the keyboard.
func _press_escape(release_focus: bool = true) -> void:
	if release_focus:
		get_viewport().gui_release_focus()
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = KEY_ESCAPE
		event.physical_keycode = KEY_ESCAPE
		event.pressed = pressed
		get_viewport().push_input(event)
	await _settle()


## Every window that is up, by its own `visible`, so a page is found without a predicate per page.
func _windows_up() -> Array[Window]:
	var up: Array[Window] = []
	for page: Window in _every_window(_hud):
		if page.visible:
			up.append(page)
	return up


## The one that was not up before, if opening put exactly one on the screen.
func _newly_up(before: Array[Window]) -> Window:
	for page: Window in _windows_up():
		if not before.has(page):
			return page
	return null


## Every `Window` under a node, however deep: the pages are built in code and hang off the HUD rather
## than sitting in the scene file.
func _every_window(under: Node) -> Array[Window]:
	var found: Array[Window] = []
	for child: Node in under.get_children():
		if child is Window:
			found.append(child as Window)
		found.append_array(_every_window(child))
	return found


func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw