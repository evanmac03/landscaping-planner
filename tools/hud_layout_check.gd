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
	return { "name": "HUD layout", "ok": ok, "clashes": clashes, "overflow": overflow, "summary": summary }
