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
