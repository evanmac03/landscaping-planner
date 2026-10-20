extends Node
## The plant browser: what it shows, what narrows it, and what it says about a plant.
##
## The browser is built in code, so it can be built here without a scene tree - a bare
## `PlantBrowser.new()` plus `bind()` is the whole browser, and every question these tests ask is a
## question a designer asks of the real one.

const BrowserScript := preload("res://scripts/plant_browser.gd")
const CatalogueScript := preload("res://scripts/plant_catalogue.gd")
const SpeciesScript := preload("res://scripts/plant_species.gd")
const PlanStyleScript := preload("res://scripts/plan_style.gd")

const SEED := "res://data/plants/nursery_list.json"

const MAPLE := &"acer-rubrum-autumn-blaze"
const LILAC := &"syringa-vulgaris"
const CHRISTMAS_ROSE := &"helleborus-niger"
const RUDBECKIA := &"rudbeckia-fulgida-goldsturm"


func _catalogue() -> PlantCatalogue:
	var read: Dictionary = CatalogueScript.load_from(SEED)
	assert(bool(read["ok"]), "the shipped list loads: %s" % String(read["reason"]))
	var catalogue: PlantCatalogue = read["catalogue"]
	assert(catalogue.count() > 0, "the shipped list has plants in it")
	return catalogue


func _browser(catalogue: PlantCatalogue = null) -> PlantBrowser:
	var browser: PlantBrowser = BrowserScript.new()
	browser.bind(catalogue if catalogue != null else _catalogue())
	return browser


## A tick box in a pane, found by the words on it rather than by where it sits: the pane is rebuilt
## as the selection changes, and a test that counted children would be a test about the order they
## happen to be made in.
func _tick_box(container: Node, words: String) -> CheckBox:
	for child in container.get_children():
		if child is CheckBox and (child as CheckBox).text == words:
			return child
	return null


# --- the shipped list ---------------------------------------------------------------------


func test_the_shipped_list_is_a_catalogue_a_nursery_would_recognise() -> void:
	var catalogue: PlantCatalogue = _catalogue()
	# Sound, and drawn with scenes that exist: the one check that ties the data to the props, and
	# the check that would catch a list written against a prop that was later renamed.
	assert(catalogue.is_sound(), "the shipped list is sound: %s" % " | ".join(catalogue.problems()))
	assert(catalogue.missing_files().is_empty(),
		"every form in the list is on disk: %s" % " | ".join(catalogue.missing_files()))
	assert(catalogue.source == "starter list", "the list says where it came from")
	# Every category a plant can be in is represented, because a browser that offers a filter which
	# can never find anything is worse than one that does not offer it.
	for kind: int in PlantSpecies.CATEGORY_NAMES.keys():
		assert(
			not catalogue.filter({"category": kind}).is_empty(),
			"the list has a %s" % String(PlantSpecies.CATEGORY_NAMES[kind])
		)


func test_a_plant_that_blooms_across_the_new_year_is_in_the_list() -> void:
	# The reason the bloom set is circular, made a fact about the shipped data rather than about the
	# arithmetic: a filter for January finds a plant whose bloom runs December to February.
	var catalogue: PlantCatalogue = _catalogue()
	var january: Array[PlantSpecies] = catalogue.filter({"bloom_month": 1})
	assert(january.has(catalogue.get_species(CHRISTMAS_ROSE)), "January finds the Christmas rose")
	assert(catalogue.get_species(CHRISTMAS_ROSE).bloom_text() == "December-February",
		"and it says so as one run of months, not two")


# --- what the grid shows ------------------------------------------------------------------


func test_the_browser_shows_every_species_and_the_one_box_narrows_it() -> void:
	var catalogue: PlantCatalogue = _catalogue()
	var browser: PlantBrowser = _browser(catalogue)
	assert(browser.row_titles().size() == catalogue.count(), "unfiltered, it shows the lot")
	assert(browser.status_text() == "%d species" % catalogue.count(), "and says how many")

	browser.set_query_text("acer")
	assert(browser.row_titles().size() == 1, "one box, one word: %s" % " | ".join(browser.row_titles()))
	assert(browser.status_text() == "1 of %d species" % catalogue.count(), "and says how many it found")

	browser.set_query_text("")
	assert(browser.row_titles().size() == catalogue.count(), "clearing it puts them back")
	browser.free()


