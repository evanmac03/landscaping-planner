extends Node
## Whether a plant belongs where it is about to be planted: the verdict, the reasons, and the report
## on the planting that is already in the ground.
##
## The examples are the ones a designer would actually argue about, because the point of the feature
## is to be right about horticulture rather than merely consistent:
##
## * a **tomato** - full sun, medium water - is wrong in shade and right in the open.
## * a **hosta** - shade to part shade, medium water - is right in shade and wrong in full sun.
## * a **willow** - full sun, high water - is right in a damp bed and wrong in a dry one.
## * a **lavender** - low water - is right in dry ground and wrong in a bog, because wanting *less*
##   water than the ground holds is not the mirror image of wanting more: one drowns, the other is
##   thirsty and can be watered.
##
## And the fourth verdict, `UNKNOWN`, is tested hardest of all, because it is the one that is easy to
## get wrong in a way nobody notices: a plan that says nothing about the ground must produce "I
## cannot tell you", never a confident green.

const Suitability := preload("res://scripts/plant_suitability.gd")
const Profile := preload("res://scripts/terrain_profile.gd")
const ZoneMapScript := preload("res://scripts/zone_map.gd")
const SpeciesScript := preload("res://scripts/plant_species.gd")
const CatalogueScript := preload("res://scripts/plant_catalogue.gd")
const PlacementScript := preload("res://scripts/plant_placement.gd")

const SHADE := SpeciesScript.FULL_SHADE
const SUN := SpeciesScript.FULL_SUN
const PART := SpeciesScript.PART_SHADE
const DRY := SpeciesScript.WATER_LOW
const DAMP := SpeciesScript.WATER_MEDIUM
const WET := SpeciesScript.WATER_HIGH


## A species with the fields a suitability check reads. Everything else is whatever the table
## defaults to, because none of it is what is under test.
func _species(
	id: String, common: String, sun: int, water: int, zone_min: int = 3, zone_max: int = 9
) -> PlantSpecies:
	var species: PlantSpecies = SpeciesScript.make(
		StringName(id), "Species %s" % id, common, 60, 45
	)
	species.sun = sun
	species.water = water
	species.zone_min = zone_min
	species.zone_max = zone_max
	return species


func _tomato() -> PlantSpecies:
	return _species("tomato", "Tomato", SUN, DAMP)


func _hosta() -> PlantSpecies:
	return _species("hosta", "Hosta", PART | SHADE, DAMP)


func _willow() -> PlantSpecies:
	return _species("willow", "Willow", SUN, WET)


func _lavender() -> PlantSpecies:
	return _species("lavender", "Lavender", SUN, DRY)


func _outcome(verdict: Dictionary, key: String) -> int:
	for finding: Dictionary in verdict["findings"]:
		if String(finding["key"]) == key:
			return int(finding["outcome"])
	return -1


# --- the three plants a designer argues about ---------------------------------------------


func test_a_hosta_in_shade_is_green() -> void:
	var ground: TerrainProfile = Profile.make({"sun": SHADE, "moisture": DAMP})
	var verdict: Dictionary = Suitability.check(_hosta(), ground)
	assert(int(verdict["verdict"]) == Suitability.GOOD, "a shade plant in shade: %s" % verdict["summary"])
	assert(bool(verdict["ok"]) and bool(verdict["certain"]), "and it is a confident answer")
	assert(verdict["colour"] == Suitability.GOOD_COLOUR, "which is drawn green")
	assert(_outcome(verdict, "sun") == Suitability.GOOD, "the light is what was checked")
	assert(_outcome(verdict, "moisture") == Suitability.GOOD, "and so is the water")
	assert(String(verdict["summary"]).contains("Hosta"), verdict["summary"])
	assert(String(verdict["label"]) == "suits this spot", String(verdict["label"]))


func test_a_tomato_in_shade_is_red() -> void:
	var ground: TerrainProfile = Profile.make({"sun": SHADE, "moisture": DAMP})
	var verdict: Dictionary = Suitability.check(_tomato(), ground)
	assert(int(verdict["verdict"]) == Suitability.UNSUITABLE)
	assert(not bool(verdict["ok"]), "red means not suited")
	assert(verdict["colour"] == Suitability.UNSUITABLE_COLOUR)
	assert(_outcome(verdict, "sun") == Suitability.UNSUITABLE, "it is the light that is wrong")
	assert(String(verdict["summary"]).contains("wrong plant for this spot"), verdict["summary"])
	assert(String(verdict["summary"]).contains("full shade"), "and the reason names the ground: %s" % verdict["summary"])
	assert(String(verdict["label"]).contains("full sun"), "the short label says what it wants: %s" % verdict["label"])


