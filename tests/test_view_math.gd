extends Node
## Checks the geometry that makes the plan <-> ground flight seamless.
##
## The critical invariant: at the altitude the flight starts from, a perspective
## camera using the matched field of view frames exactly what the orthographic
## plan camera framed. That is what hides the projection swap, so it is worth
## pinning down.

const TOLERANCE := 0.0001


func test_perspective_view_height_matches_definition() -> void:
	# At 10 m with a 90 degree vertical fov the visible height is 2 * 10 * tan(45).
	assert(absf(ViewMath.perspective_view_height(10.0, 90.0) - 20.0) < TOLERANCE)


func test_match_distance_is_inverse_of_view_height() -> void:
	var distance: float = ViewMath.match_distance(26.0, 30.0)
	assert(
		absf(ViewMath.perspective_view_height(distance, 30.0) - 26.0) < TOLERANCE,
		"match_distance must frame exactly the orthographic size"
	)


func test_match_fov_is_inverse_of_view_height() -> void:
	var fov: float = ViewMath.match_fov(26.0, 60.0)
	assert(
		absf(ViewMath.perspective_view_height(60.0, fov) - 26.0) < TOLERANCE,
		"match_fov must frame exactly the orthographic size at that distance"
	)


func test_matched_framing_survives_the_projection_swap() -> void:
	# The invariant the whole flight depends on, checked at the real scene values.
	var ortho_size := 23.0
	var altitude := 60.0
	var fov: float = ViewMath.match_fov(ortho_size, altitude)
	assert(fov > 0.0 and fov < 90.0, "matched fov should be a sane angle")
	assert(
		absf(ViewMath.perspective_view_height(altitude, fov) - ortho_size) < TOLERANCE,
		"plan framing must be identical before and after the projection swap"
	)


func test_match_fov_stays_narrow_so_the_swap_is_invisible() -> void:
	# A narrow angle high up is what makes perspective and orthographic agree. A
	# wide one would betray the swap with visible perspective distortion.
	assert(ViewMath.match_fov(23.0, 60.0) < 35.0)


func test_clamp_to_rect_keeps_points_inside() -> void:
	var rect := Rect2(-1.0, -2.0, 4.0, 8.0)
	assert(ViewMath.clamp_to_rect(Vector2(99.0, 99.0), rect) == Vector2(3.0, 6.0))
	assert(ViewMath.clamp_to_rect(Vector2(-99.0, -99.0), rect) == Vector2(-1.0, -2.0))
	assert(ViewMath.clamp_to_rect(Vector2(0.0, 0.0), rect) == Vector2(0.0, 0.0))


func test_wrap_angle_folds_full_turns() -> void:
	assert(absf(ViewMath.wrap_angle(TAU * 3.0 + 0.5) - 0.5) < TOLERANCE)
	assert(absf(ViewMath.wrap_angle(-TAU * 2.0 - 0.25) + 0.25) < TOLERANCE)


func test_wrap_angle_is_bounded() -> void:
	assert(absf(ViewMath.wrap_angle(TAU * 17.0)) < TOLERANCE)


func test_pixels_per_metre_uses_the_viewport_height() -> void:
	# An orthographic size of 23 m spread over 900 px is 900/23 px per metre.
	assert(absf(ViewMath.pixels_per_metre(900.0, 23.0) - 900.0 / 23.0) < TOLERANCE)


func test_pixels_per_metre_guards_against_zero_size() -> void:
	assert(ViewMath.pixels_per_metre(900.0, 0.0) == 0.0)
	assert(ViewMath.pixels_per_metre(900.0, -5.0) == 0.0)
