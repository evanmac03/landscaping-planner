extends Node
## The lighting arithmetic: the fixture table, a circuit, the layout rule, the load check and the
## cover check.
##
## The rings here are written out rather than taken from a `DraftEntity`, for the reason the planting
## tests give: the arithmetic takes a ring and not an entity, and a test that went through the entity
## layer would be a test about the entity layer.
##
## Every count is hand-computed from the grid the planting code uses, so a change to the grid shows
## up here as a number rather than as a plausible-looking difference.

const LightingScript := preload("res://scripts/draft/lighting.gd")
const SpacingScript := preload("res://scripts/plant_spacing.gd")
const Geom := preload("res://scripts/draft/geom2d.gd")
const LayerSet := preload("res://scripts/draft/layer_set.gd")

## A transformer a designer actually has: a residential low-voltage unit.
const TRANSFORMER_VA := 100.0
const TRANSFORMER_VOLTS := 12.0


## A square area of `metres` a side with its corner at the origin.
func _square(metres: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(metres, 0.0), Vector2(metres, metres), Vector2(0.0, metres),
	])


func _transformer(va: float = TRANSFORMER_VA, volts: float = TRANSFORMER_VOLTS) -> Dictionary:
	return LightingScript.make_transformer(va, volts)


## A circuit of `count` fixtures of one kind, set in a line so nothing about the position matters.
func _circuit_of(count: int, kind: String) -> Dictionary:
	var circuit := LightingScript.make_circuit(1, kind)
	for index in count:
		LightingScript.add_fixture(circuit, Vector2(float(index), 0.0), kind)
	return circuit


func _reasons(result: Dictionary) -> Array:
	return result["reasons"]


# --- the fixture table --------------------------------------------------------------


func test_every_kind_is_named_and_carries_its_numbers() -> void:
	var kinds: Array = LightingScript.kind_list()
	assert(kinds.size() == 6, "six kinds: %d" % kinds.size())
	assert(LightingScript.kind_names().size() == kinds.size(), "one name each")
	for kind: String in kinds:
		assert(LightingScript.is_kind(kind), "the list holds kinds the table knows: %s" % kind)
		assert(not LightingScript.kind_name(kind).is_empty(), "%s is named" % kind)
		assert(LightingScript.watts_of_kind(kind) > 0.0, "%s draws power" % kind)
		assert(LightingScript.volts_of_kind(kind) > 0.0, "%s has a voltage" % kind)
		assert(LightingScript.throw_of_kind(kind) > 0.0, "%s throws somewhere" % kind)
		assert(LightingScript.spread_of_kind(kind) > 0.0, "%s has a beam" % kind)
		assert(LightingScript.kind_for_name(LightingScript.kind_name(kind)) == kind,
			"the name a drop-down shows turns back into %s" % kind)


func test_a_kind_nobody_has_is_refused_rather_than_guessed() -> void:
	assert(not LightingScript.is_kind("chandelier"), "not a kind")
	assert(LightingScript.kind_for_name("chandelier") == "", "no name matches a kind nobody has")
	assert(LightingScript.watts_of_kind("chandelier") == 0.0, "an unknown kind draws nothing")
	assert(LightingScript.kind_words("chandelier").contains("nobody"), "and says so in words")


func test_a_lantern_is_the_one_line_voltage_fixture() -> void:
	assert(LightingScript.volts_of_kind(LightingScript.LANTERN) == 120.0, "a lantern is 120 V")
	for kind: String in LightingScript.kind_list():
		if kind != LightingScript.LANTERN:
			assert(LightingScript.volts_of_kind(kind) == 12.0, "%s is low voltage" % kind)


func test_the_layer_comes_from_the_layer_set() -> void:
	assert(LightingScript.layer() == LayerSet.LIGHTING, "fixtures live on the lighting layer")
	assert(String(LightingScript.layer()) == "501-LIGHTING", "and it is 501")


# --- the transformer -----------------------------------------------------------------


func test_a_transformer_that_is_not_stated_is_not_a_transformer() -> void:
	assert(not LightingScript.has_transformer({}), "no dictionary is no transformer")
	assert(not LightingScript.has_transformer(LightingScript.make_transformer(0.0, 12.0)),
		"no capacity is no transformer")
	assert(not LightingScript.has_transformer(LightingScript.make_transformer(100.0, 0.0)),
		"no voltage is no transformer")
	assert(LightingScript.has_transformer(_transformer()), "a stated one is a transformer")
	assert(LightingScript.transformer_words({}) == "no transformer stated", "and says so")
	assert(LightingScript.transformer_words(_transformer()).contains("100 VA at 12 V"),
		"a stated one reads as itself")


