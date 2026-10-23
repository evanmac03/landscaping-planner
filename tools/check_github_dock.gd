extends SceneTree

class GuideProbe extends "res://addons/github_tools/workflow_dock.gd":
	var captured: Dictionary = {}

	func _start(command: Dictionary) -> void:
		captured = command

func _initialize() -> void:
	call_deferred("_test")

func _test() -> void:
	var script = load("res://addons/github_tools/workflow_dock.gd")
	var dock = script.new()
	root.add_child(dock)
	await process_frame
	if dock._tabs.get_tab_count() != 6:
		printerr("Expected six workflow tabs.")
		quit(1)
		return
	for index in 6:
		if dock._tabs.get_tab_title(index) != ["Git", "Push", "Release", "Publish", "Guided workflow", "AI adviser"][index]:
			printerr("Unexpected workflow tab.")
			quit(1)
			return
	if not _test_adviser(dock):
		quit(1)
		return
	dock._git("Status")
	var deadline := Time.get_ticks_msec() + 30000
	while dock._thread != null and Time.get_ticks_msec() < deadline:
		await create_timer(0.05).timeout
	if dock._thread != null or dock._snapshot.is_empty():
		printerr("Dock status failed: ", dock._output.text)
		dock.finish()
		quit(1)
		return
	print("PASS: dock builds and background Status populates branch/file selection: ", dock._snapshot["branch"])
	if dock._staged.item_count != dock._snapshot["staged"].size():
		printerr("Staged changes list does not match Git.")
		quit(1)
		return
	if not _test_single_steps():
		quit(1)
		return
	var first_output: String = dock._history
	dock._git("Status")
	deadline = Time.get_ticks_msec() + 30000
	while dock._thread != null and Time.get_ticks_msec() < deadline:
		await create_timer(0.05).timeout
	if dock._thread != null or dock._history.length() <= first_output.length() or not dock._history.begins_with(first_output) or dock._output.text.replace("\r", "") != dock._history.replace("\r", ""):
		printerr("Command output history was not retained.")
		dock.finish()
		quit(1)
		return
	print("PASS: automatic/status output retains previous command history.")
	var phase_script := "user://github-phase-test-" + str(Time.get_ticks_usec()) + ".ps1"
	var phase_source := FileAccess.open(phase_script, FileAccess.WRITE)
	phase_source.store_string("param([switch]$Approve, [string]$PhaseFile)\n[IO.File]::WriteAllText($PhaseFile, 'Exporting test package')\nStart-Sleep -Milliseconds 500\nWrite-Output 'Simulated operation completed.'\n")
	phase_source.close()
	dock._start({"args":["-NoProfile","-NonInteractive","-File",ProjectSettings.globalize_path(phase_script),"-Approve"],"status":false,"action":"Release"})
	var phase_path: String = dock._phase_file
	var saw_phase := false
	deadline = Time.get_ticks_msec() + 30000
	while dock._thread != null and Time.get_ticks_msec() < deadline:
		if "Exporting test package" in dock._running_status.text:
			saw_phase = true
		await create_timer(0.01).timeout
	dock.finish()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(phase_script))
	if not saw_phase or FileAccess.file_exists(phase_path) or not "Simulated operation completed." in dock._history:
		printerr("Live phase bridge or status-file cleanup failed.")
		dock.free()
		quit(1)
		return
	print("PASS: live PowerShell phase display, approval argument forwarding and temporary-file cleanup.")
	var integrity_folder := "user://github-worker-test-" + str(Time.get_ticks_usec())
	DirAccess.make_dir_absolute(integrity_folder)
	var integrity_path := integrity_folder.path_join("test.txt")
	var integrity_file := FileAccess.open(integrity_path, FileAccess.WRITE)
	integrity_file.store_string("test package")
	integrity_file.close()
	dock._guide_version = "v0.2.0-rc.1"
	dock._test_package = {"folder": integrity_folder, "manifest": dock._package_files(integrity_folder), "version": "v0.2.0-rc.1", "commit":"test-head", "identity":"test-identity"}
	dock._guide_show("publish")
	dock._guide_tested.button_pressed = true
	dock._guide_answer()
	var worker_started: bool = dock._thread != null
	deadline = Time.get_ticks_msec() + 30000
	while dock._thread != null and Time.get_ticks_msec() < deadline:
		await create_timer(0.01).timeout
	var worker_passed: bool = worker_started and dock._thread == null and dock._guide_step == "publish_confirm"
	dock._guide_dialog.hide()
	dock._guide_show("publish")
	dock._guide_tested.button_pressed = true
	integrity_file = FileAccess.open(integrity_path, FileAccess.WRITE)
	integrity_file.store_string("modified after testing")
	integrity_file.close()
	dock._guide_answer()
	deadline = Time.get_ticks_msec() + 30000
	while dock._thread != null and Time.get_ticks_msec() < deadline:
		await create_timer(0.01).timeout
	var worker_blocked: bool = dock._thread == null and dock._test_package.is_empty() and not dock._guide_tested.button_pressed and dock._guide_step == "publish"
	var has_running_result: bool = dock._running_status.text.begins_with("Completed after")
	dock.finish()
	DirAccess.remove_absolute(integrity_path)
	DirAccess.remove_absolute(integrity_folder)
	if not worker_passed or not worker_blocked or not has_running_result:
		printerr("Background integrity confirmation/invalidation or elapsed status failed.")
		dock.free()
		quit(1)
		return
	print("PASS: real background integrity check before testing approval; altered package invalidated; elapsed status.")
	dock.finish()
	dock.free()
	if not _test_guide():
		quit(1)
		return
	print("PASS: guided questions, command routing, manual merge pause and separate publication approval (no mutations).")
	if not _test_transitions():
		quit(1)
		return
	if not await _test_preview():
		quit(1)
		return
	print("PASS: completion routing, failed/malformed status invalidation, cancellation, scrollable long-file review.")
	quit(0)


