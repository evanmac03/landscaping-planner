class_name IrrigationPanel
extends VBoxContainer
## The controls that water an area: what the supply is, which bed to water, what kind of head, how
## far apart, and the zones already on the drawing.
##
## Built the way the hatch panel is, and for the same reason: **nothing in it holds the keyboard**.
## Every control is `FOCUS_NONE`, because the number keys and the arrow keys belong to the drawing
## while this is open over it. That is also why the supply and the spacing are drop-downs rather than
## typed numbers - a field for "40 L/min" would take the keyboard, and the flows and pressures a
## residential supply is ever stated at are a short, conventional list.
##
## It owns no drawing: it says which area, which kind and where the supply is, and the HUD does the
## watering.

signal supply_requested(flow: float, pressure: float)
signal water_requested(region_key: String, kind: String, spacing: float, staggered: bool)
signal remove_requested(zone_number: int)
signal close_requested()

const IrrigationScript := preload("res://scripts/draft/irrigation.gd")
const ZoneMapScript := preload("res://scripts/zone_map.gd")

## The flows a residential supply is stated at, in litres a minute. 40 is the module's own default
## and the one a panel opens on, so an unstated supply has a sensible first answer rather than none.
const FLOW_CHOICES: Array[float] = [10.0, 20.0, 30.0, 40.0, 50.0, 60.0, 80.0]
const FLOW_DEFAULT := 40.0
## The pressures, in kilopascals. 350 drives every kind in the table; a spray head opens at 210.
const PRESSURE_CHOICES: Array[float] = [150.0, 200.0, 250.0, 300.0, 350.0, 400.0, 450.0]
const PRESSURE_DEFAULT := 350.0
## How far apart the heads are set, as a share of the kind's own throw. One is head-to-head, which is
## the spacing that covers a bed; a shade under it overlaps the circles a little, which is what a plan
## does where the wind takes the water. Less than 0.7 wastes heads and the coverage line says so.
const SPACING_FACTORS: Array[float] = [1.0, 0.9, 0.8, 0.7]

var _flow_option: OptionButton = null
var _pressure_option: OptionButton = null
var _supply_button: Button = null
var _budget: Label = null
var _area_option: OptionButton = null
var _kind_option: OptionButton = null
var _spacing_option: OptionButton = null
var _staggered_box: CheckBox = null
var _water_button: Button = null
var _zone_list: ItemList = null
var _remove_button: Button = null
var _status: Label = null
## The areas the drawing encloses that can be watered, as the controller offers them, and the key of
## the one the drop-down is on. Held rather than looked up on the button, so the area watered is the
## one named.
var _areas: Array[Dictionary] = []
var _areas_signature: String = ""
var _area_key: String = ""
## The zones already laid out, as a schedule reads them, and the number the list is on.
var _zones: Array[Dictionary] = []
var _zones_signature: String = ""
var _zone_number: int = 0
## The last thing this panel did. A field rather than a label write, because the status line is
## recomputed on every refresh and a transient line would be gone a frame later.
var _said: String = ""
## Whether the drawing has a supply stated at all. Kept apart from the two drop-downs, which always
## show *a* number: a panel that read "is there a supply" off its own default would say yes on a
## drawing where nobody has stated one, and the module never assumes forty litres a minute.
var _supply_stated: bool = false
var _built: bool = false
## Set while the panel is writing its own controls from state, so a CheckBox's own `toggled` - which
## fires when `button_pressed` is assigned in code - does not read as a person clicking it.
var _filling: bool = false


