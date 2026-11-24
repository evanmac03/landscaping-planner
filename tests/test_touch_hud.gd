extends Node
## The furniture a finger gets and a desk does not: the row of controls that stands inside the top bar where
## the fourteen menus stand, and the dock along the foot of the screen.
##
## **These tests hold the two rules that keep that furniture from becoming a second program.** Every tab and
## every control it offers must be a door to something that already exists - the dock's tools are the palette's
## own buttons, filtered, and the drawer is the menu plan gathered rather than worded again - because a dock
## with its own list of tools would be exactly the second vocabulary this project works hardest to avoid, and
## the two would drift the first time a tool was added to one of them.
##
## The third rule is about the two shipping faults a phone found: a development addon that is not part of the
## program must not be named by anything the program ships, which is what put `addons/tree_sitter_gd/` inside a
## build whose device cannot load it, and what an autoload of `addons/crabbyconsole/` did on every launch.

const HudScript := preload("res://scripts/hud.gd")
const PalettePanelScript := preload("res://scripts/palette_panel.gd")
const DraftToolScript := preload("res://scripts/draft/draft_tool.gd")
const MenuPlanScript := preload("res://scripts/menu_bar_plan.gd")
const ToolPaletteScript := preload("res://scripts/tool_palette.gd")
const PhoneHudScript := preload("res://scripts/phone_hud.gd")

## The directories the program itself ships: what is named in here reaches a build.
const SHIPPED: Array[String] = ["res://scripts", "res://scenes"]


## **The two drawing tabs are a partition of the palette's own list, and this is the rule that says so.** Every
## tool the palette builds a button for is on exactly one of them: none is lost, none is offered twice, and
## neither tab holds a tool the palette does not have - which is what makes the dock a view of one list rather
## than a second table of tools.
func test_the_two_tool_tabs_offer_every_tool_exactly_once() -> void:
	var kinds: Array = []
	for pair: Array in PalettePanelScript.DRAFTING_TOOLS:
		kinds.append(int(pair[2]))
	var in_draw: int = 0
	var in_dim: int = 0
	for kind: int in kinds:
		var is_a_dimension: bool = HudScript.DIMENSION_KINDS.has(kind)
		if is_a_dimension:
			in_dim += 1
		else:
			in_draw += 1
	assert(
		in_draw + in_dim == kinds.size(),
		"every tool is on one of the two tabs: %d + %d against %d tools" % [in_draw, in_dim, kinds.size()],
	)
	assert(in_draw > 0, "and the drawing tab is not empty: %d tools" % in_draw)
	assert(in_dim > 0, "and neither is the dimensions tab: %d tools" % in_dim)


## The four kinds the dimensions tab claims are the four the tool module actually draws dimensions with, read
## off its own enum rather than counted here: a number written into the HUD would be a second statement of which
## tool is a dimension, free to drift from the one the buttons are built from.
func test_the_dimensions_tab_names_the_kinds_the_tool_module_does() -> void:
	assert(
		HudScript.DIMENSION_KINDS.size() == 4,
		"there are four dimensions in this program: %d named" % HudScript.DIMENSION_KINDS.size(),
	)
	for kind: int in HudScript.DIMENSION_KINDS:
		assert(
			DraftToolScript.Kind.keys().has(DraftToolScript.Kind.keys()[kind]),
			"the kind is one the tool module has: %d" % kind,
		)
		var found: bool = false
		for pair: Array in PalettePanelScript.DRAFTING_TOOLS:
			if int(pair[2]) == kind:
				found = true
		assert(found, "and it is a tool the palette draws a button for: %d" % kind)


## **A tab with no words on it is a tab nobody can guess at.** Every name in the row opens something, and each
## says what, in its own sentence - so two tabs cannot come to describe the same thing by accident.
func test_every_tab_says_what_it_opens() -> void:
	var hud: CanvasLayer = HudScript.new()
	var said: Dictionary = { }
	for tab: String in HudScript.TOUCH_TABS:
		var words: String = hud.call(&"_touch_tab_tooltip", tab)
		assert(not words.is_empty(), "the %s tab says what it opens" % tab)
		assert(not said.has(words), "and no two tabs say the same thing: %s" % words)
		said[words] = true
	hud.free()


