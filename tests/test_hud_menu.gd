extends Node
## The menu bar: its entries, the keys they advertise, and the methods they name.
##
## A menu is one of the few places a program can promise something without doing it - an entry
## that does nothing, or that names a key which is no longer bound. These are the tests that
## stand between the bar and that, and they read the bar the way it is built: as data.

const HudScript := preload("res://scripts/hud.gd")
const DeskScript := preload("res://scripts/biz/estimate_desk.gd")
const ToolScript := preload("res://scripts/draft/draft_tool.gd")
const TierScript := preload("res://scripts/vis/presentation_tier.gd")
const PlotScaleScript := preload("res://scripts/draft/plot_scale.gd")
const ControllerScript := preload("res://scripts/draft/draft_controller.gd")
const DocumentScript := preload("res://scripts/draft/draft_document.gd")
const TerrainProfile := preload("res://scripts/terrain_profile.gd")
const ZoneMapScript := preload("res://scripts/zone_map.gd")

const KINDS: Array[StringName] = [
	&"command", &"radio", &"check", &"submenu", &"separator", &"info",
]


## The entry with an id, or a failure that names it: an entry that has been renamed should break
## the test that was about it rather than quietly testing nothing.
func _entry(id: StringName) -> Dictionary:
	for entry: Dictionary in HudScript.menu_entries():
		if StringName(entry.get("id", &"")) == id:
			return entry
	assert(false, "no menu entry with id %s" % String(id))
	return {}


func test_the_bar_is_the_menus_a_program_of_this_kind_has() -> void:
	var titles: Array[String] = []
	for menu: Dictionary in HudScript.menu_plan():
		titles.append(String(menu["title"]))
		var items: Array = menu["items"]
		assert(items.size() > 0, "the %s menu has entries" % String(menu["title"]))
		for entry: Dictionary in items:
			assert(
				KINDS.has(StringName(entry.get("kind", &""))),
				"%s entry has a kind the builder knows" % String(menu["title"])
			)
	var expected: Array[String] = [
		"File", "Edit", "View", "Draft", "Site", "Plant", "Estimate", "Present", "Help",
	]
	assert(titles == expected)


func test_every_entry_names_a_method_that_exists() -> void:
	# An entry that names nothing, or names a method that has been renamed away, is a menu item
	# that looks like it works.
	var hud := HudScript.new()
	for entry: Dictionary in HudScript.menu_entries():
		# A separator and an "info" line are the only entries that are not meant to do anything:
		# they are punctuation.
		if StringName(entry.get("kind", &"")) in [&"separator", &"submenu", &"info"]:
			continue
		var method := String(entry.get("method", ""))
		assert(method != "", "%s names a method" % String(entry["id"]))
		assert(hud.has_method(method), "%s names a method that exists: %s" % [String(entry["id"]), method])
	hud.free()


func test_the_draft_menu_holds_every_tool_the_legend_holds() -> void:
	# The tools come from the table the legend and the palette are built from, so the menu cannot
	# offer a different set of tools from the one the keys arm.
	var in_menu: Array[StringName] = []
	for entry: Dictionary in HudScript.items_for("Draft"):
		var id := String(entry.get("id", ""))
		if id.begins_with("draft.tool."):
			in_menu.append(StringName(entry.get("action", &"")))
	var expected: Array[StringName] = []
	for pair: Array in HudScript.DRAFTING_TOOLS:
		expected.append(StringName(pair[0]))
	assert(in_menu == expected, "the Draft menu offers the tools, in the legend's order")
	for pair: Array in HudScript.DRAFTING_TOOLS:
		var entry: Dictionary = _entry(StringName("draft.tool." + String(pair[0])))
		assert(int(entry["value"]) == int(pair[2]), "%s arms the tool the key arms" % String(pair[0]))


## The editing commands live in the Edit menu, and it offers exactly the set the
## controller can run, in the order the legend lists them.
func test_the_edit_menu_holds_every_editing_command() -> void:
	var in_menu: Array[StringName] = []
	for entry: Dictionary in HudScript.items_for("Edit"):
		var id := String(entry.get("id", ""))
		if id.begins_with("edit.tool."):
			in_menu.append(StringName(entry.get("action", &"")))
	var expected: Array[StringName] = []
	for pair: Array in HudScript.EDIT_TOOLS:
		expected.append(StringName(pair[0]))
	assert(in_menu == expected, "the Edit menu offers the editing commands, in the legend's order")
	for pair: Array in HudScript.EDIT_TOOLS:
		var entry: Dictionary = _entry(StringName("edit.tool." + String(pair[0])))
		assert(int(entry["value"]) == int(pair[2]), "%s runs the command the key runs" % String(pair[0]))


