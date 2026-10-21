extends Node
## Lighting as the controller runs it: a circuit is laid out over an area of the plan, its fixtures
## land on the lighting layer carrying what they are, and the transformer is something somebody
## stated.
##
## The controller is built with its parts and no scene tree, exactly as the watering commands are
## tested: lighting a bed needs a document and a controller, and nothing else.

const Ctrl := preload("res://scripts/draft/draft_controller.gd")
const Tool := preload("res://scripts/draft/draft_tool.gd")
const Document := preload("res://scripts/draft/draft_document.gd")
const SnapScript := preload("res://scripts/draft/snap_engine.gd")
const Entity := preload("res://scripts/draft/draft_entity.gd")
const LayerSet := preload("res://scripts/draft/layer_set.gd")
const Lighting := preload("res://scripts/draft/lighting.gd")


func _controller():
	var controller = Ctrl.new()
	controller.document = Document.new()
	controller.snap = SnapScript.new()
	controller.tool = Tool.new()
	return controller


## A square area of `metres` a side, with its corner at the origin.
func _bed(metres: float = 9.0) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(metres, 0.0), Vector2(metres, metres), Vector2(0.0, metres),
	])


## A bed on the drawing, so the areas a panel offers are the drawing's own.
func _drawn_bed(controller, metres: float = 9.0, layer: StringName = LayerSet.NEW_BED) -> int:
	controller.document.add(Entity.make_polyline(_bed(metres), true), layer)
	return controller.document.count()


# --- the transformer ------------------------------------------------------------------


func test_a_transformer_that_has_not_been_stated_is_not_a_transformer() -> void:
	var controller = _controller()
	assert(controller.lighting_transformer().is_empty(), "nothing is stated on a new drawing")
	assert(Lighting.transformer_words(controller.lighting_transformer()) == "no transformer stated",
		"and it says so in words")
	assert(controller.lighting_fixture_budget(Lighting.FLOOD) == 0,
		"so the budget is nothing rather than a guess")
	controller.free()


func test_stating_the_transformer_is_one_undo_step() -> void:
	var controller = _controller()
	var stated: Dictionary = controller.set_lighting_transformer(100.0, 12.0)
	assert(bool(stated["ok"]), "100 VA at 12 V is a transformer: %s" % String(stated.get("reason", "")))
	assert(absf(float(controller.lighting_transformer()["va"]) - 100.0) < 0.001, "and it is remembered")
	assert(controller.lighting_fixture_budget(Lighting.FLOOD) == 8, "eight floodlights fit")
	assert(controller.dirty, "stating a transformer changes the drawing")
	assert(controller.document.undo_last(), "and it can be taken back")
	assert(controller.lighting_transformer().is_empty(), "leaving nothing stated")
	controller.free()


func test_a_transformer_of_nothing_is_refused() -> void:
	var controller = _controller()
	assert(not bool(controller.set_lighting_transformer(0.0, 12.0)["ok"]), "no capacity is not a transformer")
	assert(not bool(controller.set_lighting_transformer(100.0, 0.0)["ok"]), "and no voltage is not either")
	assert(controller.lighting_transformer().is_empty(), "nothing was stated")
	controller.free()


# --- lighting an area -----------------------------------------------------------------


func test_lighting_a_bed_lays_the_fixtures_out_and_is_one_undo_step() -> void:
	var controller = _controller()
	controller.set_lighting_transformer(100.0, 12.0)
	var before: int = _drawn_bed(controller)
	var lit: Dictionary = controller.light_area(_bed(), Lighting.WELL)
	assert(bool(lit["ok"]), "a nine metre bed takes sixteen well lights: %s" % String(lit.get("reason", "")))
	assert(int(lit["placed"]) == 16, "sixteen fixtures on the plan: %d" % int(lit["placed"]))
	assert(controller.document.count() == before + 16, "and they are on the drawing")
	var circuits := controller.lighting_circuits()
	assert(circuits.size() == 1, "one circuit is kept with the drawing")
	assert(int(circuits[0]["number"]) == 1, "numbered one")
	assert(int(circuits[0]["tap"]) == 1, "on tap one")
	assert(Lighting.fixture_count(circuits[0]) == 16, "holding its sixteen fixtures")
	assert(String(lit["verdict"]).contains("will run"), "and it says the circuit runs: %s"
		% String(lit["verdict"]))
	assert(controller.document.undo_last(), "the whole lighting comes off in one step")
	assert(controller.document.count() == before, "leaving the bed alone: %d" % controller.document.count())
	assert(controller.lighting_circuits().is_empty(), "and no circuit")
	controller.free()


