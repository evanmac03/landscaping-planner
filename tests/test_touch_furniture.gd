extends Node
## The phone's furniture, held to the one rule a table of kinds can break: the tools it calls dimensions have to
## be tools this program has, or the `Dim` tab offers a row that opens nothing.

const TouchFurnitureScript := preload("res://scripts/touch_furniture.gd")
const PalettePanelScript := preload("res://scripts/palette_panel.gd")


## Every kind the furniture calls a dimension is a kind some drawing tool actually declares.
##
## The other half of the split is the reason this matters: a dimension kind mentioned nowhere in `DRAFTING_TOOLS`
## would put a button in the `Dim` tab that stands for no tool, and a tool whose kind is *both* categories would
## be offered in two tabs at once. Both are invisible in a table and both are a defect a person would meet.
func test_every_dimension_kind_is_a_tool_the_program_has() -> void:
	var kinds_in_use: Array = []
	for entry: Array in PalettePanelScript.DRAFTING_TOOLS:
		kinds_in_use.append(int(entry[2]))
	for kind: int in TouchFurnitureScript.DIMENSION_KINDS:
		assert(
			kinds_in_use.has(kind),
			"the dimension kind %d stands for a tool the palette builds: in use %s" % [kind, str(kinds_in_use)],
		)
	assert(TouchFurnitureScript.DIMENSION_KINDS.size() > 0, "and there is at least one dimension to put in that tab")


## The two tabs between them offer every drawing tool exactly once.
##
## A tool in neither tab could not be reached by a finger at all, and a tool in both is two doors to one thing -
## and neither shows up in the table, because every row looks perfectly reasonable read on its own.
func test_the_two_tabs_partition_the_drawing_tools() -> void:
	var in_draw: Array[int] = TouchFurnitureScript.tool_indices_for_a_tab("Draw")
	var in_dim: Array[int] = TouchFurnitureScript.tool_indices_for_a_tab("Dim")
	var every_tool: int = PalettePanelScript.DRAFTING_TOOLS.size()
	assert(
		in_draw.size() + in_dim.size() == every_tool,
		"every tool is offered exactly once: %d + %d against %d" % [in_draw.size(), in_dim.size(), every_tool],
	)
	for index: int in in_draw:
		assert(not in_dim.has(index), "and no tool is offered in both tabs: %d" % index)
	assert(in_draw.size() > 0, "the Draw tab has something in it")
	assert(in_dim.size() > 0, "and so does the Dim tab")


## A tab fills the strip from whatever its door hands back, however that list reaches it.
##
## **This is the shape the real door has, and the shape `press_a_tab` first refused.** The HUD keeps its tool
## buttons in a dictionary, so what a door hands over is an `Array[Button]` held in a `Variant` - not a typed
## array the callee can assign straight across - and the first version re-typed it through
## `Array(asked, TYPE_OBJECT, &"Array", [Button])`, where `&"Array"` is the *element's* class and the cast
## therefore asked for an array of arrays. Pressing the first tab ever pressed threw
## `Trying to assign an array of type "Array[Array]" to a variable of type "Array[Button]"`. A development view
## found it, which is to say by running rather than by reading: every line of it looks reasonable on its own.
func test_a_tab_fills_the_strip_from_whatever_its_door_hands_back() -> void:
	var made: Array[Button] = [Button.new(), Button.new()]
	var held: Dictionary = { "Draw": made }
	var furniture: TouchFurnitureScript = TouchFurnitureScript.new()
	var strip := PanelContainer.new()
	var strip_row := HBoxContainer.new()
	var tabs := HBoxContainer.new()
	# **A tool starts in the palette's own column, and the fixture has to say so or it is not the same thing.**
	# A node with no parent cannot be reparented at all - `press_a_tab` says so in as many words, and the strip
	# came back empty until this was put right in the development view too. A tool's home is the whole reason
	# `put_the_tools_back` has somewhere to hand it back to.
	var column: PalettePanelScript = PalettePanelScript.new()
	for button: Button in made:
		column.add_child(button)
	furniture.strip = strip
	furniture.strip_row = strip_row
	furniture.tabs = tabs
	furniture.palette_column = column
	furniture.tools_for_door = func(_tab: String) -> Variant:
		return held["Draw"]
	furniture.press_a_tab("Draw")
	assert(
		strip_row.get_child_count() == made.size(),
		"every button the door handed back stands in the strip: %d" % strip_row.get_child_count(),
	)
	assert(strip.visible, "and the strip is shown, because there is something in it")
	assert(furniture.tab_in_hand == "Draw", "with the tab that did it held as the one in hand")
	for node: Node in [strip, strip_row, tabs, column]:
		node.free()