func test_every_command_the_legend_lists_is_in_the_bar() -> void:
	# Not every one of them is in the Draft menu: undo and redo are in Edit, which is where a
	# program of this kind keeps them, and copying them into both menus would be one command with
	# two owners. What has to hold is that the legend names nothing the bar cannot reach.
	var actions: Array[StringName] = []
	for entry: Dictionary in HudScript.menu_entries():
		actions.append(StringName(entry.get("action", &"")))
	for pair: Array in HudScript.DRAFTING_COMMANDS:
		assert(
			actions.has(StringName(pair[0])),
			"the bar has %s, which the legend lists" % String(pair[1])
		)
	# And the four that are about the shape in hand are in the menu about drawing.
	var draft: Array[StringName] = []
	for entry: Dictionary in HudScript.items_for("Draft"):
		draft.append(StringName(entry.get("action", &"")))
	for action: StringName in [
		&"draft_finish", &"draft_close", &"draft_undo_point", &"draft_cancel", &"draft_plot",
	]:
		assert(draft.has(action), "the Draft menu has %s" % String(action))


func test_every_key_a_menu_advertises_is_bound_and_shown() -> void:
	for entry: Dictionary in HudScript.menu_entries():
		var action := StringName(entry.get("action", &""))
		if action == &"":
			continue
		assert(InputMap.has_action(action), "%s names a bound action: %s" % [String(entry["id"]), action])
		var key := HudScript._key_label(action)
		assert(key != "", "%s names an action with a key: %s" % [String(entry["id"]), action])
		assert(
			HudScript.menu_label(entry).contains(key),
			"%s shows the key it names: %s" % [String(entry["id"]), key]
		)


func test_no_two_entries_share_an_id() -> void:
	# The dispatcher finds an entry by the menu it is in and its position, so ids are for reading
	# and for tests; two entries with one id would make a test about the wrong one pass.
	var seen: Array[String] = []
	for entry: Dictionary in HudScript.menu_entries():
		if StringName(entry.get("kind", &"")) == &"separator":
			continue
		var id := String(entry["id"])
		assert(not seen.has(id), "an id appears once: %s" % id)
		seen.append(id)


func test_every_entry_that_needs_something_names_something_known() -> void:
	# What an entry needs from the scene decides whether it is offered live; a need nobody answers
	# for would leave an entry switched off forever, with no reason.
	for entry: Dictionary in HudScript.menu_entries():
		assert(HudScript.KNOWN_NEEDS.has(StringName(entry.get("needs", &""))),
			"%s needs something known" % String(entry["id"]))
	assert(_entry(&"file.plot")["needs"] == HudScript.NEEDS_DRAFT)
	assert(_entry(&"file.still")["needs"] == HudScript.NEEDS_PRESENTATION)
	assert(_entry(&"file.quit")["needs"] == HudScript.NEEDS_NOTHING)


func test_the_view_the_menu_shows_as_chosen_is_the_view_you_are_in() -> void:
	var plan: Dictionary = _entry(&"view.plan")
	var ground: Dictionary = _entry(&"view.ground")
	var overhead: Dictionary = _entry(&"view.overhead")
	var in_plan: Dictionary = {"mode": int(ViewController.ViewMode.PLAN_2D)}
	var in_ground: Dictionary = {"mode": int(ViewController.ViewMode.GROUND)}
	var in_overhead: Dictionary = {"mode": int(ViewController.ViewMode.OVERHEAD_3D)}
	assert(HudScript.is_checked(&"mode", plan["value"], in_plan))
	assert(not HudScript.is_checked(&"mode", plan["value"], in_ground))
	assert(HudScript.is_checked(&"mode", ground["value"], in_ground))
	assert(not HudScript.is_checked(&"mode", ground["value"], in_overhead))
	assert(HudScript.is_checked(&"mode", overhead["value"], in_overhead))
	# The three entries are the three views there are, so a fourth added to the enum would show
	# up here as a menu that cannot reach it.
	var offered: Array[int] = [int(plan["value"]), int(overhead["value"]), int(ground["value"])]
	offered.sort()
	var all_views: Array[int] = [
		int(ViewController.ViewMode.PLAN_2D),
		int(ViewController.ViewMode.OVERHEAD_3D),
		int(ViewController.ViewMode.GROUND),
	]
	all_views.sort()
	assert(offered == all_views)


