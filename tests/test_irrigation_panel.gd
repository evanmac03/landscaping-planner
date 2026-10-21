extends Node
## Tests for the irrigation panel: the supply, the area to water, the kind of head, the spacing, the
## zone list, and the one rule every panel in this HUD obeys - nothing in it takes the keyboard.
##
## Built with a bare `IrrigationPanel.new()` and driven by hand, so there is no scene tree and no HUD:
## the panel only says what was asked for and a signal carries it away.

const PanelScript := preload("res://scripts/irrigation_panel.gd")
const Irrigation := preload("res://scripts/draft/irrigation.gd")


func _area(id: int, name: String, area: float) -> Dictionary:
	return {"entity_id": id, "key": "bed#%d" % id, "name": name, "area_m2": area, "layer": &"400-NEW-BED"}


func _zone(number: int, label: String, valve: int) -> Dictionary:
	return {
		"number": number, "label": label, "valve": valve, "kind": Irrigation.SPRAY,
		"kind_name": Irrigation.kind_name(Irrigation.SPRAY), "heads": 4, "flow": 36.0,
		"area_m2": 36.0, "precipitation": 60.0, "verdict": "will run",
	}


func _panel():
	var panel = PanelScript.new()
	panel.build()
	return panel


# --- the area list --------------------------------------------------------------------


func test_a_panel_with_no_area_says_so_rather_than_failing() -> void:
	var panel = _panel()
	assert(panel.selected_area().is_empty())
	assert(panel.status_text().contains("encloses no area"))
	assert(not panel.water_selected(), "there is nothing to water")
	panel.free()


func test_the_areas_the_drawing_offers_are_the_ones_the_drop_down_shows() -> void:
	var panel = _panel()
	assert(panel.set_areas([_area(1, "bed 1", 12.5), _area(2, "lawn 2", 30.0)]))
	assert(panel.region_key() == "bed#1", "the first area is chosen by default")
	assert(String(panel.selected_area()["name"]) == "bed 1")
	panel.free()


func test_a_new_list_keeps_the_choice_when_it_is_still_there() -> void:
	var panel = _panel()
	panel.set_areas([_area(1, "bed 1", 12.5), _area(2, "lawn 2", 30.0)])
	panel.set_areas([_area(2, "lawn 2", 30.0), _area(1, "bed 1", 12.5)])
	assert(panel.region_key() == "bed#1", "a bed drawn elsewhere does not move the choice")
	panel.free()


# --- what watering asks for -----------------------------------------------------------


func test_watering_asks_for_the_area_the_kind_the_spacing_and_the_stagger_by_signal() -> void:
	var panel = _panel()
	panel.set_areas([_area(7, "bed 7", 12.0)])
	panel.set_supply(Irrigation.make_supply(40.0, 350.0))
	var asked: Array = []
	panel.water_requested.connect(
		func(key: String, kind: String, spacing: float, staggered: bool) -> void:
			asked.append([key, kind, spacing, staggered]))
	assert(panel.water_selected())
	assert(asked.size() == 1)
	assert(String(asked[0][0]) == "bed#7")
	assert(String(asked[0][1]) == Irrigation.SPRAY)
	assert(absf(float(asked[0][2]) - 4.5) < 1.0e-9, "a spray head's own 4.5 m throw")
	assert(not bool(asked[0][3]))
	panel.free()


func test_the_spacing_is_the_factor_applied_to_the_kind_s_own_throw() -> void:
	var panel = _panel()
	assert(absf(panel.spacing() - 4.5) < 1.0e-9, "a spray head throws 4.5 m")
	# The rotor is the one kind whose throw is far bigger, so the same choice means a different
	# distance - which is why the panel rewrites its own labels when the kind changes.
	panel._kind_option.selected = Irrigation.kind_list().find(Irrigation.ROTOR)
	assert(absf(panel.spacing() - 11.0) < 1.0e-9, "a rotor throws 11 m")
	panel._spacing_option.selected = 1
	assert(absf(panel.spacing_factor() - 0.9) < 1.0e-9)
	assert(absf(panel.spacing() - 9.9) < 1.0e-9, "90% of 11 m")
	panel.free()


func test_every_kind_the_table_has_is_offered_and_the_first_is_a_spray() -> void:
	var panel = _panel()
	assert(panel.kind_choice() == Irrigation.SPRAY, "the panel opens on a spray head")
	assert(panel._kind_option.item_count == Irrigation.kind_list().size(), "one entry per kind")
	var shown: Array[String] = []
	for index in panel._kind_option.item_count:
		shown.append(panel._kind_option.get_item_text(index))
		shown.append(String(panel._kind_option.get_item_metadata(index)))
	for kind: String in Irrigation.kind_list():
		assert(shown.has(Irrigation.kind_name(kind)), "%s is offered by name" % kind)
		assert(shown.has(kind), "and carries its own word: %s" % kind)
	panel.free()


