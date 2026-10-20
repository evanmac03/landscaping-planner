extends Node
## The revision log as the controller runs it, and the file it lives in: recording a revision of a
## real drawing, finding it again when the drawing is opened, and putting an earlier one back.
##
## The controller is built with its parts but no scene tree, as the sheet and fill tests are. The
## file these tests touch is `user://revisions`, and each of them takes its own away again.

const Ctrl := preload("res://scripts/draft/draft_controller.gd")
const Tool := preload("res://scripts/draft/draft_tool.gd")
const Document := preload("res://scripts/draft/draft_document.gd")
const SnapScript := preload("res://scripts/draft/snap_engine.gd")
const Entity := preload("res://scripts/draft/draft_entity.gd")
const LayerSet := preload("res://scripts/draft/layer_set.gd")
const StoreScript := preload("res://scripts/draft/drawing_store.gd")
const LogScript := preload("res://scripts/draft/revision_log.gd")

const SCRATCH := "user://drawings/test-revisions-scratch.json"


func _controller():
	var controller = Ctrl.new()
	controller.document = Document.new()
	controller.snap = SnapScript.new()
	controller.tool = Tool.new()
	return controller


func _with_a_bed():
	var controller = _controller()
	controller.document.add(
		Entity.make_rectangle(Vector2(0.0, 0.0), Vector2(12.0, 8.0)), LayerSet.NEW_BED
	)
	return controller


## A history is a file in the user's folder, so a test takes it away again: one left behind is a file
## nobody asked for, and worse, it would be read by the *next* test to use the same name.
func _clean() -> void:
	StoreScript.ensure_dir()
	for path: String in [SCRATCH, StoreScript.revisions_path(SCRATCH)]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


# --- where a history lives -------------------------------------------------------------


func test_a_history_is_kept_beside_the_drawings_and_not_among_them() -> void:
	# The same decision as the recent list, for the same reason: the file dialogs open on the drawings
	# folder, so a file kept there is one a person is offered as a drawing and can save over.
	var path: String = StoreScript.revisions_path(SCRATCH)
	assert(path.begins_with(StoreScript.REVISIONS_DIR), path)
	assert(not path.begins_with(StoreScript.DIR + "/"), path)
	assert(path.ends_with(".json"))
	assert(path.get_file() == "test-revisions-scratch.json", "named after the drawing: %s" % path.get_file())
	# And a drawing with no name yet has nowhere to keep one rather than a history filed under "".
	assert(StoreScript.revisions_path("") == "")


func test_a_history_file_is_never_offered_as_a_drawing() -> void:
	_clean()
	var controller = _with_a_bed()
	assert(bool(controller.save_drawing(SCRATCH)["ok"]))
	controller.capture_revision("sent to the client")
	var history: String = StoreScript.revisions_path(SCRATCH)
	assert(FileAccess.file_exists(history), "the history is written when a revision is recorded")
	for listed: String in StoreScript.list_drawings():
		assert(listed != history, "the folder shows drawings only, and %s is not one" % history)
	controller.free()
	_clean()


# --- keeping and finding a history ------------------------------------------------------


func test_a_history_survives_the_file() -> void:
	_clean()
	var controller = _with_a_bed()
	assert(bool(controller.save_drawing(SCRATCH)["ok"]))
	controller.capture_revision("sent to the client")
	controller.document.add(
		Entity.make_circle(Vector2(2.0, 3.0), 1.5), LayerSet.NEW_PLANTING
	)
	controller.capture_revision("client asked for a tree")
	assert(controller.revisions.count() == 2)
	controller.free()

	# A different controller opens the same file, which is what a second visit to the drawing is.
	var reopened = _controller()
	assert(reopened.open_drawing(SCRATCH), reopened.last_message)
	assert(reopened.revisions.count() == 2, "the history came with the drawing")
	assert(reopened.revisions.messages() == ["sent to the client", "client asked for a tree"],
		str(reopened.revisions.messages()))
	assert(reopened.revisions.record_at(1)["shapes"] == 2, "and the drawing it held")
	# What is on the drawing is what was *saved*, not what was last recorded - and here the two differ on
	# purpose: the tree was added and recorded after the last save. A history is read, never applied: the
	# moment opening a drawing put an earlier revision on screen the file would be lying about itself.
	assert(reopened.document.count() == 1, "opening a drawing does not restore its history")
	assert(reopened.revisions.record_at(1)["shapes"] == 2, "though a revision of it holds more")
	assert(reopened.dirty == false, "and the drawing matches the file it came from")
	reopened.free()
	_clean()


