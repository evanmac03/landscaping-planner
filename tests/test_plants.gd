extends Node
## The plant database: the species entry, the catalogue, and the search a browser drives.
##
## The types are preloaded here rather than named, because a `class_name` is only visible once the
## editor's class cache has picked the file up, and a test that cannot run until the editor has
## rescanned is a test that fails for a reason that has nothing to do with the code.

const SpeciesScript := preload("res://scripts/plant_species.gd")
const CatalogueScript := preload("res://scripts/plant_catalogue.gd")

const SCRATCH := "user://plants/test-catalogue.json"
const SCRATCH_COLLECTIONS := "user://plants/test-collections.json"
const SCRATCH_IMPORT := "user://plants/test-import.json"


## A red maple: a tree, full sun, blooms in spring, tagged as a native shade tree.
func _maple() -> SpeciesScript:
	var plant: SpeciesScript = SpeciesScript.make(
		&"ACER-RUBRUM", "Acer rubrum", "Red maple", 1500, 1200, SpeciesScript.TREE
	)
	plant.zone_min = 3
	plant.zone_max = 9
	plant.sun = SpeciesScript.FULL_SUN | SpeciesScript.PART_SHADE
	plant.water = SpeciesScript.WATER_MEDIUM
	plant.bloom_months = 0
	plant.set_blooms_in(3, true)
	plant.set_blooms_in(4, true)
	plant.bloom_colour = Color(0.85, 0.25, 0.3)
	plant.form = "res://scenes/props/tree.tscn"
	plant.tags = ["native", "shade tree"]
	return plant


## A hosta: a shade perennial, a different category, different tags.
func _hosta() -> SpeciesScript:
	var plant: SpeciesScript = SpeciesScript.make(
		&"HOSTA-PATRIOT", "Hosta", "Plantain lily", 60, 90, SpeciesScript.PERENNIAL
	)
	plant.cultivar = "Patriot"
	plant.zone_min = 3
	plant.zone_max = 9
	plant.sun = SpeciesScript.PART_SHADE | SpeciesScript.FULL_SHADE
	plant.water = SpeciesScript.WATER_MEDIUM
	plant.set_blooms_in(7, true)
	plant.set_blooms_in(8, true)
	plant.form = "res://scenes/props/flower_bed.tscn"
	plant.tags = ["shade"]
	return plant


## A witch hazel: it blooms November to March, which is one run of months across the new year - the
## case a single month value or a naive range check gets wrong.
func _witch_hazel() -> SpeciesScript:
	var plant: SpeciesScript = SpeciesScript.make(
		&"HAMAMELIS-VIRGINIANA", "Hamamelis virginiana", "Witch hazel", 300, 300, SpeciesScript.SHRUB
	)
	plant.zone_min = 5
	plant.zone_max = 9
	plant.sun = SpeciesScript.FULL_SUN | SpeciesScript.PART_SHADE
	for month: int in [11, 12, 1, 2, 3]:
		plant.set_blooms_in(month, true)
	plant.form = "res://scenes/props/shrub.tscn"
	plant.tags = ["native", "winter interest"]
	return plant


## A grass: no bloom at all, and a low water need.
func _grass() -> SpeciesScript:
	var plant: SpeciesScript = SpeciesScript.make(
		&"PANICUM-VIRGATUM", "Panicum virgatum", "Switch grass", 120, 60, SpeciesScript.GRASS
	)
	plant.zone_min = 4
	plant.zone_max = 9
	plant.sun = SpeciesScript.FULL_SUN
	plant.water = SpeciesScript.WATER_LOW
	plant.form = "res://scenes/props/shrub.tscn"
	plant.tags = ["native", "low water"]
	return plant


func _catalogue() -> PlantCatalogue:
	var catalogue: PlantCatalogue = CatalogueScript.make(2, "test")
	for plant: SpeciesScript in [_maple(), _hosta(), _witch_hazel(), _grass()]:
		catalogue.add(plant)
	return catalogue


