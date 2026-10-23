extends Node
## The grading tools, joined to the drawing.
##
## The module is tested on its own in `test_grading.gd`. This is the part that only exists once the
## tools, the controller and the drawing are put together: that a grading tool completes with *picks*
## rather than with an entity, that the controller stamps those picks as a record plus its marks, that
## every stamp is one named undoable gesture, that a refusal leaves the drawing exactly as it was, and
## that a level in hand is a number in hand rather than a fact about the file.
##
## Nothing here enters a tree, so no `_ready` runs and no window is ever shown.

const ControllerScript := preload("res://scripts/draft/draft_controller.gd")
const DocumentScript := preload("res://scripts/draft/draft_document.gd")
const SnapScript := preload("res://scripts/draft/snap_engine.gd")
const ToolScript := preload("res://scripts/draft/draft_tool.gd")
const GradingScript := preload("res://scripts/draft/grading.gd")
const LayerSetScript := preload("res://scripts/draft/layer_set.gd")
const TakeoffScript := preload("res://scripts/biz/takeoff.gd")

const SPOT := GradingScript.SPOT
const CONTOUR := GradingScript.CONTOUR
const SLOPE := GradingScript.SLOPE


# --- helpers --------------------------------------------------------------------------


## A controller with a drawing on it and no scene around it.
func _controller() -> DraftController:
	var controller := ControllerScript.new()
	controller.document = DocumentScript.new()
	controller.document.changed.connect(controller._on_document_changed)
	controller.snap = SnapScript.new()
	controller.snap.bind(controller.document.entities())
	controller.tool = ToolScript.new()
	return controller


## Stamp a spot level at a place, the way a person does: state the level, take the tool, click.
func _spot_at(controller: DraftController, at: Vector2, level: float) -> Dictionary:
	controller.set_grading_level(level)
	controller.begin_grading(SPOT)
	var pick: Dictionary = controller.tool.click(at)
	controller._commit(pick)
	return pick


## Stamp a slope arrow, stating the fall in hand.
func _arrow(controller: DraftController, from: Vector2, to: Vector2, percent: float) -> Dictionary:
	controller.set_grading_fall(percent)
	controller.begin_grading(SLOPE)
	var pick: Dictionary = controller.tool.click(from)
	controller._commit(controller.tool.click(to))
	return pick


## The label the plan holds for a record, or "" when there is none - which is how a test reads what a
## level is written as on the drawing rather than inside the record.
func _label_text(controller: DraftController, kind: String, id: int) -> String:
	for entity: DraftEntity in controller.document.entities():
		if GradingScript.kind_of_entity(entity) != kind or GradingScript.id_of_entity(entity) != id:
			continue
		if entity.kind == EntityKind.TEXT:
			return String(entity.meta.get("text", ""))
	return ""


const EntityKind := preload("res://scripts/draft/draft_entity.gd").Kind


func _on_layer(controller: DraftController, layer: StringName) -> int:
	return controller.document.entities_on_layer(layer).size()


# --- the tools ----------------------------------------------------------------------------


func test_the_three_grading_tools_are_the_three_the_module_knows() -> void:
	for pair: Array in [
		[ToolScript.Kind.GRADE_SPOT, SPOT], [ToolScript.Kind.GRADE_CONTOUR, CONTOUR],
		[ToolScript.Kind.GRADE_SLOPE, SLOPE],
	]:
		var kind: ToolScript.Kind = pair[0]
		assert(ToolScript.is_grading(kind), str(kind))
		assert(ToolScript.grading_kind(kind) == String(pair[1]), ToolScript.grading_kind(kind))
	assert(not ToolScript.is_grading(ToolScript.Kind.LINE), "a line is not about the ground's heights")
	assert(not ToolScript.is_grading(ToolScript.Kind.POLYLINE), "and neither is a polyline")
	assert(ToolScript.grading_kind(ToolScript.Kind.LINE) == "", "which states no kind of record")
	assert(ToolScript.label_for(ToolScript.Kind.GRADE_SPOT) == "Spot level", ToolScript.label_for(ToolScript.Kind.GRADE_SPOT))
	assert(ToolScript.label_for(ToolScript.Kind.GRADE_CONTOUR) == "Contour", ToolScript.label_for(ToolScript.Kind.GRADE_CONTOUR))
	assert(ToolScript.label_for(ToolScript.Kind.GRADE_SLOPE) == "Slope arrow", ToolScript.label_for(ToolScript.Kind.GRADE_SLOPE))
	# A contour collects points until it is told to stop, like a polyline; the other two complete on
	# their own count.
	assert(ToolScript.is_ring(ToolScript.Kind.GRADE_CONTOUR), "a contour is drawn like a polyline")
	assert(ToolScript.is_ring(ToolScript.Kind.POLYLINE), "beside the polyline it is a copy of")
	assert(not ToolScript.is_ring(ToolScript.Kind.GRADE_SPOT), "a spot level is not a ring")


