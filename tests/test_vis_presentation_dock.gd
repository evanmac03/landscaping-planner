extends Node
## Tests for the presentation dock (specification 11.2 and 11.3).
##
## The dock is a plain `Control` with no editor API, so everything below is driven with the dock never
## added to a tree - the same discipline the cost book dock follows, and the reason the only file that
## cannot be tested this way is `plugin.gd`.
##
## What is worth pinning is that the dock **holds no arithmetic and does no rendering**: the findings it
## lists are `VisDiagnostics`'s own report, the jobs it hands out are `VisRenderBatch`'s own jobs, and
## `render_requested` is a *request*. So the tests here are about the two things a dock adds - what it
## shows, and the order it asks for things in - and about the batch being driven as a ledger: one job in
## flight, the next asked for when the last one answers.

const DockScript := preload("res://addons/vis_tools/presentation_dock.gd")
const Diag := preload("res://scripts/vis/vis_diagnostics.gd")
const BatchScript := preload("res://scripts/vis/render_batch.gd")
const PresetScript := preload("res://scripts/vis/still_preset.gd")
const Doc := preload("res://scripts/draft/draft_document.gd")
const Ent := preload("res://scripts/draft/draft_entity.gd")
const Layer := preload("res://scripts/draft/draft_layer.gd")
const LayerSet := preload("res://scripts/draft/layer_set.gd")

const POND := &"450-NEW-POND"


## A built dock, never added to a tree. Every test frees it, because a `Control` left behind makes the
## runner report resources still in use - which fails the verdict even when every assertion passed.
func _dock() -> VisPresentationDock:
	var dock: VisPresentationDock = DockScript.new()
	dock.build()
	return dock


## A drawing with something on it and one layer the presentation tables have never heard of.
func _drawing() -> DraftDocument:
	var doc := Doc.new()
	doc.add(Ent.make_line(Vector2(0, 0), Vector2(6, 0)), LayerSet.NEW_HARDSCAPE)
	doc.add(Ent.make_text(Vector2(1, 1), "valley gutter"), LayerSet.CALLOUT)
	var extra := Layer._new()
	extra.name = POND
	extra.purpose = "A pond"
	doc.layers.add(extra)
	doc.add(Ent.make_polyline(PackedVector2Array([
		Vector2(0, 6), Vector2(3, 6), Vector2(3, 8), Vector2(0, 8),
	]), true), POND)
	return doc


func _with_four_jobs() -> VisRenderBatch:
	var batch: VisRenderBatch = BatchScript.new()
	batch.add_every_view(PresetScript.PROPOSAL_DEFAULT, BatchScript.DEFAULT_VIEWS)
	return batch


# --- the controls a person works with ---------------------------------------------------------


func test_the_dock_builds_the_controls_and_says_where_to_start() -> void:
	var dock := _dock()
	assert(dock.name == "Presentation", "the dock has a name: %s" % dock.name)
	for control_name: String in ["SourceLine", "Findings", "Summary", "ShowNotes", "Check", "JobName",
			"Preset", "View", "AddJob", "Jobs", "RenderAll", "Progress", "Status"]:
		assert(dock.find_child(control_name, true, false) != null, "%s was built" % control_name)
	assert(dock.last_words != "", "it has said something: %s" % dock.last_words)
	dock.free()


func test_nothing_in_the_dock_takes_the_keyboard() -> void:
	# A focused button in a dock would swallow the editor's own shortcuts, and the space bar with them.
	var dock := _dock()
	var checked := 0
	for found: Node in dock.find_children("*", "Button", true, false):
		var button: Button = found
		assert(button.focus_mode == Control.FOCUS_NONE, "%s takes no focus" % button.name)
		checked += 1
	assert(checked >= 4, "there are buttons to check, got %d" % checked)
	for found: Node in dock.find_children("*", "ItemList", true, false):
		var list: ItemList = found
		assert(list.focus_mode == Control.FOCUS_NONE, "%s takes no focus" % list.name)
	dock.free()


