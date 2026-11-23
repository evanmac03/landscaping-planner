class_name TouchFurniture
extends RefCounted
## The phone's furniture for the HUD - the dock, its tabs and the strip between them, the sheet a tab opens
## into, and the drawer under `More` - held away from the HUD itself so that one arrangement is stated once and
## can be stood up by something that is not the running program.
##
## **Why it is its own module rather than a corner of `hud.gd`.** The pieces below are the only part of the HUD
## that is *placed by hand* rather than left to the engine's layout: a dock pinned to the foot, a sheet taking a
## share of the room, a strip borrowed from the drawing palette and handed back. Everything such a thing needs
## is a node and a number, both of which can be handed in - which is what lets a development view build the real
## furniture in an editor, where the HUD's own script has no instance and none of its members exist to be
## assigned. The members are named here rather than reached for: whoever holds them says so.
##
## The HUD keeps **doors of the same name** for every constant and every method here, so the callers that reach
## into it - `tests/test_touch_hud.gd`, `tools/console.gd` (which reads `TOUCH_TABS` out of the script's own
## constant map, by name), `tools/hud_layout_check.gd` and `tools/touch_hud_workspace.gd` - keep working
## untouched. Nothing in here words a size, a look or a name a second time.

const DraftToolScript := preload("res://scripts/draft/draft_tool.gd")

## The row of tabs along the dock, in the order a thumb meets them. Five, and each is a door to something the
## program already has: the drawing tools split by what they do, the plant library, and the rest of the menu.
const TOUCH_TABS: Array[String] = ["Draw", "Dim", "Edit", "Plants", "More"]

## The four dimension kinds, read off the tool module's own enum rather than written down as numbers: they are
## what tells the `Dim` tab's tools from the `Draw` tab's, and a number copied here would be a second statement
## of which tool draws a dimension, free to drift from the one the palette builds its own buttons from.
const DIMENSION_KINDS: Array = [
	DraftToolScript.Kind.DIMENSION,
	DraftToolScript.Kind.DIMENSION_LINEAR,
	DraftToolScript.Kind.DIMENSION_RADIUS,
	DraftToolScript.Kind.DIMENSION_ANGULAR,
]

## How much of the room a sheet takes. A share of the room's own height rather than a number of pixels, so the
## same plate is right on any screen - and the board keeps the rest, which is the whole reason a sheet stands
## over the drawing instead of replacing it.
const SHEET_OF_THE_ROOM := 0.45

## The palette's own table of drawing tools, because which tab a tool belongs in is a fact about the tools.
const PalettePanelScript := preload("res://scripts/palette_panel.gd")


## Which of the palette's drawing tools a tab wants, as **indices** into the palette's own list.
##
## The split is the whole of the `Draw` and `Dim` tabs: a tool that draws a dimension is offered in `Dim` and a
## tool that does not is offered in `Draw`, and nothing is offered in both. The indices rather than the buttons,
## so that the caller says where a button comes from - this module never reaches for a node.
##
## `Edit` is deliberately not answered here: its buttons are a **different list** on the palette rather than a
## selection of this one, so the HUD asks the palette for them directly.
static func tool_indices_for_a_tab(tab: String) -> Array[int]:
	var wanted: Array[int] = []
	for index in PalettePanelScript.DRAFTING_TOOLS.size():
		var kind: int = int(PalettePanelScript.DRAFTING_TOOLS[index][2])
		var is_a_dimension: bool = DIMENSION_KINDS.has(kind)
		if (tab == "Dim" and is_a_dimension) or (tab == "Draw" and not is_a_dimension):
			wanted.append(index)
	return wanted


## The menu plan gathered as the drawer's own submenus: one per menu, named by that menu's own title, holding
## that menu's own items, with ids of its own so two of them cannot collide.
##
## **It gathers; it does not word anything again.** Every word and every action is still the plan's, which is
## what makes an entry added to the plan appear in the drawer and in the bar in one edit.
static func drawer_plan(plan: Array[Dictionary]) -> Array[Dictionary]:
	var gathered: Array[Dictionary] = []
	for index in plan.size():
		var menu: Dictionary = plan[index]
		gathered.append(
			{
				"kind": &"submenu",
				"id": "drawer.%d" % index,
				"label": String(menu["title"]),
				"items": Array(menu.get("items", [])),
			}
		)
	return gathered


## The look the plates are borrowed from, and the device floors a control is built to. Both are modules of
## statics, which is the point: nothing below needs a HUD, so a view that has none can still build the furniture.
const ChromeStyleScript := preload("res://scripts/chrome_style.gd")
const PhoneHudScript := preload("res://scripts/phone_hud.gd")

