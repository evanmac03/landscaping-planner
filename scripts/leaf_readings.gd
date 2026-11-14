class_name LeafReadings
extends RefCounted
## The leaves a plant list states, in a file somebody keeps in a spreadsheet, and the one sentence that says
## how much of a list states its leaves.
##
## A leaf trait is a **set of bits** on a species (spec §7c.6): `ARR_OPPOSITE` is 2, `MRG_LOBED` is 16, and
## nobody remembers that from one week to the next. So the file holds the **words** a field guide uses, and
## this is where they become the bits the rest of the program reads. `words_to_bits` looks each word up in
## the trait's **own** table (`PlantSpecies.names_for`), so a word and its value cannot come apart, and a
## word this program does not have is refused by name rather than quietly dropped.
##
## **Why the readings are a file of their own and not rows in the catalogue.** An entry is matched by its id
## and an import skips an id the catalogue already holds; a record read back through
## `PlantSpecies.from_dict` **defaults every field it omits**, so a row stating only leaves would come back
## with no height and be refused as a plant that cannot be drawn. Stating a leaf is a fact about a plant that
## already exists rather than a new version of it, so it is merged onto the plant in hand - and the shipped
## list stays the file it was, which is what keeps `data/plants/nursery_list.json` diffable.
##
## The shape of the file:
##
##     {
##       "readings": {
##         "acer-rubrum": { "leaf_arrangement": "opposite", "leaf_margin": "lobed" }
##       }
##     }
##
## A trait this program does not have, a word its trait does not have, and an id the list does not hold are
## each named and change nothing. **An id the list does not hold is not created**: a plant invented out of a
## leaf would be a plant nobody chose.

## Where the readings live. Written by `tools/leaf_reading.gd`, and **absent until somebody has read a
## leaf**: a program that ships no readings ships no file, exactly as it ships no catalogue of somebody's own
## until they save one.
const FILE_PATH := "res://data/plants/leaf_readings.json"
## The one key the file has above its readings, so the file says what it is - and so it cannot be taken for a
## catalogue, which `PlantCatalogue.load_from` refuses for holding neither a version nor a species list.
const READINGS_KEY := "readings"

# --- a person's words to the bits the program reads --------------------------------------------


## The bits one trait's words stand for: `{ ok, reason, bits }`.
##
## **Several words may be given**, separated by commas - "alternate, whorled" - because a trait is a set: a
## plant takes two of the arrangements the way it takes two of the lights. A word the trait does not have is
## refused **with the words it does have**, because the person who typed it has one word wrong rather than a
## broken file, and which words exist is the whole of the help they need.
static func words_to_bits(trait_name: StringName, words: String) -> Dictionary:
	var table: Dictionary = PlantSpecies.names_for(trait_name)
	if table.is_empty():
		return _refused("There is no leaf called \"%s\" in this program." % String(trait_name))
	var bits: int = 0
	for raw: String in words.split(",", false):
		var wanted: String = raw.strip_edges().to_lower()
		if wanted.is_empty():
			continue
		var found: int = _bit_for(table, wanted)
		if found == 0:
			return _refused(
				(
					"\"%s\" is not a word this program has for %s. It has %s."
					% [wanted, String(trait_name), vocabularies(trait_name)]
				)
			)
		bits |= found
	if bits == 0:
		return _refused("No %s was stated at all." % String(trait_name))
	return { "ok": true, "reason": "", "bits": bits }


## The words one trait offers, quoted and in the table's own order, for a page or a tool that has to print
## them. Empty for a trait this program does not have.
static func vocabularies(trait_name: StringName) -> String:
	return _vocabulary(PlantSpecies.names_for(trait_name))


static func _vocabulary(table: Dictionary) -> String:
	var out: PackedStringArray = PackedStringArray()
	for word: Variant in table.values():
		out.append("\"%s\"" % String(word))
	return ", ".join(out)


## The bit whose own word is this, or 0. **The table is the vocabulary**, so there is no second list of words
## beside it that could drift away from it.
static func _bit_for(table: Dictionary, word: String) -> int:
	for bit: Variant in table.keys():
		if String(table[bit]).to_lower() == word:
			return int(bit)
	return 0


static func _refused(reason: String) -> Dictionary:
	return { "ok": false, "reason": reason, "bits": 0 }

