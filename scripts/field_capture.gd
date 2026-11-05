class_name FieldCapture
extends RefCounted
## One thing seen standing in the field: where it was, what it was identified as, how sure that
## identification was, and which photograph it came from.
##
## This is the **contract** between the thing that does the looking - a phone, a person at the
## keyboard, or a classifier on the far side of one - and this program. Everything that arrives from
## the field arrives as one of these, so the rules about what a half-answered capture means live in
## one class, and a capture is the same dictionary whether it was typed in a garden or handed over as
## JSON by a program that has never heard of Godot.
##
## The rules are refusals rather than guesses, and each one is here because the alternative puts
## something on a plan that nobody said was there:
##
## * an identification read below `PlantIDResolver`'s own floors **is not an identification**. The
##   capture is carried as unidentified, with the name that was offered kept as a string nobody has
##   agreed to; the person at the desk can then accept or correct it. `resolve_identification` is the
##   engine that decides this and this class does not re-decide it.
## * a capture **with no species is still a capture** - it keeps its position, its photograph and its
##   note, because that is what the person on site actually knows.
## * a **bit that is not one of the model's own bits** is refused, naming the mask. A mask of zero is
##   not an error: it is a question nobody answered.
##
## A capture is also exactly the shape `FieldManifestExporter` writes - `to_manifest` reads these
## keys - so a capture goes into a manifest with no conversion in between and there is no second
## description of a field record for the first to drift from. What it deliberately does **not** carry
## is an instance id: naming an instance is the job of whatever puts the plant on the plan.
##
## **Write a capture through `to_manifest`, never by calling `JSON.stringify` on it yourself.** The
## position is a real `Vector3` while it is being passed around inside the program, and a bare
## `Vector3` does not survive JSON - it comes back as a string and the plant's place in the world is
## lost without an error. `FieldManifestExporter._position_dict` is the one place that turns a
## `Vector3` into the `{x, y, z}` a JSON file can hold, which is why the writer is the way in.

## What part of the plant a photograph was of. A classifier told which part it is looking at is being
## asked a much easier question, and a person reading a record wants to know whether they are looking
## at a leaf or a trunk.
const PART_WHOLE := &"whole"
const PART_LEAF := &"leaf"
const PART_FLOWER := &"flower"
const PART_FRUIT := &"fruit"
const PART_BARK := &"bark"
const PART_NAMES := {
	PART_WHOLE: "the whole plant",
	PART_LEAF: "a leaf",
	PART_FLOWER: "a flower",
	PART_FRUIT: "fruit",
	PART_BARK: "bark",
}

## Where a size came from, as the two words a record and a planted node both use. Kept here because
## this is the class that decides which of them applies; `PlantPlacement` records whichever it is told.
const SIZE_STATED := "stated"
const SIZE_CATALOGUE := "catalogue"

## Every bit a `sun_mask` may hold, and every bit a `drainage_mask` may hold. The vocabulary is
## `PlantSpecies`' own, aliased rather than restated: a capture must not be able to describe a light
## level the model has no bit for.
const SUN_BITS := PlantSpecies.FULL_SUN | PlantSpecies.PART_SHADE | PlantSpecies.FULL_SHADE
const DRAINAGE_BITS := PlantSpecies.DRAINS_FAST | PlantSpecies.DRAINS_MEDIUM | PlantSpecies.DRAINS_SLOW


## A capture nobody has identified: somebody stood in front of a plant, recorded where it was and
## photographed it, and could not say what it is. This is a record rather than a failure - it is the
## one thing they knew.
static func unidentified(
	position: Vector3, photo_path: String = "", note: String = "", part: StringName = PART_WHOLE
) -> Dictionary:
	return {
		"species_id": "",
		"confidence": 0.0,
		"position": position,
		"sun_mask": 0,
		"drainage_mask": 0,
		"notes": note,
		"photo_path": photo_path,
		"raw_taxon": "",
		"part": part,
		# What somebody measured, in metres, with zero meaning nobody measured it - the same "a question
		# nobody answered" rule the masks keep. Never filled in from the catalogue: a plant is the size
		# the list says until a person measures the one in front of them.
		"measured_height_m": 0.0,
		"measured_spread_m": 0.0,
	}