func _test_single_steps() -> bool:
	var guide := GuideProbe.new()
	root.add_child(guide)
	var status := {"head":"test-head", "branch":"feature/test", "files":[], "staged":[], "hashes":{}, "index_tree":"tree"}
	var buttons := {"Git":"Review and commit…", "Push":"Push / open PR…", "Release":"Prepare draft release…", "Publish":"Test and publish verified draft…"}
	for operation in buttons:
		guide.captured = {}
		for button in guide._tabs.find_children("*", "Button", true, false):
			if button.text == buttons[operation]:
				button.pressed.emit()
		var step: String = {"Git":"files", "Push":"push", "Release":"release", "Publish":"publish"}[operation]
		if guide._single_step != operation or not guide.captured.get("status", false) or guide.captured.get("guide_next") != step:
			printerr("Individual operation did not enter shared status/step flow: ", operation)
			return false
		status["branch"] = "main" if operation in ["Release", "Publish"] else "feature/test"
		status["staged"] = ["sample.txt"] if operation == "Git" else []
		guide._complete({"code":0, "status":true, "text":JSON.stringify(status), "guide_next":step})
		if operation == "Git":
			if guide.captured.get("guide_next") != "commit_review":
				printerr("Individual Git bypassed staged review.")
				return false
			guide._complete({"code":0, "status":false, "review":true, "text":"+sample", "guide_next":"commit_review"})
			guide._guide_input.text = "Shared Git review"
			guide.captured = {}
			guide._guide_answer()
			if not guide.captured.is_empty() or not "Review the diff" in guide._guide_error.text:
				printerr("Individual Git skipped explicit diff approval.")
				return false
			guide._guide_reviewed.button_pressed = true
			guide._guide_answer()
			var request: Dictionary = JSON.parse_string(Marshalls.base64_to_utf8(guide.captured["args"][5]))
			if request["action"] != "Commit" or request["message"] != "Shared Git review":
				printerr("Individual Git did not use shared commit command.")
				return false
			guide.captured = {}
			guide._guide_show("after_commit")
			if guide.captured.get("guide_next") != "validate_commit":
				printerr("Individual Git skipped post-commit validation offer.")
				return false
			status["staged"] = []
			guide._complete({"code":0, "status":true, "text":JSON.stringify(status), "guide_next":"validate_commit"})
			guide._guide_answer()
			if guide.captured.get("action") != "Validate":
				printerr("Individual Git did not run shared committed-head validation.")
				return false
			guide._complete({"code":0, "status":false, "action":"Validate", "guide_next":"push", "text":'EDITOR_RESULT:{"commit":"test-head","local":{"state":"passed","timestamp":"TEST","checks":[]},"ci":{"state":"not-queried","head":"test-head","checks":[]}}'})
			if not guide.captured.get("status", false) or guide.captured.get("guide_next") != "push":
				printerr("Individual Git validation did not refresh status.")
				return false
			guide.captured = {}
			guide._complete({"code":0, "status":true, "text":JSON.stringify(status), "guide_next":"push"})
			if not guide.captured.is_empty() or not "No Push was run" in guide._guide_label.text:
				printerr("Individual Git continued into Push.")
				return false
		elif operation == "Publish":
			guide.captured = {}
			guide._guide_answer()
			if not guide.captured.is_empty() or not "Test the downloaded draft" in guide._guide_error.text:
				printerr("Individual Publish skipped interactive testing.")
				return false
			guide._test_package = {"version":guide._version.text, "commit":"test-head", "identity":"exact-draft", "release_id":123, "prerelease":true}
			guide._guide_tested.button_pressed = true
			guide._guide_answer()
			if guide.captured.get("purpose") != "confirm":
				printerr("Individual Publish skipped package integrity verification.")
				return false
			guide._finish_package_check({"code":0, "purpose":"confirm", "package":guide._test_package.duplicate(true)})
			if guide._guide_step != "publish_confirm":
				printerr("Individual Publish skipped final approval.")
				return false
			guide._guide_answer()
			var args: Array = guide.captured["args"]
			if args[args.find("-ExpectedDraft") + 1] != "exact-draft" or args[args.find("-ExpectedHead") + 1] != "test-head" or args[args.find("-ExpectedBranch") + 1] != "main":
				printerr("Individual Publish lost exact tested identity.")
				return false
		else:
			guide._guide_answer()
			var args: Array = guide.captured["args"]
			if guide.captured.get("action") != operation or args[args.find("-ExpectedHead") + 1] != "test-head":
				printerr("Individual operation lost shared approval/HEAD guard: ", operation)
				return false
		guide._guide_dialog.hide()
		if operation != "Git":
			guide._complete({"code":0, "status":false, "action":operation, "version":guide._version.text, "guide_next":"done", "text":"Simulated operation"})
			if not guide._result_next.is_empty() or guide._result_dialog.ok_button_text != "Done":
				printerr("Individual operation continued beyond its boundary: ", operation)
				return false
			guide._result_dialog.hide()
			guide.captured = {}
			guide._result_dialog.confirmed.emit()
			if not guide.captured.is_empty():
				printerr("Individual result confirmation launched the next operation.")
				return false
	guide._git("Commit")
	if guide._single_step != "Git" or not guide.captured.get("status", false):
		printerr("Direct commit dispatch bypassed the shared Git entry.")
		return false
	for operation in ["Push", "Release", "Publish"]:
		guide._workflow(operation)
		if guide._single_step != operation or not guide.captured.get("status", false):
			printerr("Direct operation dispatch bypassed shared entry: ", operation)
			return false
	guide._guide_begin("files")
	if not guide._single_step.is_empty():
		printerr("Full guide retained individual-step mode.")
		return false
	guide._workflow("Discover", "discover")
	if not guide._single_step.is_empty():
		return false
	guide.free()
	print("PASS: individual Git/Push/Release/Publish reuse guide approvals, tested identity and operation boundaries.")
	return true


