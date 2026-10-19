extends Node
## Tests for survey import: bearings, metes-and-bounds closure, the similarity
## alignment, and the validation checks that make an import trustworthy.

const Survey := preload("res://scripts/draft/survey.gd")
const Units := preload("res://scripts/draft/units.gd")
const Geom := preload("res://scripts/draft/geom2d.gd")

const FOOT := 0.3048


func _rectangle_lot() -> Array:
	# A 50.00 ft x 120.00 ft lot, walked from the south-west corner.
	var width := 50.0 * FOOT
	var depth := 120.0 * FOOT
	return [
		{"azimuth": 90.0, "distance": width},    # frontage, due east
		{"azimuth": 0.0, "distance": depth},     # side, due north
		{"azimuth": 270.0, "distance": width},   # rear
		{"azimuth": 180.0, "distance": depth},   # side back to start
	]


# --- bearings -----------------------------------------------------------------------


func test_bearings_parse_from_several_notations() -> void:
	var expected := 45.0 + 30.0 / 60.0 + 15.0 / 3600.0
	assert(is_equal_approx(Survey.parse_bearing("N 45°30'15\" E"), expected))
	assert(is_equal_approx(Survey.parse_bearing("N45-30-15E"), expected))
	assert(is_equal_approx(Survey.parse_bearing("N 45 30 15 E"), expected))
	assert(is_equal_approx(Survey.parse_bearing("n 45 30 15 e"), expected))


func test_all_four_quadrants() -> void:
	assert(is_equal_approx(Survey.parse_bearing("N 45°0'0\" E"), 45.0))
	assert(is_equal_approx(Survey.parse_bearing("S 45°0'0\" E"), 135.0))
	assert(is_equal_approx(Survey.parse_bearing("S 45°0'0\" W"), 225.0))
	assert(is_equal_approx(Survey.parse_bearing("N 45°0'0\" W"), 315.0))
	# Cardinal cases must be exact, not merely close.
	assert(is_equal_approx(Survey.parse_bearing("N 0°0'0\" E"), 0.0))
	assert(is_equal_approx(Survey.parse_bearing("N 90°0'0\" E"), 90.0))


func test_a_plain_azimuth_is_accepted() -> void:
	assert(is_equal_approx(Survey.parse_bearing("135"), 135.0))
	assert(is_equal_approx(Survey.parse_bearing("95.5"), 95.5))


func test_unreadable_bearings_are_nan_not_north() -> void:
	assert(is_nan(Survey.parse_bearing("")))
	assert(is_nan(Survey.parse_bearing("north-ish")))
	# A quadrant letter with no angle is a failure, not due north.
	assert(is_nan(Survey.parse_bearing("N  E")))


func test_bearing_formatting_round_trips() -> void:
	var text := Survey.azimuth_to_bearing(45.5)
	assert(text.begins_with("N "))
	assert(text.ends_with(" E"))
	var parsed := Survey.parse_bearing(text)
	assert(is_equal_approx(snappedf(parsed, 0.0001), 45.5))

	# A due east bearing reads as N 90 E, and due north as N 0 E.
	assert(Survey.azimuth_to_bearing(90.0).begins_with("N 90"))
	assert(Survey.azimuth_to_bearing(180.0).begins_with("S 0"))


func test_a_leg_converts_feet_to_metres() -> void:
	var entry: Dictionary = Survey.leg("N 90°0'0\" E", 50.0)
	assert(is_equal_approx(entry["azimuth"], 90.0))
	assert(is_equal_approx(entry["distance"], 15.24))


# --- traverse and closure -----------------------------------------------------------


func test_a_rectangular_lot_closes_and_measures_correctly() -> void:
	var result := Survey.traverse(_rectangle_lot())
	assert(result["closed"])
	assert(is_equal_approx(snappedf(result["misclosure"], 0.000001), 0.0))
	assert(is_equal_approx(snappedf(result["perimeter"], 0.001), 103.632))
	# 6000 sq ft, which is the verified 557.4182 m2.
	assert(is_equal_approx(snappedf(result["area_m2"], 0.0001), 557.4182))


