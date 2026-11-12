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
	"Abies",
	"Cedrus",
	"Chamaecyparis",
	"Cryptomeria",
	"Cupressus",
	"Juniperus",
	"Larix",
	"Metasequoia",
	"Picea",
	"Pinus",
	"Pseudotsuga",
	"Taxodium",
	"Taxus",
	"Thuja",
	"Tsuga",
]

## Sun tolerance, as bits. A plant that takes both is `FULL_SUN | PART_SHADE`.
const FULL_SUN := 1
const PART_SHADE := 2
const FULL_SHADE := 4
const SUN_NAMES := { FULL_SUN: "full sun", PART_SHADE: "part shade", FULL_SHADE: "full shade" }

const WATER_LOW := 0
const WATER_MEDIUM := 1
const WATER_HIGH := 2
const WATER_NAMES := { WATER_LOW: "low water", WATER_MEDIUM: "medium water", WATER_HIGH: "high water" }

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
const SOILS := { SAND: "sand", LOAM: "loam", CLAY: "clay", SILT: "silt", ORGANIC: "organic" }

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

## The leaf: the part of a plant a person standing in front of it is most able to describe, and the
## vocabulary a field guide's key is built from.
##
## These are the morphology a leaf is read by - how the leaves sit on the stem, whether a leaf is one
## blade or several, its outline, its edge, and the way its veins run - each stored as **bits** for the
## reason `sun` and `drainage` are: a species is often variable, and one value would force a choice that
## is wrong half the time.
##
## **Zero means it is not stated**, the rule `soils` and `drainage` keep. `PlantKey` is what makes that
## safe: it asks a leaf question only while every plant left states that leaf, so a plant nobody has
## described is never eliminated by a description nobody gave.
##
## The words are a field guide's, in plain English, so somebody who has looked at a leaf can answer.

## Where the leaves come off the stem: one at a time, in pairs, in rings, or all from the base.
const LEAF_ARRANGEMENT := &"leaf_arrangement"
## Whether a leaf is one blade, or several joined - which is the first thing a field guide asks.
const LEAF_COMPLEXITY := &"leaf_complexity"
## The outline of a leaf.
const LEAF_SHAPE := &"leaf_shape"
## The edge of a leaf.
const LEAF_MARGIN := &"leaf_margin"
## The way the veins run.
const LEAF_VENATION := &"leaf_venation"

## The five, in the order a person is asked them: the coarsest thing to see first, the veins of a leaf
## last, because that is the one most people have never looked at.
const LEAF_TRAITS: Array[StringName] = [
	LEAF_ARRANGEMENT,
	LEAF_COMPLEXITY,
	LEAF_SHAPE,
	LEAF_MARGIN,
	LEAF_VENATION,
]

const ARR_ALTERNATE := 1
const ARR_OPPOSITE := 2
const ARR_WHORLED := 4
const ARR_BASAL := 8
const ARRANGEMENT_NAMES := {
	ARR_ALTERNATE: "alternate",
	ARR_OPPOSITE: "opposite",
	ARR_WHORLED: "whorled",
	ARR_BASAL: "a rosette at the base",
}

const CMP_SIMPLE := 1
const CMP_PINNATE := 2
const CMP_PALMATE := 4
const CMP_TRIFOLIATE := 8
const CMP_BIPINNATE := 16
const COMPLEXITY_NAMES := {
	CMP_SIMPLE: "one blade",
	CMP_PINNATE: "many leaflets along a stem",
	CMP_PALMATE: "many leaflets from one point",
	CMP_TRIFOLIATE: "three leaflets",
	CMP_BIPINNATE: "twice divided",
}

const SHP_OVATE := 1
const SHP_OBOVATE := 2
const SHP_ELLIPTICAL := 4
const SHP_LANCEOLATE := 8
const SHP_OBLONG := 16
const SHP_CORDATE := 32
const SHP_RENIFORM := 64
const SHP_SPATULATE := 128
const SHP_LINEAR := 256
const SHP_ACICULAR := 512
const SHP_SCALE := 1024
const SHP_DELTOID := 2048
const SHAPE_NAMES := {
	SHP_OVATE: "oval and widest below the middle",
	SHP_OBOVATE: "oval and widest above the middle",
	SHP_ELLIPTICAL: "an even oval",
	SHP_LANCEOLATE: "long and narrow and pointed",
	SHP_OBLONG: "a rounded oblong",
	SHP_CORDATE: "heart-shaped",
	SHP_RENIFORM: "kidney-shaped",
	SHP_SPATULATE: "spoon-shaped",
	SHP_LINEAR: "narrow as grass",
	SHP_ACICULAR: "a needle",
	SHP_SCALE: "tiny scales",
	SHP_DELTOID: "triangular",
}