func test_a_tool_is_shown_as_chosen_only_while_the_tools_are_out() -> void:
	var line: Dictionary = _entry(&"draft.tool.draft_line")
	assert(HudScript.is_checked(&"tool", line["value"], {"drawing": true, "tool": int(ToolScript.Kind.LINE)}))
	assert(not HudScript.is_checked(&"tool", line["value"], {"drawing": true, "tool": int(ToolScript.Kind.CIRCLE)}))
	assert(not HudScript.is_checked(&"tool", line["value"], {"drawing": false, "tool": int(ToolScript.Kind.LINE)}))
	assert(HudScript.is_checked(&"drawing", null, {"drawing": true}))
	assert(not HudScript.is_checked(&"drawing", null, {"drawing": false}))


func test_the_sheet_and_the_scale_shown_are_the_ones_the_plotter_will_use() -> void:
	var first_sheet := String(PlotScaleScript.sheet_names()[0])
	var sheet: Dictionary = _entry(StringName("file.sheet." + first_sheet))
	assert(HudScript.is_checked(&"sheet", sheet["value"], {"sheet": first_sheet}))
	assert(not HudScript.is_checked(&"sheet", sheet["value"], {"sheet": first_sheet + "-not"}))
	var hundred: Dictionary = _entry(&"file.scale.100")
	assert(HudScript.is_checked(&"scale", hundred["value"], {"plot_scale": 100.0}))
	assert(not HudScript.is_checked(&"scale", hundred["value"], {"plot_scale": 50.0}))
	# One entry for every sheet and every scale the plotter knows, which is where the set comes
	# from in the first place.
	var sheets: Array[String] = []
	for name in PlotScaleScript.sheet_names():
		sheets.append(String(name))
	for name in sheets:
		assert(not _entry(StringName("file.sheet." + name)).is_empty())
	var scales := 0
	for entry: Dictionary in HudScript.items_for("File"):
		if String(entry.get("id", "")).begins_with("file.scale."):
			scales += 1
	assert(scales == 0, "the scales are behind their submenu, not in the File menu")


func test_a_dimension_standard_is_shown_when_it_is_the_one_in_force() -> void:
	var entry: Dictionary = _entry(&"edit.dimension_style.architectural")
	assert(HudScript.is_checked(&"dimension_style", entry["value"], {"dimension_style": &"architectural"}))
	assert(not HudScript.is_checked(&"dimension_style", entry["value"], {"dimension_style": &"engineering"}))
	var styles := 0
	for style: StringName in ControllerScript.DIMENSION_STYLES:
		styles += 1
		assert(not _entry(StringName("edit.dimension_style." + String(style))).is_empty())
	assert(styles >= 2)


func test_the_presentation_entries_report_the_presentation() -> void:
	var running: Dictionary = _entry(&"present.running")
	assert(HudScript.is_checked(&"presenting", running["value"], {"presenting": true}))
	assert(not HudScript.is_checked(&"presenting", running["value"], {"presenting": false}))
	var still: Dictionary = _entry(StringName("present.quality.%d" % TierScript.STILL))
	assert(HudScript.is_checked(&"tier", still["value"], {"tier": TierScript.STILL}))
	assert(not HudScript.is_checked(&"tier", still["value"], {"tier": TierScript.WORKING}))
	# One entry for every budget the tier table offers.
	var offered: Array[int] = []
	for entry: Dictionary in HudScript.tier_items():
		offered.append(int(entry["value"]))
	assert(offered == TierScript.CHOICES)
	# And one for every still size the render button offers.
	var sizes := 0
	for entry: Dictionary in HudScript.still_size_items():
		assert(String(entry["label"]) == String(HudScript.STILL_SIZES[sizes][0]))
		sizes += 1
	assert(sizes == HudScript.STILL_SIZES.size())
	assert(HudScript.is_checked(&"still_size", 2, {"still_size": 2}))
	assert(not HudScript.is_checked(&"still_size", 2, {"still_size": 0}))


