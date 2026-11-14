extends Node
## Shows the plant key's page against a list whose leaves have been stated, so the drawings can be looked
## at rather than inferred. A development tool, so `tools/` only - nothing in `scripts/` or `scenes/` may
## depend on it.
##
## The shipped nursery list states no leaf for any of its 130 species, and the key asks a leaf question only
## while every plant left states that leaf - so on the real list the drawings can never appear. This builds
## the one catalogue that puts them on screen: twelve plants that agree about everything except the shape of
## a leaf, so the shape question is worth asking and all twelve of its answers are live. That is the widest
## the answers row ever gets, which is the thing worth seeing.
##
## Run it with `run_scene res://tools/plant_key_leaf_demo.tscn` and look at the page; it quits itself.

const SpeciesScript := preload("res://scripts/plant_species.gd")
const CatalogueScript := preload("res://scripts/plant_catalogue.gd")
const KeyWindowScript := preload("res://scripts/plant_key_window.gd")
const KeyScript := preload("res://scripts/plant_key.gd")

const SECONDS_UP := 4.0


func _ready() -> void:
	var catalogue: CatalogueScript = _twelve_shapes()
	var page: KeyWindowScript = KeyWindowScript.new()
	add_child(page)
	page.build()
	page.bind(catalogue)
	page.popup_centered()

	var state: Dictionary = page.the_state()
	print("[leaf demo] %d plants, first question is '%s'" % [catalogue.count(), state["question"]])
	print("[leaf demo] %d answers offered, and the readings below are how many carry a drawing:" % page.option_count())
	var drawn: int = 0
	for index: int in page.option_count():
		var has_one: bool = page.option_picture(index) != null
		if has_one:
			drawn += 1
		print("   %-46s drawn=%s" % [page.option_words(index), has_one])
	print("[leaf demo] %d of %d answers have a drawing" % [drawn, page.option_count()])

	# The widths the page really has, read off the live tree rather than worked out on paper: an answer
	# button is as wide as its own words, and the row it sits in gets whatever the window has left. Two
	# frames, because a container's own size only settles after the layout pass.
	await get_tree().process_frame
	await get_tree().process_frame
	var row: Control = page.find_child("Answers", true, false) as Control
	print("[leaf demo] window %d wide, answers row %d wide at x=%d" % [page.size.x, row.size.x, row.position.x])
	var widest: float = 0.0
	for index: int in page.option_count():
		var button: Button = row.get_child(index) as Button
		widest = maxf(widest, button.get_combined_minimum_size().x)
		print(
			"   %-46s min=%d wide, given %d"
			% [page.option_words(index), button.get_combined_minimum_size().x, button.size.x]
		)
	print("[leaf demo] the widest answer needs %d, the row has %d" % [widest, row.size.x])

	# And what that width would be if the words were allowed to wrap instead of setting it. Read in the tree,
	# because a Button off-tree has no theme font and its own minimum means nothing there.
	var probe: Button = row.get_child(0) as Button
	print("[leaf demo] the widest answer's own minimum:            %d" % probe.get_combined_minimum_size().x)
	probe.clip_text = true
	await get_tree().process_frame
	print("[leaf demo]   with its text allowed to be clipped:      %d" % probe.get_combined_minimum_size().x)
	probe.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	await get_tree().process_frame
	print("[leaf demo]   with its text allowed to wrap as well:    %d" % probe.get_combined_minimum_size().x)
	probe.custom_minimum_size = Vector2(0, 140)
	await get_tree().process_frame
	print("[leaf demo]   and given room for two lines and a leaf:  %d" % probe.get_combined_minimum_size().x)

	var timer: Timer = Timer.new()
	timer.wait_time = SECONDS_UP
	timer.one_shot = true
	timer.timeout.connect(
		func() -> void:
			get_tree().quit(),
	)
	add_child(timer)
	timer.start()


## Twelve plants that agree about everything a leaf question can ask except the shape of the leaf, one per
## value the shape vocabulary knows. Built from `SHAPE_NAMES` so a shape added to the table appears here too,
## and named after its own label so the page reads as what it is.
func _twelve_shapes() -> CatalogueScript:
	var catalogue: CatalogueScript = CatalogueScript.make()
	for value: Variant in SpeciesScript.SHAPE_NAMES.keys():
		var shape: int = int(value)
		var label: String = String(SpeciesScript.SHAPE_NAMES[shape])
		var plant: SpeciesScript = SpeciesScript.make(
			StringName("SHAPE-%d" % shape),
			"Test species %d" % shape,
			label,
			500,
			500,
			SpeciesScript.SHRUB,
		)
		plant.leaf_arrangement = SpeciesScript.ARR_ALTERNATE
		plant.leaf_complexity = SpeciesScript.CMP_SIMPLE
		plant.leaf_margin = SpeciesScript.MRG_ENTIRE
		plant.leaf_venation = SpeciesScript.VEN_PINNATE
		plant.leaf_shape = shape
		catalogue.add(plant)
	return catalogue
