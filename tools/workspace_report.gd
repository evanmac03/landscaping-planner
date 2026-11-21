class_name WorkspaceReport
extends RefCounted
## The phone's furniture read as numbers in one fixed shape, so that a 2D workspace in the editor and the same
## scene run with F6 can be **compared** rather than squinted at.
##
## **Why this is a module and not two screenshots.** The two are *different processes*: the editor's copy of the
## scene is not the game's, and no running program can see both. What can be shared is a *reading* - the same
## nodes, the same facts, the same words - so each side prints the same block and `differences` says what does not
## match between two of them. That is the whole instrument, and it exists because of one measured fault: **an
## editor states no device, so it builds a phone's furniture at a desk's size** (31 px against 97), and the two
## have to be *named* apart rather than guessed at.
##
## **Three facts per node, and the third is why the first two are not enough.** `visible` says whether anything
## was shown at all, `size` whether it was laid out for the screen it stands on, and `children` whether it was
## *built* - a view can easily do one and not the others, which is exactly what this cost to find. Nothing here
## measures a colour or a pixel: that is `screenshot_reader.gd`'s question, and it wants a picture.
##
## **A reading is flat, and it holds the *buttons* and not only the rows.** Each named node is read, and so is
## every control a finger could press underneath it, at its own full path - because the floor a thumb needs is a
## question about **targets**, and a row is not one. This file first judged the *named* nodes only, and judged
## them by whether they held children: it flagged the hint line (a caption, which nothing presses) and the tool
## strip (a container), while the six buttons *inside* the strip - the only things on it a thumb can hit - were
## never read at all. **Holding children is what makes a container, and pressing is what makes a target**; a rule
## that cannot tell those apart names the wrong half of the screen. So the walk goes *down* as well as across, and
## `looks_built_for_a_finger` judges the buttons it finds.

## What a person comparing the two sides would look at, in the order they meet it on the screen: the bar's own
## words, the four the furniture draws beside them, the dock, the tabs, the strip, the sheet, and the two aids the
## overlay draws. **The paths are the scene's own**, so both sides can be read by them; the furniture's own list of
## what it is *given* is `touch_hud_workspace.gd`'s `NODES`, which is a different question - what is handed in
## against what a person looks at - and this file keeps no copy of it.
##
## Each of these is read *and* searched underneath for buttons, so the strip's own entry brings the six tools with
## it and the dock brings its tabs. Rows with nothing pressable under them read as one line and report nothing.
##
## **The row is named as well as the furniture inside it, and that was the second fault this file had.** The bar's
## own `3D view`, `Fit` and `Ground view` are *siblings* of `TouchRow` rather than children of it, so naming only
## `TouchRow` read four of the seven controls a thumb meets in the bar and called the bar clean. Measured on the
## A16W's own specs the three it missed are `228x31`, `28x31` and `190x31` - a desk's row, in the bar of a phone. **A
## walk that starts at the wrong control is a clean reading of the wrong screen.**
const NODES: Array[String] = [
	"Hud/Root/TopBar/Row/TouchRow",
	"Hud/Root/TopBar/Row",
	"Hud/Root/TopBar/Row/AppLabel",
	"Hud/Root/TouchDock",
	"Hud/Root/TouchDock/Column/Tabs",
	"Hud/Root/TouchDock/Column/ToolStrip/StripScroll/Strip",
	"Hud/Root/TouchSheet",
	"Hud/Root/Overlay",
	"Hud/Root/Hints",
]

## The field separator, and it is a mistake to read it as decoration: a reading is written to a file and read
## back, so the one format has to be one this file both writes and parses.
const FIELD := " | "

## **The device a reading was taken from, carried in the reading itself.** A floor is a *length* only once a
## density turns it into pixels: this file first asked `HELD_DPI` - the density `TouchInput` uses to *decide*
## whether a hand is a thumb - and got 43 px for a question whose real answers are 97 px on the A16W and 31 px
## on this desk. A threshold reused as a screen is a second place stating a floor, free to disagree with the
## first. So the reading says what it came from, and `looks_built_for_a_finger` **refuses to judge a reading that
## does not say** - because a verdict from a floor nobody stated is the fault wearing an answer's clothes.
const DEVICE := "#device"

## What a row of a finger's furniture should measure on the device this program is aimed at - the floor
## `TouchInput` states and `PhoneHud` turns into pixels, asked of both rather than written down here. It is
## `TouchInput` that owns the millimetre figure: a desk's answer and a phone's are the same *question* asked of
## two devices, and the answer already lives with the question.
const PhoneHudScript := preload("res://scripts/phone_hud.gd")
const TouchInputScript := preload("res://scripts/touch_input.gd")


