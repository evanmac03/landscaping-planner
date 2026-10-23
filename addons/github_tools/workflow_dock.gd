@tool
extends VBoxContainer

var _thread: Thread
var _snapshot: Dictionary = {}
var _files: ItemList
var _staged: ItemList
var _commit_dialog: ConfirmationDialog
var _status: Label
var _message: LineEdit
var _branch: LineEdit
var _version: LineEdit
var _build: LineEdit
var _godot: LineEdit
var _output: TextEdit
var _confirm: ConfirmationDialog
var _pending: Dictionary
var _section: VBoxContainer
var _tabs: TabContainer
var _history: String = ""
var _guide_label: Label
var _guide_dialog: ConfirmationDialog
var _guide_body: VBoxContainer
var _guide_step: String = ""
var _guide_files: Array[CheckBox] = []
var _guide_input: LineEdit
var _guide_godot: LineEdit
var _guide_tested: CheckBox
var _guide_version: String = ""
var _guide_error: Label
var _guide_reviewed: CheckBox
var _guide_diff: String = ""
var _guide_progress: Label
var _guide_branch: LineEdit
var _guide_commit_name: String = ""
var _guide_back_button: Button
var _guide_back_to_files: bool = false


func _ready() -> void:
	_status = Label.new()
	_status.text = "Save files, then Refresh status."
	add_child(_status)
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.custom_minimum_size = Vector2(280, 340)
	add_child(_tabs)
	_page("Git", "1. Changes → Stage → Commit → name your commit.")
	_button("Refresh status", _git.bind("Status"))
	_button("Tracked diff", _git.bind("Diff"))
	var changes_label := Label.new()
	changes_label.text = "Changes (not staged)"
	_section.add_child(changes_label)
	_files = ItemList.new()
	_files.select_mode = ItemList.SELECT_MULTI
	_files.custom_minimum_size.y = 160
	_section.add_child(_files)
	_button("Stage selected", _git.bind("Stage"))
	var staged_label := Label.new()
	staged_label.text = "Staged changes (next commit)"
	_section.add_child(staged_label)
	_staged = ItemList.new()
	_staged.select_mode = ItemList.SELECT_MULTI
	_staged.custom_minimum_size.y = 120
	_section.add_child(_staged)
	_button("Review staged diff", _git.bind("StagedDiff"))
	_button("Unstage selected", _git.bind("Unstage"))
	_branch = _field("New feature branch", "feature/my-change")
	_button("Create branch", _git.bind("Branch"))
	_button("Commit…", _name_commit)
	_page("Push", "2. Push committed work and open a pull request.\nReview and merge separately on GitHub.")
	_button("Check readiness", _workflow.bind("Plan"))
	_button("Fetch origin", _git.bind("Fetch"))
	_button("Push / open PR…", _workflow.bind("Push"))
	_page("Release", "3. Export Windows and prepare a private draft.\nRequires clean, synchronized main and export templates.")
	_version = _field("Version (also used by Publish)", "v0.1.0-rc.1")
	_godot = _field("Godot executable", OS.get_executable_path())
	_button("Prepare draft release…", _workflow.bind("Release"))
	var recovery := Label.new()
	recovery.text = "Interrupted preparation only:"
	_section.add_child(recovery)
	_build = _field("Retained build folder (recovery only)", "")
	_button("Recover existing draft…", _workflow.bind("RecoverDraft"))
	_page("Publish", "4. Publish the exact verified draft.\nFirst download and test the Windows package.\nUses the version entered in Release; never rebuilds assets.")
	var version_label := Label.new()
	version_label.text = "Version: " + _version.text
	_section.add_child(version_label)
	_version.text_changed.connect(func(value: String): version_label.text = "Version: " + value)
	_button("Publish verified draft…", _workflow.bind("Publish"))
	_page("Guided workflow", "Git → Push → Release → Publish\nAnswer each question before continuing. Cancel stops the guide without undoing completed operations.")
	_guide_label = Label.new()
	_guide_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_guide_label.text = "Save all editor files first. Review changes and run your tests before starting. No automatic tests, merge, pull or stash."
	_section.add_child(_guide_label)
	_guide_progress = Label.new()
	_guide_progress.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_section.add_child(_guide_progress)
	_button("Start: Git → Push → Release → Publish…", _guide_begin.bind("files"))
	_button("Resume after manual PR merge and sync…", _guide_begin.bind("release"))
	_button("Resume at verified draft publication…", _guide_begin.bind("publish"))
	_button("Open GitHub pull requests", func(): OS.shell_open("https://github.com/evanmac03/landscaping-planner/pulls"))
	_button("Open GitHub releases / drafts", func(): OS.shell_open("https://github.com/evanmac03/landscaping-planner/releases"))
	var output_label := Label.new()
	output_label.text = "Command output (all stages)"
	add_child(output_label)
	_output = TextEdit.new()
	_output.editable = false
	_output.custom_minimum_size = Vector2(260, 220)
	add_child(_output)
	_confirm = ConfirmationDialog.new()
	add_child(_confirm)
	_confirm.confirmed.connect(func(): _start(_pending))
	_commit_dialog = ConfirmationDialog.new()
	_commit_dialog.title = "Name commit"
	_commit_dialog.ok_button_text = "Create commit"
	var contents := VBoxContainer.new()
	var explanation := Label.new()
	explanation.text = "Commits all staged changes, not later unstaged edits.\nReview staged diff first. No automatic tests run."
	contents.add_child(explanation)
	_message = LineEdit.new()
	_message.placeholder_text = "Commit name / message"
	contents.add_child(_message)
	_commit_dialog.add_child(contents)
	add_child(_commit_dialog)
	_commit_dialog.confirmed.connect(_git.bind("Commit"))
	_guide_dialog = ConfirmationDialog.new()
	_guide_dialog.dialog_hide_on_ok = false
	_guide_dialog.ok_button_text = "Continue"
	var guide_scroll := ScrollContainer.new()
	guide_scroll.custom_minimum_size = Vector2(380, 400)
	guide_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_guide_dialog.add_child(guide_scroll)
	_guide_body = VBoxContainer.new()
	_guide_body.custom_minimum_size.x = 340
	_guide_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	guide_scroll.add_child(_guide_body)
	add_child(_guide_dialog)
	_guide_dialog.confirmed.connect(_guide_answer)
	_guide_dialog.canceled.connect(func(): _guide_label.text = "Paused. Completed operations remain in place. Inspect output before restarting or resuming.")
	_guide_back_button = _guide_dialog.add_button("Back", false, "back")
	_guide_dialog.custom_action.connect(func(action: String):
		if action == "back":
			_guide_back()
	)


