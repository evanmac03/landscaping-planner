extends Node
## Tests for the LandXML reader: the coordinate order, the closure a parcel *states*, the curve that
## arrives as the bulge of the line it is part of, the point database a line may point into, and the
## refusals.
##
## The reader is a pure static module, so every test is hand-written text in and a table out - no
## scene, no document, no file - except the two that are about `of_file`, which use a temporary file
## under `user://` because that is the only way to test reading one.

const LandXml := preload("res://scripts/draft/landxml_file.gd")
const Dxf := preload("res://scripts/draft/dxf_file.gd")
const LayerSet := preload("res://scripts/draft/layer_set.gd")

## The keys every reader in this program fills, whichever format it read: the table
## `DraftController._entity_from_shape` draws from. A reader may add its own words beside them - the
## DXF reader names the layer a shape came from, this one and the OSM reader name the *feature* - but
## these are what makes a shape a shape.
const SHARED: Array[String] = [
	"kind", "layer", "points", "bulges", "closed", "words", "height", "arc", "radius",
]

## A plat with a parcel of four corners, an alignment with a quarter-turn curve in it, a fence written
## as a point list with elevations, and a surface this reader does not follow.
##
## The numbers are chosen so that a *swap* of the coordinate pair cannot be mistaken for the truth:
## every northing is in the 1000s and every easting in the 3000s, an order of magnitude apart.
func _plat(units: String = "<Metric linearUnit=\"meter\"/>", extra: String = "") -> String:
	var lines: Array[String] = [
		"<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
		"<LandXML xmlns=\"http://www.landxml.org/schema/LandXML-1.2\" version=\"1.2\">",
		"  <Units>" + units + "</Units>",
		"  <CgPoints>",
		"    <CgPoint name=\"BND1\">1000.0 3000.0</CgPoint>",
		"    <CgPoint name=\"BND2\">1000.0 3060.0</CgPoint>",
		"    <CgPoint name=\"BND3\">1060.0 3060.0</CgPoint>",
		"    <CgPoint name=\"BND4\">1060.0 3000.0</CgPoint>",
		"  </CgPoints>",
		"  <Parcels>",
		"    <Parcel name=\"LOT 12\" area=\"3600.0\">",
		"      <CoordGeom>",
		"        <Line><Start pntRef=\"BND1\"/><End pntRef=\"BND2\"/></Line>",
		"        <Line><Start pntRef=\"BND2\"/><End pntRef=\"BND3\"/></Line>",
		"        <Line><Start pntRef=\"BND3\"/><End pntRef=\"BND4\"/></Line>",
		"        <Line><Start pntRef=\"BND4\"/><End pntRef=\"BND1\"/></Line>",
		"      </CoordGeom>",
		"    </Parcel>",
		"  </Parcels>",
		"  <Alignments>",
		"    <Alignment name=\"DRIVEWAY\">",
		"      <CoordGeom>",
		"        <Line><Start>1030.0 3050.0</Start><End>1030.0 3010.0</End></Line>",
		extra,
		"        <Line><Start>1040.0 3000.0</Start><End>1090.0 3000.0</End></Line>",
		"      </CoordGeom>",
		"    </Alignment>",
		"  </Alignments>",
		"  <PlanFeatures>",
		"    <PlanFeature name=\"FENCE\">",
		"      <CoordGeom>",
		"        <IrregularLine><PntList3D>1010.0 3000.0 12.5 1010.0 3010.0 12.6 1020.0 3010.0 12.7</PntList3D></IrregularLine>",
		"      </CoordGeom>",
		"    </PlanFeature>",
		"  </PlanFeatures>",
		"  <Surfaces>",
		"    <Surface name=\"EXISTING\"><Definition surfType=\"TIN\"><Pnts name=\"NEZ\">1000.0 3000.0 12.0</Pnts></Definition></Surface>",
		"  </Surfaces>",
		"</LandXML>",
	]
	return "\n".join(PackedStringArray(lines))


## The quarter turn the alignment's curve is, written the way a file writes one: from a point due west
## of the centre, round to a point due south of it.
func _curve(rot: String = "ccw", start: String = "<Start>1030.0 3010.0</Start>",
		centre: String = "<Center>1040.0 3010.0</Center>",
		finish: String = "<End>1040.0 3000.0</End>") -> String:
	return "        <Curve rot=\"%s\">%s%s%s</Curve>" % [rot, start, centre, finish]


