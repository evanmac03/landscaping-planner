extends Node
## The survey manifest (`res://scripts/io/field_manifest_exporter.gd`): what a phone writes and the
## desktop reads.
##
## The rules held here are the ones the other side of this file depends on, and it is the other side
## that makes them matter: a separate program reads whatever is in the file, so a write that cannot
## leave a half manifest where the real one was, and a record that carries the photograph it came
## from, are the difference between a survey and a list of names.

const ExporterScript := preload("res://scripts/io/field_manifest_exporter.gd")

const SCRATCH := "user://test_field_manifest.json"
const NESTED := "user://test_field_manifest_folder/survey/manifest.json"


func _clean() -> void:
	for path: String in [
		SCRATCH,
		SCRATCH + ExporterScript.TEMP_SUFFIX,
		NESTED,
		NESTED + ExporterScript.TEMP_SUFFIX,
	]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _feature(overrides: Dictionary = {}) -> Dictionary:
	var feature: Dictionary = {
		"instance_id": "cap-001",
		"species_id": "thymus-serpyllum",
		"confidence": 0.91,
		"position": Vector3(1.5, 0.0, -2.25),
		"sun_mask": 1,
		"drainage_mask": 7,
		"notes": "by the gate",
		"photo_path": "user://field_photos/ab12cd.png",
	}
	feature.merge(overrides, true)
	return feature


func test_a_manifest_written_to_a_folder_that_does_not_exist_yet_is_still_written() -> void:
	_clean()
	var error: Error = ExporterScript.export_manifest("Elm Street", [_feature()], NESTED)
	assert(error == OK, "the folder is made rather than the write being refused")
	var read: Dictionary = ExporterScript.read_manifest(NESTED)
	assert(bool(read["ok"]), "and what was written is readable: %s" % String(read["reason"]))
	assert(String(read["data"]["site_name"]) == "Elm Street", "under the site it was written for")
	_clean()


func test_the_temporary_file_is_gone_once_the_manifest_is_written() -> void:
	_clean()
	ExporterScript.export_manifest("Elm Street", [_feature()], SCRATCH)
	assert(FileAccess.file_exists(SCRATCH), "the manifest is there")
	assert(
		not FileAccess.file_exists(SCRATCH + ExporterScript.TEMP_SUFFIX),
		"and no half-written manifest is left lying beside it"
	)
	_clean()


func test_a_field_record_carries_the_photo_it_was_taken_from() -> void:
	# A manifest without the photograph is a list of names somebody typed. The path is the field side's
	# own, passed through unchanged: this file is a format and does not decide where a picture lives.
	_clean()
	ExporterScript.export_manifest("Elm Street", [_feature()], SCRATCH)
	var read: Dictionary = ExporterScript.read_manifest(SCRATCH)
	var features: Array = read["data"]["features"]
	assert(features.size() == 1, "one record")
	assert(
		String(features[0]["photo_path"]) == "user://field_photos/ab12cd.png",
		"and it names the photograph: %s" % str(features[0].get("photo_path", "<absent>"))
	)
	_clean()


func test_a_manifest_survives_the_file_and_comes_back_the_way_it_went_in() -> void:
	_clean()
	ExporterScript.export_manifest("Elm Street", [_feature()], SCRATCH)
	var read: Dictionary = ExporterScript.read_manifest(SCRATCH)
	var record: Dictionary = read["data"]["features"][0]
	assert(String(record["species_id"]) == "thymus-serpyllum", "the species it was identified as")
	assert(String(record["notes"]) == "by the gate", "the note somebody made")
	assert(int(record["sun_mask"]) == 1, "the sun it was recorded in")
	assert(int(record["drainage_mask"]) == 7, "and the drainage")
	# Every number comes back as a float, because that is what a JSON round trip does, so this asks
	# whether the value survived rather than whether it typed as it went out.
	assert(is_equal_approx(float(record["confidence"]), 0.91), "the confidence it was read at")
	var position: Dictionary = record["position"]
	assert(is_equal_approx(float(position["x"]), 1.5), "and where it stands, in metres")
	assert(is_equal_approx(float(position["z"]), -2.25), "in every direction")
	_clean()


func test_a_feature_nobody_could_identify_is_written_and_kept_rather_than_dropped() -> void:
	# An unidentified capture is a real record: somebody stood in front of a plant and could not say
	# what it was. The format keeps it with no species id; deciding what to do with it is the desk's
	# problem, and a format that silently dropped it would lose the one thing the person knew - where
	# it was.
	_clean()
	ExporterScript.export_manifest("Elm Street", [_feature({
		"species_id": "",
		"confidence": 0.0,
		"notes": "did not recognise it",
	})], SCRATCH)
	var read: Dictionary = ExporterScript.read_manifest(SCRATCH)
	var record: Dictionary = read["data"]["features"][0]
	assert(String(record["species_id"]).is_empty(), "it is written with no species named")
	assert(is_equal_approx(float(record["position"]["x"]), 1.5), "and keeps where it was seen")
	_clean()


func test_there_is_one_way_to_write_a_manifest() -> void:
	# A second writer that skipped the temporary file was removed rather than left beside this one: two
	# doors where one of them is unsafe is a door somebody will use.
	var exporter: RefCounted = ExporterScript.new()
	assert(
		not exporter.has_method("save_to_file"),
		"the only way a manifest reaches the disk is the writer that renames it into place"
	)


