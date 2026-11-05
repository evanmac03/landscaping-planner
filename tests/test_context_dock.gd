extends Node
## The AI context dock (`addons/context_tools/context_dock.gd`), driven off-tree.
##
## The dock is a plain `Control` with no editor API, so every decision it makes is tested here
## without adding it to a tree. Every test frees the dock it builds so the runner never sees a
## leaked `Control` at exit.

const DockScript := preload("res://addons/context_tools/context_dock.gd")
const ContextReportScript := preload("res://tools/context_report.gd")


func _dock() -> Control:
	var dock: Control = DockScript.new()
	dock.build()
	return dock


func test_the_dock_builds_its_controls_and_says_where_to_start() -> void:
	var dock: Control = _dock()

	assert(dock.name == "AI Context", "the dock is named AI Context")
	for control_name: String in [
		"Heading", "Intro", "SubjectPicker", "ChosenLine", "TargetPath", "IncludeSource",
		"IncludeGit", "IncludeRun", "SourceLine", "PromptBox", "CopyButton", "SaveButton",
		"BuildButton", "OpenFolder", "Summary", "PreviewBox", "Status",
	]:
		assert(dock.find_child(control_name, true, false) != null, "%s was built" % control_name)
	assert(dock.last_words.contains("Copy to clipboard"), "it opens with guidance on the status line")

	dock.free()


func test_nothing_in_the_dock_steals_editor_shortcuts() -> void:
	# A focused button in an editor dock swallows the editor's own shortcuts when pressed.
	var dock := _dock()
	var checked := 0
	for found: Node in dock.find_children("*", "Button", true, false):
		var button: Button = found
		assert(button.focus_mode == Control.FOCUS_NONE, "%s takes no focus" % button.name)
		checked += 1
	assert(checked >= 5, "all buttons and the option picker were checked")

	dock.free()


func test_the_picker_offers_the_whole_snapshot_and_every_subject_pack() -> void:
	var dock := _dock()
	var picker: OptionButton = dock.find_child("SubjectPicker", true, false)
	var subjects: PackedStringArray = ContextReportScript.subject_names()

	var scopes: int = 2
	assert(picker.item_count == scopes + subjects.size(),
			"an entry for the whole snapshot, one for the change in hand, and one per pack")
	assert(picker.get_item_text(0) == DockScript.WHOLE_LABEL, "the first entry is the whole snapshot")
	assert(picker.get_item_text(1) == ContextReportScript.REVIEW_LABEL,
			"the second is the change under review")
	for index: int in subjects.size():
		var name: String = subjects[index]
		assert(picker.get_item_text(index + scopes).begins_with(name + " - "),
				"entry %d names %s and its title" % [index + scopes, name])

	dock.free()


func test_the_review_scope_carries_the_change_without_a_box_being_ticked() -> void:
	# Every pack's extra is opt-in. The review pack is the one exception, and deliberately: the change
	# *is* the subject there, so leaving it out would build the one pack with nothing in it, and asking
	# somebody to tick a box to say what they have already picked would be asking twice.
	var dock: Control = _dock()
	dock.git_reader = func() -> Dictionary:
		return {
			"status": " M scripts/crop_rotation.gd\n",
			"diff": "diff --git a/x b/x\n+hello\n",
			"commit": "abc1234 Fix the thing\n",
		}
	assert(dock.select_subject(ContextReportScript.REVIEW), "the review scope can be picked")
	assert(not dock.include_git(), "and no box was ticked to get here")
	assert(dock.target_path() == "user://gemini_context_review.md", "it writes a file of its own")
	var text: String = dock.refresh_preview()
	assert(text.contains("## The files this change touches"), "the pack is about the change")
	assert(text.contains("abc1234 Fix the thing"), "and carries the commit it sits on")
	assert(dock.last_words.contains("the change in hand"), "the status line says what it carried")

	dock.free()


