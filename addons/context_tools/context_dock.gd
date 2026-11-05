@tool
class_name ContextExportDock
extends Control
## The AI context dock: pick a subject (or the whole project), optionally add your task prompt and
## the source of the script you have open, preview the generated Markdown snapshot, and copy or write
## it with one click.
##
## A dock rather than an EditorScript you have to hunt down and edit `const SUBJECT` in: picking
## between the full snapshot and `plant-id` / `planting` / `drafting`, typing a question to append
## at the foot, and seeing the line and byte count before you paste are all things a form does
## naturally.
##
## It holds no formatting rules of its own. Every line of the snapshot and every output path comes
## from `ContextReport`, so the dock, the EditorScript and the headless CLI runner cannot disagree
## about what a pack contains or where it is written.
##
## Nothing here touches `EditorInterface`. The dock is a plain `Control`, so every decision it makes
## is driven in a unit test with the dock never added to a tree; `plugin.gd` is the only file that
## knows it is an editor plugin.

const ContextReportScript := preload("res://tools/context_report.gd")

const WHOLE_LABEL := "Everything - the whole project"
## A rough token estimate is four characters per token: close enough to size a prompt before pasting
## it, and the number is labelled an estimate everywhere it is shown.
const CHARS_PER_TOKEN := 4
## Past this many tokens a web chat starts to lose the thread, so the summary says so in a sentence.
const LARGE_TOKENS := 15000
## The colour the summary takes when the payload is larger than a web chat handles well.
const WARN_COLOR := Color(0.93, 0.68, 0.25)
## How often the dock checks whether the files behind the pack on screen have changed. A pack is pasted
## into a chat minutes or hours after it was built, and nothing in the chat can see that a file
## underneath it has moved on - so it is checked every couple of seconds, which costs a read of the
## files the pack quotes rather than of the whole project.
const FRESH_CHECK_SECONDS := 2.0

## What the source row says when the editor has no script open to offer.
const SOURCE_NONE := "No script is open in the editor's script editor."
## The first entry of the second-pack picker: one pack, which is what most questions want.
const SECOND_NONE := "Nothing else - one pack"

## Emitted whenever the status line changes.
signal said(line: String)
## Emitted after a snapshot or pack is built, copied or saved.
signal exported(subject: String, path: String, chars: int)

## Where output files are written (`user://` in the editor; tests and demos point it at their own
## folder so they never clobber the user's snapshot).
var output_dir: String = "user://"
## The currently selected subject (`""` means the whole project snapshot).
var current_subject: String = ""
## An optional **second** pack built into the same payload (`""` means just the one). A question that
## reaches across two subsystems would otherwise force a choice that loses the other half.
var second_subject: String = ""
## The last built Markdown payload (including any appended task prompt).
var last_output: String = ""
## The last file path written to disk.
var last_path: String = ""
## The last message shown on the status line, for a caller or a test.
var last_words: String = ""
## The estimated token cost of `last_output`, for a caller or a test.
var last_tokens: int = 0
## The **content address** of the payload last built, so a pack whose files have changed underneath it
## can be called out of date rather than pasted as if it still described the project. See
## `ContextReport.fingerprint_for`.
var last_fingerprint: String = ""
## The script open in the editor's script editor, as `plugin.gd` last handed it over, and its text.
##
## Both are empty when nothing is open. The dock never reads a file itself: this is handed to it, which
## is what keeps every decision here testable with no editor in sight.
var source_path: String = ""
var source_text: String = ""

## Where the dock gets the uncommitted-work text, as `{"status": String, "diff": String}`, and the
## last test run's log. `Callable`s rather than direct calls, so a test can hand over canned text and
## the packing stays covered without a repository or a log; running `git` and reading a file are the
## only two things here that touch anything outside this dock.
var git_reader: Callable = Callable()
var run_reader: Callable = Callable()

var _subjects: PackedStringArray = PackedStringArray()
## The second picker's entries: `""` first, then every subject. Kept beside the picker for the same
## reason `_subjects` is.
var _seconds: PackedStringArray = PackedStringArray()
var _built: bool = false
## Seconds since the last freshness check, and whether the pack on screen having gone out of date has
## already been said. It is said once rather than on every check: the answer does not change until the
## person rebuilds, and a status line that repeats itself is a status line nobody reads.
var _fresh_clock: float = 0.0
var _said_stale: bool = false

