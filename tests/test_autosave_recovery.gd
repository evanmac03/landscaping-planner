extends Node
## The copy kept in case the program stops, joined to the drawing and to the menu.
##
## The module is tested on its own in `test_autosave.gd`; this is the part that only exists when the
## three are put together - when a copy is kept, what a drawing being saved or left behind does to the
## copy that was kept of it, and the two answers to the question a session that ended without saving
## leaves behind.
##
## Neither node is added to the tree, so no `_ready` runs: no dialog is built, no button is focused, and
## no error is pushed for a HUD with no view controller. The question itself is driven through the
## handlers its two answers call, because a `Window` cannot be shown in a headless test.

const HudScript := preload("res://scripts/hud.gd")
const AutosaveScript := preload("res://scripts/draft/autosave.gd")
const StoreScript := preload("res://scripts/draft/drawing_store.gd")
const ControllerScript := preload("res://scripts/draft/draft_controller.gd")
const DocumentScript := preload("res://scripts/draft/draft_document.gd")
const SnapScript := preload("res://scripts/draft/snap_engine.gd")
const EntityScript := preload("res://scripts/draft/draft_entity.gd")
const LayerSetScript := preload("res://scripts/draft/layer_set.gd")

const SCRATCH := "user://drawings/test-autosave-recovery.json"
const ELSEWHERE := "user://drawings/test-autosave-other.json"


## A drawing with `count` shapes on it and no scene around it. `dirty` is set the way the scene sets
## it, by the document saying it changed.
func _drawn(count: int) -> DraftController:
	var controller := ControllerScript.new()
	controller.document = DocumentScript.new()
	controller.document.changed.connect(controller._on_document_changed)
	# `open_drawing` binds the snap index, so it has to be there for the same reason it is there in the
	# scene - a controller that never entered a tree never ran `_ready`.
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


## What a drawing this one is *not* looks like on the way into a copy.
func _foreign_state(count: int) -> Dictionary:
	var other := _drawn(count)
	var state: Dictionary = other.document.to_dict()
	other.free()
	return state


func _clean() -> void:
	AutosaveScript.clear_all()
	for at: String in [SCRATCH, ELSEWHERE]:
		if FileAccess.file_exists(at):
			DirAccess.remove_absolute(at)


## Put a drawing on disk, the way a person having saved it would have.
func _save(document: DraftDocument, at: String) -> Dictionary:
	return StoreScript.write(document, at)


# --- keeping a copy --------------------------------------------------------------------


func test_a_drawing_with_unsaved_work_is_copied_once_the_interval_has_passed() -> void:
	_clean()
	var controller := _drawn(3)
	var hud := _hud_for(controller)
	assert(AutosaveScript.list().is_empty(), "nothing is kept before the drawing has been worked on")
	hud._tick_autosave(1.0)
	assert(AutosaveScript.list().is_empty(), "nor a moment later")
	hud._tick_autosave(AutosaveScript.INTERVAL)
	assert(AutosaveScript.list().size() == 1, "half a minute of work is worth a copy")
	var found: Dictionary = AutosaveScript.read(AutosaveScript.path_for(""))
	assert(int(found["serial"]) == controller.document.gesture_serial(), "the copy knows which gesture it was taken at")
	hud.free()
	controller.free()
	_clean()


func test_a_drawing_with_nothing_on_it_is_not_copied() -> void:
	# Dirty and empty, which is reachable: draw a shape and erase it, and the drawing has been through
	# something without anything being left on the paper.
	_clean()
	var controller := _drawn(0)
	controller.dirty = true
	var hud := _hud_for(controller)
	hud._tick_autosave(900.0)
	assert(AutosaveScript.list().is_empty(), "a copy of nothing is not worth offering back")
	hud.free()
	controller.free()
	_clean()


func test_a_copy_of_the_drawing_in_hand_is_a_backup_and_not_a_rescue() -> void:
	_clean()
	var controller := _drawn(3)
	var hud := _hud_for(controller)
	hud._tick_autosave(AutosaveScript.INTERVAL)
	hud._refresh_pending_recovery()
	assert(AutosaveScript.list().size() == 1, "a copy was kept")
	assert(hud._pending_recovery.is_empty(), "but it is what is already on the screen, not something to rescue")
	# The same identity holding a drawing this one has never been: a gesture it has not been through.
	AutosaveScript.write(_foreign_state(5), "", "", controller.document.gesture_serial() + 4)
	hud._refresh_pending_recovery()
	assert(not hud._pending_recovery.is_empty(), "work from another session is a rescue")
	hud.free()
	controller.free()
	_clean()


# --- the question ----------------------------------------------------------------------


