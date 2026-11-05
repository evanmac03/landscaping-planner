extends Node
## The context exporter: the whole snapshot and the scoped subject packs.
##
## These hold down the properties that make the exporter useful rather than decorative: a pack
## describes the subject it is named for, it quotes specification sections that really exist, and
## it **refuses** an unknown subject instead of answering with the whole codebase.

const ContextReportScript := preload("res://tools/context_report.gd")

const FULL_PATH := "user://gemini_context.md"


func test_the_snapshot_carries_every_part() -> void:
	var text: String = ContextReportScript.build()

	assert(text.begins_with("# Landscaping Planner - context snapshot"), "it opens with its title")
	for part: String in [
		"## Project", "## Specifications in docs/", "## Folder map", "## Conventions",
		"## A test file", "## The scene tree of the main scene", "## Data file shapes",
		"## Script inventory (derived)", "## Data models in detail (derived)",
	]:
		assert(text.contains(part), "the snapshot carries %s" % part)


func test_the_scene_tree_names_the_script_of_each_node() -> void:
	# The guard on a real bug: `id="..."` was being found inside `uid="..."`, so every resource that
	# carries a uid answered with its uid and most nodes looked scriptless.
	var text: String = ContextReportScript.build()

	assert(text.contains("`res://scenes/main.tscn`, in full"), "the main scene is the one shown")
	assert(text.contains("- `/ViewController` (Node) - script `res://scripts/view_controller.gd`"),
			"a node's script is named")
	assert(text.contains("- `/DraftOverlay` (Node3D) - script `res://scripts/draft/draft_overlay.gd`"),
			"for more than the one node")
	assert(text.contains("instance of `res://scenes/ui/hud.tscn`"),
			"and a node that is an instance says what of")


func test_a_data_file_is_shown_as_one_record() -> void:
	var text: String = ContextReportScript.build()

	assert(text.contains("### res://data/plants/nursery_list.json"), "each data file is named")
	assert(text.contains("\"acer-platanoides-crimson-king\""), "with one record, under its own key")
	assert(text.contains("`JSON.parse_string`"), "and the note that a number reads as a float")


func test_the_test_convention_is_shown_as_a_file() -> void:
	var text: String = ContextReportScript.build()

	assert(text.contains("func test_a_spread_that_cannot_be_worked_out_is_refused_rather_than_guessed()"),
			"a test name states the rule")
	assert(text.contains("const ThingScript := preload(\"res://scripts/thing.gd\")"),
			"and classes are preloaded by path")
	assert(text.contains("page.free()"), "and a node a test makes is freed by the test")
	assert(ContextReportScript.build_subject("plant-id").contains("## A test file"),
			"a pack carries the convention too")


func test_the_snapshot_lists_its_subjects() -> void:
	var names: PackedStringArray = ContextReportScript.subject_names()

	assert(names.size() >= 3, "there is more than one subject to choose from")
	for expected: String in [
		"plant-id", "planting", "drafting", "estimating", "jobs-billing", "visualization",
		"irrigation-lighting", "food-garden", "field-capture", "workflow", "help",
	]:
		assert(names.has(expected), "%s is one of them" % expected)
		assert(ContextReportScript.has_subject(expected), "and it is buildable")


func test_every_subject_builds_a_pack_of_its_own() -> void:
	for name: String in ContextReportScript.subject_names():
		var text: String = ContextReportScript.build_subject(name)
		var title: String = String((ContextReportScript.SUBJECTS[name] as Dictionary)["title"])

		assert(text.begins_with("# Context pack: %s" % title), "%s opens as its own pack" % name)
		assert(text.contains("## Conventions"), "%s still carries the conventions" % name)
		assert(not text.contains("## Script inventory (derived)"),
				"%s leaves out the whole-project inventory" % name)
		assert(not text.contains("## Tests and tools"), "%s leaves out the tools listing" % name)


func test_a_pack_details_the_scripts_it_names() -> void:
	var text: String = ContextReportScript.build_subject("field-capture")

	assert(text.contains("### res://scripts/plant_id_resolver.gd"), "it details the resolver")
	assert(text.contains("### res://scripts/survey_watcher.gd"), "and the watcher")
	assert(text.contains("#### Methods"), "with the signatures a caller needs")
	assert(text.contains("#### Constants"), "and the constants")
	assert(not text.contains("### res://scripts/biz/"), "and nothing from another subsystem")


func test_a_pack_quotes_the_specification_sections_it_names() -> void:
	var text: String = ContextReportScript.build_subject("plant-id")

	assert(text.contains("*From `res://docs/plant-database-spec.md`:*"), "it names its source")
	assert(not text.contains("MISSING SECTION"), "and every section it names was found")
	assert(not text.contains("## 9. The tests"), "and it stops at the end of a quoted section")


func test_every_declared_section_still_exists_in_its_document() -> void:
	# A specification heading that has been renamed empties a pack's rule book without emptying
	# the pack, so every heading a subject names is proved to be there.
	for name: String in ContextReportScript.subject_names():
		var entry: Dictionary = ContextReportScript.SUBJECTS[name]
		for section: Dictionary in (entry["sections"] as Array):
			var doc: String = String(section["doc"])
			assert(FileAccess.file_exists(doc), "%s's specification is there" % name)
			for heading: String in (section["headings"] as Array):
				var body: PackedStringArray = ContextReportScript._section_lines(doc, heading)
				assert(not body.is_empty(), "%s: %s still has \"%s\"" % [name, doc, heading])


