extends Node
## A dev tool: every check that needs the real game running, run in one pass against **one** instance
## of it, with a pass/fail table at the end.
##
## The checks existed already, as separate tools, and each one brought up its own copy of `main.tscn`.
## That is three startup costs to answer one question - and worse, three differently-aged scenes: a
## fault that only shows once something else has run is invisible to a check that runs alone. So this
## brings the game up once and calls `run()` on each check in turn. The two check scripts expose that
## function for exactly this reason; their own scenes are a smaller version of this file.
##
## Three of them bring nothing up themselves: the page layout check builds pages, not the game, and the
## resource walk never starts one. That is the point of calling them here instead.
##
##     res://tools/audit.tscn
##
## Read the table at the end. `AUDIT: all checks passed` is the line to look for; anything else names
## the check that did not, next to what that check found. The detail each check prints along the way is
## still there, above the table, for a person who wants to see the numbers behind a FAIL.

const MAIN := preload("res://scenes/main.tscn")
const LayoutCheck := preload("res://tools/hud_layout_check.gd")
const PlantCheck := preload("res://tools/plant_scene_check.gd")
const PageCheck := preload("res://tools/page_layout_check.gd")

## How long the game is given to lay itself out and read its own scene before anything is measured.
const SETTLING_FRAMES := 5

## What the resource walk does not descend into: the editor's own cache, and the one package here that
## is not this project's (`addons/ziva_agent` is the agent itself).
const SKIP_DIRS: Array[String] = [".godot", "ziva_agent"]


func _ready() -> void:
	var main: Node = MAIN.instantiate()
	add_child(main)
	for i: int in SETTLING_FRAMES:
		await get_tree().process_frame

	print("################ AUDIT: every check, on one instance of the game ################")
	var rows: Array[Dictionary] = []
	# Planting first. The layout check forces panels open and switches the Hud's own processing off,
	# and the plant check wants the scene the way it comes up. Planting is synchronous, so it is called
	# and not awaited; the layout check is a coroutine and has to be.
	rows.append(PlantCheck.run(main))
	rows.append(await LayoutCheck.run(main, get_tree()))
	rows.append(await PageCheck.run(get_tree()))
	rows.append(_resources_load())

	print("")
	print("=== AUDIT RESULTS ===")
	var passed: int = 0
	for row: Dictionary in rows:
		if bool(row["ok"]):
			passed += 1
		print("  %-4s  %-22s  %s" % [
			"PASS" if bool(row["ok"]) else "FAIL", String(row["name"]), String(row["summary"]),
		])
	print("  %d of %d checks passed" % [passed, rows.size()])
	if passed == rows.size():
		print("AUDIT: all checks passed")
	else:
		print("AUDIT: %d check(s) failed, named above" % (rows.size() - passed))
	print("################ END AUDIT ################")


## Every scene and resource in the project still loads, and a number to say how much was looked at.
##
## This is the check that needs nothing running and no frames: a file that will not load is a broken
## edit, and the test suite catches that only where a test happens to point at the file. It is the
## cheapest check here and the one that fails first after a bad change.
func _resources_load() -> Dictionary:
	var paths := PackedStringArray()
	_collect("res://", paths)
	paths.sort()
	var broken: Array[String] = []
	var nodes: int = 0
	for path: String in paths:
		var loaded: Resource = ResourceLoader.load(path)
		if loaded == null:
			broken.append(path)
			continue
		var packed := loaded as PackedScene
		if packed == null:
			continue
		# Instantiated and freed without ever entering the tree: `_ready` does not run, so this reads
		# the scene the file describes rather than starting a second copy of the game.
		var instance: Node = packed.instantiate()
		if instance == null:
			broken.append(path)
			continue
		nodes += _count(instance)
		instance.free()

	print("=== EVERY SCENE AND RESOURCE LOADS (%d files, %d nodes) ===" % [paths.size(), nodes])
	for path: String in broken:
		print("  WILL NOT LOAD  %s" % path)
	var summary: String
	if broken.is_empty():
		summary = "%d file(s) load" % paths.size()
		print("  all of them load")
	else:
		summary = "%d of %d will not load: %s" % [broken.size(), paths.size(), ", ".join(broken)]
	return {"name": "every scene loads", "ok": broken.is_empty(), "summary": summary}


func _count(node: Node) -> int:
	var total: int = 1
	for child in node.get_children():
		total += _count(child)
	return total


func _collect(dir_path: String, out: PackedStringArray) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for file: String in dir.get_files():
		if file.ends_with(".tscn") or file.ends_with(".tres"):
			out.append(dir_path.path_join(file))
	for folder: String in dir.get_directories():
		if folder.begins_with(".") or folder in SKIP_DIRS:
			continue
		_collect(dir_path.path_join(folder), out)