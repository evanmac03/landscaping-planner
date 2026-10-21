extends Node
## The irrigation arithmetic: the head table, a zone, the layout rule, the flow check and the
## coverage check.
##
## The rings here are written out rather than taken from a `DraftEntity`, for the reason the planting
## tests give: the arithmetic takes a ring and not an entity, and a test that went through the entity
## layer would be a test about the entity layer.
##
## Every count is hand-computed from the grid the planting code uses, so a change to the grid shows
## up here as a number rather than as a plausible-looking difference.

const IrrigationScript := preload("res://scripts/draft/irrigation.gd")
const SpacingScript := preload("res://scripts/plant_spacing.gd")
const Geom := preload("res://scripts/draft/geom2d.gd")
const LayerSet := preload("res://scripts/draft/layer_set.gd")

## A supply a designer actually has: a residential service line.
const SUPPLY_FLOW := 40.0
const SUPPLY_PRESSURE := 350.0


## A square area of `metres` a side with its corner at the origin.
func _square(metres: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(metres, 0.0), Vector2(metres, metres), Vector2(0.0, metres),
	])


func _supply(flow: float = SUPPLY_FLOW, pressure: float = SUPPLY_PRESSURE) -> Dictionary:
	return IrrigationScript.make_supply(flow, pressure)


## A zone of `count` heads of one kind, set in a line so nothing about the position matters.
func _zone_of(count: int, kind: String) -> Dictionary:
	var zone := IrrigationScript.make_zone(1, kind)
	for index in count:
		IrrigationScript.add_head(zone, Vector2(float(index), 0.0), kind)
	return zone


func _reasons(result: Dictionary) -> Array:
	return result["reasons"]


# --- the head table -----------------------------------------------------------------


func test_every_kind_is_named_and_carries_its_numbers() -> void:
	var kinds: Array = IrrigationScript.kind_list()
	assert(kinds.size() == 4, "four kinds: %d" % kinds.size())
	assert(IrrigationScript.kind_names().size() == kinds.size(), "one name each")
	for kind: String in kinds:
		assert(IrrigationScript.is_kind(kind), "the list holds kinds the table knows: %s" % kind)
		assert(not IrrigationScript.kind_name(kind).is_empty(), "%s is named" % kind)
		assert(IrrigationScript.flow_of_kind(kind) > 0.0, "%s draws water" % kind)
		assert(IrrigationScript.throw_of_kind(kind) > 0.0, "%s throws somewhere" % kind)
		assert(IrrigationScript.pressure_of_kind(kind) > 0.0, "%s wants a pressure" % kind)
		assert(IrrigationScript.NOZZLES.has(IrrigationScript.arc_of_kind(kind)),
			"a default arc is a nozzle a person can buy: %s" % kind)
		assert(IrrigationScript.kind_for_name(IrrigationScript.kind_name(kind)) == kind,
			"the name a drop-down shows turns back into %s" % kind)


func test_a_kind_nobody_has_is_refused_rather_than_guessed() -> void:
	assert(not IrrigationScript.is_kind("mister"), "not a kind")
	assert(IrrigationScript.kind_for_name("mister") == "", "no name matches a kind nobody has")
	assert(IrrigationScript.flow_of_kind("mister") == 0.0, "an unknown kind draws nothing")
	assert(IrrigationScript.kind_words("mister").contains("nobody"), "and says so in words")


func test_a_head_lives_on_the_irrigation_layer() -> void:
	assert(IrrigationScript.layer() == LayerSet.IRRIGATION, "the layer set decides the layer")


# --- what a head reaches ------------------------------------------------------------


func test_a_full_head_reaches_its_throw_in_every_direction() -> void:
	var head := {"kind": IrrigationScript.ROTOR, "at": Vector2.ZERO, "heading": 0.0, "arc": 360.0}
	assert(IrrigationScript.reaches(head, Vector2(11.0, 0.0)), "to its own throw")
	assert(not IrrigationScript.reaches(head, Vector2(11.5, 0.0)), "and no further")
	assert(IrrigationScript.reaches(head, Vector2(-11.0, 0.0)), "a full circle has no behind")


