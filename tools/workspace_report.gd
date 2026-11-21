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
## **Four facts per node, and the fourth is why the first three are not enough.** `visible` says whether anything
## was shown at all, `size` whether it was laid out for the screen it stands on, `children` whether it was
## *built*, and `font` what size its words are drawn at - a view can easily do one and not the others, which is
## exactly what this cost to find. The last of them arrived late and for a reason worth keeping: every fault this
## file was written for was found, and then a fifth was found by eye while the reading called the same strip clean.
## Nothing here measures a colour or a pixel: that is `screenshot_reader.gd`'s question, and it wants a picture.
##
## **A reading is flat, and it holds the *buttons* and not only the rows.** Each named node is read, and so is
## every control a finger could press underneath it, at its own full path - because the floor a thumb needs is a
## question about **targets**, and a row is not one. This file first judged the *named* nodes only, and judged
## them by whether they held children: it flagged the hint line (a caption, which nothing presses) and the tool
## strip (a container), while the six buttons *inside* the strip - the only things on it a thumb can hit - were
## never read at all. **Holding children is what makes a container, and pressing is what makes a target**; a rule
## that cannot tell those apart names the wrong half of the screen. So the walk goes *down* as well as across, and
## `looks_built_for_a_finger` judges the buttons it finds.
##
## **A name nobody chose is not an identity, and the first comparison this file printed was half noise for want of
## saying so.** Godot gives every node it makes a placeholder name - `@Button@<n>` - where `<n>` counts every node
## that *process* has ever made. The same button is `@Button@6` in a run fresh off the ground and `@Button@21445` in
## an editor that has been up all day, so thirty-four differences arrived of which **eighteen were nine buttons
## called absent on both sides at once** - the reading had no way to say that the third thing in the row was the
## third thing in the row. A deliberate name is kept and a placeholder is stood in for by where it stands:
## `a_name_that_travels` is that rule, and `_a_path_to` is the walk that applies it to every ancestor.

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
##
## **The key is built from names that travel**, because two *instances* of one scene are the only things this file
## is ever asked to compare - that is the whole instrument. A key taken from `get_path_to` is the scene's own
## placeholder names written down, and a placeholder is a receipt for a node, not a name for it.
static func read(root: Node, density: float, scale: float = 0.0, built_at: float = 0.0) -> Dictionary:
	var found: Dictionary = { }
	# The density is *handed in* rather than read here, and that is the point: by the time this runs, a view that
	# stated a phone has handed the machine's own density back, so `PhoneHud.dpi()` would answer 144 beside
	# furniture that was built at 450. The caller knows which device it photographed; this only records it.
	found[DEVICE] = { "dpi": density, "scale": scale, "built_at": built_at }
	for path: String in NODES:
		var node: Node = root.get_node_or_null(NodePath(path))
		if node == null:
			found[path] = { "missing": true }
			continue
		found[path] = _facts(node)
		for button: Node in _buttons_under(node):
			found[_a_path_to(root, button)] = _facts(button)
	return found


## What to call a node so that the same node under two instances of one scene is called the same thing.
##
## **A deliberate name is kept; a name Godot invented is replaced by where the node stands.** The test for the second
## is the `@` Godot puts in front of its own placeholders - and a person cannot set such a name, because the engine
## strips `@` out of any name handed to it - so a name without one was chosen by somebody and means something.
##
## A placeholder becomes `#<index>`, its place among its siblings, and the word it shows when it is a button reads
## beside it - `#2 "View"`, the third control in the row, which is how a person counting along the bar would name it.
## **The index has to be there**: the word alone would collide the moment two buttons said the same thing, and a flat
## reading would then let one silently overwrite the other. The word is there because a person reading a difference
## is owed *which* control and not merely *the third one*.
static func a_name_that_travels(node: Node) -> String:
	var chosen: String = String(node.name)
	if not chosen.begins_with("@"):
		return chosen
	var stand_in: String = "#%d" % node.get_index()
	var words: Variant = node.get("text")
	if words != null and String(words) != "":
		stand_in += " \"%s\"" % String(words)
	return stand_in