func test_the_water_button_is_dead_until_there_is_an_area_and_a_supply() -> void:
	var panel = _panel()
	assert(panel._water_button.disabled, "no area and no supply")
	panel.set_areas([_area(1, "bed 1", 12.5)])
	assert(panel._water_button.disabled, "an area but no supply stated")
	panel.set_supply(Irrigation.make_supply(40.0, 350.0))
	assert(not panel._water_button.disabled, "an area and a supply")
	panel.free()


# --- the supply -----------------------------------------------------------------------


func test_stating_the_supply_asks_for_what_the_drop_downs_show() -> void:
	var panel = _panel()
	var asked: Array = []
	panel.supply_requested.connect(
		func(flow: float, pressure: float) -> void: asked.append([flow, pressure]))
	assert(panel.state_supply())
	assert(asked.size() == 1)
	assert(absf(float(asked[0][0]) - PanelScript.FLOW_DEFAULT) < 1.0e-9)
	assert(absf(float(asked[0][1]) - PanelScript.PRESSURE_DEFAULT) < 1.0e-9)
	panel.free()


func test_a_stated_supply_is_shown_in_the_drop_downs() -> void:
	var panel = _panel()
	panel.set_supply(Irrigation.make_supply(50.0, 200.0))
	var choice := panel.supply_choice()
	assert(absf(float(choice["flow"]) - 50.0) < 1.0e-9)
	assert(absf(float(choice["pressure"]) - 200.0) < 1.0e-9)
	panel.free()


func test_a_supply_that_is_not_a_conventional_value_is_shown_as_itself() -> void:
	var panel = _panel()
	# 41 is not one of the flows a panel offers, and neither is 340. The panel shows them as stated
	# rather than rounding them to the nearest choice: it is reporting what the drawing holds.
	panel.set_supply(Irrigation.make_supply(41.0, 340.0))
	var choice := panel.supply_choice()
	assert(absf(float(choice["flow"]) - 41.0) < 1.0e-9, "the stated flow, not the nearest choice")
	assert(absf(float(choice["pressure"]) - 340.0) < 1.0e-9, "and the stated pressure")
	assert(panel._flow_option.item_count == PanelScript.FLOW_CHOICES.size() + 1,
		"the conventional flows plus the stated one")
	panel.free()


func test_the_budget_line_names_what_the_supply_buys() -> void:
	var panel = _panel()
	assert(panel.budget_text().contains("No supply stated"))
	panel.set_supply(Irrigation.make_supply(40.0, 350.0))
	# Four spray heads draw 36 of 40, so the budget is four.
	assert(panel.budget_text().contains("4"), "four spray heads: %s" % panel.budget_text())
	assert(panel.budget_text().contains("40 L/min"), "and the supply it is stated as")
	panel.free()


# --- the zone list --------------------------------------------------------------------


func test_the_rows_a_drawing_offers_are_listed_one_each() -> void:
	var panel = _panel()
	assert(panel.set_zones([_zone(1, "Zone 1", 1), _zone(2, "Zone 2", 2)]))
	assert(panel.zone_rows().size() == 2)
	assert(panel._zone_list.item_count == 2)
	assert(panel.status_text().contains("2 zones"), "and the status counts them")
	panel.free()


func test_taking_a_zone_off_asks_for_the_number_that_was_chosen() -> void:
	var panel = _panel()
	panel.set_zones([_zone(1, "Zone 1", 1), _zone(2, "Zone 2", 2)])
	assert(panel.selected_zone_number() == 0, "nothing is chosen until a person chooses")
	assert(panel._remove_button.disabled, "so the button is dead")
	var asked: Array = []
	panel.remove_requested.connect(
		func(number: int) -> void: asked.append(number))
	panel._zone_list.select(1)
	panel._on_zone_selected(1)
	assert(panel.selected_zone_number() == 2)
	assert(not panel._remove_button.disabled)
	assert(panel.remove_selected())
	assert(asked.size() == 1 and int(asked[0]) == 2)
	panel.free()


func test_a_said_line_reports_what_last_happened() -> void:
	var panel = _panel()
	panel.set_areas([_area(1, "bed 1", 12.5)])
	panel.say("Zone 1 will run: 4 spray heads, 36 of 40 L/min")
	assert(panel.status_text() == "Zone 1 will run: 4 spray heads, 36 of 40 L/min")
	assert(panel.said() != "")
	panel.reset()
	assert(panel.said() == "", "a reset clears the line")
	panel.free()


# --- the one rule ---------------------------------------------------------------------


func test_nothing_in_the_panel_takes_the_keyboard() -> void:
	var panel = _panel()
	assert(panel.list_is_keyboard_free(), "every control is FOCUS_NONE")
	panel.free()