func test_every_specification_is_either_quoted_by_a_pack_or_named_as_needing_none() -> void:
	# A specification nothing quotes is a rule book with the cover missing: the whole snapshot lists
	# every document in `docs/`, but a pack that *names* one without quoting it leaves the reader with
	# rules they were told to obey and none of the text. So the quoted set and the packless set have to
	# cover `docs/` between them - nothing missing from both, and nothing in both at once.
	var quoted := PackedStringArray()
	for subject: String in ContextReportScript.subject_names():
		for section: Dictionary in (ContextReportScript.SUBJECTS[subject]["sections"] as Array):
			var doc: String = String(section["doc"])
			if not quoted.has(doc):
				quoted.append(doc)

	var listed := PackedStringArray()
	for row: Dictionary in ContextReportScript.PACKLESS_DOCS:
		var doc: String = String(row["doc"])
		listed.append(doc)
		assert(FileAccess.file_exists(doc), "a document named as needing no pack is there: %s" % doc)
		assert(String(row.get("why", "")).length() > 40, "and the row says why: %s" % doc)
		assert(not quoted.has(doc), "%s is not both quoted by a pack and named as needing none" % doc)

	var on_disk := PackedStringArray()
	for name: String in ContextReportScript._names_in("res://docs", ".md"):
		on_disk.append("res://docs/" + name)
	assert(on_disk.size() > 5, "there are documents to check: %d" % on_disk.size())

	for doc: String in on_disk:
		assert(
			quoted.has(doc) or listed.has(doc),
			"every specification is either quoted by a pack or named as needing none: %s" % doc
		)

	# And the snapshot lists them all, so a new document is visible there even before a pack decides
	# what to do with it.
	assert(
		ContextReportScript._spec_lines().size() == on_disk.size(),
		"the whole snapshot lists every document in docs/"
	)


func test_every_subject_names_scripts_that_exist() -> void:
	for name: String in ContextReportScript.subject_names():
		var entry: Dictionary = ContextReportScript.SUBJECTS[name]
		for path: String in (entry["scripts"] as Array):
			assert(FileAccess.file_exists(path), "%s names a real script: %s" % [name, path])
		for path: String in (entry["data"] as Array):
			assert(
				not ContextReportScript._sample_record(path).is_empty(),
				"%s names data with a readable sample: %s" % [name, path]
			)


func test_signatures_print_valid_gdscript_types_and_defaults() -> void:
	var text: String = ContextReportScript.build_subject("field-capture")

	# Guard on three formatting traps: Variant parameters must never print as `void`, null defaults
	# must never print as `<null>`, and typed class members must name their class rather than `Object`.
	assert(not text.contains(": void)"), "no parameter is ever printed with type `void`")
	assert(not text.contains("<null>"), "null defaults print as `null`, not `<null>`")
	assert(text.contains("- controller: ViewController"), "a typed member names its class")
	assert(text.contains("- static _position_dict(raw: Variant) -> Dictionary"),
			"an untyped Variant parameter prints as `Variant`")
	assert(text.contains("### user://site_manifest.json"),
			"the field-capture pack shows the manifest's own JSON shape")


func test_a_pack_says_what_it_leaves_out() -> void:
	var text: String = ContextReportScript.build_subject("drafting")

	assert(text.contains("## What this pack leaves out"), "it is honest about its scope")
	assert(text.contains("One subject of"), "and says how much of the project it covers")


func test_an_unknown_subject_is_refused_by_name() -> void:
	assert(not ContextReportScript.has_subject("no-such-subject"), "it is not a subject")

	var text: String = ContextReportScript.build_subject("no-such-subject")
	assert(text.begins_with("# Unknown subject: no-such-subject"), "the refusal names it")
	assert(text.contains("plant-id"), "and lists the subjects that do exist")

	# The important half: asking for the unknown one must not quietly hand back the whole thing.
	assert(ContextReportScript.build_for("no-such-subject") == text,
			"an unknown subject is never answered with the whole snapshot")


func test_the_conventions_come_from_agents_md() -> void:
	# One set of rules and not two: the snapshot quotes AGENTS.md instead of restating it, so a rule
	# edited there reaches the snapshot and every pack, and cannot drift from a second copy.
	assert(FileAccess.file_exists("res://AGENTS.md"), "the instructions file is there")

	var section: PackedStringArray = ContextReportScript._section_lines(
			"res://AGENTS.md", "Conventions", true)
	assert(not section.is_empty(), "and it has a Conventions section to quote")

	var text: String = ContextReportScript.build()
	assert(text.contains("## Conventions (from AGENTS.md)"), "the snapshot says where they come from")
	assert(text.contains("\n".join(section)), "and carries the file's own words, not a paraphrase")
	assert(not text.contains("MISSING SECTION"), "with nothing missing")

	var pack: String = ContextReportScript.build_subject("plant-id")
	assert(pack.contains("\n".join(section)), "a pack carries the same rules")