func test_the_filters_narrow_the_grid_and_the_chips_say_how_much_they_leave() -> void:
	var catalogue: PlantCatalogue = _catalogue()
	var browser: PlantBrowser = _browser(catalogue)
	# The chips are made from the catalogue, so a tag cannot be on the list of one and missing here.
	assert(browser._chips.size() == catalogue.tag_names().size(), "a chip for every tag there is")
	for tag_name: String in browser._chips.keys():
		var chip: CheckBox = browser._chips[tag_name]
		assert(
			chip.text == "%s (%d)" % [tag_name, int(catalogue.tag_counts()[tag_name])],
			"the %s chip says how many plants carry it" % tag_name
		)

	# One chip, and the grid is the plants that carry it.
	assert(browser.set_tag_filter("shade", true), "the shade chip can be ticked")
	var shaded: Array[PlantSpecies] = browser.results()
	assert(shaded.size() == catalogue.tagged("shade").size(), "the chip finds the tagged plants")
	for plant: PlantSpecies in shaded:
		assert(plant.tags.has("shade"), "%s really carries the tag" % plant.id)

	# And a second chip is an "and", not an "or".
	assert(browser.set_tag_filter("shade", false), "and unticked again")
	assert(browser.set_tag_filter("native", true), "the native chip can be ticked")
	var natives: Array[PlantSpecies] = browser.results()
	assert(natives.size() == catalogue.tagged("native").size(), "and finds its own plants")
	for plant: PlantSpecies in natives:
		assert(plant.tags.has("native"), "%s carries native" % plant.id)
	assert(not browser.set_tag_filter("not-a-tag", true), "a tag the catalogue does not have is refused")
	browser.free()


func test_a_zone_and_a_month_and_a_light_are_questions_the_filter_answers() -> void:
	var catalogue: PlantCatalogue = _catalogue()
	var browser: PlantBrowser = _browser(catalogue)

	# "What will live in zone 5 in full sun?" - both of those at once.
	assert(browser.set_zone_filter(5), "the zone can be chosen by its number")
	assert(browser.set_light_filter(PlantSpecies.FULL_SUN), "and the light by what it means")
	var found: Array[PlantSpecies] = browser.results()
	assert(not found.is_empty(), "there is something for a zone 5 sunny bed")
	for plant: PlantSpecies in found:
		assert(plant.hardy_in(5), "%s is hardy in zone 5" % plant.id)
		assert(plant.takes_sun(PlantSpecies.FULL_SUN), "%s takes full sun" % plant.id)

	# And a month, which is the one criterion a plant can meet across the new year.
	assert(browser.set_zone_filter(PlantBrowser.ANY), "the zone filter can be put back to any")
	assert(browser.set_light_filter(PlantBrowser.ANY), "and so can the light")
	assert(browser.results().size() == catalogue.count(), "and putting them back shows everything again")
	assert(browser.set_bloom_filter(1), "and a month can be asked for by its number")
	var january: Array[PlantSpecies] = browser.results()
	assert(not january.is_empty(), "something blooms in January")
	for plant: PlantSpecies in january:
		assert(plant.blooms_in(1), "%s blooms in January" % plant.id)
	assert(january.has(catalogue.get_species(CHRISTMAS_ROSE)), "including the one that crosses the year")
	assert(not browser.set_bloom_filter(13), "and a month there is no such thing as is refused")
	browser.free()


func test_the_sort_choices_are_the_orders_a_designer_asks_for() -> void:
	var catalogue: PlantCatalogue = _catalogue()
	var browser: PlantBrowser = _browser(catalogue)

	assert(browser.set_sort("height", false), "shortest first is a sort")
	assert(browser.results()[0].id == &"thymus-serpyllum", "which is the thyme")

	assert(browser.set_sort("height", true), "and tallest first is the other end of it")
	var tallest: Array[PlantSpecies] = browser.results()
	assert(tallest[0].height_cm == 1800, "which is the birch")
	assert(tallest[0].height_cm > tallest[1].height_cm, "and it is in order")

	assert(browser.set_sort("bloom"), "and by when it blooms")
	var earliest: Array[PlantSpecies] = browser.results()
	assert(earliest[0].blooms_in(1), "which puts the midwinter bloomer first")

	# The table of orders is the one the drop-down's labels come from, so a row cannot say one thing
	# and sort by another.
	assert(BrowserScript.sort_labels().size() == BrowserScript.sort_orders().size(), "one label per order")
	assert(browser._sort_option.item_count == BrowserScript.sort_orders().size(), "and a row per order")
	assert(not browser.set_sort("by the colour of its leaves"), "an order nobody has is refused")
	browser.free()