func test_selecting_a_subject_points_at_its_pack_and_refuses_an_unknown_one() -> void:
	var dock := _dock()
	var path_label: Label = dock.find_child("TargetPath", true, false)

	assert(dock.select_subject("plant-id"), "a known subject is accepted")
	assert(dock.current_subject == "plant-id", "current_subject updated")
	assert(path_label.text.ends_with("user://gemini_context_plant-id.md"),
			"the output path label tracks the subject")

	assert(not dock.select_subject("no-such-pack"), "an unknown subject is refused")
	assert(dock.current_subject == "plant-id", "and does not disturb the previous selection")
	assert(dock.last_words.contains("There is no 'no-such-pack' pack"),
			"the refusal names what was asked for")

	dock.free()


func test_a_second_pack_can_be_built_alongside_the_first() -> void:
	# A question can reach across two subsystems, and choosing one pack loses the other half of it. The
	# two are built as one payload, with the blocks that are the same in every pack printed once.
	var dock := _dock()
	var second: OptionButton = dock.find_child("SecondPicker", true, false)
	assert(second != null, "the second-pack row is built")
	assert(second.item_count == 1 + ContextReportScript.subject_names().size(),
			"offering nothing-else and every pack: %d" % second.item_count)

	dock.select_subject("estimating")
	assert(not dock.has_second(), "one pack to begin with")
	assert(dock.select_second("jobs-billing"), "a second pack can be chosen")
	assert(dock.has_second(), "and is taken on")
	assert(dock.current_subjects().size() == 2, "both subjects are the payload's")

	var text: String = dock.refresh_preview()
	assert(text.begins_with("# Context pack: two subjects"), "the payload says it carries two")
	assert(text.contains("## The 'estimating' pack"), "with the first subject's own blocks")
	assert(text.contains("## The 'jobs-billing' pack"), "and the second's")
	assert(text.count("## Conventions (from AGENTS.md)") == 1, "and the shared blocks printed once")
	assert(dock.last_words.contains("the 'estimating' and 'jobs-billing' packs"),
			"the status line names both: %s" % dock.last_words)
	assert(dock.target_path().ends_with("gemini_context_estimating+jobs-billing.md"),
			"and the file is named for both")

	# Back to one pack, rather than leaving the second choice half applied.
	dock.select_second("")
	assert(not dock.has_second(), "the second pack is off again")
	assert(not dock.refresh_preview().begins_with("# Context pack: two subjects"),
			"and the payload is one pack again")

	# A name that is not a subject is refused by name, the way the first picker refuses one.
	assert(not dock.select_second("no-such-pack"), "an unknown second pack is refused")
	assert(dock.last_words.contains("There is no 'no-such-pack' pack"), "by name")

	# The whole snapshot is not a pack, so nothing can be built beside it.
	dock.select_subject("")
	dock.select_second("plant-id")
	assert(not dock.has_second(), "the whole snapshot has no second pack")

	dock.free()


func test_building_the_preview_populates_the_box_and_appends_an_optional_prompt() -> void:
	var dock := _dock()
	var preview: TextEdit = dock.find_child("PreviewBox", true, false)
	var summary: Label = dock.find_child("Summary", true, false)

	dock.select_subject("plant-id")
	dock.set_prompt("Write a helper that counts captures per species.")
	var text: String = dock.refresh_preview()

	# Read from the report rather than written out again, so renaming a pack cannot leave this test
	# asserting a title that no longer exists.
	assert(text.begins_with("# Context pack: %s"
			% String(ContextReportScript.SUBJECTS["plant-id"]["title"])),
			"it builds the selected pack")
	assert(text.ends_with("## Request\n\nWrite a helper that counts captures per species.\n"),
			"and appends the optional prompt under ## Request")
	assert(preview.text == text, "the preview box holds the built text")
	assert(summary.text.contains("the 'plant-id' pack:"), "the summary states which pack was built")

	dock.free()


func test_writing_to_file_saves_the_pack_and_announces_it() -> void:
	var dock := _dock()
	dock.output_dir = "user://demo_context"
	var announced: Array[String] = []
	dock.exported.connect(func(subject: String, path: String, chars: int) -> void:
		announced.append("%s:%s:%d" % [subject, path, chars]))

	dock.select_subject("drafting")
	assert(dock.write_to_file(), "the pack is written")
	assert(dock.last_path == "user://demo_context/gemini_context_drafting.md", "to the subject's own file")
	assert(FileAccess.file_exists(dock.last_path), "and the file is on disk")
	assert(announced.size() == 1 and announced[0].begins_with("drafting:user://demo_context/gemini_context_drafting.md:"),
			"the exported signal reports the subject, path and size")

	dock.free()


