extends Node
## The sun study: that the astronomy is astronomical (visualization spec §16).
##
## These tests are written against facts from outside this codebase - Meeus's own worked
## example, the published dates the equation of time is zero, the standard thirty-four
## arcminutes of refraction at the horizon, the almanac's sunrise in Ottawa. A test that
## agreed only with `sun_study.gd` would pass for a file that was consistently wrong.

const SunStudyScript := preload("res://scripts/vis/sun_study.gd")
const Document := preload("res://scripts/draft/draft_document.gd")

## The first moment of JD 2000.0, which is a definition rather than a measurement.
const J2000 := 2451545.0

# --- the calendar ---------------------------------------------------------------------


func test_the_julian_day_of_a_known_instant() -> void:
	assert(is_equal_approx(SunStudyScript.julian_day(2000, 1, 1, 12.0), J2000))
	# Meeus, Astronomical Algorithms, example 7.a: 1957 October 4.81 (19:26:24 UT).
	var meeus: float = SunStudyScript.julian_day(1957, 10, 4, 19.0 + 26.0 / 60.0 + 24.0 / 3600.0)
	assert(absf(meeus - 2436116.31) < 0.0001, "Meeus's own worked example should reproduce")


func test_the_julian_day_carries_the_hour_and_the_day() -> void:
	assert(is_equal_approx(
		SunStudyScript.julian_day(2025, 6, 21, 18.0)
		- SunStudyScript.julian_day(2025, 6, 21, 6.0),
		0.5
	))
	assert(is_equal_approx(
		SunStudyScript.julian_day(2025, 6, 22) - SunStudyScript.julian_day(2025, 6, 21),
		1.0
	))


func test_a_day_of_the_year_names_a_date_and_back_again() -> void:
	assert(SunStudyScript.month_day_from_day_of_year(172) == Vector2i(6, 21))
	assert(SunStudyScript.month_day_from_day_of_year(1) == Vector2i(1, 1))
	assert(SunStudyScript.month_day_from_day_of_year(365) == Vector2i(12, 31))
	for day in range(1, 366):
		var month_day: Vector2i = SunStudyScript.month_day_from_day_of_year(day)
		assert(SunStudyScript.day_of_year_from_month_day(month_day.x, month_day.y) == day)


func test_a_leap_year_has_a_twenty_ninth_of_february() -> void:
	assert(SunStudyScript.month_day_from_day_of_year(60, 2024) == Vector2i(2, 29))
	assert(SunStudyScript.month_day_from_day_of_year(60, 2025) == Vector2i(3, 1))
	assert(SunStudyScript.days_in_year(2024) == 366)
	assert(SunStudyScript.days_in_year(2025) == 365)
	# The study is computed for one fixed year so that it repeats. A leap epoch would only
	# move the dates after February, and the year changes the sun by less than a minute of
	# arc - which is why no drawing needs to carry one.
	assert(not SunStudyScript.is_leap_year(SunStudyScript.EPOCH_YEAR))


func test_the_instant_of_a_day_and_an_hour_is_the_epoch_year() -> void:
	var noon: float = SunStudyScript.jd_of_day(172, 12.0)
	assert(is_equal_approx(noon, SunStudyScript.julian_day(SunStudyScript.EPOCH_YEAR, 6, 21, 12.0)))


# --- the tilt, and where the sun stands ----------------------------------------------


func test_the_tilt_of_the_earth_is_where_the_books_say() -> void:
	# 23°26'21.448" at J2000, drifting by about 47 arcseconds a century.
	assert(absf(SunStudyScript.mean_obliquity(J2000) - 23.4392911) < 0.000001)
	var jd: float = SunStudyScript.jd_of_day(172)
	assert(absf(SunStudyScript.mean_obliquity(jd) - 23.436) < 0.003)
	# Nutation is a wobble of under ten arcseconds, which is why the true obliquity differs
	# from the mean one by a thousandth of a degree and not more.
	assert(absf(SunStudyScript.obliquity(jd) - SunStudyScript.mean_obliquity(jd)) < 0.003)


