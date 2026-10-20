class_name SolidTable
extends RefCounted
## Which layer becomes which solid, and how thick (§8.6).
##
## **A height is not in the drawing.** A patio at 0.05 m and a raised bed at 0.45 m are
## the same rectangle in plan, so the height is a decision, not a measurement, and the
## decision is made here — keyed by the layer the drawer already chose, like every other
## table in this project (REQ-V8.6).
##
## Keyed by **this project's real layer names**, like `WashTable`, and for the same
## reason: a table keyed by a layer that does not exist is a table whose entries can
## never fire. The specification's version of this table keyed `LayerSet.WALLS`,
## `LayerSet.WATER`, `LayerSet.DECK` and `LayerSet.PLANTING_BED`; three of those four
## are not layers in this project at all, so two thirds of it could never have matched
## anything. `MISSING` records them, because a reader who came to this file looking for
## the water of §8.5 deserves to find out where it went.
##
## **`height_m` and `base_m` name the top and the bottom of the solid, not a thickness.**
## A negative base is normally right: paving sits *in* the ground rather than on it, and
## a 2 cm bedding course below the surface is why a patio edge reads as flush rather than
## as a floating slab.
##
## **The entity decides whether a solid is a surface or a centreline; this table only
## says how thick.** A closed outline becomes a slab and an open line becomes a ribbon
## of `width_m`. The specification gave each *layer* one shape, which cannot be right:
## paving is a patio where it is drawn as a rectangle and a kerb where it is drawn as a
## line, and one rectangle of paving extruded as a 0.6 m ribbon is a fence.

const LayerSetScript := preload("res://scripts/draft/layer_set.gd")

## Layers that do become solids.
##
## `material_set` names a set in `HardscapeMaterial.SETS`, `width_m` is the width an
## open linework solid is given (0 means "only a closed outline makes sense here"), and
## `collide` is deliberately per entry: a mulch surface the player trips over is a bug
## and a wall the player walks through is a worse one (REQ-V8.7).
const SOLIDS := {
	# Paving. Barely proud of the ground and only a little below it, which is what makes
	# a path read as a path rather than as a wall.
	LayerSetScript.NEW_HARDSCAPE: {
		"base_m": -0.02, "height_m": 0.05, "width_m": 0.60,
		"material_set": "paver_granite", "collide": false,
		"what": "paving, paths, kerbs, steps",
	},
	# A deck is raised, so it is both taller and further off the ground, and it is
	# something a person stands on: it collides.
	LayerSetScript.NEW_STRUCTURE: {
		"base_m": 0.02, "height_m": 0.32, "width_m": 0.20,
		"material_set": "deck_timber", "collide": true,
		"what": "deck, pergola posts, structure",
	},
	# A bed is a mulch surface: six centimetres of it, no collider, because walking
	# through a flower bed is something people do.
	LayerSetScript.NEW_BED: {
		"base_m": 0.0, "height_m": 0.06, "width_m": 0.60,
		"material_set": "mulch_bark", "collide": false,
		"what": "bed soil and mulch",
	},
	# Existing work is already built and is drawn as a fact about the site, so it gets a
	# real solid — an existing patio is a step you can stand on — but a thin one, because
	# nothing here is being proposed.
	LayerSetScript.EXISTING_HARDSCAPE: {
		"base_m": -0.02, "height_m": 0.04, "width_m": 0.50,
		"material_set": "paver_sandstone", "collide": true,
		"what": "existing paving and walls",
	},
	# The one solid in the table with a height a person can see from across the garden.
	# A building drawn on 100-EXIST-STRUCT becomes a mass, which is the single most
	# useful thing the 3D view can derive from a plan.
	LayerSetScript.EXISTING_STRUCTURE: {
		"base_m": 0.0, "height_m": 2.60, "width_m": 0.30,
		"material_set": "render_stucco", "collide": true,
		"what": "existing buildings",
	},
}

