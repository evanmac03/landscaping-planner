class_name SunReport
extends RefCounted
## What a shadow study says: where the sun stands at each moment somebody chose, and what a
## thing of a stated height casts at that moment.
##
## `SunStudy` answers where the sun is. This answers the question a client actually asks -
## "will the fence shade the patio at four, and in June" - which is a *list* of moments and a
## height, and the arithmetic of one shadow: its length is the height over the tangent of the
## sun's altitude, and its bearing is the sun's own bearing turned round.
##
## **The height is stated, not read off the drawing.** An entity on the plan is a shape on the
## ground and carries no height; the 3D yard's models carry one and are not what a fence's
## shadow is cast by. So the study states a height in hand - a fence's 1.8 m - and reports what
## that casts, which is honest, checkable, and the whole of what the astronomy plus the height
## can support. It does not claim to know what is in the shade; nothing here reads the yard.
##
## Two distinctions are kept apart, because collapsing either one produces a number nobody
## should act on:
##
## - **A sun below the horizon casts no shadow at all**, and that is a refusal naming the
##   moment rather than "0 m", which would be a lie: a shadow at a sun on the horizon has no
##   end.
## - **A sun a few degrees up casts a shadow that is arithmetically right and practically
##   meaningless** - at 3° a 1.8 m fence throws 34 m - so the length is stated and a note says
##   it is a grazing one.

const SunStudyScript := preload("res://scripts/vis/sun_study.gd")
const UnitsScript := preload("res://scripts/draft/units.gd")

## The hours a day is usually studied at, on the site's own clock: mid-morning to early
## evening, which is when a garden is used.
const DAY_HOURS: Array[float] = [8.0, 10.0, 12.0, 14.0, 16.0, 18.0]

## The hours the two solstices are compared at, which is the pair a client asks about: the
## highest sun of the year and the lowest.
const SOLSTICE_HOURS: Array[float] = [9.0, 12.0, 15.0]

## The hours an equinox is compared at, which is the pair that says what an ordinary day does.
const EQUINOX_HOURS: Array[float] = [9.0, 12.0, 15.0]

## Day of the year of the two solstices and the two equinoxes, for the epoch year `SunStudy`
## computes in. 172 is 21 June, 355 is 21 December, 80 is 21 March and 264 is 21 September.
const JUNE_SOLSTICE := 172
const DECEMBER_SOLSTICE := 355
const MARCH_EQUINOX := 80
const SEPTEMBER_EQUINOX := 264

## What a study assumes is casting the shadow unless it is told otherwise: a 1.8 m fence, which
## is the thing a client's question is usually about.
const DEFAULT_HEIGHT_M := 1.8

## The lowest sun a shadow length is worth *trusting*, in degrees.
##
## A shadow is the height over the tangent of the altitude, so the number grows without bound
## as the sun goes down: at 5° a 1.8 m fence casts 20.6 m, at 1° it casts 103 m, and at the
## horizon it has no end. The arithmetic is right at every one of those; the *answer* stops
## being one, because the length is then a statement about the hour rather than about the
## garden. Below this the length is still reported - withholding it would be hiding a number
## the study can work out - and a note says which kind of number it is.
const MIN_ALTITUDE_DEG := 5.0

## A shadow is drawn to the opposite bearing from the sun, which is a half turn.
const OPPOSITE_DEG := 180.0

## The sixteen points of the compass, so a shadow's direction is said the way a person says it.
const COMPASS: Array[String] = [
	"N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
	"S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW",
]

## The months, for naming a day of the year the way a client reads it.
const MONTHS: Array[String] = [
	"January", "February", "March", "April", "May", "June",
	"July", "August", "September", "October", "November", "December",
]


# --- the moments a study is made of --------------------------------------------------


## The hours of a study day, as a copy, so a caller cannot sort the table itself.
static func day_hours() -> Array[float]:
	return DAY_HOURS.duplicate()


## One moment on one day: the same shape `SunStudy.position_for` takes.
static func moments_on(day_of_year: int, hours: Array = DAY_HOURS) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for hour: float in hours:
		out.append(SunStudyScript.moment(day_of_year, hour))
	return out


