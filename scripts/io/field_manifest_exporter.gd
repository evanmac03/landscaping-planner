class_name FieldManifestExporter
extends RefCounted
## Writes and reads the survey manifest a phone capture arrives as: a site's features, where each
## one is, and how confidently it was identified.
##
##     FieldManifestExporter.export_manifest(site_name, features, "user://site_manifest.json")
##     var read: Dictionary = FieldManifestExporter.read_manifest(path)   # { ok, reason, data }
##
## JSON, so a program that has never heard of Godot can read it, and every write goes through
## `to_manifest`, so the shape on disk and the shape in memory are one description and not two.

## The manifest format this build writes. **2** added the classifier's own words (`raw_taxon`) and
## which part of the plant was photographed (`part`). A version **1** manifest still reads, and is not
## upcast: a record that does not say which part was photographed is one that simply does not say.
const FORMAT_VERSION := 2

## The name a half-written manifest carries while it is being written. The same suffix
## `PlantCatalogue` uses, because these are the two files a nursery list and a field survey arrive as
## and a person looking in the folder should see one shape of litter, not two.
const TEMP_SUFFIX := ".writing"

# --- export formats --------------------------------------------------------

## One feature as a JSON object. A feature may carry the PlantSpecies itself or only
## its id; both are written as `species_id`, which is what the other side matches on.
static func _feature_dict(feature: Dictionary) -> Dictionary:
	var entry: Dictionary = {}
	entry["instance_id"] = String(feature.get("instance_id", ""))
	var species: Variant = feature.get("species", null)
	if species is PlantSpecies:
		entry["species_id"] = String((species as PlantSpecies).id)
		entry["botanical_name"] = (species as PlantSpecies).botanical_name
	else:
		entry["species_id"] = String(feature.get("species_id", ""))
	# The name the classifier offered, kept whether or not it resolved to a species: on this side of
	# the file that string is the only evidence of what was actually seen, and a person correcting a
	# record needs it. And which part of the plant was in the photograph, because that is what makes a
	# second identification of the same plant a fair comparison rather than a different question.
	entry["raw_taxon"] = String(feature.get("raw_taxon", ""))
	entry["part"] = String(feature.get("part", ""))
	# Which model named the plant, when one did. A confidence with nothing behind it is a number; a
	# confidence with the model's name and version beside it is something a person can weigh later.
	entry["model_id"] = String(feature.get("model_id", ""))
	entry["model_version"] = String(feature.get("model_version", ""))
	# What somebody measured on site, in metres. Zero means nobody measured it, and the reader treats a
	# zero as "the catalogue's own size" rather than as a plant of no size.
	entry["measured_height_m"] = float(feature.get("measured_height_m", 0.0))
	entry["measured_spread_m"] = float(feature.get("measured_spread_m", 0.0))
	entry["confidence"] = float(feature.get("confidence", 0.0))
	entry["position"] = _position_dict(feature.get("position", null))
	entry["sun_mask"] = int(feature.get("sun_mask", 0))
	entry["drainage_mask"] = int(feature.get("drainage_mask", 0))
	entry["notes"] = String(feature.get("notes", ""))
	# The photograph the capture was taken from, as the path the field side filed it under. A manifest
	# without it is a list of names somebody typed; with it, a record of what was actually seen.
	entry["photo_path"] = String(feature.get("photo_path", ""))
	return entry


## A position as `{x, y, z}`, from whichever shape the caller had it in: a `Vector3` from a
## GDScript caller, or the dictionary a parsed JSON manifest hands back. A manifest that
## comes in as JSON - which is how the phone's manifest arrives - has no `Vector3` in it,
## so accepting only one shape would refuse to round-trip the exporter's own output.
static func _position_dict(raw: Variant) -> Dictionary:
	if raw is Vector3:
		var point: Vector3 = raw
		return {"x": point.x, "y": point.y, "z": point.z}
	if raw is Dictionary:
		var given: Dictionary = raw
		return {
			"x": float(given.get("x", 0.0)),
			"y": float(given.get("y", 0.0)),
			"z": float(given.get("z", 0.0)),
		}
	return {"x": 0.0, "y": 0.0, "z": 0.0}


## The **one** way a manifest is written, and it goes through a temporary file and a rename, the same
## rule as a drawing, a catalogue and a cost book: a write that fails half way must not leave a shorter
## manifest where the real one was. That matters more here than anywhere else in the program, because
## the other side of this file is a separate one that reads whatever is there and has no way to tell a
## survey cut off in the middle from a small survey. The folder is made first, so a survey written
## under `user://surveys/` does not need it to exist.
static func export_manifest(site_name: String, features: Array, path: String) -> Error:
	var folder: String = path.get_base_dir()
	if not folder.is_empty() and not DirAccess.dir_exists_absolute(folder):
		var made: Error = DirAccess.make_dir_recursive_absolute(folder)
		if made != OK and made != ERR_ALREADY_EXISTS:
			return made
	var temp: String = path + TEMP_SUFFIX
	var file: FileAccess = FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(to_manifest(site_name, features), "  "))
	file.close()
	var moved: Error = DirAccess.rename_absolute(temp, path)
	if moved != OK:
		# The real file is still the one that was there, so the half-written one is nothing but litter.
		DirAccess.remove_absolute(temp)
		return moved
	return OK