func test_the_work_a_session_left_behind_is_offered_with_what_it_holds() -> void:
	_clean()
	AutosaveScript.write(_foreign_state(4), "", "Backyard Design", 6)
	var controller := _drawn(0)
	var hud := _hud_for(controller)
	hud._refresh_pending_recovery()
	assert(not hud._pending_recovery.is_empty(), "the work is waiting")
	assert(
		String(hud._pending_recovery["project_name"]) == "Backyard Design",
		String(hud._pending_recovery["project_name"])
	)
	assert(hud._recovery_notice() == "unsaved work from an earlier session", hud._recovery_notice())
	assert(
		hud._drawing_state_with_recovery() == "untitled drawing  |  unsaved work from an earlier session",
		hud._drawing_state_with_recovery()
	)
	hud.free()
	controller.free()
	_clean()


func test_recovering_puts_the_work_back_and_takes_the_offer_away() -> void:
	_clean()
	AutosaveScript.write(_foreign_state(4), "", "", 6)
	var controller := _drawn(0)
	var hud := _hud_for(controller)
	hud._refresh_pending_recovery()
	assert(not hud._pending_recovery.is_empty(), "there is something to recover")
	hud._on_recovery_confirmed()
	assert(controller.document.count() == 4, "the work is on the drawing")
	assert(controller.dirty, "and it is unsaved, because the file it belongs to does not hold it")
	assert(controller.last_message.begins_with("recovered "), controller.last_message)
	assert(hud._pending_recovery.is_empty(), "the offer is gone")
	# What came back is an ordinary edit, so the drawing it replaced is one undo away.
	assert(controller.document.gestures.can_undo(), "recovering is one undoable step")
	# And the work is not left unprotected for the half minute until the next copy: a fresh copy of
	# exactly what came back goes down at once.
	assert(AutosaveScript.list().size() == 1, "a fresh copy of the recovered work is kept at once")
	hud.free()
	controller.free()
	_clean()


func test_discarding_takes_the_offer_away_and_removes_the_copy() -> void:
	_clean()
	AutosaveScript.write(_foreign_state(4), "", "", 6)
	var controller := _drawn(0)
	var hud := _hud_for(controller)
	hud._refresh_pending_recovery()
	hud._on_recovery_action(&"discard")
	assert(hud._pending_recovery.is_empty(), "the offer is gone")
	assert(AutosaveScript.list().is_empty(), "and so is the copy, so the question is not asked again")
	hud._refresh_pending_recovery()
	assert(hud._pending_recovery.is_empty(), "reading again does not bring it back")
	assert(controller.document.count() == 0, "and nothing was put on the drawing")
	hud.free()
	controller.free()
	_clean()


func test_closing_the_question_decides_nothing_and_leaves_the_copy() -> void:
	# A dialog's cancel button and its close button are the same signal, so Escaping it must not be the
	# one act that destroys the only copy of somebody's work. Anything that is not the discard action
	# leaves the copy alone.
	_clean()
	AutosaveScript.write(_foreign_state(4), "", "", 6)
	var controller := _drawn(0)
	var hud := _hud_for(controller)
	hud._refresh_pending_recovery()
	for action: StringName in [&"", &"not now", &"recover"]:
		hud._on_recovery_action(action)
		assert(AutosaveScript.list().size() == 1, "the copy is still there after %s" % String(action))
		hud._refresh_pending_recovery()
		assert(not hud._pending_recovery.is_empty(), "and it is still offered")
	assert(controller.document.count() == 0, "and nothing was put on the drawing")
	hud.free()
	controller.free()
	_clean()


# --- what the drawing being saved or left behind does to its copy -----------------------


func test_saving_a_drawing_clears_the_copy_kept_of_it() -> void:
	_clean()
	var controller := _drawn(3)
	var hud := _hud_for(controller)
	hud._tick_autosave(AutosaveScript.INTERVAL)
	assert(AutosaveScript.list().size() == 1, "a copy was kept of the work in hand")
	controller.save_drawing(SCRATCH)
	assert(controller.drawing_path == SCRATCH, controller.drawing_path)
	assert(AutosaveScript.list().is_empty(), "the copy was of work that is now on disk, so it is not a rescue")
	hud.free()
	controller.free()
	_clean()


func test_a_drawing_left_behind_takes_its_copy_with_it() -> void:
	# New and Open both ask before throwing work away, so an abandoned drawing's copy is not work anybody
	# lost - and offering it on the next launch would be offering back something that was deliberately
	# let go of.
	_clean()
	var elsewhere := _drawn(2)
	assert(bool(_save(elsewhere.document, ELSEWHERE)["ok"]), "a drawing to open")
	elsewhere.free()
	var controller := _drawn(3)
	var kept: Dictionary = AutosaveScript.write(controller.document.to_dict(), "", "", 3)
	assert(bool(kept["ok"]), String(kept["reason"]))
	assert(AutosaveScript.list().size() == 1, "the drawing in hand has a copy")
	controller.open_drawing(ELSEWHERE)
	assert(controller.document.count() == 2, "the other drawing is open")
	assert(AutosaveScript.list().is_empty(), "and the copy of the one that was left behind went with it")
	controller.free()
	_clean()