var _subject_picker: OptionButton = null
## The optional second pack, or `null` before `build()`.
var _second_picker: OptionButton = null
var _path_line: Label = null
## The line under the picker saying when to choose the pack that is selected. Without it a person who
## has never read a specification has no way to tell one pack from another.
var _chosen_line: Label = null
var _prompt_box: TextEdit = null
var _build_button: Button = null
var _copy_button: Button = null
var _save_button: Button = null
var _open_button: Button = null
var _source_check: CheckBox = null
var _git_check: CheckBox = null
var _run_check: CheckBox = null
var _source_line: Label = null
var _summary_line: Label = null
var _preview_box: TextEdit = null
var _status_line: Label = null


func _ready() -> void:
	if not _built:
		build()


## A dock lives in the editor for hours, so it watches for the one thing a person cannot see: that the
## files behind the pack on screen have changed since it was built. Polled rather than watched, because
## there is no notification for "a file this pack quotes was edited", and this is cheap enough to poll.
func _process(delta: float) -> void:
	_fresh_clock += delta
	if _fresh_clock < FRESH_CHECK_SECONDS:
		return
	_fresh_clock = 0.0
	check_freshness()


## Whether what is on screen was built from contents that have since changed. `false` when nothing has
## been built, when the scope has no address of its own (the whole snapshot and the change under
## review), or when the address is the one that was recorded.
func is_stale() -> bool:
	if last_output.is_empty() or last_fingerprint.is_empty():
		return false
	var now: String = current_address()
	return not now.is_empty() and now != last_fingerprint


## Say so, once, when the pack on screen has gone out of date. A separate call rather than three lines
## inside `_process`, so a test can drive the decision with no frames and no editor.
func check_freshness() -> bool:
	if not is_stale():
		_said_stale = false
		return false
	if not _said_stale:
		_said_stale = true
		_say("The files this pack quotes have changed since it was built - press Build preview to catch up.")
	return true


