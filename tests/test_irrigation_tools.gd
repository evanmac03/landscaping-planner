extends Node
## Watering as the controller runs it: a zone is laid out over an area of the plan, its heads land on
## the irrigation layer carrying what they are, and the supply is something somebody stated.
##
## The controller is built with its parts and no scene tree, exactly as the filling and selection
## commands are tested: watering a bed needs a document and a controller, and nothing else.

const Ctrl := preload("res://scripts/draft/draft_controller.gd")
const Tool := preload("res://scripts/draft/draft_tool.gd")
const Document := preload("res://scripts/draft/draft_document.gd")
const SnapScript := preload("res://scripts/draft/snap_engine.gd")
const Entity := preload("res://scripts/draft/draft_entity.gd")
const LayerSet := preload("res://scripts/draft/layer_set.gd")
const Irrigation := preload("res://scripts/draft/irrigation.gd")


func _controller():
	var controller = Ctrl.new()
	controller.document = Document.new()
	controller.snap = SnapScript.new()
	controller.tool = Tool.new()
	return controller


## A nine metre square: two throws each way, so a spray zone comes out the textbook nine heads.
func _bed(metres: float = 9.0) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(metres, 0.0), Vector2(metres, metres), Vector2(0.0, metres),
	])


## A bed on the drawing, so the areas a panel offers are the drawing's own.
func _drawn_bed(controller, metres: float = 9.0, layer: StringName = LayerSet.NEW_BED) -> int:
	controller.document.add(Entity.make_polyline(_bed(metres), true), layer)
	return controller.document.count()


# --- the supply -----------------------------------------------------------------------


func test_a_supply_that_has_not_been_stated_is_not_a_supply() -> void:
	var controller = _controller()
	assert(controller.irrigation_supply().is_empty(), "nothing is stated on a new drawing")
	assert(Irrigation.supply_words(controller.irrigation_supply()) == "no supply stated",
		"and it says so in words")
	assert(controller.irrigation_head_budget(Irrigation.SPRAY) == 0,
		"so the budget is nothing rather than a guess")
	controller.free()


func test_stating_the_supply_is_one_undo_step() -> void:
	var controller = _controller()
	var stated: Dictionary = controller.set_irrigation_supply(40.0, 350.0)
	assert(bool(stated["ok"]), "forty litres a minute at 350 kPa is a supply: %s"
		% String(stated.get("reason", "")))
	assert(absf(float(controller.irrigation_supply()["flow"]) - 40.0) < 0.001, "and it is remembered")
	assert(controller.irrigation_head_budget(Irrigation.SPRAY) == 4, "four spray heads fit")
	assert(controller.dirty, "stating a supply changes the drawing")
	assert(controller.document.undo_last(), "and it can be taken back")
	assert(controller.irrigation_supply().is_empty(), "leaving nothing stated")
	controller.free()


func test_a_supply_of_nothing_is_refused() -> void:
	var controller = _controller()
	assert(not bool(controller.set_irrigation_supply(0.0, 350.0)["ok"]), "no flow is not a supply")
	assert(not bool(controller.set_irrigation_supply(40.0, 0.0)["ok"]), "and no pressure is not either")
	assert(controller.irrigation_supply().is_empty(), "nothing was stated")
	controller.free()


# --- watering an area -----------------------------------------------------------------


func test_watering_a_bed_lays_the_heads_out_and_is_one_undo_step() -> void:
	var controller = _controller()
	controller.set_irrigation_supply(120.0, 350.0)
	var before: int = _drawn_bed(controller)
	var watered: Dictionary = controller.water_area(_bed(), Irrigation.SPRAY)
	assert(bool(watered["ok"]), "a nine metre bed takes nine spray heads: %s"
		% String(watered.get("reason", "")))
	assert(int(watered["placed"]) == 9, "nine heads on the plan: %d" % int(watered["placed"]))
	assert(controller.document.count() == before + 9, "and they are on the drawing")
	var zones := controller.irrigation_zones()
	assert(zones.size() == 1, "one zone is kept with the drawing")
	assert(int(zones[0]["number"]) == 1, "numbered one")
	assert(int(zones[0]["valve"]) == 1, "on valve one")
	assert(Irrigation.head_count(zones[0]) == 9, "holding its nine heads")
	assert(String(watered["verdict"]).contains("will run"), "and it says the zone runs: %s"
		% String(watered["verdict"]))
	assert(controller.document.undo_last(), "the whole watering comes off in one step")
	assert(controller.document.count() == before, "leaving the bed alone: %d" % controller.document.count())
	assert(controller.irrigation_zones().is_empty(), "and no zone")
	controller.free()


