extends Node
## Tests for the drafting key legend, and for the keys it promises.
##
## A legend is documentation that rots in silence: it is the one place a user
## learns which key does what, so a legend that has drifted sends them to a key
## that does nothing and nothing else in the project would notice. Every entry is
## therefore checked against the binding it claims, and the keys are pinned
## outright - a test that only compared the legend with itself would pass happily
## while both were wrong.

const Hud := preload("res://scripts/hud.gd")
const Tool := preload("res://scripts/draft/draft_tool.gd")
const Ctrl := preload("res://scripts/draft/draft_controller.gd")
const Document := preload("res://scripts/draft/draft_document.gd")
const SnapScript := preload("res://scripts/draft/snap_engine.gd")
const LayerSet := preload("res://scripts/draft/layer_set.gd")


## A drafting controller with its parts but no scene tree. The canvas and the
## overlay are absent, which _refresh_canvas already tolerates.
func _controller():
	var controller = Ctrl.new()
	controller.document = Document.new()
	controller.snap = SnapScript.new()
	controller.tool = Tool.new()
	return controller


## What the polyline is saying about itself while it is in hand.
func _polyline_status() -> String:
	var tool = Tool.new()
	tool.begin(Tool.Kind.POLYLINE)
	tool.click(Vector2(0, 0))
	tool.click(Vector2(3, 0))
	return tool.status()


# --- the legend names the right keys -------------------------------------------------


## The keys a draughtsman is promised, stated here rather than read back out of
## the legend. This is the assertion that catches a mis-read binding; the tests
## below only catch a legend that disagrees with the key reader.
##
## The nine number keys belong to the nine tools that were there first. The angular dimension is the
## tenth command and there is no digit left for it, so it takes the free key beside the digit row - which
## is also the key a decimal degree is written with, so the letter it carries is at least the letter of
## the thing it makes.
func test_the_keys_are_the_ones_the_legend_promises() -> void:
	var numbers: Array[String] = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "."]
	var tool_keys: Array[String] = []
	for pair: Array in Hud.DRAFTING_TOOLS:
		tool_keys.append(Hud._key_label(pair[0]))
	assert(tool_keys == numbers, "tool keys are %s, expected %s" % [tool_keys, numbers])
	assert(Hud._key_label(&"draft_finish") == "Enter")
	assert(Hud._key_label(&"draft_close") == "C")
	assert(Hud._key_label(&"draft_undo_point") == "Backspace")
	assert(Hud._key_label(&"draft_cancel") == "Esc")
	assert(Hud._key_label(&"draft_undo") == "Ctrl+Z")
	assert(Hud._key_label(&"draft_redo") == "Ctrl+Y")
	assert(Hud._key_label(&"draft_plot") == "P")
	assert(Hud._key_label(&"draft_dimension_style") == "K")
	# Mode moved off D: walking about on the ground is D, and two commands on one key means one of them
	# silently never fires. It sits next to the tools it switches between instead - 0 is the key that
	# puts the tools away.
	assert(Hud._key_label(&"draft_mode") == "0")


## Ctrl is part of the key. Printing a bare Z would name a different command.
func test_a_modified_key_keeps_its_modifier() -> void:
	assert(Hud._key_label(&"draft_undo") != "Z")
	assert(Hud._key_label(&"draft_undo").begins_with("Ctrl+"))


## An action bound to nothing has no key, rather than a blank one: the legend
## leaves the line out instead of printing a key that cannot be pressed.
func test_an_unbound_action_has_no_key() -> void:
	assert(Hud._key_label(&"a_binding_that_does_not_exist") == "")


# --- every entry is backed by a binding ----------------------------------------------


func test_every_drafting_tool_is_named_with_its_own_key() -> void:
	var legend := Hud.drafting_hints()
	for pair: Array in Hud.DRAFTING_TOOLS:
		var action: StringName = pair[0]
		assert(InputMap.has_action(action), "%s is not an action" % action)
		var key: String = Hud._key_label(action)
		assert(key != "", "%s is bound to nothing" % action)
		assert(
			legend.contains("%s %s" % [key, pair[1]]),
			"the legend does not say %s means %s" % [key, pair[1]]
		)


