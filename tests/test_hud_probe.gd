extends Node
## The probe that says what is on the screen, held to the two things a driver depends on: what it lists is
## what a finger could actually hit, and a page answers for its own controls rather than being walked into.
##
## Nothing here needs a scene: a control and a `Window` are built, put in the tree and freed in the test that
## made them. The pixels themselves are the phone's business - `Viewport.get_screen_transform()` is the
## engine's own answer, and what a screenshot's pixels really are is checked on the glass.

const HudProbeScript := preload("res://scripts/hud_probe.gd")
const WindowPostureScript := preload("res://scripts/window_posture.gd")
const InViewScript := preload("res://scripts/in_view.gd")
const TouchTargetScript := preload("res://scripts/touch_target.gd")

## Where the log half of this writes, and removes again. A probe that kept a file nobody cleans would leave
## one behind on every run of the suite.
const SCRATCH := "user://test_probe.log"

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
	# Each number says whose it is: the room belongs to the menus, the minimum to the whole row, and printed
	# as a bare `room=` and `min=` beside each other they read as one object measured against itself - which is
	# how a row wanting 1052 px was read as a bar overflowing a room of 349 on a phone, twice.
	assert(said.contains("menus_room=900"), "the room the menus were given, named as the menus'")
	assert(said.contains("row_min="), "and what the row itself asks for, named as the row's")
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
	assert(
		inner.get_center().is_equal_approx(inner.position + inner.size * 0.5),
		"the middle of a rectangle is the middle of a rectangle",
	)
	assert(
		inner.position.x >= outer.position.x and inner.position.y >= outer.position.y,
		"a control placed inside its root stands inside it: %s in %s" % [str(inner), str(outer)],
	)
	_free_made()


func test_something_to_read_is_not_something_to_tap() -> void:
	var root: Control = _root()
	var words := Label.new()
	words.text = "A sentence."
	_control(root, words, Vector2(10.0, 10.0), Vector2(200.0, 30.0))
	assert(HudProbeScript.tap_lines(root, "a page").is_empty(), "a line of words is read, not pressed")
	_free_made()


func test_a_control_that_is_not_on_the_screen_is_not_listed() -> void:
	var root: Control = _root()
	var hidden := Button.new()
	hidden.text = "Not shown"
	hidden.visible = false
	_control(root, hidden, Vector2(10.0, 10.0), Vector2(100.0, 40.0))
	assert(HudProbeScript.tap_lines(root, "a page").is_empty(), "a thing nobody can see is not a thing to tap")
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
	assert(
		not HudProbeScript._controls_under(root).has(inside),
		"a control inside a page is not swept up with the board's own",
	)
	assert(HudProbeScript._controls_under(root).size() == 0, "and nothing else was invented on the way")
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
		true,
		false,
		450.0,
		1.62,
		Vector2i(1137, 2600),
		Vector2i(1080, 2340),
		true,
		WindowPostureScript.of(Vector2i(1137, 2600)),
		"Left-drag: move a plant     Two fingers: pan",
		"Line: click two ends",
	)
	var all: String = "\n".join(lines)
	assert(all.contains("finger=true"), "the device answer is said as it was answered: %s" % all)
	assert(all.contains("dpi=450.0"), "with the density it was read from")
	assert(
		all.contains("shape=standing"),
		"and which way up its window is, worked out from the room on the line above: %s" % all,
	)
	assert(all.contains("Two fingers: pan"), "and the words the foot of the screen is showing")
	assert(all.contains("Line: click two ends"), "and the words the tool line is showing")
	_free_made()


## The whole point of the file: a session that outran the phone's log ring can still be read, so what was
## printed has to have landed here, in the same words, still one line each.
func test_every_line_kept_in_the_file_is_one_prefixed_line_so_nothing_was_wrapped() -> void:
	_clean()
	HudProbeScript.record(PackedStringArray(["--- what is on the screen ---", "device   finger=true"]), SCRATCH)
	HudProbeScript.record(PackedStringArray(["tap \"Line\nL\""]), SCRATCH)
	var text: String = _read(SCRATCH)

	assert(text.begins_with("PROBE --- what is on the screen ---"), "the block is kept: %s" % text)
	assert(text.contains("PROBE device   finger=true"), "with every line of it")
	# A caption that is two rows is flattened on the way to the file exactly as it is on the way to logcat,
	# or a person pulling the log would have to know two shapes of the same report.
	assert(text.contains("Line / L"), "and a caption's two rows arrive flattened: %s" % text)
	for line: String in text.split("\n", false):
		assert(line.begins_with("PROBE "), "every record is one prefixed line; this one is not: %s" % line)
	_clean()


