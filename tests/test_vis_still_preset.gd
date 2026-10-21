extends Node
## Tests for the named still sizes: that the table agrees with its own numbers, and that
## "A3 at 300 dpi" means the pixels an A3 sheet is when it is printed.
##
## The point of the table is that nobody types 4961 by 3508 again, so the one thing worth
## asserting is that the numbers *are* the paper: the pixel size is recomputed from the
## millimetres and the resolution and must match the stored one.

const Preset := preload("res://scripts/vis/still_preset.gd")


func test_the_order_lists_every_preset_once() -> void:
	var names := Preset.names()
	assert(names.size() == Preset.SIZES.size(), "the order must name every preset")
	for name in names:
		assert(Preset.SIZES.has(name), "%s is in the order but not the table" % name)
	var seen: Array[StringName] = []
	for name in names:
		assert(not seen.has(name), "%s is listed twice" % name)
		seen.append(name)


func test_every_preset_carries_its_four_numbers() -> void:
	for name in Preset.names():
		var entry: Dictionary = Preset.preset(name)
		for key in ["label", "px", "dpi", "mm"]:
			assert(entry.has(key), "%s is missing its %s" % [name, key])
		assert(String(entry["label"]) != "", "%s has no label" % name)
		assert(Preset.size(name).x > 0 and Preset.size(name).y > 0, "%s has no size" % name)
		assert(Preset.dpi(name) > 0.0, "%s has no resolution" % name)
		assert(Preset.paper_mm(name).x > 0.0, "%s has no paper" % name)


func test_the_pixels_are_the_paper_at_its_resolution() -> void:
	for name in Preset.names():
		var worked: Vector2i = Preset.pixels_for_paper(Preset.paper_mm(name), Preset.dpi(name))
		var stored: Vector2i = Preset.size(name)
		# A millimetre rounded to a tenth cannot land exactly on the pixel count, so the
		# two agree to within one pixel on each axis rather than exactly.
		assert(absi(worked.x - stored.x) <= 1, "%s: %s px is not %s mm at %s dpi" % [
			name, stored, Preset.paper_mm(name), Preset.dpi(name),
		])
		assert(absi(worked.y - stored.y) <= 1, "%s: height does not agree" % name)


func test_a3_at_three_hundred_prints_on_a3() -> void:
	assert(Preset.size(&"a3_300") == Vector2i(4961, 3508), "A3 at 300 dpi is 4961 x 3508 px")
	assert(Preset.paper_mm(&"a3_300") == Vector2(420.0, 297.0), "A3 is 420 x 297 mm")
	assert(is_equal_approx(Preset.dpi(&"a3_300"), 300.0), "A3 at 300 dpi is 300 dpi")


func test_the_render_size_is_the_output_supersampled() -> void:
	var render: Vector2i = Preset.render_size(&"hd", 2)
	assert(render == Vector2i(3840, 2160), "a 1080p still renders at 4K, got %s" % render)
	# A supersample of one is no supersample: the render *is* the output.
	assert(Preset.render_size(&"hd", 1) == Preset.size(&"hd"), "one is the output size")
	# A factor below one cannot make a bigger picture than the one asked for.
	assert(Preset.render_size(&"hd", 0) == Preset.size(&"hd"), "a factor of nothing is one")


func test_a_name_nobody_has_gives_nothing_and_says_so() -> void:
	assert(not Preset.has(&"poster"))
	assert(Preset.preset(&"poster").is_empty())
	assert(Preset.size(&"poster") == Vector2i.ZERO)
	assert(Preset.paper_mm(&"poster") == Vector2.ZERO)
	assert(Preset.dpi(&"poster") == 0.0)
	# A label falls back to the name, which is what a picker shows for an unknown one.
	assert(Preset.label(&"poster") == "poster", "an unknown preset reads as its own name")
	assert(Preset.describe(&"poster").contains("poster"), "describe names the unknown size")


func test_a_string_is_the_same_preset_as_a_string_name() -> void:
	assert(Preset.has("a3_300"), "a string names a preset")
	assert(Preset.size("a3_300") == Preset.size(&"a3_300"), "the two forms agree")


func test_the_proposal_default_is_a_preset_that_exists() -> void:
	assert(Preset.has(Preset.PROPOSAL_DEFAULT), "the proposal default must exist")


func test_no_paper_and_no_resolution_work_out_to_no_pixels() -> void:
	assert(Preset.pixels_for_paper(Vector2.ZERO, 300.0) == Vector2i.ZERO)
	assert(Preset.pixels_for_paper(Vector2(100, 100), 0.0) == Vector2i.ZERO)