## Build the dock's controls once. Called by the plugin when the dock enters the editor, and by a
## test directly off-tree.
func build() -> void:
	if _built:
		return
	_built = true
	name = "AI Context"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	var column := VBoxContainer.new()
	column.name = "Dock"
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 8)
	add_child(column)

	var heading := Label.new()
	heading.name = "Heading"
	heading.text = "Send this project to an AI"
	heading.add_theme_font_size_override("font_size", get_theme_font_size("font_size") + 3)
	column.add_child(heading)

	var intro := Label.new()
	intro.name = "Intro"
	intro.text = "Pick what to send, add your question, then press Copy to clipboard and paste it into Gemini or DeepSeek."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dim(intro)
	column.add_child(intro)

	# The scope, where the file will be written and what extra it carries are one decision, so they sit
	# in one card rather than reading as three unrelated rows.
	var card := PanelContainer.new()
	card.name = "ScopeCard"
	column.add_child(card)

	var card_margin := MarginContainer.new()
	card_margin.add_theme_constant_override("margin_left", 8)
	card_margin.add_theme_constant_override("margin_top", 6)
	card_margin.add_theme_constant_override("margin_right", 8)
	card_margin.add_theme_constant_override("margin_bottom", 6)
	card.add_child(card_margin)

	var card_box := VBoxContainer.new()
	card_box.add_theme_constant_override("separation", 4)
	card_margin.add_child(card_box)

	var picker_row := HBoxContainer.new()
	picker_row.add_theme_constant_override("separation", 6)
	card_box.add_child(picker_row)

	var picker_label := Label.new()
	picker_label.text = "What to send"
	picker_row.add_child(picker_label)

	_subject_picker = OptionButton.new()
	_subject_picker.name = "SubjectPicker"
	_subject_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# The longest pack title would otherwise set this dock's minimum width - and a minimum width is
	# what pushed the buttons and the summary off the edge of a narrow dock panel.
	_subject_picker.clip_text = true
	# An `OptionButton` normally sizes itself to its **longest** item, and a pack's title is a whole
	# sentence: that one line set this dock's minimum width at 843 px, which no dock panel can give it.
	# The popup still shows every title in full; only the closed button is allowed to be narrower.
	_subject_picker.fit_to_longest_item = false
	_subject_picker.focus_mode = Control.FOCUS_NONE
	picker_row.add_child(_subject_picker)

	# A second pack, because a question can reach across two subsystems and choosing one loses the other
	# half of it. Its entries are slugs rather than titles: this row is about the second choice, and the
	# line under the picker above already says what each pack is for.
	var second_row := HBoxContainer.new()
	second_row.name = "SecondRow"
	second_row.add_theme_constant_override("separation", 6)
	card_box.add_child(second_row)

	var second_label := Label.new()
	second_label.text = "Also include"
	second_row.add_child(second_label)

	_second_picker = OptionButton.new()
	_second_picker.name = "SecondPicker"
	_second_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_second_picker.clip_text = true
	_second_picker.fit_to_longest_item = false
	_second_picker.focus_mode = Control.FOCUS_NONE
	second_row.add_child(_second_picker)

	# Both lists are filled once both pickers exist, since the second is filled from the same subjects.
	_populate_subjects()
	_subject_picker.item_selected.connect(_on_subject_selected)
	_second_picker.item_selected.connect(_on_second_selected)

	_chosen_line = Label.new()
	_chosen_line.name = "ChosenLine"
	_chosen_line.text = ContextReportScript.when_for("")
	_chosen_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dim(_chosen_line)
	card_box.add_child(_chosen_line)

	_path_line = Label.new()
	_path_line.name = "TargetPath"
	_path_line.text = "Also saved as: %s" % target_path("")
	_path_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dim(_path_line)
	card_box.add_child(_path_line)

	_source_check = CheckBox.new()
	_source_check.name = "IncludeSource"
	# Short on purpose: a checkbox's caption is a line that cannot wrap, and a long one becomes the
	# dock's minimum width. The dimmed line under it names the file and its length.
	_source_check.text = "Include the open script's source"
	# Like every other control here: a focused checkbox in a dock swallows the editor's space bar.
	_source_check.focus_mode = Control.FOCUS_NONE
	_source_check.disabled = true
	_source_check.toggled.connect(_on_extra_toggled.bind("the open script's source"))
	card_box.add_child(_source_check)

	_source_line = Label.new()
	_source_line.name = "SourceLine"
	_source_line.text = SOURCE_NONE
	_source_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dim(_source_line)
	card_box.add_child(_source_line)

	# Two more things worth attaching than the pack itself: the work that is not committed yet, and
	# what the tests last said. Both are the reasons somebody asks about a file they are in the middle
	# of changing.
	_git_check = _make_check("IncludeGit", "Include what is not committed yet",
			_on_extra_toggled.bind("the uncommitted work"))
	# The caption is kept short because a checkbox's caption is a line that cannot wrap, and a long one
	# becomes the dock's minimum width; what else the same tick carries goes in the tooltip, which costs
	# no width at all.
	_git_check.tooltip_text = "Also carries the commits that touched this pack's own files."
	card_box.add_child(_git_check)

	_run_check = _make_check("IncludeRun", "Include the last test run",
			_on_extra_toggled.bind("the last test run"))
	card_box.add_child(_run_check)

	column.add_child(HSeparator.new())

	var prompt_label := Label.new()
	prompt_label.name = "PromptLabel"
	prompt_label.text = "Your question or request (optional)"
	prompt_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(prompt_label)

	_prompt_box = TextEdit.new()
	_prompt_box.name = "PromptBox"
	_prompt_box.placeholder_text = "For example: Add a count of captures per species, or explain how a plant gets onto the plan."
	_prompt_box.custom_minimum_size = Vector2(220, 72)
	_prompt_box.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	column.add_child(_prompt_box)

	# A flow container and not a plain row: the bottom-right dock slot has no room for four buttons on
	# one line, and a row that cannot wrap is a row whose last buttons are off the edge of the panel.
	var buttons_row := HFlowContainer.new()
	buttons_row.name = "Buttons"
	buttons_row.add_theme_constant_override("h_separation", 6)
	buttons_row.add_theme_constant_override("v_separation", 4)
	column.add_child(buttons_row)

	_copy_button = _make_button("CopyButton", "Copy to clipboard", copy_to_clipboard)
	buttons_row.add_child(_copy_button)

	_save_button = _make_button("SaveButton", "Write file", write_to_file)
	buttons_row.add_child(_save_button)

	_build_button = _make_button("BuildButton", "Build preview", refresh_preview)
	buttons_row.add_child(_build_button)

	_open_button = _make_button("OpenFolder", "Open folder", open_output_folder)
	buttons_row.add_child(_open_button)

	_summary_line = Label.new()
	_summary_line.name = "Summary"
	_summary_line.text = "Nothing built yet - Build preview shows exactly what Copy will send."
	_summary_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_summary_line)

	var preview_label := Label.new()
	preview_label.name = "PreviewLabel"
	preview_label.text = "Preview"
	preview_label.add_theme_font_size_override("font_size", get_theme_font_size("font_size") + 1)
	column.add_child(preview_label)

	_preview_box = TextEdit.new()
	_preview_box.name = "PreviewBox"
	_preview_box.editable = false
	_preview_box.custom_minimum_size = Vector2(220, 180)
	_preview_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview_box.wrap_mode = TextEdit.LINE_WRAPPING_NONE
	_preview_box.placeholder_text = "Press Build preview to see exactly what will be copied."
	column.add_child(_preview_box)

	_status_line = Label.new()
	_status_line.name = "Status"
	_status_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_dim(_status_line)
	column.add_child(_status_line)

	_say("Pick what to send, add your question, then press Copy to clipboard.")