func test_the_open_script_is_carried_only_when_the_box_is_ticked() -> void:
	# The dock never opens a file: `plugin.gd` hands it the path and the text, which is why this is
	# covered with no editor anywhere. The box is dead until there is something to include, so it can
	# never promise a source that does not exist.
	var dock := _dock()
	var check: CheckBox = dock.find_child("IncludeSource", true, false)
	var source_line: Label = dock.find_child("SourceLine", true, false)
	var body := "extends RefCounted\n\nfunc doubled(value: int) -> int:\n\treturn value * 2\n"

	assert(check.disabled, "with no script in hand the box is dead rather than misleading")
	assert(not dock.include_source(), "and nothing would be included")

	dock.set_source("res://scripts/doubled.gd", body)
	assert(not check.disabled, "handing the dock a script wakes the box")
	assert(source_line.text.contains("res://scripts/doubled.gd"), "and names what is in hand")
	assert(not dock.include_source(), "an unticked box still means no source")

	check.button_pressed = true
	assert(dock.include_source(), "ticking the box asks for it")
	dock.select_subject("plant-id")
	assert(dock.refresh_preview().contains("## Full source of `res://scripts/doubled.gd`"),
			"and the build carries the code")

	check.button_pressed = false
	assert(not dock.refresh_preview().contains("Full source of"), "unticking it takes it out again")

	dock.set_source("", "")
	assert(check.disabled, "closing the script deadens the box again")
	assert(source_line.text == DockScript.SOURCE_NONE, "and the row says there is nothing open")
	assert(not dock.refresh_preview().contains("Full source of"), "with nothing carried")

	dock.free()


func test_ticking_the_box_rebuilds_what_is_already_on_screen() -> void:
	# A preview that disagreed with the checkbox would be a snapshot somebody copies believing it
	# holds the source. Before the first build there is nothing to keep in step, so the box only
	# announces what the next build will do.
	var dock := _dock()
	var check: CheckBox = dock.find_child("IncludeSource", true, false)
	var preview: TextEdit = dock.find_child("PreviewBox", true, false)

	assert(dock.last_output.is_empty(), "no build has happened yet, so there is nothing to refresh")
	dock.set_source("res://scripts/doubled.gd", "extends RefCounted\nfunc x() -> int:\n\treturn 1\n")
	dock.select_subject("drafting")
	assert(not dock.refresh_preview().contains("Full source of"), "a build without it starts clean")

	check.button_pressed = true
	assert(dock.last_output.contains("## Full source of"), "ticking it rebuilds the preview")
	assert(preview.text.contains("Full source of"), "and the box on screen is the new text")

	dock.free()


func test_the_dock_says_when_to_choose_the_pack_in_hand() -> void:
	# The picker lists slugs; this is the line that tells a person which one they want. It follows the
	# picker rather than being chosen once, and the whole snapshot - which is not a pack - has its own
	# sentence instead of borrowing one.
	var dock := _dock()
	var chosen: Label = dock.find_child("ChosenLine", true, false)

	assert(chosen.text.begins_with("Everything."), "it opens explaining the whole snapshot")

	dock.select_subject("food-garden")
	assert(chosen.text == ContextReportScript.when_for("food-garden"),
			"and follows the picker to that pack's own sentence")
	assert(chosen.text.contains("Growing food"), "which says what the pack is for")

	dock.select_subject("")
	assert(chosen.text.begins_with("Everything."), "and back to the whole project again")

	dock.free()