func test_a_half_head_reaches_only_its_own_half() -> void:
	# Facing +x, the half a spray head is fitted with.
	var head := {"kind": IrrigationScript.SPRAY, "at": Vector2.ZERO, "heading": 0.0, "arc": 180.0}
	assert(IrrigationScript.reaches(head, Vector2(3.0, 0.0)), "in front of it")
	assert(IrrigationScript.reaches(head, Vector2(0.0, 3.0)), "on its own edge")
	assert(not IrrigationScript.reaches(head, Vector2(-3.0, 0.0)), "not behind it")
	assert(not IrrigationScript.reaches(head, Vector2(-0.1, 0.0)), "not just behind it")


func test_a_head_with_no_arc_of_its_own_uses_its_kinds() -> void:
	var head := {"kind": IrrigationScript.ROTOR, "at": Vector2.ZERO, "heading": 0.0, "arc": 0.0}
	assert(is_equal_approx(IrrigationScript.arc_of_head(head), 360.0), "a rotor's own arc")
	var spray := {"kind": IrrigationScript.SPRAY, "at": Vector2.ZERO, "heading": 0.0, "arc": 0.0}
	assert(is_equal_approx(IrrigationScript.arc_of_head(spray), 180.0), "a spray's own arc")


# --- the flow check -----------------------------------------------------------------


func test_the_flow_is_the_sum_of_the_heads_own_flows() -> void:
	var zone := _zone_of(4, IrrigationScript.SPRAY)
	assert(is_equal_approx(IrrigationScript.demand_of(zone), 36.0),
		"four nine-litre heads: %s" % str(IrrigationScript.demand_of(zone)))
	IrrigationScript.add_head(zone, Vector2(9.0, 0.0), IrrigationScript.SPRAY)
	assert(is_equal_approx(IrrigationScript.demand_of(zone), 45.0), "and one more")


func test_a_zone_with_no_supply_stated_is_refused_and_never_sound() -> void:
	var zone := _zone_of(2, IrrigationScript.SPRAY)
	for empty: Dictionary in [{}, IrrigationScript.make_supply(0.0, 0.0)]:
		var result := IrrigationScript.check(zone, empty)
		assert(not bool(result["ok"]), "never sound: %s" % str(empty))
		assert(not IrrigationScript.sound(zone, empty), "and never blessed")
		assert(String(_reasons(result)[0]).contains("supply has not been stated"),
			"the first reason is the supply: %s" % String(_reasons(result)[0]))


func test_a_zone_over_its_supply_is_refused_naming_the_numbers_and_what_fits() -> void:
	var zone := _zone_of(12, IrrigationScript.SPRAY)
	var result := IrrigationScript.check(zone, _supply())
	assert(not bool(result["ok"]), "twelve sprays will not run off forty litres a minute")
	var reason := String(_reasons(result)[0])
	assert(reason.contains("108"), "the demand is named: %s" % reason)
	assert(reason.contains("40"), "the supply is named: %s" % reason)
	assert(reason.contains("4 of them fit"), "and what would fit: %s" % reason)
	assert(int(result["budget"]) == 4, "a forty litre supply runs four: %d" % int(result["budget"]))


func test_a_zone_within_its_supply_will_run() -> void:
	var zone := _zone_of(4, IrrigationScript.SPRAY)
	var result := IrrigationScript.check(zone, _supply())
	assert(bool(result["ok"]), "four spray heads draw 36 of 40: %s" % str(_reasons(result)))
	assert(_reasons(result).is_empty(), "nothing to report")
	assert(int(result["budget"]) == 4, "and the budget says so")


func test_a_rotor_on_a_supply_that_will_not_drive_it_is_refused_and_a_spray_is_not() -> void:
	# 220 kPa drives a spray head, which wants 210. It will not drive a rotor, which wants 350: a
	# head that will not open is a refusal about the head rather than about how many there are.
	var rotor := _zone_of(1, IrrigationScript.ROTOR)
	var weak := _supply(SUPPLY_FLOW, 220.0)
	var refused := IrrigationScript.check(rotor, weak)
	assert(not bool(refused["ok"]), "a rotor wants 350 kPa and the supply gives 220")
	assert(String(_reasons(refused)[0]).contains("350"), "naming what it wants: %s"
		% String(_reasons(refused)[0]))
	var spray := _zone_of(1, IrrigationScript.SPRAY)
	var allowed := IrrigationScript.check(spray, weak)
	assert(bool(allowed["ok"]), "a spray wants 210 and gets 220: %s" % str(_reasons(allowed)))


