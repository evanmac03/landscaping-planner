extends Node
## The standalone test runner's discovery: which files are tests, and which methods in them are.
##
## Discovery is the part that decides whether a run is honest, so it is the part that is tested:
## a file that is silently skipped, or a helper silently run as a test, would make the verdict a
## statement about a smaller set of tests than the one it names.

const RunnerScript := preload("res://tools/run_tests.gd")


func test_the_tests_folder_is_a_suite() -> void:
	var paths: PackedStringArray = RunnerScript.test_paths("res://tests")

	assert(paths.size() > 200, "the suite is not a handful of files")
	assert(paths.has("res://tests/test_plants.gd"), "and a known test file is in it")
	for path: String in paths:
		assert(path.ends_with(".gd"), "%s is a script" % path)


func test_one_file_or_a_missing_one_can_be_named() -> void:
	assert(RunnerScript.test_paths("res://tests/test_plants.gd").size() == 1, "one file, one path")
	assert(RunnerScript.test_paths("res://tests/no_such_test.gd").is_empty(),
			"a file that is not there is no run")
	assert(RunnerScript.test_paths("res://no_such_folder").is_empty(),
			"and a folder that is not there is no run either")


func test_only_test_methods_are_offered() -> void:
	var names: PackedStringArray = RunnerScript.test_methods(load("res://tests/test_plants.gd"))

	assert(not names.is_empty(), "the file has tests")
	for name: String in names:
		assert(name.begins_with("test_"), "%s is a test" % name)


func test_a_helper_is_not_run_as_a_test() -> void:
	# test_view_keys.gd has `_bring_up` and `_tear_down`: real code, not tests.
	var names: PackedStringArray = RunnerScript.test_methods(
			load("res://tests/test_view_keys.gd"))

	assert(not names.has("_bring_up"), "a helper is not a test")
	assert(not names.has("_tear_down"), "nor is the one that cleans up after it")
	assert(names.size() >= 3, "while the tests in the file are offered")


func test_a_filter_narrows_the_run() -> void:
	var script: Script = load("res://tests/test_plants.gd")
	var all: PackedStringArray = RunnerScript.test_methods(script)
	var one: String = String(all[0])
	var filtered: PackedStringArray = RunnerScript.test_methods(script, one)

	assert(filtered.has(one), "the test that was asked for is in the run")
	assert(filtered.size() <= all.size(), "and the run did not grow")
	assert(RunnerScript.test_methods(script, "no_such_test_name").is_empty(),
			"a filter that matches nothing runs nothing, rather than everything")


func test_no_script_is_no_tests() -> void:
	assert(RunnerScript.test_methods(null).is_empty(), "a script that failed to load has no tests")


## **A file that will not load is a failure, not a skip.**
##
## `load()` on a script with a parse error does **not** return `null`: it returns a `GDScript` whose
## `can_instantiate()` is false and which lists no methods, so a check for `null` alone missed it, the file
## was counted as "held no test", and a run of zero tests printed `VERDICT: TESTS PASSED` - a verdict CI
## would take as green. This is the predicate that says otherwise.
##
## The broken case is not *built* here, and deliberately: compiling bad source raises the very script error
## this runner counts as a failure, so a test that made one would fail itself (measured - it does, and that
## is why this comment exists). The predicate is held down on the two halves it is made of instead, and the
## real broken file was proved by running the suite with one in place.
func test_a_script_that_cannot_be_made_is_not_one_to_run() -> void:
	assert(not RunnerScript.is_runable(null), "nothing is not a script to run")
	var never_compiled := GDScript.new()
	assert(
		not RunnerScript.is_runable(never_compiled),
		"a script that cannot be instantiated is not one to run"
	)
	assert(
		RunnerScript.is_runable(load("res://tests/test_run_tests.gd")),
		"while a real test file is"
	)


func test_the_run_is_left_where_a_pack_can_read_it() -> void:
	# The AI context dock offers "include the last test run" as something to attach, so a run has to
	# leave one behind: the verdict, and every failure by name. Written to a temporary file and renamed,
	# so a run killed mid-write cannot leave a shorter log than the last good one in its place.
	var runner: Node = RunnerScript.new()
	# Its own path, never the dock's own log: a test that failed halfway through would otherwise leave
	# a fake failure exactly where the next pack would find it and attach it.
	var where := "user://test_log_check.txt"
	runner._passed = 2
	runner._failed = 1
	runner._failures = PackedStringArray(["res://tests/x.gd::test_the_rule"])
	runner._write_log(3, 1000, "VERDICT: TESTS FAILED - 2 passed, 1 failed", where)

	assert(FileAccess.file_exists(where), "the run leaves a log behind")
	assert(not FileAccess.file_exists(where + ".part"), "and the temporary file is gone, not left over")
	var file := FileAccess.open(where, FileAccess.READ)
	var text := file.get_as_text()
	file.close()
	assert(text.contains("Ran 3 tests in 3 files in 1.0 s."), "with what was run, and how long it took")
	assert(text.contains("VERDICT: TESTS FAILED - 2 passed, 1 failed"), "and the verdict")
	assert(text.contains("FAILED: res://tests/x.gd::test_the_rule"), "and the failure by name")

	runner.free()
	DirAccess.remove_absolute(where)