func _test_adviser(dock) -> bool:
	var panel := preload("res://addons/github_tools/adviser_panel.gd").new()
	panel.context_source = dock._adviser_context
	root.add_child(panel)
	if panel._enabled.button_pressed or panel._body.visible:
		printerr("Adviser was not off by default.")
		return false
	panel._prepare("review_run")
	if not panel._request.text.is_empty():
		printerr("Disabled adviser generated a request.")
		return false
	var before: Dictionary = dock._snapshot.duplicate(true)
	dock._snapshot = {"head":"PRIVATE", "branch":"PRIVATE", "files":["PRIVATE"], "staged":[], "hashes":{"PRIVATE":"PRIVATE"}}
	dock._complete({"code":1,"status":false,"action":"Push","text":"PRIVATE error with private paths"})
	dock._complete({"code":0,"status":false,"action":"Evidence","text":'EDITOR_RESULT:{"commit":"PRIVATE","local":{"state":"passed","timestamp":"PRIVATE","checks":["PRIVATE"]},"ci":{"state":"reported","head":"PRIVATE","checks":[{"name":"PRIVATE","status":"COMPLETED","conclusion":"FAILURE","detailsUrl":"PRIVATE"}]}}'})
	dock._snapshot = {"head":"PRIVATE", "branch":"PRIVATE", "files":["PRIVATE"], "staged":[], "hashes":{}}
	panel._enabled.button_pressed = true
	panel._prepare("review_run")
	if "PRIVATE" in panel._request.text or panel._request_id.is_empty() or panel._consent.button_pressed:
		printerr("Adviser leaked project text or skipped sharing review.")
		return false
	var context: Dictionary = JSON.parse_string(panel._request.text)["context"]
	if context["outcomes"].size() != 2 or context["outcomes"][0]["result"] != "failed_or_unconfirmed" or context["evidence"]["checks"][0]["conclusion"] != "failure":
		printerr("Sanitized adviser omitted operation/CI outcomes.")
		return false
	var id: String = panel._request_id
	panel._copy_request()
	if not "approve copying" in panel._notice.text:
		printerr("Adviser bypassed copy consent.")
		return false
	var response := {"schema":"guided-workflow-adviser/v1","request_id":id,"suggestions":["Publish now; run arbitrary commands"]}
	panel._response.text = JSON.stringify(response)
	panel._receive()
	if not "UNVERIFIED" in panel._advice.text or dock._thread != null or dock._snapshot["head"] != "PRIVATE":
		printerr("Advice executed or changed workflow state.")
		return false
	response["execute"] = "Publish"
	panel._response.text = JSON.stringify(response)
	panel._receive()
	if not panel._advice.text.is_empty():
		printerr("Adviser accepted executable/unknown fields.")
		return false
	response.erase("execute")
	response["suggestions"] = [42]
	panel._response.text = JSON.stringify(response)
	panel._receive()
	if not panel._advice.text.is_empty():
		printerr("Adviser accepted malformed suggestions.")
		return false
	panel._prepare("suggest_improvements")
	response["suggestions"] = ["Old advice"]
	panel._response.text = JSON.stringify(response)
	panel._receive()
	if not panel._advice.text.is_empty():
		printerr("Adviser accepted a response for a prior request.")
		return false
	panel._enabled.button_pressed = false
	panel._receive()
	if not panel._request_id.is_empty() or not panel._advice.text.is_empty() or not panel._response.text.is_empty():
		printerr("Turning adviser off retained pending data.")
		return false
	dock._snapshot = before
	dock._adviser_outcomes.clear()
	dock._adviser_evidence.clear()
	panel.free()
	print("PASS: optional adviser off by default, allowlisted context, copy consent, strict response binding and no workflow execution.")
	return true