func test_two_kinds_on_one_valve_are_refused_and_both_are_named() -> void:
	var zone := _zone_of(2, IrrigationScript.SPRAY)
	IrrigationScript.add_head(zone, Vector2(9.0, 0.0), IrrigationScript.ROTOR)
	var result := IrrigationScript.check(zone, _supply())
	assert(not bool(result["ok"]), "one valve, one kind")
	var reason := String(_reasons(result)[0])
	assert(reason.contains("spray head") and reason.contains("gear rotor"),
		"both kinds are named: %s" % reason)


func test_a_head_outside_its_own_area_is_refused() -> void:
	var zone := IrrigationScript.make_zone(1, IrrigationScript.SPRAY)
	IrrigationScript.set_area(zone, _square(10.0))
	IrrigationScript.add_head(zone, Vector2(5.0, 5.0), IrrigationScript.SPRAY)
	IrrigationScript.add_head(zone, Vector2(20.0, 5.0), IrrigationScript.SPRAY)
	var result := IrrigationScript.check(zone, _supply())
	assert(not bool(result["ok"]), "a head 20 m out is not watering this bed")
	assert(String(_reasons(result)[0]).contains("outside the area"),
		"and the reason says so: %s" % String(_reasons(result)[0]))


func test_a_zone_with_no_heads_is_refused() -> void:
	var zone := IrrigationScript.make_zone(3, IrrigationScript.SPRAY)
	var result := IrrigationScript.check(zone, _supply())
	assert(not bool(result["ok"]), "a valve with nothing on it runs nothing")
	assert(String(_reasons(result)[0]) == "the zone has no heads", "said plainly: %s"
		% String(_reasons(result)[0]))


func test_the_precipitation_rate_is_the_zone_own_flow_over_its_own_area() -> void:
	# Two micro-sprays at three litres a minute over a ten by ten metre bed: six litres a minute over
	# a hundred square metres, which is 3.6 mm an hour.
	var zone := IrrigationScript.make_zone(1, IrrigationScript.MICRO)
	IrrigationScript.set_area(zone, _square(10.0))
	IrrigationScript.add_head(zone, Vector2(3.0, 3.0), IrrigationScript.MICRO)
	IrrigationScript.add_head(zone, Vector2(7.0, 7.0), IrrigationScript.MICRO)
	assert(is_equal_approx(IrrigationScript.area_m2(zone), 100.0), "a hundred square metres")
	var rate := IrrigationScript.precipitation_mm_hour(zone)
	assert(absf(rate - 3.6) < 0.001, "six litres a minute over a hundred metres is 3.6 mm/h: %f" % rate)
	assert(IrrigationScript.verdict_words(zone, _supply()).contains("3.6 mm/h"),
		"and the line a person reads says so: %s" % IrrigationScript.verdict_words(zone, _supply()))


func test_a_zone_with_no_area_says_what_cannot_be_worked_out() -> void:
	var zone := _zone_of(2, IrrigationScript.SPRAY)
	var result := IrrigationScript.check(zone, _supply())
	assert(bool(result["ok"]), "it can still be run: %s" % str(_reasons(result)))
	assert(IrrigationScript.precipitation_mm_hour(zone) == 0.0, "with no rate to give")
	var notes: Array = result["notes"]
	assert(not notes.is_empty(), "but it says so")
	assert(String(notes[0]).contains("no area is stated"), "in words: %s" % String(notes[0]))


# --- coverage -----------------------------------------------------------------------


func test_a_coverage_shortfall_is_reported_rather_than_refused() -> void:
	# A half-circle head in the middle of a ten metre square waters half of it.
	var zone := IrrigationScript.make_zone(1, IrrigationScript.SPRAY)
	IrrigationScript.set_area(zone, _square(10.0))
	IrrigationScript.add_head(zone, Vector2(5.0, 5.0), IrrigationScript.SPRAY, 0.0, 180.0)
	var covered := IrrigationScript.coverage(zone)
	assert(bool(covered["ok"]), "the area can be sampled")
	assert(int(covered["sampled"]) > 0, "and was")
	var fraction := float(covered["fraction"])
	assert(fraction > 0.3 and fraction < 0.7, "about half: %f" % fraction)
	var worst: Vector2 = covered["worst"]
	assert(worst.x <= 5.0, "the gap is behind the head: %s" % str(worst))
	var result := IrrigationScript.check(zone, _supply())
	assert(bool(result["ok"]), "a gap is a fact and not a refusal: %s" % str(_reasons(result)))
	var notes: Array = result["notes"]
	assert(not notes.is_empty(), "and it is reported")
	assert(String(notes[0]).contains("beyond every head"), "in words: %s" % String(notes[0]))


