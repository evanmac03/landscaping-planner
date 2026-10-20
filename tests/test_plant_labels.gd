extends Node
## Tests for the planting labels: what they say, where they stand, and how they reach
## the drawing.
##
## The pure half is driven with a list of points and no scene at all; the drawing half
## builds a controller with its parts but no tree, the way the editing tools are tested.

const Labels := preload("res://scripts/plant_labels.gd")
const Ctrl := preload("res://scripts/draft/draft_controller.gd")
const Tool := preload("res://scripts/draft/draft_tool.gd")
const Document := preload("res://scripts/draft/draft_document.gd")
const SnapScript := preload("res://scripts/draft/snap_engine.gd")
const LayerSet := preload("res://scripts/draft/layer_set.gd")


func _plant(species: String, name: String, x: float, y: float) -> Dictionary:
	return {"species": StringName(species), "name": name, "position": Vector2(x, y)}


func _controller():
	var controller = Ctrl.new()
	controller.document = Document.new()
	controller.snap = SnapScript.new()
	controller.tool = Tool.new()
	return controller


# --- what a label says ----------------------------------------------------------------


func test_a_label_names_the_plant_and_counts_it() -> void:
	assert(Labels.label_text("Acer rubrum", 3) == "Acer rubrum (3)")
	assert(Labels.label_text("Acer rubrum", 1) == "Acer rubrum (1)", "one plant is still counted")


func test_a_keyed_plan_writes_the_count_alone() -> void:
	assert(Labels.label_text("Acer rubrum", 3, true) == "3",
		"where a key letters the plants, the label is the count and the key says the name")


# --- where a label stands -------------------------------------------------------------


func test_a_single_plant_stands_at_itself() -> void:
	var points := PackedVector2Array([Vector2(3.0, 4.0)])
	assert(Labels.centroid(points) == Vector2(3.0, 4.0))


func test_a_group_is_labelled_at_its_middle() -> void:
	var points := PackedVector2Array([Vector2(0.0, 0.0), Vector2(4.0, 0.0), Vector2(4.0, 6.0)])
	assert(Labels.centroid(points) == Vector2(8.0 / 3.0, 2.0), "the mean of the group")


func test_a_group_of_no_plants_has_no_middle() -> void:
	assert(Labels.centroid(PackedVector2Array()) == Vector2.ZERO, "and it does not divide by nothing")


# --- one label a species --------------------------------------------------------------


func test_one_label_stands_for_each_species() -> void:
	var wanted := Labels.labels_for([
		_plant("acer", "Acer rubrum", 0.0, 0.0),
		_plant("acer", "Acer rubrum", 2.0, 0.0),
		_plant("hosta", "Hosta", 10.0, 10.0),
	])
	var labels: Array = wanted["labels"]
	assert(labels.size() == 2, "two species, two labels")
	assert(Labels.planted_count(labels) == 3, "and three plants")
	for entry: Dictionary in labels:
		if String(entry["species"]) == "acer":
			assert(int(entry["count"]) == 2)
			assert(entry["at"] == Vector2(1.0, 0.0), "the label stands between the two acers")
			assert(String(entry["text"]) == "Acer rubrum (2)")
		else:
			assert(entry["at"] == Vector2(10.0, 10.0), "a lone plant is labelled at itself")


func test_the_labels_come_out_in_the_same_order_every_time() -> void:
	var plants: Array = [
		_plant("hosta", "Hosta", 1.0, 1.0),
		_plant("acer", "Acer rubrum", 2.0, 2.0),
		_plant("taxus", "Taxus", 3.0, 3.0),
	]
	var first := Labels.labels_for(plants)
	var again := Labels.labels_for(plants)
	var texts: Array[String] = []
	for entry: Dictionary in first["labels"]:
		texts.append(String(entry["text"]))
	var repeated: Array[String] = []
	for entry: Dictionary in again["labels"]:
		repeated.append(String(entry["text"]))
	assert(texts == repeated, "the same drawing writes the same list")
	assert(texts[0] == "Acer rubrum (1)", "and it is in the order a person reads: %s" % str(texts))


