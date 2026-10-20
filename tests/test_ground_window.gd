extends Node
## The ground window: the site's conditions, and one statement per area of the plan.
##
## Driven the way a click drives it - `build()`, then the same methods the controls call - because the
## window is built by hand (`_ready` would show an empty frame for a frame) and because a `Window` in
## a test is a window nobody has to look at.
##
## Two rules are under test here, and both are about **what a statement is allowed to be**:
##
## * an area states **only what the designer changed** about it, never the conditions it inherits from
##   the site - or the area would stop following the site the moment somebody edited it;
## * the boxes show what the area *states* while the line beside them shows what that *comes to*, which
##   are two different things and an editor needs both.

const WindowScript := preload("res://scripts/ground_window.gd")
const Profile := preload("res://scripts/terrain_profile.gd")
const ZoneMapScript := preload("res://scripts/zone_map.gd")
const Species := preload("res://scripts/plant_species.gd")
const Entity := preload("res://scripts/draft/draft_entity.gd")
const Document := preload("res://scripts/draft/draft_document.gd")
const LayerSet := preload("res://scripts/draft/layer_set.gd")
const Ctrl := preload("res://scripts/draft/draft_controller.gd")
const Tool := preload("res://scripts/draft/draft_tool.gd")
const SnapScript := preload("res://scripts/draft/snap_engine.gd")

const SUN := Species.FULL_SUN
const SHADE := Species.FULL_SHADE
const DRY := Species.WATER_LOW
const DAMP := Species.WATER_MEDIUM


## A drawing with one of each kind of ground: a bed, a lawn and a patio.
func _drawing() -> DraftDocument:
	var document: DraftDocument = Document.new()
	document.add(Entity.make_rectangle(Vector2(0.0, 0.0), Vector2(6.0, 3.0)), LayerSet.NEW_BED)
	document.add(Entity.make_rectangle(Vector2(12.0, 0.0), Vector2(4.0, 4.0)), LayerSet.NEW_TURF)
	document.add(Entity.make_rectangle(Vector2(0.0, 12.0), Vector2(4.0, 4.0)), LayerSet.NEW_HARDSCAPE)
	# A line on a bed layer encloses nothing, so it is not an area anybody can state.
	document.add(Entity.make_line(Vector2(20.0, 0.0), Vector2(24.0, 0.0)), LayerSet.NEW_BED)
	return document


func _window(document: DraftDocument = null) -> GroundWindow:
	var window: GroundWindow = WindowScript.new()
	window.build()
	window.document = document if document != null else _drawing()
	window.refresh()
	return window


func _line_named(window: GroundWindow, name: String) -> String:
	for text: String in window.area_list_texts():
		if text.begins_with(name):
			return text
	return ""


# --- what it shows -------------------------------------------------------------------------


func test_the_window_lists_the_site_and_every_area_of_the_plan() -> void:
	var window: GroundWindow = _window()
	assert(window.area_count() == 3, "three areas enclose ground: %d" % window.area_count())
	var texts: Array[String] = window.area_list_texts()
	assert(texts.size() == 3)
	for index in texts.size():
		assert(texts[index].contains("nothing stated"), "nothing is known yet: %s" % texts[index])
	# Read by name, not by position: the list is in **draw order**, and the drawing draws its paving
	# band before its bed band - the order the areas plot in is not the order somebody drew them in.
	assert(_line_named(window, "bed 1").contains("18.0 m²"), _line_named(window, "bed 1"))
	assert(_line_named(window, "lawn 2").contains("16.0 m²"), _line_named(window, "lawn 2"))
	assert(_line_named(window, "paving 3").contains("16.0 m²"), _line_named(window, "paving 3"))
	# A bed nobody has described is named as nothing stated, and the window says so in one line too.
	assert(window.status_text().contains("Nothing is stated about the ground yet"), window.status_text())
	window.free()


func test_a_window_with_no_drawing_says_so_rather_than_failing() -> void:
	var window: GroundWindow = WindowScript.new()
	window.build()
	window.document = null
	window.refresh()
	assert(window.area_count() == 0)
	assert(window.status_text().contains("there is no drawing open"), window.status_text())
	assert(window.select_area_by_name("bed 1") == false, "and nothing can be selected")
	window.apply_area()
	assert(window.status_text().contains("there is no drawing open"), "and nothing can be stated")
	window.free()


# --- what it states ------------------------------------------------------------------------


