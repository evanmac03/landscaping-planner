class_name ZoneMap
extends RefCounted
## The site's growing conditions, as areas on the plan.
##
## A map is **one base profile for the whole site plus any number of zones laid over it**, and a zone
## states only what it knows: marking a bed "full shade" does not also claim to know its soil, which
## then comes from the base. That is how a designer actually describes a garden - "the site is part
## shade on loam; this bed is full shade, and the strip by the wall is dry" - and it means the same
## fact is written once instead of once per zone.
##
## **Later zones win.** A zone list is in the order it was drawn, and the last one containing a point
## answers for it, so a designer can lay down a whole-garden zone and then cut a bed out of it. That
## is the order they draw in, and the alternative - smallest area wins - would silently reorder a map
## as somebody edited it.
##
## The drawing itself is evidence: `from_document()` reads the two things a plan already states about
## the ground - a building is shade, a hard surface is hot and dry - so a plan that has been drawn on
## gives real verdicts without anybody filling in a form first. See `NOT_DERIVED` for what a drawing
## cannot tell you.

const GeomScript := preload("res://scripts/draft/geom2d.gd")
const TerrainProfileScript := preload("res://scripts/terrain_profile.gd")
const PlantSpeciesScript := preload("res://scripts/plant_species.gd")
const LayerSetScript := preload("res://scripts/draft/layer_set.gd")

## The layers a drawing states conditions for, and what each one says about the ground.
##
## Only two kinds of thing on a plan are *evidence* about growing conditions: a building is shade and
## its eaves are dry, and a hard surface is full sun and drains fast. Everything else - a bed outline,
## a turf area, a hatch over paving - is a design intention about what will be planted, not a fact
## about the site, so nothing is derived from it. Reading a bed outline as "this is where the beds
## are" would be describing the design back to itself and calling it the environment.
const DERIVED := {
	LayerSetScript.EXISTING_STRUCTURE: {
		"name": "under the building",
		"profile": {"sun": PlantSpeciesScript.FULL_SHADE, "moisture": PlantSpeciesScript.WATER_LOW},
	},
	LayerSetScript.NEW_STRUCTURE: {
		"name": "under the building",
		"profile": {"sun": PlantSpeciesScript.FULL_SHADE, "moisture": PlantSpeciesScript.WATER_LOW},
	},
	LayerSetScript.EXISTING_HARDSCAPE: {
		"name": "hard surface",
		"profile": {
			"sun": PlantSpeciesScript.FULL_SUN,
			"moisture": PlantSpeciesScript.WATER_LOW,
			"drainage": TerrainProfileScript.DRAINAGE_FAST,
		},
	},
	LayerSetScript.NEW_HARDSCAPE: {
		"name": "hard surface",
		"profile": {
			"sun": PlantSpeciesScript.FULL_SUN,
			"moisture": PlantSpeciesScript.WATER_LOW,
			"drainage": TerrainProfileScript.DRAINAGE_FAST,
		},
	},
}

## What a drawing cannot tell you, so that "the ring is grey everywhere" has an answer: shade cast by
## a tree is a study away (the sun study can compute it), and a soil is a site visit.
const NOT_DERIVED := "a drawing shows where things are, not how wet the ground is: shade cast by a " \
	+ "tree, soil, and the fall of the land are not read from it"


## One area with its own conditions.
class Zone extends RefCounted:
	var name: String = ""
	## The ring, in plan metres. Not closed: the first point is not repeated.
	var outline: PackedVector2Array = PackedVector2Array()
	## Only what this zone states, over whatever the map's base says.
	var profile: TerrainProfile = null
	## Where it came from - "by hand", or the entity or layer a derived zone was read from.
	var source: String = ""

	func _init(zone_name: String = "") -> void:
		name = zone_name
		profile = TerrainProfile.make()

	func has_area() -> bool:
		return outline.size() >= 3 and GeomScript.polygon_area(outline) > 0.0

	func area() -> float:
		return absf(GeomScript.polygon_area(outline))

	func contains(point: Vector2) -> bool:
		return has_area() and GeomScript.point_in_polygon(point, outline)

	func bounds() -> Rect2:
		if outline.is_empty():
			return Rect2()
		var box := Rect2(outline[0], Vector2.ZERO)
		for point: Vector2 in outline:
			box = box.expand(point)
		return box

	func describe() -> String:
		return "%s (%s)" % [name, profile.describe()]

	func to_dict() -> Dictionary:
		var points: Array = []
		for point: Vector2 in outline:
			points.append([point.x, point.y])
		return {
			"name": name,
			"outline": points,
			"profile": profile.to_dict(),
			"source": source,
		}

	static func from_dict(data: Dictionary) -> Zone:
		var zone: Zone = Zone.new(String(data.get("name", "")))
		var raw: Variant = data.get("outline", [])
		if raw is Array:
			for pair: Variant in raw:
				if pair is Array and (pair as Array).size() >= 2:
					zone.outline.append(Vector2(float(pair[0]), float(pair[1])))
		var stated: Variant = data.get("profile", {})
		zone.profile = TerrainProfileScript.from_dict(stated if stated is Dictionary else {})
		zone.source = String(data.get("source", ""))
		return zone


## What the whole site is like before any zone is laid over it.
var base: TerrainProfile = TerrainProfile.make()
## In the order they were drawn; the last one containing a point answers for it.
var zones: Array[Zone] = []


