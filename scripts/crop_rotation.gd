class_name CropRotation
extends RefCounted
## What a food crop should and should not be grown with: the family it follows, and the family it
## stands beside.
##
## `PlantSpecies` already carries the one field this needs - `family`, the group a crop rotates with -
## and until now nothing read it. A kitchen gardener asks two questions of it, and they are the whole
## of this module:
##
## * **In turn** - *the same family shall not follow itself in the same bed.* That is the law of crop
##   rotation in a sentence: a brassica after a brassica shares its pests and its diseases year on
##   year, so a bed wants a different family each time round. Everything else is a preference, and the
##   one preference worth stating is that a **legume** as the predecessor is a good thing - beans and
##   peas leave the ground richer than they found it, which is why they are planted into a rotation
##   rather than at its end.
## * **Together** - what a crop gets on with standing beside it. This is *companion planting*, and most
##   of it is convention rather than science, so the tables below are deliberately short and the module
##   says so: they hold the pairings a seed packet or a kitchen garden book would repeat, each one names
##   where it came from, and they claim no more than that. There are **two** of them - the *families* a
##   pairing groups together, and the *plants* a pairing names by name - and a named plant is read
##   before its family, because a herb is not one thing: the family row says a herb grows well beside a
##   nightshade, and fennel is the herb that does not. The section on the named pairings says why that
##   second table has to exist at all.
##
## The four verdicts are `PlantSuitability`'s - good, tolerated, wrong, unknown - borrowed rather than
## restated, so a rotation verdict and a suitability verdict and a sun verdict are the same four words
## in the same four colours wherever they meet on a page.
##
## **A question nobody answered is skipped, not answered.** A crop that names no family cannot be
## rotated and is not called good; a bed whose history nobody has stated leaves the turn unchecked;
## and a crop with nothing asked about it comes back **unknown**, never green - the same honesty
## `PlantSuitability` and `CropSun` keep, because a green ring for a check that never ran is the one
## answer this must not give.

const PlantSpeciesScript := preload("res://scripts/plant_species.gd")
const PlantSuitabilityScript := preload("res://scripts/plant_suitability.gd")

## The four verdicts, borrowed from the suitability check so there is one vocabulary and one set of
## colours in the whole program.
const GOOD := PlantSuitabilityScript.GOOD
const TOLERATED := PlantSuitabilityScript.TOLERATED
const UNSUITABLE := PlantSuitabilityScript.UNSUITABLE
const UNKNOWN := PlantSuitabilityScript.UNKNOWN

# --- the families -------------------------------------------------------------------------
#
# Re-exported so a caller building a bed's history or a crop's neighbour writes the family the same
# way the catalogue does, rather than reaching past this module into `PlantSpecies`.


const FAMILY_NONE := PlantSpeciesScript.FAMILY_NONE
const BRASSICA := PlantSpeciesScript.BRASSICA
const NIGHTSHADE := PlantSpeciesScript.NIGHTSHADE
const LEGUME := PlantSpeciesScript.LEGUME
const ALLIUM := PlantSpeciesScript.ALLIUM
const ROOT_CROP := PlantSpeciesScript.ROOT_CROP
const CUCURBIT := PlantSpeciesScript.CUCURBIT
const LEAFY := PlantSpeciesScript.LEAFY
const FRUITING := PlantSpeciesScript.FRUITING
const HERB_FAMILY := PlantSpeciesScript.HERB_FAMILY

## The families a bed can be rotated through, in the order the catalogue names them. A person choosing
## "what grew here last" is choosing one of these, or leaving it unstated.
const FAMILIES := [
	BRASSICA, NIGHTSHADE, LEGUME, ALLIUM, ROOT_CROP, CUCURBIT, LEAFY, FRUITING, HERB_FAMILY,
]

## The pairings that are **said to** grow well together: an unordered list, read as a symmetry so the
## table cannot disagree with itself about which way round a pairing goes.
##
## Deliberately short. Companion planting is a tradition carried on seed packets and in kitchen garden
## books, and the honest thing is to hold the pairings a person would recognise - the legume with the
## leafy and the brassica and the squash, the allium with the carrot, a herb among the fruiting crops -
## rather than to invent a matrix. Nothing here claims a yield.
const COMPANION_GOOD := [
	[LEGUME, LEAFY],
	[LEGUME, BRASSICA],
	[LEGUME, CUCURBIT],
	[LEGUME, ROOT_CROP],
	[LEGUME, NIGHTSHADE],
	[ALLIUM, ROOT_CROP],
	[ALLIUM, LEAFY],
	[BRASSICA, LEAFY],
	[BRASSICA, ROOT_CROP],
	[HERB_FAMILY, NIGHTSHADE],
	[HERB_FAMILY, CUCURBIT],
	[HERB_FAMILY, BRASSICA],
	[HERB_FAMILY, FRUITING],
	[HERB_FAMILY, LEAFY],
]