func test_choosing_a_site_condition_states_it_and_only_it() -> void:
	var document: DraftDocument = _drawing()
	var window: GroundWindow = _window(document)
	assert(window.choose_site("sun", SHADE), "the site's light can be stated")
	assert(document.environment.base.sun_level() == SHADE)
	assert(not document.environment.base.has("moisture"), "and nothing else is claimed")
	assert(document.environment.zones.is_empty(), "no area was invented")
	# Choosing "not stated" takes the statement back: the way out of a claim must exist.
	assert(window.choose_site("sun", Profile.no_value("sun")), "the site's light can be unstated")
	assert(document.environment.base.is_empty(), "and the site states nothing again")
	window.free()


func test_stating_an_area_stores_only_what_was_changed() -> void:
	# The site is shade on clay. The bed is dry, and saying so must not also record the shade and the
	# clay on the bed: a zone that restates the whole site is a zone that has stopped following it.
	var document: DraftDocument = _drawing()
	var window: GroundWindow = _window(document)
	window.choose_site("sun", SHADE)
	window.choose_site("soil", Profile.CLAY)
	assert(window.select_area_by_name("bed 1"), "the bed can be selected")
	assert(window.choose_area("moisture", DRY))
	window.apply_area()
	assert(document.environment.zone_count() == 1, "one zone")
	var zone: ZoneMapScript.Zone = document.environment.zones[0]
	assert(zone.profile.moisture_level() == DRY, "the bed is dry")
	assert(zone.profile.stated_keys() == ["moisture"], "and says nothing else: %s" % str(zone.profile.stated_keys()))
	assert(zone.name == "bed 1", "the zone is named for the area it came from")
	assert(zone.source == ZoneMapScript.area_key(LayerSet.NEW_BED, 1), zone.source)
	# The effect at the bed is the site's conditions under the bed's own.
	var ground: Profile = document.environment.profile_at(Vector2(0.0, 0.0))["profile"]
	assert(ground.sun_level() == SHADE and ground.soil_name() == Profile.CLAY)
	assert(ground.moisture_level() == DRY)
	window.free()


func test_the_boxes_show_the_statement_and_the_line_shows_what_it_comes_to() -> void:
	# Two different questions, and an editor that confused them would pre-fill every box with an
	# inherited value and store it the moment somebody changed one thing.
	var document: DraftDocument = _drawing()
	var window: GroundWindow = _window(document)
	window.choose_site("sun", SHADE)
	window.choose_site("moisture", DAMP)
	assert(window.select_area_by_name("bed 1"))
	assert(window.area_status_text().contains("the site's own conditions"), window.area_status_text())
	assert(window.area_status_text().contains("full shade"), window.area_status_text())
	# The boxes are for the area's own statement, so they start empty.
	assert(window.area_choice().is_empty(), "the bed states nothing yet")
	window.choose_area("moisture", DRY)
	window.apply_area()
	assert(_line_named(window, "bed 1").contains("stated: low water"), _line_named(window, "bed 1"))
	# The line now shows the whole effect: the site's light, and the bed's own moisture.
	assert(window.area_status_text().contains("full shade, low water"), window.area_status_text())
	# Re-applying the same statement edits the zone rather than stacking another one.
	window.select_area_by_name("bed 1")
	assert(window.area_choice().moisture_level() == DRY, "the box shows what the bed states")
	assert(not window.area_choice().has("sun"), "and not what it inherits")
	window.apply_area()
	assert(document.environment.zone_count() == 1, "still one zone")
	window.free()


func test_taking_an_area_back_returns_it_to_the_site() -> void:
	var document: DraftDocument = _drawing()
	var window: GroundWindow = _window(document)
	window.choose_site("moisture", DAMP)
	window.select_area_by_name("paving 3")
	window.choose_area("sun", SUN)
	window.apply_area()
	assert(document.environment.zone_count() == 1)
	assert(_line_named(window, "paving 3").contains("stated: full sun"), _line_named(window, "paving 3"))
	window.clear_area()
	assert(document.environment.zone_count() == 0, "the statement was taken back")
	assert(_line_named(window, "paving 3").contains("medium water"), _line_named(window, "paving 3"))
	assert(window.status_text().contains("back to"), window.status_text())
	# Taking back something that was never stated says so rather than pretending to act.
	window.clear_area()
	assert(window.status_text().contains("nothing stated by hand"), window.status_text())
	window.free()


