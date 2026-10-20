extends Node
## Tests for filling as the controller runs it: the region comes from the drawing, the pattern lands
## as lines on the hatch layer, and the whole fill is one undo step.
##
## The controller is built with its parts but no scene tree, exactly as the selection and editing
## commands are: a fill needs a document and a controller, and nothing else.

const Ctrl := preload("res://scripts/draft/draft_controller.gd")
const Tool := preload("res://scripts/draft/draft_tool.gd")
const Document := preload("res://scripts/draft/draft_document.gd")
const SnapScript := preload("res://scripts/draft/snap_engine.gd")
const Entity := preload("res://scripts/draft/draft_entity.gd")
const LayerSet := preload("res://scripts/draft/layer_set.gd")
const Fill := preload("res://scripts/draft/hatch_fill.gd")


func _controller():
	var controller = Ctrl.new()
	controller.document = Document.new()
	controller.snap = SnapScript.new()
	controller.tool = Tool.new()
	return controller


func _polygon(size: float = 10.0):
	return Entity.make_polyline(PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(size, 0.0), Vector2(size, size), Vector2(0.0, size)]), true)


func _hatch_options(pattern: StringName = Fill.HATCH) -> Dictionary:
	return {"pattern": pattern, "spacing_mm": 2.0, "angle_deg": 0.0, "symbol": Fill.SYMBOL_DOT}


# --- the fill -------------------------------------------------------------------------


func test_filling_a_region_lands_on_the_hatch_layer_and_is_one_undo_step() -> void:
	var controller = _controller()
	var id: int = controller.document.add(_polygon(), LayerSet.NEW_BED)
	var before: int = controller.document.count()
	var filled: Dictionary = controller.fill_entity(id, _hatch_options())
	assert(bool(filled["ok"]), String(filled["reason"]))
	assert(int(filled["count"]) > 0, "something was drawn")
	assert(controller.document.count() == before + int(filled["count"]))
	for entity in controller.document.entities():
		if entity.id != id:
			assert(entity.layer == LayerSet.HATCH, "the pattern lands on the hatch layer")
	assert(controller.dirty, "a fill is an edit")
	# Hatching a bed is one act, so one undo takes the whole pattern back off.
	assert(controller.document.undo_last())
	assert(controller.document.count() == before)
	controller.free()


func test_the_fill_says_what_it_drew() -> void:
	var controller = _controller()
	var id: int = controller.document.add(_polygon(), LayerSet.NEW_BED)
	var filled: Dictionary = controller.fill_entity(id, _hatch_options())
	assert(String(filled["message"]).begins_with("filled the region: Line hatch, "))
	# The count in the words is the count of lines that were actually added.
	var expected: int = int(String(filled["message"]).split(" ")[-2])
	assert(int(filled["count"]) == expected)
	controller.free()


func test_the_paper_spacing_is_turned_into_model_metres_by_the_scale() -> void:
	var controller = _controller()
	var id: int = controller.document.add(_polygon(), LayerSet.NEW_BED)
	# At 1:100, 2 mm is 0.2 m, so a ten-metre square is crossed about fifty times.
	var coarse: Dictionary = controller.fill_entity(id, _hatch_options())
	controller.document.undo_last()
	controller.plot_scale = 50.0
	var fine: Dictionary = controller.fill_entity(id, _hatch_options())
	assert(int(fine["count"]) > int(coarse["count"]), "a smaller scale draws a finer hatch")
	controller.free()


func test_a_stipple_fill_writes_symbol_marks() -> void:
	var controller = _controller()
	var id: int = controller.document.add(_polygon(), LayerSet.NEW_BED)
	var filled: Dictionary = controller.fill_entity(id, _hatch_options(Fill.STIPPLE))
	assert(bool(filled["ok"]), String(filled["reason"]))
	assert(String(filled["message"]).contains("Symbol stipple"))
	assert(String(filled["message"]).contains("dot"))
	assert(int(filled["count"]) > 0)
	controller.free()


