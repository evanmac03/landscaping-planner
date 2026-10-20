class_name PlantExpansion
extends RefCounted
## The rest of the trade's workhorses, added to the shipped plant list.
##
## ## Why a tool and a list rather than just a bigger file
##
## `nursery_list.json` shipped with seventeen species, which is a demonstration rather than a
## nursery's list: a designer drawing a real garden reaches the end of it in an afternoon. The
## rest of the list is here, and it is applied through the module's **own importer**
## (`PlantCatalogue.import_json`), which is what makes "do not add what is already there" a
## property of the mechanism rather than a promise about this file:
##
## * an id already in the catalogue is **refused, not replaced**, so running this twice adds
##   nothing the second time (`PlantCatalogue.add` refuses a duplicate id outright - the id is what
##   an imported list and the catalogue are matched on, and a silent replace is how a plant quietly
##   becomes a different plant);
## * an entry the model will not accept is refused **with its reason**, so a mistyped zone cannot
##   reach the list;
## * the raw list is written to `data/plants/nursery_list_more.json` as well, so the additions exist
##   as data somebody can read and diff rather than only as GDScript.
##
## The entries are therefore **additive by construction**: this tool cannot edit a plant that is
## already in the shipped list, which is the rule the request for more plants came with.
##
## ## What the data claims
##
## Zones are USDA hardiness ranges, sizes are whole centimetres as a nursery label gives them, and
## `soils` and `drainage` are stated **only where the plant is particular** - a lavender wants
## sharp drainage and says so, a spirea does not and stays silent. Everything the catalogue does not
## claim is skipped by the suitability check rather than assumed, so a plant with no soil stated
## cannot be marked wrong for the soil it is planted in.
##
## `blooms` is a run of months, "5,6", or `""` for a plant grown for its foliage - which is what
## sets `bloom_months` to zero, and why `note` on the foliage plants says what they are for.

const PlantSpeciesScript := preload("res://scripts/plant_species.gd")
const CatalogueScript := preload("res://scripts/plant_catalogue.gd")

## The shipped list, and the additions of this expansion.
const SHIPPED_PATH := "res://data/plants/nursery_list.json"
const MORE_PATH := "res://data/plants/nursery_list_more.json"

const TREE_FORM := "res://scenes/props/tree.tscn"
const SHRUB_FORM := "res://scenes/props/shrub.tscn"
const BED_FORM := "res://scenes/props/flower_bed.tscn"

const TREE := PlantSpeciesScript.TREE
const SHRUB := PlantSpeciesScript.SHRUB
const PERENNIAL := PlantSpeciesScript.PERENNIAL
const ANNUAL := PlantSpeciesScript.ANNUAL
const GRASS := PlantSpeciesScript.GRASS
const GROUNDCOVER := PlantSpeciesScript.GROUNDCOVER
const VINE := PlantSpeciesScript.VINE
const FERN := PlantSpeciesScript.FERN
const BULB := PlantSpeciesScript.BULB
const HERB := PlantSpeciesScript.HERB

const SUN := PlantSpeciesScript.FULL_SUN
const PART := PlantSpeciesScript.PART_SHADE
const SHADE := PlantSpeciesScript.FULL_SHADE
const DRY := PlantSpeciesScript.WATER_LOW
const MED := PlantSpeciesScript.WATER_MEDIUM
const WET := PlantSpeciesScript.WATER_HIGH

## Drainage, as bits. `ANY` is not stated.
const FAST := PlantSpeciesScript.DRAINS_FAST
const MODERATE := PlantSpeciesScript.DRAINS_MEDIUM
const SLOW := PlantSpeciesScript.DRAINS_SLOW
const ANY := PlantSpeciesScript.DRAINS_ANY


# --- one species ----------------------------------------------------------------------------


## One entry, in the order the file stores it, so a line here reads against a line there.
##
## `blooms` is a comma-separated run of month numbers or empty for foliage. `soils` and `drainage`
## are the two claims a plant only sometimes has, and they are the last two arguments because a
## caller that does not care about them should not have to spell them out.
static func _s(
	id: StringName,
	botanical: String,
	common: String,
	cultivar: String,
	category: int,
	zone_from: int,
	zone_to: int,
	height: int,
	spread: int,
	light: int,
	drink: int,
	blooms: String,
	colour: String,
	form: String,
	note: String,
	tags: Array,
	soils: Array = [],
	drainage: int = ANY
) -> Dictionary:
	var months: int = 0
	for part: String in blooms.split(",", false):
		var month: int = int(part.strip_edges())
		if month < 1 or month > 12:
			# A month that is not a month would put a bit past December, and the model refuses that -
			# but only as "bits 65535", at the far end of the pipeline, which names no field. Every
			# bit set says the same thing in words a person can act on.
			months = 0xFFFF
			break
		months |= 1 << (month - 1)
	return {
		"id": String(id),
		"botanical_name": botanical,
		"common_name": common,
		"cultivar": cultivar,
		"category": category,
		"zone_min": zone_from,
		"zone_max": zone_to,
		"height_cm": height,
		"spread_cm": spread,
		"sun": light,
		"water": drink,
		"soils": soils,
		"drainage": drainage,
		"bloom_months": months,
		"bloom_colour": colour,
		"form": form,
		"model_scene": "",
		"thumbnail": "",
		"tags": tags,
		"note": note,
	}