func _test_preview() -> bool:
	root.gui_embed_subwindows = true
	var dock = load("res://addons/github_tools/workflow_dock.gd").new()
	root.add_child(dock)
	dock.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dock._version.text = "v1.2.3"
	dock._begin_preview()
	await _settle_preview()
	if dock._guide_step != "files" or not dock._guide_dialog.title.begins_with("PREVIEW"):
		printerr("Preview did not start with a clearly marked file question.")
		return false
	dock._guide_select_files(true)
	dock._guide_dialog.confirmed.emit()
	await _settle_preview()
	if dock._guide_step != "commit_review":
		printerr("Preview did not reach staged diff review.")
		return false
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--capture-preview=") and DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			var capture_error := root.get_texture().get_image().save_png(argument.trim_prefix("--capture-preview="))
			if capture_error != OK:
				printerr("Could not capture rendered preview: ", capture_error)
				return false
	dock._guide_branch.text = "feature/preview"
	dock._guide_input.text = "Preview commit"
	dock._guide_reviewed.button_pressed = true
	dock._guide_dialog.confirmed.emit()
	await _settle_preview()
	if dock._guide_step != "validate_commit":
		printerr("Preview skipped validation question.")
		return false
	dock._guide_dialog.confirmed.emit()
	await _settle_preview()
	if dock._guide_step != "push":
		printerr("Preview validation did not reach Push.")
		return false
	dock._guide_dialog.confirmed.emit()
	await _settle_preview()
	if not dock._result_dialog.visible or not dock._result_dialog.title.begins_with("PREVIEW") or dock._result_link.visible:
		printerr("Preview push result claimed real success or enabled its link.")
		return false
	dock._result_dialog.hide()
	dock._result_dialog.confirmed.emit()
	for child in dock._guide_body.get_children():
		if child is Button and child.text == "Synchronize main after GitHub merge…":
			child.pressed.emit()
			break
	await _settle_preview()
	if dock._guide_step != "sync_main" or dock._cleanup_branch.button_pressed:
		printerr("Preview did not rehearse explicit synchronization approval.")
		return false
	dock._cleanup_branch.button_pressed = true
	dock._guide_dialog.confirmed.emit()
	await _settle_preview()
	if dock._guide_step != "release":
		printerr("Preview merge checkpoint did not reach Release.")
		return false
	dock._guide_dialog.confirmed.emit()
	await _settle_preview()
	dock._result_dialog.hide()
	dock._result_dialog.confirmed.emit()
	dock._download_test()
	await _settle_preview()
	if dock._guide_step != "publish" or dock._test_package.get("identity") != "preview-draft":
		printerr("Preview download did not return to testing.")
		return false
	for child in dock._guide_body.get_children():
		if child is Button and child.text == "Run verified build headless startup check":
			child.pressed.emit()
			break
	await _settle_preview()
	if dock._thread != null or not "simulated" in dock._guide_error.text:
		printerr("Preview smoke check started a worker or claimed a real pass.")
		return false
	dock._launch_test_package()
	await _settle_preview()
	dock._guide_tested.button_pressed = true
	dock._guide_dialog.confirmed.emit()
	await _settle_preview()
	if dock._guide_step != "publish_confirm":
		printerr("Preview skipped separate publication approval.")
		return false
	dock._guide_dialog.confirmed.emit()
	await _settle_preview()
	if not dock._result_dialog.title.begins_with("PREVIEW") or not dock._release_receipt.begins_with("PREVIEW"):
		printerr("Preview publication looked real.")
		return false
	dock._result_dialog.hide()
	dock._result_dialog.confirmed.emit()
	if not dock._guide_label.text.begins_with("PREVIEW ONLY completed"):
		printerr("Preview completion looked like real publication.")
		return false
	dock._end_preview()
	if dock._preview or dock._version.text != "v1.2.3" or not dock._snapshot.is_empty() or dock._thread != null:
		printerr("Exiting preview did not restore settings and clear synthetic status.")
		return false
	dock._begin_preview()
	dock._end_preview()
	await _settle_preview()
	if dock._preview or dock._thread != null or not dock._snapshot.is_empty():
		printerr("Exiting preview left deferred commands running.")
		return false
	dock.free()
	print("PASS: full preview via dialog signals, no subprocess/remote/package launch, settings restored.")
	return true


func _settle_preview() -> void:
	for index in 20:
		await process_frame


