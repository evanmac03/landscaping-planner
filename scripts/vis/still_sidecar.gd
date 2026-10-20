class_name StillSidecar
extends RefCounted
## The record that goes beside a rendered still.
##
## A proposal image with no record of how it was made cannot be re-made: the same
## view, at the same sun, with the same lens, is what turns "that picture" into
## "that picture again, but with the hedge I just moved". So a still is always two
## files, and the second one is small.

## The keys every record carries. A test asserts them, because a field that
## quietly stops being written is worse than a field that was never promised.
const KEYS: Array[String] = [
	"app", "view", "rendered", "output_px", "supersample", "tier",
	"sun", "plot_scale", "camera", "document", "godot",
]


## A record for one still.
##
## Everything is passed in rather than read from the running scene, so the record
## describes the picture that was actually taken rather than the state of the
## application when somebody got round to asking.
static func record(
	view_name: String,
	output_size: Vector2i,
	supersample: int,
	tier_name: String,
	sun: Dictionary,
	camera: Dictionary,
	plot_scale: float,
	entity_count: int
) -> Dictionary:
	return {
		"app": ProjectSettings.get_setting("application/config/name", "Backyard Design"),
		"view": view_name,
		"rendered": Time.get_datetime_string_from_system(false, true),
		"output_px": [output_size.x, output_size.y],
		"supersample": supersample,
		"tier": tier_name,
		"sun": sun,
		"plot_scale": plot_scale,
		"camera": camera,
		"document": {"entities": entity_count},
		# A renderer change is the one thing that silently changes a picture, so
		# the version that drew it is part of the record.
		"godot": Engine.get_version_info()["string"],
	}


## Write a record beside a PNG. Returns the path, or "" if it could not be written.
static func write(png_path: String, record_data: Dictionary) -> String:
	var sidecar_path: String = png_path.get_basename() + ".json"
	var file := FileAccess.open(sidecar_path, FileAccess.WRITE)
	if file == null:
		push_error("StillSidecar: could not write %s (%d)" % [
			sidecar_path, FileAccess.get_open_error(),
		])
		return ""
	# Indented, because this file is meant to be read by a person trying to work
	# out how a picture was made.
	file.store_string(JSON.stringify(record_data, "  "))
	file.close()
	return sidecar_path


## Read a record back. Returns {} when the file is missing or unreadable, so a
## caller can tell "no record" from "a record that says nothing".
static func read(png_path: String) -> Dictionary:
	var sidecar_path: String = png_path.get_basename() + ".json"
	if not FileAccess.file_exists(sidecar_path):
		return {}
	var file := FileAccess.open(sidecar_path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}