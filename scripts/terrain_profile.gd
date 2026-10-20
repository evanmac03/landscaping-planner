class_name TerrainProfile
extends RefCounted
## What the ground is like at one place on the plan: the light it gets, how wet it stays, what the
## soil is, and how freely it drains.
##
## A profile states **only what somebody has told it**. There is no default "medium" for a property
## nobody has set, because a plan that says nothing about how wet a spot is has not said "medium" -
## it has said nothing at all, and a check that read silence as an average would give a green ring to
## a willow in a bone-dry bed with exactly the confidence it gave to a willow in a bog. An unstated
## attribute is simply absent from `attrs`, and `PlantSuitability` reports the gap instead of
## filling it.
##
## The vocabulary is the plant table's, deliberately: a place's light level is stored as the same bit
## a species uses for the conditions it tolerates, and moisture uses the same 0..2 the species' water
## need does. Two vocabularies for one idea is how a check comes to compare "semi-shade" with
## "part shade" and decide they disagree.

const PlantSpeciesScript := preload("res://scripts/plant_species.gd")

## The light a place is in, one level at a time - a spot is not "full sun and part shade". The values
## are the species table's bits, so a plant's tolerated set can be tested against a place's single
## level with no translation in between.
const SUN_LEVELS: Array[int] = [
	PlantSpeciesScript.FULL_SUN, PlantSpeciesScript.PART_SHADE, PlantSpeciesScript.FULL_SHADE
]
const SUN_NAMES := PlantSpeciesScript.SUN_NAMES

## How wet a place stays, on the same scale as a species' water need.
const MOISTURE_LEVELS: Array[int] = [
	PlantSpeciesScript.WATER_LOW, PlantSpeciesScript.WATER_MEDIUM, PlantSpeciesScript.WATER_HIGH
]
const MOISTURE_NAMES := PlantSpeciesScript.WATER_NAMES

## The soil a place is on. A short list on purpose: a designer can tell sand from clay from loam by
## hand, and a forty-entry classification is a lab report.
##
## Reused from the plant table rather than restated - see `plant_species.gd` for why the vocabulary of
## growing conditions lives there. Two lists of soils is how a check comes to think "sandy loam" is a
## soil one side of it has never heard of.
const SAND := PlantSpeciesScript.SAND
const LOAM := PlantSpeciesScript.LOAM
const CLAY := PlantSpeciesScript.CLAY
const SILT := PlantSpeciesScript.SILT
const ORGANIC := PlantSpeciesScript.ORGANIC
const SOILS := PlantSpeciesScript.SOILS

## How freely a place drains: **one** of these, because a place drains one way. The values are the
## plant table's drainage bits, so a species' tolerated set is tested against a place's single bit
## with a bitwise and and nothing in between.
const DRAINAGE_FAST := PlantSpeciesScript.DRAINS_FAST
const DRAINAGE_MEDIUM := PlantSpeciesScript.DRAINS_MEDIUM
const DRAINAGE_SLOW := PlantSpeciesScript.DRAINS_SLOW
const DRAINAGE_NAMES := PlantSpeciesScript.DRAINAGE_NAMES

## The attributes a profile may state, in the order a person reads them.
const KEYS: Array[String] = ["sun", "moisture", "soil", "drainage", "zone"]
const KEY_LABELS := {
	"sun": "light",
	"moisture": "moisture",
	"soil": "soil",
	"drainage": "drainage",
	"zone": "hardiness zone",
}

## The value that means "this attribute is not stated", per kind of attribute.
const NO_LEVEL := -1

## What the profile states: key -> value, and nothing else.
var attrs: Dictionary = {}


## `given` and not `stated`: "stated" is the name of the function that reads one attribute back, and a
## parameter that shadows it is an error rather than a convenience.
func _init(given: Dictionary = {}) -> void:
	for key: Variant in given:
		var attribute: String = String(key)
		if is_known_key(attribute):
			attrs[attribute] = given[key]


