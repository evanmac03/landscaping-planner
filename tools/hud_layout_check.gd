extends Node

## A dev tool: instance the real game, then measure every HUD panel's on-screen rectangle and report
## which ones meet. The panels are laid out by anchors and by their own contents, so the only honest
## way to know whether they collide is to let the engine lay them out and read the rectangles back.
##
## Run it with run_scene and read the console:
##     res://tools/hud_layout_check.tscn
##
## The check is `run()` and not the scene, so `tools/audit.gd` can call it on the same instance of the
## game it runs the other checks on; this scene is that call with a game brought up for it. It returns
## `{name, ok, clashes, overflow, summary}`, counting a panel whose contents do not fit as a fault
## exactly as it counts a clash.

const MAIN := preload("res://scenes/main.tscn")
const Hud := preload("res://scripts/hud.gd")
const DrawnSurfacesScript := preload("res://scripts/drawn_surfaces.gd")
const HudProbeScript := preload("res://scripts/hud_probe.gd")
const PageLayoutScript := preload("res://scripts/page_layout.gd")
const PhoneHudScript := preload("res://scripts/phone_hud.gd")
const TouchInputScript := preload("res://scripts/touch_input.gd")
const PageChromeScript := preload("res://scripts/page_chrome.gd")

const PANELS: Array[String] = [
	"TopBar",
	"Hints",
	"DraftHints",
	"Palette",
	"Presentation",
	"PaintedSheet",
	"KeysPanel",
	"SiteReportPanel",
	"SurveyPanel",
	"DxfPanel",
	"HatchPanel",
	"WaterPanel",
	"LightPanel",
	"PlantWindow",
]

## Panels that are on screen with nothing opened: a collision with one of these is one a person sees.
const ALWAYS: Array[String] = ["TopBar", "Hints", "Presentation"]

## Full-screen modes: they cover the drawing on purpose, so they are measured but never called a clash.
const OVERLAY_MODE: Array[String] = ["PaintedSheet"]

## Panels built as a full-rect centering wrapper: the wrapper is a transparent, click-through device
## that spans the screen, so measuring it would report a clash with everything. Measure the page inside.
const PAGE_OF: Dictionary = {
	"KeysPanel": "Page",
	"SiteReportPanel": "Page",
	"SurveyPanel": "Page",
	"DxfPanel": "Page",
	"HatchPanel": "Page",
	"WaterPanel": "Page",
	"LightPanel": "Page",
}


## The one word `_fits` says when a thing has the room it wants, so the verdict below can count the
## other case without comparing prose.
const FITS := "FITS"


## Whether what wants a width has it, in the words the check reports it with.
static func _fits(wants: float, have: float) -> String:
	return FITS if wants <= have else "OVERFLOWS BY %.1f px" % (wants - have)


## The density a phone's pass states. A desk cannot *be* a phone, but the thing that made this check blind
## to the phone's own faults is the **finger's type** - which grows the top bar far past the scene's 50 px
## and wraps the foot line onto three - and that is state a caller may state, through the two doors a
## demonstration and a test already use: `PhoneHud.force_density` and `TouchInput.force`.
const PHONE_DENSITY := 450.0


