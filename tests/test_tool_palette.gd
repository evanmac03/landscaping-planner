extends Node
## The palette's measuring half, held to the rules that were *measured* rather than reasoned about.
##
## Nothing here needs a HUD, which is the point of the module: the fitting is handed a panel and a column, so
## a test can hold what a phone would be told without being one. The arithmetic underneath - what size a
## button becomes on a finger - belongs to `PhoneHud` and is held in `test_phone_hud.gd`; what is held here is
## the glue: which node the room is read from, and what happens when there is nothing to fit.
##
## A control is built and freed in the test that made it, the same way `test_hud_probe.gd` does it.

const ToolPaletteScript := preload("res://scripts/tool_palette.gd")

var _made: Array[Node] = []


func test_a_panel_grown_to_hold_its_contents_still_answers_the_room_its_anchors_gave_it() -> void:
	# The defect that was measured, twice: a re-flow read the panel's own width back, which is the width the
	# *previous* re-flow had grown it to, so the edit row went from three columns to four on the second showing
	# and stayed at four. This grows the panel exactly as `grow_to_its_contents` grows it - by its contents -
	# and then asks for the room. It is still the 200 px the scene's anchors describe, which is the whole point:
	# anchors and offsets are what the scene wrote down, and a pass that widened the panel cannot change them.
	#
	# Not by assigning `size`, which would prove nothing: the engine answers that by rewriting the offsets, so
	# the anchors would legitimately say 500 afterwards and the room would be right to report it.
	var root: Control = _root()
	var panel := PanelContainer.new()
	panel.anchor_right = 0.0
	panel.offset_right = 200.0
	root.add_child(panel)
	var column := VBoxContainer.new()
	panel.add_child(column)
	var words := Button.new()
	words.text = "A word long enough to be wider than the panel it is in"
	column.add_child(words)

	var anchored: float = ToolPaletteScript.room(panel)
	assert(is_equal_approx(anchored, 200.0), "the anchors give 200 px: %.1f" % anchored)
	ToolPaletteScript.grow_to_its_contents(panel, column)
	assert(panel.custom_minimum_size.x > 0.0, "and the panel was grown to hold the column")
	assert(
		is_equal_approx(ToolPaletteScript.room(panel), anchored),
		"the grown panel still answers the room its anchors gave it: %.1f" % ToolPaletteScript.room(panel),
	)
	_free_made()


func test_a_panel_that_is_not_there_has_no_room_rather_than_failing() -> void:
	# Zero is the answer that leaves the fitting alone, which is the only honest one for a HUD with no palette.
	assert(ToolPaletteScript.room(null) == 0.0, "nothing to measure is no room")
	ToolPaletteScript.fit(null, 2.0, 300.0)
	ToolPaletteScript.grow_to_its_contents(null, null)
	ToolPaletteScript.reflow_the_tool_row(null, null, [])
	ToolPaletteScript.reflow_the_edit_row(null, null, [])
	assert(true, "fitting nothing is not a failure")


func test_a_re_flow_of_a_column_with_no_grid_leaves_it_alone() -> void:
	var root: Control = _root()
	var panel := PanelContainer.new()
	root.add_child(panel)
	var column := VBoxContainer.new()
	panel.add_child(column)
	var before: PackedStringArray = _children_named(column)

	ToolPaletteScript.reflow_the_tool_row(panel, column, [])
	ToolPaletteScript.reflow_the_edit_row(panel, column, [])

	assert(_children_named(column) == before, "a column with no grid is left as it was")
	assert(panel.custom_minimum_size.x == 0.0, "and nothing was widened for it")
	_free_made()


## A root in the tree to hang controls on.
func _root() -> Control:
	var made := Control.new()
	made.name = "PaletteRoot"
	made.size = Vector2(400.0, 400.0)
	_made.append(made)
	add_child(made)
	return made


## What a column holds, by name: a re-flow that invented a node would show here.
func _children_named(column: Node) -> PackedStringArray:
	var names := PackedStringArray()
	for child: Node in column.get_children():
		names.append(child.name)
	return names


## Take each thing back out of the tree before freeing it, which is the order every page test here uses: a
## node freed while it is still a child is freed under the frame that is walking the tree.
func _free_made() -> void:
	for node: Node in _made:
		if not is_instance_valid(node):
			continue
		if node.get_parent() != null:
			node.get_parent().remove_child(node)
		node.free()
	_made.clear()
