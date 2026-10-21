class_name HatchPanel
extends VBoxContainer
## The controls that hatch a region: the pattern, how tight it is, which way it runs, and which of
## the drawing's own regions to cover.
##
## Separate from the palette's plant section because it is a different job, and built the same way:
## **nothing in it holds the keyboard**. Every control is `FOCUS_NONE`, because the number keys and
## the arrow keys belong to the drawing while the panel is open over it. That is also why every
## choice is a drop-down rather than a typed number: a field for "2 mm" would take the keyboard, and
## the choices a mulch hatch is ever drawn at are a short, conventional list.
##
## It owns no drawing: it says which region, pattern and settings, and the HUD does the filling.

signal fill_requested(entity_id: int, options: Dictionary)
signal close_requested()

const HatchFillScript := preload("res://scripts/draft/hatch_fill.gd")
const ZoneMapScript := preload("res://scripts/zone_map.gd")

var _region_option: OptionButton = null
var _pattern_option: OptionButton = null
var _spacing_option: OptionButton = null
var _angle_option: OptionButton = null
var _symbol_option: OptionButton = null
var _fill_button: Button = null
var _status: Label = null
## The regions the drawing encloses, as `ZoneMap.areas_of` returns them, and the key of the one the
## drop-down is on. Held rather than looked up on the button, so the region filled is the one named.
var _regions: Array[Dictionary] = []
var _regions_signature: String = ""
var _region_key: String = ""
## The last thing this panel did. A field rather than a label write, because the status line is
## recomputed on every refresh and a transient line would be gone a frame later.
var _said: String = ""
var _built: bool = false


func build() -> void:
	if _built:
		return
	_built = true
	add_theme_constant_override("separation", 6)

	_region_option = _row("Region", "The closed regions the drawing encloses. Nothing here draws one.")
	_region_option.item_selected.connect(_on_region_selected)

	_pattern_option = _row("Pattern", "Line hatch, crosshatch, symbol stipple, or a solid tone.")
	for pattern: StringName in HatchFillScript.PATTERNS:
		_pattern_option.add_item(HatchFillScript.pattern_words(pattern))
		_pattern_option.set_item_metadata(_pattern_option.item_count - 1, pattern)
	_pattern_option.selected = HatchFillScript.PATTERNS.find(HatchFillScript.HATCH)
	_pattern_option.item_selected.connect(_on_pattern_selected)

	_spacing_option = _row("Spacing", "How far apart the pattern is drawn, on the sheet.")
	for millimetres: float in HatchFillScript.SPACING_MM:
		_spacing_option.add_item(HatchFillScript.spacing_words(millimetres))
		_spacing_option.set_item_metadata(_spacing_option.item_count - 1, millimetres)
	_spacing_option.selected = HatchFillScript.SPACING_MM.find(2.0)

	_angle_option = _row("Angle", "Which way the pattern runs.")
	for degrees: float in HatchFillScript.ANGLES_DEG:
		_angle_option.add_item(HatchFillScript.angle_words(degrees))
		_angle_option.set_item_metadata(_angle_option.item_count - 1, degrees)
	_angle_option.selected = HatchFillScript.ANGLES_DEG.find(45.0)

	_symbol_option = _row("Symbol", "The mark a symbol stipple lays down.")
	for symbol: StringName in HatchFillScript.SYMBOLS:
		_symbol_option.add_item(HatchFillScript.symbol_words(symbol))
		_symbol_option.set_item_metadata(_symbol_option.item_count - 1, symbol)

	_status = Label.new()
	_status.name = "Status"
	_status.add_theme_font_size_override("font_size", 12)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)

	var buttons := HBoxContainer.new()
	buttons.name = "Buttons"
	add_child(buttons)
	_fill_button = Button.new()
	_fill_button.name = "FillButton"
	_fill_button.text = "Hatch the region"
	_fill_button.focus_mode = Control.FOCUS_NONE
	_fill_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fill_button.pressed.connect(fill_selected)
	buttons.add_child(_fill_button)
	var close_button := Button.new()
	close_button.name = "CloseButton"
	close_button.text = "Close"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.pressed.connect(func() -> void: close_requested.emit())
	buttons.add_child(close_button)

	_refresh_detail()


## One labelled drop-down row. Named rather than numbered, so a test can find it and the focus rule
## is applied in one place.
func _row(caption_text: String, tip: String) -> OptionButton:
	var row := HBoxContainer.new()
	row.name = caption_text + "Row"
	add_child(row)
	var caption := Label.new()
	caption.name = caption_text + "Caption"
	caption.text = caption_text
	caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(caption)
	var option := OptionButton.new()
	option.name = caption_text + "Option"
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	option.focus_mode = Control.FOCUS_NONE
	option.tooltip_text = tip
	row.add_child(option)
	return option


func _ready() -> void:
	build()


# --- what it shows --------------------------------------------------------------------


func _on_region_selected(index: int) -> void:
	if index < 0 or index >= _region_option.item_count:
		return
	_region_key = String(_region_option.get_item_metadata(index))
	_refresh_detail()


## A choice that changes which other choices mean anything: solid has no spacing to choose, a
## stipple's symbol only matters when it is a stipple.
func _on_pattern_selected(_index: int) -> void:
	_refresh_detail()


