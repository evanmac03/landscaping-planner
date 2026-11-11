extends Node
## What the planner lets you pick, and what it draws a ring around.
##
## The plan draws a selection ring under whatever the cursor is over, and `ViewController` answers
## that question from `Yard.PLACEABLE_GROUP`. A new drawing is a blank page, so the yard's own
## planting is put away - those nodes are hidden, but they are still in the yard and still in that
## group. Reading the group at its word therefore found a plant the page was not showing, so the
## plan drew a ring around a plant nobody could see, the cursor turned into a hand over it, and a
## click would have grabbed something invisible.
##
## These tests bring the real planner up rather than standing in a group of their own: the question
## is about the real yard's planting and the real group, and a stand-in would only answer for itself.

const MAIN_PATH := "res://scenes/main.tscn"

var _main: Node = null


## Bring the planner up and settle it, returning its ViewController. Two frames, because a scene's
## children enter the tree on the frame after `add_child`.
func _bring_up() -> ViewController:
	_main = load(MAIN_PATH).instantiate()
	add_child(_main)
	await get_tree().process_frame
	await get_tree().process_frame
	return _main.get_node("ViewController") as ViewController


## Take the planner back down, so a test leaves no scene behind it.
func _tear_down() -> void:
	if _main != null:
		_main.queue_free()
		_main = null
	await get_tree().process_frame


## The yard's own planting: the plants the yard shipped with, which a blank page puts away.
func _the_yards_planting(controller: ViewController) -> Array[Node3D]:
	return PlantPlacement.planted(controller.yard)


## The rule itself: a design object the page is not showing is not one the cursor can be over.
func test_a_put_away_plant_is_not_one_the_cursor_can_be_over() -> void:
	var controller: ViewController = await _bring_up()
	assert(not controller.is_site_shown(), "a new drawing is a blank page")
	var planting: Array[Node3D] = _the_yards_planting(controller)
	assert(not planting.is_empty(), "the yard really does ship planting for a blank page to put away")
	for plant: Node3D in planting:
		assert(not plant.is_visible_in_tree(),
			"%s was put away, so the page is not showing it" % plant.name)
	for pickable: Node3D in controller.placeables():
		assert(pickable.is_visible_in_tree(),
			"the planner offers only what the page shows, and %s is not shown" % pickable.name)
	await _tear_down()


## And the ring follows the pick: hovering where a put-away plant stands finds nothing, so the plan
## has no hovered node to draw a ring around.
func test_hovering_where_a_put_away_plant_stands_finds_nothing() -> void:
	var controller: ViewController = await _bring_up()
	controller.mode = ViewController.ViewMode.PLAN_2D
	var planting: Array[Node3D] = _the_yards_planting(controller)
	assert(not planting.is_empty(), "the yard ships planting to hover over")
	var plant: Node3D = planting[0]
	assert(not plant.is_visible_in_tree(), "this is one of the plants that was put away")
	var over_it: Vector2 = controller.plan_canvas.world_to_screen(plant.global_position)
	assert(controller.nearest_placeable(over_it) == null,
		"the cursor is over a plant the page is not showing, and nothing is under it")
	await _tear_down()


## The site put back is the site you can pick again: putting the planting away must not simply
## strike it off the planner's list for good.
func test_showing_the_site_makes_its_planting_pickable_again() -> void:
	var controller: ViewController = await _bring_up()
	controller.set_site_shown(true)
	var planting: Array[Node3D] = _the_yards_planting(controller)
	assert(not planting.is_empty(), "the yard ships planting to put back")
	for plant: Node3D in planting:
		assert(plant.is_visible_in_tree(), "%s is standing again" % plant.name)
		assert(controller.placeables().has(plant), "%s can be picked again" % plant.name)
	await _tear_down()