func test_reading_the_drawing_keeps_what_a_person_stated() -> void:
	var document: DraftDocument = _drawing()
	var window: GroundWindow = _window(document)
	window.select_area_by_name("bed 1")
	window.choose_area("moisture", DRY)
	window.apply_area()
	window.read_drawing()
	# The patio is read from the drawing, and the bed keeps the statement somebody made about it.
	assert(document.environment.zone_count() == 2, "one read, one stated: %d" % document.environment.zone_count())
	assert(window.status_text().contains("Read 1 area"), window.status_text())
	var at_patio: Dictionary = document.environment.profile_at(Vector2(0.0, 12.0))
	assert(String(at_patio["place"]) == "hard surface", "the paving was read")
	assert((at_patio["profile"] as Profile).sun_level() == SUN)
	var at_bed: Dictionary = document.environment.profile_at(Vector2(0.0, 0.0))
	assert((at_bed["profile"] as Profile).moisture_level() == DRY, "the bed's statement survived")
	assert(String(at_bed["place"]) == "bed 1", "and it is what answers there")
	window.free()


# --- the dropdowns -------------------------------------------------------------------------


func test_every_value_a_dropdown_offers_is_a_value_the_model_accepts() -> void:
	# The dropdown's item index is how a choice is read back, so the round trip has to hold for every
	# attribute - and each set's "not stated" is a different value, which is the trap this is here for.
	# The list is the window's own `SETS`, so a condition added to the window cannot skip the check.
	for key: String in WindowScript.SETS:
		var values: Array = WindowScript.values_for(key)
		assert(not values.is_empty(), "%s offers something" % key)
		assert(not Profile.value_stated(key, values[0]), "%s starts with not stated" % key)
		for index in values.size():
			var value: Variant = values[index]
			assert(WindowScript.text_for(key, value) != "", "%s %d has words" % [key, index])
			assert(WindowScript.index_of(key, value) == index, "%s %d finds itself" % [key, index])
			if index > 0:
				assert(Profile.value_stated(key, value), "%s %d is a statement" % [key, index])
		assert(WindowScript.text_for(key, values[0]) == "not stated", key)
		assert(WindowScript.index_of(key, &"NONSENSE") == -1, "%s refuses what it does not offer" % key)
		assert(WindowScript.index_of(key, null) == -1, "%s refuses nothing at all" % key)
	# A name is not a level and a level is not a name: matching them by value alone would make every
	# nonsense light level read as "not stated" and every nonsense soil read as the first soil in the
	# table - and for moisture it would read as low water, which is a real thing to claim by mistake.
	assert(WindowScript.index_of("soil", 4) == -1, "a number is not a soil")
	assert(WindowScript.index_of("sun", &"LOAM") == -1, "a soil is not a light level")
	assert(WindowScript.index_of("moisture", &"NONSENSE") != 0, "nonsense is not low water")
	assert(WindowScript.index_of("sun", 4.0) == 3, "a level that came back from a file is still a level")
	# Zero is a real moisture level and the missing value for light: the same number, two meanings.
	assert(WindowScript.text_for("moisture", 0) == "low water")
	assert(WindowScript.text_for("sun", 0) == "not stated")
	assert(WindowScript.text_for("soil", &"CLAY") == "clay")
	assert(WindowScript.text_for("zone", 6) == "zone 6")

## Drainage is a condition of a *place*, not only of a plant: a boggy corner and a fast-draining bank
## in one garden are the whole reason conditions are stated per area. The window offers it at the site
## and at every area, and it reads back as a value the model accepts.
func test_drainage_is_a_condition_a_place_can_state() -> void:
	assert(WindowScript.SETS.has("drainage"), "the window offers drainage")
	assert(WindowScript.text_for("drainage", Species.DRAINS_FAST) == "fast-draining")
	assert(WindowScript.text_for("drainage", Species.DRAINS_SLOW) == "slow-draining")
	# Not stated comes first and is not a drainage: the first choice is a claim that can be withdrawn.
	var values: Array = WindowScript.values_for("drainage")
	assert(not Profile.value_stated("drainage", values[0]))
	assert(values.size() == 4, "three ways a place drains, and a way of saying nothing")


## A place drains one way, and one area's way does not become the site's: stating a bed fast-draining
## leaves the rest of the garden saying whatever it said.
func test_a_boggy_corner_is_stated_in_one_area_and_leaves_the_site_alone() -> void:
	var document: DraftDocument = _drawing()
	var window: GroundWindow = _window(document)
	window.choose_site("drainage", Species.DRAINS_SLOW)
	window.select_area_by_name("bed 1")
	window.choose_area("drainage", Species.DRAINS_FAST)
	assert(document.environment.zone_count() == 1, "one area stated, not the site")
	assert(document.environment.zones[0].profile.drainage_level() == Species.DRAINS_FAST)
	assert(document.environment.base.drainage_level() == Species.DRAINS_SLOW, "the site is unchanged")
	assert(_line_named(window, "bed 1").contains("fast-draining"), _line_named(window, "bed 1"))
	window.free()