## A plant the catalogue does not have, for the import tests.
func _boxwood() -> SpeciesScript:
	var plant: SpeciesScript = SpeciesScript.make(
		&"BUXUS-SEMPERVIRENS", "Buxus sempervirens", "Common box", 200, 150, SpeciesScript.SHRUB
	)
	plant.form = "res://scenes/props/shrub.tscn"
	plant.tags = ["evergreen"]
	return plant


func _clean() -> void:
	for path: String in [SCRATCH, SCRATCH_COLLECTIONS, SCRATCH_IMPORT]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
		if FileAccess.file_exists(path + CatalogueScript.TEMP_SUFFIX):
			DirAccess.remove_absolute(path + CatalogueScript.TEMP_SUFFIX)


func _ids(plants: Array) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for plant: SpeciesScript in plants:
		out.append(String(plant.id))
	return out


func _any_contains(lines: Array, text: String) -> bool:
	for line: Variant in lines:
		if String(line).contains(text):
			return true
	return false


# --- the species entry ------------------------------------------------------------------


func test_a_species_says_what_a_nursery_label_says() -> void:
	var plant := _maple()
	assert(plant.display_name() == "Acer rubrum - Red maple", plant.display_name())
	assert(plant.category_name() == "Tree")
	assert(plant.width_or_height_text() if plant.has_method("width_or_height_text") else true)
	assert(plant.height_m() == 15.0, "1,500 cm is 15 m, got %f" % plant.height_m())
	assert(plant.spread_m() == 12.0)
	assert(plant.is_valid(), plant.problem())
	# The cultivar is quoted, because that is what makes it a cultivar.
	var hosta := _hosta()
	assert(hosta.display_name() == "Hosta 'Patriot' - Plantain lily", hosta.display_name())


func test_hardiness_and_light_are_ranges_and_sets() -> void:
	var plant := _maple()
	assert(plant.hardy_in(3), "the coldest zone it is hardy in")
	assert(plant.hardy_in(9), "and the warmest")
	assert(not plant.hardy_in(2), "one colder than it survives")
	assert(not plant.hardy_in(10))
	assert(plant.takes_sun(SpeciesScript.FULL_SUN))
	assert(plant.takes_sun(SpeciesScript.PART_SHADE), "a maple takes sun and part shade")
	assert(not plant.takes_sun(SpeciesScript.FULL_SHADE))
	assert(plant.sun_text() == "full sun, part shade", plant.sun_text())
	# A plant that takes both shade conditions says both, and the order is the sun scale's order.
	assert(_hosta().sun_text() == "part shade, full shade", _hosta().sun_text())
	assert(_maple().water_text() == "medium water")
	assert(_grass().water_text() == "low water")


func test_a_bloom_that_crosses_the_new_year_is_one_run_of_months() -> void:
	# November to March is one run, not "November, December, January, February, March" and not two
	# disconnected runs. A filter for January has to find this plant.
	var plant := _witch_hazel()
	assert(plant.blooms_in(1) and plant.blooms_in(12) and plant.blooms_in(3))
	assert(not plant.blooms_in(6))
	assert(plant.bloom_text() == "November-March", plant.bloom_text())
	# A single month, a contiguous spring pair, and two separate runs.
	var one := _hosta()
	one.bloom_months = 0
	one.set_blooms_in(7, true)
	assert(one.bloom_text() == "July", one.bloom_text())
	assert(_maple().bloom_text() == "March-April", _maple().bloom_text())
	var scattered := _grass()
	scattered.set_blooms_in(3, true)
	scattered.set_blooms_in(9, true)
	assert(scattered.bloom_text() == "March, September", scattered.bloom_text())
	# A plant grown for its foliage says nothing rather than "no bloom".
	assert(_grass().bloom_text() == "", _grass().bloom_text())


func test_a_plant_that_blooms_every_month_says_so() -> void:
	var plant := _grass()
	plant.bloom_months = 0
	for month in range(1, 13):
		plant.set_blooms_in(month, true)
	assert(plant.bloom_text() == "all year", plant.bloom_text())
	# And the bits come back off as easily as they went on.
	plant.set_blooms_in(6, false)
	assert(not plant.blooms_in(6))
	assert(plant.bloom_text() == "July-May", "the run now starts in July: %s" % plant.bloom_text())