func test_the_equinox_puts_the_sun_on_the_equator() -> void:
	# The vernal equinox of 2025 falls at 09:01 UT on 20 March. At that instant the sun's
	# declination is zero by definition, so a study that says otherwise is wrong about
	# something earlier in the chain - the calendar, the longitude or the obliquity.
	var equinox: float = SunStudyScript.julian_day(2025, 3, 20, 9.0 + 1.0 / 60.0)
	assert(absf(SunStudyScript.declination_at(equinox)) < 0.01)


func test_the_solstice_puts_the_sun_as_far_out_as_the_tilt_allows() -> void:
	# The June solstice of 2025 falls at 02:42 UT on 21 June, and the earth's tilt is the
	# ceiling on the declination: the sun can stand no further from the equator than that.
	var solstice: float = SunStudyScript.julian_day(2025, 6, 21, 2.0 + 42.0 / 60.0)
	var declination: float = SunStudyScript.declination_at(solstice)
	assert(absf(declination - SunStudyScript.obliquity(solstice)) < 0.005)
	assert(absf(declination - 23.44) < 0.01)


func test_the_sun_never_stands_further_from_the_equator_than_the_tilt() -> void:
	for day in range(1, 366, 7):
		var jd: float = SunStudyScript.jd_of_day(day)
		assert(absf(SunStudyScript.declination_at(jd)) <= SunStudyScript.obliquity(jd) + 0.0001)


# --- the equation of time -------------------------------------------------------------


func test_the_equation_of_time_is_the_sundials_error() -> void:
	# Published as zero on four dates a year: 15 April, 13 June, 1 September, 25 December.
	for day in [105, 164, 244, 359]:
		assert(
			absf(SunStudyScript.equation_of_time_on(day)) < 0.5,
			"the equation of time is within half a minute of zero on day %d" % day
		)
	# And its extremes: about +16.4 minutes in early November, -14.2 in mid-February. A
	# sundial runs up to sixteen minutes fast, which is a quarter of a degree of shadow.
	assert(SunStudyScript.equation_of_time_on(307) > 16.3)
	assert(SunStudyScript.equation_of_time_on(42) < -14.0)


# --- refraction ------------------------------------------------------------------------


func test_refraction_lifts_the_sun_at_the_horizon_and_not_overhead() -> void:
	# Twenty-eight to twenty-nine arcminutes of lift with the sun on the horizon, from the
	# standard table. About a minute at 45 degrees up, and nothing at all overhead.
	var horizon: float = SunStudyScript.refraction(0.0)
	assert(horizon > 0.45 and horizon < 0.50, "about 28 arcminutes at true zero")
	assert(absf(SunStudyScript.refraction(45.0) - 0.0167) < 0.003)
	assert(absf(SunStudyScript.refraction(90.0)) < 0.001)
	# Below a degree under the horizon the expression stops meaning anything, so it is
	# dropped rather than extrapolated into a number nobody should act on.
	assert(is_zero_approx(SunStudyScript.refraction(-1.5)))
	assert(is_zero_approx(SunStudyScript.refraction(-30.0)))


func test_refraction_falls_away_as_the_sun_climbs() -> void:
	var previous: float = SunStudyScript.refraction(-0.9) + 1.0
	for step in range(0, 40):
		var altitude: float = -0.9 + float(step) * 2.3
		var lift: float = SunStudyScript.refraction(altitude)
		assert(lift <= previous + 0.0001, "refraction must not increase with altitude")
		previous = lift


func test_the_horizon_refraction_is_the_thirty_four_arcminutes_it_is_named_for() -> void:
	# The standard convention pairs thirty-four arcminutes of refraction with the sun's
	# sixteen of radius to make sunrise. Feeding the formula the altitude that convention
	# implies has to give that same refraction back, or the two halves disagree.
	var named: float = SunStudyScript.REFRACTION_AT_HORIZON_DEG
	assert(absf(SunStudyScript.refraction(-named) - named) < 0.01)
	# And the convention itself: sunrise is when the upper limb appears, not when the
	# centre's altitude passes zero.
	assert(is_equal_approx(
		SunStudyScript.SUNRISE_ALTITUDE_DEG,
		-(SunStudyScript.SEMIDIAMETER_DEG + SunStudyScript.REFRACTION_AT_HORIZON_DEG)
	))


