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
	if not "Selected files staged." in guide._history or not "Simulated failure" in guide._history:
		printerr("Transitions lost output history.")
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
	guide._guide_show("branch")
	guide._guide_input.text = "invalid branch"
	guide._guide_answer()
	if guide._guide_error.text.is_empty() or guide._guide_input.text != "invalid branch":
		printerr("Guide did not retain invalid branch input.")
		return false
	guide._guide_input.text = "feature/guided-test"
	guide._guide_dialog.hide()
	guide._guide_answer()
	request = JSON.parse_string(Marshalls.base64_to_utf8(guide.captured["args"][-1]))
	if request["action"] != "Branch" or request["name"] != "feature/guided-test":
		printerr("Guide did not ask for branch.")
		return false
	guide._snapshot["branch"] = "feature/guided-test"
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
	if request["action"] != "Commit" or request["message"] != "Guided test":
		printerr("Guide did not ask for commit name.")
		return false
	guide._snapshot["staged"] = []
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
	guide._guide_tested.button_pressed = true
	guide._guide_dialog.hide()
	guide._guide_answer()
	if not "Publish" in guide.captured["args"] or guide.captured["guide_next"] != "done":
		printerr("Guide publication parameters incorrect.")
		return false
	guide.free()
	return true
