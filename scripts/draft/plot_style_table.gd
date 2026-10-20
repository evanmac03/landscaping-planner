class_name DraftPlotStyleTable
extends RefCounted
## A colour-dependent plot style table: a pen table.
##
## Landscape practices have plotted this way for decades. Every entity carries a
## colour slot, and the slot decides how it comes out on paper — the pen's width
## and colour, not the layer. A practice that already has pen assignments must be
## able to keep them, which is why this is keyed by slot rather than by layer.
##
## Slots follow the conventional colour index. 1 to 9 are the named colours
## every CAD user knows, 250 to 255 are the greys, and 10 to 249 are the
## generated families in between. The generation is not a guess: it reproduces
## the canonical values, so a slot loaded from an old standard still means the
## same colour it always did.
##
## Six hues and white are in the palette twice, because the named slot and the
## first shade of its generated family hold the same value: slot 1 and slot 10
## are both red. The named slot wins, and that is what lets a layer declare
## itself as colour 1 and pick up a standard red pen instead of landing on
## colour 10, which no pen table assigns.
##
## Screen colour and plot colour are deliberately separate concerns. Screens are
## colour-coded for legibility and sheets are usually monochrome, so resolving a
## plot colour out of a screen colour is the whole point of the table.

const LineStyleScript := preload("res://scripts/draft/line_style.gd")

## Slots run 1..255. Slot 0 means "by block" and is not a pen.
const SLOT_COUNT := 255

## The nine named slots, which is all most standards ever reference.
const SLOT_RED := 1
const SLOT_YELLOW := 2
const SLOT_GREEN := 3
const SLOT_CYAN := 4
const SLOT_BLUE := 5
const SLOT_MAGENTA := 6
const SLOT_WHITE := 7
const SLOT_DARK_GREY := 8
const SLOT_LIGHT_GREY := 9

## Slots 10..249 are 24 hue families of ten shades each. Within a family the
## shade alternates between full saturation and a half-saturated tint, and the
## value steps down this ladder.
const SHADE_VALUES := [255, 255, 204, 204, 153, 153, 127, 127, 76, 76]
const FAMILY_COUNT := 24
const HUE_STEP_DEGREES := 15.0
const FIRST_FAMILY_SLOT := 10

var name: String = "Default pen table"
## When off, every entity plots with its own layer's style and the table is
## ignored entirely.
var enabled: bool = true

var _entries: Dictionary = {}
var _palette: Dictionary = {}
var _nearest: Dictionary = {}


static func _new() -> DraftPlotStyleTable:
	return (load("res://scripts/draft/plot_style_table.gd") as GDScript).new()


func _init() -> void:
	_build_palette()


static func empty_table() -> DraftPlotStyleTable:
	return _new()


## The table a new document starts with. Conventional landscape weights: the
## heaviest pen on the boundary and structures, the finest on traces and text.
static func default_table() -> DraftPlotStyleTable:
	var table := _new()
	table.name = "Default landscape pen table"
	table.set_entry(SLOT_RED, table._pen(Color.BLACK, 0.50, &"continuous"))
	table.set_entry(SLOT_YELLOW, table._pen(Color.BLACK, 0.25, &"continuous"))
	table.set_entry(SLOT_GREEN, table._pen(Color.BLACK, 0.35, &"continuous"))
	table.set_entry(SLOT_CYAN, table._pen(Color.BLACK, 0.18, &"continuous"))
	table.set_entry(SLOT_BLUE, table._pen(Color.BLACK, 0.70, &"continuous"))
	table.set_entry(SLOT_MAGENTA, table._pen(Color.BLACK, 0.35, &"dashed"))
	table.set_entry(SLOT_WHITE, table._pen(Color.BLACK, 0.25, &"continuous"))
	table.set_entry(SLOT_DARK_GREY, table._pen(Color.BLACK, 0.13, &"continuous"))
	table.set_entry(SLOT_LIGHT_GREY, table._pen(Color.BLACK, 0.13, &"dotted"))
	# The grey ramp, which is where greys that are not declared as one of the
	# named colours land.
	for slot in range(250, 256):
		table.set_entry(slot, table._pen(Color.BLACK, 0.13, &"continuous"))
	return table


func _pen(colour: Color, weight_mm: float, linetype: StringName) -> LineStyleScript:
	var style := LineStyleScript.new()
	style.plot_colour = colour
	style.plot_weight_mm = weight_mm
	style.linetype = linetype
	return style


# --- the palette --------------------------------------------------------------------


func _build_palette() -> void:
	_palette.clear()
	for slot in range(1, SLOT_COUNT + 1):
		_palette[slot] = _slot_colour(slot)