## Layers that deliberately have no solid, with the reason. The same device as
## `WashTable.NO_WASH`: a reader asking "why is my turf flat" gets the answer here
## rather than from a missing entry that looks like an oversight.
const NO_SOLID := {
	LayerSetScript.SURVEY_PROPERTY: "A property line is a fact about the site, not something built on it.",
	LayerSetScript.SURVEY_ANNOTATION: "An annotation.",
	LayerSetScript.SETBACK_EASEMENT: "A constraint, drawn as a line.",
	LayerSetScript.EXISTING_PLANTING: "Existing planting is modelled as props, not extruded from symbols; a canopy's height is a property of the plant, not of the drawing.",
	LayerSetScript.GRADING_CONTOUR: "A contour is a line. The ground it crosses is a solid on the layer that owns the ground.",
	LayerSetScript.GRADING_SPOT: "An annotation.",
	LayerSetScript.NEW_PLANTING: "New planting is props too, for the same reason as existing: a symbol is a canopy seen from above, and a tree is not an extrusion of it.",
	LayerSetScript.NEW_TURF: "Turf *is* the ground. Extruding it would raise the whole garden by the thickness of the grass and put a step at every border.",
	LayerSetScript.IRRIGATION: "Below ground, and drawn as linework.",
	LayerSetScript.LIGHTING: "Above ground, and drawn as a symbol.",
	LayerSetScript.HATCH: "A pattern layer: the ground under it is solid on the layer that owns the ground.",
	LayerSetScript.DIMENSION: "An annotation (drafting spec §4).",
	LayerSetScript.TEXT: "An annotation.",
	LayerSetScript.CALLOUT: "An annotation.",
	LayerSetScript.SHEET_BORDER: "Sheet furniture.",
	LayerSetScript.SHEET_VIEWPORT: "Sheet furniture.",
	LayerSetScript.UNDERLAY: "A tracing aid.",
	LayerSetScript.GUIDES: "A tracing aid.",
}

## The layers the specification's own version of this table named, and what became of
## them. Recorded rather than silently dropped: §8.5 asks for a pond as "a surface at
## water level plus a rim at coping level", and the honest answer is that this project
## has nowhere to draw a pond yet.
const MISSING := {
	"WATER": "No water layer exists in this project's preset set. A pond is §8.5's example of a surface-plus-rim solid, and it cannot be built until there is a layer to draw it on; a pond drawn on 300-NEW-HARD would extrude as paving.",
	"DECK": "No deck layer exists. A deck is drawn on 301-NEW-STRUCT, which is where its timber and its raised base live.",
	"PLANTING_BED": "The preset set calls this 400-NEW-BED.",
	"WALLS": "No separate wall layer exists. A retaining wall is drawn on 300-NEW-HARD as a line, which is a ribbon 0.20 m wide, and its *height* is therefore the paving height — the one place this table is knowingly coarse.",
}


## The solid specification for a layer, or {} when that layer stays flat.
##
## Empty is the answer for a layer that is not in the table and for one that is
## deliberately flat, which is the same thing to a caller: no solid. `reason_for()`
## tells the two apart for a person.
static func solid_for(layer_name: StringName) -> Dictionary:
	return SOLIDS.get(StringName(layer_name), {})


## Whether a layer becomes solids at all.
static func has_solid(layer_name: StringName) -> bool:
	return SOLIDS.has(StringName(layer_name))


## Why a layer has no solid, or "" when it has one.
##
## A layer in neither table says so as a missing entry rather than being described as
## deliberate, because those are different problems: one is a table to extend, the
## other is a decision that was made.
static func reason_for(layer_name: StringName) -> String:
	var name := StringName(layer_name)
	if SOLIDS.has(name):
		return ""
	if NO_SOLID.has(name):
		return String(NO_SOLID[name])
	return "%s is not in the solid table: either add it to SolidTable.SOLIDS or record why it stays flat." % name


## Whether an entity of this size should become a ribbon rather than a surface.
##
## The rule, in one place: an open line with a width becomes a ribbon; anything else
## with a usable outline becomes a slab. A closed entity is never a ribbon, however
## narrow its layer's width, because a patio drawn as a rectangle is a patio.
static func wants_ribbon(closed: bool, width_m: float) -> bool:
	return not closed and width_m > 0.0


## Every material set this table asks for, so a missing texture can be found by a test
## rather than by looking at a grey patio.
static func material_sets() -> Array[String]:
	var out: Array[String] = []
	for entry: Dictionary in SOLIDS.values():
		var name := String(entry["material_set"])
		if not out.has(name):
			out.append(name)
	return out


## The table in one line per layer, for a status bar or a report.
static func describe() -> String:
	var lines: Array[String] = []
	for layer_name: StringName in SOLIDS:
		var entry: Dictionary = SOLIDS[layer_name]
		lines.append("%s: %.2f to %.2f m in %s" % [
			layer_name, float(entry["base_m"]), float(entry["height_m"]),
			String(entry["material_set"]),
		])
	return "\n".join(lines)