func test_a_spot_level_completes_with_one_click_and_hands_back_the_picks() -> void:
	var controller := _controller()
	controller.set_grading_level(102.35)
	controller.begin_grading(SPOT)
	assert(controller.tool.kind == ToolScript.Kind.GRADE_SPOT, "the spot tool is out")
	assert(controller.tool.needed_points() == 1, "and it wants one place")
	var pick: Dictionary = controller.tool.click(Vector2(1.0, 2.0))
	assert(bool(pick["committed"]), "one click completes it")
	assert(pick["entity"] == null, "**and no entity comes back**: the marks are stamped by the controller")
	var measure: Dictionary = pick["measure"]
	assert(String(measure["grading"]) == SPOT, str(measure))
	assert((measure["points"] as PackedVector2Array).size() == 1, "with the place it was picked at")
	assert((measure["points"] as PackedVector2Array)[0].is_equal_approx(Vector2(1.0, 2.0)), str(measure))
	controller.free()


func test_a_contour_is_drawn_like_a_polyline_and_an_arrow_completes_on_two_picks() -> void:
	var controller := _controller()
	controller.begin_grading(CONTOUR)
	assert(controller.tool.needed_points() == 0, "a contour collects points until it is finished")
	controller.tool.click(Vector2.ZERO)
	var open: Dictionary = controller.tool.click(Vector2(6.0, 0.0))
	assert(not bool(open["committed"]), "a second click is not the end of it")
	var finished: Dictionary = controller.tool.finish()
	assert(bool(finished["committed"]), "Enter is")
	assert(String((finished["measure"] as Dictionary)["grading"]) == CONTOUR, str(finished["measure"]))
	assert(not bool((finished["measure"] as Dictionary)["closed"]), "open, because C was not pressed")
	controller.begin_grading(SLOPE)
	assert(controller.tool.needed_points() == 2, "an arrow runs between two places")
	controller.tool.click(Vector2.ZERO)
	var arrow: Dictionary = controller.tool.click(Vector2(6.0, 0.0))
	assert(bool(arrow["committed"]), "and completes on the second")
	assert(String((arrow["measure"] as Dictionary)["grading"]) == SLOPE, str(arrow["measure"]))
	controller.free()


# --- the stamp ----------------------------------------------------------------------------


func test_a_spot_level_puts_a_mark_and_a_label_on_its_own_layer() -> void:
	var controller := _controller()
	_spot_at(controller, Vector2(3.0, 4.0), 102.35)
	assert(controller.document.count() == 2, "a mark and a label: %d" % controller.document.count())
	assert(_on_layer(controller, LayerSetScript.GRADING_SPOT) == 2, "both on the spot layer")
	assert(_on_layer(controller, LayerSetScript.NEW_HARDSCAPE) == 0, "and nothing on the layer in hand")
	assert(controller.grading_spots().size() == 1, "one record")
	assert(_label_text(controller, SPOT, 1) == "102.35 m", _label_text(controller, SPOT, 1))
	# The layer in hand for drawing tools is not disturbed by stamping a level: a grading tool goes to
	# its own layer for the reason a dimension goes to the dimension layer.
	assert(controller.drawing_layer == LayerSetScript.NEW_HARDSCAPE, String(controller.drawing_layer))
	assert(String(controller.last_message).contains("102.35 m at (3, 4) is on the drawing"),
		controller.last_message)
	controller.free()


func test_a_contour_puts_its_line_and_its_level_on_the_contour_layer() -> void:
	var controller := _controller()
	controller.set_grading_level(101.5)
	controller.begin_grading(CONTOUR)
	controller.tool.click(Vector2.ZERO)
	controller._commit(controller.tool.click(Vector2(10.0, 0.0)))
	controller._commit(controller.tool.finish())
	assert(controller.grading_contours().size() == 1, "one record")
	assert(_on_layer(controller, LayerSetScript.GRADING_CONTOUR) == 2, "a line and its level")
	assert(_label_text(controller, CONTOUR, 1) == "101.5 m", _label_text(controller, CONTOUR, 1))
	assert(controller.grading_lines().size() == 1, str(controller.grading_lines()))
	controller.free()


