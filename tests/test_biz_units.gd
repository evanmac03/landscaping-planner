extends Node
## Work units: what a cost book prices in, and the dimension that makes a takeoff checkable.
##
## The conversions here are the load-bearing part of the takeoff (spec §2.4): a paving area measured
## off the drawing in square metres has to reach a price list written in square feet without picking
## up the 0.092903 a spreadsheet carries instead of 0.09290304.

const MoneyScript := preload("res://scripts/biz/money.gd")
const WorkUnitScript := preload("res://scripts/biz/work_unit.gd")


func test_every_unit_declares_a_dimension_and_an_exact_ratio() -> void:
	# A unit with no dimension cannot be checked, and a unit with no ratio cannot be converted: both
	# are silent holes in a takeoff, so the table is checked as a whole.
	for unit: StringName in WorkUnitScript.UNITS.keys():
		assert(WorkUnitScript.has(unit))
		assert(WorkUnitScript.dimension(unit) != &"", "unit %s has a dimension" % String(unit))
		assert(WorkUnitScript.RATIOS.has(unit), "unit %s has a ratio" % String(unit))
		var ratio: Array = WorkUnitScript.RATIOS[unit]
		assert(int(ratio[0]) > 0 and int(ratio[1]) > 0, "unit %s has a usable ratio" % String(unit))
		assert(not WorkUnitScript.name_of(unit).is_empty())
		assert(WorkUnitScript.describe(unit).contains(String(WorkUnitScript.dimension(unit))))


func test_the_imperial_conversions_are_exact_ratios_not_rounded_decimals() -> void:
	# 1 ft = 0.3048 m exactly, so a foot is 304.8 mm and 1 m is 3.2808399 ft. The conversions round
	# to the nearest thousandth of a unit - the resolution a quantity is stored at - and nothing
	# coarser.
	assert(WorkUnitScript.convert(1000, &"LIN_FT", &"LIN_M")["quantity_milli"] == 305)
	assert(WorkUnitScript.convert(1000, &"LIN_M", &"LIN_FT")["quantity_milli"] == 3281)
	# Squared and cubed: (381/1250)² and 0.9144³, not 0.0929 and 0.765.
	assert(WorkUnitScript.convert(1000, &"SQ_M", &"SQ_FT")["quantity_milli"] == 10764)
	assert(WorkUnitScript.convert(1000, &"SQ_FT", &"SQ_M")["quantity_milli"] == 93)
	assert(WorkUnitScript.convert(1000, &"CU_YD", &"CU_M")["quantity_milli"] == 765)
	assert(WorkUnitScript.convert(1000, &"CU_M", &"CU_YD")["quantity_milli"] == 1308)


func test_a_conversion_and_back_returns_what_it_started_with() -> void:
	# A round trip through a coarser unit cannot be exact, and saying it can would be a test that
	# fails on correct code: a thousandth of a day is 1.44 minutes, so an hour taken to days and
	# back lands within twelve thousandths of an hour rather than within one. The tolerance is the
	# coarseness of the intermediate unit, named per pair.
	for pair: Array in [
		[&"LIN_M", &"LIN_FT", 1], [&"SQ_M", &"SQ_FT", 1], [&"CU_M", &"CU_YD", 1],
		[&"HOUR", &"DAY", 12],
	]:
		for quantity in [1000, 45000, 1234567]:
			var there: Dictionary = WorkUnitScript.convert(quantity, pair[0], pair[1])
			var back: Dictionary = WorkUnitScript.convert(int(there["quantity_milli"]), pair[1], pair[0])
			var drift: int = absi(int(back["quantity_milli"]) - quantity)
			assert(drift <= int(pair[2]),
				"%d through %s came back %d away" % [quantity, String(pair[1]), drift])


func test_a_dimension_is_what_stops_a_perimeter_being_priced_as_paving() -> void:
	var refused: Dictionary = WorkUnitScript.convert(1000, &"LIN_M", &"SQ_M")
	assert(not bool(refused["ok"]))
	assert(int(refused["quantity_milli"]) == 0)
	assert(String(refused["reason"]).contains("linear"))
	assert(String(refused["reason"]).contains("area"))
	assert(WorkUnitScript.same_dimension(&"LIN_M", &"LIN_FT"))
	assert(WorkUnitScript.same_dimension(&"SQ_M", &"SQ_FT"))
	assert(not WorkUnitScript.same_dimension(&"SQ_M", &"CU_M"))
	assert(not WorkUnitScript.same_dimension(&"SQ_M", &"NOT-A-UNIT"))


func test_time_converts_by_the_hour_and_the_day() -> void:
	assert(WorkUnitScript.dimension(&"HOUR") == WorkUnitScript.TIME)
	assert(WorkUnitScript.dimension(&"DAY") == WorkUnitScript.TIME)
	assert(WorkUnitScript.convert(1000, &"DAY", &"HOUR")["quantity_milli"] == 24000)
	# Eight and a half hours is 0.354 of a working day, to the nearest thousandth.
	assert(WorkUnitScript.convert(8500, &"HOUR", &"DAY")["quantity_milli"] == 354)
	assert(WorkUnitScript.convert(1000, &"EACH", &"EACH")["quantity_milli"] == 1000)


func test_an_unknown_unit_is_refused_with_its_name() -> void:
	var refused: Dictionary = WorkUnitScript.convert(1000, &"SQUARES", &"SQ_M")
	assert(not bool(refused["ok"]))
	assert(String(refused["reason"]).contains("SQUARES"))
	var other: Dictionary = WorkUnitScript.convert(1000, &"SQ_M", &"SQUARES")
	assert(not bool(other["ok"]))
	assert(String(other["reason"]).contains("SQUARES"))
	assert(WorkUnitScript.describe(&"SQUARES").contains("unknown work unit"))
	assert(not WorkUnitScript.has(&"SQUARES"))
	assert(WorkUnitScript.name_of(&"SQ_M") == "m²")


func test_the_preferred_unit_follows_the_document_units() -> void:
	# The drawing already knows whether it is metric (Units), so a takeoff offers the column that
	# matches it rather than making the designer convert.
	assert(WorkUnitScript.preferred(WorkUnitScript.AREA, true) == &"SQ_M")
	assert(WorkUnitScript.preferred(WorkUnitScript.AREA, false) == &"SQ_FT")
	assert(WorkUnitScript.preferred(WorkUnitScript.LINEAR, false) == &"LIN_FT")
	assert(WorkUnitScript.preferred(WorkUnitScript.VOLUME, true) == &"CU_M")
	assert(WorkUnitScript.preferred(WorkUnitScript.TIME, true) == &"HOUR")
	assert(WorkUnitScript.preferred(WorkUnitScript.COUNT, true) == &"EACH")
	assert(WorkUnitScript.preferred(&"invented", true) == &"")


func test_a_large_quantity_does_not_overflow_the_ratio() -> void:
	# The ratios are in lowest terms so that a big garden stays inside a 64-bit int: a million square
	# metres is fine, and the result is the right number rather than a wrapped one. (Quantities are
	# thousandths of a unit, so a million square metres is ten thousand million milli-square-feet.)
	var converted: Dictionary = WorkUnitScript.convert(1000000000, &"SQ_M", &"SQ_FT")
	assert(bool(converted["ok"]))
	assert(int(converted["quantity_milli"]) == 10763910417, "a million square metres in square feet")
	var cubic: Dictionary = WorkUnitScript.convert(100000000, &"CU_YD", &"CU_M")
	assert(bool(cubic["ok"]))
	assert(int(cubic["quantity_milli"]) == 76455486, "a hundred thousand cubic yards in cubic metres")