func test_a_revision_recorded_before_the_drawing_had_a_name_is_kept_when_it_is_saved() -> void:
	_clean()
	var controller = _with_a_bed()
	# Nothing is lost by recording before the first save: the designer has done their part and the file
	# name is a separate errand, so the revision waits in memory and the message says where it is.
	var record: Dictionary = controller.capture_revision("the first idea")
	assert(controller.revisions.count() == 1)
	assert(int(record["shapes"]) == 1)
	assert(controller.last_message.contains("in memory only"), controller.last_message)
	assert(controller.drawing_path == "")
	# Saving is the moment it has somewhere to go.
	assert(bool(controller.save_drawing(SCRATCH)["ok"]))
	assert(FileAccess.file_exists(StoreScript.revisions_path(SCRATCH)))
	controller.free()

	var reopened = _controller()
	assert(reopened.open_drawing(SCRATCH))
	assert(reopened.revisions.messages() == ["the first idea"], str(reopened.revisions.messages()))
	reopened.free()
	_clean()


func test_a_new_drawing_begins_with_no_history() -> void:
	_clean()
	var controller = _with_a_bed()
	assert(bool(controller.save_drawing(SCRATCH)["ok"]))
	controller.capture_revision("sent to the client")
	controller.new_drawing()
	assert(controller.revisions.count() == 0, "a new drawing is a new job, not a continuation")
	assert(controller.drawing_path == "")
	# And the drawing that was in hand kept its own history, untouched.
	var reopened = _controller()
	assert(reopened.open_drawing(SCRATCH))
	assert(reopened.revisions.count() == 1)
	reopened.free()
	controller.free()
	_clean()


# --- putting a revision back ------------------------------------------------------------


func test_restoring_a_revision_puts_the_drawing_back_and_the_undo_puts_it_forward() -> void:
	_clean()
	var controller = _with_a_bed()
	assert(bool(controller.save_drawing(SCRATCH)["ok"]))
	# What the client saw.
	controller.capture_revision("sent to the client")
	var seen: int = controller.document.count()
	# And what happened after they saw it.
	controller.document.add(
		Entity.make_circle(Vector2(2.0, 3.0), 1.5), LayerSet.NEW_PLANTING
	)
	controller.capture_revision("a tree added off the cuff")
	assert(controller.document.count() == seen + 1)

	assert(controller.restore_revision(0), controller.last_message)
	assert(controller.document.count() == seen, "the drawing is as the earlier revision had it")
	assert(controller.dirty, "and no longer matches the file, because nothing has been written")
	assert(controller.last_message.begins_with("restored rev 1"), controller.last_message)
	# A designer who restores the wrong revision must be able to get back the drawing they had a moment
	# before: restoring is a change like any other and goes on the undo stack.
	assert(controller.document.undo_last(), "the drawing that was replaced can be put back")
	assert(controller.document.count() == seen + 1, "which is the drawing with the tree in it")
	controller.free()
	_clean()


func test_a_revision_that_is_not_there_cannot_be_restored() -> void:
	var controller = _with_a_bed()
	var before: int = controller.document.count()
	assert(not controller.restore_revision(7))
	assert(controller.last_message == "there is no such revision", controller.last_message)
	assert(controller.document.count() == before, "and the drawing is left alone")
	assert(not controller.dirty)
	controller.free()


func test_the_rows_a_list_shows_carry_what_changed() -> void:
	_clean()
	var controller = _with_a_bed()
	assert(bool(controller.save_drawing(SCRATCH)["ok"]))
	controller.capture_revision("the first idea")
	controller.document.add(
		Entity.make_circle(Vector2(2.0, 3.0), 1.5), LayerSet.NEW_PLANTING
	)
	controller.capture_revision("a tree added")
	var rows: Array[Dictionary] = controller.revision_rows()
	assert(rows.size() == 2)
	assert(String(rows[0]["description"]).begins_with("rev 1  the first idea"), str(rows[0]["description"]))
	# The first revision has nothing before it, so there is nothing to say about how it changed - which
	# is different from saying nothing changed, and a list that showed "0 added" for it would be lying.
	assert(String(rows[0]["change"]) == "", str(rows[0]["change"]))
	assert(String(rows[1]["change"]).begins_with("1 added"), str(rows[1]["change"]))
	assert(int(rows[1]["shapes"]) == 2)
	controller.free()
	_clean()


func test_a_drawing_that_was_never_recorded_opens_with_an_empty_history() -> void:
	_clean()
	var controller = _with_a_bed()
	assert(bool(controller.save_drawing(SCRATCH)["ok"]))
	controller.capture_revision("")  # a revision, so a history file exists
	controller.free()

	# A drawing with no history file at all reads as a history with nothing in it rather than refusing
	# to open: every drawing is unrecorded to begin with.
	DirAccess.remove_absolute(StoreScript.revisions_path(SCRATCH))
	var reopened = _controller()
	assert(reopened.open_drawing(SCRATCH), reopened.last_message)
	assert(reopened.revisions.count() == 0)
	assert(reopened.revisions.record_at(0).is_empty())
	assert(LogScript.describe_diff(reopened.revisions.diff(0, 0)) == "there is no such revision")
	reopened.free()
	_clean()