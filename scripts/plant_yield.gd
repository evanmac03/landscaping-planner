class_name PlantYield
extends RefCounted
## How much to plant: how many plants it takes to feed a given number of people through a season.
##
## The rest of the food garden starts from the drawing - what will crop *here*, what should follow what,
## when it ripens, when to sow it. This one starts from a person: "there are four of us and we want to
## grow most of our own vegetables this year". It is the question a kitchen gardener asks in winter,
## before anything is drawn, and it is arithmetic all the way down:
##
##     plants one person needs   =  how much a person eats  /  how much one plant gives
##
## Two things it joins, and neither of them invented here:
##
## * **`PlantSpecies.yield_per_plant_g`** - how much one plant gives in a season, a rule of thumb a
##   kitchen-garden book prints and the catalogue either states or does not.
## * **`PlantSpecies.need_per_person_g`** - how much of that crop one person eats in a season, the same
##   kind of stated rule of thumb. It is **per crop** because a person eats far more tomato than thyme,
##   and a single figure for "vegetables in general" would be a number nobody could plant from.
##
## A **spare** is added on top, because no garden gives every plant whole: a lettuce is stripped by
## slugs and a tomato splits, and the number a person plants is always a little more than the sum. It is
## a stated percentage rather than a hidden margin, so the answer can be checked.
##
## ## Why this page has no verdicts
##
## Every other food page but one answers with the four words good / tolerated / wrong / unknown, because
## each of them is a **judgement** - will it live here, will it crop, will it ripen, will it follow. This
## one gives a **count**, and a count is not a judgement: "twelve tomato plants" is no more good or bad
## than "ready in July" is. So, like the harvest calendar and for the same reason, it borrows no verdict
## vocabulary. A crop that cannot be worked out is **reported apart** - it says which of the two facts is
## missing - rather than called anything.
##
## ## The hand-off
##
## `order_rows` writes the plan in the exact row shape a planting schedule writes - a species, a count,
## and the names - which is what `PlantOrder.plan` takes to price a nursery order. So the count this
## works out is the count a nursery order is written from, and a yield plan prices through the same
## module as the yard's own planting, with no second set of arithmetic.

const PlantSpeciesScript := preload("res://scripts/plant_species.gd")

## Who the plan is for, when nobody has said. A household, offered as a starting point rather than a
## claim - the page states it, and the module only works from whatever it is handed.
const DEFAULT_PEOPLE := 4

## The spare added on top, as a percentage, when nobody has said. A tenth more than the bare number is
## the margin a kitchen gardener plants to, stated plainly and offered as a default rather than hidden.
const DEFAULT_SPARE := 10

## What a person may state. One is the fewest there can be, and fifty a household garden: beyond that
## the number stops being a garden plan.
const MIN_PEOPLE := 1
const MAX_PEOPLE := 50

## The widest spare. Nothing at all is a real answer (plant exactly the sum), and a spare of the whole
## again covers the worst year; more than that is not a plan.
const MIN_SPARE := 0
const MAX_SPARE := 100

## What it says when one of the two facts is missing, each naming the one that is.
const NO_YIELD := "no yield per plant stated"
const NO_NEED := "no amount per person stated"
const NO_CROP := "there is no crop to work out"
const NO_CROPS := "no food crops are recorded in this plant list"


# --- weights --------------------------------------------------------------------------------


## Whether a number is an amount this program will work from: more than nothing, and no more than a
## tonne. Zero means not stated, and a negative is not an amount.
static func is_grams(grams: int) -> bool:
	return grams > 0 and grams <= PlantSpeciesScript.MAX_SEASON_GRAMS


## A weight in grams as a person writes it: "2 kg", "1.5 kg" or "450 g". Empty for nothing stated.
## Read off `PlantSpecies.weight_text`, so a weight is only ever worded one way.
static func weight_text(grams: int) -> String:
	return PlantSpeciesScript.weight_text(grams)


