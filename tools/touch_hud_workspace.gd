@tool
extends Control
## The phone's arrangement of the HUD, stood up by hand so the whole of it can be looked at and pushed about
## with a mouse, rather than worked out from a probe block or a screenshot.
##
## **It fills in the 2D workspace, and that is the point of `TouchFurniture`'s shape.** This file builds the
## furniture itself out of the scene's own nodes: the scene is `scenes/ui/hud.tscn`, every control in it is real
## - the four words in the top bar, the five tabs along the dock, the strip between them - and every one of them
## is built by the furniture module's own `build`, dressed by its own `apply_the_plates`, shown by its own
## `show_the_furniture` and placed by its own `place_the_dock`.
##
## **Why it cannot go through the HUD's own script, in one measurement.** A script that is not `@tool` gets no
## script *instance* in the editor, so the HUD's plain and `@onready` members do not exist in a 2D view to be
## assigned: `node_get_property_list("Hud", mask:"script")` returns exactly the three `@export`s
## (`view_controller`, `presentation`, `painted_plan`), and the first hand-over throws
## `Invalid assignment of property or key 'top_bar' ... on a base object of type 'CanvasLayer (PlannerHud)'`.
## A **`RefCounted`**, though, does get an instance in an editor - the `@tool` rule is about *nodes in a scene* -
## so the furniture can be built here while the HUD's own `_ready` stays out of the editor entirely, which
## matters because that `_ready` arms autosave, starts the survey watcher's timer and opens the document.
##
## **A finger is stated rather than asked.** `on_a_finger = true` is the same door `Hud` itself answers
## `shows_touch_controls()` with; here there is no device to ask and no HUD to ask, so the view says so. Every
## door the furniture connects is left **empty**: the buttons are built, sized and dressed and simply press
## nothing, which is the honest arrangement for a view with nothing to run. That is also why three pieces are
## absent rather than wrong - **the strip is empty, because its buttons are the drawing palette's own** and the
## palette needs a drawing to build them; **the sheet is not open, because nothing here has opened one**; and
## the six panels that stand over the board keep their desk rectangles, because the band they were to be given
## was measured wrong and withdrawn (`hud.gd`'s `_place_the_overlay_panels` says why).
##
## **The density is different, and is why this file states a number.** `PhoneHud.dpi()` reads the real screen,
## and a desk monitor's 96 is not a phone's 450, so left alone every control would come out a fifth of the
## height a thumb needs. The density is stated around the building and put back the moment it is made: a control
## keeps the height it was made with, and a static left standing would be read by whatever asked next.
##
## **Run it as well as open it.** In 2D there is no frame loop of the scene's own, so the placement is asked for
## two frames later - the same frames `phone_hud_demo` waits, and the same reason `Hud` defers its own
## `_place_the_touch_dock`: a control asked for its size before it has laid out answers the size it had before.
## Asked from `_ready` the dock came out with its foot 908 px up a 900 px room and the probe named all eight of
## its controls as off the screen.

const PhoneHudScript := preload("res://scripts/phone_hud.gd")
const TouchFurnitureScript := preload("res://scripts/touch_furniture.gd")

## The phone this program is aimed at: the A16W's own glass, which reports 450 dots to the inch. Stated in the
## words the other device tools state it in, because it is the device and not this file's choice.
const PHONE_DPI := 450.0

## The nodes the furniture is given, by the paths the scene carries them under.
const NODES := {
	"row": "Root/TopBar/Row/TouchRow",
	"dock": "Root/TouchDock",
	"strip": "Root/TouchDock/Column/ToolStrip",
	"strip_row": "Root/TouchDock/Column/ToolStrip/StripScroll/Strip",
	"tabs": "Root/TouchDock/Column/Tabs",
	"sheet": "Root/TouchSheet",
	"sheet_title": "Root/TouchSheet/Column/Header/Title",
	"sheet_close": "Root/TouchSheet/Column/Header/Close",
	"palette_column": "Root/Palette/PaletteScroll/PaletteColumn",
	"hints": "Root/Hints",
	"menu_bar": "Root/TopBar/Row/MenuBar",
	"top_bar": "Root/TopBar",
}


