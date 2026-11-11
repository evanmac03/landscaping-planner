extends Node
## What the shipped yard is made of (`res://scripts/site_scenery.gd`).
##
## The two lists decide what a blank page keeps and what it puts away, so what is held here is that they
## are two answers rather than one list used twice, and - the part a list like this always gets wrong -
## that **every** part of the yard the project actually ships is in one of them. A prop added to
## `yard.tscn` and forgotten here would be a prop nothing ever puts away, which is a garden showing through
## a blank page.

const SiteScript := preload("res://scripts/site_scenery.gd")

const YARD_SCENE := "res://scenes/world/yard.tscn"


func test_the_scenery_and_the_ground_are_two_lists_that_do_not_overlap() -> void:
	assert(not SiteScript.SCENERY.is_empty(), "there is scenery to put away")
	assert(not SiteScript.GROUND.is_empty(), "and ground to keep")
	for name: String in SiteScript.SCENERY:
		assert(not SiteScript.is_ground(name), "%s cannot be both garden and ground" % name)


## The rule that keeps the two lists honest: every top-level part of the yard the project ships is scenery,
## ground, or the planting subtree. This reads the real scene rather than a copy of its names, because a
## copy is the thing that would fall behind the day somebody adds a prop.
func test_every_part_of_the_shipped_yard_is_accounted_for() -> void:
	var scene: PackedScene = load(YARD_SCENE) as PackedScene
	assert(scene != null, "%s loads" % YARD_SCENE)
	var yard: Node = scene.instantiate()
	var unaccounted: Array[String] = []
	for child: Node in yard.get_children():
		if not SiteScript.is_known(child.name):
			unaccounted.append(String(child.name))
	assert(
		unaccounted.is_empty(),
		"these parts of the yard are neither garden, ground, nor planting: %s"
			% ", ".join(unaccounted)
	)
	yard.free()


## The scenery is returned as nodes, and only the groups that are there: a small yard with a house and a
## lawn gives back the house and not the lawn.
func test_the_scenery_of_a_yard_is_its_furniture_groups() -> void:
	var yard := Node3D.new()
	yard.name = "Yard"
	yard.add_child(_named("House", Node3D.new()))
	yard.add_child(_named("Lawn", MeshInstance3D.new()))
	var garden: Array[Node3D] = SiteScript.furniture(yard)
	assert(garden.size() == 1, "one piece of scenery: %d" % garden.size())
	assert(String(garden[0].name) == "House", "and it is the house: %s" % garden[0].name)
	yard.free()


## A part nobody has classified is neither: the answer a caller relies on to notice a new prop.
func test_a_part_nobody_has_classified_is_neither_scenery_nor_ground() -> void:
	assert(not SiteScript.is_scenery(&"Greenhouse"))
	assert(not SiteScript.is_ground(&"Greenhouse"))
	assert(not SiteScript.is_known(&"Greenhouse"))


func _named(node_name: String, node: Node3D) -> Node3D:
	node.name = node_name
	return node