## The shape of a named feature, or an empty dictionary.
func _feature(plan: Dictionary, wording: String) -> Dictionary:
	for shape: Dictionary in (plan["shapes"] as Array):
		if String(shape["feature"]) == wording:
			return shape
	return {}


func _read(extra: String = "", options: Dictionary = {}) -> Dictionary:
	return LandXml.read_text(_plat("<Metric linearUnit=\"meter\"/>", extra), options)


# --- the table it fills ------------------------------------------------------------------


func test_a_plat_reads_into_the_same_shape_table_the_other_readers_fill() -> void:
	var plan: Dictionary = _read(_curve())
	assert(bool(plan["ok"]), String(plan["reason"]))
	assert((plan["shapes"] as Array).size() == 3, "a parcel, an alignment and a fence: %d" % (plan["shapes"] as Array).size())
	for shape: Dictionary in (plan["shapes"] as Array):
		for key: String in SHARED:
			assert(shape.has(key), "a shape carries %s, whichever reader made it" % key)
		assert(String(shape["kind"]) == "LWPOLYLINE", String(shape["kind"]))
	assert(String(LandXml.describe(plan)) == "3 shapes in metres", LandXml.describe(plan))
	assert(LandXml.is_usable(plan))
	# And the keys a refused plan has are the keys it would have had: a caller may read either.
	var refused: Dictionary = LandXml.refused("nothing")
	assert(not bool(refused["ok"]))
	for key: String in plan.keys():
		assert(refused.has(key), "a refused plan still carries %s" % key)


func test_northing_comes_first_so_the_pair_is_swapped_and_not_only_reflected() -> void:
	var plan: Dictionary = _read(_curve())
	# BND1 is northing 1000, easting 3000. East is +X and north is -Y, so the model holds it 3000 m
	# east and 1000 m south. A reader that took the pair as (x, y) would put it 1000 m east.
	var parcel: Dictionary = _feature(plan, "parcel")
	var points: PackedVector2Array = parcel["points"]
	assert(points.size() == 4, "four corners: %d" % points.size())
	assert(points[0].is_equal_approx(Vector2(3000.0, -1000.0)),
		"the first corner is east 3000, south 1000: %s" % str(points[0]))
	assert(points[2].is_equal_approx(Vector2(3060.0, -1060.0)), str(points[2]))
	# The extent says it too: the lot is 60 m of easting and 60 m of northing, and the y-span is the
	# northing. Nothing about a square lot can tell a swap apart, which is why the *absolute* corner is
	# asserted above and the span is only the second claim.
	var west := 1.0e9
	var east := -1.0e9
	var north := 1.0e9
	var south := -1.0e9
	for point: Vector2 in points:
		west = minf(west, point.x)
		east = maxf(east, point.x)
		north = minf(north, point.y)
		south = maxf(south, point.y)
	assert(is_equal_approx(east - west, 60.0), "60 m of easting: %.3f" % (east - west))
	assert(is_equal_approx(south - north, 60.0), "60 m of northing: %.3f" % (south - north))


func test_a_parcel_is_a_ring_because_a_parcel_is_a_parcel() -> void:
	var plan: Dictionary = _read(_curve())
	var parcel: Dictionary = _feature(plan, "parcel")
	# The file never repeats its first point - the parcel closes because its fourth line ends where its
	# first began - and the closure is stated by the *container*, not inferred from the geometry.
	assert(bool(parcel["closed"]), "a parcel is a ring")
	assert((parcel["points"] as PackedVector2Array).size() == 4, "and the repeated corner is not a corner")
	var fence: Dictionary = _feature(plan, "plan feature")
	assert(not bool(fence["closed"]), "a plan feature is a line until something closes it")


func test_a_parcel_with_no_closing_line_is_still_a_ring() -> void:
	# The file states three lines and stops one corner short of where it began. A parcel is a ring by
	# the format's own definition, so the four corners are the ring and the closure is the container's
	# word rather than the geometry's - the opposite of how the OSM reader has to infer one.
	var text := _plat("<Metric linearUnit=\"meter\"/>", _curve())
	text = text.replace(
		"        <Line><Start pntRef=\"BND4\"/><End pntRef=\"BND1\"/></Line>\n", ""
	)
	var plan: Dictionary = LandXml.read_text(text)
	var parcel: Dictionary = _feature(plan, "parcel")
	assert((parcel["points"] as PackedVector2Array).size() == 4,
		"the corners the file did state: %d" % (parcel["points"] as PackedVector2Array).size())
	assert(bool(parcel["closed"]), "and it is still a ring")
	assert((parcel["bulges"] as PackedFloat64Array).size() == 4, "one bulge per point")


