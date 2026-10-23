class_name HarvestCalendar
extends RefCounted
## What is ready when: the year as twelve lists of crops.
##
## `PlantSpecies` already carries the one fact this needs - `harvest_months`, the set of months a crop
## is cut in, with `harvests_in(month)` to ask it and `harvest_text()` to say it. This is the join that
## turns a whole catalogue into a calendar: pick a month and every crop recorded as ready then.
##
## **There is no verdict here, and that is the decision worth stating.** `PlantSuitability`, `CropSun`
## and `CropRotation` each answer their question with one of four words because each is a judgement -
## will this grow here, will it get its sun, may it follow that. A harvest is not a judgement: it is a
## fact about timing that the catalogue either records or does not. So this module keeps no reds and no
## greens and borrows none; it names months. A crop whose window nobody recorded is **not** called
## unsuitable - it is a crop that has not been given a harvest time, and it is counted apart for exactly
## that reason, so an empty month reads as "nothing is ready then" rather than as a fault.
##
## The one thing it does reuse is the wording of a run of months:
## `PlantSpecies.months_run_text`, so the months a plant **blooms**, the months a crop is **harvested**
## and the months a calendar has something **ready** are all said the same way.

const PlantSpeciesScript := preload("res://scripts/plant_species.gd")

## A year has twelve months, and the calendar is one list for each.
const MONTHS := 12

const NO_FOOD := "this plant list has no food in it yet"
const NONE_RECORDED := "no crop in this list has a harvest time recorded"


# --- the months ---------------------------------------------------------------------------


## Whether a number is a month of the year (1..12).
static func is_month(month: int) -> bool:
	return month >= 1 and month <= 12


## A month as a person says it: "June". Empty for a number that is not a month.
static func month_name(month: int) -> String:
	if not is_month(month):
		return ""
	return PlantSpeciesScript.MONTH_NAMES[month - 1]


# --- what is ready ------------------------------------------------------------------------


## Whether a crop is ready to cut in a month. Edible, and its window covers the month - both, because a
## boxwood has no harvest however its bits read.
static func ready(crop: PlantSpecies, month: int) -> bool:
	return crop != null and is_month(month) and crop.is_edible() and crop.harvests_in(month)


## Every crop in the catalogue ready in a month, by botanical order so the list is the same twice.
static func crops_in(catalogue: PlantCatalogue, month: int) -> Array[PlantSpecies]:
	var out: Array[PlantSpecies] = []
	if catalogue == null or not is_month(month):
		return out
	for plant: PlantSpecies in catalogue.all():
		if ready(plant, month):
			out.append(plant)
	out.sort_custom(func(a: PlantSpecies, b: PlantSpecies) -> bool:
		return a.display_name() < b.display_name())
	return out