## A survey as a plain Dictionary: a site name and a `features` array, each feature
## naming the species it was identified as and where it stands. Built to be written
## with JSON.stringify and nothing else, so every value in it is a JSON type.
static func to_manifest(site_name: String, features: Array) -> Dictionary:
	return {
		"format_version": FORMAT_VERSION,
		"site_name": site_name,
		"features": _features_list(features),
	}


static func _features_list(features: Array) -> Array:
	var out_features: Array = []
	for feature: Variant in features:
		if feature is Dictionary:
			out_features.append(_feature_dict(feature))
	return out_features


## Add features to the survey at `path`, keeping the ones already in it. Returns
## `{ok, reason, added, total}`.
##
## This is the desk side of the same file the field tool writes, so a capture recorded on the page
## arrives the way a phone's does and nothing downstream can tell the two apart. Three rules, each of
## them there because the alternative loses a record:
##
## * a feature that brings no `instance_id` **is given one derived from what it is**. `SurveyWatcher`
##   keeps an imported feature by that id and skips one without it, so a capture with no id would be a
##   record that reached the file and never arrived. Derived from the content rather than counted, so
##   the same capture written twice is the same record.
## * a feature whose id the survey already has **is not added again**. An append that turns one capture
##   into two plants is worse than one that refuses; this is what makes pressing the button twice safe.
## * a survey that is **there and cannot be read is refused rather than replaced**. Writing over a
##   survey whose records this build does not understand would lose them without saying so.
static func append(site_name: String, features: Array, path: String) -> Dictionary:
	var kept: Array = []
	var named: String = site_name
	if FileAccess.file_exists(path):
		var read: Dictionary = read_manifest(path)
		if not bool(read["ok"]):
			return {
				"ok": false, "reason": String(read["reason"]), "added": 0, "total": 0,
			}
		var data: Dictionary = read["data"]
		var existing: Variant = data.get("features", [])
		if existing is Array:
			kept = existing
		if named.strip_edges().is_empty():
			named = String(data.get("site_name", ""))
	var seen: Dictionary = {}
	for record: Variant in kept:
		if record is Dictionary:
			seen[identity_of(record)] = true
	var added: int = 0
	for feature: Variant in features:
		if not (feature is Dictionary):
			continue
		var entry: Dictionary = (feature as Dictionary).duplicate()
		var id: String = String(entry.get("instance_id", "")).strip_edges()
		if id.is_empty():
			id = _derived_id(entry)
			entry["instance_id"] = id
		if seen.has(id):
			continue
		seen[id] = true
		kept.append(entry)
		added += 1
	var error: Error = export_manifest(named, kept, path)
	if error != OK:
		return {
			"ok": false,
			"reason": "the survey could not be written (error %d)" % error,
			"added": 0,
			"total": kept.size() - added,
		}
	return {"ok": true, "reason": "", "added": added, "total": kept.size()}


## What a record is known by: the id it brought, or the one derived from what it is.
##
## Public because it is the answer to a question **two** places ask - the writer, to tell an append that
## would duplicate from one that would add, and `SurveyWatcher`, to tell a capture it has already planted
## from a new one - and two answers to it would be a survey that plants a tree twice or refuses one it
## has never seen.
static func identity_of(record: Dictionary) -> String:
	var given: String = String(record.get("instance_id", "")).strip_edges()
	return given if not given.is_empty() else _derived_id(record)


## A name for a record that brought none, made from what the record says rather than from a counter.
## Two captures of the same plant, in the same place, from the same photograph are one record; two
## photographs of the same species are two, because the photograph is part of what the record is.
static func _derived_id(feature: Dictionary) -> String:
	var parts := PackedStringArray([
		String(feature.get("species_id", "")),
		String(feature.get("raw_taxon", "")),
		String(feature.get("part", "")),
		String(feature.get("photo_path", "")),
		_position_text(feature.get("position", null)),
	])
	return "cap-%s" % "|".join(parts).sha256_text().substr(0, 16)


static func _position_text(raw: Variant) -> String:
	var point: Dictionary = _position_dict(raw)
	return "%.3f,%.3f,%.3f" % [float(point["x"]), float(point["y"]), float(point["z"])]


## Read a manifest back. Returns {"ok": bool, "reason": String, "data": Dictionary}.
static func read_manifest(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "reason": "there is no file at %s" % path, "data": {}}
	var text: String = file.get_as_text()
	file.close()
	var reader := JSON.new()
	if reader.parse(text) != OK:
		return {"ok": false, "reason": "not readable JSON: %s" % reader.get_error_message(), "data": {}}
	# A manifest from a newer field tool is refused by name rather than read on. This program would
	# recognise most of it and quietly ignore what it does not know, and a survey missing records looks
	# exactly like a survey with fewer plants in it.
	var version: int = 0
	if reader.data is Dictionary:
		version = int((reader.data as Dictionary).get("format_version", 0))
	if version > FORMAT_VERSION:
		return {
			"ok": false,
			"reason": (
				"this manifest is format %d and this build writes %d, so it came from a newer field tool"
				% [version, FORMAT_VERSION]
			),
			"data": {},
		}
	return {"ok": true, "reason": "", "data": reader.data}