# --- reading the file --------------------------------------------------------------------------


## What a readings file holds: `{ id: { trait_name: bits } }`, with everything it could not read named.
##
## A file that is **not there** is not a failure: it is a list nobody has read the leaves of, which is how
## this program ships, and the sentence at the foot of this file says so. That is why an absent file answers
## `ok`, and only a file that is there and wrong answers a sentence instead.
static func read(path: String = FILE_PATH) -> Dictionary:
	var empty: Dictionary = { "ok": true, "reason": "", "ids": { }, "refused": PackedStringArray() }
	if not FileAccess.file_exists(path):
		return empty
	var loaded: Dictionary = PlantCatalogue.read_json(path)
	if not bool(loaded.get("ok", false)):
		return { "ok": false, "reason": String(loaded.get("reason", "")), "ids": { }, "refused": PackedStringArray() }
	var data: Variant = loaded.get("data", null)
	if not (data is Dictionary) or not (data as Dictionary).has(READINGS_KEY):
		return _not_readings(path, "it holds no \"%s\"" % READINGS_KEY)
	var raw: Variant = (data as Dictionary)[READINGS_KEY]
	if not (raw is Dictionary):
		return _not_readings(path, "its \"%s\" is not a list of plants" % READINGS_KEY)
	var ids: Dictionary = { }
	var refused: PackedStringArray = PackedStringArray()
	for key: Variant in (raw as Dictionary).keys():
		var entry: Variant = (raw as Dictionary)[key]
		if not (entry is Dictionary):
			refused.append("%s is not an object of leaf words." % String(key))
			continue
		var traits: Dictionary = { }
		for trait_name: Variant in (entry as Dictionary).keys():
			var name: StringName = StringName(trait_name)
			var made: Dictionary = words_to_bits(name, String((entry as Dictionary)[trait_name]))
			if not bool(made["ok"]):
				refused.append("%s: %s" % [String(key), String(made["reason"])])
				continue
			traits[name] = int(made["bits"])
		# A row with no trait that could be read states nothing, and a statement of nothing is not kept:
		# it would make the plant look read while leaving it as silent as it was.
		if not traits.is_empty():
			ids[StringName(key)] = traits
	return { "ok": true, "reason": "", "ids": ids, "refused": refused }


static func _not_readings(path: String, what: String) -> Dictionary:
	return {
		"ok": false,
		"reason": "%s is not a leaf reading: %s." % [path, what],
		"ids": { },
		"refused": PackedStringArray(),
	}

# --- stating what a list already holds ----------------------------------------------------------


## State the leaves of the plants a list already holds: `{ ok, reason, stated, refused }`.
##
## **Nothing is created and nothing is replaced.** A reading adds a fact to a plant that is there; an id the
## list does not hold is named in `refused` and left alone, because a plant invented out of a leaf would be a
## plant nobody chose. Whether the list is the shipped one or somebody's own does not matter - the reading is
## matched on the id, which is what an id is for.
static func apply(catalogue: PlantCatalogue, path: String = FILE_PATH) -> Dictionary:
	var made: Dictionary = read(path)
	var refused: PackedStringArray = _refusals_of(made)
	if not bool(made.get("ok", false)):
		return { "ok": false, "reason": String(made.get("reason", "")), "stated": 0, "refused": refused }
	if catalogue == null:
		return { "ok": true, "reason": "", "stated": 0, "refused": refused }
	var ids: Variant = made.get("ids", { })
	var stated: int = 0
	for key: Variant in (ids as Dictionary).keys():
		var plant: PlantSpecies = catalogue.get_species(StringName(key))
		if plant == null:
			refused.append("The list has no plant %s, so this reading was left alone." % String(key))
			continue
		var traits: Dictionary = (ids as Dictionary)[key]
		for trait_name: Variant in traits.keys():
			plant.set_leaf_trait(StringName(trait_name), int(traits[trait_name]))
		stated += 1
	return { "ok": true, "reason": "", "stated": stated, "refused": refused }


static func _refusals_of(made: Dictionary) -> PackedStringArray:
	var listed: Variant = made.get("refused", PackedStringArray())
	if listed is PackedStringArray:
		return listed
	return PackedStringArray()

# --- writing, which is the authoring tool's half -------------------------------------------------


