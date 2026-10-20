extends Node
## Tests for the hand-drawn half of the painted plan: the wobble, the ink pass, and the
## compositor's promise that the paper does not care how big the picture is.
##
## Three of the acceptance criteria in §14 are these tests by name: AC-V1 (a wobbled
## stroke stays within the limit), AC-V2 (the same seed wobbles the same way), AC-V3
## (the painted path and the working path draw the same geometry before the wobble), and
## AC-V6 (grain and hatch are paper lengths, not pixel counts).

const Entity := preload("res://scripts/draft/draft_entity.gd")
const Document := preload("res://scripts/draft/draft_document.gd")
const LayerSet := preload("res://scripts/draft/layer_set.gd")
const RenderScript := preload("res://scripts/draft/draft_render.gd")
const SketchStrokeScript := preload("res://scripts/vis/sketch_stroke.gd")
const SketchStyleScript := preload("res://scripts/vis/sketch_style.gd")
const InkPainterScript := preload("res://scripts/vis/ink_painter.gd")
const CompositorScript := preload("res://scripts/vis/sketch_compositor.gd")
const WashPainterScript := preload("res://scripts/vis/wash_painter.gd")

const PROP_TREE := "res://scenes/props/tree.tscn"
const PROP_BED := "res://scenes/props/flower_bed.tscn"


func _line(length: float = 6.0) -> PackedVector2Array:
	return PackedVector2Array([Vector2.ZERO, Vector2(length, 0.0)])


func _document() -> Variant:
	return Document.new()


func _prop(scene_path: String, at: Vector2) -> Node3D:
	var node: Node3D = (load(scene_path) as PackedScene).instantiate()
	node.position = Vector3(at.x, 0.0, at.y)
	add_child(node)
	return node


# --- the wobble (AC-V1, AC-V2) --------------------------------------------------------


func test_a_wobbled_line_stays_within_its_limit() -> void:
	# AC-V1. A pencil mark that wanders further than its own width is measuring
	# something else, so this is the requirement that keeps the drawing honest - and it
	# is checked at every sample of every stroke, not on average.
	var limit_m: float = SketchStrokeScript.WOBBLE_LIMIT_MM * 0.001 * 100.0
	var shapes: Array[PackedVector2Array] = [
		_line(6.0),
		PackedVector2Array([Vector2.ZERO, Vector2(3.0, 3.0), Vector2(6.0, 0.0)]),
		PackedVector2Array([Vector2(0.5, 0.0), Vector2(0.5, 9.0)]),
	]
	for shape: PackedVector2Array in shapes:
		for seed_value in [1, 7, 4242]:
			var wobbled: PackedVector2Array = SketchStrokeScript.wobble(shape, seed_value, 100.0)
			var worst: float = SketchStrokeScript.max_deviation(shape, wobbled)
			assert(worst <= limit_m, "seed %d strayed %.4f m, limit %.4f" % [seed_value, worst, limit_m])
			# And it did move: a wobble that stayed exactly on the line would pass the
			# test above while drawing a plotter line.
			assert(worst > 0.0)


func test_the_same_seed_wobbles_the_same_way_and_a_different_one_does_not() -> void:
	# AC-V2, and REQ-V3.1: the drawing must be stable between frames and between
	# renders, which means the wobble cannot depend on the frame, the camera or TIME.
	var first: PackedVector2Array = SketchStrokeScript.wobble(_line(), 11, 100.0)
	var again: PackedVector2Array = SketchStrokeScript.wobble(_line(), 11, 100.0)
	assert(first == again)
	var other: PackedVector2Array = SketchStrokeScript.wobble(_line(), 12, 100.0)
	assert(other != first)
	assert(other.size() == first.size())


func test_the_wobble_is_a_paper_length_not_a_model_length() -> void:
	# The same bed drawn at 1:50 and at 1:200 must wander the same distance on the
	# paper. In model metres that means the wander scales with the plot scale, so the
	# deviation at 1:200 is twice the deviation at 1:100.
	var shape := _line(20.0)
	var at_100: float = SketchStrokeScript.max_deviation(
		shape, SketchStrokeScript.wobble(shape, 3, 100.0)
	)
	var at_200: float = SketchStrokeScript.max_deviation(
		shape, SketchStrokeScript.wobble(shape, 3, 200.0)
	)
	# Proportional to within the sampling: the step is also a paper length, so at 1:200
	# the samples land further apart in model metres and the worst point found is a
	# slightly different point on the same wave. A test demanding exact equality would
	# be asserting the sampler rather than the law.
	assert(absf(at_200 / at_100 - 2.0) < 0.05, "%.5f vs %.5f" % [at_100, at_200])


