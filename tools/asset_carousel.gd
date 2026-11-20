extends Control
## A demonstration of a **horizontal dock of assets** at the size a finger is given on the device, so that
## "would a dock along the bottom serve a thumb?" is answered by the modules the program already obeys rather
## than by a second opinion about thumbs.
##
## A development tool rather than part of the game. It was first written as a `class_name` widget with its own
## constants for the thumb floor (`28`, `5.5`, `107`) and its own invented asset names; each of those is a second
## copy of a fact this project keeps in one place, and a second copy is a copy that can disagree with the sizes
## the program actually draws at. So the cell a finger is asked for is `PhoneHud.row_height` - the device's own
## row - and the words on the cells are `PlantSymbols`'s nine shapes, which is the vocabulary a plan is drawn
## with and the only list of them.
##
##     res://tools/asset_carousel.tscn
##
## What it is for: the program's own palette is a **vertical column** down the left of the board. This lays the
## same kind of target out along the bottom instead, so the two can be looked at side by side. It decides nothing:
## the touch rules are the probe's (`HudProbe.small_lines`, `close_lines`), and they judge a target by its own
## rectangle wherever that target was built.

const PhoneHudScript := preload("res://scripts/phone_hud.gd")
const PlantSymbolsScript := preload("res://scripts/plants/plant_symbols.gd")

## Emitted when a cell is pressed, carrying the kind of asset and the name on it. The program's own drag is
## started from a palette button; this is where a dock would begin the same gesture.
signal drag_started(asset_type: String, asset_name: String)

## The assets on the dock, each `{ "name": String, "asset_type": String }`. A dictionary rather than a record
## class because it never leaves this file and nothing reads it but the cells built from it.
var _assets: Array[Dictionary] = []

## The row the cells are laid along, made in `_ready` and used by every later refresh.
var _row: HBoxContainer = null


## The rectangle one cell is given: the device's own row tall, and twice that wide, because the rule a finger's
## target obeys is a floor under the **shorter** side rather than a size to fill.
func cell_size() -> Vector2:
	var side: float = PhoneHudScript.row_height(PhoneHudScript.canvas_scale(get_window()), PhoneHudScript.dpi())
	return Vector2(side * 2.0, side)


## Add an asset to the dock and show it. The name is `asset_name` rather than `name` because a `Control` is a
## `Node`, and `Node.name` is already a property - a parameter that shadows it is a session error, measured: the
## file would not load at all and the dock drew nothing.
func add_asset(asset_name: String, asset_type: String) -> void:
	_assets.append({ "name": asset_name, "asset_type": asset_type })
	refresh_thumbnails()


## Take the first asset of a given name off the dock. A name nobody has is not a failure: the dock is a
## demonstration, and asking it to remove something it never held has changed nothing.
func remove_asset(asset_name: String) -> void:
	for index: int in _assets.size():
		if String(_assets[index]["name"]) == asset_name:
			_assets.remove_at(index)
			refresh_thumbnails()
			return


## Empty the dock.
func clear_assets() -> void:
	_assets.clear()
	refresh_thumbnails()


## Build the row again from the assets in hand. The cells are rebuilt rather than patched, because a dock this
## size is cheap and a half-updated one is the kind of thing a person reads wrongly.
func refresh_thumbnails() -> void:
	if _row == null:
		return
	for old: Node in _row.get_children():
		old.queue_free()
	var box: Vector2 = cell_size()
	for asset: Dictionary in _assets:
		var cell := Button.new()
		cell.text = String(asset["name"])
		cell.custom_minimum_size = box
		cell.focus_mode = Control.FOCUS_NONE
		# The pressed call is a bound method rather than a lambda with a default: a lambda written inside a loop
		# closes over the loop's own variable, so every cell would report the last asset on the dock.
		cell.pressed.connect(_on_cell_pressed.bind(String(asset["asset_type"]), String(asset["name"])))
		_row.add_child(cell)


## A cell was pressed: say which kind of asset and which name, which is what a dock's drag would begin from.
func _on_cell_pressed(asset_type: String, asset_name: String) -> void:
	drag_started.emit(asset_type, asset_name)


## The dock itself: a band along the foot of the window, with one row of cells in it, filled with the nine plant
## symbols said the way the module that owns them says them. A plan is drawn with those, so a dock of them is the
## honest thing to measure a thumb against.
##
## **The band's offsets are written out rather than taken from a preset.** A preset computes them from the size
## the control happens to have at that moment, and at this moment it has none - so the band came out no pixels
## tall, and a `ScrollContainer` clips its own contents, so the first run of this tool showed an empty window with
## the dock in it and nothing of the dock on screen. The band is a little taller than a cell because the scroller
## draws its own bar along the foot of it once the row is wider than the window.
func _ready() -> void:
	var row: float = cell_size().y
	var scroller := ScrollContainer.new()
	scroller.name = "Dock"
	scroller.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroller.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroller.anchor_top = 1.0
	scroller.anchor_bottom = 1.0
	scroller.anchor_right = 1.0
	scroller.offset_top = -(row * 1.2)
	scroller.offset_bottom = 0.0
	scroller.offset_right = 0.0
	add_child(scroller)
	_row = HBoxContainer.new()
	_row.name = "Cells"
	_row.add_theme_constant_override(&"separation", 8)
	scroller.add_child(_row)

	for shape: StringName in PlantSymbolsScript.NAMES:
		add_asset(String(shape).capitalize(), String(shape))
