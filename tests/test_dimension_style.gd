extends Node
## Tests for dimension styles: the mark at each end, the sizes, and how the
## measurement is written - and for the rule that decides which style applies,
## which is the document's standard unless a single dimension overrides it.

const Dimension := preload("res://scripts/draft/dimension.gd")
const DimensionStyle := preload("res://scripts/draft/dimension_style.gd")
const Entity := preload("res://scripts/draft/draft_entity.gd")
const Document := preload("res://scripts/draft/draft_document.gd")
const UnitsScript := preload("res://scripts/draft/units.gd")
const LayerSet := preload("res://scripts/draft/layer_set.gd")
const Exporter := preload("res://scripts/draft/sheet_exporter.gd")


## A 10 m dimension set out 1 m north of the wall it measures.
func _dimension():
	return Entity.make_dimension(Vector2(0, 0), Vector2(10, 0), 1.0)


func _text(layout: Dictionary) -> String:
	return String(layout["labels"][0]["text"])


# --- the mark at each end -----------------------------------------------------------


func test_the_default_style_is_the_architectural_one() -> void:
	var entity = _dimension()
	var plain: Dictionary = Dimension.layout(entity, 100.0)
	var named: Dictionary = Dimension.layout(entity, 100.0, null, DimensionStyle.architectural())
	assert(plain["lines"].size() == named["lines"].size())
	assert(plain["marks"][0]["kind"] == &"arrow")


## A tick is linework rather than a solid, so it joins the lines: a view that
## cannot fill anything still draws an engineering dimension correctly.
func test_a_tick_style_draws_crosswise_strokes_instead_of_arrows() -> void:
	var layout: Dictionary = Dimension.layout(
		_dimension(), 100.0, null, DimensionStyle.engineering()
	)
	# Two extension lines, the dimension line, and a tick at each end.
	assert(layout["lines"].size() == 5)
	assert(layout["marks"].is_empty())
	var first: PackedVector2Array = layout["lines"][3]
	# 2.5 mm of paper at 1:100 is a quarter of a metre of model.
	assert(absf(first[0].distance_to(first[1]) - 0.25) < 0.001)
	assert(first[0].x < first[1].x)


## Both ticks lean off the dimension line's own direction rather than off each
## arrow, so they lean the same way instead of mirroring. Mirroring is the kind of
## mistake that looks deliberate.
func test_both_ticks_lean_the_same_way() -> void:
	var layout: Dictionary = Dimension.layout(
		_dimension(), 100.0, null, DimensionStyle.engineering()
	)
	var first: PackedVector2Array = layout["lines"][3]
	var second: PackedVector2Array = layout["lines"][4]
	assert(
		(first[1] - first[0]).normalized().is_equal_approx(
			(second[1] - second[0]).normalized()
		)
	)


func test_a_dot_style_marks_the_ends_with_discs() -> void:
	var style := DimensionStyle.architectural()
	style.mark = DimensionStyle.Mark.DOT
	var layout: Dictionary = Dimension.layout(_dimension(), 100.0, null, style)
	assert(layout["marks"].size() == 2)
	assert(layout["marks"][0]["kind"] == &"dot")
	assert(Vector2(layout["marks"][0]["at"]).is_equal_approx(Vector2(0, 1)))
	assert(Vector2(layout["marks"][1]["at"]).is_equal_approx(Vector2(10, 1)))
	assert(is_equal_approx(float(layout["marks"][0]["size"]), 0.25))


func test_a_style_with_no_marks_draws_only_the_lines() -> void:
	var layout: Dictionary = Dimension.layout(_dimension(), 100.0, null, DimensionStyle.minimal())
	assert(layout["marks"].is_empty())
	# No marks and no extension lines: the measured line alone.
	assert(layout["lines"].size() == 1)
	assert(_text(layout) == "10.00 m")


func test_extension_lines_can_be_switched_off_on_their_own() -> void:
	var style := DimensionStyle.architectural()
	style.extension_lines = false
	var layout: Dictionary = Dimension.layout(_dimension(), 100.0, null, style)
	assert(layout["lines"].size() == 1)
	assert(layout["marks"].size() == 2)


func test_the_mark_size_comes_from_the_style() -> void:
	var style := DimensionStyle.architectural()
	style.mark_size_mm = 4.0
	assert(is_equal_approx(
		float(Dimension.layout(_dimension(), 100.0, null, style)["marks"][0]["size"]), 0.4
	))


# --- the text -----------------------------------------------------------------------