func _guide_begin(step: String) -> void:
	if _thread != null or _guide_dialog.visible or _confirm.visible or _commit_dialog.visible:
		return
	_tabs.current_tab = 4
	_guide_label.text = "Reading current Git status…"
	_git("Status", step)


func _guide_field(title: String, value: String) -> LineEdit:
	var label := Label.new()
	label.text = title
	_guide_body.add_child(label)
	var field := LineEdit.new()
	field.text = value
	_guide_body.add_child(field)
	return field


func _guide_show(step: String) -> void:
	if step in ["after_stage", "after_branch", "after_commit"]:
		var next := {"after_stage": "branch", "after_branch": "commit", "after_commit": "push"}
		_git("Status", next[step])
		return
	if step == "files" and _snapshot.get("files", []).is_empty() and not _guide_back_to_files:
		step = "branch" if not _snapshot.get("staged", []).is_empty() else "push"
	_guide_back_to_files = false
	if step == "branch":
		step = "commit"
	if step == "commit":
		if not _snapshot.get("files", []).is_empty():
			_guide_label.text = "Stopped before commit: unstaged work remains and would block Push. Handle it in Git, then restart. Nothing was committed."
			return
		_git("StagedReview", "commit_review")
		return
	if step == "push" and (_snapshot.get("branch", "") in ["", "main"] or not _snapshot.get("files", []).is_empty() or not _snapshot.get("staged", []).is_empty()):
		_guide_label.text = "Push blocked before execution: needs a clean feature branch. Handle dirty work in Git first."
		return
	if step == "release" and (_snapshot.get("branch", "") != "main" or not _snapshot.get("files", []).is_empty() or not _snapshot.get("staged", []).is_empty()):
		_guide_label.text = "Release blocked: review/merge the PR on GitHub, switch to main and synchronize it, and handle all dirty work. Then resume after merge. Nothing was pulled or discarded."
		return
	_guide_step = step
	var stage: String = {"files": "Git", "branch": "Git", "commit_review": "Git", "push": "Push", "merge": "Review/merge", "release": "Release", "publish": "Publish", "done": "Complete"}.get(step, step)
	_guide_progress.text = "Git → Push → Review/merge → Release → Publish\nCurrent: " + stage
	for child in _guide_body.get_children():
		_guide_body.remove_child(child)
		child.queue_free()
	_guide_dialog.title = {"files": "1. Choose files", "commit_review": "2. Review and name commit", "push": "3. Push to GitHub", "merge": "4. Review and merge", "release": "5. Prepare draft", "publish": "6. Test and publish"}.get(step, "Guided workflow")
	var description := Label.new()
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_guide_body.add_child(description)
	match step:
		"files":
			description.text = "%s saved changes; %s already staged.\nCheck the files to include. Push needs a clean checkout; use the Git tab for partial commits. Back never undoes staging." % [_snapshot.get("files", []).size(), _snapshot.get("staged", []).size()]
			_guide_files.clear()
			var selection_buttons := HBoxContainer.new()
			for option in ["Select all", "Select none"]:
				var button := Button.new()
				button.text = option
				button.pressed.connect(_guide_select_files.bind(option == "Select all"))
				selection_buttons.add_child(button)
			_guide_body.add_child(selection_buttons)
			for file in _snapshot["files"]:
				var checkbox := CheckBox.new()
				checkbox.text = file
				checkbox.tooltip_text = file
				checkbox.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				_guide_files.append(checkbox)
				_guide_body.add_child(checkbox)
		"branch":
			description.text = "A feature branch is required. What should it be called? Existing edits stay in place."
			_guide_input = _guide_field("New branch", _branch.text)
		"commit_review":
			description.text = "Commit ALL %s staged files? Later unstaged edits stay out. The diff below includes the file paths." % _snapshot.get("staged", []).size()
			var diff := TextEdit.new()
			diff.editable = false
			diff.text = _guide_diff
			diff.custom_minimum_size = Vector2(340, 200)
			_guide_body.add_child(diff)
			_guide_reviewed = CheckBox.new()
			_guide_reviewed.text = "I reviewed the staged diff and any binary assets separately."
			_guide_reviewed.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_guide_body.add_child(_guide_reviewed)
			_guide_branch = null
			if _snapshot.get("branch", "") in ["", "main"]:
				_guide_branch = _guide_field("New feature branch", _branch.text)
			_guide_input = _guide_field("Commit name", _guide_commit_name)
		"push":
			description.text = "Push committed HEAD %s on %s to GitHub and open/reuse a PR? Requires a clean feature branch. Does not run tests, wait for CI, or merge." % [String(_snapshot.get("head", "")).left(8), _snapshot.get("branch", "")]
		"merge":
			description.text = "Push complete.\n1. Review the PR, tests and checks on GitHub.\n2. Merge there.\n3. Switch to main and synchronize outside this dock.\nThen check readiness, or Cancel and resume later."
		"release":
			description.text = "Prepare a private Windows draft? This exports committed main, pushes a version tag and uploads assets. Requires matching export templates. What unused version and Godot executable should be used?"
			_guide_input = _guide_field("Release version", _version.text)
			_guide_godot = _guide_field("Godot executable", _godot.text)
		"publish":
			description.text = "Publish an existing verified draft? Download and manually test its Windows ZIP first. This makes it visible to repository viewers; it does not rebuild. The backend rechecks the exact receipt, commit, tag and assets."
			_guide_input = _guide_field("Exact prepared version", _guide_version if not _guide_version.is_empty() else _version.text)
			_guide_tested = CheckBox.new()
			_guide_tested.text = "I tested this draft's Windows package and approve publication."
			_guide_tested.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_guide_body.add_child(_guide_tested)
		"done":
			_guide_label.text = "Publication completed. See command output for the release result. No Forgejo backup was made."
			return
	_guide_label.text = "Waiting for your answer: " + step + ". Cancel leaves completed work in place."
	_guide_error = Label.new()
	_guide_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_guide_body.add_child(_guide_error)
	_guide_dialog.ok_button_text = {"files": "Stage selected", "branch": "Create branch", "commit_review": "Create commit", "push": "Push and open PR", "merge": "Check main readiness", "release": "Prepare draft", "publish": "Publish release"}.get(step, "Continue")
	if step == "files" and _snapshot.get("files", []).is_empty():
		_guide_dialog.ok_button_text = "Review staged changes"
	_guide_back_button.visible = step in ["commit_review", "release", "publish"]
	_guide_dialog.reset_size()
	_guide_dialog.popup_centered()