# --- the sun in the sky ----------------------------------------------------------------


func test_a_midsummer_noon_stands_at_the_latitude_and_the_tilt() -> void:
	# The classic identity: at solar noon the altitude is ninety degrees less the angle
	# between the observer and the sun's own parallel, which outside the tropics - where the
	# sun is south of the observer - is 90 - latitude + declination. Checking it at two
	# latitudes checks the trigonometry rather than one answer.
	for latitude in [45.0, 60.0]:
		var sun: Dictionary = SunStudyScript.position(latitude, 172, 12.0)
		var expected: float = 90.0 - absf(latitude - float(sun["declination_deg"]))
		assert(
			absf(float(sun["altitude_deg"]) - expected) < 0.05,
			"noon altitude at %.0f degrees north" % latitude
		)
		# Due south, because the observer is north of the parallel the solstice sun stands on.
		assert(absf(float(sun["azimuth_deg"]) - 180.0) < 0.01)
	# Over the equator the sun has crossed to the far side of the zenith on this day, so the
	# identity is the other branch and the *shadow* has changed ends: it falls south. A noon
	# altitude as a single formula would have said 113 degrees here.
	var tropics: Dictionary = SunStudyScript.position(0.0, 172, 12.0)
	assert(absf(float(tropics["altitude_deg"]) - (90.0 - 23.44)) < 0.05)
	var bearing: float = float(tropics["azimuth_deg"])
	assert(minf(bearing, 360.0 - bearing) < 0.01, "due north over the equator on the solstice")


func test_the_sun_is_up_before_its_centre_clears_the_horizon() -> void:
	var sunrise: float = float(SunStudyScript.daylight(45.0, 79)["sunrise_hour"])
	# Just after first light: the centre is still below the horizon and the sun is up,
	# because the upper limb is what appears first. This is the whole reason `is_up` is not
	# a comparison against zero.
	var just_up: Dictionary = SunStudyScript.position(45.0, 79, sunrise + 0.02)
	assert(float(just_up["altitude_deg"]) < 0.0)
	assert(bool(just_up["is_up"]))
	# At the exact moment of sunrise the limb is on the horizon, not above it.
	assert(not bool(SunStudyScript.position(45.0, 79, sunrise)["is_up"]))
	# And well before it, the sun is down in both senses.
	var before: Dictionary = SunStudyScript.position(45.0, 79, sunrise - 0.5)
	assert(not bool(before["is_up"]))
	assert(float(before["apparent_altitude_deg"]) < 0.0)


func test_the_apparent_altitude_is_the_true_one_lifted_by_refraction() -> void:
	var sun: Dictionary = SunStudyScript.position(45.0, 79, 12.0)
	assert(is_equal_approx(
		float(sun["apparent_altitude_deg"]),
		float(sun["altitude_deg"]) + SunStudyScript.refraction(float(sun["altitude_deg"]))
	))
	# Overhead there is nothing to lift, so the two agree.
	var high: Dictionary = SunStudyScript.position(0.0, 79, 12.0)
	assert(absf(float(high["apparent_altitude_deg"]) - float(high["altitude_deg"])) < 0.01)


func test_the_same_moment_gives_the_same_sun() -> void:
	var first: Dictionary = SunStudyScript.position_for(
		SunStudyScript.site(45.0, -75.0, -5.0), SunStudyScript.moment(200, 15.25)
	)
	var second: Dictionary = SunStudyScript.position_for(
		SunStudyScript.site(45.0, -75.0, -5.0), SunStudyScript.moment(200, 15.25)
	)
	assert(first == second)


