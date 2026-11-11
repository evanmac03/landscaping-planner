class_name SurveyWatcher
extends Node
## Watches the site manifest a phone survey writes and plants what arrives.
##
## The phone app writes `user://site_manifest.json` when a survey is finished. This node
## looks at that file's modification time on a slow clock - a 1.5 s `Timer`, **not** a
## per-frame hook, because a disk `stat` inside the render loop is micro-stutter and the
## file cannot change between one frame and the next - and, **only when the time has
## changed**, reads it and plants whatever feature is new. A file that has not changed
## costs one `stat` and nothing else: no parse, no nodes, no work. Regaining window focus
## looks at once, so a survey dropped while the app was in the background does not have to
## wait for the next tick.
##
## Two things it deliberately does not do. It does not arm the planting tool or change
## the view (`PlantPlacement.place` only adds a node under the yard's `Plants`), so a
## survey arriving mid-drawing neither moves the camera nor closes a dock. And it does
## not keep a catalogue of its own: it plants against `catalogue_source`'s list - the one
## the browser shows - so a capture lands in the "Field Survey Captures" collection a
## person can actually open.
##
## A feature already planted is remembered by its `instance_id`, so the same survey read
## twice does not plant the same tree twice.

const FieldManifestExporterScript := preload("res://scripts/io/field_manifest_exporter.gd")
const FieldCaptureScript := preload("res://scripts/field_capture.gd")
const PlantPlacementScript := preload("res://scripts/plant_placement.gd")
const PlantSuitabilityScript := preload("res://scripts/plant_suitability.gd")

## Where the phone writes. The same name `FieldManifestExporter` writes.
const DEFAULT_MANIFEST_PATH := "user://site_manifest.json"

## How often the file is looked at. A survey is not a live feed, so this is slow on
## purpose - a fifth of a second would be a `stat` sixty times a second for nothing.
const POLL_SECONDS := 1.5

@export var manifest_path: String = DEFAULT_MANIFEST_PATH
## The controller a capture is identified through, and whose yard the plants go into.
@export var controller: ViewController
## Where the plant list lives. The HUD owns the one catalogue the app uses.
@export var catalogue_source: PlannerHud

## The file's modification time as last acted on. Zero means "nothing seen yet".
var _last_modified: int = 0
## instance_id -> true, for every feature already dealt with.
var _imported_ids: Dictionary = {}

# Counters, so a test (or a person) can tell a poll that did work from one that did not.
var polls: int = 0
var reads: int = 0
var imports: int = 0
var placed_total: int = 0

## What the plan's own conditions made of the spots the **last** import put plants in - one row per
## plant, `{species, place, verdict, summary}`. Emptied at the start of every import, because this is a
## report on one arrival and not a running commentary, and `suitability_line` turns it into a sentence.
var imported_verdicts: Array[Dictionary] = []


func _ready() -> void:
	ensure_timer()


## Make the Timer this node watches on, once. A **Timer**, not a per-frame hook: a disk `stat`
## inside a render loop is a stutter waiting to happen, and the file does not change between
## frames. Public and idempotent so a test can build it off-tree (a node's `_ready` does not
## run there) and so a scene that already carries a `ManifestTimer` child does not get a second.
func ensure_timer() -> Timer:
	var existing: Node = get_node_or_null(^"ManifestTimer")
	if existing is Timer:
		return existing
	var timer := Timer.new()
	timer.name = "ManifestTimer"
	timer.wait_time = POLL_SECONDS
	timer.one_shot = false
	timer.autostart = true
	timer.timeout.connect(poll)
	add_child(timer)
	return timer


## A survey written while the window was in the background is picked up the moment the
## application is focused again, rather than waiting for the Timer's next tick.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN:
		poll()


## One look at the file. Returns how many plants went in - zero when nothing changed,
## which is the ordinary case and must stay cheap.
func poll() -> int:
	polls += 1
	var modified: int = FileAccess.get_modified_time(manifest_path)
	if modified == 0 or modified == _last_modified:
		return 0
	_last_modified = modified
	return import_manifest()


## Read the manifest and plant the features not seen before. Returns plants added.
##
## Public so a caller that already knows the file changed (a test, a manual "import now")
## can skip the modification-time check.
func import_manifest() -> int:
	var read: Dictionary = FieldManifestExporterScript.read_manifest(manifest_path)
	if not bool(read["ok"]):
		return 0
	reads += 1
	# The report is about **this** arrival, so it starts empty every time: a second import of the same
	# file plants nothing, and must not repeat the first one's sentence as though it had.
	imported_verdicts.clear()
	var data: Dictionary = read["data"]
	var features: Variant = data.get("features", [])
	if not (features is Array):
		return 0

	var yard: Node3D = controller.yard if controller != null else null
	var catalogue: PlantCatalogue = _catalogue()
	if catalogue == null or controller == null or yard == null:
		return 0
	# Identified against the same catalogue the browser lists, so the capture is filed in
	# the collection a person can open rather than in a second, invisible catalogue.
	controller.plant_catalogue = catalogue

	var added: int = 0
	for feature: Variant in features:
		if not (feature is Dictionary):
			continue
		var entry: Dictionary = feature
		# What a feature is known by comes from `FieldManifestExporter`, which is also what decides
		# whether an append would be a duplicate: one answer, asked by the writer and the reader both. A
		# survey written without instance ids - a field tool that did not bother to make any - still
		# imports, and the same capture read twice is still one plant.
		var key: String = FieldManifestExporterScript.identity_of(entry)
		if _imported_ids.has(key):
			continue
		var species: PlantSpecies = controller.process_field_identification(_name_of(entry))
		if species == null:
			# A name the catalogue does not know is left alone - and **not** remembered,
			# so a survey read before the plant list was imported can still be planted once
			# the list arrives.
			continue
		_imported_ids[key] = true
		var placed: Dictionary = PlantPlacementScript.place(
			catalogue, species.id, yard, _position_of(entry), _size_of(entry)
		)
		if bool(placed["ok"]):
			added += 1
			# Judged **after** it is in the ground. A survey records what is on site, so the import is not
			# the place to refuse a plant - the software's job is to inform the designer, not to overrule
			# the person who was standing in the garden. What it does do is say what the plan's own
			# conditions make of the spot the plant landed in, asked of the controller through the same
			# door the ring uses, so an import and a cursor cannot disagree about the same square metre.
			var judged: Dictionary = _verdict_of(controller, species, _position_of(entry))
			if not judged.is_empty():
				imported_verdicts.append(judged)
	imports += 1
	placed_total += added
	# One sentence, once, into the same status line the planting tools write. The plants are already in
	# the ground by now, so this is a report and not a decision.
	controller.say_survey(suitability_line())
	return added


