extends Node
## Core tests for the drafting subsystem: units, geometry kernel, entities,
## line style, the layer convention, and undo.
##
## The kernel and the unit system are pure, so these need no scene at all — the
## same shape as the existing ViewMath tests.

const Units := preload("res://scripts/draft/units.gd")
const Geom := preload("res://scripts/draft/geom2d.gd")
const Entity := preload("res://scripts/draft/draft_entity.gd")
const Style := preload("res://scripts/draft/line_style.gd")
const Layer := preload("res://scripts/draft/draft_layer.gd")
const LayerSet := preload("res://scripts/draft/layer_set.gd")
const Undo := preload("res://scripts/draft/undo_stack.gd")


# --- units --------------------------------------------------------------------------


func test_metric_lengths_parse() -> void:
	assert(is_equal_approx(Units.parse_length("1.5m"), 1.5))
	assert(is_equal_approx(Units.parse_length("1500mm"), 1.5))
	assert(is_equal_approx(Units.parse_length("150cm"), 1.5))
	assert(is_equal_approx(Units.parse_length("0.0015km"), 1.5))
	# A bare number takes the active system.
	assert(is_equal_approx(Units.parse_length("6"), 6.0))
	assert(is_equal_approx(Units.parse_length("6", Units.System.IMPERIAL), 6.0 * Units.FOOT))


func test_imperial_lengths_parse() -> void:
	assert(is_equal_approx(Units.parse_length("12in"), 12.0 * Units.INCH))
	assert(is_equal_approx(Units.parse_length("12\""), 12.0 * Units.INCH))
	assert(is_equal_approx(Units.parse_length("6ft"), 6.0 * Units.FOOT))
	assert(is_equal_approx(Units.parse_length("3yd"), 3.0 * Units.YARD))


func test_feet_and_inches_forms_agree() -> void:
	# 12'6" is 12.5 international feet.
	var expected := 12.5 * Units.FOOT
	assert(is_equal_approx(Units.parse_length("12'6\""), expected))
	assert(is_equal_approx(Units.parse_length("12-6"), expected))
	assert(is_equal_approx(Units.parse_length("12 6"), expected))
	# With a fraction: 10'6 1/2"
	assert(is_equal_approx(Units.parse_length("10'6 1/2\""), 10.5 * Units.FOOT + 0.5 * Units.INCH))
	assert(is_equal_approx(Units.parse_length("10'6-1/2\""), 10.5 * Units.FOOT + 0.5 * Units.INCH))


func test_bad_input_is_nan_not_zero() -> void:
	# A failed parse must never be mistaken for a measurement of zero.
	assert(is_nan(Units.parse_length("")))
	assert(is_nan(Units.parse_length("abc")))
	assert(is_nan(Units.parse_length("m")))
	assert(is_nan(Units.parse_area("nonsense")))


func test_us_survey_foot_is_distinct_and_exact() -> void:
	assert(is_equal_approx(Units.US_SURVEY_FOOT, 0.3048006096012192))
	# 2 ppm longer than the international foot.
	var relative := Units.US_SURVEY_FOOT / Units.FOOT - 1.0
	assert(is_equal_approx(snappedf(relative, 0.000001), 0.000002))
	var international := Units.parse_length("100ft")
	var survey := Units.parse_length("100ft", Units.System.METRIC, true)
	assert(survey > international)
	assert(is_equal_approx(snappedf((survey - international) * 1000.0, 0.001), 0.061))


func test_length_formatting_round_trips() -> void:
	var units := Units.new()
	for metres: float in [0.0, 1.0, 3.81, 12.5, 42.195]:
		var parsed := Units.parse_length(units.format_length(metres))
		assert(is_equal_approx(snappedf(parsed, 0.001), snappedf(metres, 0.001)))

	units.system = Units.System.IMPERIAL
	units.length_style = Units.LengthStyle.ARCHITECTURAL
	# The exact case from the survey requirement.
	assert(units.format_length(3.81) == "12'-6\"")
	assert(units.format_length(10.0 * Units.FOOT) == "10'-0\"")
	# Half an inch, reduced.
	assert(units.format_length(10.5 * Units.FOOT + 0.5 * Units.INCH) == "10'-6 1/2\"")


