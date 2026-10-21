class_name WashTable
extends RefCounted
## What colour each layer washes in, and how it behaves when it does (§4.2).
##
## Keyed by layer name, like `PlotStyleTable` is keyed by pen slot and `PlanStyle`
## by material resource. A layer missing from this table is a wash that does not
## happen, and `wash_for()` says so by returning an empty dictionary rather than
## guessing: a bed washed in the wrong colour is worse than a bed that is only
## inked.
##
## `colour` is the pigment, `opacity` how much paper it lets through, `bleed_mm`
## how far it runs past its own edge, `mottle` how much it wanders within the
## region, and `wet_edge` how dark it goes where it stops. All lengths are paper
## millimetres, like every other authored length in this project.
##
## **The keys are this project's real layer names**, not invented ones: a wash table
## keyed by a layer that does not exist is a table whose entries can never fire, and
## the point of keying by name is that a renamed layer turns up as a missing key
## rather than as a wrong colour (REQ-V13.1).
##
## `material` names the resource in `PlanStyle.COLOURS` that the pigment is taken
## from, and `test_vis_wash.gd` asserts the two agree. That is REQ-V4.1 made
## mechanical: the flat working view and the painted wash cannot drift, because a
## change to the palette that this table does not follow fails a test.

const LayerSetScript := preload("res://scripts/draft/layer_set.gd")
const PlanStyleScript := preload("res://scripts/plan_style.gd")

## A plant is washed by its own name rather than by a layer, because a plant is not
## on a layer: it is a prop that happens to sit on one. Naming it here keeps every
## wash behind one lookup, so `wash_for()` stays the only way in.
const PLANTING_PROPS := "planting_props"

## Materials written as they are spelled in `PlanStyle.COLOURS`, so a typo here is a
## missing key there and a failing test rather than a silently neutral colour.
const LAWN := "res://resources/materials/lawn.tres"
const STONE := "res://resources/materials/stone.tres"
const SOIL := "res://resources/materials/soil.tres"
const FOLIAGE := "res://resources/materials/foliage.tres"
const ROUGH_GRASS := "res://resources/materials/rough_grass.tres"
const STUCCO := "res://resources/materials/stucco.tres"
const FENCE_WOOD := "res://resources/materials/fence_wood.tres"

const WASHES := {
	# A hard surface barely bleeds and barely mottles: water sits on it. The numbers
	# are the spec's, and they are the reason paving reads as paving rather than as
	# wet pigment.
	LayerSetScript.NEW_HARDSCAPE: {
		"colour": Color(0.804, 0.792, 0.753), "material": STONE,
		"opacity": 0.34, "bleed_mm": 0.6, "mottle": 0.10, "wet_edge": 0.10,
		"what": "paving, walls, steps",
	},
	LayerSetScript.NEW_STRUCTURE: {
		"colour": Color(0.616, 0.502, 0.361), "material": FENCE_WOOD,
		"opacity": 0.40, "bleed_mm": 0.8, "mottle": 0.14, "wet_edge": 0.16,
		"what": "deck, pergola, structure",
	},
	# A bed is soil or mulch, so it mottles hard and bleeds little. There is no
	# separate mulch layer in the preset set - mulch *patterns* live on 600-HATCH,
	# and a pattern layer must not wash (REQ-V4.2) - so the bed layer carries the
	# medium's behaviour.
	LayerSetScript.NEW_BED: {
		"colour": Color(0.706, 0.596, 0.451), "material": SOIL,
		"opacity": 0.50, "bleed_mm": 1.2, "mottle": 0.45, "wet_edge": 0.22,
		"what": "bed soil and mulch",
	},
	LayerSetScript.NEW_PLANTING: {
		"colour": Color(0.42, 0.62, 0.329), "material": FOLIAGE,
		"opacity": 0.50, "bleed_mm": 2.0, "mottle": 0.38, "wet_edge": 0.30,
		"what": "planting masses",
	},
	LayerSetScript.NEW_TURF: {
		"colour": Color(0.655, 0.784, 0.451), "material": LAWN,
		"opacity": 0.42, "bleed_mm": 1.0, "mottle": 0.30, "wet_edge": 0.16,
		"what": "lawn and seeding",
	},
	# What is already there washes faintly. Not a taste call: the drawing's subject
	# is the *proposal*, and existing work that washes as strongly as new work makes
	# the proposal unreadable.
	LayerSetScript.EXISTING_HARDSCAPE: {
		"colour": Color(0.804, 0.792, 0.753), "material": STONE,
		"opacity": 0.20, "bleed_mm": 0.5, "mottle": 0.08, "wet_edge": 0.06,
		"what": "existing paving and walls",
	},
	LayerSetScript.EXISTING_STRUCTURE: {
		"colour": Color(0.929, 0.918, 0.878), "material": STUCCO,
		"opacity": 0.22, "bleed_mm": 0.4, "mottle": 0.05, "wet_edge": 0.05,
		"what": "existing buildings",
	},
	LayerSetScript.EXISTING_PLANTING: {
		"colour": Color(0.871, 0.863, 0.792), "material": ROUGH_GRASS,
		"opacity": 0.35, "bleed_mm": 1.6, "mottle": 0.35, "wet_edge": 0.24,
		"what": "existing plant material",
	},
	# A canopy bleeds further and mottles more than a bed: a mass of foliage is
	# uneven by nature, which is exactly what makes a planting plan read as foliage
	# over soil rather than as soil over foliage (REQ-V4.3).
	PLANTING_PROPS: {
		"colour": Color(0.42, 0.62, 0.329), "material": FOLIAGE,
		"opacity": 0.58, "bleed_mm": 2.2, "mottle": 0.42, "wet_edge": 0.38,
		"what": "plant canopies",
	},
}