func test_a_willow_wants_a_damp_bed_and_not_a_dry_one() -> void:
	var damp: Dictionary = Suitability.check(_willow(), Profile.make({"sun": SUN, "moisture": WET}))
	assert(int(damp["verdict"]) == Suitability.GOOD, "a willow in a bog is at home")
	var dry: Dictionary = Suitability.check(_willow(), Profile.make({"sun": SUN, "moisture": DRY}))
	assert(int(dry["verdict"]) == Suitability.UNSUITABLE, "and in a dry bed it is not")
	assert(_outcome(dry, "moisture") == Suitability.UNSUITABLE)
	assert(String(dry["summary"]).contains("wants more water than this spot holds"), dry["summary"])
	assert(String(dry["label"]) == "wants more water", String(dry["label"]))


func test_a_drought_lover_in_wet_ground_is_red_the_other_way() -> void:
	var verdict: Dictionary = Suitability.check(_lavender(), Profile.make({"sun": SUN, "moisture": WET}))
	assert(int(verdict["verdict"]) == Suitability.UNSUITABLE, "a lavender in a bog rots")
	assert(String(verdict["summary"]).contains("sharper drainage"), verdict["summary"])


func test_the_milder_mismatch_in_each_direction_is_tolerated_not_failed() -> void:
	# A thirsty plant on ground one step short of what it wants is carried by irrigation, and a
	# drought-tolerant plant on ground one step wetter holds on. Calling both of those failures would
	# teach a designer to ignore red rings, which is the expensive way to be wrong.
	var thirsty: Dictionary = Suitability.check(_willow(), Profile.make({"sun": SUN, "moisture": DAMP}))
	assert(int(thirsty["verdict"]) == Suitability.TOLERATED, thirsty["summary"])
	assert(bool(thirsty["ok"]), "it will live")
	assert(thirsty["colour"] == Suitability.TOLERATED_COLOUR, "which is worth saying in amber")
	var damp_lover: Dictionary = Suitability.check(
		_species("mint", "Mint", PART, DAMP), Profile.make({"sun": PART, "moisture": WET})
	)
	assert(int(damp_lover["verdict"]) == Suitability.TOLERATED, damp_lover["summary"])
	assert(String(damp_lover["label"]).contains("medium water"), String(damp_lover["label"]))


# --- the answer when nobody has described the ground --------------------------------------


func test_a_ground_nobody_has_described_is_unknown_and_never_green() -> void:
	var verdict: Dictionary = Suitability.check(_hosta(), Profile.make())
	assert(int(verdict["verdict"]) == Suitability.UNKNOWN, verdict["summary"])
	assert(bool(verdict["ok"]), "unknown is not a failure: it is an absence of an answer")
	assert(not bool(verdict["certain"]), "but it is not a confident one either")
	assert(verdict["colour"] == Suitability.UNKNOWN_COLOUR, "and it is drawn grey, not green")
	assert(String(verdict["summary"]).contains("cannot be checked"), verdict["summary"])
	assert(_outcome(verdict, "sun") == Suitability.UNKNOWN)
	assert(int(verdict["verdict"]) != Suitability.GOOD, "silence is never a pass")


func test_a_gap_in_the_plan_outranks_a_mere_mismatch() -> void:
	# The moisture is stated and is one step off (tolerated); the light is not stated at all. The gap
	# is what a designer can go and fix, so that is what the verdict reports.
	var verdict: Dictionary = Suitability.check(
		_willow(), Profile.make({"moisture": DAMP})
	)
	assert(_outcome(verdict, "moisture") == Suitability.TOLERATED, "the water is only worked around")
	assert(_outcome(verdict, "sun") == Suitability.UNKNOWN, "the light is unknown")
	assert(int(verdict["verdict"]) == Suitability.UNKNOWN, "and unknown is what comes back")
	assert(String(verdict["summary"]).contains("nothing says how much sun"), verdict["summary"])


func test_something_wrong_outranks_a_gap() -> void:
	var verdict: Dictionary = Suitability.check(_tomato(), Profile.make({"sun": SHADE}))
	assert(int(verdict["verdict"]) == Suitability.UNSUITABLE, "a stated fault beats an unstated fact")
	assert(_outcome(verdict, "moisture") == Suitability.UNKNOWN, "the moisture was never stated")


