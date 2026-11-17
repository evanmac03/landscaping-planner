extends Node
## A dev tool: write down the desk's layout again, which `tests/test_desk_layout.gd` holds the program to.
##
##     GODOT_MCP_RUNTIME=0 <godot> --headless --path . res://tools/record_desk_layout.tscn
##
## Run it when a change to the desk is **meant**, then **read the diff it leaves**. The record is written one page
## per block, in the page's own name, sorted, and each block says what the page declares, the widest thing its
## contents need, how many controls it holds and whether its column scrolls - so the diff names the page and the
## number that moved rather than showing a wall of digits. The height a page's contents want is deliberately not
## in there: it is a fact about the room the page was measured in and not about the page, and the two runners this
## project has do not agree on that room. The check's own doc carries the measurement.
##
## The measurement is **not** taken here. It is `DeskLayout.recorded()` and `DeskLayout.write_record()`, the same
## two calls the check makes, so that the desk which is recorded and the desk which is held cannot become two
## readings of one program. Nothing in the check writes the record, because a test that records its own answer is
## a test that cannot fail.
##
## The two halves of that discipline, side by side: this tool is how a record *changes*, and the check is how it
## *fails*. A layout that moved by accident is caught by the check, and a layout that moved on purpose is a diff
## a person reads here.

const DeskLayout := preload("res://tests/test_desk_layout.gd")


func _ready() -> void:
	# The scene is the recording and the quitting; `run` is the recording alone, so that a test can hold what
	# this does without ending its own run.
	await run(get_tree())
	get_tree().quit()


## The recording, as a call a test can make. Returns whether the record was written.
static func run(tree: SceneTree) -> bool:
	# A frame first, because this is reached from `_ready` and a node cannot be added to the root while the root
	# is still setting up its own children.
	await tree.process_frame
	var pages: Dictionary = await DeskLayout.recorded(tree)
	var written: bool = DeskLayout.write_record(DeskLayout.GOLDEN, pages)
	if written:
		print("recorded %d page(s) to %s" % [pages.size(), DeskLayout.GOLDEN])
	else:
		printerr("could not write the desk's layout to %s" % DeskLayout.GOLDEN)
	return written