func test_the_heads_land_on_the_irrigation_layer_carrying_what_they_are() -> void:
	var controller = _controller()
	controller.set_irrigation_supply(120.0, 350.0)
	controller.water_area(_bed(), Irrigation.SPRAY)
	var heads := 0
	for entity in controller.document.entities():
		if not Irrigation.is_head_entity(entity):
			continue
		heads += 1
		assert(entity.layer == LayerSet.IRRIGATION, "on the irrigation layer: %s" % String(entity.layer))
		assert(Irrigation.zone_of_entity(entity) == 1, "belonging to Zone 1")
		assert(String(entity.meta[Irrigation.META_KIND]) == Irrigation.SPRAY, "and saying what it is")
		assert(Irrigation.NOZZLES.has(float(entity.meta[Irrigation.META_ARC])),
			"with a nozzle a person can buy: %s" % str(entity.meta[Irrigation.META_ARC]))
		assert(entity.kind == Entity.Kind.CIRCLE, "drawn as a circle")
		assert(entity.params[2] > 0.0, "with a radius on it: %f" % entity.params[2])
	assert(heads == 9, "nine heads: %d" % heads)
	# A head is a *symbol*: three millimetres across on the sheet, so at 1:100 it is 0.3 m of ground
	# and at 1:200 it is 0.6 m.
	assert(absf(_first_head_radius(controller) - 0.3) < 1e-6,
		"three millimetres on paper at 1:100 is 0.3 m of ground: %f" % _first_head_radius(controller))
	controller.plot_scale = 200.0
	controller.water_area(_bed(18.0), Irrigation.SPRAY)
	for entity in controller.document.entities():
		if Irrigation.zone_of_entity(entity) == 2:
			assert(absf(entity.params[2] - 0.6) < 1e-6,
				"twice the paper size at half the scale: %f" % entity.params[2])
	controller.free()


## The radius the first head on the drawing is drawn at, or 0 when there is none.
func _first_head_radius(controller) -> float:
	for entity in controller.document.entities():
		if Irrigation.is_head_entity(entity):
			return float(entity.params[2])
	return 0.0


func test_a_zone_that_would_not_run_is_not_put_on_the_drawing() -> void:
	# Nine spray heads draw 81 litres a minute and the supply gives 40: refused, and *nothing* lands -
	# a valve that cannot be opened is worse left on the drawing than said.
	var controller = _controller()
	controller.set_irrigation_supply(40.0, 350.0)
	var before: int = _drawn_bed(controller)
	var watered: Dictionary = controller.water_area(_bed(), Irrigation.SPRAY)
	assert(not bool(watered["ok"]), "nine heads will not run off forty litres a minute")
	assert(String(watered["reason"]).contains("4 of them fit"), "and the refusal says what fits: %s"
		% String(watered["reason"]))
	assert(controller.document.count() == before, "nothing was put on the drawing")
	assert(controller.irrigation_zones().is_empty(), "and no zone was kept")
	controller.free()


func test_watering_with_a_supply_nobody_stated_is_refused() -> void:
	var controller = _controller()
	var before: int = _drawn_bed(controller)
	var watered: Dictionary = controller.water_area(_bed(), Irrigation.SPRAY)
	assert(not bool(watered["ok"]), "a zone cannot be blessed on a supply nobody stated")
	assert(String(watered["reason"]).contains("supply has not been stated"),
		"and the reason is the supply: %s" % String(watered["reason"]))
	assert(controller.document.count() == before, "nothing was put on the drawing")
	controller.free()