## The palette's own fitting of a strip of borrowed buttons, which is what lays the strip out for a finger.
const ToolPaletteScript := preload("res://scripts/tool_palette.gd")


# --- what it is given, and what it connects -----------------------------------------------------------------
#
# A builder that reached for the HUD's own members could only ever run inside a running HUD. Named properties
# can be handed in by anything - a running program, a test, or a development view in an editor, where the HUD's
# own script has no instance and none of its members exist to be assigned.

## The row of controls the bar carries on a phone, and the dock's own parts.
var row: HBoxContainer = null
var dock: PanelContainer = null
var strip: PanelContainer = null
var strip_row: HBoxContainer = null
var tabs: HBoxContainer = null

## The sheet a tab opens into, and the control that closes it.
var sheet: PanelContainer = null
var sheet_close: Button = null

## The one control in the scene wearing the bar's plate, from which every other pane here is derived.
var top_bar: PanelContainer = null

## The window the device's scale and dots-per-inch are read from, as `get_window()` would give it.
var app_window: Window = null

## The pane the drafting aids are drawn on, so they can be stood clear of the dock. **The aids are drawn behind
## everything else and anchored to the bottom-right corner at fixed offsets**, knowing nothing about what stands
## there - which is right, because a pane that read the dock's own rectangle could not be `@tool` and edited
## against. Measured on the A16W's own specs the dock's 285 px put the north arrow over its own `More` tab.
var overlay: HudOverlay = null

## The dots-per-inch the furniture was built at, captured by `build` while the device's own arrangement is
## certainly the one standing, and read back by `fit_the_strip` on the frame after. It exists because a caller
## may state a density for the length of the build - a development view does, so that a desk's 96 does not make
## every control a fifth of the height a thumb needs - and a fitting that asked the machine again would then
## measure the buttons it had just laid out against the wrong screen.
var built_at: float = 0.0

## A device the caller states for this furniture, so a view can stand a phone's arrangement up on a desk.
##
## **Handed over rather than read from a global, and that is what makes the development view match F6.** A script
## loaded in an editor without `@tool` is a **separate copy of itself, statics included**, so a density written by
## `PhoneHud.force_density` from a tool script is not necessarily the density a plain script reads back afterwards.
## Measured: the 2D workspace laid its bar out at this desk's 31 px with the theme's own 16 px type while the very
## same scene run with F6 came out at the phone's 97 px and 41 px, and every door between them was working. **A
## number handed over cannot be read from the wrong copy of anything.**
##
## 0 means "ask the machine", which is what a running program does: the HUD states nothing, so the device's own
## density and its window's own scale are what a real phone's furniture is made from.
var stated_density: float = 0.0
var stated_scale: float = 0.0

## How many buttons have been dressed, counted rather than assumed.
##
## **This is the number that tells "it never built" apart from "it built and produced nothing"**, and those two need
## opposite repairs. Measured, an editor left its bar at the desk's 31 px while the run came out at the phone's 97 -
## and `dress_the_bar_for_a_finger` has no guard on rows at all, so a `build` that reached it *must* have dressed
## those buttons. Either it was never reached or the dressing came out zero; a count answers which, where reading the
## code could not. It is deliberately not reset by `build`, so the second build in a session is as countable as the
## first.
var dressings: int = 0

## What the most recent dressing came out as, and the two numbers it came out of - in words, recorded at the moment
## of use.
##
## **The instrument that ends an argument three theories lost.** The count proved `build` reached the dressing; the
## reading beside it stated a density of 450 and a scale of 1.000; and the row still measured 0.0 px. Reading a value
## *afterwards* answers a different question from what was *used*, so the pair is written down where it is used.
var last_dressing: String = ""

## The clearance the aids last stood at, or `-1.0` before any answer. It exists because **a panel placed
## zero-height grows upward from its contents**, so the first read is taken while the dock is still growing and
## answers a height it no longer has: measured, the clearance came out 187 px where the dock needed 295, and the
## scale bar stayed drawn across the strip. The frame that answers the same figure twice is the one that stops.
var _aids_clearance: float = -1.0

## What each control does, and **an empty `Callable` is allowed: it is the honest door for a view with nothing
## to run.** The button is built, sized and dressed; it simply presses nothing. A running program passes all six.
var drawer_door: Callable = Callable()
var layer_door: Callable = Callable()
var view_door: Callable = Callable()
var find_door: Callable = Callable()
var tab_door: Callable = Callable()
var close_door: Callable = Callable()