func test_a_solar_time_and_a_clock_time_are_not_the_same_number() -> void:
	# A site on the prime meridian on UTC reads its own solar time up to sixteen minutes
	# off the clock, and the whole point of the site is that the study pays that.
	var site: Dictionary = SunStudyScript.site(45.0, 0.0, 0.0)
	var moment: Dictionary = SunStudyScript.moment(105, 12.0)
	var solar: float = SunStudyScript.solar_time(site, moment)
	assert(absf(solar - (12.0 + SunStudyScript.equation_of_time_on(105) / 60.0)) < 0.0001)
	# The two paths agree once the difference is accounted for: this is the independent
	# check that the site machinery is the same trigonometry rather than a second copy.
	var by_site: Dictionary = SunStudyScript.position_for(site, moment)
	var by_solar: Dictionary = SunStudyScript.position(45.0, 105, solar)
	assert(absf(float(by_site["altitude_deg"]) - float(by_solar["altitude_deg"])) < 0.001)
	assert(absf(float(by_site["azimuth_deg"]) - float(by_solar["azimuth_deg"])) < 0.001)


# --- a site on the clock ---------------------------------------------------------------


func test_fifteen_degrees_of_longitude_is_an_hour_of_clock() -> void:
	# Four minutes a degree: the earth turns fifteen degrees an hour, so a site a zone-wide
	# step to the west sees every solar event an hour later.
	var moment: Dictionary = SunStudyScript.moment(200, 12.0)
	var west: float = SunStudyScript.solar_time(SunStudyScript.site(45.0, -15.0, 0.0), moment)
	var east: float = SunStudyScript.solar_time(SunStudyScript.site(45.0, 15.0, 0.0), moment)
	assert(absf(east - west - 2.0) < 0.000001)
	# And the sun itself knows it: two hours apart in solar time is two hours apart in the
	# sky, which at 45 degrees north is a different day's worth of shadow direction.
	var west_sun: Dictionary = SunStudyScript.position_for(
		SunStudyScript.site(45.0, -15.0, 0.0), SunStudyScript.moment(200, 16.0)
	)
	var east_sun: Dictionary = SunStudyScript.position_for(
		SunStudyScript.site(45.0, 15.0, 0.0), SunStudyScript.moment(200, 16.0)
	)
	assert(float(west_sun["azimuth_deg"]) > 180.0)
	assert(float(east_sun["azimuth_deg"]) > 180.0)
	# The eastern site's solar time is two hours later, so its sun has gone further round.
	assert(float(east_sun["azimuth_deg"]) > float(west_sun["azimuth_deg"]))


func test_a_zone_offset_moves_the_clock_and_not_the_sky() -> void:
	# The same place on standard time and on summer time, each read at the hour its own
	# clock calls noon: one instant, one sun. Only the labels differ.
	var standard: Dictionary = SunStudyScript.position_for(
		SunStudyScript.site(45.0, -75.0, -5.0), SunStudyScript.moment(200, 12.0)
	)
	var summer: Dictionary = SunStudyScript.position_for(
		SunStudyScript.site(45.0, -75.0, -4.0), SunStudyScript.moment(200, 13.0)
	)
	assert(is_equal_approx(float(standard["altitude_deg"]), float(summer["altitude_deg"])))
	assert(is_equal_approx(float(standard["azimuth_deg"]), float(summer["azimuth_deg"])))
	assert(is_equal_approx(float(standard["clock_hour"]), 12.0))
	assert(is_equal_approx(float(summer["utc_offset_hours"]), -4.0))


func test_the_clock_time_and_the_solar_time_are_inverses() -> void:
	var site: Dictionary = SunStudyScript.site(52.0, 13.4, 1.0)
	var moment: Dictionary = SunStudyScript.moment(300, 7.25)
	var solar: float = SunStudyScript.solar_time(site, moment)
	assert(absf(SunStudyScript.clock_time(site, moment, solar) - 7.25) < 0.000001)


# --- day and night ---------------------------------------------------------------------


