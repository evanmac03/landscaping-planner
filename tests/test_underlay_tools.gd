extends Node
## A picture under the drawing, joined to the drawing.
##
## The reader and the arithmetic are tested on their own in `test_raster_underlay.gd`; this is the part
## that only exists once the two are put together - where a picture lands, that taking one on is one
## undo step, that changing one is one gesture and changing nothing is no gesture at all, and that a
## picture is a record the drawing keeps rather than geometry it holds.
##
## That last claim is the whole design and it is asserted rather than described: a picture under the
## drawing leaves the entity count alone, the plot set alone and the drawing's own bounding box alone.
## A tracing aid that moved the drawing's extent would move the plot scale with it.

const ControllerScript := preload("res://scripts/draft/draft_controller.gd")
const DocumentScript := preload("res://scripts/draft/draft_document.gd")
const SnapScript := preload("res://scripts/draft/snap_engine.gd")
const EntityScript := preload("res://scripts/draft/draft_entity.gd")
const LayerSetScript := preload("res://scripts/draft/layer_set.gd")
const RasterUnderlayScript := preload("res://scripts/draft/raster_underlay.gd")

const PREFIX := "test-"
const SCRATCH := "user://drawings/test-underlay.json"


# --- helpers --------------------------------------------------------------------------


## A picture on disk, under a name this file owns. 64 by 32, so its proportion is a half and a width
## of 12 lies 6 deep.
func _source(name: String, width: int = 64, height: int = 32) -> String:
	RasterUnderlayScript.ensure_dir()
	var path := RasterUnderlayScript.DIR.path_join(PREFIX + name + ".png")
	var image := Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.2, 0.4, 0.6, 1.0))
	image.save_png(path)
	return path


func _notes(name: String) -> String:
	RasterUnderlayScript.ensure_dir()
	var path := RasterUnderlayScript.DIR.path_join(PREFIX + name + ".txt")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string("a list of things to buy, long enough to have a header worth reading")
		file.close()
	return path


## A controller with a drawing on it and no scene around it: nothing here enters a tree, so no `_ready`
## runs and no window is ever shown.
func _controller(count: int = 1) -> DraftController:
	var controller := ControllerScript.new()
	controller.document = DocumentScript.new()
	controller.document.changed.connect(controller._on_document_changed)
	controller.snap = SnapScript.new()
	controller.snap.bind(controller.document.entities())
	for index in count:
		controller.document.add(
			EntityScript.make_line(Vector2(0, index), Vector2(4, 2 + index)), LayerSetScript.NEW_HARDSCAPE
		)
	return controller


## What this file has made, so a test can say what it must end with. Narrow on purpose: a picture a
## person actually kept is not this file's to remove.
func _mine() -> Array[String]:
	var out: Array[String] = []
	for path: String in RasterUnderlayScript.list():
		if path.get_file().begins_with(PREFIX):
			out.append(path)
	return out


func _clean() -> void:
	for path: String in _mine():
		DirAccess.remove_absolute(path)
	if FileAccess.file_exists(SCRATCH):
		DirAccess.remove_absolute(SCRATCH)


# --- taking a picture on ---------------------------------------------------------------


func test_a_picture_goes_under_the_drawing_without_becoming_geometry() -> void:
	_clean()
	var controller := _controller(1)
	var entities := controller.document.count()
	var plot_set := controller.document.plotting_entities().size()
	var extent: Rect2 = controller.document.bounds()
	var taken: Dictionary = controller.place_underlay(_source("scan"), 12.0)
	assert(bool(taken["ok"]), String(taken["reason"]))
	assert(int(taken["id"]) == 1, str(taken["id"]))
	assert(controller.underlays().size() == 1, str(controller.underlays().size()))
	var picture: Dictionary = controller.underlays()[0]
	assert(is_equal_approx(float(picture["width_m"]), 12.0), str(picture["width_m"]))
	assert(is_equal_approx(RasterUnderlayScript.height_of(picture), 6.0), "12 across, half as deep")
	assert(
		is_equal_approx(float(picture["opacity"]), RasterUnderlayScript.DEFAULT_OPACITY),
		"and see-through enough to trace over"
	)
	assert(FileAccess.file_exists(String(picture["path"])), "a copy is kept beside the drawing")
	assert(
		String(picture["path"]).begins_with(RasterUnderlayScript.DIR),
		"and it is in the drawing's own folder rather than where it was found: " + String(picture["path"])
	)
	assert(controller.dirty, "the drawing has unsaved work now")
	assert(String(taken["message"]).contains("under the drawing"), String(taken["message"]))
	# The three claims that make a picture a picture rather than linework.
	assert(controller.document.count() == entities, "a picture is not an entity")
	assert(controller.document.plotting_entities().size() == plot_set, "and it never plots")
	assert(controller.document.bounds() == extent, "and it does not move the drawing's own extent")
	controller.free()
	_clean()


