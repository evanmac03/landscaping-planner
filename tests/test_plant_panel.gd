extends Node
## The plants section of the palette: what it lists, what narrows it, and what it asks for.
##
## Like the palette and the browser, the panel is built in code, so a bare `PlantPanel.new()` plus
## `bind()` is the whole panel with no scene tree. The one thing these tests hold that the browser's
## do not is the keyboard rule: nothing in this HUD may take the keyboard away from the drawing, and
## this panel has more kinds of control in it than any other, so the rule is asserted here rather
## than assumed.

const PanelScript := preload("res://scripts/plant_panel.gd")
const CatalogueScript := preload("res://scripts/plant_catalogue.gd")
const SpeciesScript := preload("res://scripts/plant_species.gd")

const SEED := "res://data/plants/nursery_list.json"

const MAPLE := &"acer-rubrum-autumn-blaze"
const BOXWOOD := &"buxus-sempervirens"


func _catalogue() -> PlantCatalogue:
	var read: Dictionary = CatalogueScript.load_from(SEED)
	assert(bool(read["ok"]), "the shipped list loads: %s" % String(read["reason"]))
	return read["catalogue"]


func _panel(catalogue: PlantCatalogue = null) -> PlantPanel:
	var panel: PlantPanel = PanelScript.new()
	panel.build("Library... (L)")
	panel.bind(catalogue if catalogue != null else _catalogue())
	return panel


## A catalogue of numbered plants, for the question the shipped list cannot ask: what happens when
## there are more species than the panel is willing to list.
func _many(count: int) -> PlantCatalogue:
	var catalogue: PlantCatalogue = CatalogueScript.new()
	for number in count:
		var species: PlantSpecies = SpeciesScript.make(
			StringName("plant-%03d" % number),
			"Botanica %03d" % number,
			"Common %03d" % number,
			100 + number,
			60 + number
		)
		species.tags.assign(["trial"])
		catalogue.add(species)
	return catalogue


# --- what it lists ------------------------------------------------------------------------


func test_the_panel_lists_the_catalogue_by_the_name_a_person_uses() -> void:
	var catalogue: PlantCatalogue = _catalogue()
	var panel: PlantPanel = _panel(catalogue)
	var listed: Array[StringName] = panel.listed_ids()
	# The whole starter list, not a slice of it: a palette that hides most of the catalogue behind a
	# cap it does not mention is worse than one that makes a person scroll.
	assert(listed.size() == catalogue.count(),
		"the whole shipped list is listed: %d of %d" % [listed.size(), catalogue.count()])
	assert(listed.has(MAPLE), "including the maple")
	# By the name a person uses rather than the one a nursery sends: the label on a red maple is
	# "Red maple", and "Acer rubrum" is what they write down afterwards.
	var first: PlantSpecies = panel.catalogue.get_species(listed[0])
	assert(first != null, "the first row is a plant")
	assert(first.common_name.begins_with("A"), "the list is in common-name order: %s" % first.common_name)
	assert(panel.status_text() == "%d species." % catalogue.count(),
		"and the panel says how many: %s" % panel.status_text())
	panel.free()


func test_a_catalogue_with_no_names_still_lists_by_its_botanical_name() -> void:
	# A nursery list from a grower with no common names on it is still a list you can plant from.
	var catalogue: PlantCatalogue = CatalogueScript.new()
	var anonymous: PlantSpecies = SpeciesScript.make(&"mystery", "Mysteriorum ignotum", "", 90, 45)
	catalogue.add(anonymous)
	var panel: PlantPanel = _panel(catalogue)
	assert(panel.listed_ids() == [&"mystery"], "the plant is listed")
	assert(panel.selected_id() == &"", "and nothing is chosen yet")
	panel.select(&"mystery")
	assert(panel.place_selected(), "it can be placed")
	# What the HUD does with that: arm it, then tell the panel. The panel has no artillery of its own.
	panel.refresh(&"mystery", 1)
	assert(panel.status_text().begins_with("Planting Mysteriorum"), "under its botanical name")
	panel.free()


func test_a_catalogue_bigger_than_the_list_is_capped_and_says_so() -> void:
	# A palette is a quick picker, not a browser. The honest thing is to say what is not shown
	# rather than to quietly leave most of a catalogue out.
	var over: int = PanelScript.MAX_LISTED + 80
	var panel: PlantPanel = _panel(_many(over))
	assert(panel.listed_ids().size() == PanelScript.MAX_LISTED, "the list is capped")
	assert(panel.status_text().contains("Showing the first %d of %d" % [PanelScript.MAX_LISTED, over]),
		"and says how much of the catalogue it is not showing: %s" % panel.status_text())
	panel.free()


