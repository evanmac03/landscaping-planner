class_name LightingPanel
extends VBoxContainer
## The controls that light an area: what the transformer is, which bed to light, what kind of
## fixture, how far apart, and the circuits already on the drawing.
##
## Built the way the water panel is, and for the same reason: **nothing in it holds the keyboard**.
## Every control is `FOCUS_NONE`, because the number keys and the arrow keys belong to the drawing
## while this is open over it. That is also why the capacity and the voltage are drop-downs rather
## than typed numbers - a field for "100 VA" would take the keyboard, and the transformers and
## voltages a residential garden is ever wired at are a short, conventional list.
##
## It owns no drawing: it says which area, which kind and where the transformer is, and the HUD does
## the lighting.

signal transformer_requested(va: float, volts: float)
signal light_requested(region_key: String, kind: String, spacing: float, staggered: bool)
signal remove_requested(circuit_number: int)
signal close_requested()

const LightingScript := preload("res://scripts/draft/lighting.gd")

## The transformer capacities a residential garden is wired with, in volt-amperes. 100 is the
## module's own default and the one a panel opens on.
const VA_CHOICES: Array[float] = [60.0, 100.0, 150.0, 200.0, 300.0, 400.0, 600.0]
const VA_DEFAULT := 100.0
## The voltages, in volts. 12 is the low-voltage a garden runs on; 24 is its commercial cousin, and
## 120 is line voltage, which only the lantern in the fixture table wants.
const VOLTAGE_CHOICES: Array[float] = [12.0, 24.0, 120.0]
const VOLTAGE_DEFAULT := 12.0
## How far apart the fixtures are set, as a share of the kind's own throw. One is fixture-to-fixture,
## which is the spacing that lights an area evenly; a shade under it overlaps the beams a little.
const SPACING_FACTORS: Array[float] = [1.0, 0.9, 0.8, 0.7]

var _va_option: OptionButton = null
var _voltage_option: OptionButton = null
var _transformer_button: Button = null
var _budget: Label = null
var _area_option: OptionButton = null
var _kind_option: OptionButton = null
var _spacing_option: OptionButton = null
var _staggered_box: CheckBox = null
var _light_button: Button = null
var _circuit_list: ItemList = null
var _remove_button: Button = null
var _status: Label = null
## The areas the drawing encloses that can be lit, as the controller offers them, and the key of the
## one the drop-down is on. Held rather than looked up on the button, so the area lit is the one named.
var _areas: Array[Dictionary] = []
var _areas_signature: String = ""
var _area_key: String = ""
## The circuits already laid out, as a schedule reads them, and the number the list is on.
var _circuits: Array[Dictionary] = []
var _circuits_signature: String = ""
var _circuit_number: int = 0
## The last thing this panel did. A field rather than a label write, because the status line is
## recomputed on every refresh and a transient line would be gone a frame later.
var _said: String = ""
## Whether the drawing has a transformer stated at all. Kept apart from the two drop-downs, which
## always show *a* number: a panel that read "is there a transformer" off its own default would say
## yes on a drawing where nobody has stated one, and the module never assumes a hundred volt-amperes.
var _transformer_stated: bool = false
var _built: bool = false
## Set while the panel is writing its own controls from state, so a CheckBox's own `toggled` - which
## fires when `button_pressed` is assigned in code - does not read as a person clicking it.
var _filling: bool = false