## A capture from a name and the confidence it was read at: the door a classifier's answer comes
## through.
##
## `ok` is false when the name could not be placed, and the capture comes back with it either way -
## a name this program cannot place is not a reason to throw away where the plant was and the
## photograph of it. The caller decides what to do with an unidentified capture; it does not have to
## invent one.
##
##     FieldCapture.identify("Thymus serpyllum", 0.92, catalogue, spot, "user://field_photos/ab.png")
static func identify(
	raw_taxon: String,
	confidence: float,
	catalogue: PlantCatalogue = null,
	position: Vector3 = Vector3.ZERO,
	photo_path: String = "",
	note: String = "",
	part: StringName = PART_WHOLE
) -> Dictionary:
	var offered: String = raw_taxon.strip_edges()
	var capture: Dictionary = unidentified(position, photo_path, note, part)
	capture["raw_taxon"] = offered
	capture["confidence"] = confidence
	if offered.is_empty():
		return _refuse("nothing was offered as a name, so there is nothing to look up", capture)
	if catalogue == null:
		return _refuse("there is no plant list to look '%s' up in" % offered, capture)
	# The resolver's arithmetic, not a second copy of it: what counts as an identification is one
	# decision in this project and it is made in `PlantIDResolver`.
	var answer: Dictionary = PlantIDResolver.new(catalogue).resolve_identification(offered, confidence)
	var species: PlantSpecies = answer["species"] as PlantSpecies
	if species == null:
		return _refuse(
			(
				"nothing in the list is close enough to '%s' at %d%% confidence to file it as a species"
				% [offered, roundi(confidence * 100.0)]
			),
			capture
		)
	capture["species_id"] = String(species.id)
	return {"ok": true, "reason": "", "capture": capture}


## Whether a capture names a species. The one question the rest of the program asks of a capture, so
## it is asked here rather than by every caller comparing a string to an empty one.
static func identified(capture: Dictionary) -> bool:
	return not String(capture.get("species_id", "")).is_empty()


## Read a capture back out of a manifest record - which is what a phone hands over, and what a JSON
## round trip makes of anything this class built. Numbers arrive as floats and the position arrives as
## an object, so this is the one place that knows both shapes. `ok` is false when the record cannot be
## one of these at all, and the reason names the part of it that cannot.
static func from_record(feature: Dictionary) -> Dictionary:
	var capture: Dictionary = {
		"species_id": String(feature.get("species_id", "")),
		"confidence": _number(feature.get("confidence", 0.0)),
		"position": _point(feature.get("position", null)),
		"sun_mask": _bits(feature.get("sun_mask", 0)),
		"drainage_mask": _bits(feature.get("drainage_mask", 0)),
		"notes": String(feature.get("notes", "")),
		"photo_path": String(feature.get("photo_path", "")),
		"raw_taxon": String(feature.get("raw_taxon", "")),
		"part": StringName(String(feature.get("part", String(PART_WHOLE)))),
		"model_id": String(feature.get("model_id", "")),
		"model_version": String(feature.get("model_version", "")),
		"measured_height_m": _number(feature.get("measured_height_m", 0.0)),
		"measured_spread_m": _number(feature.get("measured_spread_m", 0.0)),
	}
	if not feature.has("position"):
		# A zero would be believed as a real place, and the plant would be planted at the origin of a
		# drawing it has nothing to do with. A record that does not say where cannot go on the plan.
		return _refuse(
			"this record does not say where the plant is, so putting it on the plan would be a guess",
			capture
		)
	var checked: Dictionary = validate(capture)
	return {
		"ok": bool(checked["ok"]),
		"reason": String(checked["reason"]),
		"capture": capture,
	}


## Whether this can be a capture at all, and if not, which part of it cannot. The same rules on the
## way in from a page and on the way out of a file: a record that arrived damaged is not a different
## kind of thing from one somebody typed wrong.
static func validate(capture: Dictionary) -> Dictionary:
	var point: Vector3 = _point(capture.get("position", null))
	if not (is_finite(point.x) and is_finite(point.y) and is_finite(point.z)):
		return {"ok": false, "reason": "a capture whose position is not a number cannot go on a plan"}
	var confidence: float = _number(capture.get("confidence", 0.0))
	if confidence < 0.0 or confidence > 1.0:
		return {
			"ok": false,
			"reason": "a confidence of %d%% is not a confidence: it runs from 0 to 100"
					% roundi(confidence * 100.0),
		}
	var sun: int = _bits(capture.get("sun_mask", 0))
	if (sun & ~SUN_BITS) != 0:
		return {
			"ok": false,
			"reason": "a sun mask of %d holds a bit that is not a light level, which are %d, %d and %d"
					% [sun, PlantSpecies.FULL_SUN, PlantSpecies.PART_SHADE, PlantSpecies.FULL_SHADE],
		}
	var drainage: int = _bits(capture.get("drainage_mask", 0))
	if (drainage & ~DRAINAGE_BITS) != 0:
		return {
			"ok": false,
			"reason": (
				"a drainage mask of %d holds a bit that is not a drainage, which are %d, %d and %d"
				% [drainage, PlantSpecies.DRAINS_FAST, PlantSpecies.DRAINS_MEDIUM, PlantSpecies.DRAINS_SLOW]
			),
		}
	var part: StringName = StringName(String(capture.get("part", String(PART_WHOLE))))
	if not PART_NAMES.has(part):
		return {
			"ok": false,
			"reason": "'%s' is not a part of a plant this program knows, which are %s"
					% [part, ", ".join(PackedStringArray(PART_NAMES.values()))],
		}
	return {"ok": true, "reason": ""}


