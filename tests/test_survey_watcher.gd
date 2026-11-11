extends Node
## Tests for SurveyWatcher: picking up a phone survey and planting it.
##
## The watcher's whole reason to exist is that a survey arriving must plant plants and do
## nothing else - no camera move, no tool armed, no dock disturbed - and must be cheap when
## the file has not changed. These tests are about exactly those two promises: the cheap
## path (an unchanged file is not read) and the planting path (each new feature becomes a
## plant, once, against the catalogue the browser shows).
##
## Everything runs off a scene tree: a bare ViewController, a bare Node3D yard and a
## catalogue are enough, because `PlantPlacement.place` only needs a yard to add to. The
## nodes made here are freed again, so the runner does not end with resources in use.

const WatcherScript := preload("res://scripts/survey_watcher.gd")
const ExporterScript := preload("res://scripts/io/field_manifest_exporter.gd")
const PlacementScript := preload("res://scripts/plant_placement.gd")
const Suitability := preload("res://scripts/plant_suitability.gd")
const ZoneMapScript := preload("res://scripts/zone_map.gd")
const SpeciesScript := preload("res://scripts/plant_species.gd")
const DraftControllerScript := preload("res://scripts/draft/draft_controller.gd")
const DocumentScript := preload("res://scripts/draft/draft_document.gd")

## A manifest path of this test's own, so a real survey file is never touched.
const MANIFEST := "user://test_survey_watcher.json"


## A catalogue holding one plant, whose default form (a shrub prop) really is on disk.
func _catalogue() -> PlantCatalogue:
	var catalogue := PlantCatalogue.new()
	var species := PlantSpecies.new()
	species.id = &"quercus_alba"
	species.botanical_name = "Quercus alba"
	species.common_name = "White Oak"
	species.height_cm = 1500
	species.spread_cm = 1200
	catalogue.species[species.id] = species
	return catalogue


## A controller with a yard to plant into and the catalogue in hand.
func _rig() -> Array:
	var catalogue := _catalogue()
	var controller := ViewController.new()
	var yard := Node3D.new()
	controller.yard = yard
	controller.plant_catalogue = catalogue
	return [catalogue, controller, yard]


func _cleanup(watcher: Node, controller: Node, yard: Node) -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(MANIFEST))
	if watcher != null:
		watcher.free()
	if controller != null:
		controller.free()
	if yard != null:
		yard.free()


## A catalogue whose one plant states what it wants - the light and the water - so a spot in the drawing
## can disagree with it. Both sides have to state something for anything to be asked, which is why the
## plant states its own.
func _sun_loving_catalogue() -> PlantCatalogue:
	var catalogue := PlantCatalogue.new()
	var oak := PlantSpecies.new()
	oak.id = &"quercus_alba"
	oak.botanical_name = "Quercus alba"
	oak.common_name = "White Oak"
	oak.height_cm = 1500
	oak.spread_cm = 1200
	oak.sun = SpeciesScript.FULL_SUN
	oak.water = SpeciesScript.WATER_MEDIUM
	catalogue.species[oak.id] = oak
	return catalogue


## A controller whose drawing says what the ground is like. The drafting controller is added as a child
## as well as held in `_draft`, so `_cleanup` frees it with the controller: a node left standing is a
## failed run, and the runner says so.
func _rig_with_ground(conditions: Dictionary) -> Array:
	var catalogue := _sun_loving_catalogue()
	var controller := ViewController.new()
	var yard := Node3D.new()
	controller.yard = yard
	controller.plant_catalogue = catalogue
	var draft: DraftControllerScript = DraftControllerScript.new()
	var document: DraftDocument = DocumentScript.new()
	var stated: bool = document.set_environment(ZoneMapScript.make(conditions))
	assert(stated, "the test's own drawing states the ground")
	draft.document = document
	controller._draft = draft
	controller.add_child(draft)
	return [catalogue, controller, yard]


