class_name PlantIdentifier
extends RefCounted
## What this program knows about naming a plant from a photograph: nothing yet, and it says so.
##
## This is the **contract** a classifier has to satisfy and the shape of the answer it must give, written
## down before there is anything to satisfy it. A photograph is read by a model running somewhere this
## program does not control - a phone, a service, a future GDExtension - and what that model hands back
## is one of these:
##
##     {"raw_taxon": String, "confidence": float, "model_id": String, "model_version": String}
##
## `raw_taxon` is the **name the model offered**, kept as a string rather than as a species: whether this
## program's plant list knows that name is `FieldCapture`'s decision, and a model that named a plant is
## not a model that is allowed to put one on a plan. `confidence` is the model's own, and it is measured
## against `PlantIDResolver`'s floors like every other name in this program.
##
## ## Why the refusal is a sentence rather than an absence
##
## There is no inference engine in this project: no model, no weights, no dependency that could run one.
## A program that simply lacked the feature would leave somebody pressing a button that does nothing.
## `NOTHING_INSTALLED` is what a page shows where such a button would be, and it names both what is
## missing and what to do until it exists.
##
## A photograph is worth keeping without any of this: `FieldPhotoStore` keeps it beside the drawing's
## records and a person names the plant themselves, which is what the capture page is for.

const FieldCaptureScript := preload("res://scripts/field_capture.gd")

## What a page says where a model would be, if there were a model.
const NOTHING_INSTALLED := (
	"A photograph is kept, not read: this program has no identification model installed, so the name "
	+ "is yours to type. Everything the photograph needs to go with it is still recorded."
)


## Whether a model is installed. False here, and honest about it: a caller asks this rather than assuming
## it, which is the whole reason the question has an answer instead of being absent.
static func installed() -> bool:
	return false


## Which model and which version, for a record to say what looked at the picture. Empty while there is no
## model, which is a fact rather than a blank.
static func model_id() -> String:
	return ""


static func model_version() -> String:
	return ""


## What a page should say about reading a photograph. One sentence, written once, so no page has to
## decide for itself how to word the absence of a feature - and so the day a model arrives is one line
## in one file rather than an audit of every page.
static func photo_hint() -> String:
	if not installed():
		return NOTHING_INSTALLED
	return "A photograph can be read by %s %s." % [model_id(), model_version()]


## No model can look at a picture, and this says so by name rather than answering with an empty result a
## caller could read as "the picture shows nothing".
func identify(_image: Image) -> Dictionary:
	return {
		"ok": false,
		"reason": NOTHING_INSTALLED,
		"raw_taxon": "",
		"confidence": 0.0,
		"model_id": "",
		"model_version": "",
	}


## A capture from a classifier's answer - **the one path there is** from a model naming a plant to a
## record on this side. The name goes through `FieldCapture.identify`, so a weak reading is refused by
## the same floors every other name is refused by, and an answer that names nothing is refused by name
## rather than becoming a capture about nothing.
##
## Which model answered travels with the record, so a person reading it later can weigh the answer
## instead of trusting it because it appeared on a screen.
static func capture_from(
	identification: Dictionary,
	catalogue: PlantCatalogue = null,
	position: Vector3 = Vector3.ZERO,
	photo_path: String = "",
	note: String = "",
	part: StringName = FieldCaptureScript.PART_WHOLE
) -> Dictionary:
	var offered: String = String(identification.get("raw_taxon", "")).strip_edges()
	if offered.is_empty():
		return {
			"ok": false,
			"reason": "the identification named no plant, so there is nothing to look up",
			"capture": FieldCaptureScript.unidentified(position, photo_path, note, part),
		}
	var answer: Dictionary = FieldCaptureScript.identify(
		offered,
		float(identification.get("confidence", 0.0)),
		catalogue,
		position,
		photo_path,
		note,
		part
	)
	var capture: Dictionary = answer["capture"]
	capture["model_id"] = String(identification.get("model_id", ""))
	capture["model_version"] = String(identification.get("model_version", ""))
	return {
		"ok": bool(answer["ok"]),
		"reason": String(answer["reason"]),
		"capture": capture,
	}