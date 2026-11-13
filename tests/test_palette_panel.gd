extends Node
## The palette's own controls: built from the tables that already exist, reporting what was chosen rather
## than doing it, and surviving a HUD with no drawing at all.
##
## Nothing here needs a scene or a HUD. `PalettePanel` is handed its controller and its key words, so a bare
## `PalettePanel.new()` is the whole fixture - which is the point of the panel leaving the HUD: the wiring is
## held down without building a window to hold it. The rules about what a *drawing* does live in the tests of
## the controller and the document; what is held here is the seam.

const PalettePanelScript := preload("res://scripts/palette_panel.gd")
const DraftToolScript := preload("res://scripts/draft/draft_tool.gd")
const DraftControllerScript := preload("res://scripts/draft/draft_controller.gd")
const DraftDocumentScript := preload("res://scripts/draft/draft_document.gd")
const SnapScript := preload("res://scripts/draft/snap_engine.gd")
const MenuBarPlanScript := preload("res://scripts/menu_bar_plan.gd")

var _made: Array[Object] = []


func test_a_palette_has_one_button_per_tool_and_per_editing_command() -> void:
	# The whole reason this panel is built from the tables: there is one list of tools in the program, and a
	# button here exists because a tool does. A hand-written scene would be a second list to keep in step.
	var panel: PalettePanelScript = _built()
	assert(
		panel.tool_buttons().size() == DraftToolScript.DRAFTING_TOOLS.size(),
		"one button per drawing tool: %d" % panel.tool_buttons().size(),
	)
	assert(
		panel.edit_buttons().size() == DraftControllerScript.EDIT_TOOLS.size(),
		"one button per editing command: %d" % panel.edit_buttons().size(),
	)
	for index in panel.tool_buttons().size():
		assert(
			panel.tool_buttons()[index].name == String(DraftToolScript.DRAFTING_TOOLS[index][0]),
			"a tool button is named after the action it stands for, so the tree says what it does",
		)
	_free_made()


func test_a_layer_or_a_lock_is_offered_even_with_no_drawing_to_offer_it_for() -> void:
	# The guard case: a scene with no drawing still gets a palette rather than nothing, and every control it
	# draws is present and dead. Something that is not there cannot be seen to be unavailable.
	var panel: PalettePanelScript = _built()
	assert(panel.layer_button() != null and panel.layer_button().item_count == 0, "no layers to offer")
	assert(panel.lock_button() != null, "and a lock that reads unlocked")
	assert(not panel.lock_button().button_pressed, "an unlocked box for a layer there is none of")
	assert(panel.arm_button() != null and not panel.arm_button().button_pressed, "and the tools put away")
	panel.refresh(false, "", "")
	_free_made()


func test_every_command_row_names_an_action_the_menu_bar_holds() -> void:
	# The rule that lets the palette hold no `Callable` at all: a command button reports the action it stands
	# for, and the HUD runs the menu bar's own entry for that action. An action the bar does not hold would be
	# a button that does nothing - so this is the test that keeps the two tables from drifting apart, and the
	# reason `PalettePanel` may not invent a ninth way to do something the menu already does.
	var known: Array[StringName] = []
	for entry: Dictionary in MenuBarPlanScript.menu_entries():
		var action: StringName = StringName(entry.get("action", &""))
		if action != &"":
			known.append(action)
	for row: Array in PalettePanelScript.COMMAND_ROWS:
		for command: Array in row[1]:
			assert(known.has(StringName(command[0])), "%s is an action the menu bar holds as well" % command[0])
			assert(not String(command[1]).is_empty(), "%s says what it does" % command[0])


func test_a_click_reports_which_tool_was_chosen_and_does_nothing_else() -> void:
	# What the panel is for: it says what was chosen. It has no controller here, so a report is the only thing
	# that can happen - which is exactly the property being asserted. Each kind of choice arrives by its own
	# signal, so a caller can take a tool without being told about an editing command.
	var panel: PalettePanelScript = _built()
	var tools: Array[int] = []
	var edits: Array[int] = []
	panel.tool_chosen.connect(
		func(kind: int) -> void:
			tools.append(kind),
	)
	panel.edit_chosen.connect(
		func(kind: int) -> void:
			edits.append(kind),
	)
	panel.tool_buttons()[0].pressed.emit()
	assert(tools == [int(DraftToolScript.DRAFTING_TOOLS[0][2])], "the first tool, by its kind: %s" % str(tools))
	assert(edits.is_empty(), "and an editing command is not a drawing tool")
	panel.edit_buttons()[0].pressed.emit()
	assert(edits == [int(DraftControllerScript.EDIT_TOOLS[0][2])], "the first edit, by its kind: %s" % str(edits))
	assert(tools.size() == 1, "and it did not arrive as a tool as well")
	_free_made()