func test_the_pickers_offer_the_sizes_and_the_views_the_modules_have() -> void:
	var dock := _dock()
	var presets: OptionButton = dock.find_child("Preset", true, false)
	assert(presets.item_count == PresetScript.ORDER.size(), "one entry per preset")
	for index in PresetScript.ORDER.size():
		assert(presets.get_item_text(index) == PresetScript.label(PresetScript.ORDER[index]),
			"entry %d is labelled as the preset table labels it" % index)
	var views: OptionButton = dock.find_child("View", true, false)
	assert(views.item_count == BatchScript.DEFAULT_VIEWS.size())
	assert(views.get_item_text(0) == BatchScript.DEFAULT_VIEWS[0])
	dock.free()


# --- the diagnostics, on the page -------------------------------------------------------------


func test_a_dock_with_nothing_bound_says_exactly_that() -> void:
	var dock := _dock()
	var findings: Array[Dictionary] = dock.check()
	assert(findings.is_empty(), "there is nothing to check")
	assert(dock.problems().is_empty())
	assert(dock.last_words.contains("nothing to check"), "it says so: %s" % dock.last_words)
	assert(dock.summarise().begins_with("nothing to report"), dock.summarise())
	dock.free()


func test_checking_a_drawing_lists_the_findings_and_announces_them() -> void:
	var dock := _dock()
	var doc := _drawing()
	var heard: Array[Dictionary] = []
	dock.checked.connect(func(findings: Array) -> void: heard.append({"n": findings.size()}))
	dock.bind_visuals(doc, doc.layers)
	dock.check()
	assert(dock.findings().size() == 3, "two warnings and a note, got %d" % dock.findings().size())
	assert(dock.problems().size() == 2, "one problem per table the pond layer is missing from")
	assert(heard.size() == 1, "the report was announced once, got %d" % heard.size())
	assert(int(heard[0]["n"]) == 3, "and carried the findings")
	assert(dock.summarise().contains("2 warnings"), "the summary is the report's own: %s" % dock.summarise())
	# The findings are VisDiagnostics's own answers, not a second opinion.
	var mine: Array[Dictionary] = Diag.report(doc, doc.layers)
	assert(dock.findings().size() == mine.size())
	assert(dock.summarise() == Diag.summarise(mine))
	dock.free()


func test_the_list_shows_the_problems_and_the_notes_are_behind_a_toggle() -> void:
	var dock := _dock()
	var doc := _drawing()
	dock.bind_visuals(doc, doc.layers)
	dock.check()
	assert(dock.listed().size() == 2, "the problems, and not the note: got %d" % dock.listed().size())
	for row: Dictionary in dock.listed():
		assert(String(row["severity"]) != Diag.NOTE, "no notes among the problems")
	var list: ItemList = dock.find_child("Findings", true, false)
	assert(list.item_count == dock.listed().size(), "the list is as long as the rows")
	# Asking for the notes lists them beside the problems and says so on the box.
	dock.set_show_notes(true)
	assert(dock.listed().size() == 3, "the note joins them: got %d" % dock.listed().size())
	var box: CheckBox = dock.find_child("ShowNotes", true, false)
	assert(box.button_pressed, "the box shows what the dock is doing")
	assert(list.item_count == 3, "and the list grew with it")
	dock.set_show_notes(false)
	assert(list.item_count == 2, "and shrinks again")
	dock.free()


func test_pointing_the_dock_at_another_drawing_clears_the_old_report() -> void:
	var dock := _dock()
	var doc := _drawing()
	dock.bind_visuals(doc, doc.layers)
	dock.check()
	assert(dock.findings().size() == 3)
	dock.bind_visuals(Doc.new(), LayerSet.default_set())
	assert(dock.findings().is_empty(), "the old report is not still on the page")
	assert(dock.listed().is_empty(), "and the list is empty")
	dock.free()


