extends Node
## Proof that a survey recorded on this side reaches the plan: write one the way the capture page does,
## stand the real game up around it, and report what the watcher made of it.
##
## This is the end-to-end check the modules cannot make for themselves. Everything it does is something a
## person does - a survey file appears, the timer ticks, a plant is planted - and what it prints is the
## only thing that answers "does a field capture actually arrive".
##
##     run_scene res://tools/field_capture_demo.tscn with about 5 seconds to let the 1.5 s timer tick
##
## It writes to the **real** survey path, because that is the file the watcher watches and a proof that
## wrote somewhere else would be a proof about a different file. It removes it again at the end, so the
## next time the game starts there is no survey left lying about.

const ExporterScript := preload("res://scripts/io/field_manifest_exporter.gd")
const PlacementScript := preload("res://scripts/plant_placement.gd")
const FieldCaptureScript := preload("res://scripts/field_capture.gd")
const MainScene := preload("res://scenes/main.tscn")

const MANIFEST := "user://site_manifest.json"
## The two files this tool needs nodes by: the HUD owns the one plant list and the controller owns the
## yard the plants go into.
const HUD_SCRIPT := "res://scripts/hud.gd"
const CONTROLLER_SCRIPT := "res://scripts/view_controller.gd"
## Long enough for two ticks of the watcher's 1.5 s clock, which is what makes this a test of the timer
## rather than a test of a function called by hand.
const WAIT_SECONDS := 3.5

var _game: Node = null


func _ready() -> void:
	_game = MainScene.instantiate()
	add_child(_game)

	# The game's own plant list, so the capture below is identified exactly as it would be if a person
	# had typed the name on the capture page.
	var hud: PlannerHud = _first_with_script(_game, HUD_SCRIPT) as PlannerHud
	var catalogue: PlantCatalogue = hud.plant_list() if hud != null else null
	print("DEMO the game's list holds %d species" % (catalogue.count() if catalogue != null else -1))

	# Two captures of the same plant, one measured with a tape on site and one left alone, so the report
	# below shows what a measurement really changes: the measured spread, and the catalogue's spread where
	# nobody measured anything. The third is a name the list cannot place, which must be left alone.
	var measured: Dictionary = FieldCaptureScript.identify(
		"Thymus serpyllum", 0.92, catalogue, Vector3(2.0, 0.0, 2.0), "", "by the gate, 60 cm across"
	)
	print("DEMO the offered name resolved: ok=%s species=%s" % [
		str(measured["ok"]), String(measured["capture"]["species_id"]),
	])
	measured["capture"]["measured_spread_m"] = 0.60
	var unmeasured: Dictionary = FieldCaptureScript.identify(
		"Thymus serpyllum", 0.88, catalogue, Vector3(3.6, 0.0, 2.0), "", "the one beside it"
	)
	var offered: Dictionary = FieldCaptureScript.unidentified(
		Vector3(-2.0, 0.0, 1.5), "", "did not recognise it"
	)
	offered["raw_taxon"] = "something ferny"
	var written: Error = ExporterScript.export_manifest(
		"Field survey", [measured["capture"], unmeasured["capture"], offered], MANIFEST
	)
	print("DEMO wrote %s (%s)" % [MANIFEST, "ok" if written == OK else "error %d" % written])

	var timer := Timer.new()
	timer.name = "ReportTimer"
	timer.wait_time = WAIT_SECONDS
	timer.one_shot = true
	timer.timeout.connect(_report)
	add_child(timer)
	timer.start()


func _report() -> void:
	var controller: ViewController = _first_with_script(_game, CONTROLLER_SCRIPT) as ViewController
	var hud: PlannerHud = _first_with_script(_game, HUD_SCRIPT) as PlannerHud
	if controller == null or hud == null:
		print("DEMO could not find the controller or the HUD in the scene")
		return
	var planted: Array[Node3D] = PlacementScript.planted(controller.yard)
	print("DEMO planted = %d" % planted.size())
	for node: Node3D in planted:
		# Only the plants this program put there carry these; the yard the scene ships with was built by
		# hand and has no reason to say how wide anything is.
		print("  %s  spread=%s cm  source=%s" % [
			node.name,
			str(node.get_meta(PlacementScript.SPREAD_META)) if node.has_meta(
				PlacementScript.SPREAD_META
			) else "-",
			str(node.get_meta(PlacementScript.SIZE_SOURCE_META)) if node.has_meta(
				PlacementScript.SIZE_SOURCE_META
			) else "-",
		])
	var catalogue: PlantCatalogue = hud.plant_list()
	var captures: Array = catalogue.collection("Field Survey Captures")
	print("DEMO the survey collection holds %d: %s" % [captures.size(), str(captures)])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(MANIFEST))
	print("DEMO the survey file was removed again, so the next start is clean")


## The first node in a tree whose script is this file, found by walking rather than by node path: this
## tool must not depend on where in the scene the controller happens to sit. Matched on the script's own
## path rather than on a class name, because the path is what a scene binds and it cannot be ambiguous.
func _first_with_script(root: Node, script_path: String) -> Node:
	if root == null:
		return null
	var script: Script = root.get_script() as Script
	if script != null and script.resource_path == script_path:
		return root
	for child: Node in root.get_children():
		var found: Node = _first_with_script(child, script_path)
		if found != null:
			return found
	return null