func test_the_help_entry_reports_whether_the_keys_are_up() -> void:
	var keys: Dictionary = _entry(&"help.keys")
	assert(HudScript.is_checked(&"keys_panel", keys["value"], {"keys_panel": true}))
	assert(not HudScript.is_checked(&"keys_panel", keys["value"], {"keys_panel": false}))
	var hints: Dictionary = _entry(&"view.hints")
	assert(HudScript.is_checked(&"hints", hints["value"], {"hints": true}))
	assert(not HudScript.is_checked(&"hints", hints["value"], {"hints": false}))


func test_the_file_menu_offers_what_a_file_menu_offers() -> void:
	var ids: Array[String] = []
	for entry: Dictionary in HudScript.items_for("File"):
		ids.append(String(entry.get("id", "")))
	for wanted: String in [
		"file.new", "file.open", "file.recent", "file.save", "file.save_as",
		"file.plot", "file.still", "file.sheet", "file.scale", "file.quit",
	]:
		assert(ids.has(wanted), "the File menu offers %s" % wanted)
	# In the order a person looks for them: what is open, then the drawing itself, then what
	# leaves the program, then the sheet, then leaving.
	assert(ids.find("file.info") < ids.find("file.new"), "the drawing is named at the top")
	assert(ids.find("file.open") < ids.find("file.save"), "open before save")
	assert(ids.find("file.save_as") < ids.find("file.plot"), "saving before plotting")
	assert(ids.find("file.still") < ids.find("file.sheet"), "output before setup")
	assert(ids.find("file.sheet") < ids.find("file.quit"), "and quitting last")
	assert(_entry(&"file.new")["method"] == &"_menu_new_drawing")
	assert(_entry(&"file.open")["method"] == &"_menu_open_drawing")
	assert(_entry(&"file.save")["method"] == &"_menu_save_drawing")
	assert(_entry(&"file.save_as")["method"] == &"_menu_save_drawing_as")
	# Each of them needs the drawing to exist, and says so.
	assert(_entry(&"file.save")["needs"] == HudScript.NEEDS_DRAFT)


func test_save_is_only_available_when_there_is_something_to_save() -> void:
	# A greyed-out Save is how a menu answers "have I saved this?" without a word, and it is the
	# only entry in the bar that comes and goes with the state rather than with the scene.
	assert(_entry(&"file.save")["enabled_when"] == &"dirty")
	assert(HudScript.is_enabled(&"dirty", {"dirty": true}))
	assert(not HudScript.is_enabled(&"dirty", {"dirty": false}))
	assert(HudScript.is_enabled(&"", {}), "an entry that names no condition is available")
	assert(_entry(&"file.new").get("enabled_when", &"") == &"")


func test_the_recent_menu_is_empty_until_the_menu_fills_it() -> void:
	# The one part of the bar whose entries are not fixed: it is filled at build time from what the
	# store remembers, which is nothing until a drawing has been saved. Its static emptiness is the
	# point - a stale list in the plan would be a list that never changes.
	var recent: Dictionary = _entry(&"file.recent")
	assert(recent["kind"] == &"submenu")
	assert((recent["items"] as Array).is_empty())
	var dynamic := 0
	for entry: Dictionary in HudScript.menu_entries():
		if String(entry.get("id", "")).begins_with("file.recent."):
			dynamic += 1
	assert(dynamic == 0, "the recent entries are made, not declared")


func test_an_unknown_state_is_never_shown_as_on() -> void:
	# A checkable entry whose state nothing answers for would be a tick that never appears: it is
	# better to make that obvious here than to find it in the running program.
	assert(not HudScript.is_checked(&"invented", 1, {"invented": 1}))
	assert(not HudScript.is_checked(&"", null, {}))