func test_the_classifiers_own_words_and_the_part_photographed_travel_with_the_record() -> void:
	# The name that was offered is the evidence a person corrects a record from, and the part of the
	# plant that was photographed is what makes a second attempt at the same plant a fair comparison
	# rather than a different question.
	_clean()
	ExporterScript.export_manifest("Elm Street", [_feature({
		"species_id": "",
		"raw_taxon": "something ferny",
		"part": "leaf",
		"photo_path": "user://field_photos/ab12cd.png",
	})], SCRATCH)
	var read: Dictionary = ExporterScript.read_manifest(SCRATCH)
	var record: Dictionary = read["data"]["features"][0]
	assert(String(record["raw_taxon"]) == "something ferny", "the name that was offered")
	assert(String(record["part"]) == "leaf", "and the part it was a picture of")
	assert(
		int(read["data"]["format_version"]) == ExporterScript.FORMAT_VERSION,
		"written at the version this build writes"
	)
	_clean()


func test_a_manifest_from_a_newer_field_tool_is_refused_by_name() -> void:
	# Reading it on would mean recognising most of it and quietly ignoring the rest, and a survey
	# missing records is indistinguishable from a survey with fewer plants in it.
	_clean()
	var file := FileAccess.open(SCRATCH, FileAccess.WRITE)
	assert(file != null, "the scratch file opens")
	file.store_string(JSON.stringify({
		"format_version": ExporterScript.FORMAT_VERSION + 3,
		"site_name": "Elm Street",
		"features": [],
	}, "  "))
	file.close()
	var read: Dictionary = ExporterScript.read_manifest(SCRATCH)
	assert(not bool(read["ok"]), "it is refused")
	assert(
		String(read["reason"]).contains(str(ExporterScript.FORMAT_VERSION + 3)),
		"naming the version it found: %s" % String(read["reason"])
	)
	_clean()


func test_appending_a_capture_keeps_what_the_survey_already_held() -> void:
	_clean()
	ExporterScript.export_manifest("Elm Street", [_feature()], SCRATCH)
	var result: Dictionary = ExporterScript.append("Elm Street", [_feature({
		"instance_id": "cap-002",
		"species_id": "rudbeckia-fulgida-goldsturm",
		"position": Vector3(4.0, 0.0, 0.0),
	})], SCRATCH)
	assert(bool(result["ok"]), "it appends: %s" % String(result["reason"]))
	assert(int(result["added"]) == 1, "one record went in")
	assert(int(result["total"]) == 2, "and the survey holds both")
	var read: Dictionary = ExporterScript.read_manifest(SCRATCH)
	var ids: Array = []
	for record: Variant in read["data"]["features"]:
		ids.append(String((record as Dictionary)["instance_id"]))
	assert(ids.has("cap-001"), "the record that was there is still there: %s" % str(ids))
	assert(ids.has("cap-002"), "and the new one is beside it")
	_clean()


func test_appending_the_same_capture_twice_is_one_record() -> void:
	_clean()
	var capture: Dictionary = _feature({
		"instance_id": "", "photo_path": "user://field_photos/ab12cd.png",
	})
	var first: Dictionary = ExporterScript.append("Elm Street", [capture], SCRATCH)
	var again: Dictionary = ExporterScript.append("Elm Street", [capture], SCRATCH)
	assert(int(first["added"]) == 1, "the first append records it")
	assert(int(again["added"]) == 0, "the second adds nothing")
	assert(int(again["total"]) == 1, "because it is the same record, not a second plant")
	_clean()


func test_a_capture_that_brings_no_id_is_given_one_the_watcher_can_keep_it_by() -> void:
	# `SurveyWatcher` skips a feature with no instance id, so a record written without one would reach
	# the file and never reach the plan - which is the quietest way there is to lose a capture.
	_clean()
	ExporterScript.append("Elm Street", [_feature({"instance_id": ""})], SCRATCH)
	var read: Dictionary = ExporterScript.read_manifest(SCRATCH)
	var record: Dictionary = read["data"]["features"][0]
	assert(
		not String(record["instance_id"]).strip_edges().is_empty(),
		"it was given a name of its own: %s" % str(record.get("instance_id", "<absent>"))
	)
	_clean()


func test_a_survey_that_cannot_be_read_is_refused_rather_than_replaced() -> void:
	# Appending to a file this build cannot read would replace somebody's whole survey with one record.
	_clean()
	var file := FileAccess.open(SCRATCH, FileAccess.WRITE)
	assert(file != null, "the scratch file opens")
	file.store_string("{ this is not a manifest")
	file.close()
	var result: Dictionary = ExporterScript.append("Elm Street", [_feature()], SCRATCH)
	assert(not bool(result["ok"]), "the append is refused")
	var kept := FileAccess.open(SCRATCH, FileAccess.READ)
	var words: String = kept.get_as_text()
	kept.close()
	assert(words == "{ this is not a manifest", "and the file is exactly as it was: %s" % words)
	_clean()


func test_a_manifest_written_at_an_older_version_still_reads() -> void:
	# There is nothing to upcast: a version 1 record simply does not carry the two keys version 2
	# added, and "nobody said" is already the meaning of an absent one.
	_clean()
	var file := FileAccess.open(SCRATCH, FileAccess.WRITE)
	assert(file != null, "the scratch file opens")
	file.store_string(JSON.stringify({
		"format_version": 1,
		"site_name": "Elm Street",
		"features": [{"species_id": "thymus-serpyllum", "confidence": 0.9,
				"position": {"x": 1.0, "y": 0.0, "z": 0.0}}],
	}, "  "))
	file.close()
	var read: Dictionary = ExporterScript.read_manifest(SCRATCH)
	assert(bool(read["ok"]), "an older manifest is read: %s" % String(read["reason"]))
	assert(
		String(read["data"]["features"][0]["species_id"]) == "thymus-serpyllum",
		"with its records intact"
	)
	_clean()