## The pairings that should be kept apart. One entry, and it is the one worth having: an **allium**
## stunts a **legume**, which is the companion pairing a gardener acts on rather than repeats.
const COMPANION_BAD := [
	[LEGUME, ALLIUM],
]


# --- the plants a pairing names -------------------------------------------------------------
#
# The table above groups; this one names. A **plant** with a plant, or a plant with a family, where it
# is the plant itself the tradition or the research names - and it is the layer the family table cannot
# be, because a herb is not one thing.
#
# Fennel is the case that proves the need: the tradition's own chart gives fennel as compatible with
# nothing, while the family row above says a herb grows well beside a nightshade. **A pairing that
# names a plant is read before one that names only its family**, so the named rule is the answer rather
# than a second opinion standing beside the first.
#
# And a plant with no family at all can still be a companion, which the family table can never reach:
# marigold is an ornamental, it rotates with nobody, and it is the best-stated companion in this file.
#
# Every entry says **how** it is known, and the two are not the same thing:
#
# * `NATURE_KNOWN` - a mechanism somebody has looked into and named: a chemical, an insect, a smell.
# * `NATURE_TRADITION` - what a seed packet repeats. Worth keeping, and worth saying so.
#
# A pairing is read **between plants somebody has named.** A crop the caller has given us only the
# family of is answered by the family table and by nothing here, which is what stops a rule about one
# plant from being read as a rule about every plant in the family it happens to sit in.

const NATURE_KNOWN := "known"
const NATURE_TRADITION := "tradition"

## Where a pairing came from. A companion table is a claim, and a claim with no author is the thing this
## project does not write: every entry below names one of these, and a test holds them to it.
const COMPANION_SOURCES := {
	&"ncat": {
		"title": "NCAT, Companion Planting & Botanical Pesticides",
		"note": "a chart compiled from traditional literature on companion planting",
	},
	&"psu": {
		"title": "Penn State Extension, Herbs Make Good Plant Partners and Companions",
		"note": "the mechanism, in its own words: an herb does not repel a pest, it confuses one - "
			+ "masking the crop's smell, or drawing in the insects that eat the pest",
	},
	&"wisc": {
		"title": "Wisconsin Horticulture, Root-Knot Nematode",
		"note": "the mechanism with the chemical named, and the reason it is a rotation",
	},
	&"msstate": {
		"title": "Mississippi State Extension, Nematode Control in the Home Garden",
		"note": "the practice: a solid bed of marigolds, not one beside a tomato",
	},
}

## The pairings that name a plant, with where each one came from.
##
## A side is one of `{"id": ...}` for a plant in the catalogue, `{"name": "..."}` for a plant named but
## not necessarily held - a rule can be right about a plant this list has not got yet - `{"family": ...}`
## for a group, or `{"any": true}` for "whatever is growing".
##
## `why` is why the pairing is said to hold, in the source's own terms, and it carries the limit as
## well as the claim: the marigold entry is the one mechanism in this file, and it says plainly that
## the mechanism is a season of the ground rather than a neighbour. `source` names one work or a list
## of them, and a test holds every one of those names to `COMPANION_SOURCES`.
##
## **One pairing, one entry.** Two entries about the same two plants would be two answers to one
## question, and the second would never be read.
const COMPANION_PLANTS := [
	{
		"a": {"id": &"tagetes-patula"},
		"b": {"any": true},
		"outcome": GOOD,
		"nature": NATURE_KNOWN,
		"source": [&"wisc", &"msstate"],
		"why": "its roots give off alpha-terthienyl, which is poisonous to the root-knot nematode and "
			+ "stops its eggs hatching - so it is given the ground for a season, as a solid bed of the "
			+ "French marigolds, rather than set here and there among the vegetables",
	},
	{
		"a": {"id": &"anethum-graveolens"},
		"b": {"family": BRASSICA},
		"outcome": GOOD,
		"nature": NATURE_KNOWN,
		"source": &"psu",
		"why": "dill, chamomile, hyssop and sage are recorded as putting the adult cabbageworm off "
			+ "laying its eggs on the brassicas - the herb confuses the moth rather than poisoning it",
	},
	{
		"a": {"id": &"anethum-graveolens"},
		"b": {"name": "Carrot"},
		"outcome": UNSUITABLE,
		"nature": NATURE_TRADITION,
		"source": &"ncat",
		"why": "the chart that gathers the tradition keeps dill away from carrot, and nothing in the "
			+ "research explains it - which is most of what a companion chart is",
	},
	{
		"a": {"id": &"ocimum-basilicum-genovese"},
		"b": {"family": NIGHTSHADE},
		"outcome": GOOD,
		"nature": NATURE_KNOWN,
		"source": &"psu",
		"why": "beside a tomato, basil masks the plant's own smell from the thrips that hunt it",
	},
	{
		"a": {"name": "Fennel"},
		"b": {"any": true},
		"outcome": UNSUITABLE,
		"nature": NATURE_TRADITION,
		"source": &"ncat",
		"why": "the chart that gathers the tradition gives it as compatible with nothing, so it is grown "
			+ "in a bed of its own - and it is the one plant a herb's family cannot speak for",
	},
]