## Stand the furniture up: the row, the tabs, the plates, and the sheet's own close.
func build() -> void:
	if row == null or dock == null or tabs == null or strip == null:
		return
	# **The density is read here, at the one moment it is certainly the device's.** Everything this file builds
	# asks `PhoneHud` for its size, and `build` is called inside whatever density the device's own arrangement
	# states - so the number is captured rather than asked for again later, when a caller that stated a density
	# for the length of the build has put its machine's own back.
	built_at = density_for_a_size()
	build_the_row()
	build_the_tabs()
	apply_the_plates()
	# **The sheet's Close is a scene node, so nothing that builds a button ever touched it.** Measured on the
	# A16W's own specs it came out 50x31 - a desk's row - on the only way out of the plant sheet by thumb, while
	# the four words beside it in the bar came out 98 px. One file dressed what it *built* and left what it was
	# *given* alone.
	if sheet_close != null:
		dress_for_a_finger(sheet_close)
		if close_door.is_valid() and not sheet_close.pressed.is_connected(close_door):
			sheet_close.pressed.connect(close_door)
	# **Every button the bar carries, not only the four this file built.** The scene's own `3D view`, `Fit` and
	# `Ground view` stand *beside* the row this file fills rather than inside it, so a walk from the row alone
	# dresses the four words and reports the bar done. Measured on the A16W's own specs those three came out 31 px
	# tall with `Fit` 28 px across, against a bar row of 98 - and the report named all three.
	dress_the_bar_for_a_finger()


## The four controls the top bar carries on a phone, where a desk carries fourteen menus: the drawer, the layer
## the next shape is drawn on, the view, and the command palette.
##
## They are **words rather than the glyphs the shape of this furniture suggests**, and that is measured rather
## than chosen: this engine draws no glyph the theme's own font does not hold, and the two that read best on
## paper - a hamburger and a magnifier - are in none of the fonts a build carries. A button wearing an empty box
## says nothing at all, so each of these says what it does.
func build_the_row() -> void:
	if row == null or row.get_child_count() > 0:
		return
	row.add_child(a_button("Menu", "Everything the menus hold", drawer_door))
	row.add_child(a_button("Layer", "The layer the next shape is drawn on", layer_door))
	row.add_child(a_button("View", "The 2D plan, the 3D view and the ground", view_door))
	row.add_child(a_button("Find", "Find a command by its name", find_door))


## Dress every button the bar carries for a finger - **the ones the scene supplied as well as the ones built here**.
##
## The walk starts at the row's *parent* rather than at `row` itself, and that is the whole point of it: the bar's
## own `3D view`, `Fit` and `Ground view` stand **beside** the row this file fills rather than inside it, so a walk
## from `row` alone would dress the four words and report the bar finished. Which control stands where is the
## scene's business; what a finger meets on it is this file's.
func dress_the_bar_for_a_finger() -> void:
	if row == null:
		return
	var bar: Node = row.get_parent()
	if bar == null:
		return
	for node: Node in _every_control_under(bar):
		var button: Button = node as Button
		if button != null:
			dress_for_a_finger(button)


## Every control under a node, the node itself excluded. **The walk goes down**, which is the point: what a finger
## meets is rarely the node a file believes it owns.
func _every_control_under(root: Node) -> Array[Node]:
	var out: Array[Node] = []
	for child: Node in root.get_children():
		out.append(child)
		out.append_array(_every_control_under(child))
	return out


## One button of the touch furniture, sized by the same two floors every other control on a device is sized by.
##
## **The height is `PhoneHud.row_height`, read rather than restated**, so a control built here and a palette
## fitted there cannot come out at two different heights on one screen. A button taller than its own row is what
## puts a control's middle inside a band the device keeps, which is a fault this project has measured twice.
##
## A door that is not valid leaves the button unconnected rather than refused: a view with nothing to run still
## wants to see the size and the words of what a finger would be offered.
func a_button(words: String, tooltip: String, door: Callable) -> Button:
	var button := Button.new()
	button.text = words
	button.tooltip_text = tooltip
	if door.is_valid():
		button.pressed.connect(door)
	dress_for_a_finger(button)
	return button