func test_a_zone_of_heads_one_throw_apart_leaves_no_gap() -> void:
	# A nine metre square is two throws each way, so heads set half a throw in from every edge sit at
	# 2.25 and 6.75 - and every point of the bed is then within one throw of the nearest head, the
	# farthest being a corner of the grid at 3.18 m. Given full circles there is nothing to report.
	var zone := IrrigationScript.make_zone(1, IrrigationScript.SPRAY)
	IrrigationScript.set_area(zone, _square(9.0))
	for x: float in [2.25, 6.75]:
		for y: float in [2.25, 6.75]:
			IrrigationScript.add_head(zone, Vector2(x, y), IrrigationScript.SPRAY, 0.0, 360.0)
	var covered := IrrigationScript.coverage(zone)
	assert(is_equal_approx(float(covered["fraction"]), 1.0),
		"nothing is left dry: %f of %d points" % [float(covered["fraction"]), int(covered["sampled"])])
	assert(IrrigationScript.check(zone, _supply())["notes"].is_empty(), "and nothing is reported")


func test_a_bed_that_is_not_a_whole_number_of_throws_reports_the_ground_it_misses() -> void:
	# Twenty metres is four and a half throws, so the far strip between the last grid line at 18 and
	# the edge at 20 has no head standing in it, and the ground there is only partly within a throw
	# of the row before. The check reports the fraction rather than refusing the design, which is the
	# point of measuring coverage instead of assuming that a grid one throw apart covers everything.
	var zone := IrrigationScript.make_zone(1, IrrigationScript.SPRAY)
	IrrigationScript.set_area(zone, _square(20.0))
	var report := IrrigationScript.lay_out(zone)
	assert(bool(report["ok"]), "twenty metres takes spray heads: %s" % String(report["reason"]))
	assert(int(report["placed"]) == 25, "five rows of five: %d" % int(report["placed"]))
	var covered := IrrigationScript.coverage(zone)
	var fraction := float(covered["fraction"])
	assert(fraction > 0.9 and fraction < 1.0, "most of it and not all of it: %f" % fraction)
	var notes: Array = IrrigationScript.check(zone, _supply())["notes"]
	assert(not notes.is_empty(), "the report carries the gap")
	assert(String(notes[0]).contains("%"), "and says how much of the area it is: %s"
		% String(notes[0]))


# --- laying heads out ---------------------------------------------------------------


func test_the_layout_sets_heads_across_the_bed_including_its_edges() -> void:
	# A nine metre square at a spray head's own 4.5 m throw: a grid line on each edge and one down the
	# middle, so three rows of three. The corner heads take quarter nozzles, the edge heads halves and
	# the middle one a full circle - which is what an irrigation plan of this bed looks like, and
	# which leaves nothing dry.
	var zone := IrrigationScript.make_zone(1, IrrigationScript.SPRAY)
	var ring := _square(9.0)
	IrrigationScript.set_area(zone, ring)
	var report := IrrigationScript.lay_out(zone)
	assert(bool(report["ok"]), "a nine metre bed takes spray heads: %s" % String(report["reason"]))
	assert(int(report["placed"]) == 9, "three rows of three: %d" % int(report["placed"]))
	assert(IrrigationScript.head_count(zone) == 9, "and they are in the zone")
	assert(is_equal_approx(float(report["spacing"]), 4.5), "head to head at the throw")
	assert(is_equal_approx(float(report["clearance"]), 0.0), "on the grid line, not pulled in from it")
	assert(is_equal_approx(IrrigationScript.demand_of(zone), 81.0), "nine heads draw 81 L/min")
	var nozzles := _nozzle_tally(zone)
	assert(int(nozzles.get(90.0, 0)) == 4, "four corners take quarters: %s" % str(nozzles))
	assert(int(nozzles.get(180.0, 0)) == 4, "four edges take halves: %s" % str(nozzles))
	assert(int(nozzles.get(360.0, 0)) == 1, "and the middle takes a full circle: %s" % str(nozzles))
	assert(is_equal_approx(float(IrrigationScript.coverage(zone)["fraction"]), 1.0),
		"and the bed is watered edge to edge: %f" % float(IrrigationScript.coverage(zone)["fraction"]))


