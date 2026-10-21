class_name PlantSpecies
extends RefCounted
## One species a designer can plant: what it is called, where it will grow, how big it gets, and
## what it is drawn as.
##
## The horticultural fields are the ones a nursery label carries, and they are stored the way a
## nursery states them:
##
## * **Dimensions are whole centimetres.** A label says "60 cm tall, 45 cm across"; a metre value in
##   a float would not compare equal to itself after a round trip through JSON, and every "is this
##   smaller than that" question would need a tolerance. Centimetres are exact, they sort, and
##   `height_m()` is there for the plan.
## * **USDA zone is an integer range**, 1..13, because "hardy in zone 7" is a range a plant has, not
##   a number it approximates.
## * **Sun is a set of bits, not a single value**: a great many plants take full sun *and* part
##   shade, and a single choice would force a designer to pick one and be wrong half the time.
## * **Bloom is a set of months**, also bits, and the set is **circular**: a witch hazel blooms
##   November to March, which is one run of months across the new year, and a filter for "blooms in
##   January" has to find it.
##
## What a species is *drawn* as is a property of the entry (`form`, `model_scene`, `thumbnail`), not
## of a name: there is one tree model and four thousand trees. The **symbol** the plan draws for it is
## derived from what the plant *is* - its category, and whether it is a conifer - by `PlantSymbols`,
## because a form is one prop for four thousand trees and a spruce and a maple must not come out as
## the same green disc. See `planting_scale()` for how a species' own spread becomes the size of the
## thing placed on the plan.

const CATEGORY_NAMES := {
	0: "Tree",
	1: "Shrub",
	2: "Perennial",
	3: "Annual",
	4: "Ornamental grass",
	5: "Groundcover",
	6: "Vine",
	7: "Fern",
	8: "Bulb",
	9: "Herb",
}
const TREE := 0
const SHRUB := 1
const PERENNIAL := 2
const ANNUAL := 3
const GRASS := 4
const GROUNDCOVER := 5
const VINE := 6
const FERN := 7
const BULB := 8
const HERB := 9

## The genera that are conifers. A botanical fact about a plant, asked of the botanical name rather
## than of a tag: the tag a nursery writes is "evergreen", and a boxwood is evergreen without being a
## conifer. `PlantSymbols` is the one caller - which shape a plant is drawn as is its business, and
## whether a plant is a conifer is this one's.
const CONIFER_GENERA := [
	"Abies", "Cedrus", "Chamaecyparis", "Cryptomeria", "Cupressus", "Juniperus", "Larix",
	"Metasequoia", "Picea", "Pinus", "Pseudotsuga", "Taxodium", "Taxus", "Thuja", "Tsuga",
]

## Sun tolerance, as bits. A plant that takes both is `FULL_SUN | PART_SHADE`.
const FULL_SUN := 1
const PART_SHADE := 2
const FULL_SHADE := 4
const SUN_NAMES := {FULL_SUN: "full sun", PART_SHADE: "part shade", FULL_SHADE: "full shade"}

const WATER_LOW := 0
const WATER_MEDIUM := 1
const WATER_HIGH := 2
const WATER_NAMES := {WATER_LOW: "low water", WATER_MEDIUM: "medium water", WATER_HIGH: "high water"}

## The soils a species will grow in. **Empty means the catalogue does not say**, which is not the same
## as "any soil": a question nobody answered is skipped, not answered on their behalf.
##
## This table and the drainage bits below are the *vocabulary of growing conditions*, and they live
## here rather than in `TerrainProfile` because this is where they were first needed and because a
## place's conditions are described in the same words a plant's needs are. `TerrainProfile` reuses
## them verbatim - a light level is the same bit, a moisture level the same number - so that no
## translation layer can ever decide that "semi-shade" and "part shade" are different things.
const SAND := &"SAND"
const LOAM := &"LOAM"
const CLAY := &"CLAY"
const SILT := &"SILT"
const ORGANIC := &"ORGANIC"
const SOILS := {
	SAND: "sand",
	LOAM: "loam",
	CLAY: "clay",
	SILT: "silt",
	ORGANIC: "organic",
}

## The drainage a species tolerates, as **bits**, because a plant very often takes more than one kind
## of ground. A *place* drains one way, so a place's drainage is a single bit of the same set, and
## asking whether a plant belongs there is a bitwise test with nothing in between.
##
## `DRAINS_ANY` is the default: a catalogue that says nothing about drainage must not make every
## plant in it wrong on a heavy clay site.
const DRAINS_FAST := 1
const DRAINS_MEDIUM := 2
const DRAINS_SLOW := 4
const DRAINS_ANY := 7
const DRAINAGE_NAMES := {
	DRAINS_FAST: "fast-draining",
	DRAINS_MEDIUM: "moderately drained",
	DRAINS_SLOW: "slow-draining",
}