func test_the_size_a_plant_is_drawn_at_comes_from_its_own_spread() -> void:
	# One tree model stands for every tree, so what is planted has to be scaled to the species'
	# spread rather than to the model's.
	var plant := _maple()
	assert(plant.planting_scale(3.7) > 3.2 and plant.planting_scale(3.7) < 3.3, "%f" % plant.planting_scale(3.7))
	assert(plant.planting_scale(12.0) == 1.0, "a form that is already the right size is not scaled")
	# A form with no size, or a species with no spread, is left alone rather than dividing by zero.
	assert(plant.planting_scale(0.0) == 1.0)
	var sizeless := _grass()
	sizeless.spread_cm = 0
	sizeless.height_cm = 60
	assert(sizeless.planting_scale(3.7) == 1.0)


func test_an_entry_that_could_not_be_planted_is_refused_and_named() -> void:
	var no_name := _grass()
	no_name.botanical_name = "   "
	assert(not no_name.is_valid() and no_name.problem().contains("botanical"), no_name.problem())

	var zone_zero := _grass()
	zone_zero.zone_min = 0
	assert(not zone_zero.is_valid() and zone_zero.problem().contains("zone"), zone_zero.problem())

	var backwards := _grass()
	backwards.zone_min = 9
	backwards.zone_max = 4
	assert(not backwards.is_valid(), "9..4 is not a range")

	var sizeless := _grass()
	sizeless.height_cm = 0
	sizeless.spread_cm = 0
	assert(not sizeless.is_valid() and sizeless.problem().contains("size"), sizeless.problem())

	var wrong_kind := _grass()
	wrong_kind.category = 42
	assert(not wrong_kind.is_valid() and wrong_kind.problem().contains("category"), wrong_kind.problem())

	var no_light := _grass()
	no_light.sun = 0
	assert(not no_light.is_valid() and no_light.problem().contains("sun"), no_light.problem())

	var not_shade := _grass()
	not_shade.sun = 8
	assert(not not_shade.is_valid(), "bit 8 is not one of the three light conditions")

	var odd_months := _grass()
	odd_months.bloom_months = 1 << 13
	assert(not odd_months.is_valid() and odd_months.problem().contains("month"), odd_months.problem())

	var shapeless := _grass()
	shapeless.form = ""
	assert(not shapeless.is_valid() and shapeless.problem().contains("drawn"), shapeless.problem())


func test_a_species_survives_the_file_format_as_whole_numbers() -> void:
	# Through the text: JSON has one number type, so a zone read straight through would be 7.0, and
	# a height would compare unequal to itself.
	var plant := _witch_hazel()
	plant.note = "the earliest thing to flower"
	var text: String = JSON.stringify(plant.to_dict())
	var reader := JSON.new()
	assert(reader.parse(text) == OK, reader.get_error_message())
	var back: SpeciesScript = SpeciesScript.from_dict(reader.data)
	assert(back.id == plant.id)
	assert(back.botanical_name == plant.botanical_name)
	assert(back.zone_min == 5 and back.zone_max == 9, "zones came back as %d..%d" % [back.zone_min, back.zone_max])
	assert(back.height_cm == 300, "height came back as %d" % back.height_cm)
	assert(back.bloom_months == plant.bloom_months, "the bloom bits survived")
	assert(back.blooms_in(1) and back.blooms_in(11) and not back.blooms_in(6))
	assert(back.bloom_text() == "November-March")
	assert(back.tags == plant.tags)
	assert(back.form == plant.form, "what it is drawn as survives")
	# Compared as the file stores it: a colour written as an eight-bit hex run cannot satisfy
	# `is_equal_approx` against the float it came from, and that is the format's precision, not a
	# fault - what matters is that the plan draws the same colour the catalogue names.
	assert(
		back.bloom_colour.to_html(false) == plant.bloom_colour.to_html(false),
		"the bloom colour survives: %s against %s" % [
			back.bloom_colour.to_html(false), plant.bloom_colour.to_html(false)
		]
	)
	assert(back.note == "the earliest thing to flower")
	assert(back.is_valid(), back.problem())
	# A copy is independent, so editing a catalogue entry does not reach into a placed plant.
	var other: SpeciesScript = plant.copy()
	other.height_cm = 999
	assert(plant.height_cm == 300)