func test_every_drafting_command_is_named_with_its_own_key() -> void:
	var legend := Hud.drafting_hints()
	for pair: Array in Hud.DRAFTING_COMMANDS:
		var action: StringName = pair[0]
		assert(InputMap.has_action(action), "%s is not an action" % action)
		var key: String = Hud._key_label(action)
		assert(key != "", "%s is bound to nothing" % action)
		assert(
			legend.contains("%s %s" % [key, pair[1]]),
			"the legend does not say %s means %s" % [key, pair[1]]
		)


## The editing commands get their own row of the legend, and each is bound to a key
## with nothing else on it.
func test_every_edit_command_is_named_with_its_own_key() -> void:
	var legend := Hud.drafting_hints()
	var keys: Array[String] = []
	for pair: Array in Hud.EDIT_TOOLS:
		var action: StringName = pair[0]
		assert(InputMap.has_action(action), "%s is not an action" % action)
		var key: String = Hud._key_label(action)
		assert(key != "", "%s is bound to nothing" % action)
		assert(legend.contains("%s %s" % [key, pair[1]]), "the legend does not say %s" % key)
		assert(not keys.has(key), "%s is not shared with another command" % key)
		keys.append(key)
	assert(keys == ["O", "T", "X", "I", "E", "U", "J", "Y"], "the edit keys are the ones promised")


## The edit commands are exactly the controller's own set, so a command cannot
## arrive with no way to reach it, and a row cannot outlive its command.
func test_the_legend_row_is_the_controllers_own_edit_set() -> void:
	var offered: Array[int] = []
	for pair: Array in Hud.EDIT_TOOLS:
		offered.append(int(pair[2]))
	var expected: Array[int] = []
	for kind: int in Ctrl.EditKind.values():
		if kind != int(Ctrl.EditKind.NONE):
			expected.append(kind)
	offered.sort()
	expected.sort()
	assert(offered == expected, "the legend offers %s, the commands are %s" % [offered, expected])


# --- the layer lock ---------------------------------------------------------------


## Locking the layer in hand is the palette's decision, driven here rather than through a built
## palette. The lock belongs to the layer rather than to the button, and like any other change to
## the drawing it is one step of undo - a lock somebody tripped over is a change they may want back.
func test_locking_the_layer_in_hand_is_one_undoable_step() -> void:
	var controller = _controller()
	controller.set_layer(LayerSet.NEW_BED)
	var hud := Hud.new()
	hud._draft = controller
	assert(not controller.document.is_layer_locked(controller.current_layer()),
		"a fresh drawing has nothing locked")
	hud.set_layer_locked(true)
	assert(controller.document.is_layer_locked(LayerSet.NEW_BED))
	assert(controller.document.undo_last(), "a lock can be taken back")
	assert(not controller.document.is_layer_locked(LayerSet.NEW_BED), "and it lets go again")
	hud.free()
	controller.free()


## With no drawing there is no layer in hand, so the palette has nothing to lock and nothing to
## report: it says so rather than failing.
func test_a_hud_with_no_drawing_has_no_layer_to_lock() -> void:
	var hud := Hud.new()
	assert(not hud._is_layer_locked())
	hud.set_layer_locked(true)
	assert(not hud._is_layer_locked(), "and locking nothing locks nothing")
	hud.free()


## The legend covers every drafting action the project binds, and no others. A new
## tool cannot arrive without a line, and a line cannot outlive its binding.
func test_the_legend_covers_every_drafting_action_exactly() -> void:
	var covered: Array[StringName] = [&"draft_mode"]
	for pair: Array in Hud.DRAFTING_TOOLS:
		covered.append(pair[0])
	for pair: Array in Hud.DRAFTING_COMMANDS:
		covered.append(pair[0])
	var bound: Array[StringName] = []
	for action: StringName in InputMap.get_actions():
		if String(action).begins_with("draft_"):
			bound.append(action)
	covered.sort()
	bound.sort()
	assert(covered == bound, "legend covers %s, the project binds %s" % [covered, bound])