func build() -> void:
	if _built:
		return
	_built = true
	add_theme_constant_override("separation", 6)

	_flow_option = _row("Supply", "The flow the water source gives, in litres a minute.")
	_fill_option(_flow_option, FLOW_CHOICES, "L/min", FLOW_DEFAULT)
	_flow_option.item_selected.connect(_on_supply_changed)

	_pressure_option = _row("Pressure", "The pressure at the source, in kilopascals.")
	_fill_option(_pressure_option, PRESSURE_CHOICES, "kPa", PRESSURE_DEFAULT)
	_pressure_option.item_selected.connect(_on_supply_changed)

	var supply_row := HBoxContainer.new()
	supply_row.name = "SupplyRow"
	add_child(supply_row)
	_supply_button = Button.new()
	_supply_button.name = "SupplyButton"
	_supply_button.text = "State the supply"
	_supply_button.focus_mode = Control.FOCUS_NONE
	_supply_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_supply_button.tooltip_text = "Every zone is checked against this: no head is laid out until one is stated."
	_supply_button.pressed.connect(state_supply)
	supply_row.add_child(_supply_button)

	_budget = Label.new()
	_budget.name = "Budget"
	_budget.add_theme_font_size_override("font_size", 12)
	_budget.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_budget)

	_area_option = _row("Area", "The closed areas the drawing encloses. Nothing here draws one.")
	_area_option.item_selected.connect(_on_area_selected)

	_kind_option = _row("Head", "A spray, a rotor, a micro spray, or a bubbler.")
	for kind: String in IrrigationScript.kind_list():
		_kind_option.add_item(IrrigationScript.kind_name(kind))
		_kind_option.set_item_metadata(_kind_option.item_count - 1, kind)
	_kind_option.selected = maxi(IrrigationScript.kind_list().find(IrrigationScript.SPRAY), 0)
	_kind_option.item_selected.connect(_on_kind_selected)

	_spacing_option = _row("Spacing", "How far apart the heads are set, as a share of the head's throw.")
	for factor: float in SPACING_FACTORS:
		_spacing_option.add_item("")
		_spacing_option.set_item_metadata(_spacing_option.item_count - 1, factor)
	_spacing_option.selected = 0

	var stagger_row := HBoxContainer.new()
	stagger_row.name = "StaggerRow"
	add_child(stagger_row)
	var stagger_caption := Label.new()
	stagger_caption.name = "StaggerCaption"
	stagger_caption.text = "Layout"
	stagger_caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	stagger_row.add_child(stagger_caption)
	_staggered_box = CheckBox.new()
	_staggered_box.name = "StaggeredButton"
	_staggered_box.text = "Stagger alternate rows"
	_staggered_box.focus_mode = Control.FOCUS_NONE
	_staggered_box.tooltip_text = "Triangular spacing: rows are closer together and every other row is offset half a step, which covers the same ground with fewer heads."
	_staggered_box.toggled.connect(_on_stagger_toggled)
	stagger_row.add_child(_staggered_box)

	_water_button = Button.new()
	_water_button.name = "WaterButton"
	_water_button.text = "Water the area"
	_water_button.focus_mode = Control.FOCUS_NONE
	_water_button.pressed.connect(water_selected)
	add_child(_water_button)

	_zone_list = ItemList.new()
	_zone_list.name = "ZoneList"
	_zone_list.custom_minimum_size = Vector2(0.0, 76.0)
	_zone_list.focus_mode = Control.FOCUS_NONE
	_zone_list.item_selected.connect(_on_zone_selected)
	add_child(_zone_list)

	var remove_row := HBoxContainer.new()
	remove_row.name = "RemoveRow"
	add_child(remove_row)
	_remove_button = Button.new()
	_remove_button.name = "RemoveButton"
	_remove_button.text = "Take the zone off"
	_remove_button.focus_mode = Control.FOCUS_NONE
	_remove_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_remove_button.pressed.connect(remove_selected)
	remove_row.add_child(_remove_button)
	var close_button := Button.new()
	close_button.name = "CloseButton"
	close_button.text = "Close"
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.pressed.connect(func() -> void: close_requested.emit())
	remove_row.add_child(close_button)

	_status = Label.new()
	_status.name = "Status"
	_status.add_theme_font_size_override("font_size", 12)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)

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


func _on_supply_changed(_index: int) -> void:
	_refresh_detail()


func _on_area_selected(index: int) -> void:
	if index < 0 or index >= _area_option.item_count:
		return
	_area_key = String(_area_option.get_item_metadata(index))
	_refresh_detail()


## The head kind decides what a spacing means: the factors are shares of that kind's own throw, so
## the drop-down's own text has to be rewritten when the kind changes.
func _on_kind_selected(_index: int) -> void:
	_refresh_detail()


func _on_stagger_toggled(_pressed: bool) -> void:
	if _filling:
		return
	_refresh_detail()


func _on_zone_selected(index: int) -> void:
	if index < 0 or index >= _zones.size():
		_zone_number = 0
	else:
		_zone_number = int(_zones[index].get("number", 0))
	_refresh_detail()


## The areas the drawing encloses, re-read whenever the drawing changes. A signature check keeps a bed
## drawn in the next moment from moving the drop-down out from under somebody.
func set_areas(rows: Array[Dictionary]) -> bool:
	build()
	var keys: Array[String] = []
	for row: Dictionary in rows:
		keys.append(String(row.get("key", "")))
	var signature := "|".join(keys)
	if signature == _areas_signature:
		return false
	_areas_signature = signature
	_areas = rows.duplicate()
	_area_option.clear()
	var keep := -1
	for index in _areas.size():
		_area_option.add_item(_area_words(_areas[index]))
		_area_option.set_item_metadata(index, String(_areas[index].get("key", "")))
		if String(_areas[index].get("key", "")) == _area_key:
			keep = index
	if _areas.is_empty():
		_area_key = ""
	else:
		var chosen: int = maxi(keep, 0)
		_area_key = String(_areas[chosen].get("key", ""))
		_area_option.selected = chosen
	_refresh_detail()
	return true


