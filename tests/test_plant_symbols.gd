extends Node
## Plant symbols: the vocabulary a plant can be drawn as, the figure each one is drawn from, and the
## rule that says which symbol a *species* gets.
##
## The point of the feature is that a form is one prop for four thousand trees. Before this, every
## tree in the catalogue came out as the same green disc and every spruce came out as the maple's
## canopy. These tests hold the two halves of the fix together: the drawing's vocabulary and the
## catalogue's description of a plant, and the one call both the plan and the picture make.

const CatalogueScript := preload("res://scripts/plant_catalogue.gd")
const PlanStyleScript := preload("res://scripts/plan_style.gd")
const PlantIconsScript := preload("res://scripts/plant_icons.gd")
const SymbolsScript := preload("res://scripts/plant_symbols.gd")
const SpeciesScript := preload("res://scripts/plant_species.gd")
const CanvasScript := preload("res://scripts/plan_canvas.gd")
const PlacementScript := preload("res://scripts/plant_placement.gd")

const SEED := "res://data/plants/nursery_list.json"

## A spruce, a maple, a boxwood and a creeping juniper: the four answers to "is it a conifer, and is
## it a tree", which is the whole of the rule.
const SPRUCE := &"picea-glauca-densata"
const MAPLE := &"acer-rubrum-autumn-blaze"
const BOXWOOD := &"buxus-sempervirens"
const CEDAR := &"thuja-occidentalis-smaragd"

## Every shape and every ink a figure is allowed to be made of. The two renderers - the plan and the
## swatch - know these and nothing else, so a part outside them would be a symbol that draws as
## nothing rather than as a mistake somebody can see.
const SHAPES: Array[StringName] = [&"disc", &"rect", &"poly", &"line"]
const INKS: Array[StringName] = [&"fill", &"edge", &"mark"]


func _catalogue() -> PlantCatalogue:
	var read: Dictionary = CatalogueScript.load_from(SEED)
	assert(bool(read["ok"]), "the shipped list loads: %s" % String(read["reason"]))
	return read["catalogue"]


## The first species of a category, so a test that is about a *kind* of plant does not break when
## somebody adds or renames a plant in the list.
func _first_of(catalogue: PlantCatalogue, category: int) -> PlantSpecies:
	for species: PlantSpecies in catalogue.all():
		if species.category == category:
			return species
	assert(false, "the shipped list has no plant of category %d" % category)
	return null


# --- the vocabulary ------------------------------------------------------------------------


func test_the_symbols_are_named_and_each_has_a_word_for_it() -> void:
	assert(SymbolsScript.NAMES.size() >= 6, "there is a vocabulary: %d" % SymbolsScript.NAMES.size())
	for symbol: StringName in SymbolsScript.NAMES:
		assert(SymbolsScript.is_symbol(symbol), "%s is a symbol" % symbol)
		assert(SymbolsScript.words(symbol).length() > 0, "%s has a word" % symbol)
	# The words are the point of them - a label names a symbol, so two symbols said the same way
	# would be two shapes a person cannot tell apart in the line that is supposed to explain them.
	var said: Dictionary = {}
	for symbol: StringName in SymbolsScript.NAMES:
		var word: String = SymbolsScript.words(symbol)
		assert(not said.has(word), "%s and %s are both \"%s\"" % [said.get(word, ""), symbol, word])
		said[word] = symbol
	assert(not SymbolsScript.is_symbol(&"triangle"), "something nobody has is not a symbol")
	assert(SymbolsScript.words(&"triangle") == SymbolsScript.words(SymbolsScript.MARKER),
		"and an unknown symbol is said as the marker rather than as nothing")


# --- the figures ----------------------------------------------------------------------------


