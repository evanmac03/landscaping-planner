extends Node
## A dev tool: opens the pages that hold prose or a list, and reports **everything wrong with them that a
## rectangle cannot show** - a box cut while the room around it had room to give, and words a person should not
## be shown: a note to the author, a message a compiler would write, a sentence where a name belongs.
##
## It asks two questions about the screen itself as well: whether any control a page holds is drawn past the edge
## of it, and whether a tap on one of its buttons would reach it. The reach question is asked of the page **on
## its own**, with the board left out of it - whether the page has put itself over a button of the board's is the
## HUD's own question and is asked once there rather than once per page here.
##
## The rules are `RoomToSpare`'s and `GuiWords`'s and the walks are the probe's; this only decides which doors to
## open, opens one at a time, and puts each thing away before the next. **A door is named by the HUD method that
## opens it**, which is the same door the menu uses - so a page nobody can reach is not swept, and a door whose
## name changes is caught by the sweep saying so rather than by passing quietly.
##
## **What a door puts up is one of two kinds of thing, and they are not the same thing.** A *page* is a `Window`
## - the kind that takes the keyboard and carries its own title bar - and a *panel* is a `Control` laid over the
## drawing, which six of these doors open. Both are swept: every question here but one is about the controls
## underneath and asks a page and a panel the same way, and the one that is a page's alone - the page's own
## rectangle against the room - is a question about a `Window`. What came up is found by comparing what was
## visible before the door was called with what is visible after, because which node holds it is not a fact about
## the door: an earlier version looked only among the Hud's own children and reported every panel as *nothing came
## up* - and never put the panel away, so the six of them piled up inside one another and the block filled with
## one panel's words drawn over the next one's.
##
## The pages chosen are the ones with something in them that can be wrong. A page of buttons and a page of
## pictures have nothing that wants more room than it was given and nothing but names on it, so opening them
## would cost a page-load each and say nothing; the ones below hold the manual, a table, a list, or a field of
## words.
##
## **The state a page is swept in is the state it opens in.** A page whose prose only appears once something is
## chosen - the manual, whose body is empty until a subject is - cannot be reached this way, and that is a
## known ceiling rather than a defect in the sweep.
##
## Run it with run_scene and read the console:
##     res://tools/gui_sweep.tscn
##
## It prints and ends by itself, so a scripted run wants no `timeout`. Not part of the game: the export excludes
## `tools/*`, so nothing here ships.

const MainScene: PackedScene = preload("res://scenes/main.tscn")
const HudProbeScript := preload("res://scripts/hud_probe.gd")
const PageLayoutScript := preload("res://scripts/page_layout.gd")

## The HUD doors worth opening, in the order the menus offer them.
const PAGES: Array[String] = [
	"open_help_window",
	"open_keys",
	"open_status_window",
	"open_analytics_window",
	"open_billing_window",
	"open_ledger_window",
	"open_closeout_window",
	"open_estimate_window",
	"open_cost_window",
	"open_pipeline_board",
	"open_schedule_board",
	"open_plant_order_window",
	"open_plant_browser",
	"open_plant_key_window",
	"open_food_window",
	"open_rotation_window",
	"open_harvest_window",
	"open_sowing_window",
	"open_yield_window",
	"open_season_window",
	"open_ground_window",
	"open_walk_window",
	"open_snap_window",
	"open_sheet_window",
	"open_revision_window",
	"open_sync_window",
	"open_grading_window",
	"open_sun_window",
	"open_layer_window",
	"open_nearby_window",
	"open_site_report",
	"open_capture_window",
	"open_dxf_panel",
	"open_landxml_panel",
	"open_hatch_panel",
	"open_water_panel",
	"open_light_panel",
	"open_underlay_window",
	"open_osm_window",
	"open_command_palette",
	"open_start_drawing_window",
]


