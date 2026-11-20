extends Node
## Read the leaves somebody has stated into the file the catalogue reads.
##
## The path a person takes: run this with no sheet and it writes one - every plant in the list, with the five
## leaf traits blank beside it - and prints the words each trait takes. Open that sheet in a spreadsheet, fill
## in the words, run this again, and the readings are written where the program looks for them. Running it a
## third time reports what the list now states, which is the same sentence the key page shows.
##
##     run_scene res://tools/leaf_reading.tscn
##
## The sheet lives in `user://` because it is somebody's working file and not part of the project; the
## readings it produces go to `res://data/plants/leaf_readings.json`, which **is** part of the project and is
## meant to be committed - the way `data/plants/nursery_list_more.json` is, for the same reason: the data
## should be readable and diffable rather than only inside a tool.
##
## **Nothing here invents a leaf.** A trait nobody wrote a word for is left blank, and a blank is not a
## statement: the readings file holds only what somebody read.

const ReadingsScript := preload("res://scripts/leaf_readings.gd")
const CatalogueScript := preload("res://scripts/plants/plant_catalogue.gd")
const SpeciesScript := preload("res://scripts/plants/plant_species.gd")

## The sheet a person fills in and the list it is written from. The readings file's own path is the module's,
## so the tool and the program cannot come to look in two different places.
const SHEET := "user://leaf_reading_sheet.json"
const SHEET_KEY := "plants"
const SHIPPED_LIST := "res://data/plants/nursery_list.json"


func _ready() -> void:
	var read: Dictionary = CatalogueScript.load_from(SHIPPED_LIST)
	if not bool(read["ok"]):
		print("LEAF READING FAILED the list could not be read: %s" % String(read["reason"]))
		get_tree().quit(1)
		return
	var catalogue: PlantCatalogue = read["catalogue"]
	print("the list holds %d plants" % catalogue.count())
	if not FileAccess.file_exists(SHEET):
		_write_sheet(catalogue)
		print("wrote a sheet to %s" % SHEET)
		print("fill in the words beside the plants that need them, then run this again.")
		print("the words each leaf takes:")
		for trait_name: StringName in SpeciesScript.LEAF_TRAITS:
			print("  %s: %s" % [String(trait_name), ReadingsScript.vocabularies(trait_name)])
		get_tree().quit()
		return
	_apply_sheet(catalogue)
	get_tree().quit()


## Write the blank sheet: every plant, and the five traits empty beside it. Empty rather than a default,
## because a default would be this tool stating a leaf nobody has looked at.
func _write_sheet(catalogue: PlantCatalogue) -> void:
	var rows: Dictionary = { }
	for id: StringName in catalogue.ids():
		var plant: PlantSpecies = catalogue.get_species(id)
		var blanks: Dictionary = { }
		for trait_name: StringName in SpeciesScript.LEAF_TRAITS:
			blanks[String(trait_name)] = ""
		blanks["name"] = plant.display_name()
		rows[String(id)] = blanks
	PlantCatalogue.write_json({ SHEET_KEY: rows }, SHEET)


## The sheet's rows with every column that is not a leaf taken out, and those columns named once.
##
## A sheet is a person's working file and grows columns that are not leaves - the plant's name, a date, the
## bed it is going in - so a column the five traits do not have is left out of the readings **once**, rather
## than refused once for every plant in the list. What is left still goes through the module, which refuses a
## word a trait does not have and a leaf it does not know, because those are about the readings themselves.
func _leaf_columns_only(rows: Dictionary) -> Dictionary:
	var kept: Dictionary = { }
	var strangers: PackedStringArray = PackedStringArray()
	for key: Variant in rows.keys():
		var entry: Variant = rows[key]
		if not (entry is Dictionary):
			continue
		var traits: Dictionary = { }
		for column: Variant in (entry as Dictionary).keys():
			var trait_name: StringName = StringName(column)
			if SpeciesScript.names_for(trait_name).is_empty():
				if not strangers.has(String(column)):
					strangers.append(String(column))
				continue
			traits[String(trait_name)] = String((entry as Dictionary)[column])
		kept[String(key)] = traits
	if not strangers.is_empty():
		print("not a leaf, so left out of the readings: %s" % ", ".join(strangers))
	return kept


## Turn the words somebody typed into the readings file, and say what happened in a way that names the plant
## and the word rather than only counting them.
func _apply_sheet(catalogue: PlantCatalogue) -> void:
	var loaded: Dictionary = CatalogueScript.read_json(SHEET)
	if not bool(loaded.get("ok", false)):
		print("LEAF READING FAILED the sheet could not be read: %s" % String(loaded.get("reason", "")))
		return
	var data: Variant = loaded.get("data", null)
	if not (data is Dictionary) or not (data as Dictionary).has(SHEET_KEY):
		print("LEAF READING FAILED %s holds no \"%s\"." % [SHEET, SHEET_KEY])
		return
	var rows: Variant = (data as Dictionary)[SHEET_KEY]
	if not rows is Dictionary:
		print("LEAF READING FAILED %s says \"%s\" is not a list of plants." % [SHEET, SHEET_KEY])
		return
	var written: Dictionary = ReadingsScript.write(_leaf_columns_only(rows as Dictionary))
	if not bool(written["ok"]):
		print("LEAF READING FAILED %s" % String(written["reason"]))
		return
	print("wrote %d reading(s) to %s" % [int(written["written"]), ReadingsScript.FILE_PATH])
	var refused: PackedStringArray = written["refused"]
	if refused.is_empty():
		print("and there was nothing in the sheet that could not be read.")
	else:
		print("%d line(s) could not be read, and are not in the file:" % refused.size())
		for line: String in refused:
			print("  %s" % line)
	# Read what was just written back through the program's own door, so the sentence below is the state of
	# the list rather than this tool's idea of it.
	var applied: Dictionary = ReadingsScript.apply(catalogue)
	if not bool(applied["ok"]):
		print("LEAF READING FAILED the readings could not be applied: %s" % String(applied["reason"]))
		return
	print("the list now states: %s" % ReadingsScript.states_words(catalogue))