# --- whether the question can be answered ---------------------------------------------------


## Whether the catalogue says enough to work out a number of plants for this crop: how much one gives
## and how much one person eats. Both, or there is nothing to divide.
static func can_answer(crop: PlantSpecies) -> bool:
	return crop != null and is_grams(crop.yield_per_plant_g) and is_grams(crop.need_per_person_g)


## Why a crop cannot be worked out, in a phrase naming the missing fact, or "" when it can be. The two
## are different errands - one is a yield nobody wrote down, the other an appetite nobody stated - and a
## page that said "unknown" for both would send a person to look in the wrong place.
static func reason(crop: PlantSpecies) -> String:
	if crop == null:
		return NO_CROP
	if not is_grams(crop.yield_per_plant_g):
		return NO_YIELD
	if not is_grams(crop.need_per_person_g):
		return NO_NEED
	return ""


# --- how many plants ------------------------------------------------------------------------


## How many plants of this crop feed `people` people, with `spare_percent` more for losses.
##
## Nothing to divide, nobody to feed, or a fact missing gives zero rather than a guessed number. The
## count is always rounded **up**, because half a plant is not a plant, and then the spare is applied
## and rounded up again - so the answer is the smallest planting that covers the stated need.
static func plants_for(crop: PlantSpecies, people: int, spare_percent: int = DEFAULT_SPARE) -> int:
	if not can_answer(crop) or people <= 0:
		return 0
	var heads: int = clampi(people, MIN_PEOPLE, MAX_PEOPLE)
	var want: float = float(heads) * float(crop.need_per_person_g)
	var plants: float = ceilf(want / float(crop.yield_per_plant_g))
	var with_spare: float = plants * float(100 + clampi(spare_percent, MIN_SPARE, MAX_SPARE)) / 100.0
	return int(ceilf(with_spare))


## How much of the crop `people` people eat in a season, in grams. Zero when one person's share is not
## stated. The need the planting is measured against.
static func need_grams(crop: PlantSpecies, people: int) -> int:
	if crop == null or not is_grams(crop.need_per_person_g):
		return 0
	return clampi(people, MIN_PEOPLE, MAX_PEOPLE) * crop.need_per_person_g


# --- the plan ------------------------------------------------------------------------------


## Every food crop in the catalogue worked out for a household: one row per edible species, in
## `{id, title, plants, yield_g, need_g, yield_text, need_text, stated, note}` shape, sorted by title so
## the list is the same twice running.
##
## A crop that cannot be worked out is a row too - with `plants` of zero and `note` naming what is
## missing - because a list that quietly dropped it would look like a garden that needs no thyme rather
## than one nobody has said how much thyme to plant.
static func plan(catalogue: PlantCatalogue, people: int, spare_percent: int = DEFAULT_SPARE) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if catalogue == null:
		return out
	for plant: PlantSpecies in catalogue.all():
		if not plant.is_edible():
			continue
		out.append(_row(plant, people, spare_percent))
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["title"]) < String(b["title"]))
	return out


static func _row(crop: PlantSpecies, people: int, spare_percent: int) -> Dictionary:
	var answerable: bool = can_answer(crop)
	return {
		"id": crop.id,
		"title": crop.display_name(),
		"plants": plants_for(crop, people, spare_percent),
		"yield_g": crop.yield_per_plant_g,
		"need_g": crop.need_per_person_g,
		"yield_text": crop.yield_text(),
		"need_text": crop.need_text(),
		"stated": answerable,
		"note": "" if answerable else reason(crop),
	}


# --- what a page reads ----------------------------------------------------------------------


## Those rows as the lines a list control shows: the crop and the number of plants, or the fact that is
## missing. The line is built from the row's own `note`, so the list and the summary cannot disagree.
static func row_texts(catalogue: PlantCatalogue, people: int, spare_percent: int = DEFAULT_SPARE) -> Array[String]:
	var out: Array[String] = []
	for row: Dictionary in plan(catalogue, people, spare_percent):
		if bool(row["stated"]):
			out.append("%s: plant %d" % [String(row["title"]), int(row["plants"])])
		else:
			out.append("%s: %s" % [String(row["title"]), String(row["note"])])
	return out