func test_an_equinox_day_is_a_little_over_twelve_hours() -> void:
	# On the equator at the equinox the day is twelve hours and seven minutes, not twelve:
	# the half degree of refraction and the sun's own width are the difference. This is the
	# cleanest check that refraction is in the day length at all.
	var day: float = float(SunStudyScript.daylight(0.0, 79)["day_length_hours"])
	assert(day > 12.08 and day < 12.14, "twelve hours and seven minutes on the equator")
	# And it grows with latitude, which is what makes a northern garden's summer long.
	var north: float = float(SunStudyScript.daylight(45.0, 79)["day_length_hours"])
	assert(north > 12.0 and north < 12.3)
	assert(north > day)


func test_the_standard_sunrise_altitude_makes_the_day_longer_than_the_geometry_would() -> void:
	var latitude: float = 45.0
	var declination: float = SunStudyScript.declination(79)
	var geometric_half: float = rad_to_deg(acos(clampf(
		-tan(deg_to_rad(latitude)) * tan(deg_to_rad(declination)), -1.0, 1.0
	))) / 15.0
	var reported: float = float(SunStudyScript.daylight(latitude, 79)["day_length_hours"])
	assert(reported > geometric_half * 2.0 + 0.05, "refraction and the sun's radius add minutes")


func test_the_day_grows_longer_as_you_go_north() -> void:
	assert(float(SunStudyScript.daylight(60.0, 172)["day_length_hours"]) > 18.5)
	assert(float(SunStudyScript.daylight(0.0, 172)["day_length_hours"]) < 12.2)
	# The same day, seen from the other side: the southern hemisphere's midwinter.
	assert(float(SunStudyScript.daylight(-45.0, 172)["day_length_hours"]) < 9.5)


func test_sunrise_and_sunset_are_symmetric_about_solar_noon() -> void:
	for latitude in [0.0, 30.0, 60.0]:
		var hours: Dictionary = SunStudyScript.daylight(latitude, 200)
		assert(absf(
			float(hours["sunrise_hour"]) - (24.0 - float(hours["sunset_hour"]))
		) < 0.000001)
		assert(is_equal_approx(float(hours["day_length_hours"]), float(hours["sunset_hour"]) - float(hours["sunrise_hour"])))


func test_the_arctic_gets_a_day_with_no_sunrise_to_report() -> void:
	var midsummer: Dictionary = SunStudyScript.daylight(80.0, 172)
	assert(bool(midsummer["polar_day"]))
	assert(not bool(midsummer["polar_night"]))
	assert(is_equal_approx(float(midsummer["day_length_hours"]), 24.0))
	var midwinter: Dictionary = SunStudyScript.daylight(80.0, 355)
	assert(bool(midwinter["polar_night"]))
	assert(is_equal_approx(float(midwinter["day_length_hours"]), 0.0))
	# An ordinary latitude reports neither, which is what a caller has to be able to tell
	# apart from "the sun sets at midnight" or "at a quarter past 23".
	var ordinary: Dictionary = SunStudyScript.daylight(45.0, 172)
	assert(not bool(ordinary["polar_day"]) and not bool(ordinary["polar_night"]))


func test_daylight_reads_the_sites_own_clock() -> void:
	var standard: Dictionary = SunStudyScript.daylight_for(
		SunStudyScript.site(45.0, -75.0, -5.0), SunStudyScript.moment(79, 12.0)
	)
	var summer: Dictionary = SunStudyScript.daylight_for(
		SunStudyScript.site(45.0, -75.0, -4.0), SunStudyScript.moment(79, 12.0)
	)
	# At one longitude, turning the clock forward an hour moves every solar event an hour
# later on the dial: the same sun, read off a different clock. This is the fact that makes
# summer time worth modelling at all - it is the difference between the client's sunrise
# and the sun's.
	assert(absf(
		float(summer["sunrise_clock_hour"]) - (float(standard["sunrise_clock_hour"]) + 1.0)
	) < 0.000001)
	assert(absf(float(standard["sunrise_clock_hour"]) - 6.03) < 0.15)
	assert(absf(float(standard["sunset_clock_hour"]) - 18.20) < 0.15)