func test_the_text_height_comes_from_the_style() -> void:
	var style := DimensionStyle.architectural()
	style.text_height_mm = 3.5
	assert(is_equal_approx(
		float(Dimension.layout(_dimension(), 100.0, null, style)["labels"][0]["height"]),
		3.5 * 100.0 / 1000.0
	))


## The dimension line sits at y = 1 with the measured points at y = 0, so there
## are two sides and the style chooses which one the value goes on.
func test_the_text_can_sit_on_either_side_of_the_line() -> void:
	var above: Dictionary = Dimension.layout(_dimension(), 100.0)
	var style := DimensionStyle.architectural()
	style.text_above = false
	var below: Dictionary = Dimension.layout(_dimension(), 100.0, null, style)
	assert(Vector2(above["labels"][0]["position"]).y < 1.0)
	assert(Vector2(below["labels"][0]["position"]).y > 1.0)


func test_a_style_can_name_the_precision() -> void:
	var style := DimensionStyle.architectural()
	style.text_decimals = 1
	assert(_text(Dimension.layout(_dimension(), 100.0, null, style)) == "10.0 m")
	# A named count is the style's, so it does not move with the scale.
	assert(_text(Dimension.layout(_dimension(), 2000.0, null, style)) == "10.0 m")
	style.text_decimals = 3
	assert(_text(Dimension.layout(_dimension(), 100.0, null, style)) == "10.000 m")


## With no count of its own a style takes one from the plot scale, because a
## dimension can only be read as finely as it can be drawn. Switching that off
## hands the precision back to the document's units instead.
func test_an_unnamed_precision_comes_from_the_scale_until_it_is_switched_off() -> void:
	var style := DimensionStyle.architectural()
	assert(style.decimals_at(100.0) == 2)
	assert(_text(Dimension.layout(_dimension(), 100.0, null, style)) == "10.00 m")
	style.scale_aware = false
	assert(style.decimals_at(100.0) == -1)
	var units = UnitsScript.new()
	assert(_text(Dimension.layout(_dimension(), 100.0, units, style)) == units.format_length(10.0))


func test_the_description_says_where_the_precision_comes_from() -> void:
	assert(DimensionStyle.architectural().describe().contains("precision by scale"))
	var named := DimensionStyle.architectural()
	named.text_decimals = 2
	assert(named.precision_description() == "2 decimal places")
	named.scale_aware = false
	named.text_decimals = -1
	assert(named.precision_description() == "precision by units")


func test_the_named_precision_follows_the_scale() -> void:
	assert(DimensionStyle.decimals_for_scale(20.0) == 3)
	assert(DimensionStyle.decimals_for_scale(100.0) == 2)
	assert(DimensionStyle.decimals_for_scale(500.0) == 1)
	assert(DimensionStyle.decimals_for_scale(2000.0) == 0)
	var scaled := DimensionStyle.architectural().with_scale(100.0)
	assert(scaled.text_decimals == 2)
	assert(_text(Dimension.layout(_dimension(), 100.0, null, scaled)) == "10.00 m")


## An imperial document writes feet and inches, where the fraction is the
## precision, so a decimal count would mean something else and is ignored.
func test_an_imperial_document_ignores_the_decimal_count() -> void:
	var style := DimensionStyle.architectural()
	style.text_decimals = 3
	var units = UnitsScript.new()
	units.system = UnitsScript.System.IMPERIAL
	units.length_style = UnitsScript.LengthStyle.ARCHITECTURAL
	var text := _text(Dimension.layout(_dimension(), 100.0, units, style))
	assert(text == units.format_length(10.0))
	assert(text.contains("'"))


# --- persistence --------------------------------------------------------------------


func test_a_style_round_trips_through_persistence() -> void:
	var style := DimensionStyle.engineering()
	style.mark_size_mm = 3.25
	style.text_above = false
	style.text_decimals = 1
	style.scale_aware = false
	style.extension_lines = false
	var back := DimensionStyle.from_dict(style.to_dict())
	assert(back.mark == DimensionStyle.Mark.TICK)
	assert(is_equal_approx(back.mark_size_mm, 3.25))
	assert(not back.text_above)
	assert(back.text_decimals == 1)
	assert(not back.scale_aware)
	assert(not back.extension_lines)


