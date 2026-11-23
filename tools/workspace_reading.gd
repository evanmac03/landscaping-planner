@tool
class_name WorkspaceReading
extends Node
## What any 2D workspace adds to read the scene it is standing in: the reading, the judgement, the caption on the
## glass, the report left for the other half of the comparison - and not one word about what that scene is.
##
## **Why this can be general at all.** The phone workshop's instruments were written for one scene: they knew which
## paths stood for furniture, which density a thumb's row wanted, and which two files the readings lived in. None of
## that is knowledge a *reading* has - it is knowledge a *workspace* has. Everything that was not the workspace's own
## now lives in `WorkspaceReport`, which reads any root; what is left here is the plumbing around it. **Wait for the
## scene to lay out, read the root this node is parented to, say what was found, and leave it where the other half can
## find it.** A second workspace adds this one node, states its device or states nothing and is read at this machine's
## own, and has the whole instrument - with no script of its own.
##
## **The waits are not politeness.** A control asked for its size before it has laid out answers the size it had
## before, which is how the touch dock once came out with its foot 908 px up a 900 px room and every one of its
## controls was reported off the screen. One frame is therefore the floor, whatever `wait_frames` says.
##
## **Nothing here decides anything.** The floor a control is judged against is `PhoneHud`'s - a floor belongs to a
## device and not to a scene - the arithmetic is `WorkspaceReport`'s, and the two files are named for whoever is
## reading them. A second implementation of any of the three is the defect this instrument exists to make visible.

const WorkspaceReportScript := preload("res://tools/workspace_report.gd")
const PhoneHudScript := preload("res://scripts/phone_hud.gd")
const SpacingScript := preload("res://scripts/spacing.gd")

## What this workspace is called in its two files. Empty takes the scene root's own name, so a workspace that says
## nothing still leaves files of its own rather than sharing another scene's reading.
@export var called: String = ""
## The device the scene is being read as. 0 asks this machine, which is the honest answer for a scene that is not
## claiming to be a phone - and the difference between the two is named first when two readings are compared.
@export var stated_dpi: float = 0.0
## How many physical pixels a logical one is. 0 asks the window, and a window that will not say - an editor's own
## viewport is one - is read as 1.0, because a canvas scale of nothing makes every length nothing.
@export var stated_scale: float = 0.0
## The density the scene's furniture was built at, where that is known and is not the density it is being read at. 0
## says the two are the same, which is the ordinary case for a scene that is not being stood up by hand.
@export var built_at: float = 0.0
## The paths this workspace wants read by name, besides the root itself and every control a finger could press under
## it. Empty, which is the right answer for a scene that has not decided, reads the scene's own tree and reports no
## name it never had - the report's own list is one particular HUD's nine rows and belongs to that workspace.
@export var watch: Array[String] = []
## Whether this reading is kept as the workspace's own baseline. Tick it, let the scene read once, then untick it:
## from then on every reading says how it differs from that one. Off is the ordinary state, and on is the deliberate
## act of saying "this is the shape I want" - which is why it is a tick and not a default.
@export var baseline: bool = false
## How many frames to let the scene lay out before reading it. 0 is read as one frame, never as none.
@export var wait_frames: int = 2
## Where down the room the caption is drawn, as a fraction of the room's height, so that it lands over the middle of
## the scene rather than across the scene's own title bar.
@export var caption_at: float = 0.45
## Which part of the scene to read, as a path from this node. Empty reads the whole scene this node was added to,
## which is the right answer for a workspace - and a path is the right answer for one that has grown large enough
## that a person working on a panel wants the panel measured and not the other four hundred controls with it.
@export var read_from: NodePath = NodePath()
## Whether the caption is drawn at all. Turned off, the instrument still reads, prints and leaves its report - it is
## for looking at the furniture itself with nothing over it, and the furniture is the thing being judged.
@export var show_caption: bool = true
## Whether the caption is replaced by **the whole reading**, every row of it, drawn on the glass. Off is the ordinary
## state: a judgement and its figures, over the middle of the scene. On is for laying controls out, when a person wants
## the rows themselves and would otherwise be reading a console this project's tools cannot reach - and it takes the
## caption's place as well as its words, because twenty-eight rows from the middle of a 600 px room run off the bottom.
@export var show_the_reading: bool = false
## Whether the reading follows the room being resized. On, which is what a person working in the 2D workspace does
## constantly; off, for a caller whose scene lays itself out in a way this would chase.
@export var refresh_on_resize: bool = true

