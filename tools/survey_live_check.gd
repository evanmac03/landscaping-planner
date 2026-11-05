extends Node
## Dev tool: instances the real game scene, waits past the watcher's 1.5 s Timer, and prints what
## the watcher actually did in a *live* scene.
##
## The unit tests drive `poll()` by hand, which says nothing about whether the Timer ever fires in
## the running game. This is the honest instrument for that: run the scene, let the clock run, and
## read the watcher's own counters plus the yard's planted list.
##
## Run it with run_scene on res://tools/survey_live_check.tscn. It prints lines beginning "CHECK".

const MAIN := "res://scenes/main.tscn"
const PlantPlacementScript := preload("res://scripts/plant_placement.gd")

## Long enough for the 1.5 s Timer to fire at least once, with room to spare.
const WAIT_SECONDS := 2.8

var _elapsed: float = 0.0
var _reported: bool = false


func _ready() -> void:
	var packed: PackedScene = load(MAIN)
	var main: Node = packed.instantiate()
	main.name = "Main"
	add_child(main)


func _process(delta: float) -> void:
	if _reported:
		return
	_elapsed += delta
	if _elapsed < WAIT_SECONDS:
		return
	_reported = true

	var main: Node = get_node_or_null(^"Main")
	if main == null:
		print("CHECK: main scene did not instance")
		return

	var watcher: Node = main.get_node_or_null(^"SurveyWatcher")
	if watcher == null:
		print("CHECK: no SurveyWatcher under Main")
	else:
		print("CHECK watcher polls=", watcher.polls, " reads=", watcher.reads,
				" imports=", watcher.imports, " placed_total=", watcher.placed_total)

	var yard: Node = main.get_node_or_null(^"Yard")
	var planted: Array = PlantPlacementScript.planted(yard)
	print("CHECK planted in yard=", planted.size())
	for node: Node3D in planted:
		print("  CHECK plant ", node.name, " species=", node.get_meta(&"species", &"(none)"),
				" at=", node.global_position)
	print("CHECK done")