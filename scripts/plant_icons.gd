class_name PlantIcons
extends RefCounted
## The pictures of plants: the swatch a species is drawn as when it has no photograph of its own, and
## the tint that tells one species from another in a list.
##
## Shared by the browser and by the palette's plants section, because both want the same picture and
## a second copy of a pixel loop is a second thing to get wrong. The swatch is the *plan's* symbol for
## the prop a species is drawn as, in the pigment `PlanStyle` washes that prop in - so the palette,
## the browser and the drawing itself cannot disagree about what a plant looks like.
##
## The cache is keyed by **symbol, form and category**, not by species: seventeen species drawn as
## three props and nine symbols make a handful of pictures, and four thousand make a few dozen. It is
## static because both callers want the same handful of textures and a texture made twice is a buffer
## paid for twice.

const PlanStyleScript := preload("res://scripts/plan_style.gd")
const PlantSymbolsScript := preload("res://scripts/plant_symbols.gd")

## How big a generated swatch is. Small enough that a whole catalogue is cheap, big enough that the
## shape of a symbol is legible. Callers ask `ItemList` to scale it to the size they want.
const PIXELS := 64
const HALF := 32.0
## How far the symbol sits from the centre of the swatch, per axis at most. Held in from the edge so
## an outline is not clipped by the edge of the picture.
const EXTENT := HALF * 0.8125

static var CACHE := {}


## The colour a species' swatch is tinted with: its bloom colour when it has one, and white when it is
## grown for its foliage. Held towards white so the pigment underneath still reads as foliage - a tint
## that swallows the symbol is worse than no tint at all.
static func tint(species: PlantSpecies) -> Color:
	if species == null or species.bloom_months == 0:
		return Color.WHITE
	return Color.WHITE.lerp(species.bloom_colour, 0.4)


## The picture for a species: its own thumbnail when the catalogue has one, and the swatch drawn from
## the plan's own table when it has not.
##
## The second half is the point. A catalogue of four thousand species will not carry four thousand
## photographs, and a grid of empty boxes is one nobody can look through - so a species with no
## picture is drawn as its *symbol*.
static func textured(catalogue: PlantCatalogue, species_id: StringName) -> Texture2D:
	if catalogue == null:
		return null
	var species: PlantSpecies = catalogue.get_species(species_id)
	if species == null:
		return null
	var thumbnail: Texture2D = catalogue.thumbnail_for(species_id)
	if thumbnail != null:
		return thumbnail
	return texture_for(species)


## The symbol a species is drawn as. The same answer the plan reaches, through the same call, so the
## grid cannot show a plant as one shape while the drawing shows it as another.
static func symbol_of(species: PlantSpecies) -> StringName:
	if species == null:
		return PlantSymbolsScript.MARKER
	return PlantSymbolsScript.of(species, PlanStyleScript.spec_for(species.form)["symbol"])


static func texture_for(species: PlantSpecies) -> Texture2D:
	if species == null:
		return null
	var cache_key: String = "%s|%s|%d" % [String(symbol_of(species)), species.form, species.category]
	if CACHE.has(cache_key):
		return CACHE[cache_key] as Texture2D
	var texture: Texture2D = ImageTexture.create_from_image(swatch(species))
	CACHE[cache_key] = texture
	return texture


static func clear_cache() -> void:
	CACHE.clear()


