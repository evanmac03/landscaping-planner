extends Node
## Runs the GDScript test suite **headlessly, with no editor and no MCP**, so an agent that is not
## Ziva - and CI - can answer "does it still work" with one command:
##
##     Godot_v4.7.2-stable_win64_console.exe --headless --path <project> res://tools/run_tests.tscn
##     ... res://tools/run_tests.tscn -- res://tests/test_plants.gd    (one file)
##     ... res://tools/run_tests.tscn -- res://tests plant_            (a name filter)
##
## A test file is a script under `res://tests` that `extends Node` and has methods named `test_*`.
## A test **passes when running it raises no script error**, which is exactly what a failed
## `assert()` raises. `push_error`, `push_warning` and the engine's own `ERR_FAIL_*` checks are not
## script errors and do not fail a test - a test that asserts a refusal is a test doing its job.
##
## **A file that will not load is a failure, not a quiet skip.** `load()` on a script with a parse error
## does *not* return `null` - it returns a `GDScript` with no methods and `can_instantiate()` false - so a
## file nothing could run looked exactly like one whose tests a filter had not named, and a run of **zero**
## tests still printed `VERDICT: TESTS PASSED`. That is a verdict CI would take as green, so `is_runable`
## below is the check and the file is recorded as a failure.
##
## The suite is added to this node, because a test that brings the planner up (`test_view_keys.gd`
## does) needs `get_tree()` and `add_child` to work. Each test call is **awaited**, so a test that
## waits for frames finishes before the next one starts.
##
## Exit code 0 when everything passed, 1 when something failed, 2 when the run timed out.

const TESTS_DIR := "res://tests"

## A run that stops finishing is worse than one that fails: this ends it, loudly.
const WATCHDOG_SECONDS := 900.0

## Where a run leaves its result, for the AI context dock to attach to a pack. One name, so the runner
## and the dock cannot disagree about where it is.
const LOG_PATH := "user://last_test_run.txt"

var _passed: int = 0
var _failed: int = 0
var _failures: PackedStringArray = PackedStringArray()


## Captures the script errors raised while one test runs. Only `ERROR_TYPE_SCRIPT` is kept: the
## other kinds are how a test states that something was refused, and refusing is not failing.
class ErrorCapture:
	extends Logger

	var lines: PackedStringArray = PackedStringArray()
	var capturing: bool = false

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _backtraces: Array) -> void:
		if error_type != ERROR_TYPE_SCRIPT or not capturing:
			return
		lines.append("%s (%s:%d in %s)" % [
				rationale if not rationale.is_empty() else code, file.get_file(), line, function])


# --- discovery, which is what the unit test holds down ----------------------------------------


## The test files to run: one named file, or every `.gd` in a folder, sorted.
static func test_paths(target: String = TESTS_DIR) -> PackedStringArray:
	var out := PackedStringArray()
	if target.ends_with(".gd"):
		if FileAccess.file_exists(target):
			out.append(target)
		return out
	var dir := DirAccess.open(target)
	if dir == null:
		return out
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and entry.ends_with(".gd"):
			out.append(target.path_join(entry))
		entry = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out


## Whether a loaded script is one this runner can actually run tests from.
##
## **A file that fails to compile is not `null`.** Godot hands back a `GDScript` object whose
## `can_instantiate()` is false and which lists no methods at all - measured: `reload()` returns
## `ERR_PARSE_ERROR` (43), `can_instantiate()` is false, `get_script_method_list()` is empty. A check for
## `null` alone therefore missed it, and the file was counted as "held no test matching the filter": a run
## of zero tests printed `VERDICT: TESTS PASSED`. A script that cannot be made is not a script to run.
static func is_runable(script: Script) -> bool:
	return script != null and script.can_instantiate()