func test_the_budget_is_how_many_of_a_kind_fit() -> void:
	assert(LightingScript.power_budget(_transformer(), LightingScript.FLOOD) == 8, "100 / 12 = 8")
	assert(LightingScript.power_budget(_transformer(), LightingScript.PATH) == 25, "100 / 4 = 25")
	assert(LightingScript.power_budget(_transformer(), LightingScript.LANTERN) == 1, "100 / 60 = 1")
	assert(LightingScript.power_budget({}, LightingScript.FLOOD) == 0, "no transformer, no budget")


# --- what a fixture reaches -----------------------------------------------------------


func test_a_full_circle_fixture_reaches_its_throw_in_every_direction() -> void:
	var fixture := {"kind": LightingScript.PATH, "at": Vector2.ZERO, "heading": 0.0, "spread": 0.0}
	assert(LightingScript.reaches(fixture, Vector2(2.4, 0.0)), "inside the throw")
	assert(LightingScript.reaches(fixture, Vector2(0.0, -2.4)), "and the other way")
	assert(not LightingScript.reaches(fixture, Vector2(2.6, 0.0)), "beyond the throw, no")


func test_a_half_beam_fixture_lights_only_its_own_half() -> void:
	# A step light throws 1.5 m over a half circle; aimed along +x it lights +x and not -x.
	var fixture := {"kind": LightingScript.STEP, "at": Vector2.ZERO, "heading": 0.0, "spread": 0.0}
	assert(LightingScript.reaches(fixture, Vector2(1.0, 0.0)), "in front is lit")
	assert(not LightingScript.reaches(fixture, Vector2(-1.0, 0.0)), "behind is dark")
	assert(LightingScript.reaches(fixture, Vector2(0.0, 1.0)), "on the edge counts as lit")


func test_a_beam_as_a_person_says_it() -> void:
	assert(LightingScript.beam_words(40.0) == "a narrow beam", "40 is narrow")
	assert(LightingScript.beam_words(90.0) == "a wide beam", "90 is wide")
	assert(LightingScript.beam_words(180.0) == "a half circle", "180 is a half")
	assert(LightingScript.beam_words(360.0) == "a full circle", "360 is full")


# --- the load check -----------------------------------------------------------------


func test_the_load_is_the_sum_of_the_fixtures() -> void:
	assert(LightingScript.demand_of(_circuit_of(4, LightingScript.FLOOD)) == 48.0, "4 x 12 = 48")
	assert(LightingScript.demand_of(_circuit_of(3, LightingScript.UPLIGHT)) == 21.0, "3 x 7 = 21")
	assert(LightingScript.demand_of(LightingScript.make_circuit(1)) == 0.0, "an empty one draws nothing")


func test_a_circuit_with_no_transformer_is_refused_and_never_sound() -> void:
	var circuit := _circuit_of(2, LightingScript.PATH)
	var result := LightingScript.check(circuit, {})
	assert(not bool(result["ok"]), "not sound")
	assert(not LightingScript.sound(circuit, {}), "sound() agrees")
	assert(String(_reasons(result)[0]).contains("transformer"), "and names the transformer")


func test_a_circuit_with_no_fixtures_is_refused() -> void:
	var result := LightingScript.check(LightingScript.make_circuit(1), _transformer())
	assert(not bool(result["ok"]), "not sound")
	var joined := " ".join(_reasons(result))
	assert(joined.contains("no fixtures"), "and says there is nothing to run: %s" % joined)


func test_a_circuit_over_the_transformer_is_refused_naming_the_numbers() -> void:
	var circuit := _circuit_of(9, LightingScript.FLOOD)
	var result := LightingScript.check(circuit, _transformer())
	assert(not bool(result["ok"]), "108 W on a 100 VA unit is refused")
	var line := " ".join(_reasons(result))
	assert(line.contains("108"), "names the load: %s" % line)
	assert(line.contains("100"), "names the transformer: %s" % line)
	assert(line.contains("8"), "and names the eight that fit: %s" % line)


