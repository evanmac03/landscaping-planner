@tool
extends VBoxContainer

var _thread: Thread
var _snapshot: Dictionary = {}
var _files: ItemList
var _staged: ItemList
var _status: Label
var _commit_message: String = ""
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
var _single_step: String = ""
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
var _result_dialog: AcceptDialog
var _result_summary: Label
var _result_link: LinkButton
var _result_next: String = ""
var _result_url: String = ""
var _guide_result: Label
var _github_url: String = "https://github.com/evanmac03/landscaping-planner/releases"
var _test_package: Dictionary = {}
var _draft_choices: Array = []
var _draft_picker: OptionButton
var _sync_distance: String = ""
var _running_since: int = 0
var _running_label: String = ""
var _running_status: Label
var _checks_label: Label
var _checks_summary: String = "Local validation: not checked this session.\nGitHub CI: not queried. Local tests are not CI."
var _phase_file: String = ""
var _release_receipt: String = ""
var _preview: bool = false
var _cleanup_branch: CheckBox
var _preview_saved: Dictionary = {}
var _preview_snapshot: Dictionary = {}
var _adviser_outcomes: Array[Dictionary] = []
var _adviser_evidence: Dictionary = {}


func _ready() -> void:
	_status = Label.new()
	_status.text = "Save files, then Refresh status."
	add_child(_status)
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.custom_minimum_size = Vector2(280, 340)
	add_child(_tabs)
	_page("Git", "The Guided workflow Git step, run on its own.\nReview files, staged diff, branch and commit name, then validate. Stops before Push.")
	_button("Review and commit…", _single_begin.bind("Git"))
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
	_page("Push", "2. Push committed work and open a pull request.\nReview and merge separately on GitHub.")
	_button("Check readiness", _workflow.bind("Plan"))
	_button("Fetch origin", _git.bind("Fetch"))
	_button("Push / open PR…", _single_begin.bind("Push"))
	_page("Release", "3. Export Windows and prepare a private draft.\nRequires clean, synchronized main and export templates.")
	_version = _field("Version (also used by Publish)", "v0.1.0-rc.1")
	_godot = _field("Godot executable", OS.get_executable_path())
	_button("Prepare draft release…", _single_begin.bind("Release"))
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
	_button("Test and publish verified draft…", _single_begin.bind("Publish"))
	_page("Guided workflow", "Git → Push → Release → Publish\nAnswer each question before continuing. Cancel stops the guide without undoing completed operations.")
	_guide_label = Label.new()
	_guide_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_guide_label.text = "Save all editor files first. Review changes and run your tests before starting. No automatic tests, merge, pull or stash."
	add_child(_guide_label)
	_guide_progress = Label.new()
	_guide_progress.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_guide_progress)
	_guide_result = Label.new()
	_guide_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_guide_result)
	_button("Copy last result summary", func(): DisplayServer.clipboard_set(_release_receipt))
	_button("View last publication (saved locally)", _workflow.bind("LastPublication", "receipt"))
	_button("Preview full guide (no Git/GitHub writes)", _begin_preview)
	_button("Exit preview", _end_preview)
	_checks_label = Label.new()
	_checks_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_checks_label.text = _checks_summary
	add_child(_checks_label)
	_button("Run local workflow checks", _workflow.bind("Validate", "checks"))
	_button("Refresh local / GitHub CI evidence", _workflow.bind("Evidence", "checks"))
	_button("Start / detect next step…", _workflow.bind("Discover", "discover"))
	_button("Resume after manual PR merge and sync…", _guide_begin.bind("release"))
	_button("Resume at verified draft publication…", _guide_begin.bind("publish"))
	_button("Open GitHub pull requests", _open_github.bind("https://github.com/evanmac03/landscaping-planner/pulls"))
	_button("Open GitHub releases / drafts", _open_github.bind("https://github.com/evanmac03/landscaping-planner/releases"))
	_page("AI adviser", "Optional, provider-neutral advice. Off by default.")
	var adviser := preload("res://addons/github_tools/adviser_panel.gd").new()
	adviser.context_source = _adviser_context
	_section.add_child(adviser)
	var output_label := Label.new()
	output_label.text = "Command output (all stages)"
	add_child(output_label)
	_output = TextEdit.new()
	_output.editable = false
	_output.custom_minimum_size = Vector2(260, 220)
	add_child(_output)
	_running_status = Label.new()
	_running_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_running_status)
	_confirm = ConfirmationDialog.new()
	add_child(_confirm)
	_confirm.confirmed.connect(func(): _start(_pending))
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
	_result_dialog = AcceptDialog.new()
	_result_dialog.ok_button_text = "Continue"
	var result_scroll := ScrollContainer.new()
	result_scroll.custom_minimum_size = Vector2(400, 360)
	result_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_result_dialog.add_child(result_scroll)
	var result_body := VBoxContainer.new()
	result_body.custom_minimum_size.x = 360
	result_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_result_summary = Label.new()
	_result_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result_body.add_child(_result_summary)
	_result_link = LinkButton.new()
	_result_link.text = "Open on GitHub"
	_result_link.pressed.connect(func(): _open_github(_result_url))
	result_body.add_child(_result_link)
	result_scroll.add_child(result_body)
	var copy_receipt := Button.new()
	copy_receipt.text = "Copy result summary"
	copy_receipt.pressed.connect(func(): DisplayServer.clipboard_set(_release_receipt))
	result_body.add_child(copy_receipt)
	add_child(_result_dialog)
	_result_dialog.confirmed.connect(func():
		var next := _result_next
		_result_next = ""
		if not next.is_empty():
			_guide_show(next)
	)
	_result_dialog.canceled.connect(func():
		_result_next = ""
		_guide_label.text = "Paused after a completed operation. See the result above; use the appropriate resume button."
	)