## How many of the crops a household can be given a number for, and how many it cannot.
static func counts(rows_list: Array) -> Dictionary:
	var worked := 0
	var unstated := 0
	for row: Dictionary in rows_list:
		if bool(row.get("stated", false)):
			worked += 1
		else:
			unstated += 1
	return {"worked": worked, "unstated": unstated}


## How many plants the whole plan comes to.
static func total_plants(rows_list: Array) -> int:
	var total := 0
	for row: Dictionary in rows_list:
		total += int(row.get("plants", 0))
	return total


## "9 crops: 7 can be worked out, 2 cannot be told." A list with no food crop says so rather than reading
## as a garden that needs nothing planted.
static func describe_rows(rows_list: Array) -> String:
	if rows_list.is_empty():
		return NO_CROPS
	var held: Dictionary = counts(rows_list)
	var parts: PackedStringArray = PackedStringArray()
	parts.append("%d can be worked out" % int(held["worked"]))
	var unstated: int = int(held["unstated"])
	if unstated > 0:
		parts.append("%d cannot be told" % unstated)
	return "%d crop%s: %s." % [
		rows_list.size(), "" if rows_list.size() == 1 else "s", ", ".join(parts)
	]


## The household in words: "4 people", or "1 person".
static func people_text(people: int) -> String:
	var heads: int = clampi(people, MIN_PEOPLE, MAX_PEOPLE)
	return "%d person" % heads if heads == 1 else "%d people" % heads


## The whole plan as the sentence a page opens with: "To feed 4 people, about 96 plants across 7 kinds,
## with a tenth spare." A plan that works nothing out says so rather than reading as no plants at all.
static func feed_text(rows_list: Array, people: int, spare_percent: int = DEFAULT_SPARE) -> String:
	var total: int = total_plants(rows_list)
	if total <= 0:
		return "nothing on this list can be worked out into a number of plants"
	var kinds: int = int(counts(rows_list)["worked"])
	var margin: String = "with no spare" if spare_percent <= 0 else "with %d%% spare" % spare_percent
	return "To feed %s, about %d plant%s across %d kind%s, %s." % [
		people_text(people), total, "" if total == 1 else "s", kinds, "" if kinds == 1 else "s", margin,
	]


# --- the hand-off to a nursery order ---------------------------------------------------------


## The plan as a planting schedule: one row per crop that worked out, in the **exact** shape
## `PlantPlacement.schedule()` writes - a species, a count, and the names - which is what
## `PlantOrder.plan` takes to price a nursery order.
##
## A crop that could not be worked out has no row, because a count nobody stated must not become a line
## on an order. This is the join the whole slice is for: what a household *needs*, in the shape the
## ordering side already reads.
static func order_rows(rows_list: Array, catalogue: PlantCatalogue) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if catalogue == null:
		return out
	for row: Dictionary in rows_list:
		var count: int = int(row.get("plants", 0))
		var species_id: StringName = StringName(row.get("id", &""))
		if count <= 0 or species_id.is_empty():
			continue
		var species: PlantSpecies = catalogue.get_species(species_id)
		if species == null:
			continue
		out.append({
			"id": species_id,
			"count": count,
			"botanical_name": species.botanical_name,
			"common_name": species.common_name,
			"cultivar": species.cultivar,
			"category": species.category,
			"category_name": species.category_name(),
			"spread_cm": species.spread_cm,
			"height_cm": species.height_cm,
		})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var order: int = String(a["botanical_name"]).naturalnocasecmp_to(String(b["botanical_name"]))
		if order != 0:
			return order < 0
		return String(a["cultivar"]).naturalnocasecmp_to(String(b["cultivar"])) < 0)
	return out