func _ready() -> void:
	_stand_the_phone_arrangement()


## Build the phone's furniture out of this scene's own nodes, say a finger is here, and stand it where a finger
## would find it.
func _stand_the_phone_arrangement() -> void:
	var furniture: TouchFurnitureScript = TouchFurnitureScript.new()
	var missing: PackedStringArray = PackedStringArray()
	for key: String in NODES:
		var node: Node = get_node_or_null(NodePath("Hud/" + String(NODES[key])))
		if node == null:
			missing.append(key)
			continue
		furniture.set(key, node)
	# The scene moves; this file does not guess. A path that no longer resolves is named rather than left to the
	# builders, each of which would return at its own guard and say nothing about why.
	if not missing.is_empty():
		print("TOUCH WORKSHOP: the scene has moved - no node for: %s" % ", ".join(missing))
		return
	_clear_what_was_built(furniture)
	furniture.on_a_finger = true
	furniture.app_window = get_window()
	# The phone's density for exactly as long as it takes to make the furniture, then the machine's own back.
	PhoneHudScript.force_density(PHONE_DPI)
	furniture.build()
	PhoneHudScript.force_density(0.0)
	furniture.show_the_furniture(true)
	# The room a control reports is the room it had before it laid out, so the placement is asked for two frames
	# later - one for the layout, and the second for the dock's own height before the sheet may stand on it.
	await get_tree().process_frame
	await get_tree().process_frame
	furniture.place_the_dock()
	_say_what_was_stood_up(furniture)


## Empty the three rows the furniture builds into, so it can be asked for again at a phone's density.
##
## **A copy that has already built itself has to be asked a second time, and asking is not repeating**: run in
## the Game tab, the HUD's own `_ready` has already made these buttons at whatever density this machine has, and
## every builder returns early when its row is not empty - so without this the workshop would show a desk's
## buttons under a phone's furniture and say nothing about it. In 2D there is nothing here to clear, and this is
## the line that does nothing.
func _clear_what_was_built(furniture: TouchFurnitureScript) -> void:
	for row: Control in [furniture.row, furniture.tabs, furniture.strip_row]:
		if row == null:
			continue
		for made: Node in row.get_children():
			row.remove_child(made)
			made.queue_free()


## What was stood up, in the numbers that decide whether a thumb could hit it - the whole reason a view like this
## is worth having beside the arithmetic it is made of.
func _say_what_was_stood_up(furniture: TouchFurnitureScript) -> void:
	if furniture.row == null or furniture.row.get_child_count() == 0:
		print("TOUCH WORKSHOP: the furniture did not build - the scene and the module have parted company")
		return
	var made: Button = furniture.row.get_child(0) as Button
	# The room the dock stands in, which is the whole canvas - read off the dock's own parent rather than the
	# bar's row, whose parent is the bar and comes back a tenth of the size.
	var room: Vector2 = furniture.dock.get_parent_area_size()
	print(
		(
			"TOUCH WORKSHOP: %d words in the bar and %d tabs, each %.0f px tall with %.0f px of type"
			+ ", at %.0f dpi; the dock's foot is %.0f px up a %.0f px room; %d tools in the strip"
		)
		% [
			furniture.row.get_child_count(),
			furniture.tabs.get_child_count(),
			made.custom_minimum_size.y,
			float(made.get_theme_font_size(&"font_size")),
			# The density the furniture was *built* at, not the one this machine reports now - the point of the
			# line is what is on the screen, and a density of 144 beside 97 px buttons would read as a puzzle.
			PHONE_DPI,
			absf(furniture.dock.offset_bottom),
			room.y,
			furniture.strip_row.get_child_count(),
		]
	)
