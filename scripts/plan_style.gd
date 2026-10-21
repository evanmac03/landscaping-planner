class_name PlanStyle
extends RefCounted
## Style tables for the flat 2D plan view.
##
## Both tables are keyed by the very resources the 3D scene already uses, so the
## plan cannot quietly drift away from the model. A material or prop scene that
## gets renamed turns up here as a missing key rather than silently drawing the
## wrong thing, and a prop the tables do not know about is still drawn and still
## draggable, just generically.

const PlantSymbolsScript := preload("res://scripts/plant_symbols.gd")

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
##
## The symbol here is the one a **prop** draws as, which is what a plant with no
## catalogue entry behind it gets. A species the catalogue knows is drawn as its own
## symbol instead (`PlantSymbols.of`), because one tree model stands in for every
## tree and a spruce must not come out as the maple's canopy. The names are bare
## symbols rather than `PlantSymbols` constants on purpose: this table is read
## before that script is built, and a test holds the two together.
const SYMBOLS := {
	"res://scenes/props/tree.tscn": {
		"symbol": &"canopy", "size": Vector2(3.7, 3.7), "wash": FOLIAGE_WASH,
	},
	"res://scenes/props/shrub.tscn": {
		"symbol": &"shrub", "size": Vector2(1.5, 1.5), "wash": FOLIAGE_WASH,
	},
	"res://scenes/props/flower_bed.tscn": {
		"symbol": &"bed", "size": Vector2(2.6, 1.4), "wash": BLOOM_WASH,
	},
	# The shapes the drawing already spoke, as models: `PlantSymbols` has drawn a spruce as a conifer
	# and a fern as a fern since it was written, while the 3D view had three props for all nine of
	# them, so a spruce stood in the garden as a maple's crown. Built by `tools/plant_models.gd`, and
	# each size is the footprint that file measured rather than one typed in by hand - a plant is
	# planted at `spread / size.x`, so a size that drifted would put every plant at the wrong size
	# while every view still looked plausible. `tests/test_plant_models.gd` measures the assets.
	"res://assets/plants/conifer.gltf": {
		"symbol": &"conifer", "size": Vector2(2.6, 2.6), "wash": FOLIAGE_WASH,
	},
	"res://assets/plants/grass.gltf": {
		"symbol": &"grass", "size": Vector2(1.09, 1.09), "wash": FOLIAGE_WASH,
	},
	"res://assets/plants/groundcover.gltf": {
		"symbol": &"groundcover", "size": Vector2(0.64, 0.64), "wash": FOLIAGE_WASH,
	},
	"res://assets/plants/vine.gltf": {
		"symbol": &"vine", "size": Vector2(0.91, 0.91), "wash": FOLIAGE_WASH,
	},
	"res://assets/plants/fern.gltf": {
		"symbol": &"fern", "size": Vector2(1.13, 1.13), "wash": FOLIAGE_WASH,
	},
	# A perennial is drawn as the bed it is planted as, so its model is a bed too - the same oblong
	# ground the raised bed prop occupied, and the oblong shape is what makes the `bed` symbol oblong
	# rather than round (`PlantSymbols.shape_for`). The size is the one the builder *measured*, not one
	# typed in: the sphere a bed's soil is made of reports a bounding box a shade inside its radius.
	"res://assets/plants/perennial.gltf": {
		"symbol": &"bed", "size": Vector2(2.56, 1.38), "wash": BLOOM_WASH,
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
const PLACEHOLDER := {"symbol": &"marker", "size": Vector2(1.2, 1.2)}
const UNKNOWN_COLOUR := Color(0.55, 0.55, 0.58)


## Plan footprint and symbol for a prop scene. Never fails; unknown props get the
## placeholder.
static func spec_for(scene_path: String) -> Dictionary:
	return SYMBOLS.get(scene_path, PLACEHOLDER)


## The symbol a placed prop is drawn as: the symbol a species wrote on the node when it was planted,
## and otherwise whatever its prop draws as. A plant the catalogue never saw - one dropped in by hand
## in the editor - is drawn as its prop, which is what every plant was drawn as before symbols.
static func symbol_of(node: Node3D) -> StringName:
	var spec: Dictionary = spec_for(node.scene_file_path)
	var symbol: StringName = spec["symbol"]
	if node.has_meta(PlantSymbolsScript.SYMBOL_META):
		symbol = StringName(node.get_meta(PlantSymbolsScript.SYMBOL_META))
	if not PlantSymbolsScript.is_symbol(symbol):
		return PlantSymbolsScript.MARKER
	return symbol


## On-plan size of a placed prop, in metres, including the instance's own scale.
## The footprint's *shape* comes from the symbol: a round symbol is drawn as a disc
## and an oblong one as a rectangle, so a bed does not come out round and a grass
## planted as a flower bed does not come out oblong.
static func footprint_size(node: Node3D) -> Vector2:
	var size: Vector2 = spec_for(node.scene_file_path)["size"]
	# A prop in the yard reports the scale it inherits from its parents. Outside
	# the tree there is no global transform to ask for, so fall back to its own.
	var basis: Basis = node.transform.basis
	if node.is_inside_tree():
		basis = node.global_transform.basis
	return PlantSymbolsScript.shape_for(symbol_of(node), size * basis.get_scale().x)


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


## Points around a round footprint. Enough that the edge has something to wander along
## once it is wobbled, without the canopy reading as a polygon.
const FOOTPRINT_POINTS := 28


## A prop's footprint as a closed ring in model metres, in the shape the working plan
## draws it: a disc for a round symbol, a rectangle for an oblong one such as a bed.
##
## Shared by the painted plan's two layers, which is the point of it: the wash fills this
## ring and the ink draws round it, so they cannot disagree about what shape the plant
## is. Found by looking at a painted plan - the first version washed every prop as a disc
## and put round colour under the oblong symbol a flower bed is drawn as.
##
## The result is not closed (no repeated first point), like every other ring in this
## project: the closing edge is implied.
static func footprint_ring(node: Node3D) -> PackedVector2Array:
	var size: Vector2 = footprint_size(node)
	var centre := Vector2(node.global_position.x, node.global_position.z)
	if size.x <= 0.0 or size.y <= 0.0:
		return PackedVector2Array()
	if PlantSymbolsScript.is_round(symbol_of(node)):
		return _disc_ring(centre, maxf(size.x, size.y) * 0.5)
	return _rectangle_ring(centre, size)


static func _disc_ring(centre: Vector2, radius: float) -> PackedVector2Array:
	var ring := PackedVector2Array()
	for step in FOOTPRINT_POINTS:
		var angle: float = TAU * float(step) / float(FOOTPRINT_POINTS)
		ring.append(centre + Vector2(cos(angle), sin(angle)) * radius)
	return ring


static func _rectangle_ring(centre: Vector2, size: Vector2) -> PackedVector2Array:
	var half := size * 0.5
	return PackedVector2Array([
		centre + Vector2(-half.x, -half.y),
		centre + Vector2(half.x, -half.y),
		centre + Vector2(half.x, half.y),
		centre + Vector2(-half.x, half.y),
	])


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