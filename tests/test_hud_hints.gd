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


## What the polyline is telling the drawer to press.
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
func test_the_keys_are_the_ones_the_legend_promises() -> void:
	var numbers: Array[String] = ["1", "2", "3", "4", "5", "6", "7", "8", "9"]
	var tool_keys: Array[String] = []
	for pair: Array in Hud.DRAFTING_TOOLS:
		tool_keys.append(Hud._key_label(pair[0]))
	assert(tool_keys == numbers)
	assert(Hud._key_label(&"draft_finish") == "Enter")
	assert(Hud._key_label(&"draft_close") == "C")
	assert(Hud._key_label(&"draft_undo_point") == "Backspace")
	assert(Hud._key_label(&"draft_cancel") == "Esc")
	assert(Hud._key_label(&"draft_undo") == "Ctrl+Z")
	assert(Hud._key_label(&"draft_plot") == "P")
	assert(Hud._key_label(&"draft_dimension_style") == "K")
	assert(Hud._key_label(&"draft_mode") == "D")


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


## The polyline's prompt tells the drawer to press C to close the shape. It did so
## while nothing listened for C: the tool could close a shape, the command was
## tested, and the key that was supposed to reach it was never wired up. A prompt
## is a promise, and this is the binding that keeps it.
func test_the_key_the_polyline_names_for_closing_is_bound() -> void:
	assert(_polyline_status().contains("C to close"))
	assert(Hud._key_label(&"draft_close") == "C")


## And the key it names for finishing, likewise.
func test_the_key_the_polyline_names_for_finishing_is_bound() -> void:
	assert(_polyline_status().contains("Enter to finish"))
	assert(Hud._key_label(&"draft_finish") == "Enter")


# --- shape of the block --------------------------------------------------------------


## The one key a user cannot discover by accident is advertised on the idle status
## line, which is where the other one - P - already is. The rest of the legend
## appears once the tools are armed.
func test_the_idle_status_advertises_the_key_that_arms_the_tools() -> void:
	var controller = Ctrl.new()
	assert(controller.status().contains("D: drawing tools"))
	assert(controller.status().contains("P plots a sheet"))
	controller.free()


# --- shape of the block --------------------------------------------------------------


## The legend is drawn in a panel with room for five lines, so it had better be
## five lines.
func test_the_legend_is_as_many_lines_as_the_panel_has_room_for() -> void:
	var rows := Hud.drafting_rows()
	assert(rows.size() == 5)
	assert(rows[0].contains("leaves the drawing tools"))
	assert(rows[1].contains("line"))
	assert(rows[2].contains("measure"))
	# No blank lines: every row has something on it.
	for row: String in rows:
		assert(row.strip_edges() != "")