func _guide_select_files(selected: bool) -> void:
	for checkbox in _guide_files:
		checkbox.button_pressed = selected


func _guide_back() -> void:
	if _thread != null:
		return
	match _guide_step:
		"commit_review":
			_guide_commit_name = _guide_input.text
			if _guide_branch != null:
				_branch.text = _guide_branch.text
			_guide_dialog.hide()
			_guide_back_to_files = true
			_git("Status", "files")
		"release":
			_version.text = _guide_input.text
			_godot.text = _guide_godot.text
			_guide_dialog.hide()
			_guide_show("merge")
		"publish":
			_guide_version = _guide_input.text
			_guide_dialog.hide()
			_guide_label.text = "Draft left unchanged. Test it using GitHub releases, then Resume at verified draft publication. Preparing another draft is not a Back action."


func _guide_answer() -> void:
	if _thread != null:
		return
	_guide_error.text = ""
	match _guide_step:
		"files":
			var selected_indices: Array[int] = []
			for index in _guide_files.size():
				if _guide_files[index].button_pressed:
					selected_indices.append(index)
			if selected_indices.size() != _guide_files.size():
				_guide_error.text = "Unselected dirty files would block Push. Handle excluded work deliberately in Git first, or select all reviewed files. Nothing was staged."
				return
			if selected_indices.is_empty():
				if not _snapshot.get("staged", []).is_empty():
					_guide_dialog.hide()
					_guide_show("branch")
				else:
					_guide_error.text = "No files selected or staged."
				return
			_files.deselect_all()
			for index in selected_indices:
				_files.select(index, false)
			_guide_dialog.hide()
			_git("Stage", "after_stage")
		"branch":
			var pattern := RegEx.create_from_string("^feature/[a-z0-9][a-z0-9-]*$")
			if pattern.search(_guide_input.text.strip_edges()) == null:
				_guide_error.text = "Use feature/lowercase-kebab-name."
				return
			_branch.text = _guide_input.text.strip_edges()
			_guide_dialog.hide()
			_git("Branch", "after_branch")
		"commit_review":
			if _guide_branch != null and RegEx.create_from_string("^feature/[a-z0-9][a-z0-9-]*$").search(_guide_branch.text.strip_edges()) == null:
				_guide_error.text = "Use feature/lowercase-kebab-name."
				return
			if _guide_input.text.strip_edges().is_empty() or _snapshot.get("staged", []).is_empty():
				_guide_error.text = "Commit needs staged files and a nonblank name."
				return
			if not _guide_reviewed.button_pressed:
				_guide_error.text = "Review the diff and confirm before committing."
				return
			_message.text = _guide_input.text.strip_edges()
			_guide_commit_name = _message.text
			if _guide_branch != null:
				_branch.text = _guide_branch.text.strip_edges()
			_guide_dialog.hide()
			_git("Commit", "after_commit")
		"push":
			_guide_dialog.hide()
			_workflow("Push", "merge")
		"merge":
			_guide_dialog.hide()
			_git("Status", "release")
		"release":
			if not _valid_version(_guide_input.text.strip_edges()):
				_guide_error.text = "Use a version such as v0.2.0 or v0.2.0-rc.1."
				return
			if not FileAccess.file_exists(_guide_godot.text.strip_edges()):
				_guide_error.text = "Choose an existing Godot executable."
				return
			_version.text = _guide_input.text.strip_edges()
			_godot.text = _guide_godot.text.strip_edges()
			_guide_version = _version.text
			_guide_dialog.hide()
			_workflow("Release", "publish")
		"publish":
			if not _valid_version(_guide_input.text.strip_edges()):
				_guide_error.text = "Enter the exact prepared version, such as v0.2.0-rc.1."
				return
			if not _guide_tested.button_pressed:
				_guide_error.text = "Test the downloaded draft and explicitly approve publication."
				return
			_version.text = _guide_input.text.strip_edges()
			_guide_dialog.hide()
			_workflow("Publish", "done")