func test_a_picture_lands_on_the_middle_of_the_drawing() -> void:
	_clean()
	# A line from (0,0) to (4,2): its middle is (2,1), and that is where a tracing aid belongs.
	var controller := _controller(1)
	controller.place_underlay(_source("centred"), 10.0)
	var picture: Dictionary = controller.underlays()[0]
	assert(is_equal_approx(float(picture["x"]), 2.0), str(picture["x"]))
	assert(is_equal_approx(float(picture["z"]), 1.0), str(picture["z"]))
	# And it can be told otherwise.
	controller.place_underlay(_source("placed"), 10.0, {"at": Vector2(-3.0, 7.0)})
	var second: Dictionary = controller.underlays()[1]
	assert(is_equal_approx(float(second["x"]), -3.0), str(second["x"]))
	assert(is_equal_approx(float(second["z"]), 7.0), str(second["z"]))
	controller.free()
	# A drawing with nothing on it has no middle to speak of, so the origin is the answer rather than
	# a guess at where the site is.
	var empty := _controller(0)
	empty.place_underlay(_source("empty-sheet"), 20.0)
	var first: Dictionary = empty.underlays()[0]
	assert(float(first["x"]) == 0.0 and float(first["z"]) == 0.0, "an empty drawing lands at the origin")
	empty.free()
	_clean()


func test_taking_a_picture_on_is_one_undo_step() -> void:
	_clean()
	var controller := _controller(1)
	var before := controller.document.gesture_serial()
	controller.place_underlay(_source("undoable"), 10.0)
	assert(controller.document.gesture_serial() == before + 1, "one act, one gesture")
	assert(controller.document.undo_label() == "putting a picture under the drawing", controller.document.undo_label())
	assert(controller.document.undo_last(), "and it comes back off")
	assert(controller.underlays().is_empty(), "with nothing under the drawing")
	assert(controller.document.redo_last(), "and goes back on")
	assert(controller.underlays().size() == 1, str(controller.underlays().size()))
	controller.free()
	_clean()


func test_a_file_that_is_not_a_picture_never_reaches_the_drawing() -> void:
	_clean()
	var controller := _controller(1)
	var refused: Dictionary = controller.place_underlay(_notes("shopping"), 10.0)
	assert(not bool(refused["ok"]), "a notes file is not a picture")
	assert(String(refused["reason"]).contains("is not a picture this can read"), String(refused["reason"]))
	assert(controller.underlays().is_empty(), "nothing is under the drawing")
	assert(controller.document.count() == 1, "and nothing was drawn")
	# The notes file itself is the one file this made in the drawing's folder: a refusal copies nothing,
	# so a folder of tracing aids cannot fill up with files the app cannot draw.
	assert(_mine().size() == 1, "and no copy was kept: %s" % str(_mine()))
	controller.free()
	_clean()


func test_a_picture_with_no_width_on_the_ground_is_refused_by_name() -> void:
	_clean()
	var controller := _controller(1)
	var kept: Dictionary = RasterUnderlayScript.keep(_source("nowidth"), PREFIX + "nowidth-copy")
	assert(bool(kept["ok"]), String(kept["reason"]))
	var record: Dictionary = RasterUnderlayScript.from_kept(kept, 10.0)
	assert(not record.is_empty(), "a picture with a width is a picture")
	var refused: Dictionary = controller.place_underlay(String(record["path"]), 0.0)
	assert(not bool(refused["ok"]), "nothing across is not a size")
	assert(String(refused["reason"]) == "a picture has to be more than nothing across", String(refused["reason"]))
	# And the same refusal arrives from the other door, where the width is set on the record itself.
	var stated: Dictionary = controller.take_on_picture(record, {"width_m": 0.0})
	assert(not bool(stated["ok"]), "a form left blank is refused too")
	assert(String(stated["reason"]) == "a picture has to be more than nothing across", String(stated["reason"]))
	var unreadable: Dictionary = controller.take_on_picture(record, {"width_m": NAN})
	assert(not bool(unreadable["ok"]), "and so is a width that is not a number")
	assert(String(unreadable["reason"]) == "the width across the ground is not a number", String(unreadable["reason"]))
	assert(controller.underlays().is_empty(), "and nothing reached the drawing either way")
	controller.free()
	_clean()