func test_a_wobble_does_not_move_the_ends_of_a_stroke() -> void:
	# Where two entities meet, the joint has to stay a joint: wobbling the endpoints
	# away from each other would open a gap at every corner of a closed shape.
	var shape := _line(4.0)
	var wobbled: PackedVector2Array = SketchStrokeScript.wobble(shape, 5, 100.0)
	# The samples are taken along the stroke rather than at its ends, so the ends are
	# *near* where they were rather than exactly there.
	var limit_m: float = SketchStrokeScript.WOBBLE_LIMIT_MM * 0.001 * 100.0
	assert(wobbled[0].distance_to(shape[0]) <= 2.0 * limit_m)
	assert(wobbled[wobbled.size() - 1].distance_to(shape[1]) <= 2.0 * limit_m)


func test_a_stroke_of_no_length_is_left_alone() -> void:
	var single := PackedVector2Array([Vector2(1.0, 1.0)])
	assert(SketchStrokeScript.wobble(single, 1, 100.0) == single)
	assert(SketchStrokeScript.wobble(PackedVector2Array(), 1, 100.0).is_empty())
	# A zero-length segment inside a stroke is skipped rather than dividing by zero.
	var degenerate := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2(2.0, 0.0)])
	var wobbled: PackedVector2Array = SketchStrokeScript.wobble(degenerate, 1, 100.0)
	assert(not wobbled.is_empty())


func test_two_sides_of_one_shape_do_not_wobble_in_step() -> void:
	# One seed per stroke, stepped: a rectangle whose opposite sides wandered
	# identically would not look drawn, it would look skewed.
	var square := PackedVector2Array([
		Vector2.ZERO, Vector2(4.0, 0.0), Vector2(4.0, 4.0), Vector2(0.0, 4.0),
	])
	var strokes: Array[PackedVector2Array] = [square]
	var wobbled: Array[PackedVector2Array] = SketchStrokeScript.wobble_strokes(strokes, 9, 100.0)
	assert(wobbled.size() == 1)
	assert(wobbled[0] != square)
	# Two different seeds give two different strokes, which is what stepping the seed
	# per stroke buys.
	var a: PackedVector2Array = SketchStrokeScript.wobble(square, 9, 100.0)
	var b: PackedVector2Array = SketchStrokeScript.wobble(
		square, 9 + SketchStrokeScript.SEED_STRIDE, 100.0
	)
	assert(a != b)


# --- the ink pass (AC-V3) -------------------------------------------------------------


func test_the_painted_path_draws_the_same_geometry_as_the_working_path() -> void:
	# AC-V3 and REQ-V2.3: the two paths are projections of one document, so before the
	# wobble the stroke lists must be equal entity for entity. This is the test that
	# makes "the painted plan is the same drawing, coloured" true rather than hoped for.
	var document = _document()
	document.add(Entity.make_line(Vector2.ZERO, Vector2(5.0, 0.0)), LayerSet.NEW_HARDSCAPE)
	document.add(Entity.make_circle(Vector2(8.0, 0.0), 2.0), LayerSet.NEW_BED)
	document.add(
		Entity.make_polyline(PackedVector2Array([
			Vector2(0.0, 3.0), Vector2(4.0, 3.0), Vector2(4.0, 6.0),
		]), true),
		LayerSet.NEW_TURF
	)
	document.add(
		Entity.make_dimension(Vector2(0.0, -2.0), Vector2(5.0, -2.0), 1.0, 0),
		LayerSet.DIMENSION
	)
	var painter := InkPainterScript.new(document, 100.0, SketchStyleScript.new())
	var painted: Array[Dictionary] = painter.parts(false)
	var expected: int = document.plotting_entities().size()
	assert(painted.size() == expected, "one entry per plotted entity")
	for index in expected:
		var entity = document.plotting_entities()[index]
		var layer = document.layers.get_layer(entity.layer)
		var working: Dictionary = RenderScript.layout(
			entity, layer, 100.0, document.units, null
		)
		var painted_strokes: Array = painted[index]["strokes"]
		var working_strokes: Array = working["lines"]
		assert(
			painted_strokes.size() == working_strokes.size(),
			"%s: %d painted strokes against %d working" % [
				entity.layer, painted_strokes.size(), working_strokes.size(),
			]
		)
		for stroke_index in working_strokes.size():
			assert(painted_strokes[stroke_index] == working_strokes[stroke_index])
		# The marks and labels come across too: a dimension that lost its arrowheads in
		# the painted plan would be a dimension with no reading.
		assert(painted[index]["marks"].size() == working["marks"].size())
		assert(painted[index]["labels"].size() == working["labels"].size())
	painter.free()