func test_architectural_rounds_to_the_configured_fraction() -> void:
	var units := Units.new()
	units.system = Units.System.IMPERIAL
	units.length_style = Units.LengthStyle.ARCHITECTURAL
	units.inch_denominator = 2
	assert(units.format_length(3.81) == "12'-6\"")
	units.inch_denominator = 16
	# 0.2 mm over 12 ft is a fortieth of an inch: rounds away to nothing.
	assert(units.format_length(12.0 * Units.FOOT + 0.0002) == "12'-0\"")
	# 3 mm is closer to 1/8 in than to nothing, and must show as such.
	assert(units.format_length(12.0 * Units.FOOT + 0.003) == "12'-0 1/8\"")


func test_area_conversions_use_exact_constants() -> void:
	# 1 acre = 4840 sq yd, exactly.
	assert(is_equal_approx(Units.ACRE, 4046.8564224))
	assert(is_equal_approx(Units.parse_area("1ac"), 4046.8564224))
	assert(is_equal_approx(Units.parse_area("450ft2"), 450.0 * Units.SQ_FOOT))
	assert(is_equal_approx(Units.parse_area("0.5ha"), 5000.0))
	# The verified lot from the survey requirements.
	var lot := 6000.0 * Units.SQ_FOOT
	assert(is_equal_approx(snappedf(lot, 0.0001), 557.4182))
	assert(is_equal_approx(snappedf(Units.acres(lot), 0.000001), 0.137741))


func test_display_precision_follows_zoom() -> void:
	assert(Units.display_decimals(33.71) == 3)
	assert(Units.display_decimals(0.5) == 1)
	assert(Units.display_decimals(0.0) == 0)
	# Never claims more precision than is resolvable.
	assert(Units.display_decimals(1.0) == 1)


# --- geometry kernel ----------------------------------------------------------------


func test_segment_intersection_crossing() -> void:
	var result := Geom.segment_segment(Vector2(-5, 0), Vector2(5, 0), Vector2(0, -5), Vector2(0, 5))
	assert(result["hit"])
	assert(result["point"].is_equal_approx(Vector2.ZERO))


func test_segment_intersection_misses() -> void:
	# The infinite lines cross, but the segments do not.
	var result := Geom.segment_segment(Vector2(0, 0), Vector2(1, 0), Vector2(5, -5), Vector2(5, 5))
	assert(not result["hit"])
	assert(not result["parallel"])


func test_segment_intersection_parallel_and_collinear() -> void:
	var parallel := Geom.segment_segment(Vector2(0, 0), Vector2(10, 0), Vector2(0, 1), Vector2(10, 1))
	assert(not parallel["hit"])
	assert(parallel["parallel"])
	assert(not parallel["collinear"])
	# Collinear overlap has no single intersection point and is reported as such.
	var collinear := Geom.segment_segment(Vector2(0, 0), Vector2(10, 0), Vector2(5, 0), Vector2(15, 0))
	assert(not collinear["hit"])
	assert(collinear["parallel"])
	assert(collinear["collinear"])


func test_segment_intersection_touching_an_endpoint_returns_that_endpoint() -> void:
	var result := Geom.segment_segment(Vector2(0, 0), Vector2(10, 0), Vector2(10, 0), Vector2(10, 10))
	assert(result["hit"])
	assert(result["point"].is_equal_approx(Vector2(10, 0)))


func test_line_circle_cases() -> void:
	var two := Geom.line_circle(Vector2(-10, 0), Vector2(1, 0), Vector2.ZERO, 5.0)
	assert(two.size() == 2)
	assert(two[0].is_equal_approx(Vector2(-5, 0)))
	assert(two[1].is_equal_approx(Vector2(5, 0)))
	# Tangent yields exactly one hit.
	var tangent := Geom.line_circle(Vector2(-10, 5), Vector2(1, 0), Vector2.ZERO, 5.0)
	assert(tangent.size() == 1)
	assert(tangent[0].is_equal_approx(Vector2(0, 5)))
	# A miss yields none, not a sentinel point at the origin.
	assert(Geom.line_circle(Vector2(-10, 6), Vector2(1, 0), Vector2.ZERO, 5.0).is_empty())


