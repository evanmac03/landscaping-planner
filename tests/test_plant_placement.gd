extends Node
## Planting a catalogue species into the design, and the planting list that comes out of it.
##
## The yard here is a bare `Node3D`: planting needs somewhere to put the plant and nothing else, and
## a test that needed the whole scene would be a test about the scene.

const CatalogueScript := preload("res://scripts/plant_catalogue.gd")
const SpeciesScript := preload("res://scripts/plant_species.gd")
const PlacementScript := preload("res://scripts/plant_placement.gd")
const PlanStyleScript := preload("res://scripts/plan_style.gd")

const SEED := "res://data/plants/nursery_list.json"

const MAPLE := &"acer-rubrum-autumn-blaze"
const LILAC := &"syringa-vulgaris"
const RUDBECKIA := &"rudbeckia-fulgida-goldsturm"


func _catalogue() -> PlantCatalogue:
	var read: Dictionary = CatalogueScript.load_from(SEED)
	assert(bool(read["ok"]), "the shipped list loads: %s" % String(read["reason"]))
	return read["catalogue"]


func _yard() -> Node3D:
	var yard := Node3D.new()
	yard.name = "Yard"
	return yard


# --- planting one -------------------------------------------------------------------------


func test_planting_a_species_puts_it_in_the_yard_at_the_size_the_catalogue_says() -> void:
	var catalogue: PlantCatalogue = _catalogue()
	var yard: Node3D = _yard()
	var planted: Dictionary = PlacementScript.place(catalogue, MAPLE, yard, Vector3(2.0, 0.0, 3.0))

	assert(bool(planted["ok"]), "the maple is planted: %s" % String(planted["reason"]))
	var tree: Node3D = planted["node"]
	assert(tree != null, "and there is something there")

	# The whole point of the link: a red maple spreads 9 m and the tree prop is 3.7 m across, so
	# what stands in the yard is 9 m across - which is what the plan, the 3D view and the planting
	# list all read.
	var base: float = float(PlanStyleScript.spec_for(tree.scene_file_path)["size"].x)
	assert(is_equal_approx(float(planted["scale"]), 9.0 / base), "planted at spread over base")
	assert(is_equal_approx(PlanStyleScript.footprint_size(tree).x, 9.0),
		"the plan's own footprint is the catalogue's spread: %.3f" % (
			PlanStyleScript.footprint_size(tree).x
		))
	assert(is_equal_approx(PlanStyleScript.footprint_radius(tree), 4.5), "and the radius is half of it")
	assert(tree.position.is_equal_approx(Vector3(2.0, 0.0, 3.0)), "and it stands where it was put")
	yard.free()


func test_a_species_drawn_as_a_bed_is_sized_against_the_bed() -> void:
	# A perennial is not a small shrub: it is drawn as a planted bed, and it is the bed's own 2.6 m
	# footprint the species' 0.9 m spread is measured against.
	var catalogue: PlantCatalogue = _catalogue()
	var yard: Node3D = _yard()
	var planted: Dictionary = PlacementScript.place(catalogue, RUDBECKIA, yard, Vector3.ZERO)
	var bed: Node3D = planted["node"]
	assert(is_equal_approx(PlanStyleScript.footprint_size(bed).x, 0.45), "the bed is 0.45 m across")
	assert(PlanStyleScript.footprint_size(bed).y < PlanStyleScript.footprint_size(bed).x,
		"and oblong, as the plan draws a bed")
	yard.free()


func test_a_planted_plant_is_one_object_in_both_views() -> void:
	# Nothing is registered twice: the group is what the view controller picks in and the subtree is
	# what the plan draws, and a plant that had one and not the other would be a plant you can see
	# and not touch, or touch and not see.
	var catalogue: PlantCatalogue = _catalogue()
	var yard: Node3D = _yard()
	var planted: Dictionary = PlacementScript.place(catalogue, MAPLE, yard, Vector3.ZERO)
	var tree: Node3D = planted["node"]
	assert(tree.is_in_group(Yard.PLACEABLE_GROUP), "it is a design object the planner can select")
	assert(tree.get_parent().name == PlacementScript.PLANTS, "and it stands in the planting subtree")
	assert(tree.get_parent().get_parent() == yard, "which is the yard's")
	assert(PlacementScript.planted(yard).has(tree), "and the yard can list it")
	assert(PlacementScript.species_of(tree) == MAPLE, "and it knows what species it is")
	assert(int(tree.get_meta(PlacementScript.HEIGHT_META)) == 1500, "and how tall that species gets")
	yard.free()