func test_the_ink_is_wobbled_by_the_look_and_left_alone_without_one() -> void:
	var document = _document()
	document.add(Entity.make_line(Vector2.ZERO, Vector2(5.0, 0.0)), LayerSet.NEW_HARDSCAPE)
	var look := SketchStyleScript.new()
	var painter := InkPainterScript.new(document, 100.0, look)
	var straight: PackedVector2Array = painter.parts(false)[0]["strokes"][0]
	var drawn: PackedVector2Array = painter.parts(true)[0]["strokes"][0]
	assert(straight.size() == 2, "the unwobbled line is two points")
	assert(drawn.size() > straight.size(), "the drawn line is sampled along its length")
	var limit_m: float = SketchStrokeScript.WOBBLE_LIMIT_MM * 0.001 * 100.0
	assert(SketchStrokeScript.max_deviation(straight, drawn) <= limit_m)
	# A look with no wobble gives a plotted line, which is a legitimate look rather
	# than a degenerate case.
	look.wobble_mm = 0.0
	var plotted: PackedVector2Array = painter.parts(true)[0]["strokes"][0]
	# A plotted line, to within arithmetic: the stroke is still sampled along its length,
	# so its points are interpolated rather than copied, and this build is
	# single-precision - a raw `==` after an interpolation is a failure that means
	# nothing. A thousandth of the wobble limit is the honest bar: this is a line, not a
	# faint wobble.
	assert(SketchStrokeScript.max_deviation(straight, plotted) <= limit_m * 1.0e-3)
	painter.free()


func test_a_plant_symbol_is_inked_round_the_same_ring_it_is_washed_in() -> void:
	# The wash and the ink read one shape. If they disagreed, the painted plan would
	# show a rim of colour outside the line - which is how the round-bed bug looked.
	var tree := _prop(PROP_TREE, Vector2(2.0, 1.0))
	var bed := _prop(PROP_BED, Vector2(7.0, 1.0))
	var painter := InkPainterScript.new(null, 100.0, SketchStyleScript.new(), 6.0,
		[tree, bed] as Array[Node3D])
	var symbols: Array[Dictionary] = painter.symbol_parts(false)
	assert(symbols.size() == 2, "a symbol for every planted prop with a colour")
	for symbol: Dictionary in symbols:
		var stroke: PackedVector2Array = symbol["strokes"][0]
		# Closed: the ring's first point is repeated at the end, which is what makes it
		# an outline rather than a path.
		assert(stroke[0].is_equal_approx(stroke[stroke.size() - 1]))
		assert(stroke.size() >= 5)
		var colour: Color = (symbol["style"] as LineStyle).plot_colour
		assert(colour.v < 1.0, "a symbol is inked in a dark version of its own colour")
	painter.free()
	tree.free()
	bed.free()


func test_an_unknown_prop_is_inked_in_nothing_rather_than_guessed() -> void:
	var unknown := Node3D.new()
	add_child(unknown)
	var painter := InkPainterScript.new(null, 100.0, SketchStyleScript.new(), 6.0,
		[unknown] as Array[Node3D])
	assert(painter.symbol_parts().is_empty())
	painter.free()
	unknown.free()


func test_the_ink_width_is_the_layer_weight_on_paper() -> void:
	# The weight is authored in paper millimetres, so a heavier layer draws a heavier
	# line - and the same weight on the paper whatever the plot scale.
	var document = _document()
	document.add(Entity.make_line(Vector2.ZERO, Vector2(5.0, 0.0)), LayerSet.NEW_HARDSCAPE)
	var painter := InkPainterScript.new(document, 100.0, SketchStyleScript.new())
	var style: LineStyle = painter.parts(false)[0]["style"]
	var layer = document.layers.get_layer(LayerSet.NEW_HARDSCAPE)
	# The weight is the layer's own, not a number invented by the painter: the painted
	# plan keeps the drawing's hierarchy, because the hierarchy is the drawing.
	assert(is_equal_approx(style.plot_weight_mm, layer.plot_weight_mm))
	assert(is_equal_approx(
		LineStyle.model_width_m(style.plot_weight_mm, 100.0),
		layer.plot_weight_mm * 0.1
	), "0.50 mm at 1:100 is 50 mm of ground")
	painter.free()


# --- the compositor (AC-V6) -----------------------------------------------------------


func test_the_compositor_takes_no_pixel_count() -> void:
	# AC-V6, made structural rather than remembered. The uniforms are a function of the
	# look and the sheet, and there is no argument a bake size could even arrive
	# through - so a 4K bake cannot have finer grain than a 1080p one, because nothing
	# in the composite knows which it is.
	var look := SketchStyleScript.new()
	var values: Dictionary = CompositorScript.uniform_values(look, Vector2(420.0, 297.0))
	assert(values.size() > 0)
	for name: String in values:
		assert(not name.contains("texel"), "%s is a pixel count" % name)
		assert(not name.contains("pixel"), "%s is a pixel count" % name)
	# Every value is a length or a share, and the two lengths that are paper scales are
	# the millimetre repeats rather than counts of repeats.
	assert(is_equal_approx(values["grain_mm"], look.grain_mm))
	assert(is_equal_approx(values["hatch_mm"], look.hatch_mm))
	assert((values["paper_mm"] as Vector2) == Vector2(420.0, 297.0))