func build() -> void:
	if _built:
		return
	_built = true
	add_theme_constant_override("separation", 6)

	_va_option = _row("Transformer", "The capacity of the transformer, in volt-amperes.")
	_fill_option(_va_option, VA_CHOICES, "VA", VA_DEFAULT)
	_va_option.item_selected.connect(_on_transformer_changed)

	_voltage_option = _row("Voltage", "The voltage the transformer puts out, in volts.")
	_fill_option(_voltage_option, VOLTAGE_CHOICES, "V", VOLTAGE_DEFAULT)
	_voltage_option.item_selected.connect(_on_transformer_changed)

	var supply_row := HBoxContainer.new()
	supply_row.name = "TransformerRow"
	add_child(supply_row)
	_transformer_button = Button.new()
	_transformer_button.name = "TransformerButton"
	_transformer_button.text = "State the transformer"
	_transformer_button.focus_mode = Control.FOCUS_NONE
	_transformer_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_transformer_button.tooltip_text = "Every circuit is checked against this: no fixture is laid out until one is stated."
	_transformer_button.pressed.connect(state_transformer)
	supply_row.add_child(_transformer_button)

	_budget = Label.new()
	_budget.name = "Budget"
	_budget.add_theme_font_size_override("font_size", 12)
	_budget.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_budget)

	_area_option = _row("Area", "The closed areas the drawing encloses. Nothing here draws one.")
	_area_option.item_selected.connect(_on_area_selected)

	_kind_option = _row("Fixture", "A path light, an uplight, a floodlight, a well light, a step light, or a lantern.")
	for kind: String in LightingScript.kind_list():
		_kind_option.add_item(LightingScript.kind_name(kind))
		_kind_option.set_item_metadata(_kind_option.item_count - 1, kind)
	_kind_option.selected = maxi(LightingScript.kind_list().find(LightingScript.PATH), 0)
	_kind_option.item_selected.connect(_on_kind_selected)

	_spacing_option = _row("Spacing", "How far apart the fixtures are set, as a share of the fixture's throw.")
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
	_staggered_box.tooltip_text = "Triangular spacing: rows are closer together and every other row is offset half a step, which covers the same ground with fewer fixtures."
	_staggered_box.toggled.connect(_on_stagger_toggled)
	stagger_row.add_child(_staggered_box)

	_light_button = Button.new()
	_light_button.name = "LightButton"
	_light_button.text = "Light the area"
	_light_button.focus_mode = Control.FOCUS_NONE
	_light_button.pressed.connect(light_selected)
	add_child(_light_button)

	_circuit_list = ItemList.new()
	_circuit_list.name = "CircuitList"
	_circuit_list.custom_minimum_size = Vector2(0.0, 76.0)
	_circuit_list.focus_mode = Control.FOCUS_NONE
	_circuit_list.item_selected.connect(_on_circuit_selected)
	add_child(_circuit_list)

	var remove_row := HBoxContainer.new()
	remove_row.name = "RemoveRow"
	add_child(remove_row)
	_remove_button = Button.new()
	_remove_button.name = "RemoveButton"
	_remove_button.text = "Take the circuit off"
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


func _on_transformer_changed(_index: int) -> void:
	_refresh_detail()


func _on_area_selected(index: int) -> void:
	if index < 0 or index >= _area_option.item_count:
		return
	_area_key = String(_area_option.get_item_metadata(index))
	_refresh_detail()


## The fixture kind decides what a spacing means: the factors are shares of that kind's own throw, so
## the drop-down's own text has to be rewritten when the kind changes.
func _on_kind_selected(_index: int) -> void:
	_refresh_detail()


func _on_stagger_toggled(_pressed: bool) -> void:
	if _filling:
		return
	_refresh_detail()


func _on_circuit_selected(index: int) -> void:
	if index < 0 or index >= _circuits.size():
		_circuit_number = 0
	else:
		_circuit_number = int(_circuits[index].get("number", 0))
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
	return "%s, %s m2" % [String(row.get("name", "")), _number(float(row.get("area_m2", 0.0)))]