## A button dressed as a finger's target - **the one place any button on a device is dressed**, the scene's own
## included, which is the fault this exists to close: a file that only dressed what it *built* left every control
## it was handed at whatever size the scene gave it.
##
## The floor is a square of `PhoneHud.row_height`, read rather than restated: the words may want more width and a
## `Control` grows for them, but no target a finger meets is narrower than the row it stands in - the sheet's Close
## came out 50 px wide on a 1080 px glass. The height is asked of `PhoneHud` so a control built here and a palette
## fitted elsewhere cannot come out at two heights on one screen.
##
## The focus is off every button the HUD draws, and for the reason the palette's own note keeps: Godot hands Tab to
## focus navigation the moment a Control holds it, and a focused button swallows the keys a drawing tool is driven
## by.
func dress_for_a_finger(button: Button) -> void:
	dressings += 1
	# **The pair this dressing actually used, kept as words.** The count said 23 buttons were dressed; the reading
	# beside it said the device was 450 dpi at a canvas scale of 1.000; and the row still came out 0.0 px - three
	# facts that cannot all be true of one object. What a *later* reader saw and what the dressing *used* are not the
	# same number until this is written down at the moment of use, which is the whole lesson of this fault: a value
	# read afterwards is a different reading, not the same one.
	var device_scale: float = scale_for_a_size()
	var device_density: float = density_for_a_size()
	var square: float = PhoneHudScript.row_height(device_scale, device_density)
	last_dressing = "%.2f px from scale %.3f, density %.1f" % [square, device_scale, device_density]
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(
		maxf(button.custom_minimum_size.x, square),
		maxf(button.custom_minimum_size.y, square),
	)
	button.add_theme_font_size_override("font_size", type_size())


## A row's height on this device, in the room's own pixels.
func row_height() -> float:
	return PhoneHudScript.row_height(PhoneHudScript.canvas_scale(app_window), density_for_a_size())


## The size words are drawn at on this device: the millimetre floor `PhoneHud` states, never a number chosen here.
func type_size() -> int:
	return PhoneHudScript.font_size(PhoneHudScript.canvas_scale(app_window), density_for_a_size())


## The density a size is worked out at: **the one the furniture was built at, whenever it has one.**
##
## `built_at` is not a convenience, it is the answer to a measured fault, and this is the second place that answer
## belongs. A caller may state a device for the length of the build and hand its own back the moment the build is
## made - the development view does exactly that - so anything dressed *later* asked the machine instead and got the
## desk's 144. Measured on the strip: the six tool stand-ins came out with their words drawn at the desk's size
## inside a 98 px row, because they are built when a tab is pressed, which is a frame or two after the density was
## put back. **Every size in the reading beside them was right**, and that is why it went unnoticed: the reading
## holds a control's size and not the size of its type, and a button can be exactly as tall as it should be with its
## words a third the size they belong. Asking the machine again is the fault in both places - the density the
## furniture was made at is one fact, and it is kept.
##
## A running program states nothing and this changes nothing there: `built_at` is the device's own density, so the
## two are the same number and the same answer.
func density_for_a_size() -> float:
	if stated_density > 0.0:
		return stated_density
	return built_at if built_at > 0.0 else PhoneHudScript.dpi()


## The canvas scale a size is worked out at, kept for the same reason the density is: a caller may state a device
## for the length of the build, and asking the window again afterwards - or asking a different copy of this project's
## arithmetic - answers something else.
func scale_for_a_size() -> float:
	if stated_scale > 0.0:
		return stated_scale
	return PhoneHudScript.canvas_scale(app_window)


## The dock's tabs, one per name in `TOUCH_TABS`, each as wide a share of the row as the rest.
func build_the_tabs() -> void:
	if tabs == null or tabs.get_child_count() > 0:
		return
	for tab: String in TOUCH_TABS:
		var pressed: Callable = tab_door.bind(tab) if tab_door.is_valid() else Callable()
		var button: Button = a_button(tab, tab_tooltip(tab), pressed)
		button.toggle_mode = true
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tabs.add_child(button)


## What each tab opens, in the words a person reads on the glass.
## **A view with no HUD can still want these**, so the question is answered from the tab's own name and from
## nothing else - which is why it is a plain function of a `String` rather than of the HUD's state.
func tab_tooltip(tab: String) -> String:
	match tab:
		"Draw":
			return "The shapes a plan is drawn with"
		"Dim":
			return "The dimensions a plan is measured with"
		"Edit":
			return "Change what is already drawn"
		"Plants":
			return "The plant library"
	return "The rest of the menu"


## **Show the two plates through `ChromeStyle`, off the plate the scene drew.** The bar's own look is read from
## `top_bar`, which is the one control in the scene wearing it, so the dock and the strip are the same pane as
## the bar rather than three panes three people styled. The dock is drawn wide and flat, so its corners are
## round at the top and square at the foot and its rule runs along the top edge alone; the strip floats, so it
## keeps every corner and the whole rule. On a desk the plates are still replaced - the look is identical, and a
## control that is never shown costs nothing.
func apply_the_plates() -> void:
	if top_bar == null:
		return
	var drawn: StyleBox = top_bar.get_theme_stylebox(&"panel")
	if dock != null:
		dock.add_theme_stylebox_override(&"panel", ChromeStyleScript.dock_plate(drawn, 0.0))
	if strip != null:
		strip.add_theme_stylebox_override(&"panel", ChromeStyleScript.floating_plate(drawn))
	# The sheet wears the plate for the panels anchored to the foot as well: one look, asked of the one function
	# that derives it from the bar's own. The six panels take theirs in `_place_the_overlay_panels`, which is
	# where their placement lives and which runs after they have been built.
	var along_the_foot: StyleBox = a_dock_plate()
	if sheet != null and along_the_foot != null:
		sheet.add_theme_stylebox_override(&"panel", along_the_foot)


