class_name OsmFetch
extends Node
## Asking OpenStreetMap for the map around a site, and handing what it answers to `OsmFile`.
##
## ## The two halves, kept apart on purpose
##
## What to *ask for* is arithmetic on the site's coordinates and is a pure static function
## (`build_query`, `bounds_of`, `can_fetch`) with no network in it, so it can be read and tested on a
## machine that has never been online. Actually *asking* is one `HTTPRequest` in `fetch`, which is the
## only line of this file that touches the network - and the only part the test suite does not
## exercise, because a test that needs the internet is a test that fails on a train.
##
## ## Why Overpass
##
## OpenStreetMap's own API answers about one object at a time; Overpass answers "everything in this
## rectangle with these tags", which is exactly the question a site plan asks. The query it wants is
## one string: a header, a union of tag-and-area selections, and `out geom` so each way comes back with
## its own points rather than a list of node ids that would each need a second request.
##
## ## What it will not do
##
## It will not guess a place. A centre that is not on the earth, a radius of nothing, or a radius
## larger than `MAX_RADIUS_M` is refused with the sentence that says so, because the failure mode of
## guessing is a map of somewhere else drawn confidently over somebody's garden.

const OsmFileScript := preload("res://scripts/draft/osm_file.gd")

## The public Overpass interpreter. One URL, stated here, because it is the one thing about this
## module that is somebody else's and could move.
const ENDPOINT := "https://overpass-api.de/api/interpreter"

## What a site map is asked for by default: a couple of hundred metres, which is a garden and its
## street. Small enough that an extract is a page of geometry rather than a megabyte of city.
const DEFAULT_RADIUS_M := 120.0

## The most this will ask for. Beyond a couple of kilometres the answer stops being site context and
## starts being a map of a town, and a drawing holding one is slow to open and impossible to read.
const MAX_RADIUS_M := 2000.0

## How long Overpass is given before it gives up on its own side of the query.
const TIMEOUT_S := 25.0

## The tag keys this asks for. Almost the same list `OsmFile.feature_for` understands, and the two are
## read together: a key asked for here and drawn nowhere there is a wasted round trip, and one drawn
## but not asked for never arrives. `OsmFile` decides what each key *means*; this decides which ones
## are worth fetching. `natural` and `landuse` cover trees, woods, water and open ground; the rest are
## the built things a plan has to sit beside.
const ASKED_TAGS: Array[String] = [
	"building", "highway", "railway", "waterway", "natural", "landuse", "leisure", "amenity",
	"barrier", "wall",
]


## Whether there is a place to ask about at all, and why not when there is not. One function so the
## window that offers the button and the request that would be made cannot disagree about whether the
## question makes sense.
static func can_fetch(centre: Dictionary, radius_m: float) -> Dictionary:
	if centre.is_empty() or not centre.has("latitude") or not centre.has("longitude"):
		return {"ok": false, "reason": "there is no centre to put the map around, so it is not asked for"}
	var latitude := float(centre["latitude"])
	var longitude := float(centre["longitude"])
	if is_nan(latitude) or is_nan(longitude) or absf(latitude) > 90.0 or absf(longitude) > 180.0:
		return {
			"ok": false,
			"reason": "%.4f, %.4f is not a place on the earth" % [latitude, longitude],
		}
	if is_nan(radius_m) or radius_m <= 0.0:
		return {"ok": false, "reason": "a map is asked for around a distance, and that is not one"}
	if radius_m > MAX_RADIUS_M:
		return {
			"ok": false,
			"reason": "%.0f m is more map than this draws: the most it will ask for is %.0f m" % [
				radius_m, MAX_RADIUS_M,
			],
		}
	return {"ok": true, "reason": ""}


## The rectangle a radius about a centre covers, in degrees. The two are not the same number of
## degrees: a metre is a smaller share of a degree of longitude than of a degree of latitude anywhere
## but the equator, so each is divided by its own degree length.
static func bounds_of(centre: Dictionary, radius_m: float) -> Dictionary:
	var latitude := float(centre.get("latitude", 0.0))
	var longitude := float(centre.get("longitude", 0.0))
	var d_lat := radius_m / maxf(OsmFileScript.metres_per_degree_latitude(latitude), 1.0)
	var d_lon := radius_m / maxf(OsmFileScript.metres_per_degree_longitude(latitude), 1.0)
	return {
		"south": maxf(latitude - d_lat, -90.0),
		"north": minf(latitude + d_lat, 90.0),
		"west": longitude - d_lon,
		"east": longitude + d_lon,
	}