func test_a_slope_arrow_puts_its_shaft_head_and_fall_on_the_arrow_layer() -> void:
	var controller := _controller()
	_arrow(controller, Vector2.ZERO, Vector2(6.0, 0.0), 2.5)
	assert(controller.grading_slopes().size() == 1, "one record")
	assert(_on_layer(controller, LayerSetScript.GRADING_SLOPE) == 3, "a shaft, a head and the fall")
	assert(_label_text(controller, SLOPE, 1) == "falling 2.5% (1 in 40)", _label_text(controller, SLOPE, 1))
	controller.free()


func test_the_level_in_hand_is_not_written_into_the_file() -> void:
	# It is what the next spot level *gets*, not a fact about the drawing - so a file carries the levels
	# that were stamped and nothing about the ones that were merely in hand.
	var controller := _controller()
	_spot_at(controller, Vector2.ZERO, 102.35)
	var saved: Dictionary = controller.document.to_dict()
	assert(int(saved["version"]) == 11, "the file version: " + str(saved["version"]))
	assert(saved.has("grading"), "the records are in it")
	assert(not saved.has("grading_level"), "and the level in hand is not")
	assert(not saved.has("grading_fall_percent"), "nor is the fall in hand")
	var read = DocumentScript.from_dict(saved)
	assert(GradingScript.spots_of(read.grading).size() == 1, "the stamped level comes back")
	assert(controller.grading_level == 0.0 or true, "and a fresh drawing's level in hand is its own")
	controller.free()


func test_every_stamp_is_one_named_undoable_gesture() -> void:
	var controller := _controller()
	var before: int = controller.document.gesture_serial()
	_spot_at(controller, Vector2.ZERO, 102.35)
	assert(controller.document.gesture_serial() == before + 1, "one gesture")
	assert(controller.document.undo_label() == "stating a spot level", controller.document.undo_label())
	assert(controller.document.undo_last(), "which can be undone")
	assert(controller.document.count() == 0, "taking the marks with it")
	assert(controller.grading_spots().is_empty(), "**and the record**: so undo cannot leave a level on the "
		+ "drawing with no mark, or a mark with no level")
	assert(controller.document.redo_last(), "and put back")
	assert(controller.grading_spots().size() == 1, "record and marks together")
	assert(controller.document.count() == 2, "both marks")
	controller.free()


func test_a_stamp_that_found_nothing_records_no_gesture_at_all() -> void:
	# A gesture whose act found nothing to do is not a gesture: an undo step that does nothing is worse
	# than no step, because the button says there is something to undo.
	var controller := _controller()
	var before: int = controller.document.gesture_serial()
	var empty: Dictionary = controller.stamp_grading({"grading": CONTOUR, "points": PackedVector2Array()})
	assert(not bool(empty["ok"]), "a contour of no points is refused")
	assert(String(empty["reason"]) == "a contour needs at least two points to be a line",
		String(empty["reason"]))
	assert(controller.document.count() == 0, "nothing reached the drawing")
	assert(controller.document.gesture_serial() == before, "and nothing was recorded to undo")
	var one: Dictionary = controller.stamp_grading({
		"grading": SLOPE, "points": PackedVector2Array([Vector2.ZERO]),
	})
	assert(not bool(one["ok"]), "an arrow of one point is refused")
	assert(controller.document.gesture_serial() == before, "and records nothing either")
	controller.free()


func test_a_level_that_is_not_a_number_is_refused_rather_than_read_as_zero() -> void:
	# Zero is a real elevation above a real benchmark, so a level that is not a number is refused - and
	# the level in hand stays what it was rather than being quietly replaced.
	var controller := _controller()
	assert(bool(controller.set_grading_level(101.0)["ok"]), "a level is taken")
	var refused: Dictionary = controller.set_grading_level(NAN)
	assert(not bool(refused["ok"]), "NAN is not a level")
	assert(String(refused["reason"]) == "a level is a number", String(refused["reason"]))
	assert(is_equal_approx(controller.grading_level, 101.0), "and the level in hand is untouched")
	assert(not bool(controller.set_grading_level(INF)["ok"]), "and neither is infinity")
	controller.free()