## Everything this expansion adds.
##
## Grouped the way a nursery list is grouped - trees, shrubs, perennials, grasses, groundcovers,
## vines, ferns, bulbs, herbs, annuals - because that is the order a person reads one in, and
## because a category with nothing in it is a filter in the browser that can never find anything.
static func additions() -> Array[Dictionary]:
	var out: Array[Dictionary] = []

	# --- trees -----------------------------------------------------------------------------
	out.append(_s(
		&"acer-saccharum-green-mountain", "Acer saccharum", "Sugar maple", "Green Mountain",
		TREE, 3, 8, 2000, 1200, 3, MED, "4,5", "#b7c25a", TREE_FORM,
		"The tree a whole autumn is about. Give it the room it will want in forty years.",
		["native", "shade tree", "fall colour"], [PlantSpeciesScript.LOAM, PlantSpeciesScript.CLAY, PlantSpeciesScript.SILT], SLOW
	))
	out.append(_s(
		&"quercus-rubra", "Quercus rubra", "Red oak", "",
		TREE, 3, 8, 2000, 1500, 3, MED, "5", "#a8b04a", TREE_FORM,
		"Fast for an oak, and the acorns come at thirty. A tree for the next owner of the house.",
		["native", "wildlife", "shade tree"], [PlantSpeciesScript.SAND, PlantSpeciesScript.LOAM, PlantSpeciesScript.CLAY], FAST | MODERATE
	))
	out.append(_s(
		&"betula-nigra-heritage", "Betula nigra", "River birch", "Heritage",
		TREE, 4, 9, 1500, 1000, 3, WET, "4,5", "#b6c46a", TREE_FORM,
		"The birch for a wet corner: it shrugs off the borers that take the paper birch.",
		["native", "wet soil", "winter interest"], [PlantSpeciesScript.LOAM, PlantSpeciesScript.SILT, PlantSpeciesScript.CLAY], MODERATE | SLOW
	))
	out.append(_s(
		&"gleditsia-triacanthos-inermis-sunburst", "Gleditsia triacanthos var. inermis", "Honey locust", "Sunburst",
		TREE, 3, 9, 1500, 1200, SUN, DRY, "6", "#d8e07a", TREE_FORM,
		"Thin shade, so the lawn survives under it, and it takes the worst of a boulevard.",
		["street tree", "drought tolerant", "shade tree"], [PlantSpeciesScript.SAND, PlantSpeciesScript.LOAM, PlantSpeciesScript.CLAY], FAST | MODERATE
	))
	out.append(_s(
		&"picea-glauca-densata", "Picea glauca", "White spruce", "Densata",
		TREE, 2, 6, 1500, 600, SUN, MED, "5", "#b9a86a", TREE_FORM,
		"The spruce for a windbreak: dense, tough, and it does not mind the cold end of the map.",
		["evergreen", "windbreak", "native"], [], FAST | MODERATE
	))
	out.append(_s(
		&"picea-pungens-hoopsii", "Picea pungens", "Colorado spruce", "Hoopsii",
		TREE, 2, 7, 1500, 500, SUN, MED, "5", "#9fb8c9", TREE_FORM,
		"Blue, slow, and the best of the blue spruces for a small yard.",
		["evergreen", "winter interest"], [PlantSpeciesScript.LOAM, PlantSpeciesScript.SAND], FAST | MODERATE
	))
	out.append(_s(
		&"acer-platanoides-crimson-king", "Acer platanoides", "Norway maple", "Crimson King",
		TREE, 3, 7, 1500, 1200, 3, MED, "4", "#b6885a", TREE_FORM,
		"Planted for a century and now a problem in the woods. Ask before you plant another.",
		["street tree", "fall colour"]
	))
	out.append(_s(
		&"malus-royalty", "Malus", "Crabapple", "Royalty",
		TREE, 3, 8, 600, 600, SUN, MED, "5", "#8f3a5c", TREE_FORM,
		"Purple leaf, dark flowers, and scab in a wet June. Choose it for the leaf, not the fruit.",
		["flowering", "fall colour", "small tree"], [], FAST | MODERATE
	))
	out.append(_s(
		&"prunus-virginiana-shubert", "Prunus virginiana", "Chokecherry", "Shubert",
		TREE, 2, 7, 700, 500, 3, MED, "5,6", "#e8e6e0", TREE_FORM,
		"A native that colours like a plum. It suckers, so plant it where a thicket is welcome.",
		["native", "fall colour", "suckers"]
	))
	out.append(_s(
		&"amelanchier-canadensis", "Amelanchier canadensis", "Serviceberry", "",
		TREE, 4, 8, 700, 600, 3, MED, "4,5", "#f0eee6", TREE_FORM,
		"Blossom, then berries the birds take about four minutes before you do.",
		["native", "edible", "wildlife"], [], MODERATE | SLOW
	))
	out.append(_s(
		&"cornus-alternifolia", "Cornus alternifolia", "Pagoda dogwood", "",
		TREE, 3, 7, 600, 500, 3, MED, "5,6", "#efece2", TREE_FORM,
		"Horizontal branches under a flat crown; it reads as a small tree even in leaf.",
		["native", "wildlife"], [], MODERATE | SLOW
	))
	out.append(_s(
		&"syringa-reticulata", "Syringa reticulata", "Japanese tree lilac", "",
		TREE, 3, 7, 700, 500, 3, MED, "6", "#f2eede", TREE_FORM,
		"The lilac that is a tree. Cream plumes in June, and no mildew worth mentioning.",
		["flowering", "small tree", "fragrant"]
	))

	# --- shrubs ----------------------------------------------------------------------------
	out.append(_s(
		&"taxus-cuspidata", "Taxus cuspidata", "Japanese yew", "",
		SHRUB, 4, 7, 300, 250, SHADE | PART, MED, "4", "#a8b06a", SHRUB_FORM,
		"The one evergreen that will take the north side of a house. Every part of it is toxic, so "
		+ "keep it out of a fence line a dog patrols.",
		["evergreen", "shade", "formal"], [], FAST | MODERATE
	))
	out.append(_s(
		&"juniperus-chinensis-pfitzeriana", "Juniperus chinensis", "Spreading juniper", "Pfitzeriana",
		SHRUB, 4, 9, 150, 300, SUN, DRY, "4,5", "#8ba06a", SHRUB_FORM,
		"Half a century of parking-lot planting has not made it any less useful.",
		["evergreen", "drought tolerant", "spreading"], [PlantSpeciesScript.SAND, PlantSpeciesScript.LOAM], FAST
	))
	out.append(_s(
		&"juniperus-scopulorum-blue-arrow", "Juniperus scopulorum", "Upright juniper", "Blue Arrow",
		SHRUB, 3, 7, 400, 70, SUN, DRY, "5", "#8fa8b8", SHRUB_FORM,
		"A blue pencil for a narrow bed, and it holds the colour through winter.",
		["evergreen", "narrow", "blue foliage"], [PlantSpeciesScript.SAND, PlantSpeciesScript.LOAM], FAST
	))
	out.append(_s(
		&"thuja-occidentalis-hetz-midget", "Thuja occidentalis", "Globe cedar", "Hetz Midget",
		SHRUB, 3, 8, 60, 60, 3, MED, "", "#7c9a6a", SHRUB_FORM,
		"A globe that stays a globe: evergreen without a hedge to clip.",
		["evergreen", "dwarf", "formal"], [], ANY
	))
	out.append(_s(
		&"hydrangea-arborescens-annabelle", "Hydrangea arborescens", "Smooth hydrangea", "Annabelle",
		SHRUB, 3, 9, 120, 150, 3, WET, "6,7,8", "#f0eee4", SHRUB_FORM,
		"Flops in a thunderstorm unless it is cut to the ground every March.",
		["long bloom", "cut flower", "native"], [], MODERATE | SLOW
	))
	out.append(_s(
		&"hydrangea-macrophylla-endless-summer", "Hydrangea macrophylla", "Bigleaf hydrangea", "Endless Summer",
		SHRUB, 5, 9, 120, 150, PART | SHADE, WET, "6,7,8,9", "#8fa8dd", SHRUB_FORM,
		"Blue in acid ground and pink in lime, and the colour is the soil's doing rather than the "
		+ "plant's. It flowers on old wood and new, which is why it survives a bad spring.",
		["long bloom", "shade", "flower"], [PlantSpeciesScript.LOAM, PlantSpeciesScript.ORGANIC], MODERATE | SLOW
	))
	out.append(_s(
		&"hydrangea-quercifolia", "Hydrangea quercifolia", "Oakleaf hydrangea", "",
		SHRUB, 5, 9, 180, 180, 3, WET, "6,7", "#f2f0e6", SHRUB_FORM,
		"Oak-shaped leaves and a red autumn that nothing else in the border does.",
		["fall colour", "shade", "native"], [], MODERATE
	))
	out.append(_s(
		&"rhododendron-pjm", "Rhododendron", "Rhododendron", "PJM",
		SHRUB, 4, 8, 150, 150, PART | SHADE, WET, "4,5", "#a04a7c", SHRUB_FORM,
		"It needs acid ground; everything else about it is easy.",
		["evergreen", "acid soil", "spring flower"], [PlantSpeciesScript.ORGANIC, PlantSpeciesScript.LOAM], FAST | MODERATE
	))
	out.append(_s(
		&"kalmia-latifolia", "Kalmia latifolia", "Mountain laurel", "",
		SHRUB, 5, 9, 150, 150, PART | SHADE, WET, "5,6", "#e8b6cc", SHRUB_FORM,
		"A sturdier evergreen for acid ground than most rhododendrons, and the buds alone are worth it.",
		["evergreen", "acid soil", "native", "shade"], [PlantSpeciesScript.ORGANIC, PlantSpeciesScript.LOAM], FAST | MODERATE
	))
	out.append(_s(
		&"syringa-meyeri-palibin", "Syringa meyeri", "Dwarf lilac", "Palibin",
		SHRUB, 3, 7, 120, 150, SUN, MED, "5,6", "#b79ad0", SHRUB_FORM,
		"A lilac for a small yard: fragrant, and it takes a hard cut without sulking.",
		["fragrant", "dwarf", "flower"]
	))
	out.append(_s(
		&"viburnum-trilobum", "Viburnum trilobum", "American cranberrybush", "",
		SHRUB, 2, 7, 300, 300, 3, WET, "5,6", "#f4f2ea", SHRUB_FORM,
		"Berries for the birds and a red autumn: a hedge that earns its place.",
		["native", "wildlife", "wet soil", "fall colour"], [], MODERATE | SLOW
	))
	out.append(_s(
		&"viburnum-carlesii", "Viburnum carlesii", "Koreanspice viburnum", "",
		SHRUB, 4, 7, 150, 150, 3, MED, "4,5", "#f0e2e6", SHRUB_FORM,
		"The most fragrant thing in this catalogue in April.",
		["fragrant", "flower"]
	))
	out.append(_s(
		&"physocarpus-opulifolius-diabolo", "Physocarpus opulifolius", "Ninebark", "Diabolo",
		SHRUB, 3, 7, 180, 180, 3, MED, "6", "#e6e2d2", SHRUB_FORM,
		"Dark leaf, tough as a fence post, and native to the edge of a swamp.",
		["native", "dark foliage", "tough"], [], MODERATE | SLOW
	))
	out.append(_s(
		&"clethra-alnifolia-hummingbird", "Clethra alnifolia", "Summersweet", "Hummingbird",
		SHRUB, 4, 9, 100, 120, 3, WET, "7,8", "#f0eee2", SHRUB_FORM,
		"Spice in the air in August, and bees in the whole plant while it lasts.",
		["fragrant", "pollinator", "wet soil", "native"], [], MODERATE | SLOW
	))
	out.append(_s(
		&"itea-virginica-henrys-garnet", "Itea virginica", "Virginia sweetspire", "Henry's Garnet",
		SHRUB, 5, 9, 120, 150, 3, WET, "6,7", "#eeeae0", SHRUB_FORM,
		"A wet-corner shrub that turns crimson: two reasons to plant it, which is one more than most.",
		["fall colour", "wet soil", "native"], [], MODERATE | SLOW
	))
	out.append(_s(
		&"caryopteris-clandonensis-blue-mist", "Caryopteris x clandonensis", "Bluebeard", "Blue Mist",
		SHRUB, 6, 9, 90, 90, SUN, DRY, "8,9", "#7f8fd0", SHRUB_FORM,
		"Late blue when the border has run out of ideas. Cut it back in spring.",
		["late bloom", "pollinator", "drought tolerant"], [], FAST | MODERATE
	))
	out.append(_s(
		&"potentilla-fruticosa-goldfinger", "Potentilla fruticosa", "Shrubby cinquefoil", "Goldfinger",
		SHRUB, 2, 7, 90, 120, 3, MED, "6,7,8,9", "#f2d24a", SHRUB_FORM,
		"Flowers from June to frost and asks for nothing: the prairie answer to a rose.",
		["long bloom", "drought tolerant", "native", "tough"], [PlantSpeciesScript.SAND, PlantSpeciesScript.LOAM, PlantSpeciesScript.CLAY], FAST | MODERATE
	))
	out.append(_s(
		&"spiraea-japonica-gold-mound", "Spiraea japonica", "Japanese spirea", "Gold Mound",
		SHRUB, 4, 8, 60, 80, 3, MED, "6,7", "#e8a2c0", SHRUB_FORM,
		"The low gold-leaf spirea: clip it and it flowers again.",
		["low maintenance", "colour", "flower"]
	))
	out.append(_s(
		&"weigela-florida-wine-and-roses", "Weigela florida", "Weigela", "Wine and Roses",
		SHRUB, 5, 8, 120, 150, 3, MED, "5,6", "#d0607c", SHRUB_FORM,
		"Dark leaf and pink flower, and the hummingbirds find it before you do.",
		["hummingbirds", "dark foliage", "flower"]
	))
	out.append(_s(
		&"rosa-knock-out", "Rosa", "Shrub rose", "Knock Out",
		SHRUB, 5, 9, 100, 100, SUN, MED, "6,7,8,9,10", "#c03a4a", SHRUB_FORM,
		"Black spot barely bothers it and it flowers until the snow: the rose for people who gave up "
		+ "on roses.",
		["repeat bloom", "disease resistant", "flower"], [], MODERATE
	))
	out.append(_s(
		&"rosa-rugosa", "Rosa rugosa", "Rugosa rose", "",
		SHRUB, 2, 7, 120, 150, SUN, MED, "6,7,8,9", "#d0648a", SHRUB_FORM,
		"Salt, sand and wind, and it still sets hips. Plant it where nothing else will grow.",
		["tough", "fragrant", "wildlife", "salt tolerant"], [PlantSpeciesScript.SAND, PlantSpeciesScript.LOAM], FAST | MODERATE
	))
	out.append(_s(
		&"cornus-sericea", "Cornus sericea", "Red osier dogwood", "",
		SHRUB, 2, 7, 250, 300, 3, WET, "5,6", "#f2f0e8", SHRUB_FORM,
		"The stems are the winter show and they are only red on young wood, so cut a third to the "
		+ "ground each spring.",
		["native", "wet soil", "winter interest"], [PlantSpeciesScript.LOAM, PlantSpeciesScript.CLAY, PlantSpeciesScript.SILT], MODERATE | SLOW
	))
	out.append(_s(
		&"cornus-alba-elegantissima", "Cornus alba", "Tatarian dogwood", "Elegantissima",
		SHRUB, 2, 7, 200, 250, 3, WET, "5,6", "#f4f2ec", SHRUB_FORM,
		"Variegated leaf, red stem, and the same rule: cut it back or lose the colour.",
		["variegated", "winter interest", "wet soil"], [], MODERATE | SLOW
	))
	out.append(_s(
		&"salix-integra-hakuro-nishiki", "Salix integra", "Dappled willow", "Hakuro-nishiki",
		SHRUB, 4, 8, 150, 150, 3, WET, "4,5", "#eec6cc", SHRUB_FORM,
		"Pink and white on every new shoot, which means it is dullest exactly when it is oldest.",
		["variegated", "wet soil", "small"], [], MODERATE | SLOW
	))
	out.append(_s(
		&"callicarpa-bodinieri-profusion", "Callicarpa bodinieri", "Beautyberry", "Profusion",
		SHRUB, 5, 8, 150, 150, 3, MED, "6,7", "#c9a8d8", SHRUB_FORM,
		"The berries arrive in October and are a colour nothing else in the garden has.",
		["winter interest", "berries", "wildlife"]
	))
	out.append(_s(
		&"fothergilla-gardenii", "Fothergilla gardenii", "Dwarf fothergilla", "",
		SHRUB, 5, 8, 90, 90, 3, WET, "4,5", "#f2f2ea", SHRUB_FORM,
		"Bottlebrush flowers before the leaves and a three-colour autumn after them.",
		["native", "fall colour", "acid soil"], [PlantSpeciesScript.ORGANIC, PlantSpeciesScript.LOAM], MODERATE | SLOW
	))
	out.append(_s(
		&"enkianthus-campanulatus", "Enkianthus campanulatus", "Redvein enkianthus", "",
		SHRUB, 4, 7, 180, 150, 3, WET, "5,6", "#eed8e2", SHRUB_FORM,
		"Bells in spring, scarlet in October, and it wants the same acid ground as a rhododendron.",
		["acid soil", "fall colour", "flower"], [PlantSpeciesScript.ORGANIC, PlantSpeciesScript.LOAM], FAST | MODERATE
	))
	out.append(_s(
		&"hamamelis-virginiana", "Hamamelis virginiana", "Witch hazel", "",
		SHRUB, 3, 8, 400, 400, 3, MED, "10,11,12", "#e8c04a", SHRUB_FORM,
		"The last flower of the year, opening as the leaves come down, when nothing else is doing "
		+ "anything at all.",
		["native", "winter interest", "fragrant"], [], MODERATE
	))
	out.append(_s(
		&"hibiscus-syriacus", "Hibiscus syriacus", "Rose of Sharon", "",
		SHRUB, 5, 8, 250, 180, SUN, MED, "7,8,9", "#a058b0", SHRUB_FORM,
		"Late, showy, and it seeds itself about if you let it.",
		["late bloom", "flower", "tough"]
	))
	out.append(_s(
		&"buddleja-davidii", "Buddleja davidii", "Butterfly bush", "",
		SHRUB, 5, 9, 200, 200, SUN, MED, "7,8,9", "#8a5cb0", SHRUB_FORM,
		"The butterflies do come. Cut it to the ground in spring, and check it is not on your local "
		+ "problem list before you plant it.",
		["pollinator", "fragrant", "late bloom"]
	))

	# --- perennials ------------------------------------------------------------------------
	out.append(_s(
		&"echinacea-purpurea-magnus", "Echinacea purpurea", "Purple coneflower", "Magnus",
		PERENNIAL, 3, 8, 90, 60, SUN, MED, "6,7,8", "#b06aa8", BED_FORM,
		"Leave the cones standing and it seeds itself into a colony for the birds.",
		["native", "pollinator", "cut flower"], [PlantSpeciesScript.LOAM, PlantSpeciesScript.CLAY, PlantSpeciesScript.SAND], MODERATE
	))
	out.append(_s(
		&"hylotelephium-autumn-joy", "Hylotelephium spectabile", "Stonecrop", "Autumn Joy",
		PERENNIAL, 3, 9, 60, 60, SUN, DRY, "8,9,10", "#d87a9a", BED_FORM,
		"Carries the border into October and then stands there, brown and dry, all winter.",
		["drought tolerant", "late bloom", "pollinator"], [PlantSpeciesScript.SAND, PlantSpeciesScript.LOAM], FAST
	))
	out.append(_s(
		&"perovskia-atriplicifolia", "Perovskia atriplicifolia", "Russian sage", "",
		PERENNIAL, 4, 9, 120, 90, SUN, DRY, "7,8,9", "#8a8fd8", BED_FORM,
		"Silver stems and blue haze in the hottest, poorest bed you have.",
		["drought tolerant", "late bloom", "silver foliage"], [PlantSpeciesScript.SAND, PlantSpeciesScript.LOAM], FAST
	))
	out.append(_s(
		&"salvia-nemorosa-caradonna", "Salvia nemorosa", "Perennial sage", "Caradonna",
		PERENNIAL, 4, 8, 60, 45, SUN, DRY, "6,7", "#6a5cb0", BED_FORM,
		"Cut it back after the first flush and it does the whole thing again in September.",
		["pollinator", "drought tolerant", "repeat bloom"], [], FAST | MODERATE
	))
	out.append(_s(
		&"nepeta-faassenii", "Nepeta x faassenii", "Catmint", "",
		PERENNIAL, 3, 8, 45, 60, SUN, DRY, "5,6,7,8,9", "#9a9ad8", BED_FORM,
		"Six weeks of grey-blue haze, then shear it and get six more. The cat will roll in it either way.",
		["pollinator", "drought tolerant", "long bloom", "deer resistant"], [], FAST | MODERATE
	))
	out.append(_s(
		&"geranium-rozanne", "Geranium", "Cranesbill", "Rozanne",
		PERENNIAL, 5, 8, 60, 90, 3, MED, "5,6,7,8,9,10", "#6a7fd0", BED_FORM,
		"Flowers from June to the frost, which nothing else in this list manages without a rest.",
		["long bloom", "pollinator"]
	))
	out.append(_s(
		&"achillea-millefolium-paprika", "Achillea millefolium", "Yarrow", "Paprika",
		PERENNIAL, 3, 9, 60, 60, SUN, DRY, "6,7,8", "#c0504a", BED_FORM,
		"Native to the roadsides here and just as happy in a border; it flops in rich soil.",
		["native", "drought tolerant", "cut flower"], [PlantSpeciesScript.SAND, PlantSpeciesScript.LOAM, PlantSpeciesScript.CLAY], FAST
	))
	out.append(_s(
		&"coreopsis-verticillata-moonbeam", "Coreopsis verticillata", "Threadleaf coreopsis", "Moonbeam",
		PERENNIAL, 3, 9, 45, 60, SUN, DRY, "6,7,8", "#f2e070", BED_FORM,
		"A pale yellow that reads as light rather than as colour.",
		["native", "drought tolerant", "long bloom"], [], FAST | MODERATE
	))
	out.append(_s(
		&"gaillardia-grandiflora-goblin", "Gaillardia x grandiflora", "Blanket flower", "Goblin",
		PERENNIAL, 3, 9, 30, 45, SUN, DRY, "6,7,8", "#c8623a", BED_FORM,
		"Hot, dry and poor is what it wants. Coddle it and it dies over the winter.",
		["native", "drought tolerant", "pollinator"], [PlantSpeciesScript.SAND, PlantSpeciesScript.LOAM], FAST
	))
	out.append(_s(
		&"liatris-spicata", "Liatris spicata", "Blazing star", "",
		PERENNIAL, 3, 9, 90, 40, SUN, MED, "7,8", "#a06ad0", BED_FORM,
		"Flowers from the top down, which is the wrong way round and looks deliberate.",
		["native", "pollinator", "cut flower"], [], MODERATE
	))
	out.append(_s(
		&"monarda-didyma-jacob-cline", "Monarda didyma", "Bee balm", "Jacob Cline",
		PERENNIAL, 4, 9, 120, 60, 3, WET, "7,8", "#c0384a", BED_FORM,
		"The hummingbird plant. Give it moving air or mildew takes it by August.",
		["native", "hummingbirds", "pollinator", "fragrant"], [], MODERATE
	))
	out.append(_s(
		&"phlox-paniculata-david", "Phlox paniculata", "Garden phlox", "David",
		PERENNIAL, 4, 8, 100, 60, 3, MED, "7,8", "#f0f0e8", BED_FORM,
		"White, fragrant, and the one garden phlox that resists mildew. Plant it where air moves.",
		["fragrant", "cut flower", "pollinator"]
	))
	out.append(_s(
		&"astilbe-arendsii-fanal", "Astilbe x arendsii", "Astilbe", "Fanal",
		PERENNIAL, 4, 9, 60, 50, PART | SHADE, WET, "6,7", "#c0385a", BED_FORM,
		"The shade plant that flowers rather than merely coping.",
		["shade", "cut flower", "wet soil"], [], MODERATE | SLOW
	))
	out.append(_s(
		&"lamprocapnos-spectabilis", "Lamprocapnos spectabilis", "Bleeding heart", "",
		PERENNIAL, 3, 9, 90, 60, PART | SHADE, MED, "5,6", "#e08aa8", BED_FORM,
		"Flowers in May and disappears in July. Put something in front of the hole it leaves.",
		["shade", "spring flower"]
	))
	out.append(_s(
		&"paeonia-lactiflora-festiva-maxima", "Paeonia lactiflora", "Peony", "Festiva Maxima",
		PERENNIAL, 3, 8, 90, 90, 3, MED, "6", "#f2eae8", BED_FORM,
		"Wants a cold winter and its crown an inch under the soil. Planted too deep it sulks for years.",
		["fragrant", "cut flower", "long lived"], [], MODERATE
	))
	out.append(_s(
		&"iris-sibirica", "Iris sibirica", "Siberian iris", "",
		PERENNIAL, 3, 8, 90, 60, 3, WET, "5,6", "#5a6ac0", BED_FORM,
		"Takes wet ground in spring and dry ground in August, which is most of this climate.",
		["wet soil", "cut flower", "tough"], [], MODERATE | SLOW
	))
	out.append(_s(
		&"hemerocallis-stella-de-oro", "Hemerocallis", "Daylily", "Stella de Oro",
		PERENNIAL, 3, 10, 50, 60, 3, MED, "6,7,8", "#f2d04a", BED_FORM,
		"One flower a day for six weeks, and not a lily at all.",
		["long bloom", "tough", "pollinator"]
	))
	out.append(_s(
		&"leucanthemum-superbum-becky", "Leucanthemum x superbum", "Shasta daisy", "Becky",
		PERENNIAL, 5, 9, 100, 60, SUN, MED, "6,7,8", "#f4f2ec", BED_FORM,
		"The white daisy a child draws, and it stays upright in rain.",
		["cut flower", "pollinator"]
	))
	out.append(_s(
		&"echinops-bannaticus", "Echinops bannaticus", "Globe thistle", "",
		PERENNIAL, 3, 8, 120, 60, SUN, DRY, "7,8", "#7a7fd0", BED_FORM,
		"Blue globes on grey stems, and the bees are on them before they are fully open.",
		["pollinator", "drought tolerant", "cut flower"], [], FAST | MODERATE
	))
	out.append(_s(
		&"helenium-autumnale-moerheim-beauty", "Helenium autumnale", "Sneezeweed", "Moerheim Beauty",
		PERENNIAL, 3, 8, 90, 60, SUN, MED, "8,9,10", "#b04a2a", BED_FORM,
		"Copper and rust in September, when the rest of the palette has gone quiet.",
		["native", "late bloom", "pollinator"], [], MODERATE
	))
	out.append(_s(
		&"baptisia-australis", "Baptisia australis", "Wild indigo", "",
		PERENNIAL, 3, 9, 120, 120, 3, DRY, "5,6", "#4a5cb0", BED_FORM,
		"Blue spikes in June and black pods after, and it resents being moved.",
		["native", "drought tolerant", "cut flower"], [], FAST | MODERATE
	))
	out.append(_s(
		&"asclepias-tuberosa", "Asclepias tuberosa", "Butterfly weed", "",
		PERENNIAL, 3, 9, 60, 45, SUN, DRY, "6,7,8", "#e8812a", BED_FORM,
		"The monarch caterpillar needs the plant, and the plant wants sand and sun.",
		["native", "monarch host", "drought tolerant"], [PlantSpeciesScript.SAND, PlantSpeciesScript.LOAM], FAST
	))
	out.append(_s(
		&"asclepias-incarnata", "Asclepias incarnata", "Swamp milkweed", "",
		PERENNIAL, 3, 9, 120, 60, 3, WET, "7,8", "#c87898", BED_FORM,
		"The wet corner's answer to the last one, and just as good for caterpillars.",
		["native", "monarch host", "wet soil"], [], MODERATE | SLOW
	))
	out.append(_s(
		&"amsonia-tabernaemontana", "Amsonia tabernaemontana", "Bluestar", "",
		PERENNIAL, 3, 9, 90, 60, 3, MED, "5,6", "#8aa8e0", BED_FORM,
		"Blue in May and butter yellow in October, out of the same leaves.",
		["native", "fall colour", "tough"], [], MODERATE
	))
	out.append(_s(
		&"geranium-maculatum", "Geranium maculatum", "Wild geranium", "",
		PERENNIAL, 3, 8, 45, 45, 3, MED, "5,6", "#c08ac0", BED_FORM,
		"A native that seeds itself quietly into the shade under a shrub.",
		["native", "shade"]
	))
	out.append(_s(
		&"eutrochium-purpureum", "Eutrochium purpureum", "Joe-pye weed", "",
		PERENNIAL, 3, 9, 180, 90, 3, WET, "8,9", "#c088a8", BED_FORM,
		"Two metres of dusty pink and every bee in the county. Give it the back of the border.",
		["native", "pollinator", "wet soil"], [], MODERATE | SLOW
	))
	out.append(_s(
		&"solidago-fireworks", "Solidago", "Goldenrod", "Fireworks",
		PERENNIAL, 4, 9, 90, 60, SUN, MED, "8,9,10", "#f2d24a", BED_FORM,
		"Goldenrod does not cause your hay fever; the ragweed beside it does.",
		["native", "pollinator", "late bloom"], [], FAST | MODERATE
	))
	out.append(_s(
		&"chrysanthemum-sheffield", "Chrysanthemum", "Hardy mum", "Sheffield",
		PERENNIAL, 5, 9, 60, 90, SUN, MED, "9,10", "#e8a0b8", BED_FORM,
		"A mum that comes back every year, which is not true of the ones sold in pots.",
		["late bloom", "cut flower"]
	))
	out.append(_s(
		&"stachys-byzantina", "Stachys byzantina", "Lamb's ears", "",
		PERENNIAL, 4, 8, 45, 45, 3, DRY, "6,7", "#b09ad0", BED_FORM,
		"The leaves are the point. Pinch the flowers off and it stays a carpet.",
		["foliage", "drought tolerant", "silver foliage"], [], FAST | MODERATE
	))
	out.append(_s(
		&"artemisia-schmidtiana", "Artemisia schmidtiana", "Silver mound", "",
		PERENNIAL, 4, 9, 30, 45, SUN, DRY, "", "#c9ccd0", BED_FORM,
		"A silver dome that has to be cut back the moment it opens in the middle.",
		["foliage", "silver foliage", "drought tolerant"], [], FAST
	))

	# --- ornamental grasses ------------------------------------------------------------------
	out.append(_s(
		&"miscanthus-sinensis-morning-light", "Miscanthus sinensis", "Silver grass", "Morning Light",
		GRASS, 5, 9, 150, 90, 3, MED, "9,10", "#d8d2b0", SHRUB_FORM,
		"The plume is the winter and the plant is the summer. Cut it down in March, never in autumn.",
		["winter interest", "screen"], [], MODERATE
	))
	out.append(_s(
		&"calamagrostis-acutiflora-karl-foerster", "Calamagrostis x acutiflora", "Feather reed grass", "Karl Foerster",
		GRASS, 4, 9, 150, 60, 3, MED, "6,7", "#d8cc9a", SHRUB_FORM,
		"It stands up in a storm, which is the whole reason it is everywhere.",
		["winter interest", "tough", "vertical"], [], MODERATE
	))
	out.append(_s(
		&"schizachyrium-scoparium", "Schizachyrium scoparium", "Little bluestem", "",
		GRASS, 3, 9, 90, 60, SUN, DRY, "8,9", "#c09060", SHRUB_FORM,
		"Blue-green in June, rust in October, and it holds that colour under snow.",
		["native", "drought tolerant", "fall colour"], [PlantSpeciesScript.SAND, PlantSpeciesScript.LOAM], FAST | MODERATE
	))
	out.append(_s(
		&"andropogon-gerardii", "Andropogon gerardii", "Big bluestem", "",
		GRASS, 4, 9, 180, 90, SUN, MED, "8,9", "#b8845a", SHRUB_FORM,
		"The grass the prairie was made of. Too big for a small border and right for a big one.",
		["native", "tall", "fall colour"], [], MODERATE
	))
	out.append(_s(
		&"sorghastrum-nutans", "Sorghastrum nutans", "Indian grass", "",
		GRASS, 4, 9, 180, 60, SUN, MED, "8,9", "#d0a860", SHRUB_FORM,
		"Gold in September; plant it where it can stand against the sky.",
		["native", "tall", "fall colour"], [], MODERATE
	))
	out.append(_s(
		&"pennisetum-alopecuroides-hameln", "Pennisetum alopecuroides", "Fountain grass", "Hameln",
		GRASS, 5, 9, 90, 90, 3, MED, "8,9", "#e0d8b0", SHRUB_FORM,
		"Soft bottlebrush plumes, and the seed heads hold the frost in the morning.",
		["winter interest", "pollinator"], [], MODERATE
	))
	out.append(_s(
		&"deschampsia-cespitosa", "Deschampsia cespitosa", "Tufted hair grass", "",
		GRASS, 4, 9, 90, 90, 3, WET, "6,7", "#d8d0a8", SHRUB_FORM,
		"A grass that takes both the shade and the wet, which almost no other grass will.",
		["shade", "wet soil", "native"], [], MODERATE | SLOW
	))
	out.append(_s(
		&"hakonechloa-macra-aureola", "Hakonechloa macra", "Japanese forest grass", "Aureola",
		GRASS, 5, 9, 45, 60, PART | SHADE, WET, "", "#d8d060", SHRUB_FORM,
		"It spills over a wall like water, and it is grown for the leaf rather than a plume.",
		["shade", "foliage", "wet soil", "variegated"], [], MODERATE | SLOW
	))

	# --- groundcovers ------------------------------------------------------------------------
	out.append(_s(
		&"sedum-spurium-john-creech", "Sedum spurium", "Two-row stonecrop", "John Creech",
		GROUNDCOVER, 3, 9, 10, 45, 3, DRY, "7,8", "#d06090", BED_FORM,
		"A mat of pink in July that keeps the weeds out of everything underneath it.",
		["groundcover", "drought tolerant", "pollinator"], [PlantSpeciesScript.SAND, PlantSpeciesScript.LOAM], FAST
	))
	out.append(_s(
		&"ajuga-reptans", "Ajuga reptans", "Bugleweed", "",
		GROUNDCOVER, 3, 9, 15, 45, 7, MED, "5,6", "#4a5cb0", BED_FORM,
		"Blue spikes over bronze leaves, and it will walk into the lawn if you let it.",
		["groundcover", "shade", "tough"]
	))
	out.append(_s(
		&"phlox-subulata-emerald-cushion", "Phlox subulata", "Moss phlox", "Emerald Cushion",
		GROUNDCOVER, 3, 9, 15, 50, 3, DRY, "4,5", "#e08ac0", BED_FORM,
		"A sheet of colour in April on a bank nothing else will hold.",
		["groundcover", "drought tolerant", "spring flower"], [PlantSpeciesScript.SAND, PlantSpeciesScript.LOAM], FAST
	))
	out.append(_s(
		&"tiarella-cordifolia", "Tiarella cordifolia", "Foamflower", "",
		GROUNDCOVER, 4, 9, 20, 30, PART | SHADE, WET, "4,5", "#f0eee4", BED_FORM,
		"Foam over the leaves in May, and it spreads itself politely.",
		["native", "shade", "groundcover"], [], MODERATE | SLOW
	))
	out.append(_s(
		&"waldsteinia-fragarioides", "Waldsteinia fragarioides", "Barren strawberry", "",
		GROUNDCOVER, 3, 8, 15, 30, 3, MED, "4,5", "#e8d24a", BED_FORM,
		"Yellow flowers and no fruit, but it does the job under a shrub.",
		["native", "shade", "groundcover", "tough"]
	))

	# --- vines ----------------------------------------------------------------------------------
	out.append(_s(
		&"clematis-jackmanii", "Clematis", "Clematis", "Jackmanii",
		VINE, 4, 9, 400, 150, 3, MED, "6,7,8", "#6a4aa8", SHRUB_FORM,
		"Cool feet and a warm head: shade the roots and give it the sun, or it sulks.",
		["vine", "flower", "cut flower"], [], MODERATE
	))
	out.append(_s(
		&"parthenocissus-quinquefolia", "Parthenocissus quinquefolia", "Virginia creeper", "",
		VINE, 3, 9, 1200, 400, 3, MED, "6,7", "#f2d04a", SHRUB_FORM,
		"Crimson in October on a wall nothing else would cover. It holds on with little cups, not roots.",
		["native", "fall colour", "vine"], [PlantSpeciesScript.LOAM, PlantSpeciesScript.CLAY, PlantSpeciesScript.SAND], MODERATE
	))
	out.append(_s(
		&"wisteria-frutescens", "Wisteria frutescens", "American wisteria", "",
		VINE, 5, 9, 1200, 400, 3, MED, "5,6", "#9a7fc8", SHRUB_FORM,
		"The native wisteria: slower than the Asian ones and far less likely to take the downspout with it.",
		["native", "fragrant", "vine", "flower"], [], MODERATE
	))
	out.append(_s(
		&"hydrangea-anomala-petiolaris", "Hydrangea anomala", "Climbing hydrangea", "Petiolaris",
		VINE, 4, 8, 1500, 300, 3, MED, "6,7", "#f2f0e4", SHRUB_FORM,
		"Nothing for three years, then it covers the wall. Plant it and be patient.",
		["shade", "vine", "flower", "wet soil"], [], MODERATE
	))

	# --- ferns ----------------------------------------------------------------------------------
	out.append(_s(
		&"athyrium-filix-femina", "Athyrium filix-femina", "Lady fern", "",
		FERN, 3, 8, 90, 90, PART | SHADE, WET, "", "#7ca05a", SHRUB_FORM,
		"The easy fern: fine-textured, quick, and it seeds itself about gently.",
		["native", "shade", "wet soil"], [], MODERATE | SLOW
	))
	out.append(_s(
		&"matteuccia-struthiopteris", "Matteuccia struthiopteris", "Ostrich fern", "",
		FERN, 3, 7, 150, 90, SHADE, WET, "", "#8aa860", SHRUB_FORM,
		"The fiddleheads are edible in May; after that it is a two-metre vase of fronds.",
		["native", "shade", "wet soil", "edible"], [], MODERATE | SLOW
	))
	out.append(_s(
		&"polystichum-acrostichoides", "Polystichum acrostichoides", "Christmas fern", "",
		FERN, 3, 9, 60, 60, PART | SHADE, MED, "", "#5a8a4a", SHRUB_FORM,
		"Evergreen through the winter, which is why it is the fern for a north wall.",
		["native", "evergreen", "shade"], [], MODERATE
	))
	out.append(_s(
		&"adiantum-pedatum", "Adiantum pedatum", "Maidenhair fern", "",
		FERN, 3, 8, 45, 45, SHADE, WET, "", "#9ab86a", SHRUB_FORM,
		"Black stems and a horseshoe of leaflets. It wants the soil of a forest floor.",
		["native", "shade", "wet soil"], [], MODERATE | SLOW
	))

	# --- bulbs ----------------------------------------------------------------------------------
	out.append(_s(
		&"tulipa-queen-of-night", "Tulipa", "Tulip", "Queen of Night",
		BULB, 3, 8, 60, 15, 3, MED, "5", "#4a2c50", BED_FORM,
		"Nearly black in the vase and purple in the sun. Plant them deep and let the leaves yellow.",
		["bulb", "cut flower"], [], FAST | MODERATE
	))
	out.append(_s(
		&"allium-globemaster", "Allium", "Ornamental onion", "Globemaster",
		BULB, 4, 8, 90, 20, 3, MED, "5,6", "#9a6ac8", BED_FORM,
		"A globe the size of a child's ball on a stem that stands all summer, even dry.",
		["bulb", "deer resistant", "cut flower"], [], FAST | MODERATE
	))
	out.append(_s(
		&"crocus-vernus", "Crocus vernus", "Crocus", "",
		BULB, 3, 8, 12, 8, 3, MED, "3,4", "#a08ad0", BED_FORM,
		"The first thing the bees find, in a snow-melt week.",
		["bulb", "spring flower", "pollinator"], [], FAST
	))
	out.append(_s(
		&"galanthus-nivalis", "Galanthus nivalis", "Snowdrop", "",
		BULB, 3, 7, 15, 8, 3, MED, "2,3", "#f4f4ee", BED_FORM,
		"Flowers while the ground is still frozen. Plant it where you walk past in February.",
		["bulb", "winter interest"], [], MODERATE
	))
	out.append(_s(
		&"lilium-stargazer", "Lilium", "Lily", "Stargazer",
		BULB, 4, 8, 100, 30, 3, MED, "7,8", "#e070a0", BED_FORM,
		"Scented enough to fill a room, and the one bulb the deer will eat to the ground.",
		["bulb", "fragrant", "cut flower"], [], FAST | MODERATE
	))
	out.append(_s(
		&"muscari-armeniacum", "Muscari armeniacum", "Grape hyacinth", "",
		BULB, 4, 8, 20, 8, 3, MED, "4,5", "#5a6ab0", BED_FORM,
		"Blue in the lawn before the first cut, and it multiplies where it is happy.",
		["bulb", "spring flower"], [], MODERATE
	))

	# --- herbs ----------------------------------------------------------------------------------
	out.append(_s(
		&"thymus-vulgaris", "Thymus vulgaris", "Common thyme", "",
		HERB, 5, 9, 30, 30, SUN, DRY, "6,7", "#e0c0d0", SHRUB_FORM,
		"The kitchen needs it and the bees use it; it wants sand and no kindness.",
		["herb", "drought tolerant", "pollinator"], [PlantSpeciesScript.SAND, PlantSpeciesScript.LOAM], FAST
	))
	out.append(_s(
		&"rosmarinus-officinalis", "Salvia rosmarinus", "Rosemary", "",
		HERB, 7, 10, 100, 100, SUN, DRY, "4,5", "#8ab0d8", SHRUB_FORM,
		"A shrub where it is hardy and a pot you bring inside here. Pinch it or it goes woody.",
		["herb", "drought tolerant", "fragrant"], [PlantSpeciesScript.SAND, PlantSpeciesScript.LOAM], FAST
	))
	out.append(_s(
		&"mentha-spicata", "Mentha spicata", "Spearmint", "",
		HERB, 4, 9, 60, 60, 3, WET, "7,8", "#e0d0e8", SHRUB_FORM,
		"Put it in a pot, or it owns the bed within two seasons.",
		["herb", "wet soil", "spreading"], [], MODERATE | SLOW
	))
	out.append(_s(
		&"origanum-vulgare", "Origanum vulgare", "Oregano", "",
		HERB, 4, 9, 45, 45, SUN, DRY, "7,8", "#d8b0d0", SHRUB_FORM,
		"Poor soil makes the flavour; a rich bed makes leaves and no oil.",
		["herb", "drought tolerant", "pollinator"], [], FAST
	))
	out.append(_s(
		&"allium-schoenoprasum", "Allium schoenoprasum", "Chives", "",
		HERB, 3, 9, 30, 30, 3, MED, "5,6", "#b08ad0", SHRUB_FORM,
		"Cut it and it comes back. The flowers are edible and the bees like them too.",
		["herb", "edible", "pollinator"]
	))
	out.append(_s(
		&"anethum-graveolens", "Anethum graveolens", "Dill", "",
		HERB, 2, 11, 90, 30, SUN, MED, "6,7", "#d8d040", SHRUB_FORM,
		"Sow it every year, and let one stand for the swallowtails.",
		["herb", "annual", "pollinator", "edible"], [], MODERATE
	))
	out.append(_s(
		&"petroselinum-crispum", "Petroselinum crispum", "Parsley", "",
		HERB, 5, 9, 30, 30, 3, MED, "6", "#b0c090", SHRUB_FORM,
		"A biennial: the second year it flowers and stops being parsley.",
		["herb", "edible", "biennial"]
	))
	out.append(_s(
		&"ocimum-basilicum-genovese", "Ocimum basilicum", "Basil", "Genovese",
		HERB, 10, 11, 45, 30, SUN, MED, "7,8", "#e8e8d8", SHRUB_FORM,
		"An annual in this climate whatever the label says. Pinch the flowers or the leaves go bitter.",
		["herb", "edible", "annual"], [], MODERATE
	))

	# --- annuals ----------------------------------------------------------------------------------
	out.append(_s(
		&"tagetes-patula", "Tagetes patula", "Marigold", "",
		ANNUAL, 2, 11, 30, 30, SUN, MED, "6,7,8,9", "#e8821a", BED_FORM,
		"Cheap, tough, and it flowers until the frost takes it.",
		["annual", "pollinator", "tough"]
	))
	out.append(_s(
		&"pelargonium-hortorum", "Pelargonium x hortorum", "Zonal geranium", "",
		ANNUAL, 10, 11, 40, 40, SUN, MED, "5,6,7,8,9", "#d0384a", BED_FORM,
		"The window-box plant, and it wants to dry out a little between waterings.",
		["annual", "container", "long bloom"]
	))
	out.append(_s(
		&"impatiens-walleriana", "Impatiens walleriana", "Impatiens", "",
		ANNUAL, 10, 11, 40, 40, PART | SHADE, WET, "6,7,8,9", "#e08ab8", BED_FORM,
		"Flowers in the shade all summer. Downy mildew took the old ones out of the trade, so ask for "
		+ "a resistant series.",
		["annual", "shade", "container", "long bloom"], [], MODERATE | SLOW
	))
	out.append(_s(
		&"petunia-atkinsiana", "Petunia x atkinsiana", "Petunia", "",
		ANNUAL, 10, 11, 30, 60, SUN, MED, "5,6,7,8,9", "#a05ad0", BED_FORM,
		"Trailing ones fill a basket by July and want deadheading as much as water.",
		["annual", "container", "long bloom"]
	))
	out.append(_s(
		&"coleus-scutellarioides", "Coleus scutellarioides", "Coleus", "",
		ANNUAL, 10, 11, 60, 45, PART | SHADE, WET, "", "#d0688a", BED_FORM,
		"Grown for the leaf, and it will take shade a flower will not.",
		["annual", "foliage", "shade", "container"], [], MODERATE | SLOW
	))
	out.append(_s(
		&"zinnia-elegans", "Zinnia elegans", "Zinnia", "",
		ANNUAL, 2, 11, 60, 30, SUN, MED, "7,8,9", "#e85878", BED_FORM,
		"Cut it and it flowers harder. Powdery mildew gets it if the air stands still.",
		["annual", "cut flower", "pollinator"]
	))

	return out