func test_a_circuit_within_its_transformer_will_run() -> void:
	var circuit := _circuit_of(8, LightingScript.FLOOD)
	var result := LightingScript.check(circuit, _transformer())
	assert(bool(result["ok"]), "8 floodlights is 96 W, which fits: %s" % str(_reasons(result)))


func test_a_fixture_whose_voltage_differs_is_refused() -> void:
	var lantern := _circuit_of(1, LightingScript.LANTERN)
	var result := LightingScript.check(lantern, _transformer())
	assert(not bool(result["ok"]), "a 120 V lantern on a 12 V transformer is refused")
	var line := " ".join(_reasons(result))
	assert(line.contains("120") and line.contains("12"), "and names both voltages: %s" % line)


func test_two_kinds_may_share_a_circuit_which_is_the_difference_from_irrigation() -> void:
	var circuit := LightingScript.make_circuit(1, LightingScript.PATH)
	LightingScript.add_fixture(circuit, Vector2(0.0, 0.0), LightingScript.PATH)
	LightingScript.add_fixture(circuit, Vector2(1.0, 0.0), LightingScript.UPLIGHT)
	var result := LightingScript.check(circuit, _transformer())
	assert(bool(result["ok"]), "a path light and an uplight run off one 12 V run: %s" % str(_reasons(result)))


func test_a_fixture_outside_the_area_is_refused() -> void:
	var circuit := _circuit_of(1, LightingScript.PATH)
	LightingScript.set_area(circuit, _square(5.0))
	LightingScript.add_fixture(circuit, Vector2(10.0, 10.0), LightingScript.PATH)
	var result := LightingScript.check(circuit, _transformer())
	assert(not bool(result["ok"]), "a fixture off its own area is refused")
	assert(" ".join(_reasons(result)).contains("outside"), "and says so")


# --- laying fixtures out --------------------------------------------------------------


func test_a_layout_lands_on_the_grid_lines_including_the_edges() -> void:
	# A well light throws 3 m; over a 9 m square that is three throws, so the grid lines fall at
	# 0, 3, 6 and 9, and the edge lines are the point of the layout.
	var circuit := LightingScript.make_circuit(1, LightingScript.WELL)
	LightingScript.set_area(circuit, _square(9.0))
	var report := LightingScript.lay_out(circuit)
	assert(bool(report["ok"]), "a 9 m square lays out: %s" % report.get("reason", ""))
	assert(int(report["placed"]) == 16, "four by four = 16: %d" % int(report["placed"]))
	assert(LightingScript.fixture_count(circuit) == 16, "and they are in the circuit")
	var on_edge := 0
	for entry in LightingScript.fixtures_of(circuit):
		var at: Vector2 = (entry as Dictionary)["at"]
		if at.x <= 0.001 or at.x >= 8.999 or at.y <= 0.001 or at.y >= 8.999:
			on_edge += 1
	assert(on_edge == 12, "twelve of them are on an edge line: %d" % on_edge)


func test_laying_a_circuit_out_again_replaces_its_fixtures() -> void:
	var circuit := LightingScript.make_circuit(1, LightingScript.WELL)
	LightingScript.set_area(circuit, _square(9.0))
	LightingScript.lay_out(circuit)
	LightingScript.lay_out(circuit, LightingScript.WELL, 4.5)
	assert(LightingScript.fixture_count(circuit) == 9, "the second layout is the only one: %d"
		% LightingScript.fixture_count(circuit))


func test_a_triangular_layout_sets_fewer_fixtures() -> void:
	var wide := _square(30.0)
	var square := LightingScript.make_circuit(1, LightingScript.UPLIGHT)
	LightingScript.set_area(square, wide)
	LightingScript.lay_out(square, LightingScript.UPLIGHT, LightingScript.spacing_for(LightingScript.UPLIGHT, false))
	var staggered := LightingScript.make_circuit(2, LightingScript.UPLIGHT)
	LightingScript.set_area(staggered, wide)
	LightingScript.lay_out(staggered, LightingScript.UPLIGHT, LightingScript.spacing_for(LightingScript.UPLIGHT, true), true)
	var square_count := LightingScript.fixture_count(square)
	var staggered_count := LightingScript.fixture_count(staggered)
	assert(staggered_count < square_count, "staggered sets fewer: %d < %d" % [staggered_count, square_count])


