@tool
extends Control
## The phone's arrangement of the HUD, standing in the editor's 2D workspace so it can be looked at and pushed
## about with a mouse, rather than worked out from a probe block or a screenshot.
##
## Open `res://tools/touch_hud_workspace.tscn` and press **2D**. What appears is the real furniture, not a
## drawing of it: the scene this file instances is `scenes/ui/hud.tscn` itself, and every control in it - the
## four words in the top bar, the five tabs along the dock and the strip between them - is built by the HUD's
## own `_build_touch_furniture`, dressed by its own `_apply_the_touch_plates`, shown by its own
## `_show_the_touch_furniture` and placed by its own `_place_the_touch_dock`. This file words no size, no look
## and no name a second time; its whole job is to hand the HUD the nodes the scene gave it, say that a finger
## is here, and get out of the way.
##
## **Handing over the nodes is what an editor view needs and a running game gets for free.** An editor copy of
## a scene never runs `_ready`, so every `@onready` reference in `hud.gd` is null in the 2D workspace and each
## builder returns at its first guard - which is exactly why the touch furniture, switched off in the file and
## built in code, is invisible there today. Each reference is set below to the node the scene carries under the
## same path, so the builders run untouched.
##
## **A finger is stated through the HUD's own door.** `force_touch_controls(true)` is the one built for this
## - "for seeing the ground view's controls without a phone in hand" - so nothing about this machine is
## convinced of anything, and nothing is left standing when the scene is closed.
##
## **The density is different, and is why this file states a number.** `PhoneHud.dpi()` reads the real screen,
## and a desk monitor's 96 is not a phone's 450, so left alone every control would come out a fifth of the
## height a thumb needs. The density is therefore stated around the building of the furniture **and put back
## the moment it is made** - the two lines are adjacent on purpose: a control keeps the height it was made
## with, so nothing is lost by restoring the number at once, and a static left standing would be read by
## whatever asked next. `force_density` is the same door `phone_hud_demo` and the touch sweep use.
##
## **Run it as well as open it.** The scene is meant to be looked at in the 2D workspace, where nothing runs
## and the frame loop never places anything, and it is also worth running in the Game tab, where the HUD's own
## placement does run. Both are handled: the furniture is emptied before it is built, so a HUD that has already
## built itself at a desk's density is asked again at a phone's rather than left half-made.
##
## **What this view is honest about, and what it is not.** The heights and the type are the phone's, because
## they come from `PhoneHud`'s millimetre floors - a control here is as tall, and its words as big, as on the
## glass. The *room* is not: it is the editor's canvas, as wide as the editor window, where a phone's is 1185
## px. So a row that fits here has not been proved to fit there. Three pieces of the phone's arrangement are
## also absent, each for a reason rather than a fault: the tool strip is empty, because those buttons are the
## palette's own, borrowed and handed back while the program runs, and there is no palette in an editor; the
## sheet is not shown, because a sheet is what a *page* opens into and nothing here has opened one; and the six
## panels that stand over the board keep their desk rectangles, because the band they were to be given was
## measured wrong and withdrawn (`hud.gd`'s `_place_the_overlay_panels` says why). For the strip and the panels,
## `res://tools/phone_gui_probe.tscn` is the instrument - it runs the whole program, so its strip is filled and
## its probe block names every target that came up.

const PhoneHudScript := preload("res://scripts/phone_hud.gd")

## The phone this program is aimed at: the A16W's own glass, which reports 450 dots to the inch. Stated in the
## words the other device tools state it in, because it is the device and not this file's choice.
const PHONE_DPI := 450.0


func _ready() -> void:
	_stand_the_phone_arrangement()


