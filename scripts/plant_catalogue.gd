class_name PlantCatalogue
extends RefCounted
## The plant list: every species a designer can plant, a search over them, and the collections a
## person makes out of them.
##
## JSON, not a `.tres` per species, and the reason is a count (spec §2.3, the same decision as the
## cost book): a catalogue is four thousand entries, it arrives from a nursery as a spreadsheet
## export, it is mailed to a colleague, and it is diffed in a review. Four thousand `.tres` files
## would be four thousand files in version control that no buyer of this tool can edit in a
## spreadsheet - and not one of them would be readable by a program that has never heard of Godot.
##
## What *is* a `Resource` is the runtime handle: the thumbnail texture and the scene a species is
## drawn as. They are loaded through `ResourceLoader` and cached here, once each, because a browser
## grid that re-loaded its images on every keystroke would load four thousand files to type a word.
##
## User collections are kept **apart** from the catalogue: the catalogue ships and is replaced
## wholesale by an import, and a person's own groupings must not be replaced with it.

const DEFAULT_PATH := "user://plants/catalogue.json"
const COLLECTIONS_PATH := "user://plants/collections.json"
const TEMP_SUFFIX := ".writing"

var version: int = 1
## Where it came from: a nursery list, a hand edit, a file.
var source: String = ""
## StringName -> PlantSpecies. A query with a String finds it too (verified: Godot treats a String
## and a StringName key as the same entry), which matters because JSON hands keys back as Strings.
var species: Dictionary[StringName, PlantSpecies] = {}
## Entries a load carried but could not use, with the reason - reported by `problems()`.
var rejected: Array[String] = []
## A person's own groups: name -> an array of StringName ids. Saved separately (COLLECTIONS_PATH).
## The value is a plain `Array`: Godot refuses a typed collection nested inside a typed one, so the
## ids are held untyped even though they are always StringNames.
var collections: Dictionary[StringName, Array] = {}

var _thumbnails: Dictionary[String, Texture2D] = {}
var _scenes: Dictionary[String, PackedScene] = {}
var _thumbnail_loads: int = 0
var _scene_loads: int = 0


func _init(catalogue_version: int = 1) -> void:
	version = catalogue_version


static func make(catalogue_version: int = 1, from: String = "") -> PlantCatalogue:
	var catalogue: PlantCatalogue = PlantCatalogue.new(catalogue_version)
	catalogue.source = from
	return catalogue


# --- the list ---------------------------------------------------------------------------


## Add a species. A duplicate id is refused rather than replaced: the id is what an imported list
## and this catalogue are matched on, and a silent replace is how a plant quietly becomes a
## different plant.
func add(plant: PlantSpecies) -> bool:
	if plant == null or not plant.is_valid() or species.has(plant.id):
		return false
	species[plant.id] = plant
	return true


## Add or replace, for an import that has already decided this is the entry's new version.
func put(plant: PlantSpecies) -> bool:
	if plant == null or not plant.is_valid():
		return false
	species[plant.id] = plant
	return true


func get_species(id: StringName) -> PlantSpecies:
	return species.get(id, null) as PlantSpecies


func has(id: StringName) -> bool:
	return species.has(id)


func erase(id: StringName) -> bool:
	return species.erase(id)


## Every id, sorted, so a listing is stable between runs.
func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for key: Variant in species.keys():
		out.append(StringName(key))
	out.sort()
	return out


func count() -> int:
	return species.size()


func all() -> Array[PlantSpecies]:
	var out: Array[PlantSpecies] = []
	for id: StringName in ids():
		out.append(get_species(id))
	return out


# --- search -----------------------------------------------------------------------------


## The search a browser's one box needs: it matches the botanical name, the common name, the
## cultivar, the id and the tags, and it returns the **best** matches rather than the alphabetical
## ones. Typing "acer" should put the maples first, not the forty-second maple in a list that also
## contains "glacier" somewhere.
func search(text: String) -> Array[PlantSpecies]:
	var needle: String = text.strip_edges().to_lower()
	if needle.is_empty():
		return all()
	var ranked: Array = []
	for id: StringName in ids():
		var plant: PlantSpecies = get_species(id)
		var rank: int = rank_of(plant, needle)
		if rank >= 0:
			ranked.append({"rank": rank, "plant": plant})
	ranked.sort_custom(_by_rank)
	var out: Array[PlantSpecies] = []
	for entry: Dictionary in ranked:
		out.append(entry["plant"])
	return out