## The dock's own row of tabs is the five the HUD offers, and the two that are doors rather than groups are in
## it: the plant library and the drawer, which are reached without touching the strip at all.
func test_the_dock_has_a_tab_for_the_library_and_one_for_the_menu() -> void:
	assert(HudScript.TOUCH_TABS.size() >= 4, "the dock carries a row of tabs: %d" % HudScript.TOUCH_TABS.size())
	assert(HudScript.TOUCH_TABS.has("Plants"), "the plant library is one of them: %s" % str(HudScript.TOUCH_TABS))
	assert(HudScript.TOUCH_TABS.has("More"), "and so is the rest of the menu: %s" % str(HudScript.TOUCH_TABS))


## **The drawer gathers the plan; it does not word it again.** One submenu per menu, named by that menu's own
## title, holding that menu's own items, with ids of its own so two submenus cannot collide. Every word and
## every action inside them is still the plan's, which is what makes an entry added to the plan appear in the
## drawer and in the bar in one edit.
func test_the_drawer_gathers_the_plan_without_wording_any_of_it() -> void:
	var plan: Array[Dictionary] = MenuPlanScript.menu_plan()
	assert(plan.size() >= 10, "the program's plan is a real one: %d menus" % plan.size())
	var gathered: Array[Dictionary] = HudScript.touch_drawer_plan(plan)
	assert(gathered.size() == plan.size(), "one submenu per menu: %d against %d" % [gathered.size(), plan.size()])
	var seen: Dictionary = { }
	for index in gathered.size():
		var one: Dictionary = gathered[index]
		var menu: Dictionary = plan[index]
		assert(String(one["label"]) == String(menu["title"]), "named by the menu's own title")
		assert(Array(one["items"]) == Array(menu["items"]), "and holding the menu's own items, untouched")
		assert(one["kind"] == &"submenu", "each is a submenu rather than a list of everything at once")
		assert(not seen.has(String(one["id"])), "and no two carry one id: %s" % str(one["id"]))
		seen[one["id"]] = true


## The furniture is in the scene and **put away in it**, so a computer draws exactly what it always drew: the
## touch row, the dock and the strip all arrive hidden, and it is the HUD that shows them where a finger is.
func test_the_touch_furniture_is_put_away_in_the_scene() -> void:
	var scene: PackedScene = load("res://scenes/ui/hud.tscn")
	assert(scene != null, "the HUD's scene is where the HUD's own name resolves")
	var board: Node = scene.instantiate()
	for path: String in [
		^"Root/TopBar/Row/TouchRow",
		^"Root/TouchDock",
		^"Root/TouchDock/Column/ToolStrip",
		^"Root/TouchSheet",
	]:
		var control: Control = board.get_node_or_null(path) as Control
		assert(control != null, "the scene carries %s" % path)
		if control != null:
			assert(not control.visible, "and it is put away there, so a desk is unchanged: %s" % path)
	# The plate each of them wears is the scene's own, which is the one thing `ChromeStyle` can derive the look
	# of this program's chrome from - a plate left off would force it onto constants of its own.
	var dock: Control = board.get_node_or_null(^"Root/TouchDock") as Control
	var strip: Control = board.get_node_or_null(^"Root/TouchDock/Column/ToolStrip") as Control
	var sheet: Control = board.get_node_or_null(^"Root/TouchSheet") as Control
	assert(dock.get_theme_stylebox(&"panel") is StyleBoxFlat, "the dock carries the scene's own plate")
	assert(strip.get_theme_stylebox(&"panel") is StyleBoxFlat, "and so does the strip")
	assert(sheet.get_theme_stylebox(&"panel") is StyleBoxFlat, "and the sheet, which is derived from the same")
	# A sheet is titled and closable in the scene, so the two things it needs to be a panel a person can put
	# away are the scene's own and not something built at run time on one screen.
	var title: Node = board.get_node_or_null(^"Root/TouchSheet/Column/Header/Title")
	var shut: Node = board.get_node_or_null(^"Root/TouchSheet/Column/Header/Close")
	assert(title is Label, "the sheet carries a title")
	assert(shut is Button, "and a way out of it")
	board.free()


## **A development addon must not be named by anything the program ships.** `addons/tree_sitter_gd/` is a parser
## for the editor's own tooling and `addons/crabbyconsole/` is a desk's console: neither is part of the program,
## and both were found on a phone rather than at a desk - the parser shipped into a build whose device has no
## library for it, and the console's autoload logged on every launch. Whatever reaches `scripts/` or `scenes/`
## reaches a build, so neither name may appear there.
func test_nothing_the_program_ships_names_a_development_addon() -> void:
	var forbidden: Array[String] = ["tree_sitter_gd", "CrabbyConsole", "crabbyconsole", "godot_mcp_toolkit"]
	var found: Array[String] = []
	for root: String in SHIPPED:
		for path: String in _files_under(root):
			var text: String = FileAccess.get_file_as_string(path)
			for word: String in forbidden:
				if text.contains(word):
					found.append("%s names %s" % [path, word])
	assert(found.is_empty(), "nothing the program ships names a development addon:\n  " + "\n  ".join(found))