# --- choosing, and what a click would plant -------------------------------------------------


func test_choosing_a_plant_asks_for_it_and_placing_needs_a_choice() -> void:
	var panel: PlantPanel = _panel()
	var asked: Array[StringName] = []
	panel.plant_chosen.connect(func(species_id: StringName) -> void:
		asked.append(species_id)
	)
	assert(not panel.place_selected(), "nothing is chosen yet")
	assert(asked.is_empty(), "so nothing is asked for")
	# Nothing chosen is not a state the panel has to *say* anything about: the button that would
	# plant is dead, and says why on itself.
	var place: Button = panel.get_node("Actions/PlaceButton")
	assert(place.disabled, "and the button that would plant is dead")
	assert(place.tooltip_text == "Choose a plant first", "and says why: %s" % place.tooltip_text)

	assert(panel.select(MAPLE), "the maple can be chosen")
	assert(panel.selected_id() == MAPLE, "and is")
	assert(not place.disabled, "which wakes the button up")
	assert(panel.place_selected(), "and placing it asks for it")
	assert(asked == [MAPLE], "by name")
	assert(panel.selected_id() == MAPLE, "and it stays chosen, so a bed is a run of clicks")
	panel.free()


func test_a_plant_that_is_not_listed_cannot_be_chosen() -> void:
	# Refuse rather than choose something else: a panel that answers a question about one plant with
	# another is worse than one that says no.
	var panel: PlantPanel = _panel()
	assert(not panel.select(&"not-a-plant"), "an unknown plant cannot be chosen")
	assert(panel.selected_id() == &"", "and nothing was chosen in its place")
	# The boxwood is real, and not a shade tree, so it is not on the list while that tag is on.
	assert(panel.set_tag_filter("shade tree"), "narrow the list to the shade trees")
	assert(not panel.listed_ids().has(BOXWOOD), "the boxwood is not one of them")
	assert(not panel.select(BOXWOOD), "so it cannot be chosen")
	assert(panel.selected_id() == &"", "and still nothing was chosen in its place")
	panel.free()


func test_the_plant_in_hand_is_shown_as_chosen_and_says_how_many_stand() -> void:
	# The panel is refreshed every frame by the HUD, and what is in hand has to read off it: a
	# designer who looks down at the palette must be able to see what a click would plant.
	var panel: PlantPanel = _panel()
	var total: int = panel.catalogue.count()
	panel.refresh(&"", 0)
	assert(panel.status_text() == "%d species." % total, "with nothing in hand it is just the list")
	panel.refresh(MAPLE, 30)
	assert(panel.selected_id() == MAPLE, "the plant in hand is the chosen row")
	assert(panel.status_text().begins_with("Planting Red maple"), "and is named")
	assert(panel.status_text().contains("30 standing"), "with the count: %s" % panel.status_text())
	# And a planted count that changes does not rebuild the list under the person's hand.
	var before: Array[StringName] = panel.listed_ids()
	panel.refresh(MAPLE, 31)
	assert(panel.listed_ids() == before, "the list is not rebuilt for a count")
	panel.refresh(&"", 0)
	assert(panel.status_text() == "%d species." % total, "and putting it away reads as the plain list again")
	panel.free()


func test_choosing_another_plant_while_one_is_in_hand_replaces_what_is_in_hand() -> void:
	# The panel re-selects what is in hand on every refresh, so a click on another row would be undone
	# before it could be read unless the click is taken as a change of mind. Nothing in hand is a
	# different matter: there the row is only a choice, and the Place button is the door to what is in
	# hand, so a click asks for nothing on its own.
	var panel: PlantPanel = _panel()
	var asked: Array[StringName] = []
	panel.plant_chosen.connect(func(id: StringName) -> void: asked.append(id))
	var listed: Array[StringName] = panel.listed_ids()
	var other: StringName = listed[0] if listed[0] != MAPLE else listed[1]
	assert(other != MAPLE, "the test needs two different plants")

	panel.select(MAPLE)
	asked.clear()
	_click_row(panel, listed.find(other))
	assert(asked.is_empty(), "a row clicked with nothing in hand asks for nothing")

	panel.refresh(MAPLE, 3)
	asked.clear()
	_click_row(panel, listed.find(other))
	assert(asked == [other], "a row clicked while something is in hand replaces it: %s" % [asked])
	# The panel has no artillery of its own: the HUD arms what was asked for and tells it, which is the
	# same refresh every placement ends with. Without that the panel would go on naming the old plant.
	panel.refresh(other, 3)
	assert(panel.selected_id() == other, "and the row shown as chosen is the one that was clicked")
	assert(panel.status_text().begins_with("Planting"), "named on the line: %s" % panel.status_text())

	# Clicking the plant that is already in hand is not a change, so it asks for nothing: a run of
	# clicks on one plant to put down a bed must not re-arm it every time.
	asked.clear()
	_click_row(panel, listed.find(other))
	assert(asked.is_empty(), "clicking the plant already in hand changes nothing")
	panel.free()


