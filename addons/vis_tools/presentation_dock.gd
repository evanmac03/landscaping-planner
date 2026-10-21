@tool
class_name VisPresentationDock
extends Control
## The presentation dock: what the presentation is missing, and the batch that makes one.
##
## A dock rather than more game HUD, because both of its jobs are *authoring* rather than designing:
## a batch of stills is a list of sizes and views a person edits while looking at the project, and a
## missing wash entry is a table to extend in a script. Neither belongs in the running game.
##
## It holds no arithmetic and no rendering. Every finding comes from `VisDiagnostics`, which asks the
## wash table, the solid table and the texture table their own reasons; every job is a `VisRenderBatch`
## entry, which the game's exporter will render. **This dock never renders** - `render_requested` asks
## whoever adopted it to render one job through the project's own exporter (REQ-V11.1), and
## `record_result` puts the answer back. A second render path in the editor would be a second thing to
## keep in step with the one that has tests, and the first one is the one that has tests.
##
## The batch is driven as a ledger rather than a loop, for the same reason `VisRenderBatch` is: a
## render is asynchronous and cannot be awaited through a callable, so the dock hands out one job at a
## time and asks for the next when the last one comes back. `record_result` is that answer.
##
## Nothing here touches the editor. The dock is a plain `Control`, so every method below is reachable
## in a test with the dock never added to a tree; `plugin.gd` is the only file that knows it is a
## plugin.

const DiagnosticsScript := preload("res://scripts/vis/vis_diagnostics.gd")
const PresetScript := preload("res://scripts/vis/still_preset.gd")
const BatchScript := preload("res://scripts/vis/render_batch.gd")

## Asked for one job, which the adopter renders through the project's exporter.
signal render_requested(job: Dictionary)
## The report was worked out. Carries the findings, most serious first.
signal checked(findings: Array)
## Something to put on a status line.
signal said(line: String)

## The drawing whose layers are checked, and the layer set they are checked against. Either may be
## null: a layer set alone answers for the whole project rather than for one drawing.
var document: Variant = null
var layer_set: Variant = null
## The batch of stills in hand.
var batch: VisRenderBatch = null
## Whether the notes - the decisions on the record, not problems - are listed too.
var show_notes: bool = false
## The last thing the dock said, for a status bar or a test.
var last_words: String = ""

var _findings: Array[Dictionary] = []
## What the bound drawing is called, when it did not come from the scene the editor has open.
var _source_where: String = ""
## The job handed out and not yet answered. One at a time, because a renderer is one thing.
var _in_flight: String = ""
var _built: bool = false

var _source_line: Label = null
var _summary: Label = null
var _finding_list: ItemList = null
var _notes_box: CheckBox = null
var _job_list: ItemList = null
var _progress: Label = null
var _job_name: LineEdit = null
var _preset_picker: OptionButton = null
var _view_picker: OptionButton = null
var _render_button: Button = null
var _status: Label = null


func _ready() -> void:
	if not _built:
		build()


# --- the dock ----------------------------------------------------------------------------------