func test_the_key_reference_quotes_the_strings_the_screen_shows() -> void:
	# The page is built from the hint lines and the drafting legend rather than written again, so
	# it cannot disagree with the corner of the screen it is quoting.
	var hud := HudScript.new()
	var text := hud.keys_text()
	assert(text.contains(HudScript.HINTS_GROUND))
	assert(text.contains(HudScript._hints_for(ViewController.ViewMode.PLAN_2D)))
	for row: String in HudScript.drafting_rows():
		assert(text.contains(row), "the reference has the legend row: %s" % row)
	assert(text.contains("Keys") or text.contains("Drawing"))
	assert(hud.keys_footer().contains(Engine.get_version_info()["string"]))
	hud.free()

# --- the ground the plants are judged against ----------------------------------------------


## The two selection bands are chosen from the Edit menu, and choosing one names the method that
## arms it with that mode.
func test_the_edit_menu_offers_both_selection_bands() -> void:
	var ids: Array[String] = []
	for entry: Dictionary in HudScript.items_for("Edit"):
		ids.append(String(entry.get("id", "")))
	assert(ids.has("edit.select_window"), "the Edit menu offers a window band")
	assert(ids.has("edit.select_crossing"), "and a crossing band")
	var window: Dictionary = _entry(&"edit.select_window")
	assert(String(window["method"]) == "_menu_select_mode")
	assert(StringName(window["state"]) == &"select_mode", "they are a set, checked against the mode")
	assert(StringName(window["value"]) == &"window")
	assert(StringName(_entry(&"edit.select_crossing")["value"]) == &"crossing")


## A selection mode is shown as chosen only while the band is actually in hand: a menu claiming a
## mode that is not on would be describing a tool nobody has.
func test_a_selection_mode_is_shown_as_chosen_only_while_the_band_is_out() -> void:
	var out: Dictionary = {
		"drawing": true, "tool": int(ToolScript.Kind.SELECT), "select_mode": &"crossing",
	}
	assert(HudScript.is_checked(&"select_mode", &"crossing", out), "the mode the band is in")
	assert(not HudScript.is_checked(&"select_mode", &"window", out), "and not the other one")
	var away: Dictionary = {
		"drawing": false, "tool": int(ToolScript.Kind.SELECT), "select_mode": &"crossing",
	}
	assert(not HudScript.is_checked(&"select_mode", &"crossing", away),
		"a mode is not on while the tools are put away")
	var other: Dictionary = {
		"drawing": true, "tool": int(ToolScript.Kind.LINE), "select_mode": &"crossing",
	}
	assert(not HudScript.is_checked(&"select_mode", &"crossing", other),
		"nor while another tool is out")


## Labelling the planting is reached from the Plant menu, and it names the method that writes it.
func test_the_plant_menu_offers_labelling_the_planting() -> void:
	var ids: Array[String] = []
	for entry: Dictionary in HudScript.items_for("Plant"):
		ids.append(String(entry.get("id", "")))
	assert(ids.has("plant.label"), "the Plant menu can label what is planted")
	var entry: Dictionary = _entry(&"plant.label")
	assert(String(entry["method"]) == "_menu_label_plants")


## A survey is a file, so it is reached from the File menu, and the entry names the method that
## reads the file and shows what was read.
func test_the_file_menu_offers_importing_a_survey() -> void:
	var ids: Array[String] = []
	for entry: Dictionary in HudScript.items_for("File"):
		ids.append(String(entry.get("id", "")))
	assert(ids.has("file.survey"), "the File menu can import a survey")
	var entry: Dictionary = _entry(&"file.survey")
	assert(String(entry["method"]) == "_menu_import_survey")
	assert(entry["needs"] == HudScript.NEEDS_DRAFT, "and it needs a drawing to import into")


## The coverage report is reached from the Site menu, and it names the method that shows it.
func test_the_site_menu_offers_the_site_report() -> void:
	var ids: Array[String] = []
	for entry: Dictionary in HudScript.items_for("Site"):
		ids.append(String(entry.get("id", "")))
	assert(ids.has("site.report"), "the Site menu can report what the drawing covers")
	var entry: Dictionary = _entry(&"site.report")
	assert(String(entry["method"]) == "_menu_site_report")


func test_the_site_menu_opens_the_ground_window_and_reports_on_it() -> void:
	# The ring around a plant being placed is the answer; the Site menu is the way to the question.
	# The site's conditions and the conditions of every area of the plan live in one window, because a
	# menu cannot hold an area: a bed under the eaves is a fact about the ground, and a list of four
	# site-wide choices has nowhere to put it.
	assert(_entry(&"site.ground")["kind"] == &"info", "the menu says what the ground is")
	assert(String(_entry(&"site.window")["method"]) == "_menu_ground_window")
	assert(String(_entry(&"site.read")["method"]) == "_menu_read_ground")
	assert(String(_entry(&"site.check")["method"]) == "_menu_check_planting")