# --- what the catalogue is asked, and what it is not --------------------------------------


func test_the_catalogue_is_not_asked_what_it_does_not_say() -> void:
	# The plant says nothing about soil or drainage, so those questions are not asked - not asked and
	# answered "fine", and not asked and reported as a gap. A plant is not wrong on every soil
	# nobody has an opinion about.
	var ground: TerrainProfile = Profile.make({
		"sun": SUN, "moisture": DAMP, "soil": Profile.CLAY,
		"drainage": Profile.DRAINAGE_SLOW,
	})
	var verdict: Dictionary = Suitability.check(_tomato(), ground)
	assert(_outcome(verdict, "soil") == -1, "no soil was asked about")
	assert(_outcome(verdict, "drainage") == -1, "and no drainage either")
	assert(int(verdict["verdict"]) == Suitability.GOOD, "so the verdict is about the light and water")


func test_a_plant_that_names_its_soil_is_checked_on_it() -> void:
	var fussy: PlantSpecies = _species("fussy", "Fussy", SUN, DAMP)
	fussy.soils.assign([Profile.LOAM])
	var clay: Dictionary = Suitability.check(
		fussy, Profile.make({"sun": SUN, "moisture": DAMP, "soil": Profile.CLAY})
	)
	assert(_outcome(clay, "soil") == Suitability.UNSUITABLE, "it wants loam and this is clay")
	assert(String(clay["summary"]).contains("grows on loam"), clay["summary"])
	var right: Dictionary = Suitability.check(
		fussy, Profile.make({"sun": SUN, "moisture": DAMP, "soil": Profile.LOAM})
	)
	assert(int(right["verdict"]) == Suitability.GOOD)
	# And a plant that names its soil against a plan that does not name one is a gap, not a pass.
	var unstated: Dictionary = Suitability.check(fussy, Profile.make({"sun": SUN, "moisture": DAMP}))
	assert(_outcome(unstated, "soil") == Suitability.UNKNOWN, "the plan does not say what the soil is")
	assert(String(unstated["summary"]).contains("nothing says what the soil is"), unstated["summary"])


func test_a_plant_that_takes_one_drainage_is_checked_on_it() -> void:
	var dry_lover: PlantSpecies = _species("dry", "Dry lover", SUN, DRY)
	dry_lover.drainage = SpeciesScript.DRAINS_FAST
	var bog: Dictionary = Suitability.check(
		dry_lover, Profile.make({"sun": SUN, "moisture": DRY, "drainage": Profile.DRAINAGE_SLOW})
	)
	assert(_outcome(bog, "drainage") == Suitability.UNSUITABLE, "it wants sharp drainage")
	assert(String(bog["summary"]).contains("slow-draining"), bog["summary"])
	assert(String(bog["summary"]).contains("takes fast-draining"), "and says what it wants: %s" % bog["summary"])
	var sharp: Dictionary = Suitability.check(
		dry_lover, Profile.make({"sun": SUN, "moisture": DRY, "drainage": Profile.DRAINAGE_FAST})
	)
	assert(int(sharp["verdict"]) == Suitability.GOOD)
	assert(dry_lover.drainage_text() == "fast-draining", dry_lover.drainage_text())


func test_the_species_table_still_accepts_the_catalogue_that_ships() -> void:
	# The two added columns are optional, and the contract they keep with the shipped list is: an
	# entry that states neither is still valid, an entry that does state one states a value the
	# vocabulary knows, and whatever it states survives its own file format unchanged.
	var read: Dictionary = CatalogueScript.load_from("res://data/plants/nursery_list.json")
	assert(bool(read["ok"]), "the shipped list loads: %s" % String(read["reason"]))
	var catalogue: PlantCatalogue = read["catalogue"]
	var soily: int = 0
	var drained: int = 0
	for id: StringName in catalogue.ids():
		var species: PlantSpecies = catalogue.get_species(id)
		assert(species.is_valid(), "shipped entry %s: %s" % [id, species.problem()])
		for soil: StringName in species.soils:
			assert(Profile.SOILS.has(soil), "%s states a soil the vocabulary does not have: %s" % [id, soil])
		if not species.soils.is_empty():
			soily += 1
		if species.drainage != SpeciesScript.DRAINS_ANY:
			drained += 1
		var again: PlantSpecies = SpeciesScript.from_dict(species.to_dict())
		assert(again.soils == species.soils, "%s keeps its soil through a file" % id)
		assert(again.drainage == species.drainage, "%s keeps its drainage through a file" % id)
	# Both columns are actually in use, so the checks above are a check of the data rather than of
	# an empty set that would pass whatever it was given.
	assert(soily > 0, "the shipped list says something about soil")
	assert(drained > 0, "and something about drainage")


