class_name SunStudy
extends RefCounted
## Where the sun is, for a site and a moment.
##
## Astronomical, not approximate (visualization spec §16). The sun's place in the sky
## comes from the routine Meeus gives and the NOAA solar calculator uses: good to about a
## hundredth of a degree, which is a centimetre of shadow direction for every metre of
## shadow. The equation of time and atmospheric refraction are in it, because between them
## they are worth sixteen minutes and half a degree - the difference between a shadow at
## the client's four o'clock and a shadow at somebody else's noon.
##
## What is left uncertain is the drawing, not the sky. A survey point a metre out or a roof
## height guessed by eye moves a shadow further than the astronomy ever will, so this file
## is careful not to be the limiting error, and the study is as trustworthy as the model it
## is cast from.

## Where the light sits from. Far enough that its shadow map covers the yard, near enough
## that it stays a direction rather than becoming a lamp.
const DISTANCE_M := 40.0

## The year the study is computed for. Any year will do: the sun's position moves by less
## than a hundredth of a degree a year, and the day-of-year numbering only tells leap years
## apart after 28 February, which is not a distinction a shadow study can see. Fixed rather
## than read from the system clock, so that a study is reproducible and a test is not a
## race with the calendar.
const EPOCH_YEAR := 2025

## The mean obliquity of the ecliptic at J2000, in degrees. (Meeus, Astronomical
## Algorithms, 22.2: 23°26'21.448".)
const OBLIQUITY_J2000_DEG := 23.0 + 26.0 / 60.0 + 21.448 / 3600.0

## The sun's angular radius, in degrees: sixteen arcminutes of the fifty that separate the
## moment its upper limb touches the horizon from the moment its centre does.
const SEMIDIAMETER_DEG := 0.2666

## Refraction at the horizon, in degrees: thirty-four arcminutes, at the standard pressure
## and temperature the formula below assumes.
const REFRACTION_AT_HORIZON_DEG := 0.5667

## The true altitude of the sun's centre when its upper limb first appears - the standard
## convention, and the reason sunrise is not the moment the centre's altitude passes zero.
const SUNRISE_ALTITUDE_DEG := -(SEMIDIAMETER_DEG + REFRACTION_AT_HORIZON_DEG)


# --- the calendar -------------------------------------------------------------------


static func is_leap_year(year: int) -> bool:
	return year % 4 == 0 and (year % 100 != 0 or year % 400 == 0)


static func days_in_year(year: int) -> int:
	return 366 if is_leap_year(year) else 365


## The month and day of a day of the year, as a Vector2i(month, day).
static func month_day_from_day_of_year(day_of_year: int, year: int = EPOCH_YEAR) -> Vector2i:
	var lengths: PackedInt32Array = _month_lengths(year)
	var left: int = clampi(day_of_year, 1, days_in_year(year))
	for month in range(12):
		if left <= lengths[month]:
			return Vector2i(month + 1, left)
		left -= lengths[month]
	return Vector2i(12, 31)


## The day of the year of a month and a day: the inverse of the above, which is what makes
## round-tripping it testable.
static func day_of_year_from_month_day(month: int, day: int, year: int = EPOCH_YEAR) -> int:
	var lengths: PackedInt32Array = _month_lengths(year)
	var safe_month: int = clampi(month, 1, 12)
	var total: int = 0
	for index in range(safe_month - 1):
		total += lengths[index]
	return total + clampi(day, 1, lengths[safe_month - 1])


static func _month_lengths(year: int) -> PackedInt32Array:
	var lengths: PackedInt32Array = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	if is_leap_year(year):
		lengths[1] = 29
	return lengths


## The Julian day of a Gregorian calendar date and an hour UT. (Meeus 7.1.)
##
## The fractional part is the time of day, and a negative or over-24 hour is honest: it is
## how a clock time in one zone becomes an instant in UT without a branch.
static func julian_day(year: int, month: int, day: int, hour_utc: float = 0.0) -> float:
	var y: int = year
	var m: int = month
	if m <= 2:
		y -= 1
		m += 12
	var a: int = int(floor(float(y) / 100.0))
	var b: int = 2 - a + int(floor(float(a) / 4.0))
	return (
		floor(365.25 * float(y + 4716))
		+ floor(30.6001 * float(m + 1))
		+ float(day) + float(b) - 1524.5
		+ hour_utc / 24.0
	)