func test_every_symbol_is_drawn_from_a_figure_the_renderers_can_draw() -> void:
	for symbol: StringName in SymbolsScript.NAMES:
		var figure: Array[Dictionary] = SymbolsScript.figure(symbol)
		assert(not figure.is_empty(), "%s is drawn as something" % symbol)
		var filled: bool = false
		for part: Dictionary in figure:
			assert(INKS.has(StringName(part["ink"])), "%s has a known ink: %s" % [symbol, part["ink"]])
			assert(SHAPES.has(StringName(part["kind"])), "%s has a known shape: %s" % [symbol, part["kind"]])
			if StringName(part["ink"]) == &"fill":
				filled = true
		assert(filled, "%s has something filled in it" % symbol)


func test_a_figure_is_data_that_is_built_once() -> void:
	# The plan asks for a figure per plant every frame, so a figure rebuilt each time would be
	# allocation in a draw loop.
	SymbolsScript.clear_cache()
	var first: Array[Dictionary] = SymbolsScript.figure(SymbolsScript.CANOPY)
	assert(SymbolsScript.figure(SymbolsScript.CANOPY) == first, "asking twice gives the same figure")
	assert(SymbolsScript.FIGURES.has(SymbolsScript.CANOPY), "and it is kept")
	SymbolsScript.clear_cache()
	assert(not SymbolsScript.FIGURES.has(SymbolsScript.CANOPY), "clearing really clears it")
	assert(SymbolsScript.figure(SymbolsScript.CANOPY).size() == first.size(), "and it comes back")


func test_a_shape_difference_you_can_count() -> void:
	# A conifer is a crown with needles round it and a canopy is a bare disc: the difference is in the
	# figure, so both renderers get it without knowing what a conifer is.
	var canopy: Array[Dictionary] = SymbolsScript.figure(SymbolsScript.CANOPY)
	var conifer: Array[Dictionary] = SymbolsScript.figure(SymbolsScript.CONIFER)
	assert(conifer.size() > canopy.size(), "a conifer is drawn from more parts: %d" % conifer.size())
	# A bed is a rectangle and a canopy is round, which is the other half of what a person reads.
	assert(not SymbolsScript.is_round(SymbolsScript.BED), "a bed is oblong")
	assert(SymbolsScript.is_round(SymbolsScript.CANOPY), "a canopy is round")


func test_a_round_symbol_is_drawn_round_whatever_its_prop_says() -> void:
	# The cheap way to add a grass to the catalogue is to stand it in as the flower bed every other
	# perennial uses, and its footprint is then wider than it is deep. A grass is not an oblong.
	var grass: Vector2 = SymbolsScript.shape_for(SymbolsScript.GRASS, Vector2(2.6, 1.4))
	assert(grass.x == grass.y, "a round symbol is drawn square: %s" % grass)
	assert(is_equal_approx(grass.x, 2.6), "at the prop's longest side")
	var bed: Vector2 = SymbolsScript.shape_for(SymbolsScript.BED, Vector2(2.6, 1.4))
	assert(bed == Vector2(2.6, 1.4), "and an oblong one keeps the prop's proportions")


# --- which symbol a species gets -------------------------------------------------------------


func test_a_conifer_is_drawn_as_a_conifer_and_a_maple_as_a_canopy() -> void:
	# The feature in one line each. Both are the same prop, the same form, the same category.
	var catalogue: PlantCatalogue = _catalogue()
	var spruce: PlantSpecies = catalogue.get_species(SPRUCE)
	var maple: PlantSpecies = catalogue.get_species(MAPLE)
	assert(spruce.form == maple.form, "they are the same prop: %s" % spruce.form)
	assert(spruce.category == maple.category, "and the same category")
	assert(spruce.is_conifer(), "a spruce is a conifer")
	assert(not maple.is_conifer(), "a maple is not")
	assert(SymbolsScript.described_for(spruce) == SymbolsScript.CONIFER, "so it is drawn as one")
	assert(SymbolsScript.described_for(maple) == SymbolsScript.CANOPY, "and the maple as a canopy")