func test_the_fixtures_land_on_the_lighting_layer_carrying_what_they_are() -> void:
	var controller = _controller()
	controller.set_lighting_transformer(100.0, 12.0)
	controller.light_area(_bed(), Lighting.WELL)
	var fixtures := 0
	for entity in controller.document.entities():
		if not Lighting.is_fixture_entity(entity):
			continue
		fixtures += 1
		assert(entity.layer == LayerSet.LIGHTING, "on the lighting layer: %s" % String(entity.layer))
		assert(Lighting.circuit_of_entity(entity) == 1, "belonging to Circuit 1")
		assert(String(entity.meta[Lighting.META_KIND]) == Lighting.WELL, "and saying what it is")
		assert(entity.kind == Entity.Kind.CIRCLE, "drawn as a circle")
		assert(entity.params[2] > 0.0, "with a radius on it: %f" % entity.params[2])
	assert(fixtures == 16, "sixteen fixtures: %d" % fixtures)
	# A fixture is a *symbol*: three millimetres across on the sheet, so at 1:100 it is 0.3 m of ground
	# and at 1:200 it is 0.6 m.
	assert(absf(_first_fixture_radius(controller) - 0.3) < 1e-6,
		"three millimetres on paper at 1:100 is 0.3 m of ground: %f" % _first_fixture_radius(controller))
	controller.plot_scale = 200.0
	controller.light_area(_bed(18.0), Lighting.WELL)
	for entity in controller.document.entities():
		if Lighting.circuit_of_entity(entity) == 2:
			assert(absf(entity.params[2] - 0.6) < 1e-6,
				"twice the paper size at half the scale: %f" % entity.params[2])
	controller.free()


## The radius the first fixture on the drawing is drawn at, or 0 when there is none.
func _first_fixture_radius(controller) -> float:
	for entity in controller.document.entities():
		if Lighting.is_fixture_entity(entity):
			return float(entity.params[2])
	return 0.0


func test_a_circuit_that_would_not_run_is_not_put_on_the_drawing() -> void:
	# Four floodlights draw 48 W and the transformer gives 40: refused, and *nothing* lands - a run
	# that cannot be carried is worse left on the drawing than said.
	var controller = _controller()
	controller.set_lighting_transformer(40.0, 12.0)
	var before: int = _drawn_bed(controller)
	var lit: Dictionary = controller.light_area(_bed(), Lighting.FLOOD)
	assert(not bool(lit["ok"]), "four floodlights will not run off 40 VA")
	assert(String(lit["reason"]).contains("3 of them fit"), "and the refusal says what fits: %s"
		% String(lit["reason"]))
	assert(controller.document.count() == before, "nothing was put on the drawing")
	assert(controller.lighting_circuits().is_empty(), "and no circuit was kept")
	controller.free()


func test_lighting_with_a_transformer_nobody_stated_is_refused() -> void:
	var controller = _controller()
	var before: int = _drawn_bed(controller)
	var lit: Dictionary = controller.light_area(_bed(), Lighting.WELL)
	assert(not bool(lit["ok"]), "a circuit cannot be blessed on a transformer nobody stated")
	assert(String(lit["reason"]).contains("transformer has not been stated"),
		"and the reason is the transformer: %s" % String(lit["reason"]))
	assert(controller.document.count() == before, "nothing was put on the drawing")
	controller.free()


func test_a_line_voltage_fixture_on_a_low_voltage_transformer_is_refused() -> void:
	var controller = _controller()
	controller.set_lighting_transformer(400.0, 12.0)
	var before: int = _drawn_bed(controller)
	var lit: Dictionary = controller.light_area(_bed(), Lighting.LANTERN)
	assert(not bool(lit["ok"]), "a 120 V lantern will not run off a 12 V transformer")
	var reason := String(lit["reason"])
	assert(reason.contains("120") and reason.contains("12"), "and the refusal names both: %s" % reason)
	assert(controller.document.count() == before, "nothing was put on the drawing")
	controller.free()