## One row clicked the way a person clicks it: the list takes the selection, then the panel is told.
## `ItemList.select` is programmatic and emits nothing, so both halves are needed to be a click.
func _click_row(panel: PlantPanel, row: int) -> void:
	assert(row >= 0, "the row is on the list")
	(panel.get_node("Species") as ItemList).select(row, false)
	panel._on_row_selected(row)


func test_a_panel_with_no_list_open_says_so_rather_than_failing() -> void:
	var panel: PlantPanel = PanelScript.new()
	panel.build()
	panel.bind(null)
	assert(panel.listed_ids().is_empty(), "nothing to show")
	assert(panel.status_text() == "No plant list open.", "and it says why")
	assert(not panel.place_selected(), "and nothing to place")
	assert(not panel.select(MAPLE), "and nothing to choose")
	panel.free()


# --- the tag drop-down ---------------------------------------------------------------------


func test_a_tag_narrows_the_list_and_an_unknown_tag_is_refused() -> void:
	var panel: PlantPanel = _panel()
	var all_count: int = panel.listed_ids().size()
	assert(panel.tag_filter().is_empty(), "the panel starts on every plant")
	assert(panel.set_tag_filter("shade tree"), "a tag the catalogue has can be chosen")
	assert(panel.tag_filter() == "shade tree", "and the panel is narrowed to it")
	var narrowed: Array[StringName] = panel.listed_ids()
	assert(narrowed.size() > 0 and narrowed.size() < all_count,
		"which is some of the list and not all of it: %d of %d" % [narrowed.size(), all_count])
	for species_id: StringName in narrowed:
		assert(panel.catalogue.get_species(species_id).tags.has("shade tree"),
			"%s carries the tag" % species_id)
	assert(panel.status_text() == "%d of %d species." % [narrowed.size(), all_count],
		"and the count says what it is not showing: %s" % panel.status_text())

	assert(not panel.set_tag_filter("nonsense"), "a tag no plant carries is refused")
	assert(panel.tag_filter() == "shade tree", "and the filter is left as it was")
	assert(panel.listed_ids() == narrowed, "and so is the list")
	assert(panel.set_tag_filter(""), "every plant can be asked for again")
	assert(panel.listed_ids().size() == all_count, "and the list is whole")
	panel.free()


func test_a_tag_that_the_catalogue_loses_falls_back_to_every_plant() -> void:
	# A catalogue can be replaced by an import. A filter left pointing at a tag that no longer exists
	# would show an empty panel and look like a broken list.
	var panel: PlantPanel = _panel()
	panel.set_tag_filter("shade tree")
	assert(panel.listed_ids().size() > 0, "the filter is on")
	panel.bind(_many(3))
	assert(panel.tag_filter().is_empty(), "a catalogue with no 'shade tree' in it clears the filter")
	assert(panel.listed_ids().size() == 3, "and the panel shows the new catalogue rather than nothing")
	panel.free()


# --- the rule this panel has that the browser does not -------------------------------------


func test_nothing_in_the_panel_takes_the_keyboard() -> void:
	# The library is a `Window` and is allowed to hold the keyboard while it is up. This is not: it
	# lives in the palette, beside the drawing tools, so every key it swallowed would be an arrow key
	# or a tool number taken away from the drawing.
	var panel: PlantPanel = _panel()
	assert(panel.list_is_keyboard_free(), "the list, the drop-down and the buttons are all focus-free")
	# Named individually as well as in one line, so a failure says which control went wrong.
	assert(panel.get_node("Species").focus_mode == Control.FOCUS_NONE, "the list")
	assert(panel.get_node("TagRow/TagOption").focus_mode == Control.FOCUS_NONE, "the tag drop-down")
	assert(panel.get_node("Actions/PlaceButton").focus_mode == Control.FOCUS_NONE, "place")
	assert(panel.get_node("Actions/StopButton").focus_mode == Control.FOCUS_NONE, "stop")
	assert(panel.get_node("Header/LibraryButton").focus_mode == Control.FOCUS_NONE, "the library button")
	# The controls that fill a bed are the newest thing in the panel and the easiest to forget: a
	# drop-down that keeps the keyboard is a number key that stops arming a tool.
	assert(panel.get_node("FillRow/SpacingOption").focus_mode == Control.FOCUS_NONE, "the spacing")
	assert(panel.get_node("FillRow/ArrangementOption").focus_mode == Control.FOCUS_NONE, "the rows")
	assert(panel.get_node("BedRow/BedOption").focus_mode == Control.FOCUS_NONE, "the bed")
	assert(panel.get_node("FillButton").focus_mode == Control.FOCUS_NONE, "and the fill button")
	assert(not (panel.get_node("Species") as ItemList).allow_search,
		"and the list does not search, because letter keys belong to the drawing")
	panel.free()


