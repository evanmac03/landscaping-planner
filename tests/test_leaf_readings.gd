extends Node
## The leaves a list states: a person's words turned into the bits the program reads, a reading landing on the
## plant that is already there, and the one sentence that says how much of a list states its leaves.
##
## The fixture is a garden of three built here rather than the shipped list, so every count in the sentence is
## a number this file can check - and it writes its sheet in `user://`, because `res://` is the project's own
## data and a test does not edit the thing it is testing against.

const ReadingsScript := preload("res://scripts/leaf_readings.gd")
const SpeciesScript := preload("res://scripts/plants/plant_species.gd")
const CatalogueScript := preload("res://scripts/plants/plant_catalogue.gd")
const KeyScript := preload("res://scripts/plants/plant_key.gd")

const SHEET := "user://test_leaf_readings.json"

# --- the fixture -------------------------------------------------------------------------------


func _clean() -> void:
	if FileAccess.file_exists(SHEET):
		DirAccess.remove_absolute(SHEET)


## A plant the catalogue takes: it insists on an id, a name and a size, and asks nothing else of a fixture.
func _plant(species_id: String) -> SpeciesScript:
	return SpeciesScript.make(
		StringName(species_id),
		species_id + " botanical",
		species_id,
		60,
		60,
		SpeciesScript.PERENNIAL,
	)


func _catalogue() -> CatalogueScript:
	var catalogue: CatalogueScript = CatalogueScript.make()
	for species_id: String in ["APLANT", "BPLANT", "CPLANT"]:
		assert(catalogue.add(_plant(species_id)), "the fixture's %s is a plant the catalogue takes" % species_id)
	return catalogue

# --- a person's words to the bits the program reads ---------------------------------------------


func test_a_word_becomes_the_bit_its_own_table_holds() -> void:
	# The table **is** the vocabulary. A word looked up in the trait's own table is the only way a word and a
	# value can be guaranteed to keep meaning the same thing as the tables change.
	var lobed: Dictionary = ReadingsScript.words_to_bits(SpeciesScript.LEAF_MARGIN, "lobed")
	assert(bool(lobed["ok"]), "the margin's own word is read: %s" % String(lobed["reason"]))
	assert(int(lobed["bits"]) == SpeciesScript.MRG_LOBED, "as the bit the table holds for it")
	var basal: Dictionary = ReadingsScript.words_to_bits(SpeciesScript.LEAF_ARRANGEMENT, "a rosette at the base")
	assert(int(basal["bits"]) == SpeciesScript.ARR_BASAL, "and a phrase of four words is one value too")
	var shouted: Dictionary = ReadingsScript.words_to_bits(SpeciesScript.LEAF_ARRANGEMENT, "  OPPOSITE ")
	assert(int(shouted["bits"]) == SpeciesScript.ARR_OPPOSITE, "a person's capitals and spaces do not matter")
	var two: Dictionary = ReadingsScript.words_to_bits(SpeciesScript.LEAF_ARRANGEMENT, "alternate, whorled")
	assert(
		int(two["bits"]) == SpeciesScript.ARR_ALTERNATE | SpeciesScript.ARR_WHORLED,
		"and a trait is a set: two words are two bits, the way a plant takes two kinds of light",
	)


func test_a_word_the_trait_does_not_have_is_refused_by_name() -> void:
	# Whoever typed it has one word wrong rather than a broken file, so the refusal names the word and prints
	# the words that do exist - which is the whole of the help they need.
	var wrong: Dictionary = ReadingsScript.words_to_bits(SpeciesScript.LEAF_MARGIN, "toothy")
	assert(not bool(wrong["ok"]), "a word this program does not have is refused")
	assert(String(wrong["reason"]).contains("toothy"), "by name: %s" % String(wrong["reason"]))
	assert(String(wrong["reason"]).contains("scalloped"), "and with the words the trait does have")
	var no_trait: Dictionary = ReadingsScript.words_to_bits(&"leaf_colour", "red")
	assert(not bool(no_trait["ok"]), "a leaf this program does not have is refused too")
	assert(String(no_trait["reason"]).contains("leaf_colour"), "naming it: %s" % String(no_trait["reason"]))
	var silent: Dictionary = ReadingsScript.words_to_bits(SpeciesScript.LEAF_MARGIN, "   ")
	assert(not bool(silent["ok"]), "and a blank says nothing rather than standing for a value")

# --- stating what a list already holds ----------------------------------------------------------


func test_a_reading_states_the_plant_it_names_and_creates_nothing() -> void:
	_clean()
	var catalogue: CatalogueScript = _catalogue()
	var written: Dictionary = ReadingsScript.write(
		{ "BPLANT": { "leaf_margin": "lobed", "leaf_arrangement": "opposite" } },
		SHEET,
	)
	assert(bool(written["ok"]), "the reading is written: %s" % String(written["reason"]))
	assert(int(written["written"]) == 1, "one plant was stated")
	var made: Dictionary = ReadingsScript.apply(catalogue, SHEET)
	assert(bool(made["ok"]), "and it lands: %s" % String(made["reason"]))
	assert(int(made["stated"]) == 1, "on the one plant it names: %d" % int(made["stated"]))
	assert(catalogue.count() == 3, "without adding a plant: %d" % catalogue.count())
	var plant: SpeciesScript = catalogue.get_species(&"BPLANT")
	assert(plant.leaf_trait(SpeciesScript.LEAF_MARGIN) == SpeciesScript.MRG_LOBED, "the margin is stated")
	assert(plant.leaf_trait(SpeciesScript.LEAF_ARRANGEMENT) == SpeciesScript.ARR_OPPOSITE, "and the arrangement")
	assert(
		catalogue.get_species(&"APLANT").leaf_trait(SpeciesScript.LEAF_MARGIN) == 0,
		"and a plant nobody read is left saying nothing",
	)
	_clean()


