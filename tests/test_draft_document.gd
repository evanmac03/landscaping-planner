extends Node
## Tests for the document store: draw order, layer visibility driving selection,
## snapshot undo, and persistence.

const Entity := preload("res://scripts/draft/draft_entity.gd")
const Document := preload("res://scripts/draft/draft_document.gd")
const LayerSet := preload("res://scripts/draft/layer_set.gd")


func _sample_line(x: float = 0.0) -> Variant:
	return Entity.make_line(Vector2(x, 0.0), Vector2(x + 2.0, 0.0))


func test_a_new_document_has_the_preset_layers() -> void:
	var document = Document.new()
	assert(document.layers.size() == LayerSet.PRESETS.size())
	assert(document.count() == 0)
	assert(document.units.system == document.units.System.METRIC)


func test_add_assigns_an_id_and_a_layer() -> void:
	var document = Document.new()
	var first: int = document.add(_sample_line(), LayerSet.NEW_HARDSCAPE)
	var second: int = document.add(_sample_line(5.0))
	assert(first != second)
	assert(first == 1)
	assert(document.count() == 2)
	assert(document.has(first))
	# An entity with no layer lands on the default drafting layer rather than
	# becoming invisible.
	assert(document.get_entity(second).layer == LayerSet.NEW_BED)


## A site is a fact about the drawing, so it is saved with it: a designer who works in one
## place should not have to tell every presentation about it again (visualization spec §16).
func test_a_site_is_a_property_of_the_drawing() -> void:
	var document = Document.new()
	assert(is_equal_approx(document.site_latitude, Document.DEFAULT_SITE_LATITUDE))
	assert(is_equal_approx(document.site_longitude, Document.DEFAULT_SITE_LONGITUDE))
	assert(is_equal_approx(document.site_utc_offset_hours, Document.DEFAULT_SITE_UTC_OFFSET_HOURS))
	# The three defaults agree with each other, which is what makes a study run on a new
	# drawing merely wrong about the site rather than nonsense about the sky: a longitude
	# more than half a zone away from its own meridian would put solar noon near 1 o'clock.
	assert(
		absf(document.site_longitude - 15.0 * document.site_utc_offset_hours) < 7.5,
		"the default site's longitude should be near its own zone's meridian"
	)
	document.set_site(51.5, -0.12, 0.0)
	var restored = Document.from_dict(document.to_dict())
	assert(is_equal_approx(restored.site_latitude, 51.5))
	assert(is_equal_approx(restored.site_longitude, -0.12))
	assert(is_equal_approx(restored.site_utc_offset_hours, 0.0))
	# A file written before the site was a place has the latitude and nothing else: the
	# latitude is kept and the rest is defaulted. A file with no site at all gets the
	# defaults rather than zeroes, because zero latitude is the equator and zero longitude
	# is Greenwich, which are two sites, and both of them wrong.
	var older: Dictionary = document.to_dict()
	older.erase("site")
	older["site_latitude"] = 51.5
	var legacy = Document.from_dict(older)
	assert(is_equal_approx(legacy.site_latitude, 51.5))
	assert(is_equal_approx(legacy.site_longitude, Document.DEFAULT_SITE_LONGITUDE))
	var oldest: Dictionary = document.to_dict()
	oldest.erase("site")
	assert(is_equal_approx(Document.from_dict(oldest).site_latitude, Document.DEFAULT_SITE_LATITUDE))
	# And an undo step does not move the site to another country.
	restored.set_site(45.0, -75.0, -5.0)
	restored.add(_sample_line())
	var snapshot: Dictionary = restored.snapshot()
	restored.set_site(12.0, 0.0, 8.0)
	restored.restore(snapshot)
	assert(is_equal_approx(restored.site_latitude, 45.0))
	assert(is_equal_approx(restored.site_longitude, -75.0))


## Moving the site is a change to the drawing like any other: one act, one undo step, and it
## says whether there was anything to do.
func test_moving_the_site_is_one_undoable_step() -> void:
	var document = Document.new()
	var moves: Array = []
	document.changed.connect(func() -> void: moves.append(1))
	assert(document.set_site(43.7, -79.4, -5.0))
	assert(moves.size() == 1)
	# The same site again is not a change, and does not pretend to be one.
	assert(not document.set_site(43.7, -79.4, -5.0))
	assert(moves.size() == 1)
	assert(document.undo_last())
	assert(is_equal_approx(document.site_latitude, Document.DEFAULT_SITE_LATITUDE))
	assert(is_equal_approx(document.site_longitude, Document.DEFAULT_SITE_LONGITUDE))