## The colour a slot stands for.
static func slot_colour(slot: int) -> Color:
	if slot == SLOT_RED:
		return Color(1, 0, 0)
	if slot == SLOT_YELLOW:
		return Color(1, 1, 0)
	if slot == SLOT_GREEN:
		return Color(0, 1, 0)
	if slot == SLOT_CYAN:
		return Color(0, 1, 1)
	if slot == SLOT_BLUE:
		return Color(0, 0, 1)
	if slot == SLOT_MAGENTA:
		return Color(1, 0, 1)
	if slot == SLOT_WHITE:
		return Color(1, 1, 1)
	if slot == SLOT_DARK_GREY:
		return Color(128.0 / 255.0, 128.0 / 255.0, 128.0 / 255.0)
	if slot == SLOT_LIGHT_GREY:
		return Color(192.0 / 255.0, 192.0 / 255.0, 192.0 / 255.0)
	if slot >= 250:
		# The six-step grey ramp, from near-black to white.
		var level := 51.0 + float(slot - 250) * 41.0
		level = minf(level, 255.0)
		return Color(level / 255.0, level / 255.0, level / 255.0)
	if slot >= FIRST_FAMILY_SLOT:
		var index := slot - FIRST_FAMILY_SLOT
		var family := index / 10
		var shade := index % 10
		if family >= FAMILY_COUNT:
			return Color.WHITE
		var value := float(SHADE_VALUES[shade]) / 255.0
		# Even shades are full strength, odd shades are the same hue at half
		# saturation, which is what produces the alternating pairs.
		var saturation := 1.0 if shade % 2 == 0 else 0.5
		return Color.from_hsv(float(family) * HUE_STEP_DEGREES / 360.0, saturation, value)
	return Color.WHITE


func _slot_colour(slot: int) -> Color:
	return slot_colour(slot)


func palette_colour(slot: int) -> Color:
	return _palette.get(slot, Color.WHITE)


func is_slot(slot: int) -> bool:
	return slot >= 1 and slot <= SLOT_COUNT


## The slot a screen colour belongs to, by nearest palette colour. This is how a
## layer whose colour was chosen for the screen finds its pen.
func slot_for_colour(colour: Color) -> int:
	var key := colour.to_html(false)
	if _nearest.has(key):
		return _nearest[key]
	var best := SLOT_WHITE
	var best_distance := INF
	for slot in range(1, SLOT_COUNT + 1):
		var candidate: Color = _palette[slot]
		var distance := (candidate.r - colour.r) * (candidate.r - colour.r) \
			+ (candidate.g - colour.g) * (candidate.g - colour.g) \
			+ (candidate.b - colour.b) * (candidate.b - colour.b)
		if distance < best_distance:
			best_distance = distance
			best = slot
	_nearest[key] = best
	return best


# --- entries ------------------------------------------------------------------------


func set_entry(slot: int, style: LineStyleScript) -> bool:
	if not is_slot(slot) or style == null:
		return false
	_entries[slot] = style
	return true


func entry(slot: int) -> LineStyleScript:
	return _entries.get(slot, null)


func has_entry(slot: int) -> bool:
	return _entries.has(slot)


func remove_entry(slot: int) -> bool:
	return _entries.erase(slot)


func size() -> int:
	return _entries.size()


func slots() -> Array[int]:
	var out: Array[int] = []
	for slot: int in _entries:
		out.append(slot)
	out.sort()
	return out


## The style an entity with this screen colour plots with. Falls back to the
## entity's own style when the table is off or has no pen for that slot, so a
## colour nobody assigned a pen to still plots rather than vanishing.
func resolve_for(colour: Color, fallback: LineStyleScript) -> LineStyleScript:
	if not enabled:
		return fallback
	var style: LineStyleScript = _entries.get(slot_for_colour(colour), null)
	return style if style != null else fallback


func copy() -> DraftPlotStyleTable:
	var other := _new()
	other.name = name
	other.enabled = enabled
	for slot: int in _entries:
		other._entries[slot] = _entries[slot].copy()
	return other


func describe() -> String:
	return "%s, %d pens, %s" % [name, _entries.size(), "enabled" if enabled else "disabled"]


# --- persistence --------------------------------------------------------------------


## A practice's standard table, small enough to keep in the project as JSON.
func to_dict() -> Dictionary:
	var pens: Dictionary = {}
	for slot: int in _entries:
		var style: LineStyleScript = _entries[slot]
		pens[str(slot)] = {
			"plot_colour": style.plot_colour.to_html(false),
			"plot_weight_mm": style.plot_weight_mm,
			"linetype": String(style.linetype),
		}
	return {"name": name, "enabled": enabled, "pens": pens}


static func from_dict(data: Dictionary) -> DraftPlotStyleTable:
	var table := _new()
	table.name = String(data.get("name", "Pen table"))
	table.enabled = bool(data.get("enabled", true))
	var pens: Dictionary = data.get("pens", {})
	for key in pens:
		var slot := int(key)
		if not table.is_slot(slot):
			continue
		var entry_data: Dictionary = pens[key]
		table.set_entry(slot, table._pen(
			Color.html(String(entry_data.get("plot_colour", "000000"))),
			float(entry_data.get("plot_weight_mm", 0.25)),
			StringName(entry_data.get("linetype", "continuous"))
		))
	return table