func _guide_begin(step: String) -> void:
	_begin_step(step, "")


func _single_begin(operation: String) -> void:
	_begin_step({"Git":"files", "Push":"push", "Release":"release", "Publish":"publish"}[operation], operation)


func _begin_step(step: String, operation: String) -> void:
	if _thread != null or _guide_dialog.visible or _confirm.visible or _result_dialog.visible:
		return
	_single_step = operation
	if operation.is_empty():
		_tabs.current_tab = 4
	if step == "publish":
		_guide_version = _version.text
		_test_package.clear()
	_guide_label.text = "Reading current Git status…"
	_git("Status", step)


func _adviser_context() -> Dictionary:
	var steps := ["files", "branch", "commit_review", "validate_commit", "push", "merge", "sync_main", "release", "publish", "publish_confirm", "sync", "drafts", "done"]
	return {
		"captured_at_utc":Time.get_datetime_string_from_system(true),
		"mode":"preview" if _preview else "live",
		"step":_guide_step if _guide_step in steps else "not_started",
		"operation_running":_thread != null,
		"status_snapshot_available":not _snapshot.is_empty(),
		"unstaged_count":_snapshot.get("files", []).size(),
		"staged_count":_snapshot.get("staged", []).size(),
		"package_selected":not _test_package.is_empty(),
		"outcomes":_adviser_outcomes.duplicate(true),
		"evidence":_adviser_evidence.duplicate(true),
		"evidence_note":"Session-only sanitized observations. Stale after external changes; inspect current workflow evidence before acting.",
		"approval_policy":"User approval required. Adviser cannot modify workflow state."
	}


func _open_github(url: String) -> void:
	if _preview:
		_guide_label.text = "PREVIEW ONLY: GitHub link opening simulated."
		return
	var error := OS.shell_open(url)
	if error != OK:
		_output.text += "\nCannot open GitHub: " + error_string(error)


func _begin_preview() -> void:
	if _preview or _thread != null or _guide_dialog.visible or _result_dialog.visible or _confirm.visible:
		return
	_preview_saved = {"branch":_branch.text, "version":_version.text, "godot":_godot.text, "message":_commit_message, "guide_version":_guide_version, "receipt":_release_receipt, "package":_test_package.duplicate(true), "checks":_checks_summary, "result":_guide_result.text, "url":_github_url, "commit_name":_guide_commit_name, "single_step":_single_step}
	_single_step = ""
	_preview = true
	_preview_saved["adviser_outcomes"] = _adviser_outcomes.duplicate(true)
	_preview_saved["adviser_evidence"] = _adviser_evidence.duplicate(true)
	_adviser_outcomes.clear()
	_adviser_evidence.clear()
	_test_package.clear()
	_version.text = "v9.9.9-preview"
	_guide_version = _version.text
	_branch.text = "feature/preview"
	_guide_commit_name = ""
	_preview_snapshot = {"head":"preview-commit", "branch":"main", "files":["example.txt"], "staged":[], "hashes":{}, "index_tree":"preview-tree"}
	_tabs.current_tab = 4
	_git("Status", "files")


func _end_preview() -> void:
	if not _preview or _thread != null:
		return
	_guide_dialog.hide()
	_result_dialog.hide()
	_confirm.hide()
	_result_next = ""
	_pending = {}
	_preview = false
	_branch.text = _preview_saved["branch"]
	_version.text = _preview_saved["version"]
	_godot.text = _preview_saved["godot"]
	_commit_message = _preview_saved["message"]
	_single_step = _preview_saved["single_step"]
	_guide_version = _preview_saved["guide_version"]
	_release_receipt = _preview_saved["receipt"]
	_test_package = _preview_saved["package"]
	_checks_summary = _preview_saved["checks"]
	_checks_label.text = _checks_summary
	_guide_result.text = _preview_saved["result"]
	_github_url = _preview_saved["url"]
	_guide_commit_name = _preview_saved["commit_name"]
	_adviser_outcomes.assign(_preview_saved["adviser_outcomes"])
	_adviser_evidence = _preview_saved["adviser_evidence"]
	_preview_saved.clear()
	_guide_step = ""
	_guide_back_to_files = false
	_invalidate_status()
	_guide_label.text = "Preview ended. No Git/GitHub operation ran. Refresh real status before continuing."
	_guide_progress.text = ""