func _populate_subjects() -> void:
	_subjects.clear()
	_subject_picker.clear()
	_subjects.append("")
	_subject_picker.add_item(WHOLE_LABEL)
	# The review pack is not a slice of the project but a slice of time, and it is the second thing
	# anybody reaches for: the change they are in the middle of making.
	_subjects.append(ContextReportScript.REVIEW)
	_subject_picker.add_item(ContextReportScript.REVIEW_LABEL)
	for subject: String in ContextReportScript.subject_names():
		_subjects.append(subject)
		var entry: Dictionary = ContextReportScript.SUBJECTS[subject]
		var title: String = String(entry.get("title", subject))
		_subject_picker.add_item("%s - %s" % [subject, title])
	if _second_picker != null:
		_seconds.clear()
		_second_picker.clear()
		_seconds.append("")
		_second_picker.add_item(SECOND_NONE)
		for subject: String in ContextReportScript.subject_names():
			_seconds.append(subject)
			_second_picker.add_item(subject)
		_second_picker.select(0)


func _make_button(node_name: String, caption: String, action: Callable) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = caption
	button.focus_mode = Control.FOCUS_NONE
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Deliberately **not** clipped. A button that may be narrower than its own caption is a button
	# reading "Copy to clip" in a narrow dock, and a flow container wraps around a full caption on its
	# own: its minimum width is its widest child rather than the sum of them, so this stays narrow
	# without anyone having to lie about what the buttons say.
	button.pressed.connect(action)
	return button


## A checkbox that never takes focus: a focused control in a dock swallows the editor's space bar, and
## the tick's own action is bound the same way the buttons' actions are.
func _make_check(node_name: String, caption: String, action: Callable) -> CheckBox:
	var check := CheckBox.new()
	check.name = node_name
	check.text = caption
	check.focus_mode = Control.FOCUS_NONE
	check.toggled.connect(action)
	return check


## A line that explains rather than acts. Dimmed with alpha rather than a colour, because the editor
## theme may be light or dark and a hardcoded grey is illegible in one of them.
func _dim(control: Control) -> void:
	control.modulate = Color(1, 1, 1, 0.72)


## Select a subject by name (`""` for the whole project snapshot). Refuses an unknown subject by
## name on the status line rather than silently falling back.
func select_subject(subject: String) -> bool:
	if not _built:
		build()
	var index: int = _subjects.find(subject)
	if index < 0:
		_say("There is no '%s' pack. The packs are: %s." % [
				subject, ", ".join(ContextReportScript.subject_names())])
		return false
	_subject_picker.select(index)
	_apply_subject(subject)
	return true


func _on_subject_selected(index: int) -> void:
	if index < 0 or index >= _subjects.size():
		return
	_apply_subject(_subjects[index])


## Choose a second pack to build alongside the first (`""` for none). A name that is not a subject is
## refused **by name**, the way the first picker's is, rather than silently building just the one.
func select_second(subject: String) -> bool:
	if not _built:
		build()
	if not subject.is_empty() and not ContextReportScript.has_subject(subject):
		_say("There is no '%s' pack. The packs are: %s." % [
				subject, ", ".join(ContextReportScript.subject_names())])
		return false
	var index: int = _seconds.find(subject)
	if index < 0:
		return false
	if _second_picker != null:
		_second_picker.select(index)
	_apply_second(subject)
	return true