func test_a_plant_nobody_can_name_is_labelled_as_such() -> void:
	var wanted := Labels.labels_for([
		_plant("", "", 4.0, 4.0),
		_plant("", "", 6.0, 4.0),
		_plant("hosta", "Hosta", 0.0, 0.0),
	])
	assert(int(wanted["skipped"]) == 2, "two plants stand under no name")
	var texts: Array[String] = []
	for entry: Dictionary in wanted["labels"]:
		texts.append(String(entry["text"]))
	assert(texts.has("no species (2)"), "and they are named as such rather than dropped: %s" % str(texts))


func test_a_plant_with_no_position_is_passed_over() -> void:
	var wanted := Labels.labels_for([
		{"species": &"acer", "name": "Acer rubrum"},
		_plant("hosta", "Hosta", 1.0, 1.0),
	])
	assert((wanted["labels"] as Array).size() == 1, "a plant nowhere cannot be labelled")
	assert(String((wanted["labels"] as Array)[0]["text"]) == "Hosta (1)", "and the rest still are")


func test_nothing_planted_says_so() -> void:
	var wanted := Labels.labels_for([])
	assert((wanted["labels"] as Array).is_empty())
	assert(String(wanted["reason"]) == "nothing is planted", "an empty planting is named, not guessed at")
	assert(Labels.summary([]) == "nothing to label")


func test_the_summary_counts_both_ways() -> void:
	var wanted := Labels.labels_for([
		_plant("acer", "Acer rubrum", 0.0, 0.0),
		_plant("acer", "Acer rubrum", 1.0, 0.0),
	])
	assert(Labels.summary(wanted["labels"]) == "1 label for 2 plants", Labels.summary(wanted["labels"]))


# --- reaching the drawing -------------------------------------------------------------


func test_the_labels_land_on_the_text_layer() -> void:
	var controller = _controller()
	var wanted := Labels.labels_for([
		_plant("acer", "Acer rubrum", 0.0, 0.0),
		_plant("acer", "Acer rubrum", 2.0, 0.0),
	])
	var taken: Dictionary = controller.label_planting(wanted["labels"])
	assert(bool(taken["ok"]), String(taken["reason"]))
	assert(controller.document.count() == 1, "one label for the group")
	var entity = controller.document.entities()[0]
	assert(String(entity.layer) == String(LayerSet.TEXT), "a label is an annotation")
	assert(String(entity.meta.get("text", "")) == "Acer rubrum (2)", "and it says what it says")
	assert(is_equal_approx(float(entity.meta.get("height", 0.0)), Labels.LABEL_HEIGHT_MM),
		"written at a paper height, not a model one")
	controller.free()


func test_labelling_a_planning_is_one_undo_step() -> void:
	var controller = _controller()
	var wanted := Labels.labels_for([
		_plant("acer", "Acer rubrum", 0.0, 0.0),
		_plant("hosta", "Hosta", 5.0, 5.0),
	])
	controller.label_planting(wanted["labels"])
	assert(controller.document.count() == 2)
	assert(controller.document.undo_last(), "one Ctrl+Z takes the whole run of labels back")
	assert(controller.document.count() == 0)
	controller.free()


func test_labeling_nothing_is_refused_rather_than_writing_nothing() -> void:
	var controller = _controller()
	var taken: Dictionary = controller.label_planting([])
	assert(not bool(taken["ok"]))
	assert(controller.document.count() == 0)
	assert(controller.last_message == "there is nothing to label", controller.last_message)
	controller.free()


func test_a_label_with_nothing_to_say_is_passed_over() -> void:
	var controller = _controller()
	var taken: Dictionary = controller.label_planting([
		{"at": Vector2(1.0, 1.0), "text": "   "},
		{"at": Vector2(2.0, 2.0), "text": "Hosta (1)"},
		{"text": "nowhere (1)"},
	])
	assert(bool(taken["ok"]))
	assert(int(taken["count"]) == 1, "only the label that says something and has somewhere to stand")
	assert(controller.document.count() == 1)
	controller.free()


func test_the_status_line_says_what_was_labelled() -> void:
	var controller = _controller()
	controller.label_planting(Labels.labels_for([
		_plant("acer", "Acer rubrum", 0.0, 0.0),
		_plant("hosta", "Hosta", 1.0, 1.0),
	])["labels"])
	assert(controller.last_message.begins_with("labelled 2 labels"),
		"the drawing says what it wrote: " + controller.last_message)
	controller.free()