func _preview_command(command: Dictionary) -> void:
	if not _preview:
		return
	var result := {"code":0, "text":"PREVIEW ONLY: simulated operation; nothing written or launched.", "status":command.get("status", false), "action":command.get("action", ""), "version":_version.text, "guide_next":command.get("guide_next", ""), "review":command.get("review", false)}
	if command.has("package"):
		result["purpose"] = command["purpose"]
		result["package"] = command["package"]
	elif command.has("args") and "-Request" in command["args"]:
		var request: Dictionary = JSON.parse_string(Marshalls.base64_to_utf8(command["args"].back()))
		match request["action"]:
			"Status":
				if _guide_step == "merge" and result["guide_next"] == "release":
					_preview_snapshot["branch"] = "main"
				result["text"] = JSON.stringify(_preview_snapshot)
			"Stage":
				_preview_snapshot["files"] = []
				_preview_snapshot["staged"] = ["example.txt"]
			"StagedReview":
				result["text"] = "PREVIEW ONLY\ndiff --git a/example.txt b/example.txt\n+Example change"
			"Commit":
				_preview_snapshot["branch"] = _branch.text
				_preview_snapshot["staged"] = []
			_:
				result["guide_next"] = ""
	else:
		var metadata: Dictionary = {}
		match result["action"]:
			"Validate", "Evidence":
				metadata = {"commit":"preview-commit","local":{"state":"simulated","timestamp":"PREVIEW","checks":["Simulated suites; not executed"]},"ci":{"state":"simulated; not queried","head":"preview-commit","checks":[]}}
				if result["guide_next"] == "push":
					result["guide_next"] = "checks"
			"DownloadTest":
				metadata = {"version":_version.text,"commit":"preview-commit","identity":"preview-draft","release_id":"PREVIEW","prerelease":true,"folder":"","executable":"","manifest":{},"url":""}
			"SmokeTest":
				metadata = {"state":"simulated"}
			"Synchronize":
				_preview_snapshot["branch"] = "main"
				metadata = {"branch":"main","commit":"preview-commit"}
			"Push", "Release", "Publish":
				metadata = {"url":"","version":_version.text}
			_:
				result["guide_next"] = ""
		result["text"] += "\nEDITOR_RESULT:" + JSON.stringify(metadata)
	_complete(result)
	if command.get("action") == "Validate" and command.get("guide_next") == "push":
		_git("Status", "push")


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
		var next := {"after_stage": "branch", "after_branch": "commit", "after_commit": "validate_commit"}
		_git("Status", next[step])
		return
	if step == "files" and _snapshot.get("files", []).is_empty() and not _guide_back_to_files:
		step = "branch" if not _snapshot.get("staged", []).is_empty() else "push"
	if step == "push" and _single_step == "Git":
		_guide_step = ""
		_guide_label.text = "Git step finished. No Push was run. See output and validation evidence; use Push separately when ready."
		_output.text = _history + "\n" + _guide_label.text
		return
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
	if step == "sync_main" and (not String(_snapshot.get("branch", "")).begins_with("feature/") or not _snapshot.get("files", []).is_empty() or not _snapshot.get("staged", []).is_empty()):
		_guide_label.text = "Synchronization needs a clean, reviewed feature branch. If already on main, use Check main readiness."
		return
	_guide_step = step
	var stage: String = {"files": "Git", "branch": "Git", "commit_review": "Git", "validate_commit": "Validate commit", "push": "Push", "merge": "Review/merge", "release": "Release", "publish": "Test package", "publish_confirm": "Publish", "sync": "Synchronize main", "drafts": "Choose draft", "done": "Complete"}.get(step, step)
	_guide_progress.text = "Git → Push → Review/merge → Release → Test → Publish\nCurrent: " + stage
	for child in _guide_body.get_children():
		_guide_body.remove_child(child)
		child.queue_free()
	_guide_dialog.title = {"files": "1. Choose files", "commit_review": "2. Review and name commit", "push": "3. Push to GitHub", "merge": "4. Review and merge", "release": "5. Prepare draft", "publish": "6. Test and publish"}.get(step, "Guided workflow")
	var description := Label.new()
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_guide_body.add_child(description)
	match step:
		"validate_commit":
			description.text = "Commit created: %s\nValidate this committed snapshot before Push? Earlier validation is now stale. Runs workflow, Git and Godot guide tests, not a full game test or CI." % _snapshot.get("head", "")
			_guide_godot = _guide_field("Godot executable", _godot.text)
		"files":
			description.text = "%s saved changes; %s already staged.\nSelect ALL reviewed changes to continue. Handle partial commits outside this workflow. Select none clears the checklist but cannot continue with dirty files excluded. Back never undoes staging." % [_snapshot.get("files", []).size(), _snapshot.get("staged", []).size()]
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
				checkbox.text = file + (" (staged + newer edits)" if file in _snapshot.get("staged", []) else " (needs staging)")
				checkbox.tooltip_text = file
				checkbox.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				_guide_files.append(checkbox)
				_guide_body.add_child(checkbox)
			if not _snapshot.get("staged", []).is_empty():
				var staged_label := Label.new()
				staged_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				var staged_lines: Array[String] = []
				for file in _snapshot["staged"]:
					staged_lines.append(String(file) + (" — newer edits listed above" if file in _snapshot.get("files", []) else " — ready; will not be staged again"))
				staged_label.text = "Already staged (included in commit):\n" + "\n".join(staged_lines)
				_guide_body.add_child(staged_label)
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
			description.text += "\n\n" + _checks_summary
		"merge":
			description.text = "Push complete.\n1. Review the PR, tests and checks on GitHub.\n2. Merge there.\n3. Use Synchronize main below, or switch and synchronize outside this dock.\nThen check readiness, or Cancel and resume later."
			var open_pr := Button.new()
			open_pr.text = "Open detected pull request"
			open_pr.pressed.connect(func(): _open_github(_github_url))
			_guide_body.add_child(open_pr)
			description.text += "\n\n" + _checks_summary
			var refresh_checks := Button.new()
			refresh_checks.text = "Refresh local / GitHub CI evidence"
			refresh_checks.pressed.connect(func():
				_guide_dialog.hide()
				_workflow("Evidence", "merge")
			)
			_guide_body.add_child(refresh_checks)
			var synchronize := Button.new()
			synchronize.text = "Synchronize main after GitHub merge…"
			synchronize.pressed.connect(func():
				_guide_dialog.hide()
				_git("Status", "sync_main")
			)
			_guide_body.add_child(synchronize)
		"sync_main":
			description.text = "After you merge on GitHub, synchronize main from reviewed feature %s at %s? This verifies an exact-head merged PR and fast-forwards main only. Dirty work, local-only main commits or an unmerged PR stop the operation. No automatic merge, stash or rebase." % [_snapshot.get("branch", ""), String(_snapshot.get("head", "")).left(8)]
			_cleanup_branch = CheckBox.new()
			_cleanup_branch.text = "Also delete this exact merged local feature branch after synchronization."
			_cleanup_branch.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_guide_body.add_child(_cleanup_branch)
		"release":
			description.text = "Prepare a private Windows draft? This exports committed main, pushes a version tag and uploads assets. Requires matching export templates. What unused version and Godot executable should be used?"
			_guide_input = _guide_field("Release version", _version.text)
			_guide_godot = _guide_field("Godot executable", _godot.text)
		"publish":
			description.text = "Test the exact Windows package before publication. Download verification, launch and interactive testing are separate checks."
			_guide_input = _guide_field("Exact prepared version", _guide_version if not _guide_version.is_empty() else _version.text)
			_guide_input.text_changed.connect(func(_value: String):
				_test_package.clear()
				_guide_tested.button_pressed = false
			)
			if not _test_package.is_empty():
				description.text += "\nDownload: verified\nVersion: %s\nCommit: %s" % [_test_package["version"], _test_package["commit"]]
			var download := Button.new()
			download.text = "Download and verify Windows ZIP"
			download.pressed.connect(_download_test)
			_guide_body.add_child(download)
			var smoke := Button.new()
			smoke.text = "Run verified build headless startup check"
			smoke.pressed.connect(func():
				if _test_package.is_empty() or _test_package.get("version") != _guide_input.text.strip_edges():
					_guide_error.text = "Download and verify this version first."
					return
				_guide_dialog.hide()
				_workflow("SmokeTest", "publish")
			)
			_guide_body.add_child(smoke)
			var open_folder := Button.new()
			open_folder.text = "Open verified package folder"
			open_folder.pressed.connect(_open_test_folder)
			_guide_body.add_child(open_folder)
			var launch := Button.new()
			launch.text = "Launch verified Windows build"
			launch.pressed.connect(_launch_test_package)
			_guide_body.add_child(launch)
			_guide_tested = CheckBox.new()
			_guide_tested.text = "I completed interactive testing of this exact version."
			_guide_tested.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_guide_body.add_child(_guide_tested)
		"publish_confirm":
			description.text = "Publish %s?\nCommit: %s\nDraft ID: %s\nType: %s\nVerified assets become visible to repository viewers. No rebuild or Forgejo backup." % [_test_package["version"], _test_package["commit"], str(_test_package.get("release_id", _test_package["identity"])), "Prerelease" if _test_package.get("prerelease", "-" in String(_test_package["version"])) else "Stable"]
		"sync":
			description.text = "Main needs synchronization.\nLocal-only / remote-only commits: %s\nInspect history and synchronize outside the dock, then Start / detect again. No pull, rebase or discard was performed." % _sync_distance
		"drafts":
			description.text = "Multiple prepared drafts match this commit. Choose the exact version to test. Nothing will be published yet."
			_draft_picker = OptionButton.new()
			for draft in _draft_choices:
				_draft_picker.add_item("%s — %s" % [draft["version"], String(draft["commit"]).left(8)])
			_guide_body.add_child(_draft_picker)
		"done":
			_guide_label.text = "PREVIEW ONLY completed. Nothing was committed, pushed, downloaded, launched or published. Use Exit preview." if _preview else "Publication completed. See command output for the release result. No Forgejo backup was made."
			return
	_guide_label.text = "Waiting for your answer: " + step + ". Cancel leaves completed work in place."
	_guide_error = Label.new()
	_guide_error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_guide_body.add_child(_guide_error)
	_guide_dialog.ok_button_text = {"files": "Stage selected", "branch": "Create branch", "commit_review": "Create commit", "push": "Push and open PR", "merge": "Check main readiness", "release": "Prepare draft", "publish": "Publish release"}.get(step, "Continue")
	if step == "publish":
		_guide_dialog.title = "6. Test Windows package"
		_guide_dialog.ok_button_text = "Review publication"
	elif step == "publish_confirm":
		_guide_dialog.title = "7. Approve publication"
		_guide_dialog.ok_button_text = "Publish this release"
	elif step == "sync":
		_guide_dialog.ok_button_text = "Close"
	elif step == "sync_main":
		_guide_dialog.title = "Approve main synchronization"
		_guide_dialog.ok_button_text = "Synchronize main"
	elif step == "validate_commit":
		_guide_dialog.title = "Validate committed work"
		_guide_dialog.ok_button_text = "Validate this commit"
	if step == "files" and _snapshot.get("files", []).is_empty():
		_guide_dialog.ok_button_text = "Review staged changes"
	_guide_back_button.visible = step in ["commit_review", "publish", "publish_confirm"] or (step == "release" and _single_step.is_empty())
	_guide_dialog.reset_size()
	_guide_dialog.popup_centered(Vector2i(640, 600))
	if _preview:
		_guide_dialog.title = "PREVIEW ONLY — " + _guide_dialog.title
		_guide_label.text = "PREVIEW ONLY. No commands, downloads, launches or publication will run. Exit preview to return to real work."