static func make(given: Dictionary = {}) -> TerrainProfile:
	return (load("res://scripts/terrain_profile.gd") as GDScript).new(given)


## A profile stating one thing. `TerrainProfile.of("sun", TerrainProfile.FULL_SHADE)`.
static func of(key: String, value: Variant) -> TerrainProfile:
	var profile: TerrainProfile = make()
	profile.attrs[key] = value
	return profile


## State one more thing, and answer with itself so several can be chained.
func with(key: String, value: Variant) -> TerrainProfile:
	if is_known_key(key):
		attrs[key] = value
	return self


func forget(key: String) -> TerrainProfile:
	attrs.erase(key)
	return self


## What "not stated" is for one attribute, and **it is a different value in every set**, because each
## holds a different kind of value: no light level is 0 (the levels are 1, 2 and 4), no moisture is
## -1 - **0 is a real moisture level**, low water, so it cannot be the missing one - no soil is the
## empty name, and no zone is 0, which is the "zone 0 is not a zone" rule `PlantSpecies` already uses.
##
## A rule like this belongs beside the values it is about rather than in whichever menu first needed
## it: every way into the ground - a dialog, a menu, a script, a test - has to agree about what
## "nothing stated" looks like, and the place they agree in is here.
static func no_value(key: String) -> Variant:
	if key == "soil":
		return &""
	if key == "sun" or key == "zone":
		return 0
	return NO_LEVEL


## Whether a value states something, rather than being that attribute's "not stated".
static func value_stated(key: String, value: Variant) -> bool:
	if key == "soil":
		return not StringName(value).is_empty()
	if key == "sun" or key == "zone":
		return int(value) > 0
	return int(value) >= 0


## State one attribute, or take the statement back when the value is that attribute's "not stated".
##
## The one place that decides between `with` and `forget`, so that choosing "not stated" in a dialog
## un-states an attribute rather than storing a value that means nothing and would fail validation.
func with_stated(key: String, value: Variant) -> TerrainProfile:
	if not is_known_key(key):
		return self
	if value_stated(key, value):
		return with(key, value)
	return forget(key)


## The attribute as a form reads it: the stated value, or that attribute's "not stated".
func stated(key: String) -> Variant:
	if not attrs.has(key):
		return no_value(key)
	match key:
		"sun":
			return sun_level()
		"moisture":
			return moisture_level()
		"soil":
			return soil_name()
		"drainage":
			return drainage_level()
	return zone()


func is_known_key(key: String) -> bool:
	return KEYS.has(key)


## Whether anything at all has been stated. An empty profile is the honest starting state of a plan
## nobody has described yet, and it is what makes the first suitability check say "the plan does not
## say" rather than inventing a garden.
func is_empty() -> bool:
	return attrs.is_empty()


func has(key: String) -> bool:
	return attrs.has(key)


func stated_keys() -> Array[String]:
	var out: Array[String] = []
	for key: String in KEYS:
		if attrs.has(key):
			out.append(key)
	return out


# --- the values, typed -------------------------------------------------------------------


func sun_level() -> int:
	return int(attrs.get("sun", 0))


func moisture_level() -> int:
	return int(attrs.get("moisture", NO_LEVEL))


func soil_name() -> StringName:
	return StringName(attrs.get("soil", ""))


func drainage_level() -> int:
	return int(attrs.get("drainage", NO_LEVEL))


## The hardiness zone *at this spot*, or 0 when it is not stated. A site has a zone and a frost pocket
## is colder than the rest of it, which is why this is a property of the place rather than of the
## drawing.
func zone() -> int:
	return int(attrs.get("zone", 0))


# --- combining -------------------------------------------------------------------------


## This profile laid over another one: everything `base` states, with everything this one states
## taking precedence. This is how a zone is stored - **only what it says**, not a whole restated
## garden - so a designer who marks a bed "full shade" has not also claimed to know its soil.
func merged_over(base: TerrainProfile) -> TerrainProfile:
	var out: TerrainProfile = TerrainProfile.make(base.attrs if base != null else {})
	for key: String in stated_keys():
		out.attrs[key] = attrs[key]
	return out


