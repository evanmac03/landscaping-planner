extends Node
## The question asked before work is thrown away, and the two answers to it.
##
## Driven through the HUD's own handlers rather than through a dialog, because a `Window` cannot be
## shown in a headless test - and because what the dialog *does* is emit `confirmed` or `canceled`,
## which are exactly the two methods called here. The dialog's own rendering and a real click on it
## were verified live with the mouse.
##
## Neither node is added to the tree, so no `_ready` runs: nothing needs wiring, no dialog is
## built, and no error is pushed for a HUD with no view controller.

const HudScript := preload("res://scripts/hud.gd")
const ControllerScript := preload("res://scripts/draft/draft_controller.gd")
const DocumentScript := preload("res://scripts/draft/draft_document.gd")
const SnapScript := preload("res://scripts/draft/snap_engine.gd")
const EntityScript := preload("res://scripts/draft/draft_entity.gd")
const LayerSetScript := preload("res://scripts/draft/layer_set.gd")
const StoreScript := preload("res://scripts/draft/drawing_store.gd")

const SCRATCH := "user://drawings/test-guard.json"


## A drawing with something in it and no scene around it. `dirty` is set the way the scene sets it:
## by the document saying it changed.
func _drawn(count: int = 1) -> DraftController:
	var controller := ControllerScript.new()
	controller.document = DocumentScript.new()
	controller.document.changed.connect(controller._on_document_changed)
	# `open_drawing` binds the snap index and disconnects the document's signal, so both have to be
	# there for the same reason they are there in the scene.
	controller.snap = SnapScript.new()
	controller.snap.bind(controller.document.entities())
	for index in count:
		controller.document.add(
			EntityScript.make_line(Vector2(0, index), Vector2(4, 2 + index)), LayerSetScript.NEW_HARDSCAPE
		)
	return controller


func _hud_for(controller: DraftController) -> Node:
	var hud := HudScript.new()
	hud._draft = controller
	return hud


func _clean() -> void:
	if FileAccess.file_exists(SCRATCH):
		DirAccess.remove_absolute(SCRATCH)


func test_a_dirty_drawing_is_something_worth_asking_about() -> void:
	var controller := _drawn()
	assert(controller.dirty, "drawing in it makes it unsaved")
	assert(controller.document.count() == 1)
	var clean_case := ControllerScript.new()
	clean_case.document = DocumentScript.new()
	assert(not clean_case.dirty, "an untouched drawing is not")
	controller.free()
	clean_case.free()


func test_discarding_does_what_the_question_was_asked_about() -> void:
	# "Discard" is the answer that loses work, so it is the one that has to run the action that was
	# interrupted rather than merely close.
	var controller := _drawn()
	var hud := _hud_for(controller)
	hud._pending_action = &"new"
	hud._on_discard_confirmed()
	assert(controller.document.count() == 0, "the drawing was thrown away")
	assert(not controller.dirty, "and the new one is not dirty")
	assert(hud._pending_action == &"", "and the question is over")
	hud.free()
	controller.free()


func test_closing_the_question_runs_nothing_and_forgets_the_action() -> void:
	# The other answer. A question left armed would fire on whatever the next click happened to be.
	var controller := _drawn()
	var hud := _hud_for(controller)
	hud._pending_action = &"new"
	hud._pending_path = SCRATCH
	hud._on_discard_cancelled()
	assert(controller.document.count() == 1, "the drawing is still there")
	assert(controller.dirty, "and still unsaved")
	assert(hud._pending_action == &"", "the action is dropped")
	assert(hud._pending_path == "", "and so is the path it was going to use")
	hud.free()
	controller.free()


func test_an_answer_to_a_question_that_is_no_longer_asked_is_harmless() -> void:
	# A dialog can be closed twice, and a stale answer must not be a command.
	var controller := _drawn()
	var hud := _hud_for(controller)
	hud._pending_action = &""
	hud._on_discard_confirmed()
	assert(controller.document.count() == 1, "nothing happened")
	assert(controller.drawing_path == "", "and nothing was opened")
	hud.free()
	controller.free()


func test_discarding_then_opening_opens_the_drawing_that_was_asked_for() -> void:
	# The guard sits in front of Open as well as New, and the path it was told to open has to
	# survive the question - otherwise "yes, discard" would answer by opening nothing.
	_clean()
	var writer := _drawn(3)
	var written: Dictionary = StoreScript.write(writer.document, SCRATCH)
	assert(bool(written["ok"]), String(written["reason"]))
	writer.free()
	var controller := _drawn()
	var hud := _hud_for(controller)
	hud._pending_action = &"open"
	hud._pending_path = SCRATCH
	hud._on_discard_confirmed()
	assert(controller.document.count() == 3, "the drawing that was asked for is open")
	assert(controller.drawing_path == SCRATCH, "and the drawing knows where it came from")
	assert(hud._pending_path == "", "the path is consumed rather than kept")
	hud.free()
	controller.free()
	_clean()


func test_an_action_that_means_nothing_does_nothing() -> void:
	# `&"quit"` is deliberately not covered: it calls `get_tree().quit()`, which would end the run
	# that is testing it. What is covered is that an id nothing recognises is not a command.
	var controller := _drawn()
	var hud := _hud_for(controller)
	hud._run_pending(&"open-something-else")
	assert(controller.document.count() == 1, "nothing happened")
	assert(controller.drawing_path == "", "and no drawing was opened")
	hud.free()
	controller.free()


func test_with_nothing_to_ask_with_the_action_is_not_blocked() -> void:
	# The scene always builds the dialog, so this is the "cannot ask" fallback: refusing to act
	# because the question could not be put is worse than acting, and it is what a HUD with no
	# dialog does. The question itself is built in `_ready`, so this test has none.
	var controller := _drawn()
	var hud := _hud_for(controller)
	assert(hud._discard_dialog == null, "this HUD has no dialog, which is the case being tested")
	hud._guard_unsaved(&"new")
	assert(controller.document.count() == 0, "the action ran rather than being stuck behind a question")
	hud.free()
	controller.free()