## How well one plant matches, or -1 for no match. Lower is better: an exact id first, then the
## botanical name, then what a person actually types.
static func rank_of(plant: PlantSpecies, needle: String) -> int:
	if plant == null:
		return -1
	if String(plant.id).to_lower() == needle:
		return 0
	var botanical: String = plant.botanical_name.to_lower()
	var common: String = plant.common_name.to_lower()
	var cultivar: String = plant.cultivar.to_lower()
	if botanical.begins_with(needle):
		return 1
	if cultivar.begins_with(needle) or common.begins_with(needle):
		return 2
	if botanical.contains(needle):
		return 3
	if common.contains(needle) or cultivar.contains(needle):
		return 4
	for tag: String in plant.tags:
		if tag.to_lower().contains(needle):
			return 5
	return 6 if plant.search_text().contains(needle) else -1


static func _by_rank(first: Dictionary, second: Dictionary) -> bool:
	var first_rank: int = int(first["rank"])
	var second_rank: int = int(second["rank"])
	if first_rank != second_rank:
		return first_rank < second_rank
	var first_plant: PlantSpecies = first["plant"]
	var second_plant: PlantSpecies = second["plant"]
	return first_plant.botanical_name.naturalnocasecmp_to(second_plant.botanical_name) < 0


# --- filtering --------------------------------------------------------------------------


## The filter a browser's chips and sliders drive. `criteria` keys, all optional:
##
## `text` - the search box (ranked results)
## `category` - one of `PlantSpecies.CATEGORY_NAMES`
## `sun` - bits the plant must take **all** of, so full sun | part shade means "shade tolerant"
## `bloom_month` - 1..12, matching a bloom that crosses the new year
## `zone` - the plant must be hardy in that zone
## `water_max`, `water_min` - water need as a scale
## `height_max_cm`, `height_min_cm`, `spread_max_cm`
## `tag` - one required tag; `tags` - an Array of tags, all required
## `form` - drawn as that prop scene
## `sort` - `botanical` (default), `common`, `height`, `spread`, `bloom`, `zone`; `descending`
##
## An unknown key in `criteria` is **refused**: a filter that silently ignores what it does not
## understand is a browser that shows a designer plants that will not grow there.
func filter(criteria: Dictionary) -> Array[PlantSpecies]:
	var unknown: String = unknown_criterion(criteria)
	if not unknown.is_empty():
		return []
	var found: Array[PlantSpecies] = search(String(criteria.get("text", "")))
	var out: Array[PlantSpecies] = []
	for plant: PlantSpecies in found:
		if matches(plant, criteria):
			out.append(plant)
	return sort_species(out, String(criteria.get("sort", "botanical")), bool(criteria.get("descending", false)))


## The name of the first criterion this does not understand, or "".
static func unknown_criterion(criteria: Dictionary) -> String:
	const KNOWN := [
		"text", "category", "sun", "bloom_month", "zone", "water_max", "water_min",
		"height_max_cm", "height_min_cm", "spread_max_cm", "tag", "tags", "form",
		"sort", "descending",
	]
	for key: Variant in criteria.keys():
		if not KNOWN.has(String(key)):
			return String(key)
	return ""


static func matches(plant: PlantSpecies, criteria: Dictionary) -> bool:
	if plant == null:
		return false
	if criteria.has("category") and plant.category != int(criteria["category"]):
		return false
	if criteria.has("sun") and (plant.sun & int(criteria["sun"])) != int(criteria["sun"]):
		return false
	if criteria.has("bloom_month") and not plant.blooms_in(int(criteria["bloom_month"])):
		return false
	if criteria.has("zone") and not plant.hardy_in(int(criteria["zone"])):
		return false
	if criteria.has("water_max") and plant.water > int(criteria["water_max"]):
		return false
	if criteria.has("water_min") and plant.water < int(criteria["water_min"]):
		return false
	if criteria.has("height_max_cm") and plant.height_cm > int(criteria["height_max_cm"]):
		return false
	if criteria.has("height_min_cm") and plant.height_cm < int(criteria["height_min_cm"]):
		return false
	if criteria.has("spread_max_cm") and plant.spread_cm > int(criteria["spread_max_cm"]):
		return false
	if criteria.has("tag") and not plant.tags.has(String(criteria["tag"])):
		return false
	if criteria.has("tags"):
		var wanted: Variant = criteria["tags"]
		if wanted is Array:
			for tag: Variant in wanted:
				if not plant.tags.has(String(tag)):
					return false
	if criteria.has("form") and plant.form != String(criteria["form"]):
		return false
	return true