## Forget the file and everything imported from it, as though the program had just started.
func reset() -> void:
	_last_modified = 0
	_imported_ids.clear()
	imported_verdicts.clear()


## What the last import's plants landed in, in one sentence for whoever reports the arrival.
##
## Three counts and one name, because "3 of 4" without a name is a number nobody can act on: what suits
## the spot, what is in the wrong place - carrying the first one's own sentence - and what the plan cannot
## say. **Nothing stated is not the same as nothing wrong**: a survey arriving into a drawing nobody has
## described reports that it cannot tell, which is what prompts somebody to describe it.
func suitability_line() -> String:
	if imported_verdicts.is_empty():
		return ""
	var suits: int = 0
	var wrong: int = 0
	var unknown: int = 0
	var first_wrong: String = ""
	for row: Dictionary in imported_verdicts:
		match int(row.get("verdict", PlantSuitabilityScript.UNKNOWN)):
			PlantSuitabilityScript.GOOD, PlantSuitabilityScript.TOLERATED:
				suits += 1
			PlantSuitabilityScript.UNSUITABLE:
				wrong += 1
				if first_wrong.is_empty():
					first_wrong = String(row.get("summary", ""))
			_:
				unknown += 1
	var total: int = imported_verdicts.size()
	var parts: Array[String] = []
	if suits > 0:
		parts.append("1 suits the spot" if suits == 1 else "%d suit the spot" % suits)
	if wrong > 0:
		parts.append("1 is in the wrong place" if wrong == 1 else "%d are in the wrong place" % wrong)
	if unknown > 0:
		parts.append(
			"nothing says how the ground is" if unknown == 1
			else "nothing says how the ground is at %d of them" % unknown
		)
	var said: String = "1 capture placed" if total == 1 else "%d captures placed" % total
	if not parts.is_empty():
		said += ": " + ", ".join(parts)
	said += "."
	if not first_wrong.is_empty():
		said += " " + first_wrong
	return said


## One capture's verdict, in the shape this node reports - or nothing when nobody can be asked.
func _verdict_of(controller_node: ViewController, species: PlantSpecies, at: Vector3) -> Dictionary:
	if controller_node == null or species == null:
		return {}
	# The plan is (x, z): the yard is a `Vector3` and the drawing is a `Vector2`, and a survey record
	# carries the first. This is the one place the survey side has to remember which is which.
	var verdict: Dictionary = controller_node.spot_verdict(species, Vector2(at.x, at.z))
	if verdict.is_empty():
		return {}
	return {
		"species": String(verdict.get("species", "")),
		"place": String(verdict.get("place", "")),
		"verdict": int(verdict.get("verdict", PlantSuitabilityScript.UNKNOWN)),
		"summary": String(verdict.get("summary", "")),
	}


# --- internals -------------------------------------------------------------------------


func _catalogue() -> PlantCatalogue:
	if catalogue_source != null:
		return catalogue_source.plant_list()
	if controller != null:
		return controller.plant_catalogue
	return null


## The name a feature is identified by: its species id when the survey knew one, and its
## botanical name otherwise.
func _name_of(entry: Dictionary) -> String:
	var id: String = String(entry.get("species_id", "")).strip_edges()
	if not id.is_empty():
		return id
	return String(entry.get("botanical_name", "")).strip_edges()


## The size the record states, in the shape `PlantPlacement.place` takes - or nothing at all, in which
## case the plant is planted at the size the catalogue says. A survey is a list of numbers somebody wrote
## down: either they measured the plant or they did not, and a zero means they did not.
##
## The conversion from metres to centimetres happens here and nowhere else: a record is in metres because
## the model is, and a node's own metas are in whole centimetres because `PlantSpecies` keeps its mature
## sizes that way.
func _size_of(entry: Dictionary) -> Dictionary:
	var spread_cm: int = roundi(float(entry.get("measured_spread_m", 0.0)) * 100.0)
	var height_cm: int = roundi(float(entry.get("measured_height_m", 0.0)) * 100.0)
	if spread_cm <= 0 and height_cm <= 0:
		return {}
	return {
		"spread_cm": spread_cm,
		"height_cm": height_cm,
		"source": FieldCaptureScript.SIZE_STATED,
	}


## A feature's ground position. `FieldManifestExporter` writes `{x, y, z}`, and y is the
## height the phone recorded - the ground plane is y = 0 there.
func _position_of(entry: Dictionary) -> Vector3:
	var raw: Variant = entry.get("position", null)
	if raw is Dictionary:
		var point: Dictionary = raw
		return Vector3(
			float(point.get("x", 0.0)), float(point.get("y", 0.0)), float(point.get("z", 0.0))
		)
	return Vector3.ZERO