## USDA hardiness zones 1..13. Zone 0 is not a zone: it is a missing value, and a plant that claims
## it would be offered to every customer in the coldest climate the map has.
const ZONE_MIN := 1
const ZONE_MAX := 13

const MONTH_NAMES := [
	"January", "February", "March", "April", "May", "June",
	"July", "August", "September", "October", "November", "December",
]

## The longest name worth storing. A nursery list with a 4,000-character "name" is a paste accident.
const MAX_NAME := 120

var id: StringName = &""
var botanical_name: String = ""
var common_name: String = ""
## The cultivar, without quotes: "Autumn Blaze".
var cultivar: String = ""
var category: int = SHRUB
var zone_min: int = ZONE_MIN
var zone_max: int = ZONE_MAX
## Mature size, in whole centimetres.
var height_cm: int = 0
var spread_cm: int = 0
var sun: int = FULL_SUN
var water: int = WATER_MEDIUM
## The soils it will grow in, from `SOILS`. Empty means the catalogue does not say.
var soils: Array[StringName] = []
## The drainage it tolerates, as bits from `DRAINS_*`. `DRAINS_ANY` means it is not stated.
var drainage: int = DRAINS_ANY
## Bloom months as bits, bit `month - 1` set. Zero means it is grown for its foliage.
var bloom_months: int = 0
var bloom_colour: Color = Color(0.89, 0.42, 0.6)
## The prop scene this species is drawn as - its 2D plan symbol and its 3D model both come from it.
## One tree model is shared by every tree in the catalogue rather than one scene per species.
var form: String = "res://scenes/props/shrub.tscn"
## Its own 3D model, when it has one (a GLB or a scene). Empty means the form scene stands in.
var model_scene: String = ""
## A 2D image for the browser's thumbnail grid. Empty means the form scene's plan symbol is drawn.
var thumbnail: String = ""
var tags: Array[String] = []
var note: String = ""


func _init(species_id: StringName = &"", botanical: String = "", common: String = "") -> void:
	id = species_id
	botanical_name = botanical
	common_name = common


## The ordinary way to make one. Sizes are centimetres, as a label states them.
static func make(
	species_id: StringName,
	botanical: String,
	common: String,
	height: int,
	spread: int,
	kind: int = SHRUB
) -> PlantSpecies:
	var species: PlantSpecies = PlantSpecies.new(species_id, botanical, common)
	species.height_cm = height
	species.spread_cm = spread
	species.category = kind
	return species


# --- horticulture -----------------------------------------------------------------------


func hardy_in(zone: int) -> bool:
	return zone >= zone_min and zone <= zone_max


## Whether the plant will take the light it is offered. The argument is a single sun bit, so a
## designer asks "will this live in full shade?" rather than choosing between three answers.
func takes_sun(kind: int) -> bool:
	return (sun & kind) != 0


func blooms_in(month: int) -> bool:
	if month < 1 or month > 12:
		return false
	return (bloom_months & (1 << (month - 1))) != 0


func set_blooms_in(month: int, blooming: bool) -> void:
	if month < 1 or month > 12:
		return
	var bit: int = 1 << (month - 1)
	bloom_months = (bloom_months | bit) if blooming else (bloom_months & ~bit)


func height_m() -> float:
	return float(height_cm) / 100.0


func spread_m() -> float:
	return float(spread_cm) / 100.0


## How much to scale the form scene so that what is planted is the size the catalogue says, rather
## than the size the generic model happens to be. A species that spreads 4.5 m drawn as a form whose
## own footprint is 3.7 m is planted at 1.216.
##
## The base size comes in rather than being looked up here: this module knows plant data, and the
## table that says how big a prop scene stands for is a plan-style table, which is not this module's
## business to read.
func planting_scale(base_size_m: float) -> float:
	if base_size_m <= 0.0 or spread_cm <= 0:
		return 1.0
	return spread_m() / base_size_m


