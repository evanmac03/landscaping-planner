extends Node
## The sun and shadow study.
##
## This is the report module on its own: the moments a study is made of, the arithmetic of one
## shadow, the rows a table shows, the days the study covers, and what it all comes to. The page is
## tested in `test_sun_window.gd` and the join to the menu in `test_hud_sun.gd`; `SunStudy`'s own
## astronomy is tested in `test_vis_sun.gd` and is not repeated here.
##
## Three things are pinned throughout, and each is a decision rather than a detail:
##
## - **A shadow is arithmetic on a sun and a height**, so a test can work the answer out by hand from
##   the sun the study reports: the length is the height over the tangent of the altitude.
## - **A sun below the horizon casts nothing**, and that is a refusal naming the moment rather than a
##   length of zero - zero is what a sun straight overhead casts.
## - **A grazing sun states a number that is not worth quoting**, so the length is reported and a
##   note says what kind of number it is.

const SunReportScript := preload("res://scripts/vis/sun_report.gd")
const SunStudyScript := preload("res://scripts/vis/sun_study.gd")
const UnitsScript := preload("res://scripts/draft/units.gd")

## Ottawa: north of the fortieth, five hours behind Greenwich, so a study of it is a study with a
## real longitude and a real offset in it rather than a site at the origin.
const SITE := {"latitude": 45.0, "longitude": -75.0, "utc_offset_hours": -5.0}


# --- helpers --------------------------------------------------------------------------


func _june() -> Array:
	return SunReportScript.preset(&"june_day")


func _december() -> Array:
	return SunReportScript.preset(&"december_day")


## The moment the sun becomes visible with its centre still under the horizon, found by scanning a
## morning rather than typed: it is a three minute window and a typed time would go stale.
func _horizon_crossing() -> Dictionary:
	for minute in range(240, 360):
		var hour: float = float(minute) / 60.0
		var moment_dict: Dictionary = SunStudyScript.moment(SunReportScript.JUNE_SOLSTICE, hour)
		var sun: Dictionary = SunStudyScript.position_for(SITE, moment_dict)
		if bool(sun["is_up"]) and float(sun["altitude_deg"]) <= 0.0:
			return moment_dict
	return {}


func _imperial() -> DraftUnits:
	var units := UnitsScript.new()
	units.system = UnitsScript.System.IMPERIAL
	return units


# --- the moments a study is made of ---------------------------------------------------


func test_the_presets_are_named_and_every_name_has_moments_in_it() -> void:
	var names: Array[StringName] = SunReportScript.preset_names()
	assert(names.size() == 4, "four studies a garden gets asked about")
	for preset_name: StringName in names:
		assert(
			not SunReportScript.preset(preset_name).is_empty(),
			"every name the page offers is a study: %s" % String(preset_name)
		)
		assert(
			SunReportScript.preset_name(preset_name) != "",
			"and every one of them reads as words: %s" % String(preset_name)
		)


func test_a_name_nobody_has_is_an_empty_study_rather_than_a_default_one() -> void:
	assert(SunReportScript.preset(&"sunny_tuesday").is_empty(), "no study by that name")
	assert(SunReportScript.preset_name(&"sunny_tuesday") == "", "and no words for it either")


func test_a_june_day_is_one_day_of_six_moments_and_a_season_is_two_days() -> void:
	assert(_june().size() == 6, "a day is studied at six hours")
	var days: Array[Dictionary] = SunReportScript.days(SITE, _june())
	assert(days.size() == 1, "which is one day")
	assert(
		int(days[0]["day_of_year"]) == SunReportScript.JUNE_SOLSTICE,
		"and it is the June solstice"
	)
	assert(SunReportScript.preset(&"equinoxes").size() == 6, "two equinoxes at three hours each")
	assert(
		SunReportScript.days(SITE, SunReportScript.preset(&"equinoxes")).size() == 2,
		"which is two days"
	)


func test_the_hours_handed_out_are_a_copy_so_the_table_cannot_be_sorted() -> void:
	var hours: Array[float] = SunReportScript.day_hours()
	hours.sort()
	hours.reverse()
	assert(
		SunReportScript.day_hours()[0] < SunReportScript.day_hours()[1],
		"the study's own hours are still in the order a day is read"
	)