func _ready() -> void:
	var main: Node = MainScene.instantiate()
	add_child(main)
	for _i: int in 40:
		await get_tree().process_frame
	var hud: Node = main.get_node_or_null("Hud")
	if hud == null:
		print("SWEEP no Hud")
		return
	var pages := 0
	var panels := 0
	var faults := 0
	for door: String in PAGES:
		if not hud.has_method(door):
			print("SWEEP %-26s - no such door" % door)
			continue
		# What a door put up is a difference between two readings of what is visible, taken through the one walk
		# both sweeps share: a second search that could disagree with this one is the defect this project works
		# hardest to avoid.
		var before: Array[Node] = doors_up(hud)
		hud.call(door)
		for _i: int in 8:
			await get_tree().process_frame
		var up: Node = what_came_up(before, doors_up(hud))
		if up == null:
			print("SWEEP %-26s - nothing came up" % door)
			continue
		var window: Window = up as Window
		if window != null:
			pages += 1
		else:
			panels += 1
		var scope: String = scope_of(up)
		var found: PackedStringArray = HudProbeScript.crowded_lines(up, scope)
		var said: PackedStringArray = HudProbeScript.words_lines(up, scope)
		var loose: PackedStringArray = HudProbeScript.offscreen_lines(up, scope)
		# The reach question is asked of the page alone, with the board left out of it: whether one of the page's
		# own buttons is covered by another of its own is the page's business, and whether the *page* has put
		# itself over a button of the board's is asked once in the HUD's own block rather than once per page here.
		# A page is asked as a page; a panel is asked the way the board is asked - its own buttons against its own
		# furniture - because a panel is not a page.
		var far: Array[Dictionary] = (
			HudProbeScript.reach_findings(null, [window], scope)
			if window != null
			else HudProbeScript.reach_findings(up, [], scope)
		)
		# The two kinds, weighed apart: a button something else stands over cannot be pressed by anybody, and one
		# that is there and switched off is the design - a state button is dead until its field holds something -
		# so the first is a fault and the second is one of the lines below. Counting both said "2 thing(s) wrong"
		# about two pages that were behaving exactly as they are meant to.
		var covered: int = 0
		for one: Dictionary in far:
			if not bool(one["switched_off"]):
				covered += 1
		# And the four questions about what is *inside* the rectangles rather than where they are: words that
		# cannot be read against their paper, two things of one kind in one rectangle, a picture showing nothing,
		# and the page's own rectangle against the room. All four are named and none is counted as a clash, since
		# a plain plate and a pair a page means to swap are judgements - but they are counted here, because this
		# tool's job is to say how much there is to look at.
		var unreadable: PackedStringArray = HudProbeScript.contrast_lines(up, scope)
		var twins: PackedStringArray = HudProbeScript.twin_lines(up, scope)
		var empties: PackedStringArray = HudProbeScript.blank_lines(up, scope)
		# The page's own rectangle against the room is the one question that is a page's alone: a panel's rectangle
		# is where the person put the thing it reports on, and being over the drawing is what a panel is for. A
		# panel is not asked it, and nothing is written in its place.
		var adrift: PackedStringArray = (
			HudProbeScript.page_edge_lines([window]) if window != null else PackedStringArray()
		)
		# And whether the words fit the box they were drawn in, which is the one question here that means the
		# same thing on a phone as on a desk: a caption wanting more room than it was given is a caption losing
		# words at every size. It is the question the phone's own foot line answered with "Pinch: zoo". The
		# questions that depend on the *device* - a floor in pixels, a band the system keeps - are asked where
		# the device is, which is the phone itself through the probe's log and `tools/phone_touch_pass`.
		var cut: PackedStringArray = HudProbeScript.clipped_lines(up, scope)
		faults += (
			found.size() + said.size() + loose.size() + covered + unreadable.size()
			+ twins.size() + empties.size() + adrift.size() + cut.size()
		)
		print(
			(
				"SWEEP %-26s %-22s %d cut, %d word(s), %d offscreen, %d blocked, %d switched off, %d unreadable, %d twin(s), %d blank, %d adrift, %d clipped"
				% [
					door,
					scope,
					found.size(),
					said.size(),
					loose.size(),
					covered,
					far.size() - covered,
					unreadable.size(),
					twins.size(),
					empties.size(),
					adrift.size(),
					cut.size(),
				]
			)
		)
		var far_lines := PackedStringArray()
		for one: Dictionary in far:
			far_lines.append(String(one["line"]))
		for line: String in found + said + loose + far_lines + unreadable + twins + empties + adrift + cut:
			print("       " + line)
		# And whatever came up is put away, page or panel: the old run left every panel standing, which is what
		# filled the block above with one panel's words drawn over the next one's.
		put_away(up)
		for _i: int in 4:
			await get_tree().process_frame
	print("")
	print(
		(
			"SWEEP %d door(s) opened %d page(s) and %d panel(s), %d thing(s) wrong with what they show"
			% [pages + panels, pages, panels, faults]
		)
	)
	# And it ends. A tool that prints its verdict and then sits there for ever is a run somebody has to time out,
	# which is a fault this project has already fixed in another tool.
	get_tree().quit()