const MRG_ENTIRE := 1
const MRG_SERRATE := 2
const MRG_DENTATE := 4
const MRG_CRENATE := 8
const MRG_LOBED := 16
const MRG_SINUATE := 32
const MARGIN_NAMES := {
	MRG_ENTIRE: "smooth",
	MRG_SERRATE: "finely toothed",
	MRG_DENTATE: "toothed",
	MRG_CRENATE: "scalloped",
	MRG_LOBED: "lobed",
	MRG_SINUATE: "wavy",
}

const VEN_PINNATE := 1
const VEN_PALMATE := 2
const VEN_PARALLEL := 4
const VEN_DICHOTOMOUS := 8
const VENATION_NAMES := {
	VEN_PINNATE: "a midrib with side veins",
	VEN_PALMATE: "several ribs from one point",
	VEN_PARALLEL: "veins running parallel",
	VEN_DICHOTOMOUS: "veins forking in two",
}

## USDA hardiness zones 1..13. Zone 0 is not a zone: it is a missing value, and a plant that claims
## it would be offered to every customer in the coldest climate the map has.
const ZONE_MIN := 1
const ZONE_MAX := 13

const MONTH_NAMES := [
	"January",
	"February",
	"March",
	"April",
	"May",
	"June",
	"July",
	"August",
	"September",
	"October",
	"November",
	"December",
]

## The four seasons, as the months each one is. A person standing in front of a flowering plant knows the
## season it flowers in and very rarely the exact month, so the key asks the **season** and this table is
## the one place the season-to-month mapping is written - the key and any browser chip read this one.
##
## The seasons are meteorological (spring is March to May), which is the parting every garden calendar
## uses. Winter wraps the new year, which is why the months are a list rather than a run.
const SEASONS := {
	&"spring": [3, 4, 5],
	&"summer": [6, 7, 8],
	&"autumn": [9, 10, 11],
	&"winter": [12, 1, 2],
}

## The colours a flower is offered as, in the order a key asks them. A colour answer is a **bucket**, not
## the shade a nursery chose: the shipped list holds 125 distinct shades, which is not 125 answers anybody
## can give. `flower_colour_name` is what puts a shade in a bucket, and it is the same rule for the plant
## and for the person's answer, so the two can never come to use different words for one flower.
const FLOWER_COLOURS: Array[StringName] = [
	&"white",
	&"cream",
	&"yellow",
	&"orange",
	&"red",
	&"pink",
	&"purple",
	&"blue",
	&"green",
]

## The longest name worth storing. A nursery list with a 4,000-character "name" is a paste accident.
const MAX_NAME := 120

## Which parts of a plant are eaten, as **bits**, because a plant is very often more than one of these
## at once: chives are a leaf *and* a flower, a beet is a root and its own leaves. Zero means the
## catalogue does not say this is an edible plant, which is the same "a question nobody answered"
## rule `soils` keeps - an ornamental is not claiming to be inedible, it is simply not claiming.
##
## The names carry `EAT_` rather than the bare part, because `BULB` is already the eighth **category**
## and a bulb of garlic and a bulb of tulip are not the same kind of fact.
const EAT_LEAF := 1
const EAT_FRUIT := 2
const EAT_ROOT := 4
const EAT_BULB := 8
const EAT_STEM := 16
const EAT_FLOWER := 32
const EAT_SEED := 64
## Every part there is, so a validation can refuse a bit that is not one of them.
const EDIBLE_ANY := EAT_LEAF | EAT_FRUIT | EAT_ROOT | EAT_BULB | EAT_STEM | EAT_FLOWER | EAT_SEED
const EDIBLE_NAMES := {
	EAT_LEAF: "leaf",
	EAT_FRUIT: "fruit",
	EAT_ROOT: "root",
	EAT_BULB: "bulb",
	EAT_STEM: "stem",
	EAT_FLOWER: "flower",
	EAT_SEED: "seed",
}