## A log that grows forever is a file that fills a phone, so past its limit it gives up its oldest lines -
## and gives them up whole, because a block starting halfway through a control's rectangle is worse than no
## block at all.
func test_a_log_past_its_limit_gives_up_its_oldest_lines_whole_and_keeps_the_newest() -> void:
	_clean()
	var many := PackedStringArray()
	for index in 40:
		many.append("block %02d" % index)

	HudProbeScript.record(many, SCRATCH, 300, 150)
	var text: String = _read(SCRATCH)

	assert(text.length() <= 300, "the file is under the limit it was given: %d bytes" % text.length())
	assert(text.contains("block 39"), "the newest line is the one that had to survive: %s" % text)
	assert(not text.contains("block 00"), "and the oldest went: %s" % text)
	for line: String in text.split("\n", false):
		assert(line.begins_with("PROBE block "), "and no line was cut in half: %s" % line)
	assert(not FileAccess.file_exists(SCRATCH + HudProbeScript.TEMP_SUFFIX), "no half file is left behind")
	_clean()


## A probe able to stop the program it was measuring would be worse than no probe at all, so a log that
## cannot be written is quietly not written - and the caller is a diagnostic path nobody is waiting on.
func test_a_log_that_cannot_be_opened_is_not_a_reason_to_stop() -> void:
	var impossible := "user://no_such_folder_here/inside/probe.log"
	HudProbeScript.record(PackedStringArray(["anything"]), impossible)
	assert(not FileAccess.file_exists(impossible), "nothing was left behind where nothing could be written")