func test_a_reading_for_a_plant_the_list_does_not_have_is_named_rather_than_invented() -> void:
	# A reading is a fact about a plant, not a plant: one invented out of a leaf would be a plant nobody chose.
	_clean()
	var catalogue: CatalogueScript = _catalogue()
	ReadingsScript.write({ "NOBODY": { "leaf_margin": "lobed" } }, SHEET)
	var made: Dictionary = ReadingsScript.apply(catalogue, SHEET)
	assert(int(made["stated"]) == 0, "nothing was stated")
	var refused: PackedStringArray = made["refused"]
	assert(refused.size() == 1, "and it is not silent: %d" % refused.size())
	assert(String(refused[0]).contains("NOBODY"), "the refusal names the plant: %s" % String(refused[0]))
	assert(catalogue.count() == 3, "the list is exactly as it was")


func test_a_missing_file_is_a_list_nobody_has_read_rather_than_a_failure() -> void:
	# Every install starts with no readings at all, so this is the ordinary case and not an error to report.
	_clean()
	var made: Dictionary = ReadingsScript.read(SHEET)
	assert(bool(made["ok"]), "an absent file is not a failure")
	assert((made["ids"] as Dictionary).is_empty(), "and holds no readings")
	assert((made["refused"] as PackedStringArray).is_empty(), "and refuses nothing")


func test_a_file_that_is_not_a_leaf_reading_is_refused() -> void:
	_clean()
	var file: FileAccess = FileAccess.open(SHEET, FileAccess.WRITE)
	file.store_string(JSON.stringify({ "species": { } }))
	file.close()
	var made: Dictionary = ReadingsScript.read(SHEET)
	assert(not bool(made["ok"]), "a catalogue is not a leaf reading")
	assert(String(made["reason"]).contains("not a leaf reading"), "and says so: %s" % String(made["reason"]))
	_clean()


func test_the_file_holds_the_words_rather_than_the_bits() -> void:
	# The file is the thing a person opens and edits; the bits are the program's business and would be a
	# number nobody can check against a field guide.
	_clean()
	ReadingsScript.write({ "APLANT": { "leaf_margin": "lobed" } }, SHEET)
	var text: String = FileAccess.get_file_as_string(SHEET)
	assert(text.contains("lobed"), "the word is in the file: %s" % text)
	assert(not text.contains("\"leaf_margin\": 16"), "and not the bit it stands for")
	_clean()

# --- what the list states, in one sentence --------------------------------------------------------


func test_a_list_nobody_has_read_states_nothing_and_says_so() -> void:
	# The state this program ships in, and a count of nought is not an answer to it.
	var words: String = ReadingsScript.states_words(_catalogue())
	assert(words.contains("states no leaf"), "the nothing case is written out: %s" % words)
	assert(words.contains("3 plants"), "with the list's own count: %s" % words)
	assert(words.contains("not asked"), "and what it means for the key: %s" % words)


func test_the_sentence_counts_what_is_stated_trait_by_trait() -> void:
	_clean()
	var catalogue: CatalogueScript = _catalogue()
	ReadingsScript.write({ "APLANT": { "leaf_margin": "lobed" } }, SHEET)
	ReadingsScript.apply(catalogue, SHEET)
	var words: String = ReadingsScript.states_words(catalogue)
	assert(words.contains("1 of its 3 plants"), "it counts the plants that have been read: %s" % words)
	assert(words.contains("the margin 1"), "and each trait on its own: %s" % words)
	assert(words.contains("the arrangement 0"), "including the traits nobody has stated: %s" % words)
	_clean()


func test_a_leaf_question_becomes_askable_once_the_readings_arrive() -> void:
	# The payoff, and the reason readings are worth holding at all: a leaf question is asked only while every
	# plant still in the running states that leaf, so reading the leaves is what makes the leaf half of the
	# key appear. Nothing in the key changes to make it happen.
	_clean()
	var catalogue: CatalogueScript = _catalogue()
	var plants: Array[PlantSpecies] = []
	for id: StringName in catalogue.ids():
		plants.append(catalogue.get_species(id))
	assert(not KeyScript.askable(plants, SpeciesScript.LEAF_MARGIN), "a list read nowhere is asked nothing")
	ReadingsScript.write(
		{
			"APLANT": { "leaf_margin": "lobed" },
			"BPLANT": { "leaf_margin": "smooth" },
			"CPLANT": { "leaf_margin": "wavy" },
		},
		SHEET,
	)
	ReadingsScript.apply(catalogue, SHEET)
	assert(KeyScript.askable(plants, SpeciesScript.LEAF_MARGIN), "read leaf by leaf, the question is asked")
	assert(
		not KeyScript.askable(plants, SpeciesScript.LEAF_VENATION),
		"while the veins nobody has read are still not asked about",
	)
	_clean()