var _waited: int = 0
var _said: bool = false
var _caption: Label = null
var _watching: Control = null


func _process(_delta: float) -> void:
	if _said:
		return
	_waited += 1
	if _waited < maxi(wait_frames, 1):
		return
	_said = true
	_read_and_say(true)


## The scene this node was added to, which is the thing read: a node added to a scene is added under its root.
func _the_scene() -> Node:
	return get_parent()


## What is actually read: the workspace's own stated path, or the scene this node was added to.
func _the_read() -> Node:
	if not read_from.is_empty():
		return get_node_or_null(read_from)
	return get_parent()


## The device this reading is taken as: the workspace's own statement, or this machine's.
func _the_density() -> float:
	return stated_dpi if stated_dpi > 0.0 else PhoneHudScript.dpi()


## How many physical pixels a logical one is here: the workspace's own statement, or the window's - and a window that
## will not say, or a workspace run off a tree with no window to ask, is read as 1.0. A canvas scale of nothing makes
## every length nothing, which is the fault this whole instrument was built to name.
func _the_scale() -> float:
	var one: float = stated_scale
	if one <= 0.0:
		var room: Window = get_window()
		if room != null:
			one = PhoneHudScript.canvas_scale(room)
	return one if one > 0.0 else 1.0


## Read the scene again, now, and redraw - the door a script calls after it has dressed or moved something.
##
## **A caption is a photograph of one instant, and one that never changes is worse than none**: it goes on describing
## a scene that has moved under it, in the confident words of a reading that was true once. So the instrument follows
## the scene - the room it was read in is watched for a resize, which is what changes while a person works in the 2D
## workspace, and this is public for a caller who has just changed something and knows it.
##
## It **never writes the report again.** A file written on every resize is a flood, and the report's job is to be the
## record of what was *built* for the other half to compare against - not of what was looked at last. Nor does it
## print the whole reading again: a developer sitting on a window edge would be reading a wall.
func refresh() -> void:
	if not _said:
		return
	_read_and_say(false)


## Keep the reading as this workspace's baseline, and say whether it was kept.
##
## **A baseline is a promise made once and read many times.** Comparing against the other half answers "does the 2D
## view match F6"; this answers a different question - "has my edit changed anything but what I meant" - which is the
## one a person has *while working*: between runs, with nobody to compare against but their own last good shape.
##
## It goes through the same machinery under a third name, `baseline`. A second way of writing readings would be a
## second format free to disagree with the first, and this instrument exists to make exactly that visible in other
## people's work; the file name is the only thing that differs.
func keep_the_baseline() -> bool:
	var mine: Dictionary = WorkspaceReportScript.read(_the_read(), _the_density(), _the_scale(), built_at, watch)
	var where: String = WorkspaceReportScript.a_reading_file(_the_name(), "baseline")
	var kept: bool = WorkspaceReportScript.leave(mine, where)
	print("WORKSPACE READING: %s the baseline in %s" % ["kept" if kept else "could not keep", where])
	return kept


## What this workspace is called, and therefore what its two files are called - the scene's own name unless the
## workspace states one. It goes through `to_snake_case` because it is half of a file name and not a title.
func _the_name() -> String:
	if not called.is_empty():
		return called
	var it: Node = _the_scene()
	if it == null:
		return "workspace"
	return String(it.name).to_snake_case()


