extends Node
## Tests for the dimension layout: what a dimension is set out into, and the
## paper-versus-model conversion that keeps it legible at any plot scale.

const Dimension := preload("res://scripts/draft/dimension.gd")
const DimensionStyle := preload("res://scripts/draft/dimension_style.gd")
const Entity := preload("res://scripts/draft/draft_entity.gd")
const LineStyle := preload("res://scripts/draft/line_style.gd")
const UnitsScript := preload("res://scripts/draft/units.gd")


func _label(layout: Dictionary) -> Dictionary:
	return layout["labels"][0]


# --- linear -------------------------------------------------------------------------


func test_a_horizontal_dimension_measures_along_x() -> void:
	var entity = Entity.make_dimension(Vector2(0, 0), Vector2(10, 0), 1.0)
	var layout: Dictionary = Dimension.layout(entity, 100.0)
	# Two extension lines and the dimension line itself.
	assert(layout["lines"].size() == 3)
	assert(layout["marks"].size() == 2)
	assert(layout["labels"].size() == 1)
	assert(_label(layout)["text"] == "10.000 m")


func test_the_dimension_line_is_set_out_by_the_offset() -> void:
	var entity = Entity.make_dimension(Vector2(0, 0), Vector2(10, 0), 1.0)
	var layout: Dictionary = Dimension.layout(entity, 100.0)
	var dimension_line: PackedVector2Array = layout["lines"][2]
	assert(dimension_line[0].is_equal_approx(Vector2(0, 1)))
	assert(dimension_line[1].is_equal_approx(Vector2(10, 1)))
	# And the offset can go the other way.
	var below = Entity.make_dimension(Vector2(0, 0), Vector2(10, 0), -2.0)
	assert(Dimension.layout(below, 100.0)["lines"][2][0].is_equal_approx(Vector2(0, -2)))


## An extension line gaps off the measured point and overshoots the dimension
## line, which is what makes a dimension read as one object rather than four
## strokes that nearly touch.
func test_extension_lines_gap_and_overshoot() -> void:
	var entity = Entity.make_dimension(Vector2(0, 0), Vector2(10, 0), 1.0)
	var layout: Dictionary = Dimension.layout(entity, 100.0)
	var first: PackedVector2Array = layout["lines"][0]
	# 1.5 mm of paper at 1:100 is 0.15 m of model.
	assert(first[0].is_equal_approx(Vector2(0, 0.15)))
	assert(first[1].is_equal_approx(Vector2(0, 1.15)))


func test_a_vertical_dimension_measures_along_y() -> void:
	var entity = Entity.make_dimension(Vector2(0, 0), Vector2(0, 6), 2.0)
	var layout: Dictionary = Dimension.layout(entity, 100.0)
	var dimension_line: PackedVector2Array = layout["lines"][2]
	assert(dimension_line[0].is_equal_approx(Vector2(2, 0)))
	assert(dimension_line[1].is_equal_approx(Vector2(2, 6)))
	assert(_label(layout)["text"] == "6.000 m")


func test_an_aligned_dimension_measures_the_true_distance() -> void:
	var entity = Entity.make_dimension(Vector2(0, 0), Vector2(3, 4), 1.0, Entity.DimensionKind.ALIGNED)
	var layout: Dictionary = Dimension.layout(entity, 100.0)
	assert(_label(layout)["text"] == "5.000 m")
	# The dimension line runs parallel to the measured points.
	var line: PackedVector2Array = layout["lines"][2]
	var along := line[1] - line[0]
	assert(absf(along.cross(Vector2(3, 4))) < 0.001)
	assert(absf(along.length() - 5.0) < 0.001)


## ANGULAR needs a vertex and two arms, which two points cannot express. It is
## set out as an aligned dimension rather than dropped, so the measurement is
## still on the sheet and visibly a straight one.
func test_an_angular_dimension_falls_back_to_aligned() -> void:
	var entity = Entity.make_dimension(Vector2(0, 0), Vector2(4, 0), 1.0, Entity.DimensionKind.ANGULAR)
	var layout: Dictionary = Dimension.layout(entity, 100.0)
	assert(layout["lines"].size() == 3)
	assert(_label(layout)["text"] == "4.000 m")


func test_a_degenerate_dimension_draws_nothing() -> void:
	var entity = Entity.make_dimension(Vector2(2, 2), Vector2(2, 2), 1.0)
	var layout: Dictionary = Dimension.layout(entity, 100.0)
	assert(layout["lines"].is_empty())
	assert(layout["marks"].is_empty())
	assert(layout["labels"].is_empty())


# --- radius -------------------------------------------------------------------------