## The circuits already on the drawing, one row each. The same signature trick, and the selection is
## carried across a refresh when the circuit it was on is still there.
func set_circuits(rows: Array[Dictionary]) -> bool:
	build()
	var signature := "|".join(_row_keys(rows))
	if signature == _circuits_signature:
		return false
	_circuits_signature = signature
	_circuits = rows.duplicate()
	_circuit_list.clear()
	var keep := -1
	for index in _circuits.size():
		_circuit_list.add_item(LightingScript.schedule_row_words(_circuits[index]))
		if int(_circuits[index].get("number", 0)) == _circuit_number:
			keep = index
	if keep >= 0:
		_circuit_list.select(keep)
	else:
		_circuit_number = 0
	_refresh_detail()
	return true


static func _row_keys(rows: Array[Dictionary]) -> Array[String]:
	var out: Array[String] = []
	for row: Dictionary in rows:
		out.append(String(LightingScript.schedule_row_words(row)))
	return out


## The transformer as the drawing states it, or nothing. Fills the two drop-downs from it when it is
## stated, so the panel opens showing what somebody said rather than what the defaults are.
func set_transformer(transformer: Dictionary) -> void:
	build()
	_filling = true
	_transformer_stated = LightingScript.has_transformer(transformer)
	var va: float = float(transformer.get("va", 0.0)) if _transformer_stated else VA_DEFAULT
	var volts: float = float(transformer.get("volts", 0.0)) if _transformer_stated else VOLTAGE_DEFAULT
	_fill_option(_va_option, VA_CHOICES, "VA", va)
	_fill_option(_voltage_option, VOLTAGE_CHOICES, "V", volts)
	_filling = false
	_refresh_detail()


## Fill a drop-down with the conventional values, plus the stated one when it is not among them, and
## select the stated value.
##
## The second half is the point: a drawing may hold a transformer that is not on the list - stated by
## a script, or simply bigger than the list goes - and a panel that rounded 750 volt-amperes down to
## the nearest choice would show a number the drawing does not hold. The extra entry is the stated
## transformer, shown as itself, and it goes when the transformer does.
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
		return LightingScript.PATH
	return String(_kind_option.get_item_metadata(maxi(_kind_option.selected, 0)))


func spacing_factor() -> float:
	if _spacing_option == null or _spacing_option.item_count == 0:
		return 1.0
	return float(_spacing_option.get_item_metadata(maxi(_spacing_option.selected, 0)))


## The spacing in metres: the factor applied to the chosen kind's own throw. A panel that showed
## "90%" and a controller that needed metres would be two numbers a person has to hold in their head;
## this is the one place they are joined.
func spacing() -> float:
	return spacing_factor() * LightingScript.throw_of_kind(kind_choice())


func staggered() -> bool:
	return _staggered_box != null and _staggered_box.button_pressed


## The four things lighting an area is, taken together, so a caller hands them on in one piece.
func options() -> Dictionary:
	return {
		"region_key": region_key(),
		"kind": kind_choice(),
		"spacing": spacing(),
		"staggered": staggered(),
	}


func transformer_choice() -> Dictionary:
	return {
		"va": float(_va_option.get_item_metadata(maxi(_va_option.selected, 0))) \
			if _va_option != null and _va_option.item_count > 0 else VA_DEFAULT,
		"volts": float(_voltage_option.get_item_metadata(maxi(_voltage_option.selected, 0))) \
			if _voltage_option != null and _voltage_option.item_count > 0 else VOLTAGE_DEFAULT,
	}


func circuit_rows() -> Array[Dictionary]:
	return _circuits


func selected_circuit_number() -> int:
	return _circuit_number


func _refresh_detail() -> void:
	if _light_button == null:
		return
	# A control that cannot matter is greyed rather than hidden: the panel keeps its shape, and a
	# person can see that the spacing a lantern is set at is its own before they wonder why.
	var kind := kind_choice()
	var throw := LightingScript.throw_of_kind(kind)
	for index in _spacing_option.item_count:
		var factor := float(_spacing_option.get_item_metadata(index))
		_spacing_option.set_item_text(index, "%s%% of the throw (%.1f m)" % [
			_number(factor * 100.0), factor * throw])
	_light_button.disabled = _area_key.is_empty() or not _transformer_stated
	_light_button.tooltip_text = "Draw a bed or a lawn outline first"
	if not _area_key.is_empty():
		_light_button.tooltip_text = "Light %s" % _area_words(selected_area())
	_remove_button.disabled = _selected_index() < 0
	_budget.text = budget_text()
	_status.text = status_text()


