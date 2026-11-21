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
	build_the_row()
	build_the_tabs()
	apply_the_plates()
	if sheet_close != null and close_door.is_valid() and not sheet_close.pressed.is_connected(close_door):
		sheet_close.pressed.connect(close_door)


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
	# The focus is off every button the HUD draws, and for the reason the palette's own note keeps: Godot hands
	# Tab to focus navigation the moment a Control holds it, and a focused button swallows the keys a drawing
	# tool is driven by.
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0.0, row_height())
	button.add_theme_font_size_override("font_size", type_size())
	return button


## A row's height on this device, in the room's own pixels.
func row_height() -> float:
	return PhoneHudScript.row_height(PhoneHudScript.canvas_scale(app_window), PhoneHudScript.dpi())


## The size words are drawn at on this device: the millimetre floor `PhoneHud` states, never a number chosen here.
func type_size() -> int:
	return PhoneHudScript.font_size(PhoneHudScript.canvas_scale(app_window), PhoneHudScript.dpi())


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