## Which half of the comparison this process is. Two processes, two files: one reading compared against itself agrees
## by construction and measures nothing.
func _the_half() -> String:
	return "editor" if Engine.is_editor_hint() else "run"


## The other half, and how a person would say it.
func _the_other_half() -> String:
	return "the last run" if Engine.is_editor_hint() else "the editor's own copy"


func _read_and_say(tell_the_other_half: bool) -> void:
	var it: Node = _the_read()
	if it == null:
		return
	var density: float = _the_density()
	var built_scale: float = _the_scale()
	var mine: Dictionary = WorkspaceReportScript.read(it, density, built_scale, built_at, watch)
	var told: Array[String] = WorkspaceReportScript.looks_built_for_a_finger(mine)
	if not tell_the_other_half:
		print(
			"WORKSPACE READING: %s, read again - %d node(s), %d under a finger's floor"
			% [_the_name(), mine.size() - 1, told.size()]
		)
		_show(mine, density, built_scale)
		# The baseline comes along on a redraw, because it is the working comparison; the other half does not, because
		# a comparison against a *build* is a fact about what was made and a resize changes nothing about that.
		_compare_the_baseline(mine)
		_say_what_cannot_be_told_apart(mine)
		return
	print("WORKSPACE READING: %s, read at %.0f dpi on a canvas scale of %.3f" % [_the_name(), density, built_scale])
	for line: String in WorkspaceReportScript.lines(mine):
		print("  ", line)
	for told_one: String in told:
		print("  ! ", told_one)
	# **The judgement travels with the numbers**, so the half that cannot ask anything can still read both: a run
	# cannot ask an editor what it thinks and an editor's `print` reaches nobody, which is why the reading goes to a
	# file at all. Which file is the workspace's own name, so a second workspace cannot be measured against the first.
	var where: String = WorkspaceReportScript.a_reading_file(_the_name(), _the_half())
	if WorkspaceReportScript.leave(mine, where):
		print("WORKSPACE READING: left for %s in %s" % [_the_other_half(), where])
	else:
		print("WORKSPACE READING: the reading could not be written to ", where)
	# **And then it follows the scene.** The room's own `resized` is the one signal that means "the thing you read has
	# changed shape" without asking the whole tree every frame - and it is a `Control`'s signal, so a scene whose root
	# is not one is simply read once, which is all it can honestly promise.
	if refresh_on_resize and _watching == null:
		var stand: Control = it as Control
		if stand != null:
			_watching = stand
			if not stand.resized.is_connected(refresh):
				stand.resized.connect(refresh)
	if baseline:
		keep_the_baseline()
	_show(mine, density, built_scale)
	_compare(mine)
	_compare_the_baseline(mine)
	_say_what_cannot_be_told_apart(mine)


## Draw the caption over the scene, **where the person editing is standing**. A number that only reaches a console
## this project's tools cannot read is not a diagnosis, and the words are held in one place - `WorkspaceReport` owns
## them exactly as it owns the arithmetic, so the caption cannot come to disagree with the reading under it.
func _show(mine: Dictionary, density: float, built_scale: float) -> void:
	if not show_caption:
		if _caption != null:
			_caption.visible = false
		return
	var stand: Control = _the_read() as Control
	if stand == null:
		return
	if _caption == null:
		_caption = Label.new()
		_caption.name = "WorkspaceReading"
		_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_caption.add_theme_font_size_override("font_size", 20)
		_caption.add_theme_color_override("font_color", Color(1.0, 0.92, 0.45))
		# Added without an `owner` on purpose: Godot serialises only owned nodes, so the caption a person is reading
		# never finds its way into the scene file it is describing.
		stand.add_child(_caption)
	# **The whole reading, on the glass, when a workspace asks for it**, drawn at the top of the room because it is
	# the tall thing and the middle is where the scene is. The caption's own words are kept at the head of it - the
	# judgement is still the first thing read - and the rows follow, which is the order a person reads them in.
	var words: PackedStringArray = WorkspaceReportScript.caption_lines(mine, density, built_scale)
	_caption.add_theme_font_size_override("font_size", 12 if show_the_reading else 20)
	if show_the_reading:
		words.append_array(WorkspaceReportScript.lines(mine))
		_caption.position = Vector2(16.0, 8.0)
	else:
		_caption.position = Vector2(16.0, maxf(stand.get_rect().size.y * caption_at, 8.0))
	_caption.text = "\n".join(words)