## A ground zone has no entity behind it, so it is not in `areas_of`: the window reaches it through the
## map. It is listed beside the plan's areas, and stating conditions for it edits that one zone.
func test_a_ground_zone_drawn_by_hand_is_listed_beside_the_plan_areas() -> void:
	var document: DraftDocument = _drawing()
	var controller = Ctrl.new()
	controller.document = document
	controller.tool = Tool.new()
	controller.snap = SnapScript.new()
	var stated: Dictionary = controller.state_ground_zone(PackedVector2Array([
		Vector2(40.0, 40.0), Vector2(50.0, 40.0), Vector2(50.0, 50.0), Vector2(40.0, 50.0)]))
	assert(bool(stated["ok"]), String(stated["reason"]))
	var window: GroundWindow = _window(document)
	assert(window.area_count() == 4, "three areas of the plan and the hand zone")
	var found := ""
	for text: String in window.area_list_texts():
		if text.begins_with("ground zone 1"):
			found = text
	assert(found != "", str(window.area_list_texts()))
	# And it is stated like anything else, editing that one zone rather than stacking a second.
	window.select_area_by_name("ground zone 1")
	window.choose_area("drainage", Species.DRAINS_FAST)
	assert(document.environment.zone_count() == 1, "one zone, edited not stacked")
	assert(document.environment.zones[0].profile.drainage_level() == Species.DRAINS_FAST)
	window.free()
	controller.free()


## A zone whose outline is drawn by hand is not an area of the plan, so `areas_of` must not pick it up
## or the window would list it twice.
func test_a_hand_zone_is_not_an_area_of_the_plan() -> void:
	var document: DraftDocument = _drawing()
	var controller = Ctrl.new()
	controller.document = document
	controller.tool = Tool.new()
	controller.snap = SnapScript.new()
	controller.state_ground_zone(PackedVector2Array([
		Vector2(40.0, 40.0), Vector2(50.0, 40.0), Vector2(50.0, 50.0)]))
	assert(ZoneMapScript.areas_of(document).size() == 3, "areas_of sees only the plan's own areas")
	controller.free()


func test_choosing_a_condition_for_an_area_states_it_at_once() -> void:
	# The dropdowns apply as they are chosen, the same way the site's do: the ground a designer is
	# describing is the ground they are looking at, and a chosen-but-not-stated half-state is a state
	# nobody asked for.
	var document: DraftDocument = _drawing()
	var window: GroundWindow = _window(document)
	window.choose_site("sun", SHADE)
	window.select_area_by_name("bed 1")
	window.choose_area("moisture", DRY)
	assert(document.environment.zone_count() == 1, "choosing stated it")
	assert(window.status_text().contains("bed 1 is stated as low water"), window.status_text())
	assert(_line_named(window, "bed 1").contains("stated: low water"), _line_named(window, "bed 1"))
	# A second condition joins the first rather than replacing it.
	window.choose_area("soil", Profile.SAND)
	assert(document.environment.zones[0].profile.stated_keys() == ["moisture", "soil"], str(document.environment.zones[0].profile.stated_keys()))
	assert(document.environment.zone_count() == 1, "and it is still one zone")
	# Choosing "not stated" for the last stated attribute is no statement at all, so the area goes back
	# to following the site - not a zone that states nothing and changes no verdict.
	window.choose_area("moisture", Profile.no_value("moisture"))
	window.choose_area("soil", Profile.no_value("soil"))
	assert(document.environment.zone_count() == 0, "the area follows the site again")
	assert(window.status_text().contains("follows the site's own conditions"), window.status_text())
	assert(_line_named(window, "bed 1").contains("full shade"), "and the site's light answers for it")
	window.free()


func test_a_statement_is_one_undo_step_however_many_conditions_it_has() -> void:
	# Choose then commit: the button re-states what the dropdowns already said, and re-stating the same
	# thing is not a change - so a designer who presses it twice does not get two entries in the
	# history, and the ground they end up with is the ground they chose.
	var document: DraftDocument = _drawing()
	var window: GroundWindow = _window(document)
	window.select_area_by_name("paving 3")
	window.choose_area("sun", SUN)
	assert(document.environment.zone_count() == 1)
	window.apply_area()
	assert(document.environment.zone_count() == 1, "the button does not stack a second zone")
	assert(document.undo_last(), "and the statement can be undone")
	assert(document.environment.zone_count() == 0, "which takes it off again")
	window.free()