func test_an_area_the_grid_cannot_be_laid_out_in_is_refused_in_words() -> void:
	var controller = _controller()
	controller.set_lighting_transformer(400.0, 12.0)
	var tiny := PackedVector2Array([
		Vector2(2.0, 1.6), Vector2(2.4, 2.0), Vector2(2.0, 2.4), Vector2(1.6, 2.0),
	])
	var lit: Dictionary = controller.light_area(tiny, Lighting.WELL)
	assert(not bool(lit["ok"]), "an 0.8 m diamond takes no well light")
	assert(String(lit["reason"]).contains("no grid line"), "and says why: %s" % String(lit["reason"]))
	controller.free()


func test_a_kind_nobody_has_is_refused() -> void:
	var controller = _controller()
	controller.set_lighting_transformer(100.0, 12.0)
	var lit: Dictionary = controller.light_area(_bed(), "chandelier")
	assert(not bool(lit["ok"]), "a chandelier is not a kind of fixture")
	assert(controller.lighting_circuits().is_empty(), "and no circuit was made")
	controller.free()


func test_two_circuits_are_numbered_and_tapped_apart() -> void:
	var controller = _controller()
	controller.set_lighting_transformer(400.0, 12.0)
	controller.light_area(_bed(9.0), Lighting.WELL)
	var second: Dictionary = controller.light_area(_bed(18.0), Lighting.WELL)
	assert(bool(second["ok"]), "a second bed: %s" % String(second.get("reason", "")))
	var circuits := controller.lighting_circuits()
	assert(circuits.size() == 2, "two circuits")
	assert(int(circuits[1]["number"]) == 2, "the second is Circuit 2")
	assert(int(circuits[1]["tap"]) == 2, "on tap 2")
	assert(Lighting.fixture_count(circuits[1]) == int(second["placed"]), "holding its own fixtures")
	controller.free()


func test_the_transformer_is_stated_for_the_whole_drawing_not_for_a_circuit() -> void:
	# A second circuit is checked against the same transformer, so a bigger bed is refused on the same
	# numbers rather than on ones of its own.
	var controller = _controller()
	controller.set_lighting_transformer(100.0, 12.0)
	# Sixteen well lights over a nine metre bed draw 80 W and fit in 100.
	var small: Dictionary = controller.light_area(_bed(9.0), Lighting.WELL)
	assert(bool(small["ok"]), "sixteen well lights fit: %s" % String(small.get("reason", "")))
	assert(int(small["placed"]) == 16, "sixteen of them: %d" % int(small["placed"]))
	var big: Dictionary = controller.light_area(_bed(30.0), Lighting.WELL)
	assert(not bool(big["ok"]), "a thirty metre bed of well lights does not")
	assert(int(controller.lighting_circuits().size()) == 1, "and only the first circuit is kept")
	controller.free()


# --- taking a circuit back off --------------------------------------------------------


func test_taking_a_circuit_off_takes_its_fixtures_with_it() -> void:
	var controller = _controller()
	controller.set_lighting_transformer(400.0, 12.0)
	controller.light_area(_bed(9.0), Lighting.WELL)
	controller.light_area(_bed(18.0), Lighting.WELL)
	var fixtures_before := _fixtures(controller)
	var removed: Dictionary = controller.remove_circuit(1)
	assert(bool(removed["ok"]), "Circuit 1 comes off: %s" % String(removed.get("reason", "")))
	assert(int(removed["removed"]) == 16, "with its sixteen fixtures: %d" % int(removed["removed"]))
	assert(_fixtures(controller) == fixtures_before - 16, "and the rest of the drawing is left alone")
	var circuits := controller.lighting_circuits()
	assert(circuits.size() == 1, "one circuit is left")
	assert(int(circuits[0]["number"]) == 2, "and it is Circuit 2")
	assert(_fixtures_of_circuit(controller, 1) == 0, "no fixtures of Circuit 1 remain")
	assert(_fixtures_of_circuit(controller, 2) == Lighting.fixture_count(circuits[0]), "Circuit 2's are all there")
	assert(controller.document.undo_last(), "and it is one step")
	assert(_fixtures_of_circuit(controller, 1) == 16, "the fixtures come back with it")
	assert(controller.lighting_circuits().size() == 2, "and so does the circuit")
	controller.free()


