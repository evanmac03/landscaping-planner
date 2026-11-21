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
		one[path] = { "visible": true, "size": Vector2i(464, 98), "children": 4, "font": 41 }
	var there: Dictionary = WorkspaceReportScript.from_lines(WorkspaceReportScript.lines(one))
	assert(
		WorkspaceReportScript.differences(one, there).is_empty(),
		"a reading compared with itself through the words says nothing: %s"
		% str(WorkspaceReportScript.differences(one, there)),
	)
	var walked: Dictionary = there[WorkspaceReportScript.NODES[0]]
	assert(walked["size"] == Vector2i(464, 98), "the size comes back whole: %s" % str(walked["size"]))
	assert(int(walked["children"]) == 4, "and so does the count: %s" % str(walked["children"]))
	# **And the type travels with them.** The fact was added to this reading because a fault hid behind its absence,
	# so a round trip that dropped it would leave the very gap it was written to close.
	assert(int(walked["font"]) == 41, "and the size of its words: %s" % str(walked["font"]))


## **A target's height and the size of its type are two questions, and the tool could answer only the first.**
##
## Measured on the strip: the six tool stand-ins stood 98 px tall in a 98 px row with their words drawn at the
## desk's 13, because they are built when a tab is pressed - a frame after the device the view stated has been
## handed back. Every fact this file held was right and its verdict was "clean", which is why it holds a fifth.
##
## The floor is `PhoneHud`'s, asked of it: this file states no millimetre figure of its own for either question.
func test_type_under_the_devices_floor_is_named_beside_the_height() -> void:
	const path := "Hud/Root/TouchDock/Column/ToolStrip/StripScroll/Strip/draft_line"
	const ON_A_PHONE := 450.0
	var floor_px: int = WorkspaceReportScript.expected_type_size(ON_A_PHONE)
	assert(floor_px > 30, "a phone's type floor is a phone's: %d" % floor_px)
	assert(
		WorkspaceReportScript.expected_type_size(200.0) < 20,
		"and the threshold's is not: %d" % WorkspaceReportScript.expected_type_size(200.0),
	)
	var roomy: Dictionary = {
		WorkspaceReportScript.DEVICE: { "dpi": ON_A_PHONE },
		path: {
			"visible": true,
			"size": Vector2i(98, int(ceil(WorkspaceReportScript.expected_row_height(ON_A_PHONE)))),
			"children": 0,
			"target": true,
			"font": floor_px,
		},
	}
	assert(
		WorkspaceReportScript.looks_built_for_a_finger(roomy).is_empty(),
		"a target at the device's own type is what a reader needs: %s"
		% str(WorkspaceReportScript.looks_built_for_a_finger(roomy)),
	)
	var small: Dictionary = roomy.duplicate(true)
	small[path]["font"] = 13
	var told: Array[String] = WorkspaceReportScript.looks_built_for_a_finger(small)
	assert(told.size() == 1, "a target whose words are a third of the size is named: %s" % str(told))
	assert(told[0].contains("type"), "and the answer says which of the two questions is wrong: %s" % told[0])
	assert(told[0].contains("13"), "with the figure it measured: %s" % told[0])
	# The same button, the same words, and a control that draws none: a panel is not judged for its type.
	var panel: Dictionary = roomy.duplicate(true)
	panel[path]["target"] = false
	panel[path]["font"] = 0
	assert(
		WorkspaceReportScript.looks_built_for_a_finger(panel).is_empty(),
		"a control that draws no words has no type to be short of",
	)


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
	# **And a device that is stated but whose floor comes out nothing is refused too.** A floor of zero is cleared by
	# every control there is, so a verdict measured against one reads "built for a finger" over furniture that is
	# nothing of the kind - the worst shape a wrong answer takes, because it is a clean bill of health from a
	# measurement that never happened. The floor is asked of `PhoneHud`, and a real device's own is never zero.
	assert(
		WorkspaceReportScript.expected_row_height(ON_A_PHONE) > 0.0,
		"a real device's floor is a real number: %.1f" % WorkspaceReportScript.expected_row_height(ON_A_PHONE),
	)
	assert(
		WorkspaceReportScript.expected_type_size(ON_A_PHONE) > 0,
		"and so is its type floor: %d" % WorkspaceReportScript.expected_type_size(ON_A_PHONE),
	)


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


## **A name nobody chose is not an identity.** Two instances of one scene give the same button different placeholder
## names - `@Button@6` against `@Button@21445` - because the number counts every node the *process* has ever made. A
## reading keyed by those names called the same nine buttons of the phone's bar and dock "there in one and not the
## other" *in both directions at once*: eighteen of the thirty-four differences the first real comparison printed
## were that one fault, and it made the instrument half noise exactly where it was supposed to speak.
##
## The rule is held down by building the same little chain twice with a pile of nodes made in between, so the two
## instances cannot possibly land on the same numbers - which is the accident the real comparison met: a run fresh
## off the ground held against an editor that had been up all day.
func test_a_name_nobody_chose_is_not_an_identity() -> void:
	var first: Node = _a_row_of_two_buttons()
	# Made and dropped, so the count every placeholder name carries on from has moved before the second tree exists.
	_a_row_of_two_buttons().free()
	var second: Node = _a_row_of_two_buttons()
	var one: Dictionary = WorkspaceReportScript.read(first, 450.0)
	var other: Dictionary = WorkspaceReportScript.read(second, 450.0)
	assert(
		WorkspaceReportScript.differences(one, other).is_empty(),
		"two instances of one row read as the same row: %s" % str(WorkspaceReportScript.differences(one, other)),
	)
	# **And the buttons are in the reading at all**, or two trees holding nothing would agree just as well and the
	# line above would pass while saying nothing.
	var pressed: int = 0
	for path: String in one:
		if bool(one[path].get("target", false)):
			pressed += 1
	assert(pressed == 2, "with both buttons read, under names that travel: %d" % pressed)
	first.free()
	second.free()


