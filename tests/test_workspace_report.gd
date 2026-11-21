extends Node
## The workspace report, held to the two rules that make it worth having: a reading survives being written down
## and read back, and two readings that disagree are *named* apart rather than counted.
##
## The model is all statics and needs no scene, so most of this is arithmetic on dictionaries. The one test that
## does build nodes frees them, and it builds a single path rather than all eight: a path that does not resolve is
## the *other* half of the rule and is asserted on purpose.

const WorkspaceReportScript := preload("res://tools/workspace_report.gd")


## A reading written out and read back is the same reading.
##
## This is what lets an editor's own block be compared with a run's: the two are never in one process, so the only
## way they can be held against each other is through the words this file writes - and a format that could not be
## read back would leave every comparison silently empty, which reads exactly like agreement.
func test_a_reading_survives_being_written_down_and_read_back() -> void:
	var one: Dictionary = { }
	for path: String in WorkspaceReportScript.NODES:
		one[path] = { "visible": true, "size": Vector2i(464, 98), "children": 4 }
	var there: Dictionary = WorkspaceReportScript.from_lines(WorkspaceReportScript.lines(one))
	assert(
		WorkspaceReportScript.differences(one, there).is_empty(),
		"a reading compared with itself through the words says nothing: %s"
		% str(WorkspaceReportScript.differences(one, there)),
	)
	var walked: Dictionary = there[WorkspaceReportScript.NODES[0]]
	assert(walked["size"] == Vector2i(464, 98), "the size comes back whole: %s" % str(walked["size"]))
	assert(int(walked["children"]) == 4, "and so does the count: %s" % str(walked["children"]))


## Every way two readings can disagree is named, with both figures in the sentence.
##
## The three facts are separate questions - whether anything was shown, what it was laid out at, and whether it was
## *built* - and a report that folded them into one verdict would send a person to the wrong pane. The sizes here
## are the two this project actually measured on the two sides: a desk's 31 px against the phone's 97.
func test_each_fact_that_disagrees_is_named_with_both_figures() -> void:
	const path := "Hud/Root/TouchDock"
	var run: Dictionary = { path: { "visible": true, "size": Vector2i(1576, 197), "children": 1 } }
	var editor: Dictionary = { path: { "visible": false, "size": Vector2i(1576, 40), "children": 1 } }
	var named: Array[String] = WorkspaceReportScript.differences(run, editor)
	assert(named.size() == 2, "shown and sized are two differences, not one: %s" % str(named))
	assert(named[0].contains(path), "and each names the node: %s" % named[0])
	assert(named[0].contains("true") and named[0].contains("false"), "with both readings: %s" % named[0])
	assert(named[1].contains("197") and named[1].contains("40"), "and both figures for the size: %s" % named[1])


## A node one side could not read at all is a difference, and a node neither side has is not.
##
## **A side that could not read a node has not agreed with anything**, so it cannot be counted as a match - and a
## path missing from both is simply not this scene's business, which is not a fault to report either.
func test_a_node_only_one_side_has_is_named_and_a_node_neither_has_is_not() -> void:
	var both: Dictionary = { }
	for path: String in WorkspaceReportScript.NODES:
		both[path] = { "visible": true, "size": Vector2i(10, 10), "children": 1 }
	var partial: Dictionary = both.duplicate(true)
	partial.erase(WorkspaceReportScript.NODES[0])
	var named: Array[String] = WorkspaceReportScript.differences(both, partial)
	assert(named.size() == 1, "one node is in one reading and not the other: %s" % str(named))
	assert(named[0].contains(WorkspaceReportScript.NODES[0]), "named: %s" % named[0])
	var empty: Dictionary = { }
	assert(
		WorkspaceReportScript.differences(empty, empty).is_empty(),
		"a path neither side has is not a fault to report",
	)


