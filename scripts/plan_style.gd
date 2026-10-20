class_name PlanStyle
extends RefCounted
## Style tables for the flat 2D plan view.
##
## Both tables are keyed by the very resources the 3D scene already uses, so the
## plan cannot quietly drift away from the model. A material or prop scene that
## gets renamed turns up here as a missing key rather than silently drawing the
## wrong thing, and a prop the tables do not know about is still drawn and still
## draggable, just generically.

enum Symbol {
	TREE,    ## Canopy circle with a trunk dot at the centre.
	SHRUB,   ## Soft scalloped blob.
	BED,     ## Planted bed with a stone edge and a row of blooms.
	GENERIC, ## Fallback marker for a prop these tables do not describe.
}

## Flat drafting colours, keyed by material resource path. The 3D materials are
## noise-textured, which leaves their albedo_color white and useless here, so
## these are the plan colours that stand in for them.
const COLOURS := {
	"res://resources/materials/lawn.tres": Color(0.655, 0.784, 0.451),
	"res://resources/materials/rough_grass.tres": Color(0.871, 0.863, 0.792),
	"res://resources/materials/soil.tres": Color(0.706, 0.596, 0.451),
	"res://resources/materials/stone.tres": Color(0.804, 0.792, 0.753),
	"res://resources/materials/stucco.tres": Color(0.929, 0.918, 0.878),
	"res://resources/materials/shingle.tres": Color(0.451, 0.42, 0.416),
	"res://resources/materials/fence_wood.tres": Color(0.616, 0.502, 0.361),
	"res://resources/materials/bark.tres": Color(0.443, 0.341, 0.243),
	"res://resources/materials/foliage.tres": Color(0.42, 0.62, 0.329),
	"res://resources/materials/flower_pink.tres": Color(0.89, 0.42, 0.6),
	"res://resources/materials/flower_yellow.tres": Color(0.949, 0.82, 0.278),
	"res://resources/materials/flower_white.tres": Color(0.929, 0.918, 0.878),
}

## Props, keyed by scene path, with the plan footprint each occupies in metres
## before the instance's own scale is applied, and the colour it washes in when the
## plan is painted (§4.4).
##
## The wash belongs in this table rather than in a second one keyed by species,
## because this is already the entry that decides what a prop looks like in the
## plan: the symbol it draws as, the ground it covers, and now the pigment under it.
## One entry, so a prop cannot be a tree in the working view and a shrub in the
## painted one.
const SYMBOLS := {
	"res://scenes/props/tree.tscn": {
		"symbol": Symbol.TREE, "size": Vector2(3.7, 3.7), "wash": FOLIAGE_WASH,
	},
	"res://scenes/props/shrub.tscn": {
		"symbol": Symbol.SHRUB, "size": Vector2(1.5, 1.5), "wash": FOLIAGE_WASH,
	},
	"res://scenes/props/flower_bed.tscn": {
		"symbol": Symbol.BED, "size": Vector2(2.6, 1.4), "wash": BLOOM_WASH,
	},
}

## The foliage green and the bloom pink, spelled out as constants so the tests can
## hold them against `COLOURS` and fail if the palette moves under the wash.
const FOLIAGE_WASH := Color(0.42, 0.62, 0.329)
const BLOOM_WASH := Color(0.89, 0.42, 0.6)

## Used for any prop missing from SYMBOLS, so nothing becomes invisible. It has no
## wash entry on purpose: a prop this table does not describe is left out of the
## painted plan's colour rather than washed in a guessed one, and it keeps its
## linework, so what is missing reads as a plant with no foliage wash rather than as
## a plant with the wrong one.
const PLACEHOLDER := {"symbol": Symbol.GENERIC, "size": Vector2(1.2, 1.2)}
const UNKNOWN_COLOUR := Color(0.55, 0.55, 0.58)


## Plan footprint and symbol for a prop scene. Never fails; unknown props get the
## placeholder.
static func spec_for(scene_path: String) -> Dictionary:
	return SYMBOLS.get(scene_path, PLACEHOLDER)


## On-plan size of a placed prop, in metres, including the instance's own scale.
## The footprint's *shape* comes from the size pair: a square footprint is drawn as a
## disc and an oblong one as a rectangle, so a bed does not come out round.
static func footprint_size(node: Node3D) -> Vector2:
	var size: Vector2 = spec_for(node.scene_file_path)["size"]
	# A prop in the yard reports the scale it inherits from its parents. Outside
	# the tree there is no global transform to ask for, so fall back to its own.
	var basis: Basis = node.transform.basis
	if node.is_inside_tree():
		basis = node.global_transform.basis
	return size * basis.get_scale().x


## On-plan radius of a placed prop, in metres, including the instance's own
## scale. Used both to hit-test a click and to size the selection ring.
##
## The half of the *longest* side, because this is a radius for grabbing and ringing
## something: a circle that reaches the far side of a bed is the one a click inside
## the bed should find.
static func footprint_radius(node: Node3D) -> float:
	var size: Vector2 = footprint_size(node)
	return maxf(size.x, size.y) * 0.5


## The colour a prop washes in when the plan is painted, or `Color.TRANSPARENT`
## when this table does not describe it.
##
## Transparent rather than a neutral grey: a wash is the one layer where a wrong
## colour is worse than no colour, because a grey canopy looks like a deliberate
## choice and a missing one looks like something to finish (REQ-V4.4).
static func wash_colour_for(node: Node3D) -> Color:
	return spec_for(node.scene_file_path).get("wash", Color.TRANSPARENT)


## Plan colour for a material, by resource path. The 3D materials are
## noise-textured, which leaves their albedo white and useless here, so the plan
## keeps its own flat palette. Anything without an entry gets the neutral grey.
static func colour_for_material(material: Material) -> Color:
	if material == null:
		return UNKNOWN_COLOUR
	# resource_path is empty for a sub-resource defined inside a scene, which is
	# why inline materials fall through to the neutral colour.
	return COLOURS.get(material.resource_path, UNKNOWN_COLOUR)


## Plan colour for a 3D mesh, taken from whichever material it actually uses.
static func colour_for(mesh_instance: MeshInstance3D) -> Color:
	var material: Material = mesh_instance.get_surface_override_material(0)
	if material == null:
		material = mesh_instance.material_override
	if material == null:
		var mesh: Mesh = mesh_instance.mesh
		if mesh != null and mesh.get_surface_count() > 0:
			material = mesh.surface_get_material(0)
	return colour_for_material(material)