func test_circle_circle_reduction_to_the_radical_axis() -> void:
	var hits := Geom.circle_circle(Vector2.ZERO, 5.0, Vector2(6, 0), 5.0)
	assert(hits.size() == 2)
	# The chord sits at x = 3 with half-length 4.
	for point: Vector2 in hits:
		assert(is_equal_approx(point.x, 3.0))
		assert(is_equal_approx(absf(point.y), 4.0))
	# Externally tangent: one hit.
	assert(Geom.circle_circle(Vector2.ZERO, 5.0, Vector2(10, 0), 5.0).size() == 1)
	# Separate, and one inside the other: no hits.
	assert(Geom.circle_circle(Vector2.ZERO, 5.0, Vector2(20, 0), 5.0).is_empty())
	assert(Geom.circle_circle(Vector2.ZERO, 5.0, Vector2(1, 0), 2.0).is_empty())
	# Concentric has no unique answer.
	assert(Geom.circle_circle(Vector2.ZERO, 5.0, Vector2.ZERO, 5.0).is_empty())


func test_arc_sweep_membership_handles_the_wrap() -> void:
	# Quarter arc from 0 to +90 degrees.
	assert(Geom.angle_in_sweep(PI * 0.25, 0.0, PI * 0.5))
	assert(not Geom.angle_in_sweep(-PI * 0.25, 0.0, PI * 0.5))
	# Clockwise arc.
	assert(Geom.angle_in_sweep(-PI * 0.25, 0.0, -PI * 0.5))
	assert(not Geom.angle_in_sweep(PI * 0.25, 0.0, -PI * 0.5))
	# An arc crossing the +/-PI seam must still contain the angles inside it.
	assert(Geom.angle_in_sweep(PI, 3.0, 2.0))
	assert(Geom.angle_in_sweep(-3.0, 3.0, 2.0))
	assert(not Geom.angle_in_sweep(0.0, 3.0, 1.0))
	# A full turn contains everything.
	assert(Geom.angle_in_sweep(2.5, 0.0, TAU))


func test_arc_measurement() -> void:
	assert(is_equal_approx(Geom.arc_length(5.0, PI * 0.5), 5.0 * PI * 0.5))
	assert(is_equal_approx(Geom.arc_chord(5.0, PI * 0.5), 5.0 * sqrt(2.0)))


func test_bulge_round_trips() -> void:
	# A quarter turn has bulge tan(90deg/4) = tan(22.5deg).
	var quarter := Geom.bulge_from_sweep(PI * 0.5)
	assert(is_equal_approx(snappedf(quarter, 0.000001), 0.414214))
	assert(is_equal_approx(Geom.sweep_from_bulge(quarter), PI * 0.5))


func test_nearest_point_on_arc_falls_back_to_an_end() -> void:
	var centre := Vector2.ZERO
	# A point beyond the arc's finish end snaps to that end, not to the bounding
	# circle. The arc runs from (5,0) anticlockwise to (0,5).
	var beyond := Vector2(-10, 10)
	var nearest := Geom.closest_point_on_arc(beyond, centre, 5.0, 0.0, PI * 0.5)
	assert(nearest.is_equal_approx(Geom.arc_point(centre, 5.0, 0.0, PI * 0.5, 1.0)))

	# A point beyond the start end snaps back to the start.
	var behind := Vector2(10, -10)
	var back := Geom.closest_point_on_arc(behind, centre, 5.0, 0.0, PI * 0.5)
	assert(back.is_equal_approx(Geom.arc_point(centre, 5.0, 0.0, PI * 0.5, 0.0)))