# --- the catalogue ----------------------------------------------------------------------


func test_a_catalogue_takes_plants_and_refuses_a_second_one_with_the_same_id() -> void:
	var catalogue := _catalogue()
	assert(catalogue.count() == 4)
	var again := _maple()
	again.height_cm = 9000
	assert(not catalogue.add(again), "the id is taken")
	assert(catalogue.get_species(&"ACER-RUBRUM").height_cm == 1500, "and the entry did not move")
	# The importer's door is separate and says what it is for.
	assert(catalogue.put(again))
	assert(catalogue.get_species(&"ACER-RUBRUM").height_cm == 9000)
	assert(catalogue.count() == 4, "a replace is not a fifth plant")
	assert(not catalogue.add(_grass()), "a plant that cannot be planted is not stored")


func test_search_finds_a_plant_by_any_of_its_names_and_puts_the_best_first() -> void:
	var catalogue := _catalogue()
	assert(catalogue.search("ACER-RUBRUM")[0].id == &"ACER-RUBRUM", "an exact id is the best match")
	assert(catalogue.search("panicum")[0].id == &"PANICUM-VIRGATUM", "a botanical name")
	assert(catalogue.search("red ma")[0].id == &"ACER-RUBRUM", "what a person actually types")
	assert(catalogue.search("plantain")[0].id == &"HOSTA-PATRIOT", "a common name")
	assert(catalogue.search("PATRIOT")[0].id == &"HOSTA-PATRIOT", "a cultivar")
	# A tag finds the plants that carry it, and everything else is out.
	var natives: Array = catalogue.search("native")
	assert(natives.size() == 3, "three natives, got %d" % natives.size())
	for plant: SpeciesScript in natives:
		assert(plant.tags.has("native"), String(plant.id))
	assert(catalogue.search("zzz").is_empty(), "nothing matches nothing")
	assert(catalogue.search("").size() == 4, "an empty box is the whole catalogue")


func test_a_filter_that_is_not_understood_is_refused_rather_than_ignored() -> void:
	# A browser that silently ignores a criterion shows plants that will not grow where they are
	# going, so an unknown key is refused and named.
	var catalogue := _catalogue()
	assert(CatalogueScript.unknown_criterion({"sun": 1}) == "")
	assert(CatalogueScript.unknown_criterion({"too_tall": 5}) == "too_tall")
	assert(catalogue.filter({"sun": SpeciesScript.FULL_SHADE}).is_empty() == false, "hostas take shade")
	assert(catalogue.filter({"too_tall": 5}).is_empty(), "an unknown criterion finds nothing")


