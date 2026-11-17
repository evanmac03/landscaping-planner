extends Control
## A demonstration of a **layer panel** - one toggle per layer of a `DraftLayerSet` - at the size a finger is
## given on the device, so that switching a layer on a phone is asked about the same way the program's own
## controls are.
##
## A development tool rather than part of the game. It was first written with its own four invented layers
## ("Satellite", "Shade Fall", "Site Boundary", "Plant Zones"), its own layer numbers, its own idea of what a
## layer is (a bitmask), and a `preload` of a file that does not exist. Each of those is a second answer to a
## question this project keeps in one place: `DraftLayerSet` owns the layer vocabulary (`010-SURVEY-PROP`,
## `500-IRRIGATION`, `501-LIGHTING` and the rest) and the switching too, in `set_visible`. So this panel spells
## no layer by hand and decides nothing about what a layer is: it is handed a set, and calls the one place a
## layer's visibility is stated.
##
##     res://tools/layer_toggle.tscn
##
## Opened with no argument it shows a fresh document's own set (`DraftLayerSet.default_set`), which is the set a
## new drawing starts with - so what is on the screen is the project's real layers rather than examples.

const PhoneHudScript := preload("res://scripts/phone_hud.gd")
const DraftLayerSetScript := preload("res://scripts/draft/layer_set.gd")

## Emitted whenever a layer is switched, so something outside the panel can follow the change rather than
## reading the toggles back.
signal layer_switched(layer_name: StringName, shown: bool)

## The set this panel is a view of. Null until `use` is called, and the panel says so in words rather than
## showing nothing.
var _set: DraftLayerSetScript = null

## The toggles, by the layer each one stands for.
var _toggles: Dictionary[StringName, CheckButton] = {}

## The column the toggles are stacked in, the scroller it lives in, the panel around it, and the line that says
## how many layers show.
var _column: VBoxContainer = null
var _scroller: ScrollContainer = null
var _panel: PanelContainer = null
var _status: Label = null


## The height one row of the panel is given: the device's own row, which is the floor a finger's target obeys.
func _row_height() -> float:
	return PhoneHudScript.row_height(PhoneHudScript.canvas_scale(get_window()), PhoneHudScript.dpi())


## Point the panel at a set of layers and build a toggle for each. It may be pointed at another set later; the
## toggles are made again from the new one rather than kept, because a toggle standing for a layer the set no
## longer holds is a control that can only lie.
func use(layer_set: DraftLayerSetScript) -> void:
	_set = layer_set
	refresh()
	_fit_the_panel()


## **The panel is as wide as the names on it need, and never narrower than a thumb's row.** A name that does not
## fit is a name nobody can read - `010-SURVEY-PROP` came out as `010-SUR`, measured on the first run - so the
## width is asked for rather than guessed at with a multiple of the row.
##
## **It is asked of the column of toggles and not of the panel**, because a `ScrollContainer`'s own minimum size
## deliberately ignores what is inside it: that is what scrolling is for. So a panel sized from its own minimum
## learned the status line's width and nothing else, and went on clipping every name - measured, on the second
## run. The additions are the panel's own frame and the bar the scroller draws when the list is taller than the
## screen, each asked of the thing that owns it rather than spelled out here.
func _fit_the_panel() -> void:
	if _panel == null or _column == null:
		return
	await get_tree().process_frame
	var frame: StyleBox = _panel.get_theme_stylebox(&"panel")
	var padding: float = 0.0 if frame == null else frame.get_margin(SIDE_LEFT) + frame.get_margin(SIDE_RIGHT)
	var bar: float = 0.0 if _scroller == null else _scroller.get_v_scroll_bar().size.x
	var needed: float = _column.get_combined_minimum_size().x + padding + bar
	_panel.offset_left = -maxf(_row_height() * 2.4, needed)


## The toggle a layer was given, or null when the panel is not showing that layer. This is for a driver that
## wants to press one; changing a layer's state is `DraftLayerSet.set_visible`'s business and not this panel's.
func toggle_for(layer_name: StringName) -> CheckButton:
	return _toggles.get(layer_name, null)


## Build the toggles again from the set in hand.
func refresh() -> void:
	if _column == null:
		return
	for old: Node in _column.get_children():
		old.queue_free()
	_toggles.clear()
	if _set == null:
		_say_what_is_showing()
		return
	var row: float = _row_height()
	for layer: Variant in _set.layers():
		var layer_name: StringName = layer.name
		var toggle := CheckButton.new()
		toggle.name = "Layer_" + String(layer_name)
		toggle.text = String(layer_name)
		toggle.button_pressed = bool(layer.visible)
		toggle.custom_minimum_size = Vector2(0.0, row)
		toggle.focus_mode = Control.FOCUS_NONE
		toggle.toggled.connect(_on_layer_toggled.bind(layer_name))
		_column.add_child(toggle)
		_toggles[layer_name] = toggle
	_say_what_is_showing()


## A toggle was switched: state it in the one place a layer's visibility lives, then say what came of it.
func _on_layer_toggled(shown: bool, layer_name: StringName) -> void:
	if _set == null:
		return
	_set.set_visible(layer_name, shown)
	_say_what_is_showing()
	layer_switched.emit(layer_name, shown)


## How many layers the set is showing, asked of the set rather than counted off the ticks - so the panel reports
## the thing the drawing obeys rather than its own idea of it.
func _say_what_is_showing() -> void:
	if _status == null:
		return
	if _set == null:
		_status.text = "no layer set is open, so there is nothing to show"
		return
	_status.text = "%d of %d layer(s) showing" % [_set.visible_names().size(), _set.size()]


## The panel itself: a scrollable column of toggles down the right of the window, and the line that says how
## many layers are showing.
##
## **The panel's offsets are written out rather than taken from a preset**, for the reason the dock's are: a
## preset computes them from the size the control has at that moment, and a control just made has none - so the
## panel came out no pixels wide with every toggle clipped inside it.
func _ready() -> void:
	var row: float = _row_height()

	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.anchor_left = 1.0
	_panel.anchor_right = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = -(row * 2.4)
	_panel.offset_right = 0.0
	_panel.offset_top = 0.0
	_panel.offset_bottom = 0.0
	add_child(_panel)

	var stack := VBoxContainer.new()
	stack.name = "Stack"
	_panel.add_child(stack)

	_status = Label.new()
	_status.name = "Status"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stack.add_child(_status)

	_scroller = ScrollContainer.new()
	_scroller.name = "Layers"
	_scroller.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(_scroller)

	_column = VBoxContainer.new()
	_column.name = "Toggles"
	_column.add_theme_constant_override(&"separation", 8)
	_scroller.add_child(_column)

	# A fresh document's own layer set, which is what a new drawing starts with.
	use(DraftLayerSetScript.default_set())