func test_the_window_is_the_way_in_and_the_menu_only_reports() -> void:
	# Editing the ground moved into the window; what stayed is the menu's honesty about it - its info
	# line is written from the same map the window edits, so the two cannot disagree.
	var hud := HudScript.new()
	# A bare controller, freed by hand: a Node is not reference counted, and a leaked one is reported
	# as a resource still in use at exit.
	var controller: DraftController = ControllerScript.new()
	hud._draft = controller
	assert(hud.has_method("open_ground_window"), "the menu has something to open")
	assert(hud.has_method("close_ground_window"))
	assert(hud.has_method("_menu_ground_window"))
	assert(not hud.is_ground_window_open(), "and it is not open until it is asked for")
	hud.free()
	controller.free()


func test_a_value_that_has_been_through_a_file_is_still_the_value_it_was() -> void:
	# A number that has come back from a saved drawing is a float. Every ground control indexes its
	# dropdown by the stated value, so "is this the stated one" must not depend on which side of the
	# file the number came from - and the rule is asked of the model, not of a menu.
	assert(HudScript.is_checked(&"invented", 1, {"invented": 1}) == false)
	assert(HudScript.is_checked(&"mode", ViewController.ViewMode.OVERHEAD_3D, {"mode": 1}))
	assert(not HudScript.is_checked(&"mode", ViewController.ViewMode.PLAN_2D, {"mode": 1}))


func test_stating_the_ground_changes_the_drawing_and_leaves_the_old_map_alone() -> void:
	# The one thing that must not break: the map on the document is the map that is edited, and
	# `set_environment` tells "saved" from "already so" by comparing what it is given with what is
	# already there - so a map edited in place would always look unchanged, and the window would tick
	# and change nothing. (The window itself is driven in `tests/test_ground_window.gd`; this is the
	# document half of the contract.)
	var document: DraftDocument = DocumentScript.new()
	assert(document.environment.base.is_empty(), "a new drawing states nothing about the ground")
	var stated: ZoneMap = document.environment.copy()
	stated.base.with_stated("moisture", 2)
	assert(document.set_environment(stated), "the moisture is stated")
	assert(document.environment.base.moisture_level() == 2)
	assert(document.environment.zones.is_empty(), "and nothing else was invented")
	var again: ZoneMap = document.environment.copy()
	again.base.with_stated("soil", &"CLAY")
	document.set_environment(again)
	assert(document.environment.base.soil_name() == &"CLAY")
	assert(document.environment.base.moisture_level() == 2, "the moisture survives the soil")
	# Choosing "not stated" takes the statement back, and it is a change like any other.
	var back: ZoneMap = document.environment.copy()
	back.base.with_stated("moisture", TerrainProfile.no_value("moisture"))
	document.set_environment(back)
	assert(not document.environment.base.has("moisture"), "the moisture is unstated again")
	assert(document.environment.base.soil_name() == &"CLAY", "and the soil is untouched")
	# And each is one undo step, because it went through the document.
	assert(document.undo_last(), "the ground changes are undoable")
	assert(document.environment.base.has("moisture"), "which put the moisture back")


func test_the_estimate_menu_opens_the_estimate_window_and_reports_on_it() -> void:
	var hud := HudScript.new()
	assert(hud._estimate_window == null, "no window until there is a HUD to hold one")
	# The menu's own line, before anything has been taken off a plan: it is the desk's answer and not
	# a sentence the menu keeps to itself, so a menu and a window cannot disagree.
	var desk := DeskScript.new()
	assert(desk.describe().contains("no drawing"), desk.describe())
	assert(HudScript.estimate_items().size() >= 4, "the menu has the entries it promises")
	var ids: Array[String] = []
	for entry: Dictionary in HudScript.estimate_items():
		ids.append(String(entry["id"]))
	assert(ids.has("estimate.window"), str(ids))
	assert(ids.has("estimate.take_off"), str(ids))
	assert(ids.has("estimate.check"), str(ids))
	hud.free()