## Read the named nodes out of whatever tree is handed in, and every control a finger could press underneath
## each one: whether it is shown, what it was laid out at, and how many children it has.
##
## A path that does not resolve is recorded as `missing` rather than left out, because **a node that is not there
## is the most important difference there is** - an absent strip and an empty one look the same in a count and
## nothing alike to a person.
##
## **The walk goes down as well as across**, which is the fix for the fault this file was born with: the buttons
## are what a thumb meets, and they are never the named rows. A named path that is itself a button is read once
## rather than twice, because the same control under two keys would let a comparison agree with itself.
static func read(root: Node, density: float) -> Dictionary:
	var found: Dictionary = { }
	# The density is *handed in* rather than read here, and that is the point: by the time this runs, a view that
	# stated a phone has handed the machine's own density back, so `PhoneHud.dpi()` would answer 144 beside
	# furniture that was built at 450. The caller knows which device it photographed; this only records it.
	found[DEVICE] = { "dpi": density }
	for path: String in NODES:
		var node: Node = root.get_node_or_null(NodePath(path))
		if node == null:
			found[path] = { "missing": true }
			continue
		found[path] = _facts(node)
		for button: Node in _buttons_under(node):
			found[String(root.get_path_to(button))] = _facts(button)
	return found


## Whether a control is one a finger presses, which is the only kind of thing the thumb floor is about. A
## `BaseButton` is the whole vocabulary here - a label, a panel and a scroll container all take no press - and a
## control switched off is read but is not counted as a target by `looks_built_for_a_finger`.
static func is_a_target(node: Node) -> bool:
	var button: BaseButton = node as BaseButton
	if button == null:
		return false
	return not button.disabled