# --- the drawing's own prompts --------------------------------------------------------


## The polyline's prompt must promise no key at all, and the line drawn beside it must name the ones that
## really answer the tool.
##
## The prompt once read "Enter to finish, C to close" while nothing listened for C: the tool could close a
## shape, the command was tested, and the key that was meant to reach it was never wired up. A key written
## into a string is a promise that goes stale the moment a binding moves. So the prompt says nothing, the
## bindings say it, and this pair of assertions is what holds the two halves apart.
func test_the_polyline_prompt_promises_no_key_and_the_bindings_name_them() -> void:
	var prompt := _polyline_status()
	assert(prompt.contains("Specify the next point"), prompt)
	assert(not prompt.contains(Hud._key_label(&"draft_close")), prompt)
	assert(not prompt.to_lower().contains("enter"), prompt)
	assert(Hud._key_label(&"draft_close") == "C", "the close key is still C")
	assert(Hud._key_label(&"draft_finish") == "Enter", "and the finish key is still Enter")


## The line at the foot of the screen offers a ring of points - the polyline, and the contour that is a
## polyline landing on a grading layer - the three keys that end it, and the key that cancels it.
func test_a_tool_that_collects_points_until_told_to_stop_is_offered_its_keys() -> void:
	var keys := Hud.hand_keys(Tool.Kind.POLYLINE, false)
	assert(keys.contains("%s: finish" % Hud._key_label(&"draft_finish")), keys)
	assert(keys.contains("%s: close" % Hud._key_label(&"draft_close")), keys)
	assert(keys.contains("%s: drop a point" % Hud._key_label(&"draft_undo_point")), keys)
	assert(keys.contains("%s: cancel" % Hud._key_label(&"draft_cancel")), keys)


## A line takes two picks and is finished by the second of them. It has no last point to drop and no shape
## to close, so offering it those keys would be the legend-that-lies defect in miniature - and this is the
## line a person reads with their hand already busy, which is the worst place to be told about a key that
## does nothing.
func test_a_tool_that_ends_by_its_own_picks_is_not_offered_the_keys_that_end_a_ring() -> void:
	var keys := Hud.hand_keys(Tool.Kind.LINE, false)
	assert(not keys.contains(Hud._key_label(&"draft_finish")), keys)
	assert(not keys.contains(Hud._key_label(&"draft_close")), keys)
	assert(not keys.contains(Hud._key_label(&"draft_undo_point")), keys)
	assert(keys.contains("%s: cancel" % Hud._key_label(&"draft_cancel")), keys)


## A measurement is the other tool that ends by key rather than by a pick, because its answer is the pair
## of picks it has already taken; a rectangle never does.
func test_a_measurement_is_finished_by_key_where_a_rectangle_is_not() -> void:
	assert(Hud.hand_keys(Tool.Kind.MEASURE, false).contains(Hud._key_label(&"draft_finish")))
	assert(not Hud.hand_keys(Tool.Kind.RECTANGLE, false).contains(Hud._key_label(&"draft_finish")))


## An editing command is cancelled and never finished: there is no half-drawn shape to end or to close.
func test_an_editing_command_is_offered_only_the_key_that_cancels_it() -> void:
	assert(
		Hud.hand_keys(Tool.Kind.POLYLINE, true) == "%s: cancel" % Hud._key_label(&"draft_cancel"),
		Hud.hand_keys(Tool.Kind.POLYLINE, true),
	)


## The line reads as the tool's own words and then the keys that answer them, in that order, so a person
## reads what is being asked for before what to press.
func test_the_line_at_the_foot_reads_as_the_prompt_and_then_its_keys() -> void:
	var line := Hud.hand_hints(
		"Line  ·  Specify the second point", Hud.hand_keys(Tool.Kind.LINE, false)
	)
	assert(line.begins_with("Line  ·  Specify the second point"), line)
	assert(line.ends_with("%s: cancel" % Hud._key_label(&"draft_cancel")), line)