# --- the signals the HUD listens to --------------------------------------------------------


func test_the_library_and_stop_are_asked_for_by_signal() -> void:
	# The panel owns no design state, so the two things that are not a species are asked for rather
	# than done: it has no window and no planting to stop.
	var panel: PlantPanel = _panel()
	var wanted: Array[String] = []
	panel.library_requested.connect(func() -> void: wanted.append("library"))
	panel.stop_requested.connect(func() -> void: wanted.append("stop"))
	(panel.get_node("Header/LibraryButton") as Button).pressed.emit()
	(panel.get_node("Actions/StopButton") as Button).pressed.emit()
	assert(wanted == ["library", "stop"], "both were asked for: %s" % " | ".join(wanted))
	assert(panel.library_label() == "Library... (L)", "and the button carries its key")
	panel.free()


func test_the_stop_button_is_dead_until_something_is_being_planted() -> void:
	# A button that does nothing should look like it does nothing.
	var panel: PlantPanel = _panel()
	var stop: Button = panel.get_node("Actions/StopButton")
	var place: Button = panel.get_node("Actions/PlaceButton")
	assert(stop.disabled, "nothing is being planted")
	assert(place.disabled, "and nothing is chosen")
	panel.select(MAPLE)
	assert(not place.disabled, "choosing a plant makes placing possible")
	panel.refresh(MAPLE, 1)
	assert(not stop.disabled, "and having one in hand makes stopping possible")
	panel.refresh(&"", 0)
	assert(stop.disabled, "and putting it away makes stopping impossible again")
	panel.free()


# --- filling a bed -------------------------------------------------------------------------


## A bed row as `PlantSpacing.bed_areas` returns one. The panel never sees an outline of its own
## making: a bed is an area of the drawing, and the outline in the row is the drawing's.
func _bed_row(key: String, name: String, area: float) -> Dictionary:
	return {
		"entity_id": 1 + absi(key.hash() % 100),
		"layer": &"400-NEW-BED",
		"key": key,
		"label": "bed",
		"name": name,
		"outline": PackedVector2Array([
			Vector2.ZERO, Vector2(4.0, 0.0), Vector2(4.0, 4.0), Vector2(0.0, 4.0),
		]),
		"area_m2": area,
	}


func test_the_beds_the_drawing_encloses_are_offered_and_a_change_is_reported() -> void:
	var panel: PlantPanel = _panel()
	var first := _bed_row("a", "bed 1", 12.0)
	var second := _bed_row("b", "bed 2", 6.0)
	assert(panel.set_beds([first, second]), "the list is taken")
	assert(panel.beds().size() == 2, "both beds are held")
	assert(panel.selected_bed_key() == "a", "and the first is on")

	# The same list again is not a change: the HUD offers this every refresh, and rebuilding a
	# drop-down sixty times a second would close it out from under whoever is using it.
	assert(not panel.set_beds([first, second]), "the same beds are not a change")

	# A bed that is still there stays chosen, however the list has been reordered around it.
	assert(panel.set_beds([second, first]), "a reordered list is a change")
	assert(panel.selected_bed_key() == "a", "and the bed that was chosen is still chosen")

	# A bed the drawing no longer encloses cannot stay chosen. The drop-down moves to the first bed
	# rather than sitting empty with a dead button under it.
	assert(panel.set_beds([second]), "one bed left")
	assert(panel.selected_bed_key() == "b", "and the drop-down is on the one that is left")

	assert(panel.set_beds([]), "a drawing with no beds")
	assert(panel.selected_bed_key().is_empty(), "has nothing to fill")
	panel.free()