func test_a_conifer_is_asked_of_the_botanical_name_and_not_of_evergreen() -> void:
	# The tag a nursery writes is "evergreen", and a boxwood is evergreen without being a conifer.
	var catalogue: PlantCatalogue = _catalogue()
	var boxwood: PlantSpecies = catalogue.get_species(BOXWOOD)
	assert(boxwood.tags.has("evergreen"), "a boxwood is tagged evergreen: %s" % str(boxwood.tags))
	assert(not boxwood.is_conifer(), "and it is not a conifer")
	assert(SymbolsScript.described_for(boxwood) == SymbolsScript.SHRUB, "so it is a soft shrub")
	assert(SymbolsScript.described_for(catalogue.get_species(CEDAR)) == SymbolsScript.CONIFER,
		"while a cedar is")


func test_a_plant_is_drawn_as_what_it_is() -> void:
	# Category by category, from the shipped list rather than from a plant named here: a grass, a
	# groundcover, a fern and a vine each get their own symbol, which is the whole point of deriving
	# them from the catalogue instead of from the prop.
	var catalogue: PlantCatalogue = _catalogue()
	for pair: Array in [
		[SpeciesScript.GRASS, SymbolsScript.GRASS],
		[SpeciesScript.GROUNDCOVER, SymbolsScript.GROUNDCOVER],
		[SpeciesScript.FERN, SymbolsScript.FERN],
		[SpeciesScript.VINE, SymbolsScript.VINE],
		[SpeciesScript.TREE, SymbolsScript.CANOPY],
		[SpeciesScript.SHRUB, SymbolsScript.SHRUB],
	]:
		var species: PlantSpecies = _first_of(catalogue, int(pair[0]))
		var wanted: StringName = pair[1]
		var got: StringName = SymbolsScript.described_for(species)
		# A tree or a shrub may legitimately be a conifer; the others have one answer.
		if wanted == SymbolsScript.CANOPY or wanted == SymbolsScript.SHRUB:
			assert(got == wanted or got == SymbolsScript.CONIFER,
				"category %d is drawn as %s, not %s" % [int(pair[0]), wanted, got])
		else:
			assert(got == wanted, "category %d is drawn as %s, not %s" % [int(pair[0]), wanted, got])


func test_a_plant_the_form_already_describes_falls_through_to_the_form() -> void:
	# A perennial is planted as a flower bed and the bed *is* the symbol, so the catalogue has nothing
	# to add and the prop decides - which is what every plant did before symbols existed.
	var catalogue: PlantCatalogue = _catalogue()
	var perennial: PlantSpecies = _first_of(catalogue, SpeciesScript.PERENNIAL)
	assert(SymbolsScript.described_for(perennial) == &"", "a perennial adds nothing")
	var form_symbol: StringName = PlanStyleScript.spec_for(perennial.form)["symbol"]
	assert(SymbolsScript.of(perennial, form_symbol) == form_symbol, "so its prop decides")
	assert(form_symbol == SymbolsScript.BED, "and that prop is the bed")


func test_a_plant_with_no_entry_and_a_prop_nobody_knows_are_still_drawn() -> void:
	# Two ways to have nothing to go on, and neither may make a plant vanish from the plan.
	var tree_symbol: StringName = PlanStyleScript.spec_for("res://scenes/props/tree.tscn")["symbol"]
	assert(SymbolsScript.of(null, tree_symbol) == tree_symbol, "no catalogue entry: draw the prop")
	var nobody: StringName = PlanStyleScript.spec_for("res://scenes/props/nothing.tscn")["symbol"]
	assert(SymbolsScript.of(null, nobody) == SymbolsScript.MARKER, "an unknown prop: the marker")
	assert(SymbolsScript.of(null, &"triangle") == SymbolsScript.MARKER, "and an unknown symbol too")