## **The strip gives every tool a square cell sized by the device's own floor, and a floor is a *minimum*.**
## A tool whose words are longer than the cell keeps them - a minimum only ever hands a control more room - so a
## long tool's name survives beside a short one instead of being cut to make the row tidy. Cutting a name here
## would leave two tools a person cannot tell apart.
func test_the_strip_gives_every_tool_a_square_cell_of_the_devices_own_row() -> void:
	var strip := HBoxContainer.new()
	for words: String in ["Rectangle", "Circle", "Polyline"]:
		var button := Button.new()
		button.text = words
		strip.add_child(button)
	var drawn_at := 0.91
	var density := 450.0
	ToolPaletteScript.fit_a_strip(strip, drawn_at, density)
	var want: float = PhoneHudScript.row_height(drawn_at, density)
	assert(want > 0.0, "the device states a row a thumb can hit: %s" % str(want))
	for child: Node in strip.get_children():
		var box: Control = child as Control
		assert(
			is_equal_approx(box.custom_minimum_size.x, want) and is_equal_approx(box.custom_minimum_size.y, want),
			"a square cell of that row: %s against %s" % [str(box.custom_minimum_size), str(want)],
		)
	assert(
		not is_equal_approx(PhoneHudScript.row_height(0.0, 0.0), want),
		"and the floor really is the device's, not a number this laid out anyway",
	)
	strip.free()


## **The tab in hand is the only one shown down.** The row is the only thing that says which group the strip is
## showing - the tools in the strip carry their own names and none of them names a group - so a row left with two
## tabs down, or with one down after the strip was put away, tells a person something untrue about the screen.
func test_the_tab_in_hand_is_the_only_one_shown_down() -> void:
	var hud: CanvasLayer = HudScript.new()
	var row := HBoxContainer.new()
	for name: String in ["Draw", "Dim", "Edit", "Plants", "More"]:
		var button := Button.new()
		button.text = name
		button.toggle_mode = true
		row.add_child(button)
	hud.set(&"touch_tabs", row)
	hud.set(&"_touch_tab", "Dim")
	hud.call(&"_mark_the_touch_tab")
	assert(_tabs_down(row) == PackedStringArray(["Dim"]), "one tab is down, the one in hand: %s" % str(_tabs_down(row)))
	# An empty hand - the strip put away, or a sheet closed - leaves the whole row up.
	hud.set(&"_touch_tab", "")
	hud.call(&"_mark_the_touch_tab")
	assert(_tabs_down(row).is_empty(), "and an empty hand stands every tab up: %s" % str(_tabs_down(row)))
	# The tabs are told rather than left to the engine's own toggling, so a row that came up with two down is
	# put back by the same call - which is the shape the fault would take.
	(row.get_child(0) as Button).button_pressed = true
	(row.get_child(2) as Button).button_pressed = true
	hud.set(&"_touch_tab", "Edit")
	hud.call(&"_mark_the_touch_tab")
	assert(_tabs_down(row) == PackedStringArray(["Edit"]), "two down is put back to one: %s" % str(_tabs_down(row)))
	row.free()
	hud.free()


## **A panel stands along the foot of the screen, clear of whatever is under it.** The board is what a person is
## working on, so a panel opened over it belongs at the bottom of the screen rather than in the middle of the work
## - and it must not reach down over the dock's own tabs, which are the controls that opened it. That clearance is
## the caller's figure and not this rule's, which is why it is handed in: the dock's height is its own contents'.
func test_a_panel_stands_along_the_foot_and_clear_of_what_is_below_it() -> void:
	var wrapper := Control.new()
	HudScript.settle_a_panel_on_the_foot(wrapper, 20.0, 240.0, 380.0)
	assert(
		is_equal_approx(wrapper.anchor_top, 1.0) and is_equal_approx(wrapper.anchor_bottom, 1.0),
		"the wrapper is anchored to the foot of the room: %s" % str([wrapper.anchor_top, wrapper.anchor_bottom]),
	)
	assert(
		is_equal_approx(wrapper.offset_left, 20.0) and is_equal_approx(wrapper.offset_right, -20.0),
		"and stands inside the margins a thumb needs: %s" % str([wrapper.offset_left, wrapper.offset_right]),
	)
	assert(
		is_equal_approx(wrapper.offset_bottom, -240.0),
		"clear of everything below it: %s" % str(wrapper.offset_bottom),
	)
	assert(
		is_equal_approx(wrapper.offset_top, -620.0),
		"and as tall as the caller states: %s" % str(wrapper.offset_top),
	)
	assert(
		-wrapper.offset_top > 0.0 and -wrapper.offset_top < 1000.0,
		"so it is a band along the foot and never the whole room",
	)
	wrapper.free()


