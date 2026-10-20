extends Node
## Tests for turning entities into drawable strokes: which style wins, and the
## dash conversion between paper millimetres and model metres.

const Render := preload("res://scripts/draft/draft_render.gd")
const Entity := preload("res://scripts/draft/draft_entity.gd")
const LineStyle := preload("res://scripts/draft/line_style.gd")
const LayerScript := preload("res://scripts/draft/draft_layer.gd")


# --- the shared layout ------------------------------------------------------------------


## The plan, the sheet and the 3D overlay all draw through the layout, so what it
## reports for an entity is what every view shows.
func test_the_layout_of_a_plain_entity_is_its_linework() -> void:
	var entity = Entity.make_line(Vector2(0, 0), Vector2(10, 0))
	var parts := Render.layout(entity, _layer(), 100.0)
	assert(parts["lines"].size() == 1)
	assert(parts["arrows"].is_empty())
	assert(parts["labels"].is_empty())
	# The lines are the same ones strokes would have given, not a second opinion.
	assert(parts["lines"][0] == Render.strokes(entity, _layer(), 100.0)[0])


func test_the_layout_of_a_dimension_is_its_extension_and_arrowheads() -> void:
	var entity = Entity.make_dimension(Vector2(0, 0), Vector2(10, 0), 1.0)
	var parts := Render.layout(entity, _layer(), 100.0)
	assert(parts["lines"].size() == 3)
	assert(parts["arrows"].size() == 2)
	assert(parts["labels"].size() == 1)


## A text entity has a position but no outline, so it reaches a view as a label
## alone. Its height is authored in paper millimetres and converted like a weight.
func test_the_layout_of_a_text_entity_is_a_label_with_a_height() -> void:
	var entity = Entity.make_text(Vector2(3, 4), "Patio (new)")
	var parts := Render.layout(entity, _layer(), 100.0)
	assert(parts["lines"].is_empty())
	assert(parts["arrows"].is_empty())
	assert(parts["labels"].size() == 1)
	assert(parts["labels"][0]["text"] == "Patio (new)")
	assert(Vector2(parts["labels"][0]["position"]).is_equal_approx(Vector2(3, 4)))
	assert(is_equal_approx(
		parts["labels"][0]["height"], LineStyle.DEFAULT_TEXT_HEIGHT * 100.0 / 1000.0
	))
	# A height set on the entity wins, so a note can be authored to its own size.
	entity.meta["height"] = 5.0
	assert(is_equal_approx(
		Render.layout(entity, _layer(), 100.0)["labels"][0]["height"], 0.5
	))


## A dimension measures the drawing and a note annotates it: neither is a thing
## standing in the garden, so the 3D overlay leaves both out.
func test_annotations_are_flagged_for_the_ground_view() -> void:
	assert(Render.is_annotation(Entity.make_dimension(Vector2(0, 0), Vector2(10, 0))))
	assert(Render.is_annotation(Entity.make_text(Vector2(0, 0), "note")))
	assert(not Render.is_annotation(Entity.make_line(Vector2(0, 0), Vector2(1, 1))))
	assert(not Render.is_annotation(Entity.make_circle(Vector2(0, 0), 2.0)))
	assert(not Render.is_annotation(Entity.make_rectangle(Vector2(0, 0), Vector2(2, 2))))


func _layer(linetype: StringName = &"continuous"):
	var layer = LayerScript.new()
	layer.linetype = linetype
	layer.plot_weight_mm = 0.25
	layer.screen_colour = Color(1, 0, 0)
	layer.plot_colour = Color.BLACK
	return layer


func test_a_continuous_layer_draws_one_stroke() -> void:
	var entity = Entity.make_line(Vector2(0, 0), Vector2(10, 0))
	var strokes := Render.strokes(entity, _layer(), 100.0)
	assert(strokes.size() == 1)
	assert(strokes[0].size() == 2)


