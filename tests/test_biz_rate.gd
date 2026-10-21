extends Node
## Rates as parts per million, printed and read the way a person writes a percentage (spec §2.1a).
##
## What is under test is the reason this is parts per million and not basis points: 9.975% - Quebec's
## QST - has no basis-point representation at all, so a table in basis points cannot state a rate
## published by a tax authority. And the reason it is one module: a rate printed on a schedule and on
## the invoice that bills it must be the same characters.

const RateScript := preload("res://scripts/biz/rate.gd")


func test_a_percent_is_ten_thousand_parts_per_million() -> void:
	assert(RateScript.PER_PERCENT == 10000)
	assert(RateScript.percent_text(RateScript.WHOLE) == "100%")
	assert(RateScript.percent_text(130000) == "13%")
	assert(RateScript.percent_text(0) == "0%")


func test_the_rate_no_basis_point_table_can_hold_prints_exactly() -> void:
	assert(RateScript.percent_text(99750) == "9.975%")


func test_trailing_zeros_are_trimmed_because_a_rate_is_never_published_with_them() -> void:
	assert(RateScript.percent_text(5000) == "0.5%")
	assert(RateScript.percent_text(10000) == "1%")
	assert(RateScript.percent_text(10) == "0.001%")
	assert(RateScript.percent_text(1) == "0.0001%")
	assert(RateScript.percent_text(-25000) == "-2.5%")


func test_a_rate_nobody_has_prints_as_a_dash_and_is_never_zero() -> void:
	assert(RateScript.percent_text(RateScript.INVALID) == "—")
	assert(not RateScript.is_valid(RateScript.INVALID))
	assert(RateScript.is_valid(0))


func test_reading_a_percent_accepts_the_ways_a_person_writes_one() -> void:
	assert(RateScript.parse_percent("13") == 130000)
	assert(RateScript.parse_percent("13%") == 130000)
	assert(RateScript.parse_percent("9.975%") == 99750)
	assert(RateScript.parse_percent(" 0.5 %") == 5000)
	assert(RateScript.parse_percent(".5") == 5000)
	assert(RateScript.parse_percent("-2.5%") == -25000)
	assert(RateScript.parse_percent("+75") == 750000)
	assert(RateScript.parse_percent("0.0001%") == 1)


func test_a_rate_typed_too_finely_is_refused_rather_than_rounded() -> void:
	assert(RateScript.parse_percent("0.00001%") == RateScript.INVALID)
	assert(RateScript.parse_percent("13.12345") == RateScript.INVALID)


func test_what_is_not_a_percent_is_refused() -> void:
	assert(RateScript.parse_percent("") == RateScript.INVALID)
	assert(RateScript.parse_percent("twelve") == RateScript.INVALID)
	assert(RateScript.parse_percent("13.5.2") == RateScript.INVALID)
	assert(RateScript.parse_percent("1e3") == RateScript.INVALID)
	assert(RateScript.parse_percent("-") == RateScript.INVALID)


func test_reading_back_what_it_printed_gives_the_same_rate() -> void:
	for ppm in [0, 1, 10, 5000, 99750, 130000, 250000, RateScript.WHOLE]:
		assert(RateScript.parse_percent(RateScript.percent_text(ppm)) == ppm,
			"%d printed as %s" % [ppm, RateScript.percent_text(ppm)])


func test_a_date_is_a_date_all_digits_and_a_real_day_of_a_real_month() -> void:
	assert(RateScript.is_date("2026-06-01"))
	assert(RateScript.is_date("2024-02-29"))
	assert(not RateScript.is_date("2026-02-29"))
	assert(not RateScript.is_date("2026-6-1"))
	assert(not RateScript.is_date("2026-13-01"))
	assert(not RateScript.is_date("2026-00-10"))
	assert(not RateScript.is_date("2026-04-31"))
	assert(not RateScript.is_date("June"))
	assert(not RateScript.is_date(""))
	assert(not RateScript.is_date("2026/06/01"))