# --- reading the pairings ------------------------------------------------------------------


## A plant as the pairings read it, so the page and the check cannot describe one plant two ways.
static func subject_of(plant: PlantSpecies) -> Dictionary:
	if plant == null:
		return {}
	var made: Dictionary = {"id": plant.id, "family": plant.family}
	made["name"] = plant.common_name
	made["botanical"] = plant.botanical_name
	return made


## A family as the pairings read it, for the caller that has a family and not a plant. Empty for a
## family of nothing, which is a plant nobody rotates rather than a family called nothing.
static func family_subject(family: StringName) -> Dictionary:
	if family.is_empty():
		return {}
	return {"family": family}


## Whether one side of a stated pairing is this plant. A side that names a family answers a subject with
## that family, one that names an id or a name answers a subject named that way, and `any` - whatever is
## growing - answers **only a subject that names a plant**, so a rule about one plant can never quietly
## become a rule about the whole family it sits in.
static func _side_fits(side: Dictionary, subject: Dictionary) -> bool:
	if subject.is_empty():
		return false
	if bool(side.get("any", false)):
		return not StringName(subject.get("id", &"")).is_empty() \
			or not String(subject.get("name", "")).strip_edges().is_empty()
	var wanted_id: StringName = StringName(side.get("id", &""))
	if not wanted_id.is_empty():
		return StringName(subject.get("id", &"")) == wanted_id
	var wanted_name: String = String(side.get("name", ""))
	if not wanted_name.is_empty():
		return _same_plant_name(wanted_name, subject)
	var wanted_family: StringName = StringName(side.get("family", &""))
	if not wanted_family.is_empty():
		return StringName(subject.get("family", &"")) == wanted_family
	return false


## A name matches the common name or the botanical name, folded and trimmed: "Fennel", "fennel" and
## "Foeniculum vulgare" are one plant, and a rule about it should not miss because of a capital letter.
static func _same_plant_name(wanted: String, subject: Dictionary) -> bool:
	var needle: String = wanted.strip_edges().to_lower()
	if needle.is_empty():
		return false
	return String(subject.get("name", "")).strip_edges().to_lower() == needle \
		or String(subject.get("botanical", "")).strip_edges().to_lower() == needle


## How exactly a side states what it means: a plant by name or id (2) beats a family (1) beats "whatever
## is growing" (0). The most exactly-stated pairing about a plant is the one that is reported.
static func _side_weight(side: Dictionary) -> int:
	if not StringName(side.get("id", &"")).is_empty():
		return 2
	if not String(side.get("name", "")).strip_edges().is_empty():
		return 2
	if not StringName(side.get("family", &"")).is_empty():
		return 1
	return 0


## The family table read as a pairing, so there is one shape of answer whether the rule came from a
## named plant or from a family. Empty when the family table states nothing about the two - which is
## most pairs, and passing them over is right: this is not a place to invent an opinion about
## everything, only to report one somebody has written down.
static func _family_pair(first: Dictionary, second: Dictionary) -> Dictionary:
	var mine: StringName = StringName(first.get("family", &""))
	var other: StringName = StringName(second.get("family", &""))
	if mine.is_empty() or other.is_empty() or mine == other:
		return {}
	var outcome: int = UNKNOWN
	if _has_pair(COMPANION_BAD, mine, other):
		outcome = UNSUITABLE
	elif _has_pair(COMPANION_GOOD, mine, other):
		outcome = GOOD
	else:
		return {}
	return {
		"a": {"family": mine},
		"b": {"family": other},
		"outcome": outcome,
		"nature": NATURE_TRADITION,
		"source": &"ncat",
		"why": "",
	}


