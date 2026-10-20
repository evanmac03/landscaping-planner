extends Node
## Tests for the pen table: the palette, slot lookup, resolution against a
## practice's pens, and persistence.

const Style := preload("res://scripts/draft/plot_style_table.gd")
const LineStyle := preload("res://scripts/draft/line_style.gd")
const LayerSet := preload("res://scripts/draft/layer_set.gd")


func _close(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.005 and absf(a.g - b.g) < 0.005 and absf(a.b - b.b) < 0.005


func test_the_named_slots_are_the_conventional_colours() -> void:
	assert(Style.slot_colour(Style.SLOT_RED).is_equal_approx(Color(1, 0, 0)))
	assert(Style.slot_colour(Style.SLOT_YELLOW).is_equal_approx(Color(1, 1, 0)))
	assert(Style.slot_colour(Style.SLOT_GREEN).is_equal_approx(Color(0, 1, 0)))
	assert(Style.slot_colour(Style.SLOT_CYAN).is_equal_approx(Color(0, 1, 1)))
	assert(Style.slot_colour(Style.SLOT_BLUE).is_equal_approx(Color(0, 0, 1)))
	assert(Style.slot_colour(Style.SLOT_MAGENTA).is_equal_approx(Color(1, 0, 1)))


## The generated families are not an approximation. These are the canonical
## values, so a slot read out of an old standard still means the colour it did.
func test_the_generated_families_reproduce_the_canonical_values() -> void:
	assert(_close(Style.slot_colour(10), Color(1, 0, 0)))
	assert(_close(Style.slot_colour(11), Color(1, 0.5, 0.5)))
	assert(_close(Style.slot_colour(12), Color(0.8, 0, 0)))
	assert(_close(Style.slot_colour(19), Color(76.0 / 255.0, 38.0 / 255.0, 38.0 / 255.0)))
	# The next family starts at 15 degrees round the wheel.
	assert(_close(Style.slot_colour(20), Color(1, 63.0 / 255.0, 0)))
	var table = Style.empty_table()
	assert(table.is_slot(1))
	assert(table.is_slot(255))
	assert(not table.is_slot(0))
	assert(not table.is_slot(256))


func test_the_grey_ramp() -> void:
	assert(_close(Style.slot_colour(250), Color(51.0 / 255.0, 51.0 / 255.0, 51.0 / 255.0)))
	assert(_close(Style.slot_colour(255), Color(1, 1, 1)))
	for slot in range(250, 256):
		var colour: Color = Style.slot_colour(slot)
		assert(is_equal_approx(colour.r, colour.g))
		assert(is_equal_approx(colour.g, colour.b))


## Every palette colour has to find a slot holding the same colour. If it does
## not, the table is quietly mis-resolving colours, which stays invisible until a
## drawing plots with the wrong pen.
func test_every_palette_colour_resolves_to_the_same_colour() -> void:
	var table = Style.empty_table()
	for slot in range(1, Style.SLOT_COUNT + 1):
		var colour: Color = Style.slot_colour(slot)
		var found: int = table.slot_for_colour(colour)
		assert(Style.slot_colour(found).is_equal_approx(colour))


## Six hues and white are in the palette twice: the named slot and the first
## shade of its generated family are the same value, so slot 1 and slot 10 are
## both red. One of them has to win, and the named slot does, because the scan
## runs in ascending order. That is exactly what lets a layer declare itself as
## colour 1 and pick up a pen table's red pen rather than landing on colour 10,
## which no pen table assigns.
func test_a_duplicated_colour_resolves_to_the_named_slot() -> void:
	var table = Style.empty_table()
	assert(table.slot_for_colour(Color(1, 0, 0)) == Style.SLOT_RED)
	assert(table.slot_for_colour(Color(1, 1, 0)) == Style.SLOT_YELLOW)
	assert(table.slot_for_colour(Color(0, 1, 0)) == Style.SLOT_GREEN)
	assert(table.slot_for_colour(Color(0, 1, 1)) == Style.SLOT_CYAN)
	assert(table.slot_for_colour(Color(0, 0, 1)) == Style.SLOT_BLUE)
	assert(table.slot_for_colour(Color(1, 0, 1)) == Style.SLOT_MAGENTA)
	assert(table.slot_for_colour(Color(1, 1, 1)) == Style.SLOT_WHITE)


func test_a_near_colour_finds_the_nearest_slot() -> void:
	var table = Style.empty_table()
	assert(table.slot_for_colour(Color(0.98, 0.02, 0.02)) == Style.SLOT_RED)
	assert(table.slot_for_colour(Color(0.02, 0.98, 0.02)) == Style.SLOT_GREEN)


## The reason the layer palette uses the exact standard values: every preset
## layer's colour must be a slot the default table actually has a pen for, or
## the default table would silently apply to nothing.
func test_every_preset_layer_resolves_to_a_pen() -> void:
	var layers = LayerSet.default_set()
	var table = Style.default_table()
	assert(layers.size() > 0)
	for layer_name: StringName in layers.names():
		var layer = layers.get_layer(layer_name)
		var slot: int = table.slot_for_colour(layer.screen_colour)
		assert(table.has_entry(slot))


func test_resolution_prefers_the_pen_and_falls_back_without_one() -> void:
	var table = Style.default_table()
	var fallback := LineStyle.new()
	fallback.plot_weight_mm = 0.99

	var pen = table.resolve_for(Color(1, 0, 0), fallback)
	assert(pen != fallback)
	assert(is_equal_approx(pen.plot_weight_mm, 0.50))

	# Slot 100 is in the generated families and has no pen, so the entity keeps
	# its own style rather than plotting with nothing.
	var stranger = table.resolve_for(Style.slot_colour(100), fallback)
	assert(stranger == fallback)


func test_disabling_the_table_uses_the_entity_style() -> void:
	var table = Style.default_table()
	var fallback := LineStyle.new()
	table.enabled = false
	assert(table.resolve_for(Color(1, 0, 0), fallback) == fallback)
	table.enabled = true
	assert(table.resolve_for(Color(1, 0, 0), fallback) != fallback)


func test_the_default_table_has_a_hierarchy_of_weights() -> void:
	var table = Style.default_table()
	# Boundary and structures heaviest, traces and text finest.
	assert(is_equal_approx(table.entry(Style.SLOT_BLUE).plot_weight_mm, 0.70))
	assert(is_equal_approx(table.entry(Style.SLOT_RED).plot_weight_mm, 0.50))
	assert(is_equal_approx(table.entry(Style.SLOT_CYAN).plot_weight_mm, 0.18))
	var heaviest := 0.0
	var lightest := INF
	for slot: int in table.slots():
		heaviest = maxf(heaviest, table.entry(slot).plot_weight_mm)
		lightest = minf(lightest, table.entry(slot).plot_weight_mm)
	assert(heaviest > lightest * 3.0)


func test_entries_can_be_set_and_removed() -> void:
	var table = Style.empty_table()
	assert(table.size() == 0)
	# Slot 0 means "by block" and 256 does not exist, so neither is a pen.
	assert(not table.set_entry(0, LineStyle.new()))
	assert(not table.set_entry(256, LineStyle.new()))
	assert(not table.set_entry(5, null))
	assert(table.set_entry(5, LineStyle.new()))
	assert(table.has_entry(5))
	assert(table.size() == 1)
	assert(table.remove_entry(5))
	assert(table.size() == 0)
	assert(not table.remove_entry(5))


func test_slots_come_back_in_order() -> void:
	var table = Style.empty_table()
	table.set_entry(200, LineStyle.new())
	table.set_entry(3, LineStyle.new())
	table.set_entry(50, LineStyle.new())
	var ordered: Array[int] = table.slots()
	assert(ordered.size() == 3)
	assert(ordered[0] == 3)
	assert(ordered[1] == 50)
	assert(ordered[2] == 200)


func test_a_copy_is_independent() -> void:
	var table = Style.default_table()
	var other = table.copy()
	assert(other.entry(Style.SLOT_RED) != table.entry(Style.SLOT_RED))
	var original = table.entry(Style.SLOT_RED)
	original.plot_weight_mm = 9.0
	assert(not is_equal_approx(other.entry(Style.SLOT_RED).plot_weight_mm, 9.0))


func test_persistence_round_trip() -> void:
	var table = Style.default_table()
	table.name = "Storm Landscapes standard"
	var restored = Style.from_dict(table.to_dict())
	assert(restored.name == "Storm Landscapes standard")
	assert(restored.enabled)
	assert(restored.size() == table.size())
	for slot: int in table.slots():
		assert(restored.has_entry(slot))
		assert(is_equal_approx(
			restored.entry(slot).plot_weight_mm, table.entry(slot).plot_weight_mm
		))
		assert(restored.entry(slot).linetype == table.entry(slot).linetype)
	assert(restored.entry(Style.SLOT_BLUE).plot_colour.is_equal_approx(Color.BLACK))


func test_loading_a_table_ignores_impossible_slots() -> void:
	var restored = Style.from_dict({
		"name": "Damaged",
		"enabled": false,
		"pens": {"0": {"plot_weight_mm": 1.0}, "7": {"plot_weight_mm": 0.25}},
	})
	assert(restored.size() == 1)
	assert(restored.has_entry(Style.SLOT_WHITE))
	assert(not restored.enabled)


func test_describe_names_the_table_and_its_pens() -> void:
	var table = Style.default_table()
	assert(table.name != "")
	assert(table.describe().contains("pens"))
	assert(table.describe().contains("enabled"))