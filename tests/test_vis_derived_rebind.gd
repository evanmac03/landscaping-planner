extends Node
## Tests that the derived builder follows *the drawing in hand* rather than the document it was
## handed once, at `_ready`.
##
## The bug this guards was reported as "the building isn't rendered along with the plants" in a
## client presentation. The plants are yard props and are always in the scene; the building, the
## paving, the decks and the beds are solids derived from the drawing. Opening a drawing - and
## restoring a revision of it, and recovering an autosave copy of it - *replaces* the document
## rather than editing it, so a builder that kept the first document went on deriving a drawing
## nobody could see. The working plan and the 3D linework followed the new drawing, because the
## controller re-binds those itself, so the only thing missing was the derived world: a
## presentation of a garden with the planting standing in an empty yard.

const Entity := preload("res://scripts/draft/draft_entity.gd")
const LayerSet := preload("res://scripts/draft/layer_set.gd")
const ControllerScript := preload("res://scripts/draft/draft_controller.gd")
const DerivedScript := preload("res://scripts/vis/derived_builder.gd")

## Where this test's drawing is filed. `user://` because a test writes a file and the project
## folder is version-controlled.
const DRAWING_PATH := "user://test-derived-rebind.json"


## A view controller in miniature. The one thing `DerivedBuilder` asks of the real one is the
## drafting controller, so a facade is enough and the whole scene stays out of the test.
class StubView:
	extends Node

	var controller: Node = null

	func draft_controller() -> Node:
		return controller


func test_the_builder_follows_a_drawing_that_is_opened() -> void:
	var controller := ControllerScript.new()
	add_child(controller)
	var stub := StubView.new()
	stub.controller = controller
	add_child(stub)
	var builder := DerivedScript.new()
	builder.view_controller = stub
	add_child(builder)

	# A drawing with a building on it, filed where it can be opened again.
	var building_id: int = controller.document.add(
		Entity.make_rectangle(Vector2(2.0, 3.0), Vector2(6.0, 4.0)),
		LayerSet.EXISTING_STRUCTURE
	)
	assert(
		bool(controller.save_drawing(DRAWING_PATH)["ok"]),
		"the test's drawing could not be written"
	)
	builder.rebuild()
	assert(builder.loft_count() == 1, "a building on the drawing should stand as one solid")

	# Take the building off the drawing in hand, so the drawing on the screen and the drawing in
	# the file differ by their contents and not only by their identity. A stale builder is then
	# told apart from a live one by what it derives, which is what a person sees.
	controller.document.remove(building_id)
	builder.rebuild()
	assert(builder.loft_count() == 0, "the building was removed but is still standing")

	# Open the file. This *replaces* the document, and it is the act the whole test exists for.
	assert(
		controller.open_drawing(DRAWING_PATH),
		"the test's drawing could not be opened"
	)
	assert(
		builder.document == controller.document,
		"the builder is still deriving the drawing that was replaced"
	)
	builder.rebuild()
	assert(
		builder.loft_count() == 1,
		"the building in the opened drawing is not standing"
	)

	builder.queue_free()
	stub.queue_free()
	controller.queue_free()