## The Julian day of a day of the year and an hour UT, in the epoch year.
static func jd_of_day(day_of_year: int, hour_utc: float = 12.0) -> float:
	var month_day: Vector2i = month_day_from_day_of_year(day_of_year)
	return julian_day(EPOCH_YEAR, month_day.x, month_day.y, hour_utc)


## Julian centuries since J2000.0, the argument every expression below is written in.
static func julian_centuries(jd: float) -> float:
	return (jd - 2451545.0) / 36525.0


# --- the sun's position -------------------------------------------------------------


## The sun's geometric mean longitude in degrees. (Meeus 25.2.)
static func mean_longitude(jd: float) -> float:
	var t: float = julian_centuries(jd)
	return fposmod(280.46646 + t * (36000.76983 + t * 0.0003032), 360.0)


## The sun's geometric mean anomaly in degrees. (Meeus 25.3.)
static func mean_anomaly(jd: float) -> float:
	var t: float = julian_centuries(jd)
	return fposmod(357.52911 + t * (35999.05029 - 0.0001537 * t), 360.0)


## The eccentricity of the earth's orbit. (Meeus 25.4.)
static func eccentricity(jd: float) -> float:
	var t: float = julian_centuries(jd)
	return 0.016708634 - t * (0.000042037 + 0.0000001267 * t)


## The equation of the centre: true anomaly less mean anomaly, in degrees. The one term
## that makes the earth's speed vary through the year. (Meeus 25.4.)
static func equation_of_centre(jd: float) -> float:
	var t: float = julian_centuries(jd)
	var m: float = deg_to_rad(mean_anomaly(jd))
	return (
		sin(m) * (1.914602 - t * (0.004817 + 0.000014 * t))
		+ sin(2.0 * m) * (0.019993 - 0.000101 * t)
		+ sin(3.0 * m) * 0.000289
	)


## The sun's apparent longitude in degrees: its true longitude corrected for aberration and
## for the nutation in longitude. (Meeus 25.9.)
static func apparent_longitude(jd: float) -> float:
	var t: float = julian_centuries(jd)
	var true_longitude: float = mean_longitude(jd) + equation_of_centre(jd)
	var omega: float = 125.04 - 1934.136 * t
	return true_longitude - 0.00569 - 0.00478 * sin(deg_to_rad(omega))


## The mean obliquity of the ecliptic in degrees: the earth's tilt, with the drift of the
## centuries in it and none of the wobble. (Meeus 22.2.)
static func mean_obliquity(jd: float) -> float:
	var t: float = julian_centuries(jd)
	return OBLIQUITY_J2000_DEG - (46.8150 * t + 0.00059 * t * t - 0.001813 * t * t * t) / 3600.0


## The true obliquity in degrees: the mean tilt plus the nutation, under ten arcseconds of
## wobble either way. The distinction matters because the sun cannot be further from the
## equator than the *true* tilt, which is what makes the pair testable. (Meeus 22.5.)
static func obliquity(jd: float) -> float:
	var t: float = julian_centuries(jd)
	var omega: float = 125.04 - 1934.136 * t
	return mean_obliquity(jd) + 0.00256 * cos(deg_to_rad(omega))


## The sun's declination in degrees at an instant: how far off the equator it stands, and
## the number the whole of the rest of the year's sun hangs on. (Meeus 25.11.)
static func declination_at(jd: float) -> float:
	var epsilon: float = deg_to_rad(obliquity(jd))
	var longitude: float = deg_to_rad(apparent_longitude(jd))
	return rad_to_deg(asin(clampf(sin(epsilon) * sin(longitude), -1.0, 1.0)))


## The sun's declination in degrees by day of the year, sampled at noon UT.
##
## The sun moves four tenths of a degree a day, so this is the convenience for a caller who
## knows the day but not the place: `position_for`, which knows the longitude, takes the
## declination at the true instant instead.
static func declination(day_of_year: int) -> float:
	return declination_at(jd_of_day(day_of_year, 12.0))


## The equation of time in minutes: apparent solar time less mean solar time, which is the
## difference between a sundial and a clock. Sixteen minutes of it, twice a year, in
## opposite directions. (Meeus 28.3, the expression the NOAA calculator uses.)
static func equation_of_time(jd: float) -> float:
	var e: float = eccentricity(jd)
	var epsilon: float = deg_to_rad(obliquity(jd))
	var l0: float = deg_to_rad(mean_longitude(jd))
	var m: float = deg_to_rad(mean_anomaly(jd))
	var y: float = tan(epsilon / 2.0) * tan(epsilon / 2.0)
	var degrees: float = rad_to_deg(
		y * sin(2.0 * l0)
		- 2.0 * e * sin(m)
		+ 4.0 * e * y * sin(m) * cos(2.0 * l0)
		- 0.5 * y * y * sin(4.0 * l0)
		- 1.25 * e * e * sin(2.0 * m)
	)
	# Four minutes to a degree: the sun's day divided by 360.
	return degrees * 4.0


