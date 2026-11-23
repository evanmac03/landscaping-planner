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

## The format a reading is written in, and **the reason a reading says which one it is**: the second format added
## where each control stands, and a row written before that fact existed parses as a control standing at `0,0`. An old
## file compared against a new one would then report every node as **moved** - a screenful of false differences with
## the real ones buried in it - so `from_lines` refuses a reading that does not state this number rather than reading
## it at a guess. A line with no format at all is the first one, which is the case the refusal exists for.
const FORMAT := 2

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
## What is drawn over what, and the words for it: the gathering of a scene's surfaces and the sentence for a
## meeting are `HudProbe`'s and `DrawnSurfaces`', so this file asks the question and writes nothing of its own.
const HudProbeScript := preload("res://scripts/hud_probe.gd")


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
static func read(
	root: Node,
	density: float,
	scale: float = 0.0,
	built_at: float = 0.0,
	watch: Array[String] = NODES,
) -> Dictionary:
	var found: Dictionary = { }
	# The density is *handed in* rather than read here, and that is the point: by the time this runs, a view that
	# stated a phone has handed the machine's own density back, so `PhoneHud.dpi()` would answer 144 beside
	# furniture that was built at 450. The caller knows which device it photographed; this only records it.
	found[DEVICE] = { "dpi": density, "scale": scale, "built_at": built_at, "format": FORMAT }
	# **The paths a caller cares about are handed in, and this file's own list is only the default.** The nine names
	# below are what a HUD workspace wants read, and they are no part of a *reading*: a general caller passes its own
	# list, or none, and is then measured on the scene's own tree rather than against nine paths it never had - which
	# is how a bare `Control` with one button came back describing nine `Hud/Root/...` nodes as missing. A walk that
	# reports names nobody asked about is a second place stating what the scene contains, free to be wrong about it.
	# **And a caller who names nothing gets the scene's own tree, never nothing at all.** The first version of this
	# branch read only the names it was given, so a general workspace - which has no names of its own yet - came back
	# with no nodes and a caption that said `built for a finger - 0 nodes read`: a clean bill of health from a reading
	# that never happened, which is the one verdict this file refuses elsewhere and must not hand out here. Empty
	# therefore means *the whole of it* - the root, and every control a finger could press under it, which is what a
	# person pointing a workspace at a scene with no idea yet what is in it is asking for.
	if watch.is_empty():
		# **The root is named by its own name, because a path to itself is the empty string.** A row with no name, in
		# an instrument built on names that travel, is a row nobody can read and nothing can be diffed against.
		var stand: String = _a_path_to(root, root)
		found[stand if not stand.is_empty() else a_name_that_travels(root)] = _facts(root)
		for button: Node in _buttons_under(root):
			found[_a_path_to(root, button)] = _facts(button)
		return found
	for path: String in watch:
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