# --- the curve ---------------------------------------------------------------------------


func test_a_curve_arrives_as_the_bulge_of_the_line_it_is_part_of() -> void:
	var plan: Dictionary = _read(_curve("ccw"))
	var drive: Dictionary = _feature(plan, "alignment")
	# One shape, not one shape per element: an alignment is one thing a person selects.
	assert((drive["points"] as PackedVector2Array).size() == 4,
		"three elements, one line: %d points" % (drive["points"] as PackedVector2Array).size())
	var bulges: PackedFloat64Array = drive["bulges"]
	assert(bulges.size() == 4, "one bulge per point, which is what the table's bulges are")
	assert(is_zero_approx(bulges[0]) and is_zero_approx(bulges[2]), "the straight parts are straight")
	# A quarter turn, counterclockwise in the file's own north-up frame, negated by the reflection that
	# makes north -Y - exactly as a DXF bulge is negated for the same reason. The tolerance is loose
	# because the sweep is computed from points the model holds as float32: the value is right to a
	# micron of arc, and the geometry is asserted exactly below.
	var expected := -tan(PI / 4.0 * 0.5)
	assert(absf(bulges[1] - expected) < 1.0e-6,
		"a quarter turn is %.6f and the shape says %.6f" % [expected, bulges[1]])
	# And the arc it describes is the arc the file described: its own midpoint is one radius from the
	# centre the file named. This is the measurement the point count cannot make.
	var start := (drive["points"] as PackedVector2Array)[1]
	var finish := (drive["points"] as PackedVector2Array)[2]
	var centre := Vector2(3010.0, -1040.0)
	var chord := start.distance_to(finish)
	var middle := (start + finish) * 0.5
	var away := (middle - centre).normalized()
	var arc_middle := middle + away * (chord * 0.5 * absf(bulges[1]))
	# A thousandth of a metre, because the model holds its points as float32 and this is a 10 m radius:
	# the claim is that the arc is the circle, not that the arithmetic is exact.
	assert(absf(arc_middle.distance_to(centre) - 10.0) < 1.0e-3,
		"the arc's own midpoint is the radius from the centre: %.6f" % arc_middle.distance_to(centre))
	assert(absf(start.distance_to(centre) - 10.0) < 1.0e-3, "and so is its start")


func test_a_curve_the_other_way_round_turns_the_other_way() -> void:
	var plan: Dictionary = _read(_curve("cw"))
	var bulges: PackedFloat64Array = _feature(plan, "alignment")["bulges"]
	# The same start and end, the other way round: clockwise in a north-up file is the other sign in
	# this one, and it is the *long* way round rather than the short one, because `rot` is the file's
	# answer to which of the two arcs between two points it means. A bulge past 1 is a major arc.
	assert(bulges[1] > 0.0, "clockwise in a north-up file is the other sign here: %.6f" % bulges[1])
	assert(absf(bulges[1]) > 1.0, "and the far side of the circle: %.6f" % bulges[1])
	var far := tan(deg_to_rad(135.0) / 2.0)
	assert(absf(bulges[1] - far) < 1.0e-6,
		"a 270 degree turn is %.6f and the shape says %.6f" % [far, bulges[1]])
	var other: PackedFloat64Array = _feature(_read(_curve("ccw")), "alignment")["bulges"]
	assert(absf(other[1]) < 1.0, "the other way is the short one: %.6f" % other[1])


func test_a_curve_with_no_centre_cannot_be_reconstructed_and_is_named() -> void:
	var plan: Dictionary = _read(_curve("ccw", "<Start>1030.0 3010.0</Start>", "", "<End>1040.0 3000.0</End>"))
	var drive: Dictionary = _feature(plan, "alignment")
	# The two straight parts still arrive, and the missing arc leaves a *straight* join where it was:
	# the curve's end is where the next line begins, so the corners are all there and only the turn is
	# gone. Guessing a centre would draw an arc the file never stated.
	assert(bool(plan["ok"]))
	assert((drive["points"] as PackedVector2Array).size() == 4,
		"the lines either side, joined: %d" % (drive["points"] as PackedVector2Array).size())
	for bulge: float in (drive["bulges"] as PackedFloat64Array):
		assert(is_zero_approx(bulge), "and nothing on it turns: %.6f" % bulge)
	var report := "\n".join(PackedStringArray(LandXml.report_lines(plan)))
	assert(report.contains("a curve with no centre, which cannot be drawn"), report)