func test_a_moment_is_named_by_its_day_and_the_sites_own_clock() -> void:
	var moment_dict: Dictionary = SunStudyScript.moment(SunReportScript.JUNE_SOLSTICE, 16.0)
	assert(SunReportScript.day_of(moment_dict) == 172, "the day is the day it was asked for")
	assert(SunReportScript.time_text(moment_dict) == "16:00", "and the clock time reads as one")
	assert(
		SunReportScript.moment_words(moment_dict) == "21 June 16:00",
		"and together they name the moment: %s" % SunReportScript.moment_words(moment_dict)
	)
	assert(
		SunReportScript.time_text(SunStudyScript.moment(172, 16.5)) == "16:30",
		"a half hour is a time a client can ask about"
	)


func test_a_day_is_named_the_way_a_client_reads_it() -> void:
	assert(SunReportScript.day_words(172) == "21 June", "the solstice is the twenty-first")
	assert(SunReportScript.day_words(1) == "1 January", "the first day is the first of January")
	assert(SunReportScript.day_words(365) == "31 December", "and the last is the last")
	assert(SunReportScript.day_short(355) == "21 Dec", "a table has room for three letters")


func test_the_days_the_study_covers_are_each_day_once_and_in_the_order_asked_for() -> void:
	var mixed: Array = []
	mixed.append_array(SunReportScript.moments_on(SunReportScript.DECEMBER_SOLSTICE, [10.0]))
	mixed.append_array(SunReportScript.moments_on(SunReportScript.JUNE_SOLSTICE, [10.0, 12.0]))
	var days: Array[Dictionary] = SunReportScript.days(SITE, mixed)
	assert(days.size() == 2, "two days, not three: a day asked for twice is one day")
	assert(int(days[0]["day_of_year"]) == 355, "the first day asked for comes first")


# --- one shadow -----------------------------------------------------------------------


func test_a_shadow_is_the_height_over_the_tangent_of_the_altitude() -> void:
	var moment_dict: Dictionary = SunStudyScript.moment(SunReportScript.JUNE_SOLSTICE, 16.0)
	var sun: Dictionary = SunStudyScript.position_for(SITE, moment_dict)
	var cast: Dictionary = SunReportScript.shadow(SITE, moment_dict, 1.8)
	var by_hand: float = 1.8 / tan(deg_to_rad(float(sun["altitude_deg"])))
	assert(bool(cast["ok"]), "there is a shadow at four in the afternoon")
	assert(
		absf(float(cast["length_m"]) - by_hand) < 1e-9,
		"and it is the height over the tangent of the altitude: %f against %f" % [
			float(cast["length_m"]), by_hand
		]
	)
	assert(
		absf(float(cast["altitude_deg"]) - float(sun["altitude_deg"])) < 1e-9,
		"the row reports the same sun the study does"
	)


func test_a_shadow_points_away_from_the_sun() -> void:
	var moment_dict: Dictionary = SunStudyScript.moment(SunReportScript.JUNE_SOLSTICE, 16.0)
	var cast: Dictionary = SunReportScript.shadow(SITE, moment_dict, 1.8)
	var expected: float = fposmod(float(cast["sun_bearing_deg"]) + 180.0, 360.0)
	assert(
		absf(float(cast["bearing_deg"]) - expected) < 1e-9,
		"a shadow falls opposite the sun that casts it"
	)
	assert(float(cast["bearing_deg"]) < 360.0, "and a bearing is a bearing, not a wound-up angle")


func test_a_sun_below_the_horizon_casts_nothing_and_says_so() -> void:
	var cast: Dictionary = SunReportScript.shadow(
		SITE, SunStudyScript.moment(SunReportScript.JUNE_SOLSTICE, 23.0), 1.8
	)
	assert(not bool(cast["ok"]), "there is no shadow at eleven at night")
	assert(
		String(cast["reason"]).contains("below the horizon"),
		"and the refusal says which case it is: %s" % String(cast["reason"])
	)
	assert(
		float(cast["length_m"]) == 0.0,
		"the length is nothing because there is no shadow, and the refusal is what says so"
	)


func test_a_sun_on_the_horizon_has_no_end_and_is_refused_rather_than_divided_by() -> void:
	var moment_dict: Dictionary = _horizon_crossing()
	assert(not moment_dict.is_empty(), "the sun is visible with its centre under the horizon")
	var cast: Dictionary = SunReportScript.shadow(SITE, moment_dict, 1.8)
	assert(not bool(cast["ok"]), "a shadow from a sun on the horizon has no end")
	assert(
		String(cast["reason"]).contains("no end"),
		"and that is what the refusal says: %s" % String(cast["reason"])
	)