func test_a_yard_with_no_planting_subtree_grows_one() -> void:
	var catalogue: PlantCatalogue = _catalogue()
	var yard: Node3D = _yard()
	assert(yard.get_node_or_null("Plants") == null, "there is nothing there yet")
	var planted: Dictionary = PlacementScript.place(catalogue, LILAC, yard, Vector3.ZERO)
	assert(bool(planted["ok"]), "the lilac is still planted")
	assert(yard.get_node_or_null("Plants") != null, "and the subtree was made for it")
	assert(PlacementScript.planted(yard).size() == 1, "with one plant in it")
	yard.free()


func test_two_of_one_species_are_two_plants_with_their_own_names() -> void:
	var catalogue: PlantCatalogue = _catalogue()
	var yard: Node3D = _yard()
	var first: Node3D = PlacementScript.place(catalogue, MAPLE, yard, Vector3(1.0, 0.0, 0.0))["node"]
	var second: Node3D = PlacementScript.place(catalogue, MAPLE, yard, Vector3(4.0, 0.0, 0.0))["node"]
	assert(first.name != second.name, "they are named apart: %s and %s" % [first.name, second.name])
	assert(String(first.name) == String(MAPLE), "the first one keeps the plain name")
	assert(PlacementScript.planted(yard).size() == 2, "and both are standing")
	# A name is made apart before it is added, so the two are siblings rather than one renamed by
	# Godot on the way in.
	assert(second.get_parent() == first.get_parent(), "and they are siblings")
	assert(PlacementScript.species_of(second) == MAPLE, "and both are the same species")
	yard.free()


# --- when it cannot be done ---------------------------------------------------------------


func test_planting_something_the_list_does_not_have_is_refused_naming_it() -> void:
	var catalogue: PlantCatalogue = _catalogue()
	var yard: Node3D = _yard()
	var planted: Dictionary = PlacementScript.place(catalogue, &"not-a-plant", yard, Vector3.ZERO)
	assert(not bool(planted["ok"]), "it is refused")
	assert(String(planted["reason"]).contains("not-a-plant"), "and the reason names it")
	assert(PlacementScript.planted(yard).is_empty(), "and nothing was put anywhere")
	yard.free()


func test_a_species_whose_scene_is_missing_is_refused_rather_than_silent() -> void:
	# A catalogue entry can name a prop that was renamed or never shipped. A click that does nothing
	# at all is the failure mode this refusal exists to prevent.
	var catalogue: PlantCatalogue = _catalogue()
	var orphan: PlantSpecies = PlantSpecies.make(&"orphan", "Nowhereus plantii", "Nowhere plant", 100, 100)
	orphan.form = "res://scenes/props/not_shipped.tscn"
	assert(catalogue.add(orphan), "the entry is in the list")
	var yard: Node3D = _yard()
	var planted: Dictionary = PlacementScript.place(catalogue, &"orphan", yard, Vector3.ZERO)
	assert(not bool(planted["ok"]), "planting it is refused")
	assert(String(planted["reason"]).contains("not_shipped.tscn"), "and the reason names the scene")
	assert(PlacementScript.planted(yard).is_empty(), "and the yard is untouched")
	yard.free()