## The family a food crop rotates with. A **name**, not a category, and empty for a plant nobody
## rotates - a fruit tree, a shrub, an ornamental. It exists for one question and one question only:
## *the same family shall not follow itself in the same bed*, which is the whole of crop rotation.
##
## The names are the groups a kitchen gardener actually rotates by, and `HERB_FAMILY` is deliberately
## spelled that way: `HERB` is already the ninth **category**, and a second meaning for one word is
## how two tables come to disagree about it.
const FAMILY_NONE := &""
const BRASSICA := &"BRASSICA"
const NIGHTSHADE := &"NIGHTSHADE"
const LEGUME := &"LEGUME"
const ALLIUM := &"ALLIUM"
const ROOT_CROP := &"ROOT"
const CUCURBIT := &"CUCURBIT"
const LEAFY := &"LEAFY"
const FRUITING := &"FRUITING"
const HERB_FAMILY := &"HERB"
const FAMILY_NAMES := {
	BRASSICA: "brassica",
	NIGHTSHADE: "nightshade",
	LEGUME: "legume",
	ALLIUM: "allium",
	ROOT_CROP: "root",
	CUCURBIT: "cucurbit",
	LEAFY: "leafy",
	FRUITING: "fruiting",
	HERB_FAMILY: "herb",
}

## The most tenths of an hour a day has: a crop cannot be asked for more sun than there is.
const MAX_SUN_HOURS_TENTHS := 240
## The heaviest a seasonal amount a plant is stated with can be: a tonne. A yield or a need beyond that
## is not a fine number but a mistyped one, and the catalogue refuses it rather than storing it.
const MAX_SEASON_GRAMS := 1000000

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
## The leaf morphology, as bits from the `ARR_*`, `CMP_*`, `SHP_*`, `MRG_*` and `VEN_*` tables above.
## Zero means the catalogue does not say.
var leaf_arrangement: int = 0
var leaf_complexity: int = 0
var leaf_shape: int = 0
var leaf_margin: int = 0
var leaf_venation: int = 0
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
## What of it is eaten, as bits from `EAT_LEAF`..`EAT_SEED`. Zero means the catalogue does not say
## this is an edible plant.
var edible_parts: int = 0
## The months it is harvested in, as bits, bit `month - 1`. Zero means it is not stated. The same
## **circular** set as `bloom_months`, and for the same reason: a leek stands through the winter and a
## winter kale is cut from November to March, which is one run of months across the new year.
var harvest_months: int = 0
## The family it rotates with, or `FAMILY_NONE`. See the family constants.
var family: StringName = FAMILY_NONE
## Days from sowing to the first harvest. Zero means it is not stated.
var maturity_days: int = 0
## The direct sun it needs to crop, in **tenths of an hour** (60 = 6.0 h). Zero means it is not
## stated.
##
## Tenths rather than a float, for the reason the sizes are whole centimetres: a requirement is
## compared and round-tripped, and a value that came back 6.0000000001 would not compare equal to the
## six it was stated as - which is a check that quietly never fires.
var sun_hours_tenths: int = 0
## How much one plant gives in a season, in **grams**. Zero means it is not stated.
##
## A yield is a rule of thumb a kitchen-garden book prints - "about two kilos of tomatoes a plant" - and
## not a measurement, and the catalogue states it or does not. It is the thing that turns "I want to
## feed four people" from a wish into a number of plants, beside the amount a person eats.
var yield_per_plant_g: int = 0
## How much of it one person eats in a season, in **grams**. Zero means it is not stated.
##
## The other half of the same rule of thumb, and stated **per crop** rather than guessed at, because a
## person eats a great deal more tomato than thyme and a single figure for "vegetables" would be a
## number nobody could act on.
var need_per_person_g: int = 0


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
	kind: int = SHRUB,
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


## Whether the catalogue says this plant flowers at all. A fern, a grass and a conifer grown for its
## habit state no month, and a plant that never flowers has no colour and no season to be asked about.
##
## This is what makes the flower questions safe to ask only while every remaining candidate blooms, in the
## same way the leaf questions are asked only of plants whose leaves somebody has read.
func blooms() -> bool:
	return bloom_months != 0