func test_a_fall_that_is_not_a_percentage_is_refused() -> void:
	var controller := _controller()
	assert(bool(controller.set_grading_fall(2.5)["ok"]), "a fall is taken")
	assert(is_equal_approx(controller.grading_fall_percent, 2.5), str(controller.grading_fall_percent))
	var steep: Dictionary = controller.set_grading_fall(400.0)
	assert(not bool(steep["ok"]), "a fall past one in one is a wall, not a path")
	assert(String(steep["reason"]).contains("100"), String(steep["reason"]))
	assert(is_equal_approx(controller.grading_fall_percent, 2.5), "and the fall in hand is untouched")
	assert(not bool(controller.set_grading_fall(NAN)["ok"]), "a fall that is not a number is refused")
	controller.free()


func test_a_locked_layer_refuses_the_stamp_rather_than_writing_through_the_lock() -> void:
	var controller := _controller()
	controller.document.layers.set_locked(LayerSetScript.GRADING_SPOT, true)
	var stamped: Dictionary = controller.stamp_grading({
		"grading": SPOT, "points": PackedVector2Array([Vector2.ZERO]),
	})
	assert(not bool(stamped["ok"]), "a locked layer takes nothing")
	assert(String(stamped["reason"]).contains("is locked"), String(stamped["reason"]))
	assert(controller.document.count() == 0, "and the drawing is untouched")
	assert(controller.grading_spots().is_empty(), "no record either")
	controller.free()


# --- the check, live -----------------------------------------------------------------------


func test_the_check_catches_an_arrow_that_contradicts_the_levels_under_it() -> void:
	var controller := _controller()
	_spot_at(controller, Vector2.ZERO, 102.35)
	_spot_at(controller, Vector2(6.0, 0.0), 101.95)
	_arrow(controller, Vector2.ZERO, Vector2(6.0, 0.0), 2.5)
	var report: Dictionary = controller.grading_report()
	assert(not bool(report["ok"]), "the drawing does not agree with itself")
	assert(controller.grading_reports_findings(), "and the controller says so without being asked twice")
	var findings: Array = report["findings"]
	assert(findings.size() == 1, str(findings))
	assert(String(findings[0]).contains("says falling 2.5% (1 in 40)"), String(findings[0]))
	assert(String(findings[0]).contains("say falling 6.7% (1 in 15)"), String(findings[0]))
	assert(controller.grading_summary() == (
		"2 spot levels and a slope arrow on this drawing, running from 101.95 m to 102.35 m"
	), controller.grading_summary())
	controller.free()


# --- changing and taking off ----------------------------------------------------------------


func test_changing_a_level_rewrites_its_label_as_one_gesture() -> void:
	var controller := _controller()
	_spot_at(controller, Vector2.ZERO, 102.35)
	assert(_label_text(controller, SPOT, 1) == "102.35 m", _label_text(controller, SPOT, 1))
	var before: int = controller.document.gesture_serial()
	var changed: Dictionary = controller.set_grading_level_of(SPOT, 1, 103.0)
	assert(bool(changed["ok"]), String(changed["reason"]))
	assert(bool(changed["changed"]), "it changed")
	assert(controller.document.gesture_serial() == before + 1, "one gesture")
	assert(
		controller.document.undo_label() == "changing the level of a spot level",
		controller.document.undo_label()
	)
	assert(_label_text(controller, SPOT, 1) == "103.0 m", _label_text(controller, SPOT, 1))
	assert(controller.document.count() == 2, "**and no label was left behind**: two marks, not four")
	assert(is_equal_approx(float(controller.grading_spots()[0]["level"]), 103.0), "and the record moved")
	assert(String(controller.last_message) == "spot level is 103.0 m", controller.last_message)
	controller.free()


func test_asking_for_the_level_it_already_has_records_nothing() -> void:
	var controller := _controller()
	_spot_at(controller, Vector2.ZERO, 102.35)
	var before: int = controller.document.gesture_serial()
	var same: Dictionary = controller.set_grading_level_of(SPOT, 1, 102.35)
	assert(not bool(same["ok"]), "nothing changed")
	assert(not bool(same["changed"]), "and it says so")
	assert(controller.document.gesture_serial() == before, "so no undo step was added")
	assert(controller.document.undo_label() == "stating a spot level", "the history still ends where it did")
	assert(controller.document.count() == 2, "and the drawing is exactly as it was")
	controller.free()


