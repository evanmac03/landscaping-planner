extends Node
## Tests for sheets, plot scales, and the model/paper/point conversions that make
## a drawing true to scale.

const PlotScale := preload("res://scripts/draft/plot_scale.gd")


func test_sheet_sizes() -> void:
	assert(PlotScale.sheet_size_mm("A3") == Vector2(420.0, 297.0))
	assert(PlotScale.sheet_size_mm("A0") == Vector2(1189.0, 841.0))
	# 24 x 18 in in millimetres.
	assert(PlotScale.sheet_size_mm("ARCH C (24x18 in)") == Vector2(610.0, 457.0))
	assert(PlotScale.sheet_names().size() == PlotScale.SHEETS.size())


func test_printable_area_is_inset_by_the_margin() -> void:
	assert(PlotScale.printable_size_mm("A3") == Vector2(390.0, 267.0))
	assert(PlotScale.printable_size_mm("A3", 10.0) == Vector2(400.0, 277.0))


func test_coverage_follows_the_scale() -> void:
	# 390 mm of paper at 1:100 is 39 m of model.
	assert(PlotScale.coverage_m("A3", 100.0) == Vector2(39.0, 26.7))
	assert(PlotScale.coverage_m("A3", 200.0) == Vector2(78.0, 53.4))
	assert(PlotScale.coverage_m("A3", 50.0) == Vector2(19.5, 13.35))


func test_required_scale_for_a_known_design() -> void:
	# This project's own yard, 28 x 20 m, needs 1:74.9 on A3.
	var need := PlotScale.required_scale(Vector2(28.0, 20.0), "A3")
	assert(is_equal_approx(snappedf(need, 0.1), 74.9))


func test_suggested_scale_is_the_smallest_standard_that_fits() -> void:
	var choice := PlotScale.suggest(Vector2(28.0, 20.0), "A3")
	assert(is_equal_approx(choice["scale"], 100.0))
	assert(choice["label"] == "1:100")
	assert(choice["fits"])
	assert(choice["coverage_m"] == Vector2(39.0, 26.7))

	assert(is_equal_approx(PlotScale.suggest(Vector2(12.0, 9.0), "A3")["scale"], 50.0))
	assert(is_equal_approx(PlotScale.suggest(Vector2(45.0, 30.0), "A3")["scale"], 125.0))
	assert(is_equal_approx(PlotScale.suggest(Vector2(90.0, 60.0), "A3")["scale"], 250.0))


func test_suggested_imperial_scale_uses_imperial_ladder() -> void:
	var choice := PlotScale.suggest(Vector2(28.0, 20.0), "ARCH C (24x18 in)", 15.0, true)
	# Needs 1:48.3, so the next conventional imperial scale up is 3/16 in = 1 ft.
	assert(is_equal_approx(choice["scale"], 64.0))
	assert(choice["label"] == "3/16 in = 1 ft")
	assert(choice["fits"])


func test_imperial_scale_labels_and_ratios() -> void:
	assert(is_equal_approx(PlotScale.imperial_ratio("1/4 in = 1 ft"), 48.0))
	assert(is_equal_approx(PlotScale.imperial_ratio("1/8 in = 1 ft"), 96.0))
	assert(is_equal_approx(PlotScale.imperial_ratio("1 in = 20 ft"), 240.0))
	assert(PlotScale.imperial_label(96.0) == "1/8 in = 1 ft")
	assert(PlotScale.imperial_label(48.0) == "1/4 in = 1 ft")
	# A non-standard ratio is reported as a ratio.
	assert(PlotScale.imperial_label(77.0) == "1:77")
	assert(PlotScale.metric_label(100.0) == "1:100")


func test_standard_scale_recognition() -> void:
	assert(PlotScale.is_standard(100.0))
	assert(PlotScale.is_standard(96.0))
	assert(PlotScale.is_standard(48.0))
	assert(not PlotScale.is_standard(77.0))


func test_model_metres_per_paper_millimetre() -> void:
	assert(is_equal_approx(PlotScale.model_metres_per_paper_mm(100.0), 0.1))
	assert(is_equal_approx(PlotScale.model_metres_per_paper_mm(200.0), 0.2))


# --- points, for exact vector output ------------------------------------------------


func test_points_are_exact_by_definition() -> void:
	# 1 pt = 1/72 in, so 1 mm is 72/25.4 pt.
	assert(is_equal_approx(snappedf(PlotScale.points_from_mm(1.0), 0.0001), 2.8346))
	assert(is_equal_approx(snappedf(PlotScale.points_from_mm(100.0), 0.001), 283.465))
	assert(is_equal_approx(PlotScale.mm_from_points(PlotScale.points_from_mm(42.0)), 42.0))


func test_a3_page_box_in_points() -> void:
	var size := PlotScale.sheet_size_points("A3")
	# 420 x 297 mm in points.
	assert(is_equal_approx(snappedf(size.x, 0.001), 1190.551))
	assert(is_equal_approx(snappedf(size.y, 0.001), 841.890))


func test_a_known_model_length_becomes_the_right_paper_length() -> void:
	# The acceptance criterion: 10.000 m at 1:100 is 100 mm, which is 283.465 pt.
	assert(is_equal_approx(snappedf(PlotScale.model_length_points(10.0, 100.0), 0.001), 283.465))
	# At 1:200 the same length halves on paper.
	assert(is_equal_approx(snappedf(PlotScale.model_length_points(10.0, 200.0), 0.001), 141.732))


# --- scale bars ---------------------------------------------------------------------


func test_scale_bar_chooses_a_round_length_that_fits() -> void:
	# At 1:100 on A3 viewed 900 px tall, the plan runs at 33.71 px/m, so a 5 m bar
	# is the longest round length inside a 220 px budget.
	var bar := PlotScale.scale_bar_length(33.71, 220.0)
	assert(is_equal_approx(bar["label_value"], 5.0))
	assert(is_equal_approx(bar["metres"], 5.0))
	assert(bar["pixels"] <= 220.0)


func test_scale_bar_in_feet_uses_the_foot_length() -> void:
	var bar := PlotScale.scale_bar_length(33.71, 220.0, true)
	# 20 ft is 6.096 m, which fits; 50 ft does not.
	assert(is_equal_approx(bar["label_value"], 20.0))
	assert(is_equal_approx(bar["metres"], 6.096))
	assert(bar["pixels"] <= 220.0)