## The bloom months as a person would say them, with the new year handled: November to March is one
## run of five months, not two disconnected runs. Empty when the plant is grown for its foliage.
func bloom_text() -> String:
	if bloom_months == 0:
		return ""
	if bloom_months == 0xFFF:
		return "all year"
	# Start at a month that blooms and whose predecessor does not, so a run that crosses December
	# begins in November rather than in January.
	var start: int = 0
	for month in range(1, 13):
		if blooms_in(month) and not blooms_in(((month - 2 + 12) % 12) + 1):
			start = month
			break
	var runs: PackedStringArray = PackedStringArray()
	var month: int = start
	# The counter is months **traversed**, not steps taken: a step that consumes a five-month run
	# traverses five months, and counting steps instead let the walk come back round to the run it
	# had just written and print it again - forever.
	var traversed: int = 0
	while traversed < 12:
		if not blooms_in(month):
			month = (month % 12) + 1
			traversed += 1
			continue
		var run_start: int = month
		var last: int = month
		for step in 12:
			var next: int = (month % 12) + 1
			if not blooms_in(next):
				break
			last = next
			month = next
		runs.append(_run_text(run_start, last))
		traversed += 1 + ((last - run_start + 12) % 12)
		month = (last % 12) + 1
	return ", ".join(runs)


static func _run_text(first: int, last: int) -> String:
	var first_name: String = MONTH_NAMES[first - 1]
	if first == last:
		return first_name
	return "%s-%s" % [first_name, MONTH_NAMES[last - 1]]


func sun_text() -> String:
	var parts: PackedStringArray = PackedStringArray()
	for kind: int in [FULL_SUN, PART_SHADE, FULL_SHADE]:
		if takes_sun(kind):
			parts.append(String(SUN_NAMES[kind]))
	return "full sun" if parts.is_empty() else ", ".join(parts)


func water_text() -> String:
	return String(WATER_NAMES.get(water, "?"))


## The soils it takes, in words, or "" when the catalogue does not say. The empty answer is reported
## as empty on purpose: a suitability check that treated it as "any soil" would be inventing a fact
## about the plant, and one that treated it as "no soil" would make every plant in an incomplete
## catalogue wrong everywhere.
func soil_text() -> String:
	var parts: PackedStringArray = PackedStringArray()
	for soil: StringName in soils:
		parts.append(String(SOILS.get(soil, "?")))
	return ", ".join(parts)


## The drainage it takes, in words, or "" when it is not stated.
func drainage_text() -> String:
	if drainage >= DRAINS_ANY:
		return ""
	var parts: PackedStringArray = PackedStringArray()
	for bit: int in [DRAINS_FAST, DRAINS_MEDIUM, DRAINS_SLOW]:
		if (drainage & bit) != 0:
			parts.append(String(DRAINAGE_NAMES[bit]))
	return ", ".join(parts)


func category_name() -> String:
	return String(CATEGORY_NAMES.get(category, "?"))


# --- what it is drawn as -----------------------------------------------------------------


## The genus: the first word of the botanical name, or "" when the entry has no botanical name.
func genus() -> String:
	var parts: PackedStringArray = botanical_name.strip_edges().split(" ", false)
	return parts[0] if parts.size() > 0 else ""


## Whether this is a conifer, which is a question about the botanical name rather than about a tag:
## `"evergreen"` would catch a boxwood, and a boxwood is a broadleaf.
func is_conifer() -> bool:
	return CONIFER_GENERA.has(genus())


## "Acer rubrum 'Autumn Blaze' - Red maple". The cultivar is quoted, because that is what makes a
## cultivar a cultivar and it is how a nursery list writes it.
func display_name() -> String:
	var botanical: String = botanical_name
	if not cultivar.strip_edges().is_empty():
		botanical = "%s '%s'" % [botanical_name, cultivar]
	if common_name.strip_edges().is_empty():
		return botanical
	return "%s - %s" % [botanical, common_name]


## Everything a person might type into a search box for this plant, lowercased.
func search_text() -> String:
	var parts: PackedStringArray = PackedStringArray([
		String(id), botanical_name, common_name, cultivar, category_name()
	])
	parts.append_array(PackedStringArray(tags))
	return " ".join(parts).to_lower()


# --- validation -------------------------------------------------------------------------