## Build the dock. Called by the plugin when the dock is added, and by a test directly, so the whole
## of it is reachable without the editor.
func build() -> void:
	if _built:
		return
	_built = true
	name = "Presentation"
	var column: VBoxContainer = _column("Dock")
	add_child(column)

	column.add_child(_heading("What the presentation is missing"))
	_source_line = _label(column, "no drawing is open")
	_source_line.name = "SourceLine"
	_finding_list = ItemList.new()
	_finding_list.name = "Findings"
	_finding_list.focus_mode = Control.FOCUS_NONE
	_finding_list.custom_minimum_size = Vector2(0.0, 140.0)
	column.add_child(_finding_list)
	_summary = _label(column, DiagnosticsScript.summarise([]))
	_summary.name = "Summary"
	var check_row := HBoxContainer.new()
	column.add_child(check_row)
	_notes_box = CheckBox.new()
	_notes_box.name = "ShowNotes"
	_notes_box.text = "Show notes"
	_notes_box.focus_mode = Control.FOCUS_NONE
	_notes_box.toggled.connect(set_show_notes)
	check_row.add_child(_notes_box)
	check_row.add_child(_button("Check the drawing", check, "Check"))

	column.add_child(_heading("Render a batch of stills"))
	_job_name = LineEdit.new()
	_job_name.name = "JobName"
	_job_name.placeholder_text = "name, e.g. Front garden"
	var add_row := HBoxContainer.new()
	column.add_child(add_row)
	add_row.add_child(_labelled("Name", _job_name))
	_preset_picker = OptionButton.new()
	_preset_picker.name = "Preset"
	_preset_picker.focus_mode = Control.FOCUS_NONE
	for preset_name: StringName in PresetScript.ORDER:
		_preset_picker.add_item(PresetScript.label(preset_name))
	add_row.add_child(_labelled("Size", _preset_picker))
	_view_picker = OptionButton.new()
	_view_picker.name = "View"
	_view_picker.focus_mode = Control.FOCUS_NONE
	for view: String in BatchScript.DEFAULT_VIEWS:
		_view_picker.add_item(view)
	add_row.add_child(_labelled("View", _view_picker))
	add_row.add_child(_button("Add", add_job_from_fields, "AddJob"))

	_job_list = ItemList.new()
	_job_list.name = "Jobs"
	_job_list.focus_mode = Control.FOCUS_NONE
	_job_list.custom_minimum_size = Vector2(0.0, 120.0)
	column.add_child(_job_list)
	var render_row := HBoxContainer.new()
	column.add_child(render_row)
	_render_button = _button("Render all", render_all, "RenderAll")
	render_row.add_child(_render_button)
	_render_button.disabled = true
	_progress = _label(render_row, "no batch is loaded")
	_progress.name = "Progress"

	_status = _label(column, "A dock, replaced by Y when it is added.")
	_status.name = "Status"
	_say("Nothing has been checked yet.")


# --- the diagnostics ----------------------------------------------------------------------------


## Point the dock at a drawing and the layer set to check it against. Either may be null.
##
## `where` names the drawing in a person's words ("the most recent drawing, south-lawn"), and is only
## needed when the drawing did not come from the scene the editor has open - in which case the dock
## would otherwise say "the open drawing" about a file the editor has never seen.
func bind_visuals(source_document: Variant, source_layers: Variant, where: String = "") -> void:
	document = source_document
	layer_set = source_layers
	_source_where = where
	_findings = []
	_refresh_findings()
	_source_line.text = _source_text()
	_say("Ready to check %s." % _source_text())


## Work out the report and put it on the page. Returns the findings, most serious first, so a test
## and a person read the same thing.
func check() -> Array[Dictionary]:
	if document == null and layer_set == null:
		_findings = []
		_refresh_findings()
		_say("There is nothing to check: no drawing is open and no layer set is bound.")
		return _findings
	_findings = DiagnosticsScript.report(document, layer_set)
	_refresh_findings()
	_say(DiagnosticsScript.summarise(_findings))
	checked.emit(_findings)
	return _findings


## The report in hand.
func findings() -> Array[Dictionary]:
	return _findings.duplicate(true)


## The findings that are something to fix: the errors and the warnings, without the notes.
func problems() -> Array[Dictionary]:
	return DiagnosticsScript.problems(_findings)


## The report in one line, as the dock's own summary shows it.
func summarise() -> String:
	return DiagnosticsScript.summarise(_findings)


## Whether the notes are listed beside the problems. A note is a decision on the record, not
## something to act on, so it is behind a toggle rather than mixed in.
func set_show_notes(on: bool) -> void:
	show_notes = on
	if _notes_box != null and _notes_box.button_pressed != on:
		_notes_box.button_pressed = on
	_refresh_findings()


## The rows the list shows right now, in order: the problems, and the notes when they are asked for.
func listed() -> Array[Dictionary]:
	return DiagnosticsScript.rows(_findings if show_notes else problems())


func _refresh_findings() -> void:
	if _finding_list == null:
		return
	_finding_list.clear()
	for row: Dictionary in listed():
		_finding_list.add_item(String(row["text"]))
	if _summary != null:
		_summary.text = summarise()


func _source_text() -> String:
	var layers := "its own layers" if layer_set == null else "the bound layer set"
	if _source_where != "":
		return "%s, checked against %s" % [_source_where, layers]
	var drawing := "the open drawing" if document != null else "no drawing"
	return "%s, checked against %s" % [drawing, layers]


# --- the batch ----------------------------------------------------------------------------------


## Adopt a batch of stills. The dock does not make one: a batch is a thing a person makes, and
## `VisRenderBatch` is where it lives.
func bind_batch(new_batch: VisRenderBatch) -> void:
	batch = new_batch
	_in_flight = ""
	_refresh_jobs()
	_say("A batch of %d jobs is loaded." % (batch.count() if batch != null else 0))