## How many heads of each nozzle a zone holds.
func _nozzle_tally(zone: Dictionary) -> Dictionary:
	var counts := {}
	for entry in IrrigationScript.heads_of(zone):
		var arc := IrrigationScript.arc_of_head(entry as Dictionary)
		counts[arc] = int(counts.get(arc, 0)) + 1
	return counts


func test_a_big_bed_lays_out_a_head_on_every_grid_line() -> void:
	# Thirty metres is six and two thirds throws, so seven grid lines each way - the last one three
	# metres short of the far edge, which the row before it still reaches.
	var zone := IrrigationScript.make_zone(1, IrrigationScript.SPRAY)
	IrrigationScript.set_area(zone, _square(30.0))
	var report := IrrigationScript.lay_out(zone)
	assert(bool(report["ok"]), "thirty metres takes spray heads: %s" % String(report["reason"]))
	assert(int(report["placed"]) == 49, "seven by seven: %d" % int(report["placed"]))


func test_every_head_stands_on_the_bed() -> void:
	var zone := IrrigationScript.make_zone(1, IrrigationScript.MICRO)
	var ring := _square(12.0)
	IrrigationScript.set_area(zone, ring)
	var report := IrrigationScript.lay_out(zone)
	assert(bool(report["ok"]), "a twelve metre bed takes micro-sprays: %s" % String(report["reason"]))
	var box := Geom.points_aabb(ring)
	for entry in IrrigationScript.heads_of(zone):
		var at: Vector2 = (entry as Dictionary)["at"]
		assert(Geom.point_in_polygon(at, ring), "on the bed rather than near it: %s" % str(at))
		assert(box.has_point(at), "and inside the bed's own bounds: %s" % str(at))


func test_a_triangular_layout_stretches_the_spacing_and_sets_fewer_heads() -> void:
	# A triangular grid carries 1.155 times the spacing over the same ground: a bed of 49 heads square
	# comes out 42 staggered, which is one head in seven saved for exactly the same coverage.
	assert(absf(IrrigationScript.spacing_for(IrrigationScript.SPRAY, true) / 4.5
		- IrrigationScript.TRIANGULAR_SPACING) < 1e-9, "the spacing stretches by two over root three")
	var wide := IrrigationScript.make_zone(1, IrrigationScript.SPRAY)
	IrrigationScript.set_area(wide, _square(30.0))
	var square_report := IrrigationScript.lay_out(wide)
	var staggered := IrrigationScript.make_zone(2, IrrigationScript.SPRAY)
	IrrigationScript.set_area(staggered, _square(30.0))
	var staggered_report := IrrigationScript.lay_out(staggered, IrrigationScript.SPRAY, 0.0, true)
	assert(bool(square_report["ok"]) and bool(staggered_report["ok"]),
		"both arrangements lay out: %s / %s" % [square_report["reason"], staggered_report["reason"]])
	assert(int(square_report["placed"]) == 49, "seven by seven square: %d" % int(square_report["placed"]))
	assert(int(staggered_report["placed"]) == 42, "and 42 staggered: %d" % int(staggered_report["placed"]))
	assert(is_equal_approx(float(staggered_report["spacing"]),
		4.5 * IrrigationScript.TRIANGULAR_SPACING), "on the wider spacing")


func test_a_layout_that_wants_more_than_the_cap_is_refused_and_sets_nothing() -> void:
	var zone := IrrigationScript.make_zone(1, IrrigationScript.SPRAY)
	IrrigationScript.set_area(zone, _square(400.0))
	IrrigationScript.add_head(zone, Vector2(2.0, 2.0), IrrigationScript.SPRAY)
	var report := IrrigationScript.lay_out(zone)
	assert(not bool(report["ok"]), "a four hundred metre bed is not one zone")
	assert(String(report["reason"]).contains("300"), "the cap is named: %s" % String(report["reason"]))
	assert(int(report["placed"]) == 0, "and nothing was set")
	assert(IrrigationScript.head_count(zone) == 1, "the head that was already there is left alone")