func test_polygon_measures() -> void:
	var square := PackedVector2Array([
		Vector2(0, 0), Vector2(10, 0), Vector2(10, 10), Vector2(0, 10)])
	assert(is_equal_approx(Geom.polygon_area(square), 100.0))
	assert(is_equal_approx(Geom.polygon_perimeter(square, true), 40.0))
	assert(is_equal_approx(Geom.polygon_perimeter(square, false), 30.0))
	assert(not Geom.is_polygon_clockwise(square))
	assert(Geom.polygon_centroid(square).is_equal_approx(Vector2(5, 5)))


func test_self_intersecting_polygon_is_rejected() -> void:
	var bow_tie := PackedVector2Array([
		Vector2(0, 0), Vector2(10, 10), Vector2(10, 0), Vector2(0, 10)])
	assert(not Geom.polygon_is_simple(bow_tie))
	assert(Geom.polygon_is_simple(PackedVector2Array([
		Vector2(0, 0), Vector2(10, 0), Vector2(10, 10), Vector2(0, 10)])))


func test_significant_digits_survive_a_double_round_trip() -> void:
	# A value that a float32 cannot hold exactly must come back unchanged.
	var precise := 12.3456789012345
	var points := PackedVector2Array([Vector2(precise, 0.0)])
	assert(points[0].x == precise or absf(points[0].x - precise) < 0.00001)


func test_hatch_spacing_and_clipping() -> void:
	var square := PackedVector2Array([
		Vector2(0, 0), Vector2(10, 0), Vector2(10, 10), Vector2(0, 10)])
	var lines := Geom.hatch_lines([square], 2.0, 0.0)
	# Scanlines at y = 0, 2, 4, 6, 8 cross the square; y = 10 does not, because
	# the half-open rule counts a vertex once.
	assert(lines.size() == 5)
	for segment: PackedVector2Array in lines:
		assert(segment.size() == 2)
		assert(is_equal_approx(segment[0].y, segment[1].y))
		assert(is_equal_approx(segment[0].x, 0.0))
		assert(is_equal_approx(segment[1].x, 10.0))


func test_hatch_does_not_fill_a_hole() -> void:
	var outer := PackedVector2Array([
		Vector2(0, 0), Vector2(30, 0), Vector2(30, 30), Vector2(0, 30)])
	var hole := PackedVector2Array([
		Vector2(12, 12), Vector2(18, 12), Vector2(18, 18), Vector2(12, 18)])
	var lines := Geom.hatch_lines([outer, hole], 3.0, 0.0)
	# Some scanline must be split into two runs by the hole.
	var outside := 0
	for segment: PackedVector2Array in lines:
		if is_equal_approx(segment[1].x - segment[0].x, 30.0):
			outside += 1
	assert(lines.size() > outside)


func test_fill_grid_stays_inside() -> void:
	var square := PackedVector2Array([
		Vector2(0, 0), Vector2(10, 0), Vector2(10, 10), Vector2(0, 10)])
	var points := Geom.fill_grid(square, 3.0)
	assert(points.size() == 16)
	for point: Vector2 in points:
		assert(Geom.point_in_polygon(point, square))


func test_dash_pattern_repeats_and_preserves_phase() -> void:
	# A 20 m run with a 6 m dash and a 2 m gap is three dashes.
	var straight := PackedVector2Array([Vector2(0, 0), Vector2(20, 0)])
	assert(Geom.dash_polyline(straight, [6.0, 2.0]).size() == 3)

	# The same total length bent into two segments must not restart the pattern.
	var bent := PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(20, 0)])
	assert(Geom.dash_polyline(bent, [6.0, 2.0]).size() == 3)

	# Doubling every coordinate must not change the pattern in any way: this is
	# what keeps dashes still when the view pans (REQ 4.3.2).
	var shifted := PackedVector2Array([Vector2(1000, 500), Vector2(1020, 500)])
	var first := Geom.dash_polyline(straight, [6.0, 2.0])
	var second := Geom.dash_polyline(shifted, [6.0, 2.0])
	assert(first.size() == second.size())
	for index in first.size():
		assert(is_equal_approx(first[index].size(), second[index].size()))