func test_a_command_reports_the_action_it_stands_for() -> void:
	var row: Array = PalettePanelScript.COMMAND_ROWS[0]
	var first: Array = row[1][0]
	var panel: PalettePanelScript = _built()
	var chosen: Array[StringName] = []
	panel.command_chosen.connect(
		func(action: StringName) -> void:
			chosen.append(action),
	)
	var button: Button = panel.find_child(String(first[0]), true, false) as Button
	assert(button != null, "the command row built a button for %s" % first[0])
	button.pressed.emit()
	assert(chosen == [StringName(first[0])], "and it reports the action the menu bar knows it by")
	_free_made()


func test_the_arm_toggle_reports_the_state_the_button_now_reads() -> void:
	var panel: PalettePanelScript = _built()
	var heard: Array[bool] = []
	panel.armed.connect(
		func(on: bool) -> void:
			heard.append(on),
	)
	panel.arm_button().button_pressed = true
	assert(heard == [true], "arming the drawing is reported: %s" % str(heard))
	panel.arm_button().button_pressed = false
	assert(heard == [true, false], "and putting it away again: %s" % str(heard))
	_free_made()


func test_a_refresh_sets_the_buttons_without_clicking_them() -> void:
	# The rule the silent setters exist for, and the bug they were written after: the refresh writes these
	# buttons every time the drawing moves, and a button written the ordinary way fires its handler - the
	# palette would then be driving the controller it is reporting on, once per change and a frame late.
	var controller: DraftControllerScript = _controller()
	var panel: PalettePanelScript = _built(controller)
	var heard: Array[bool] = []
	panel.armed.connect(
		func(on: bool) -> void:
			heard.append(on),
	)
	controller.set_drawing(true)
	panel.refresh(false, "", "")
	assert(panel.arm_button().button_pressed, "the button now reads the drawing's own state")
	assert(heard.is_empty(), "and nobody was told a person had chosen it: %s" % str(heard))
	_free_made()


func test_a_label_puts_the_key_on_a_second_line_and_nothing_at_all_without_one() -> void:
	var pair: Array = [&"draft_line", "line"]
	assert(
		PalettePanelScript.label(pair, "L") == "Line\nL",
		"the tool on one line and the key that does it on the next",
	)
	assert(
		PalettePanelScript.label(pair, "") == "Line",
		"and an action nothing is bound to says its name alone rather than trailing a bracket",
	)


func test_the_words_for_the_keys_are_handed_in_rather_than_read_here() -> void:
	# The input map is the HUD's to read; the panel is a second copy of nothing. What it is handed it shows,
	# and what it is not handed it leaves out - the honest answer for a command nobody bound.
	var pair: Array = DraftToolScript.DRAFTING_TOOLS[0]
	var action: StringName = StringName(pair[0])
	var panel: PalettePanelScript = _built(null, { action: "K" })
	assert(panel.key_words(action) == "K", "the words arrive with the build")
	assert(panel.tool_buttons()[0].text.ends_with("\nK"), "and reach the button that stands for it")
	_free_made()
	var bare: PalettePanelScript = _built()
	assert(bare.key_words(action).is_empty(), "an action nothing was said about has no key")
	assert(not bare.tool_buttons()[0].text.contains("\n"), "and its button says its name alone")
	_free_made()


## A palette built with no controller and no keys unless a test hands one over: the guard case rather than a
## working palette, because the HUD builds one only where it has a drawing.
func _built(draft: DraftControllerScript = null, keys: Dictionary = { }) -> PalettePanelScript:
	var panel := PalettePanelScript.new()
	_made.append(panel)
	panel.build(draft, keys)
	return panel


## A controller with its parts and no scene tree, the way `test_gesture_labels.gd` builds one: none of this
## needs a canvas, because setting a button is bookkeeping rather than a picture.
func _controller() -> DraftControllerScript:
	var controller := DraftControllerScript.new()
	controller.document = DraftDocumentScript.new()
	controller.snap = SnapScript.new()
	controller.tool = DraftToolScript.new()
	_made.append(controller)
	return controller


## Free what this test made. A node is freed and a `RefCounted` is simply let go of, so this holds whichever
## kind either end of the seam turns out to be.
func _free_made() -> void:
	for made: Object in _made:
		if not is_instance_valid(made):
			continue
		if made is Node:
			var node: Node = made as Node
			if node.get_parent() != null:
				node.get_parent().remove_child(node)
			node.free()
	_made.clear()