static func make(stated_base: Dictionary = {}) -> ZoneMap:
	var map: ZoneMap = (load("res://scripts/zone_map.gd") as GDScript).new()
	map.base = TerrainProfile.make(stated_base)
	return map


# --- asking it ---------------------------------------------------------------------------


## The zone containing a point, or null when the site's own conditions are what apply.
func zone_at(point: Vector2) -> Zone:
	for index in range(zones.size() - 1, -1, -1):
		if zones[index].contains(point):
			return zones[index]
	return null


## What the ground is like at a point: the conditions, the zone they came from (or null), and a
## phrase naming the place, for a person reading a verdict rather than a row.
##
## Returns `{profile, zone, place, source}`.
func profile_at(point: Vector2) -> Dictionary:
	var zone: Zone = zone_at(point)
	if zone == null:
		return {
			"profile": base.copy(),
			"zone": null,
			"place": "the rest of the site",
			"source": "the site",
		}
	return {
		"profile": zone.profile.merged_over(base),
		"zone": zone,
		"place": zone.name if not zone.name.is_empty() else "this area",
		"source": zone.source,
	}


## The spot in words, for a status line or a tooltip: "hard surface (full sun, low water, drains
## fast)" or "the plan does not say what this spot is like".
func describe_at(point: Vector2) -> String:
	var spot: Dictionary = profile_at(point)
	var profile: TerrainProfile = spot["profile"]
	if profile.is_empty():
		return "%s: the plan does not say what the ground is like" % String(spot["place"])
	return "%s: %s" % [String(spot["place"]), profile.describe()]


# --- building one ------------------------------------------------------------------------


func add_zone(
	zone_name: String,
	outline: PackedVector2Array,
	profile: TerrainProfile,
	source: String = "by hand"
) -> Zone:
	var zone: Zone = Zone.new(zone_name)
	zone.outline = outline
	zone.profile = profile if profile != null else TerrainProfile.make()
	zone.source = source
	zones.append(zone)
	return zone


func zone_named(zone_name: String) -> Zone:
	for zone: Zone in zones:
		if zone.name == zone_name:
			return zone
	return null


## Remove a zone by name. Answers whether there was one: a map that silently did nothing is worse
## than one that says it did not find it.
func erase_zone(zone_name: String) -> bool:
	for index in zones.size():
		if zones[index].name == zone_name:
			zones.remove_at(index)
			return true
	return false


func zone_count() -> int:
	return zones.size()


func zone_names() -> Array[String]:
	var out: Array[String] = []
	for zone: Zone in zones:
		out.append(zone.name)
	return out


func clear_zones() -> void:
	zones.clear()


## The conditions a drawing already states, as zones. See `DERIVED`.
##
## A derived zone is a real zone with a real `source`, so a verdict that came from the drawing says
## so - "hard surface (full sun, low water)" - rather than presenting an inference as a fact somebody
## entered.
static func from_document(document: DraftDocument, stated_base: Dictionary = {}) -> ZoneMap:
	var map: ZoneMap = ZoneMap.make(stated_base)
	if document == null:
		return map
	for entity: DraftEntity in document.plotting_entities():
		var plan: Variant = DERIVED.get(entity.layer)
		if not (plan is Dictionary):
			continue
		var outline: PackedVector2Array = entity.outline()
		if outline.size() < 3:
			# A line, a dimension or a text: a run of wall is not an area of ground.
			continue
		var profile: TerrainProfile = TerrainProfile.make(plan["profile"])
		if profile.is_empty():
			continue
		var zone: Zone = map.add_zone(
			String(plan["name"]), outline, profile,
			"layer:%s#%d" % [String(entity.layer), entity.id]
		)
		if not zone.has_area():
			# A zero-area ring (a degenerate outline) states nothing about anywhere.
			map.zones.pop_back()
	return map


# --- reading and writing -----------------------------------------------------------------


func problems() -> Array[String]:
	var out: Array[String] = []
	var base_problem: String = base.problem()
	if not base_problem.is_empty():
		out.append("the site's own conditions: %s" % base_problem)
	for index in zones.size():
		var zone: Zone = zones[index]
		var label: String = zone.name if not zone.name.is_empty() else "zone %d" % (index + 1)
		var stated: String = zone.profile.problem()
		if not stated.is_empty():
			out.append("%s: %s" % [label, stated])
			continue
		if not zone.has_area():
			out.append("%s has no area, so nothing can ever be inside it" % label)
		if zone.profile.is_empty():
			out.append("%s states nothing, so it changes no verdict" % label)
	return out


func is_sound() -> bool:
	return problems().is_empty()


func describe() -> String:
	if zones.is_empty():
		return "site: %s" % base.describe()
	return "site: %s, over %d zone%s" % [base.describe(), zones.size(), "" if zones.size() == 1 else "s"]


func copy() -> ZoneMap:
	return from_dict(to_dict())


func to_dict() -> Dictionary:
	var rows: Array = []
	for zone: Zone in zones:
		rows.append(zone.to_dict())
	return {
		"base": base.to_dict(),
		"zones": rows,
	}


static func from_dict(data: Dictionary) -> ZoneMap:
	var map: ZoneMap = (load("res://scripts/zone_map.gd") as GDScript).new()
	var base_stated: Variant = data.get("base", {})
	map.base = TerrainProfileScript.from_dict(base_stated if base_stated is Dictionary else {})
	var rows: Variant = data.get("zones", [])
	if rows is Array:
		for record: Variant in rows:
			if record is Dictionary:
				map.zones.append(Zone.from_dict(record))
	return map