# --- the point database ------------------------------------------------------------------


func test_a_point_may_be_a_reference_to_a_point_elsewhere_in_the_file() -> void:
	var plan: Dictionary = _read(_curve())
	assert(int(plan["cg_points"]) == 4, "four points in the database")
	assert(int(plan["refs"]) == 8, "and eight references to them, one per end of a parcel line: %d" % int(plan["refs"]))
	assert(int(plan["bad_refs"]) == 0)
	# A reference into nothing is counted and reported rather than becoming a shape at the origin. The
	# *reference* is broken rather than the point: a file that holds BND9 and points at BND9 is sound.
	var text := _plat("<Metric linearUnit=\"meter\"/>", _curve())
	var plan_broken: Dictionary = LandXml.read_text(text.replace("pntRef=\"BND4\"", "pntRef=\"BND9\""))
	assert(int(plan_broken["bad_refs"]) > 0, "the parcel points at a point the file does not hold")
	var report := "\n".join(PackedStringArray(LandXml.report_lines(plan_broken)))
	assert(report.contains("point at a CgPoint the file does not hold"), report)
	# The alignment, which states its own coordinates, is unaffected: nothing is dropped in silence.
	assert(String(_feature(plan_broken, "alignment").get("feature", "")) == "alignment")


func test_a_point_list_reads_and_its_elevations_are_dropped() -> void:
	var plan: Dictionary = _read(_curve())
	var fence: Dictionary = _feature(plan, "plan feature")
	var points: PackedVector2Array = fence["points"]
	assert(points.size() == 3, "three posts: %d" % points.size())
	assert(points[0].is_equal_approx(Vector2(3000.0, -1010.0)),
		"north 1010, east 3000, and no height at all: %s" % str(points[0]))


# --- what it refuses to draw -------------------------------------------------------------


func test_a_spiral_breaks_the_line_it_is_in_and_is_named() -> void:
	var plan: Dictionary = _read(
		"        <Spiral rot=\"ccw\"><Start>1030.0 3010.0</Start><Center>1040.0 3010.0</Center><End>1040.0 3000.0</End></Spiral>"
	)
	# An alignment with a spiral in it arrives as *two* shapes rather than one joined across something
	# this reader cannot draw - which is the one thing the shape table cannot express for itself.
	assert((plan["shapes"] as Array).size() == 4, "the alignment is in two pieces: %d shapes" % (plan["shapes"] as Array).size())
	assert(int(plan["broken"]) == 1, "one break")
	assert(int(plan["counts"]["alignment"]) == 2, "counted as two alignments, because it is two lines")
	var report := "\n".join(PackedStringArray(LandXml.report_lines(plan)))
	assert(report.contains("a Spiral in a line, which broke it there"), report)


func test_something_this_reader_does_not_follow_is_counted_by_name() -> void:
	var plan: Dictionary = _read(_curve())
	var skipped: Dictionary = plan["skipped"]
	var reasons: Array = skipped.keys()
	assert(reasons.size() == 1, "one thing was left out: %s" % str(reasons))
	assert(String(reasons[0]) == "a surface, which is a whole problem of its own", String(reasons[0]))
	var report := "\n".join(PackedStringArray(LandXml.report_lines(plan)))
	assert(report.contains("a surface"), report)
	# And the counts say what came in, by feature.
	assert(int(plan["counts"]["parcel"]) == 1)
	assert(int(plan["counts"]["plan feature"]) == 1)
	assert(String(plan["shapes"][0]["name"]) == "LOT 12", "a feature keeps the name the file gave it")


# --- units -------------------------------------------------------------------------------