## A moment on each of several days, so a season is a list of days and a day is a list of hours.
##
## The parameter is not called `days`, because this class has a `days()` of its own and a parameter that
## shadowed it would be a warning rather than a compile error - which is how it survives being read.
static func moments_on_days(days_of_year: Array, hours: Array = DAY_HOURS) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for day_of_year in days_of_year:
		out.append_array(moments_on(int(day_of_year), hours))
	return out


## The names of the ready-made studies the page offers, in the order it offers them.
static func preset_names() -> Array[StringName]:
	return [&"june_day", &"december_day", &"equinoxes", &"solstices"]


## A preset's name as a person reads it.
static func preset_name(name: StringName) -> String:
	match name:
		&"june_day":
			return "a June day"
		&"december_day":
			return "a December day"
		&"equinoxes":
			return "the equinoxes"
		&"solstices":
			return "the two solstices"
		_:
			return ""


## The moments a named preset is made of. An empty list for a name nobody has, which is what
## lets the page say so rather than offer an empty study.
##
## Four of them, because they are the four questions a garden gets asked: what the middle of
## summer does across a day, what the middle of winter does, what an ordinary day does twice a
## year, and how the year's tallest sun and its lowest compare at the same hours.
static func preset(name: StringName) -> Array[Dictionary]:
	match name:
		&"june_day":
			return moments_on(JUNE_SOLSTICE, DAY_HOURS)
		&"december_day":
			return moments_on(DECEMBER_SOLSTICE, DAY_HOURS)
		&"equinoxes":
			return moments_on_days([MARCH_EQUINOX, SEPTEMBER_EQUINOX], EQUINOX_HOURS)
		&"solstices":
			return moments_on_days([JUNE_SOLSTICE, DECEMBER_SOLSTICE], SOLSTICE_HOURS)
		_:
			return [] as Array[Dictionary]


# --- naming a day and an hour --------------------------------------------------------


## A day of the year as a person writes it: "21 June".
static func day_words(day_of_year: int) -> String:
	var month_day: Vector2i = SunStudyScript.month_day_from_day_of_year(day_of_year)
	return "%d %s" % [month_day.y, MONTHS[month_day.x - 1]]


## A day of the year short enough for a table: "21 Jun".
static func day_short(day_of_year: int) -> String:
	var month_day: Vector2i = SunStudyScript.month_day_from_day_of_year(day_of_year)
	return "%d %s" % [month_day.y, MONTHS[month_day.x - 1].substr(0, 3)]


## The clock time a moment is at, as a client reads it: "16:00" - or "16:30" for a moment that
## was asked for at half past, which a study of a client's own afternoon has to be able to say.
static func time_text(moment_dict: Dictionary) -> String:
	return SunStudyScript.clock_text(float(moment_dict.get("clock_hour", 12.0)))


## The day of the year a moment is on.
static func day_of(moment_dict: Dictionary) -> int:
	return int(moment_dict.get("day_of_year", JUNE_SOLSTICE))


## A moment as a person writes it: "21 June 16:00". This is the name a study's still is filed
## under, so a folder of them reads as the study does.
static func moment_words(moment_dict: Dictionary) -> String:
	return "%s %s" % [day_words(day_of(moment_dict)), time_text(moment_dict)]


## The file name a still of a moment is written with: the day and the time, not the wall clock
## the render happened to run at, because a study is read in the order of its moments.
static func still_name(moment_dict: Dictionary) -> String:
	var hours: float = float(moment_dict.get("clock_hour", 12.0))
	var hour: int = int(floor(fposmod(hours, 24.0)))
	var minute: int = int(round(fposmod(hours, 1.0) * 60.0))
	if minute == 60:
		hour = (hour + 1) % 24
		minute = 0
	return "sun-study-%03d-%02d%02d" % [day_of(moment_dict), hour, minute]


## The still names for a whole study, in the study's own order.
static func still_names(moments: Array) -> Array[String]:
	var out: Array[String] = []
	for moment_dict: Dictionary in moments:
		out.append(still_name(moment_dict))
	return out