## The equation of time in minutes on a day of the year, sampled at noon UT. (The function
## of date itself is a truth of the day, not of the instant.)
static func equation_of_time_on(day_of_year: int) -> float:
	return equation_of_time(jd_of_day(day_of_year, 12.0))


## Atmospheric refraction in degrees, for a true altitude in degrees.
##
## Saemundsson's expression, at the standard pressure and temperature it assumes: it lifts
## the sun by half a degree at the horizon, which is the same half degree that gives a
## sunrise early and a sunset late. It stops being meaningful a degree below the horizon,
## where it is dropped rather than extrapolated into a number no one should act on.
static func refraction(true_altitude_deg: float) -> float:
	if true_altitude_deg < -1.0:
		return 0.0
	var arcminutes: float = 1.02 / tan(
		deg_to_rad(true_altitude_deg + 10.3 / (true_altitude_deg + 5.11))
	)
	return arcminutes / 60.0


# --- sites and moments --------------------------------------------------------------


## A site: where the garden is, and what the clock there reads.
static func site(latitude: float, longitude: float = 0.0, utc_offset_hours: float = 0.0) -> Dictionary:
	return {
		"latitude": latitude,
		"longitude": longitude,
		"utc_offset_hours": utc_offset_hours,
	}


## A moment: which day of the year, and the clock hour at the site.
static func moment(day_of_year: int, clock_hour: float, year: int = EPOCH_YEAR) -> Dictionary:
	return {
		"day_of_year": day_of_year,
		"clock_hour": clock_hour,
		"year": year,
	}


## Solar time in hours for a clock time at a site. Apparent solar noon is 12.0.
##
## Four things move a clock's noon off the sun's: the longitude (four minutes a degree,
## east of the zone's meridian the sun is early), the zone offset, and the equation of
## time. This is where all three are paid.
static func solar_time(site_dict: Dictionary, moment_dict: Dictionary) -> float:
	var day: int = int(moment_dict.get("day_of_year", 172))
	var offset: float = float(site_dict.get("utc_offset_hours", 0.0))
	var longitude: float = float(site_dict.get("longitude", 0.0))
	return (
		float(moment_dict.get("clock_hour", 12.0)) - offset
		+ longitude / 15.0
		+ equation_of_time_on(day) / 60.0
	)


## The clock hour at a site for a given solar time: the inverse of `solar_time`, which is
## what turns a sunrise into something a client can read. Wrapped into the day, since a
## sunrise before midnight has to be shown as one.
static func clock_time(site_dict: Dictionary, moment_dict: Dictionary, solar: float) -> float:
	var day: int = int(moment_dict.get("day_of_year", 172))
	var offset: float = float(site_dict.get("utc_offset_hours", 0.0))
	var longitude: float = float(site_dict.get("longitude", 0.0))
	return fposmod(solar + offset - longitude / 15.0 - equation_of_time_on(day) / 60.0, 24.0)


## A time of day as a client reads it: "05:25".
static func clock_text(hours: float) -> String:
	var minutes_total: int = int(round(fposmod(hours, 24.0) * 60.0))
	minutes_total = posmod(minutes_total, 1440)
	var hour: int = int(floor(float(minutes_total) / 60.0))
	return "%02d:%02d" % [hour, minutes_total % 60]


# --- the sun, as seen -----------------------------------------------------------------