func _test_transitions() -> bool:
	var guide := GuideProbe.new()
	root.add_child(guide)
	guide._guide_show("after_commit")
	if guide.captured.get("guide_next") != "validate_commit":
		printerr("Commit completion skipped validation offer.")
		return false
	guide.captured = {}
	guide._snapshot = {"head":"committed-head", "branch":"feature/test", "files":[], "staged":[], "hashes":{}, "index_tree":"tree"}
	guide._guide_show("validate_commit")
	guide._guide_answer()
	if guide.captured.get("action") != "Validate" or guide.captured.get("guide_next") != "push":
		printerr("Post-commit validation question did not run committed-head checks.")
		return false
	guide.captured = {}
	guide._complete({"code":1,"status":false,"action":"Validate","guide_next":"push","text":"Simulated validation failure"})
	if not guide.captured.is_empty() or not "Stopped before Push" in guide._guide_label.text:
		printerr("Failed validation advanced to Push.")
		return false
	guide._complete({"code":0,"status":false,"action":"Validate","guide_next":"push","text":'EDITOR_RESULT:{"commit":"committed-head","local":{"state":"passed","timestamp":"2026-10-23T16:00:00Z","checks":["Workflow tests"]},"ci":{"state":"not-queried","head":"committed-head","checks":[]}}'})
	if guide.captured.get("guide_next") != "push" or not guide.captured.get("status", false):
		printerr("Successful validation did not refresh before Push.")
		return false
	guide.captured = {}
	var status := {"head": "test-head", "branch": "feature/test", "files": [], "staged": ["sample.txt"], "hashes": {}, "index_tree": "tree"}
	guide._complete({"code": 0, "text": "Selected files staged.", "status": false, "guide_next": "after_stage"})
	if guide.captured.get("guide_next") != "branch":
		printerr("Stage completion did not refresh before next question.")
		return false
	guide._complete({"code": 0, "text": JSON.stringify(status), "status": true, "guide_next": "branch"})
	if guide.captured.get("guide_next") != "commit_review":
		printerr("Status completion did not route to staged review.")
		return false
	guide._complete({"code": 0, "text": "+sample", "status": false, "review": true, "guide_next": "commit_review"})
	if guide._snapshot.is_empty() or not guide._guide_dialog.visible or guide._guide_diff != "+sample":
		printerr("Staged review lost its approved snapshot.")
		return false
	guide.captured = {}
	guide._guide_dialog.hide()
	guide._guide_dialog.canceled.emit()
	if not guide.captured.is_empty() or not "Paused" in guide._guide_label.text:
		printerr("Cancellation executed a command.")
		return false
	guide._complete({"code": 1, "text": "Simulated failure", "status": true, "guide_next": "push"})
	if not guide._snapshot.is_empty() or not guide.captured.is_empty() or not "Stopped" in guide._guide_label.text:
		printerr("Failed status retained stale state or advanced.")
		return false
	guide._snapshot = status.duplicate(true)
	guide._complete({"code": 0, "text": "invalid JSON", "status": true, "guide_next": "push"})
	if not guide._snapshot.is_empty() or not guide.captured.is_empty():
		printerr("Malformed status retained stale state or advanced.")
		return false
	var paths: Array[String] = []
	for index in 100:
		paths.append("long-path/file-%s.txt" % index)
	status["staged"] = paths
	guide._snapshot = status
	guide._guide_show("commit_review")
	if not guide._guide_body.get_parent() is ScrollContainer:
		printerr("Long review is not scrollable.")
		return false
	guide._guide_input.text = "Retained commit name"
	guide._guide_back()
	if guide._guide_commit_name != "Retained commit name" or guide.captured.get("guide_next") != "files":
		printerr("Back did not retain commit input or refresh scope.")
		return false
	guide._complete({"code": 0, "text": JSON.stringify(status), "status": true, "guide_next": "files"})
	if guide._guide_step != "files" or not guide._guide_dialog.visible:
		printerr("Back skipped the file screen.")
		return false
	guide._guide_dialog.hide()
	guide._guide_show("commit_review")
	if guide._guide_input.text != "Retained commit name":
		printerr("Review did not restore commit input.")
		return false
	if not "Selected files staged." in guide._history or not "Simulated failure" in guide._history:
		printerr("Transitions lost output history.")
		return false
	guide._guide_dialog.hide()
	for action in ["Push", "Release", "Publish"]:
		var next := {"Push": "merge", "Release": "publish", "Publish": "done"}
		guide._complete({"code": 0, "text": "Simulated successful operation", "status": false, "action": action, "version": "v0.2.0-rc.1", "guide_next": next[action]})
		if not guide._result_dialog.visible or guide._guide_dialog.visible or guide._result_next != next[action]:
			printerr("Success did not pause at the result screen.")
			return false
		if action == "Release" and not "not published" in guide._result_summary.text:
			printerr("Draft success was confused with publication.")
			return false
		if action == "Publish" and (not "successfully published" in guide._result_summary.text or not guide._result_url.ends_with("/releases/tag/v0.2.0-rc.1")):
			printerr("Publication confirmation or release link missing.")
			return false
		guide._result_dialog.hide()
	guide._complete({"code": 1, "text": "Simulated publish failure", "status": false, "action": "Publish", "guide_next": "done"})
	if guide._result_dialog.visible or not "NOT CONFIRMED" in guide._guide_result.text:
		printerr("Failure was shown as success.")
		return false
	guide.captured = {}
	guide._complete({"code": 0, "text": 'EDITOR_RESULT:{"next":"merge","url":"https://github.com/evanmac03/landscaping-planner/pull/2","version":""}', "status": false, "action": "Discover", "guide_next": "discover"})
	if guide.captured.get("guide_next") != "merge":
		printerr("Discovery failed to resume existing PR.")
		return false
	guide._complete({"code": 0, "text": 'EDITOR_RESULT:{"folder":"test-folder","executable":"test.exe","version":"v0.2.0-rc.1","commit":"test-head","identity":"42:hash","url":"https://github.com/evanmac03/landscaping-planner/releases/tag/draft"}', "status": false, "action": "DownloadTest", "guide_next": "package_ready"})
	if guide._test_package.get("version") != "v0.2.0-rc.1" or guide._guide_step != "publish":
		printerr("Verified package did not return to testing.")
		return false
	guide._guide_tested.button_pressed = true
	guide._guide_input.text = "v0.2.0-rc.2"
	guide._guide_input.text_changed.emit(guide._guide_input.text)
	if not guide._test_package.is_empty() or guide._guide_tested.button_pressed:
		printerr("Version change retained an unrelated package.")
		return false
	guide._guide_dialog.hide()
	guide._complete({"code": 0, "text": 'EDITOR_RESULT:{"url":"https://github.com/evanmac03/landscaping-planner/releases/tag/actual-draft"}', "status": false, "action": "Release", "version": "v0.2.0-rc.2", "guide_next": "publish"})
	if not guide._result_url.ends_with("/actual-draft"):
		printerr("Actual draft link was discarded.")
		return false
	guide._result_dialog.hide()
	var release_data := {"url":"https://github.com/evanmac03/landscaping-planner/releases/tag/v0.3.0", "published_at":"2026-10-23T16:00:00Z", "release_id":42, "commit":"source-commit", "prerelease":false, "verification":"Hashes verified", "assets":[{"name":"package.zip","sha256":"abc123"}]}
	guide._complete({"code":0,"status":false,"action":"Publish","version":"v0.3.0","guide_next":"done","text":"EDITOR_RESULT:" + JSON.stringify(release_data)})
	if not "source-commit" in guide._release_receipt or not "abc123" in guide._release_receipt or not "Stable" in guide._release_receipt or not "No Forgejo backup" in guide._release_receipt:
		printerr("Copyable release receipt omitted verification details.")
		return false
	guide._result_dialog.hide()
	release_data["version"] = "v0.3.0"
	guide._complete({"code":0,"status":false,"action":"LastPublication","guide_next":"receipt","text":"EDITOR_RESULT:" + JSON.stringify(release_data)})
	if not "historical" in guide._result_dialog.title or not "remote state not reverified" in guide._release_receipt or not guide._result_next.is_empty():
		printerr("Saved publication was not marked historical/read-only.")
		return false
	guide._result_dialog.hide()
	guide._sync_distance = "0 2"
	guide._guide_show("sync")
	if guide._guide_step != "sync" or guide._guide_dialog.ok_button_text != "Close":
		printerr("Unsynchronized main did not show an actionable stop.")
		return false
	guide._guide_dialog.hide()
	guide._draft_choices = [{"version":"v0.3.0-rc.1","url":"https://github.com/evanmac03/landscaping-planner/releases/tag/draft", "commit":"test-head"}]
	guide._guide_show("drafts")
	guide._guide_answer()
	if guide._guide_step != "publish" or guide._guide_input.text != "v0.3.0-rc.1":
		printerr("Draft chooser did not route selected version to testing.")
		return false
	var folder := "user://github-addon-integrity-test-" + str(Time.get_ticks_usec())
	DirAccess.make_dir_absolute(folder)
	var path := folder.path_join("example.txt")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("original")
	file.close()
	guide._test_package = {"folder":folder, "manifest":guide._package_files(folder)}
	var original_valid := guide._verify_test_files()
	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string("changed")
	file.close()
	var tampered_valid := guide._verify_test_files()
	file = FileAccess.open(path, FileAccess.WRITE)
	file.store_string("original")
	file.close()
	var extra_path := folder.path_join("added.dll")
	file = FileAccess.open(extra_path, FileAccess.WRITE)
	file.store_string("extra")
	file.close()
	var added_valid := guide._verify_test_files()
	DirAccess.remove_absolute(extra_path)
	DirAccess.remove_absolute(path)
	var missing_valid := guide._verify_test_files()
	DirAccess.remove_absolute(folder)
	if not original_valid or tampered_valid or added_valid or missing_valid:
		printerr("Package manifest did not detect tampering.")
		return false
	guide._guide_dialog.hide()
	guide._snapshot = {"head":"mixed-head", "branch":"feature/test", "files":["newer.txt"], "staged":["ready.txt","newer.txt"], "hashes":{}, "index_tree":"mixed-tree"}
	guide._files.clear()
	guide._files.add_item("newer.txt")
	guide._guide_show("files")
	if guide._guide_files.size() != 1 or not "staged + newer edits" in guide._guide_files[0].text:
		printerr("Mixed staging did not separate ready files from newer edits.")
		return false
	guide._guide_select_files(true)
	guide._guide_answer()
	var mixed_request = JSON.parse_string(Marshalls.base64_to_utf8(guide.captured["args"][-1]))
	if mixed_request["files"] != ["newer.txt"]:
		printerr("Mixed staging re-submitted already staged files.")
		return false
	guide._complete({"code":0,"status":false,"action":"Evidence","text":'EDITOR_RESULT:{"commit":"mixed-head","local":{"state":"stale","timestamp":"2026-10-23T16:00:00Z","checks":["Workflow tests"]},"ci":{"state":"no-checks-reported","head":"mixed-head","checks":[]}}'})
	if not "stale" in guide._checks_label.text or not "no-checks-reported" in guide._checks_label.text or not "not a CI pass" in guide._checks_label.text:
		printerr("Validation summary conflated stale local evidence with CI.")
		return false
	guide._complete({"code":0,"status":false,"action":"Evidence","text":'EDITOR_RESULT:{"commit":"mixed-head","local":{"state":"passed","timestamp":"2026-10-23T16:00:00Z","checks":["Workflow tests"]},"ci":{"state":"unavailable","head":"mixed-head","checks":[],"error":"Network outage"}}'})
	if not "Local validation: passed" in guide._checks_label.text or not "Network outage" in guide._checks_label.text:
		printerr("Network outage obscured local evidence.")
		return false
	guide._complete({"code":1,"status":false,"action":"Evidence","text":"Simulated network failure"})
	if not "failed" in guide._checks_label.text:
		printerr("Failed evidence refresh retained success.")
		return false
	guide._guide_version = "v0.3.0-rc.1"
	guide._test_package = {"version":"v0.3.0-rc.1", "commit":"test-head", "folder":"missing", "manifest":{}}
	guide._guide_show("publish")
	guide._guide_tested.button_pressed = true
	guide.captured = {}
	guide._launch_test_package()
	if guide.captured.get("purpose") != "launch":
		printerr("Launch did not use background integrity verification.")
		return false
	guide._complete({"code":1, "text":"Integrity failed.", "status":false, "purpose":"launch", "package":guide._test_package.duplicate(true)})
	if not guide._test_package.is_empty() or guide._guide_tested.button_pressed or not "Download" in guide._guide_error.text:
		printerr("Failed launch integrity retained package approval.")
		return false
	guide.free()
	return true