func _guide_select_files(selected: bool) -> void:
	for checkbox in _guide_files:
		checkbox.button_pressed = selected


func _guide_back() -> void:
	if _thread != null:
		return
	match _guide_step:
		"publish_confirm":
			_guide_dialog.hide()
			_guide_show("publish")
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
		"validate_commit":
			if not FileAccess.file_exists(_guide_godot.text.strip_edges()):
				_guide_error.text = "Choose an existing Godot executable."
				return
			_godot.text = _guide_godot.text.strip_edges()
			_guide_dialog.hide()
			_workflow("Validate", "push")
		"files":
			var selected_indices: Array[int] = []
			for index in _guide_files.size():
				if _guide_files[index].button_pressed:
					selected_indices.append(index)
			if selected_indices.size() != _guide_files.size():
				_guide_error.text = "Unselected dirty files would block Push. Handle excluded work deliberately outside this workflow, or select all reviewed files. Nothing was staged."
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
			_commit_message = _guide_input.text.strip_edges()
			_guide_commit_name = _commit_message
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
		"sync_main":
			_guide_dialog.hide()
			_workflow("Synchronize", "release")
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
			if _test_package.is_empty() or _test_package.get("version") != _guide_input.text.strip_edges():
				_guide_error.text = "Download and verify the exact version before confirming testing."
				return
			_version.text = _guide_input.text.strip_edges()
			_check_package("confirm")
		"publish_confirm":
			_guide_dialog.hide()
			_workflow("Publish", "done")
		"sync":
			_guide_dialog.hide()
		"drafts":
			_guide_version = _draft_choices[_draft_picker.selected]["version"]
			_github_url = _draft_choices[_draft_picker.selected]["url"]
			_test_package.clear()
			_guide_dialog.hide()
			_guide_show("publish")