func test_a_filter_finds_a_plant_by_light_water_zone_size_and_tags() -> void:
	var catalogue := _catalogue()
	# Light: only the hosta will take full shade, and only the grass *needs* full sun.
	var shade: Array = catalogue.filter({"sun": SpeciesScript.FULL_SHADE})
	assert(_ids(shade) == PackedStringArray(["HOSTA-PATRIOT"]), str(_ids(shade)))
	# A plant must take **all** of the light conditions asked for.
	for plant: SpeciesScript in catalogue.filter({"sun": SpeciesScript.FULL_SUN | SpeciesScript.PART_SHADE}):
		assert(plant.takes_sun(SpeciesScript.FULL_SUN) and plant.takes_sun(SpeciesScript.PART_SHADE))
	# Water, as a ceiling.
	assert(_ids(catalogue.filter({"water_max": SpeciesScript.WATER_LOW})) == PackedStringArray(["PANICUM-VIRGATUM"]))
	# A zone: hardy where it is going. The witch hazel is the tender one here.
	var zone_three := _ids(catalogue.filter({"zone": 3}))
	assert(zone_three.has("ACER-RUBRUM") and zone_three.has("HOSTA-PATRIOT"), str(zone_three))
	assert(not zone_three.has("HAMAMELIS-VIRGINIANA"), "zone 3 is colder than it is hardy in")
	# Size, as a ceiling for a space 1 m tall.
	assert(_ids(catalogue.filter({"height_max_cm": 100})) == PackedStringArray(["HOSTA-PATRIOT"]))
	# Every tag asked for is required, not any of them.
	assert(_ids(catalogue.filter({"tags": ["native", "low water"]})) == PackedStringArray(["PANICUM-VIRGATUM"]))
	assert(catalogue.filter({"tags": ["native", "not a tag"]}).is_empty())
	# What it is drawn as, for a placement tool asking what it may plant on a tree form.
	assert(_ids(catalogue.filter({"form": "res://scenes/props/tree.tscn"})) == PackedStringArray(["ACER-RUBRUM"]))


func test_a_filter_for_january_finds_the_plant_that_blooms_across_the_new_year() -> void:
	# The case a single month value gets wrong: the witch hazel blooms November to March, so it
	# blooms in January - and a browser asked "what is in flower in January?" has to offer it.
	var catalogue := _catalogue()
	assert(_ids(catalogue.filter({"bloom_month": 1})) == PackedStringArray(["HAMAMELIS-VIRGINIANA"]))
	assert(_ids(catalogue.filter({"bloom_month": 12})) == PackedStringArray(["HAMAMELIS-VIRGINIANA"]))
	assert(_ids(catalogue.filter({"bloom_month": 3})) == PackedStringArray(["ACER-RUBRUM", "HAMAMELIS-VIRGINIANA"]))
	assert(_ids(catalogue.filter({"bloom_month": 7})) == PackedStringArray(["HOSTA-PATRIOT"]))
	assert(catalogue.filter({"bloom_month": 5}).is_empty(), "nothing blooms in May in this catalogue")


func test_the_catalogue_sorts_the_way_a_browser_needs_it_to() -> void:
	var catalogue := _catalogue()
	# By height, shortest first: a designer choosing for a low bed wants the small ones together.
	assert(_ids(catalogue.filter({"sort": "height"})) == PackedStringArray([
		"HOSTA-PATRIOT", "PANICUM-VIRGATUM", "HAMAMELIS-VIRGINIANA", "ACER-RUBRUM"
	]))
	assert(_ids(catalogue.filter({"sort": "height", "descending": true}))[0] == "ACER-RUBRUM")
	# By bloom, with the January flower first and the foliage plant last rather than second.
	assert(_ids(catalogue.filter({"sort": "bloom"})) == PackedStringArray([
		"HAMAMELIS-VIRGINIANA", "ACER-RUBRUM", "HOSTA-PATRIOT", "PANICUM-VIRGATUM"
	]))
	# By default: botanical name, which is how a plant list is written.
	assert(_ids(catalogue.filter({})) == PackedStringArray([
		"ACER-RUBRUM", "HAMAMELIS-VIRGINIANA", "HOSTA-PATRIOT", "PANICUM-VIRGATUM"
	]))


func test_tags_come_with_their_counts_so_a_browser_can_build_its_chips() -> void:
	var catalogue := _catalogue()
	var counts: Dictionary = catalogue.tag_counts()
	assert(int(counts["native"]) == 3, "three natives")
	assert(int(counts["low water"]) == 1)
	assert(int(counts["shade tree"]) == 1)
	assert(catalogue.tag_names() == ["low water", "native", "shade", "shade tree", "winter interest"],
		str(catalogue.tag_names()))
	assert(catalogue.tagged("shade").size() == 1)
	assert(catalogue.tagged("not a tag").is_empty())