## What is drawn over what in the scene handed in, in `HudProbe`'s words and `DrawnSurfaces`' own sentence.
##
## **The question `Spacing` cannot ask**, and the reason this is here rather than in that caption. `Spacing`
## judges two targets against each other; this is the other fault - a plate or a sentence drawn across a
## control, or across other words - and it is the one that hid on a phone: the foot line was drawn straight
## across the dock's own tabs while every target was still a row tall and clear of its neighbour.
##
## It needs the **scene** rather than a reading, because what a surface stands inside is not something a row of
## numbers carries - so it is asked of whatever tree the workspace was handed, and a saved reading cannot
## answer it. That is the one place this differs from `Spacing`, which a reading can answer on its own.
static func overlap_lines(root: Node) -> PackedStringArray:
	if root == null:
		return PackedStringArray()
	return HudProbeScript.meeting_lines(HudProbeScript.all_in(root, "the scene"))


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
			"%s%sdpi=%.1f%sscale=%.3f%sbuilt_at=%.1f%sformat=%d"
			% [
				DEVICE,
				FIELD,
				float(device.get("dpi", 0.0)),
				FIELD,
				float(device.get("scale", 0.0)),
				FIELD,
				float(device.get("built_at", 0.0)),
				FIELD,
				# **Stamped, not copied out of the reading.** This function writes *this* format by definition -
				# what comes in is a reading and what goes out is a file - so taking the number from the dictionary
				# would let a reading made by hand in a test write a file that is then refused as an older format.
				FORMAT,
			]
		)
	)
	for path: String in _every_path(reading):
		var facts: Dictionary = reading[path]
		if bool(facts.get("missing", false)):
			out.append("%s%smissing" % [path, FIELD])
			continue
		var size: Vector2i = facts["size"]
		# **Where the control stands, in the frame every control on the screen shares**, which is the one fact a pair
		# of readings needs to be asked whether two controls overlap - and no other fact can answer it. Appended at
		# the end of the row so that every earlier field keeps its place in a file already written.
		var at: Vector2i = facts.get("at", Vector2i.ZERO)
		out.append(
			(
				"%s%svisible=%s%ssize=%dx%d%schildren=%d%starget=%s%sfont=%d%sat=%d,%d"
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
					FIELD,
					at.x,
					at.y,
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
			# **A reading of an older format is refused, and this is the whole reason the number exists.** The format
			# gained where each control stands, and a row written before it reads as a control at `0,0`, so an old
			# file against a new one would report every node as moved. A refusal is somebody being told to look
			# again; a guess is a screenful of differences that are not there, with the real ones buried among them.
			# **`its_format` and not `written`, because `written` is this function's own parameter** - a local
			# shadowing it is a slip this project's analyser names, and the two are different things: one is the
			# lines being read, the other is the number they claim to be in.
			var its_format: int = 1 if parts.size() <= 4 else String(parts[4]).trim_prefix("format=").to_int()
			if its_format != FORMAT:
				return { }
			device["format"] = its_format
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
			# **Where it stands, defaulted to nothing rather than invented.** A row of this format always carries it;
			# the default is what a row of an older format would read as, and that reading has already been refused
			# above, so an absent place is a zero and never a claim about where a control is.
			"at": Vector2i.ZERO if parts.size() <= 6 else _a_point(String(parts[6]).trim_prefix("at=")),
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
	# **And where it stands, which the first four facts between them could not say.** A control that has slid across
	# the screen while keeping its size, its type and its visibility is exactly the change a person laying a GUI out
	# makes and the one this file used to be silent about - measured, a button moved 40 px came back as no difference
	# at all. Both places are named, in the order the two readings were handed in, so the sentence is readable either
	# way round rather than needing the caller to remember which argument was which.
	var here_at: Vector2i = here.get("at", Vector2i.ZERO)
	var there_at: Vector2i = there.get("at", Vector2i.ZERO)
	if here_at != there_at:
		out.append("%s: it stood at %d,%d and now at %d,%d" % [path, here_at.x, here_at.y, there_at.x, there_at.y])
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
		# **Asked in whichever way the node can answer.** `is_visible_in_tree` belongs to `CanvasItem`, so a plain `Node`
		# has no such call - measured, a reading whose root was a `Node` failed inside this function and left every fact
		# after it unwritten, so `differences` reported a row it had never managed to read. A `CanvasLayer` is not a
		# `CanvasItem` either and keeps its own `visible`, which means what it says; anything else is not hidden, which is
		# the honest answer for a thing that cannot be.
		"visible": _is_showing(node),
		"size": Vector2i.ZERO if control == null else Vector2i(control.size),
		# **Where it stands in the common frame, which no other fact can say.** `global_position` rather than
		# `position`: two controls under different parents have no frame in common otherwise, and an overlap question
		# asked in two frames is two answers. Truncated to whole pixels, as the size is, because this is a reading of
		# a layout and not of a sub-pixel.
		"at": Vector2i.ZERO if control == null else Vector2i(control.global_position),
		"children": node.get_child_count(),
		"target": is_a_target(node),
		"font": 0 if control == null else control.get_theme_font_size(&"font_size"),
	}


## Whether a node is showing, asked in whichever way it can answer.
##
## **This is a fact about the node's *class* and not about the scene**, which is why it is here rather than in the
## reading: a walk that can meet any node at all has to be able to ask that node its questions, and asking a `Node`
## for a `CanvasItem`'s leaves a reading half taken rather than reporting that it could not.
static func _is_showing(node: Node) -> bool:
	if node is CanvasItem:
		return (node as CanvasItem).is_visible_in_tree()
	if node is CanvasLayer:
		return (node as CanvasLayer).visible
	return true


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


## "221,31" as a `Vector2i`, for **a place** rather than a size.
##
## **Its own reader rather than `_a_size`, because the separators are deliberately different.** A size and a place
## that read alike in a file would be read into each other's field by a person's eye, and somebody comparing two
## readings should not have to count fields to know which pair of numbers is which.
static func _a_point(written: String) -> Vector2i:
	var halves: PackedStringArray = written.split(",")
	if halves.size() != 2:
		return Vector2i.ZERO
	return Vector2i(halves[0].to_int(), halves[1].to_int())


## The marker a judgement line carries in a written reading, so the words and the numbers can travel in one file and
## still be told apart. It leads the line and is stripped on the way back in.
const VERDICT_LINE := "! "


## The file one workspace's half of the comparison leaves its reading in, **named for the workspace**.
##
## **This is the fault that would have waited for a second user of this instrument.** The names were the phone
## workshop's, hard-coded: any other scene that read itself would have left its numbers where the phone's were, and
## then been compared against a phone HUD it had never built - reporting a screenful of differences that were not
## there, and hiding the real ones among them. A reading names itself the way a person names a file, and `which` is
## the half it is - `"editor"` or `"run"`, the two processes that cannot share one file because one would overwrite
## the other's.
static func a_reading_file(called: String, which: String) -> String:
	return "user://%s_%s_reading.txt" % [called, which]


## Every judgement line of a written reading, in the order written, with the marker taken off - so a run can echo what
## an editor said about its own furniture, and an editor can do the same for a run.
static func verdict_lines_of(written: PackedStringArray) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for one: String in written:
		if one.begins_with(VERDICT_LINE):
			out.append(one.trim_prefix(VERDICT_LINE))
	return out


## Leave a reading where the other half of the comparison can find it, through a temporary file and a rename - the
## house rule for every write, so a write that fails never leaves a shorter file where the real one was.
##
## **The judgement travels with the numbers**, marked by `VERDICT_LINE`: figures without their judgement make every
## reader work it out again, and a judgement without its figures cannot be checked. `false` comes back when the write
## failed, so a caller can say so rather than believe a reading was left.
static func leave(reading: Dictionary, where: String) -> bool:
	var temporary: String = where + ".writing"
	var file: FileAccess = FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return false
	for line: String in lines(reading):
		file.store_line(line)
	for told: String in looks_built_for_a_finger(reading):
		file.store_line(VERDICT_LINE + told)
	file.close()
	return DirAccess.rename_absolute(temporary, where) == OK


## A reading read back off a file, or nothing where there was none - which is what lets "nothing to compare with yet"
## be said rather than a comparison against an absent reading that agrees with everything. Blank lines are dropped,
## because a trailing newline is a property of the file and not a node of the scene.
static func lines_from(where: String) -> PackedStringArray:
	if not FileAccess.file_exists(where):
		return PackedStringArray()
	var file: FileAccess = FileAccess.open(where, FileAccess.READ)
	if file == null:
		return PackedStringArray()
	var out: PackedStringArray = PackedStringArray()
	while not file.eof_reached():
		var one: String = file.get_line()
		if not one.is_empty():
			out.append(one)
	file.close()
	return out


## How many of the nodes a reading holds are ones a finger could press - **the set the floor is measured against**,
## and therefore the number that belongs beside a judgement about a finger. Public because a workspace may want to say
## it on its own account, and a count of the reading is the reading's own business to work out.
static func how_many_a_finger_could_press(reading: Dictionary) -> int:
	var out: int = 0
	for path: String in _every_path(reading):
		if bool((reading[path] as Dictionary).get("target", false)):
			out += 1
	return out


## Every control a finger could press, as the shape `Spacing` asks its pairs in: `{ "name", "rect" }`, with the
## rectangle built from the two facts the reading already carries.
##
## **Built here rather than in a workspace**, because *which controls are targets* is a fact of the reading and a
## workspace that worked it out again could come to disagree about who is in the list - the one thing this instrument
## exists to make visible. And a control the reading holds no place for is left out rather than placed at `0,0`: an
## absent place is not a place, and a reading that invented one would report an overlap with whatever really stands at
## the origin.
static func the_things_a_finger_could_press(reading: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for path: String in _every_path(reading):
		var facts: Dictionary = reading[path]
		# **And what a person cannot see is not a pair.** A hidden control is not one a finger can meet, so it cannot be
		# confused with one - and `looks_built_for_a_finger` already judges only what is showing, so a pair list that
		# did not would be two answers to one question, free to disagree. Measured on the demo scene: the HUD's sheet
		# is down, its Close reads `visible=false`, and it stood clear of everything by luck rather than by rule.
		if (
			bool(facts.get("missing", false)) or not bool(facts.get("target", false))
			or not bool(facts.get("visible", false)) or not facts.has("at")
		):
			continue
		var at: Vector2i = facts["at"]
		var size: Vector2i = facts["size"]
		out.append({ "name": path, "rect": Rect2i(at, size) })
	return out


## What a finger's row comes to on the devices that matter, **asked of `PhoneHud` and never restated**: the device the
## reading was taken at, this machine's own, and the density `TouchInput` decides by. A floor is a length only once a
## density turns it into pixels, so three densities is three answers to one question - and the arithmetic belongs to
## `PhoneHud`, which is why nothing here works one out.
static func _rows_where_it_matters(density: float) -> String:
	var here: float = PhoneHudScript.dpi()
	return (
		"a finger's row is %.1f px at %.0f dpi, %.1f at this machine's %.0f, %.1f at the %.0f TouchInput decides by"
		% [
			expected_row_height(density),
			density,
			expected_row_height(here),
			here,
			expected_row_height(TouchInputScript.HELD_DPI),
			TouchInputScript.HELD_DPI,
		]
	)


## The caption a 2D workspace draws over the scene it is reading: the judgement, how much of the scene was read, the
## device it was read at, which controls are under a finger's floor, and what a finger's row comes to elsewhere.
##
## **This is the half a scene should not have to word for itself.** A reading and the words about it are one thing
## here for the same reason the arithmetic is: a caption written beside a report is a second place that can disagree
## with it, and the words are the part a person actually reads. **Which** controls are under the floor are named,
## not counted, for the first two - a count sends a person hunting - and the rest are a count, so a screen with forty
## faults still says so in one line rather than running off the edge of the room.
##
## The count of nodes read is `reading.size() - 1` because `read` writes the device line first and that line is not a
## node. The judgement is the device's own floor, so a scene drawn for a desk is measured against a desk's floor and
## says nothing at all about a finger - see `looks_built_for_a_finger`.
static func caption_lines(reading: Dictionary, density: float, built_scale: float) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var told: Array[String] = looks_built_for_a_finger(reading)
	var said: String = "built for a finger" if told.is_empty() else "%d under a finger's floor" % told.size()
	# **And how much of what was read a finger could press, said beside the judgement.** "27 nodes read" does not
	# say how many of them are things a thumb can meet: a scene of forty containers and three buttons would read as
	# either enormous or tiny depending on which number a person guessed, and the set the floor is measured against is
	# the fingers', not the nodes'.
	out.append(
		"%s - %d node(s) read, %d of them a finger's, at %.0f dpi, canvas scale %.3f"
		% [said, reading.size() - 1, how_many_a_finger_could_press(reading), density, built_scale]
	)
	for one: String in told.slice(0, 2):
		out.append(one)
	if told.size() > 2:
		out.append("... and %d more" % (told.size() - 2))
	out.append(_rows_where_it_matters(density))
	return out