## A bearing as a compass point: "ENE". What a person says instead of 68°, and the reason a
## study's rows are readable without a compass.
static func bearing_words(bearing_deg: float) -> String:
	var index: int = int(round(fposmod(bearing_deg, 360.0) / 22.5)) % COMPASS.size()
	return COMPASS[index]


## A height in the drawing's own units, which is how the height in hand is stated and read.
static func height_words(metres: float, units: DraftUnits = null) -> String:
	return UnitsScript.or_default(units).format_length(metres)


## A site as a person writes it: "45.0°N 75.0°W, UTC-5". The one place the three numbers of a
## study's place are turned into words, so the page, the presentation panel and a saved record
## cannot describe the same site three ways.
static func site_words(site_dict: Dictionary) -> String:
	var latitude: float = float(site_dict.get("latitude", 0.0))
	var longitude: float = float(site_dict.get("longitude", 0.0))
	var offset: float = float(site_dict.get("utc_offset_hours", 0.0))
	# "UTC-5" rather than "UTC-5.0": most of the world's zones are whole hours, and the
	# half-hour ones are the reason this is not simply an integer.
	var offset_words: String = "UTC%+.1f" % offset
	if is_equal_approx(offset, roundf(offset)):
		offset_words = "UTC%+d" % int(roundf(offset))
	return "%.1f°%s %.1f°%s, %s" % [
		absf(latitude), "N" if latitude >= 0.0 else "S",
		absf(longitude), "E" if longitude >= 0.0 else "W",
		offset_words,
	]


# --- one shadow ----------------------------------------------------------------------


## What a thing of a stated height casts at a moment.
##
## Returns `{ok, reason, height_m, length_m, bearing_deg, compass, sun_up, altitude_deg,
## sun_bearing_deg, note, clock_text, day_of_year}`. `ok` is false only when there is no
## shadow at all, and `reason` then says which case it is rather than leaving a length of zero
## to be read as "the sun is straight overhead", which is not what it means. The sun's own
## bearing is reported beside the shadow's, so a row can be checked without doing the half turn
## in one's head.
static func shadow(
	site_dict: Dictionary, moment_dict: Dictionary, height_m: float = DEFAULT_HEIGHT_M
) -> Dictionary:
	var out: Dictionary = {
		"ok": false,
		"reason": "",
		"height_m": height_m,
		"length_m": 0.0,
		"bearing_deg": 0.0,
		"compass": "",
		"sun_up": false,
		"altitude_deg": 0.0,
		"sun_bearing_deg": 0.0,
		"note": "",
		"clock_text": time_text(moment_dict),
		"day_of_year": day_of(moment_dict),
	}
	if not is_finite(height_m):
		out["reason"] = "the height in hand is not a number, so there is nothing to cast a shadow"
		return out
	if height_m <= 0.0:
		out["reason"] = "a height of nothing casts no shadow, so a shadow needs a height to be of"
		return out
	var sun: Dictionary = SunStudyScript.position_for(site_dict, moment_dict)
	var altitude: float = float(sun["altitude_deg"])
	out["sun_up"] = bool(sun["is_up"])
	out["altitude_deg"] = altitude
	out["sun_bearing_deg"] = float(sun["azimuth_deg"])
	if not bool(sun["is_up"]):
		out["reason"] = "the sun is below the horizon at %s" % out["clock_text"]
		return out
	if altitude <= 0.0:
		# The sun can be visible with its centre still under the horizon - half a degree of
		# refraction and the sun's own width - and a shadow cast by a sun on the horizon has no
		# end at all. Dividing by that tangent gives an enormous number that reads as an answer.
		out["reason"] = (
			"the sun's centre is on the horizon at %s, so the shadow has no end" % out["clock_text"]
		)
		return out
	var length: float = height_m / tan(deg_to_rad(altitude))
	out["ok"] = true
	out["length_m"] = length
	out["bearing_deg"] = fposmod(float(sun["azimuth_deg"]) + OPPOSITE_DEG, 360.0)
	out["compass"] = bearing_words(float(out["bearing_deg"]))
	if altitude < MIN_ALTITUDE_DEG:
		out["note"] = (
			"the sun is only %.0f° up, so this length says more about the hour than the garden"
			% altitude
		)
	return out