## **What a door put up, in one place, because both sweeps have to answer it the same way.** `gui_sweep` and
## `phone_touch_sweep` drive one door list, so a second search for what a door opened would be a second answer to
## one question - the defect this project works hardest to avoid.
##
## The two kinds of thing a door puts up - a page, which is a `Window`, and a panel, which is a `Control` - share no
## type between them: a `Window` is a `Viewport` and a `Control` is a `CanvasItem`, so both are carried here as a
## plain `Node` and asked what they are before they are asked anything else. The question has two halves: what is
## up before the door is called, and what came up because of it.


## **Every thing the Hud is showing**, wherever it is kept: a page the Hud holds directly, or a panel under a node
## of its own, which is where the six panel doors put theirs. A panel's own flag is not enough to see it by - every
## control inside a panel is switched on all along, so a panel nobody has opened has hundreds of controls reporting
## themselves visible - and a panel is up when it is visible in the tree, every control inside it coming with it.
static func is_up(node: Node) -> bool:
	var window: Window = node as Window
	if window != null:
		return window.visible
	var item: CanvasItem = node as CanvasItem
	return item != null and item.is_visible_in_tree()


static func doors_up(hud: Node) -> Array[Node]:
	var up: Array[Node] = []
	var stack: Array[Node] = [hud]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if is_up(node):
			up.append(node)
		for child: Node in node.get_children():
			stack.append(child)
	return up


## **The outermost thing that is up now and was not before.** Outermost because a page or a panel shows its contents
## with it, so without that rule a door would be answered with one of its own buttons. Nothing became visible means
## the door opened nothing, which is said rather than guessed at.
static func what_came_up(before: Array[Node], now: Array[Node]) -> Node:
	for item: Node in now:
		if before.has(item):
			continue
		var outermost := true
		var walk: Node = item.get_parent()
		while walk != null:
			if now.has(walk) and not before.has(walk):
				outermost = false
				break
			walk = walk.get_parent()
		if outermost:
			return item
	return null


## Put away whatever a door put up, page or panel. A `Window` and a `CanvasItem` are put away the same way but do
## not share the method, so this is the one place that knows both.
static func put_away(up: Node) -> void:
	var window: Window = up as Window
	if window != null:
		window.hide()
		return
	var item: CanvasItem = up as CanvasItem
	if item != null:
		item.hide()


## What to call the thing a door put up in a line of a report: a page by `PageLayout`, which owns that name, and a
## panel by the name it was given when it was built - the same fallback `PageLayout.page_name` itself uses for a
## node with no page script.
static func scope_of(up: Node) -> String:
	var window: Window = up as Window
	return PageLayoutScript.page_name(window) if window != null else String(up.name)