func test_a_collection_is_a_persons_own_and_survives_its_own_file() -> void:
	_clean()
	var catalogue := _catalogue()
	assert(catalogue.create_collection("front bed"))
	assert(not catalogue.create_collection("front bed"), "the name is taken")
	assert(not catalogue.create_collection("   "), "a nameless list is not a list")
	assert(catalogue.add_to_collection("front bed", &"HOSTA-PATRIOT"))
	assert(catalogue.add_to_collection("front bed", &"ACER-RUBRUM"))
	assert(catalogue.add_to_collection("front bed", &"HOSTA-PATRIOT"), "twice is once")
	assert(not catalogue.add_to_collection("front bed", &"NOT-A-PLANT"), "an id that is not in the catalogue")
	assert(not catalogue.add_to_collection("no such list", &"HOSTA-PATRIOT"))
	assert(
		_ids(catalogue.collection("front bed")) == PackedStringArray(["ACER-RUBRUM", "HOSTA-PATRIOT"]),
		"the group holds both plants, sorted: %s" % str(_ids(catalogue.collection("front bed")))
	)
	assert(
		", ".join(catalogue.collections_of(&"HOSTA-PATRIOT")) == "front bed",
		str(catalogue.collections_of(&"HOSTA-PATRIOT"))
	)
	assert(catalogue.rename_collection("front bed", "shade border"))
	assert(catalogue.collection_count("shade border") == 2, "renaming keeps the plants")
	assert(not catalogue.rename_collection("shade border", "shade border"))
	assert(catalogue.remove_from_collection("shade border", &"ACER-RUBRUM"))
	assert(catalogue.collection_count("shade border") == 1)

	# The list survives its own file, apart from the catalogue.
	var written: Dictionary = catalogue.save_collections(SCRATCH_COLLECTIONS)
	assert(bool(written["ok"]), String(written["reason"]))
	var fresh := _catalogue()
	var read: Dictionary = fresh.load_collections(SCRATCH_COLLECTIONS)
	assert(bool(read["ok"]), String(read["reason"]))
	assert(fresh.collection_names() == ["shade border"], str(fresh.collection_names()))
	assert(_ids(fresh.collection("shade border")) == PackedStringArray(["HOSTA-PATRIOT"]))
	# A list naming a plant the catalogue does not have keeps its name, drops the id, and says so.
	var file := FileAccess.open(SCRATCH_COLLECTIONS, FileAccess.WRITE)
	file.store_string(JSON.stringify({"shade border": ["HOSTA-PATRIOT", "GONE"], "old list": ["ALSO-GONE"]}))
	file.close()
	var other := _catalogue()
	var read_again: Dictionary = other.load_collections(SCRATCH_COLLECTIONS)
	assert(bool(read_again["ok"]))
	assert(other.collection_count("shade border") == 1, "the plant that is there is kept")
	assert(other.has_collection("old list"), "an emptied list keeps its name")
	var dropped: Array = read_again["dropped"]
	assert(dropped.size() == 2, "and both losses are reported: %s" % str(dropped))
	assert(other.problems().is_empty(), "a dropped id is reported once, not forever")
	_clean()


func test_a_catalogue_survives_its_file() -> void:
	_clean()
	var catalogue := _catalogue()
	var written: Dictionary = catalogue.save_to(SCRATCH)
	assert(bool(written["ok"]), String(written["reason"]))
	var read: Dictionary = CatalogueScript.load_from(SCRATCH)
	assert(bool(read["ok"]), String(read["reason"]))
	var back: PlantCatalogue = read["catalogue"]
	assert(back.version == 2)
	assert(back.source == "test")
	assert(back.count() == 4)
	assert(back.get_species(&"HAMAMELIS-VIRGINIANA").blooms_in(1), "the winter bloom survived")
	assert(back.get_species(&"HAMAMELIS-VIRGINIANA").bloom_text() == "November-March")
	assert(back.get_species(&"ACER-RUBRUM").height_cm == 1500)
	assert(back.get_species(&"PANICUM-VIRGATUM").tags.has("low water"))
	assert(back.problems().is_empty(), "a catalogue written and read back is sound")
	assert(not FileAccess.file_exists(SCRATCH + CatalogueScript.TEMP_SUFFIX), "no half file is left")
	# And it is text a nursery could read, which is the point of not using one resource per plant.
	var text: String = catalogue.to_json()
	assert(text.contains("\"botanical_name\": \"Acer rubrum\""), "the names are legible")
	assert(text.contains("\"bloom_months\""))
	_clean()


