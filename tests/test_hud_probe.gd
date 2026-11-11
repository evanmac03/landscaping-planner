extends Node
## The probe that says what is on the screen, held to the two things a driver depends on: what it lists is
## what a finger could actually hit, and a page answers for its own controls rather than being walked into.
##
## Nothing here needs a scene: a control and a `Window` are built, put in the tree and freed in the test that
## made them. The pixels themselves are the phone's business - `Viewport.get_screen_transform()` is the
## engine's own answer, and what a screenshot's pixels really are is checked on the glass.

const HudProbeScript := preload("res://scripts/hud_probe.gd")

var _made: Array[Node] = []


func test_a_caption_that_is_two_lines_arrives_as_one() -> void:
	# The report is read back out of a logcat line, and a logcat line is cut off rather than wrapped. A tool
	# button's caption really is two rows - the tool over its shortcut key - so a newline left in would take
	# away the very thing the line was printed for, which is where on the screen that button is.
	var said: String = HudProbeScript.line_for_printing("Line\nR")
	assert(not said.contains("\n"), "the caption still holds a line break, so logcat would cut it there")
	assert(said.contains("Line") and said.contains("R"), "both rows of the caption should arrive")


func test_a_line_that_is_already_one_line_is_left_exactly_as_it_was() -> void:
	var said: String = HudProbeScript.line_for_printing("Line (L)")
	assert(said == "Line (L)", "a line with nothing to flatten should not be changed")


func test_a_row_says_where_each_of_its_controls_stands() -> void:
	# The top bar is a row that comes out wider than a phone's screen, and the one thing a screenshot
	# cannot answer is *which* control is the one that would not fit. A row of two buttons answers for
	# itself: the room it was given, and each control by name with what it asks for.
	var row := HBoxContainer.new()
	add_child(row)
	var one := Button.new()
	one.text = "Fit"
	row.add_child(one)
	var other := Button.new()
	other.text = "Ground view"
	row.add_child(other)
	var said: String = "\n".join(HudProbeScript.row_lines(row, "the top bar", 900.0))
	assert(said.contains("the top bar"), "the report names the row it is about")
	assert(said.contains("room=900"), "and the room it was given")
	assert(said.contains("Fit") and said.contains("Ground view"), "each control is named")
	assert(said.contains("min="), "and each says how much room it asks for")
	assert(said.contains("shown="), "and whether it is showing")
	remove_child(row)
	row.free()


func test_a_row_that_is_not_there_says_nothing_rather_than_failing() -> void:
	assert(HudProbeScript.row_lines(null, "the top bar", 0.0).is_empty(), "no row, nothing to say")


## Take each thing back out of the tree before freeing it, which is the order every other page test here
## uses: a node freed while it is still a child is freed under the frame that is walking the tree, and a
## `Window` is a `Viewport` - freeing one where it stands takes the whole run down rather than failing a test.
##
## A thing on the list may already be gone, because freeing a parent frees what it holds: the page freed with
## its root is not freed a second time, and asking a dead instance where its parent is would fail the test
## that got this far.
func _free_made() -> void:
	for node: Node in _made:
		if not is_instance_valid(node):
			continue
		if node.get_parent() != null:
			node.get_parent().remove_child(node)
		node.free()
	_made.clear()


## A root in the tree to hang controls on.
func _root() -> Control:
	var made := Control.new()
	made.name = "ProbeRoot"
	made.size = Vector2(400.0, 400.0)
	_made.append(made)
	add_child(made)
	return made


## A control to hang on a root, placed and sized so that it has a real rectangle. A `Node` rather than a
## `Control`, because the page the walk must not descend into is a `Window`.
func _control(root: Node, control: Control, at: Vector2, size: Vector2) -> Control:
	control.position = at
	control.size = size
	root.add_child(control)
	return control


func test_a_control_a_finger_can_hit_is_listed_with_where_to_tap_it() -> void:
	var root: Control = _root()
	var button := Button.new()
	button.text = "Design the garden"
	_control(root, button, Vector2(20.0, 40.0), Vector2(200.0, 60.0))

	var lines: PackedStringArray = HudProbeScript.tap_lines(root, "a page")
	assert(lines.size() == 1, "one control a finger can hit, one line: %s" % str(lines))
	var line: String = lines[0]
	assert(line.contains("Design the garden"), "the line says what it is called: %s" % line)
	assert(line.contains("centre ("), "and where to tap it: %s" % line)
	_free_made()


