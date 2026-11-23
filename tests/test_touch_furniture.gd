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


## **One undo button, moved rather than copied.** A desk's palette is put away on a finger, so the button it holds
## is off the screen there and a thumb has no undo at all. This is the rule that the finger's arrangement gets
## *that* button - the same instance, reporting the same command - and hands it back wearing what it wore.
##
## The fixture is a faithful miniature of the dock the scene describes: a plate holding a scroll holding the strip.
## It cannot be less than that, because the wrap is the point: a button left *inside* the scroll is a button a
## person has to scroll past a tool to find, which is the fault this closes. `PalettePanel.build` is callable with
## no draft for exactly this reason - a bare `PalettePanel.new()` is the whole fixture.
func test_the_finger_borrows_the_palettes_own_undo_and_hands_it_back_as_it_was() -> void:
	var column: PalettePanelScript = PalettePanelScript.new()
	column.build(null, { })
	var borrowed: Button = column.undo_button()
	assert(borrowed != null, "the palette builds an Undo of its own, and that is the button a finger gets")
	var plate := PanelContainer.new()
	var scrolling := ScrollContainer.new()
	var strip_row := HBoxContainer.new()
	scrolling.add_child(strip_row)
	plate.add_child(scrolling)
	var furniture: TouchFurnitureScript = TouchFurnitureScript.new()
	furniture.strip = plate
	furniture.strip_row = strip_row
	furniture.palette_column = column
	furniture.on_a_finger = true
	furniture.stated_density = 450.0
	furniture.stated_scale = 1.0
	var flags: int = borrowed.size_flags_horizontal
	var wanted: Vector2 = borrowed.custom_minimum_size
	furniture.stand_the_gesture_button()
	assert(borrowed.get_parent() != column, "the button leaves the palette for the dock while a finger is up")
	assert(
		borrowed.get_parent() != scrolling,
		"and not inside the strip's scroll, where a tab's own tools would push it out of reach",
	)
	assert(borrowed.get_parent() == scrolling.get_parent(), "but beside it, in the one row both of them stand in")
	assert(scrolling.get_parent().get_parent() == plate, "which is a level in from the plate the scene gave the strip")
	assert(
		borrowed.custom_minimum_size.y > wanted.y,
		"dressed for a thumb rather than left at the size the palette gave it: %s" % str(borrowed.custom_minimum_size),
	)
	assert(borrowed.has_theme_font_size_override(&"font_size"), "and wearing the device's own type")
	furniture.give_the_gesture_button_back()
	assert(borrowed.get_parent() == column, "the arrangement it was borrowed for hands it back")
	assert(borrowed.size_flags_horizontal == flags, "wearing the flags the palette laid it out with")
	assert(borrowed.custom_minimum_size == wanted, "and the size the palette gave it back")
	assert(
		not borrowed.has_theme_font_size_override(&"font_size"),
		"and the palette's own type, not the device's - a phone session must not deform a desk's palette",
	)
	for node: Node in [plate, column]:
		node.free()


## **The dock is given ground on the sides as well as along the foot**, because the band a phone keeps is not only
## along its foot: held sideways the camera is across a side, and the dock is placed by hand like the palette and
## the top bar - both of which had been given that ground while this piece of furniture never asked. Measured on
## the A16W lying down, the display's first 100 px is the room's first 62, and the dock's `Draw` tab - the first
## thing a thumb reaches on it - stood 25 px inside the band, so a press aimed at a tool was answered by the
## system. The reading is handed in rather than taken here, which is the whole reason the arithmetic is its own
## function: a device with a band across it is not a thing this machine can be.
func test_the_dock_gives_the_device_its_ground_on_the_sides_as_well_as_the_foot() -> void:
	var at_a_desk: Vector4 = TouchFurnitureScript.offsets_for_the_dock(49.0, Vector4i.ZERO, 200.0)
	assert(
		at_a_desk.x == 49.0 and at_a_desk.y == -49.0,
		"a display keeping nothing is given the scene's own margins: %s" % str(at_a_desk),
	)
	assert(at_a_desk.z == -200.0 and at_a_desk.w == -200.0, "and stands above the foot by what it was told")

	# The A16W lying down: its camera along the left, and the dock's own edge moved in by that band.
	var lying: Vector4 = TouchFurnitureScript.offsets_for_the_dock(49.0, Vector4i(62, 0, 0, 42), 200.0)
	assert(lying.x == 111.0, "a band on the left moves the dock's left edge in by it: %s" % lying.x)
	assert(lying.y == -49.0, "and leaves the right edge exactly where the scene drew it: %s" % lying.y)

	# **And the mirror of it**, which is the half a one-sided guess would get wrong: the same phone held the other
	# way keeps its camera on the right, so the right edge comes in and the left one does not move.
	var the_other_way: Vector4 = TouchFurnitureScript.offsets_for_the_dock(49.0, Vector4i(0, 0, 62, 42), 200.0)
	assert(the_other_way.x == 49.0, "a phone lying the other way keeps its left edge: %s" % the_other_way.x)
	assert(the_other_way.y == -111.0, "and gives ground on the right instead: %s" % the_other_way.y)