func _on_second_selected(index: int) -> void:
	if index < 0 or index >= _seconds.size():
		return
	_apply_second(_seconds[index])


## Take the second choice on: the file it will be saved as changes with it, and a preview already on
## screen is rebuilt so it never disagrees with the two rows that describe it.
func _apply_second(subject: String) -> void:
	second_subject = subject
	if _path_line != null:
		_path_line.text = "Also saved as: %s" % target_path(current_subject)
	if has_second():
		_say("Also building the '%s' pack." % second_subject)
	else:
		_say("One pack again: %s." % _scope_words(current_subject))
	if not last_output.is_empty():
		refresh_preview()


## Whether a second pack is chosen **and can be built**: the whole snapshot and the change under review
## are not packs, so choosing either of them leaves a second one unbuildable rather than half built.
func has_second() -> bool:
	return (
		not second_subject.is_empty()
		and second_subject != current_subject
		and not current_subject.is_empty()
		and current_subject != ContextReportScript.REVIEW
	)


## The subjects the payload on screen is about: the chosen one, and the second when one is chosen.
func current_subjects() -> PackedStringArray:
	var subjects := PackedStringArray()
	if not current_subject.is_empty() and current_subject != ContextReportScript.REVIEW:
		subjects.append(current_subject)
	if has_second():
		subjects.append(second_subject)
	return subjects


## The content address of what is on screen - both subjects' files when a second pack is chosen.
func current_address() -> String:
	return ContextReportScript.pack_fingerprint(current_subjects())


func _apply_subject(subject: String) -> void:
	current_subject = subject
	var target: String = target_path(subject)
	if _path_line != null:
		_path_line.text = "Also saved as: %s" % target
	if _chosen_line != null:
		_chosen_line.text = ContextReportScript.when_for(subject)
	_say("Selected %s (%s)." % [_scope_words(subject), target])


## The file path this dock writes to for `subject`, rooted under `output_dir`. A two-pack build gets a
## file named for both, so it can overwrite neither pack's own file nor the whole snapshot.
func target_path(subject: String = current_subject) -> String:
	var declared: String = ContextReportScript.output_path(subject)
	if has_second():
		declared = ContextReportScript.pair_output_path(current_subject, second_subject)
	var file_name: String = declared.trim_prefix("user://")
	if output_dir == "user://" or output_dir.is_empty():
		return "user://" + file_name
	return output_dir.path_join(file_name)


## Set the optional task prompt that is appended to the foot of the snapshot.
func set_prompt(prompt_text: String) -> void:
	if not _built:
		build()
	_prompt_box.text = prompt_text


func prompt_text() -> String:
	if _prompt_box == null:
		return ""
	return _prompt_box.text.strip_edges()


## Build the current scope's Markdown (plus any optional task prompt) and put it in the preview box.
func refresh_preview() -> String:
	if not _built:
		build()
	var attached: Dictionary = attachment()
	var base: String = ""
	if has_second():
		base = ContextReportScript.build_pair(current_subject, second_subject, attached)
	else:
		base = ContextReportScript.build_for(current_subject, attached)
	var extra: String = prompt_text()
	if not extra.is_empty():
		base += "\n## Request\n\n" + extra + "\n"
	last_output = base
	last_fingerprint = current_address()
	_said_stale = false
	_preview_box.text = last_output
	last_tokens = token_estimate()
	var measure: String = _measure_words(last_output)
	# No path here: the card above already says which file this is, and repeating it only makes the
	# line too long to read in a dock panel.
	_summary_line.text = "%s: %s" % [_scope_words(current_subject), measure]
	if last_tokens > LARGE_TOKENS:
		_summary_line.text += " Large for a web chat - consider a scoped pack."
		_summary_line.add_theme_color_override("font_color", WARN_COLOR)
	else:
		_summary_line.remove_theme_color_override("font_color")
	var words: String = _attachment_words()
	if (include_git() or current_subject == ContextReportScript.REVIEW) and _nothing_uncommitted(attached):
		words += " - nothing uncommitted, or git is not available here"
	_say("Built %s (%s)%s." % [_scope_words(current_subject), measure, words])
	return last_output