func _valid_version(value: String) -> bool:
	return RegEx.create_from_string("^v[0-9]+\\.[0-9]+\\.[0-9]+(?:-[0-9A-Za-z]+(?:[.-][0-9A-Za-z]+)*)?$").search(value) != null


func _download_test() -> void:
	if _thread != null:
		return
	_version.text = _guide_input.text.strip_edges()
	if not _valid_version(_version.text):
		_guide_error.text = "Enter the exact prepared version first."
		return
	_test_package.clear()
	_guide_dialog.hide()
	_workflow("DownloadTest", "package_ready")


func _open_test_folder() -> void:
	if _preview:
		_guide_error.text = "PREVIEW ONLY: folder opening is simulated."
		return
	if _test_package.is_empty() or _test_package.get("version") != _guide_input.text.strip_edges():
		_guide_error.text = "Download and verify this version first."
		return
	var error := OS.shell_open(_test_package["folder"])
	if error != OK:
		_guide_error.text = "Cannot open folder: " + error_string(error)


func _launch_test_package() -> void:
	_check_package("launch")


func _check_package(purpose: String) -> void:
	if _thread != null:
		return
	if _test_package.is_empty() or _test_package.get("version") != _guide_input.text.strip_edges():
		_guide_error.text = "Download and verify this version first."
		return
	_guide_dialog.hide()
	_start({"package": _test_package.duplicate(true), "purpose": purpose, "action": "Checking package integrity"})


func _finish_package_check(result: Dictionary) -> void:
	if result["code"] != 0:
		_test_package.clear()
		_guide_show("publish")
		_guide_error.text = "Package changed, is missing or cannot be read. Testing approval cleared. Download and verify again."
		return
	if result.get("package", {}) != _test_package:
		_test_package.clear()
		_guide_show("publish")
		_guide_error.text = "Package selection changed during verification. Download and test again."
		return
	if result["purpose"] == "confirm":
		_guide_show("publish_confirm")
		return
	_guide_show("publish")
	if _preview:
		_guide_error.text = "PREVIEW ONLY: Windows launch simulated."
		return
	if OS.create_process(_test_package["executable"], PackedStringArray()) == -1:
		_guide_error.text = "Could not launch the verified Windows executable."
	else:
		_guide_error.text = "Build launched. Test it interactively; startup alone is not a playtest."


func _package_files(folder: String, prefix: String = "") -> Dictionary:
	var result: Dictionary = {}
	var directory := DirAccess.open(folder)
	if directory == null:
		return {"!error": "unreadable"}
	for file in directory.get_files():
		result[prefix + file] = FileAccess.get_sha256(folder.path_join(file))
	for subfolder in directory.get_directories():
		result.merge(_package_files(folder.path_join(subfolder), prefix + subfolder + "/"))
	return result


func _verify_test_files() -> bool:
	return _test_package.has("manifest") and _package_files(_test_package["folder"]) == _test_package["manifest"]


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
	if action == "Commit" and guide_next.is_empty():
		_single_begin("Git")
		return
	if action in ["Branch", "Stage", "Unstage", "Commit"] and _snapshot.is_empty():
		_output.text = "Refresh status first."
		return
	var request := _snapshot.duplicate(true)
	request["action"] = action
	request["name"] = _branch.text
	request["message"] = _commit_message
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
		"invalidates_checks": action in ["Branch", "Stage", "Unstage", "Commit"],
	}
	if not guide_next.is_empty():
		command["refresh"] = false
		_start(command)
	elif action == "Branch":
		_ask(command, "Create %s at the reviewed HEAD? Existing edits stay in place." % _branch.text)
	else:
		_start(command)


