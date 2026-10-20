extends Node
## Tests for the hatch panel: the region list, the four choices, what each choice greys out, and the
## one rule every panel in this HUD obeys - nothing in it takes the keyboard.
##
## Built with a bare `HatchPanel.new()` and driven by hand, so there is no scene tree and no HUD:
## the panel only says what was asked for and a signal carries it away.

const HatchPanelScript := preload("res://scripts/hatch_panel.gd")
const Fill := preload("res://scripts/draft/hatch_fill.gd")


func _row(id: int, name: String, area: float) -> Dictionary:
	return {"entity_id": id, "key": "bed#%d" % id, "name": name, "area_m2": area, "layer": &"400-NEW-BED"}


func _panel():
	var panel = HatchPanelScript.new()
	panel.build()
	return panel


# --- the region list ------------------------------------------------------------------


func test_a_panel_with_no_region_says_so_rather_than_failing() -> void:
	var panel = _panel()
	assert(panel.regions().is_empty())
	assert(panel.status_text().contains("encloses no region"))
	assert(not panel.fill_selected(), "there is nothing to fill")
	panel.free()


func test_the_regions_the_drawing_offers_are_the_ones_the_drop_down_shows() -> void:
	var panel = _panel()
	assert(panel.set_regions([_row(1, "bed 1", 12.5), _row(2, "paving 2", 30.0)]))
	assert(panel.regions().size() == 2)
	assert(panel.selected_region_key() == "bed#1", "the first region is chosen by default")
	assert(String(panel.selected_region()["name"]) == "bed 1")
	panel.free()


func test_a_new_list_keeps_the_choice_when_it_is_still_there() -> void:
	var panel = _panel()
	panel.set_regions([_row(1, "bed 1", 12.5), _row(2, "paving 2", 30.0)])
	panel.set_regions([_row(2, "paving 2", 30.0), _row(1, "bed 1", 12.5)])
	assert(panel.selected_region_key() == "bed#1", "a bed drawn elsewhere does not move the choice")
	panel.free()


# --- what a fill asks for -------------------------------------------------------------


func test_choosing_a_region_and_filling_asks_for_it_by_signal() -> void:
	var panel = _panel()
	panel.set_regions([_row(7, "bed 7", 12.0)])
	var asked: Array = []
	panel.fill_requested.connect(
		func(id: int, options: Dictionary) -> void: asked.append([id, options]))
	assert(panel.fill_selected())
	assert(asked.size() == 1)
	assert(int(asked[0][0]) == 7)
	assert(StringName(asked[0][1]["pattern"]) == Fill.HATCH)
	assert(absf(float(asked[0][1]["spacing_mm"]) - 2.0) < 1.0e-9)
	panel.free()


func test_the_pattern_choice_is_the_one_the_drop_down_shows() -> void:
	var panel = _panel()
	assert(panel.pattern_choice() == Fill.HATCH)
	assert(panel.set_pattern(Fill.STIPPLE))
	assert(panel.pattern_choice() == Fill.STIPPLE)
	assert(panel.options()["symbol"] == Fill.SYMBOL_DOT)
	panel.free()


func test_a_choice_that_cannot_matter_is_greyed_rather_than_hidden() -> void:
	var panel = _panel()
	# Solid has no spacing to set; a stipple's angle does nothing and its symbol does.
	panel.set_pattern(Fill.SOLID)
	assert(panel._spacing_option.disabled, "a solid fill has no spacing")
	panel.set_pattern(Fill.STIPPLE)
	assert(not panel._spacing_option.disabled, "a stipple is spaced")
	assert(panel._angle_option.disabled, "a stipple has no angle")
	assert(not panel._symbol_option.disabled, "a stipple has a symbol to choose")
	panel.set_pattern(Fill.HATCH)
	assert(not panel._angle_option.disabled)
	assert(panel._symbol_option.disabled, "a line hatch draws no symbols")
	panel.free()


func test_the_fill_button_is_dead_until_there_is_a_region() -> void:
	var panel = _panel()
	assert(panel._fill_button.disabled)
	panel.set_regions([_row(1, "bed 1", 12.5)])
	assert(not panel._fill_button.disabled)
	panel.free()


func test_a_said_line_reports_what_last_happened() -> void:
	var panel = _panel()
	panel.set_regions([_row(1, "bed 1", 12.5)])
	panel.say("filled the region: Crosshatch, 40 lines")
	assert(panel.status_text() == "filled the region: Crosshatch, 40 lines")
	assert(panel.said() != "")
	panel.free()


# --- the one rule ---------------------------------------------------------------------


func test_nothing_in_the_panel_takes_the_keyboard() -> void:
	var panel = _panel()
	assert(panel.list_is_keyboard_free(), "every control is FOCUS_NONE")
	panel.free()