# --- changing one ----------------------------------------------------------------------


func test_changing_a_picture_is_one_gesture_and_changing_nothing_is_no_gesture() -> void:
	_clean()
	var controller := _controller(1)
	var id := int(controller.place_underlay(_source("changed"), 10.0)["id"])
	var after_placing := controller.document.gesture_serial()
	var widened: Dictionary = controller.change_underlay(id, {"width_m": 25.0})
	assert(bool(widened["changed"]), "a new width is a change")
	assert(is_equal_approx(float(controller.underlays()[0]["width_m"]), 25.0), str(controller.underlays()[0]["width_m"]))
	assert(controller.document.gesture_serial() == after_placing + 1, "one change, one gesture")
	# The same numbers again: the gesture is what would be wrong, not the change.
	var again: Dictionary = controller.change_underlay(id, {"width_m": 25.0})
	assert(bool(again["ok"]), String(again["reason"]))
	assert(not bool(again["changed"]), "the same width is not a change")
	assert(
		controller.document.gesture_serial() == after_placing + 1,
		"so no undo step that puts back what is already there: %d" % controller.document.gesture_serial()
	)
	var nowhere: Dictionary = controller.change_underlay(99, {"width_m": 5.0})
	assert(not bool(nowhere["ok"]), "and a picture that is not there cannot be changed")
	assert(String(nowhere["reason"]).contains("no picture 99"), String(nowhere["reason"]))
	controller.free()
	_clean()


func test_a_picture_can_be_turned_moved_and_made_see_through() -> void:
	_clean()
	var controller := _controller(1)
	var id := int(controller.place_underlay(_source("moved"), 10.0)["id"])
	var changed: Dictionary = controller.change_underlay(id, {
		"rotation_deg": 90.0, "opacity": 0.25, "at": Vector2(6.0, -4.0),
	})
	assert(bool(changed["changed"]), String(changed["reason"]))
	var picture: Dictionary = controller.underlays()[0]
	assert(is_equal_approx(float(picture["rotation_deg"]), 90.0), str(picture["rotation_deg"]))
	assert(is_equal_approx(float(picture["opacity"]), 0.25), str(picture["opacity"]))
	assert(is_equal_approx(float(picture["x"]), 6.0) and is_equal_approx(float(picture["z"]), -4.0), str(picture))
	# A quarter turn swaps which way round it lies, which is what the row's words have to agree with.
	var box: Rect2 = RasterUnderlayScript.bounds_of(picture)
	assert(is_equal_approx(box.size.x, 5.0) and is_equal_approx(box.size.y, 10.0), str(box.size))
	var rows := controller.underlay_rows()
	assert(rows.size() == 1, str(rows.size()))
	assert(int(rows[0]["id"]) == id, str(rows[0]))
	assert(String(rows[0]["text"]).contains("turned 90.0 degrees"), String(rows[0]["text"]))
	assert(String(rows[0]["text"]).contains("25% opaque"), String(rows[0]["text"]))
	assert(bool(rows[0]["usable"]), "and it can be drawn")
	# And it can be put away without being thrown away.
	var hidden: Dictionary = controller.change_underlay(id, {"visible": false})
	assert(bool(hidden["changed"]), String(hidden["reason"]))
	assert(not bool(hidden["picture"]["visible"]), "a picture can be hidden")
	assert(controller.document.underlays.size() == 1, "and is still kept")
	assert(controller.document.visible_underlays().is_empty(), "but is not drawn")
	controller.free()
	_clean()


func test_taking_a_picture_off_keeps_its_copy_and_can_be_undone() -> void:
	_clean()
	var controller := _controller(1)
	var id := int(controller.place_underlay(_source("removed"), 10.0)["id"])
	var path := String(controller.underlays()[0]["path"])
	assert(controller.remove_underlay(id), "it comes off the drawing")
	assert(controller.underlays().is_empty(), "with nothing left under it")
	assert(FileAccess.file_exists(path), "and its copy stays, because an undo has to be able to put it back")
	assert(controller.document.undo_last(), "which it can")
	assert(controller.underlays().size() == 1, str(controller.underlays().size()))
	assert(not controller.remove_underlay(99), "and a picture that is not there cannot be taken off")
	controller.free()
	_clean()


