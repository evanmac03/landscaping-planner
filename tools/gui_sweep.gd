extends Node
## A dev tool: opens the pages that hold prose or a list, and reports **everything wrong with them that a
## rectangle cannot show** - a box cut while the room around it had room to give, and words a person should not
## be shown: a note to the author, a message a compiler would write, a sentence where a name belongs.
##
## It asks two questions about the screen itself as well: whether any control a page holds is drawn past the edge
## of it, and whether a tap on one of its buttons would reach it. The reach question is asked of the page **on
## its own**, with the board left out of it - whether the page has put itself over a button of the board's is the
## HUD's own question and is asked once there rather than 33 times here.
##
## The rules are `RoomToSpare`'s and `GuiWords`'s and the walks are the probe's; this only decides which pages
## to open, opens one at a time, and closes each before the next. A page is named by the HUD method that opens
## it, which is the same door the menu uses - so a page nobody can reach is not swept, and a door whose name
## changes is caught by the sweep saying so rather than by passing quietly.
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
	"open_site_report",
	"open_dxf_panel",
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
	var swept := 0
	var faults := 0
	for door: String in PAGES:
		if not hud.has_method(door):
			print("SWEEP %-26s - no such door" % door)
			continue
		hud.call(door)
		for _i: int in 8:
			await get_tree().process_frame
		var page: Window = _the_page(hud)
		if page == null:
			print("SWEEP %-26s - nothing came up" % door)
			continue
		swept += 1
		var scope: String = PageLayoutScript.page_name(page)
		var found: PackedStringArray = HudProbeScript.crowded_lines(page, scope)
		var said: PackedStringArray = HudProbeScript.words_lines(page, scope)
		var loose: PackedStringArray = HudProbeScript.offscreen_lines(page, scope)
		# The reach question is asked of the page alone, with the board left out of it: whether one of the page's
		# own buttons is covered by another of its own is the page's business, and whether the *page* has put
		# itself over a button of the board's is asked once in the HUD's own block rather than 33 times here.
		var far: PackedStringArray = HudProbeScript.reach_lines(null, [page], scope)
		# And the four questions about what is *inside* the rectangles rather than where they are: words that
		# cannot be read against their paper, two things of one kind in one rectangle, a picture showing nothing,
		# and the page's own rectangle against the room. All four are named and none is counted as a clash, since
		# a plain plate and a pair a page means to swap are judgements - but they are counted here, because this
		# tool's job is to say how much there is to look at.
		var unreadable: PackedStringArray = HudProbeScript.contrast_lines(page, scope)
		var twins: PackedStringArray = HudProbeScript.twin_lines(page, scope)
		var empties: PackedStringArray = HudProbeScript.blank_lines(page, scope)
		var adrift: PackedStringArray = HudProbeScript.page_edge_lines([page])
		# And whether the words fit the box they were drawn in, which is the one question here that means the
		# same thing on a phone as on a desk: a caption wanting more room than it was given is a caption losing
		# words at every size. It is the question the phone's own foot line answered with "Pinch: zoo". The
		# questions that depend on the *device* - a floor in pixels, a band the system keeps - are asked where
		# the device is, which is the phone itself through the probe's log and `tools/phone_touch_pass`.
		var cut: PackedStringArray = HudProbeScript.clipped_lines(page, scope)
		faults += (
			found.size() + said.size() + loose.size() + far.size() + unreadable.size()
			+ twins.size() + empties.size() + adrift.size() + cut.size()
		)
		print(
			(
				"SWEEP %-26s %-22s %d cut, %d word(s), %d off, %d unreachable, %d unreadable, %d twin(s), %d blank, %d adrift, %d clipped"
				% [
					door,
					scope,
					found.size(),
					said.size(),
					loose.size(),
					far.size(),
					unreadable.size(),
					twins.size(),
					empties.size(),
					adrift.size(),
					cut.size(),
				]
			)
		)
		for line: String in found + said + loose + far + unreadable + twins + empties + adrift + cut:
			print("       " + line)
		page.hide()
		for _i: int in 4:
			await get_tree().process_frame
	print("")
	print("SWEEP %d page(s) opened, %d thing(s) wrong with what they show" % [swept, faults])


## The page the HUD just put up: the visible Window it holds.
func _the_page(hud: Node) -> Window:
	for node: Node in hud.get_children():
		var page: Window = node as Window
		if page != null and page.visible:
			return page
	return null