## A shadow in words: "3.0 m to the ENE" - or the reason there is none, which is a sentence the
## caller can print as it stands.
static func shadow_words(cast: Dictionary, units: DraftUnits = null) -> String:
	if not bool(cast["ok"]):
		return String(cast["reason"])
	return "%s to the %s" % [
		height_words(float(cast["length_m"]), units), String(cast["compass"]),
	]


# --- the study, as rows --------------------------------------------------------------


## One row of the study's table. `text` is the whole row, so a page shows the row the module
## built rather than assembling one of its own out of the fields.
static func row_for(
	site_dict: Dictionary,
	moment_dict: Dictionary,
	height_m: float = DEFAULT_HEIGHT_M,
	units: DraftUnits = null
) -> Dictionary:
	var sun: Dictionary = SunStudyScript.position_for(site_dict, moment_dict)
	var cast: Dictionary = shadow(site_dict, moment_dict, height_m)
	var row: Dictionary = {
		"day_of_year": day_of(moment_dict),
		"day": day_short(day_of(moment_dict)),
		"clock_text": time_text(moment_dict),
		"sun_up": bool(sun["is_up"]),
		"altitude_deg": float(sun["altitude_deg"]),
		"bearing_deg": float(sun["azimuth_deg"]),
		"shadow_m": float(cast["length_m"]),
		"shadow_bearing_deg": float(cast["bearing_deg"]),
		"compass": String(cast["compass"]),
		"shadow_words": shadow_words(cast, units),
		"problem": String(cast["reason"]),
		"note": String(cast["note"]),
		"still_name": still_name(moment_dict),
		"moment": moment_dict,
	}
	row["text"] = _row_text(row, height_m, units)
	return row


static func _row_text(row: Dictionary, height_m: float, units: DraftUnits) -> String:
	var head: String = "%s %s" % [row["day"], row["clock_text"]]
	if not bool(row["sun_up"]):
		return "%s  the sun is below the horizon, so there is no shadow" % head
	var sun: String = "sun %2.0f° up at bearing %3.0f°" % [
		float(row["altitude_deg"]), float(row["bearing_deg"]),
	]
	var cast: String = "%s casts %s" % [height_words(height_m, units), String(row["shadow_words"])]
	var text: String = "%s  %s  %s" % [head, sun, cast]
	if String(row["note"]) != "":
		text += "  (%s)" % String(row["note"])
	return text


