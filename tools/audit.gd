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

## What the resource walk does not descend into. **The editor's own cache, and the packages installed here
## rather than written here** - and it is no longer one package. This list held only `ziva_agent` when the
## note above was written, and said so; eight tool addons have been installed since, and these are the ones
## that carry a scene. Two shapes of false finding live in them, and neither is a fault of this project:
## `StyleboxFancy`'s corner inspector holds an `EditorSpinSlider`, which cannot be instantiated outside the
## editor, so the walk met it and reported sixteen errors against a project with nothing wrong with it; and
## `PlantGenerator` ships a `calculator.tscn` whose root node is a `Node` wearing a script that extends
## `RefCounted`, which cannot be assigned to the node at all, and whose `ext_resource` path no longer
## resolves (only its uid still does). Both are the same as a rectangle read from a stale block - a finding
## about a package, not about the game. `.gitignore` draws this line for the packages it names, calling
## them "not source"; this is that list, and it stops before their scenes rather than trying to tell an
## editor scene from a game one.
const SKIP_DIRS: Array[String] = [
	".godot",
	"ziva_agent",
	"godot_mcp_toolkit",
	"crabbyconsole",
	"GDQuest_GDScript_formatter",
	"godoban",
	"gdscript2all",
	"StyleboxFancy",
	"syntax_plus",
	"PlantGenerator",
]


func _ready() -> void:
	await run(self)


## Bring the game up under `host`, let it settle, and run every check on it - printing the table as this
## file always has, and **returning** the rows as well, so that a caller can read the verdict without
## reading this file's words. `tools/debug_toolbox.gd` is that caller, and is why this is static: a caller
## is not a second copy of the audit, it is the same one journey.
static func run(host: Node) -> Array[Dictionary]:
	var main: Node = MAIN.instantiate()
	host.add_child(main)
	for i: int in SETTLING_FRAMES:
		await host.get_tree().process_frame

	print("################ AUDIT: every check, on one instance of the game ################")
	var rows: Array[Dictionary] = []
	# Planting first. The layout check forces panels open and switches the Hud's own processing off,
	# and the plant check wants the scene the way it comes up. Planting is synchronous, so it is called
	# and not awaited; the layout check is a coroutine and has to be.
	rows.append(PlantCheck.run(main))
	rows.append(await LayoutCheck.run(main, host.get_tree()))
	rows.append(await PageCheck.run(host.get_tree()))
	rows.append(_resources_load())

	print("")
	print("=== AUDIT RESULTS ===")
	var passed: int = 0
	for row: Dictionary in rows:
		if bool(row["ok"]):
			passed += 1
		print(
			"  %-4s  %-22s  %s" % ["PASS" if bool(row["ok"]) else "FAIL", String(row["name"]), String(row["summary"])]
		)
	print("  %d of %d checks passed" % [passed, rows.size()])
	if passed == rows.size():
		print("AUDIT: all checks passed")
	else:
		print("AUDIT: %d check(s) failed, named above" % (rows.size() - passed))
	print("################ END AUDIT ################")
	return rows


## Every scene and resource in the project still loads, and a number to say how much was looked at.
##
## This is the check that needs nothing running and no frames: a file that will not load is a broken
## edit, and the test suite catches that only where a test happens to point at the file. It is the
## cheapest check here and the one that fails first after a bad change.
static func _resources_load() -> Dictionary:
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
	# **The reading, beside its consequence.** "n files load" cannot be weighed without the list of what was
	# not looked at, and SKIP_DIRS has grown from the editor's cache to ten trees as packages were installed
	# and two were vendored. A scene inside one of them is not this project's to load, so a fault in one is not
	# this project's fault - and without this line a reader has no way to tell the two apart.
	print("  the walk leaves %d tree(s) alone: %s" % [SKIP_DIRS.size(), ", ".join(SKIP_DIRS)])
	print("  and a scene inside one of them is not this project's to load")
	for path: String in broken:
		print("  WILL NOT LOAD  %s" % path)
	var summary: String
	if broken.is_empty():
		summary = "%d file(s) load" % paths.size()
		print("  all of them load")
	else:
		summary = "%d of %d will not load: %s" % [broken.size(), paths.size(), ", ".join(broken)]
	return { "name": "every scene loads", "ok": broken.is_empty(), "summary": summary }


static func _count(node: Node) -> int:
	var total: int = 1
	for child in node.get_children():
		total += _count(child)
	return total


static func _collect(dir_path: String, out: PackedStringArray) -> void:
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