## The line the layout check measures the bottom panel against: the longest prompt any tool can be in,
## under its own name, with that tool's keys beside it.
func test_the_longest_line_the_foot_can_be_asked_to_carry_names_its_tool_and_its_keys() -> void:
	var worst := Hud.worst_hint_line()
	assert(worst.contains("Polyline"), worst)
	assert(worst.contains("%s: close" % Hud._key_label(&"draft_close")), worst)


# --- the instruction and the report are two different lines ---------------------------


## What the tool in hand is waiting for is the instruction, and the layer it is drawing on is not part of
## it: the palette's own row is on screen at the same moment and says which layer that is.
func test_the_instruction_does_not_repeat_the_layer_the_palette_already_shows() -> void:
	var controller = _controller()
	controller.arm(Tool.Kind.LINE)
	controller.tool.layer = LayerSet.NEW_HARDSCAPE
	var prompt: String = controller.prompt()
	assert(prompt.contains("Specify the first point"), prompt)
	assert(not prompt.contains(String(LayerSet.NEW_HARDSCAPE)), prompt)
	controller.free()


## The last thing the drawing said is a report rather than an instruction, so it is not on the prompt:
## a refusal left on the foot line would go on hiding what the tool in hand is waiting for.
func test_what_the_drawing_last_said_is_a_report_and_not_the_instruction() -> void:
	var controller = _controller()
	controller.arm(Tool.Kind.LINE)
	controller.last_message = "placed a line 2.50 m long"
	assert(controller.status_report() == "placed a line 2.50 m long", controller.status_report())
	assert(not controller.prompt().contains("placed a line"), controller.prompt())
	assert(controller.status().contains("placed a line"), "the status line still carries it")
	controller.free()


# --- shape of the block --------------------------------------------------------------


## The one key a user cannot discover by accident is advertised on the idle status
## line, which is where the other one - P - already is. The rest of the legend
## appears once the tools are armed.
func test_the_idle_status_advertises_the_key_that_arms_the_tools() -> void:
	var controller = Ctrl.new()
	# The line reads its keys from the bindings rather than printing a letter, so it cannot go on
	# naming a key that has moved - it did once, when the tools' key moved from D to 0. It is held
	# to the same labels the legend's own rows are written from, so the two cannot disagree.
	assert(controller.status().contains(Hud._key_label(&"draft_mode") + ": drawing tools"),
		controller.status())
	assert(controller.status().contains(Hud._key_label(&"draft_plot") + " plots a sheet"),
		controller.status())
	controller.free()


# --- shape of the block --------------------------------------------------------------


## The legend is drawn in a panel with room for six lines, so it had better be
## six lines. The sixth is the row of editing commands.
func test_the_legend_is_as_many_lines_as_the_panel_has_room_for() -> void:
	var rows := Hud.drafting_rows()
	assert(rows.size() == 6)
	assert(rows[0].contains("leaves the drawing tools"))
	assert(rows[1].contains("line"))
	assert(rows[2].contains("measure"))
	assert(rows[5].contains("offset"), "the last row is the editing commands")
	assert(rows[5].contains("erase"))
	# No blank lines: every row has something on it.
	for row: String in rows:
		assert(row.strip_edges() != "")


# --- the palette ----------------------------------------------------------------------