func test_a_height_of_nothing_or_of_nan_is_refused_and_the_two_read_differently() -> void:
	var noon: Dictionary = SunStudyScript.moment(SunReportScript.JUNE_SOLSTICE, 12.0)
	var nothing: Dictionary = SunReportScript.shadow(SITE, noon, 0.0)
	var not_a_number: Dictionary = SunReportScript.shadow(SITE, noon, NAN)
	assert(not bool(nothing["ok"]), "a height of nothing casts no shadow")
	assert(not bool(not_a_number["ok"]), "and neither does a height that is not a number")
	assert(
		String(nothing["reason"]) != String(not_a_number["reason"]),
		"the two are different faults and are told apart"
	)


func test_a_grazing_sun_states_the_length_and_says_what_kind_of_number_it_is() -> void:
	var cast: Dictionary = SunReportScript.shadow(
		SITE, SunStudyScript.moment(SunReportScript.DECEMBER_SOLSTICE, 16.0), 1.8
	)
	assert(bool(cast["ok"]), "a December afternoon still has a sun, if a low one")
	assert(float(cast["length_m"]) > 40.0, "and its shadow is forty metres long and more")
	assert(
		String(cast["note"]) != "",
		"so the length is stated with a note about the hour: %s" % String(cast["note"])
	)
	var high: Dictionary = SunReportScript.shadow(
		SITE, SunStudyScript.moment(SunReportScript.JUNE_SOLSTICE, 12.0), 1.8
	)
	assert(
		String(high["note"]) == "",
		"and a high sun's shadow needs no note, because it is a number worth quoting"
	)


func test_a_shadow_in_words_is_its_length_and_its_compass_point() -> void:
	var cast: Dictionary = SunReportScript.shadow(
		SITE, SunStudyScript.moment(SunReportScript.JUNE_SOLSTICE, 16.0), 1.8
	)
	var words: String = SunReportScript.shadow_words(cast)
	assert(words.contains("m"), "the length is in the drawing's own unit: %s" % words)
	assert(words.contains(String(cast["compass"])), "and it says which way it falls: %s" % words)
	var refused: Dictionary = SunReportScript.shadow(
		SITE, SunStudyScript.moment(SunReportScript.JUNE_SOLSTICE, 23.0), 1.8
	)
	assert(
		SunReportScript.shadow_words(refused) == String(refused["reason"]),
		"a shadow there is none of reads as the reason rather than as a length"
	)


func test_a_bearing_is_said_as_a_compass_point() -> void:
	assert(SunReportScript.bearing_words(0.0) == "N", "north is north")
	assert(SunReportScript.bearing_words(90.0) == "E", "and a quarter turn is east")
	assert(SunReportScript.bearing_words(180.0) == "S", "and half a turn is south")
	assert(SunReportScript.bearing_words(270.0) == "W", "and three quarters is west")
	assert(SunReportScript.bearing_words(68.0) == "ENE", "and 68° is east-north-east")
	assert(
		SunReportScript.bearing_words(-1.0) == "N",
		"a bearing just west of north wraps rather than falling off the table"
	)


# --- the study, as rows ---------------------------------------------------------------


func test_a_row_carries_the_moment_the_sun_and_what_the_height_casts() -> void:
	var row: Dictionary = SunReportScript.row_for(
		SITE, SunStudyScript.moment(SunReportScript.JUNE_SOLSTICE, 16.0), 1.8
	)
	assert(String(row["day"]) == "21 Jun", "the day")
	assert(String(row["clock_text"]) == "16:00", "the time")
	assert(bool(row["sun_up"]), "whether the sun is up")
	assert(float(row["altitude_deg"]) > 0.0, "how high it stands")
	assert(float(row["shadow_m"]) > 0.0, "what the height casts")
	assert(
		String(row["text"]).contains("21 Jun 16:00"),
		"and the row says all of it in one line: %s" % String(row["text"])
	)
	assert(
		String(row["still_name"]) == "sun-study-172-1600",
		"and it carries the name a still of it would be filed under"
	)


func test_a_row_whose_sun_is_down_says_so_rather_than_leaving_a_hole() -> void:
	var row: Dictionary = SunReportScript.row_for(
		SITE, SunStudyScript.moment(SunReportScript.DECEMBER_SOLSTICE, 18.0), 1.8
	)
	assert(not bool(row["sun_up"]), "the sun is down at six in December")
	assert(String(row["problem"]) != "", "the row carries the reason")
	assert(
		String(row["text"]).contains("no shadow"),
		"and reads as a sentence: %s" % String(row["text"])
	)


