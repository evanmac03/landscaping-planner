class_name SiteScenery
extends RefCounted
## What the shipped yard is made of: the scenery that is the *site*, and the ground that stays under a
## blank sheet.
##
## A new drawing is a blank page. The garden this program opens onto - `scenes/world/yard.tscn`, a house,
## a lawn, paving and its planting - is one fixed example rather than something a person drew, so it is
## scenery the designer brings back on purpose rather than a background that is always there. Putting it
## away has to leave *something* under the drawing, or a blank page would be a void with nowhere to
## stand, so the yard's parts are sorted into two lists here and nowhere else.
##
## Named by node name rather than by kind, because "what is the garden" is a fact about this yard and not
## about node types: the house is scenery and the lawn is ground, and both are meshes. `is_known` is what
## keeps this list honest - a part added to the yard that is in none of the three is a part nothing will
## put away, and `tests/test_site_scenery.gd` holds every part of the shipped yard to one of them.

## The parts that are the designed garden: shown by "Show the site" and put away on a new drawing.
const SCENERY: Array[String] = ["House", "Paving", "Feature", "Surroundings", "Fence"]
## The parts that are ground: kept when the site is put away, so a blank sheet still has a floor to stand
## on and the ground view is somewhere rather than nowhere. `FenceCollision` is the invisible barrier that
## keeps the walk on the property, so it is ground for the same reason - it is the floor's edge.
const GROUND: Array[String] = ["Terrain", "TerrainBody", "Lawn", "FenceCollision"]
## The subtree whose children are the planted props. The same name `PlanCanvas` and `PlantPlacement` read.
const PLANTS := "Plants"


## Whether a node name is a piece of the garden scenery.
static func is_scenery(name: StringName) -> bool:
	return SCENERY.has(String(name))


## Whether a node name is a piece of ground.
static func is_ground(name: StringName) -> bool:
	return GROUND.has(String(name))


## Whether this part of the yard is accounted for: scenery, ground, or the planting subtree. Anything
## else is a part nothing knows what to do with, which is the fault this whole file exists to notice.
static func is_known(name: StringName) -> bool:
	return is_scenery(name) or is_ground(name) or String(name) == PLANTS


## The yard's scenery, as the nodes a caller puts away: the garden groups that are there, by name. Named
## rather than by kind, because the house and the lawn are both meshes and only one of them is scenery.
##
## The planting is deliberately **not** here. A plant the yard was shipped with is scenery, but a plant a
## designer puts down later is their design, and both live under the one `Plants` subtree - so what is
## put away from that subtree is decided by whoever knows which was which, and handed in rather than
## guessed at here.
static func furniture(yard: Node) -> Array[Node3D]:
	var out: Array[Node3D] = []
	if yard == null:
		return out
	for child: Node in yard.get_children():
		if not is_scenery(child.name):
			continue
		var spatial: Node3D = child as Node3D
		if spatial != null:
			out.append(spatial)
	return out