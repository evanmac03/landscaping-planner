extends Node
## A dev tool: arms a drawing tool in the running program and prints the box beside the plan, tool by tool, so
## what the box says for the tool in hand can be **seen** rather than read out of the script that writes it.
##
## It exists for the same reason `palette_demo` does: what a box beside a busy drawing says is not settled by
## reading `Hud.tool_box_text`. It instances the **real main scene**, arms tools through the **real
## controller**, and reads the text off the **real label** the HUD writes - awaiting real frames, so what it
## prints is what a running window is showing.
##
## The front door has to be put away by hand. It stands over the board with a sheet that stops the mouse, and a
## mouse a tool can inject does not reach a control inside an embedded window at all - so the door is closed here
## the way no key would: by hiding the two nodes the HUD builds it from, by the names the HUD gives them.
##
## It leaves a tool in hand when it finishes, so the frame it is captured in is a frame with the box on it.
##
## Run it with `run_scene` and read the console, or capture the frame:
##     res://tools/draft_box_demo.tscn

const MAIN := preload("res://scenes/main.tscn")
const DraftToolScript := preload("res://scripts/draft/draft_tool.gd")

## The tools it walks through: a two-pick shape, a ring, a shape that takes two opposite corners, a dimension,
## and one of the ground's three - which is not in the tool table at all, so its key has to be found by the kind
## it puts in hand rather than by matching its name against an action's.
const TOOLS: Array[int] = [
	DraftToolScript.Kind.LINE,
	DraftToolScript.Kind.POLYLINE,
	DraftToolScript.Kind.RECTANGLE,
	DraftToolScript.Kind.DIMENSION_RADIUS,
	DraftToolScript.Kind.GRADE_SLOPE,
]


func _ready() -> void:
	var main: Node = MAIN.instantiate()
	add_child(main)
	await _settle()
	var hud: Node = _find_scripted(main, "hud.gd")
	var controller: Node = _find_scripted(main, "draft_controller.gd")
	if hud == null or controller == null:
		print("DRAFT BOX: the running program has no HUD or no drawing controller")
		return
	var box: Label = hud.find_child("DraftHintsLabel", true, false) as Label
	var panel: Control = hud.find_child("DraftHints", true, false) as Control
	if box == null or panel == null:
		print("DRAFT BOX: the HUD has no box beside the plan")
		return
	var sheet: ColorRect = hud.find_child("StartBackdrop", true, false) as ColorRect
	var door: Window = hud.find_child("StartWindow", true, false) as Window
	if sheet != null:
		sheet.visible = false
	if door != null:
		door.hide()
	await _settle()

	print("--- the box beside the plan, for the tool in hand ---")
	for kind: int in TOOLS:
		controller.call("arm", kind)
		await _settle()
		var rows: PackedStringArray = box.text.split("\n")
		print("")
		print(
			"%d row(s) for %s, and the box is up: %s"
			% [rows.size(), DraftToolScript.label_for(kind), str(panel.visible)]
		)
		for row: String in rows:
			print("    %s" % row)
	print("")
	print("the last tool is still in hand, which is the state the captured frame shows")


## Let the running scene take a few frames, which is where the HUD and its own per-frame writer settle.
func _settle() -> void:
	for _frame in 4:
		await get_tree().process_frame


## The first node under the app carrying a given script, found by the script rather than by a node path a scene
## edit would move out from under this tool - the same way every other demo here reaches the program.
func _find_scripted(root: Node, file: String) -> Node:
	for node: Node in root.find_children("*", "", true, false):
		var script: Script = node.get_script()
		if script != null and String(script.resource_path).ends_with(file):
			return node
	return null