# --- hardiness ----------------------------------------------------------------------------


func test_hardiness_is_asked_about_only_where_the_place_claims_a_zone() -> void:
	var tender: PlantSpecies = _species("tender", "Tender", SUN, DAMP, 7, 11)
	# A place with no zone of its own is not a gap: a site's zone is stated once for the site, and a
	# plan that has not stated it must not turn every ring grey.
	var nowhere: Dictionary = Suitability.check(tender, Profile.make({"sun": SUN, "moisture": DAMP}))
	assert(_outcome(nowhere, "zone") == -1, "no zone was claimed, so none was asked about")
	assert(int(nowhere["verdict"]) == Suitability.GOOD, "and the answer is about the light and water")
	# A place that *does* claim a zone is a frost pocket, and then hardiness is exactly the question.
	var pocket: Dictionary = Suitability.check(
		tender, Profile.make({"sun": SUN, "moisture": DAMP, "zone": 5})
	)
	assert(_outcome(pocket, "zone") == Suitability.UNSUITABLE, "zone 7-11 in a zone 5 pocket")
	assert(String(pocket["summary"]).contains("hardy to zone 7"), pocket["summary"])
	assert(String(pocket["label"]) == "not hardy here", String(pocket["label"]))
	var sheltered: Dictionary = Suitability.check(
		tender, Profile.make({"sun": SUN, "moisture": DAMP, "zone": 8})
	)
	assert(int(sheltered["verdict"]) == Suitability.GOOD)


# --- the ground under the cursor ----------------------------------------------------------


func test_two_metres_away_can_be_a_different_answer() -> void:
	# The whole reason the ground is a map rather than a form: the same plant dropped in the sunny bed
	# instead of the shady garden is a different verdict, and the map is what knows that.
	var map: ZoneMapScript = ZoneMapScript.make({"sun": SHADE, "moisture": DAMP})
	map.add_zone(
		"the sunny bed",
		PackedVector2Array([
			Vector2(10.0, 10.0), Vector2(14.0, 10.0), Vector2(14.0, 14.0), Vector2(10.0, 14.0),
		]),
		Profile.of("sun", SUN)
	)
	var shade: Dictionary = Suitability.check_at(_tomato(), map, Vector2(0.0, 0.0))
	assert(int(shade["verdict"]) == Suitability.UNSUITABLE, shade["summary"])
	assert(String(shade["place"]) == "the rest of the site", String(shade["place"]))
	var bed: Dictionary = Suitability.check_at(_tomato(), map, Vector2(12.0, 12.0))
	assert(int(bed["verdict"]) == Suitability.GOOD, "the sunny bed suits it: %s" % bed["summary"])
	assert(String(bed["place"]) == "the sunny bed")
	# And a plant checked with no map at all is an unknown, not a crash.
	var nowhere: Dictionary = Suitability.check_at(_tomato(), null, Vector2.ZERO)
	assert(int(nowhere["verdict"]) == Suitability.UNKNOWN)


# --- the planting already in the ground ----------------------------------------------------


## A yard built by hand: `Plants` with three planted props on it and one the catalogue cannot name.
##
## The props are bare `Node3D`s carrying the species metadata rather than instanced scenes, because
## what is under test is the audit's reading of the planting - which species, at which point - and not
## the prop scenes, which have their own tests.
##
## The three are planted where they belong - two hostas in the shade, the tomato in the sunny bed -
## so that the first test is about an audit finding nothing wrong and the second can move one.
func _yard() -> Node3D:
	var yard := Node3D.new()
	yard.name = "Yard"
	var plants := Node3D.new()
	plants.name = PlacementScript.PLANTS
	yard.add_child(plants)
	var at := [Vector3(0.0, 0.0, 0.0), Vector3(2.0, 0.0, 2.0), Vector3(12.0, 0.0, 12.0)]
	var ids := [&"hosta", &"hosta", &"tomato"]
	for index in ids.size():
		var node := Node3D.new()
		node.name = "Plant%d" % index
		node.set_meta(PlacementScript.SPECIES_META, String(ids[index]))
		node.position = at[index]
		node.add_to_group("placeable")
		plants.add_child(node)
	var stranger := Node3D.new()
	stranger.name = "Prop30"
	stranger.position = Vector3(2.0, 0.0, 2.0)
	stranger.add_to_group("placeable")
	plants.add_child(stranger)
	return yard