func test_opening_a_drawing_does_not_decide_about_the_copy_of_that_file() -> void:
	# Opening the file says the file is what was wanted; it says nothing about a copy that is newer than
	# the file, so the copy is left for the File menu to offer rather than quietly removed.
	_clean()
	var writer := _drawn(2)
	assert(bool(_save(writer.document, SCRATCH)["ok"]), "a drawing to open")
	var held: Dictionary = writer.document.to_dict()
	writer.free()
	AutosaveScript.write(held, SCRATCH, "", 2)
	assert(AutosaveScript.list().size() == 1, "a copy of the file is waiting")
	var controller := _drawn(0)
	controller.open_drawing(SCRATCH)
	assert(controller.document.count() == 2, "the file is open")
	assert(AutosaveScript.list().size() == 1, "and the copy of it is still waiting")
	controller.free()
	_clean()


# --- the entry and the line -------------------------------------------------------------


func test_the_file_menu_offers_recovering_and_says_when_it_means_something() -> void:
	var found: Dictionary = {}
	for entry: Dictionary in HudScript.file_items():
		if StringName(entry.get("id", &"")) == &"file.recover":
			found = entry
	assert(not found.is_empty(), "the File menu offers recovering unsaved work")
	assert(String(found["label"]) == "Recover unsaved work...", String(found["label"]))
	assert(StringName(found["method"]) == &"_menu_recover_unsaved", String(found["method"]))
	assert(StringName(found["needs"]) == HudScript.NEEDS_DRAFT, "it needs a drawing")
	assert(
		StringName(found["enabled_when"]) == &"recovery",
		"and is switched off until a session that ended without saving has left something"
	)
	assert(HudScript.is_enabled(&"recovery", {"recovery": true}), "a copy waiting switches it on")
	assert(not HudScript.is_enabled(&"recovery", {"recovery": false}), "and none switches it off")
	assert(not HudScript.is_enabled(&"recovery", {}), "nor in a world that says nothing about it")


func test_the_offer_is_read_when_it_can_have_changed_and_not_on_every_frame() -> void:
	# The folder the copies live in is not something a frame may read, so the offer is held in a
	# dictionary refreshed where it can have changed - and the sentence moves when the copy does, rather
	# than leaving a stale description of work that has been replaced.
	_clean()
	AutosaveScript.write(_foreign_state(4), "", "", 6)
	var controller := _drawn(0)
	var hud := _hud_for(controller)
	assert(hud._pending_recovery.is_empty(), "a HUD that has not read the disk is offering nothing")
	assert(hud._recovery_notice() == "", "and the File menu's line says nothing extra")
	hud._refresh_pending_recovery()
	assert(not hud._pending_recovery.is_empty(), "reading finds the work")
	assert(
		String(AutosaveScript.describe(hud._pending_recovery)).ends_with(
			"4 shapes, kept " + AutosaveScript.clock_of(String(hud._pending_recovery["when"]))
		),
		AutosaveScript.describe(hud._pending_recovery)
	)
	AutosaveScript.write(_foreign_state(7), "", "", 11)
	hud._refresh_pending_recovery()
	assert(int(hud._pending_recovery["serial"]) == 11, "the offer is the newest copy")
	assert(
		String(AutosaveScript.describe(hud._pending_recovery)).begins_with("untitled, 7 shapes"),
		AutosaveScript.describe(hud._pending_recovery)
	)
	hud.free()
	controller.free()
	_clean()


func test_a_hud_with_no_drawing_copies_nothing_and_offers_nothing() -> void:
	var hud := HudScript.new()
	hud._tick_autosave(900.0)
	hud._refresh_pending_recovery()
	assert(hud._pending_recovery.is_empty(), "a scene with no drawing has nothing to offer")
	assert(hud._recovery_notice() == "", "and the File menu's line says nothing extra")
	hud.free()


func test_the_drawing_being_saved_by_the_menu_clears_the_copy_too() -> void:
	# The menu's Save on a drawing that already has a file: the copy is cleared at the moment the drawing
	# is written, not at the moment a Save As dialog closes.
	_clean()
	var controller := _drawn(3)
	assert(bool(_save(controller.document, SCRATCH)["ok"]), "a drawing with a file")
	controller.drawing_path = SCRATCH
	controller.dirty = false
	var hud := _hud_for(controller)
	AutosaveScript.write(controller.document.to_dict(), SCRATCH, "", 3)
	assert(AutosaveScript.list().size() == 1, "a copy is waiting")
	controller.document.add(EntityScript.make_line(Vector2(0, 9), Vector2(2, 9)), LayerSetScript.NEW_HARDSCAPE)
	assert(controller.dirty, "and the drawing has been worked on since")
	hud._menu_save_drawing({})
	assert(not controller.dirty, "the drawing was saved")
	assert(AutosaveScript.list().is_empty(), "and the copy of it is gone")
	hud.free()
	controller.free()
	_clean()