func test_the_rows_come_in_the_order_the_moments_were_given() -> void:
	var reversed: Array = []
	var moments: Array = _june()
	for index in range(moments.size() - 1, -1, -1):
		reversed.append(moments[index])
	var texts: Array[String] = SunReportScript.row_texts(SITE, reversed, 1.8)
	assert(texts.size() == moments.size(), "one row a moment")
	assert(texts[0].contains("18:00"), "and the study reads in the order it was asked for")
	assert(texts[texts.size() - 1].contains("08:00"), "both ways round")


func test_a_row_text_is_the_row_the_module_built() -> void:
	var rows: Array[Dictionary] = SunReportScript.rows(SITE, _june(), 1.8)
	var texts: Array[String] = SunReportScript.row_texts(SITE, _june(), 1.8)
	for index in rows.size():
		assert(
			texts[index] == String(rows[index]["text"]),
			"the list a page shows is the module's own row, not a second one"
		)


# --- the days a study covers ----------------------------------------------------------


func test_a_day_reports_its_sunrise_and_sunset_on_the_sites_own_clock() -> void:
	var day: Dictionary = SunReportScript.day_for(SITE, SunReportScript.JUNE_SOLSTICE)
	assert(not bool(day["polar_day"]) and not bool(day["polar_night"]), "Ottawa has both")
	assert(
		String(day["sunrise_clock"]) < String(day["sunset_clock"]),
		"the sun rises before it sets: %s then %s" % [
			String(day["sunrise_clock"]), String(day["sunset_clock"])
		]
	)
	assert(float(day["day_length_hours"]) > 15.0, "and June is a long day this far north")
	assert(
		String(day["text"]).contains("sunrise"),
		"the day reads as a sentence: %s" % String(day["text"])
	)


func test_a_polar_day_and_a_polar_night_say_so_rather_than_giving_a_time() -> void:
	var arctic: Dictionary = {"latitude": 78.0, "longitude": 15.0, "utc_offset_hours": 1.0}
	var summer: Dictionary = SunReportScript.day_for(arctic, SunReportScript.JUNE_SOLSTICE)
	var winter: Dictionary = SunReportScript.day_for(arctic, SunReportScript.DECEMBER_SOLSTICE)
	assert(bool(summer["polar_day"]), "the sun does not set at 78° north in June")
	assert(
		String(summer["text"]).contains("does not set"),
		"and the day says so: %s" % String(summer["text"])
	)
	assert(bool(winter["polar_night"]), "and does not rise in December")
	assert(
		String(winter["text"]).contains("does not rise"),
		"which is a different sentence: %s" % String(winter["text"])
	)
	assert(float(winter["day_length_hours"]) == 0.0, "a day with no sun is no daylight")


func test_the_day_lines_are_one_a_day_and_in_the_studys_own_order() -> void:
	var texts: Array[String] = SunReportScript.day_texts(
		SITE, SunReportScript.preset(&"equinoxes")
	)
	assert(texts.size() == 2, "two days, two lines")
	assert(texts[0].contains("21 March"), "the first equinox first: %s" % texts[0])
	assert(texts[1].contains("21 September"), "and the second second")
	var none: Array[String] = SunReportScript.day_texts(SITE, [])
	assert(none.is_empty(), "a study of nothing has no days")


# --- what it comes to -----------------------------------------------------------------


func test_the_summary_counts_the_moments_the_days_and_the_sun() -> void:
	var text: String = SunReportScript.summary(SITE, _june(), 1.8)
	assert(text.contains("6 moments"), "six moments: %s" % text)
	assert(text.contains("1 day"), "over one day")
	assert(text.contains("6 with the sun up"), "all of them in the sun")
	assert(
		text.contains("The highest sun stands"),
		"and it names the year's own best moment"
	)
	var december: String = SunReportScript.summary(SITE, _december(), 1.8)
	assert(
		december.contains("1 below the horizon"),
		"a December evening after dark is counted and said: %s" % december
	)