func _workflow(action: String, guide_next: String = "") -> void:
	if guide_next.is_empty() and action in ["Push", "Release", "Publish"]:
		_single_begin(action)
		return
	if action == "Discover" and guide_next == "discover":
		_single_step = ""
	var args := ["-NoProfile", "-NonInteractive", "-File",
		ProjectSettings.globalize_path("res://tools/github.ps1"), "-Action", action]
	if action in ["Release", "RecoverDraft", "Publish", "DownloadTest"]:
		args.append_array(["-Version", _version.text])
	if action in ["Release", "Validate"]:
		args.append_array(["-Godot", _godot.text])
	if action == "RecoverDraft":
		args.append_array(["-BuildDirectory", _build.text])
	if action == "SmokeTest":
		args.append_array(["-Package", Marshalls.utf8_to_base64(JSON.stringify(_test_package))])
	if action == "Synchronize":
		args.append_array(["-CleanupBranch", "yes" if _cleanup_branch.button_pressed else "no"])
	if not guide_next.is_empty() and action in ["Push", "Release", "Synchronize"]:
		args.append_array(["-ExpectedHead", _snapshot.get("head", ""), "-ExpectedBranch", _snapshot.get("branch", "")])
	if action == "Publish" and not guide_next.is_empty():
		args.append_array(["-ExpectedHead", _test_package.get("commit", ""), "-ExpectedBranch", "main", "-ExpectedDraft", _test_package.get("identity", "")])
	if action not in ["Plan", "Discover", "LastPublication", "Validate", "Evidence"]:
		args.append("-Approve")
	var command := {"args": args, "status": false, "guide_next": guide_next, "action": action, "version": _version.text}
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
	if _preview:
		_preview_command.call_deferred(command.duplicate(true))
		return
	if _thread != null:
		_output.text += "\nA command is already running."
		return
	if command.get("invalidates_checks", false) or command.get("action", "") in ["Push", "Release", "Publish", "Synchronize"]:
		_checks_summary = "Validation / CI evidence needs refresh after this operation. Previous results remain in output."
		_checks_label.text = _checks_summary
	_output.text = _history + "\nRunning; output will appear when the command completes…"
	_running_since = Time.get_ticks_msec()
	_running_label = command.get("action", "Git operation")
	_running_status.text = _running_label + " — starting…"
	if command.get("action", "") in ["Release", "Publish", "DownloadTest", "SmokeTest", "Synchronize", "Validate", "Evidence", "Discover", "Push"]:
		_phase_file = ProjectSettings.globalize_path("user://github-phase-%s.txt" % Time.get_ticks_usec())
		var insert_at: int = command["args"].size()
		if command["args"].back() == "-Approve":
			insert_at -= 1
		command["args"].insert(insert_at, "-PhaseFile")
		command["args"].insert(insert_at + 1, _phase_file)
	_thread = Thread.new()
	var error := _thread.start(_execute.bind(command))
	if error != OK:
		_thread = null
		_output.text = "Cannot start worker: " + error_string(error)
		_running_status.text = _output.text
		_clear_phase_file()


func _execute(command: Dictionary) -> Dictionary:
	if command.has("package"):
		var package: Dictionary = command["package"]
		var valid: bool = package.has("manifest") and _package_files(package["folder"]) == package["manifest"]
		return {"code": 0 if valid else 1, "text": "Package integrity verified." if valid else "Package integrity check failed.", "status": false, "purpose": command["purpose"], "package": package}
	var output: Array = []
	# Godot may inherit PowerShell 7's module path, which breaks Windows PowerShell cmdlets.
	var invocation := "$ProgressPreference = 'SilentlyContinue'; $env:PSModulePath = \"$PSHOME\\Modules;$env:ProgramFiles\\WindowsPowerShell\\Modules\"; & "
	var quoted: Array[String] = []
	var arguments: Array = command["args"].slice(3)
	for index in arguments.size():
		var argument := String(arguments[index])
		if index % 2 == 1:
			if argument not in ["-Request", "-Action", "-Version", "-Godot", "-BuildDirectory", "-Approve", "-ExpectedHead", "-ExpectedBranch", "-ExpectedDraft", "-PhaseFile", "-Package", "-CleanupBranch"]:
				return {"code": 1, "text": "Invalid command parameter.", "status": false}
			quoted.append(argument)
		else:
			quoted.append("'" + argument.replace("'", "''") + "'")
	invocation += " ".join(quoted)
	var utf16 := invocation.to_utf16_buffer()
	var encoded := Marshalls.raw_to_base64(utf16)
	var code := OS.execute("powershell.exe",
		PackedStringArray(["-NoProfile", "-NonInteractive", "-OutputFormat", "Text", "-EncodedCommand", encoded]), output, true, false)
	return {"code": code, "text": "\n".join(output), "status": command["status"], "refresh": command.get("refresh", false), "guide_next": command.get("guide_next", ""), "review": command.get("review", false), "action": command.get("action", ""), "version": command.get("version", "")}