func test_two_renders_of_one_look_composite_with_one_set_of_uniforms() -> void:
	# The same statement from the other side: one look on one sheet gives one set of
	# uniforms, whatever else changes.
	var look := SketchStyleScript.new()
	var first: Dictionary = CompositorScript.uniform_values(look, Vector2(420.0, 297.0))
	var second: Dictionary = CompositorScript.uniform_values(look, Vector2(420.0, 297.0))
	assert(first == second)


func test_a_look_with_a_zero_repeat_is_held_off_the_divide() -> void:
	# A shader dividing by zero gives an infinity sampled as black: the whole sheet
	# would come out dark, from a setting that looks like "no grain".
	var look := SketchStyleScript.new()
	look.grain_mm = 0.0
	look.hatch_mm = -1.0
	var values: Dictionary = CompositorScript.uniform_values(look, Vector2(420.0, 297.0))
	assert(float(values["grain_mm"]) > 0.0)
	assert(float(values["hatch_mm"]) > 0.0)


func test_the_paper_textures_are_made_not_found() -> void:
	# The grain is a procedural texture, so the project carries its own paper rather
	# than depending on a file somebody might not have.
	var grain: Texture2D = CompositorScript.grain_texture()
	assert(grain != null)
	assert(grain.get_width() > 1 and grain.get_height() > 1)
	assert(grain == CompositorScript.grain_texture(), "made once")
	var hatch: Texture2D = CompositorScript.hatch_texture()
	assert(hatch != null)
	assert(hatch is GradientTexture2D)
	# The hatch has to tile: a gradient without repeat would fade out instead of
	# crossing, and the mid-tones would have a tooth on one side of the sheet only.
	assert((hatch as GradientTexture2D).repeat == GradientTexture2D.REPEAT)


func test_the_paper_texture_actually_varies() -> void:
	# A texture that came out flat would leave the sheet perfectly smooth however the
	# grain strength was set, which is a setting that does nothing while looking fine.
	var image: Image = (CompositorScript.grain_texture() as ImageTexture).get_image()
	assert(image != null, "the paper's fibre is drawn synchronously, not on a thread")
	var first: Color = image.get_pixel(0, 0)
	var varies := false
	for y in range(0, image.get_height(), 3):
		for x in range(0, image.get_width(), 3):
			if not image.get_pixel(x, y).is_equal_approx(first):
				varies = true
				break
		if varies:
			break
	assert(varies, "the paper fibre is a flat colour")


func test_the_grain_is_not_squashed_into_nothing() -> void:
	# The bug this test exists for: a grain repeat of a quarter of a millimetre put the
	# whole 256-texel fibre texture inside one and a half texels of the sheet, so the mip
	# filter averaged it away and the paper came out perfectly flat. Nothing failed - it
	# just quietly stopped being paper.
	var look := SketchStyleScript.new()
	var bake_density: float = look.texels_per_mm * float(look.supersample)
	var grain_squash: float = CompositorScript.minification_for(
		CompositorScript.GRAIN_PIXELS, look.grain_mm, bake_density
	)
	var hatch_squash: float = CompositorScript.minification_for(
		CompositorScript.HATCH_PIXELS, look.hatch_mm, bake_density
	)
	assert(grain_squash <= CompositorScript.MAX_MINIFICATION,
		"grain minified %.1fx: it will be averaged into flat paper" % grain_squash)
	assert(hatch_squash <= CompositorScript.MAX_MINIFICATION,
		"hatch minified %.1fx" % hatch_squash)
	# And the relationship is stated rather than implied: a repeat of zero gives no
	# answer rather than an infinite one to compare against.
	assert(is_equal_approx(
		CompositorScript.minification_for(64, 4.0, 4.0), 4.0
	))
	assert(CompositorScript.minification_for(64, 0.0, 6.0) == INF)


# --- the look -------------------------------------------------------------------------


func test_the_look_describes_itself_and_copies_independently() -> void:
	var look := SketchStyleScript.new()
	var words: String = look.describe()
	assert(words.contains("mm"))
	assert(words.contains("texels/mm"))
	var other: SketchStyleScript = look.copy()
	other.wobble_mm = 1.5
	assert(not is_equal_approx(look.wobble_mm, other.wobble_mm))
	assert(is_equal_approx(other.grain, look.grain), "a copy carries every other field")