## Add a still to the batch by name, size and view. Refused, in the batch's own words, when the batch
## will not take it - a blank name, a name already used, or a full batch.
func add_job(job_name: String, preset: StringName, view: String) -> bool:
	if batch == null:
		_say("There is no batch to add to.")
		return false
	if not batch.add(job_name, preset, view, false, ""):
		# The batch's own sentence about why not, rather than one invented here: a dock that wrote
		# its own wording for "that name is taken" would be a second copy of the batch's rule.
		_say("'%s' was not added: %s" % [job_name, batch.reason_against(job_name)])
		return false
	_refresh_jobs()
	_say("Added %s." % job_name)
	return true


## Add a still from what the fields hold.
func add_job_from_fields() -> bool:
	if _job_name == null or _preset_picker == null or _view_picker == null:
		return false
	var preset: StringName = PresetScript.ORDER[_preset_picker.selected]
	var view: String = _view_picker.get_item_text(_view_picker.selected)
	var added: bool = add_job(_job_name.text, preset, view)
	if added:
		_job_name.text = ""
	return added


## Hand out the next unrendered job and ask for it. Returns the job, or an empty dictionary when the
## batch is done, empty, or has one already in flight.
##
## One at a time on purpose: a renderer is one thing, and two renders at once is two frames fighting
## over the same viewport.
func render_next() -> Dictionary:
	if batch == null or _in_flight != "":
		return {}
	var job: Dictionary = batch.next_job()
	if job.is_empty():
		_refresh_jobs()
		return {}
	_in_flight = String(job["name"])
	_say("Rendering %s." % _in_flight)
	_refresh_jobs()
	render_requested.emit(job)
	return job


## The answer for the job in flight: where the still landed, or "" when the render was refused. The
## next job is asked for straight away, which is what makes the batch run to the end without a loop.
func record_result(path: String) -> bool:
	if batch == null or _in_flight == "":
		_say("Nothing is being rendered.")
		return false
	var job_name: String = _in_flight
	_in_flight = ""
	batch.record(job_name, path)
	_refresh_jobs()
	_say("%s: %s" % [job_name, "written" if path != "" else "refused"])
	if not batch.is_done():
		render_next()
	return true


## Start the batch. It carries on by itself: each `record_result` asks for the next job.
func render_all() -> bool:
	if batch == null or batch.is_empty():
		_say("There is nothing to render.")
		return false
	if _in_flight != "":
		return false
	return not render_next().is_empty()


## Whether a job has been handed out and not yet answered.
func in_flight() -> String:
	return _in_flight


## How the batch stands, in one line.
func progress() -> String:
	if batch == null:
		return "no batch is loaded"
	if batch.is_empty():
		return "the batch is empty"
	return "%d of %d done, %d refused" % [
		batch.attempted(), batch.count(), batch.failed(),
	]


func _refresh_jobs() -> void:
	if _progress != null:
		_progress.text = progress()
	if _render_button != null:
		_render_button.disabled = batch == null or batch.is_empty() or batch.is_done()
	if _job_list == null:
		return
	_job_list.clear()
	if batch == null:
		return
	for line: String in batch.report_text().split("\n", false):
		# The job in flight is the one the dock is waiting on, which the batch's own report
		# cannot know: it is a fact about the dock's ledger, not about the job.
		var shown: String = line
		if _in_flight != "" and line.begins_with(_in_flight + " "):
			shown = "%s  <- rendering" % line
		_job_list.add_item(shown)


func _say(line: String) -> void:
	last_words = line
	if _status != null:
		_status.text = line
	said.emit(line)


# --- widgets ------------------------------------------------------------------------------------


## Nothing in a dock takes the keyboard: the editor's own shortcuts belong to the editor, and a
## focused button here would swallow the space bar.
func _button(text: String, handler: Callable, node_name: String) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(handler)
	return button


func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label


func _label(parent: Node, text: String) -> Label:
	var label := Label.new()
	label.text = text
	parent.add_child(label)
	return label


func _labelled(text: String, field: Control) -> VBoxContainer:
	var box := VBoxContainer.new()
	var label := Label.new()
	label.text = text
	box.add_child(label)
	box.add_child(field)
	return box


func _column(node_name: String) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.name = node_name
	return column