func _process(_delta: float) -> void:
	if _thread == null:
		return
	if _thread.is_alive():
		var seconds := (Time.get_ticks_msec() - _running_since) / 1000
		_running_status.text = "%s — %ss elapsed. Output appears at completion. Do not close Godot." % [_running_label, seconds]
		if not _phase_file.is_empty() and FileAccess.file_exists(_phase_file):
			_running_status.text += "\nPhase: " + FileAccess.get_file_as_string(_phase_file).strip_edges()
		if seconds >= 60:
			_running_status.text += "\nStill waiting; elapsed time does not prove failure. No automatic timeout, cancellation or retry."
		return
	var result: Dictionary = _thread.wait_to_finish()
	_thread = null
	_clear_phase_file()
	_running_status.text = "Completed after %ss." % ((Time.get_ticks_msec() - _running_since) / 1000)
	_complete(result)


func _complete(result: Dictionary) -> void:
	var action: String = result.get("action", "")
	if action in ["Validate", "Evidence"]:
		_adviser_evidence = {"local":"unavailable", "ci":"unavailable", "mode":"preview" if _preview else "live", "captured_at_utc":Time.get_datetime_string_from_system(true)}
	if action in ["Validate", "Evidence", "Push", "Release", "Publish", "DownloadTest", "SmokeTest", "Synchronize"]:
		_adviser_outcomes.append({"operation":action, "mode":"preview" if _preview else "live", "result":"completed" if result["code"] == 0 else "failed_or_unconfirmed", "captured_at_utc":Time.get_datetime_string_from_system(true)})
		if _adviser_outcomes.size() > 20:
			_adviser_outcomes.pop_front()
	_history += "\n[%s] Exit %s\n%s\n" % [Time.get_datetime_string_from_system(), result["code"], result["text"]]
	_output.text = _history
	if result.has("purpose"):
		_finish_package_check(result)
		return
	var metadata: Dictionary = {}
	for line in String(result["text"]).split("\n"):
		if line.begins_with("EDITOR_RESULT:"):
			var parser := JSON.new()
			if parser.parse(line.trim_prefix("EDITOR_RESULT:")) != OK or not parser.data is Dictionary:
				_guide_label.text = "Stopped: invalid workflow result."
				return
			metadata = parser.data
	if result.get("action") == "SmokeTest":
		_guide_show("publish")
		var matched: bool = metadata.get("state") == "passed" and not _test_package.is_empty() and metadata.get("identity") == _test_package.get("identity") and metadata.get("version") == _test_package.get("version") and metadata.get("commit") == _test_package.get("commit")
		if result["code"] == 0 and (matched or (_preview and metadata.get("state") == "simulated")):
			_guide_error.text = "PREVIEW ONLY: startup check simulated." if _preview else "Headless startup passed; interactive testing is still required."
		else:
			_guide_error.text = "Headless startup failed or selection changed. Inspect output; no successful playtest is claimed."
		return
	if result.get("action") == "Synchronize" and result["code"] == 0:
		if metadata.get("branch") != "main" or not metadata.has("commit"):
			_guide_label.text = "Synchronization result invalid. Inspect Git before continuing."
			return
		_git("Status", "release")
		return
	if result.get("action", "") in ["Validate", "Evidence"]:
		if result["code"] != 0:
			_checks_summary = "Checks unavailable or failed. See command output; no pass is claimed. Refresh before relying on previous evidence."
		elif not metadata.has_all(["local", "ci", "commit"]):
			_checks_summary = "Checks response invalid. No pass is claimed."
		else:
			var local: Dictionary = metadata["local"]
			var ci: Dictionary = metadata["ci"]
			var local_state: String = local.get("state", "unavailable")
			var ci_state: String = ci.get("state", "unavailable")
			_adviser_evidence["local"] = local_state if local_state in ["passed", "stale", "not-run"] else "unavailable"
			_adviser_evidence["ci"] = ci_state if ci_state in ["reported", "not-queried", "no-open-pr", "no-checks-reported", "no-runs-reported", "different-head", "unavailable"] else "unavailable"
			var check_states: Array[Dictionary] = []
			for check in ci["checks"]:
				var state := String(check.get("status", check.get("state", ""))).to_lower()
				var conclusion := String(check.get("conclusion", "")).to_lower()
				check_states.append({"status":state if state in ["completed", "in_progress", "queued", "pending", "success", "failure", "error", "expected", "waiting", "requested"] else "unknown", "conclusion":conclusion if conclusion in ["success", "failure", "cancelled", "skipped", "neutral", "timed_out", "action_required", "stale", "startup_failure", ""] else "unknown"})
			_adviser_evidence["checks"] = check_states
			_checks_summary = "Evidence captured at %s (refresh after external changes).\nLocal validation: %s\nTimestamp (UTC): %s\nSuites: %s\nGitHub CI: %s\nCI head: %s\nLocal tests are not a CI pass." % [Time.get_datetime_string_from_system(), local["state"], local["timestamp"], ", ".join(local["checks"]), ci["state"], ci["head"]]
			for check in ci["checks"]:
				_checks_summary += "\n%s: %s %s" % [check.get("name", check.get("context", "Check")), check.get("status", check.get("state", "")), check.get("conclusion", "")]
			if ci.has("error"):
				_checks_summary += "\nGitHub retrieval error: " + String(ci["error"])
		_checks_label.text = _checks_summary
		if result.get("guide_next") == "merge" and result["code"] == 0:
			_guide_show("merge")
		elif result.get("guide_next") == "push":
			if result["code"] == 0 and metadata.get("local", {}).get("state") == "passed":
				_git("Status", "push")
			else:
				_guide_label.text = "Stopped before Push: committed-head validation failed or became stale. Inspect output and retry validation."
		return
	if result["code"] == 0 and result.get("action", "") in ["Discover", "DownloadTest"]:
		if metadata.is_empty():
			_guide_label.text = "Stopped: workflow did not return verified state."
			return
		if not metadata.get("url", "").is_empty():
			_github_url = metadata["url"]
			result["url"] = metadata["url"]
		if result["action"] == "DownloadTest":
			_test_package = metadata
			_guide_version = metadata["version"]
			_guide_show("publish")
			_guide_error.text = "ZIP hashes verified. Open the folder or launch the build. Interactive testing still required."
		else:
			if not metadata.get("version", "").is_empty():
				_guide_version = metadata["version"]
				_version.text = _guide_version
			_draft_choices = metadata.get("choices", [])
			_sync_distance = metadata.get("distance", "")
			_guide_result.text = "Detected next step: %s\n%s" % [metadata["next"], metadata.get("url", "")]
			_git("Status", metadata["next"])
		return
	if not metadata.get("url", "").is_empty():
		_github_url = metadata["url"]
		result["url"] = metadata["url"]
	result["receipt"] = metadata
	if result.get("action") == "LastPublication":
		if result["code"] == 0 and metadata.has_all(["published_at", "commit", "release_id", "assets", "version", "url"]):
			result["action"] = "Publish"
			result["version"] = metadata["version"]
			result["guide_next"] = ""
			_show_workflow_result(result)
			_result_dialog.title = "Saved publication receipt (historical)"
			_guide_label.text = "Loaded local historical receipt. This did not contact GitHub or publish; current remote state was not reverified."
			_release_receipt = "Historical local receipt — remote state not reverified.\n" + _release_receipt
			_result_summary.text = "Historical local receipt — remote state not reverified.\n" + _result_summary.text
			_guide_result.text = _release_receipt
		else:
			_guide_label.text = "Cannot load saved publication receipt. See output."
		return
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
			if result.get("action", "") in ["Push", "Release", "Publish"]:
				_show_workflow_result(result)
			else:
				_guide_show(result["guide_next"])
		else:
			_guide_label.text = "Stopped after an error. Inspect output and local/GitHub state before retrying. No later step ran; completed operations were not undone."
			_guide_result.text = "NOT CONFIRMED: %s did not complete successfully. A partial GitHub write may have occurred. Inspect GitHub and output before retrying." % result.get("action", "Operation")