func test_a_plant_the_filter_excludes_is_not_described_in_the_detail_pane() -> void:
	# The one thing the pane must not do: describe a plant the grid is not showing.
	var browser: PlantBrowser = _browser()
	assert(browser.select(MAPLE), "the maple can be chosen")
	assert(browser.selected_species().id == MAPLE, "and it is the one in hand")
	assert(browser.detail_text().contains("Acer rubrum"))

	browser.set_query_text("lilac")
	assert(browser.selected_species() == null, "a filter that drops it drops the selection too")
	assert(browser.detail_text().begins_with("Nothing chosen"), "and the pane says so")
	assert(browser.row_titles().size() == 1, "the grid is the lilac")
	browser.free()


# --- the detail pane ----------------------------------------------------------------------


func test_the_detail_pane_says_what_a_nursery_label_says() -> void:
	var browser: PlantBrowser = _browser()
	browser.select(MAPLE)
	var text: String = browser.detail_text()
	for wanted: String in [
		"Acer rubrum 'Autumn Blaze' - Red maple", "Type:      Tree", "Hardy:     zones 3 to 9",
		"Size:      15.0 m tall, 9.0 m across", "Light:     full sun, part shade",
		"Water:     medium water", "Bloom:     March-April", "shade tree", "wants room for the crown",
	]:
		assert(text.contains(wanted), "the label says %s" % wanted)
	# A plant grown for its foliage says so rather than showing an empty bloom line.
	browser.select(&"buxus-sempervirens")
	assert(browser.detail_text().contains("grown for its foliage"), "an evergreen says it does not bloom")
	browser.free()


func test_the_drawn_as_line_names_the_symbol_the_plan_uses() -> void:
	var browser: PlantBrowser = _browser()
	browser.select(MAPLE)
	assert(browser.detail_text().contains("tree.tscn (a tree symbol)"),
		"a tree says it is drawn as the tree prop")
	browser.select(&"rudbeckia-fulgida-goldsturm")
	assert(browser.detail_text().contains("flower_bed.tscn (a planted bed)"),
		"a perennial drawn as a bed says so")
	for plant: PlantSpecies in browser.catalogue.all():
		assert(not browser._drawn_as(plant).is_empty(), "%s says what it is drawn as" % plant.id)
	browser.free()


# --- collections --------------------------------------------------------------------------


func test_a_collection_is_a_persons_own_and_the_browser_can_put_a_plant_in_it() -> void:
	var browser: PlantBrowser = _browser()
	assert(browser.collection_names().is_empty(), "a new list has no collections")
	assert(browser._collections_box.get_child_count() > 0, "and the pane says so rather than being blank")

	browser._new_collection_name.text = "front bed"
	browser._on_make_collection()
	assert(browser.collection_names() == ["front bed"], "the collection is made")
	assert(browser._new_collection_name.text == "", "and the box it was typed in is cleared")

	browser.select(MAPLE)
	browser._on_collection_toggled(true, "front bed")
	assert(browser.catalogue.collections_of(MAPLE) == ["front bed"], "the maple is in it")
	# And the box in the pane is ticked, because the pane is rebuilt from the catalogue rather than
	# remembering what was clicked.
	browser.select(LILAC)
	browser.select(MAPLE)
	var box: CheckBox = _tick_box(browser._collections_box, "front bed")
	assert(box != null, "there is a box for the collection")
	assert(box.button_pressed, "and the maple is in it")

	browser._on_collection_toggled(false, "front bed")
	assert(browser.catalogue.collections_of(MAPLE).is_empty(), "and out again")
	# A collection nobody is in is refused a name that is already taken.
	assert(not browser.catalogue.create_collection("front bed"), "a name is not taken twice")
	assert(not browser.create_collection_named(""), "and a collection needs a name")
	browser.free()