func test_the_fill_button_is_dead_until_there_is_both_a_plant_and_a_bed() -> void:
	var panel: PlantPanel = _panel()
	var fill: Button = panel.get_node("FillButton")
	assert(fill.disabled, "nothing chosen, nothing to fill")
	assert(fill.tooltip_text.contains("Choose a plant"), "and it says which: %s" % fill.tooltip_text)

	panel.select(MAPLE)
	assert(fill.disabled, "a plant and no bed is still no fill")
	assert(fill.tooltip_text.contains("no bed"), "and it says so: %s" % fill.tooltip_text)

	panel.set_beds([_bed_row("a", "bed 1", 12.0)])
	assert(not fill.disabled, "both halves and the button is live")
	assert(fill.tooltip_text.contains("bed 1"), "and it names the bed: %s" % fill.tooltip_text)
	assert(fill.tooltip_text.contains("Its own spread"), "and what the spacing is: %s" % fill.tooltip_text)
	panel.free()


## The spacing is what the drop-down says, and the first choice is the plant's own spread - which is
## zero, because the spread is a property of the plant and not of this list.
func test_the_choices_are_the_ones_the_drop_downs_show() -> void:
	var panel: PlantPanel = _panel()
	assert(panel.spacing_choice() == 0.0, "its own spread to begin with")
	assert(panel.arrangement_choice() == "triangular", "and staggered rows, as a planting plan draws")
	assert(panel.set_spacing_choice(0.45), "a round spacing can be asked for by value")
	assert(panel.spacing_choice() == 0.45)
	assert(panel.set_arrangement_choice("square"), "so can an arrangement")
	assert(panel.arrangement_choice() == "square")
	assert(not panel.set_spacing_choice(0.123), "and one the list does not offer is refused")
	assert(panel.spacing_choice() == 0.45, "rather than replacing what is chosen")
	assert(not panel.set_arrangement_choice("hexagonal"), "as is an arrangement nobody offers")
	assert(panel.arrangement_choice() == "square")
	panel.free()


func test_filling_asks_for_the_bed_the_spacing_and_the_arrangement() -> void:
	var panel: PlantPanel = _panel()
	panel.select(BOXWOOD)
	panel.set_beds([_bed_row("a", "bed 1", 12.0), _bed_row("b", "bed 2", 6.0)])
	var asked: Array = []
	panel.fill_requested.connect(
		func(bed_key: String, spacing: float, arrangement: String) -> void:
			asked.append([bed_key, spacing, arrangement])
	)

	assert(panel.fill_selected(), "a plant and a bed is a fill")
	assert(asked.size() == 1, "and it was asked for once")
	assert(String(asked[0][0]) == "a", "the bed it names: %s" % String(asked[0][0]))
	assert(float(asked[0][1]) == 0.0, "the spacing it is on")
	assert(String(asked[0][2]) == "triangular", "and the arrangement")

	panel.set_spacing_choice(0.6)
	panel.set_arrangement_choice("square")
	panel.fill_selected()
	assert(float(asked[1][1]) == 0.6, "changing the controls changes what is asked for")
	assert(String(asked[1][2]) == "square")

	# The button goes through the same door, so a click and a call cannot ask for two different fills.
	(panel.get_node("FillButton") as Button).pressed.emit()
	assert(asked.size() == 3, "the button fills by the same signal")

	# And with nothing chosen there is nothing to ask for.
	panel.free()
	var fresh: PlantPanel = _panel()
	fresh.set_beds([_bed_row("a", "bed 1", 12.0)])
	assert(not fresh.fill_selected(), "no plant, no fill")
	fresh.free()


func test_a_fill_reports_itself_beside_the_plant_count_and_a_new_plant_clears_it() -> void:
	var panel: PlantPanel = _panel()
	panel.select(BOXWOOD)
	panel.set_beds([_bed_row("a", "bed 1", 12.0)])
	panel.say("38 x Buxus sempervirens at 0.45 m, staggered")
	assert(panel.status_text() == "38 x Buxus sempervirens at 0.45 m, staggered",
		"what just happened is what the panel says: %s" % panel.status_text())

	# A new plant in hand is a new act, and the report of the last one is not news any more.
	panel.refresh(MAPLE, 38)
	assert(not panel.status_text().contains("Buxus"), "a new choice clears it: %s" % panel.status_text())
	# What is left is the line about what is in hand, which is the one a person needs while planting.
	assert(panel.status_text().contains("Red maple") and panel.status_text().contains("38"),
		"the line is about the plant in hand: %s" % panel.status_text())

	# A count on its own does not: a fill changes how many are standing, and the report is what says so.
	panel.say("nothing to report")
	panel.refresh(MAPLE, 40)
	assert(panel.status_text() == "nothing to report", "the plant count moving is not a new act")
	panel.free()