## The file as it stands after a test wrote it, and nothing at all where there is no file - a test that
## asserted against what a missing file holds would fail on the reason rather than on the rule.
func _read(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text: String = file.get_as_text()
	file.close()
	return text


## The scratch log, and anything a rewrite left half-way: the same two removals the other writers' tests
## here make, so a failed run does not decide whether the next one starts clean.
func _clean() -> void:
	if FileAccess.file_exists(SCRATCH):
		DirAccess.remove_absolute(SCRATCH)
	if FileAccess.file_exists(SCRATCH + HudProbeScript.TEMP_SUFFIX):
		DirAccess.remove_absolute(SCRATCH + HudProbeScript.TEMP_SUFFIX)


## The phone's own case, in the two halves a name is made of. The unsaved-changes question reported its screen
## rectangle as `(933, 433) .. (1405, 646)` on a **1080-wide** screen, and no `page-edge` line was printed for
## it - so either the composition puts a page somewhere other than where it stands, or the rule does not see
## one that hangs off the edge. A page cannot be *shown* in a headless runner, which is the one thing
## `page_edge_lines` insists on, so what is held here is the composition and the comparison underneath it.
func test_a_page_whose_own_rectangle_is_composed_off_the_screen_is_named() -> void:
	var page := Window.new()
	page.name = "ProbeAdrift"
	_made.append(page)
	add_child(page)
	page.position = Vector2i(1500, 100)
	page.size = Vector2i(300, 200)

	var room: Vector2i = HudProbeScript.screen_room(self)
	assert(room.x > 0 and room.y > 0, "the runner has a room to be measured against: %s" % str(room))
	var composed: Rect2 = HudProbeScript.window_rect(page)
	assert(
		composed.end.x > float(room.x),
		"a page standing at x 1500..1800 is composed past the right edge of a %d px room: %s" % [room.x, str(composed)],
	)
	var faults: Array[Dictionary] = InViewScript.faults(
		[{ "name": "the page (ProbeAdrift)", "rect": Rect2i(composed), "room": room }]
	)
	assert(faults.size() == 1, "and the rule names it: %s" % str(faults))
	assert(InViewScript.sentence(faults[0]).contains("ProbeAdrift"), InViewScript.sentence(faults[0]))
	_free_made()


## A caption is judged against the room it was given in its own pixels, and a control that puts its words on
## another line has cut nothing - which is the difference between a box short of room and a caption that has
## lost a word. The phone's own foot line showed "Pinch: zoo".
func test_words_a_caption_cannot_show_are_named_and_wrapping_ones_are_left_alone() -> void:
	var root: Control = _root()
	var cut := Label.new()
	cut.text = "Left-drag: move a plant     Two fingers: pan     Pinch: zoom"
	cut.clip_text = true
	_control(root, cut, Vector2(10.0, 10.0), Vector2(120.0, 30.0))
	var wrapping := Label.new()
	wrapping.text = "The same words, on as many lines as they need."
	wrapping.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_control(root, wrapping, Vector2(10.0, 60.0), Vector2(120.0, 60.0))

	var lines: PackedStringArray = HudProbeScript.clipped_lines(root, "a page")
	assert(lines.size() == 1, "one caption has lost words and one has not: %s" % str(lines))
	assert(lines[0].begins_with("clipped "), "and it is a line about words: %s" % lines[0])
	assert("Pinch: zoom" in lines[0], "quoting what it was told to say: %s" % lines[0])
	assert(not "\n" in lines[0], "and arriving as one line, which is what the file and logcat can carry")
	_free_made()


## The floor a target is judged against is the caller's, because it is a fact about the device rather than
## about this project: the desk's own 44 px is right for a mouse, and a phone at 450 dpi wants a 5.5 mm row,
## which is about 107 px. Two things are held here - the desk's half, which a runner can be asked about, and
## the arithmetic the phone's half rests on, which is `TouchTarget`'s own and needs no screen.
##
## **An absolute floor is not asked of a screen that is not there.** Measured: a headless run's dummy display
## reports a 64 x 64 window with the canvas drawn at 0.04, so a 109 x 50 button measures 4 x 2 px on the
## "screen" and every control in the program would be named for a fault nobody could have. The probe refuses
## the question instead, which is why the desk's half reads the same with a display and without one.
func test_the_floor_is_the_callers_and_is_never_asked_of_a_screen_that_is_not_there() -> void:
	var root: Control = _root()
	var button := Button.new()
	button.text = "Discard"
	_control(root, button, Vector2(20.0, 20.0), Vector2(109.0, 50.0))

	assert(
		HudProbeScript.small_lines(root, "a page", 44).is_empty(),
		"a 109 x 50 button clears the desk's own floor, and no floor is judged where there is no screen",
	)
	# The device's own floor, on the rectangle the rule reads - the same button, half the size the program
	# itself asks for on a phone at 450 dpi.
	var phone: Array[Dictionary] = TouchTargetScript.faults(
		[{ "name": "the question's own button", "rect": Rect2i(20, 20, 109, 50) }],
		107,
	)
	assert(phone.size() == 1, "and it is 57 px short of what the device asks for: %s" % str(phone))
	assert(phone[0]["short"] == 57, "57 px short of 107: %d" % phone[0]["short"])
	_free_made()


## **A floor and a rectangle have to be in one space**, which is a rule this project has now paid for four times,
## and the smallest form of it is pure arithmetic: a row the layout states, the room the layout was given, and the
## screen the probe measures in.
##
## The numbers are the A16W's, measured: held upright it states a 107 px row in a 1185 px room on a 1080 px screen.
## The `Fit` button came back **97 px** wide once `PhoneHud` gave it the row - so a floor of 107 called it ten
## pixels short of a row it meets exactly, which is what it did, for every button on the screen, in the very build
## that fixed its width. Nothing here needs a phone: it is the arithmetic the phone's reading rests on.
func test_a_floor_stated_in_the_layouts_pixels_is_brought_into_the_screens() -> void:
	var row: float = 107.0
	var room := Vector2i(1080, 2340)
	var laid := Vector2(1185.0, 2567.0)
	assert(
		HudProbeScript.floor_in_screen_px(row, room, laid) == 97,
		"107 px of a 1185 px room is 97 px of a 1080 px screen: %d" % HudProbeScript.floor_in_screen_px(row, room, laid),
	)
	# A floor is a "no less than", so it is truncated and never rounded up: a 5 px row drawn at half size is
	# 2.5 px, and calling that 3 would report a target that meets the row as a pixel short of it.
	assert(
		HudProbeScript.floor_in_screen_px(5.0, Vector2i(1, 1), Vector2(2.0, 2.0)) == 2,
		"a floor rounds down: %d" % HudProbeScript.floor_in_screen_px(5.0, Vector2i(1, 1), Vector2(2.0, 2.0)),
	)
	# A screen the size of the layout leaves the floor alone, which is the desk's own case.
	assert(
		HudProbeScript.floor_in_screen_px(row, Vector2i(1185, 2567), laid) == 107,
		"a screen as wide as the layout changes nothing",
	)
	# Anything unknown is no floor at all, rather than a zero-pixel one that nothing could fail.
	assert(HudProbeScript.floor_in_screen_px(0.0, room, laid) == 0, "a row of no size is no floor")
	assert(HudProbeScript.floor_in_screen_px(row, Vector2i.ZERO, laid) == 0, "a room of no size is no floor")
	assert(HudProbeScript.floor_in_screen_px(row, room, Vector2.ZERO) == 0, "a layout of no size is no floor")
	# And the device's own door is shut on a desk: a runner that is not being served a finger is answered with
	# nothing rather than with the phone's floor, whatever screen it happens to be on.
	assert(HudProbeScript.finger_floor(_root()) == 0, "a desk's own runner is not handed the device's floor")
	_free_made()


## **A centre is only where a finger should land in the room it was measured in**, and the device turns under the
## program. A tap aimed from a portrait block at a landscape screen reaches nothing at all - measured, a centre at
## y 1654 on a 1080-tall screen - and the run that sent it had to be wondered about, because nothing said so.
##
## The room is read back out of the block's own line, in the one place that also writes it. The two spellings are
## both held here, because the same block arrives as the probe wrote it and behind the `PROBE ` a log line carries.
func test_the_room_a_block_was_taken_in_is_read_back_off_its_own_line() -> void:
	var as_written: String = "device   finger=true dpi=450.0 scale=1.62 shape=lying\nroom     viewport=(1444, 666) native=(2340, 1080)"
	assert(
		HudProbeScript.read_room_line(as_written) == Vector2i(1444, 666),
		"the room the block was taken in: %s" % str(HudProbeScript.read_room_line(as_written)),
	)
	# The same line as it reaches a reader out of `probe.log`, behind the `PROBE ` every line there carries, and
	# with the newest block's own line to be picked over an older one's.
	var two_blocks: String = (
		"PROBE room     viewport=(1080, 2340) native=(1080, 2340)\n"
		+ "PROBE room     viewport=(1444, 666) native=(2340, 1080)\n"
	)
	assert(
		HudProbeScript.read_room_line(two_blocks) == Vector2i(1080, 2340),
		"the first room in the text handed over is the one read",
	)
	# Nothing said is no room at all, rather than a room of no size with a point outside it by definition.
	assert(HudProbeScript.read_room_line("") == Vector2i.ZERO, "no block, no room")
	assert(
		HudProbeScript.read_room_line("room     viewport=(1444 native=()") == Vector2i.ZERO,
		"a line with no pair in it is not a room",
	)


## Both band questions read the platform, so a desk - and a headless runner, which has no display at all -
## answers nothing rather than answering about a monitor nobody is standing at.
func test_a_room_that_is_not_a_phones_names_nothing_in_a_kept_band() -> void:
	var root: Control = _root()
	var button := Button.new()
	button.text = "Fit"
	_control(root, button, Vector2(0.0, 0.0), Vector2(60.0, 100.0))
	assert(HudProbeScript.unsafe_lines(root, "a page").is_empty(), "no promise, no band to stand in")
	assert(HudProbeScript.middle_lines(root, "a page").is_empty(), "and nothing to be aimed into")
	_free_made()


## A box that clips shows the part of its child standing inside it and draws nothing else, so a control below
## its foot is **not on the glass at all** - it is reached by scrolling. Measured on the desk, the palette's own
## column is 924 px tall inside a 768 px box, and `Place`, `Stop` and the plant list's caption `130 species.`
## stand below its foot. They were reported as sharing rows with the foot line, which is a fault nobody could
## see, and the tap list a driver follows offered them as targets. Every shape here is compared with another
## shape in the same space, so a headless runner's 64 x 64 dummy display does not matter.
func test_a_control_a_box_above_it_cuts_off_is_not_drawn_at_all() -> void:
	var root: Control = _root()
	var box := Control.new()
	box.clip_contents = true
	_control(root, box, Vector2(0.0, 0.0), Vector2(200.0, 200.0))
	var below := Button.new()
	below.text = "Place"
	_control(box, below, Vector2(20.0, 260.0), Vector2(120.0, 40.0))

	assert(not HudProbeScript.drawn(below), "a control entirely below the box is drawn nowhere")
	assert(
		HudProbeScript.drawn_rect(below).size == Vector2.ZERO,
		"and the part of it that shows is nothing at all: %s" % str(HudProbeScript.drawn_rect(below)),
	)
	_free_made()


func test_a_control_half_out_of_the_box_is_drawn_as_the_half_that_shows() -> void:
	var root: Control = _root()
	var box := Control.new()
	box.clip_contents = true
	_control(root, box, Vector2(0.0, 0.0), Vector2(200.0, 200.0))
	# Two thirds of it is below the box's foot, so what is drawn is its top twenty rows.
	var half := Button.new()
	half.text = "Stop"
	_control(box, half, Vector2(20.0, 180.0), Vector2(120.0, 40.0))

	var shown: Rect2 = HudProbeScript.drawn_rect(half)
	assert(HudProbeScript.drawn(half), "part of it is on the screen, so it is drawn")
	# Compared with the same two rectangles in the same space rather than with a pair of subtracted numbers:
	# a headless runner's display scales every rectangle, and a subtraction of two scaled numbers is not the
	# same question as a shape against a shape.
	assert(
		shown == HudProbeScript.screen_rect(half).intersection(HudProbeScript.screen_rect(box)),
		"and what shows is the part of it standing inside the box: %s" % str(shown),
	)
	_free_made()


func test_a_control_standing_inside_its_box_is_drawn_as_the_whole_of_itself() -> void:
	var root: Control = _root()
	var box := Control.new()
	box.clip_contents = true
	_control(root, box, Vector2(0.0, 0.0), Vector2(200.0, 200.0))
	var inside := Button.new()
	inside.text = "Undo"
	_control(box, inside, Vector2(20.0, 40.0), Vector2(120.0, 40.0))

	assert(
		HudProbeScript.drawn_rect(inside) == HudProbeScript.screen_rect(inside),
		"a control nothing cuts is handed back exactly as it stands",
	)
	_free_made()


## The engine's own parts are not controls of their own. Measured on the desk: `16.0` and `16.0  h` were
## reported as two things sharing one cell, two targets a thumb cannot tell apart, and one control's size
## counted twice - a `SpinBox` and the field it composes its number into, which is one control named twice.
func test_a_spinboxs_own_field_is_the_engines_part_rather_than_a_second_control() -> void:
	var box := SpinBox.new()
	var field: LineEdit = box.get_line_edit()
	assert(field != null, "a SpinBox has a field at all")
	assert(HudProbeScript._the_engines_own(field), "and the field's name is the engine's own: %s" % field.name)
	assert(not HudProbeScript._the_engines_own(box), "while the SpinBox itself is the program's: %s" % box.name)
	box.free()


## **Why this is a reading and not a walk.** `get_children(true)` reads internal children on purpose - a
## `ScrollContainer`'s bars are internal and a driver needs their rectangles - so a rule applied to the walk
## would take a control the *program* built with it, because a control *added* with no name of its own is named
## `@Button@1` by the engine as well. Measured: putting the rule in the walk failed two tests in this very file.
func test_a_control_the_suite_builds_carries_an_engine_name_and_is_still_the_programs() -> void:
	var root: Control = _root()
	var built := Button.new()
	built.text = "Fit"
	_control(root, built, Vector2(0.0, 0.0), Vector2(60.0, 40.0))
	assert(
		HudProbeScript._the_engines_own(built),
		"a control added with no name of its own is engine-named: %s" % built.name,
	)
	built.name = "FitButton"
	assert(not HudProbeScript._the_engines_own(built), "and one the program named is not: %s" % built.name)
	_free_made()