func test_a_file_that_states_its_units_is_believed() -> void:
	var plan: Dictionary = _read(_curve())
	assert(String(plan["units"]) == "metres", String(plan["units"]))
	assert(String(plan["declared_unit"]) == "meter", "the file's own word is kept beside the reader's")
	assert(String(plan["units_from"]) == "the file's own linear unit")
	assert(is_equal_approx(float(plan["unit_factor"]), 1.0))
	# In feet, the same numbers are feet: 3060 east is 932.688 m.
	var imperial: Dictionary = LandXml.read_text(
		_plat("<Imperial linearUnit=\"USSurveyFoot\"/>")
	)
	assert(bool(imperial["ok"]), String(imperial["reason"]))
	assert(String(imperial["declared_unit"]) == "USSurveyFoot")
	assert(absf(float(imperial["unit_factor"]) - 1200.0 / 3937.0) < 1.0e-9, "the survey foot, not the international one")
	var lot: Dictionary = _feature(imperial, "parcel")
	assert(absf((lot["points"] as PackedVector2Array)[2].x - 3060.0 * 1200.0 / 3937.0) < 1.0e-3,
		"the same numbers as survey feet: %.6f" % (lot["points"] as PackedVector2Array)[2].x)


func test_every_length_the_reader_can_read_has_a_word_to_call_it_by() -> void:
	# The two tables are keyed by the same normalised names, and a length this reader can read and
	# cannot name would reach a report as an empty word: "3 shapes in " is not a sentence.
	for unit_name: Variant in LandXml.LINEAR_UNITS:
		assert(LandXml.UNIT_WORDS.has(String(unit_name)),
			"the reader can read %s and has no word for it" % String(unit_name))
	for unit_name: Variant in LandXml.UNIT_WORDS:
		assert(LandXml.LINEAR_UNITS.has(String(unit_name)),
			"and %s is a word for a length it cannot read" % String(unit_name))
	# Every spelling a file or a person might use reaches a sentence with words in it.
	for spelling: String in [
		"meter", "metre", "metres", "m", "foot", "ft", "USSurveyFoot", "us survey feet", "inch",
	]:
		assert(String(LandXml.units_for(spelling, "")["name"]) != "", spelling)
	# And the words are the ones a person would write, not the file's own camel case.
	assert(String(LandXml.units_for("meter", "")["name"]) == "metres")
	assert(String(LandXml.units_for("foot", "")["name"]) == "feet")
	assert(String(LandXml.units_for("USSurveyFoot", "")["name"]) == "US survey feet")
	assert(String(LandXml.units_for("", "feet")["name"]) == "feet", "and so is what a person answers")


func test_a_file_that_does_not_say_its_units_is_refused_until_it_is_asked() -> void:
	# No `Units` element at all: the reader refuses with the sentence that asks.
	var unstated: Dictionary = LandXml.read_text(_plat(""))
	assert(not bool(unstated["ok"]))
	assert(String(unstated["reason"]).contains("does not say"), String(unstated["reason"]))
	assert(not LandXml.is_usable(unstated))
	# A person answers, and the same text reads. A file that *does* state its units ignores the answer.
	var answered: Dictionary = LandXml.read_text(_plat(""), {"units": "feet"})
	assert(bool(answered["ok"]), String(answered["reason"]))
	assert(String(answered["units_from"]) == "what was asked for")
	assert(absf(float(answered["unit_factor"]) - 0.3048) < 1.0e-12)
	assert(String(LandXml.describe(answered)).ends_with(", because the file does not say"),
		LandXml.describe(answered))
	var ignored: Dictionary = LandXml.read_text(_plat(), {"units": "feet"})
	assert(String(ignored["units"]) == "metres", "the file's own answer stands: %s" % String(ignored["units"]))
	# A unit nothing knows is not an answer, and a file naming one is refused rather than guessed at.
	var nonsense: Dictionary = LandXml.read_text(_plat("<Metric linearUnit=\"furlongs\"/>"))
	assert(not bool(nonsense["ok"]))
	assert(String(nonsense["reason"]).contains("furlongs"), String(nonsense["reason"]))
	assert(not bool(LandXml.read_text(_plat(""), {"units": "furlongs"})["ok"]))
	assert(String(LandXml.units_for("", "").get("reason", "")).contains("asked about"))


# --- what is not a plat ------------------------------------------------------------------