## **A height of nothing is reported, not passed.** A control that has not been laid out has not been measured, and
## a check that treated zero as "no fault found" would pass the exact state this project spent a night chasing.
##
## **And only a button is judged at all.** This test was written against the rule this file was born with - judge
## whatever holds children - and that rule flagged the hint line (a caption) while never reading the six buttons
## inside the tool strip. The three cases below are the correction: a button at the floor is fine, a button with no
## height is named, a button built for a desk is named - and the *same sizes* on a thing nothing presses are not
## faults, because a caption a person reads is not a target a thumb misses.
func test_a_control_with_no_height_is_reported_rather_than_passed() -> void:
	const path := "Hud/Root/TopBar/Row/TouchRow"
	const ON_A_PHONE := 450.0
	var laid_out: float = WorkspaceReportScript.expected_row_height(ON_A_PHONE)
	assert(laid_out > 90.0, "a phone's floor is a phone's: %.0f" % laid_out)
	# **And it belongs to the device, not to a threshold.** `HELD_DPI` is the density `TouchInput` *decides* by - "is
	# this hand a thumb" - and it is no screen's: asking it gave 43 px for a floor whose real answers are 97 px here
	# and 31 px on a desk. Reusing it is a second place stating a floor, which is why the reading carries its own.
	assert(WorkspaceReportScript.expected_row_height(200.0) < 50.0, "the threshold's row is not the phone's row")
	var good: Dictionary = {
		WorkspaceReportScript.DEVICE: { "dpi": ON_A_PHONE },
		path: { "visible": true, "size": Vector2i(464, int(ceil(laid_out))), "children": 4, "target": true },
	}
	assert(
		WorkspaceReportScript.looks_built_for_a_finger(good).is_empty(),
		"a row built at the phone's floor is what a finger needs",
	)
	var unlaid: Dictionary = {
		WorkspaceReportScript.DEVICE: { "dpi": ON_A_PHONE },
		path: { "visible": true, "size": Vector2i(464, 0), "children": 4, "target": true },
	}
	var told: Array[String] = WorkspaceReportScript.looks_built_for_a_finger(unlaid)
	assert(told.size() == 1, "a control with no height at all is named: %s" % str(told))
	var desk_sized: Dictionary = {
		WorkspaceReportScript.DEVICE: { "dpi": ON_A_PHONE },
		path: { "visible": true, "size": Vector2i(221, 31), "children": 4, "target": true },
	}
	var small: Array[String] = WorkspaceReportScript.looks_built_for_a_finger(desk_sized)
	assert(small.size() == 1, "and so is one built for a desk: %s" % str(small))
	assert(small[0].contains("31"), "with the figure it measured: %s" % small[0])
	# The same two sizes on a caption: named by nobody, which is the whole point of the correction.
	var captions: Dictionary = {
		WorkspaceReportScript.DEVICE: { "dpi": ON_A_PHONE },
		path: { "visible": true, "size": Vector2i(740, 42), "children": 1, "target": false },
	}
	assert(
		WorkspaceReportScript.looks_built_for_a_finger(captions).is_empty(),
		"a caption under a thumb's floor is not a target a thumb misses",
	)
	# **A reading that does not say what it came from is refused, not judged.** A verdict measured against a floor
	# nobody stated is the fault this fix exists for, wearing an answer's clothes - so it says so instead.
	var anonymous: Dictionary = { path: { "visible": true, "size": Vector2i(221, 31), "children": 4, "target": true } }
	var refused: Array[String] = WorkspaceReportScript.looks_built_for_a_finger(anonymous)
	assert(refused.size() == 1, "a reading with no device is answered, not passed: %s" % str(refused))
	assert(refused[0].contains("device"), "and the answer names what is missing: %s" % refused[0])


## `read` takes three facts from a real tree, and a path that is not there is *named* as missing.
##
## The chain is built here rather than loaded, because this test is about the reading and not about the scene - and
## a path that does not resolve is the half worth holding down: an absent strip and an empty one look the same in
## a count and nothing alike to a person.
func test_a_node_is_read_from_a_tree_and_a_missing_path_is_named() -> void:
	var root := Node.new()
	var hud := Node.new()
	hud.name = "Hud"
	root.add_child(hud)
	var parent: Node = hud
	for part: String in ["Root", "TopBar", "Row", "TouchRow"]:
		var made := Control.new()
		made.name = part
		parent.add_child(made)
		parent = made
	var reading: Dictionary = WorkspaceReportScript.read(root, 450.0)
	var found: Dictionary = reading[WorkspaceReportScript.NODES[0]]
	assert(not bool(found.get("missing", false)), "the chain that is there resolves")
	# **The height and the count, and not the visibility.** What this reads for `visible` is
	# `is_visible_in_tree`, which is the truth a person's eye gets - and a fixture built off any tree answers
	# `false` honestly, so asserting it here would either pin a fixture's own artefact or say nothing at all.
	# What a *shown* node reads is the running program's business and the readings it prints are where that is
	# seen; what is held here is that the three facts are taken from the tree rather than made up.
	assert(
		Vector2i(found["size"]) == Vector2i.ZERO,
		"a control that has not been laid out is read as size nothing: %s" % str(found["size"]),
	)
	assert(int(found["children"]) == 0, "with its own count: %d" % int(found["children"]))
	var absent: Dictionary = reading[WorkspaceReportScript.NODES[2]]
	assert(bool(absent.get("missing", false)), "a path the tree does not have is named missing, not dropped")
	# **One `free`, and it is the root's.** A tree freed child by child is a tree whose children are gone while
	# the loop still holds them, and freeing a node that is already freed takes the *runner* down with it - which
	# is what this test did, and why the suite printed no verdict at all for several runs. Freeing the root frees
	# everything under it, once.
	root.free()