# --- applying them -------------------------------------------------------------------------------


## Why the additions file says what it is, and why it is not the list the program reads.
const MORE_SOURCE := "nursery list - the additions of tools/plant_expansion.gd"


## What is wrong with the additions themselves, in sentences, or nothing.
##
## `PlantSpecies.problem()` already covers every field's range, and this adds the one fault it cannot
## see: an entry listed twice. The importer would refuse the second one as "already in the catalogue",
## which is true and hides the fact that the file is wrong.
static func validate(rows: Array[Dictionary]) -> Array[String]:
	var out: Array[String] = []
	var seen: Dictionary = {}
	for row: Dictionary in rows:
		var id: String = String(row["id"])
		var plant: PlantSpeciesScript = PlantSpeciesScript.from_dict(row)
		if not plant.is_valid():
			out.append("%s: %s" % [id, plant.problem()])
		if seen.has(id):
			out.append("%s is in the additions twice" % id)
		seen[id] = true
	return out


## The additions as a catalogue, which is what gets written to `MORE_PATH`.
##
## Built through `from_dict` rather than assembled by hand, so what is written to disk is exactly what
## the loader will read back: the file cannot end up in a shape only the writer understands.
static func as_catalogue(rows: Array[Dictionary]) -> CatalogueScript:
	var keyed: Dictionary = {}
	for row: Dictionary in rows:
		keyed[String(row["id"])] = row
	return CatalogueScript.from_dict({"version": 1, "source": MORE_SOURCE, "species": keyed})