func test_the_output_file_is_per_subject() -> void:
	assert(ContextReportScript.output_path("") == FULL_PATH, "no subject keeps the one file")
	assert(ContextReportScript.output_path("plant-id") == "user://gemini_context_plant-id.md",
			"a subject gets a file of its own, so it cannot overwrite the full snapshot")
	assert(ContextReportScript.build_for("") == ContextReportScript.build(),
			"and asking for no subject builds the whole snapshot")


func test_the_uncommitted_work_is_quoted_and_a_clean_tree_is_silent() -> void:
	# A clean tree, or a machine with no git at all, must leave the section out rather than print an
	# empty heading: "nothing is uncommitted" and "the command is not installed" would read the same.
	var asked: String = ContextReportScript.build_subject("drafting", {
		"git_status": " M scripts/hud.gd\n?? scripts/new_thing.gd",
		"git_diff": "--- a/scripts/hud.gd\n+++ b/scripts/hud.gd\n-old\n+new",
	})

	assert(asked.contains("## Uncommitted changes"), "the section is there when there is work")
	assert(asked.contains("?? scripts/new_thing.gd"), "with the status in it")
	assert(asked.contains("+new"), "and the diff")
	assert(not ContextReportScript.build_subject("drafting", {"git_status": "  ", "git_diff": ""})
			.contains("## Uncommitted changes"), "nothing uncommitted prints no heading")
	assert(not ContextReportScript.build_subject("drafting").contains("## Uncommitted changes"),
			"and a pack nobody asked for work in carries none")


func test_a_diff_longer_than_the_cap_says_what_it_left_out() -> void:
	# A silently shortened diff would have a reader believe a change is complete when it is not.
	var cap: int = ContextReportScript.DIFF_LINE_CAP
	var lines := PackedStringArray()
	for index: int in cap + 5:
		lines.append("+ line %d" % index)
	var asked: String = ContextReportScript.build_subject("drafting", {
		"git_status": " M a.gd", "git_diff": "\n".join(lines) + "\n"})

	assert(asked.contains("+ line %d" % (cap - 1)), "every line up to the cap is there")
	assert(not asked.contains("+ line %d" % cap), "and the rest are not")
	assert(asked.contains("The last 5 of %d lines are not shown." % (cap + 5)),
			"with the cut stated rather than silent")


func test_the_last_test_run_is_carried_and_its_tail_is_what_is_kept() -> void:
	# The verdict and the failures are the end of a log, so the end is what a pack keeps.
	var lines := PackedStringArray()
	lines.append("Ran 3 tests in 1 files in 0.1 s.")
	lines.append("VERDICT: TESTS FAILED - 2 passed, 1 failed")
	lines.append("FAILED: res://tests/test_thing.gd::test_the_rule")
	var run: String = ContextReportScript.build_subject("planting", {
		"last_run": "\n".join(lines) + "\n"})

	assert(run.contains("## The last test run"), "the section is there")
	assert(run.contains("VERDICT: TESTS FAILED - 2 passed, 1 failed"), "with the verdict in it")
	assert(run.contains("test_the_rule"), "and the failure")
	assert(not ContextReportScript.build_subject("planting", {"last_run": "\n\n"})
			.contains("## The last test run"), "an empty log prints nothing at all")


func test_a_long_test_log_keeps_its_end_not_its_start() -> void:
	var lines := PackedStringArray()
	for index: int in 100:
		lines.append("  noise line %d" % index)
	lines.append("VERDICT: TESTS PASSED - 5 passed, 0 failed")
	var run: String = ContextReportScript.build_subject("drafting", {
		"last_run": "\n".join(lines) + "\n"})

	assert(run.contains("VERDICT: TESTS PASSED"), "the verdict at the end is kept")
	assert(run.contains("The first %d of 101 lines are not shown" % (101 - ContextReportScript.RUN_TAIL_LINES)),
			"and the log says how much of its start was dropped")
	assert(not run.contains("noise line 0"), "which is the part that goes")

	assert(run.contains("## The last test run"), "and the section still names itself")


func test_a_pack_can_carry_the_commits_that_touched_this_work() -> void:
	# The rules say what the project **is**; this says what is moving in it, which is what a reader
	# needs before proposing a change to a file somebody has been editing all week.
	var text: String = ContextReportScript.build_subject("estimating", {
		"recent_commits": "abc1234 Price the last line\n9f8e7d6 Refuse an unreadable line\n",
	})

	assert(text.contains("## What has changed here lately"), "the block is there")
	assert(text.contains("abc1234 Price the last line"), "and quotes what it was given")
	assert(text.contains("9f8e7d6 Refuse an unreadable line"), "all of it")
	assert(
		not ContextReportScript.build_subject("estimating").contains("What has changed here lately"),
		"a pack nobody asked the git side of carries none"
	)

	# Capped, with the cut said in words, like every other pasted block.
	var many := PackedStringArray()
	for row: int in 100:
		many.append(" commit %d" % row)
	var capped: String = ContextReportScript.build_subject("estimating", {
		"recent_commits": "\n".join(many) + "\n"})
	assert(
		capped.contains(
			"The last %d of 100 lines are not shown." % (100 - ContextReportScript.COMMIT_LINE_CAP)
		),
		"the cap says how much of it was left out"
	)