## Every drawing tool has a button, and no button names a tool that does not exist.
## This is the check that stops a new tool arriving with no way to pick it - which is
## precisely how the tools were reachable before there was a palette.
func test_the_palette_offers_a_button_for_every_drawing_tool() -> void:
	var offered: Array[int] = []
	for pair: Array in Hud.DRAFTING_TOOLS:
		offered.append(int(pair[2]))
	var expected: Array[int] = []
	for kind: Tool.Kind in Tool.Kind.values():
		# Selecting is not a drawing tool: it is what you do with no tool in hand.
		if kind == Tool.Kind.SELECT:
			continue
		# Nor are the three grading tools drawing tools. A spot level, a contour and a slope arrow put
		# no shape on the drawing - they state something about the ground's heights - so they are
		# reached from the Site menu and from the grading page, the same footing the ground zone and the
		# planting fill are on. That their own reach exists is what `test_hud_grading.gd` checks.
		if Tool.is_grading(kind):
			continue
		expected.append(int(kind))
	offered.sort()
	expected.sort()
	assert(offered == expected, "palette offers %s, the tools are %s" % [offered, expected])


## A button says the tool on one line and the key that does the same thing on the
## next, so the palette teaches the shortcut while it is being used.
func test_a_palette_button_is_labelled_with_its_tool_and_its_key() -> void:
	var labels: Array[String] = []
	for pair: Array in Hud.DRAFTING_TOOLS:
		labels.append(Hud.palette_label(pair))
	assert(labels[0] == "Line\n1")
	assert(labels[2] == "Rectangle\n3")
	assert(labels[5] == "Measure\n6")
	assert(labels[6] == "Aligned dim\n7")
	assert(labels[8] == "Radial dim\n9")
	for label: String in labels:
		assert(label.contains("\n"), "%s carries no key" % label)


## Choosing a tool from the palette is one press, not two: it puts the tool in your
## hand and starts drawing with it.
func test_choosing_a_tool_from_the_palette_arms_it() -> void:
	var controller = _controller()
	assert(not controller.drawing)
	controller.arm(Tool.Kind.CIRCLE)
	assert(controller.drawing)
	assert(controller.current_tool() == Tool.Kind.CIRCLE)
	assert(controller.current_layer() == LayerSet.NEW_HARDSCAPE)
	# An annotation still goes on the annotation layer, however it was chosen.
	controller.arm(Tool.Kind.DIMENSION_RADIUS)
	assert(controller.current_layer() == LayerSet.DIMENSION)
	controller.free()


## Arming is explicit rather than only a toggle, so a button that says what it does
## and a key that toggles can both be truthful about the same state.
func test_setting_the_armed_state_is_not_a_toggle() -> void:
	var controller = _controller()
	controller.set_drawing(true)
	assert(controller.drawing)
	# Asking for the state it is already in is not a request to leave it.
	controller.set_drawing(true)
	assert(controller.drawing)
	controller.set_drawing(false)
	assert(not controller.drawing)
	# And the key still toggles.
	controller.toggle_drawing()
	assert(controller.drawing)
	controller.free()


## The layer list comes from the document rather than from the preset table, and
## carries the purpose as well as the name: "300-NEW-HARD" is a code, "New paving,
## walls, steps" is a choice somebody can make.
func test_the_palette_lists_every_layer_with_a_purpose() -> void:
	var controller = _controller()
	var choices := controller.layer_choices()
	assert(choices.size() == controller.document.layers.size())
	for choice: Dictionary in choices:
		assert(controller.document.layers.has(choice["name"]), "unknown layer in the list")
		assert(String(choice["purpose"]) != "", "%s has no purpose" % choice["name"])
	# In draw order, which is the order the numeric prefixes put them in.
	assert(choices[0]["name"] == LayerSet.SURVEY_PROPERTY)
	assert(choices[choices.size() - 1]["name"] == LayerSet.GUIDES)
	controller.free()


# --- the view switch ------------------------------------------------------------------


## Q swaps the two overhead views, and the hints and the button name it because they
## read the key out of the input map rather than spelling it out. This is the
## assertion that would notice the key being rebound without the labels saying so.
func test_the_view_switch_is_advertised_as_the_key_it_is_really_on() -> void:
	assert(Hud._key_label(&"toggle_view") == "Q")


