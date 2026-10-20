extends Node
## The pictures of plants: the swatch a species with no photograph is drawn as, and the tint that
## tells one species from another.
##
## Shared by the browser and by the palette's plants section, so these are the tests that hold the
## *picture* to the plan it is drawn from: a swatch that stopped being the plan's symbol would be a
## plant that looks like one thing while being planted as another.

const CatalogueScript := preload("res://scripts/plant_catalogue.gd")
const PlanStyleScript := preload("res://scripts/plan_style.gd")

const SEED := "res://data/plants/nursery_list.json"

const MAPLE := &"acer-rubrum-autumn-blaze"
const BOXWOOD := &"buxus-sempervirens"
const RUDBECKIA := &"rudbeckia-fulgida-goldsturm"


func _catalogue() -> PlantCatalogue:
	var read: Dictionary = CatalogueScript.load_from(SEED)
	assert(bool(read["ok"]), "the shipped list loads: %s" % String(read["reason"]))
	return read["catalogue"]


## Whether two colours are the same picture colour. The swatch is stored eight bits a channel, so a
## colour that was never quantised does not compare equal to the one that comes back.
func _nearly(first: Color, second: Color) -> bool:
	return absf(first.r - second.r) < 0.01 and absf(first.g - second.g) < 0.01 \
		and absf(first.b - second.b) < 0.01


## How many pixels of a swatch have anything in them. Every byte, because a picture can be wrong in a
## way that one sampled pixel cannot see.
func _opaque_pixels(image: Image) -> int:
	var count: int = 0
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.0:
				count += 1
	return count


# --- the swatch ---------------------------------------------------------------------------


func test_a_swatch_is_the_pigment_the_painted_plan_would_use() -> void:
	# The swatch reads `PlanStyle`, so it cannot show a plant as one colour and paint it another.
	var catalogue: PlantCatalogue = _catalogue()
	var maple: Image = PlantIcons.swatch(catalogue.get_species(MAPLE))
	assert(maple.get_size() == Vector2i(PlantIcons.PIXELS, PlantIcons.PIXELS), "at the swatch size")
	var middle: Color = maple.get_pixel(int(PlantIcons.HALF), int(PlantIcons.HALF))
	assert(middle.a > 0.5, "the middle of the swatch is drawn")
	var pigment: Color = PlanStyleScript.spec_for(catalogue.get_species(MAPLE).form)["wash"]
	# `_nearly`, because the swatch is stored eight bits a channel and the colour it was drawn from
	# was never quantised.
	assert(_nearly(middle, pigment.darkened(0.45)) or _nearly(middle, pigment),
		"and it is the plan's own pigment, or its edge: %s" % str(middle))


func test_a_swatch_is_not_blank_and_not_a_solid_square() -> void:
	# Two failures a single sampled pixel would miss: nothing drawn at all, and one flat fill.
	var catalogue: PlantCatalogue = _catalogue()
	var total: int = PlantIcons.PIXELS * PlantIcons.PIXELS
	for id: StringName in catalogue.ids():
		var image: Image = PlantIcons.swatch(catalogue.get_species(id))
		var drawn: int = _opaque_pixels(image)
		assert(drawn > 0, "%s is drawn" % id)
		assert(drawn < total, "%s is not one solid square" % id)


func test_a_bed_is_an_oblong_and_a_canopy_is_a_disc() -> void:
	# A difference you can find in the picture: directly above the centre, a bed's short side has
	# already ended and a tree's canopy has not.
	var catalogue: PlantCatalogue = _catalogue()
	var maple: Image = PlantIcons.swatch(catalogue.get_species(MAPLE))
	var bed: Image = PlantIcons.swatch(catalogue.get_species(RUDBECKIA))
	var centre: int = PlantIcons.PIXELS / 2
	assert(bed.get_pixel(centre, 12).a < 0.5, "a bed is empty above its own centre")
	assert(maple.get_pixel(centre, 12).a >= 0.5, "a canopy is not")
	assert(bed.get_pixel(centre, centre).a >= 0.5, "and the bed is filled where a bed is")
	# And the two are genuinely different pictures rather than one marker for everything, which is
	# the whole reason the swatch is drawn from the plan's own table.
	assert(bed.get_pixel(centre, 12) != maple.get_pixel(centre, 12), "a bed is not a canopy")


# --- one picture per prop, and the tint ---------------------------------------------------


func test_the_same_prop_in_the_same_category_is_one_picture() -> void:
	# The cache is keyed by form and category: seventeen species drawn as three props make three
	# pictures, and four thousand make thirty. A texture made twice is a buffer paid for twice.
	PlantIcons.clear_cache()
	var catalogue: PlantCatalogue = _catalogue()
	var first: Texture2D = PlantIcons.texture_for(catalogue.get_species(MAPLE))
	assert(first != null, "a tree has a picture")
	assert(PlantIcons.texture_for(catalogue.get_species(MAPLE)) == first,
		"asking twice gives the same picture")
	# The birch is drawn as the same form in the same category, so it shares it.
	assert(PlantIcons.texture_for(catalogue.get_species(&"betula-papyrifera")) == first,
		"another tree shares it")
	# A bed is a different form, so it is a different picture.
	assert(PlantIcons.texture_for(catalogue.get_species(RUDBECKIA)) != first,
		"a bed is its own picture")
	PlantIcons.clear_cache()
	assert(PlantIcons.texture_for(catalogue.get_species(MAPLE)) != first,
		"and clearing the cache really clears it")


func test_the_tint_is_the_bloom_colour_and_a_foliage_plant_has_none() -> void:
	var catalogue: PlantCatalogue = _catalogue()
	var tinted: Color = PlantIcons.tint(catalogue.get_species(MAPLE))
	assert(tinted != Color.WHITE, "a flowering tree is tinted")
	# Held towards white, so the pigment underneath still reads as foliage.
	assert(tinted.r > catalogue.get_species(MAPLE).bloom_colour.r, "and the tint is a tint, not a fill")
	assert(PlantIcons.tint(catalogue.get_species(BOXWOOD)) == Color.WHITE,
		"a plant grown for its foliage is not tinted")
	assert(PlantIcons.tint(null) == Color.WHITE, "and nothing at all is not tinted")


func test_a_species_the_catalogue_does_not_have_is_not_a_picture() -> void:
	var catalogue: PlantCatalogue = _catalogue()
	assert(PlantIcons.textured(catalogue, &"not-a-plant") == null, "an unknown id has no picture")
	assert(PlantIcons.textured(null, MAPLE) == null, "and neither has a plant with no catalogue")
	assert(PlantIcons.texture_for(null) == null, "nor a species that is not there")