func test_a_layout_that_wants_more_than_the_cap_is_refused_and_sets_nothing() -> void:
	var circuit := LightingScript.make_circuit(1, LightingScript.UPLIGHT)
	LightingScript.set_area(circuit, _square(20.0))
	LightingScript.add_fixture(circuit, Vector2(1.0, 1.0), LightingScript.UPLIGHT)
	var report := LightingScript.lay_out(circuit, LightingScript.UPLIGHT, 0.5)
	assert(not bool(report["ok"]), "0.5 m over 20 m wants more than 300")
	assert(String(report["reason"]).contains(str(LightingScript.MAX_FIXTURES)), "and names the cap")
	assert(LightingScript.fixture_count(circuit) == 1, "and leaves the one it had alone")


func test_an_outline_that_is_not_an_area_is_refused_in_words() -> void:
	var circuit := LightingScript.make_circuit(1, LightingScript.PATH)
	LightingScript.set_area(circuit, PackedVector2Array([Vector2.ZERO, Vector2(1.0, 0.0)]))
	var report := LightingScript.lay_out(circuit)
	assert(not bool(report["ok"]), "two points are not an area")
	assert(not String(report["reason"]).is_empty(), "and it says why")


# --- cover --------------------------------------------------------------------------


func test_a_covered_area_reports_no_shortfall() -> void:
	# A full-circle fixture per throw over a whole number of throws covers the bed.
	var circuit := LightingScript.make_circuit(1, LightingScript.PATH)
	LightingScript.set_area(circuit, _square(5.0))
	LightingScript.lay_out(circuit)
	var lit := LightingScript.cover(circuit)
	assert(bool(lit["ok"]), "the cover was measured")
	assert(float(lit["fraction"]) >= 0.999, "a whole-throw bed is covered: %f" % float(lit["fraction"]))


func test_a_shortfall_is_reported_rather_than_refused() -> void:
	# A single narrow beam leaves most of a bed dark, and the check reports it as a fact.
	var circuit := LightingScript.make_circuit(1, LightingScript.FLOOD)
	LightingScript.set_area(circuit, _square(12.0))
	LightingScript.add_fixture(circuit, Vector2(1.0, 1.0), LightingScript.FLOOD)
	var lit := LightingScript.cover(circuit)
	assert(bool(lit["ok"]), "measured")
	assert(float(lit["fraction"]) < 1.0, "there is a gap: %f" % float(lit["fraction"]))
	var verdict := LightingScript.check(circuit, _transformer())
	assert(bool(verdict["ok"]), "a gap is not a refusal")
	assert(" ".join(verdict["notes"]).contains("beyond every fixture"), "and it is noted")


func test_cover_needs_an_area() -> void:
	var lit := LightingScript.cover(LightingScript.make_circuit(1))
	assert(not bool(lit["ok"]), "no area, no cover")
	assert(String(lit["reason"]).contains("area"), "and it says so")


# --- the plan and the file ------------------------------------------------------------


func test_a_fixture_is_drawn_at_a_paper_size() -> void:
	var circuit := _circuit_of(1, LightingScript.PATH)
	var fixture: Dictionary = LightingScript.fixtures_of(circuit)[0]
	var entity := LightingScript.fixture_entity(fixture, 3, 100.0)
	assert(entity != null, "a fixture makes an entity")
	assert(entity.layer == LayerSet.LIGHTING, "on the lighting layer")
	assert(is_equal_approx(entity.params[2], 0.3),
		"3 mm of paper at 1:100 is 0.3 m: %f" % entity.params[2])
	var big := LightingScript.fixture_entity(fixture, 3, 200.0)
	assert(is_equal_approx(big.params[2], 0.6), "and 0.6 m at 1:200")
	assert(LightingScript.is_fixture_entity(entity), "and it is recognised")
	assert(LightingScript.circuit_of_entity(entity) == 3, "carrying its circuit")
	assert(not LightingScript.is_fixture_entity(null), "nothing is not a fixture")


func test_a_run_needs_two_points() -> void:
	assert(LightingScript.run_entity(PackedVector2Array([Vector2.ZERO])) == null, "one point is no run")
	var run := LightingScript.run_entity(PackedVector2Array([Vector2.ZERO, Vector2(1.0, 0.0)]))
	assert(run != null and run.layer == LayerSet.LIGHTING, "two points make a run on the layer")