## The stated pairing between two plants, as the most exactly-stated one that fits both. Empty when
## nobody has stated one.
##
## **A pairing that names a plant is read before one that names only its family.** That single rule is
## what lets a named plant contradict its own family row and win, which is the whole difference between
## a table that can learn something about one plant and one that can only repeat its family.
##
## Where two pairings are equally exact - marigold goes with whatever is growing, and fennel goes with
## nothing - the order is decided rather than left to the order they were written in: the pairing that
## names **this** plant is read before one that merely permits it, and a warning is read before an
## encouragement. That last is the verdict's own rule, where something against the crop outranks
## something for it, and it is the reason a bean is told to keep away from fennel.
static func company_pair(first: Dictionary, second: Dictionary) -> Dictionary:
	var best: Dictionary = {}
	var best_score: int = 0
	for pair: Dictionary in COMPANION_PLANTS:
		var a: Dictionary = pair["a"]
		var b: Dictionary = pair["b"]
		var fits: bool = (_side_fits(a, first) and _side_fits(b, second)) \
			or (_side_fits(b, first) and _side_fits(a, second))
		if not fits:
			continue
		var score: int = _pair_score(pair, first)
		if score > best_score:
			best_score = score
			best = pair
	var group: Dictionary = _family_pair(first, second)
	if best.is_empty():
		return group
	if _side_weight(best["a"]) < 2 and _side_weight(best["b"]) < 2:
		return group
	return best


## How good a fit a pairing is, as one number so the comparison is in one place: how exactly the pairing
## states itself (a plant beats a family), then how exactly it names **this** plant, then whether it is
## a warning. Higher wins; a tie between two pairings that fit the same two plants is then impossible
## unless they are the same pairing, which is a thing the table is not allowed to do.
static func _pair_score(pair: Dictionary, subject: Dictionary) -> int:
	var weight: int = maxi(_side_weight(pair["a"]), _side_weight(pair["b"]))
	var on_subject: int = _naming_weight(pair, subject)
	var caution: int = 1 if int(pair.get("outcome", UNKNOWN)) == UNSUITABLE else 0
	return weight * 100 + on_subject * 10 + caution


## A plant as a sentence names it: its common name, else its family, else nothing. The one place the
## pairings turn a subject back into words, so the line and the finding cannot name it differently.
static func _name_of(subject: Dictionary) -> String:
	var named: String = String(subject.get("name", "")).strip_edges()
	if not named.is_empty():
		return named
	return family_words(StringName(subject.get("family", &"")))


## Where a pairing came from: the work's title, the titles of the works, or empty for an id nobody has
## written down - a table that has drifted, rather than an excuse to invent a citation.
static func source_title(source_ref: Variant) -> String:
	if source_ref is Array:
		var titles: PackedStringArray = PackedStringArray()
		for each: Variant in (source_ref as Array):
			var one: String = source_title(each)
			if not one.is_empty():
				titles.append(one)
		return ", ".join(titles)
	var entry: Variant = COMPANION_SOURCES.get(String(source_ref), null)
	if entry is Dictionary:
		return String((entry as Dictionary).get("title", ""))
	return ""


## How the pairing's own side names the plant standing opposite: 2 when it names the plant itself, 1
## when it names only the family, 0 when it asks for nothing in particular. A plant is named in a line
## only where the rule about it names it - a pairing between two families is the family line's business,
## and repeating it as a list of everything in the family is the same sentence twice.
static func _naming_weight(pair: Dictionary, other: Dictionary) -> int:
	var best: int = 0
	for key: String in ["a", "b"]:
		var side: Variant = pair.get(key, null)
		if side is Dictionary and _side_fits(side, other):
			best = maxi(best, _side_weight(side))
	return best


## This plant's own rule, where it has one that asks nothing of the plant opposite - "whatever is
## growing". That is the one pairing the family words cannot sit beside: a plant whose own rule is
## *with everything* or *with nothing* is not described by its family's row, and the row would say the
## opposite of its own rule. Fennel is the case: the herb row says a herb grows well beside a
## nightshade, and fennel's own rule says fennel grows with nothing. Empty for the ordinary plant,
## which is nearly all of them.
static func universal_pair(subject: Dictionary) -> Dictionary:
	for pair: Dictionary in COMPANION_PLANTS:
		if _naming_weight(pair, subject) < 2:
			continue
		var a: Dictionary = pair["a"]
		var b: Dictionary = pair["b"]
		if bool(a.get("any", false)) or bool(b.get("any", false)):
			return pair
	return {}