## Whether the palette stands between the top bar's foot and the foot line's top, with the numbers read off
## the three things' own rectangles rather than restated.
##
## A **scalar** question on purpose. At a finger's type the top bar wants 2895 px in this window's 1600, so
## the bar and everything it spills over meet - and a meeting there is this desk-sized room's artefact rather
## than a phone's fault. The palette's place *between* the two things it may not be drawn over is decided by
## no width at all, so it is the one phone question a desk window can answer honestly.
##
## **The screen is handed in rather than read here**, the same pair of doors `OrientationChoice.can_turn` and
## `PhoneHud.apply_if` have, because a comparison of two heights is only a question where there is a screen to
## have them on. A headless run's dummy display is 64 x 64, so at a finger's type the foot line wraps to several
## screen-heights and its top comes back as a number like **-69443** - measured, and the reading that made this
## check fail on a fault nobody had. Handing it in is also what lets a test hold the rule on a room it built
## itself: the suite runs headless, so a rule that read the machine here could only ever be tested by refusing.
## The one place that answers whether there is a screen is `HudProbe._a_real_screen`, and `run` passes its answer.
static func palette_between_the_bar_and_the_foot(root: Control, there_is_a_screen: bool) -> Dictionary:
	var top_bar: Control = root.get_node_or_null(^"TopBar") as Control
	var palette: Control = root.get_node_or_null(^"Palette") as Control
	var foot: Control = root.get_node_or_null(^"Hints") as Control
	if top_bar == null or palette == null or foot == null:
		return { "asked": false, "held": false }
	if not there_is_a_screen:
		return { "asked": false, "held": false, "why": "there is no screen to have a finger's measurements on" }
	var bar_foot: float = top_bar.position.y + top_bar.size.y
	var palette_top: float = palette.position.y
	var palette_foot: float = palette.position.y + palette.size.y
	var foot_top: float = foot.position.y
	return {
		"asked": true,
		"held": palette_top >= bar_foot and palette_foot <= foot_top,
		"bar_foot": bar_foot,
		"palette_top": palette_top,
		"palette_foot": palette_foot,
		"foot_top": foot_top,
	}


## Everything a finger's fitting changes about the controls and menus under a node, read so that it can be
## written back and the room left as it was found.
##
## `PhoneHud.fit_for_a_finger` grows a control's caption type and its least size, the HUD's own fitting puts
## three of the top bar's children away, and a menu is grown through the same overrides **on the `Window`
## itself**. Nothing in the program puts a desk back - `size_for_a_finger` refuses an answer that is not a
## finger - so what the pass touches is remembered here and written back by hand.
static func _remember_what_a_finger_changes(hud: Node) -> Dictionary:
	var was: Dictionary = { }
	if hud == null:
		return was
	for node: Node in hud.find_children("*", "", true, false):
		var control: Control = node as Control
		if control != null:
			was[node] = {
				"font_stated": control.has_theme_font_size_override(&"font_size"),
				"font": control.get_theme_font_size(&"font_size"),
				"least": control.custom_minimum_size,
				"shown": control.visible,
				"sep_stated": false,
				"sep": 0,
			}
			continue
		var window: Window = node as Window
		if window != null:
			was[node] = {
				"font_stated": window.has_theme_font_size_override(&"font_size"),
				"font": window.get_theme_font_size(&"font_size", StringName(window.get_class())),
				"least": Vector2.ZERO,
				"shown": window.visible,
				"sep_stated": window.has_theme_constant_override(&"v_separation"),
				"sep": window.get_theme_constant(&"v_separation"),
			}
	return was


## Write back what `_remember_what_a_finger_changes` read, so the HUD the checks that follow measure is the
## one they found.
static func _put_back_what_a_finger_changed(hud: Node, was: Dictionary) -> void:
	if hud == null:
		return
	for key: Variant in was:
		var record: Dictionary = was[key]
		var control: Control = key as Control
		if control != null:
			if bool(record["font_stated"]):
				control.add_theme_font_size_override(&"font_size", int(record["font"]))
			else:
				control.remove_theme_font_size_override(&"font_size")
			control.custom_minimum_size = Vector2(record["least"])
			control.visible = bool(record["shown"])
			continue
		var window: Window = key as Window
		if window == null:
			continue
		if bool(record["font_stated"]):
			window.add_theme_font_size_override(&"font_size", int(record["font"]))
		else:
			window.remove_theme_font_size_override(&"font_size")
		if bool(record["sep_stated"]):
			window.add_theme_constant_override(&"v_separation", int(record["sep"]))
		else:
			window.remove_theme_constant_override(&"v_separation")
		window.visible = bool(record["shown"])


func _ready() -> void:
	var main: Node = MAIN.instantiate()
	add_child(main)
	for i in 5:
		await get_tree().process_frame
	await run(main, get_tree())


