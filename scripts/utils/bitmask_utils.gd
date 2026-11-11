class_name BitMaskUtils
extends RefCounted
## The capture side's conversions between a stated figure and the bit masks `PlantSpecies` stores:
## hours of daylight into the sun mask, and a list of eaten parts into the edible mask.
##
##     BitMaskUtils.sun_hours_to_bitmask(6.0)     # -> the full-sun bit
##     BitMaskUtils.parse_edible_parts(["leaf"])  # -> the leaf bit
##
## The bit values themselves are not defined here: every one is **aliased from `PlantSpecies`**, which
## is where the model's own constants live, so this table cannot drift away from the model. The names
## beginning `SUN_`/`DRAIN_` are the same values under the spelling the capture side reads.
##
## **Nothing stated is zero, and zero is not a value.** A record that says nothing about the sun, or
## names no part of the plant as edible, converts to `0` - which every part of this program already
## reads as "not stated". There is deliberately no conservative default: a converter that answered
## `FULL_SUN` for an unstated figure, or `EDIBLE_ANY` for a plant whose parts nobody listed, would
## invent a fact about somebody's garden and hand it to the checks as though a person had stated it.

# The model's own bit values, under the names this module's caller reads. They are
# aliased from PlantSpecies, which is where they are defined, so this table cannot
# drift from the model's.
const FULL_SUN := PlantSpecies.FULL_SUN
const PART_SHADE := PlantSpecies.PART_SHADE
const FULL_SHADE := PlantSpecies.FULL_SHADE
const DRAINS_FAST := PlantSpecies.DRAINS_FAST
const DRAINS_MEDIUM := PlantSpecies.DRAINS_MEDIUM
const DRAINS_SLOW := PlantSpecies.DRAINS_SLOW
const DRAINS_ANY := PlantSpecies.DRAINS_ANY
const EAT_LEAF := PlantSpecies.EAT_LEAF
const EAT_FRUIT := PlantSpecies.EAT_FRUIT
const EAT_ROOT := PlantSpecies.EAT_ROOT
const EAT_BULB := PlantSpecies.EAT_BULB
const EAT_STEM := PlantSpecies.EAT_STEM
const EAT_FLOWER := PlantSpecies.EAT_FLOWER
const EAT_SEED := PlantSpecies.EAT_SEED
const EDIBLE_ANY := PlantSpecies.EDIBLE_ANY

# The spelling the field-capture side reads.
const SUN_FULL_SUN := FULL_SUN
const SUN_PART_SHADE := PART_SHADE
const SUN_FULL_SHADE := FULL_SHADE
const DRAIN_FAST := DRAINS_FAST
const DRAIN_MEDIUM := DRAINS_MEDIUM
const DRAIN_SLOW := DRAINS_SLOW
const DRAIN_ANY := DRAINS_ANY

# Hours of direct sun a day at which each tolerance starts.
const HOURS_FULL_SUN := 6.0
const HOURS_ALL_DAY := 12.0


## Names of the parts eaten -> the `edible_parts` mask, in `PlantSpecies`'s own bits.
##
## An empty list, or one naming nothing this knows, is `0`: a plant whose edible parts nobody wrote
## down is not known to be edible, and answering `EDIBLE_ANY` would claim every part of it from root to
## seed. That is the whole reason this returns nothing rather than something generous.
##
## The words are `PlantSpecies.EDIBLE_NAMES`' own, with a trailing "s" allowed so a phone's typist can
## write "fruits", so there is one vocabulary and this cannot disagree with
## `PlantSpecies.edible_parts_text()`.
static func parse_edible_parts(parts: Array) -> int:
	var mask: int = 0
	for part: Variant in parts:
		var word: String = String(part).to_lower().strip_edges()
		if word.is_empty():
			continue
		for bit: int in PlantSpecies.EDIBLE_NAMES:
			var named: String = String(PlantSpecies.EDIBLE_NAMES[bit]).to_lower()
			if word == named or word == named + "s":
				mask |= bit
	return mask

## Hours of direct sun a day -> the `sun` mask. Seven hours takes full sun; four and
## a half is part shade; nothing stated is zero.
static func sun_hours_to_bitmask(hours: float) -> int:
	if hours <= 0.0:
		return 0
	if hours >= HOURS_ALL_DAY:
		return SUN_FULL_SUN | SUN_PART_SHADE | SUN_FULL_SHADE
	if hours >= HOURS_FULL_SUN:
		return SUN_FULL_SUN | SUN_PART_SHADE
	return SUN_PART_SHADE | SUN_FULL_SHADE


## The same, when the figure is stored the way PlantSpecies stores it: tenths of an
## hour (60 = 6.0 h).
static func sun_tenths_to_bitmask(tenths: int) -> int:
	return sun_hours_to_bitmask(float(tenths) / 10.0)