## Write readings from rows a person typed: `{ id: { trait_name: words } }` -> `{ ok, reason, written }`.
##
## A row is converted on the way **out**, so a word that is wrong is refused here rather than written into a
## file that would refuse it on the way back in. What lands in the file is the **words**, not the bits: the
## file is the thing a person reads and edits, and its numbers are the program's business.
##
## Written through a temporary file and a rename, for the reason every other save in this program is: a write
## that fails must not leave a shorter file where somebody's work was.
static func write(rows: Dictionary, path: String = FILE_PATH) -> Dictionary:
	var out: Dictionary = { }
	var refused: PackedStringArray = PackedStringArray()
	for key: Variant in rows.keys():
		var entry: Variant = rows[key]
		if not (entry is Dictionary):
			refused.append("%s is not an object of leaf words." % String(key))
			continue
		var traits: Dictionary = { }
		for trait_name: Variant in (entry as Dictionary).keys():
			var name: StringName = StringName(trait_name)
			var words: String = String((entry as Dictionary)[trait_name]).strip_edges()
			if words.is_empty():
				continue
			var made: Dictionary = words_to_bits(name, words)
			if not bool(made["ok"]):
				refused.append("%s: %s" % [String(key), String(made["reason"])])
				continue
			traits[String(name)] = words
		if not traits.is_empty():
			out[String(key)] = traits
	var written: Dictionary = PlantCatalogue.write_json({ READINGS_KEY: out }, path)
	if not bool(written.get("ok", false)):
		return { "ok": false, "reason": String(written.get("reason", "")), "written": 0, "refused": refused }
	return { "ok": true, "reason": "", "written": out.size(), "refused": refused }

# --- what the list states, in one sentence --------------------------------------------------------


## What a list states about its leaves, in one sentence: how many of its plants state each trait, or that it
## states none at all.
##
## **A list that states nothing is a fact about the list rather than a zero to be shown**, and it is the state
## this program ships in - so the nothing case is written out rather than left as five noughts (spec §7c.6).
## Counted here and worded here, because a figure and the sentence that gives it away must not be two
## arithmetics.
static func states_words(catalogue: PlantCatalogue) -> String:
	if catalogue == null or catalogue.count() == 0:
		return "There is no plant list to read the leaves of."
	var total: int = catalogue.count()
	var counts: Dictionary = { }
	var stated: int = 0
	for id: StringName in catalogue.ids():
		var plant: PlantSpecies = catalogue.get_species(id)
		var any: bool = false
		for trait_name: StringName in PlantSpecies.LEAF_TRAITS:
			if plant.leaf_trait(trait_name) != 0:
				counts[trait_name] = int(counts.get(trait_name, 0)) + 1
				any = true
		if any:
			stated += 1
	if stated == 0:
		return "The list states no leaf for any of its %d plants, so the leaf questions are not asked." % total
	var every: bool = true
	for trait_name: StringName in PlantSpecies.LEAF_TRAITS:
		if int(counts.get(trait_name, 0)) != total:
			every = false
	if every:
		return (
			"Every plant in the list states every leaf, so the leaf questions are asked as they tell one plant from another."
		)
	var parts: PackedStringArray = PackedStringArray()
	for trait_name: StringName in PlantSpecies.LEAF_TRAITS:
		parts.append("%s %d" % [_trait_words(trait_name), int(counts.get(trait_name, 0))])
	return (
		(
			"The list states the leaves of %d of its %d plants: %s. A leaf question is asked only while every plant still in the running states that leaf."
			% [stated, total, ", ".join(parts)]
		)
	)


## What one trait is called in that sentence: a person's noun for the thing, rather than the field name the
## program reads. The words live here because this sentence is the only thing that needs a noun for a trait -
## the key asks about a leaf as a question, which is a different sentence in a different place.
static func _trait_words(trait_name: StringName) -> String:
	match trait_name:
		PlantSpecies.LEAF_ARRANGEMENT:
			return "the arrangement"
		PlantSpecies.LEAF_COMPLEXITY:
			return "the leaflets"
		PlantSpecies.LEAF_SHAPE:
			return "the shape"
		PlantSpecies.LEAF_MARGIN:
			return "the margin"
		PlantSpecies.LEAF_VENATION:
			return "the veins"
	return String(trait_name)
