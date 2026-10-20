extends Node
## The menu bar: its entries, the keys they advertise, and the methods they name.
##
## A menu is one of the few places a program can promise something without doing it - an entry
## that does nothing, or that names a key which is no longer bound. These are the tests that
## stand between the bar and that, and they read the bar the way it is built: as data.

const HudScript := preload("res://scripts/hud.gd")
const ToolScript := preload("res://scripts/draft/draft_tool.gd")
const TierScript := preload("res://scripts/vis/presentation_tier.gd")
const PlotScaleScript := preload("res://scripts/draft/plot_scale.gd")
const ControllerScript := preload("res://scripts/draft/draft_controller.gd")
const DocumentScript := preload("res://scripts/draft/draft_document.gd")

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
	var expected: Array[String] = ["File", "Edit", "View", "Draft", "Site", "Plant", "Present", "Help"]
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


func test_the_site_menu_asks_about_the_ground_in_the_sets_a_place_has() -> void:
	# The ring around a plant being placed is the answer; this menu is the question. Each set is
	# radios rather than a dialog, and each starts with "not stated".
	assert(_entry(&"site.ground")["kind"] == &"info", "the menu says what the ground is")
	assert(_entry(&"site.read")["method"] == &"_menu_read_ground")
	assert(_entry(&"site.check")["method"] == &"_menu_check_planting")
	var wanted := {
		&"site.sun": 4, &"site.moisture": 4, &"site.soil": 6, &"site.zone": 14,
	}
	for id: StringName in wanted:
		var entry: Dictionary = _entry(id)
		assert(entry["kind"] == &"submenu", "%s is a set of choices" % id)
		var items: Array = entry["items"]
		assert(items.size() == int(wanted[id]), "%s offers %d choices" % [id, items.size()])
		assert(String(items[0]["label"]) == "not stated", "%s can be unstated again" % id)
		for item: Dictionary in items:
			assert(item["kind"] == &"radio", "%s is chosen rather than toggled" % id)
			assert(String(item["method"]) == "_menu_set_ground", "%s states one thing" % id)


func test_the_missing_value_is_a_different_value_in_every_set() -> void:
	# The trap this whole menu is built around: **zero is a real moisture level** (low water), so it
	# cannot be the value that means "nothing stated" - and it *is* that value for light and zone,
	# where 0 is not a level anybody can state (the levels are 1, 2 and 4; zones start at 1).
	assert(HudScript.ground_value_stated("moisture", 0), "and 0 IS one: low water is a real level")
	assert(HudScript.ground_value_stated("moisture", 1), "medium water is a statement")
	assert(HudScript.ground_value_stated("moisture", 2), "and so is high water")
	assert(not HudScript.ground_value_stated("moisture", -1), "so the missing one is -1, not 0")
	assert(int(HudScript.no_ground_value("moisture")) == -1, "which is what the menu offers")
	assert(not HudScript.ground_value_stated("sun", 0), "no light level is 0")
	assert(HudScript.ground_value_stated("sun", 1), "full sun is 1")
	assert(HudScript.ground_value_stated("sun", 4), "full shade is 4")
	assert(not HudScript.ground_value_stated("soil", &""), "no soil is the empty name")
	assert(HudScript.ground_value_stated("soil", &"LOAM"), "and loam is a soil")
	assert(not HudScript.ground_value_stated("zone", 0), "no zone is 0")
	assert(HudScript.ground_value_stated("zone", 1), "zone 1 is the coldest zone there is")
	# Every set's missing value is the value its own "not stated" radio carries, or that radio would
	# be a choice that un-states something by stating it.
	for key: String in ["sun", "moisture", "soil", "zone"]:
		var entry: Dictionary = _entry(StringName("site.%s" % key))
		var first: Dictionary = (entry["items"] as Array)[0]
		assert(first["value"] == HudScript.no_ground_value(key), "%s: %s" % [key, str(first["value"])])
		assert(not HudScript.ground_value_stated(key, first["value"]), "%s: the radio un-states" % key)


func test_the_ground_radios_show_the_stated_value_and_only_that() -> void:
	var world := {
		"ground.sun": 4, "ground.moisture": 0, "ground.soil": &"LOAM", "ground.zone": 0,
	}
	assert(HudScript.is_checked(&"ground.sun", 4, world), "the stated light is the one that is on")
	assert(not HudScript.is_checked(&"ground.sun", 1, world))
	assert(HudScript.is_checked(&"ground.moisture", 0, world), "and the stated moisture")
	assert(not HudScript.is_checked(&"ground.moisture", -1, world), "not the unstated one")
	assert(HudScript.is_checked(&"ground.soil", &"LOAM", world))
	assert(not HudScript.is_checked(&"ground.soil", &"CLAY", world))
	assert(HudScript.is_checked(&"ground.zone", 0, world), "a zone nobody stated is not stated")
	# A number that has been through a file is a float, and "is this the stated one" must not depend
	# on which side of the file it came from.
	assert(HudScript.is_checked(&"ground.sun", 4, {"ground.sun": 4.0}), "4.0 is the level 4")
	assert(HudScript.is_checked(&"ground.moisture", 2, {"ground.moisture": 2.0}))
	assert(not HudScript.is_checked(&"ground.sun", 4, {"ground.sun": 2}))


func test_stating_the_ground_changes_the_drawing_and_leaves_the_old_map_alone() -> void:
	# The handler the radio entries call. It is tested here rather than only in the running program
	# because of the one thing it must not do: the map it is handed is the map on the document, and
	# `set_environment` tells "saved" from "already so" by comparing what it is given with what is
	# there - so an object edited in place would always look unchanged, and the menu would tick and
	# change nothing.
	var controller: DraftController = ControllerScript.new()
	var hud := HudScript.new()
	hud._draft = controller
	# A bare controller has run no `_ready`, so its document is made here: the handler reaches the
	# document through the controller and through nothing else.
	var document: DraftDocument = DocumentScript.new()
	controller.document = document
	assert(document.environment.base.is_empty(), "a new drawing states nothing about the ground")
	hud._menu_set_ground({"state": &"ground.moisture", "value": 2})
	assert(document.environment.base.moisture_level() == 2, "the moisture is stated")
	assert(document.environment.zones.is_empty(), "and nothing else was invented")
	hud._menu_set_ground({"state": &"ground.soil", "value": &"CLAY"})
	assert(document.environment.base.soil_name() == &"CLAY")
	assert(document.environment.base.moisture_level() == 2, "the moisture survives the soil")
	# Choosing "not stated" takes the statement back, and it is a change like any other.
	hud._menu_set_ground({"state": &"ground.moisture", "value": HudScript.no_ground_value("moisture")})
	assert(not document.environment.base.has("moisture"), "the moisture is unstated again")
	assert(document.environment.base.soil_name() == &"CLAY", "and the soil is untouched")
	# And it is one undo step, because it went through the document.
	assert(document.undo_last(), "the ground changes are undoable")
	assert(document.environment.base.has("moisture"), "which put the moisture back")
	hud.free()
	controller.free()
