extends Node
## A dev tool: two frames of the running program with nothing touching it, and what moved between them.
##
## It exists because a single picture cannot show a screen that will not settle. The HUD rewrites things every
## frame - the palette is asked for its own state sixty times a second - and only a comparison of two frames can
## say whether any of that reaches the glass. `Stillness` does the arithmetic; this decides what to point it at.
##
## **It shows that it works**: after the still pair it presses a key, which changes the screen on purpose, and
## reports what the same rule makes of *that*. An instrument that only ever answers "nothing moved" would be
## worth nothing, so the second pair is the proof that the first pair means something.
##
## The front door is put away first, because its sheet is opaque: a screen covered by it would hold still for
## the wrong reason, and everything worth watching is behind it.
##
## Run it with `run_scene` and read the console:
##     res://tools/gui_stillness.tscn

const MAIN := preload("res://scenes/main.tscn")
const StillnessScript := preload("res://scripts/stillness.gd")

## How far apart the two frames of the still pair are. Long enough for any per-frame rewrite to have happened
## many times, short enough that nothing in the program is doing anything of its own.
const GAP_FRAMES := 12


func _ready() -> void:
	var main: Node = MAIN.instantiate()
	add_child(main)
	await _settle(20)
	var hud: Node = _find_scripted(main, "hud.gd")
	if hud != null:
		var sheet: ColorRect = hud.find_child("StartBackdrop", true, false) as ColorRect
		var door: Window = hud.find_child("StartWindow", true, false) as Window
		if sheet != null:
			sheet.visible = false
		if door != null:
			door.hide()
	await _settle(8)

	var before: Image = _frame()
	if before == null:
		print("STILLNESS there is no framebuffer here, so there is nothing to compare")
		return
	await _settle(GAP_FRAMES)
	var after: Image = _frame()
	if after == null:
		print("STILLNESS the screen stopped answering between the two frames")
		return
	print("--- what moved while nothing touched the program, %d frames apart ---" % GAP_FRAMES)
	_report(StillnessScript.bands(before, after))

	# The same rule, on a change that is *meant* to happen: the drawing tools go on, and the box beside the
	# plan and the palette both change with them.
	print("")
	print("--- and what it makes of a change that is meant to happen ---")
	await _press(&"draft_mode")
	await _settle(GAP_FRAMES)
	var changed: Image = _frame()
	if changed == null:
		print("  the screen stopped answering")
		return
	_report(StillnessScript.bands(after, changed))


func _report(bands: Array[Dictionary]) -> void:
	if bands.is_empty():
		print("  the screen held still: not one pixel of it moved")
		return
	for band: Dictionary in bands:
		print("  %s" % StillnessScript.sentence(band))
	print("  %d place(s) moved" % bands.size())


## One frame of the glass, or null where there is no glass to read - a headless run has a dummy renderer, and
## asking it for a texture logs an error the test runner counts as a failure.
func _frame() -> Image:
	if DisplayServer.get_name() == "headless":
		return null
	var view: Viewport = get_viewport()
	if view == null:
		return null
	return view.get_texture().get_image()


## Press a bound action the way a keyboard does: through the real input pipeline, with both codes set, because
## that is what the operating system sends and what the binding is matched against.
func _press(action: StringName) -> void:
	var code: Key = KEY_0
	for event: InputEvent in InputMap.action_get_events(action):
		var key := event as InputEventKey
		if key != null:
			code = key.physical_keycode if key.physical_keycode != 0 else key.keycode
			break
	for down in [true, false]:
		var press := InputEventKey.new()
		press.keycode = code
		press.physical_keycode = code
		press.pressed = down
		Input.parse_input_event(press)
	await _settle(2)


func _settle(frames: int) -> void:
	for _frame_number in frames:
		await get_tree().process_frame


## The first node under the app carrying a given script, found by the script rather than by a node path a scene
## edit would move out from under this tool.
func _find_scripted(root: Node, file: String) -> Node:
	for node: Node in root.find_children("*", "", true, false):
		var script: Script = node.get_script()
		if script != null and String(script.resource_path).ends_with(file):
			return node
	return null