func _valid_version(value: String) -> bool:
	return RegEx.create_from_string("^v[0-9]+\\.[0-9]+\\.[0-9]+(?:-[0-9A-Za-z]+(?:[.-][0-9A-Za-z]+)*)?$").search(value) != null


func _name_commit() -> void:
	if _thread != null:
		return
	if _snapshot.is_empty() or _snapshot.get("staged", []).is_empty():
		_output.text = "Refresh status and stage changes first."
		return
	_commit_dialog.dialog_text = ""
	_message.text = ""
	_commit_dialog.popup_centered()
	_message.grab_focus()


func _page(title: String, description: String) -> void:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(scroll)
	_section = VBoxContainer.new()
	_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_section)
	var label := Label.new()
	label.text = description
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_section.add_child(label)


func _field(title: String, value: String) -> LineEdit:
	var label := Label.new()
	label.text = title
	_section.add_child(label)
	var field := LineEdit.new()
	field.text = value
	_section.add_child(field)
	return field


func _button(title: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = title
	button.pressed.connect(callback)
	_section.add_child(button)


func _git(action: String, guide_next: String = "") -> void:
	if action in ["Branch", "Stage", "Unstage", "Commit"] and _snapshot.is_empty():
		_output.text = "Refresh status first."
		return
	var request := _snapshot.duplicate(true)
	request["action"] = action
	request["name"] = _branch.text
	request["message"] = _message.text
	if action == "Commit" and guide_next == "after_commit" and _snapshot.get("branch", "") in ["", "main"]:
		request["new_branch"] = _branch.text
	var selected: Array[String] = []
	var list := _staged if action == "Unstage" else _files
	for index in list.get_selected_items():
		selected.append(list.get_item_text(index))
	request["files"] = selected
	var encoded := Marshalls.raw_to_base64(JSON.stringify(request).to_utf8_buffer())
	var command := {
		"args": ["-NoProfile", "-NonInteractive", "-File",
			ProjectSettings.globalize_path("res://tools/editor-git.ps1"), "-Request", encoded],
		"status": action == "Status",
		"refresh": action in ["Branch", "Stage", "Unstage", "Commit"],
		"guide_next": guide_next,
		"review": action == "StagedReview",
	}
	if not guide_next.is_empty():
		command["refresh"] = false
		_start(command)
	elif action == "Commit":
		_start(command)
	elif action == "Branch":
		_ask(command, "Create %s at the reviewed HEAD? Existing edits stay in place." % _branch.text)
	else:
		_start(command)


func _workflow(action: String, guide_next: String = "") -> void:
	var args := ["-NoProfile", "-NonInteractive", "-File",
		ProjectSettings.globalize_path("res://tools/github.ps1"), "-Action", action]
	if action in ["Release", "RecoverDraft", "Publish"]:
		args.append_array(["-Version", _version.text])
	if action == "Release":
		args.append_array(["-Godot", _godot.text])
	if action == "RecoverDraft":
		args.append_array(["-BuildDirectory", _build.text])
	if action != "Plan":
		args.append("-Approve")
	var command := {"args": args, "status": false, "guide_next": guide_next}
	if action == "Plan" or not guide_next.is_empty():
		_start(command)
	else:
		_ask(command, "%s for version %s?\nPush writes a branch/PR. Release writes a tag and draft. RecoverDraft verifies an existing build. Publish makes the exact verified draft public to repository viewers.\nSave your files first. No automatic merge or playtest." % [action, _version.text])


func _ask(command: Dictionary, text: String) -> void:
	if _thread != null:
		return
	_pending = command
	_confirm.dialog_text = text
	_confirm.popup_centered()


func _start(command: Dictionary) -> void:
	if _thread != null:
		_output.text += "\nA command is already running."
		return
	_output.text = _history + "\nRunning; output will appear when the command completes…"
	_thread = Thread.new()
	var error := _thread.start(_execute.bind(command))
	if error != OK:
		_thread = null
		_output.text = "Cannot start worker: " + error_string(error)


func _execute(command: Dictionary) -> Dictionary:
	var output: Array = []
	# Godot may inherit PowerShell 7's module path, which breaks Windows PowerShell cmdlets.
	var invocation := "$ProgressPreference = 'SilentlyContinue'; $env:PSModulePath = \"$PSHOME\\Modules;$env:ProgramFiles\\WindowsPowerShell\\Modules\"; & "
	var quoted: Array[String] = []
	var arguments: Array = command["args"].slice(3)
	for index in arguments.size():
		var argument := String(arguments[index])
		if index % 2 == 1:
			if argument not in ["-Request", "-Action", "-Version", "-Godot", "-BuildDirectory", "-Approve"]:
				return {"code": 1, "text": "Invalid command parameter.", "status": false}
			quoted.append(argument)
		else:
			quoted.append("'" + argument.replace("'", "''") + "'")
	invocation += " ".join(quoted)
	var utf16 := invocation.to_utf16_buffer()
	var encoded := Marshalls.raw_to_base64(utf16)
	var code := OS.execute("powershell.exe",
		PackedStringArray(["-NoProfile", "-NonInteractive", "-OutputFormat", "Text", "-EncodedCommand", encoded]), output, true, false)
	return {"code": code, "text": "\n".join(output), "status": command["status"], "refresh": command.get("refresh", false), "guide_next": command.get("guide_next", ""), "review": command.get("review", false)}


func _process(_delta: float) -> void:
	if _thread == null or _thread.is_alive():
		return
	var result: Dictionary = _thread.wait_to_finish()
	_thread = null
	_complete(result)


func _complete(result: Dictionary) -> void:
	_history += "\n[%s] Exit %s\n%s\n" % [Time.get_datetime_string_from_system(), result["code"], result["text"]]
	_output.text = _history
	if result.get("review", false) and result["code"] == 0:
		_guide_diff = result["text"]
	if not result["status"] and not result.get("review", false):
		_snapshot.clear()
		_status.text = "Refresh status before the next local change."
	if result["status"] and result["code"] == 0:
		var json := JSON.new()
		var parse_error := json.parse(result["text"].strip_edges())
		var parsed = json.data
		if parse_error != OK or not parsed is Dictionary or not parsed.has_all(["head", "branch", "files", "hashes", "staged", "index_tree"]):
			_invalidate_status()
			_history += "\nInvalid status response. Refresh status before continuing.\n"
			_output.text = _history
			_guide_label.text = "Stopped: invalid status response. No later step ran."
			return
		_snapshot = parsed
		_status.text = "%s — %s\nSelect files explicitly; untracked files included." % [parsed["branch"], String(parsed["head"]).left(8)]
		_files.clear()
		for file in parsed["files"]:
			_files.add_item(file)
		_staged.clear()
		for file in parsed["staged"]:
			_staged.add_item(file)
	elif result["status"]:
		_invalidate_status()
	if result.get("refresh", false):
		_git("Status")
	if not result.get("guide_next", "").is_empty():
		if result["code"] == 0:
			_guide_show(result["guide_next"])
		else:
			_guide_label.text = "Stopped after an error. Inspect output and local/GitHub state before retrying. No later step ran; completed operations were not undone."


func _invalidate_status() -> void:
	_snapshot.clear()
	_files.clear()
	_staged.clear()
	_status.text = "Status unavailable. Refresh before making local changes."


func finish() -> void:
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null
