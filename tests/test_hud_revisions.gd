extends Node
## The HUD's side of the drawing's history: the Edit menu's way in, and what the window's own signals do
## to the drawing.
##
## The window is built by hand here and never popped up: a `Window` popped in the headless test runner
## hangs it, and there is nothing to see anyway - what is under test is the wiring, and every handler
## below is reached by the same method the signal is connected to.

const HudScript := preload("res://scripts/hud.gd")
const ControllerScript := preload("res://scripts/draft/draft_controller.gd")
const DocumentScript := preload("res://scripts/draft/draft_document.gd")
const Entity := preload("res://scripts/draft/draft_entity.gd")
const LayerSet := preload("res://scripts/draft/layer_set.gd")
const StoreScript := preload("res://scripts/draft/drawing_store.gd")

const SCRATCH := "user://drawings/test-hud-revisions.json"


func _hud():
	var hud := HudScript.new()
	var controller = ControllerScript.new()
	controller.document = DocumentScript.new()
	hud._draft = controller
	hud._build_revision_window()
	hud._draft.document.add(
		Entity.make_rectangle(Vector2(0.0, 0.0), Vector2(12.0, 8.0)), LayerSet.NEW_BED
	)
	return hud


func _clean() -> void:
	StoreScript.ensure_dir()
	for path: String in [SCRATCH, StoreScript.revisions_path(SCRATCH)]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


## Free the Hud and the controller holding the drawing it was given. A Node is not reference counted, and
## a leaked one is reported as a resource still in use at exit - which the runner counts as a failing test.
func _done(hud) -> void:
	var controller: Node = hud._draft
	hud.free()
	if controller != null:
		controller.free()


func _entry(id: StringName) -> Dictionary:
	for entry: Dictionary in HudScript.menu_entries():
		if StringName(entry.get("id", &"")) == id:
			return entry
	assert(false, "no menu entry with id %s" % String(id))
	return {}


# --- the way in -----------------------------------------------------------------------


func test_the_edit_menu_offers_the_history() -> void:
	var entry: Dictionary = _entry(&"edit.revisions")
	assert(String(entry["label"]) == "Revisions...", String(entry["label"]))
	assert(StringName(entry["method"]) == &"_menu_revisions", String(entry["method"]))
	# It is in the Edit menu, and it takes no key: a history is opened to be read, and the drawing's keys
	# belong to the drawing.
	assert(entry.has("action") == false or StringName(entry.get("action", &"")) == &"", "no key")
	var in_edit := false
	for listed: Dictionary in HudScript.items_for("Edit"):
		if StringName(listed.get("id", &"")) == &"edit.revisions":
			in_edit = true
	assert(in_edit, "the history is under Edit, with the rest of the drawing's own commands")
	# And it is an entry the bar can actually run.
	var hud := HudScript.new()
	assert(hud.has_method(String(entry["method"])), "the method the entry names exists")
	_done(hud)


func test_a_window_with_no_drawing_opens_nothing() -> void:
	var hud := HudScript.new()
	assert(not hud.is_revision_window_open())
	# No drawing in hand: there is no history for a window to be about, and it does not open onto one.
	hud.open_revision_window()
	assert(not hud.is_revision_window_open())
	_done(hud)


# --- what the window's signals do -----------------------------------------------------


func test_recording_records_the_drawing_and_says_where_it_went() -> void:
	_clean()
	var hud = _hud()
	assert(bool(hud._draft.save_drawing(SCRATCH)["ok"]))
	hud._on_revision_recorded("sent to the client")
	assert(hud._draft.revisions.count() == 1, "the drawing was recorded")
	assert(hud._draft.revisions.messages() == ["sent to the client"])
	assert(hud._revision_window.row_count() == 1, "and the window lists it")
	assert(String(hud._revision_window.selected_row()["message"]) == "sent to the client")
	assert(hud.revision_status_text().begins_with("recorded rev 1"), hud.revision_status_text())
	# The person's own name is on it, from the only place this app can know it.
	assert(String(hud._revision_window.selected_row()["author"]).is_empty() == false,
		"a history that cannot say who is a list of timestamps")
	_done(hud)
	_clean()


func test_recording_before_the_drawing_has_a_name_says_where_it_is_kept() -> void:
	_clean()
	var hud = _hud()
	hud._on_revision_recorded("the first idea")
	assert(hud._draft.revisions.count() == 1, "the revision is taken")
	assert(hud.revision_status_text().contains("in memory only"), hud.revision_status_text())
	assert(hud._revision_window.row_count() == 1)
	_done(hud)


func test_restoring_puts_a_revision_back_on_the_drawing() -> void:
	_clean()
	var hud = _hud()
	assert(bool(hud._draft.save_drawing(SCRATCH)["ok"]))
	hud._on_revision_recorded("sent to the client")
	var seen: int = hud._draft.document.count()
	hud._draft.document.add(
		Entity.make_circle(Vector2(2.0, 3.0), 1.5), LayerSet.NEW_PLANTING
	)
	hud._on_revision_recorded("a tree added off the cuff")
	assert(hud._draft.document.count() == seen + 1)
	assert(hud._revision_window.row_count() == 2)
	assert(hud._revision_window.change_text().begins_with("1 added"),
		hud._revision_window.change_text())

	assert(hud._revision_window.select(0))
	hud._revision_window.restore()
	assert(hud._draft.document.count() == seen, "the drawing is as the earlier revision had it")
	assert(hud.revision_status_text().begins_with("restored rev 1"), hud.revision_status_text())
	_done(hud)
	_clean()


func test_the_window_reports_the_life_of_the_history() -> void:
	_clean()
	var hud = _hud()
	assert(hud.revision_status_text() == "nothing has been recorded against this drawing yet",
		hud.revision_status_text())
	hud._on_revision_recorded("the first idea")
	# While a revision has just been recorded the window is reporting *that*, which is the line the
	# person needs - where it went. Clearing it, as closing the window does, leaves the count.
	hud._revision_window.say("")
	assert(hud.revision_status_text() == "1 revision kept", hud.revision_status_text())
	_done(hud)
	_clean()