func test_planting_with_nowhere_to_plant_is_refused_rather_than_a_crash() -> void:
	var catalogue: PlantCatalogue = _catalogue()
	var planted: Dictionary = PlacementScript.place(catalogue, MAPLE, null, Vector3.ZERO)
	assert(not bool(planted["ok"]), "a yard that is not there is a refusal")
	var yard: Node3D = _yard()
	planted = PlacementScript.place(null, MAPLE, yard, Vector3.ZERO)
	assert(not bool(planted["ok"]), "and so is a catalogue that is not there")
	assert(PlacementScript.planted(null).is_empty(), "and a yard that is not there has no plants")
	assert(PlacementScript.planted(yard).is_empty(), "and nothing was put in the yard that is there")
	yard.free()


# --- the planting list --------------------------------------------------------------------


func test_the_planting_list_counts_what_is_standing_and_names_what_it_cannot() -> void:
	var catalogue: PlantCatalogue = _catalogue()
	var yard: Node3D = _yard()
	PlacementScript.place(catalogue, MAPLE, yard, Vector3(0.0, 0.0, 0.0))
	PlacementScript.place(catalogue, MAPLE, yard, Vector3(4.0, 0.0, 0.0))
	PlacementScript.place(catalogue, LILAC, yard, Vector3(0.0, 0.0, 4.0))
	# A plant somebody dropped into the yard by hand, which no catalogue can name. It is counted
	# and named separately rather than dropped: a plant on the plan the list hides is the one thing
	# a planting list must never do.
	var stray := Node3D.new()
	stray.name = "Stray"
	PlacementScript.plants_node(yard).add_child(stray)

	var rows: Array[Dictionary] = PlacementScript.schedule(catalogue, yard)
	var named: Array[String] = []
	for row: Dictionary in rows:
		named.append(String(row["botanical_name"]))
	assert(named == ["Acer rubrum", "Syringa vulgaris", "no species recorded"],
		"one row per species, in botanical order, and the stray owned up to: %s" % " | ".join(named))
	assert(int(rows[0]["count"]) == 2, "two maples")
	assert(int(rows[1]["count"]) == 1, "one lilac")
	assert(int(rows[2]["count"]) == 1, "and one nobody can name")
	# The row carries what a schedule has to print: the name, how many, and how big the plant gets.
	assert(int(rows[0]["spread_cm"]) == 900, "the row carries the spread")
	assert(String(rows[0]["category_name"]) == "Tree", "and the category")
	yard.free()


func test_the_planting_list_is_written_the_way_a_planting_plan_writes_it() -> void:
	var catalogue: PlantCatalogue = _catalogue()
	var yard: Node3D = _yard()
	assert(PlacementScript.schedule_text(catalogue, yard) == "", "nothing planted, nothing written")
	PlacementScript.place(catalogue, MAPLE, yard, Vector3.ZERO)
	PlacementScript.place(catalogue, MAPLE, yard, Vector3(5.0, 0.0, 0.0))
	PlacementScript.place(catalogue, LILAC, yard, Vector3(0.0, 0.0, 5.0))
	var text: String = PlacementScript.schedule_text(catalogue, yard)
	assert(text.contains("2 x Acer rubrum 'Autumn Blaze'"), "the cultivar is quoted: %s" % text)
	assert(text.contains("1 x Syringa vulgaris"), "and a species with no cultivar is not")
	assert(text.split("\n").size() == 2, "one line per species")
	yard.free()


func test_a_named_plant_is_one_the_catalogue_can_still_explain() -> void:
	# The link has to survive the catalogue being replaced: a plant in the yard whose species is no
	# longer in the list is counted as unidentified rather than being given a name nobody can check.
	var catalogue: PlantCatalogue = _catalogue()
	var yard: Node3D = _yard()
	PlacementScript.place(catalogue, MAPLE, yard, Vector3.ZERO)
	assert(PlacementScript.schedule(catalogue, yard).size() == 1, "it is on the list")
	catalogue.erase(MAPLE)
	var rows: Array[Dictionary] = PlacementScript.schedule(catalogue, yard)
	assert(rows.size() == 1, "still one row")
	assert(String(rows[0]["botanical_name"]) == "no species recorded",
		"but the list no longer claims to know what it is")
	assert(PlacementScript.species_of(PlacementScript.planted(yard)[0]) == MAPLE,
		"though the plant itself still remembers, so the list can be put back")
	yard.free()