func test_taking_off_a_circuit_that_is_not_there_says_so() -> void:
	var controller = _controller()
	var removed: Dictionary = controller.remove_circuit(7)
	assert(not bool(removed["ok"]), "there is no Circuit 7")
	assert(String(removed["reason"]) == "there is no Circuit 7", "and it says which: %s"
		% String(removed["reason"]))
	controller.free()


func _fixtures(controller) -> int:
	var found := 0
	for entity in controller.document.entities():
		if Lighting.is_fixture_entity(entity):
			found += 1
	return found


func _fixtures_of_circuit(controller, number: int) -> int:
	var found := 0
	for entity in controller.document.entities():
		if Lighting.circuit_of_entity(entity) == number:
			found += 1
	return found


# --- a fixture and a run as the drawing holds them ------------------------------------


func test_a_fixture_reads_as_a_line_and_is_marked_on_its_own_layer() -> void:
	var fixture := {"kind": Lighting.UPLIGHT, "at": Vector2(2.0, 3.0), "heading": 0.0, "spread": 0.0}
	var entity := Lighting.fixture_entity(fixture, 3, 100.0)
	assert(entity.layer == LayerSet.LIGHTING, "on the lighting layer")
	assert(Lighting.is_fixture_entity(entity), "and marked as a fixture")
	assert(Lighting.circuit_of_entity(entity) == 3, "belonging to Circuit 3")
	# The words a status bar or a legend writes, read off the fixture rather than off a caller.
	var words := Lighting.fixture_words(fixture)
	assert(words.contains("uplight"), "the words name the kind: %s" % words)
	assert(words.contains("a narrow beam"), "and the beam: %s" % words)
	assert(Lighting.fixture_words({"kind": Lighting.PATH, "spread": 360.0}).contains("a full circle"),
		"a path light with a full circle is a full circle")


func test_a_run_is_a_polyline_and_a_run_of_one_point_is_nothing() -> void:
	var entity := Lighting.run_entity(PackedVector2Array([Vector2.ZERO, Vector2(3.0, 0.0)]))
	assert(entity != null, "a run of two points is a run")
	assert(entity.layer == LayerSet.LIGHTING, "on the lighting layer")
	assert(entity.kind == Entity.Kind.POLYLINE, "drawn as a polyline")
	assert(not Lighting.is_fixture_entity(entity), "and it is not a fixture")
	assert(Lighting.run_entity(PackedVector2Array([Vector2.ZERO])) == null,
		"a run of one point is not a run")


# --- the schedule, and what a panel reads ---------------------------------------------


func test_the_rows_a_panel_reads_are_one_per_circuit() -> void:
	var controller = _controller()
	controller.set_lighting_transformer(400.0, 12.0)
	controller.light_area(_bed(9.0), Lighting.WELL)
	controller.light_area(_bed(18.0), Lighting.WELL)
	var rows := controller.lighting_rows()
	assert(rows.size() == 2, "one row per circuit: %d" % rows.size())
	var lines := controller.lighting_lines()
	assert(lines.size() == 2, "and one line each")
	assert(String(lines[0]).begins_with("Circuit 1"), "the first names its circuit: %s" % String(lines[0]))
	assert(String(lines[0]).contains("16 well lights"), "and its fixtures: %s" % String(lines[0]))
	assert(String(lines[0]).contains("will run"), "and its verdict: %s" % String(lines[0]))
	controller.free()