func test_a_file_that_is_not_a_landxml_plat_says_so() -> void:
	for junk: String in ["", "   ", "these are not tags at all", "<svg><rect/></svg>"]:
		var plan: Dictionary = LandXml.read_text(junk)
		assert(not bool(plan["ok"]), "refused: %s" % junk)
		assert(not String(plan["reason"]).is_empty(), "with a reason")
	assert(String(LandXml.read_text("<svg><rect/></svg>")["reason"]).contains("LandXML"))
	assert(String(LandXml.read_text("")["reason"]) == "the file is empty")
	# A document that stops part way through is damaged rather than empty, and says which line.
	var cut: Dictionary = LandXml.read_text("<LandXML><Parcels><Parcel name=\"LOT\">")
	assert(not bool(cut["ok"]), "a truncated file is refused")
	assert(String(cut["reason"]).contains("well-formed"), String(cut["reason"]))
	assert(LandXml.describe(cut) == String(cut["reason"]), "and it describes itself by saying why")


func test_the_underlay_is_the_default_and_the_layer_mapping_is_the_option() -> void:
	var plan: Dictionary = _read(_curve())
	for shape: Dictionary in (plan["shapes"] as Array):
		assert(String(shape["layer"]) == String(LayerSet.UNDERLAY),
			"a plat is something to trace over: %s" % String(shape["layer"]))
	var kept := LandXml.read_text(_plat("<Metric linearUnit=\"meter\"/>", _curve()), {"underlay": false})
	var kept_lot: Dictionary = _feature(kept, "parcel")
	var kept_drive: Dictionary = _feature(kept, "alignment")
	assert(String(kept_lot["layer"]) == String(LayerSet.SURVEY_PROPERTY),
		"a parcel is the property line")
	assert(String(kept_drive["layer"]) == String(LayerSet.EXISTING_HARDSCAPE),
		"an alignment is a way through the site")
	assert((kept["layers"] as Array).size() == 2, "and two layers were used: %s" % str(kept["layers"]))


func test_a_plat_that_is_not_there_or_is_not_readable_is_refused_rather_than_raising() -> void:
	var missing: Dictionary = LandXml.of_file("user://no-such-plat-that-exists.xml")
	assert(not bool(missing["ok"]))
	assert(String(missing["reason"]).contains("there is no file called"), String(missing["reason"]))
	assert(not bool(LandXml.of_file("")["ok"]))
	var path := "user://landxml-test-plat.xml"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(_plat("<Metric linearUnit=\"meter\"/>", _curve()))
	file.close()
	var read: Dictionary = LandXml.of_file(path)
	assert(bool(read["ok"]), String(read["reason"]))
	assert(String(read["source"]) == "landxml-test-plat.xml", "and it says which file it read")
	assert((read["shapes"] as Array).size() == 3)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_the_registration_options_reach_the_geometry() -> void:
	var plan: Dictionary = LandXml.read_text(
		_plat("<Metric linearUnit=\"meter\"/>", _curve()),
		{"offset": Vector2(10.0, -5.0), "rotation": 90.0}
	)
	var parcel: Dictionary = _feature(plan, "parcel")
	# Turned a quarter turn about the origin, then moved: the corner that was 3000 east and 1000 south
	# is 1000 east and 3000 south, and then 5 m further east and 5 m further south.
	var moved: Vector2 = parcel["points"][0]
	assert(moved.is_equal_approx(Vector2(1000.0 + 10.0, 3000.0 - 5.0)),
		"the turned and moved corner: %s" % str(moved))


func test_the_import_key_set_matches_what_a_dxf_shape_carries() -> void:
	# The claim this reader exists to test, in the small: the shape table is `DxfFile`'s, and a third
	# format fills it without a new key. What each reader adds beside it is its own provenance - the DXF
	# reader the layer name from the file, this one the feature - and that is per-reader by design.
	var dxf: Dictionary = Dxf.read_text("\n".join(PackedStringArray([
		"0", "SECTION", "2", "HEADER", "9", "$INSUNITS", "70", "6", "0", "ENDSEC",
		"0", "SECTION", "2", "ENTITIES",
		"0", "LINE", "8", "PROPERTY", "10", "0.0", "20", "0.0", "11", "10.0", "21", "10.0",
		"0", "ENDSEC", "0", "EOF", "",
	])))
	var from_dxf: Dictionary = (dxf["shapes"] as Array)[0]
	var from_landxml: Dictionary = _feature(_read(_curve()), "parcel")
	for key: String in SHARED:
		assert(from_dxf.has(key), "the DXF reader fills %s" % key)
		assert(from_landxml.has(key), "and so does this one")
	assert(from_dxf.has("dxf_layer"), "the DXF reader names the layer the file had")
	assert(from_landxml.has("feature"), "this one names the feature the container was")
	assert(not from_dxf.has("feature"), "and neither pretends to be the other")