func test_a_solid_fill_ignores_the_spacing_it_was_offered() -> void:
	var controller = _controller()
	var id: int = controller.document.add(_polygon(), LayerSet.NEW_BED)
	var solid: Dictionary = controller.fill_entity(id, {
		"pattern": Fill.SOLID, "spacing_mm": 5.0, "angle_deg": 0.0,
	})
	assert(bool(solid["ok"]), String(solid["reason"]))
	# Solid's density is fixed on paper, so it is not the sparse 5 mm a line hatch would be.
	var sparse: Dictionary = controller.fill_entity(id, {
		"pattern": Fill.HATCH, "spacing_mm": 5.0, "angle_deg": 0.0,
	})
	assert(int(solid["count"]) > int(sparse["count"]))
	controller.free()


# --- refusing -------------------------------------------------------------------------


func test_a_shape_that_encloses_nothing_cannot_be_filled() -> void:
	var controller = _controller()
	var id: int = controller.document.add(
		Entity.make_line(Vector2(0.0, 0.0), Vector2(5.0, 5.0)), LayerSet.NEW_BED)
	var filled: Dictionary = controller.fill_entity(id, _hatch_options())
	assert(not bool(filled["ok"]))
	assert(String(filled["reason"]).contains("does not enclose an area"))
	controller.free()


func test_a_region_that_has_gone_is_refused() -> void:
	var controller = _controller()
	var filled: Dictionary = controller.fill_entity(9999, _hatch_options())
	assert(not bool(filled["ok"]))
	assert(String(filled["reason"]).contains("not on the drawing"))
	controller.free()


func test_a_pattern_nobody_has_is_refused_rather_than_guessed() -> void:
	var controller = _controller()
	var id: int = controller.document.add(_polygon(), LayerSet.NEW_BED)
	var filled: Dictionary = controller.fill_entity(id, {"pattern": &"plaid"})
	assert(not bool(filled["ok"]))
	assert(String(filled["reason"]).contains("no such fill pattern"))
	assert(controller.document.count() == 1, "and nothing was drawn")
	controller.free()


# --- the regions the drawing offers ---------------------------------------------------


func test_the_regions_offered_are_the_drawings_own_closed_areas() -> void:
	var controller = _controller()
	controller.document.add(_polygon(), LayerSet.NEW_BED)
	# A line on the same layer encloses nothing, so it is not a region.
	controller.document.add(
		Entity.make_line(Vector2(20.0, 20.0), Vector2(30.0, 30.0)), LayerSet.NEW_BED)
	var rows: Array[Dictionary] = controller.hatch_regions()
	assert(rows.size() == 1, "one closed area")
	assert(String(rows[0]["name"]).begins_with("bed "))
	assert(absf(float(rows[0]["area_m2"]) - 100.0) < 1.0e-6)
	controller.free()


func test_filling_one_region_leaves_the_others_alone() -> void:
	var controller = _controller()
	var near: int = controller.document.add(_polygon(5.0), LayerSet.NEW_BED)
	var far = _polygon(8.0)
	far.set_point(0, Vector2(40.0, 40.0))
	var far_id: int = controller.document.add(far, LayerSet.NEW_BED)
	var far_before: PackedFloat64Array = controller.document.get_entity(far_id).params.duplicate()
	controller.fill_entity(near, _hatch_options())
	var rows: Array[Dictionary] = controller.hatch_regions()
	assert(rows.size() == 2, "both regions are still there")
	assert(controller.document.get_entity(far_id).params == far_before)
	controller.free()


func test_the_fill_offers_a_region_it_can_read_back_and_name() -> void:
	var controller = _controller()
	var id: int = controller.document.add(_polygon(), LayerSet.NEW_BED)
	var rows: Array[Dictionary] = controller.hatch_regions()
	assert(int(rows[0]["entity_id"]) == id)
	var outline: PackedVector2Array = rows[0]["outline"]
	assert(outline.size() == 4)
	controller.free()