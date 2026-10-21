extends Node
## Tests for the audit tool.
##
## `tools/audit.gd` is a dev tool and not a test, so there is nothing here about what it prints. What
## there *is* here is the one thing the tool cannot check about itself: **that a check can fail.**
##
## A table that says PASS is theatre if every check is a printout wearing a verdict, and the only way to
## show that a verdict is derived rather than decorative is to hand a check a scene that is not the game
## and see it refuse. So each check is called with a bare node - which is exactly what a scene that is
## not `main.tscn` looks like - and its verdict is read.
##
## The two printed lines these tests make are the checks saying what they found. They are deliberate:
## a check that refused in silence would be the thing being tested against.

const LayoutCheck := preload("res://tools/hud_layout_check.gd")
const PlantCheck := preload("res://tools/plant_scene_check.gd")


## The audit's whole premise is that each check is a function it can call on a game it brought up
## itself. Both call it as `SomeCheck.run(...)`, so a check without one would not parse - but a check
## whose `run` is not *static* would, and would fail only when the audit was run.
func test_both_checks_offer_the_call_the_audit_makes() -> void:
	for path: String in [
		"res://tools/hud_layout_check.gd",
		"res://tools/plant_scene_check.gd",
	]:
		var source: String = FileAccess.get_file_as_string(path)
		assert(source.contains("static func run("), path + " has no run() the audit can call")


## A scene with no Hud in it is not the game, and the check says so rather than reading a null.
func test_the_plant_check_refuses_a_scene_that_is_not_the_game() -> void:
	var bare := Node.new()
	var verdict: Dictionary = PlantCheck.run(bare)
	bare.free()
	assert(not bool(verdict["ok"]), "a scene with nothing to plant is not a pass")
	assert(String(verdict["name"]) == "what the scene plants", String(verdict["name"]))
	assert(int(verdict["planted"]) == 0, "and nothing was planted in it")
	assert(String(verdict["summary"]).contains("no Hud"), String(verdict["summary"]))


## The same for the layout check. It refuses before it reaches any frame, which is why it can be
## called with no tree at all - and why the `await` below never actually waits for anything.
func test_the_layout_check_refuses_a_scene_that_is_not_the_game() -> void:
	var bare := Node.new()
	var verdict: Dictionary = await LayoutCheck.run(bare, null)
	bare.free()
	assert(not bool(verdict["ok"]), "a scene with no HUD has no layout to pass")
	assert(String(verdict["name"]) == "HUD layout", String(verdict["name"]))
	assert(int(verdict["clashes"]) == 0, "and no clash was counted in it")
	assert(String(verdict["summary"]).contains("no Hud/Root"), String(verdict["summary"]))


## Every verdict carries the three things the table prints, so a check that grew a different shape
## would be a fault rather than a row of the table with blanks in it.
func test_a_verdict_carries_what_the_table_prints() -> void:
	var bare := Node.new()
	var verdict: Dictionary = PlantCheck.run(bare)
	bare.free()
	for key: String in ["name", "ok", "summary"]:
		assert(verdict.has(key), "a verdict has no " + key)
	assert(verdict["name"] is String and verdict["summary"] is String,
		"a name and a summary are words")


func test_the_audit_scene_runs_the_audit_script() -> void:
	var packed := ResourceLoader.load("res://tools/audit.tscn", "PackedScene") as PackedScene
	assert(packed != null, "the audit scene loads")
	var root: Node = packed.instantiate()
	var script: Script = root.get_script()
	var path: String = script.resource_path if script != null else ""
	root.free()
	assert(path == "res://tools/audit.gd", path)