## A survey is a record of what is on site, not a request for permission: the capture is planted where it
## was found even where the drawing says the spot is wrong for it, and the import then says what it made
## of that spot. Refusing the plant would be the software overruling the person standing in the garden.
func test_a_capture_is_planted_even_where_the_ground_says_it_does_not_belong() -> void:
	var rig: Array = _rig_with_ground({
		"sun": SpeciesScript.FULL_SHADE, "moisture": SpeciesScript.WATER_MEDIUM,
	})
	var controller: ViewController = rig[1]
	var yard: Node3D = rig[2]
	ExporterScript.export_manifest("Yard", [{
		"species_id": "quercus_alba", "position": {"x": 1.0, "y": 0.0, "z": 1.0},
	}], MANIFEST)
	var watcher = WatcherScript.new()
	watcher.manifest_path = MANIFEST
	watcher.controller = controller

	assert(watcher.poll() == 1, "the plant goes into the ground anyway")
	assert(PlacementScript.planted(yard).size() == 1, "so one plant is standing")
	assert(watcher.imported_verdicts.size() == 1, "and the spot it landed in was judged")
	assert(
		int(watcher.imported_verdicts[0]["verdict"]) == Suitability.UNSUITABLE,
		"a full-sun oak in full shade is wrong, not merely tolerated"
	)
	var said: String = watcher.suitability_line()
	assert(said.contains("1 is in the wrong place"), "the report says so in words: %s" % said)
	assert(
		said.ends_with(String(watcher.imported_verdicts[0]["summary"])),
		"carrying the check's own sentence rather than a second one written here: %s" % said
	)
	_cleanup(watcher, controller, yard)


## The fourth verdict, and the one easiest to get wrong in a way nobody notices: a drawing that says
## nothing about the ground must produce "I cannot tell you", never a green. The report is what prompts
## somebody to describe the site.
func test_an_import_into_ground_nobody_has_described_says_it_cannot_tell() -> void:
	var rig: Array = _rig()
	var controller: ViewController = rig[1]
	var yard: Node3D = rig[2]
	ExporterScript.export_manifest("Yard", [{
		"species_id": "quercus_alba", "position": {"x": 1.0, "y": 0.0, "z": 1.0},
	}], MANIFEST)
	var watcher = WatcherScript.new()
	watcher.manifest_path = MANIFEST
	watcher.controller = controller

	assert(watcher.poll() == 1, "the plant still goes in")
	assert(
		int(watcher.imported_verdicts[0]["verdict"]) == Suitability.UNKNOWN,
		"and the answer is that nobody said, never green"
	)
	assert(
		watcher.suitability_line().contains("nothing says how the ground is"),
		"in a sentence a person can act on: %s" % watcher.suitability_line()
	)
	_cleanup(watcher, controller, yard)


## The report is about one arrival. The same file read a second time plants nothing, and the second
## import must not repeat the first one's sentence as though it had just happened.
func test_an_import_that_planted_nothing_says_nothing() -> void:
	var rig: Array = _rig()
	var controller: ViewController = rig[1]
	var yard: Node3D = rig[2]
	ExporterScript.export_manifest("Yard", [{
		"species_id": "quercus_alba", "position": {"x": 1.0, "y": 0.0, "z": 1.0},
	}], MANIFEST)
	var watcher = WatcherScript.new()
	watcher.manifest_path = MANIFEST
	watcher.controller = controller

	assert(watcher.poll() == 1, "the first read plants it")
	assert(watcher.suitability_line() != "", "and has something to report")
	assert(watcher.import_manifest() == 0, "reading the same file again plants nothing")
	assert(watcher.suitability_line() == "", "so there is nothing to report the second time")
	_cleanup(watcher, controller, yard)


## Nothing to read is nothing to do, and costs not even a read.
func test_no_manifest_is_no_work() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(MANIFEST))
	var watcher = WatcherScript.new()
	watcher.manifest_path = MANIFEST
	assert(watcher.poll() == 0, "no file plants nothing")
	assert(watcher.reads == 0, "and the file was not read")
	_cleanup(watcher, null, null)