func test_the_summary_reads_as_one_line() -> void:
	var controller = _controller()
	assert(controller.lighting_summary() == "nothing on this drawing is lit yet",
		"an unlit drawing says so: %s" % controller.lighting_summary())
	controller.set_lighting_transformer(100.0, 12.0)
	controller.light_area(_bed(9.0), Lighting.WELL)
	var line := controller.lighting_summary()
	assert(line.contains("1 circuit"), "one circuit: %s" % line)
	assert(line.contains("16 fixtures"), "sixteen fixtures: %s" % line)
	assert(line.contains("80 W"), "drawing 80 watts: %s" % line)
	assert(line.contains("every circuit runs off the transformer"), "and all of them run: %s" % line)
	controller.set_lighting_transformer(40.0, 12.0)
	assert(controller.lighting_summary().contains("8 of them fit"),
		"a circuit that no longer fits the transformer is named: %s" % controller.lighting_summary())
	controller.free()


func test_the_area_a_summary_states_is_the_drawings_own() -> void:
	var controller = _controller()
	controller.set_lighting_transformer(400.0, 12.0)
	controller.light_area(_bed(9.0), Lighting.WELL)
	controller.document.units.system = DraftUnits.System.IMPERIAL
	var line := controller.lighting_summary()
	assert(line.contains("ft2"), "an imperial drawing states its area in square feet: %s" % line)
	assert(not line.contains("m2"), "and never in square metres: %s" % line)
	controller.free()


# --- the file -------------------------------------------------------------------------


func test_the_circuits_travel_in_the_drawing_file() -> void:
	var controller = _controller()
	controller.set_lighting_transformer(100.0, 12.0)
	controller.light_area(_bed(9.0), Lighting.WELL)
	var saved: Dictionary = controller.document.to_dict()
	assert(int(saved["version"]) == 10, "this build writes version 10")
	assert(saved.has("lighting"), "and it is written out")
	var loaded: DraftDocument = Document.from_dict(JSON.parse_string(JSON.stringify(saved)))
	var circuits := Lighting.from_dict(loaded.lighting)
	assert(circuits.size() == 1, "the circuit comes back: %d" % circuits.size())
	assert(Lighting.fixture_count(circuits[0]) == 16, "with its fixtures")
	assert(is_equal_approx(Lighting.area_m2(circuits[0]), 81.0), "and its area")
	assert(absf(float(loaded.lighting["transformer"]["va"]) - 100.0) < 0.001, "and the transformer")
	controller.free()


func test_a_drawing_from_before_the_lighting_existed_has_none() -> void:
	var controller = _controller()
	controller.set_lighting_transformer(100.0, 12.0)
	controller.light_area(_bed(9.0), Lighting.WELL)
	var old: Dictionary = controller.document.to_dict()
	old.erase("lighting")
	old["version"] = 7
	var legacy: DraftDocument = Document.from_dict(old)
	assert(legacy.lighting.is_empty(), "nothing stated rather than an invented transformer")
	assert(Lighting.from_dict(legacy.lighting).is_empty(), "and no circuits")
	assert(Lighting.transformer_words(legacy.lighting.get("transformer", {})) == "no transformer stated",
		"which is what a check refuses on")
	controller.free()


func test_a_damaged_lighting_record_is_dropped_rather_than_invented() -> void:
	var controller = _controller()
	controller.set_lighting_transformer(100.0, 12.0)
	controller.light_area(_bed(9.0), Lighting.WELL)
	var lit: DraftDocument = controller.document
	lit.lighting["circuits"] = [
		"not a circuit",
		{"kind": Lighting.WELL},
		(lit.lighting["circuits"] as Array)[0],
	]
	var circuits := Lighting.from_dict(lit.lighting)
	assert(circuits.size() == 1, "the one real circuit is read: %d" % circuits.size())
	assert(Lighting.fixture_count(circuits[0]) == 16, "with its fixtures")
	controller.free()


func test_a_circuit_stored_on_the_drawing_is_not_shared_with_a_snapshot() -> void:
	# The snapshot stores a copy, so undoing and then editing cannot reach back into what was undone.
	var controller = _controller()
	controller.set_lighting_transformer(400.0, 12.0)
	controller.light_area(_bed(9.0), Lighting.WELL)
	var snapshot: Dictionary = controller.document.snapshot()
	controller.light_area(_bed(18.0), Lighting.WELL)
	assert(controller.lighting_circuits().size() == 2, "two circuits now")
	var earlier = snapshot["lighting"]
	assert((earlier["circuits"] as Array).size() == 1, "and the snapshot still holds one")
	controller.free()