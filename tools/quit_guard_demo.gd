extends Node2D
## A live pass over the two ways out of the program: Escape, and the window's own close button.
##
## This is a development tool, not part of the game. It instances the **real main scene**, opens the
## **real pages** through the HUD's own doors, and sends a **real Escape key** through the viewport, so
## what is being checked is the shipped input path rather than a method called by hand. It prints every
## step.
##
## Run `res://scenes/quit_guard_demo.tscn`.
##
## The last thing it does is press "Discard and quit" on the real question, which ends the program -
## which is the proof: the window's close button reaches the same question `File > Quit` does, and the
## answer takes you out. The frame before that is saved, so the question itself is on record.

const MAIN := preload("res://scenes/main.tscn")
const EntityScript := preload("res://scripts/draft/draft_entity.gd")
const LayerSetScript := preload("res://scripts/draft/layer_set.gd")

## Every page this HUD draws itself: the member the page lives in, the predicate that says whether it is
## up, and the door that opens it. The doors are checked with `has_method` rather than assumed, so a
## renamed one is a printed line rather than a crash in a tool nobody runs until they need it.
const PAGES: Array = [
	["site report", "is_site_report_open", "open_site_report"],
	["survey", "is_survey_panel_open", ""],
	["DXF", "is_dxf_panel_open", "open_dxf_panel"],
	["LandXML", "is_landxml_panel_open", "open_landxml_panel"],
	["hatch", "is_hatch_panel_open", "open_hatch_panel"],
	["water", "is_water_panel_open", "open_water_panel"],
	["light", "is_light_panel_open", "open_light_panel"],
]

var _hud: Node = null


func _ready() -> void:
	var main: Node = MAIN.instantiate()
	add_child(main)
	_hud = main.get_node_or_null(^"Hud")
	if _hud == null or _hud._draft == null:
		print("no HUD, or no drawing for it to put away")
		return
	await _settle()
	print("the drawing starts with ", _hud._draft.document.count(), " entities in it, dirty: ",
		_hud._draft.dirty)

	print("--- a page, and the real Escape key ---")
	for pair: Array in PAGES:
		await _page_away(String(pair[0]), String(pair[1]), String(pair[2]))
	await _keys_away()
	await _sheet_away()

	print("--- with nothing up, the key belongs to the drawing ---")
	print("  the ladder answers for nothing: ", _hud.escape_puts_away())

	print("--- the window's own close button ---")
	# Something to lose: the drawing lives in memory until it is written, and the close button is the
	# way out nobody gets a second chance at.
	_hud._draft.document.add(
		EntityScript.make_line(Vector2(0, 0), Vector2(4, 2)), LayerSetScript.NEW_HARDSCAPE
	)
	print("  a line is drawn: ", _hud._draft.document.count(), " entities, dirty: ",
		_hud._draft.dirty)
	_hud._notification(NOTIFICATION_WM_CLOSE_REQUEST)
	await _settle()
	print("  closing the window asks first: ", _hud._discard_dialog.visible,
		", and the action held is \"", _hud._pending_action, "\"")
	await _save_shot()

	# The dialog's own buttons, not its signals: pressing "Keep editing" is what hides the question, and
	# skipping that would report a dialog still up when a person would see it gone.
	_hud._discard_dialog.get_cancel_button().pressed.emit()
	await _settle()
	print("  \"Keep editing\": the question is up: ", _hud._discard_dialog.visible,
		", the work is still here: ", _hud._draft.document.count(),
		" entities, and nothing is armed: ", _hud._pending_action == "")

	_hud._notification(NOTIFICATION_WM_CLOSE_REQUEST)
	await _settle()
	print("  closing it again asks again: ", _hud._discard_dialog.visible)
	print("  and \"Discard\" is the end of this pass, because it leaves the program: ", true)
	_hud._discard_dialog.get_ok_button().pressed.emit()
	await _settle()
	# Nothing after this line runs, which is the finding rather than a failure: the last answer closes
	# the window the way the close button asked to.
	print("  (if this is ever printed, \"Discard\" no longer quits)")


## Open a page through its own door, take a real Escape at it, and report both halves.
func _page_away(title: String, is_open: String, open: String) -> void:
	# One page in the list is the question a survey file is answered with, so it is only ever up once a
	# file has been read: there is no door from here to walk in through, which is its own finding.
	if open == "":
		print("  ", title, ": it has no door of its own (it is the page a read file opens)")
		return
	if not _hud.has_method(open):
		print("  ", title, ": this HUD has no door called ", open, " any more")
		return
	_hud.call(open)
	await _settle()
	if not bool(_hud.call(is_open)):
		print("  ", title, ": it did not come up, so there is nothing to test")
		return
	var left_up: bool = await _press_escape()
	print("  ", title, ": up -> Escape -> up: ", left_up, " (so it is the page it took off: ",
		not left_up, ")")


func _keys_away() -> void:
	_hud.open_keys()
	await _settle()
	if not _hud.is_keys_open():
		print("  key reference: it did not come up, so there is nothing to test")
		return
	var left_up: bool = await _press_escape()
	print("  key reference: up -> Escape -> up: ", left_up, " (so it is the page it took off: ",
		not left_up, ")")


func _sheet_away() -> void:
	if _hud.painted_plan == null:
		print("  painted sheet: this scene cannot paint one")
		return
	_hud.open_painted()
	await _settle()
	if not _hud.painted_sheet.visible:
		print("  painted sheet: it did not come up (a presentation may be in the way)")
		return
	await _press_escape()
	print("  painted sheet: up -> Escape -> up: ", _hud.painted_sheet.visible)


## The key, as the keyboard sends it: a real `InputEventKey` through the viewport, so what is tested is
## `_unhandled_input` rather than the ladder called behind it. Returns whether anything is left up.
func _press_escape() -> bool:
	# Whatever a page's own field had focused is released first: a focused control takes the key before
	# the HUD ever sees it, which is a different fact from whether Escape works.
	var focused: Control = get_viewport().gui_get_focus_owner()
	if focused != null:
		print("    (releasing focus from ", focused.name, ")")
		get_viewport().gui_release_focus()
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.physical_keycode = KEY_ESCAPE
	event.pressed = true
	get_viewport().push_input(event)
	event = InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.physical_keycode = KEY_ESCAPE
	event.pressed = false
	get_viewport().push_input(event)
	await _settle()
	return _any_page_up()


## Whether any page this HUD draws itself is still up, asked of the predicates rather than of one page.
func _any_page_up() -> bool:
	for pair: Array in PAGES:
		if bool(_hud.call(String(pair[1]))):
			return true
	return _hud.is_keys_open() or _hud.painted_sheet.visible


func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw


## The question on record: the frame it is up in, saved next to the other live passes' pictures.
func _save_shot() -> void:
	await _settle()
	var shot := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("res://preview")
	shot.save_png("res://preview/quit_guard_demo.png")
	print("  the question is saved to res://preview/quit_guard_demo.png at ", shot.get_size())