func test_nothing_is_attached_until_a_box_is_ticked() -> void:
	# The dock touches nothing outside itself unless asked: no git, no log, no file. That is also why
	# the readers are `Callable`s - a test hands over canned text and the packing stays covered.
	var dock := _dock()
	var reads := [0]
	dock.git_reader = func() -> Dictionary:
		reads[0] += 1
		return {"status": " M a.gd", "diff": ""}
	dock.run_reader = func() -> String:
		reads[0] += 1
		return "VERDICT: TESTS PASSED"

	assert(dock.attachment().is_empty(), "with every box unticked there is nothing to attach")
	dock.select_subject("drafting")
	dock.refresh_preview()
	assert(reads[0] == 0, "and nothing outside the dock was read")
	assert(not dock.last_output.contains("## Uncommitted changes"), "so no such section is built")

	dock.free()


func test_the_boxes_attach_the_uncommitted_work_and_the_last_test_run() -> void:
	var dock := _dock()
	dock.git_reader = _canned_git
	dock.run_reader = _canned_run

	(dock.find_child("IncludeGit", true, false) as CheckBox).button_pressed = true
	(dock.find_child("IncludeRun", true, false) as CheckBox).button_pressed = true

	var text: String = dock.refresh_preview()
	assert(text.contains("## Uncommitted changes"), "the uncommitted work is carried")
	assert(text.contains("?? scripts/new_thing.gd"), "with what git said")
	assert(text.contains("## The last test run"), "and the last run")
	assert(dock.last_words.contains("what is not committed yet"), "the status line names what it carried")
	assert(dock.last_words.contains("the last test run"), "both of them")

	dock.free()


func test_the_git_box_carries_what_has_changed_lately_as_well() -> void:
	# A pack says what the project *is*; the commits that touched its own files say what is moving in
	# it. It rides on the git tick, because running git is work outside the dock and an unticked box
	# has to touch nothing outside it.
	var dock := _dock()
	dock.git_reader = func() -> Dictionary: return {
		"status": " M scripts/thing.gd\n",
		"diff": "",
		"commit": "abc1234 The last commit\n",
		"recent": "abc1234 The last commit\n9f8e7d6 The one before\n",
	}

	assert(not dock.attachment().has("recent_commits"), "an unticked box attaches nothing")
	dock.select_subject("plant-id")
	(dock.find_child("IncludeGit", true, false) as CheckBox).button_pressed = true

	var text: String = dock.refresh_preview()
	assert(text.contains("## What has changed here lately"), "the recent commits are carried")
	assert(text.contains("9f8e7d6 The one before"), "with what the reader gave it")
	assert(dock.last_words.contains("what has changed lately"), "and the status line says so: %s" % dock.last_words)

	dock.free()


func test_a_ticked_but_empty_git_box_says_so_rather_than_going_quiet() -> void:
	var dock := _dock()
	dock.git_reader = func() -> Dictionary: return {"status": "", "diff": ""}
	(dock.find_child("IncludeGit", true, false) as CheckBox).button_pressed = true

	dock.refresh_preview()
	assert(not dock.last_output.contains("## Uncommitted changes"), "there is no section to show")
	assert(dock.last_words.contains("nothing uncommitted"), "and the status line explains why")

	dock.free()


func _canned_git() -> Dictionary:
	return {"status": "?? scripts/new_thing.gd", "diff": ""}


func _canned_run() -> String:
	return "VERDICT: TESTS FAILED - 0 passed, 1 failed"


func test_the_dock_fits_a_narrow_panel() -> void:
	# The bug this holds down: the scope picker sized itself to its longest item - a pack's title is a
	# whole sentence - so the dock's minimum width was 843 px, and in the bottom-right slot its own
	# buttons and summary were clipped off the edge of the panel. A leaf control's minimum size is
	# reliable off-tree; a container's is only settled once it has been laid out, so these two lines
	# are the whole floor that matters.
	var dock := _dock()
	var picker: OptionButton = dock.find_child("SubjectPicker", true, false)
	var check: CheckBox = dock.find_child("IncludeSource", true, false)

	assert(not picker.fit_to_longest_item, "the scope button is not sized to its longest pack title")
	assert(picker.get_combined_minimum_size().x < 200, "so the scope row stays narrow")
	assert(check.get_combined_minimum_size().x < 350, "and the source caption does not set the width")

	dock.free()