## Give the HUD its own nodes, then ask it for the arrangement it gives a finger.
func _stand_the_phone_arrangement() -> void:
	var hud: PlannerHud = get_node_or_null(^"Hud") as PlannerHud
	if hud == null:
		return
	# The nodes this file's scene carries under the paths `hud.gd` looks for. A null here means the scene
	# moved, and the builders below would each return at their own guard rather than fail.
	hud.top_bar = hud.get_node_or_null(^"Root/TopBar") as PanelContainer
	hud.hints = hud.get_node_or_null(^"Root/Hints") as PanelContainer
	hud.menu_bar = hud.get_node_or_null(^"Root/TopBar/Row/MenuBar") as MenuBar
	hud.touch_row = hud.get_node_or_null(^"Root/TopBar/Row/TouchRow") as HBoxContainer
	hud.touch_dock = hud.get_node_or_null(^"Root/TouchDock") as PanelContainer
	hud.touch_strip = hud.get_node_or_null(^"Root/TouchDock/Column/ToolStrip") as PanelContainer
	hud.touch_strip_row = hud.get_node_or_null(^"Root/TouchDock/Column/ToolStrip/StripScroll/Strip") as HBoxContainer
	hud.touch_tabs = hud.get_node_or_null(^"Root/TouchDock/Column/Tabs") as HBoxContainer
	hud.touch_sheet = hud.get_node_or_null(^"Root/TouchSheet") as PanelContainer
	hud.touch_sheet_title = hud.get_node_or_null(^"Root/TouchSheet/Column/Header/Title") as Label
	hud.touch_sheet_body = hud.get_node_or_null(^"Root/TouchSheet/Column/Body") as VBoxContainer
	# A finger, through the HUD's own door: this is what every one of the calls below is gated on.
	hud.force_touch_controls(true)
	_clear_what_was_built(hud)
	# The phone's density for exactly as long as it takes to make the furniture, then the machine's own back.
	PhoneHudScript.force_density(PHONE_DPI)
	hud._build_touch_furniture()
	PhoneHudScript.force_density(0.0)
	hud._apply_the_touch_plates()
	hud._show_the_touch_furniture(true)
	# **The room a control reports is the room it had before it laid out**, so the placement is asked for two
	# frames later rather than from `_ready` - the same reason `Hud` defers its own `_place_the_touch_dock`, and
	# the same frames `phone_hud_demo` waits. Asked in `_ready` the arithmetic was the HUD's own and the moment
	# was wrong: the dock came out with its foot 908 px up a 900 px room, standing off the top of the screen,
	# and the probe named all eight of its controls as off it. One frame is what the layout needs; the second is
	# what the dock's own height needs before the sheet may stand on it.
	await get_tree().process_frame
	await get_tree().process_frame
	hud._place_the_touch_dock()
	_say_what_was_stood_up(hud)


## Empty the three rows the HUD builds into, so they can be asked for again at a phone's density.
##
## **A HUD that has already built itself has to be asked a second time, and asking is not repeating**: run in
## the Game tab, `hud.gd`'s own `_ready` has already made these buttons at whatever density this machine has,
## and every builder returns early when its row is not empty - so without this the workshop would show a desk's
## buttons under a phone's furniture and say nothing about it. In the 2D workspace there is nothing here to
## clear, and this is the line that does nothing.
func _clear_what_was_built(hud: PlannerHud) -> void:
	for row: Control in [hud.touch_row, hud.touch_tabs, hud.touch_strip_row]:
		if row == null:
			continue
		for made: Node in row.get_children():
			row.remove_child(made)
			made.queue_free()


## What was stood up, in the numbers that decide whether a thumb could hit it - the whole reason a view like
## this is worth having beside the arithmetic it is made of.
func _say_what_was_stood_up(hud: PlannerHud) -> void:
	if hud.touch_row == null or hud.touch_row.get_child_count() == 0:
		print("TOUCH WORKSHOP: the furniture did not build - the scene and hud.gd have parted company")
		return
	var made: Button = hud.touch_row.get_child(0) as Button
	# The room the dock stands in, which is the whole canvas - read off the dock's own parent rather than the
	# bar's row, whose parent is the bar and comes back a tenth of the size.
	var room: Vector2 = hud.touch_dock.get_parent_area_size() if hud.touch_dock != null else Vector2.ZERO
	print(
		(
			"TOUCH WORKSHOP: %d words in the bar and %d tabs, each %.0f px tall with %.0f px of type"
			+ ", at %.0f dpi; the dock's foot is %.0f px up a %.0f px room"
		)
		% [
			hud.touch_row.get_child_count(),
			hud.touch_tabs.get_child_count(),
			made.custom_minimum_size.y,
			float(made.get_theme_font_size(&"font_size")),
			# The density the furniture was *built* at, not the one this machine reports now - the point of the
			# line is what is on the screen, and a density of 144 beside 97 px buttons would read as a puzzle.
			PHONE_DPI,
			absf(hud.touch_dock.offset_bottom) if hud.touch_dock != null else 0.0,
			room.y,
		]
	)