## One reason as a sentence: what it is about, why, and the work it came from. Empty when there is no
## why to give, so a page never prints a colon with nothing after it.
static func _reason_sentence(label: String, why: String, source_ref: Variant) -> String:
	if why.is_empty():
		return ""
	var sentence: String = "%s: %s" % [label, why]
	var who: String = source_title(source_ref)
	if not who.is_empty():
		sentence += " (%s)" % who
	return sentence


## Every plant in this list that a stated pairing names *with* this one, in the catalogue's own order:
## one row per plant, `{id, name, outcome, nature, why, source}`, so a page can say which plants in the
## list this one goes with and give the reason in the same breath. The subject itself is never listed.
static func company_names(catalogue: PlantCatalogue, subject: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if catalogue == null or subject.is_empty():
		return out
	var mine: StringName = StringName(subject.get("id", &""))
	for plant: PlantSpecies in catalogue.all():
		if not mine.is_empty() and plant.id == mine:
			continue
		var other: Dictionary = subject_of(plant)
		var pair: Dictionary = company_pair(subject, other)
		if pair.is_empty() or _naming_weight(pair, other) < 2:
			continue
		out.append({
			"id": plant.id,
			"name": plant.common_name if not plant.common_name.is_empty() else plant.display_name(),
			"outcome": int(pair.get("outcome", UNKNOWN)),
			"nature": String(pair.get("nature", NATURE_TRADITION)),
			"why": String(pair.get("why", "")),
			"source": pair.get("source", ""),
		})
	return out


## What this plant grows well beside and should be kept from, in one line for a page: the families the
## tables name, and then the plants in this list a pairing names by name. Empty for a plant nobody has
## said anything about, which is an answer rather than a failure.
##
## A plant whose own rule asks nothing of the plant opposite - marigold, fennel - is answered by that
## rule alone, because its own rule is read before its family's row and the two are opposites here.
static func company_line(catalogue: PlantCatalogue, subject: Dictionary) -> String:
	if subject.is_empty():
		return ""
	var universal: Dictionary = universal_pair(subject)
	if not universal.is_empty():
		if int(universal.get("outcome", UNKNOWN)) == UNSUITABLE:
			return "should be kept from whatever is growing"
		return "grows well with whatever is growing"
	var family: StringName = StringName(subject.get("family", &""))
	var good: Array = _words_of(good_neighbours(family))
	var bad: Array = _words_of(bad_neighbours(family))
	for row: Dictionary in company_names(catalogue, subject):
		var name: String = String(row["name"])
		if int(row["outcome"]) == UNSUITABLE:
			if not bad.has(name):
				bad.append(name)
		elif int(row["outcome"]) == GOOD:
			if not good.has(name):
				good.append(name)
	var parts: PackedStringArray = PackedStringArray()
	if not good.is_empty():
		parts.append("grows well beside %s" % _list_words(good))
	if not bad.is_empty():
		parts.append("should be kept from %s" % _list_words(bad))
	return "; ".join(parts)


## Why the pairings say what they say, where somebody has written down why: the mechanism, or plainly
## that it is tradition, with the work it came from. A plant's own rule is given first where it has one,
## then what goes with it, then what it is kept from - the reason a person reads the line is usually the
## first of those. Empty when this list names nothing with the plant, so a page shows nothing at all
## rather than a heading with no reason under it.
static func company_reason(catalogue: PlantCatalogue, subject: Dictionary) -> String:
	var good: PackedStringArray = PackedStringArray()
	var bad: PackedStringArray = PackedStringArray()
	var universal: Dictionary = universal_pair(subject)
	if not universal.is_empty():
		var own: String = _reason_sentence(
			"Whatever is growing there", String(universal.get("why", "")), universal.get("source", "")
		)
		if int(universal.get("outcome", UNKNOWN)) == UNSUITABLE:
			bad.append(own)
		else:
			good.append(own)
	for row: Dictionary in company_names(catalogue, subject):
		var sentence: String = _reason_sentence(
			"%s, in this list" % String(row["name"]), String(row["why"]), row["source"]
		)
		if sentence.is_empty():
			continue
		if int(row["outcome"]) == UNSUITABLE:
			bad.append(sentence)
		else:
			good.append(sentence)
	var parts: PackedStringArray = PackedStringArray()
	parts.append_array(good)
	parts.append_array(bad)
	return " ".join(parts)


## The one pairing between two plants, as a finding a verdict can carry: the same `{key, label, wanted,
## found, outcome, because, brief}` shape `turn_finding` returns, so a company question and a rotation
## question sit on a page side by side with no translation layer between them. Empty when nothing is
## stated about the two.
static func company_finding(first: Dictionary, second: Dictionary) -> Dictionary:
	var pair: Dictionary = company_pair(first, second)
	if pair.is_empty():
		return {}
	var mine: String = _name_of(first)
	var other: String = _name_of(second)
	if mine.is_empty() or other.is_empty():
		return {}
	var outcome: int = int(pair.get("outcome", UNKNOWN))
	var found: String = "beside %s" % other
	if outcome == UNSUITABLE:
		return _finding(
			"company", "company", mine, found, UNSUITABLE,
			"%s %s beside %s %s does not grow well, and it is worth keeping them apart" % [
				article(mine), mine, article(other), other
			],
			"kept from %s" % other
		)
	if outcome == GOOD:
		return _finding(
			"company", "company", mine, found, GOOD,
			"%s %s and %s %s grow well together" % [article(mine), mine, article(other), other],
			"good beside %s" % other
		)
	return {}


# --- the families as words ------------------------------------------------------------------


## A family as a person would say it: "brassica". Empty for `FAMILY_NONE`, which is a plant nobody
## rotates rather than a family called nothing.
static func family_words(family: StringName) -> String:
	return String(PlantSpeciesScript.FAMILY_NAMES.get(family, ""))


## The article a word wants: "an allium", "a brassica". Here rather than open-coded at each sentence,
## so "an allium after an allium" does not come out as "a allium after a allium".
static func article(word: String) -> String:
	if word.is_empty():
		return ""
	return "an" if "aeiou".contains(word.substr(0, 1).to_lower()) else "a"


## Every family there is, in the catalogue's order, as `StringName`s - what a page offers in the
## "what grew here last" dropdown.
static func families() -> Array[StringName]:
	var out: Array[StringName] = []
	for family: StringName in FAMILIES:
		out.append(family)
	return out


# --- the companions of a family -------------------------------------------------------------


## The families this one grows well beside, in the table's own order. Empty for a family nobody has.
static func good_neighbours(family: StringName) -> Array[StringName]:
	return _partners(family, COMPANION_GOOD)


## The families this one should be kept from, in the table's own order. Empty for a plant nobody
## rotates.
static func bad_neighbours(family: StringName) -> Array[StringName]:
	return _partners(family, COMPANION_BAD)


static func _partners(family: StringName, table: Array) -> Array[StringName]:
	var out: Array[StringName] = []
	if family.is_empty():
		return out
	for pair: Array in table:
		var left: StringName = pair[0]
		var right: StringName = pair[1]
		if left == family and not out.has(right):
			out.append(right)
		elif right == family and not out.has(left):
			out.append(left)
	return out


## What a crop gets on with, in one line for a page: "grows well beside leafy, brassica and cucurbit;
## should be kept from allium". The family table's answer alone, which is all a caller that knows only
## a family can be given; `company_line` is the same sentence with the plants the pairings name added.
static func companion_line(family: StringName) -> String:
	return company_line(null, family_subject(family))


static func _words_of(group: Array[StringName]) -> Array:
	var out: Array = []
	for family: StringName in group:
		out.append(family_words(family))
	return out


## A list as a person says it: "a, b and c". Empty list, empty string.
static func _list_words(words: Array) -> String:
	if words.is_empty():
		return ""
	if words.size() == 1:
		return String(words[0])
	return "%s and %s" % [
		", ".join(PackedStringArray(words.slice(0, words.size() - 1))), String(words[words.size() - 1])
	]


# --- the check ----------------------------------------------------------------------------


## Whether a crop should follow a stated family in a bed, and how it gets on with what stands beside.
##
## Returns the same shape `PlantSuitability.check` and `CropSun.check` return, so a page can show any
## of them side by side: `{verdict, ok, certain, colour, findings, summary, label, species, place,
## family, previous}`. `findings` is one row per question that was asked, in the same `{key, label,
## wanted, found, outcome, because, brief}` shape.
##
## **A question nobody answered is skipped, not answered.** A crop that names no family is not rotated
## (there is nothing to rotate), a bed whose history is unstated leaves the turn unchecked, and a
## neighbour with no stated pairing is passed over. Only when nothing at all could be asked does the
## verdict fall to unknown - and never to a green that says nothing was wrong when nothing was asked.
static func check(
	crop: PlantSpecies,
	previous_family: StringName = FAMILY_NONE,
	beside: Array = [],
	place: String = "this spot"
) -> Dictionary:
	var findings: Array[Dictionary] = []
	if crop == null:
		return _result(UNKNOWN, [], null, place, previous_family)
	var turn: Dictionary = turn_finding(crop, previous_family)
	if not turn.is_empty():
		findings.append(turn)
	var seen: Array[StringName] = []
	for raw: Variant in beside:
		var family: StringName = StringName(raw)
		if family.is_empty() or seen.has(family):
			continue
		seen.append(family)
		var company: Dictionary = companion_finding(crop.family, family)
		if not company.is_empty():
			findings.append(company)
	if findings.is_empty():
		return _result(UNKNOWN, findings, crop, place, previous_family)
	return _result(_worst(findings), findings, crop, place, previous_family)


## The turn: whether this crop's family may follow the stated one. Empty when it cannot be asked -
## the crop names no family, or nobody has said what grew here before.
static func turn_finding(crop: PlantSpecies, previous_family: StringName) -> Dictionary:
	if crop == null or crop.family.is_empty() or previous_family.is_empty():
		return {}
	var mine: String = family_words(crop.family)
	var before: String = family_words(previous_family)
	var found: String = "%s last year" % before
	if crop.family == previous_family:
		return _finding(
			"turn", "rotation", mine, found, UNSUITABLE,
			"%s %s after %s %s shares the same pests and diseases, so it wants a different family here" % [
				article(mine), mine, article(before), before
			],
			"same family twice"
		)
	if previous_family == LEGUME:
		return _finding(
			"turn", "rotation", mine, found, GOOD,
			"a legume went before it and leaves the ground richer than it found it",
			"after a legume"
		)
	return _finding(
		"turn", "rotation", mine, found, GOOD,
		"%s %s has not grown here, so this is a fresh start" % [article(mine), mine], "a fresh family"
	)


## How this crop's family gets on with one other family: the family table's answer, which is what a
## caller holding only families can be given. `company_finding` is the same question asked of
## everything that is stated, plants and all. Empty when there is no stated pairing to report - which is
## most pairs, and passing them over is right: a companion list is not a place to invent an opinion
## about everything, only about what somebody has said.
static func companion_finding(crop_family: StringName, beside_family: StringName) -> Dictionary:
	return company_finding(family_subject(crop_family), family_subject(beside_family))


static func _has_pair(table: Array, a: StringName, b: StringName) -> bool:
	for pair: Array in table:
		if (pair[0] == a and pair[1] == b) or (pair[0] == b and pair[1] == a):
			return true
	return false


static func _finding(
	key: String, label: String, wanted: String, found: String, outcome: int, because: String,
	brief: String
) -> Dictionary:
	return {
		"key": key,
		"label": label,
		"wanted": wanted,
		"found": found,
		"outcome": outcome,
		"because": because,
		"brief": brief,
	}


## The worst outcome among the findings, which is the verdict. Asked of `PlantSuitability` rather than
## carried here: one ordering rule, so a red ring and a red row cannot come to different verdicts.
static func _worst(findings: Array[Dictionary]) -> int:
	return PlantSuitabilityScript.worst_of(findings)


static func _result(
	verdict: int, findings: Array[Dictionary], crop: PlantSpecies, place: String,
	previous_family: StringName
) -> Dictionary:
	var first: Dictionary = _first_not(findings, verdict)
	var title: String = crop.display_name() if crop != null else "this crop"
	return {
		"verdict": verdict,
		"ok": verdict != UNSUITABLE,
		"certain": verdict == GOOD or verdict == TOLERATED,
		"colour": PlantSuitabilityScript.colour_of(verdict),
		"findings": findings,
		"summary": _summary(verdict, first, title, place, crop),
		"label": _label(verdict, first),
		"species": title,
		"place": place,
		"family": family_words(crop.family) if crop != null else "",
		"previous": family_words(previous_family),
	}


static func _first_not(findings: Array[Dictionary], outcome: int) -> Dictionary:
	for finding: Dictionary in findings:
		if int(finding.get("outcome", GOOD)) == outcome:
			return finding
	return findings[0] if not findings.is_empty() else {}


# --- saying it ----------------------------------------------------------------------------


static func _summary(
	verdict: int, first: Dictionary, title: String, place: String, crop: PlantSpecies
) -> String:
	if first.is_empty():
		if crop == null or crop.family.is_empty():
			return "%s does not say which family it belongs to, so it cannot be rotated." % title
		return "%s cannot be rotated at %s: nothing says what grew there before." % [title, place]
	match verdict:
		UNSUITABLE:
			return "%s should not go at %s: %s." % [title, place, String(first.get("because", ""))]
		UNKNOWN:
			return "%s cannot be checked at %s: %s." % [title, place, String(first.get("because", ""))]
		TOLERATED:
			return "%s would go at %s, but %s." % [title, place, String(first.get("because", ""))]
	return "%s follows on well at %s." % [title, place]


static func _label(verdict: int, first: Dictionary) -> String:
	if first.is_empty():
		return "cannot be checked"
	# A good verdict still carries its reason here - "after a legume" and "a fresh family" are two
	# different good answers, and the list a person reads should say which one it is.
	if verdict == GOOD:
		return String(first.get("brief", "follows on well"))
	match verdict:
		UNSUITABLE:
			return String(first.get("brief", "same family twice"))
		TOLERATED:
			return String(first.get("brief", "only just"))
	return String(first.get("brief", "cannot be checked"))


static func summary_of(result: Dictionary) -> String:
	return String(result.get("summary", ""))


static func label_of(result: Dictionary) -> String:
	return String(result.get("label", ""))


static func colour_from(result: Dictionary) -> Color:
	return PlantSuitabilityScript.colour_from(result)


static func verdict_name(verdict: int) -> String:
	return PlantSuitabilityScript.verdict_name(verdict)


# --- what would follow in a bed -------------------------------------------------------------


## Every crop in the catalogue, checked against one bed's stated history, best first: the answer to
## "what should grow here next". One row per edible species, in `{id, title, family, after, verdict,
## colour, summary, label}` shape, sorted by verdict and then by botanical name so the list is the
## same twice running.
##
## Only edible species are listed: a question about what to grow has no row for a boxwood.
static func rows(
	catalogue: PlantCatalogue, previous_family: StringName = FAMILY_NONE, beside: Array = [],
	place: String = "this spot"
) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if catalogue == null:
		return out
	for plant: PlantSpecies in catalogue.all():
		if not plant.is_edible():
			continue
		var verdict: Dictionary = check(plant, previous_family, beside, place)
		out.append({
			"id": plant.id,
			"title": plant.display_name(),
			"family": family_words(plant.family),
			"after": family_words(previous_family),
			"verdict": int(verdict["verdict"]),
			"colour": verdict["colour"],
			"summary": String(verdict["summary"]),
			"label": String(verdict["label"]),
		})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["verdict"]) != int(b["verdict"]):
			return int(a["verdict"]) < int(b["verdict"])
		return String(a["title"]) < String(b["title"]))
	return out


