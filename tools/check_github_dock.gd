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
	if dock._tabs.get_tab_count() != 5:
		printerr("Expected five workflow tabs.")
		quit(1)
		return
	for index in 5:
		if dock._tabs.get_tab_title(index) != ["Git", "Push", "Release", "Publish", "Guided workflow"][index]:
			printerr("Unexpected workflow tab.")
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
	var original: Dictionary = dock._snapshot.duplicate(true)
	dock._snapshot["staged"] = ["ui-test-only.txt"]
	dock._name_commit()
	if not dock._commit_dialog.visible or dock._message.placeholder_text != "Commit name / message":
		printerr("Commit naming dialog did not open.")
		quit(1)
		return
	dock._commit_dialog.hide()
	dock._snapshot = original
	print("PASS: staged list and Commit -> name dialog (no staging/commit performed).")
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
	print("PASS: completion routing, failed/malformed status invalidation, cancellation, scrollable long-file review.")
	quit(0)


func _test_transitions() -> bool:
	var guide := GuideProbe.new()
	root.add_child(guide)
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