func test_a_summer_morning_in_ottawa_is_where_the_almanac_puts_it() -> void:
	# The almanac for Ottawa - a tenth of a degree north of this site and half a degree west
	# of it - gives sunrise 05:14 and sunset 20:54 Eastern Daylight Time on 21 June, which
	# is 04:14 and 19:54 on standard time. This is the strongest single check in the file:
	# the calendar, the longitude, the zone, the equation of time, the refraction, the tilt
	# and the trigonometry all have to be right together for it to come out.
	var ottawa: Dictionary = SunStudyScript.daylight_for(
		SunStudyScript.site(45.0, -75.0, -5.0), SunStudyScript.moment(172, 12.0)
	)
	assert(absf(float(ottawa["sunrise_clock_hour"]) - 4.23) < 0.15)
	assert(absf(float(ottawa["sunset_clock_hour"]) - 19.90) < 0.15)
	# And the winter solstice, which is the other end of the same fact: under nine hours.
	var winter: Dictionary = SunStudyScript.daylight_for(
		SunStudyScript.site(45.0, -75.0, -5.0), SunStudyScript.moment(355, 12.0)
	)
	assert(float(winter["day_length_hours"]) > 8.5 and float(winter["day_length_hours"]) < 9.0)


# --- aiming a light --------------------------------------------------------------------


func test_aiming_the_sun_for_a_site_needs_the_sun_to_be_up() -> void:
	var light := DirectionalLight3D.new()
	add_child(light)
	var before: Transform3D = light.transform
	var night: bool = SunStudyScript.apply_for(light, SunStudyScript.site(45.0, -75.0, -5.0), SunStudyScript.moment(355, 2.0))
	assert(not night)
	# Not "moved somewhere harmless": not moved.
	assert(light.transform == before)
	light.queue_free()


func test_aiming_the_sun_for_a_site_puts_it_on_the_side_the_clock_says() -> void:
	var site: Dictionary = SunStudyScript.site(45.0, -75.0, -5.0)
	var morning: Dictionary = SunStudyScript.position_for(site, SunStudyScript.moment(172, 9.0))
	var afternoon: Dictionary = SunStudyScript.position_for(site, SunStudyScript.moment(172, 13.0))
	# Before solar noon the sun is east of south, after it west: both on the solstice, so
	# the difference is the clock and nothing else.
	assert(float(morning["azimuth_deg"]) < 180.0)
	assert(float(afternoon["azimuth_deg"]) > 180.0)
	# 09:00 standard time is a low sun; 13:00 is a high one.
	assert(float(morning["altitude_deg"]) < float(afternoon["altitude_deg"]))
	var light := DirectionalLight3D.new()
	add_child(light)
	assert(SunStudyScript.apply_for(light, site, SunStudyScript.moment(172, 13.0)))
	var altitude: float = deg_to_rad(float(afternoon["altitude_deg"]))
	var azimuth: float = deg_to_rad(float(afternoon["azimuth_deg"]))
	var expected := Vector3(
		sin(azimuth) * cos(altitude), sin(altitude), -cos(azimuth) * cos(altitude)
	) * SunStudyScript.DISTANCE_M
	assert(light.position.distance_to(expected) < 0.001)
	# West is -X in this project's model space (north is -Z), so an afternoon sun in the
	# northern hemisphere lights the garden from over there.
	assert(light.position.x < 0.0)
	light.queue_free()


# --- saying it in words ----------------------------------------------------------------


func test_clock_text_reads_a_time_of_day() -> void:
	assert(SunStudyScript.clock_text(5.9) == "05:54")
	assert(SunStudyScript.clock_text(0.0) == "00:00")
	assert(SunStudyScript.clock_text(13.5) == "13:30")
	# Rounding up to the next day is the next day's midnight, and a time before midnight
	# is the evening before rather than a negative hour.
	assert(SunStudyScript.clock_text(23.999) == "00:00")
	assert(SunStudyScript.clock_text(-0.5) == "23:30")
	assert(SunStudyScript.clock_text(24.0) == "00:00")