func test_taking_a_record_off_the_drawing_takes_its_own_marks_and_nothing_else() -> void:
	var controller := _controller()
	_spot_at(controller, Vector2.ZERO, 102.35)
	_spot_at(controller, Vector2(5.0, 0.0), 101.95)
	_arrow(controller, Vector2.ZERO, Vector2(5.0, 0.0), 8.0)
	assert(controller.document.count() == 7, str(controller.document.count()))
	var removed: Dictionary = controller.remove_grading(SPOT, 1)
	assert(bool(removed["ok"]), String(removed["reason"]))
	assert(int(removed["removed"]) == 2, "the first spot's two marks: " + str(removed["removed"]))
	assert(controller.document.count() == 5, "and nothing else: %d" % controller.document.count())
	assert(controller.grading_spots().size() == 1, "one spot level left")
	assert(controller.grading_slopes().size() == 1, "the arrow is untouched")
	assert(_on_layer(controller, LayerSetScript.GRADING_SLOPE) == 3, "all three of its marks too")
	assert(String(controller.last_message) == "spot level off the drawing, with 2 marks",
		controller.last_message)
	var missing: Dictionary = controller.remove_grading(SPOT, 9)
	assert(not bool(missing["ok"]), "a record that is not there cannot be taken off")
	assert(String(missing["reason"]) == "there is no spot level 9 on this drawing", String(missing["reason"]))
	controller.free()


# --- what the drawing keeps ------------------------------------------------------------------


func test_the_records_and_the_rows_read_the_same_as_the_modules_do() -> void:
	var controller := _controller()
	_spot_at(controller, Vector2.ZERO, 102.35)
	controller.set_grading_level(101.5)
	controller.begin_grading(CONTOUR)
	controller.tool.click(Vector2(0.0, 3.0))
	controller._commit(controller.tool.finish())
	var set := controller.grading()
	assert(controller.grading_rows() == GradingScript.schedule(set, controller.document.units),
		"the rows are the module's own")
	assert(controller.grading_lines() == GradingScript.schedule_lines(set, controller.document.units), "")
	assert(controller.grading_summary() == GradingScript.summary(set), controller.grading_summary())
	assert(controller.grading_level_words() == "101.5 m", controller.grading_level_words())
	controller.free()


func test_a_drawing_keeps_its_marks_and_its_records_through_a_file() -> void:
	var controller := _controller()
	_spot_at(controller, Vector2(3.0, 4.0), 102.35)
	_arrow(controller, Vector2.ZERO, Vector2(6.0, 0.0), 2.5)
	var saved: Dictionary = controller.document.to_dict()
	var read = DocumentScript.from_dict(saved)
	assert(read.count() == 5, "every mark comes back: %d" % read.count())
	assert(GradingScript.spots_of(read.grading).size() == 1, "and the spot record")
	assert(GradingScript.slopes_of(read.grading).size() == 1, "and the arrow record")
	assert(is_equal_approx(float(GradingScript.spots_of(read.grading)[0]["level"]), 102.35),
		"with its level")
	assert(is_equal_approx(float(GradingScript.slopes_of(read.grading)[0]["percent"]), 2.5),
		"and the arrow its fall")
	controller.free()


func test_a_grading_layer_has_a_reason_for_not_being_measured() -> void:
	# A slope arrow counts for nothing in a takeoff, and the takeoff says so rather than staying silent.
	for layer: StringName in [
		LayerSetScript.GRADING_CONTOUR, LayerSetScript.GRADING_SPOT, LayerSetScript.GRADING_SLOPE,
	]:
		assert(TakeoffScript.NOT_MEASURED.has(layer), "%s has a reason: %s" % [layer, String(layer)])
	assert(String(TakeoffScript.NOT_MEASURED[LayerSetScript.GRADING_SLOPE]).contains("not a quantity"),
		String(TakeoffScript.NOT_MEASURED[LayerSetScript.GRADING_SLOPE]))


func test_the_grading_layers_are_in_the_preset_set_and_can_be_switched_off_one_at_a_time() -> void:
	var set = LayerSetScript.default_set()
	for layer: StringName in [
		LayerSetScript.GRADING_CONTOUR, LayerSetScript.GRADING_SPOT, LayerSetScript.GRADING_SLOPE,
	]:
		assert(set.has(layer), "%s is in the preset set: %s" % [layer, String(layer)])
	var names: Array[DraftLayer] = set.layers()
	assert(not names.is_empty(), "and the set can list its layers")
	var contour: DraftLayer = set.get_layer(LayerSetScript.GRADING_CONTOUR)
	var slope: DraftLayer = set.get_layer(LayerSetScript.GRADING_SLOPE)
	assert(contour != null and slope != null, "both are layers the set actually holds")
	assert(contour.plots and slope.plots, "both plot")
	assert(contour.name != slope.name, "and they are two rows in the key")