## The Overpass query for everything this draws within `radius_m` of `centre`.
##
## The search is `around:`, a circle, rather than the bounding box of `bounds_of`: a circle is the
## shape a site actually is, and the box is only what the header states as a sanity limit.
static func build_query(centre: Dictionary, radius_m: float) -> String:
	var latitude := float(centre.get("latitude", 0.0))
	var longitude := float(centre.get("longitude", 0.0))
	var around := "around:%s,%s,%s" % [
		String.num(radius_m, 2), String.num(latitude, 6), String.num(longitude, 6),
	]
	var selectors := PackedStringArray()
	for tag: String in ASKED_TAGS:
		selectors.append("  way[\"%s\"](%s);" % [tag, around])
	# A tree is a node rather than a way, and so is anything named that has no shape of its own.
	selectors.append("  node[\"natural\"=\"tree\"](%s);" % around)
	selectors.append("  node[\"name\"](%s);" % around)
	return "\n".join(PackedStringArray([
		"[out:json][timeout:%d];" % int(TIMEOUT_S),
		"(",
		"\n".join(selectors),
		");",
		# `out geom` is not optional: without it a way arrives as a list of node ids and nothing
		# here could draw it without a second request per way.
		"out geom;",
		"",
	]))


## Whether this reader is somewhere it can reach the network at all. A `HTTPRequest` has to be in the
## scene to make a request, which is why a reader built by a test but never added to a tree refuses
## rather than pretending.
func can_reach_network() -> Dictionary:
	if not is_inside_tree():
		return {"ok": false, "reason": "the map reader is not in the scene, so it cannot reach the network"}
	return {"ok": true, "reason": ""}


## Ask OpenStreetMap for the map, and read what it answers. Returns a plan in `OsmFile`'s own shape:
## a refusal is a plan with `ok` false and the reason in words, so a caller has one thing to handle
## rather than two.
##
## Must be awaited: the request is the one thing here that takes time.
func fetch(centre: Dictionary, radius_m: float) -> Dictionary:
	var askable := can_fetch(centre, radius_m)
	if not bool(askable["ok"]):
		return OsmFileScript.refused(String(askable["reason"]))
	var reachable := can_reach_network()
	if not bool(reachable["ok"]):
		return OsmFileScript.refused(String(reachable["reason"]))
	var query := build_query(centre, radius_m)
	var headers := PackedStringArray(["Content-Type: application/x-www-form-urlencoded"])
	var error := _request().request(
		ENDPOINT, headers, HTTPClient.METHOD_POST, "data=" + query.uri_encode()
	)
	if error != OK:
		return OsmFileScript.refused(
			"the request to OpenStreetMap could not be started (%s)" % error_string(error).to_lower()
		)
	var answered: Array = await _request().request_completed
	var status := int(answered[1])
	if status != 200:
		return OsmFileScript.refused(
			"OpenStreetMap answered %d, so the map was not read" % status
		)
	var body := (answered[3] as PackedByteArray).get_string_from_utf8()
	return OsmFileScript.read_text(body, {"centre": centre, "radius": radius_m})


## Read a saved Overpass response - the file a person exported from overpass-turbo, or one this saved
## earlier. The offline half of the same import: no network, and the same reader.
static func read_saved(path: String, centre: Dictionary, radius_m: float) -> Dictionary:
	return OsmFileScript.of_file(path, {"centre": centre, "radius": radius_m})


## The one `HTTPRequest`, made on first use and kept, because a request node per fetch is a node per
## keystroke's worth of use.
var _client: HTTPRequest = null


func _request() -> HTTPRequest:
	if _client == null:
		_client = HTTPRequest.new()
		_client.name = "OsmRequest"
		_client.timeout = TIMEOUT_S
		add_child(_client)
	return _client