## The path to a node, with every name along it passed through `a_name_that_travels` - so it is an identity two
## instances can be held against, rather than the scene's own serial numbers.
##
## The walk stops *at* the root rather than including it, which is what lets the paths begin `Hud/Root/...` and meet
## the literal ones in `NODES`: a root is a node somebody asked to be read, not one of the things read.
static func _a_path_to(root: Node, node: Node) -> String:
	# An `Array` rather than a `PackedStringArray`, because the walk meets the names from the bottom up and only a
	# plain `Array` can be pushed onto at the front. The join packs it once at the end.
	var parts: Array[String] = []
	var walking: Node = node
	while walking != null and walking != root:
		parts.push_front(a_name_that_travels(walking))
		walking = walking.get_parent()
	return "/".join(PackedStringArray(parts))


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
	# First, because it is what every floor below is measured against - and it carries **the scale and the density
	# the furniture was actually built with**, not only the density a floor is judged against. Those two numbers are
	# the whole of a row's height (`5.5mm / 25.4 * dpi / scale`), so two readings that disagree about them disagree
	# about every size below and there is no point reading further until they match. It is also the one line that can
	# be read off a *file* - which matters because an editor cannot be asked anything, and this is how its own numbers
	# get out where a run can compare with them.
	var device: Dictionary = reading.get(DEVICE, { })
	out.append(
		(
			"%s%sdpi=%.1f%sscale=%.3f%sbuilt_at=%.1f"
			% [
				DEVICE,
				FIELD,
				float(device.get("dpi", 0.0)),
				FIELD,
				float(device.get("scale", 0.0)),
				FIELD,
				float(device.get("built_at", 0.0)),
			]
		)
	)
	for path: String in _every_path(reading):
		var facts: Dictionary = reading[path]
		if bool(facts.get("missing", false)):
			out.append("%s%smissing" % [path, FIELD])
			continue
		var size: Vector2i = facts["size"]
		out.append(
			(
				"%s%svisible=%s%ssize=%dx%d%schildren=%d%starget=%s%sfont=%d"
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
					FIELD,
					int(facts.get("font", 0)),
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
			var device: Dictionary = { "dpi": String(parts[1]).trim_prefix("dpi=").to_float() }
			# A line written before the scale and the built density were recorded reads 0 for both, and that is
			# honest rather than a claim: a reading that never said which screen it was built for cannot be counted
			# as built for one. `device_difference` therefore names nothing on a pair of old readings - it does not
			# invent a device, which is the fault this file exists to avoid wearing an answer's clothes.
			if parts.size() > 2:
				device["scale"] = String(parts[2]).trim_prefix("scale=").to_float()
			if parts.size() > 3:
				device["built_at"] = String(parts[3]).trim_prefix("built_at=").to_float()
			found[DEVICE] = device
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
			# **The type travels too, and a line written before it existed reads 0.** 0 is not judged rather than
			# treated as "no type", for the reason above: a reading taken by an older build says nothing about the
			# size of any words, and inventing a fault from a fact that was never written is the fault this file
			# exists to avoid.
			"font": 0 if parts.size() <= 5 else String(parts[5]).trim_prefix("font=").to_int(),
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
## **The device the two were built with, in its own line, and said first.** When the two sides were built for
## different screens, *every* size below them differs, and a list of fifty rows buries the one fact that explains all
## of them. This is the line that answers "why is the 2D workspace a different size from F6" - measured, the editor's
## furniture had been built with a density of 144 and a canvas scale of 0 against the run's 450 and 1, and every
## button in it carried a zero minimum in consequence. **Nothing is named when neither reading states a device**,
## because inventing one from an absence is the fault this file exists to avoid wearing an answer's clothes.
static func device_difference(one: Dictionary, other: Dictionary) -> String:
	var here: Dictionary = one.get(DEVICE, { })
	var there: Dictionary = other.get(DEVICE, { })
	var here_dpi: float = float(here.get("dpi", 0.0))
	var there_dpi: float = float(there.get("dpi", 0.0))
	var here_scale: float = float(here.get("scale", 0.0))
	var there_scale: float = float(there.get("scale", 0.0))
	if is_equal_approx(here_dpi, there_dpi) and is_equal_approx(here_scale, there_scale):
		return ""
	return (
		"%s: built for %.0f dpi at a canvas scale of %.3f against %.0f dpi at %.3f"
		% [DEVICE, here_dpi, here_scale, there_dpi, there_scale]
	)


static func differences(one: Dictionary, other: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var device: String = device_difference(one, other)
	if device != "":
		out.append(device)
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
	if int(here.get("font", 0)) != int(there.get("font", 0)):
		out.append("%s: %d px of type against %d" % [path, int(here.get("font", 0)), int(there.get("font", 0))])
	return out


## What a row of a finger's furniture should measure on the device this program is aimed at - the floor
## `PhoneHud` states, asked of it rather than written down here.
static func expected_row_height(density: float) -> float:
	return PhoneHudScript.row_height(1.0, density)


## And what size its words should be drawn at - the same owner asked the same way, because a target is *read* as
## well as pressed, and the two floors live together in `PhoneHud` for that reason.
static func expected_type_size(density: float) -> int:
	return PhoneHudScript.font_size(1.0, density)


## A reading's own verdict on whether it was built for a finger: **every button the reading holds should measure at
## least a row a thumb meets, and be drawn in type an eye meets.** Nothing else is judged, and that is the point - a
## hint line, a panel and a scroll container are not pressed, and naming them faults is how this file first wasted a
## person's time.
##
## **Two questions, and the second was added only after a fault got past the first.** A target's height and the size
## of the words in it are separate: measured, the strip's six stand-ins were 98 px in a 98 px row with their type at
## the desk's 13, and a verdict that judged height alone called them clean. **A floor is asked of its owner and never
## stated here**, for both - `PhoneHud` says how tall a row is and how many pixels draw a letter, and what the two
## are measured against is its own answer rather than a copy.
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
	var least_type: int = expected_type_size(density)
	# **A floor that could not be worked out refuses the question, and never passes it.** Measured: an editor whose
	# millimetre arithmetic came back zero asked this file for a floor, was handed 0, and had a screen of 31 px
	# controls clear it - so the verdict read "built for a finger" over furniture that was nothing of the kind. **That
	# is the worst shape a wrong answer takes: a clean bill of health from a measurement that never happened.** The
	# rule beside it already refuses a reading that states no device, for exactly this reason, and a floor of nothing
	# is the same fault one step further in.
	if least <= 0.0 or least_type <= 0:
		out.append(
			(
				"this device's own floor could not be worked out - %.1f px tall and %d px of type is no floor at all"
				% [least, least_type]
			)
		)
		return out
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
		# The words, and said apart from the height so a person knows which of the two to fix. A control with no
		# type of its own is passed over: it draws no words to be read.
		var words: int = int(facts.get("font", 0))
		if words > 0 and words < least_type:
			out.append("%s: %d px of type, under the %d px a reader needs" % [path, words, least_type])
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


## The four facts, taken from the node rather than made up: shown, laid out, how many children it holds, and what
## size its words are drawn at - plus whether a finger could press it, which is what `looks_built_for_a_finger`
## judges.
##
## **The type is the fact this file was missing, and the fault it hid was measured rather than imagined.** The
## strip's six tool stand-ins stood 98 px tall in a 98 px row with their words drawn at the desk's 13 - they are
## built when a tab is pressed, a frame after the device the view stated has been handed back - and this file
## reported the strip clean, because every one of the facts it held was right. **A button can be exactly as tall as
## a thumb needs with its words a third of the size they belong**, so the height of a thing and the size of the
## words in it are two questions, and a reading that holds only the first answers the wrong one.
##
## A control with no type of its own reads 0, and 0 is not judged: a row and a panel draw no words at all, while a
## button that overrides nothing answers with the theme's own size rather than with nothing.
static func _facts(node: Node) -> Dictionary:
	var control: Control = node as Control
	return {
		"visible": node.is_visible_in_tree(),
		"size": Vector2i.ZERO if control == null else Vector2i(control.size),
		"children": node.get_child_count(),
		"target": is_a_target(node),
		"font": 0 if control == null else control.get_theme_font_size(&"font_size"),
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