func equals(other: TerrainProfile) -> bool:
	if other == null or other.stated_keys() != stated_keys():
		return false
	for key: String in stated_keys():
		if attrs[key] != other.attrs[key]:
			return false
	return true


func copy() -> TerrainProfile:
	return TerrainProfile.make(attrs.duplicate(true))


# --- reading and writing -----------------------------------------------------------------


## What is wrong with a profile, in a sentence, or "" when nothing is.
##
## Refuse and name it, as the rest of this project does: `{"sun": "half sun"}` is not a light level,
## and a profile that kept it would never match any plant - a spot that silently suits nothing at all,
## which looks like horticulture and is a typo.
func problem() -> String:
	for key: String in attrs:
		if not is_known_key(key):
			return "\"%s\" is not something a place can state" % key
		var value: Variant = attrs[key]
		if key == "sun" and not SUN_LEVELS.has(int(value)):
			return "light level %s is not one of %s" % [str(value), _list(SUN_NAMES)]
		if key == "moisture" and not MOISTURE_LEVELS.has(int(value)):
			return "moisture %s is not one of %s" % [str(value), _list(MOISTURE_NAMES)]
		if key == "soil" and not SOILS.has(StringName(value)):
			return "soil \"%s\" is not one of %s" % [str(value), _list(SOILS)]
		if key == "drainage" and not DRAINAGE_NAMES.has(int(value)):
			return "drainage %s is not one of %s" % [str(value), _list(DRAINAGE_NAMES)]
		if key == "zone" and (int(value) < PlantSpeciesScript.ZONE_MIN or int(value) > PlantSpeciesScript.ZONE_MAX):
			return "zone %s is not a hardiness zone" % str(value)
	return ""


func is_valid() -> bool:
	return problem().is_empty()


static func _list(names: Dictionary) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for value: Variant in names.values():
		parts.append(String(value))
	return ", ".join(parts)


## One attribute in words, or "" when it is not stated.
func text_of(key: String) -> String:
	if not attrs.has(key):
		return ""
	match key:
		"sun":
			return String(SUN_NAMES.get(sun_level(), "?"))
		"moisture":
			return String(MOISTURE_NAMES.get(moisture_level(), "?"))
		"soil":
			return String(SOILS.get(soil_name(), "?"))
		"drainage":
			return String(DRAINAGE_NAMES.get(drainage_level(), "?"))
		"zone":
			return "zone %d" % zone()
	return ""


## The profile as a person would read it: "full shade, medium moisture, loam".
func describe() -> String:
	var parts: PackedStringArray = PackedStringArray()
	for key: String in stated_keys():
		var words: String = text_of(key)
		if not words.is_empty():
			parts.append(words)
	if parts.is_empty():
		return "nothing stated about this spot"
	return ", ".join(parts)


func to_dict() -> Dictionary:
	var out: Dictionary = {}
	for key: String in stated_keys():
		var value: Variant = attrs[key]
		# Not a ternary: it cannot hold a String on one side and an int on the other, which is the
		# one thing the soil needs - a name travels as a string, because a StringName in a JSON
		# dictionary is a type the reader on the other side has to guess at.
		if key == "soil":
			out[key] = String(value)
		else:
			out[key] = int(value)
	return out


## Read one back. Numbers come out of JSON as floats, so every level is coerced.
static func from_dict(data: Dictionary) -> TerrainProfile:
	var profile: TerrainProfile = TerrainProfile.make()
	if not (data is Dictionary):
		return profile
	for raw_key: Variant in data:
		var key: String = String(raw_key)
		if not profile.is_known_key(key):
			continue
		if key == "soil":
			profile.attrs[key] = StringName(data[raw_key])
		else:
			profile.attrs[key] = int(data[raw_key])
	return profile