## The cheap path: once seen, an unchanged file is not read again however often it is polled.
func test_an_unchanged_file_is_read_once() -> void:
	ExporterScript.export_manifest("Yard", [], MANIFEST)
	var watcher = WatcherScript.new()
	watcher.manifest_path = MANIFEST

	watcher.poll()  # the file is new, so it is read
	assert(watcher.reads == 1, "a new file is read once")
	watcher.poll()
	watcher.poll()
	assert(watcher.reads == 1, "and an unchanged file is never read again")
	assert(watcher.polls == 3, "though it is still looked at every poll")

	_cleanup(watcher, null, null)


## A feature in the survey becomes a plant in the yard, filed as a capture, with the view
## and the tool in hand left exactly as they were.
func test_a_capture_that_measured_its_plant_is_planted_at_that_size() -> void:
	# The record is the only place the measurement exists, which makes this where the two modules meet:
	# metres on paper because the model is metres, whole centimetres on the node because that is how
	# `PlantSpecies` keeps a mature size.
	var rig: Array = _rig()
	var controller: ViewController = rig[1]
	var yard: Node3D = rig[2]
	ExporterScript.export_manifest("Yard", [{
		"instance_id": "f-measured",
		"species_id": "quercus_alba",
		"position": {"x": 0.0, "y": 0.0, "z": 0.0},
		"measured_spread_m": 6.5,
	}], MANIFEST)
	var watcher = WatcherScript.new()
	watcher.manifest_path = MANIFEST
	watcher.controller = controller

	assert(watcher.poll() == 1, "the oak that was measured is planted")
	var planted: Array = PlacementScript.planted(yard)
	assert(planted.size() == 1, "one plant went in")
	assert(
		int(planted[0].get_meta(PlacementScript.SPREAD_META)) == 650,
		"at 6.5 m, the size the record states: %d"
				% int(planted[0].get_meta(PlacementScript.SPREAD_META))
	)
	assert(
		String(planted[0].get_meta(PlacementScript.SIZE_SOURCE_META)) == "stated",
		"and the node says the number was measured"
	)
	_cleanup(watcher, controller, yard)


func test_a_survey_that_brought_no_instance_ids_still_plants_once() -> void:
	# A field tool that did not bother to name its records is not a reason to refuse a whole survey, and
	# it is not a reason to plant everything in it twice either: what a record is known by is derived from
	# what the record is, so the same capture read again is the same capture.
	var rig: Array = _rig()
	var controller: ViewController = rig[1]
	var yard: Node3D = rig[2]
	ExporterScript.export_manifest("Yard", [
		{"species_id": "quercus_alba", "position": {"x": 1.0, "y": 0.0, "z": 1.0}},
		{"species_id": "quercus_alba", "position": {"x": 4.0, "y": 0.0, "z": 1.0}},
	], MANIFEST)
	var watcher = WatcherScript.new()
	watcher.manifest_path = MANIFEST
	watcher.controller = controller

	assert(watcher.poll() == 2, "both nameless records are planted")
	assert(watcher.import_manifest() == 0, "and reading the same file again plants nothing more")
	assert(PlacementScript.planted(yard).size() == 2, "so the yard holds two trees, not four")
	_cleanup(watcher, controller, yard)