func test_the_control_hints_name_the_key_that_really_switches_views() -> void:
	var flat := Hud._hints_for(ViewController.ViewMode.PLAN_2D)
	assert(flat.contains("Q: 3D view"), flat)
	assert(not flat.contains(Hud.VIEW_KEY_TOKEN), flat)
	var solid := Hud._hints_for(ViewController.ViewMode.OVERHEAD_3D)
	assert(solid.contains("Q: 2D plan"), solid)
	assert(not solid.contains(Hud.VIEW_KEY_TOKEN), solid)
	# The ground view has its own way out, and names that instead.
	assert(Hud._hints_for(ViewController.ViewMode.GROUND).contains("G: back to overhead"))
	# And on a touchscreen it names the two gestures that really drive that view, because there is no
	# keyboard and no captured mouse there to name: a phone told "Mouse: look" is told nothing at all.
	var by_a_thumb := Hud._hints_for(ViewController.ViewMode.GROUND, true)
	assert(by_a_thumb.contains("Left thumb: walk"), by_a_thumb)
	assert(by_a_thumb.contains("Right thumb: drag"), by_a_thumb)
	assert(not by_a_thumb.contains("Mouse"), by_a_thumb)
	assert(not by_a_thumb.contains("W A S D"), by_a_thumb)


# --- the keyboard belongs to the drawing ----------------------------------------------


## A focused Button swallows Tab, Enter and Escape before the drawing tools are offered
## them, so clicking the palette once used to break the view switch and the finish and
## cancel keys without a word. Nothing in the HUD is typed into, so nothing in it takes
## the keyboard.
func test_a_hud_control_never_takes_keyboard_focus() -> void:
	var root := PanelContainer.new()
	var nested := VBoxContainer.new()
	root.add_child(nested)
	for index in 3:
		var button := Button.new()
		button.name = "Button%d" % index
		# One of them built the way the palette builds its own, one already focused.
		if index == 1:
			button.focus_mode = Control.FOCUS_ALL
		nested.add_child(button)
	# A control that is typed into would keep its focus, so the rule is about buttons.
	var field := LineEdit.new()
	root.add_child(field)

	Hud.release_keyboard_focus(root)

	for child: Node in nested.get_children():
		assert((child as Button).focus_mode == Control.FOCUS_NONE, String(child.name))
	# An OptionButton is a Button, and the layer list is one of those.
	var option := OptionButton.new()
	root.add_child(option)
	Hud.release_keyboard_focus(root)
	assert(option.focus_mode == Control.FOCUS_NONE)
	assert(field.focus_mode != Control.FOCUS_NONE)
	root.free()


func test_a_dialog_keeps_the_keyboard_while_it_is_up() -> void:
	# The rule is "nothing in the HUD holds the keyboard", and a modal dialog is not the HUD: taking
	# its own buttons out of the focus chain too left it unable to focus the one it opens on, which
	# is how a file dialog ends up on screen and unable to be typed into. A Window is the boundary,
	# because a Window is what the engine hands the keyboard to.
	var hud := PanelContainer.new()
	var hud_button := Button.new()
	hud.add_child(hud_button)
	var dialog := Window.new()
	hud.add_child(dialog)
	var dialog_button := Button.new()
	var field := LineEdit.new()
	dialog.add_child(dialog_button)
	dialog.add_child(field)
	var twice_nested := Button.new()
	var deeper := MarginContainer.new()
	deeper.add_child(twice_nested)
	dialog.add_child(deeper)

	Hud.release_keyboard_focus(hud)

	assert(hud_button.focus_mode == Control.FOCUS_NONE, "the HUD's own button is released")
	assert(dialog_button.focus_mode != Control.FOCUS_NONE, "the dialog's button keeps the keyboard")
	assert(twice_nested.focus_mode != Control.FOCUS_NONE, "however deep inside the dialog it is")
	assert(field.focus_mode != Control.FOCUS_NONE, "and the field it is typed into")

	# Everything off the HUD, because nothing else needs the rule.
	assert(Hud._inside_window(dialog_button))
	assert(Hud._inside_window(twice_nested))
	assert(not Hud._inside_window(hud_button))
	hud.free()