## A bloom colour as one of `FLOWER_COLOURS`: the bucket a person standing in front of the flower would
## answer with.
##
## The rule is deliberately coarse and written down rather than clever, because the shade a nursery chose
## can sit on a boundary and a person's word for it must not be a guess. A flower with almost no colour is
## white, or **cream** when it leans warm; otherwise the hue decides, with the one adjustment that matters
## in practice - a very pale or a very light red is a **pink** to everybody who is not a colourimeter.
##
## It is one rule used twice: the plant's own shade is bucketed by this function, and the answer a person
## gives is named by this function's vocabulary, so "pink" means the same flower on both sides. A shade
## that falls the other side of a boundary is what "take the last answer back" is for.
static func flower_colour_name(colour: Color) -> StringName:
	if colour.s < 0.12:
		# Nearly colourless: **white**, unless it leans distinctly warm. A true white or grey has no hue
		# to lean with - Godot answers hue 0 for it, which on its own would read as warm - so saturation
		# is what tells a white flower from a cream one.
		if colour.s < 0.02:
			return &"white"
		return &"cream" if (colour.h < 0.14 or colour.h > 0.94) else &"white"
	var deg: float = colour.h * 360.0
	if deg < 15.0 or deg >= 345.0:
		return &"pink" if (colour.s < 0.55 or colour.v > 0.85) else &"red"
	if deg < 42.0:
		return &"orange"
	if deg < 70.0:
		return &"yellow"
	if deg < 165.0:
		return &"green"
	if deg < 255.0:
		return &"blue"
	if deg < 310.0:
		return &"purple"
	return &"pink"


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
	return months_run_text(bloom_months)


## A set of months, as a person would say them: "November-March", or two runs, and "all year" for the
## whole set. The one place the circular-run wording is written, so the months a plant **blooms** and
## the months a crop is **harvested** cannot come out said two different ways.
static func months_run_text(bits: int) -> String:
	if bits == 0:
		return ""
	if bits == 0xFFF:
		return "all year"
	# Start at a month that is set and whose predecessor is not, so a run that crosses December
	# begins in November rather than in January.
	var start: int = 0
	for month in range(1, 13):
		if _month_set(bits, month) and not _month_set(bits, ((month - 2 + 12) % 12) + 1):
			start = month
			break
	var runs: PackedStringArray = PackedStringArray()
	var month: int = start
	# The counter is months **traversed**, not steps taken: a step that consumes a five-month run
	# traverses five months, and counting steps instead let the walk come back round to the run it
	# had just written and print it again - forever.
	var traversed: int = 0
	while traversed < 12:
		if not _month_set(bits, month):
			month = (month % 12) + 1
			traversed += 1
			continue
		var run_start: int = month
		var last: int = month
		for step in 12:
			var next: int = (month % 12) + 1
			if not _month_set(bits, next):
				break
			last = next
			month = next
		runs.append(_run_text(run_start, last))
		traversed += 1 + ((last - run_start + 12) % 12)
		month = (last % 12) + 1
	return ", ".join(runs)


## Whether one month (1..12) is in a set of month bits.
static func _month_set(bits: int, month: int) -> bool:
	if month < 1 or month > 12:
		return false
	return (bits & (1 << (month - 1))) != 0


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


# --- the leaf ------------------------------------------------------------------------------


## This plant's bits for one leaf trait, or 0 when it states nothing about it. **The one place a trait's
## name becomes the field that holds it**, so the filter, the key and a page cannot call one trait two
## different things; a name this file does not have is answered as nothing stated.
func leaf_trait(trait_name: StringName) -> int:
	match trait_name:
		LEAF_ARRANGEMENT:
			return leaf_arrangement
		LEAF_COMPLEXITY:
			return leaf_complexity
		LEAF_SHAPE:
			return leaf_shape
		LEAF_MARGIN:
			return leaf_margin
		LEAF_VENATION:
			return leaf_venation
	return 0


## The vocabulary of one leaf trait: the bits and the words a person reads. There is **one table per
## trait** and it is the same table the key offers answers from, so a trait's values and their words
## cannot come apart. A trait this file does not have answers with nothing at all.
static func names_for(trait_name: StringName) -> Dictionary:
	match trait_name:
		LEAF_ARRANGEMENT:
			return ARRANGEMENT_NAMES
		LEAF_COMPLEXITY:
			return COMPLEXITY_NAMES
		LEAF_SHAPE:
			return SHAPE_NAMES
		LEAF_MARGIN:
			return MARGIN_NAMES
		LEAF_VENATION:
			return VENATION_NAMES
	return { }


# --- food ---------------------------------------------------------------------------------


## Whether the catalogue says this is something you eat. Not a guess from a tag and not a guess from
## the category: a plant is food when it names a part of itself that is eaten.
func is_edible() -> bool:
	return edible_parts != 0