func test_aabb_of_an_arc_is_not_its_bounding_circle() -> void:
	var box := Geom.arc_aabb(Vector2.ZERO, 5.0, 0.0, PI * 0.5)
	assert(is_equal_approx(box.position.x, 0.0))
	assert(is_equal_approx(box.position.y, 0.0))
	assert(is_equal_approx(box.end.x, 5.0))
	assert(is_equal_approx(box.end.y, 5.0))


func test_offset_polygon_insets_exactly() -> void:
	var square := PackedVector2Array([
		Vector2(0, 0), Vector2(10, 0), Vector2(10, 10), Vector2(0, 10)])
	var result := Geom.offset_polygon(square, -1.0, false)
	assert(result.size() == 1)
	assert(is_equal_approx(Geom.polygon_area(result[0]), 64.0))


# --- entities -----------------------------------------------------------------------


func test_line_entity() -> void:
	var line := Entity.make_line(Vector2(0, 0), Vector2(3, 4))
	assert(line.kind == Entity.Kind.LINE)
	assert(is_equal_approx(line.length(), 5.0))
	assert(line.point_count() == 2)
	assert(line.outline().size() == 2)


func test_arc_entity_is_parametric() -> void:
	var arc := Entity.make_arc(Vector2.ZERO, 5.0, 0.0, PI * 0.5)
	assert(is_equal_approx(arc.length(), 5.0 * PI * 0.5))
	# Editing the radius changes the arc without moving its centre.
	arc.params[2] = 10.0
	assert(is_equal_approx(arc.length(), 10.0 * PI * 0.5))
	assert(arc.point(0).is_equal_approx(Vector2.ZERO))


func test_rectangle_entity_measures() -> void:
	var rect := Entity.make_rectangle(Vector2(1, 2), Vector2(4, 3), 0.0)
	assert(is_equal_approx(rect.area(), 12.0))
	assert(is_equal_approx(rect.length(), 14.0))
	assert(rect.outline().size() == 4)
	assert(rect.is_closed())


func test_polygon_entity_measures() -> void:
	var polygon := Entity.make_polyline(PackedVector2Array([
		Vector2(0, 0), Vector2(10, 0), Vector2(10, 10)]), true)
	assert(is_equal_approx(polygon.area(), 50.0))
	assert(is_equal_approx(polygon.length(), 20.0 + sqrt(200.0)))


func test_bulge_expands_into_an_arc_in_the_outline() -> void:
	var polyline := Entity.make_polyline(PackedVector2Array([
		Vector2(0, 0), Vector2(10, 0)]), false)
	polyline.bulges = PackedFloat64Array([Geom.bulge_from_sweep(PI * 0.5)])
	# A quarter-circle bulge is longer than the straight chord.
	assert(polyline.outline().size() > 3)


func test_translate_moves_every_kind() -> void:
	var offset := Vector2(3, 4)
	var line := Entity.make_line(Vector2(0, 0), Vector2(2, 0))
	line.translate(offset)
	assert(line.point(0).is_equal_approx(Vector2(3, 4)))
	assert(line.point(1).is_equal_approx(Vector2(5, 4)))

	# A circle stores its centre, so the radius must survive a move untouched.
	var circle := Entity.make_circle(Vector2(0, 0), 2.5)
	circle.translate(offset)
	assert(circle.point(0).is_equal_approx(Vector2(3, 4)))
	assert(is_equal_approx(circle.params[2], 2.5))


func test_entity_round_trips_through_serialisation() -> void:
	var original := Entity.make_polyline(PackedVector2Array([
		Vector2(1.25, 2.5), Vector2(3.75, 4.125)]), false)
	original.layer = LayerSet.NEW_BED
	original.bulges = PackedFloat64Array([0.0, 0.5])
	var restored := Entity.from_dict(original.to_dict())
	assert(restored.kind == original.kind)
	assert(restored.layer == original.layer)
	assert(restored.params == original.params)
	assert(restored.bulges == original.bulges)
	assert(restored.point(0).is_equal_approx(original.point(0)))


