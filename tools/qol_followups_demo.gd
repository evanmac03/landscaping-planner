extends Node2D
## A live pass over the four things that were still on the table: keys for what had none, the pages that
## live in a `Window`, the status line kept, and the commands you ran last.
##
## This is a development tool, not part of the game. It instances the **real main scene**, presses
## **real keys** through the viewport, and drives the **real doors**, so what is being checked is the
## shipped input path rather than a method called by hand. It prints every step and saves a frame of the
## two pages it comes to.
##
## Run `res://scenes/qol_followups_demo.tscn`.
##
## Four claims, in the order a person meets them:
##   * a key that had none now opens the page it names, and Escape - which the HUD could never deliver
##     to a page in a `Window` - takes that page off;
##   * the three ground tools are on their own keys and the key really puts the tool in hand;
##   * the drawing's own answers are kept, so the page that reads them back lists sentences that have
##     already been written over;
##   * a command that was run is offered first the next time the palette is opened.

const MAIN := preload("res://scenes/main.tscn")
const EntityScript := preload("res://scripts/draft/draft_entity.gd")
const LayerSetScript := preload("res://scripts/draft/layer_set.gd")
const ToolScript := preload("res://scripts/draft/draft_tool.gd")
const GradingScript := preload("res://scripts/draft/grading.gd")

## A key that had none, the page it opens, and the predicate that says the page is up. The letters are
## named the way a person says them; the keycode is found from the letter, so a rebinding moves this
## tool with it rather than leaving a stale number behind.
const PAGES: Array = [
	["N", "plant_order", "is_plant_order_window_open", "nursery order"],
	["H", "present_sun_study", "is_sun_window_open", "sun study"],
]

## The three ground tools, on the three keys they were given: the key, the kind the module knows, and
## the kind the drawing tool has to be in.
const GROUND_KEYS: Array = [
	["Z", "spot", ToolScript.Kind.GRADE_SPOT],
	["B", "contour", ToolScript.Kind.GRADE_CONTOUR],
	["M", "slope", ToolScript.Kind.GRADE_SLOPE],
]

var _hud: Node = null


func _ready() -> void:
	var main: Node = MAIN.instantiate()
	add_child(main)
	_hud = main.get_node_or_null(^"Hud")
	if _hud == null or _hud._draft == null:
		print("no HUD, or no drawing for it to work on")
		return
	await _settle()

	await _pages_on_their_keys()
	await _ground_tools_on_their_keys()
	await _what_the_drawing_said()
	await _what_was_run_last()
	print("--- the live pass is done ---")


# --- the keys that had none ------------------------------------------------------------------


## Each key is pressed as the keyboard sends it and the page it names is asked whether it came up; then a
## real Escape is pressed and the page is asked again. Both halves matter: the key is only useful if the
## page can also be put away from inside itself, which is what `PageEscape` is for.
func _pages_on_their_keys() -> void:
	print("--- a page, on the key that had none ---")
	for pair: Array in PAGES:
		var letter: String = String(pair[0])
		var is_open: String = String(pair[2])
		var title: String = String(pair[3])
		if not _hud.has_method(is_open):
			print("  ", title, ": this HUD has no ", is_open, " any more")
			continue
		if bool(_hud.call(is_open)):
			print("  ", title, ": it is already up before the key, so this is not a test")
			continue
		await _press(letter)
		var came_up := bool(_hud.call(is_open))
		print("  ", title, " (", letter, "): up without any menu: ", came_up)
		if not came_up:
			continue
		# The page is a `Window`, so it holds the keyboard itself; the key has to be answered from inside
		# it. `gui_release_focus` first: a field that had focus would eat the press.
		await _press("Escape")
		print("  ", title, ": Escape from inside it puts it away: ", not bool(_hud.call(is_open)))


## The three ground tools. Nothing is drawn: what is being checked is that the key reaches the same door
## the Site menu does and that the tool really is in hand afterwards.
func _ground_tools_on_their_keys() -> void:
	print("--- the three ground tools, on Z, B and M ---")
	for pair: Array in GROUND_KEYS:
		var letter: String = String(pair[0])
		var kind_name: String = String(pair[1])
		var wanted: int = int(pair[2])
		await _press(letter)
		var kind: int = _hud._draft.tool.kind
		print("  ", letter, ": ", kind_name, " in hand: ", kind == wanted,
			" (tool ", ToolScript.Kind.keys()[kind], ", layer ",
			String(_hud._draft.drawing_layer), ")")
	# The tools are put away again, so the rest of the pass starts from a drawing nobody is mid-stroke on.
	await _press("Escape")
	_hud._draft.set_drawing(false)
	await _settle()