func test_the_source_line_says_what_is_being_checked() -> void:
	var dock := _dock()
	var line: Label = dock.find_child("SourceLine", true, false)
	assert(line.text.contains("no drawing"), "an unbound dock says so: %s" % line.text)
	var doc := _drawing()
	dock.bind_visuals(doc, doc.layers)
	assert(line.text.contains("open drawing"), "a bound one names it: %s" % line.text)
	assert(line.text.contains("layer set"), "and what it is checked against: %s" % line.text)
	dock.bind_visuals(doc, null)
	assert(line.text.contains("its own layers"), "a bare drawing is checked against its own: %s" % line.text)
	dock.free()


# --- the batch, driven as a ledger -------------------------------------------------------------


func test_a_dock_with_no_batch_refuses_the_batch_things() -> void:
	var dock := _dock()
	assert(not dock.add_job("Front garden", PresetScript.PROPOSAL_DEFAULT, "Painted plan"), "no batch to add to")
	assert(dock.last_words.contains("no batch"), "it says which: %s" % dock.last_words)
	assert(dock.render_next().is_empty(), "and hands out nothing")
	assert(not dock.render_all(), "and starts nothing")
	assert(not dock.record_result("somewhere.png"), "and has nothing to answer for")
	assert(dock.progress() == "no batch is loaded")
	var button: Button = dock.find_child("RenderAll", true, false)
	assert(button.disabled, "the render button is dead")
	dock.free()


func test_a_batch_of_working_stills_is_listed_and_the_button_wakes_up() -> void:
	var dock := _dock()
	dock.bind_batch(_with_four_jobs())
	assert(dock.progress().contains("of 4 done"), "the progress names the count: %s" % dock.progress())
	var list: ItemList = dock.find_child("Jobs", true, false)
	assert(list.item_count == 4, "one row per job, got %d" % list.item_count)
	assert(String(list.get_item_text(0)).contains("waiting"), "and each says it is waiting: %s" % list.get_item_text(0))
	var button: Button = dock.find_child("RenderAll", true, false)
	assert(not button.disabled, "there is something to render")
	dock.free()


func test_a_still_is_added_by_name_size_and_view_and_a_bad_one_is_refused() -> void:
	var dock := _dock()
	var batch: VisRenderBatch = BatchScript.new()
	dock.bind_batch(batch)
	assert(dock.add_job("Front garden", PresetScript.PROPOSAL_DEFAULT, "Painted plan"), "the first is taken")
	assert(not dock.add_job("Front garden", PresetScript.PROPOSAL_DEFAULT, "Painted plan"), "a duplicate name is refused")
	assert(dock.last_words.contains("Front garden"), "and the refusal names it: %s" % dock.last_words)
	assert(not dock.add_job("", PresetScript.PROPOSAL_DEFAULT, "Painted plan"), "a blank name is refused")
	assert(batch.count() == 1, "only the good one went in")
	dock.free()


func test_the_add_button_takes_what_the_pickers_show() -> void:
	var dock := _dock()
	var batch: VisRenderBatch = BatchScript.new()
	dock.bind_batch(batch)
	var name_field: LineEdit = dock.find_child("JobName", true, false)
	var presets: OptionButton = dock.find_child("Preset", true, false)
	var views: OptionButton = dock.find_child("View", true, false)
	name_field.text = "Back garden"
	presets.selected = 1
	views.selected = 2
	assert(dock.add_job_from_fields(), "the row was added")
	assert(batch.count() == 1)
	var job: Dictionary = batch.jobs()[0]
	assert(String(job["name"]) == "Back garden")
	assert(StringName(job["preset"]) == PresetScript.ORDER[1], "the size is the one the picker shows")
	assert(String(job["view"]) == BatchScript.DEFAULT_VIEWS[2], "and so is the view")
	assert(name_field.text == "", "the name field is emptied for the next one")
	dock.free()