## The check itself, against a game that is already standing: `_ready` above brings one up for it, and
## `tools/audit.gd` hands over the same instance it runs the other checks on. Returns
## `{name, ok, clashes, overflow, summary}`.
static func run(main: Node, tree: SceneTree) -> Dictionary:
	var root: Control = main.get_node_or_null(^"Hud/Root") as Control
	if root == null:
		print("LAYOUT: no Hud/Root")
		return { "name": "HUD layout", "ok": false, "clashes": 0, "overflow": 1, "summary": "no Hud/Root in the scene" }
	# The one question about the machine, asked here and handed to whichever reading depends on it, because a
	# headless run's dummy display is 64 x 64 and every figure taken from the screen would otherwise be a fault
	# nobody has. The answer itself belongs to `HudProbe._a_real_screen`.
	var there_is_a_screen: bool = HudProbeScript._a_real_screen()
	# The Hud rewrites panel visibility every frame; stop it so a forced panel stays forced.
	var hud: Node = main.get_node_or_null(^"Hud")
	if hud != null:
		hud.set_process(false)
		hud.set_process_input(false)

	print("=== HUD LAYOUT (viewport %d x %d) ===" % [int(root.size.x), int(root.size.y)])

	var measured: Dictionary = { }
	var shown: Dictionary = { }
	# A panel whose contents do not fit is a fault the same way a clash is, and it is the fault the
	# rectangles cannot see: every panel can be clear of every other one while the legend runs off the
	# side of the panel it is in.
	var overflow := 0
	for panel_name in PANELS:
		var node: Control = root.get_node_or_null(NodePath(panel_name)) as Control
		if node == null:
			print("  %-16s -" % panel_name)
			continue
		var was: bool = node.visible
		node.visible = true
		await tree.process_frame
		# A centering wrapper is measured through to its page; everything else is measured as it stands.
		var page: Control = node
		if PAGE_OF.has(panel_name):
			page = node.get_node_or_null(NodePath(String(PAGE_OF[panel_name]))) as Control
			if page == null:
				page = node
		var r: Rect2 = page.get_global_rect()
		node.visible = was
		measured[panel_name] = r
		shown[panel_name] = was
		print(
			"  %-16s x %7.1f .. %-7.1f  y %7.1f .. %-7.1f   (%s)"
			% [
				panel_name,
				r.position.x,
				r.end.x,
				r.position.y,
				r.end.y,
				"on by default" if was else "opened from a menu",
			]
		)

	var top_bar: Control = root.get_node_or_null(^"TopBar") as Control
	var row: Control = root.get_node_or_null(^"TopBar/Row") as Control
	if top_bar != null and row != null:
		var wants: float = row.get_combined_minimum_size().x
		var row_fits: String = _fits(wants, top_bar.size.x)
		if row_fits != FITS:
			overflow += 1
		print("  TopBar row wants %.1f px, panel is %.1f px  ->  %s" % [wants, top_bar.size.x, row_fits])

	# What is *inside* the panels, because a panel's own rectangle says nothing about whether its
	# contents fit: the palette's grids are as wide as the tables that build them, and the legend is one
	# line per row of those tables. A table that grows can quietly push both past their panel.
	print("--- content fitting ---")
	var palette_panel: Control = root.get_node_or_null(^"Palette") as Control
	var palette_column: Control = root.find_child("PaletteColumn", true, false) as Control
	if palette_panel != null and palette_column != null:
		var palette_was: bool = palette_panel.visible
		palette_panel.visible = true
		await tree.process_frame
		var column_wants: float = palette_column.get_combined_minimum_size().x
		var column_fits: String = _fits(column_wants, palette_panel.size.x)
		if column_fits != FITS:
			overflow += 1
		print(
			"  PaletteColumn wants %6.1f px, Palette panel is %6.1f px  ->  %s"
			% [column_wants, palette_panel.size.x, column_fits]
		)
		# **And the height**, which the width above cannot see. It is a **reading and not a fault**, because the
		# palette's own box is a scroller: a `ScrollContainer` draws the part of its child standing inside it and
		# clips the rest away, so a column taller than its box is how a long palette is *meant* to work and the
		# rest of it is reached by scrolling. The number is printed because it is what says whether the palette
		# has outgrown the room between the bar and the foot line - the column wants 924 px on the desk in a
		# 768 px box, so its last 156 px are reached by scrolling rather than by standing on the screen.
		#
		# The screen is asked for first, because only a screen gives the box the height a wrapped foot line left
		# it. On a headless dummy display this reads as a number nobody has, which is why it is asked.
		if there_is_a_screen:
			var column_tall: float = palette_column.get_combined_minimum_size().y
			var below: float = column_tall - palette_panel.size.y
			print(
				"  PaletteColumn is %6.1f px tall, Palette box is %6.1f px  ->  %s"
				% [
					column_tall,
					palette_panel.size.y,
					(
						"all of it stands on the screen"
						if below <= 0.0
						else "%d px of it below the foot, reached by scrolling" % roundi(below)
					),
				]
			)
		palette_panel.visible = palette_was
	var hints_panel: Control = root.get_node_or_null(^"DraftHints") as Control
	var box: Control = root.find_child("DraftHintsLabel", true, false) as Control
	if hints_panel != null and box != null:
		# The box beside the plan is empty until a tool is in hand, so the **worst** tool's box is what is
		# measured rather than whatever happens to be on the screen: a panel measured empty passes on the day
		# the longest tool grew a wordier sentence. The same reasoning as the foot line below.
		var hints_was: bool = hints_panel.visible
		var box_was: String = (box as Label).text
		hints_panel.visible = true
		(box as Label).text = Hud.worst_tool_box()
		await tree.process_frame
		var box_wants: float = box.get_combined_minimum_size().x
		var box_rows: int = (box as Label).text.split("\n").size()
		var box_fits: String = _fits(box_wants, hints_panel.size.x)
		if box_fits != FITS:
			overflow += 1
		print(
			"  widest tool box line wants %6.1f px, DraftHints panel is %6.1f px over %d rows  ->  %s"
			% [box_wants, hints_panel.size.x, box_rows, box_fits]
		)
		print("    it reads: %s" % (box as Label).text.replace("\n", " / "))
		(box as Label).text = box_was
		hints_panel.visible = hints_was

	# The line at the foot of the screen is the one line whose words change with what is in hand, so the
	# worst case is measured rather than whatever happens to be on it at that moment: the longest prompt
	# any tool can be in, under that tool's own name, with the keys that answer it beside it. Measuring
	# only what happens to be on the line would pass on the day nothing is armed and fail a week later.
	var foot_panel: Control = root.get_node_or_null(^"Hints") as Control
	var foot_label: Control = root.find_child("HintsLabel", true, false) as Control
	if foot_panel != null and foot_label != null:
		var foot_was: bool = foot_panel.visible
		var words_was: String = (foot_label as Label).text
		var worst: String = Hud.worst_hint_line()
		foot_panel.visible = true
		(foot_label as Label).text = worst
		await tree.process_frame
		var foot_wants: float = foot_label.get_combined_minimum_size().x
		var foot_fits: String = _fits(foot_wants, foot_panel.size.x)
		if foot_fits != FITS:
			overflow += 1
		print(
			"  longest tool line wants %6.1f px, Hints panel is %6.1f px  ->  %s"
			% [foot_wants, foot_panel.size.x, foot_fits]
		)
		print("    it reads: %s" % worst)
		(foot_label as Label).text = words_was
		foot_panel.visible = foot_was

	print("--- panel rectangles that meet ---")
	var names: Array = measured.keys()
	var clashes := 0
	var touching := 0
	for i in names.size():
		for j in range(i + 1, names.size()):
			var a: String = names[i]
			var b: String = names[j]
			var ra: Rect2 = measured[a]
			var rb: Rect2 = measured[b]
			if not ra.intersects(rb):
				continue
			if a in OVERLAY_MODE or b in OVERLAY_MODE:
				continue
			var live: bool = (a in ALWAYS) or (b in ALWAYS)
			if live:
				clashes += 1
			else:
				touching += 1
			print(
				"  %-14s x %-14s   %s" % [a, b, "BOTH CAN BE UP -> a real clash" if live else "not up at the same time"]
			)
	if clashes == 0:
		print("  no clash with a panel that is always on screen")
	if touching > 0:
		print("  (%d further pairs that cannot be open together)" % touching)

	# What is *drawn* against what may not share rows with it. The pairs above are panels against panels, and
	# nothing there can see a page's own title bar: Godot draws it *above* the rectangle a page reports, so it
	# appears in neither that table nor the page's own measurement. A meeting with the bar at the top of the
	# screen is the fault this exists for and counts as a clash; every other meeting is named and left to the
	# person reading it, because whether a page's bar over the palette's first button is wrong is a judgement
	# about how the screen looks rather than a measurement - and the one the probe found on the desk is named
	# here rather than hidden.
	print("--- what is drawn against what may not share rows with it ---")
	var top_bar_meetings := 0
	var meetings: Array = []
	if hud != null and hud.has_method("drawn_surfaces"):
		meetings = DrawnSurfacesScript.meetings(hud.drawn_surfaces())
	for meeting: Dictionary in meetings:
		var reaches_the_bar: bool = (
			StringName((meeting["a"] as Dictionary)["kind"]) == DrawnSurfacesScript.TOP_BAR
			or StringName((meeting["b"] as Dictionary)["kind"]) == DrawnSurfacesScript.TOP_BAR
		)
		if reaches_the_bar:
			top_bar_meetings += 1
		print(
			"  %s   ->  %s"
			% [
				DrawnSurfacesScript.sentence(meeting),
				"a page has reached the bar at the top of the screen" if reaches_the_bar else "named, not counted",
			]
		)
	if meetings.is_empty():
		print("  nothing is drawn in a row it may not share")
	clashes += top_bar_meetings

	# What is *cut*: a thing scrolling or clipped inside a box smaller than it needs, while a box around it had
	# room to give. Named and not counted, exactly as a meeting with anything but the bar at the top of the
	# screen is: a note field that scrolls is a scroll on purpose, and whether *this* one is right is a
	# judgement the two numbers let a person make in a second and a rule cannot make at all.
	print("--- what is cut while the room around it had room to give ---")
	var cut := 0
	var rooms: Array = [root]
	var view: Viewport = root.get_viewport()
	if view != null:
		for window: Window in view.get_embedded_subwindows():
			if window.visible:
				rooms.append(window)
	for room: Node in rooms:
		var scope: String = "the board" if room == root else PageLayoutScript.page_name(room as Window)
		for line: String in HudProbeScript.crowded_lines(room, scope):
			cut += 1
			print("  " + line)
	if cut == 0:
		print("  nothing is cut that the room around it could have given")

	# What is *inside* the rectangles, which no section above asks about: words a person cannot read against
	# the colour behind them, two things of one kind drawing in exactly one rectangle so that only the later is
	# ever seen, and a picture with nothing in it. All three are named rather than counted, because a plate
	# somebody chose to leave plain and a pair of controls a page means to swap are both judgements - and so is a
	# page overhanging the edge of a small screen, which is why that one is named too rather than counted.
	print("--- what is inside the rectangles ---")
	var unreadable := 0
	var doubled := 0
	var empty := 0
	for room: Node in rooms:
		var inner_scope: String = "the board" if room == root else PageLayoutScript.page_name(room as Window)
		for line: String in HudProbeScript.contrast_lines(room, inner_scope):
			print("  " + line)
			unreadable += 1
		for line: String in HudProbeScript.twin_lines(room, inner_scope):
			print("  " + line)
			doubled += 1
		for line: String in HudProbeScript.blank_lines(room, inner_scope):
			print("  " + line)
			empty += 1
	if unreadable == 0:
		print("  every caption has ink a person can read against what is behind it")
	if doubled == 0:
		print("  no two things of one kind are drawn in one rectangle")
	if empty == 0:
		print("  no picture is being shown with nothing in it")
	var adrift := 0
	for line: String in HudProbeScript.page_edge_lines(rooms):
		print("  " + line)
		adrift += 1
	if adrift == 0:
		print("  every page stands inside the room")

	# What the *words* themselves say wrong. A rectangle is honest about its size and says nothing about the
	# text inside it, so this is the other half of "is it showing right": named and not counted, because what a
	# caption should say is the author's to decide and only the certain faults are rules here.
	print("--- words the GUI is showing that are wrong ---")
	var spoken := 0
	for room: Node in rooms:
		var spoken_scope: String = "the board" if room == root else PageLayoutScript.page_name(room as Window)
		for line: String in HudProbeScript.words_lines(room, spoken_scope):
			spoken += 1
			print("  " + line)
	if spoken == 0:
		print("  every caption, button and menu entry on the screen is words a person can read")

	# What the *screen itself* cannot hold. Every measurement above puts a control beside another control, or
	# beside its own contents; not one of them put a control beside the room it is standing in, so a button
	# drawn past the edge of the screen - which nobody can press, and which the phone's own view buttons really
	# were, wholly off it - was invisible to all of it. This one is counted, like the bar at the top of the
	# screen, because it is not a judgement: a control the room cannot hold is one a person can never reach.
	print("--- what the room cannot hold ---")
	var outside := 0
	for room: Node in rooms:
		var outside_scope: String = "the board" if room == root else PageLayoutScript.page_name(room as Window)
		for line: String in HudProbeScript.offscreen_lines(room, outside_scope):
			outside += 1
			print("  " + line)
	if outside == 0:
		print("  everything on the screen stands inside it")
	clashes += outside

	# Whether a tap would *reach* what it is aimed at, which is the question a driver asks when a click does
	# nothing at all. Named and not counted, deliberately: a page standing over the board is what a page is
	# *for*, so the board's own buttons being covered is the ordinary case rather than a fault. What is worth
	# reading is which button, and whether the thing standing on top of it is switched off.
	print("--- what a tap would reach ---")
	var unmet := 0
	var pages_up: Array = []
	for room: Node in rooms:
		if room != root:
			pages_up.append(room)
	for line: String in HudProbeScript.reach_lines(root, pages_up, "the board"):
		unmet += 1
		print("  " + line)
	if unmet == 0:
		print("  every button on the screen would be reached by a tap at its middle")

	# The one phone-only question a desk-sized window can ask honestly. Measured on the A16W: with a
	# finger's type the top bar grows far past the scene's 50 px and the foot line wraps onto three, and the
	# offsets the scene drew the palette with - right for a desk's 62 px bar - then drew it *over* the menu
	# bar's own titles and put the wrapped foot line over the palette's last rows. Every pass above read FIT
	# while that was true, because a desk's bar and plate both still agree with the scene's own numbers: a
	# fault a finger's type creates is not findable at a desk's type until one is *stated*.
	#
	# The device is stated and put back below, because this runs inside `tools/audit.gd`, where the other
	# checks follow. What is asked of it is narrow on purpose: the palette's top and foot against the bar's
	# foot and the plate's top, which are **vertical**, and so survive the one dishonesty of measuring a
	# phone in a desk's room. The wider meetings are not asked here, because at a finger's type the bar
	# spills over every panel it can reach and a meeting there says nothing about a phone.
	print("--- the palette's place when the device asks with a finger ---")
	var at_a_desk: Dictionary = _remember_what_a_finger_changes(hud)
	PhoneHudScript.force_density(PHONE_DENSITY)
	TouchInputScript.force(TouchInputScript.Answer.FINGER)
	# Asked twice: the pass grows the fonts and defers the palette's placement to the frame after it, and
	# this HUD is not processing (the line at the top of `run`), so nothing would ask again where a phone's
	# own per-frame pass would. The second ask reads the bar and the plate the finger's type settled into.
	for ask in 2:
		if hud != null and hud.has_method("_size_the_chrome_for_the_device"):
			hud._size_the_chrome_for_the_device()
		for i in 4:
			await tree.process_frame
	var place: Dictionary = palette_between_the_bar_and_the_foot(root, there_is_a_screen)
	var palette_loose := 0
	if not bool(place["asked"]):
		print("  the palette was not asked about: %s" % String(place.get("why", "it was not on the screen")))
	elif bool(place["held"]):
		print(
			(
				"  the palette stands between the bar's foot (%.1f) and the foot line's top (%.1f)"
				% [place["bar_foot"], place["foot_top"]]
			)
		)
	else:
		palette_loose += 1
		clashes += 1
		print(
			(
				"  the palette is drawn over the bar or the foot line: top %.1f against a bar foot of %.1f,"
				+ " foot %.1f against a line top of %.1f"
			)
			% [place["palette_top"], place["bar_foot"], place["palette_foot"], place["foot_top"]]
		)
	PhoneHudScript.force_density(0.0)
	TouchInputScript.force(TouchInputScript.Answer.AUTO)
	# Put the chrome back the way it was found, in two parts, because the fitting changed two kinds of thing:
	# every control it grew - its caption's type and its least size - and the three of the bar's children it put
	# away, which are written back from the snapshot taken above. What the fitting *informs* rather than
	# changes - the strip it states above which no page may stand, and the pages it re-places - is written back
	# by asking the HUD's own pass once more, now that the bar it reads stands where the scene drew it. This
	# runs inside `tools/audit.gd`, where the checks that follow measure the same HUD.
	_put_back_what_a_finger_changed(hud, at_a_desk)
	for i in 2:
		await tree.process_frame
	if hud != null and hud.has_method("_size_the_chrome_for_the_device"):
		hud._size_the_chrome_for_the_device()
	for i in 3:
		await tree.process_frame
	# The finger's room also re-placed the pages that were up, and `_the_canvas_changed_shape` re-places a page
	# only when the room's *shape* changes - which putting the chrome back does not. So the pages are put back
	# here, through the same door a reshape uses, or the front door the tool leaves on the screen would stand
	# where a phone's room put it.
	for window: Window in main.get_viewport().get_embedded_subwindows():
		if window.visible:
			PageChromeScript.placed_again(window)
	for i in 2:
		await tree.process_frame

	# Leave the drafting state on screen so the capture shows the panels the check is about.
	var draft_hints: Control = root.get_node_or_null(^"DraftHints") as Control
	if draft_hints != null:
		draft_hints.visible = true
	for i in 3:
		await tree.process_frame
	print("=== END LAYOUT ===")
	var ok: bool = clashes == 0 and overflow == 0
	var summary: String
	if ok:
		summary = "no clash with a panel that is always on screen, and no contents wider than their panel"
	else:
		summary = "%d clash(es) with a panel that is always on screen, %d thing(s) wider than their panel" % [
			clashes,
			overflow,
		]
	if top_bar_meetings > 0:
		summary += "; a page's title bar reached the bar at the top of the screen"
	if cut > 0:
		summary += "; %d thing(s) cut while the room around them had room to give" % cut
	if spoken > 0:
		summary += "; %d caption(s) with something wrong in the words" % spoken
	if outside > 0:
		summary += "; %d thing(s) the screen cannot hold" % outside
	if unmet > 0:
		summary += "; %d button(s) a tap would not reach" % unmet
	if palette_loose > 0:
		summary += "; at a finger's type the palette is drawn over the bar or the foot line"
	return { "name": "HUD layout", "ok": ok, "clashes": clashes, "overflow": overflow, "summary": summary }