## The plate the panels anchored to the foot wear, derived from the bar's own and from nothing else.
func a_dock_plate() -> StyleBox:
	if top_bar == null:
		return null
	return ChromeStyleScript.dock_plate(top_bar.get_theme_stylebox(&"panel"), 0.0)


## The line of hints standing at the foot of the screen, and what else the placement has to know about the room.
var hints: PanelContainer = null
var menu_bar: MenuBar = null

## **Whether a finger is here, stated rather than asked.** The module cannot call the HUD's own
## `shows_touch_controls`, and a development view has no device to ask anyway - so whoever holds the furniture
## says what the arrangement is for. A view standing the phone's arrangement up says `true`.
var on_a_finger: bool = false

## The gap the palette's own placement keeps between two pieces of furniture, handed in rather than restated.
var palette_gap: float = 0.0


## The surfaces a phone arrangement puts away because they belong to a desk: the presentation panel, the desk's own
## palette column, the drafting hints. **Handed in by the workspace rather than named here**, because which surfaces a
## scene has is the scene's own fact and not this module's - the same split as every other door on this class.
##
## **Hidden, and remembered.** A phone arrangement takes the desk's surfaces away and **gives back exactly the ones it
## took**: a panel whose own logic has decided to stay down must not be brought up by a change of arrangement, and a
## panel this arrangement took away must not be left down when the desk comes back - which a HUD that follows a
## window's shape really does. Hiding without remembering is right in a view that never switches and wrong in the
## program that does, so the memory is the rule rather than a nicety.
var desk_panels: Array[Control] = []

## The desk's surfaces this arrangement has taken away, so that only those come back.
var _put_away: Array[Control] = []


## Say which of the two arrangements is up: the dock and the row of controls, or the palette and the menus.
##
## `working` is the question the frame has already asked - whether the drawing's own furniture belongs on the
## screen at all - so a presentation and a painted sheet put this away with everything else.
func show_the_furniture(working: bool) -> void:
	if row != null:
		row.visible = on_a_finger and working
	# The menus stand exactly where they always did on a desk; on a finger the drawer is the same plan reached
	# from a button a thumb can hit, so the bar itself is not drawn twice.
	if menu_bar != null:
		menu_bar.visible = not on_a_finger
	if dock != null:
		dock.visible = on_a_finger and working
	# A sheet is part of the drawing's furniture rather than a page of its own, so a presentation or a painted
	# sheet puts it away with the rest - and whatever it borrowed is handed straight back when that happens.
	if sheet != null and sheet.visible and not (on_a_finger and working) and close_door.is_valid():
		close_door.call()
	# **And the desk's own surfaces go away with the desk** - the ones this pass actually took, so that a desk coming back
	# gets them and nothing else. This is the reading `Hud` makes when it starts the presentation panel put away on a
	# finger; the panel stands at `1276,70 .. 1588,88`, inside the top bar's plate and straight across `Ground view`,
	# and it is the one panel in this program with no placement rule at all, so it kept a desk rectangle and drew a
	# ghost over two of the bar's buttons. "Which arrangement is up" is one question and this is the place that answers
	# it, so the answer belongs here rather than in each workspace.
	if on_a_finger and working:
		for panel: Control in desk_panels:
			if panel != null and panel.visible:
				panel.visible = false
				_put_away.append(panel)
	else:
		for panel: Control in _put_away:
			if is_instance_valid(panel):
				panel.visible = true
		_put_away.clear()