## A file written by an older version, or hand-edited, has to load with usable
## values rather than refuse.
func test_reading_a_broken_style_gives_a_usable_one() -> void:
	var nonsense := DimensionStyle.from_dict({"mark": 99})
	assert(nonsense.mark == DimensionStyle.Mark.ARROW)
	var empty := DimensionStyle.from_dict({})
	assert(empty.mark == DimensionStyle.Mark.ARROW)
	assert(empty.extension_lines)
	assert(empty.text_height_mm > 0.0)
	# A style written before scale-awareness existed gets the shipped behaviour.
	assert(empty.scale_aware)


func test_a_document_keeps_its_standard_through_a_snapshot() -> void:
	var document = Document.new()
	document.dimension_style = DimensionStyle.engineering()
	var state := document.snapshot()
	document.dimension_style = DimensionStyle.architectural()
	document.restore(state)
	assert(document.dimension_style.mark == DimensionStyle.Mark.TICK)


func test_a_document_keeps_its_standard_through_a_saved_file() -> void:
	var document = Document.new()
	document.dimension_style = DimensionStyle.engineering()
	document.dimension_style.mark_size_mm = 4.5
	var back = Document.from_dict(document.to_dict())
	assert(back.dimension_style.mark == DimensionStyle.Mark.TICK)
	assert(is_equal_approx(back.dimension_style.mark_size_mm, 4.5))


func test_a_file_from_before_styles_existed_still_loads() -> void:
	var document = Document.new()
	document.add(_dimension(), LayerSet.DIMENSION)
	var data := document.to_dict()
	data.erase("dimension_style")
	var back = Document.from_dict(data)
	assert(back.dimension_style.mark == DimensionStyle.Mark.ARROW)
	assert(back.count() == 1)


# --- which style applies ------------------------------------------------------------


func test_the_document_standard_applies_to_its_dimensions() -> void:
	var document = Document.new()
	assert(document.dimension_style.mark == DimensionStyle.Mark.ARROW)
	document.dimension_style = DimensionStyle.engineering()
	assert(Dimension.style_for(_dimension(), document).mark == DimensionStyle.Mark.TICK)


func test_an_entity_override_beats_the_document_standard() -> void:
	var document = Document.new()
	document.dimension_style = DimensionStyle.engineering()
	var entity = _dimension()
	entity.meta["dimension_style"] = DimensionStyle.minimal().to_dict()
	var resolved := Dimension.style_for(entity, document)
	assert(resolved.mark == DimensionStyle.Mark.NONE)
	assert(not resolved.extension_lines)


func test_an_entity_with_no_document_gets_the_shipped_standard() -> void:
	assert(Dimension.style_for(_dimension()).mark == DimensionStyle.Mark.ARROW)


# --- reaching the sheet -------------------------------------------------------------


## The style is not a plan-only setting: a tick standard plots ticks. This reads
## the actual bytes, because a style that only changed the screen would be a
## setting nobody could trust.
func test_a_tick_style_plots_ticks_rather_than_arrowheads() -> void:
	var document = Document.new()
	document.dimension_style = DimensionStyle.engineering()
	var entity = _dimension()
	document.add(entity, LayerSet.DIMENSION)
	var plan := Exporter.plan_sheet(document, {"sheet": "A3", "scale": 100.0})
	var text := Exporter.export_pdf(document, {"sheet": "A3", "scale": 100.0}) \
		.get_string_from_utf8()
	var ticks: Dictionary = Dimension.layout(
		entity, 100.0, null, DimensionStyle.engineering()
	)
	var tick: PackedVector2Array = ticks["lines"][3]
	for point in tick:
		assert(_has_point(text, Exporter.model_to_paper(point, plan)))
	# And no filled arrowhead anywhere. Its tip sits on the dimension line's own
	# end, so that point is there either way; the two base corners sit inside the
	# line and only an arrowhead has them.
	var arrows: Dictionary = Dimension.layout(entity, 100.0)
	var triangle := Dimension.arrow_triangle(
		arrows["marks"][0]["tip"], arrows["marks"][0]["direction"], arrows["marks"][0]["size"]
	)
	for corner in [triangle[1], triangle[2]]:
		assert(not _has_point(text, Exporter.model_to_paper(corner, plan)))


func _has_point(text: String, target: Vector2) -> bool:
	var numbers := [String.num(target.x, 4), String.num(target.y, 4)]
	for line in text.split("\n"):
		var parts := line.strip_edges().split(" ", false)
		if parts.size() == 3 and parts[2] in ["m", "l"] \
				and parts[0] == numbers[0] and parts[1] == numbers[1]:
			return true
	return false