## The `test_*` methods of a script, in the order the file declares them. A helper - `_bring_up`,
## `_cleanup` - is not a test however it is named.
static func test_methods(script: Script, filter: String = "") -> PackedStringArray:
	var names := PackedStringArray()
	if script == null:
		return names
	for method: Dictionary in script.get_script_method_list():
		var method_name := String(method["name"])
		if method_name.begins_with("test_") and (
			filter.is_empty() or method_name.contains(filter)
		):
			names.append(method_name)
	return names


# --- the run ----------------------------------------------------------------------------------


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var target: String = String(args[0]) if args.size() > 0 else TESTS_DIR
	var filter: String = String(args[1]) if args.size() > 1 else ""

	var watchdog := Timer.new()
	watchdog.wait_time = WATCHDOG_SECONDS
	watchdog.one_shot = true
	watchdog.timeout.connect(_on_watchdog)
	add_child(watchdog)
	watchdog.start()

	var paths := test_paths(target)
	if paths.is_empty():
		printerr("No test files under %s" % target)
		get_tree().quit(1)
		return

	var capture := ErrorCapture.new()
	OS.add_logger(capture)

	var quiet_files := 0
	var started := Time.get_ticks_msec()

	for path: String in paths:
		var script: Script = load(path)
		if not is_runable(script):
			_record_failure("%s - not loadable (a parse error?)" % path)
			continue
		var names := test_methods(script, filter)
		if names.is_empty():
			quiet_files += 1
			continue
		for test_name: String in names:
			# A **fresh instance per test**, not one per file: a test file may keep state in a member
			# (`test_sun_window.gd` records what the page announced in one) and its tests assert on
			# that state from empty. One instance for the file would carry one test into the next.
			var suite: Object = script.new()
			if not suite is Node:
				_record_failure("%s - does not extend Node" % path)
				break
			add_child(suite as Node)
			capture.lines.clear()
			capture.capturing = true
			await suite.call(test_name)
			capture.capturing = false
			if capture.lines.is_empty():
				_passed += 1
			else:
				_record_failure("%s::%s\n    %s" % [path, test_name, "\n    ".join(capture.lines)])
			(suite as Node).free()

	OS.remove_logger(capture)
	watchdog.stop()

	var elapsed_ms := Time.get_ticks_msec() - started
	print("Ran %d tests in %d files in %.1f s." % [
			_passed + _failed, paths.size(), elapsed_ms / 1000.0])
	if quiet_files > 0:
		print("  %d file(s) held no test matching the filter." % quiet_files)
	for line: String in _failures:
		printerr("FAILED: %s" % line)
	var verdict := "VERDICT: %s - %d passed, %d failed" % [
			"TESTS PASSED" if _failed == 0 else "TESTS FAILED", _passed, _failed]
	print(verdict)
	_write_log(paths.size(), elapsed_ms, verdict)
	get_tree().quit(0 if _failed == 0 else 1)


## Leave the run where the AI context dock can read it, so a pack can carry the failure it was built to
## explain. Written to a temporary file and renamed, like every other write in this project, so a run
## killed mid-write cannot leave a shorter log than the last good one in its place.
## `where` is the log's own path, so a test can write somewhere harmless; a real run uses the default.
func _write_log(
		files_n: int, elapsed_ms: int, verdict: String, where: String = LOG_PATH
) -> void:
	var out := PackedStringArray()
	out.append("Ran %d tests in %d files in %.1f s." % [
			_passed + _failed, files_n, elapsed_ms / 1000.0])
	out.append(verdict)
	for line: String in _failures:
		out.append("FAILED: %s" % line)
	var temporary := where + ".part"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return
	file.store_string("\n".join(out) + "\n")
	file.close()
	DirAccess.rename_absolute(temporary, where)


func _record_failure(message: String) -> void:
	_failed += 1
	_failures.append(message)


func _on_watchdog() -> void:
	printerr("TIMED OUT after %.0f s - a test is not finishing." % WATCHDOG_SECONDS)
	get_tree().quit(2)