## Put the dock along the foot of the screen, above whatever the device keeps there for itself.
##
## The band is the one the devices this project has measured keep along their foot - the swipe that goes back,
## which the engine does not report as a safe area - and it is read off `PhoneHud` rather than stated here. On a
## desk every number is zero and the scene's own offsets come back unchanged, which is the same floor
## `offsets_for_the_left_column` keeps for the palette.
##
## The rect is stated **zero-height** and grows upward, because `grow_vertical` is the beginning: a panel's
## height is its own contents' and not a number written into a file for one screen.
func place_the_dock() -> void:
	if dock == null or not on_a_finger:
		return
	var room: Vector2i = Vector2i(dock.get_parent_area_size())
	var margin: float = float(PhoneHudScript.edge_margin(scale_for_a_size(), density_for_a_size()))
	var foot: float = float(PhoneHudScript.kept_foot(room))
	# **Two things the dock may not be drawn over, and the second is the one that was missed.** The first is the
	# band the device keeps along its foot - the swipe that goes back, which the engine does not report as a safe
	# area and which `PhoneHud` states instead. The second is the **line of hints**, which at a finger's type
	# wraps onto three lines and stands far higher up the screen than a desk's one-line plate does: a dock placed
	# above the device's band alone was drawn straight over the words a person is reading.
	#
	# This is the same fault `place_the_left_column_for_a_device` was written for, found on the other piece of
	# furniture and by the same instrument - a check that asks whether the panel stands *between* the bar's foot
	# and the foot line's top. Both ends are floors for the reason that placement keeps: a desk's own numbers are
	# already inside them and come back to the pixel.
	var from_the_foot: float = maxf(foot + margin, float(room.y) - top_of_the_foot_line() + palette_gap)
	dock.offset_left = margin
	dock.offset_right = -margin
	dock.offset_bottom = -from_the_foot
	dock.offset_top = dock.offset_bottom
	# **The aids are stood clear on the next real frame, and `call_deferred` is not one of those.** A deferred call
	# made from inside `_process` runs at the end of the *same* frame, before the dock has laid out at the offsets
	# just set - so the first figure read was 161 px against the 285 the dock really occupies. `process_frame`
	# waits for the frame the layout actually happens on.
	if dock.is_inside_tree():
		dock.get_tree().process_frame.connect(stand_the_aids_clear_of_the_dock, CONNECT_ONE_SHOT)
	# A `RefCounted` has no `call_deferred` of its own, so the callable is the thing deferred - and the reason it
	# is deferred at all is the one every fitting here shares: a control asked for its size before it has laid out
	# answers the size it had before.
	Callable(self, &"place_the_sheet").call_deferred()


## The top of the line of hints, in the room's own pixels: what is standing at the foot of the screen that the
## dock and the sheet may not be drawn over.
##
## Read off the plate's own rectangle rather than from the offsets the scene gave it, because that plate is
## exactly what moves when the type grows - the scene's 846 is right for a desk's one line of words and wrong by
## most of a screen for a phone's three.
##
## Zero when there is no plate to read, which is the honest answer for a hidden one: a plate that is not drawn
## cannot be drawn over, and a stale rectangle from a plate that was put away would hold this furniture up the
## screen for no reason at all.
func top_of_the_foot_line() -> float:
	if hints == null or not hints.visible:
		return 0.0
	var where: Rect2 = hints.get_global_rect()
	return maxf(where.position.y, 0.0)


## Tell the aids pane how much of the foot of the screen the HUD is standing in, so the aids are not drawn over it.
##
## **The dock's height is its own contents'**, so the top of the furniture is read from the dock's own rectangle
## rather than from the offsets the scene gave it - the same floor `top_of_the_foot_line` keeps. The **highest**
## thing standing there decides it, because the aids may not be drawn over any of it.
##
## **Asked again while the answer is still moving, and that is the whole of it.** A panel placed zero-height grows
## upward from its contents, so a read taken on the first frame after the placement answers a height the dock has
## already outgrown - measured, 187 px against the 295 the dock really occupied, which lifted the north arrow off
## its `More` tab and left the scale bar drawn across the strip. This re-asks while the figure it computes changes
## and stops the moment two frames agree, so it settles without polling for the life of the program.
##
## A desk answers zero and the aids stay exactly where a desk has always had them.
func stand_the_aids_clear_of_the_dock() -> void:
	if overlay == null or dock == null or not on_a_finger:
		return
	var room: Vector2i = Vector2i(dock.get_parent_area_size())
	var highest: float = float(room.y)
	if dock.visible and dock.size.y > 0.0:
		highest = minf(highest, dock.get_global_rect().position.y)
	var hints_top: float = top_of_the_foot_line()
	if hints_top > 0.0:
		highest = minf(highest, hints_top)
	var clear: float = maxf(0.0, float(room.y) - highest)
	overlay.set_clear_of_the_foot(clear)
	# Asked again while the answer is still moving - **on the next frame, for the reason the placement gives.** A
	# re-ask built on `call_deferred` reads the dock twice inside one frame and stops on the first answer: measured,
	# the aids were told 161 px while the dock occupied 285.
	if not is_equal_approx(clear, _aids_clearance) and dock.is_inside_tree():
		_aids_clearance = clear
		dock.get_tree().process_frame.connect(stand_the_aids_clear_of_the_dock, CONNECT_ONE_SHOT)