func test_model_space_puts_north_negative_z() -> void:
	var result := Survey.traverse(_rectangle_lot())
	var points: PackedVector2Array = result["points"]
	# Walking east then north: x grows first, then z goes negative.
	assert(is_equal_approx(points[1].x, 15.24))
	assert(is_equal_approx(snappedf(points[1].y, 0.0001), 0.0))
	assert(is_equal_approx(snappedf(points[2].y, 0.001), -36.576))


func test_a_loose_traverse_reports_its_misclosure() -> void:
	var legs := [
		{"azimuth": 0.0, "distance": 10.0},
		{"azimuth": 120.0, "distance": 10.0},
		{"azimuth": 240.0, "distance": 10.5},
	]
	var result := Survey.traverse(legs)
	assert(not result["closed"])
	assert(is_equal_approx(snappedf(result["misclosure"], 0.0001), 0.5))
	# The check reports it rather than tidying it away.
	var record := Survey.check_closure(result)
	assert(record["status"] == "warn")
	assert(String(record["message"]).contains("closure ratio"))


func test_an_exact_traverse_passes_the_closure_check() -> void:
	var record := Survey.check_closure(Survey.traverse(_rectangle_lot()))
	assert(record["status"] == "pass")
	assert(record["message"] == "closed exactly")


func test_bowditch_removes_the_misclosure() -> void:
	var legs := [
		{"azimuth": 0.0, "distance": 10.0},
		{"azimuth": 120.0, "distance": 10.0},
		{"azimuth": 240.0, "distance": 10.5},
	]
	var before := Survey.traverse(legs)
	var adjusted := Survey.bowditch_adjust(legs, before["east"], before["north"])
	var after := Survey.traverse(adjusted)
	assert(after["misclosure"] < 0.0001)
	# The raw traverse is preserved on the record, since adjusting a survey is a
	# professional decision (REQ 6.5.2), and each leg remembers what it was.
	for entry in adjusted:
		assert(entry["adjusted"])
		assert(entry.has("was_distance"))


func test_area_cross_check() -> void:
	var computed: float = Survey.traverse(_rectangle_lot())["area_m2"]
	assert(Survey.check_area(computed, computed)["status"] == "pass")
	# The same 6000 sq ft stated in square metres.
	assert(Survey.check_area(computed, 6000.0 * FOOT * FOOT)["status"] == "pass")
	# A 7 percent disagreement must be flagged.
	assert(Survey.check_area(computed, computed * 1.07)["status"] == "warn")
	# With nothing stated there is nothing to disagree with.
	assert(Survey.check_area(computed, 0.0)["status"] == "pass")


# --- alignment ----------------------------------------------------------------------


func _known_transform(point: Vector2, scale: float, angle: float, offset: Vector2) -> Vector2:
	return Vector2(
		offset.x + scale * (cos(angle) * point.x - sin(angle) * point.y),
		offset.y + scale * (sin(angle) * point.x + cos(angle) * point.y)
	)


func test_similarity_fit_recovers_a_known_scale_and_rotation() -> void:
	var source := PackedVector2Array([
		Vector2(100.0, 100.0), Vector2(700.0, 100.0), Vector2(700.0, 500.0)])
	var target := PackedVector2Array()
	for point: Vector2 in source:
		target.append(_known_transform(point, 0.024, deg_to_rad(30.0), Vector2(-5.0, 12.0)))

	var fit := Survey.similarity_fit(source, target)
	assert(fit["ok"])
	assert(is_equal_approx(snappedf(fit["scale"], 0.000001), 0.024))
	assert(is_equal_approx(snappedf(fit["rotation_deg"], 0.0001), 30.0))
	assert(fit["rms"] < 0.00001)
	assert(Survey.check_alignment(fit)["status"] == "pass")


func test_the_fit_maps_source_points_onto_their_targets() -> void:
	var source := PackedVector2Array([Vector2(0, 0), Vector2(400, 0), Vector2(400, 300)])
	var target := PackedVector2Array()
	for point: Vector2 in source:
		target.append(_known_transform(point, 0.05, deg_to_rad(-12.0), Vector2(3.0, -7.0)))
	var fit := Survey.similarity_fit(source, target)
	for index in source.size():
		assert(Survey.apply_fit(fit, source[index]).distance_to(target[index]) < 0.0001)