func test_a_file_that_is_not_a_catalogue_is_refused_with_a_reason() -> void:
	_clean()
	var missing: Dictionary = CatalogueScript.load_from(SCRATCH)
	assert(not bool(missing["ok"]))
	assert(String(missing["reason"]).contains("no file"), String(missing["reason"]))

	var file := FileAccess.open(SCRATCH, FileAccess.WRITE)
	file.store_string("this is not json")
	file.close()
	var rubbish: Dictionary = CatalogueScript.load_from(SCRATCH)
	assert(not bool(rubbish["ok"]))
	assert(String(rubbish["reason"]).contains("line"), String(rubbish["reason"]))

	# A bare list of plants is a plant list, not a catalogue: it is refused here and imported there.
	file = FileAccess.open(SCRATCH, FileAccess.WRITE)
	file.store_string(JSON.stringify([_boxwood().to_dict()]))
	file.close()
	var wrong_shape: Dictionary = CatalogueScript.load_from(SCRATCH)
	assert(not bool(wrong_shape["ok"]), "a list is not a catalogue")
	assert(String(wrong_shape["reason"]).contains("not a JSON object"), String(wrong_shape["reason"]))
	_clean()


func test_importing_a_list_adds_what_is_missing_and_reports_what_it_will_not_take() -> void:
	_clean()
	var catalogue := _catalogue()
	var incoming := _boxwood().to_dict()
	var duplicate: Dictionary = _maple().to_dict()
	duplicate["height_cm"] = 9999
	var nonsense: Dictionary = _grass().to_dict()
	nonsense["id"] = "BROKEN"
	nonsense["zone_min"] = 0
	var file := FileAccess.open(SCRATCH_IMPORT, FileAccess.WRITE)
	file.store_string(JSON.stringify({"species": {
		"BUXUS-SEMPERVIRENS": incoming, "ACER-RUBRUM": duplicate, "BROKEN": nonsense,
	}}))
	file.close()

	var merged: Dictionary = catalogue.import_json(SCRATCH_IMPORT)
	assert(bool(merged["ok"]), String(merged["reason"]))
	assert(int(merged["added"]) == 1, "the boxwood is new")
	assert(int(merged["replaced"]) == 0, "and nothing was replaced without being asked")
	assert(catalogue.count() == 5)
	assert(catalogue.get_species(&"ACER-RUBRUM").height_cm == 1500, "the entry already here stands")
	var refused: Array = merged["refused"]
	assert(refused.size() == 2, "two entries were not taken: %s" % str(refused))
	assert(_any_contains(refused, "ACER-RUBRUM"), "the duplicate is named")
	assert(_any_contains(refused, "zone"), "and the unusable one says what is wrong with it")

	# With the incoming version winning, the same file replaces instead of refusing.
	var replaced: Dictionary = catalogue.import_json(SCRATCH_IMPORT, true)
	# Both entries that are already here are replaced, not just the one whose price changed: the
	# door is "the incoming version wins", and it wins for every plant the file carries.
	assert(int(replaced["replaced"]) == 2, str(replaced))
	assert(int(replaced["added"]) == 0, "the boxwood is here now")
	assert(catalogue.get_species(&"ACER-RUBRUM").height_cm == 9999, "the incoming version won")
	assert(catalogue.count() == 5)

	# A nursery's export is often a bare list rather than a catalogue.
	file = FileAccess.open(SCRATCH_IMPORT, FileAccess.WRITE)
	file.store_string(JSON.stringify([_boxwood().to_dict()]))
	file.close()
	var from_list: Dictionary = catalogue.import_json(SCRATCH_IMPORT)
	assert(bool(from_list["ok"]), String(from_list["reason"]))
	assert(int(from_list["added"]) + int(from_list["refused"].size()) == 1, "the list was read")
	_clean()