## The figures behind the clearance the aids stand at, in words a person reads.
##
## **Because this fault was theorised about twice and both theories were wrong.** The clearance came out 187 px
## where the dock's occupation looked like 295, and the read was made self-correcting on the guess that it had
## been taken before the dock grew - which produced the *identical* figure and refuted the guess. What is left is
## a question about *which* rectangle is read, and that is a question a printed number answers and a theory
## cannot: this names the room, the dock's own rect beside the offsets that placed it, the hints line's top, the
## clearance arrived at, and the figure the aids were actually told.
func foot_clearance_words() -> String:
	if dock == null:
		return "no dock to measure"
	var room: Vector2i = Vector2i(dock.get_parent_area_size())
	var where: Rect2 = dock.get_global_rect()
	var said: float = overlay.clear_of_the_foot if overlay != null else -1.0
	return (
		(
			"room=%dx%d  dock=%s  (top=%.0f height=%.0f offsets t=%.0f b=%.0f)  hints=%.0f  clearance=%.0f"
			+ "  aids told=%.0f"
		)
		% [
			room.x,
			room.y,
			str(where),
			where.position.y,
			dock.size.y,
			dock.offset_top,
			dock.offset_bottom,
			top_of_the_foot_line(),
			maxf(0.0, float(room.y) - where.position.y),
			said,
		]
	)


## Stand the sheet above the dock's own row rather than over it, so the tabs stay reachable while it is open -
## a sheet that covered its own door would be a panel with no way back to the board.
##
## **The dock's height is its own contents', so it is read rather than assumed**, and this is asked on the frame
## after the dock was placed for the reason every fitting here is deferred: a control asked for its size before
## it has laid out answers the size it had before. A sheet placed from a guess would either cover the tabs or
## leave a gap the width of a row.
##
## Its own height is a share of the room and not its contents' minimum: a sheet is the board with a panel over
## part of it, so it is *sized* to the room - a sheet that grew to its contents would cover the drawing it
## exists to leave visible.
func place_the_sheet() -> void:
	if sheet == null or dock == null or not on_a_finger:
		return
	var room: Vector2i = Vector2i(sheet.get_parent_area_size())
	var margin: float = float(PhoneHudScript.edge_margin(scale_for_a_size(), density_for_a_size()))
	# Above the dock as the dock really stands - its own offsets, read rather than worked out a second time -
	# so the two cannot come to overlap: the dock has already been held clear of the foot line, and the sheet
	# inherits that clearance by standing on the dock's own top.
	var above_the_dock: float = absf(dock.offset_bottom) + maxf(dock.size.y, row_height())
	var tall: float = maxf(float(room.y) * SHEET_OF_THE_ROOM, 2.0 * row_height())
	sheet.offset_left = margin
	sheet.offset_right = -margin
	sheet.offset_bottom = -above_the_dock
	sheet.offset_top = -(above_the_dock + tall)


## The palette whose buttons the strip borrows, and the sheet's own title.
var palette_column: PalettePanel = null
var sheet_title: Label = null

## **Which tab is in hand, held here because it is the furniture's own state**: it is what the tabs are marked
## from and what a second press of the same tab reads to know it is putting the strip away.
var tab_in_hand: String = ""

## What pressing the Plants tab opens, what the strip's buttons are chosen by, and what a closing sheet hands
## back. Each is the HUD's own business - the plant picker, the palette's tool list - so each is a door.
var plant_sheet_door: Callable = Callable()
var tools_for_door: Callable = Callable()
var hand_back_door: Callable = Callable()


## Press a tab: show its tools, open what it opens, or put the strip away when it was already in hand.
func press_a_tab(tab: String) -> void:
	var putting_it_away: bool = tab == tab_in_hand and strip != null and strip.visible
	if tab == "Plants":
		tab_in_hand = tab
		mark_the_tab()
		if plant_sheet_door.is_valid():
			plant_sheet_door.call()
		return
	if tab == "More":
		tab_in_hand = tab
		mark_the_tab()
		if drawer_door.is_valid():
			drawer_door.call()
		return
	if putting_it_away:
		tab_in_hand = ""
		if strip != null:
			strip.visible = false
		put_the_tools_back()
		mark_the_tab()
		return
	tab_in_hand = tab
	mark_the_tab()
	put_the_tools_back()
	if not tools_for_door.is_valid():
		return
	# **Taken one button at a time rather than re-typed in one cast, and this is a fault that was measured.** The
	# first version asked the door and handed what came back through `Array(asked, TYPE_OBJECT, &"Array",
	# [Button])`, intending to say "these are buttons" - but the `&"Array"` there is the *element's* class, so the
	# cast asked for an array of arrays and threw on the first tab ever pressed: `Trying to assign an array of
	# type "Array[Array]" to a variable of type "Array[Button]"`. Nothing had pressed a tab before the
	# development view did, so nothing had said so. Building the list here also means a door that hands back
	# something which is not a button fails at that button instead of silently emptying the strip.
	var asked: Variant = tools_for_door.call(tab)
	if not (asked is Array):
		return
	var wanted: Array[Button] = []
	for handed_back: Variant in asked as Array:
		if handed_back is Button:
			wanted.append(handed_back as Button)
	if strip == null or strip_row == null:
		return
	strip.visible = not wanted.is_empty()
	for button: Button in wanted:
		button.reparent(strip_row, false)
	Callable(self, &"fit_the_strip").call_deferred()