func test_an_area_the_grid_cannot_be_laid_out_in_is_refused_in_words() -> void:
	var controller = _controller()
	controller.set_irrigation_supply(120.0, 350.0)
	var tiny := PackedVector2Array([
		Vector2(2.0, 1.6), Vector2(2.4, 2.0), Vector2(2.0, 2.4), Vector2(1.6, 2.0),
	])
	var watered: Dictionary = controller.water_area(tiny, Irrigation.SPRAY)
	assert(not bool(watered["ok"]), "an 0.8 m diamond takes no spray head")
	assert(String(watered["reason"]).contains("no grid line"), "and says why: %s"
		% String(watered["reason"]))
	controller.free()


func test_a_kind_nobody_has_is_refused() -> void:
	var controller = _controller()
	controller.set_irrigation_supply(120.0, 350.0)
	var watered: Dictionary = controller.water_area(_bed(), "mister")
	assert(not bool(watered["ok"]), "a mister is not a kind of head")
	assert(controller.irrigation_zones().is_empty(), "and no zone was made")
	controller.free()


func test_two_zones_are_numbered_and_valved_apart() -> void:
	var controller = _controller()
	controller.set_irrigation_supply(400.0, 350.0)
	controller.water_area(_bed(), Irrigation.SPRAY)
	var second: Dictionary = controller.water_area(_bed(18.0), Irrigation.MICRO)
	assert(bool(second["ok"]), "a second bed: %s" % String(second.get("reason", "")))
	var zones := controller.irrigation_zones()
	assert(zones.size() == 2, "two zones")
	assert(int(zones[1]["number"]) == 2, "the second is Zone 2")
	assert(int(zones[1]["valve"]) == 2, "on valve 2")
	assert(Irrigation.head_count(zones[1]) == int(second["placed"]), "holding its own heads")
	controller.free()


func test_the_supply_is_stated_for_the_whole_drawing_not_for_a_zone() -> void:
	# A second zone is checked against the same supply, so a bigger bed is refused on the same
	# numbers rather than on ones of its own.
	var controller = _controller()
	controller.set_irrigation_supply(60.0, 350.0)
	# Sixteen micro-sprays over a nine metre bed draw 48 litres a minute and fit in 60.
	var small: Dictionary = controller.water_area(_bed(9.0), Irrigation.MICRO)
	assert(bool(small["ok"]), "sixteen micro-sprays fit: %s" % String(small.get("reason", "")))
	assert(int(small["placed"]) == 16, "sixteen of them: %d" % int(small["placed"]))
	var big: Dictionary = controller.water_area(_bed(30.0), Irrigation.SPRAY)
	assert(not bool(big["ok"]), "a thirty metre bed of spray heads does not")
	assert(int(controller.irrigation_zones().size()) == 1, "and only the first zone is kept")
	controller.free()


# --- taking a zone back off -----------------------------------------------------------


func test_taking_a_zone_off_takes_its_heads_with_it() -> void:
	var controller = _controller()
	controller.set_irrigation_supply(400.0, 350.0)
	controller.water_area(_bed(9.0), Irrigation.SPRAY)
	controller.water_area(_bed(18.0), Irrigation.MICRO)
	var heads_before := _heads(controller)
	var removed: Dictionary = controller.remove_zone(1)
	assert(bool(removed["ok"]), "Zone 1 comes off: %s" % String(removed.get("reason", "")))
	assert(int(removed["removed"]) == 9, "with its nine heads: %d" % int(removed["removed"]))
	assert(_heads(controller) == heads_before - 9, "and the rest of the drawing is left alone")
	var zones := controller.irrigation_zones()
	assert(zones.size() == 1, "one zone is left")
	assert(int(zones[0]["number"]) == 2, "and it is Zone 2")
	assert(_heads_of_zone(controller, 1) == 0, "no heads of Zone 1 remain")
	assert(_heads_of_zone(controller, 2) == Irrigation.head_count(zones[0]), "Zone 2's are all there")
	assert(controller.document.undo_last(), "and it is one step")
	assert(_heads_of_zone(controller, 1) == 9, "the heads come back with it")
	assert(controller.irrigation_zones().size() == 2, "and so does the zone")
	controller.free()