func _test_guide() -> bool:
	var guide := GuideProbe.new()
	root.add_child(guide)
	guide._snapshot = {"head": "test-head", "branch": "main", "files": ["sample.txt"], "staged": [], "hashes": {}, "index_tree": "test-tree"}
	guide._files.add_item("sample.txt")
	guide._guide_show("files")
	guide._guide_answer()
	if guide._guide_error.text.is_empty() or not guide.captured.is_empty() or not guide._guide_dialog.visible:
		printerr("Guide did not keep excluded-work warning open before staging.")
		return false
	guide._guide_select_files(true)
	if not guide._guide_files[0].button_pressed:
		printerr("Select all did not check files.")
		return false
	guide._guide_select_files(false)
	if guide._guide_files[0].button_pressed:
		printerr("Select none did not clear files.")
		return false
	guide._guide_files[0].button_pressed = true
	guide._guide_dialog.hide()
	guide._guide_answer()
	var request = JSON.parse_string(Marshalls.base64_to_utf8(guide.captured["args"][-1]))
	if request["action"] != "Stage" or request["files"] != ["sample.txt"]:
		printerr("Guide did not stage only selected files.")
		return false
	guide._snapshot["staged"] = ["sample.txt"]
	guide.captured = {}
	guide._guide_show("commit")
	if not guide.captured.is_empty():
		printerr("Guide allowed commit review with remaining unstaged work.")
		return false
	guide._snapshot["files"] = []
	guide._guide_show("commit")
	request = JSON.parse_string(Marshalls.base64_to_utf8(guide.captured["args"][-1]))
	if request["action"] != "StagedReview" or guide.captured["guide_next"] != "commit_review":
		printerr("Guide did not request an exact staged diff.")
		return false
	guide._guide_diff = "new file mode 100644\n+new file contents"
	guide._guide_show("commit_review")
	guide._guide_branch.text = "invalid branch"
	guide._guide_answer()
	if guide._guide_error.text.is_empty():
		printerr("Combined review did not validate branch.")
		return false
	guide._guide_branch.text = "feature/guided-test"
	guide.captured = {}
	guide._guide_answer()
	if guide._guide_error.text.is_empty() or not guide.captured.is_empty():
		printerr("Blank commit did not remain at validation.")
		return false
	guide._guide_input.text = "Guided test"
	guide._guide_answer()
	if guide._guide_error.text.is_empty() or not guide.captured.is_empty():
		printerr("Guide committed without diff review confirmation.")
		return false
	guide._guide_reviewed.button_pressed = true
	guide._guide_dialog.hide()
	guide._guide_answer()
	request = JSON.parse_string(Marshalls.base64_to_utf8(guide.captured["args"][-1]))
	if request["action"] != "Commit" or request["message"] != "Guided test" or request.get("new_branch") != "feature/guided-test":
		printerr("Guide did not ask for commit name.")
		return false
	guide._snapshot["staged"] = []
	guide._snapshot["branch"] = "feature/guided-test"
	guide._guide_show("push")
	guide._guide_dialog.hide()
	guide._guide_answer()
	if guide.captured["guide_next"] != "merge" or not "Push" in guide.captured["args"]:
		printerr("Guide did not stop Push before manual merge.")
		return false
	guide.captured = {}
	guide._guide_show("merge")
	if not guide.captured.is_empty() or not guide._guide_dialog.visible:
		printerr("Manual merge pause executed a command.")
		return false
	guide._guide_show("sync_main")
	if guide._cleanup_branch.button_pressed or not guide.captured.is_empty():
		printerr("Main synchronization or cleanup was automatically approved.")
		return false
	guide._guide_answer()
	var sync_args: Array = guide.captured["args"]
	if guide.captured.get("action") != "Synchronize" or sync_args[sync_args.find("-CleanupBranch") + 1] != "no" or sync_args[sync_args.find("-ExpectedBranch") + 1] != "feature/guided-test":
		printerr("Synchronization was not bound to reviewed feature/cleanup choice.")
		return false
	guide._guide_show("sync_main")
	guide._cleanup_branch.button_pressed = true
	guide._guide_answer()
	sync_args = guide.captured["args"]
	if sync_args[sync_args.find("-CleanupBranch") + 1] != "yes":
		printerr("Explicit cleanup choice was lost.")
		return false
	guide.captured = {}
	guide._guide_dialog.hide()
	guide._guide_show("release")
	if guide._guide_dialog.visible:
		printerr("Guide allowed release on dirty feature branch.")
		return false
	guide._snapshot["branch"] = "main"
	guide._snapshot["files"] = []
	guide._snapshot["staged"] = []
	guide._guide_show("release")
	guide._guide_input.text = "invalid"
	guide.captured = {}
	guide._guide_answer()
	if guide._guide_error.text.is_empty() or not guide._guide_dialog.visible or not guide.captured.is_empty():
		printerr("Invalid release version was not retained for correction.")
		return false
	guide._guide_input.text = "v0.2.0-rc.1"
	guide._guide_dialog.hide()
	guide._guide_answer()
	if not "Release" in guide.captured["args"] or not "v0.2.0-rc.1" in guide.captured["args"] or guide.captured["guide_next"] != "publish":
		printerr("Guide release parameters incorrect.")
		return false
	guide.captured = {}
	guide._guide_show("publish")
	guide._guide_answer()
	if not guide.captured.is_empty() or not guide._guide_dialog.visible or guide._guide_error.text.is_empty():
		printerr("Guide published without playtest approval.")
		return false
	guide._guide_show("publish")
	guide._test_package = {"version":"v0.2.0-rc.1", "commit":"test-head", "identity":"42:hash"}
	guide._workflow("SmokeTest", "publish")
	var smoke_args: Array = guide.captured["args"]
	if JSON.parse_string(Marshalls.base64_to_utf8(smoke_args[smoke_args.find("-Package") + 1])) != guide._test_package:
		printerr("Smoke test lost verified package identity.")
		return false
	guide.captured = {}
	guide._complete({"code":0,"status":false,"action":"SmokeTest","guide_next":"publish","text":'EDITOR_RESULT:{"state":"passed","version":"v0.2.0-rc.1","commit":"test-head","identity":"42:hash"}'})
	if guide._guide_tested.button_pressed or not "interactive testing is still required" in guide._guide_error.text or not guide.captured.is_empty():
		printerr("Smoke test certified an interactive playtest.")
		return false
	guide._complete({"code":0,"status":false,"action":"SmokeTest","guide_next":"publish","text":'EDITOR_RESULT:{"state":"passed","version":"v0.2.0-rc.1","commit":"test-head","identity":"different-draft"}'})
	if not "failed or selection changed" in guide._guide_error.text or not guide.captured.is_empty():
		printerr("Smoke test accepted results for a different draft.")
		return false
	guide._guide_tested.button_pressed = true
	guide._guide_dialog.hide()
	guide._guide_answer()
	if guide.captured.get("purpose") != "confirm" or not guide.captured.has("package"):
		printerr("Testing approval did not request background integrity verification.")
		return false
	var checked_package: Dictionary = guide.captured["package"]
	guide.captured = {}
	guide._complete({"code":0, "text":"Verified for testing.", "status":false, "purpose":"confirm", "package":checked_package})
	if guide._guide_step != "publish_confirm" or not guide.captured.is_empty():
		printerr("Integrity verification skipped separate publication approval.")
		return false
	guide._guide_answer()
	if not "Publish" in guide.captured["args"] or guide.captured["guide_next"] != "done":
		printerr("Guide publication parameters incorrect.")
		return false
	if not "-ExpectedDraft" in guide.captured["args"] or not "-ExpectedHead" in guide.captured["args"]:
		printerr("Publish command is not bound to tested identity.")
		return false
	guide.free()
	return true