## Layers that deliberately do not wash, with the reason. Not decoration: a reader
## asking "why does my irrigation layer have no colour" gets the answer here rather
## than from a missing table entry that looks like an oversight.
const NO_WASH := {
	LayerSetScript.SURVEY_PROPERTY: "A property line is a fact about the site, not ground that is coloured.",
	LayerSetScript.SURVEY_ANNOTATION: "An annotation.",
	LayerSetScript.SETBACK_EASEMENT: "A constraint, drawn as a line.",
	LayerSetScript.GRADING_CONTOUR: "A contour is a line; the ground it crosses is washed by the layer that owns the ground.",
	LayerSetScript.GRADING_SPOT: "An annotation.",
	LayerSetScript.GRADING_SLOPE: "A slope arrow is a line; the ground it falls across is washed by the layer that owns the ground.",
	LayerSetScript.IRRIGATION: "Below ground.",
	LayerSetScript.LIGHTING: "Above ground.",
	LayerSetScript.HATCH: "A pattern layer. A wash under a hatch would double-count the same ground.",
	LayerSetScript.DIMENSION: "An annotation (drafting spec §4).",
	LayerSetScript.TEXT: "An annotation.",
	LayerSetScript.CALLOUT: "An annotation.",
	LayerSetScript.SHEET_BORDER: "Sheet furniture.",
	LayerSetScript.SHEET_VIEWPORT: "Sheet furniture.",
	LayerSetScript.UNDERLAY: "A tracing aid, and it does not plot (REQ-V4.2).",
	LayerSetScript.GUIDES: "A tracing aid, and it does not plot (REQ-V4.2).",
}


## The wash for a layer, or {} when that layer does not wash.
##
## Takes a name in either form: a layer's name arrives as a `StringName` from the
## document and as a `String` from a literal, and a lookup that answered only one of
## them would be a table that works from one call site and not another.
static func wash_for(layer_name) -> Dictionary:
	return WASHES.get(StringName(layer_name), {})


## Whether a name washes at all, in either form.
static func washes(layer_name) -> bool:
	return WASHES.has(StringName(layer_name))


## Every layer that washes, in the order the project's layer bands run. Used by the
## tests and by anything that has to describe the wash set; the wash table's own
## order is not meaningful.
static func washable_layers() -> Array[StringName]:
	var out: Array[StringName] = []
	for entry: Dictionary in LayerSetScript.PRESETS:
		var name: StringName = entry["name"]
		if WASHES.has(name):
			out.append(name)
	return out


## Why a layer does not wash, or "" when it does.
static func reason_against(layer_name) -> String:
	return String(NO_WASH.get(StringName(layer_name), ""))