## One symbol swatch, pixel by pixel.
##
## Drawn rather than loaded, so it needs no image files to exist, it works for a species added to the
## catalogue five seconds ago, and a whole catalogue costs one 64x64 buffer per symbol it is drawn as.
##
## Nothing here knows a shape: the figure comes from `PlantSymbols`, the same one the plan draws, and
## this is only the rasteriser for it - fill, outline and mark, sampled a pixel at a time. That is
## what keeps the grid and the drawing from disagreeing about what a plant looks like.
static func swatch(species: PlantSpecies) -> Image:
	# `create_empty` rather than a bare `Image.new()` plus `resize`: a new Image has no data at all,
	# and resizing a buffer that was never created is an engine error per pixel, not a blank picture.
	var image: Image = Image.create_empty(PIXELS, PIXELS, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var spec: Dictionary = PlanStyleScript.spec_for(species.form)
	var symbol: StringName = symbol_of(species)
	var pigment: Color = spec.get("wash", PlanStyleScript.FOLIAGE_WASH)
	# The outline and the marks are the pigment brought down, so a swatch is one plant's colour rather
	# than three: a bloom drawn in a fixed pink would be a flower on a foliage plant.
	var edge: Color = pigment.darkened(0.45)
	# Half the symbol's drawn extent in pixels, per axis: a round symbol is drawn round whatever the
	# prop's own footprint says, and an oblong one keeps the prop's proportions.
	var shaped: Vector2 = PlantSymbolsScript.shape_for(symbol, spec["size"])
	var half: Vector2 = shaped * (EXTENT / maxf(shaped.x, shaped.y))
	if half.x <= 0.0 or half.y <= 0.0:
		return image
	var parts: Array[Dictionary] = PlantSymbolsScript.figure(symbol)

	for y in PIXELS:
		for x in PIXELS:
			var point := Vector2(
				(float(x) + 0.5 - HALF) / half.x, (float(y) + 0.5 - HALF) / half.y
			)
			var colour: Color = Color(0, 0, 0, 0)
			for part: Dictionary in parts:
				if _inks(part, PlantSymbolsScript.INK_FILL) and _inside(part, point):
					colour = pigment
			for part: Dictionary in parts:
				if _inks(part, PlantSymbolsScript.INK_EDGE) and _stroked(part, point):
					colour = edge
			for part: Dictionary in parts:
				if _inks(part, PlantSymbolsScript.INK_MARK) and _inside(part, point):
					colour = edge
			if colour.a > 0.0:
				image.set_pixel(x, y, colour)
	return image


static func _inks(part: Dictionary, ink: StringName) -> bool:
	return StringName(part["ink"]) == ink


## Whether a normalised point is inside a part that has an inside: a disc, a rectangle, or a polygon.
static func _inside(part: Dictionary, point: Vector2) -> bool:
	var centre: Vector2 = part["c"] if part.has("c") else Vector2.ZERO
	match StringName(part["kind"]):
		&"disc":
			return point.distance_to(centre) <= float(part["r"])
		&"rect":
			var rect_half: Vector2 = part["half"]
			return absf(point.x - centre.x) <= rect_half.x and absf(point.y - centre.y) <= rect_half.y
		_:
			return _in_polygon(point, part["points"])


## Whether a normalised point is on a part that is a line: a ring, a rectangle outline, or a path.
static func _stroked(part: Dictionary, point: Vector2) -> bool:
	var centre: Vector2 = part["c"] if part.has("c") else Vector2.ZERO
	var width: float = float(part["w"]) * 0.5
	match StringName(part["kind"]):
		&"disc":
			return absf(point.distance_to(centre) - float(part["r"])) <= width
		&"rect":
			var rect_half: Vector2 = part["half"]
			var outer: bool = absf(point.x - centre.x) <= rect_half.x + width \
				and absf(point.y - centre.y) <= rect_half.y + width
			var inner: bool = absf(point.x - centre.x) <= maxf(rect_half.x - width, 0.0) \
				and absf(point.y - centre.y) <= maxf(rect_half.y - width, 0.0)
			return outer and not inner
		_:
			var points: PackedVector2Array = part["points"]
			var last: int = points.size() - 1
			for index in points.size():
				var next: int = 0 if index == last and bool(part["closed"]) else index + 1
				if next >= points.size():
					break
				if _to_segment(point, points[index], points[next]) <= width:
					return true
			return false


## The distance from a point to a line segment, which is what being on a stroke means.
static func _to_segment(point: Vector2, first: Vector2, second: Vector2) -> float:
	var span: Vector2 = second - first
	var length_squared: float = span.length_squared()
	if length_squared <= 0.0:
		return point.distance_to(first)
	var along: float = clampf((point - first).dot(span) / length_squared, 0.0, 1.0)
	return point.distance_to(first + span * along)


## The even-odd test, which is what the plan's own fills use: a point inside an inner ring - the hole
## a stipple leaves - is outside the part.
static func _in_polygon(point: Vector2, ring: PackedVector2Array) -> bool:
	var inside: bool = false
	var count: int = ring.size()
	var previous: int = count - 1
	for index in count:
		var here: Vector2 = ring[index]
		var before: Vector2 = ring[previous]
		if (here.y > point.y) != (before.y > point.y) \
			and point.x < (before.x - here.x) * (point.y - here.y) / (before.y - here.y) + here.x:
			inside = not inside
		previous = index
	return inside