static func sort_species(plants: Array[PlantSpecies], by: String, descending: bool = false) -> Array[PlantSpecies]:
	var sorted: Array[PlantSpecies] = plants.duplicate()
	match by:
		"common":
			sorted.sort_custom(func(a: PlantSpecies, b: PlantSpecies) -> bool:
				return a.common_name.naturalnocasecmp_to(b.common_name) < 0)
		"height":
			sorted.sort_custom(func(a: PlantSpecies, b: PlantSpecies) -> bool:
				return a.height_cm < b.height_cm)
		"spread":
			sorted.sort_custom(func(a: PlantSpecies, b: PlantSpecies) -> bool:
				return a.spread_cm < b.spread_cm)
		"zone":
			sorted.sort_custom(func(a: PlantSpecies, b: PlantSpecies) -> bool:
				return a.zone_min < b.zone_min)
		"bloom":
			sorted.sort_custom(func(a: PlantSpecies, b: PlantSpecies) -> bool:
				return first_bloom_month(a) < first_bloom_month(b))
		_:
			sorted.sort_custom(func(a: PlantSpecies, b: PlantSpecies) -> bool:
				var order: int = a.botanical_name.naturalnocasecmp_to(b.botanical_name)
				if order != 0:
					return order < 0
				return a.cultivar.naturalnocasecmp_to(b.cultivar) < 0)
	if descending:
		sorted.reverse()
	return sorted


## The month a plant's bloom starts in, or 13 for one that does not bloom, so it sorts last.
static func first_bloom_month(plant: PlantSpecies) -> int:
	for month in range(1, 13):
		if plant.blooms_in(month):
			return month
	return 13


# --- tags -------------------------------------------------------------------------------


## Every tag in the catalogue with how many species carry it, and the list sorted, so a browser can
## build its chips from the catalogue rather than from a list somebody has to keep in step.
func tag_counts() -> Dictionary:
	var counts: Dictionary = {}
	for id: StringName in ids():
		for tag: String in get_species(id).tags:
			counts[tag] = int(counts.get(tag, 0)) + 1
	return counts


func tag_names() -> Array[String]:
	var out: Array[String] = []
	for key: Variant in tag_counts().keys():
		out.append(String(key))
	out.sort()
	return out


func tagged(tag: String) -> Array[PlantSpecies]:
	var out: Array[PlantSpecies] = []
	for plant: PlantSpecies in all():
		if plant.tags.has(tag):
			out.append(plant)
	return out


# --- collections ------------------------------------------------------------------------


## A person's own groupings, kept **apart** from the catalogue, and saved to their own file: the
## catalogue ships and an import may replace it wholesale, and nobody's "front bed" list may be
## replaced with it.
func create_collection(collection_name: String) -> bool:
	var clean: String = collection_name.strip_edges()
	if clean.is_empty() or collections.has(clean):
		return false
	collections[clean] = []
	return true


func erase_collection(collection_name: String) -> bool:
	return collections.erase(collection_name)


## Rename a group, keeping the plants in it. A name that is already taken is refused rather than
## merged: two lists silently becoming one is not a rename.
func rename_collection(from_name: String, to_name: String) -> bool:
	var clean: String = to_name.strip_edges()
	if not collections.has(from_name) or clean.is_empty() or collections.has(clean):
		return false
	var moved: Variant = collections[from_name]
	collections.erase(from_name)
	collections[clean] = moved
	return true


func collection_names() -> Array[String]:
	var out: Array[String] = []
	for key: Variant in collections.keys():
		out.append(String(key))
	out.sort()
	return out


func has_collection(collection_name: String) -> bool:
	return collections.has(collection_name)


