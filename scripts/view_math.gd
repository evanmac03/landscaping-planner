class_name ViewMath
## Pure geometry helpers for the plan <-> ground camera flight.
##
## The app keeps a single 3D world and represents the "2D" plan view with an
## orthographic camera looking straight down. Because a perspective camera high
## up with a narrow field of view frames almost exactly what an orthographic
## camera frames, the camera can change projection mid-flight without the change
## being visible. These helpers compute the poses at which the two agree.
##
## A perspective camera at `distance` with vertical field of view `fov_deg`
## shows a vertical slice of world `2 * distance * tan(fov_deg / 2)` tall.

## Vertical extent of world a perspective camera sees at a given distance.
static func perspective_view_height(distance: float, fov_deg: float) -> float:
	return 2.0 * distance * tan(deg_to_rad(fov_deg) * 0.5)


## Distance a perspective camera must sit from its subject to frame a vertical
## slice equal to `ortho_size` -- the frame of an orthographic camera.
static func match_distance(ortho_size: float, fov_deg: float) -> float:
	var half_tan := tan(deg_to_rad(fov_deg) * 0.5)
	if half_tan <= 0.0:
		return 0.0
	return ortho_size / (2.0 * half_tan)


## Vertical field of view a perspective camera at `distance` needs so that it
## frames exactly what an orthographic camera of `ortho_size` frames. Evaluated
## at the instant of the projection swap, so the swap is invisible.
static func match_fov(ortho_size: float, distance: float) -> float:
	if distance <= 0.0:
		return 0.0
	return rad_to_deg(2.0 * atan(ortho_size / (2.0 * distance)))


## Clamp a point (world XZ, stored as a Vector2) inside a rectangle.
static func clamp_to_rect(point: Vector2, rect: Rect2) -> Vector2:
	return Vector2(
		clampf(point.x, rect.position.x, rect.end.x),
		clampf(point.y, rect.position.y, rect.end.y)
	)


## Wrap an angle into (-PI, PI].
static func wrap_angle(angle: float) -> float:
	return wrapf(angle, -PI, PI)


## Interpolate between two angles the short way round.
static func lerp_angle_shortest(from: float, to: float, weight: float) -> float:
	return from + wrap_angle(to - from) * weight


## How many metres a 5 m scale bar should be drawn at, given the plan camera's
## orthographic size and the viewport height in pixels.
static func pixels_per_metre(viewport_height: float, ortho_size: float) -> float:
	if ortho_size <= 0.0:
		return 0.0
	return viewport_height / ortho_size


## The zoom multiplier a pinch asks for, from how far apart the fingers moved.
##
## The view's zoom is the *width of the plan it shows*, so spreading the fingers has to shrink that
## number: the multiplier is the reciprocal of the spread. A spread reported as nothing multiplies by
## one, because two fingers that have not moved are not a zoom, and dividing by their stillness would
## be an infinite one.
static func zoom_factor_for_spread(spread: float) -> float:
	if spread <= 0.0:
		return 1.0
	return 1.0 / spread


## Where the view's focus goes when the design is dragged `delta` screen pixels: the ground under the
## finger - or the cursor - stays where it is, so the focus moves the opposite way to the drag, by one
## screen pixel's worth of metres at this zoom.
static func focus_after_screen_drag(
	focus: Vector2, delta: Vector2, plan_size: float, viewport_height: float
) -> Vector2:
	return focus - delta * (plan_size / maxf(viewport_height, 1.0))