func _show_workflow_result(result: Dictionary) -> void:
	var action: String = result["action"]
	var version: String = result.get("version", "")
	var summary: String
	_result_url = "https://github.com/evanmac03/landscaping-planner/"
	match action:
		"Push":
			_result_dialog.title = "Successfully pushed to GitHub"
			summary = "Committed work was pushed and a pull request was created or reused.\nNot merged. No release was published.\nNext: review the PR, tests and checks; merge and synchronize main."
			_result_url += "pulls"
		"Release":
			_result_dialog.title = "Draft successfully prepared"
			summary = "%s: Windows assets were uploaded and verified on GitHub.\nThe release is still a PRIVATE DRAFT, not published.\nNext: download and test the Windows ZIP, then approve Publish separately." % version
			_result_url += "releases"
		"Publish":
			_result_dialog.title = "Successfully published to GitHub"
			summary = "%s was successfully published on GitHub.\nThe verified draft is now visible to repository viewers.\nNo Forgejo backup was made." % version
			_result_url += "releases/tag/" + version.uri_encode()
	if String(result.get("url", "")).begins_with("https://github.com/evanmac03/landscaping-planner/"):
		_result_url = result["url"]
	if action == "Publish" and result.get("receipt", {}).has("published_at"):
		var receipt: Dictionary = result["receipt"]
		summary += "\nSource commit: %s\nPublished (UTC): %s\nRelease ID: %s\nType: %s\n%s" % [receipt["commit"], receipt["published_at"], str(receipt["release_id"]), "Prerelease" if receipt["prerelease"] else "Stable", receipt["verification"]]
		for asset in receipt["assets"]:
			summary += "\n%s\nSHA-256: %s" % [asset["name"], asset["sha256"]]
	_release_receipt = _result_dialog.title + "\n" + summary + "\n" + _result_url
	_guide_result.text = _result_dialog.title + "\n" + summary + "\n" + _result_url
	_result_summary.text = summary
	_result_next = "" if not _single_step.is_empty() else String(result["guide_next"])
	_result_dialog.ok_button_text = "Done" if _result_next.is_empty() or action == "Publish" else "Continue"
	_guide_label.text = "Completed: " + action + ". Review the result before continuing."
	_result_dialog.reset_size()
	_result_dialog.popup_centered(Vector2i(640, 520))
	if _preview:
		_result_dialog.title = "PREVIEW ONLY — simulated " + action
		_result_summary.text = "PREVIEW ONLY: no operation succeeded on GitHub.\n" + summary
		_release_receipt = "PREVIEW ONLY — simulated result; nothing published."
		_guide_result.text = _release_receipt
		_result_link.visible = false
	else:
		_result_link.visible = true


func _invalidate_status() -> void:
	_snapshot.clear()
	_files.clear()
	_staged.clear()
	_status.text = "Status unavailable. Refresh before making local changes."


func finish() -> void:
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null
	_clear_phase_file()


func _clear_phase_file() -> void:
	if not _phase_file.is_empty() and FileAccess.file_exists(_phase_file):
		var error := DirAccess.remove_absolute(_phase_file)
		if error != OK:
			_output.text += "\nCannot remove phase file: " + error_string(error)
	_phase_file = ""