# --- what the drawing said, kept ---------------------------------------------------------------


## Draw two things through the drawing's own doors so it says two sentences, then open the page that
## reads them back. The point is the *history*: the status line under the plan only ever shows the last
## sentence, and the page shows both.
func _what_the_drawing_said() -> void:
	print("--- what the drawing said, kept ---")
	var document = _hud._draft.document
	document.add(EntityScript.make_line(Vector2(0, 0), Vector2(4, 2)), LayerSetScript.NEW_HARDSCAPE)
	document.add(EntityScript.make_line(Vector2(4, 2), Vector2(6, 5)), LayerSetScript.NEW_HARDSCAPE)
	# The drawing says what it did through the one setter every message passes through, so this is the
	# same door a click on the canvas would use.
	_hud._draft.last_message = "2 entities drawn by this pass"
	_hud._draft.last_message = "and something else happened after that"
	await _settle()
	var history = _hud._draft.said
	print("  the status line shows only the last thing: \"", _hud._draft.last_message, "\"")
	print("  the drawing kept ", history.count(), " answers, newest first: ", history.lines())

	# The Edit menu's own door, the way a person gets there.
	_hud._menu_said({})
	await _settle()
	print("  the page came up: ", _hud.is_status_window_open(),
		", and it lists ", _hud._status_window.line_count(), " rows")
	print("  the top row is what the plan is saying now: \"", _hud._status_window.newest(), "\"")
	print("  the page says of itself: \"", _hud._status_window.status_text(), "\"")
	await _save_shot("res://preview/qol_followups_said.png")
	await _press("Escape")
	print("  Escape from inside the page puts it away: ", not _hud.is_status_window_open())


# --- the commands you ran last ------------------------------------------------------------------


## Run two real commands through the one door a menu line and a palette row both go through, then open
## the palette with nothing typed: the last one run is the first row.
func _what_was_run_last() -> void:
	print("--- the commands you ran last ---")
	# Real entries with real methods: undo and redo are the two every drawing has, and running them here
	# changes nothing about the drawing that the pass cares about.
	for id: String in ["edit.undo", "edit.redo"]:
		var entry := _entry(id)
		if entry.is_empty():
			print("  ", id, ": this menu no longer has it")
			continue
		print("  running ", id, ": ", _hud.run_entry(entry))
	print("  remembered, newest first: ", _hud.recent_commands())
	_hud.open_command_palette()
	await _settle()
	print("  the palette opens with the box empty: ", _hud.is_command_palette_open())
	if _hud._command_palette != null:
		print("  the first rows are: ", _hud._command_palette.list_texts().slice(0, 3))
		print("  and it says why the order is what it is: \"",
			_hud._command_palette.status_text(), "\"")
	await _save_shot("res://preview/qol_followups_palette.png")
	await _press("Escape")
	print("  and Escape puts the box away: ", not _hud.is_command_palette_open())
	# The undo and the redo this pass ran cancel each other out, so the drawing is left as it was found and
	# there is nothing to take back.


## The menu entry with an id, out of the bar's own snapshot.
func _entry(id: String) -> Dictionary:
	for entry: Dictionary in _hud.command_rows():
		if String(entry.get("id", "")) == id:
			return entry
	return {}


# --- the keyboard, and the frame ----------------------------------------------------------------


## A key as the keyboard sends it: a real `InputEventKey` through the viewport, press then release, with
## both the keycode and the physical keycode set. Focus is released first, because a focused control eats
## the press before `_unhandled_input` ever sees it - a different fact from whether the key works.
func _press(key_name: String) -> void:
	var focused: Control = get_viewport().gui_get_focus_owner()
	if focused != null:
		print("    (releasing focus from ", focused.name, ")")
		get_viewport().gui_release_focus()
	var code: Key = KEY_ESCAPE if key_name == "Escape" else OS.find_keycode_from_string(key_name)
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = pressed
		get_viewport().push_input(event)
	await _settle()


## A few frames, so the HUD's own `_process` (which is what keeps an open page up to date) has run.
func _settle() -> void:
	for _frame in 8:
		await get_tree().process_frame


func _save_shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var shot: Image = get_viewport().get_texture().get_image()
	if shot == null:
		print("  (no frame to save)")
		return
	DirAccess.make_dir_recursive_absolute("res://preview")
	print("  saved ", path, " (", shot.get_width(), "x", shot.get_height(), "): ", shot.save_png(path) == OK)
