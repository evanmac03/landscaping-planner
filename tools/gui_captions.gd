extends Node
## A dev tool: the screen's words taken down twice, around one action, and what moved between the two readings.
##
## It exists because a stale caption is the one fault in a GUI with no rule. Whether a box *should* have changed
## its words when a tool changed is not arithmetic - it depends on what the page promised when it handed the
## label its text - so no module can decide it. What can be had without guessing is the reading: what every
## caption said before the action, what it says after, and which of them held still while everything around them
## moved. That list is where a person looks, and it is how the box beside the plan was found saying whichever
## tool was in hand.
##
## The action it takes is arming the drawing tools, which changes the palette, the box and the foot line at once.
##
## Run it with `run_scene` and read the console:
##     res://tools/gui_captions.tscn

const MAIN := preload("res://scenes/main.tscn")
const HudProbeScript := preload("res://scripts/hud_probe.gd")
const CaptionLedgerScript := preload("res://scripts/caption_ledger.gd")

## The action the two readings are taken around. Arming the drawing tools changes the palette's own state, the
## box beside the plan's subject and the foot line's prompt in a single keystroke.
const ACTION := &"draft_mode"


func _ready() -> void:
	var main: Node = MAIN.instantiate()
	add_child(main)
	await _settle(20)
	var hud: Node = main.get_node_or_null("Hud")
	if hud == null:
		print("CAPTIONS no Hud")
		return
	_put_the_door_away(hud)
	await _settle(8)

	var before: Dictionary = HudProbeScript.captions(hud)
	await _press(ACTION)
	await _settle(8)
	var after: Dictionary = HudProbeScript.captions(hud)

	var changes: Dictionary = CaptionLedgerScript.changes(before, after)
	print("--- what the screen's words did while %s was pressed ---" % ACTION)
	print("  %s" % CaptionLedgerScript.summary(changes))
	for change: Dictionary in changes["moved"]:
		print("  moved     %s" % CaptionLedgerScript.sentence(change))
	for path: String in changes["appeared"]:
		print("  new       %s  \"%s\"" % [path, after[path]])
	for path: String in changes["vanished"]:
		print("  gone      %s  \"%s\"" % [path, before[path]])
	print(
		(
			"  and %d caption(s) held still, which is where a caption that should have followed and did not is"
			% (changes["held"] as Array).size()
		)
	)


## Puts the front door away, because everything worth reading is behind its opaque sheet.
func _put_the_door_away(hud: Node) -> void:
	var sheet: ColorRect = hud.find_child("StartBackdrop", true, false) as ColorRect
	var door: Window = hud.find_child("StartWindow", true, false) as Window
	if sheet != null:
		sheet.visible = false
	if door != null:
		door.hide()


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