func test_a_new_manifest_plants_its_features() -> void:
	var rig: Array = _rig()
	var catalogue: PlantCatalogue = rig[0]
	var controller: ViewController = rig[1]
	var yard: Node3D = rig[2]

	ExporterScript.export_manifest("Yard", [{
		"instance_id": "f1",
		"species_id": "quercus_alba",
		"position": {"x": 1.0, "y": 0.0, "z": 2.0},
	}], MANIFEST)

	var watcher = WatcherScript.new()
	watcher.manifest_path = MANIFEST
	watcher.controller = controller

	assert(watcher.poll() == 1, "the feature was planted")

	var plants: Node3D = PlantPlacement.plants_node(yard)
	assert(plants.get_child_count() == 1, "one plant stands in the yard")
	var planted: Node3D = plants.get_child(0)
	assert(String(planted.get_meta(&"species")) == "quercus_alba", "and it is the plant the survey named")
	assert(planted.position.is_equal_approx(Vector3(1.0, 0.0, 2.0)), "where the survey put it")

	# The capture is filed in the collection the browser shows, in the same catalogue.
	assert(catalogue.collections_of(&"quercus_alba").has("Field Survey Captures"),
		"and it is filed as a field capture")

	# Nothing about the view or the tool in hand was disturbed.
	assert(controller.mode == ViewController.ViewMode.OVERHEAD_3D, "the view was not changed")
	assert(controller.planting_species.is_empty(), "no plant was armed")
	assert(not controller.is_planting(), "and nothing is being planted by hand")

	_cleanup(watcher, controller, yard)


## The same feature read twice is planted once: a survey revision that did not change this
## entry must not double the tree.
func test_the_same_feature_is_not_planted_twice() -> void:
	var rig: Array = _rig()
	var controller: ViewController = rig[1]
	var yard: Node3D = rig[2]

	ExporterScript.export_manifest("Yard", [{
		"instance_id": "f1",
		"species_id": "quercus_alba",
		"position": {"x": 0.0, "y": 0.0, "z": 0.0},
	}], MANIFEST)

	var watcher = WatcherScript.new()
	watcher.manifest_path = MANIFEST
	watcher.controller = controller

	assert(watcher.poll() == 1, "the first read plants it")
	assert(watcher.import_manifest() == 0, "reading the same feature again plants nothing")
	assert(PlantPlacement.plants_node(yard).get_child_count() == 1, "so only one plant stands")

	_cleanup(watcher, controller, yard)


## A name the catalogue does not know is left alone rather than guessed at - and is not
## remembered as done, so the survey can be read again once the plant list arrives.
func test_a_name_the_catalogue_does_not_know_is_left_alone() -> void:
	var rig: Array = _rig()
	var controller: ViewController = rig[1]
	var yard: Node3D = rig[2]

	ExporterScript.export_manifest("Yard", [{
		"instance_id": "f1",
		"species_id": "no_such_plant",
		"position": {"x": 0.0, "y": 0.0, "z": 0.0},
	}], MANIFEST)

	var watcher = WatcherScript.new()
	watcher.manifest_path = MANIFEST
	watcher.controller = controller

	assert(watcher.poll() == 0, "an unknown name plants nothing")
	assert(PlantPlacement.plants_node(yard).get_child_count() == 0, "and nothing stands in the yard")
	assert(watcher.import_manifest() == 0, "and it is not treated as imported")

	_cleanup(watcher, controller, yard)


func test_the_watch_is_a_timer_and_not_a_per_frame_hook() -> void:
	# A disk stat inside the render loop is micro-stutter; the file cannot change between one
	# frame and the next. So the watch hangs off a Timer, and the node has no _process at all.
	var watcher: Node = WatcherScript.new()

	assert(not watcher.has_method("_process"), "the watcher does not run every frame")

	var timer: Timer = watcher.ensure_timer()
	assert(timer != null, "it watches on a Timer")
	assert(is_equal_approx(timer.wait_time, 1.5), "once every 1.5 s")
	assert(timer.autostart, "which starts itself")
	assert(not timer.one_shot, "and repeats")
	assert(watcher.ensure_timer() == timer, "and is made only once")

	watcher.free()


func test_regaining_focus_looks_at_the_file() -> void:
	# A survey written while the window was in the background should not have to wait for the
	# Timer's next tick to be noticed.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(MANIFEST))
	var watcher: Node = WatcherScript.new()
	watcher.manifest_path = MANIFEST

	watcher._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	assert(watcher.polls == 1, "focusing the application looks at the file")
	assert(watcher.reads == 0, "and a file that is not there costs no read")

	watcher.free()