func test_the_summary_states_an_estimated_token_count() -> void:
	# Different chats have different sweet spots, so the size is shown in tokens as well as lines and
	# bytes - the number a person actually budgets against.
	var dock := _dock()
	var summary: Label = dock.find_child("Summary", true, false)

	dock.select_subject("plant-id")
	dock.refresh_preview()

	var expected: int = dock.token_estimate()
	assert(expected > 0, "the estimate is a real number")
	assert(dock.last_tokens == expected, "last_tokens holds it for a caller")
	assert(expected == int(round(dock.last_output.length() / float(DockScript.CHARS_PER_TOKEN))),
			"it is four characters per token")
	var phrase := RegEx.new()
	phrase.compile("~[0-9][0-9,]* tokens")
	assert(phrase.search(summary.text) != null, "the summary shows the estimate")
	assert(dock.last_words.contains("tokens"), "and so does the status line")

	dock.free()


func test_a_snapshot_too_large_for_a_web_chat_is_flagged_and_a_pack_is_not() -> void:
	# The whole snapshot is the payload that strains a browser chat; a scoped pack is the answer, so
	# the summary has to say which side of the line the selection is on. If the snapshot ever shrinks
	# below LARGE_TOKENS this test is the reminder to lower the threshold with it.
	var dock := _dock()
	var summary: Label = dock.find_child("Summary", true, false)

	dock.select_subject("")
	dock.refresh_preview()
	assert(dock.last_tokens > DockScript.LARGE_TOKENS,
			"the whole snapshot costs more than a web chat handles well")
	assert(summary.text.contains("Large for a web chat"), "so the summary says so in a sentence")

	dock.select_subject("plant-id")
	dock.refresh_preview()
	assert(dock.last_tokens <= DockScript.LARGE_TOKENS, "a scoped pack fits")
	assert(not summary.text.contains("Large for a web chat"), "and the warning is gone")

	dock.free()


func test_the_dock_says_when_the_tree_moved_since_the_pack_was_built() -> void:
	# The pack on screen was built from certain contents, and somebody pasting it into a chat has no way
	# to see that a file underneath it has moved on since. The dock is the one thing that can say so -
	# and it says it once, rather than repeating itself on every check.
	var dock := _dock()
	dock.select_subject("plant-id")
	dock.refresh_preview()

	assert(dock.last_fingerprint != "", "the build records what it was built from")
	assert(not dock.is_stale(), "and a pack that has just been built is not out of date")
	assert(not dock.check_freshness(), "so nothing is said")

	dock.last_fingerprint = "deadbeef"
	assert(dock.is_stale(), "a pack whose contents have moved on is out of date")
	assert(dock.check_freshness(), "and the check says so")
	assert(dock.last_words.contains("changed since it was built"), "in words: %s" % dock.last_words)
	var said: String = dock.last_words
	dock.check_freshness()
	assert(dock.last_words == said, "and only once, not on every check")

	dock.free()


func test_every_pack_fits_what_a_web_chat_handles() -> void:
	# A scoped pack exists to fit one paste, so a pack past the dock's own threshold is **mis-scoped**
	# rather than merely large: the answer is a smaller subject, not a longer pack. The test above says
	# the threshold is live for the snapshot; this one holds every pack to it, and it is the guard that
	# caught `business` being two subjects wearing one name.
	var over: Array[String] = []
	for subject: String in ContextReportScript.subject_names():
		var text: String = ContextReportScript.build_subject(subject)
		var tokens: int = int(round(text.length() / float(DockScript.CHARS_PER_TOKEN)))
		if tokens > DockScript.LARGE_TOKENS:
			over.append("%s is %d tokens" % [subject, tokens])

	assert(over.is_empty(), "every pack fits one chat message: %s" % ", ".join(over))


func test_a_pack_that_was_never_built_is_never_called_out_of_date() -> void:
	var dock := _dock()

	assert(not dock.is_stale(), "nothing on screen is nothing to be out of date")
	assert(not dock.check_freshness(), "and the check stays quiet")

	dock.free()