## The parts that are eaten, as a person would say them: "leaf, flower". Empty when the catalogue does
## not say it is edible.
func edible_parts_text() -> String:
	var parts: PackedStringArray = PackedStringArray()
	for bit: int in [EAT_LEAF, EAT_FRUIT, EAT_ROOT, EAT_BULB, EAT_STEM, EAT_FLOWER, EAT_SEED]:
		if (edible_parts & bit) != 0:
			parts.append(String(EDIBLE_NAMES[bit]))
	return ", ".join(parts)


func harvests_in(month: int) -> bool:
	return _month_set(harvest_months, month)


func set_harvests_in(month: int, harvesting: bool) -> void:
	if month < 1 or month > 12:
		return
	var bit: int = 1 << (month - 1)
	harvest_months = (harvest_months | bit) if harvesting else (harvest_months & ~bit)


## The harvest window as a person would say it: "July-October", with the new year handled the way a
## bloom is. Empty when it is not stated.
func harvest_text() -> String:
	return months_run_text(harvest_months)


## The family it rotates with, in words, or "" when it is not stated.
func family_name() -> String:
	return String(FAMILY_NAMES.get(family, ""))


## The direct sun it needs, in hours.
func sun_hours() -> float:
	return float(sun_hours_tenths) / 10.0


## The sun it needs, in hours, as a person would say it: "6 hours" or "6.5 hours". Empty when it is
## not stated.
func sun_hours_text() -> String:
	if sun_hours_tenths <= 0:
		return ""
	var hours: float = sun_hours()
	if is_equal_approx(hours, roundf(hours)):
		var whole: int = int(roundf(hours))
		return "%d hour%s" % [whole, "" if whole == 1 else "s"]
	return "%.1f hours" % hours


## Days to the first harvest, in words, or "" when it is not stated.
func maturity_text() -> String:
	if maturity_days <= 0:
		return ""
	return "%d day%s" % [maturity_days, "" if maturity_days == 1 else "s"]


## Whether the catalogue says enough to work out how many plants feed somebody: how much one gives and
## how much one person eats. Both, or there is nothing to divide.
func can_yield() -> bool:
	return yield_per_plant_g > 0 and need_per_person_g > 0


## How much one plant gives in a season, in words: "2 kg" or "450 g". Empty when it is not stated.
func yield_text() -> String:
	return weight_text(yield_per_plant_g)


## How much one person eats of it in a season, in words. Empty when it is not stated.
func need_text() -> String:
	return weight_text(need_per_person_g)


## A weight in grams as a person writes it: "2 kg", "1.5 kg" or "450 g". Empty for nothing stated.
##
## The one place a food weight is turned into words, so a yield and a need cannot come out said two
## different ways - the same rule the one area conversion keeps.
static func weight_text(grams: int) -> String:
	if grams <= 0:
		return ""
	if grams < 1000:
		return "%d g" % grams
	var kilos: float = float(grams) / 1000.0
	if is_equal_approx(kilos, roundf(kilos)):
		return "%d kg" % int(roundf(kilos))
	return "%.1f kg" % kilos