## One row per crop ready in a month, in `{id, title, label, window}` shape. `label` is what of the
## plant is cut - the one thing that differs between two crops ready in the same month - and `window` is
## the crop's own harvest span, so a row can say "and it is ready from June".
static func rows(catalogue: PlantCatalogue, month: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for plant: PlantSpecies in crops_in(catalogue, month):
		out.append({
			"id": plant.id,
			"title": plant.display_name(),
			"label": plant.edible_parts_text(),
			"window": plant.harvest_text(),
		})
	return out


## Those rows as the lines a list control shows: the crop and what of it is cut. The line is the row's
## own `label` rather than a format assembled here, so the list and any other line built from the same
## rows cannot say two different things.
static func row_texts(catalogue: PlantCatalogue, month: int) -> Array[String]:
	var out: Array[String] = []
	for row: Dictionary in rows(catalogue, month):
		out.append("%s: %s" % [String(row["title"]), String(row["label"])])
	return out


# --- the year -----------------------------------------------------------------------------


## How many crops are ready in each month, index 0 being January. Twelve numbers, because the whole page
## is a year and a month nobody asked about is still a month the calendar has an answer for.
static func counts(catalogue: PlantCatalogue) -> Array[int]:
	var out: Array[int] = []
	out.resize(MONTHS)
	out.fill(0)
	if catalogue == null:
		return out
	for plant: PlantSpecies in catalogue.all():
		if not plant.is_edible():
			continue
		for month in range(1, MONTHS + 1):
			if plant.harvests_in(month):
				out[month - 1] += 1
	return out


## How many crops are ready in one month, or zero for a number that is not a month.
static func month_count(catalogue: PlantCatalogue, month: int) -> int:
	if not is_month(month):
		return 0
	return counts(catalogue)[month - 1]


## The month with the most ready, as `{month, count}`. Ties go to the earlier month, so the answer does
## not depend on the order a dictionary happened to be walked in. A catalogue with nothing ready is
## month zero and no count.
static func busiest(catalogue: PlantCatalogue) -> Dictionary:
	var held: Array[int] = counts(catalogue)
	var best_month: int = 0
	var best_count: int = 0
	for month in range(1, MONTHS + 1):
		var here: int = held[month - 1]
		if here > best_count:
			best_count = here
			best_month = month
	return {"month": best_month, "count": best_count}


## The months that have anything ready at all, as `{first, last, months, bits}`: the first and last such
## month, the list of them, and the same set as month bits so a line can word it by the one rule that
## words a run of months. A catalogue with nothing ready gives `{first: 0, last: 0, months: [], bits: 0}`.
static func ready_span(catalogue: PlantCatalogue) -> Dictionary:
	var held: Array[int] = counts(catalogue)
	var months: Array[int] = []
	var bits: int = 0
	for month in range(1, MONTHS + 1):
		if held[month - 1] > 0:
			months.append(month)
			bits |= 1 << (month - 1)
	if months.is_empty():
		return {"first": 0, "last": 0, "months": months, "bits": 0}
	return {"first": months[0], "last": months[months.size() - 1], "months": months, "bits": bits}


## The year in one sentence: "12 crops are recorded, ready May-November." A list with no food, or with
## food that names no harvest time, says which of those it is rather than showing an empty year.
static func year_text(catalogue: PlantCatalogue) -> String:
	if catalogue == null or not _has_food(catalogue):
		return NO_FOOD
	var span: Dictionary = ready_span(catalogue)
	if int(span["bits"]) == 0:
		return NONE_RECORDED
	var total: int = _crop_count(catalogue)
	return "%d crop%s are recorded, ready %s." % [
		total, "" if total == 1 else "s", PlantSpeciesScript.months_run_text(int(span["bits"]))
	]


## The crops nothing is recorded about: edible, but with no harvest window, so no month can list them.
static func unstated(catalogue: PlantCatalogue) -> Array[PlantSpecies]:
	var out: Array[PlantSpecies] = []
	if catalogue == null:
		return out
	for plant: PlantSpecies in catalogue.all():
		if plant.is_edible() and plant.harvest_months == 0:
			out.append(plant)
	out.sort_custom(func(a: PlantSpecies, b: PlantSpecies) -> bool:
		return a.display_name() < b.display_name())
	return out


## The crops nothing is recorded about, in one line, named - so a page can say what it cannot place
## rather than quietly leaving them off every month. Empty when every food crop has a window.
static func unstated_line(catalogue: PlantCatalogue) -> String:
	var missing: Array[PlantSpecies] = unstated(catalogue)
	if missing.is_empty():
		return ""
	var names: PackedStringArray = PackedStringArray()
	for plant: PlantSpecies in missing:
		names.append(plant.display_name())
	var one: bool = missing.size() == 1
	return "%d crop%s %s nothing about when %s ready: %s" % [
		missing.size(), "" if one else "s", "says" if one else "say",
		"it is" if one else "they are", ", ".join(names)
	]


# --- saying it ----------------------------------------------------------------------------


## What a month comes to, in one sentence. An empty month is a real answer and says so plainly: nothing
## is recorded as ready then, which is a fact about the list and not a fault.
static func describe_rows(rows_list: Array, month: int) -> String:
	var name: String = month_name(month)
	if name.is_empty():
		return "no month was chosen"
	if rows_list.is_empty():
		return "nothing is recorded as ready in %s." % name
	return "%d crop%s ready in %s." % [rows_list.size(), "" if rows_list.size() == 1 else "s", name]


# --- the internals ------------------------------------------------------------------------


static func _has_food(catalogue: PlantCatalogue) -> bool:
	for plant: PlantSpecies in catalogue.all():
		if plant.is_edible():
			return true
	return false


## The crops the year's sentence is counting: edible and dated, because a crop with no window is not
## one of the "N crops ... ready ..." - it is what `unstated_line` accounts for instead.
static func _crop_count(catalogue: PlantCatalogue) -> int:
	var total: int = 0
	for plant: PlantSpecies in catalogue.all():
		if plant.is_edible() and plant.harvest_months != 0:
			total += 1
	return total