## Those rows as the lines a list control shows: the crop and how the bed answers it. The line is the
## row's own `label` rather than a format assembled here, so the list and the summary cannot say two
## different things.
static func row_texts(
	catalogue: PlantCatalogue, previous_family: StringName = FAMILY_NONE, beside: Array = [],
	place: String = "this spot"
) -> Array[String]:
	var out: Array[String] = []
	for row: Dictionary in rows(catalogue, previous_family, beside, place):
		out.append("%s: %s" % [String(row["title"]), String(row["label"])])
	return out


## How many crops of each verdict a bed has, for a summary line.
static func counts(rows_list: Array) -> Dictionary:
	var out: Dictionary = {GOOD: 0, TOLERATED: 0, UNSUITABLE: 0, UNKNOWN: 0}
	for row: Dictionary in rows_list:
		var level: int = int(row.get("verdict", UNKNOWN))
		out[level] = int(out[level]) + 1
	return out


## "9 crops: 6 follow on well, 2 should not, 1 cannot be checked." A bed with no edible crop in the
## catalogue says so rather than reading as a bed nothing grows in.
static func describe_rows(rows_list: Array) -> String:
	if rows_list.is_empty():
		return "no crops are recorded in this plant list"
	var held: Dictionary = counts(rows_list)
	var parts: PackedStringArray = PackedStringArray()
	parts.append("%d follow on well" % int(held.get(GOOD, 0)))
	var thin: int = int(held.get(TOLERATED, 0))
	if thin > 0:
		parts.append("%d are thin" % thin)
	var wrong: int = int(held.get(UNSUITABLE, 0))
	if wrong > 0:
		parts.append("%d should not" % wrong)
	var unknown: int = int(held.get(UNKNOWN, 0))
	if unknown > 0:
		parts.append("%d cannot be checked" % unknown)
	return "%d crop%s: %s." % [
		rows_list.size(), "" if rows_list.size() == 1 else "s", ", ".join(parts)
	]