## The bug this test exists for: dashes are authored in paper millimetres and
## strokes are in metres, so the two have to be converted. Skipping the
## conversion made every dash a thousand times too long, which looks exactly
## like a solid line, so dashed layers plotted solid and nothing complained.
func test_a_dashed_layer_actually_stops_and_starts() -> void:
	var entity = Entity.make_line(Vector2(0, 0), Vector2(10, 0))
	var strokes := Render.strokes(entity, _layer(&"dashed"), 100.0)
	assert(strokes.size() > 5)
	# A 6 mm dash at 1:100 covers 0.6 m of the model.
	var first: PackedVector2Array = strokes[0]
	assert(first.size() == 2)
	assert(absf(first[0].distance_to(first[1]) - 0.6) < 0.001)


func test_a_finer_dash_pattern_draws_more_dashes() -> void:
	var entity = Entity.make_line(Vector2(0, 0), Vector2(10, 0))
	var dotted := Render.strokes(entity, _layer(&"dotted"), 100.0).size()
	var dashed := Render.strokes(entity, _layer(&"dashed"), 100.0).size()
	assert(dotted > dashed)


func test_the_dash_scale_follows_the_plot_scale() -> void:
	var entity = Entity.make_line(Vector2(0, 0), Vector2(10, 0))
	# At 1:50 the same 6 mm dash covers half the ground, so a fixed model length
	# breaks into about twice as many of them.
	var at_50 := Render.strokes(entity, _layer(&"dashed"), 50.0).size()
	var at_100 := Render.strokes(entity, _layer(&"dashed"), 100.0).size()
	assert(at_50 > at_100)


func test_an_entity_override_beats_its_layer() -> void:
	var layer = _layer()
	var override := LineStyle.new()
	override.plot_weight_mm = 1.40
	var entity = Entity.make_line(Vector2(0, 0), Vector2(1, 0))
	entity.style = override
	assert(Render.style_for(entity, layer) == override)
	assert(is_equal_approx(Render.style_for(entity, layer).plot_weight_mm, 1.40))
	# Without one, the layer's style applies.
	var plain = Entity.make_line(Vector2(0, 0), Vector2(1, 0))
	assert(is_equal_approx(Render.style_for(plain, layer).plot_weight_mm, 0.25))


func test_an_entity_with_no_layer_still_gets_a_style() -> void:
	var entity = Entity.make_line(Vector2(0, 0), Vector2(1, 0))
	var style = Render.style_for(entity, null)
	assert(style != null)
	assert(style.plot_weight_mm > 0.0)


func test_screen_and_plot_colours_are_separate_concerns() -> void:
	var layer = _layer()
	assert(Render.screen_colour(layer).is_equal_approx(Color(1, 0, 0)))
	assert(Render.plot_colour(layer).is_equal_approx(Color.BLACK))
	# Nothing to read: fall back to ink on screen and black on paper.
	assert(Render.screen_colour(null).is_equal_approx(Render.INK))
	assert(Render.plot_colour(null).is_equal_approx(Color.BLACK))


func test_a_text_entity_has_no_linework() -> void:
	var entity = Entity.make_text(Vector2(1, 2), "Patio")
	assert(Render.strokes(entity, _layer(), 100.0).is_empty())
	assert(Render.label_of(entity) == "Patio")
	assert(Render.label_position(entity).is_equal_approx(Vector2(1, 2)))


## A zero-size shape is refused by the tools, so it cannot reach the document;
## if one ever did, it must contribute no geometry rather than a dot.
func test_a_zero_size_shape_contributes_nothing() -> void:
	var entity = Entity.make_circle(Vector2.ZERO, 0.0)
	for stroke: PackedVector2Array in Render.strokes(entity, _layer(), 100.0):
		for index in stroke.size() - 1:
			assert(stroke[index].distance_to(stroke[index + 1]) < 1e-9)


func test_width_is_the_weight_law_in_pixels() -> void:
	var style := LineStyle.new()
	style.plot_weight_mm = 0.5
	# 0.5 mm at 1:100 is 0.05 m of model, which at 40 px per metre is 2 px.
	assert(is_equal_approx(Render.width_pixels(style, 100.0, 40.0), 2.0))


func test_an_arc_becomes_a_sampled_stroke() -> void:
	var entity = Entity.make_arc(Vector2.ZERO, 5.0, 0.0, PI * 0.5)
	var strokes := Render.strokes(entity, _layer(), 100.0)
	assert(strokes.size() == 1)
	assert(strokes[0].size() > 4)