func test_describe_for_says_when_the_sun_rises_and_sets() -> void:
	var site: Dictionary = SunStudyScript.site(45.0, -75.0, -5.0)
	var daytime: String = SunStudyScript.describe_for(site, SunStudyScript.moment(172, 16.0))
	assert(daytime.contains("Sunrise"))
	assert(daytime.contains("sunset"))
	assert(not daytime.contains("below the horizon"))
	assert(daytime.contains(":"), "sunrise and sunset are times of day")
	var night: String = SunStudyScript.describe_for(site, SunStudyScript.moment(172, 22.0))
	assert(night.contains("below the horizon"))
	assert(night.contains("Sunset was"))
	# A latitude where the sun genuinely does not set says that rather than inventing a
	# time it does not have.
	var arctic: String = SunStudyScript.describe_for(
		SunStudyScript.site(80.0, -75.0, -5.0), SunStudyScript.moment(172, 12.0)
	)
	assert(arctic.contains("does not set"))
	assert(arctic.contains("80°N"))


# --- what a study has to carry to be evidence --------------------------------------------


func test_the_site_and_the_moment_carry_the_keys_the_study_reads() -> void:
	var site: Dictionary = SunStudyScript.site(45.0, -75.0, -5.0)
	assert(site.keys().size() == 3)
	var moment: Dictionary = SunStudyScript.moment(172, 16.0)
	assert(moment.has("day_of_year") and moment.has("clock_hour") and moment.has("year"))
	# A hand-built dictionary with the same keys is the same thing, which is what lets the
	# drawing hold a site without importing the study.
	var handwritten: Dictionary = {
		"latitude": 45.0, "longitude": -75.0, "utc_offset_hours": -5.0,
	}
	assert(SunStudyScript.position_for(handwritten, moment) == SunStudyScript.position_for(site, moment))


func test_a_recorded_sun_carries_enough_to_reproduce_it() -> void:
	# A still's record has to stand on its own: given the sun it recorded, a reader must be
	# able to say where the light came from without the drawing it was cast in.
	var site: Dictionary = SunStudyScript.site(45.0, -75.0, -5.0)
	var moment: Dictionary = SunStudyScript.moment(200, 15.0)
	var sun: Dictionary = SunStudyScript.position_for(site, moment)
	for key in ["latitude_deg", "longitude_deg", "utc_offset_hours", "day_of_year", "clock_hour", "year"]:
		assert(sun.has(key), key)
	var rebuilt: Dictionary = SunStudyScript.position_for(
		SunStudyScript.site(
			float(sun["latitude_deg"]), float(sun["longitude_deg"]), float(sun["utc_offset_hours"])
		),
		SunStudyScript.moment(int(sun["day_of_year"]), float(sun["clock_hour"]), int(sun["year"]))
	)
	assert(is_equal_approx(float(rebuilt["altitude_deg"]), float(sun["altitude_deg"])))
	assert(is_equal_approx(float(rebuilt["azimuth_deg"]), float(sun["azimuth_deg"])))


func test_a_drawings_site_is_the_shape_the_study_takes() -> void:
	var document = Document.new()
	# The drawing's site is a dictionary in the study's own shape, so it can be handed over
	# without a translation step - and a test is what keeps the two from drifting apart.
	var sun: Dictionary = SunStudyScript.position_for(document.site(), SunStudyScript.moment(200, 12.0))
	assert(bool(sun["is_up"]))
	# Moving the drawing fifteen degrees west makes the sun an hour later there, which is
	# the whole reason the site lives with the plan.
	var before: float = float(sun["azimuth_deg"])
	document.set_site(
		document.site_latitude, document.site_longitude - 15.0, document.site_utc_offset_hours
	)
	var after: Dictionary = SunStudyScript.position_for(document.site(), SunStudyScript.moment(200, 12.0))
	assert(float(after["azimuth_deg"]) < before, "an hour earlier in the day is further east")