## Whether the uncommitted-work text came back empty, which needs saying out loud: a ticked box and no
## section in the pack would otherwise read as the dock having failed at something.
func _nothing_uncommitted(attached: Dictionary) -> bool:
	var status: String = String(attached.get("git_status", "")).strip_edges()
	var diff: String = String(attached.get("git_diff", "")).strip_edges()
	return status.is_empty() and diff.is_empty()


## Build the current scope, write it to its `user://` file, and return `true` when written.
func write_to_file() -> bool:
	refresh_preview()
	var path: String = target_path(current_subject)
	var folder: String = path.get_base_dir()
	if not folder.is_empty() and folder != "user:":
		DirAccess.make_dir_recursive_absolute(folder)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_say("Could not open %s for writing." % path)
		return false
	file.store_string(last_output)
	file.close()
	last_path = path
	_say("Wrote %s (%s) to %s." % [
			_scope_words(current_subject), _measure_words(last_output), path])
	exported.emit(current_subject, path, last_output.length())
	return true


## Build the current scope, write its file, and copy the full text to the OS clipboard so one click
## leaves both the file on disk and the text ready to paste.
func copy_to_clipboard() -> bool:
	if not write_to_file():
		return false
	DisplayServer.clipboard_set(last_output)
	_say("Copied %s (%s) to the clipboard and wrote %s." % [
			_scope_words(current_subject), _measure_words(last_output), last_path])
	return true


## An estimate of how many chat tokens the payload costs, at four characters per token. An empty
## argument measures the last built payload.
func token_estimate(text: String = "") -> int:
	var source: String = last_output if text.is_empty() else text
	return int(round(source.length() / float(CHARS_PER_TOKEN)))


## How large a payload is, in one phrase: `1,361 lines, 82 KB, ~21,000 tokens`. The one place that
## words a size, so the summary, the status line and the write message cannot disagree.
func _measure_words(text: String) -> String:
	var lines_n: int = text.count("\n") + 1
	var kb: int = int(round(text.to_utf8_buffer().size() / 1024.0))
	return "%s lines, %s KB, ~%s tokens" % [
			_thousands(lines_n), _thousands(kb), _thousands(token_estimate(text))]


## `1361` -> `1,361`, so a six-figure token count is read at a glance.
func _thousands(value: int) -> String:
	var digits: String = str(absi(value))
	var out := ""
	for index: int in digits.length():
		if index > 0 and (digits.length() - index) % 3 == 0:
			out += ","
		out += digits[index]
	return ("-" if value < 0 else "") + out


## Open the folder this dock writes to in the OS file manager, so a snapshot too large to paste can
## be dragged into the chat as a file instead. Names what went wrong rather than appearing to work.
func open_output_folder() -> bool:
	if not _built:
		build()
	var folder: String = target_path(current_subject).get_base_dir()
	if not folder.is_empty() and folder != "user:":
		DirAccess.make_dir_recursive_absolute(folder)
	var code: int = OS.shell_show_in_file_manager(ProjectSettings.globalize_path(folder), true)
	if code != OK:
		_say("Could not open %s in the file manager (code %d)." % [folder, code])
		return false
	_say("Opened %s in the file manager." % folder)
	return true


## Hand the dock the script somebody has open in the editor. `plugin.gd` is the only caller that can
## know which that is; a test calls this directly, which is how the source feature is covered with no
## editor anywhere.
##
## A new script does **not** rebuild a preview that is already on screen unless the box is ticked: a
## build is a second of work, and switching from tab to tab must not pay for it.
func set_source(path: String, text: String) -> void:
	if not _built:
		build()
	source_path = path
	source_text = text
	if _source_check != null:
		_source_check.disabled = path.is_empty()
		if path.is_empty():
			_source_check.button_pressed = false
	if _source_line != null:
		if path.is_empty():
			_source_line.text = SOURCE_NONE
		else:
			_source_line.text = "In hand: %s (%d lines)." % [path, text.count("\n") + 1]
	if include_source() and not last_output.is_empty():
		refresh_preview()


## Whether the next build carries the open script's source: only when the box is ticked **and** there
## is a script to carry.
func include_source() -> bool:
	return _source_check != null and _source_check.button_pressed and not source_path.is_empty()