func _area_words(row: Dictionary) -> String:
	return "%s, %s" % [String(row.get("name", "")), ZoneMapScript.row_area_text(row)]


## The zones already on the drawing, one row each. The same signature trick, and the selection is
## carried across a refresh when the zone it was on is still there.
func set_zones(rows: Array[Dictionary]) -> bool:
	build()
	var signature := "|".join(_row_keys(rows))
	if signature == _zones_signature:
		return false
	_zones_signature = signature
	_zones = rows.duplicate()
	_zone_list.clear()
	var keep := -1
	for index in _zones.size():
		_zone_list.add_item(IrrigationScript.schedule_row_words(_zones[index]))
		if int(_zones[index].get("number", 0)) == _zone_number:
			keep = index
	if keep >= 0:
		_zone_list.select(keep)
	else:
		_zone_number = 0
	_refresh_detail()
	return true


static func _row_keys(rows: Array[Dictionary]) -> Array[String]:
	var out: Array[String] = []
	for row: Dictionary in rows:
		out.append(String(IrrigationScript.schedule_row_words(row)))
	return out


## The supply as the drawing states it, or nothing. Fills the two drop-downs from it when it is
## stated, so the panel opens showing what somebody said rather than what the defaults are.
func set_supply(supply: Dictionary) -> void:
	build()
	_filling = true
	_supply_stated = IrrigationScript.has_supply(supply)
	var flow: float = float(supply.get("flow", 0.0)) if _supply_stated else FLOW_DEFAULT
	var pressure: float = float(supply.get("pressure", 0.0)) if _supply_stated else PRESSURE_DEFAULT
	_fill_option(_flow_option, FLOW_CHOICES, "L/min", flow)
	_fill_option(_pressure_option, PRESSURE_CHOICES, "kPa", pressure)
	_filling = false
	_refresh_detail()


## Fill a supply drop-down with the conventional values, plus the stated one when it is not among
## them, and select the stated value.
##
## The second half is the point: a drawing may hold a supply that is not on the list - stated by a
## script, or simply bigger than the list goes - and a panel that rounded 120 litres a minute down to
## the nearest choice would show a number the drawing does not hold. The extra entry is the stated
## supply, shown as itself, and it goes when the supply does.
static func _fill_option(option: OptionButton, choices: Array[float], suffix: String, value: float) -> void:
	option.clear()
	var exact := -1
	var best := 0
	var best_gap := INF
	for index in choices.size():
		option.add_item("%s %s" % [_number(choices[index]), suffix])
		option.set_item_metadata(index, choices[index])
		var gap := absf(choices[index] - value)
		if gap <= 0.001:
			exact = index
		if gap < best_gap:
			best_gap = gap
			best = index
	if exact < 0 and value > 0.0:
		option.add_item("%s %s" % [_number(value), suffix])
		option.set_item_metadata(option.item_count - 1, value)
		option.selected = option.item_count - 1
		return
	option.selected = exact if exact >= 0 else best


func region_key() -> String:
	return _area_key


func selected_area() -> Dictionary:
	for row: Dictionary in _areas:
		if String(row.get("key", "")) == _area_key:
			return row
	return {}


func kind_choice() -> String:
	if _kind_option == null or _kind_option.item_count == 0:
		return IrrigationScript.SPRAY
	return String(_kind_option.get_item_metadata(maxi(_kind_option.selected, 0)))


func spacing_factor() -> float:
	if _spacing_option == null or _spacing_option.item_count == 0:
		return 1.0
	return float(_spacing_option.get_item_metadata(maxi(_spacing_option.selected, 0)))


## The spacing in metres: the factor applied to the chosen kind's own throw. A panel that showed
## "90%" and a controller that needed metres would be two numbers a person has to hold in their head;
## this is the one place they are joined.
func spacing() -> float:
	return spacing_factor() * IrrigationScript.throw_of_kind(kind_choice())


func staggered() -> bool:
	return _staggered_box != null and _staggered_box.button_pressed


## The four things watering an area is, taken together, so a caller hands them on in one piece.
func options() -> Dictionary:
	return {
		"region_key": region_key(),
		"kind": kind_choice(),
		"spacing": spacing(),
		"staggered": staggered(),
	}


func supply_choice() -> Dictionary:
	return {
		"flow": float(_flow_option.get_item_metadata(maxi(_flow_option.selected, 0))) \
			if _flow_option != null and _flow_option.item_count > 0 else FLOW_DEFAULT,
		"pressure": float(_pressure_option.get_item_metadata(maxi(_pressure_option.selected, 0))) \
			if _pressure_option != null and _pressure_option.item_count > 0 else PRESSURE_DEFAULT,
	}


func zone_rows() -> Array[Dictionary]:
	return _zones


func selected_zone_number() -> int:
	return _zone_number