## What is wrong with this entry, in a sentence, or "" when nothing is. Refuse and name it: a
## species with a zone of zero or a size of nothing is offered to a designer as a real plant.
func problem() -> String:
	if id.is_empty():
		return "a plant needs an id"
	if botanical_name.strip_edges().is_empty():
		return "plant %s has no botanical name" % id
	if botanical_name.length() > MAX_NAME or common_name.length() > MAX_NAME:
		return "plant %s has a name longer than %d characters" % [id, MAX_NAME]
	if not CATEGORY_NAMES.has(category):
		return "plant %s has category %d, which is not a category" % [id, category]
	if zone_min < ZONE_MIN or zone_max > ZONE_MAX or zone_min > zone_max:
		return "plant %s is hardy in zones %d..%d, which is not a zone range" % [
			id, zone_min, zone_max
		]
	if height_cm < 0 or spread_cm < 0:
		return "plant %s has a negative size" % id
	if height_cm == 0 and spread_cm == 0:
		return "plant %s has no size at all, so it cannot be planted" % id
	if sun == 0 or (sun & ~(FULL_SUN | PART_SHADE | FULL_SHADE)) != 0:
		return "plant %s has sun %d, which is not a set of light conditions" % [id, sun]
	if not WATER_NAMES.has(water):
		return "plant %s has water %d, which is not a water need" % [id, water]
	for soil: StringName in soils:
		if not SOILS.has(soil):
			return "plant %s grows in \"%s\", which is not a soil" % [id, String(soil)]
	if drainage == 0 or (drainage & ~DRAINS_ANY) != 0:
		return "plant %s has drainage %d, which is not a set of drainages" % [id, drainage]
	if (bloom_months & ~0xFFF) != 0:
		return "plant %s blooms in months outside January..December (bits %d)" % [id, bloom_months]
	if form.strip_edges().is_empty():
		return "plant %s does not say what it is drawn as" % id
	return ""


func is_valid() -> bool:
	return problem().is_empty()


# --- persistence ------------------------------------------------------------------------


func copy() -> PlantSpecies:
	return from_dict(to_dict())


## The soil names as plain strings, because a StringName in a JSON dictionary is a type the reader on
## the other side has to guess at.
func _soil_names() -> Array:
	var out: Array = []
	for soil: StringName in soils:
		out.append(String(soil))
	return out


func to_dict() -> Dictionary:
	return {
		"id": String(id),
		"botanical_name": botanical_name,
		"common_name": common_name,
		"cultivar": cultivar,
		"category": category,
		"zone_min": zone_min,
		"zone_max": zone_max,
		"height_cm": height_cm,
		"spread_cm": spread_cm,
		"sun": sun,
		"water": water,
		"soils": _soil_names(),
		"drainage": drainage,
		"bloom_months": bloom_months,
		# With the `#`: `Color.from_string` on a bare hex run is not the parse it looks like, and a
		# colour that came back as the fallback would be a bloom the plan draws in the wrong colour.
		"bloom_colour": "#" + bloom_colour.to_html(false),
		"form": form,
		"model_scene": model_scene,
		"thumbnail": thumbnail,
		"tags": tags.duplicate(),
		"note": note,
	}


## Read one back. Every integer field is coerced: Godot's JSON parser has one number type and hands
## back floats, so a zone read straight through would be 7.0 (spec §2.1a).
static func from_dict(data: Dictionary) -> PlantSpecies:
	var species: PlantSpecies = PlantSpecies.new()
	species.id = StringName(data.get("id", ""))
	species.botanical_name = String(data.get("botanical_name", ""))
	species.common_name = String(data.get("common_name", ""))
	species.cultivar = String(data.get("cultivar", ""))
	species.category = int(data.get("category", SHRUB))
	species.zone_min = int(data.get("zone_min", ZONE_MIN))
	species.zone_max = int(data.get("zone_max", ZONE_MAX))
	species.height_cm = int(data.get("height_cm", 0))
	species.spread_cm = int(data.get("spread_cm", 0))
	species.sun = int(data.get("sun", FULL_SUN))
	species.water = int(data.get("water", WATER_MEDIUM))
	var raw_soils: Variant = data.get("soils", [])
	if raw_soils is Array:
		for soil: Variant in raw_soils:
			var name: StringName = StringName(soil)
			if not name.is_empty() and not species.soils.has(name):
				species.soils.append(name)
	species.drainage = int(data.get("drainage", DRAINS_ANY))
	species.bloom_months = int(data.get("bloom_months", 0))
	var colour_text: String = String(data.get("bloom_colour", ""))
	species.bloom_colour = Color.from_string(colour_text, Color(0.89, 0.42, 0.6)) if not colour_text.is_empty() else Color(0.89, 0.42, 0.6)
	species.form = String(data.get("form", "res://scenes/props/shrub.tscn"))
	species.model_scene = String(data.get("model_scene", ""))
	species.thumbnail = String(data.get("thumbnail", ""))
	var raw_tags: Variant = data.get("tags", [])
	if raw_tags is Array:
		for tag: Variant in raw_tags:
			var text: String = String(tag).strip_edges()
			if not text.is_empty() and not species.tags.has(text):
				species.tags.append(text)
	species.note = String(data.get("note", ""))
	return species