func test_a_radius_dimension_is_a_leader_with_the_value() -> void:
	var entity = Entity.make_dimension(Vector2(0, 0), Vector2(5, 0), 0.0, Entity.DimensionKind.RADIUS)
	var layout: Dictionary = Dimension.layout(entity, 100.0)
	assert(layout["lines"].size() == 1)
	assert(layout["marks"].size() == 1)
	assert(layout["marks"][0]["tip"].is_equal_approx(Vector2(5, 0)))
	assert(layout["marks"][0]["direction"].is_equal_approx(Vector2(1, 0)))
	assert(_label(layout)["text"] == "R5.000 m")


# --- paper sizing -------------------------------------------------------------------


## Sizes are paper properties: an arrowhead is the same length on the sheet at
## any scale, which means twice the model length at twice the plot scale.
func test_dimension_sizes_are_paper_properties() -> void:
	var entity = Entity.make_dimension(Vector2(0, 0), Vector2(10, 0), 1.0)
	var fine: Dictionary = Dimension.layout(entity, 100.0)
	var coarse: Dictionary = Dimension.layout(entity, 50.0)
	assert(is_equal_approx(fine["marks"][0]["size"], 0.25))
	assert(is_equal_approx(coarse["marks"][0]["size"], 0.125))
	assert(is_equal_approx(
		_label(fine)["height"], LineStyle.DEFAULT_TEXT_HEIGHT * 100.0 / 1000.0
	))


func test_the_text_sits_on_the_side_it_was_measured_from() -> void:
	var entity = Entity.make_dimension(Vector2(0, 0), Vector2(10, 0), 1.0)
	var layout: Dictionary = Dimension.layout(entity, 100.0)
	var text: Dictionary = _label(layout)
	# Above the dimension line at y = 1, on the side of the measured points at 0.
	assert(text["position"].y < 1.0)
	assert(text["position"].y > 0.0)
	assert(is_equal_approx(text["position"].x, 5.0))


## A dimension running right to left still reads left to right, because a label
## you have to tilt your head for is a label nobody reads.
func test_the_text_stays_upright_on_a_reversed_dimension() -> void:
	var entity = Entity.make_dimension(Vector2(10, 0), Vector2(0, 0), 1.0)
	var layout: Dictionary = Dimension.layout(entity, 100.0)
	var angle: float = _label(layout)["angle"]
	assert(absf(sin(angle)) < 1e-6)
	assert(cos(angle) > 0.0)


func test_an_arrowhead_is_a_triangle_pointing_outward() -> void:
	var triangle := Dimension.arrow_triangle(Vector2(0, 0), Vector2(1, 0), 1.0)
	assert(triangle.size() == 3)
	assert(triangle[0].is_equal_approx(Vector2(0, 0)))
	var half_width: float = DimensionStyle.DEFAULT_WIDTH_RATIO
	assert(absf(triangle[1].length() - sqrt(1.0 + half_width * half_width)) < 0.001)
	assert(absf(triangle[1].x - (-1.0)) < 0.001)


# --- units --------------------------------------------------------------------------


func test_the_measurement_uses_the_document_units() -> void:
	var entity = Entity.make_dimension(Vector2(0, 0), Vector2(10, 0), 1.0)
	var units = UnitsScript.new()
	units.system = UnitsScript.System.IMPERIAL
	units.length_style = UnitsScript.LengthStyle.ARCHITECTURAL
	var layout: Dictionary = Dimension.layout(entity, 100.0, units)
	var text: String = _label(layout)["text"]
	# 10 m is 32 feet 9 11/16 inches: a surveyor's reading, not a decimal.
	assert(text == "32'-9 11/16\"")
	assert(layout["lines"].size() == 3)


func test_a_measurement_is_written_to_a_fixed_precision() -> void:
	# Two dimensions of the same drawing must not differ in precision.
	var whole = Entity.make_dimension(Vector2(0, 0), Vector2(10, 0), 1.0)
	var part = Entity.make_dimension(Vector2(0, 0), Vector2(10.5, 0), 1.0)
	assert(_label(Dimension.layout(whole, 100.0))["text"] == "10.000 m")
	assert(_label(Dimension.layout(part, 100.0))["text"] == "10.500 m")


## With a document's units in hand the measurement is written in those units,
## which is the path a plotted sheet and the plan both take.
func test_the_measurement_follows_the_document_units() -> void:
	var entity = Entity.make_dimension(Vector2(0, 0), Vector2(10, 0), 1.0)
	var units = UnitsScript.new()
	assert(_label(Dimension.layout(entity, 100.0, units))["text"] == units.format_length(10.0))
	# And an authored height is a constant unless a caller overrides it.
	assert(is_equal_approx(
		_label(Dimension.layout(entity, 100.0, units))["height"],
		LineStyle.DEFAULT_TEXT_HEIGHT * 100.0 / 1000.0
	))