func test_taking_off_a_zone_that_is_not_there_says_so() -> void:
	var controller = _controller()
	var removed: Dictionary = controller.remove_zone(7)
	assert(not bool(removed["ok"]), "there is no Zone 7")
	assert(String(removed["reason"]) == "there is no Zone 7", "and it says which: %s"
		% String(removed["reason"]))
	controller.free()


func _heads(controller) -> int:
	var found := 0
	for entity in controller.document.entities():
		if Irrigation.is_head_entity(entity):
			found += 1
	return found


func _heads_of_zone(controller, number: int) -> int:
	var found := 0
	for entity in controller.document.entities():
		if Irrigation.zone_of_entity(entity) == number:
			found += 1
	return found


# --- a head and a run as the drawing holds them ---------------------------------------


func test_a_head_reads_as_a_line_and_is_marked_on_its_own_layer() -> void:
	var head := {"kind": Irrigation.SPRAY, "at": Vector2(2.0, 3.0), "heading": 0.0, "arc": 180.0}
	var entity := Irrigation.head_entity(head, 3, 100.0)
	assert(entity.layer == LayerSet.IRRIGATION, "on the irrigation layer")
	assert(Irrigation.is_head_entity(entity), "and marked as a head")
	assert(Irrigation.zone_of_entity(entity) == 3, "belonging to Zone 3")
	# The words a status bar or a legend writes, read off the head rather than off a caller.
	var words := Irrigation.head_words(head)
	assert(words.contains("spray head"), "the words name the kind: %s" % words)
	assert(words.contains("a half circle"), "and the nozzle: %s" % words)
	assert(Irrigation.head_words({"kind": Irrigation.ROTOR, "arc": 360.0}).contains("a full circle"),
		"a rotor with no arc of its own is a full circle")


func test_a_run_is_a_polyline_and_a_run_of_one_point_is_nothing() -> void:
	var entity := Irrigation.run_entity(PackedVector2Array([Vector2.ZERO, Vector2(3.0, 0.0)]))
	assert(entity != null, "a run of two points is a run")
	assert(entity.layer == LayerSet.IRRIGATION, "on the irrigation layer")
	assert(entity.kind == Entity.Kind.POLYLINE, "drawn as a polyline")
	assert(not Irrigation.is_head_entity(entity), "and it is not a head")
	assert(Irrigation.run_entity(PackedVector2Array([Vector2.ZERO])) == null,
		"a run of one point is not a run")


# --- the schedule, and what a panel reads ---------------------------------------------


func test_the_rows_a_panel_reads_are_one_per_zone() -> void:
	var controller = _controller()
	controller.set_irrigation_supply(400.0, 350.0)
	controller.water_area(_bed(9.0), Irrigation.SPRAY)
	controller.water_area(_bed(18.0), Irrigation.MICRO)
	var rows := controller.irrigation_rows()
	assert(rows.size() == 2, "one row per zone: %d" % rows.size())
	var lines := controller.irrigation_lines()
	assert(lines.size() == 2, "and one line each")
	assert(String(lines[0]).begins_with("Zone 1"), "the first names its zone: %s" % String(lines[0]))
	assert(String(lines[0]).contains("9 spray heads"), "and its heads: %s" % String(lines[0]))
	assert(String(lines[0]).contains("will run"), "and its verdict: %s" % String(lines[0]))
	controller.free()


func test_the_summary_reads_as_one_line() -> void:
	var controller = _controller()
	assert(controller.irrigation_summary() == "nothing on this drawing is watered yet",
		"an unwatered drawing says so: %s" % controller.irrigation_summary())
	controller.set_irrigation_supply(120.0, 350.0)
	controller.water_area(_bed(9.0), Irrigation.SPRAY)
	var line := controller.irrigation_summary()
	assert(line.contains("1 zone"), "one zone: %s" % line)
	assert(line.contains("9 heads"), "nine heads: %s" % line)
	assert(line.contains("81 L/min"), "drawing 81 litres a minute: %s" % line)
	assert(line.contains("every zone runs off the supply"), "and all of them run: %s" % line)
	controller.set_irrigation_supply(40.0, 350.0)
	assert(controller.irrigation_summary().contains("4 of them fit"),
		"a zone that no longer fits the supply is named: %s" % controller.irrigation_summary())
	controller.free()