func test_a_circuit_round_trips_through_the_file() -> void:
	var circuit := LightingScript.make_circuit(2, LightingScript.UPLIGHT)
	circuit["tap"] = 1
	LightingScript.set_area(circuit, _square(6.0))
	LightingScript.lay_out(circuit)
	var data := LightingScript.to_dict([circuit])
	var back := LightingScript.from_dict(data)
	assert(back.size() == 1, "one circuit came back")
	assert(int(back[0]["number"]) == 2, "its number survived")
	assert(int(back[0]["tap"]) == 1, "its tap survived")
	assert(LightingScript.fixture_count(back[0]) == LightingScript.fixture_count(circuit),
		"every fixture came back")


func test_a_record_that_is_not_a_circuit_is_dropped() -> void:
	var data := {"circuits": [
		{"number": 1, "kind": "path", "fixtures": []},
		{"kind": "path"},                       # no number
		{"number": 2, "kind": "chandelier"},    # not a kind
		"nonsense",
	]}
	var back := LightingScript.from_dict(data)
	assert(back.size() == 1, "only the sound record survives: %d" % back.size())
	assert(int(back[0]["number"]) == 1, "and it is the one that was sound")


func test_a_damaged_fixture_is_dropped_without_losing_its_circuit() -> void:
	var data := {"circuits": [
		{"number": 1, "kind": "path", "fixtures": [
			{"kind": "path", "at": [1.0, 2.0]},
			{"kind": "path"},                    # no position
			{"kind": "chandelier", "at": [3.0, 4.0]},  # not a kind
			{"kind": "path", "at": [5.0, 6.0]},
		]},
	]}
	var back := LightingScript.from_dict(data)
	assert(back.size() == 1, "the circuit is kept")
	assert(LightingScript.fixture_count(back[0]) == 2, "with its two sound fixtures: %d"
		% LightingScript.fixture_count(back[0]))


func test_a_file_that_is_not_a_file_reads_as_no_circuits() -> void:
	assert(LightingScript.from_dict({}).is_empty(), "nothing there is nothing")
	assert(LightingScript.from_dict({"circuits": "nonsense"}).is_empty(), "and rubbish is nothing")


# --- the schedule ---------------------------------------------------------------------


func test_the_schedule_reads_as_a_row_a_designer_can_check() -> void:
	var circuit := _circuit_of(8, LightingScript.FLOOD)
	var rows := LightingScript.schedule([circuit], _transformer())
	assert(rows.size() == 1, "one circuit, one row")
	var line := LightingScript.schedule_row_words(rows[0])
	assert(line.contains("Circuit 1"), "names the circuit: %s" % line)
	assert(line.contains("tap 1"), "and the tap")
	assert(line.contains("8 floodlights"), "and what it feeds")
	assert(line.contains("96 W"), "and the load")
	assert(line.contains("will run"), "and the verdict")


func test_an_area_is_written_in_the_drawings_own_units() -> void:
	# The words an area is written in come from the drawing rather than from the page that prints it:
	# an imperial drawing must not go on claiming square metres on a schedule or a verdict line.
	var circuit := _circuit_of(8, LightingScript.FLOOD)
	LightingScript.set_area(circuit, _square(10.0))
	var imperial := DraftUnits.new()
	imperial.system = DraftUnits.System.IMPERIAL
	var row := LightingScript.schedule([circuit], _transformer(), imperial)[0]
	assert(String(row["area_text"]).ends_with(" ft2"), "an imperial drawing says square feet: %s"
		% String(row["area_text"]))
	assert(LightingScript.schedule_row_words(row).contains("ft2"),
		"and the row a sheet carries says so too: %s" % LightingScript.schedule_row_words(row))
	# Handed nothing - a panel row built by hand - the words are the metre default.
	var metric := LightingScript.schedule([circuit], _transformer())[0]
	assert(String(metric["area_text"]).ends_with(" m2"),
		"with no drawing handed over it is metres: %s" % String(metric["area_text"]))


func test_the_verdict_reads_as_one_line() -> void:
	var circuit := _circuit_of(8, LightingScript.FLOOD)
	var line := LightingScript.verdict_words(circuit, _transformer())
	assert(line.begins_with("Circuit 1 will run"), "leads with the circuit: %s" % line)
	assert(line.contains("96 W of 100 VA"), "and names the load against the transformer")
	var short := LightingScript.verdict_words(_circuit_of(9, LightingScript.FLOOD), _transformer())
	assert(short.begins_with("Circuit 1:"), "a refusal leads with the reason: %s" % short)