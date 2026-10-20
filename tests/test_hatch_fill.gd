extends Node
## Tests for the fill module: the four patterns, the paper-to-model spacing, clipping to a region
## including its holes, the stipple grid, and every way a fill refuses.
##
## Nothing here touches a document or a controller: `HatchFill` is a pure function from a region and
## four choices to linework, and that is the whole reason it can be tested this way.

const Fill := preload("res://scripts/draft/hatch_fill.gd")
const Geom := preload("res://scripts/draft/geom2d.gd")


func _square(size: float = 10.0) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(size, 0.0), Vector2(size, size), Vector2(0.0, size)])


## A square with a smaller square hole in the middle, both drawn anticlockwise: the outer ring sets
## the extent, the inner one is what must stay unfilled (REQ 4.6.4).
func _holed() -> Array:
	return [
		_square(10.0),
		PackedVector2Array([
			Vector2(4.0, 4.0), Vector2(6.0, 4.0), Vector2(6.0, 6.0), Vector2(4.0, 6.0)]),
	]


func _all_points(lines: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for line: PackedVector2Array in lines:
		for point: Vector2 in line:
			out.append(point)
	return out


# --- the table of choices -------------------------------------------------------------


func test_there_are_four_patterns_and_they_are_named() -> void:
	assert(Fill.PATTERNS.size() == 4)
	for pattern: StringName in Fill.PATTERNS:
		assert(Fill.is_pattern(pattern))
		assert(Fill.pattern_words(pattern) != "")
	assert(not Fill.is_pattern(&"plaid"))


func test_the_two_symbols_are_named() -> void:
	assert(Fill.SYMBOLS == [Fill.SYMBOL_DOT, Fill.SYMBOL_CROSS])
	assert(Fill.is_symbol(Fill.SYMBOL_DOT))
	assert(not Fill.is_symbol(&"triangle"))


# --- paper to model -------------------------------------------------------------------


func test_a_paper_spacing_becomes_a_model_one_by_the_plot_scale() -> void:
	# 2 mm on the sheet at 1:100 is 200 mm = 0.2 m of model.
	assert(absf(Fill.model_spacing_m(2.0, 100.0) - 0.2) < 1.0e-9)
	# The same 2 mm at 1:50 is half the ground.
	assert(absf(Fill.model_spacing_m(2.0, 50.0) - 0.1) < 1.0e-9)


func test_a_solid_fill_has_its_own_fixed_density() -> void:
	assert(absf(Fill.solid_spacing_m(100.0) - Fill.model_spacing_m(Fill.SOLID_MM, 100.0)) < 1.0e-9)


func test_the_words_read_the_way_a_plan_writes_them() -> void:
	assert(Fill.spacing_words(2.0) == "2 mm")
	assert(Fill.spacing_words(1.5) == "1.5 mm")
	assert(Fill.angle_words(45.0) == "45 deg")


# --- hatch ----------------------------------------------------------------------------


func test_a_line_hatch_stays_inside_the_region() -> void:
	var worked: Dictionary = Fill.fill([_square()], Fill.HATCH, 1.0, 0.0)
	assert(bool(worked["ok"]), String(worked["reason"]))
	var lines: Array = worked["lines"]
	assert(lines.size() > 5)
	for point: Vector2 in _all_points(lines):
		assert(point.x > -1.0e-6 and point.x < 10.0 + 1.0e-6)
		assert(point.y > -1.0e-6 and point.y < 10.0 + 1.0e-6)


func test_a_hatch_at_no_angle_runs_horizontally() -> void:
	var worked: Dictionary = Fill.fill([_square()], Fill.HATCH, 1.0, 0.0)
	for line: PackedVector2Array in worked["lines"]:
		assert(absf(line[0].y - line[1].y) < 1.0e-9, "an unrotated hatch is level")


func test_turning_the_angle_turns_the_hatch() -> void:
	var level: Array = Fill.fill([_square()], Fill.HATCH, 1.0, 0.0)["lines"]
	var turned: Array = Fill.fill([_square()], Fill.HATCH, 1.0, PI * 0.25)["lines"]
	# A forty-five degree hatch is not level anywhere.
	var sloped := false
	for line: PackedVector2Array in turned:
		if absf(line[0].y - line[1].y) > 1.0e-6:
			sloped = true
	assert(sloped, "the hatch follows the angle it was given")
	assert(level.size() > 0 and turned.size() > 0)


func test_a_finer_spacing_draws_more_lines() -> void:
	var coarse: Array = Fill.fill([_square()], Fill.HATCH, 2.0, 0.0)["lines"]
	var fine: Array = Fill.fill([_square()], Fill.HATCH, 0.5, 0.0)["lines"]
	assert(fine.size() > coarse.size())


func test_a_crosshatch_runs_both_ways() -> void:
	var worked: Dictionary = Fill.fill([_square()], Fill.CROSSHATCH, 1.0, 0.0)
	assert(bool(worked["ok"]))
	var level := false
	var upright := false
	for line: PackedVector2Array in worked["lines"]:
		if absf(line[0].y - line[1].y) < 1.0e-9:
			level = true
		if absf(line[0].x - line[1].x) < 1.0e-9:
			upright = true
	assert(level and upright, "a crosshatch has strokes both ways")


func test_a_solid_fill_is_two_dense_perpendicular_passes() -> void:
	var worked: Dictionary = Fill.fill([_square()], Fill.SOLID, 0.5, 0.0)
	assert(bool(worked["ok"]))
	var level := false
	var upright := false
	for line: PackedVector2Array in worked["lines"]:
		if absf(line[0].y - line[1].y) < 1.0e-9:
			level = true
		if absf(line[0].x - line[1].x) < 1.0e-9:
			upright = true
	assert(level and upright, "solid covers both ways")


# --- holes ----------------------------------------------------------------------------


func test_a_hatch_leaves_a_hole_unfilled() -> void:
	var worked: Dictionary = Fill.fill(_holed(), Fill.HATCH, 1.0, 0.0)
	assert(bool(worked["ok"]))
	for line: PackedVector2Array in worked["lines"]:
		var inside_hole_x := minf(line[0].x, line[1].x) > 4.0 \
			and maxf(line[0].x, line[1].x) < 6.0
		var in_hole_band := absf(line[0].y - 5.0) < 0.5
		assert(not (inside_hole_x and in_hole_band), "no hatch spans the hole")


func test_a_stipple_grid_leaves_a_hole_empty() -> void:
	var points: PackedVector2Array = Fill.grid_points(_holed(), 1.0)
	assert(points.size() > 0)
	for point: Vector2 in points:
		var inside := point.x > 4.0 and point.x < 6.0 and point.y > 4.0 and point.y < 6.0
		assert(not inside, "no symbol stands in the hole")


# --- stipple --------------------------------------------------------------------------


func test_a_stipple_places_symbols_inside_the_region() -> void:
	var square := _square()
	var points: PackedVector2Array = Fill.grid_points([square], 1.0)
	assert(points.size() > 10)
	for point: Vector2 in points:
		assert(Geom.point_in_polygon(point, square), "a symbol stands inside the region")
	var worked: Dictionary = Fill.fill([square], Fill.STIPPLE, 1.0, 0.0)
	assert(int(worked["marks"]) == points.size(), "one mark for every grid point")


func test_a_dot_is_one_stroke_and_a_cross_is_two() -> void:
	var dot: Array = Fill.symbol_marks(Vector2(1.0, 1.0), Fill.SYMBOL_DOT, 2.0)
	var cross: Array = Fill.symbol_marks(Vector2(1.0, 1.0), Fill.SYMBOL_CROSS, 2.0)
	assert(dot.size() == 1)
	assert(cross.size() == 2)


# --- refusing -------------------------------------------------------------------------


func test_a_region_that_is_not_closed_is_refused() -> void:
	var worked: Dictionary = Fill.fill([PackedVector2Array([Vector2(0, 0), Vector2(1, 1)])], Fill.HATCH, 1.0, 0.0)
	assert(not bool(worked["ok"]))
	assert(String(worked["reason"]).contains("closed region"))


func test_a_pattern_that_is_not_a_pattern_is_refused() -> void:
	var worked: Dictionary = Fill.fill([_square()], &"plaid", 1.0, 0.0)
	assert(not bool(worked["ok"]))
	assert(String(worked["reason"]).contains("pattern"))


func test_a_fill_with_no_spacing_is_refused() -> void:
	var worked: Dictionary = Fill.fill([_square()], Fill.HATCH, 0.0, 0.0)
	assert(not bool(worked["ok"]))
	assert(String(worked["reason"]).contains("spacing"))


func test_a_spacing_too_fine_for_the_region_is_refused_in_words() -> void:
	# A hundred-metre square at a hundredth of a metre: far past the cap.
	var worked: Dictionary = Fill.fill([_square(100.0)], Fill.HATCH, 0.01, 0.0)
	assert(not bool(worked["ok"]))
	assert(String(worked["reason"]).contains("finer"))


# --- the one line ---------------------------------------------------------------------


func test_describe_counts_the_lines_it_drew() -> void:
	var worked: Dictionary = Fill.fill([_square()], Fill.CROSSHATCH, 1.0, 0.0)
	var words: String = Fill.describe(worked)
	assert(words.begins_with("Crosshatch, "))
	assert(words.ends_with("lines"))


func test_describe_a_stipple_names_the_symbol() -> void:
	var worked: Dictionary = Fill.fill([_square()], Fill.STIPPLE, 1.0, 0.0, Fill.SYMBOL_CROSS)
	assert(Fill.describe(worked).contains("cross"))


func test_describe_a_refusal_says_the_reason() -> void:
	assert(Fill.describe(Fill.fill([], Fill.HATCH, 1.0, 0.0)) == "there is no closed region to fill")