## **When two sides were built for different screens, every size below them differs, and the one fact that explains
## all of them is said first.** This is the line that answers "why is the 2D workspace a different size from F6" -
## measured, the editor's furniture had been built with a density of 144 and a canvas scale of 0 against the run's
## 450 and 1, and every button in it carried a zero minimum in consequence.
##
## And a device **neither** reading states is not invented: a pair of readings written before this fact existed says
## nothing about one, which is honest, where a guess would be the fault wearing an answer's clothes.
func test_a_device_difference_is_named_first_and_in_its_own_words() -> void:
	const path := "Hud/Root/TouchDock"
	var run: Dictionary = {
		WorkspaceReportScript.DEVICE: { "dpi": 450.0, "scale": 1.0, "built_at": 450.0 },
		path: { "visible": true, "size": Vector2i(1502, 231), "children": 1, "target": false, "font": 16 },
	}
	var editor: Dictionary = {
		WorkspaceReportScript.DEVICE: { "dpi": 144.0, "scale": 0.0, "built_at": 144.0 },
		path: { "visible": true, "size": Vector2i(1600, 97), "children": 1, "target": false, "font": 16 },
	}
	var named: Array[String] = WorkspaceReportScript.differences(run, editor)
	assert(named.size() == 2, "the device and the one size that differs: %s" % str(named))
	assert(named[0].begins_with(WorkspaceReportScript.DEVICE), "the device is named first: %s" % named[0])
	assert(named[0].contains("450") and named[0].contains("144"), "with both readings: %s" % named[0])
	# A device both sides agree on is not a difference, however many of their sizes are.
	var same: Dictionary = run.duplicate(true)
	same[path]["size"] = Vector2i(1, 1)
	assert(
		not WorkspaceReportScript.differences(run, same)[0].begins_with(WorkspaceReportScript.DEVICE),
		"a device both sides agree on is not a difference",
	)
	var old_here: Dictionary = { path: { "visible": true, "size": Vector2i(1, 1), "children": 1 } }
	var old_there: Dictionary = { path: { "visible": true, "size": Vector2i(2, 2), "children": 1 } }
	assert(
		WorkspaceReportScript.device_difference(old_here, old_there) == "",
		"a device neither reading states is not invented",
	)


## **The lines a run must ignore.** An editor leaves its own verdict in the *same file* as its reading, marked with
## `! `, and `from_lines` has to skip them: a parser that read one as a node would invent a path nobody has and
## report a difference against a control that was never there. It is held down because that file is the **one channel
## out of an editor** - nothing can ask an editor anything, so a line misread there is a diagnosis that goes quietly
## wrong, which is the exact fault this file exists to prevent.
func test_a_verdict_line_left_beside_a_reading_is_skipped_by_the_parser() -> void:
	var one: Dictionary = { }
	for path: String in WorkspaceReportScript.NODES:
		one[path] = { "visible": true, "size": Vector2i(464, 98), "children": 4, "font": 41 }
	var written: PackedStringArray = WorkspaceReportScript.lines(one)
	var marked: PackedStringArray = written.duplicate()
	marked.append("! draft_line: 31 px tall, under the 97 px a thumb needs")
	marked.append("! 23 button(s) dressed, and the furniture's own row is 97.4 px")
	var plain: Dictionary = WorkspaceReportScript.from_lines(written)
	var with_verdict: Dictionary = WorkspaceReportScript.from_lines(marked)
	assert(
		with_verdict.size() == plain.size(),
		"a verdict line is not a node: %d against %d" % [with_verdict.size(), plain.size()],
	)
	assert(
		WorkspaceReportScript.differences(plain, with_verdict).is_empty(),
		"and leaving one beside a reading changes nothing: %s"
		% str(WorkspaceReportScript.differences(plain, with_verdict)),
	)


## A chain ending in a row of two unnamed buttons - the shape the phone's furniture builds, where the row is named
## and everything a thumb presses inside it is not.
func _a_row_of_two_buttons() -> Node:
	var root := Node.new()
	var parent: Node = root
	for part: String in ["Hud", "Root", "TopBar", "Row", "TouchRow"]:
		var made := Control.new()
		made.name = part
		parent.add_child(made)
		parent = made
	for index: int in range(2):
		var button := Button.new()
		button.text = ["Draw", "Dim"][index]
		parent.add_child(button)
	return root
