extends Node
## A dev tool: whether a page inside a `Window` really holds the keyboard while it is up, and whether
## it gives the keyboard back when it goes away.
##
## This is the ground the keyboard work on the pages stands on. The specifications state the rule -
## *"while a `Window` has the keyboard the HUD never sees a key event at all"*
## (`workflow-efficiency-spec.md`, the palette's own keys) - and it is the whole reason a page may be
## given a Tab order, an Enter that presses its own button and arrows that walk its own list without
## costing the drawing a key: the page's window holds the keyboard while the page is up, so a key the
## page does not want is a key the page *chose* not to want, rather than one that went to the drawing
## behind it. If that is not so, every one of those plans is a key lost behind the page.
##
## The claim is worth a live run rather than another reading: where a key goes is decided by the
## engine's own routing - the focused subwindow first, then the viewport's unhandled input - and only
## the engine can say which happened. So this presses **real** keys through `Input.parse_input_event`,
## the same call an OS key arrives by, and *not* `Input.action_press`, which sets an action's state and
## sends no event at all: a probe built on it would never have exercised the handler the key lives in.
##
## The key is Q, the drawing's own view switch, because it is answered from `_unhandled_input` and
## leaves a readable trace - which view the drawing ended up in. Each key is asked for the trace before
## and after, so the table says what happened rather than what was pressed.
##
##     res://tools/page_keyboard_probe.tscn
##
## Read the table: `PAGE KEYBOARD` is the line to look for, and it names every row that did not go the
## way the design says it goes.

const MAIN := preload("res://scenes/main.tscn")
const PlannerHudScript := preload("res://scripts/hud.gd")

## Frames the game is given to lay itself out, and frames each injected key is given to arrive. An
## injected event is buffered and dispatched on a later iteration of the main loop, so a key read in
## the frame it was sent has not been anywhere yet - and a table read too early reports that nothing
## moved, which is the one wrong answer this probe must not give.
const SETTLE_FRAMES := 6
const KEY_FRAMES := 3

## The pages this will open, tried in that order. The drawing tools are off in a scene that has just
## come up, and a command whose subject is absent refuses rather than opening, so a page that is always
## there is the fallback.
const PAGE_IDS: Array[String] = ["draft.snapping", "help.manual"]

var _main: Node = null
var _controller: ViewController = null
var _hud: Node = null
var _failures: int = 0


func _ready() -> void:
	_main = MAIN.instantiate()
	add_child(_main)
	for i: int in SETTLE_FRAMES:
		await get_tree().process_frame
	_controller = _main.get_node_or_null(^"ViewController") as ViewController
	_hud = _main.get_node_or_null(^"Hud")
	if _controller == null or _hud == null:
		print("PAGE KEYBOARD: no ViewController or Hud in the scene, so nothing can be asked")
		return

	print("=== PAGE KEYBOARD: does a page hold the keyboard, and give it back? ===")

	# With nothing open at all. This row is what proves the probe: a key that does not move the view
	# with no page in the way would leave every row below reporting that nothing moved, and the probe
	# rather than the page would be the thing that is wrong.
	var bare_mode: int = _controller.mode
	await _press_key(KEY_Q)
	_view_row("nothing up", "Q", bare_mode, _controller.mode, true,
		"the drawing answers its own key")
	# Back where it started, so every row below is read from the same view.
	await _press_key(KEY_Q)
	print("  view is back to %s" % _mode_words(_controller.mode))

	# A page. Printed before it is opened, so a run that stops here says where it stopped.
	print("  opening a page ...")
	var page: Window = await _open_a_page()
	if page == null:
		print("PAGE KEYBOARD: no page could be opened, so nothing below is answered")
		return
	print("  page up: \"%s\"  (%s)" % [page.title, String(page.name)])

	var before_page_key: int = _controller.mode
	await _press_key(KEY_Q)
	_view_row("page up", "Q", before_page_key, _controller.mode, false,
		"the page holds it and the drawing does not see it")

	# Tab, with the page up: what the page's own order can be reached by, and whether Tab leaks past
	# the page to whatever is behind it.
	var focus_before: Control = page.gui_get_focus_owner()
	await _press_key(KEY_TAB)
	var focus_after: Control = page.gui_get_focus_owner()
	_fact_row("page up", "Tab", "%s -> %s" % [
		_control_words(focus_before), _control_words(focus_after),
	], focus_before != focus_after, "the page's own order moves")

	# A button in the page, given the keyboard by hand - which is the change the pages are about to be
	# given - to answer the question the whole keyboard pass rests on. Only the focus mode is set, and
	# only at run time: nothing in the project is changed by asking this.
	var button: Button = _first_live_button(page)
	if button == null:
		_fact_row("page button", "none", "the page has no button to give the keyboard to", false,
			"so nothing is answered here")
	else:
		# An array, because a GDScript lambda takes a copy of a plain local and the count would never
		# leave the closure.
		var hits: Array[int] = [0]
		button.focus_mode = Control.FOCUS_ALL
		button.pressed.connect(func() -> void: hits[0] += 1)
		button.grab_focus()
		for i: int in SETTLE_FRAMES:
			await get_tree().process_frame
		var holds: bool = page.gui_get_focus_owner() == button
		_fact_row("page button", "focus", "the button has the keyboard: %s" % holds, holds,
			"a page's button can hold it")

		var before_button_key: int = _controller.mode
		await _press_key(KEY_Q)
		_view_row("page button", "Q", before_button_key, _controller.mode, false,
			"and the drawing behind it still sees nothing")

		await _press_key(KEY_ENTER)
		_fact_row("page button", "Enter", "it pressed %d time(s)%s" % [
			hits[0], ", and the page went away" if not _page_up(page) else "",
		], hits[0] >= 1, "Enter presses the button that has the keyboard")

	# Escape, with the page up: the page answers for itself from inside its own viewport, because the
	# HUD's own ladder can never see a key while a window holds the keyboard. **Two** presses are sent,
	# because the other live pass in this project found that a page whose *field* holds the keyboard
	# takes two - the first only lets the field go, and the engine answers it before `_unhandled_input`
	# is offered it - and a probe that asked once would report that as "Escape does not close a page".
	var after_one: String = ""
	var after_two: String = ""
	if _page_up(page):
		await _press_key(KEY_ESCAPE)
		after_one = "away" if not _page_up(page) else "up"
	if _page_up(page):
		await _press_key(KEY_ESCAPE)
		after_two = "away" if not _page_up(page) else "up"
	_fact_row("page up", "Esc", "after one: %s, after two: %s" % [after_one, after_two],
		not _page_up(page), "the page answers Escape for itself")

	# And back to the drawing. The keyboard has to be the drawing's again once the page is gone, or a
	# page has taken it for good and the drawing is dead until the program is restarted. A page Escape
	# could not put away is put away here instead, so this row answers the question it is asked - did the
	# keyboard come back - rather than repeating the row above it.
	if _page_up(page):
		print("  (Escape left it up, so the page is taken down by hand for this last row)")
		page.hide()
		for i: int in SETTLE_FRAMES:
			await get_tree().process_frame
	var bare_again: int = _controller.mode
	await _press_key(KEY_Q)
	_view_row("page closed", "Q", bare_again, _controller.mode, true,
		"the keyboard was given back")

	if _failures == 0:
		print("PAGE KEYBOARD: every key went where the design says it goes")
	else:
		print("PAGE KEYBOARD: %d row(s) went somewhere else, named above" % _failures)