## Put a species in a group. An id that is not in the catalogue is refused: a collection of ids that
## are not plants is a list that cannot be planted and cannot explain itself.
func add_to_collection(collection_name: String, id: StringName) -> bool:
	if not collections.has(collection_name) or not species.has(id):
		return false
	var list: Array = collections[collection_name]
	if list.has(id):
		return true
	list.append(id)
	# Sorted by **string**, because a `StringName` has no lexicographic order: `Array.sort()` on a
	# list of them produces an order that is stable and meaningless, and a group that lists its
	# plants in an order nobody can predict is a group nobody can check.
	list.sort_custom(func(first: Variant, second: Variant) -> bool:
		return String(first) < String(second))
	return true


func remove_from_collection(collection_name: String, id: StringName) -> bool:
	if not collections.has(collection_name):
		return false
	var list: Array = collections[collection_name]
	if not list.has(id):
		return false
	list.erase(id)
	return true


## Which groups a species is in, so a detail view can tick the boxes.
func collections_of(id: StringName) -> Array[String]:
	var out: Array[String] = []
	for key: Variant in collections.keys():
		var list: Array = collections[key]
		if list.has(id):
			out.append(String(key))
	out.sort()
	return out


func collection(collection_name: String) -> Array[PlantSpecies]:
	var out: Array[PlantSpecies] = []
	if not collections.has(collection_name):
		return out
	var list: Array = collections[collection_name]
	for id: Variant in list:
		var plant: PlantSpecies = get_species(StringName(id))
		if plant != null:
			out.append(plant)
	return out


func collection_count(collection_name: String) -> int:
	return collection(collection_name).size()


func save_collections(path: String = COLLECTIONS_PATH) -> Dictionary:
	var out: Dictionary = {}
	for key: Variant in collections.keys():
		var list: Array = collections[key]
		var names: Array = []
		for id: Variant in list:
			names.append(String(id))
		out[String(key)] = names
	return write_json(out, path)


## Read the collections back. A group naming a species the catalogue does not have keeps the name
## and drops the id, and says so: silently losing a person's list is worse than an empty list.
func load_collections(path: String = COLLECTIONS_PATH) -> Dictionary:
	var read: Dictionary = read_json(path)
	if not bool(read["ok"]):
		return {"ok": false, "reason": String(read["reason"]), "dropped": []}
	var raw_data: Variant = read["data"]
	if not (raw_data is Dictionary):
		return {
			"ok": false,
			"reason": "%s is not a collections file: it is not a JSON object" % path,
			"dropped": [],
		}
	var data: Dictionary = raw_data
	var dropped: Array[String] = []
	for key: Variant in data.keys():
		var raw: Variant = data[key]
		if not (raw is Array):
			dropped.append("%s is not a list of plants" % key)
			continue
		var kept: Array = []
		for id: Variant in raw:
			if species.has(StringName(id)):
				kept.append(StringName(id))
			else:
				dropped.append("%s names %s, which is not in the catalogue" % [key, id])
		collections[String(key)] = kept
	return {"ok": true, "reason": "", "dropped": dropped}


# --- what is loaded, and loaded once ----------------------------------------------------


## The 2D image for the browser's grid, or null when the species has none - in which case the
## browser draws the form's plan symbol instead, because a species with no thumbnail is not a
## species with no picture.
##
## The **misses are cached too**: a grid asks for the same thumbnail on every redraw, and a missing
## file that is checked four hundred times a second is four hundred stat calls.
func thumbnail_for(id: StringName) -> Texture2D:
	var plant: PlantSpecies = get_species(id)
	if plant == null or plant.thumbnail.is_empty():
		return null
	var path: String = plant.thumbnail
	if _thumbnails.has(path):
		return _thumbnails[path] as Texture2D
	var texture: Texture2D = null
	if ResourceLoader.exists(path, "Texture2D"):
		texture = ResourceLoader.load(path, "Texture2D") as Texture2D
		_thumbnail_loads += 1
	_thumbnails[path] = texture
	return texture


## The scene a species is planted as: its own model when it has one, and the form it is drawn as
## otherwise. Cached the same way, so placing twenty red maples loads one tree.
func scene_for(id: StringName) -> PackedScene:
	var plant: PlantSpecies = get_species(id)
	if plant == null:
		return null
	var path: String = plant.model_scene if not plant.model_scene.is_empty() else plant.form
	if path.is_empty():
		return null
	if _scenes.has(path):
		return _scenes[path] as PackedScene
	var scene: PackedScene = null
	if ResourceLoader.exists(path, "PackedScene"):
		scene = ResourceLoader.load(path, "PackedScene") as PackedScene
		_scene_loads += 1
	_scenes[path] = scene
	return scene