func test_entity_copy_is_independent() -> void:
	var original := Entity.make_line(Vector2(0, 0), Vector2(1, 1))
	var duplicate := original.copy()
	duplicate.translate(Vector2(10, 10))
	assert(original.point(0).is_equal_approx(Vector2(0, 0)))
	assert(duplicate.point(0).is_equal_approx(Vector2(10, 10)))


# --- line style ---------------------------------------------------------------------


func test_weight_law_matches_the_paper_at_sheet_zoom() -> void:
	# 1:100 on A3, printable height 267 mm, viewed 900 px tall.
	var printable_mm := 267.0
	var pixels_per_paper_mm := 900.0 / printable_mm
	var sheet_metres := printable_mm * 100.0 / 1000.0
	var pixels_per_metre := 900.0 / sheet_metres
	for weight: float in Style.WEIGHTS:
		var via_law := Style.model_width_m(weight, 100.0) * pixels_per_metre
		var via_paper := weight * pixels_per_paper_mm
		assert(is_equal_approx(snappedf(via_law, 0.0001), snappedf(via_paper, 0.0001)))


func test_weight_is_constant_on_paper() -> void:
	# The same weight covers more model at a smaller scale, which is the point.
	assert(is_equal_approx(Style.model_width_m(0.35, 100.0), 0.035))
	assert(is_equal_approx(Style.model_width_m(0.35, 200.0), 0.070))


func test_hairlines_stay_visible() -> void:
	var style := Style.new()
	style.plot_weight_mm = Style.HAIRLINE
	# Far out, the true width falls below a pixel.
	assert(style.width_pixels(100.0, 1.0) == 1.0)
	style.display_lineweights = false
	assert(style.width_pixels(100.0, 100.0) == 1.0)


func test_weight_in_points_for_vector_output() -> void:
	var style := Style.new()
	style.plot_weight_mm = 0.35
	assert(is_equal_approx(snappedf(style.width_points(), 0.001), 0.992))


func test_linetype_patterns_convert_by_the_same_law() -> void:
	assert(Style.pattern_for(&"dashed") == [6.0, 2.0])
	assert(Style.pattern_for(&"continuous").is_empty())
	var model := Style.pattern_model_m(Style.pattern_for(&"dashed"), 100.0)
	assert(is_equal_approx(model[0], 0.6))
	assert(is_equal_approx(model[1], 0.2))
	assert(Style.has_linetype(&"centre"))
	assert(not Style.has_linetype(&"nonexistent"))


func test_hierarchy_is_ordered_heaviest_first() -> void:
	assert(Style.hierarchy_weight(&"sheet_border") > Style.hierarchy_weight(&"structure_cut"))
	assert(Style.hierarchy_weight(&"structure_cut") > Style.hierarchy_weight(&"property_line"))
	assert(Style.hierarchy_weight(&"property_line") > Style.hierarchy_weight(&"annotation"))
	assert(Style.hierarchy_weight(&"annotation") > Style.hierarchy_weight(&"plant_symbol"))
	# Every hierarchical weight is a real ISO weight.
	for role: StringName in Style.hierarchy_roles():
		assert(Style.WEIGHTS.has(Style.hierarchy_weight(role)))


func test_nearest_standard_weight() -> void:
	assert(is_equal_approx(Style.nearest_weight(0.34), 0.35))
	assert(is_equal_approx(Style.nearest_weight(0.14), 0.13))
	assert(is_equal_approx(Style.nearest_weight(0.62), 0.70))
	# Off the top of the series, and off the bottom.
	assert(is_equal_approx(Style.nearest_weight(5.0), 2.00))
	assert(is_equal_approx(Style.nearest_weight(0.01), 0.13))
	# A tie resolves toward the lighter weight, so an ambiguous import never
	# thickens a drawing unexpectedly.
	assert(is_equal_approx(Style.nearest_weight(0.60), 0.50))


# --- layers -------------------------------------------------------------------------