## Altitude, azimuth and the sky's own report, from a latitude, a declination and a solar
## hour. The one place the spherical trigonometry is written.
static func _reckon(
	latitude: float, declination_deg: float, solar: float, extra: Dictionary
) -> Dictionary:
	var latitude_rad: float = deg_to_rad(clampf(latitude, -89.9, 89.9))
	var declination_rad: float = deg_to_rad(clampf(declination_deg, -89.9, 89.9))
	# Fifteen degrees an hour, zero at solar noon.
	var hour_angle: float = deg_to_rad((solar - 12.0) * 15.0)
	var sin_altitude: float = (
		sin(latitude_rad) * sin(declination_rad)
		+ cos(latitude_rad) * cos(declination_rad) * cos(hour_angle)
	)
	var altitude: float = rad_to_deg(asin(clampf(sin_altitude, -1.0, 1.0)))
	var azimuth: float = rad_to_deg(atan2(
		sin(hour_angle),
		cos(hour_angle) * sin(latitude_rad) - tan(declination_rad) * cos(latitude_rad)
	)) + 180.0
	var sun: Dictionary = {
		# The centre's geometric altitude: what a shadow is cast by. Refraction is
		# reported beside it rather than folded into it, because refraction is about
		# what the eye sees and a shadow is about where the light actually comes from.
		"altitude_deg": altitude,
		"apparent_altitude_deg": altitude + refraction(altitude),
		"azimuth_deg": fposmod(azimuth, 360.0),
		"declination_deg": declination_deg,
		"solar_hour": solar,
		# A sun is up when it can be seen, which is almost a degree before its centre
		# clears the horizon. Reported, never clamped: whether that becomes a night
		# scene or a refusal is the caller's decision.
		"is_up": altitude > SUNRISE_ALTITUDE_DEG,
	}
	sun.merge(extra, true)
	return sun


## The sun at a **solar** time: the sky's own clock, with no site in it.
##
## This is the sky over the prime meridian, for a caller that has a latitude and a time of
## day and no map - and the solar time a study is either stated in or converted into.
## `position_for` is the one that takes a place.
##
## The third argument is a **solar** hour, not the hour a site's clock reads: the two are
## up to sixteen minutes apart, and the difference is the point of `position_for`.
static func position(latitude: float, day_of_year: int, solar_hour: float) -> Dictionary:
	var jd: float = jd_of_day(day_of_year, solar_hour)
	return _reckon(latitude, declination_at(jd), solar_hour, {
		"day_of_year": day_of_year,
		"equation_of_time_minutes": equation_of_time(jd),
		"year": EPOCH_YEAR,
	})


## The sun for a site at a clock time: the path the presentation and the still's record
## both use, and the one whose answer is good to a hundredth of a degree.
static func position_for(site_dict: Dictionary, moment_dict: Dictionary) -> Dictionary:
	var day: int = int(moment_dict.get("day_of_year", 172))
	var clock: float = float(moment_dict.get("clock_hour", 12.0))
	var latitude: float = float(site_dict.get("latitude", 0.0))
	var longitude: float = float(site_dict.get("longitude", 0.0))
	var offset: float = float(site_dict.get("utc_offset_hours", 0.0))
	# The instant, in UT: the clock time less the zone's offset. The declination is taken
	# there rather than at the day's noon, which is the whole of what a longitude buys.
	var jd: float = jd_of_day(day, clock - offset)
	return _reckon(latitude, declination_at(jd), solar_time(site_dict, moment_dict), {
		"day_of_year": day,
		"clock_hour": clock,
		"latitude_deg": latitude,
		"longitude_deg": longitude,
		"utc_offset_hours": offset,
		"equation_of_time_minutes": equation_of_time(jd),
		"year": int(moment_dict.get("year", EPOCH_YEAR)),
	})


# --- day and night --------------------------------------------------------------------


## Sunrise, sunset and day length in **solar** time, on a latitude and a day.
##
## The hour angle the sun's upper limb stands at, from the standard sunrise altitude: the
## half degree of refraction and the quarter of a degree of the sun's own width are why a
## day at the equinox is a few minutes longer than twelve hours rather than exactly twelve.
static func daylight(latitude: float, day_of_year: int) -> Dictionary:
	var declination_deg: float = declination(day_of_year)
	var latitude_rad: float = deg_to_rad(clampf(latitude, -89.9, 89.9))
	var declination_rad: float = deg_to_rad(declination_deg)
	var cos_hour_angle: float = (
		sin(deg_to_rad(SUNRISE_ALTITUDE_DEG))
		- sin(latitude_rad) * sin(declination_rad)
	) / (cos(latitude_rad) * cos(declination_rad))
	var daylight_hours: Dictionary = {"declination_deg": declination_deg}
	if cos_hour_angle > 1.0:
		# The sun never gets up. There is no sunrise to report, and saying one at the
		# right time is not the same as saying there is not one.
		daylight_hours.merge({
			"polar_day": false, "polar_night": true,
			"sunrise_hour": 0.0, "sunset_hour": 24.0, "day_length_hours": 0.0,
		})
		return daylight_hours
	if cos_hour_angle < -1.0:
		daylight_hours.merge({
			"polar_day": true, "polar_night": false,
			"sunrise_hour": 0.0, "sunset_hour": 24.0, "day_length_hours": 24.0,
		})
		return daylight_hours
	var half_day: float = rad_to_deg(acos(clampf(cos_hour_angle, -1.0, 1.0))) / 15.0
	daylight_hours.merge({
		"polar_day": false,
		"polar_night": false,
		"sunrise_hour": 12.0 - half_day,
		"sunset_hour": 12.0 + half_day,
		"day_length_hours": 2.0 * half_day,
	})
	return daylight_hours