func _refresh_detail() -> void:
	if _water_button == null:
		return
	# A control that cannot matter is greyed rather than hidden: the panel keeps its shape, and a
	# person can see that the spacing a bubbler is set at is its own before they wonder why.
	var kind := kind_choice()
	var throw := IrrigationScript.throw_of_kind(kind)
	for index in _spacing_option.item_count:
		var factor := float(_spacing_option.get_item_metadata(index))
		_spacing_option.set_item_text(index, "%s%% of the throw (%.1f m)" % [
			_number(factor * 100.0), factor * throw])
	_water_button.disabled = _area_key.is_empty() or not _supply_stated
	_water_button.tooltip_text = "Draw a bed or a lawn outline first"
	if not _area_key.is_empty():
		_water_button.tooltip_text = "Water %s" % _area_words(selected_area())
	_remove_button.disabled = _selected_index() < 0
	_budget.text = budget_text()
	_status.text = status_text()


func _selected_index() -> int:
	if _zones.is_empty():
		return -1
	for index in _zones.size():
		if int(_zones[index].get("number", 0)) == _zone_number:
			return index
	return -1


## What the stated supply buys: the head budget of the kind in hand, named, or a sentence saying there
## is nothing stated yet. The number a designer wants before laying anything out.
func budget_text() -> String:
	var supply: Dictionary = supply_choice()
	if not _supply_stated:
		return "No supply stated: nothing is laid out until one is."
	return "%s. Up to %s on this supply." % [IrrigationScript.supply_words(supply),
		IrrigationScript.kind_count_words(kind_choice(),
			IrrigationScript.head_budget(supply, kind_choice()))]


func status_text() -> String:
	if not _said.is_empty():
		return _said
	if not _zones.is_empty():
		return "%s zone%s on this drawing: %s" % [_number(float(_zones.size())),
			"" if _zones.size() == 1 else "s", _zone_word_join()]
	if _areas.is_empty():
		return "The drawing encloses no area to water yet. Draw a bed or a lawn outline first."
	return "Nothing on this drawing is watered yet."


func _zone_word_join() -> String:
	var parts: Array[String] = []
	for row: Dictionary in _zones:
		parts.append("%s valve %d" % [String(row.get("label", "Zone")), int(row.get("valve", 0))])
	return ", ".join(parts)


# --- what it does ---------------------------------------------------------------------


## State the supply the two drop-downs show. The panel states nothing itself - it has no drawing - so
## this says what was asked for and the HUD does it.
func state_supply() -> bool:
	build()
	var choice := supply_choice()
	if float(choice["flow"]) <= 0.0 or float(choice["pressure"]) <= 0.0:
		return false
	supply_requested.emit(float(choice["flow"]), float(choice["pressure"]))
	return true


## Water the chosen area. The panel waters nothing itself - it has no drawing - so this says what was
## asked for and the HUD does it.
func water_selected() -> bool:
	build()
	if _area_key.is_empty():
		return false
	if selected_area().is_empty():
		return false
	water_requested.emit(region_key(), kind_choice(), spacing(), staggered())
	return true


## Take the chosen zone off. It takes the heads it put on the drawing with it, which is the HUD's job.
func remove_selected() -> bool:
	build()
	if _selected_index() < 0:
		return false
	remove_requested.emit(_zone_number)
	return true


func say(text: String) -> void:
	build()
	_said = text
	_refresh_detail()


func said() -> String:
	return _said


func reset() -> void:
	if _water_button == null:
		return
	_said = ""
	_filling = true
	_staggered_box.button_pressed = false
	_filling = false
	_refresh_detail()


## A measurement as one line writes it: whole where it is whole, one decimal otherwise.
static func _number(value: float) -> String:
	if is_equal_approx(value, round(value)):
		return "%d" % int(round(value))
	return "%.1f" % value


## The one rule this panel has, checked in one place: no control here takes the keyboard.
func list_is_keyboard_free() -> bool:
	if _flow_option == null or _pressure_option == null or _supply_button == null:
		return false
	if _area_option == null or _kind_option == null or _spacing_option == null:
		return false
	if _staggered_box == null or _water_button == null or _zone_list == null:
		return false
	if _remove_button == null:
		return false
	return _flow_option.focus_mode == Control.FOCUS_NONE \
		and _pressure_option.focus_mode == Control.FOCUS_NONE \
		and _supply_button.focus_mode == Control.FOCUS_NONE \
		and _area_option.focus_mode == Control.FOCUS_NONE \
		and _kind_option.focus_mode == Control.FOCUS_NONE \
		and _spacing_option.focus_mode == Control.FOCUS_NONE \
		and _staggered_box.focus_mode == Control.FOCUS_NONE \
		and _water_button.focus_mode == Control.FOCUS_NONE \
		and _zone_list.focus_mode == Control.FOCUS_NONE \
		and _remove_button.focus_mode == Control.FOCUS_NONE