func test_an_unknown_layer_falls_back() -> void:
	var document = Document.new()
	var id: int = document.add(_sample_line(), &"999-NOT-A-LAYER")
	assert(document.get_entity(id).layer == LayerSet.NEW_BED)


func test_replace_keeps_the_id() -> void:
	var document = Document.new()
	var id: int = document.add(_sample_line())
	var replacement = Entity.make_circle(Vector2.ZERO, 3.0)
	assert(document.replace(id, replacement))
	assert(document.get_entity(id).kind == Entity.Kind.CIRCLE)
	assert(document.get_entity(id).id == id)


func test_draw_order_follows_the_layer_band() -> void:
	var document = Document.new()
	# Added out of band order on purpose.
	document.add(_sample_line(), LayerSet.SHEET_BORDER)
	document.add(_sample_line(), LayerSet.NEW_BED)
	document.add(_sample_line(), LayerSet.NEW_PLANTING)
	var order := document.entities()
	var bands: Array[StringName] = []
	for entity in order:
		bands.append(entity.layer)
	# The bed (400) plots before the planting (401) and the border (900) sits on
	# top, which is what the numeric prefix means.
	assert(bands[0] == LayerSet.NEW_BED)
	assert(bands[1] == LayerSet.NEW_PLANTING)
	assert(bands[2] == LayerSet.SHEET_BORDER)


func test_within_a_band_insertion_order_is_kept() -> void:
	var document = Document.new()
	var first: int = document.add(_sample_line(0.0), LayerSet.NEW_BED)
	var second: int = document.add(_sample_line(10.0), LayerSet.NEW_BED)
	var order := document.entities()
	assert(order[0].id == first)
	assert(order[1].id == second)


func test_hiding_a_layer_removes_its_geometry_from_every_selection() -> void:
	var document = Document.new()
	document.add(_sample_line(), LayerSet.NEW_BED)
	document.add(_sample_line(8.0), LayerSet.NEW_PLANTING)
	assert(document.visible_entities().size() == 2)
	document.layers.set_visible(LayerSet.NEW_PLANTING, false)
	assert(document.visible_entities().size() == 1)
	# Hiding is the single state every view reads, so nothing can disagree
	# (REQ 5.2.3).
	assert(document.visible_entities()[0].layer == LayerSet.NEW_BED)


## Locking is the second state a pick reads, and it is deliberately not hiding: everything on the
## locked layer is still drawn and still plots, it is simply left out of what can be changed.
func test_a_locked_layers_geometry_is_drawn_but_not_editable() -> void:
	var document = Document.new()
	document.add(_sample_line(), LayerSet.NEW_BED)
	document.add(_sample_line(8.0), LayerSet.NEW_PLANTING)
	assert(document.editable_entities().size() == 2, "nothing is protected yet")
	document.layers.set_locked(LayerSet.NEW_PLANTING, true)
	assert(document.is_layer_locked(LayerSet.NEW_PLANTING))
	assert(document.visible_entities().size() == 2, "a locked layer is still drawn")
	assert(document.editable_entities().size() == 1, "and left out of what can be changed")
	assert(document.editable_entities()[0].layer == LayerSet.NEW_BED)
	assert(not document.is_layer_locked(LayerSet.NEW_BED), "the other layer is untouched")


func test_non_plotting_layers_are_excluded_from_the_plot_set() -> void:
	var document = Document.new()
	document.add(_sample_line(), LayerSet.NEW_BED)
	document.add(_sample_line(4.0), LayerSet.GUIDES)
	assert(document.visible_entities().size() == 2)
	assert(document.plotting_entities().size() == 1)
	assert(document.plotting_entities()[0].layer == LayerSet.NEW_BED)


func test_bounds_cover_all_geometry() -> void:
	var document = Document.new()
	document.add(Entity.make_line(Vector2(0, 0), Vector2(10, 0)))
	document.add(Entity.make_line(Vector2(5, -4), Vector2(5, 6)))
	var box := document.bounds()
	assert(is_equal_approx(box.position.x, 0.0))
	assert(is_equal_approx(box.position.y, -4.0))
	assert(is_equal_approx(box.size.x, 10.0))
	assert(is_equal_approx(box.size.y, 10.0))


func test_remove_reports_whether_it_did_anything() -> void:
	var document = Document.new()
	var id: int = document.add(_sample_line())
	assert(document.remove(id))
	assert(not document.remove(id))
	assert(document.count() == 0)


# --- undo ---------------------------------------------------------------------------


func test_a_gesture_undoes_and_redoes_as_one_step() -> void:
	var document = Document.new()
	document.begin_gesture()
	var id: int = document.add(_sample_line())
	document.add(_sample_line(20.0))
	assert(document.count() == 2)
	# One gesture, so one undo puts both back.
	assert(document.undo_last())
	assert(document.count() == 0)
	assert(document.redo_last())
	assert(document.count() == 2)
	assert(document.has(id))


