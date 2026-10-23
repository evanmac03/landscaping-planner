extends Node
## Measures the program's memory footprint, stage by stage, and says so in one line
## per stage.
##
## Not part of the game. A dev tool, run through `run_scene res://tools/mem_report.tscn`:
## a window is needed, because the largest number here - render memory - is only real when
## something is being rendered. It instances the real `main.tscn` and reads Godot's own
## `Performance` monitors, so the numbers are the engine's rather than this file's opinion.
##
## What each monitor means, because a number nobody can interpret is not a measurement:
##
##   static     bytes the engine holds for objects, scripts, resources and data. The big one
##              for a program like this, whose state is dictionaries and geometry.
##   obj        live Object count (nodes, resources, refcounted things).
##   nodes      live Node count - the UI is most of this.
##   res        live Resource count - textures, meshes, materials, scripts.
##   tex        bytes of video memory holding textures.
##   buf        bytes of video memory holding framebuffers, shadow atlases and render targets.
##              This is the one a supersampled still spikes.
##
## Nothing here is asserted; it prints and it quits, so it works while the numbers are
## still being changed.

const MAIN := preload("res://scenes/main.tscn")

var _app: Node = null
var _stage: int = 0


func _ready() -> void:
	_say("before main")
	_app = MAIN.instantiate()
	# Deferred: the root is still setting up its children during `_ready`, and an
	# `add_child()` straight into it is refused ("Parent node is busy setting up
	# children"). The stage counter below absorbs the frame that costs.
	get_tree().root.add_child.call_deferred(_app)
	set_process(true)


func _process(_delta: float) -> void:
	_stage += 1
	# A few frames at each stage: the first frame after adding the scene does the
	# layout and the first draw, and a monitor read on that frame reads half of it.
	if _stage == 6:
		_say("after main (idle)")
		_attribute()
	elif _stage == 12:
		_say("after 6 more frames")
	elif _stage == 18:
		_say("final")
		get_tree().quit()


func _say(tag: String) -> void:
	print("MEM  ", tag,
		"  static=", _mb(Performance.MEMORY_STATIC),
		"  static_max=", _mb(Performance.MEMORY_STATIC_MAX),
		"  obj=", int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"  nodes=", int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"  res=", int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		"  tex=", _mb(Performance.RENDER_TEXTURE_MEM_USED),
		"  buf=", _mb(Performance.RENDER_BUFFER_MEM_USED),
		"  vid=", _mb(Performance.RENDER_VIDEO_MEM_USED))


func _mb(monitor: int) -> String:
	return "%.1fMB" % (Performance.get_monitor(monitor) / 1048576.0)


## Where the nodes are. The HUD is expected to be most of them, because every page is
## built when the program starts rather than when it is opened - which is the question
## this line answers.
func _attribute() -> void:
	if _app == null or not is_instance_valid(_app):
		return
	var rows: Array = []
	for child: Node in _app.get_children():
		rows.append({"name": child.name, "nodes": _subtree(child)})
	rows.sort_custom(func(a, b): return int(a["nodes"]) > int(b["nodes"]))
	var parts: Array[String] = []
	for row: Dictionary in rows.slice(0, 8):
		parts.append("%s=%d" % [row["name"], int(row["nodes"])])
	print("NODES  total=", _subtree(_app), "  ", "  ".join(parts))
	var windows := 0
	var controls := 0
	for node: Node in _walk(_app):
		if node is Window:
			windows += 1
		if node is Control:
			controls += 1
	print("KINDS  windows=", windows, "  controls=", controls)
	# Every page, by size. Built at boot or on demand is the question this answers.
	var pages: Array = []
	for node: Node in _walk(_app):
		if node is Window:
			pages.append({"name": node.name, "nodes": _subtree(node)})
	pages.sort_custom(func(a, b): return int(a["nodes"]) > int(b["nodes"]))
	var top: Array[String] = []
	for row: Dictionary in pages.slice(0, 10):
		top.append("%s=%d" % [row["name"], int(row["nodes"])])
	print("PAGES  count=", pages.size(), "  top: ", "  ".join(top))


func _subtree(node: Node) -> int:
	return _walk(node).size()


func _walk(node: Node) -> Array[Node]:
	var out: Array[Node] = [node]
	# Internal children included: the engine counts them, so a breakdown that skips them
	# under-reports exactly the thing being measured.
	for child: Node in node.get_children(true):
		out.append_array(_walk(child))
	return out