## The study's rows, in the order the moments were given.
static func rows(
	site_dict: Dictionary,
	moments: Array,
	height_m: float = DEFAULT_HEIGHT_M,
	units: DraftUnits = null
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for moment_dict: Dictionary in moments:
		out.append(row_for(site_dict, moment_dict, height_m, units))
	return out


## The rows' texts alone, which is what a list control shows.
static func row_texts(
	site_dict: Dictionary,
	moments: Array,
	height_m: float = DEFAULT_HEIGHT_M,
	units: DraftUnits = null
) -> Array[String]:
	var out: Array[String] = []
	for row: Dictionary in rows(site_dict, moments, height_m, units):
		out.append(String(row["text"]))
	return out


# --- the days a study covers ---------------------------------------------------------


## One day of a study: its sunrise and sunset on the site's own clock, and how much light the
## day has. A polar day or a polar night is reported as itself rather than given a time it does
## not have, and how much light is then the whole day or none of it.
static func day_for(site_dict: Dictionary, day_of_year: int) -> Dictionary:
	var hours: Dictionary = SunStudyScript.daylight_for(
		site_dict, SunStudyScript.moment(day_of_year, 12.0)
	)
	var out: Dictionary = {
		"day_of_year": day_of_year,
		"day": day_short(day_of_year),
		"day_text": day_words(day_of_year),
		"polar_day": bool(hours["polar_day"]),
		"polar_night": bool(hours["polar_night"]),
		"sunrise_clock": SunStudyScript.clock_text(float(hours["sunrise_clock_hour"])),
		"sunset_clock": SunStudyScript.clock_text(float(hours["sunset_clock_hour"])),
		"day_length_hours": float(hours["day_length_hours"]),
	}
	out["text"] = _day_text(out)
	return out


static func _day_text(day: Dictionary) -> String:
	if bool(day["polar_day"]):
		return "%s  the sun does not set, so the whole day is daylight" % day["day_text"]
	if bool(day["polar_night"]):
		return "%s  the sun does not rise at all" % day["day_text"]
	return "%s  sunrise %s, sunset %s, %.1f h of daylight" % [
		day["day_text"], day["sunrise_clock"], day["sunset_clock"], float(day["day_length_hours"]),
	]


## The days a study's moments fall on, each day once and in the order it was first asked for.
static func days(site_dict: Dictionary, moments: Array) -> Array[Dictionary]:
	var seen: Array[int] = []
	var out: Array[Dictionary] = []
	for moment_dict: Dictionary in moments:
		var day: int = day_of(moment_dict)
		if seen.has(day):
			continue
		seen.append(day)
		out.append(day_for(site_dict, day))
	return out


## The day rows' texts alone.
static func day_texts(site_dict: Dictionary, moments: Array) -> Array[String]:
	var out: Array[String] = []
	for day: Dictionary in days(site_dict, moments):
		out.append(String(day["text"]))
	return out


# --- what it comes to -----------------------------------------------------------------


## What the study comes to in one sentence: how many moments over how many days, how many of
## them have the sun up, and what the year's own best moment casts.
##
## A study with nothing in it says so rather than reading as a study of zero, and a study whose
## every moment is after dark says that in those words rather than quoting a shadow of nothing.
static func summary(
	site_dict: Dictionary,
	moments: Array,
	height_m: float = DEFAULT_HEIGHT_M,
	units: DraftUnits = null
) -> String:
	if moments.is_empty():
		return "no moments have been chosen, so there is nothing to study"
	var up: int = 0
	var down: int = 0
	var highest_deg: float = -91.0
	var highest_text: String = ""
	var day_count: int = 0
	var days_seen: Array[int] = []
	for moment_dict: Dictionary in moments:
		var sun: Dictionary = SunStudyScript.position_for(site_dict, moment_dict)
		var day: int = day_of(moment_dict)
		if not days_seen.has(day):
			days_seen.append(day)
			day_count += 1
		if bool(sun["is_up"]):
			up += 1
			if float(sun["altitude_deg"]) > highest_deg:
				highest_deg = float(sun["altitude_deg"])
				highest_text = moment_words(moment_dict)
		else:
			down += 1
	var head: String = "%d moment%s over %d day%s: %d with the sun up" % [
		moments.size(), _plural(moments.size()), day_count, _plural(day_count), up,
	]
	if down > 0:
		head += ", %d below the horizon" % down
	if up == 0:
		return (
			"%s. No moment in this study has the sun above the horizon, so it casts nothing."
			% head
		)
	var shortest: float = height_m / tan(deg_to_rad(highest_deg))
	return "%s. The highest sun stands %.0f° at %s, where %s casts %s." % [
		head, highest_deg, highest_text,
		height_words(height_m, units), height_words(shortest, units),
	]


## The study in one line, naming the place, how big it is and what is doing the casting. This
## is the line a status bar shows and the line a saved study is filed under.
static func describe(
	site_dict: Dictionary,
	moments: Array,
	height_m: float = DEFAULT_HEIGHT_M,
	units: DraftUnits = null
) -> String:
	if moments.is_empty():
		return "%s: a shadow study with no moments in it yet" % site_words(site_dict)
	return "%s: %d moment%s, and what %s casts" % [
		site_words(site_dict),
		moments.size(),
		_plural(moments.size()),
		height_words(height_m, units),
	]


static func _plural(count: int) -> String:
	return "" if count == 1 else "s"