func test_undo_restores_geometry_exactly() -> void:
	var document = Document.new()
	var id: int = document.add(_sample_line())
	document.begin_gesture()
	var entity = document.get_entity(id)
	entity.translate(Vector2(4.5, -2.25))
	assert(document.get_entity(id).point(0).is_equal_approx(Vector2(4.5, -2.25)))
	assert(document.undo_last())
	assert(document.get_entity(id).point(0).is_equal_approx(Vector2(0, 0)))


func test_undo_restores_layer_visibility() -> void:
	var document = Document.new()
	document.begin_gesture()
	document.layers.set_visible(LayerSet.NEW_PLANTING, false)
	assert(not document.layers.get_layer(LayerSet.NEW_PLANTING).visible)
	assert(document.undo_last())
	assert(document.layers.get_layer(LayerSet.NEW_PLANTING).visible)


func test_a_snapshot_is_not_reachable_from_later_edits() -> void:
	var document = Document.new()
	var id: int = document.add(_sample_line())
	document.begin_gesture()
	document.get_entity(id).translate(Vector2(100, 100))
	# The stored snapshot must still describe the original geometry.
	document.undo_last()
	assert(document.get_entity(id).point(0).is_equal_approx(Vector2(0, 0)))


func test_undo_with_nothing_recorded_is_a_no_op() -> void:
	var document = Document.new()
	assert(not document.undo_last())
	assert(not document.redo_last())


# --- the gestures, by name and number -------------------------------------------------


func test_a_gesture_is_recorded_under_the_word_it_is_given() -> void:
	var document = Document.new()
	document.begin_gesture("drawing a new line")
	var id: int = document.add(_sample_line())
	document.begin_gesture("erasing")
	document.remove(id)
	assert(document.undo_label() == "erasing", "the last thing done")
	assert(document.gesture_serial() == 2, "and it is the drawing's second gesture")
	assert(document.undo_last())
	assert(document.undo_label() == "drawing a new line", "which puts the erasing on the redo side")
	assert(document.redo_label() == "erasing", "named, so redo can say what it would do")


func test_a_gesture_nobody_named_is_still_a_gesture() -> void:
	var document = Document.new()
	document.begin_gesture()
	assert(document.gesture_serial() == 1)
	assert(document.undo_label() == "an edit", "an unlabelled act says as much as it can")


func test_a_state_this_document_is_not_in_can_be_recorded_as_a_gesture() -> void:
	# What a restore needs: the drawing is about to be replaced by an earlier revision, so the state it
	# leaves has to be a gesture on the history it is leaving itself.
	var document = Document.new()
	document.add(_sample_line())
	var before: Dictionary = document.snapshot()
	document.clear()
	assert(document.count() == 0, "the drawing is empty")
	document.record_gesture(before, "putting a revision back")
	assert(document.undo_label() == "putting a revision back")
	assert(document.undo_last(), "and undo puts the drawing back")
	assert(document.count() == 1)


# --- persistence --------------------------------------------------------------------


func test_document_round_trips_through_persistence() -> void:
	var document = Document.new()
	var id: int = document.add(Entity.make_polyline(PackedVector2Array([
		Vector2(1.5, 2.5), Vector2(3.75, 4.125)]), true), LayerSet.NEW_BED)
	document.layers.set_visible(LayerSet.NEW_PLANTING, false)

	var restored = Document.from_dict(document.to_dict())
	assert(restored.count() == 1)
	assert(restored.has(id))
	assert(restored.get_entity(id).kind == Entity.Kind.POLYGON)
	assert(restored.get_entity(id).layer == LayerSet.NEW_BED)
	assert(restored.get_entity(id).params == document.get_entity(id).params)
	# Layer state survives, not just geometry.
	assert(not restored.layers.get_layer(LayerSet.NEW_PLANTING).visible)


func test_loading_a_document_keeps_the_preset_layers() -> void:
	var document = Document.new()
	var restored = Document.from_dict(document.to_dict())
	# A saved file lists layer records; those must not replace the live LayerSet
	# with an Array.
	assert(restored.layers.size() == LayerSet.PRESETS.size())
	assert(restored.layers.has(LayerSet.UNDERLAY))
	assert(restored.layers.get_layer(LayerSet.UNDERLAY).plots == false)


func test_clear_empties_the_document() -> void:
	var document = Document.new()
	document.add(_sample_line())
	document.add(_sample_line(3.0))
	document.clear()
	assert(document.count() == 0)
	assert(document.bounds().size == Vector2.ZERO)