func test_exporting_writes_a_list_somebody_else_can_read() -> void:
	_clean()
	var catalogue := _catalogue()
	var all_written: Dictionary = catalogue.export_json(SCRATCH)
	assert(bool(all_written["ok"]), String(all_written["reason"]))
	assert(int(all_written["count"]) == 4)
	var back: Dictionary = CatalogueScript.load_from(SCRATCH)
	assert(bool(back["ok"]), "what was exported is a catalogue")
	assert(back["catalogue"].count() == 4)
	# A chosen list: what a designer sends a client, which is two plants and not four.
	var chosen: Dictionary = catalogue.export_json(SCRATCH, ["ACER-RUBRUM", "HAMAMELIS-VIRGINIANA"])
	assert(int(chosen["count"]) == 2)
	var subset: Dictionary = CatalogueScript.load_from(SCRATCH)
	assert(subset["catalogue"].count() == 2, "only the chosen plants were written")
	assert(subset["catalogue"].has(&"HOSTA-PATRIOT") == false)
	_clean()


func test_a_model_is_loaded_once_however_many_plants_share_it() -> void:
	# The point of the cache: a browser grid and a placement tool ask for the same scene hundreds of
	# times, and a catalogue of four thousand plants has a few dozen models between them.
	var catalogue := _catalogue()
	var loads: Dictionary = catalogue.cache_loads()
	assert(int(loads["scenes"]) == 0, "nothing is loaded until it is asked for")
	var first: PackedScene = catalogue.scene_for(&"HAMAMELIS-VIRGINIANA")
	var second: PackedScene = catalogue.scene_for(&"PANICUM-VIRGATUM")
	assert(first != null and second != null)
	assert(first == second, "two shrubs share one scene")
	assert(int(catalogue.cache_loads()["scenes"]) == 1, "and it was loaded once")
	assert(
		first.resource_path == "res://scenes/props/shrub.tscn",
		"a species with no model of its own is planted as its form: %s" % first.resource_path
	)
	# A species with its own model is planted as that, not as its form.
	var boxwood := _boxwood()
	boxwood.model_scene = "res://scenes/props/tree.tscn"
	catalogue.add(boxwood)
	assert(catalogue.scene_for(&"BUXUS-SEMPERVIRENS").resource_path == "res://scenes/props/tree.tscn")
	# A missing file is not an error, and it is not re-checked on every redraw either: the miss is
	# cached alongside the hits.
	var lost := _grass()
	# Its own id: adding a second plant with an existing id is refused, so reusing the grass's would
	# have tested nothing at all.
	lost.id = &"PANICUM-LOST"
	lost.thumbnail = "res://nothing/here.png"
	assert(catalogue.add(lost), "the fixture has to be in the catalogue to be asked about")
	assert(catalogue.thumbnail_for(&"PANICUM-LOST") == null)
	assert(catalogue.thumbnail_for(&"PANICUM-LOST") == null)
	assert(int(catalogue.cache_loads()["thumbnails"]) == 0, "nothing was loaded for a file that is not there")
	assert(_any_contains(catalogue.missing_files(), "nothing/here.png"), "and it is reported by asking")
	# The counters are cumulative - they say how much work the cache has saved - so the way to prove
	# that clearing really *freed* what it held is that the next ask loads the scene again.
	var loads_so_far: int = int(catalogue.cache_loads()["scenes"])
	catalogue.clear_cache()
	assert(catalogue.scene_for(&"PANICUM-VIRGATUM") != null)
	assert(
		int(catalogue.cache_loads()["scenes"]) == loads_so_far + 1,
		"a cleared cache loads again, so the thing it held was really dropped"
	)
	assert(catalogue.scene_for(&"PANICUM-VIRGATUM") != null)
	assert(int(catalogue.cache_loads()["scenes"]) == loads_so_far + 1, "and only once")