func _selected_index() -> int:
	if _circuits.is_empty():
		return -1
	for index in _circuits.size():
		if int(_circuits[index].get("number", 0)) == _circuit_number:
			return index
	return -1


## What the stated transformer buys: the fixture budget of the kind in hand, named, or a sentence
## saying there is nothing stated yet. The number a designer wants before laying anything out.
func budget_text() -> String:
	var transformer: Dictionary = transformer_choice()
	if not _transformer_stated:
		return "No transformer stated: nothing is laid out until one is."
	return "%s. Up to %s on this transformer." % [LightingScript.transformer_words(transformer),
		LightingScript.kind_count_words(kind_choice(),
			LightingScript.power_budget(transformer, kind_choice()))]


func status_text() -> String:
	if not _said.is_empty():
		return _said
	if not _circuits.is_empty():
		return "%s circuit%s on this drawing: %s" % [_number(float(_circuits.size())),
			"" if _circuits.size() == 1 else "s", _circuit_word_join()]
	if _areas.is_empty():
		return "The drawing encloses no area to light yet. Draw a bed or a lawn outline first."
	return "Nothing on this drawing is lit yet."


func _circuit_word_join() -> String:
	var parts: Array[String] = []
	for row: Dictionary in _circuits:
		parts.append("%s tap %d" % [String(row.get("label", "Circuit")), int(row.get("tap", 0))])
	return ", ".join(parts)


# --- what it does ---------------------------------------------------------------------


## State the transformer the two drop-downs show. The panel states nothing itself - it has no drawing
## - so this says what was asked for and the HUD does it.
func state_transformer() -> bool:
	build()
	var choice := transformer_choice()
	if float(choice["va"]) <= 0.0 or float(choice["volts"]) <= 0.0:
		return false
	transformer_requested.emit(float(choice["va"]), float(choice["volts"]))
	return true


## Light the chosen area. The panel lights nothing itself - it has no drawing - so this says what was
## asked for and the HUD does it.
func light_selected() -> bool:
	build()
	if _area_key.is_empty():
		return false
	if selected_area().is_empty():
		return false
	light_requested.emit(region_key(), kind_choice(), spacing(), staggered())
	return true


## Take the chosen circuit off. It takes the fixtures it put on the drawing with it, which is the
## HUD's job.
func remove_selected() -> bool:
	build()
	if _selected_index() < 0:
		return false
	remove_requested.emit(_circuit_number)
	return true


func say(text: String) -> void:
	build()
	_said = text
	_refresh_detail()


func said() -> String:
	return _said


func reset() -> void:
	if _light_button == null:
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
	if _va_option == null or _voltage_option == null or _transformer_button == null:
		return false
	if _area_option == null or _kind_option == null or _spacing_option == null:
		return false
	if _staggered_box == null or _light_button == null or _circuit_list == null:
		return false
	if _remove_button == null:
		return false
	return _va_option.focus_mode == Control.FOCUS_NONE \
		and _voltage_option.focus_mode == Control.FOCUS_NONE \
		and _transformer_button.focus_mode == Control.FOCUS_NONE \
		and _area_option.focus_mode == Control.FOCUS_NONE \
		and _kind_option.focus_mode == Control.FOCUS_NONE \
		and _spacing_option.focus_mode == Control.FOCUS_NONE \
		and _staggered_box.focus_mode == Control.FOCUS_NONE \
		and _light_button.focus_mode == Control.FOCUS_NONE \
		and _circuit_list.focus_mode == Control.FOCUS_NONE \
		and _remove_button.focus_mode == Control.FOCUS_NONE