## One line saying what a capture is, for a page or a status line. The plant is named the way a person
## says it - common name first, with the botanical name after it - and a capture nobody could place
## shows the name that was offered, because that is the part a person can act on.
static func words(capture: Dictionary, catalogue: PlantCatalogue = null) -> String:
	var where: String = _place_words(_point(capture.get("position", null)))
	var read_at: int = roundi(_number(capture.get("confidence", 0.0)) * 100.0)
	if not identified(capture):
		var offered: String = String(capture.get("raw_taxon", "")).strip_edges()
		if offered.is_empty():
			return "not identified%s" % where
		return "not identified - the name offered was \"%s\"%s" % [offered, where]
	var named: String = String(capture.get("species_id", ""))
	if catalogue != null:
		var species: PlantSpecies = catalogue.get_species(StringName(named))
		if species != null:
			named = species.botanical_name if species.common_name.is_empty() else (
				"%s (%s)" % [species.common_name, species.botanical_name]
			)
	return "%s at %d%% confidence%s" % [named, read_at, where]


## How big the plant in this capture is, and where that number came from: `{ok, reason, height_m,
## spread_m, source}`, with `source` one of `SIZE_STATED` or `SIZE_CATALOGUE`.
##
## A measurement somebody took wins over the catalogue's own mature size, and a question nobody answered
## is never answered with a zero: `ok` is false when nothing says how big the plant is, which is a
## different thing from a plant of no size. The catalogue's numbers come from the species it is handed,
## so this asks the list rather than keeping a second copy of it.
static func size_of(capture: Dictionary, species: PlantSpecies) -> Dictionary:
	var stated_height: float = _number(capture.get("measured_height_m", 0.0))
	var stated_spread: float = _number(capture.get("measured_spread_m", 0.0))
	var height: float = stated_height if stated_height > 0.0 else _species_height(species)
	var spread: float = stated_spread if stated_spread > 0.0 else _species_spread(species)
	if height <= 0.0 and spread <= 0.0:
		return {
			"ok": false,
			"reason": (
				"nothing says how big this plant is: nobody measured it and the list does not state it"
			),
			"height_m": 0.0,
			"spread_m": 0.0,
			"source": "",
		}
	return {
		"ok": true,
		"reason": "",
		"height_m": height,
		"spread_m": spread,
		"source": SIZE_STATED if (stated_height > 0.0 or stated_spread > 0.0) else SIZE_CATALOGUE,
	}


static func _species_height(species: PlantSpecies) -> float:
	return 0.0 if species == null else float(species.height_cm) / 100.0


static func _species_spread(species: PlantSpecies) -> float:
	return 0.0 if species == null else float(species.spread_cm) / 100.0


## A position as a person says it: the two numbers on the ground, in metres.
static func _place_words(point: Vector3) -> String:
	return " at %.1f, %.1f m" % [point.x, point.z]


static func _refuse(reason: String, capture: Dictionary = {}) -> Dictionary:
	return {"ok": false, "reason": reason, "capture": capture}


static func _point(raw: Variant) -> Vector3:
	if raw is Vector3:
		return raw
	if raw is Dictionary:
		var given: Dictionary = raw
		return Vector3(
			_number(given.get("x", 0.0)),
			_number(given.get("y", 0.0)),
			_number(given.get("z", 0.0)),
		)
	return Vector3.ZERO


static func _number(raw: Variant) -> float:
	if raw is float or raw is int:
		return float(raw)
	return 0.0


static func _bits(raw: Variant) -> int:
	if raw is float or raw is int:
		return int(raw)
	return 0