func test_preset_layer_set_is_complete_and_ordered() -> void:
	var set := LayerSet.default_set()
	assert(set.size() == LayerSet.PRESETS.size())
	# Draw order is the numeric prefix, so the sheet border is on top.
	var names := set.names()
	assert(names[0] == LayerSet.SURVEY_PROPERTY)
	assert(names[names.size() - 1] == LayerSet.GUIDES)
	var previous := -1
	for name: StringName in names:
		var key: int = set.get_layer(name).sort_key()
		assert(key >= previous)
		previous = key


func test_tracing_aids_do_not_plot() -> void:
	var set := LayerSet.default_set()
	assert(not set.get_layer(LayerSet.UNDERLAY).plots)
	assert(not set.get_layer(LayerSet.GUIDES).plots)
	# Nor do they appear in the plotting order.
	assert(not set.plotting_names().has(LayerSet.UNDERLAY))
	assert(not set.plotting_names().has(LayerSet.GUIDES))
	assert(set.plotting_names().has(LayerSet.NEW_BED))


func test_bed_outline_outweighs_plant_symbols() -> void:
	var set := LayerSet.default_set()
	assert(set.get_layer(LayerSet.NEW_BED).plot_weight_mm
		> set.get_layer(LayerSet.NEW_PLANTING).plot_weight_mm)
	# And the sheet border outranks everything else on the sheet.
	for layer in set.layers():
		assert(set.get_layer(LayerSet.SHEET_BORDER).plot_weight_mm >= layer.plot_weight_mm)


func test_layer_states_show_the_right_layers() -> void:
	var set := LayerSet.default_set()
	assert(LayerSet.state_names().has("Planting plan"))
	assert(set.apply_state("Planting plan"))
	var visible := set.visible_names()
	assert(visible.has(LayerSet.NEW_PLANTING))
	assert(visible.has(LayerSet.NEW_BED))
	assert(not visible.has(LayerSet.IRRIGATION))
	# Switching to the irrigation sheet swaps them over.
	set.apply_state("Irrigation plan")
	visible = set.visible_names()
	assert(visible.has(LayerSet.IRRIGATION))
	assert(not visible.has(LayerSet.NEW_PLANTING))
	# An unknown state is refused rather than hiding everything.
	assert(not set.apply_state("Nonsense"))


func test_layer_set_copy_is_independent() -> void:
	var set := LayerSet.default_set()
	var duplicate := set.copy()
	duplicate.set_visible(LayerSet.NEW_BED, false)
	assert(set.get_layer(LayerSet.NEW_BED).visible)
	assert(not duplicate.get_layer(LayerSet.NEW_BED).visible)


func test_every_layer_has_a_purpose_and_a_weight() -> void:
	var set := LayerSet.default_set()
	for layer in set.layers():
		assert(not layer.purpose.is_empty(), "layer %s has no purpose" % layer.name)
		assert(layer.plot_weight_mm >= Style.HAIRLINE)


# --- undo ---------------------------------------------------------------------------


func test_undo_and_redo_round_trip() -> void:
	var stack := Undo.new()
	stack.push({"value": 1})
	assert(stack.can_undo())
	assert(not stack.can_redo())
	var restored := stack.undo({"value": 2})
	assert(restored["value"] == 1)
	assert(stack.can_redo())
	assert(stack.redo({"value": 1})["value"] == 2)


func test_undo_on_an_empty_stack_is_a_no_op() -> void:
	var stack := Undo.new()
	assert(stack.undo({}).is_empty())
	assert(stack.redo({}).is_empty())
	assert(not stack.can_undo())


func test_undo_stack_is_capped() -> void:
	var stack := Undo.new()
	stack.limit = 3
	for index in 10:
		stack.push({"value": index})
	assert(stack.depth() == 3)


func test_new_edits_clear_the_redo_branch() -> void:
	var stack := Undo.new()
	stack.push({"value": 1})
	stack.undo({"value": 2})
	assert(stack.can_redo())
	stack.push({"value": 3})
	assert(not stack.can_redo())