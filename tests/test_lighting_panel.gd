extends Node
## Tests for the lighting panel: the transformer, the area to light, the kind of fixture, the
## spacing, the circuit list, and the one rule every panel in this HUD obeys - nothing in it takes
## the keyboard.
##
## Built with a bare `LightingPanel.new()` and driven by hand, so there is no scene tree and no HUD:
## the panel only says what was asked for and a signal carries it away.

const PanelScript := preload("res://scripts/lighting_panel.gd")
const Lighting := preload("res://scripts/draft/lighting.gd")


func _area(id: int, name: String, area: float) -> Dictionary:
	return {"entity_id": id, "key": "bed#%d" % id, "name": name, "area_m2": area, "layer": &"400-NEW-BED"}


func _circuit(number: int, label: String, tap: int) -> Dictionary:
	return {
		"number": number, "label": label, "tap": tap, "kind": Lighting.WELL,
		"kind_name": Lighting.kind_name(Lighting.WELL), "fixtures": 16, "load": 80.0,
		"area_m2": 81.0, "verdict": "will run",
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
	assert(not panel.light_selected(), "there is nothing to light")
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


# --- what lighting asks for -----------------------------------------------------------


func test_lighting_asks_for_the_area_the_kind_the_spacing_and_the_stagger_by_signal() -> void:
	var panel = _panel()
	panel.set_areas([_area(7, "bed 7", 12.0)])
	panel.set_transformer(Lighting.make_transformer(100.0, 12.0))
	var asked: Array = []
	panel.light_requested.connect(
		func(key: String, kind: String, spacing: float, staggered: bool) -> void:
			asked.append([key, kind, spacing, staggered]))
	assert(panel.light_selected())
	assert(asked.size() == 1)
	assert(String(asked[0][0]) == "bed#7")
	assert(String(asked[0][1]) == Lighting.PATH)
	assert(absf(float(asked[0][2]) - 2.5) < 1.0e-9, "a path light's own 2.5 m throw")
	assert(not bool(asked[0][3]))
	panel.free()


func test_the_spacing_is_the_factor_applied_to_the_kind_s_own_throw() -> void:
	var panel = _panel()
	assert(absf(panel.spacing() - 2.5) < 1.0e-9, "a path light throws 2.5 m")
	# The floodlight is the one kind whose throw is far bigger, so the same choice means a different
	# distance - which is why the panel rewrites its own labels when the kind changes.
	panel._kind_option.selected = Lighting.kind_list().find(Lighting.FLOOD)
	assert(absf(panel.spacing() - 9.0) < 1.0e-9, "a floodlight throws 9 m")
	panel._spacing_option.selected = 1
	assert(absf(panel.spacing_factor() - 0.9) < 1.0e-9)
	assert(absf(panel.spacing() - 8.1) < 1.0e-9, "90% of 9 m")
	panel.free()


func test_every_kind_the_table_has_is_offered_and_the_first_is_a_path_light() -> void:
	var panel = _panel()
	assert(panel.kind_choice() == Lighting.PATH, "the panel opens on a path light")
	assert(panel._kind_option.item_count == Lighting.kind_list().size(), "one entry per kind")
	var shown: Array[String] = []
	for index in panel._kind_option.item_count:
		shown.append(panel._kind_option.get_item_text(index))
		shown.append(String(panel._kind_option.get_item_metadata(index)))
	for kind: String in Lighting.kind_list():
		assert(shown.has(Lighting.kind_name(kind)), "%s is offered by name" % kind)
		assert(shown.has(kind), "and carries its own word: %s" % kind)
	panel.free()


func test_the_light_button_is_dead_until_there_is_an_area_and_a_transformer() -> void:
	var panel = _panel()
	assert(panel._light_button.disabled, "no area and no transformer")
	panel.set_areas([_area(1, "bed 1", 12.5)])
	assert(panel._light_button.disabled, "an area but no transformer stated")
	panel.set_transformer(Lighting.make_transformer(100.0, 12.0))
	assert(not panel._light_button.disabled, "an area and a transformer")
	panel.free()


# --- the transformer ------------------------------------------------------------------


func test_stating_the_transformer_asks_for_what_the_drop_downs_show() -> void:
	var panel = _panel()
	var asked: Array = []
	panel.transformer_requested.connect(
		func(va: float, volts: float) -> void: asked.append([va, volts]))
	assert(panel.state_transformer())
	assert(asked.size() == 1)
	assert(absf(float(asked[0][0]) - PanelScript.VA_DEFAULT) < 1.0e-9)
	assert(absf(float(asked[0][1]) - PanelScript.VOLTAGE_DEFAULT) < 1.0e-9)
	panel.free()


func test_a_stated_transformer_is_shown_in_the_drop_downs() -> void:
	var panel = _panel()
	panel.set_transformer(Lighting.make_transformer(150.0, 24.0))
	var choice := panel.transformer_choice()
	assert(absf(float(choice["va"]) - 150.0) < 1.0e-9)
	assert(absf(float(choice["volts"]) - 24.0) < 1.0e-9)
	panel.free()


func test_a_transformer_that_is_not_a_conventional_value_is_shown_as_itself() -> void:
	var panel = _panel()
	# 275 is not one of the capacities a panel offers. The panel shows it as stated rather than
	# rounding it to the nearest choice: it is reporting what the drawing holds.
	panel.set_transformer(Lighting.make_transformer(275.0, 12.0))
	var choice := panel.transformer_choice()
	assert(absf(float(choice["va"]) - 275.0) < 1.0e-9, "the stated capacity, not the nearest choice")
	assert(panel._va_option.item_count == PanelScript.VA_CHOICES.size() + 1,
		"the conventional capacities plus the stated one")
	panel.free()


func test_the_budget_line_names_what_the_transformer_buys() -> void:
	var panel = _panel()
	assert(panel.budget_text().contains("No transformer stated"))
	panel.set_transformer(Lighting.make_transformer(100.0, 12.0))
	# Twenty-five path lights draw all of 100 VA, so the budget is twenty-five.
	assert(panel.budget_text().contains("25"), "twenty-five path lights: %s" % panel.budget_text())
	assert(panel.budget_text().contains("100 VA at 12 V"), "and the transformer it is stated as")
	panel.free()


# --- the circuit list -----------------------------------------------------------------


func test_the_rows_a_drawing_offers_are_listed_one_each() -> void:
	var panel = _panel()
	assert(panel.set_circuits([_circuit(1, "Circuit 1", 1), _circuit(2, "Circuit 2", 2)]))
	assert(panel.circuit_rows().size() == 2)
	assert(panel._circuit_list.item_count == 2)
	assert(panel.status_text().contains("2 circuits"), "and the status counts them")
	panel.free()


func test_taking_a_circuit_off_asks_for_the_number_that_was_chosen() -> void:
	var panel = _panel()
	panel.set_circuits([_circuit(1, "Circuit 1", 1), _circuit(2, "Circuit 2", 2)])
	assert(panel.selected_circuit_number() == 0, "nothing is chosen until a person chooses")
	assert(panel._remove_button.disabled, "so the button is dead")
	var asked: Array = []
	panel.remove_requested.connect(
		func(number: int) -> void: asked.append(number))
	panel._circuit_list.select(1)
	panel._on_circuit_selected(1)
	assert(panel.selected_circuit_number() == 2)
	assert(not panel._remove_button.disabled)
	assert(panel.remove_selected())
	assert(asked.size() == 1 and int(asked[0]) == 2)
	panel.free()


func test_a_said_line_reports_what_last_happened() -> void:
	var panel = _panel()
	panel.set_areas([_area(1, "bed 1", 12.5)])
	panel.say("Circuit 1 will run: 16 well lights, 80 W of 100 VA")
	assert(panel.status_text() == "Circuit 1 will run: 16 well lights, 80 W of 100 VA")
	assert(panel.said() != "")
	panel.reset()
	assert(panel.said() == "", "a reset clears the line")
	panel.free()


# --- the one rule ---------------------------------------------------------------------


func test_nothing_in_the_panel_takes_the_keyboard() -> void:
	var panel = _panel()
	assert(panel.list_is_keyboard_free(), "every control is FOCUS_NONE")
	panel.free()