func test_the_area_a_summary_states_is_the_drawings_own() -> void:
	var controller = _controller()
	controller.set_irrigation_supply(400.0, 350.0)
	controller.water_area(_bed(9.0), Irrigation.SPRAY)
	controller.document.units.system = DraftUnits.System.IMPERIAL
	var line := controller.irrigation_summary()
	assert(line.contains("ft2"), "an imperial drawing states its area in square feet: %s" % line)
	assert(not line.contains("m2"), "and never in square metres: %s" % line)
	controller.free()


# --- the file -------------------------------------------------------------------------


func test_the_zones_travel_in_the_drawing_file() -> void:
	var controller = _controller()
	controller.set_irrigation_supply(120.0, 350.0)
	controller.water_area(_bed(9.0), Irrigation.SPRAY)
	var saved: Dictionary = controller.document.to_dict()
	assert(int(saved["version"]) == 10, "this build writes version 10")
	assert(saved.has("irrigation"), "and it is written out")
	var loaded: DraftDocument = Document.from_dict(JSON.parse_string(JSON.stringify(saved)))
	var zones := Irrigation.from_dict(loaded.irrigation)
	assert(zones.size() == 1, "the zone comes back: %d" % zones.size())
	assert(Irrigation.head_count(zones[0]) == 9, "with its heads")
	assert(is_equal_approx(Irrigation.area_m2(zones[0]), 81.0), "and its area")
	assert(absf(float(loaded.irrigation["supply"]["flow"]) - 120.0) < 0.001, "and the supply")
	controller.free()


func test_a_drawing_from_before_the_irrigation_existed_has_none() -> void:
	var controller = _controller()
	controller.set_irrigation_supply(120.0, 350.0)
	controller.water_area(_bed(9.0), Irrigation.SPRAY)
	var old: Dictionary = controller.document.to_dict()
	old.erase("irrigation")
	old["version"] = 6
	var legacy: DraftDocument = Document.from_dict(old)
	assert(legacy.irrigation.is_empty(), "nothing stated rather than an invented supply")
	assert(Irrigation.from_dict(legacy.irrigation).is_empty(), "and no zones")
	assert(Irrigation.supply_words(legacy.irrigation.get("supply", {})) == "no supply stated",
		"which is what a check refuses on")
	controller.free()


func test_a_damaged_irrigation_record_is_dropped_rather_than_invented() -> void:
	var controller = _controller()
	controller.set_irrigation_supply(120.0, 350.0)
	controller.water_area(_bed(9.0), Irrigation.SPRAY)
	var planted: DraftDocument = controller.document
	planted.irrigation["zones"] = [
		"not a zone",
		{"kind": Irrigation.SPRAY},
		(planted.irrigation["zones"] as Array)[0],
	]
	var zones := Irrigation.from_dict(planted.irrigation)
	assert(zones.size() == 1, "the one real zone is read: %d" % zones.size())
	assert(Irrigation.head_count(zones[0]) == 9, "with its heads")
	controller.free()


func test_a_zone_stored_on_the_drawing_is_not_shared_with_a_snapshot() -> void:
	# The snapshot stores a copy, so undoing and then editing cannot reach back into what was undone.
	var controller = _controller()
	controller.set_irrigation_supply(400.0, 350.0)
	controller.water_area(_bed(9.0), Irrigation.SPRAY)
	var snapshot: Dictionary = controller.document.snapshot()
	controller.water_area(_bed(18.0), Irrigation.MICRO)
	assert(controller.irrigation_zones().size() == 2, "two zones now")
	var earlier = snapshot["irrigation"]
	assert((earlier["zones"] as Array).size() == 1, "and the snapshot still holds one")
	controller.free()