## Write the additions out, import them onto the shipped list, and save it back.
##
## The import is the module's own (`PlantCatalogue.import_json`) with `replace = false`, which is the
## whole reason this is a tool rather than an edit: **an id that is already in the catalogue is
## skipped, and the version already there is kept**. Running this twice therefore adds nothing the
## second time, and the seventeen plants that were in the list first keep their own values.
##
## What counts as a **fault** is decided by asking the catalogue afterwards rather than by reading the
## importer's refusal messages: every addition either reached the catalogue or it did not. A message
## is wording, and wording is exactly the thing that drifts.
##
## Returns `{ok, reason, added, skipped, kept, was, total, more_path}`.
static func run() -> Dictionary:
	var shipped: Dictionary = CatalogueScript.load_from(SHIPPED_PATH)
	if not bool(shipped["ok"]):
		return _failed("the shipped list would not load: %s" % String(shipped["reason"]))
	var catalogue: CatalogueScript = shipped["catalogue"]
	var rows: Array[Dictionary] = additions()
	var complaints: Array[String] = validate(rows)
	if not complaints.is_empty():
		return _failed("the additions were not applied: %s" % " | ".join(PackedStringArray(complaints)))

	var written: Dictionary = as_catalogue(rows).save_to(MORE_PATH)
	if not bool(written["ok"]):
		return _failed("the additions file was not written: %s" % String(written["reason"]))

	# Who was here first, so that "added" and "skipped" are two different numbers rather than one
	# total that cannot tell a fresh list from a re-run.
	var before: Dictionary = {}
	for row: Dictionary in rows:
		var id: StringName = StringName(row["id"])
		if catalogue.has(id):
			before[id] = catalogue.get_species(id).to_dict()
	var was: int = catalogue.count()

	var imported: Dictionary = catalogue.import_json(MORE_PATH)
	if not bool(imported["ok"]):
		return _failed("the additions would not import: %s" % String(imported["reason"]))

	var added: int = 0
	var skipped: int = 0
	var kept: int = 0
	var missing: Array[String] = []
	var changed: Array[String] = []
	for row: Dictionary in rows:
		var id: StringName = StringName(row["id"])
		var here: PlantSpeciesScript = catalogue.get_species(id)
		if here == null:
			missing.append(String(id))
			continue
		if not before.has(id):
			added += 1
			continue
		skipped += 1
		# Already here *and* different: not a fault - the entry that was here first wins, which is the
		# rule - but worth saying out loud, because it is the only way this tool can tell somebody that
		# their edit to an existing plant was ignored.
		if JSON.stringify(before[id]) != JSON.stringify(here.to_dict()):
			kept += 1
			changed.append(String(id))
	if not missing.is_empty():
		return _failed("the additions were not applied: %s did not reach the catalogue (%s)" % [
			", ".join(PackedStringArray(missing)),
			" | ".join(PackedStringArray(imported["refused"])),
		])

	var saved: Dictionary = catalogue.save_to(SHIPPED_PATH)
	if not bool(saved["ok"]):
		return _failed("the shipped list was not saved: %s" % String(saved["reason"]))
	if not catalogue.is_sound():
		return _failed("the merged list is not sound: %s" % " | ".join(PackedStringArray(catalogue.problems())))
	if not catalogue.missing_files().is_empty():
		return _failed("the merged list names files that are not there: %s"
			% " | ".join(PackedStringArray(catalogue.missing_files())))

	return {
		"ok": true,
		"reason": "",
		"added": added,
		"skipped": skipped,
		"kept": kept,
		"changed": changed,
		"was": was,
		"total": catalogue.count(),
		"more_path": MORE_PATH,
	}


static func _failed(reason: String) -> Dictionary:
	return {
		"ok": false, "reason": reason, "added": 0, "skipped": 0, "kept": 0, "changed": [],
		"was": 0, "total": 0, "more_path": MORE_PATH,
	}