func _catalogue() -> PlantCatalogue:
	var catalogue: PlantCatalogue = CatalogueScript.new()
	catalogue.add(_hosta())
	catalogue.add(_tomato())
	catalogue.add(_willow())
	return catalogue


## The same map as the check above: a shady, damp garden with one sunny bed in it.
func _map() -> ZoneMapScript:
	var map: ZoneMapScript = ZoneMapScript.make({"sun": SHADE, "moisture": DAMP})
	map.add_zone(
		"the sunny bed",
		PackedVector2Array([
			Vector2(10.0, 10.0), Vector2(14.0, 10.0), Vector2(14.0, 14.0), Vector2(10.0, 14.0),
		]),
		Profile.of("sun", SUN)
	)
	return map


func test_the_audit_checks_the_planting_that_is_already_in_the_ground() -> void:
	var yard: Node3D = _yard()
	var report: Dictionary = Suitability.audit(_catalogue(), yard, _map())
	var counts: Dictionary = report["counts"]
	assert(int(counts[Suitability.GOOD]) == 3, "the shade is right for two hostas, and the bed for a tomato: %s" % str(counts))
	assert(int(counts[Suitability.UNSUITABLE]) == 0, "nothing is in the wrong place")
	# The prop with no species is counted and named, not skipped: an audit that passed it would be
	# reporting on a planting list it cannot name.
	assert(int(report["planted"]) == 4, "four plants on the plan")
	assert(int(report["unnamed"]) == 1, "one of which the catalogue cannot name")
	assert((report["rows"] as Array).size() == 3, "three rows to report on")
	assert(String(report["text"]).contains("3 suit their spot"), String(report["text"]))
	assert(String(report["text"]).contains("1 have no species recorded"), String(report["text"]))
	yard.free()


func test_the_audit_reports_what_is_in_the_wrong_place() -> void:
	var yard: Node3D = _yard()
	# Move the tomato out of the sunny bed and into the shade, where it has no business being.
	var tomato: Node3D = yard.get_node("Plants/Plant2")
	tomato.position = Vector3(-4.0, 0.0, -4.0)
	var report: Dictionary = Suitability.audit(_catalogue(), yard, _map())
	assert(int(report["counts"][Suitability.UNSUITABLE]) == 1, "the tomato is in the shade")
	assert(String(report["text"]).contains("1 is in the wrong place"), String(report["text"]))
	var lines: Array[String] = Suitability.audit_lines(report)
	assert(lines.size() == 1, "one line to read: %s" % " | ".join(lines))
	assert(lines[0].contains("Tomato") and lines[0].contains("wrong plant"), lines[0])
	yard.free()


func test_an_audit_with_nothing_planted_says_so() -> void:
	var empty := Node3D.new()
	var report: Dictionary = Suitability.audit(_catalogue(), empty, _map())
	assert(int(report["planted"]) == 0)
	assert(String(report["text"]) == "no plants on the plan to check", String(report["text"]))
	assert(Suitability.audit_lines(report).is_empty())
	assert(String(Suitability.audit(_catalogue(), null, _map())["text"]) == "no yard to check")
	# The yard is a scene built by hand, so it is put away by hand: a Node is not reference counted.
	empty.free()


func test_an_audit_of_a_planting_that_names_nothing_leads_with_that() -> void:
	# The shipped yard is thirty props with no species on them. A report that led with "0 suit their
	# spot" would be leading with a zero about a check that could not run.
	var yard: Node3D = _yard()
	# Take the species off every plant: this is the yard as it ships.
	for plant: Node3D in PlacementScript.planted(yard):
		plant.remove_meta(PlacementScript.SPECIES_META)
	var report: Dictionary = Suitability.audit(_catalogue(), yard, _map())
	assert(int(report["planted"]) == 4, "all four are counted")
	assert(int(report["unnamed"]) == 4, "and all four are unnamed")
	assert(String(report["text"]) == "4 plants, and not one says which species it is", String(report["text"]))
	yard.free()