## Say which tab is in hand, on the tabs themselves.
##
## A toggle button that is down is the whole of what a person is told about which group the strip is showing,
## and nothing else on the screen says it: the strip's own buttons carry no group name, because a tool's name is
## its own. The tabs are told here rather than left to the engine's own toggling, so the row cannot come to show
## two tabs down - which is what a press the engine toggled while this file cleared a different one would do.
func mark_the_tab() -> void:
	if tabs == null:
		return
	for child: Node in tabs.get_children():
		if child is Button:
			var button: Button = child as Button
			button.button_pressed = button.text == tab_in_hand


## Open the sheet: a plate over the board's foot, titled and closable, holding whatever a tab put in it.
##
## **A sheet rather than a page.** A page is a `Window` the width of the screen, and it is where a person goes to
## do something; a sheet stands over part of the board, which is what choosing a plant wants - the bed being
## planted stays on the screen while the picker is in hand. Opening one puts the strip away, because the two
## share the room above the dock and a strip left standing under a sheet is furniture with nothing to do.
func open_the_sheet(title: String) -> void:
	if sheet == null:
		return
	put_the_tools_back()
	if strip != null:
		strip.visible = false
	if sheet_title != null:
		sheet_title.text = title
	sheet.visible = true
	Callable(self, &"place_the_sheet").call_deferred()


## Close the sheet and hand back whatever it borrowed.
func close_the_sheet() -> void:
	if sheet == null or not sheet.visible:
		return
	sheet.visible = false
	if hand_back_door.is_valid():
		hand_back_door.call()
	# The tab that opened it is no longer holding anything, so it comes up with the sheet: a tab left down over
	# an empty stretch of board would say a group is being shown when nothing is.
	if tab_in_hand == "Plants":
		tab_in_hand = ""
		mark_the_tab()


## Return every button standing in the strip to the column it was built in.
func put_the_tools_back() -> void:
	if palette_column == null or strip_row == null:
		return
	for child: Node in strip_row.get_children():
		if child is Button:
			(child as Button).reparent(palette_column, false)


## Lay the strip's buttons out for a finger, on the frame after they were moved: a control asked for a size
## before it has laid out answers the size it had before, which is the reason every fitting here is deferred.
##
## **Measured at the density the furniture was built at rather than at whatever the machine reports now**, and
## that is a fault that was measured: a development view states a phone's density for the length of the build
## and puts its own back the moment it is made, so by the time this deferred call runs the machine answers 144
## and the cells were laid out 32 px tall - a third of the floor a thumb needs - while the buttons themselves
## had been built 97 px tall. In the running program the two numbers are the same one and this changes nothing.
func fit_the_strip() -> void:
	if strip_row == null:
		return
	var density: float = built_at if built_at > 0.0 else PhoneHudScript.dpi()
	ToolPaletteScript.fit_a_strip(strip_row, PhoneHudScript.canvas_scale(app_window), density)


## Put the drawer under the button that opened it, and fit its words to the finger that will press them - the
## bar's own menus keep the same fitting for the same reason.
##
## The drawer's *popup* is not built here: it is filled by the bar's own renderer, so it is the bar's business
## and stays where that renderer is. Where it stands is furniture, and that is what this decides.
func where_the_drawer_stands(drawer: PopupMenu) -> void:
	# The row if it is there and the bar otherwise, written as its own assignment rather than as a ternary:
	# the two are siblings with no common ancestor below `Control`, and GDScript refuses a conditional whose
	# values it cannot reconcile - which is a parse error, not a warning.
	var anchor: Control = top_bar
	if row != null:
		anchor = row
	if anchor != null:
		var where: Rect2 = anchor.get_global_rect()
		drawer.position = Vector2i((where.position + Vector2(0.0, where.size.y)).round())
	if on_a_finger:
		PhoneHudScript.fit_the_chrome_for_a_finger(
			drawer,
			PhoneHudScript.canvas_scale(app_window),
			PhoneHudScript.dpi(),
		)