func test_a_collection_narrows_the_grid_without_replacing_the_other_filters() -> void:
	var catalogue: PlantCatalogue = _catalogue()
	var browser: PlantBrowser = _browser(catalogue)
	browser.catalogue.create_collection("sunny")
	browser.catalogue.add_to_collection("sunny", MAPLE)
	browser.catalogue.add_to_collection("sunny", LILAC)

	assert(browser.set_collection_filter("sunny"), "the collection can be chosen by name")
	assert(browser.results().size() == 2, "and it is the list")

	# "Which of the trees in this collection" is the useful question, so the two narrow together.
	assert(browser.set_category_filter(PlantSpecies.TREE), "and a type can be asked for on top of it")
	var maples: Array[PlantSpecies] = browser.results()
	assert(maples.size() == 1, "the collection and the type together: %d" % maples.size())
	assert(maples[0].id == MAPLE, "which is the maple")
	assert(not browser.set_collection_filter("not-a-collection"), "a collection nobody made is refused")
	assert(browser.set_collection_filter(""), "and the filter can be put back to every plant")
	assert(browser.results().size() == catalogue.filter({"category": PlantSpecies.TREE}).size(),
		"which is every tree again")
	browser.free()


# --- the pictures -------------------------------------------------------------------------


func test_every_species_in_the_grid_has_a_picture_and_they_share_what_they_should() -> void:
	# The browser asks `PlantIcons` for the picture, which is what stops the grid and the palette's
	# plants section from showing a plant two different ways. A species with no photograph is not a
	# species with no picture: it is drawn as the symbol the plan would draw it as.
	var catalogue: PlantCatalogue = _catalogue()
	var browser: PlantBrowser = _browser(catalogue)
	var tree: Texture2D = browser.icon_for(MAPLE)
	assert(tree != null, "a tree with no thumbnail still has a picture")
	assert(tree == PlantIcons.texture_for(catalogue.get_species(MAPLE)), "and it is the shared swatch")

	var seen: Dictionary = {}
	for plant: PlantSpecies in catalogue.all():
		var picture: Texture2D = browser.icon_for(plant.id)
		assert(picture != null, "%s has a picture" % plant.id)
		var key: String = "%s|%d" % [plant.form, plant.category]
		if seen.has(key):
			assert(seen[key] == picture, "%s shares the swatch of its form" % plant.id)
		else:
			seen[key] = picture
	assert(seen.size() < catalogue.count(), "fewer pictures than species: %d" % seen.size())
	# A tree and a bed are not the same shape, which is the whole reason the picture is drawn from the
	# plan's own table rather than being one generic marker for everything.
	assert(browser.icon_for(MAPLE) != browser.icon_for(RUDBECKIA),
		"a tree and a bed are different symbols")
	# The tint is the species' bloom colour, so two trees are still told apart in the grid.
	assert(PlantIcons.tint(catalogue.get_species(MAPLE)) != Color.WHITE, "a flowering tree is tinted")
	assert(PlantIcons.tint(catalogue.get_species(&"buxus-sempervirens")) == Color.WHITE,
		"a foliage plant is not")
	browser.free()


# --- placing ------------------------------------------------------------------------------


func test_choosing_a_plant_says_which_one_and_placing_asks_for_it() -> void:
	var browser: PlantBrowser = _browser()
	var chosen: Array[StringName] = []
	var changed: Array[StringName] = []
	browser.plant_chosen.connect(func(species_id: StringName) -> void: chosen.append(species_id))
	browser.selection_changed.connect(func(species_id: StringName) -> void: changed.append(species_id))

	assert(not browser.place_selected(), "nothing is chosen yet")
	assert(chosen.is_empty(), "so nothing is asked for")
	assert(browser.status_text() == "choose a plant first", "and the browser says so")

	browser.select(MAPLE)
	assert(changed == [MAPLE], "choosing one says which")
	assert(browser.place_selected(), "and placing it asks for it")
	assert(chosen == [MAPLE], "by name")
	assert(browser.selected_id() == MAPLE, "and it stays chosen, so a second click plants a second one")
	browser.free()


func test_a_browser_with_no_list_says_so_rather_than_failing() -> void:
	# What the menu offers before any catalogue has been loaded.
	var browser: PlantBrowser = BrowserScript.new()
	browser.bind(null)
	assert(browser.row_titles().is_empty(), "nothing to show")
	assert(browser.results().is_empty(), "and nothing found")
	assert(browser.status_text() == "no plant list open", "and it says why")
	assert(browser.icon_for(MAPLE) == null, "and has no picture to offer")
	assert(browser.collection_names().is_empty(), "and no collections")
	assert(not browser.place_selected(), "and nothing to place")
	browser.free()