## The drawing's regions, re-read whenever the drawing changes. A signature check keeps a bed drawn
## in the next plot from moving the drop-down out from under somebody.
func set_regions(rows: Array[Dictionary]) -> bool:
	build()
	var keys: Array[String] = []
	for row: Dictionary in rows:
		keys.append(String(row.get("key", "")))
	var signature := "|".join(keys)
	if signature == _regions_signature:
		return false
	_regions_signature = signature
	_regions = rows.duplicate()
	_region_option.clear()
	var keep := -1
	for index in _regions.size():
		_region_option.add_item(_region_words(_regions[index]))
		_region_option.set_item_metadata(index, String(_regions[index].get("key", "")))
		if String(_regions[index].get("key", "")) == _region_key:
			keep = index
	if _regions.is_empty():
		_region_key = ""
	else:
		var chosen: int = maxi(keep, 0)
		_region_key = String(_regions[chosen].get("key", ""))
		_region_option.selected = chosen
	_refresh_detail()
	return true


func _region_words(row: Dictionary) -> String:
	return "%s, %s" % [String(row.get("name", "")), ZoneMapScript.row_area_text(row)]


func regions() -> Array[Dictionary]:
	return _regions


func selected_region_key() -> String:
	return _region_key


func selected_region() -> Dictionary:
	for row: Dictionary in _regions:
		if String(row.get("key", "")) == _region_key:
			return row
	return {}


func pattern_choice() -> StringName:
	if _pattern_option == null or _pattern_option.item_count == 0:
		return HatchFillScript.HATCH
	return StringName(_pattern_option.get_item_metadata(maxi(_pattern_option.selected, 0)))


func spacing_mm() -> float:
	if _spacing_option == null or _spacing_option.item_count == 0:
		return 2.0
	return float(_spacing_option.get_item_metadata(maxi(_spacing_option.selected, 0)))


func angle_deg() -> float:
	if _angle_option == null or _angle_option.item_count == 0:
		return 45.0
	return float(_angle_option.get_item_metadata(maxi(_angle_option.selected, 0)))


func symbol_choice() -> StringName:
	if _symbol_option == null or _symbol_option.item_count == 0:
		return HatchFillScript.SYMBOL_DOT
	return StringName(_symbol_option.get_item_metadata(maxi(_symbol_option.selected, 0)))


## The four things a fill is, taken together, so a caller hands them on in one piece.
func options() -> Dictionary:
	return {
		"pattern": pattern_choice(),
		"spacing_mm": spacing_mm(),
		"angle_deg": angle_deg(),
		"symbol": symbol_choice(),
	}


func set_pattern(pattern: StringName) -> bool:
	build()
	for index in _pattern_option.item_count:
		if StringName(_pattern_option.get_item_metadata(index)) == pattern:
			_pattern_option.selected = index
			_refresh_detail()
			return true
	return false


func _refresh_detail() -> void:
	if _fill_button == null:
		return
	var pattern := pattern_choice()
	# A control that cannot matter is greyed rather than hidden: the panel keeps its shape, and a
	# person can see that a solid fill has no angle to set before they wonder where the angle went.
	_spacing_option.disabled = pattern == HatchFillScript.SOLID
	_angle_option.disabled = pattern == HatchFillScript.STIPPLE
	_symbol_option.disabled = pattern != HatchFillScript.STIPPLE
	_fill_button.disabled = _region_key.is_empty()
	_fill_button.tooltip_text = "The drawing encloses no region yet: draw a bed or paving outline"
	if not _region_key.is_empty():
		_fill_button.tooltip_text = "Hatch %s" % _region_words(selected_region())
	_status.text = status_text()


func status_text() -> String:
	if not _said.is_empty():
		return _said
	if _regions.is_empty():
		return "The drawing encloses no region yet. Draw a bed or a paving outline first."
	return "%s at %s, %s." % [
		HatchFillScript.pattern_words(pattern_choice()),
		HatchFillScript.spacing_words(spacing_mm()),
		HatchFillScript.angle_words(angle_deg()),
	]


## Fill the chosen region with the chosen pattern. The panel fills nothing itself - it has no
## drawing - so this says what was asked for and the HUD does it.
func fill_selected() -> bool:
	if _region_key.is_empty():
		return false
	var row: Dictionary = selected_region()
	if row.is_empty():
		return false
	fill_requested.emit(int(row.get("entity_id", 0)), options())
	return true


func say(text: String) -> void:
	build()
	_said = text
	_refresh_detail()


func said() -> String:
	return _said


## The one rule this panel has, checked in one place: no control here takes the keyboard.
func list_is_keyboard_free() -> bool:
	if _region_option == null or _pattern_option == null or _spacing_option == null:
		return false
	if _angle_option == null or _symbol_option == null or _fill_button == null:
		return false
	return _region_option.focus_mode == Control.FOCUS_NONE \
		and _pattern_option.focus_mode == Control.FOCUS_NONE \
		and _spacing_option.focus_mode == Control.FOCUS_NONE \
		and _angle_option.focus_mode == Control.FOCUS_NONE \
		and _symbol_option.focus_mode == Control.FOCUS_NONE \
		and _fill_button.focus_mode == Control.FOCUS_NONE