func test_a_bed_a_head_is_too_wide_for_reports_the_water_it_puts_off_the_bed() -> void:
	# A one metre strip with a 4.5 m spray head on its edge: the heads take their place along the
	# edge, and the check says the truth about it - most of every head's throw lands beside the bed,
	# and only about half the strip is properly watered. That is not a refusal: it is the report a
	# designer needs, and the answer is a micro-spray or a tighter spacing.
	var zone := IrrigationScript.make_zone(1, IrrigationScript.SPRAY)
	IrrigationScript.set_area(zone, PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 30.0), Vector2(0.0, 30.0),
	]))
	var report := IrrigationScript.lay_out(zone)
	assert(bool(report["ok"]), "a strip still takes heads: %s" % String(report["reason"]))
	assert(int(report["placed"]) == 7, "one every throw along it: %d" % int(report["placed"]))
	for entry in IrrigationScript.heads_of(zone):
		assert(is_equal_approx(IrrigationScript.arc_of_head(entry as Dictionary), 90.0),
			"each one a quarter, because the bed is a quarter of its throw wide")
	var covered := IrrigationScript.coverage(zone)
	assert(float(covered["fraction"]) < 0.6, "and less than two thirds of it is watered: %f"
		% float(covered["fraction"]))
	assert(bool(IrrigationScript.check(zone, _supply(80.0))["ok"]), "which is a report and not a refusal")


func test_an_area_the_grid_cannot_land_in_is_refused_in_words() -> void:
	# A small diamond between two grid lines: the grid is phased from the area's own bounding box, so
	# its corner grid line falls on the box's corner rather than on the bed, and nothing else lands
	# inside it. The refusal says that rather than setting a head somewhere off the bed.
	var zone := IrrigationScript.make_zone(1, IrrigationScript.SPRAY)
	IrrigationScript.set_area(zone, PackedVector2Array([
		Vector2(2.0, 1.6), Vector2(2.4, 2.0), Vector2(2.0, 2.4), Vector2(1.6, 2.0),
	]))
	var report := IrrigationScript.lay_out(zone)
	assert(not bool(report["ok"]), "an 0.8 m diamond takes no spray head")
	assert(String(report["reason"]).contains("no grid line"), "and says why: %s"
		% String(report["reason"]))
	assert(IrrigationScript.head_count(zone) == 0, "setting nothing")


func test_an_outline_that_is_not_an_area_is_refused() -> void:
	var zone := IrrigationScript.make_zone(1, IrrigationScript.SPRAY)
	IrrigationScript.set_area(zone, PackedVector2Array([Vector2(0.0, 0.0), Vector2(1.0, 0.0)]))
	var report := IrrigationScript.lay_out(zone)
	assert(not bool(report["ok"]), "two points are not an area")
	assert(String(report["reason"]).contains("not an area"), "in words: %s" % String(report["reason"]))


func test_a_laid_out_zone_sets_each_head_the_nozzle_its_own_position_wants() -> void:
	var ring := _square(30.0)
	assert(is_equal_approx(float(IrrigationScript.nozzle_for(ring, Vector2(15.0, 15.0),
		IrrigationScript.SPRAY)["arc"]), 360.0), "in the middle of the bed, a full circle")
	var edge := IrrigationScript.nozzle_for(ring, Vector2(15.0, 2.25), IrrigationScript.SPRAY)
	assert(is_equal_approx(float(edge["arc"]), 270.0), "half a throw in from an edge, three quarters")
	assert(absf(float(edge["heading"]) - PI * 0.5) < 0.2,
		"facing the bed it has: %f" % float(edge["heading"]))
	var corner := IrrigationScript.nozzle_for(ring, Vector2(2.25, 2.25), IrrigationScript.SPRAY)
	assert(is_equal_approx(float(corner["arc"]), 180.0), "half a throw in from two edges, a half")
	var point := IrrigationScript.nozzle_for(ring, Vector2(0.0, 0.0), IrrigationScript.SPRAY)
	assert(is_equal_approx(float(point["arc"]), 90.0), "on the corner of the area, a quarter")
	assert(absf(float(point["heading"]) - PI * 0.25) < 0.2,
		"facing into the bed: %f" % float(point["heading"]))