func test_a_picture_whose_file_has_gone_is_still_kept_but_is_not_usable() -> void:
	_clean()
	var controller := _controller(1)
	var id := int(controller.place_underlay(_source("vanished"), 10.0)["id"])
	var picture: Dictionary = controller.underlays()[0]
	DirAccess.remove_absolute(String(picture["path"]))
	var rows := controller.underlay_rows()
	assert(rows.size() == 1, "the drawing still knows about it")
	assert(not bool(rows[0]["usable"]), "but it cannot be drawn")
	assert(String(rows[0]["text"]).contains("no longer at"), String(rows[0]["text"]))
	var again: Dictionary = controller.take_on_picture(controller.underlays()[0], {"width_m": 8.0})
	assert(not bool(again["ok"]), "and it cannot be taken on again either")
	assert(controller.document.underlays.size() == 1, "no half-made second copy of it")
	assert(controller.remove_underlay(id), "though it can still be taken off the drawing")
	controller.free()
	_clean()


func test_the_summary_says_what_is_under_the_drawing() -> void:
	_clean()
	var controller := _controller(0)
	assert(controller.underlay_summary() == "nothing is under this drawing", controller.underlay_summary())
	controller.place_underlay(_source("one"), 10.0)
	assert(controller.underlay_summary() == "1 picture under the drawing", controller.underlay_summary())
	controller.place_underlay(_source("two"), 10.0)
	assert(controller.underlay_summary() == "2 pictures under the drawing", controller.underlay_summary())
	controller.free()
	_clean()


# --- what the file keeps ----------------------------------------------------------------


func test_what_is_under_the_drawing_is_written_down_and_read_back() -> void:
	_clean()
	var controller := _controller(1)
	var id := int(controller.place_underlay(_source("saved"), 12.0)["id"])
	controller.change_underlay(id, {"rotation_deg": 30.0, "opacity": 0.5})
	var saved: Dictionary = controller.document.to_dict()
	assert(int(saved["version"]) == 9, "version 9 is the one that states the pictures: %d" % int(saved["version"]))
	assert(saved.has("underlays"), "and they are written out")
	var loaded: DraftDocument = DocumentScript.from_dict(JSON.parse_string(JSON.stringify(saved)))
	assert(loaded.underlays.size() == 1, str(loaded.underlays.size()))
	var back: Dictionary = loaded.underlays[0]
	assert(int(back["id"]) == id, str(back))
	assert(is_equal_approx(float(back["width_m"]), 12.0), str(back["width_m"]))
	assert(is_equal_approx(float(back["rotation_deg"]), 30.0), str(back["rotation_deg"]))
	assert(is_equal_approx(float(back["opacity"]), 0.5), str(back["opacity"]))
	assert(String(back["path"]) == String(controller.underlays()[0]["path"]), String(back["path"]))
	assert(is_equal_approx(RasterUnderlayScript.height_of(back), 6.0), "and it lies the same size")
	# A file written before pictures existed: no pictures at all, rather than one drawn from nothing.
	var older: Dictionary = controller.document.to_dict()
	older.erase("underlays")
	older["version"] = 8
	var legacy: DraftDocument = DocumentScript.from_dict(older)
	assert(legacy.underlays.is_empty(), "a drawing nobody has traced over has nothing under it")
	controller.free()
	_clean()


func test_a_second_picture_gets_its_own_number_even_across_a_save() -> void:
	_clean()
	var controller := _controller(0)
	var first := int(controller.place_underlay(_source("n1"), 10.0)["id"])
	var second := int(controller.place_underlay(_source("n2"), 10.0)["id"])
	assert(second == first + 1, "%d then %d" % [first, second])
	var loaded: DraftDocument = DocumentScript.from_dict(controller.document.to_dict())
	loaded.add_underlay({"path": "user://underlays/test-n3.png", "width_m": 5.0, "width_px": 4, "height_px": 2})
	assert(
		int(loaded.underlays[2]["id"]) == second + 1,
		"a loaded drawing carries on from where it left off: %s" % str(loaded.underlays[2])
	)
	controller.free()
	_clean()