func include_git() -> bool:
	return _git_check != null and _git_check.button_pressed


func include_run() -> bool:
	return _run_check != null and _run_check.button_pressed


## Everything to attach beyond the subject, gathered **only when its box is ticked**: a build with no
## boxes ticked does no work outside this dock at all.
func attachment() -> Dictionary:
	var attached: Dictionary = {}
	if include_source():
		attached["source_path"] = source_path
		attached["source_text"] = source_text
	if include_git() or current_subject == ContextReportScript.REVIEW:
		var git: Dictionary = _git_text()
		attached["git_status"] = String(git.get("status", ""))
		attached["git_diff"] = String(git.get("diff", ""))
		attached["last_commit"] = String(git.get("commit", ""))
		attached["recent_commits"] = String(git.get("recent", ""))
	if include_run():
		attached["last_run"] = _last_run_text()
	return attached


## `git status --short`, `git diff` and `git log -1 --stat` in the project folder, or the canned text a
## test handed over.
##
## `-C` names the folder rather than trusting the working directory: in the editor that directory
## belongs to the editor, which is not necessarily this project. A missing `git`, or a tree that is
## clean, answers with empty text - the pack then simply has no such section.
func _git_text() -> Dictionary:
	if git_reader.is_valid():
		var canned: Variant = git_reader.call()
		if canned is Dictionary:
			return canned
	var where: String = ProjectSettings.globalize_path("res://")
	var status: Array = []
	var diff: Array = []
	var commit: Array = []
	OS.execute("git", ["-C", where, "status", "--short"], status, true)
	OS.execute("git", ["-C", where, "diff"], diff, true)
	OS.execute("git", ["-C", where, "log", "-1", "--stat"], commit, true)
	# What has changed lately, about **this pack's own files** and not the repository: the paths come
	# from the same list the pack's content address covers, so the two cannot be about different files.
	# A commit to something else entirely is noise to a reader of this pack.
	var recent := PackedStringArray()
	var paths: PackedStringArray = ContextReportScript.pack_paths(current_subjects())
	if not paths.is_empty():
		# `git` wants repository-relative paths, and these are `res://` ones.
		var args := PackedStringArray(["-C", where, "log", "-n", "5", "--oneline", "--"])
		for path: String in paths:
			args.append(path.trim_prefix("res://"))
		var out: Array = []
		OS.execute("git", args, out, true)
		recent = PackedStringArray(out)
	return {
		"status": "\n".join(PackedStringArray(status)),
		"diff": "\n".join(PackedStringArray(diff)),
		"commit": "\n".join(PackedStringArray(commit)),
		"recent": "\n".join(recent),
	}


## The log `tools/run_tests.gd` leaves, or the canned text a test handed over.
func _last_run_text() -> String:
	if run_reader.is_valid():
		return String(run_reader.call())
	var path := "user://last_test_run.txt"
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text := file.get_as_text()
	file.close()
	return text


## What a build carried beyond the pack, in plain words, for the status line.
func _attachment_words() -> String:
	var parts := PackedStringArray()
	if include_source():
		parts.append("the open script")
	if include_git() or current_subject == ContextReportScript.REVIEW:
		if current_subject == ContextReportScript.REVIEW:
			parts.append("the change in hand")
		else:
			parts.append("what is not committed yet")
			if not ContextReportScript.pack_paths(current_subjects()).is_empty():
				parts.append("what has changed lately")
	if include_run():
		parts.append("the last test run")
	if parts.is_empty():
		return ""
	return " with " + ", ".join(parts)


## Ticking any of the boxes re-builds what is already on screen, so the preview never disagrees with
## them; before the first build there is nothing to keep in step, so it only says what will happen
## next. One handler rather than three, with the thing's own name bound to it.
func _on_extra_toggled(pressed: bool, what: String) -> void:
	if last_output.is_empty():
		_say("The next build %s %s." % ["carries" if pressed else "leaves out", what])
		return
	refresh_preview()


func _scope_words(subject: String) -> String:
	if has_second():
		return "the '%s' and '%s' packs" % [current_subject, second_subject]
	return "the whole snapshot" if subject.is_empty() else "the '%s' pack" % subject


func _say(line: String) -> void:
	last_words = line
	if _status_line != null:
		_status_line.text = line
	said.emit(line)