## One key's effect on the drawing's view, in the before-and-after words the table is read by.
##
## `wanted_move` is the whole judgement, and it is why the callers pass it: with nothing in the way the
## view has to move, and with a page up it must not - a page holding the keyboard is only a fact if the
## drawing behind it really saw nothing.
func _view_row(what: String, key_name: String, before: int, after: int, wanted_move: bool, detail: String) -> void:
	var moved: bool = after != before
	var ok: bool = moved == wanted_move
	if not ok:
		_failures += 1
	print("  %-12s %-4s %-20s -> %-20s  %-4s  %s" % [
		what, key_name, _mode_words(before), _mode_words(after), "OK" if ok else "NO", detail,
	])


## One key whose effect is a sentence rather than a view: whether the page's focus moved, whether the
## page went away.
func _fact_row(what: String, key_name: String, fact: String, ok: bool, detail: String) -> void:
	if not ok:
		_failures += 1
	print("  %-12s %-4s %-40s  %-4s  %s" % [
		what, key_name, fact, "OK" if ok else "NO", detail,
	])


## One page opened the way a person opens one - through the menu plan, which is the one door a command
## is run by - and handed back so its own focus and its own viewport can be asked questions.
func _open_a_page() -> Window:
	var entries: Array[Dictionary] = PlannerHudScript.menu_entries()
	for wanted: String in PAGE_IDS:
		for entry: Dictionary in entries:
			if String(entry.get("id", "")) != wanted:
				continue
			if not _hud.run_entry(entry):
				continue
			for i: int in SETTLE_FRAMES:
				await get_tree().process_frame
			var page: Window = _hud.page_in_front()
			if page != null:
				return page
	return null


## The first button in a page that a person could actually press: on the screen, not greyed out, and a
## button rather than whatever else inherits from one. Handed back so a run time can give it the
## keyboard, which is the one change this probe makes that the project does not already make.
static func _first_live_button(page: Window) -> Button:
	for found: Node in page.find_children("*", "Button", true, false):
		var button: Button = found as Button
		if button != null and button.visible and not button.disabled:
			return button
	return null


## Whether a page is up, asked of the page's own `visible` rather than of the HUD's opinion of which
## page is in front: the row after this one is about a page that is gone, and `page_in_front` could
## hand back a different page and call it the same answer.
static func _page_up(page: Window) -> bool:
	return page != null and is_instance_valid(page) and page.visible


## One key pressed and released through the input system, exactly as the OS delivers one. Released as
## well as pressed, because a key left down is a key the next row would read as already held.
func _press_key(code: Key) -> void:
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
		for i: int in KEY_FRAMES:
			await get_tree().process_frame


## A view mode in the enum's own words, so the table is not a column of 0s and 1s.
static func _mode_words(mode: int) -> String:
	var names: Array = ViewController.ViewMode.keys()
	if mode >= 0 and mode < names.size():
		return String(names[mode])
	return "mode %d" % mode


## A control in words, including the case that matters most here: nothing holds the keyboard at all.
static func _control_words(control: Control) -> String:
	if control == null:
		return "nothing"
	return "%s (%s)" % [String(control.name), control.get_class()]