## Say, on the glass, how this side compares with the other's - the question a person editing has, answered where the
## change is being made rather than by running the scene and reading a log.
func _compare(mine: Dictionary) -> void:
	if _caption == null:
		return
	var written: PackedStringArray = WorkspaceReportScript.lines_from(
		WorkspaceReportScript.a_reading_file(_the_name(), "run" if Engine.is_editor_hint() else "editor")
	)
	if written.is_empty():
		_caption.text += "\nnothing to compare with yet - open this scene on the other side once"
		return
	for one: String in WorkspaceReportScript.verdict_lines_of(written):
		print("WORKSPACE READING: %s says about itself: %s" % [_the_other_half(), one])
	var apart: Array[String] = WorkspaceReportScript.differences(WorkspaceReportScript.from_lines(written), mine)
	if apart.is_empty():
		_caption.text += "\nmatches %s on every node read" % _the_other_half()
		return
	_caption.text += "\n%d difference(s) from %s:" % [apart.size(), _the_other_half()]
	for one: String in apart.slice(0, 2):
		_caption.text += "\n  " + one


## Say how this reading differs from the workspace's own baseline, where one has been kept.
##
## **Silent when none has been**, and silence is the point: a caption reading "same as the baseline" before any
## baseline existed would be a comparison against nothing, which agrees with everything - the same fault the absent
## other-half file is careful not to make. One line for the healthy case and the changes by name for the other, capped
## the way the findings are, because a caption a person reads at a glance is not a report.
func _compare_the_baseline(mine: Dictionary) -> void:
	if _caption == null:
		return
	var written: PackedStringArray = WorkspaceReportScript.lines_from(
		WorkspaceReportScript.a_reading_file(_the_name(), "baseline")
	)
	if written.is_empty():
		return
	var apart: Array[String] = WorkspaceReportScript.differences(WorkspaceReportScript.from_lines(written), mine)
	if apart.is_empty():
		_caption.text += "\nsame as the baseline you kept, node for node"
		return
	_caption.text += "\n%d change(s) since the baseline:" % apart.size()
	for one: String in apart.slice(0, 2):
		_caption.text += "\n  " + one


## Say which two controls a finger could not choose between.
##
## **The question is `Spacing`'s and the answer is `Spacing`'s** - two targets closer than its own `LEAST` are one
## control to the person pressing, and a tap at the seam is the one that goes astray. It is careful about what it is
## *not*: two controls in exactly one rectangle are `Stacked`'s question, and one control inside another is a button
## in a panel, which is ordinary. What is left is the pair that merely overlaps - which is the fault this was written
## for, and the one that had to be found by counting twenty-one rectangles by hand before it existed.
##
## What the instrument adds is the reading's own rectangles, so that the question can be asked of a scene nobody has
## to walk by hand - and asked of a *saved* reading as readily as of the scene in front of a person.
func _say_what_cannot_be_told_apart(mine: Dictionary) -> void:
	if _caption == null:
		return
	var found: Array[Dictionary] = SpacingScript.faults(WorkspaceReportScript.the_things_a_finger_could_press(mine))
	if found.is_empty():
		return
	_caption.text += "\n%d pair(s) a finger could not tell apart:" % found.size()
	for one: Dictionary in found.slice(0, 2):
		_caption.text += "\n  " + SpacingScript.sentence(one)
	# Named and not counted, and capped the way the findings are: a screen with twenty of these still has to say so
	# in a caption a person reads at a glance, and the console and the reading itself carry the rest.