func clear_cache() -> void:
	_thumbnails.clear()
	_scenes.clear()


## How many files have really been loaded, for a test that has to prove the cache is doing
## something. Two species sharing a form is one load, not two.
func cache_loads() -> Dictionary:
	return {"thumbnails": _thumbnail_loads, "scenes": _scene_loads}


# --- persistence ------------------------------------------------------------------------


func to_dict() -> Dictionary:
	var out: Dictionary = {}
	for id: StringName in ids():
		out[String(id)] = get_species(id).to_dict()
	return {
		"version": version,
		"source": source,
		"species": out,
	}


## The catalogue as text a person can open. Indented, because the first reader of a plant list is a
## designer checking what a nursery sent.
func to_json() -> String:
	return JSON.stringify(to_dict(), "  ")


static func from_dict(data: Dictionary) -> PlantCatalogue:
	var catalogue: PlantCatalogue = PlantCatalogue.new(int(data.get("version", 1)))
	catalogue.source = String(data.get("source", ""))
	var raw: Variant = data.get("species", {})
	if raw is Dictionary:
		for key: Variant in (raw as Dictionary).keys():
			var entry: Variant = (raw as Dictionary)[key]
			if not (entry is Dictionary):
				catalogue.rejected.append("plant %s is not an object" % key)
				continue
			var plant: PlantSpecies = PlantSpecies.from_dict(entry)
			if not catalogue.put(plant):
				catalogue.rejected.append("plant %s was in the file but is not usable: %s" % [
					key, plant.problem()
				])
	return catalogue


## Write the catalogue, through a temporary file and a rename, for the same reason a drawing and a
## cost book are written that way: a save that fails must not leave a shorter plant list behind.
func save_to(path: String = DEFAULT_PATH) -> Dictionary:
	return write_json(to_dict(), path)


static func load_from(path: String = DEFAULT_PATH) -> Dictionary:
	var read: Dictionary = read_json(path)
	if not bool(read["ok"]):
		return {"ok": false, "reason": String(read["reason"]), "catalogue": null}
	# `read_json` returns whatever parsed, so the shape is checked here rather than assumed: a file
	# that is a bare list is a plant list, not a catalogue, and assigning it to a Dictionary would
	# be a run-time error rather than a refusal with a sentence.
	var raw: Variant = read["data"]
	if not (raw is Dictionary):
		return {
			"ok": false,
			"reason": "%s is not a plant catalogue: it is not a JSON object" % path,
			"catalogue": null,
		}
	var data: Dictionary = raw
	if not data.has("species") and not data.has("version"):
		return {
			"ok": false,
			"reason": "%s is not a plant catalogue: it has neither a version nor a species list" % path,
			"catalogue": null,
		}
	return {"ok": true, "reason": "", "catalogue": from_dict(data)}


## Take a plant list from somewhere else. What it does not have is added; a duplicate id is **left
## alone** and reported, unless `replace` says the incoming entry wins - because two lists disagree
## about a plant's size is a question for a person, not for whichever file was read second.
func import_json(path: String, replace: bool = false) -> Dictionary:
	var read: Dictionary = read_json(path)
	if not bool(read["ok"]):
		return {"ok": false, "reason": String(read["reason"]), "added": 0, "replaced": 0, "refused": []}
	# The file may be a catalogue of ours, or a bare list of plants - which is what a nursery's
	# export usually is, and refusing it would be refusing the commonest thing a person imports.
	var raw: Variant = read["data"]
	var entries: Array = []
	if raw is Array:
		entries = raw
	elif raw is Dictionary:
		var data: Dictionary = raw
		var list: Variant = data.get("species", data)
		if list is Dictionary:
			for entry_key: Variant in (list as Dictionary).keys():
				entries.append((list as Dictionary)[entry_key])
		elif list is Array:
			entries = list
	var added: int = 0
	var replaced: int = 0
	var refused: Array[String] = []
	for entry: Variant in entries:
		if not (entry is Dictionary):
			refused.append("an entry in the file is not an object")
			continue
		var plant: PlantSpecies = PlantSpecies.from_dict(entry)
		if not plant.is_valid():
			refused.append("plant %s: %s" % [
				String(plant.id) if not plant.id.is_empty() else "with no id", plant.problem()
			])
			continue
		if species.has(plant.id):
			if not replace:
				refused.append("plant %s is already in the catalogue, with the version already here" % plant.id)
				continue
			put(plant)
			replaced += 1
			continue
		add(plant)
		added += 1
	return {"ok": true, "reason": "", "added": added, "replaced": replaced, "refused": refused}


