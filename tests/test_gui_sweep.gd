extends Node
## The sweep's own two rules, held down: **what a door put up is found wherever it is kept and whichever kind of
## thing it is**, and the sweep ends when it has said its verdict.
##
## The first is a fault this tool had for as long as it has existed. Its search looked only among the Hud's own
## children for a visible `Window`, so six doors - the panels, which are `Control`s laid over the drawing rather
## than pages - were reported as *nothing came up*; and because a door answered that way was never put away, the
## panels piled up inside one another and the block filled with one panel's words drawn over the next one's.
##
## Both rules are worked out on a tree built here, because neither needs the game: what a door did is a difference
## between two readings of what is visible, and the ending is read from the source, as the audit's own tests read
## the shape of a call only a live tree could make.

const Sweep := preload("res://tools/gui_sweep.gd")


## A thing one node deeper than the Hud is still a thing the Hud is showing.
func test_what_is_up_is_found_wherever_it_is_kept() -> void:
	var hud := Node.new()
	add_child(hud)
	var kept_under := Node.new()
	kept_under.name = "Root"
	hud.add_child(kept_under)
	var deep := Window.new()
	deep.name = "WaterPage"
	kept_under.add_child(deep)
	deep.visible = false

	assert(Sweep.doors_up(hud).is_empty(), "nothing is up to begin with")
	deep.visible = true
	var up: Array[Node] = Sweep.doors_up(hud)
	assert(up.has(deep), "a thing one node deeper than the Hud is found")
	assert(up.size() == 1, "and it is the only thing up: %d" % up.size())
	hud.free()


## **A panel's controls are switched on inside it**, so a panel nobody has opened would have every one of them
## reporting itself visible: what says a panel is up is the tree's answer rather than a control's own flag.
func test_a_control_inside_a_panel_nobody_opened_is_not_up() -> void:
	var hud := Node.new()
	add_child(hud)
	var panel := PanelContainer.new()
	hud.add_child(panel)
	var press := Button.new()
	press.name = "WaterTheArea"
	panel.add_child(press)
	panel.visible = false

	assert(not Sweep.doors_up(hud).has(press), "a button inside a closed panel is not up")
	panel.visible = true
	assert(Sweep.doors_up(hud).has(press), "and it is up with the panel it is inside")
	hud.free()


## **The outermost thing that became visible is what the door put up.** A page or a panel shows its contents with
## it, so without that rule a door would be answered with one of its own buttons - and one rule has to serve both
## kinds of thing, which is what the six panels needed.
func test_what_came_up_is_the_outermost_thing_that_became_visible() -> void:
	var hud := Node.new()
	add_child(hud)
	var wrapper := PanelContainer.new()
	wrapper.name = "WaterPage"
	wrapper.visible = false
	hud.add_child(wrapper)
	var row := HBoxContainer.new()
	wrapper.add_child(row)
	var press := Button.new()
	press.name = "WaterTheArea"
	row.add_child(press)

	var before: Array[Node] = Sweep.doors_up(hud)
	assert(before.is_empty(), "nothing is up before the door is called")
	wrapper.visible = true
	assert(
		Sweep.what_came_up(before, Sweep.doors_up(hud)) == wrapper,
		"the panel is what came up, not one of its buttons",
	)
	assert(Sweep.scope_of(wrapper) == "WaterPage", "and it is named by the name it was given")
	assert(Sweep.scope_of(press) == "WaterTheArea", "as is a control with no page script of its own")
	hud.free()


## A door that closes one page as it opens another is still answered, and a door that put up nothing names nothing -
## which is the line a reader has to be able to trust rather than one that stands for a panel nobody looked at.
func test_a_door_that_swaps_pages_is_answered_and_one_that_opens_nothing_is_not() -> void:
	var hud := Node.new()
	add_child(hud)
	var first := Window.new()
	first.name = "First"
	hud.add_child(first)
	var second := Window.new()
	second.name = "Second"
	hud.add_child(second)
	first.visible = false
	second.visible = false

	var before: Array[Node] = Sweep.doors_up(hud)
	second.visible = true
	assert(Sweep.what_came_up(before, Sweep.doors_up(hud)) == second, "the one that came up is the answer")
	var was_up: Array[Node] = Sweep.doors_up(hud)
	second.visible = false
	first.visible = true
	assert(Sweep.what_came_up(was_up, Sweep.doors_up(hud)) == first, "and a swap answers with the new one")
	assert(Sweep.what_came_up(was_up, was_up) == null, "while a door that put up nothing names nothing")
	hud.free()


## A tool that prints its verdict and then sits there for ever is a run somebody has to time out, which is a fault
## this project has already fixed in another tool. The ending needs a real tree, so the source is what is read.
func test_the_sweep_ends_when_it_is_done() -> void:
	var source: String = FileAccess.get_file_as_string("res://tools/gui_sweep.gd")
	assert(source.contains("get_tree().quit()"), "the sweep puts the program away when it has said its verdict")