## Everything the catalogue says about it as food, in one line: "leaf, flower; harvested May-June;
## allium; 6 hours of sun". Empty for a plant the catalogue does not call edible.
func crop_text() -> String:
	if not is_edible():
		return ""
	var parts: PackedStringArray = PackedStringArray()
	parts.append(edible_parts_text())
	var harvest: String = harvest_text()
	if not harvest.is_empty():
		parts.append("harvested %s" % harvest)
	var kin: String = family_name()
	if not kin.is_empty():
		parts.append(kin)
	var hours: String = sun_hours_text()
	if not hours.is_empty():
		parts.append("%s of sun" % hours)
	var days: String = maturity_text()
	if not days.is_empty():
		parts.append("%s to maturity" % days)
	return "; ".join(parts)

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
	var parts: PackedStringArray = PackedStringArray(
		[String(id), botanical_name, common_name, cultivar, category_name(), edible_parts_text(), family_name()]
	)
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
		return "plant %s is hardy in zones %d..%d, which is not a zone range" % [id, zone_min, zone_max]
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
	# The leaves, checked trait by trait. Zero is allowed - a plant nobody has read a leaf of is not a
	# broken plant - but a bit outside a trait's own table is a mistyped number, not a leaf. The bits a
	# trait may use are its own table's, so a value added to a leaf is a valid bit the day it is added.
	for trait_name: StringName in LEAF_TRAITS:
		var stated: int = leaf_trait(trait_name)
		var allowed: int = 0
		for bit: Variant in names_for(trait_name).keys():
			allowed |= int(bit)
		if stated != 0 and (stated & ~allowed) != 0:
			return (
				"plant %s states %s %d, which is not a set of leaf values"
				% [id, String(trait_name).replace("leaf_", "leaf "), stated]
			)
	if (bloom_months & ~0xFFF) != 0:
		return "plant %s blooms in months outside January..December (bits %d)" % [id, bloom_months]
	if (edible_parts & ~EDIBLE_ANY) != 0:
		return "plant %s is eaten as %d, which is not a set of edible parts" % [id, edible_parts]
	if (harvest_months & ~0xFFF) != 0:
		return "plant %s is harvested in months outside January..December (bits %d)" % [id, harvest_months]
	if not family.is_empty() and not FAMILY_NAMES.has(family):
		return "plant %s rotates with \"%s\", which is not a crop family" % [id, String(family)]
	if maturity_days < 0:
		return "plant %s has a negative time to maturity" % id
	if sun_hours_tenths < 0 or sun_hours_tenths > MAX_SUN_HOURS_TENTHS:
		return "plant %s needs %d tenths of an hour of sun in a day, which is not a day" % [id, sun_hours_tenths]
	if yield_per_plant_g < 0 or yield_per_plant_g > MAX_SEASON_GRAMS:
		return "plant %s gives %d grams in a season, which is not a yield" % [id, yield_per_plant_g]
	if need_per_person_g < 0 or need_per_person_g > MAX_SEASON_GRAMS:
		return "plant %s feeds a person %d grams in a season, which is not an amount" % [id, need_per_person_g]
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
		# The leaves, as bits, always written: zero is what a catalogue that has not been read leaf by
		# leaf says, and it is a fact about the record rather than an absence from it.
		"leaf_arrangement": leaf_arrangement,
		"leaf_complexity": leaf_complexity,
		"leaf_shape": leaf_shape,
		"leaf_margin": leaf_margin,
		"leaf_venation": leaf_venation,
		"bloom_months": bloom_months,
		# With the `#`: `Color.from_string` on a bare hex run is not the parse it looks like, and a
		# colour that came back as the fallback would be a bloom the plan draws in the wrong colour.
		"bloom_colour": "#" + bloom_colour.to_html(false),
		"form": form,
		"model_scene": model_scene,
		"thumbnail": thumbnail,
		"tags": tags.duplicate(),
		"note": note,
		# Food, and only what is stated: a part eaten, a harvest window, a rotation family, days to
		# maturity and the sun it needs. Left out meanings are zero/empty, which the reader treats as
		# "not stated" - an ornamental is not claiming to be inedible.
		"edible_parts": edible_parts,
		"harvest_months": harvest_months,
		"family": String(family),
		"maturity_days": maturity_days,
		"sun_hours_tenths": sun_hours_tenths,
		# How much to plant: how much one gives in a season and how much one person eats of it. Both
		# left out when not stated - a plant nobody has said this about is not claiming a yield of zero.
		"yield_per_plant_g": yield_per_plant_g,
		"need_per_person_g": need_per_person_g,
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
	# A record from a file holds every number as a float, so the leaves are read back as ints like every
	# other bit set here - and a record written before this existed states nothing, which is honest.
	species.leaf_arrangement = int(data.get("leaf_arrangement", 0))
	species.leaf_complexity = int(data.get("leaf_complexity", 0))
	species.leaf_shape = int(data.get("leaf_shape", 0))
	species.leaf_margin = int(data.get("leaf_margin", 0))
	species.leaf_venation = int(data.get("leaf_venation", 0))
	species.bloom_months = int(data.get("bloom_months", 0))
	var colour_text: String = String(data.get("bloom_colour", ""))
	species.bloom_colour = (
		Color.from_string(colour_text, Color(0.89, 0.42, 0.6))
		if not colour_text.is_empty()
		else Color(0.89, 0.42, 0.6)
	)
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
	species.edible_parts = int(data.get("edible_parts", 0))
	species.harvest_months = int(data.get("harvest_months", 0))
	species.family = StringName(data.get("family", ""))
	species.maturity_days = int(data.get("maturity_days", 0))
	species.sun_hours_tenths = int(data.get("sun_hours_tenths", 0))
	species.yield_per_plant_g = int(data.get("yield_per_plant_g", 0))
	species.need_per_person_g = int(data.get("need_per_person_g", 0))
	return species