func test_laying_a_zone_out_again_replaces_its_heads() -> void:
	var zone := IrrigationScript.make_zone(1, IrrigationScript.MICRO)
	IrrigationScript.set_area(zone, _square(12.0))
	var first := IrrigationScript.lay_out(zone)
	var second := IrrigationScript.lay_out(zone)
	assert(int(first["placed"]) == int(second["placed"]), "the same answer twice")
	assert(IrrigationScript.head_count(zone) == int(second["placed"]),
		"and the heads are not doubled: %d" % IrrigationScript.head_count(zone))


# --- the file -----------------------------------------------------------------------


func test_a_zone_round_trips_through_the_file() -> void:
	var zone := IrrigationScript.make_zone(4, IrrigationScript.ROTOR)
	IrrigationScript.set_area(zone, _square(20.0))
	IrrigationScript.add_head(zone, Vector2(2.5, 2.5), IrrigationScript.ROTOR, PI * 0.5, 270.0)
	IrrigationScript.add_head(zone, Vector2(9.5, 9.5), IrrigationScript.ROTOR)
	var read := IrrigationScript.from_dict(
		JSON.parse_string(JSON.stringify(IrrigationScript.to_dict([zone])))
	)
	assert(read.size() == 1, "one zone came back: %d" % read.size())
	var back: Dictionary = read[0]
	assert(int(back["number"]) == 4, "its number")
	assert(int(back["valve"]) == 4, "and its valve")
	assert(String(back["kind"]) == IrrigationScript.ROTOR, "and its kind")
	assert(is_equal_approx(IrrigationScript.area_m2(back), 400.0), "and its area")
	assert(IrrigationScript.head_count(back) == 2, "and its heads")
	var heads: Array = IrrigationScript.heads_of(back)
	var first: Dictionary = heads[0]
	assert((first["at"] as Vector2).is_equal_approx(Vector2(2.5, 2.5)), "at their own positions")
	assert(absf(float(first["heading"]) - PI * 0.5) < 1e-6, "with their own headings")
	assert(is_equal_approx(float(first["arc"]), 270.0), "and their own nozzles")
	assert(is_equal_approx(IrrigationScript.demand_of(back), 26.0), "and still draw their water")


func test_a_record_that_is_not_a_zone_is_dropped_rather_than_invented() -> void:
	var good := IrrigationScript.make_zone(1, IrrigationScript.SPRAY)
	IrrigationScript.add_head(good, Vector2(1.0, 1.0), IrrigationScript.SPRAY)
	var read := IrrigationScript.from_dict({
		"zones": [
			"not a zone",
			{"kind": IrrigationScript.SPRAY},
			{"number": 2, "kind": "mister"},
			good_as_dict(good),
			{"number": 3, "kind": IrrigationScript.SPRAY, "heads": [
				{"kind": IrrigationScript.SPRAY, "at": "nowhere"},
				{"kind": "mister", "at": [2.0, 2.0]},
				{"kind": IrrigationScript.SPRAY, "at": [3.0, 3.0]},
			]},
		],
	})
	assert(read.size() == 2, "only the two real zones: %d" % read.size())
	assert(int(read[0]["number"]) == 1, "the one that was written properly")
	assert(IrrigationScript.head_count(read[1]) == 1,
		"a zone with two damaged heads keeps the one it can read: %d"
		% IrrigationScript.head_count(read[1]))


## One zone as the file holds it, which is what the reader is handed.
func good_as_dict(zone: Dictionary) -> Dictionary:
	var written: Dictionary = IrrigationScript.to_dict([zone])
	return (written["zones"] as Array)[0]


func test_a_file_that_is_not_a_file_reads_as_no_zones() -> void:
	assert(IrrigationScript.from_dict({}).is_empty(), "nothing held, nothing read")
	assert(IrrigationScript.from_dict({"zones": 7}).is_empty(), "a number is not a list of zones")
	assert(IrrigationScript.from_dict({"zones": []}).is_empty(), "and an empty list is empty")


# --- the schedule, and the words ----------------------------------------------------