func test_two_points_are_enough() -> void:
	var source := PackedVector2Array([Vector2(0, 0), Vector2(100, 0)])
	var target := PackedVector2Array([Vector2(0, 0), Vector2(0, 5)])
	var fit := Survey.similarity_fit(source, target)
	assert(fit["ok"])
	assert(is_equal_approx(snappedf(fit["scale"], 0.000001), 0.05))
	assert(is_equal_approx(snappedf(fit["rotation_deg"], 0.0001), 90.0))


func test_a_sheared_source_is_reported_not_absorbed() -> void:
	# A similarity cannot reduce this, which is exactly the signal that the source
	# is distorted rather than merely imprecise (REQ 6.4.5).
	var source := PackedVector2Array([
		Vector2(100.0, 100.0), Vector2(700.0, 100.0), Vector2(700.0, 500.0)])
	var target := PackedVector2Array()
	for point: Vector2 in source:
		target.append(_known_transform(point, 0.024, deg_to_rad(30.0), Vector2(-5.0, 12.0)))
	target[1] += Vector2(0.0, 0.8)
	target[2] += Vector2(0.0, 0.8)

	var fit := Survey.similarity_fit(source, target)
	assert(fit["ok"])
	assert(fit["rms"] > 0.15)
	var record := Survey.check_alignment(fit)
	assert(record["status"] != "pass")
	assert(record["value"] > Survey.RESIDUAL_TOLERANCE_M)


func test_a_fit_needs_two_correspondences() -> void:
	var fit := Survey.similarity_fit(PackedVector2Array([Vector2.ZERO]), PackedVector2Array([Vector2.ZERO]))
	assert(not fit["ok"])
	assert(Survey.check_alignment(fit)["status"] == "fail")


func test_coincident_source_points_cannot_be_fitted() -> void:
	var source := PackedVector2Array([Vector2(5, 5), Vector2(5, 5)])
	var target := PackedVector2Array([Vector2(0, 0), Vector2(1, 1)])
	assert(not Survey.similarity_fit(source, target)["ok"])


# --- remaining checks ---------------------------------------------------------------


func test_a_self_intersecting_parcel_blocks() -> void:
	var bow_tie := PackedVector2Array([
		Vector2(0, 0), Vector2(10, 10), Vector2(10, 0), Vector2(0, 10)])
	assert(Survey.check_simple(bow_tie)["status"] == "fail")
	var square := PackedVector2Array([
		Vector2(0, 0), Vector2(10, 0), Vector2(10, 10), Vector2(0, 10)])
	assert(Survey.check_simple(square)["status"] == "pass")


func test_an_implausible_extent_is_flagged() -> void:
	assert(Survey.check_extent(Rect2(0, 0, 20, 15))["status"] == "pass")
	assert(Survey.check_extent(Rect2(0, 0, 1, 1))["status"] == "warn")
	assert(Survey.check_extent(Rect2(0, 0, 5000, 5000))["status"] == "warn")


func test_the_report_blocks_on_a_failure() -> void:
	var clean := Survey.summarise([
		Survey.check_closure(Survey.traverse(_rectangle_lot())),
		Survey.check_area(557.4182, 557.4182),
	])
	assert(clean["passed"])
	assert(clean["failures"] == 0)
	assert(clean["records"].size() == 2)

	var blocked := Survey.summarise([
		Survey.check_simple(PackedVector2Array([
			Vector2(0, 0), Vector2(10, 10), Vector2(10, 0), Vector2(0, 10)])),
	])
	assert(not blocked["passed"])
	assert(blocked["failures"] == 1)


func test_warnings_do_not_block() -> void:
	var report := Survey.summarise([
		Survey.check_area(600.0, 557.4182),
	])
	assert(report["passed"])
	assert(report["warnings"] == 1)
	assert(report["failures"] == 0)