func test_one_job_is_in_flight_at_a_time() -> void:
	var dock := _dock()
	dock.bind_batch(_with_four_jobs())
	var asked: Array[Dictionary] = []
	dock.render_requested.connect(func(job: Dictionary) -> void: asked.append(job))
	var job: Dictionary = dock.render_next()
	assert(not job.is_empty(), "the first job was handed out")
	assert(asked.size() == 1, "and asked for once, got %d" % asked.size())
	assert(String(dock.in_flight()) == String(job["name"]), "the dock knows which one it is waiting on")
	assert(dock.render_next().is_empty(), "a second job is not handed out while one is in flight")
	assert(asked.size() == 1, "so nothing else was asked for")
	dock.free()


func test_a_result_asks_for_the_next_job_and_the_batch_runs_to_the_end() -> void:
	var dock := _dock()
	dock.bind_batch(_with_four_jobs())
	var asked: Array[String] = []
	dock.render_requested.connect(func(job: Dictionary) -> void: asked.append(String(job["name"])))
	assert(dock.render_all(), "the batch started")
	# Each answer is a still written, and pulls the next job; the last one stops.
	var guard := 0
	while dock.in_flight() != "" and guard < 10:
		assert(dock.record_result("user://proposals/%s.png" % dock.in_flight()), "the answer was recorded")
		guard += 1
	assert(asked.size() == 4, "every job was asked for once, got %d" % asked.size())
	assert(dock.in_flight() == "", "nothing is left in flight")
	assert(dock.progress().contains("4 of 4 done"), "and they all counted: %s" % dock.progress())
	assert(dock.progress().contains("0 refused"))
	var button: Button = dock.find_child("RenderAll", true, false)
	assert(button.disabled, "a finished batch cannot be run again")
	dock.free()


func test_a_refused_render_is_counted_and_the_batch_carries_on() -> void:
	var dock := _dock()
	dock.bind_batch(_with_four_jobs())
	dock.render_all()
	assert(dock.record_result(""), "a refusal is still an answer")
	while dock.in_flight() != "":
		dock.record_result("")
	assert(dock.progress().contains("4 refused"), "all four were refused: %s" % dock.progress())
	assert(dock.last_words.contains("refused"), "and the dock says so: %s" % dock.last_words)
	dock.free()


func test_running_a_batch_twice_is_refused_while_one_is_in_flight() -> void:
	var dock := _dock()
	dock.bind_batch(_with_four_jobs())
	assert(dock.render_all(), "the batch started")
	assert(not dock.render_all(), "and is not started again while a job is in flight")
	var asked: Array[Dictionary] = []
	dock.render_requested.connect(func(job: Dictionary) -> void: asked.append(job))
	assert(not dock.render_all(), "nor after a second press")
	assert(asked.is_empty(), "nothing was asked for by the second press")
	dock.free()


func test_an_empty_batch_is_refused_rather_than_run() -> void:
	var dock := _dock()
	var batch: VisRenderBatch = BatchScript.new()
	dock.bind_batch(batch)
	assert(not dock.render_all(), "there is nothing to render")
	assert(dock.last_words.contains("nothing to render"), "and it says so: %s" % dock.last_words)
	assert(dock.progress() == "the batch is empty")
	dock.free()


func test_a_result_with_nothing_in_flight_is_refused() -> void:
	var dock := _dock()
	dock.bind_batch(_with_four_jobs())
	assert(not dock.record_result("somewhere.png"), "no job is waiting for an answer")
	assert(dock.last_words.contains("Nothing is being rendered"), "and it says so: %s" % dock.last_words)
	dock.free()


func test_the_last_thing_said_is_readable_without_looking_at_a_label() -> void:
	var dock := _dock()
	dock.bind_batch(_with_four_jobs())
	assert(dock.last_words.contains("4 jobs"), "binding a batch says how many: %s" % dock.last_words)
	dock.add_job("Another", PresetScript.PROPOSAL_DEFAULT, "Working plan")
	assert(dock.last_words.contains("Another"), "adding one says which: %s" % dock.last_words)
	var heard: Array[String] = []
	dock.said.connect(func(line: String) -> void: heard.append(line))
	dock.render_next()
	assert(heard.size() >= 1, "and it is announced as well as kept")
	dock.free()