## Write the catalogue, or a chosen list of ids, where somebody else can read it - the other half of
## an import, and the way a designer sends a client a plant list.
func export_json(path: String, ids_to_write: Array = []) -> Dictionary:
	var data: Dictionary = to_dict()
	if not ids_to_write.is_empty():
		var chosen: Dictionary = {}
		for id: Variant in ids_to_write:
			var plant: PlantSpecies = get_species(StringName(id))
			if plant != null:
				chosen[String(plant.id)] = plant.to_dict()
		data["species"] = chosen
	var written: Dictionary = write_json(data, path)
	written["count"] = (data["species"] as Dictionary).size()
	return written


## Everything wrong with the catalogue, named: the entries a load could not use, then what is wrong
## with each stored entry. Ordered so the first line is the first thing to fix.
func problems() -> Array[String]:
	var out: Array[String] = []
	out.append_array(rejected)
	for id: StringName in ids():
		var problem: String = get_species(id).problem()
		if not problem.is_empty():
			out.append(problem)
	for key: Variant in collections.keys():
		for id: Variant in (collections[key] as Array):
			if not species.has(StringName(id)):
				out.append("collection %s names %s, which is not in the catalogue" % [key, id])
	return out


func is_sound() -> bool:
	return problems().is_empty()


## The entries whose form, model or thumbnail is not on disk. Opt-in rather than part of `problems()`:
## this is the only check that touches the disk once per species, and a browser filtering four
## thousand plants must not stat four thousand files every keystroke.
func missing_files() -> Array[String]:
	var out: Array[String] = []
	for id: StringName in ids():
		var plant: PlantSpecies = get_species(id)
		for path: String in [plant.form, plant.model_scene, plant.thumbnail]:
			if not path.is_empty() and not ResourceLoader.exists(path):
				out.append("plant %s: %s is not on disk" % [id, path])
	return out


func describe() -> String:
	return "Plant catalogue v%d (%d species, %d tags, %d collections)%s" % [
		version, species.size(), tag_names().size(), collections.size(),
		"" if source.is_empty() else " from %s" % source,
	]


# --- the two file operations, in one place ----------------------------------------------


## Write JSON through a temporary file and a rename. The same rule as a drawing and a cost book: a
## save that fails must not leave a shorter file where the real one was.
static func write_json(data: Variant, path: String) -> Dictionary:
	var folder: String = path.get_base_dir()
	if not DirAccess.dir_exists_absolute(folder):
		if DirAccess.make_dir_recursive_absolute(folder) != OK:
			return {"ok": false, "reason": "the folder %s cannot be made" % folder, "path": path}
	var temp: String = path + TEMP_SUFFIX
	var file: FileAccess = FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "reason": "%s cannot be written" % path, "path": path}
	file.store_string(JSON.stringify(data, "  "))
	file.close()
	if DirAccess.rename_absolute(temp, path) != OK:
		return {"ok": false, "reason": "the written file could not be moved into place", "path": path}
	return {"ok": true, "reason": "", "path": path}


## Read JSON, whatever shape it is in, refusing what cannot be parsed with the line the parser gave
## up on. `data` is the parsed value: this does not decide whether a list or an object was expected,
## because the answer differs between a catalogue of ours and a list somebody exported.
static func read_json(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "reason": "there is no file at %s" % path, "data": null}
	var text: String = file.get_as_text()
	file.close()
	# `JSON.new().parse()` rather than `JSON.parse_string()`: the latter logs an engine error on
	# malformed input, and a malformed file is a thing a person does, not an engine fault.
	var reader := JSON.new()
	if reader.parse(text) != OK:
		return {
			"ok": false,
			"reason": "%s is not readable JSON: %s (line %d)" % [
				path, reader.get_error_message(), reader.get_error_line()
			],
			"data": null,
		}
	return {"ok": true, "reason": "", "data": reader.data}