## One reading as lines, which is both what a person reads and what `from_lines` parses back.
##
## The size is written as whole pixels, because a comparison between two machines that disagree by a fraction of
## one is not a difference a person could act on.
static func lines(reading: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	# First, because it is what every floor below is measured against.
	out.append("%s%sdpi=%.1f" % [DEVICE, FIELD, float(reading.get(DEVICE, { "dpi": 0.0 })["dpi"])])
	for path: String in _every_path(reading):
		var facts: Dictionary = reading[path]
		if bool(facts.get("missing", false)):
			out.append("%s%smissing" % [path, FIELD])
			continue
		var size: Vector2i = facts["size"]
		out.append(
			(
				"%s%svisible=%s%ssize=%dx%d%schildren=%d%starget=%s"
				% [
					path,
					FIELD,
					str(facts["visible"]),
					FIELD,
					size.x,
					size.y,
					FIELD,
					int(facts["children"]),
					FIELD,
					str(facts.get("target", false)),
				]
			)
		)
	return out


## A reading read back from the lines `lines` wrote, so a run can be compared with an editor that printed its
## own. A line this file cannot read is recorded as missing rather than dropped: a comparison that quietly lost a
## row would report a match it never measured.
static func from_lines(written: PackedStringArray) -> Dictionary:
	var found: Dictionary = { }
	for line: String in written:
		var parts: PackedStringArray = line.split(FIELD)
		if parts.size() < 2:
			continue
		var path: String = parts[0]
		if path == DEVICE:
			found[DEVICE] = { "dpi": String(parts[1]).trim_prefix("dpi=").to_float() }
			continue
		if parts[1] == "missing":
			found[path] = { "missing": true }
			continue
		found[path] = {
			"visible": parts[1].trim_prefix("visible=").to_lower() == "true",
			"size": _a_size(String(parts[2]).trim_prefix("size=")),
			"children": String(parts[3]).trim_prefix("children=").to_int(),
			# **Carried, and defaulted rather than dropped.** Whether a thing can be pressed decides whether it is
			# judged at all, so a reading that lost the fact would report a clean bill of health for a screen full of
			# 31 px buttons. A line written before this fact existed reads as "not a target" - honest, and not a
			# clam that was never measured.
			"target": parts.size() > 4 and String(parts[4]).trim_prefix("target=").to_lower() == "true",
		}
	return found


## One sentence per difference between two readings, each naming the node and both figures.
##
## **Named, not counted**, for the reason every instrument here names rather than counts: "six differences" tells a
## person nothing about which pane to look at, and the paths do. A node in one reading and not the other is
## reported as well, because a side that could not read a node at all has not agreed with anything.
##
## **Every path either side holds is compared**, and not the named rows alone - the buttons are where the two
## sides disagree most and where a person can act on it, and comparing only the rows would report "the strip
## matches" while its six tools were a third of the size they should be.
static func differences(one: Dictionary, other: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var seen: Dictionary = { }
	for path: String in _every_path(one) + _every_path(other):
		if seen.has(path):
			continue
		seen[path] = true
		out.append_array(_differences_for(path, one, other))
	return out


## The differences for one node, which `differences` lifts into the names a person reads.
static func _differences_for(path: String, one: Dictionary, other: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var here: Dictionary = one.get(path, { "missing": true })
	var there: Dictionary = other.get(path, { "missing": true })
	if bool(here.get("missing", false)) or bool(there.get("missing", false)):
		if bool(here.get("missing", false)) != bool(there.get("missing", false)):
			out.append("%s: there in one and not the other" % path)
		return out
	if bool(here["visible"]) != bool(there["visible"]):
		out.append("%s: shown %s against %s" % [path, str(here["visible"]), str(there["visible"])])
	var here_size: Vector2i = here["size"]
	var there_size: Vector2i = there["size"]
	if here_size != there_size:
		out.append("%s: %dx%d against %dx%d" % [path, here_size.x, here_size.y, there_size.x, there_size.y])
	if int(here["children"]) != int(there["children"]):
		out.append("%s: %d child(ren) against %d" % [path, int(here["children"]), int(there["children"])])
	return out


## What a row of a finger's furniture should measure on the device this program is aimed at - the floor
## `PhoneHud` states, asked of it rather than written down here.
static func expected_row_height(density: float) -> float:
	return PhoneHudScript.row_height(1.0, density)


## A reading's own verdict on whether it was built for a finger: **every button the reading holds should measure
## at least a row a thumb meets.** Nothing else is judged, and that is the point - a hint line, a panel and a
## scroll container are not pressed, and naming them faults is how this file first wasted a person's time.
##
## A target a person cannot see is passed over rather than reported: furniture that is put away is not built
## wrongly, and every reading here is taken with some of it away. A size of nothing *is* reported, because a
## control that has not been laid out has not been measured, and saying it is fine would be the lie this file
## exists to prevent.
static func looks_built_for_a_finger(reading: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var device: Dictionary = reading.get(DEVICE, { })
	var density: float = float(device.get("dpi", 0.0))
	if density <= 0.0:
		out.append("this reading does not say which device it came from, so no floor can be measured against it")
		return out
	# **Rounded to whole pixels, because a reading is whole pixels.** A control the furniture built to exactly the
	# device's floor measures 97.44 and reads back as 97, so a float comparison named all three of the bar's own
	# controls as faults while they sat precisely on the floor - the instrument crying wolf at the one size that is
	# right. A reading that cannot see a fraction must not judge by one.
	var least: float = roundf(expected_row_height(density))
	for path: String in _every_path(reading):
		var facts: Dictionary = reading[path]
		if bool(facts.get("missing", false)) or not bool(facts.get("visible", false)):
			continue
		if not bool(facts.get("target", false)):
			continue
		var size: Vector2i = facts["size"]
		if size.y <= 0:
			out.append("%s: standing with no height at all - it has not been laid out" % path)
			continue
		if float(size.y) < least:
			out.append("%s: %d px tall, under the %.0f px a thumb needs" % [path, size.y, least])
	return out


## Every path a reading holds, in the order `NODES` names them first so a person reads the rows before the buttons
## under them. A path in only one of two readings is still in the set, because that is the difference worth saying.
static func _every_path(reading: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for path: String in NODES:
		if reading.has(path):
			out.append(path)
	for path: String in reading:
		if path != DEVICE and not out.has(path):
			out.append(path)
	return out


## The three facts, taken from the node rather than made up: shown, laid out, and how many children it holds -
## plus whether a finger could press it, which is what `looks_built_for_a_finger` judges.
static func _facts(node: Node) -> Dictionary:
	var control: Control = node as Control
	return {
		"visible": node.is_visible_in_tree(),
		"size": Vector2i.ZERO if control == null else Vector2i(control.size),
		"children": node.get_child_count(),
		"target": is_a_target(node),
	}


## Every control a finger could press under this node, the node itself excluded because `read` takes it already.
static func _buttons_under(node: Node) -> Array[Node]:
	var out: Array[Node] = []
	for child: Node in node.get_children():
		if is_a_target(child):
			out.append(child)
		out.append_array(_buttons_under(child))
	return out


## "221x31" as a `Vector2i`.
static func _a_size(written: String) -> Vector2i:
	var halves: PackedStringArray = written.split("x")
	if halves.size() != 2:
		return Vector2i.ZERO
	return Vector2i(halves[0].to_int(), halves[1].to_int())