func test_the_highest_sun_is_the_moment_that_casts_the_shortest_shadow() -> void:
	var rows: Array[Dictionary] = SunReportScript.rows(SITE, _june(), 1.8)
	var highest_deg: float = -91.0
	var shortest_m: float = 1e9
	var highest_text: String = ""
	for row: Dictionary in rows:
		if float(row["altitude_deg"]) > highest_deg:
			highest_deg = float(row["altitude_deg"])
			highest_text = String(row["text"])
		shortest_m = minf(shortest_m, float(row["shadow_m"]))
	assert(
		SunReportScript.summary(SITE, _june(), 1.8).contains("12:00"),
		"noon is the highest sun of a June day"
	)
	assert(
		highest_text.contains("12:00") and absf(1.8 / tan(deg_to_rad(highest_deg)) - shortest_m) < 1e-9,
		"and the highest sun is the one whose shadow is shortest"
	)


func test_a_summary_of_nothing_says_there_is_nothing_to_study() -> void:
	var text: String = SunReportScript.summary(SITE, [], 1.8)
	assert(text.contains("no moments"), "a study of nothing says so: %s" % text)
	assert(
		not text.contains("0 moments"),
		"rather than reading as a study that found nothing: %s" % text
	)


func test_a_study_whose_every_moment_is_after_dark_says_it_casts_nothing() -> void:
	var night: Array = SunReportScript.moments_on(SunReportScript.DECEMBER_SOLSTICE, [22.0, 23.0])
	var text: String = SunReportScript.summary(SITE, night, 1.8)
	assert(text.contains("2 below the horizon"), "both moments are after dark: %s" % text)
	assert(
		text.contains("casts nothing"),
		"and the study says what that comes to rather than quoting a shadow: %s" % text
	)


func test_describe_names_the_place_the_size_of_the_study_and_the_height() -> void:
	var text: String = SunReportScript.describe(SITE, _june(), 1.8)
	assert(text.contains("45.0°N"), "the latitude: %s" % text)
	assert(text.contains("75.0°W"), "the longitude")
	assert(text.contains("6 moments"), "how big the study is")
	assert(text.contains("1.8 m"), "and what is doing the casting")
	var empty: String = SunReportScript.describe(SITE, [], 1.8)
	assert(
		empty.contains("no moments"),
		"a study with no moments says so: %s" % empty
	)


# --- naming and wording ---------------------------------------------------------------


func test_a_study_is_named_for_the_moment_it_shows_not_for_the_wall_clock() -> void:
	var names: Array[String] = SunReportScript.still_names(_june())
	assert(names.size() == 6, "a still a moment")
	assert(names[0] == "sun-study-172-0800", "the day and the time: %s" % names[0])
	assert(names[5] == "sun-study-172-1800", "and the last of the day last")
	assert(
		SunReportScript.still_name(SunStudyScript.moment(172, 16.5)) == "sun-study-172-1630",
		"a half hour survives into the name"
	)
	var sorted: Array[String] = names.duplicate()
	sorted.sort()
	assert(sorted == names, "so a folder of them sorts into the order of the study")


func test_the_site_is_worded_once_and_a_whole_zone_reads_as_a_whole_number() -> void:
	assert(
		SunReportScript.site_words(SITE) == "45.0°N 75.0°W, UTC-5",
		"the site as a client reads it: %s" % SunReportScript.site_words(SITE)
	)
	assert(
		SunReportScript.site_words({"latitude": -33.9, "longitude": 151.2, "utc_offset_hours": 10.0})
			== "33.9°S 151.2°E, UTC+10",
		"and a southern site is not called northern"
	)
	assert(
		SunReportScript.site_words({"latitude": 0.0, "longitude": 0.0, "utc_offset_hours": 5.5})
			.contains("UTC+5.5"),
		"a zone that is not a whole hour keeps its half: %s" % SunReportScript.site_words(
			{"latitude": 0.0, "longitude": 0.0, "utc_offset_hours": 5.5}
		)
	)


func test_the_height_is_worded_in_the_drawings_own_units() -> void:
	assert(SunReportScript.height_words(1.8).ends_with("m"), "metric by default")
	var feet: String = SunReportScript.height_words(1.8, _imperial())
	assert(feet.ends_with("ft"), "an imperial drawing reads in feet: %s" % feet)
	assert(
		float(feet.split(" ")[0]) > 5.0 and float(feet.split(" ")[0]) < 6.0,
		"and 1.8 m is a little under six feet: %s" % feet
	)
	assert(
		SunReportScript.describe(SITE, _june(), 1.8, _imperial()).contains("ft"),
		"so a description of the same study reads in the drawing's own unit"
	)