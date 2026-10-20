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
## The cache is keyed by **form and category**, not by species: seventeen species drawn as three props
## make three pictures, and four thousand make thirty. It is static because both callers want the same
## handful of textures and a texture made twice is a buffer paid for twice.

const PlanStyleScript := preload("res://scripts/plan_style.gd")

## How big a generated swatch is. Small enough that a whole catalogue is cheap, big enough that the
## shape of a symbol is legible. Callers ask `ItemList` to scale it to the size they want.
const PIXELS := 64
const HALF := 32.0

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


static func texture_for(species: PlantSpecies) -> Texture2D:
	if species == null:
		return null
	var cache_key: String = "%s|%d" % [species.form, species.category]
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
## catalogue five seconds ago, and a whole catalogue costs one 64x64 buffer per prop it is drawn as.
static func swatch(species: PlantSpecies) -> Image:
	# `create_empty` rather than a bare `Image.new()` plus `resize`: a new Image has no data at all,
	# and resizing a buffer that was never created is an engine error per pixel, not a blank picture.
	var image: Image = Image.create_empty(PIXELS, PIXELS, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var spec: Dictionary = PlanStyleScript.spec_for(species.form)
	var symbol: int = int(spec["symbol"])
	var pigment: Color = spec.get("wash", PlanStyleScript.FOLIAGE_WASH)
	var edge: Color = pigment.darkened(0.45)
	var radius: float = HALF * 0.8125

	for y in PIXELS:
		for x in PIXELS:
			var dx: float = float(x) + 0.5 - HALF
			var dy: float = float(y) + 0.5 - HALF
			var reach: float = sqrt(dx * dx + dy * dy)
			match symbol:
				PlanStyleScript.Symbol.TREE:
					# The trunk dot first, because it is the smallest radius: a branch ordered by
					# size from the centre outwards is the only order in which all of them are
					# reachable, and the other way round leaves the trunk undrawn.
					if reach <= radius * 0.18:
						image.set_pixel(x, y, edge)
					elif reach <= radius - 1.5:
						image.set_pixel(x, y, pigment)
					elif reach <= radius:
						image.set_pixel(x, y, edge)
				PlanStyleScript.Symbol.SHRUB:
					# The same seven-lobed wobble the plan's own `_blob` uses, at this size: a shrub
					# symbol is foliage rather than a disc, and the swatch should read as one.
					var lobe: float = radius * (1.0 + 0.13 * sin(7.0 * atan2(dy, dx)))
					if reach <= lobe - 1.5:
						image.set_pixel(x, y, pigment)
					elif reach <= lobe:
						image.set_pixel(x, y, edge)
				PlanStyleScript.Symbol.BED:
					if absf(dx) <= 22.0 and absf(dy) <= 14.0:
						image.set_pixel(x, y, pigment)
					# The stone edge the plan draws round a bed, as a border rather than a fill.
					if absf(dx) <= 22.0 and absf(dy) <= 14.0 and (absf(dx) > 19.0 or absf(dy) > 11.0):
						image.set_pixel(x, y, edge)
				_:
					if absf(dx) <= 17.0 and absf(dy) <= 17.0:
						image.set_pixel(x, y, pigment)
						if absf(absf(dx) - absf(dy)) <= 1.4:
							image.set_pixel(x, y, edge)
	return image