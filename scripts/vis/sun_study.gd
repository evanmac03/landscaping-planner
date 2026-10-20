class_name SunStudy
extends RefCounted
## Where the sun is, from a date, a time and a latitude.
##
## Deliberately approximate. A garden is designed at 10 a.m. or 4 p.m. or "when
## the client gets home", not at an azimuth to three decimal places. What matters
## is that the same input always gives the same sun, so two renders of one moment
## can be compared - and that the answer is honest when the sun is down, so a
## caller has to decide what a night scene means rather than being handed a
## negative altitude that quietly lights the garden from below.

## Where the light sits from. Far enough that its shadow map covers the yard, near
## enough that it stays a direction rather than becoming a lamp.
const DISTANCE_M := 40.0


## Solar declination in degrees, by day of year. A cosine approximation, good to
## about a degree, which is well inside the accuracy of the question being asked.
static func declination(day_of_year: int) -> float:
	return -23.44 * cos(TAU * (float(day_of_year) + 10.0) / 365.0)


## Sun altitude and azimuth in degrees, from a latitude and a solar time.
##
## The azimuth is measured clockwise from north, matching the plan's north-up
## convention (drafting-subsystem-spec §1.2), so a shadow in the 3D view falls the
## same way the north arrow on the sheet says it does.
static func position(latitude: float, day_of_year: int, hour: float) -> Dictionary:
	var declination_rad: float = deg_to_rad(declination(day_of_year))
	var latitude_rad: float = deg_to_rad(clampf(latitude, -89.9, 89.9))
	# Hour angle: fifteen degrees an hour, zero at solar noon.
	var hour_angle: float = deg_to_rad((hour - 12.0) * 15.0)
	var sin_altitude: float = (
		sin(latitude_rad) * sin(declination_rad)
		+ cos(latitude_rad) * cos(declination_rad) * cos(hour_angle)
	)
	var altitude: float = rad_to_deg(asin(clampf(sin_altitude, -1.0, 1.0)))
	var azimuth: float = rad_to_deg(atan2(
		sin(hour_angle),
		cos(hour_angle) * sin(latitude_rad) - tan(declination_rad) * cos(latitude_rad)
	)) + 180.0
	return {
		"altitude_deg": altitude,
		"azimuth_deg": fposmod(azimuth, 360.0),
		# Reported, never clamped: whether that becomes a night scene, a twilight
		# scene or a refusal is the caller's decision.
		"is_up": altitude > 0.0,
	}


## Aim a DirectionalLight3D at the sun's position.
##
## Returns false and leaves the light exactly as it was when the sun is down,
## because a light dragged under the ground is a state the caller would then have
## to notice and repair.
static func apply(
	light: DirectionalLight3D, latitude: float, day_of_year: int, hour: float
) -> bool:
	var sun: Dictionary = position(latitude, day_of_year, hour)
	if not bool(sun["is_up"]):
		return false
	var altitude: float = deg_to_rad(float(sun["altitude_deg"]))
	var azimuth: float = deg_to_rad(float(sun["azimuth_deg"]))
	# Model space puts north on -Z (drafting-subsystem-spec §1.2), so the bearing
	# turns from -Z toward +X, and the altitude raises the light along +Y.
	var direction := Vector3(
		sin(azimuth) * cos(altitude),
		sin(altitude),
		-cos(azimuth) * cos(altitude)
	)
	# A DirectionalLight3D looks down its own -Z, so it sits opposite the direction
	# to the sun and is turned to face the origin.
	light.position = direction * DISTANCE_M
	light.look_at(Vector3.ZERO, Vector3.UP)
	return true


## A short description of the sun, for a status line.
static func describe(latitude: float, day_of_year: int, hour: float) -> String:
	var sun: Dictionary = position(latitude, day_of_year, hour)
	if not bool(sun["is_up"]):
		return "the sun is below the horizon at %.1f h" % hour
	return "sun %.0f° up, bearing %.0f°" % [
		float(sun["altitude_deg"]), float(sun["azimuth_deg"]),
	]