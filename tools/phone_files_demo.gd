extends Node
## What the program's own file doors become when the machine is a phone, driven at the real HUD.
##
## A development tool rather than part of the game. It instances `main.tscn` with the device forced to
## a phone *before* the scene is made - because the HUD builds its doors in `_ready`, and a door is
## prepared once, where it is made - and then reads every one of them back. Run
## `scenes/phone_files_demo.tscn` and read the console:
##
##     this machine      has a picker of its own: true
##     as a phone        files come from the phone's own file picker, ...
##       _survey_dialog         handed to the picker: true
##       ...
##     PHONE FILES: every door that reaches outside follows the picker, and every door into user://
##                  stays the program's own
##
## The one thing this cannot decide for you is whether a real phone makes the same answer: `has_picker()`
## is the machine's, not the demonstration's. On a computer without one every door reads false, which is
## correct and proves less - the phone is the witness for the other reading.

const PhoneFilesScript := preload("res://scripts/phone_files.gd")

## The doors that reach outside the program's own folder: somebody else's file, or a place the person
## chose. On a phone each of these is handed to the phone's own picker.
const OUTSIDE := [
	"_survey_dialog",
	"_dxf_dialog",
	"_dxf_export_dialog",
	"_model_export_dialog",
	"_landxml_dialog",
	"_osm_dialog",
	"_underlay_dialog",
	"_plant_import_dialog",
]

## The doors into `user://`: a drawing is written to a temporary file and renamed into place, and a
## hand-over cannot rename anything. These stay the program's own whatever the device.
const INSIDE := ["_open_dialog", "_save_dialog", "_plant_export_dialog"]

var _app: Node = null
var _hud: Node = null


func _ready() -> void:
	# Before the scene exists: the HUD makes its doors in `_ready`, and a door is prepared where it is
	# made rather than every time somebody opens it.
	PhoneFilesScript.force(PhoneFilesScript.Device.PHONE)
	_app = load("res://scenes/main.tscn").instantiate()
	_app.name = "App"
	add_child(_app)
	for i in 3:
		await get_tree().process_frame

	_hud = _find_hud(_app)
	if _hud == null:
		print("PHONE FILES: no HUD in main.tscn")
		get_tree().quit(1)
		return

	var picker: bool = PhoneFilesScript.uses_the_picker()
	print("this machine      has a picker of its own: %s" % str(PhoneFilesScript.has_picker()))
	print("as a phone        files come from %s" % PhoneFilesScript.describe())

	var wrong: Array[String] = []
	for door_name: String in OUTSIDE:
		var door: FileDialog = _hud.get(StringName(door_name))
		if door == null:
			wrong.append("%s was never built" % door_name)
			print("  %-22s not built" % door_name)
			continue
		print("  %-22s handed to the picker: %s" % [door_name, str(door.use_native_dialog)])
		if door.use_native_dialog != picker:
			wrong.append("%s does not follow the picker" % door_name)
		if door.access != FileDialog.ACCESS_FILESYSTEM:
			wrong.append("%s no longer reaches the filesystem" % door_name)

	for door_name: String in INSIDE:
		var kept: FileDialog = _hud.get(StringName(door_name))
		if kept == null:
			wrong.append("%s was never built" % door_name)
			print("  %-22s not built" % door_name)
			continue
		print("  %-22s handed to the picker: %s" % [door_name, str(kept.use_native_dialog)])
		if kept.use_native_dialog:
			wrong.append("%s was handed over and writes a temporary file" % door_name)

	for complaint: String in wrong:
		print("PHONE FILES: %s" % complaint)
	print("PHONE FILES: %s" % (
		"every door that reaches outside follows the picker, and every door into user:// stays the"
		+ " program's own"
		if wrong.is_empty() else "A DOOR IS NOT WHERE IT BELONGS"
	))
	await get_tree().process_frame
	get_tree().quit(0 if wrong.is_empty() else 1)


## The running app's own HUD, found by the script it carries rather than by a node path that a scene
## edit would move out from under this tool.
func _find_hud(root: Node) -> Node:
	for node: Node in root.find_children("*", "", true, false):
		var script: Script = node.get_script()
		if script != null and String(script.resource_path).ends_with("hud.gd"):
			return node
	return null