func test_the_middle_it_gives_is_inside_the_rectangle_it_gives() -> void:
	var root: Control = _root()
	var button := Button.new()
	button.text = "Tap me"
	_control(root, button, Vector2(20.0, 40.0), Vector2(200.0, 60.0))

	var outer: Rect2 = HudProbeScript.screen_rect(root)
	var inner: Rect2 = HudProbeScript.screen_rect(button)
	assert(outer.size.x > 0.0 and inner.size.x > 0.0, "both have a rectangle to speak of")
	assert(inner.get_center().is_equal_approx(inner.position + inner.size * 0.5),
		"the middle of a rectangle is the middle of a rectangle")
	assert(inner.position.x >= outer.position.x and inner.position.y >= outer.position.y,
		"a control placed inside its root stands inside it: %s in %s" % [str(inner), str(outer)])
	_free_made()


func test_something_to_read_is_not_something_to_tap() -> void:
	var root: Control = _root()
	var words := Label.new()
	words.text = "A sentence."
	_control(root, words, Vector2(10.0, 10.0), Vector2(200.0, 30.0))
	assert(HudProbeScript.tap_lines(root, "a page").is_empty(),
		"a line of words is read, not pressed")
	_free_made()


func test_a_control_that_is_not_on_the_screen_is_not_listed() -> void:
	var root: Control = _root()
	var hidden := Button.new()
	hidden.text = "Not shown"
	hidden.visible = false
	_control(root, hidden, Vector2(10.0, 10.0), Vector2(100.0, 40.0))
	assert(HudProbeScript.tap_lines(root, "a page").is_empty(),
		"a thing nobody can see is not a thing to tap")
	_free_made()


## A page answers for its own controls: the board's own list must not sweep a page up with it, or a driver
## would be told to tap a button the page may have hidden away.
func test_the_walk_round_a_page_does_not_descend_into_it() -> void:
	var root: Control = _root()
	var page := Window.new()
	page.name = "ProbePage"
	_made.append(page)
	root.add_child(page)
	var inside := Button.new()
	inside.text = "Inside the page"
	_control(page, inside, Vector2(10.0, 10.0), Vector2(150.0, 50.0))

	# Asked of the walk itself rather than of the list a finger sees, and the two are not the same door: a
	# control inside a page is taken out by the walk **pruning the subtree**, where a control that is merely
	# hidden is taken out later by the visibility test. Only the first is being held here, so the page does
	# not have to be shown - which is what a window in a headless runner must not be asked to do.
	assert(not HudProbeScript._controls_under(root).has(inside),
		"a control inside a page is not swept up with the board's own")
	assert(HudProbeScript._controls_under(root).size() == 0,
		"and nothing else was invented on the way")
	_free_made()


func test_a_page_says_what_it_is_and_where_it_stands() -> void:
	var page := Window.new()
	page.name = "ProbePage"
	page.title = "Landscaping Planner"
	page.min_size = Vector2i(300, 400)
	_made.append(page)
	add_child(page)

	var lines: PackedStringArray = HudProbeScript.page_lines(page)
	var all: String = "\n".join(lines)
	assert(not lines.is_empty(), "a page that is up has something to say")
	assert(all.contains("Landscaping Planner"), "its title is said: %s" % all)
	assert(all.contains("screen ("), "and where it stands in the pixels a screenshot is taken in: %s" % all)
	_free_made()


func test_the_device_line_carries_what_the_program_answered() -> void:
	var lines: PackedStringArray = HudProbeScript.device_lines(
		true, false, 450.0, 1.62, Vector2i(1137, 2600), Vector2i(1080, 2340), true,
		"Left-drag: move a plant     Two fingers: pan", "Line: click two ends")
	var all: String = "\n".join(lines)
	assert(all.contains("finger=true"), "the device answer is said as it was answered: %s" % all)
	assert(all.contains("dpi=450.0"), "with the density it was read from")
	assert(all.contains("Two fingers: pan"), "and the words the foot of the screen is showing")
	assert(all.contains("Line: click two ends"), "and the words the tool line is showing")
	_free_made()