func test_the_files_a_pack_is_about_are_the_paths_a_git_query_needs() -> void:
	# The content address and "what has changed lately" have to be about the same files, so the list is
	# the builder's to give rather than a caller's to guess at.
	var paths: PackedStringArray = ContextReportScript.fingerprint_paths("plant-id")

	assert(paths.size() > 1, "a pack is about more than one file: %d" % paths.size())
	assert(paths.has("res://scripts/plant_id_resolver.gd"), "its own scripts are named")
	assert(paths.has("res://docs/plant-database-spec.md"), "and the documents it quotes")
	for path: String in paths:
		assert(FileAccess.file_exists(path), "and every one of them is there: %s" % path)
	assert(
		ContextReportScript.fingerprint_paths("no-such-subject").is_empty(),
		"a name that is not a subject is about no files at all"
	)


func test_every_subject_says_when_to_choose_it() -> void:
	# The dock shows this one line under the picker, and it is how somebody who has never opened a
	# specification decides which pack they want. A pack without one leaves that person guessing at a
	# list of slugs.
	for name: String in ContextReportScript.subject_names():
		var when: String = ContextReportScript.when_for(name)
		assert(when.length() > 40, "%s says when to choose it" % name)
		assert(when.ends_with("."), "%s's line is a sentence" % name)

	assert(ContextReportScript.when_for("").begins_with("Everything."),
			"the whole snapshot has a line of its own, because it is not a subject")
	assert(ContextReportScript.when_for("no-such-subject") == "",
			"and an unknown subject is given no advice rather than another pack's")


func test_a_source_file_is_quoted_verbatim_when_it_is_asked_for() -> void:
	# The source is the one part of a pack that is code as it stands rather than what a script
	# declares: it is what lets a reader propose a change to a file instead of describing one. It is
	# absent unless it was asked for, so a pack about a subsystem does not grow a file nobody opened.
	var body := "extends RefCounted\n\n\nfunc doubled(value: int) -> int:\n\treturn value * 2\n"
	var handover := {"source_path": "res://scripts/doubled.gd", "source_text": body}
	var asked: String = ContextReportScript.build_subject("plant-id", handover)

	assert(asked.contains("## Full source of `res://scripts/doubled.gd` - 5 lines"),
			"the section names the file and says how big it is")
	assert(asked.contains("func doubled(value: int) -> int:"), "and quotes the code itself")
	assert(asked == ContextReportScript.build_subject("plant-id", handover),
			"building twice gives the same pack")
	assert(not ContextReportScript.build_subject("plant-id").contains("Full source of"),
			"a pack nobody asked for a source in carries none")
	assert(not ContextReportScript.build_for("").contains("Full source of"),
			"nor does the whole snapshot")
	assert(ContextReportScript.build_for("", handover).contains("func doubled"),
			"and it joins the whole snapshot when it is asked for")


func test_a_source_file_longer_than_the_cap_is_quoted_up_to_it_and_says_so() -> void:
	# A silently shortened file is worse than a refused one: a reader would rewrite the lines it was
	# never shown. So the cap is stated in the heading, in words, and the lines past it are simply not
	# there rather than pretended to be.
	var cap: int = ContextReportScript.SOURCE_LINE_CAP
	var lines := PackedStringArray()
	for index: int in cap + 3:
		lines.append("var line_%d: int = %d" % [index, index])
	var text: String = ContextReportScript.build_subject("drafting", {
		"source_path": "res://scripts/long.gd", "source_text": "\n".join(lines) + "\n"})

	assert(text.contains("## The start of `res://scripts/long.gd` - the first %d of %d lines" % [
			cap, cap + 3]), "the heading admits the cut rather than claiming the whole file")
	assert(text.contains("var line_%d: int = %d" % [cap - 1, cap - 1]),
			"every line up to the cap is there")
	assert(not text.contains("var line_%d: int = %d" % [cap, cap]),
			"and the lines past it are not")


# --- the one of each thing, and the rules the tests hold down ---------------------------------