func test_the_plan_s_table_and_this_one_agree() -> void:
	# `PlanStyle` names its symbols as bare words rather than as constants of this module, because the
	# table is read before this script is built. A test is what holds the two together.
	for path: Variant in PlanStyleScript.SYMBOLS.keys():
		var spec: Dictionary = PlanStyleScript.SYMBOLS[path]
		assert(SymbolsScript.is_symbol(spec["symbol"]),
			"%s is drawn as %s, which is not a symbol" % [path, spec["symbol"]])
	assert(SymbolsScript.is_symbol(PlanStyleScript.PLACEHOLDER["symbol"]),
		"and the placeholder prop is a symbol too")
	# Every symbol a species can be is drawn in inks, so there is no symbol the plan would draw in no
	# colour at all. The marker is not in the table: it is the answer for a symbol nobody has, and it
	# comes from the fallback.
	for symbol: StringName in SymbolsScript.NAMES:
		if symbol == SymbolsScript.MARKER:
			continue
		assert(CanvasScript.SYMBOL_INKS.has(symbol), "%s has inks to draw it in" % symbol)
	var fallback: Dictionary = CanvasScript.fallback_inks()
	assert(fallback["fill"] == CanvasScript.GENERIC, "an unknown prop is drawn in the generic colour")
	assert(fallback["edge"] == CanvasScript.GENERIC.darkened(0.4), "with its own line brought down")
	assert(fallback["mark"] == fallback["edge"], "and its marks the same")


# --- the plan and the picture ------------------------------------------------------------------


func test_the_swatch_and_the_plan_reach_the_same_symbol() -> void:
	# One call, two callers. A grid that showed a plant as one shape while the plan drew another would
	# be worse than no picture at all.
	var catalogue: PlantCatalogue = _catalogue()
	for species: PlantSpecies in catalogue.all():
		var form_symbol: StringName = PlanStyleScript.spec_for(species.form)["symbol"]
		assert(PlantIconsScript.symbol_of(species) == SymbolsScript.of(species, form_symbol),
			"%s is one symbol in the grid and another on the plan" % species.id)


func test_a_planted_node_carries_its_symbol() -> void:
	# The plan reads a node, not a catalogue, so the node has to say: without this the symbol would be
	# right in the browser and the plan would still draw the prop's shape.
	var catalogue: PlantCatalogue = _catalogue()
	var yard := Node3D.new()
	add_child(yard)
	var planted: Dictionary = PlacementScript.place(catalogue, SPRUCE, yard, Vector3.ZERO)
	assert(bool(planted["ok"]), "the spruce planted: %s" % String(planted["reason"]))
	var node: Node3D = planted["node"]
	assert(PlanStyleScript.symbol_of(node) == SymbolsScript.CONIFER,
		"the plan reads a conifer off the node: %s" % PlanStyleScript.symbol_of(node))
	assert(PlanStyleScript.footprint_size(node).x == PlanStyleScript.footprint_size(node).y,
		"and draws it round")
	yard.free()


func test_a_spruce_and_a_maple_are_different_pictures() -> void:
	# The failure this whole feature exists to fix, seen in the picture: before it, these two were the
	# same green disc.
	var catalogue: PlantCatalogue = _catalogue()
	var spruce: Image = PlantIconsScript.swatch(catalogue.get_species(SPRUCE))
	var maple: Image = PlantIconsScript.swatch(catalogue.get_species(MAPLE))
	assert(spruce.get_size() == maple.get_size(), "both at the swatch size")
	var differing: int = 0
	for y in maple.get_height():
		for x in maple.get_width():
			if spruce.get_pixel(x, y) != maple.get_pixel(x, y):
				differing += 1
	assert(differing > 40, "they are different pictures: %d pixels" % differing)
	# A needle crown leaves the corners outside it empty where a canopy reaches them.
	var centre: int = int(PlantIconsScript.HALF)
	assert(spruce.get_pixel(centre, 6) != maple.get_pixel(centre, 6),
		"and not just by a pixel or two: the crowns differ where a needle ends")