func test_the_schedule_reads_as_a_row_a_designer_can_check() -> void:
	var ok_zone := _zone_of(4, IrrigationScript.SPRAY)
	var over := _zone_of(12, IrrigationScript.SPRAY)
	over["number"] = 2
	over["valve"] = 2
	var rows := IrrigationScript.schedule([ok_zone, over], _supply())
	assert(rows.size() == 2, "one row each")
	assert(String(rows[0]["verdict"]) == "will run", "the first runs: %s" % String(rows[0]["verdict"]))
	assert(int(rows[0]["heads"]) == 4, "with four heads on it")
	var line := IrrigationScript.schedule_row_words(rows[0])
	assert(line.contains("Zone 1") and line.contains("valve 1"), "naming the zone and the valve: %s"
		% line)
	assert(line.contains("4 spray heads") and line.contains("36 L/min"), "with its heads and flow: %s"
		% line)
	assert(line.contains("will run"), "and its verdict: %s" % line)
	assert(String(rows[1]["verdict"]).contains("108"), "a refusal is the row's own line: %s"
		% String(rows[1]["verdict"]))
	var lines := IrrigationScript.schedule_lines([ok_zone, over], _supply())
	assert(lines.size() == 2, "and the lines a sheet carries are one per zone")


func test_an_area_is_written_in_the_drawings_own_units() -> void:
	# The words an area is written in come from the drawing rather than from the page that prints it:
	# an imperial drawing must not go on claiming square metres on a schedule or a verdict line.
	var zone := _zone_of(4, IrrigationScript.SPRAY)
	IrrigationScript.set_area(zone, _square(10.0))
	var imperial := DraftUnits.new()
	imperial.system = DraftUnits.System.IMPERIAL
	var row := IrrigationScript.schedule([zone], _supply(), imperial)[0]
	assert(String(row["area_text"]).ends_with(" ft2"), "an imperial drawing says square feet: %s"
		% String(row["area_text"]))
	assert(IrrigationScript.schedule_row_words(row).contains("ft2"),
		"and the row a sheet carries says so too: %s" % IrrigationScript.schedule_row_words(row))
	# Handed nothing - a panel row built by hand - the words are the metre default.
	var metric := IrrigationScript.schedule([zone], _supply())[0]
	assert(String(metric["area_text"]).ends_with(" m2"),
		"with no drawing handed over it is metres: %s" % String(metric["area_text"]))


func test_the_valve_numbers_are_handed_out_once() -> void:
	assert(IrrigationScript.next_number([]) == 1, "the first zone is zone one")
	assert(IrrigationScript.next_valve([]) == 1, "on valve one")
	var one := IrrigationScript.make_zone(1, IrrigationScript.SPRAY)
	one["valve"] = 1
	var three := IrrigationScript.make_zone(3, IrrigationScript.SPRAY)
	three["valve"] = 3
	assert(IrrigationScript.next_number([one, three]) == 4, "the next zone follows the highest")
	assert(IrrigationScript.next_valve([one, three]) == 2, "and the valve that is free is two")


func test_the_zone_words_read_as_one_line() -> void:
	var zone := _zone_of(4, IrrigationScript.SPRAY)
	IrrigationScript.set_area(zone, _square(10.0))
	assert(IrrigationScript.zone_label(zone) == "Zone 1", "labelled by its number")
	assert(IrrigationScript.kind_count_words(IrrigationScript.SPRAY, 1) == "1 spray head",
		"one head is one head")
	assert(IrrigationScript.kind_count_words(IrrigationScript.SPRAY, 4) == "4 spray heads",
		"and four are four")
	var line := IrrigationScript.verdict_words(zone, _supply())
	assert(line.begins_with("Zone 1 will run:"), "the line opens with the verdict: %s" % line)
	assert(line.contains("4 spray heads"), "names the heads: %s" % line)
	assert(line.contains("of 40 L/min"), "and the supply they draw from: %s" % line)
	var refused := IrrigationScript.verdict_words(_zone_of(12, IrrigationScript.SPRAY), _supply())
	assert(refused.begins_with("Zone 1: "), "a refusal opens with the zone: %s" % refused)
	assert(refused.contains("4 of them fit"), "and says what would fit: %s" % refused)


func test_a_head_can_be_taken_back_off_a_zone() -> void:
	var zone := _zone_of(2, IrrigationScript.SPRAY)
	var before := IrrigationScript.head_count(zone)
	assert(IrrigationScript.remove_head(zone, 0), "the first head comes off")
	assert(IrrigationScript.head_count(zone) == before - 1, "and is gone")
	assert(not IrrigationScript.remove_head(zone, 7), "a head that is not there is not removed")
	IrrigationScript.clear_heads(zone)
	assert(IrrigationScript.head_count(zone) == 0, "and a zone can be emptied")