func _read(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var text: String = file.get_as_text()
	file.close()
	return text


## Every `func test_*` name in a test file - the same rule the builder finds them by, written out again
## here so this is a check *against the file* rather than against the builder's own helper.
func _rules_in(path: String) -> Array[String]:
	var out: Array[String] = []
	for line: String in _read(path).split("\n"):
		var trimmed: String = line.strip_edges()
		if trimmed.begins_with("func test_"):
			out.append(trimmed.trim_prefix("func ").split("(")[0].strip_edges())
	return out


func test_every_one_of_each_thing_names_a_file_that_is_there() -> void:
	# The table's whole value is "the thing you were about to write already has a home", so a row naming
	# a file that has gone does the opposite: it sends a reader looking for something that is not there.
	# This is the check that keeps a hand-written table honest, and it is what makes it worth quoting.
	assert(not ContextReportScript.SINGLE_SOURCES.is_empty(), "there is a table")
	for row: Dictionary in ContextReportScript.SINGLE_SOURCES:
		var path: String = String(row["path"])
		assert(FileAccess.file_exists(path), "%s names a file that is there: %s" % [row["what"], path])
		assert(String(row["what"]).length() > 3, "a row says what the thing is: %s" % str(row))
		assert(String(row["one"]).contains("`"), "and names it in code style: %s" % str(row))
		assert(
			String(row["note"]).length() > 30,
			"and says why there must not be a second one: %s" % str(row)
		)


func test_the_one_of_each_thing_reaches_the_snapshot_and_every_pack() -> void:
	# It is the one block a reader needs whatever they were asked to change, so it is not scoped to a
	# subject: the defect it guards against is not a defect in one subsystem.
	var sentence := "**There is exactly one of each thing.**"
	var first: Dictionary = ContextReportScript.SINGLE_SOURCES[0]
	assert(ContextReportScript.build().contains(sentence), "the snapshot carries it")
	assert(ContextReportScript.build().contains(String(first["one"])), "and names the things")
	for subject: String in ContextReportScript.subject_names():
		var pack: String = ContextReportScript.build_subject(subject)
		assert(pack.contains(sentence), "%s carries the one-of-each-thing rule" % subject)
		assert(pack.contains(String(first["one"])), "%s names them" % subject)


func test_a_pack_carries_the_rules_its_own_tests_hold_down() -> void:
	# The rules are the acceptance criteria in the tests' own words: a name here is the sentence the
	# suite prints when a change breaks it, so a generated change can be checked against the list.
	var pack: String = ContextReportScript.build_subject("food-garden")
	assert(pack.contains("## The rules this work's tests hold down"), "the block is there")
	assert(pack.contains("`res://tests/test_crop_rotation.gd`"), "with the module's own test file")
	assert(
		pack.contains("test_the_same_family_shall_not_follow_itself"),
		"and the rules themselves, as the file words them"
	)


func test_the_rules_listed_are_the_names_the_test_file_really_has() -> void:
	# The derivation, held to the disk: the heading states the file's own count, every name in the file
	# is promised, and when the cap bites it says so and lists no name past it.
	var path := "res://tests/test_crop_rotation.gd"
	var real: Array[String] = _rules_in(path)
	assert(real.size() > 10, "the file has tests to derive from")
	var pack: String = ContextReportScript.build_subject("food-garden")
	var cap: int = ContextReportScript.TEST_RULE_CAP
	if real.size() > cap:
		assert(pack.contains("`%s` - the first %d of %d rules:" % [path, cap, real.size()]),
				"the heading admits the cut")
	else:
		assert(pack.contains("`%s` - %d rules:" % [path, real.size()]),
				"the heading states the file's own count")
	for index in mini(real.size(), cap):
		assert(pack.contains("* `%s`" % real[index]), "the pack lists %s" % real[index])
	if real.size() > cap:
		assert(
			not pack.contains("* `%s`" % real[real.size() - 1]),
			"and the rules past the cap are not listed"
		)


func test_two_packs_can_be_built_as_one() -> void:
	# A question that reaches across two subsystems otherwise forces a choice that loses the other half.
	# But the blocks that are the same whatever the pack is about have to be printed **once**: pasting two
	# packs one after the other pastes the conventions and the one-of-each table twice.
	var both: String = ContextReportScript.build_pair("estimating", "jobs-billing")

	assert(
		both.begins_with("# Context pack: two subjects - estimating, jobs-billing"),
		"it says which two it carries"
	)
	assert(both.contains("## The 'estimating' pack"), "the first subject has a heading of its own")
	assert(both.contains("## The 'jobs-billing' pack"), "and so does the second")
	assert(both.contains("### res://scripts/biz/takeoff.gd"), "the first pack's scripts are detailed")
	assert(both.contains("### res://scripts/biz/billing.gd"), "and the second's")
	assert(both.contains("a cost book of"), "with the first subject's own words in it")
	assert(both.contains("what happens after the price is agreed"), "and the second's")

	# Once, not twice: the shared blocks are most of what a pack carries.
	var conventions: int = both.count("## Conventions (from AGENTS.md)")
	assert(conventions == 1, "the conventions are printed once, not twice: %d" % conventions)
	var table: int = both.count("## The one of each thing")
	assert(table == 1, "and so is the one-of-each table: %d" % table)
	assert(both.count("## A test file, as this project writes one") == 1,
			"and the worked test file with it")

	# Shorter than the two packs one after the other, which is the whole reason it exists.
	var apart: int = (
		ContextReportScript.build_subject("estimating").length()
		+ ContextReportScript.build_subject("jobs-billing").length()
	)
	assert(both.length() < apart, "and it is shorter than the two packs pasted one after the other")

	# An unknown name is refused **by name**, and the same name twice is that one pack.
	assert(
		ContextReportScript.build_pair("estimating", "no-such-subject").begins_with("# Unknown subject:"),
		"an unknown name is refused rather than half built"
	)
	assert(
		ContextReportScript.build_pair("estimating", "estimating")
				== ContextReportScript.build_subject("estimating"),
		"and a pair of one is that one pack"
	)


func test_a_two_pack_payload_is_addressed_over_both_of_them() -> void:
	var both: PackedStringArray = ContextReportScript.pack_paths(
		PackedStringArray(["estimating", "jobs-billing"])
	)

	assert(both.has("res://scripts/biz/takeoff.gd"), "the first subject's files are in the list")
	assert(both.has("res://scripts/biz/billing.gd"), "and the second's")
	assert(
		ContextReportScript.pack_fingerprint(PackedStringArray(["estimating"]))
				== ContextReportScript.fingerprint_for("estimating"),
		"one subject has the same address either way"
	)
	assert(
		ContextReportScript.pack_fingerprint(PackedStringArray(["estimating", "jobs-billing"]))
				!= ContextReportScript.fingerprint_for("estimating"),
		"and two subjects are addressed over both of their files"
	)
	assert(
		ContextReportScript.pair_output_path("estimating", "jobs-billing")
				.ends_with("gemini_context_estimating+jobs-billing.md"),
		"a two-subject build writes to a file named for both"
	)


func test_a_pack_says_how_to_check_a_change_to_a_script_it_names() -> void:
	# The rules block states the acceptance criteria as the tests word them, and a reader can only
	# *read* a rule - it can **run** a command. Naming the file and the command is what turns "here are
	# the criteria" into something the reader can satisfy before handing a change back.
	var pack: String = ContextReportScript.build_subject("food-garden")

	assert(pack.contains("## How to check a change to this work"), "the block is there")
	assert(pack.contains("res://tools/run_tests.tscn"), "it names the runner")
	assert(pack.contains("the whole suite"), "with the project's own rule about running all of it")

	# The one file it says to run is derived from the work's own scripts, so it is a file that is there
	# rather than a path somebody typed into the block.
	var named := 0
	for line: String in pack.split("\n"):
		if not line.begins_with("godot") or not line.contains(" -- res://tests/"):
			continue
		var file: String = "res://tests/" + line.split(" -- res://tests/")[1].strip_edges()
		assert(FileAccess.file_exists(file), "the one file it says to run is there: %s" % file)
		named += 1
	assert(named == 1, "and exactly one file is named to be run on its own")

	# A work with no test file of its own gets no block, rather than one pointing at a file that is not
	# there.
	assert(
		ContextReportScript._verify_lines({"scripts": []}, ContextReportScript._use_index()).is_empty(),
		"nothing to check prints nothing"
	)


func test_a_pack_names_the_contents_it_was_built_from() -> void:
	# A pack is pasted into a chat, where nothing can say whether it still describes the project: the
	# reader cannot see a file that has changed underneath it. The content address is the fact that can
	# be checked - and it is over the **bytes**, not a clock or a commit, so a file that was merely
	# touched does not move it and an edit to anything the pack quotes does.
	var pack: String = ContextReportScript.build_subject("plant-id")
	var address: String = ContextReportScript.fingerprint_for("plant-id")

	assert(address.length() == ContextReportScript.FINGERPRINT_CHARS, "the address is a short one")
	assert(address.is_valid_hex_number(false), "and reads as hexadecimal: %s" % address)
	assert(pack.contains("Built from "), "the pack says what it was built from")
	assert(pack.contains("content address `%s`" % address), "and prints the address itself")

	# The same contents give the same answer; another subject is another address; and a name that is not
	# a subject has no address rather than an invented one.
	assert(ContextReportScript.fingerprint_for("plant-id") == address, "twice is the same address")
	assert(ContextReportScript.fingerprint_for("planting") != address, "another pack is another address")
	assert(ContextReportScript.fingerprint_for("no-such-subject").is_empty(), "a non-subject has none")

	# The address covers the documents a pack quotes as well as its scripts, which is what makes it a
	# fingerprint of the pack rather than of its code alone.
	for subject: String in ContextReportScript.subject_names():
		assert(
			ContextReportScript.fingerprint_for(subject).length() == ContextReportScript.FINGERPRINT_CHARS,
			"%s has an address of its own" % subject
		)


func test_every_rule_file_a_pack_names_is_a_file_that_is_there() -> void:
	var pack: String = ContextReportScript.build_subject("food-garden")
	var found := 0
	for line: String in pack.split("\n"):
		if line.begins_with("`res://tests/"):
			var path: String = line.split("`")[1]
			found += 1
			assert(FileAccess.file_exists(path), "the pack names a test file that is there: %s" % path)
	assert(found > 0, "and the block named at least one, or this test measured nothing")


# --- who uses what, and where each name lives -------------------------------------------------


## The one line of a pack that starts with a given prefix, or "".
func _line_starting(text: String, prefix: String) -> String:
	for line: String in text.split("\n"):
		if line.begins_with(prefix):
			return line
	return ""


func test_every_pack_asks_for_a_rule_it_does_not_have_rather_than_letting_one_be_invented() -> void:
	# The commonest failure of an outside reader is not a wrong line of code: it is a rule invented to
	# fill a gap this slice left. Saying so in every pack - rather than in the two briefs that happened
	# to remember - is what makes the answer available at the moment the gap is met.
	for subject: String in ContextReportScript.subject_names():
		assert(
			ContextReportScript.build_subject(subject).contains("ask for it to be written down"),
			"%s says what to do about a rule it does not state" % subject
		)
	assert(
		ContextReportScript.build().contains("ask for it to be written down"),
		"and so does the whole snapshot"
	)


func test_a_review_pack_names_the_files_the_change_touches_and_what_they_are() -> void:
	# "Review my change" is unanswerable until the reviewer knows which file is a rule, which is a page
	# and which has been deleted - the diff shows the lines but never says what kind of thing they are in.
	var status := " M scripts/crop_rotation.gd\n?? docs/food-garden-spec.md\n D scripts/gone_module.gd\n"
	var text: String = ContextReportScript.build_for("review", {"git_status": status})
	assert(text.contains("## The files this change touches"), "the block is there")
	assert(
		text.contains("`res://scripts/crop_rotation.gd` - a script - its rules are in"),
		"a script says where its rules are"
	)
	assert(text.contains("`res://docs/food-garden-spec.md` - a document"), "a document says it is one")
	assert(
		text.contains("`res://scripts/gone_module.gd` - deleted"),
		"and a file that is not there is not quietly reported as a script"
	)


func test_a_line_that_is_not_a_status_line_is_passed_over() -> void:
	var touched: PackedStringArray = ContextReportScript.touched_paths(
			"On branch main\nChanges not staged for commit:\n M scripts/a.gd\n"
	)
	assert(touched.size() == 1, "only the porcelain line is a status: %s" % str(touched))
	assert(touched[0] == "res://scripts/a.gd", "and its path is the project path: %s" % touched[0])


func test_a_review_pack_with_a_clean_tree_says_there_is_nothing_to_review() -> void:
	var text: String = ContextReportScript.build_for("review", {})
	assert(text.contains("There is nothing uncommitted to review"), "it says so by name")
	assert(
		not text.contains("## The files this change touches"),
		"and prints no empty file list, which would read as a failure"
	)


func test_a_review_pack_carries_the_commit_the_change_sits_on() -> void:
	var text: String = ContextReportScript.build_for("review", {
		"git_status": " M scripts/crop_rotation.gd\n",
		"last_commit": "abc1234 Fix the thing\n scripts/x.gd | 3 +-\n",
	})
	assert(text.contains("## The commit this change sits on"), "the commit block is there")
	assert(text.contains("abc1234 Fix the thing"), "and quotes the commit it was given")
	# Capped, and the cut stated in words: a truncated commit that looks complete is worse than none.
	var long_commit := PackedStringArray()
	for row: int in 100:
		long_commit.append(" line %d" % row)
	var capped: String = ContextReportScript.build_for("review", {
		"git_status": " M scripts/crop_rotation.gd\n",
		"last_commit": "\n".join(long_commit) + "\n",
	})
	assert(
		capped.contains("*The last 60 of 100 lines are not shown.*"),
		"the cap says how much of the commit it left out"
	)


func test_the_review_pack_quotes_the_rules_of_the_scripts_it_touches() -> void:
	var text: String = ContextReportScript.build_for("review",
			{"git_status": " M scripts/crop_rotation.gd\n"})
	assert(text.contains("## The rules those files' tests hold down"), "the rules are listed")
	assert(
		text.contains("`test_the_companion_table_reads_the_same_either_way_round`"),
		"in the tests' own words rather than a description of them"
	)


func test_the_review_scope_has_a_file_of_its_own_and_a_reason_to_pick_it() -> void:
	assert(
		ContextReportScript.output_path("review").ends_with("gemini_context_review.md"),
		"the review pack keeps a file of its own"
	)
	assert(
		ContextReportScript.output_path("review") != ContextReportScript.output_path(""),
		"and never overwrites the whole snapshot"
	)
	var reason: String = ContextReportScript.when_for("review")
	assert(not reason.is_empty(), "it says when to pick it")
	assert(reason != ContextReportScript.when_for(""), "and that is not the whole snapshot's sentence")
	assert(
		ContextReportScript.build_for("review").begins_with("# Context pack: a change under review"),
		"and the pack says what it is at the top"
	)


func test_a_pack_says_who_uses_what_it_declares() -> void:
	var pack: String = ContextReportScript.build_subject("food-garden")
	assert(pack.contains("## Who uses what this work declares"), "the block is there")
	var line: String = _line_starting(pack, "* `crop_rotation.company_line`")
	assert(line != "", "a method of one of the pack's files is listed: %s" % pack.length())
	assert(line.contains("res://scripts/rotation_window.gd"), line)
	assert(line.contains("res://tests/test_crop_rotation.gd"), "and its test: %s" % line)


func test_a_pack_shows_who_calls_whom_as_a_diagram() -> void:
	# The caller block lists callers one symbol at a time; the *shape* of a subsystem is easier to see
	# than to assemble, and this draws the same resolved index rather than restating it.
	var index: Dictionary = ContextReportScript._use_index()
	var entry: Dictionary = ContextReportScript.SUBJECTS["estimating"]
	var pack: String = ContextReportScript.build_subject("estimating")

	assert(pack.contains("## Who calls whom - derived"), "the block is there")
	assert(pack.contains("```mermaid"), "fenced as mermaid")
	assert(pack.contains("flowchart LR"), "and a left-to-right flowchart")
	assert(pack.contains("-->"), "with at least one arrow in it")

	# Every node it declares is one of the pack's own files, so the diagram cannot pull in a file the
	# pack is not about.
	var lines: PackedStringArray = ContextReportScript._graph_lines(entry, index)
	var nodes := 0
	for line: String in lines:
		if not line.begins_with("  n") or not line.contains("[\""):
			continue
		var named: String = line.split("[\"")[1].split("\"]")[0]
		var found := false
		for path: String in entry["scripts"]:
			if path.get_file().get_basename() == named:
				found = true
		assert(found, "a node is one of the pack's own files: %s" % named)
		nodes += 1
	assert(nodes == (entry["scripts"] as Array).size(), "and every file of the pack is a node")

	# Nothing to draw prints nothing, rather than an empty diagram a reader has to interpret.
	assert(
		ContextReportScript._graph_lines({"scripts": ["res://scripts/biz/money.gd"]}, index).is_empty(),
		"a work of one file has no arrows to draw"
	)


func test_a_caller_is_the_file_that_calls_it_and_not_one_that_shares_the_name() -> void:
	# The defect this block was rebuilt for. `check` is a method name five modules share, and a name
	# match reported twenty-three callers for `CropRotation.check` - `crop_sun.gd` among them, which is
	# calling its own. A caller is written `receiver.name(`, and the receiver is resolved through the
	# calling file's own preload aliases, so this is a fact rather than a word count.
	var pack: String = ContextReportScript.build_subject("food-garden")
	var line: String = _line_starting(pack, "* `crop_rotation.check`")
	assert(line != "", "the method is listed")
	assert(line.contains("`res://scripts/rotation_window.gd`"), line)
	assert(
		not line.contains("crop_sun.gd"),
		"a file with a `check` of its own is not a caller of this one: %s" % line
	)
	assert(
		not line.contains("test_crop_sun.gd"),
		"nor is the test that calls it: %s" % line
	)


func test_a_signals_callers_are_a_name_match_and_the_block_says_so() -> void:
	# `closed.connect(` does not say whose `closed` it is, and half the pages here have one, so a
	# signal's users are found by name. The block says which half of the list is which rather than
	# letting a name match read as a fact, and that disclaimer is the part that must not go missing.
	for subject: String in ContextReportScript.subject_names():
		assert(
			ContextReportScript.build_subject(subject).contains("a signal's are a **name match**"),
			"%s says that a signal's users are a name match" % subject
		)
	# And the marking is exercised: at least one of the files these packs carry declares a signal.
	var signals := 0
	for subject: String in ContextReportScript.subject_names():
		for path: String in ContextReportScript.SUBJECTS[subject]["scripts"]:
			var script: Script = load(path) as Script
			if script != null:
				signals += script.get_script_signal_list().size()
	assert(signals > 0, "some of the files the packs carry declare signals")


func test_a_named_class_is_located_and_says_how_it_is_reached() -> void:
	var pack: String = ContextReportScript.build_subject("food-garden")
	var line: String = _line_starting(pack, "* `FoodWindow`")
	assert(line != "", "the class is named with where it lives")
	assert(line.contains("`res://scripts/food_window.gd`"), line)
	assert(line.contains("no scene binds it"), "and says a page is made in code: %s" % line)
	# The other half: across every pack, some class really is bound in a scene, so the one that says
	# "bound in" is exercised rather than assumed.
	var bound := 0
	for subject: String in ContextReportScript.subject_names():
		for each: String in ContextReportScript.build_subject(subject).split("\n"):
			if each.begins_with("* `") and each.contains(" - bound in `res://scenes/"):
				bound += 1
	assert(bound > 0, "a class bound in a scene is reported as bound, not as made in code")


func test_a_bound_script_says_which_node_carries_it() -> void:
	# A scene path is half an answer: what a generator needs in order to write a line that works is the
	# **node** the script sits on. The binding report and the snapshot's scene tree read the same `.tscn`
	# lines, so the node paths they print cannot disagree.
	var text: String = ContextReportScript.build()
	var index: Dictionary = ContextReportScript._use_index()
	var bindings: Dictionary = index["bindings"]
	var controller := "res://scripts/view_controller.gd"

	assert(bindings.has(controller), "the controller is bound somewhere")
	var somewhere: Array = bindings[controller]
	assert(not somewhere.is_empty(), "with at least one node")
	assert(String(somewhere[0]).contains("/ViewController"), "and the node is in the binding")

	var words: String = ContextReportScript._binding_words(controller, index)
	assert(words.begins_with("bound in"), "the words say it is bound: %s" % words)
	assert(words.contains("`/ViewController`"), "and name the node: %s" % words)
	assert(text.contains("- `/ViewController` (Node) - script `%s`" % controller),
			"and the snapshot's scene tree agrees")

	# A page built in code still says so, rather than being handed a node it does not have.
	assert(
		ContextReportScript._binding_words("res://scripts/food_window.gd", index)
				.begins_with("no scene binds it"),
		"a page made in `build()` is not given a node"
	)


func test_every_class_a_pack_names_is_a_file_that_is_there() -> void:
	var named := 0
	for subject: String in ContextReportScript.subject_names():
		for line: String in ContextReportScript.build_subject(subject).split("\n"):
			if not line.begins_with("* `") or not line.contains("` - `res://scripts/"):
				continue
			var path: String = line.split("` - `")[1].split("`")[0]
			named += 1
			assert(FileAccess.file_exists(path), "the pack names a script that is there: %s" % path)
	assert(named > 0, "and it named at least one class, or this test measured nothing")