## **The six panels a desk centres over the board, and a panel that was never built is skipped rather than worked
## around.** Three of them want a drawing, so a HUD with no drawing has three of them missing - and a list of node
## paths would be three missing nodes to guard at every use.
func test_the_overlay_panels_are_the_ones_the_hud_built() -> void:
	var every_one: Array[StringName] = [
		&"_keys_panel",
		&"_site_report_panel",
		&"_dxf_panel",
		&"_hatch_page",
		&"_water_page",
		&"_light_page",
	]
	var hud: CanvasLayer = HudScript.new()
	var built: Array[Control] = []
	for name: StringName in every_one:
		var wrapper := Control.new()
		wrapper.name = String(name).trim_prefix("_")
		hud.set(name, wrapper)
		built.append(wrapper)
	assert(
		hud.call(&"_the_overlay_panels").size() == every_one.size(),
		"all six are the panels this HUD holds: %d" % hud.call(&"_the_overlay_panels").size(),
	)
	hud.set(every_one[0], null)
	assert(
		hud.call(&"_the_overlay_panels").size() == every_one.size() - 1,
		"and one that was never built is one fewer, not a missing node: %d" % hud.call(&"_the_overlay_panels").size(),
	)
	for wrapper: Control in built:
		wrapper.free()
	hud.free()


## Which of a row's buttons are down, in the row's own order.
func _tabs_down(row: Container) -> PackedStringArray:
	var down := PackedStringArray()
	for child: Node in row.get_children():
		if child is Button and (child as Button).button_pressed:
			down.append((child as Button).text)
	return down


## Every file under a directory, walked rather than listed: a list of the files to check is a second statement
## of what the program is made of, and it would go stale the moment a file was added.
func _files_under(root: String) -> PackedStringArray:
	var out := PackedStringArray()
	var dir: DirAccess = DirAccess.open(root)
	if dir == null:
		return out
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while not name.is_empty():
		var path: String = root.path_join(name)
		if dir.current_is_dir():
			out.append_array(_files_under(path))
		elif name.ends_with(".gd") or name.ends_with(".tscn"):
			out.append(path)
		name = dir.get_next()
	dir.list_dir_end()
	return out


## A phone arrangement puts the desk's own surfaces away, and **hides them rather than showing them**.
##
## **The first half is the fault this was written for.** The presentation panel stood at `1276,70 .. 1588,88` - inside
## the top bar's plate (`12,12 .. 1588,128`) and straight across `Ground view` (`1208,0 .. 1544,97`) - so the 2D
## workspace drew a ghost over two of the bar's buttons, and nothing caught it: the panel is not one of `hud.gd`'s
## `_the_overlay_panels`, so no rule places it, and it is not a drawn surface the probe's own rules cover.
##
## **The second half is what stops the cure becoming a fault of its own.** A panel the program itself has put away
## must not be brought back up by a change of arrangement, or a desk's palette would appear on a phone - which is why
## this module hides and never shows.
func test_a_phone_arrangement_hides_the_desks_own_surfaces() -> void:
	var furniture: TouchFurniture = TouchFurniture.new()
	var up: PanelContainer = PanelContainer.new()
	up.visible = true
	var down: PanelContainer = PanelContainer.new()
	down.visible = false
	furniture.desk_panels = [up, down]
	# A finger: the desk's own surfaces go, and a surface already away is left away.
	furniture.on_a_finger = true
	furniture.show_the_furniture(true)
	assert(not up.visible, "a desk panel left standing over a phone's bar")
	assert(not down.visible, "a panel the program put away is still away under a finger")
	# A desk: what was up is given back, and what was down is not resurrected.
	furniture.on_a_finger = false
	furniture.show_the_furniture(true)
	assert(up.visible, "a desk arrangement gives the panel back")
	assert(not down.visible, "and does not bring back what it never showed")
	up.free()
	down.free()