## Sunrise and sunset on the site's own clock, which is what a client reads.
static func daylight_for(site_dict: Dictionary, moment_dict: Dictionary) -> Dictionary:
	var day: int = int(moment_dict.get("day_of_year", 172))
	var hours: Dictionary = daylight(float(site_dict.get("latitude", 0.0)), day)
	hours["sunrise_clock_hour"] = clock_time(site_dict, moment_dict, float(hours["sunrise_hour"]))
	hours["sunset_clock_hour"] = clock_time(site_dict, moment_dict, float(hours["sunset_hour"]))
	return hours


# --- aiming a light -------------------------------------------------------------------


## Aim a DirectionalLight3D at the sun.
##
## Returns false and leaves the light exactly as it was when the sun is down, because a
## light dragged under the ground is a state the caller would then have to notice and
## repair.
static func apply(
	light: DirectionalLight3D, latitude: float, day_of_year: int, solar_hour: float
) -> bool:
	var sun: Dictionary = position(latitude, day_of_year, solar_hour)
	if not bool(sun["is_up"]):
		return false
	return _aim(light, sun)


## Aim a DirectionalLight3D at the sun for a site at a clock time.
static func apply_for(
	light: DirectionalLight3D, site_dict: Dictionary, moment_dict: Dictionary
) -> bool:
	var sun: Dictionary = position_for(site_dict, moment_dict)
	if not bool(sun["is_up"]):
		return false
	return _aim(light, sun)


static func _aim(light: DirectionalLight3D, sun: Dictionary) -> bool:
	var altitude: float = deg_to_rad(float(sun["altitude_deg"]))
	var azimuth: float = deg_to_rad(float(sun["azimuth_deg"]))
	# Model space puts north on -Z (drafting-subsystem-spec §1.2), so the bearing turns
	# from -Z toward +X, and the altitude raises the light along +Y.
	var direction := Vector3(
		sin(azimuth) * cos(altitude),
		sin(altitude),
		-cos(azimuth) * cos(altitude)
	)
	# A DirectionalLight3D looks down its own -Z, so it sits opposite the direction to
	# the sun and is turned to face the origin.
	light.position = direction * DISTANCE_M
	light.look_at(Vector3.ZERO, Vector3.UP)
	return true


# --- saying it in words ---------------------------------------------------------------


## A short description of the sun, for a status line, from a solar time.
static func describe(latitude: float, day_of_year: int, solar_hour: float) -> String:
	var sun: Dictionary = position(latitude, day_of_year, solar_hour)
	if not bool(sun["is_up"]):
		return "the sun is below the horizon at %.1f h" % solar_hour
	return "sun %.0f° up, bearing %.0f°" % [
		float(sun["altitude_deg"]), float(sun["azimuth_deg"]),
	]


## A description of the sun for a site at a clock time, with the day's own sunrise and
## sunset: a shadow study is mostly a question about when, so the answer says when.
static func describe_for(site_dict: Dictionary, moment_dict: Dictionary) -> String:
	var sun: Dictionary = position_for(site_dict, moment_dict)
	var hours: Dictionary = daylight_for(site_dict, moment_dict)
	var latitude: float = float(site_dict.get("latitude", 0.0))
	if bool(hours["polar_day"]):
		return "The sun does not set at %.0f°%s on this day." % [
			absf(latitude), _hemisphere(latitude)
		]
	if bool(hours["polar_night"]):
		return "The sun does not rise at %.0f°%s on this day." % [
			absf(latitude), _hemisphere(latitude)
		]
	var rise: String = clock_text(float(hours["sunrise_clock_hour"]))
	var set_text: String = clock_text(float(hours["sunset_clock_hour"]))
	if not bool(sun["is_up"]):
		return "The sun is below the horizon at %s. Sunset was %s." % [
			clock_text(float(moment_dict.get("clock_hour", 12.0))), set_text
		]
	return "Sun %.0f° up, bearing %.0f°. Sunrise %s, sunset %s." % [
		float(sun["altitude_deg"]), float(sun["azimuth_deg"]), rise, set_text
	]


static func _hemisphere(latitude: float) -> String:
	return "N" if latitude >= 0.0 else "S"