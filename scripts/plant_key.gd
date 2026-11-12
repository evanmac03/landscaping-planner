class_name PlantKey
extends RefCounted
## Naming a plant by answering questions about it: the key a person works through when they are standing
## in front of something they cannot name and have nobody to ask.
##
## The other door onto a name is a photograph, and `PlantIdentifier` reads one. This is the door for a
## person who has no photograph, or does not trust the one they have: they look at the plant, answer what
## they can see, and the field of candidates narrows until one is left.
##
## ## It asks; `PlantCatalogue.filter` decides
##
## **A key that matched plants itself would be a second filter, and the two would eventually disagree** -
## `PlantCatalogue.filter` is this program's one filter, and the browser, the palette and every planting
## check already go through it. So each answer is a *criteria fragment* in that filter's own words: this
## class turns the answers into one `criteria` dictionary and hands it over, and which plants are left is
## the filter's answer rather than this class's.
##
## That is also why the vocabulary is not written here twice. A kind is `PlantSpecies.CATEGORY_NAMES`, a
## light level is `PlantSpecies.SUN_NAMES`, a water need is `PlantSpecies.WATER_NAMES`, and whether a
## plant is a conifer is `PlantSpecies.is_conifer()` - the same table and the same rule the rest of the
## program uses, so a question cannot come to offer a category nothing in the list is filed under.
##
## ## Which question to ask next is arithmetic
##
## The order questions are asked in is written down nowhere: it is worked out from what is left. Every
## remaining question is scored by how evenly its answers would split the plants still in the running -
## the entropy of that split, in bits - and the question that would tell a person the most is asked
## first. The authored order in `QUESTIONS` is only the tie-break between two equally informative
## questions, so the same catalogue and the same answers always ask the same thing.
##
## When nothing left can split the candidates any further the key stops asking, and that is a real
## answer rather than a failure: the plants still in the running **cannot be told apart** from what has
## been said, and a page shows them rather than picking one. A key that chose between two plants the
## list cannot distinguish would be inventing the sort of fact this program spends its effort not
## inventing. An answer that empties the list is reported plainly too, and the page offers to take it
## back - a key that showed nothing and said nothing would leave somebody stuck.
##
## ## The leaves: asked only while every plant left has been read
##
## Half these questions are about a plant's **habit** - its kind, its light, the ground it grows in - and
## every catalogue entry states those. The other half are about its **leaves**: how they sit on the stem,
## whether a leaf is one blade or several, its outline, its edge, and the way its veins run. Those are the
## questions a field guide's key is built from, and they are ones a person standing in front of a plant
## can answer without knowing what it is.
##
## Most entries state nothing about their leaves. **A plant that states nothing about a leaf fails every
## answer to a question about it**, so asking one while such a plant is still in the running would
## eliminate it by a description nobody gave - the silent wrong answer this program is arranged against.
## The rule is `askable`: a leaf question is asked only while every plant left states that leaf. The leaf
## questions come and go as the field narrows, and a catalogue nobody has read leaf by leaf is simply
## never asked about leaves.
##
## ## The answers are a plain record
##
## `answers` is a `Dictionary` of question key to option key, **in the order they were answered** - which
## is what "take the last answer back" reads.
##
## It is deliberately untyped and holds nothing but strings, because a page keeps one while it is open
## and a test builds one to check the arithmetic, and neither should have to know a class to hand over
## two words. A question key or an option key the table does not know is ignored rather than refused: a
## record that came back from a file with a question this program has since dropped should narrow by
## what the rest of it says, not refuse the whole thing.

## What kind of plant it is - a tree, a shrub, a fern. The most informative question there is, and the
## one a person can almost always answer.
const KIND := &"kind"
## Whether it is a conifer. Asked of `PlantSpecies.is_conifer()`, so a broadleaf that a nursery tags
## "evergreen" is not swept in with the spruces.
const CONIFER := &"conifer"
## The light it is growing in, as one of `PlantSpecies`' own sun bits.
const LIGHT := &"light"
## What the ground is like there, as a water need in `PlantSpecies.WATER_NAMES`.
const WATER := &"water"
## Whether any of it is eaten.
const FOOD := &"food"
## How tall it stands. Last, and deliberately: the list states the height a plant **grows to**, so a
## young plant in front of somebody is honestly shorter than the number this filters on.
const HEIGHT := &"height"
## The colour of the flowers, as one of `PlantSpecies.FLOWER_COLOURS`. The first thing a field guide asks
## when a plant is in flower. The catalogue stores the shade, not the word, so `states_for` and the filter
## both read `PlantSpecies.flower_colour_name` - one rule puts the shade and the person's answer in the
## same bucket.
const FLOWER := &"flower"
## When it flowers, as one of `PlantSpecies.SEASONS`. A person knows the season far more often than the
## exact month, so the key asks the season; a plant flowering from April to June is honestly "spring".
const BLOOM := &"bloom"

## The five leaf questions. **Their keys are the traits' own names**, because an answer to one of them is
## a criterion in exactly that trait's words - so a key, a filter and a page cannot come to call one leaf
## two different things.
const LEAF_ARRANGEMENT := PlantSpecies.LEAF_ARRANGEMENT
const LEAF_COMPLEXITY := PlantSpecies.LEAF_COMPLEXITY
const LEAF_SHAPE := PlantSpecies.LEAF_SHAPE
const LEAF_MARGIN := PlantSpecies.LEAF_MARGIN
const LEAF_VENATION := PlantSpecies.LEAF_VENATION

## Every question, in the order they break a tie.
##
## The order runs from what a person standing in front of a plant can be sure of to what they are
## guessing at. The kind first, because it is the one thing anybody can answer; then the habits; then the
## height, the only habit question whose answer is a **prediction**, because the list states the size a
## plant grows to and the plant in front of somebody is not that size yet; and the leaves last, because a
## leaf key runs from the coarsest thing about a leaf to the finest, and the way its veins run is the one
## most people have never looked at.
##
## The two flower questions sit between the height and the leaves: they are the questions a person can
## **only sometimes** answer, because a plant that is not in flower gives no colour and a plant that has
## finished flowering gives no season to read off it. `states_for` is what keeps that from mattering.
const QUESTIONS: Array[StringName] = [
	KIND,
	CONIFER,
	LIGHT,
	FOOD,
	WATER,
	HEIGHT,
	FLOWER,
	BLOOM,
	LEAF_ARRANGEMENT,
	LEAF_COMPLEXITY,
	LEAF_SHAPE,
	LEAF_MARGIN,
	LEAF_VENATION,
]

## The leaf questions on their own: the ones that read something a catalogue entry may not state, and so
## the ones `askable` can decide not to ask.
const LEAF_QUESTIONS: Array[StringName] = [
	LEAF_ARRANGEMENT,
	LEAF_COMPLEXITY,
	LEAF_SHAPE,
	LEAF_MARGIN,
	LEAF_VENATION,
]

## The four things a set of answers can amount to.
##
## `ASKING` is the working state and the other three are answers: one plant left, several the list
## cannot separate, or none at all.
const ASKING := &"asking"
const IDENTIFIED := &"identified"
const SEVERAL := &"several"
const NONE := &"none"

## How many candidates a page is handed to show. A key's whole point is that this number comes down, so
## the beginning - where it can be the whole list - is answered with a count and a short sample rather
## than four thousand rows.
const MOST_SHOWN := 20

## The answer for a question somebody cannot answer: **not one of a question's options, and offered for
## every question there is**.
##
## It is kept as an answer all the same, for two reasons that together are the whole of it. Being answered,
## the question is **not asked again** - a key that re-asked what somebody has just said they cannot see
## would be a key nobody gets to the end of. Carrying **no criterion at all**, it narrows nothing - the key
## moves on to a question that can be answered rather than taking a guess nobody made, which is the same
## care `askable` takes about a plant nobody has described.
##
## It is deliberately absent from every `options_of`, so it can never appear as one of a question's own
## answers: it is a way past a question, not a way to identify a plant.
const UNSURE := &"unsure"

## What `UNSURE` reads as, on the button and in the line that says what was taken back.
const UNSURE_WORDS := "not sure"


# --- the questions ----------------------------------------------------------------------------


## What a question asks, in a person's words. Empty for a question this program does not have, so a
## caller can tell a missing question from an unworded one.
static func question_text(question: StringName) -> String:
	match question:
		KIND:
			return "What kind of plant is it?"
		CONIFER:
			return "Is it a conifer?"
		LIGHT:
			return "What light is it growing in?"
		FOOD:
			return "Is any of it eaten?"
		WATER:
			return "What is the ground like where it grows?"
		HEIGHT:
			return (
				"How tall does it stand? (The list states the height it grows to, so a young plant is "
				+ "shorter than the size this answer matches.)"
			)
		FLOWER:
			return "What colour are the flowers?"
		BLOOM:
			return (
				"When does it flower? (Answer this only if it is in flower now, or you know when it is - "
				+ "a plant that has finished flowering will not match what you say.)"
			)
		LEAF_ARRANGEMENT:
			return "How do the leaves come off the stem?"
		LEAF_COMPLEXITY:
			return "Is a leaf one blade, or several joined?"
		LEAF_SHAPE:
			return "What shape is a leaf?"
		LEAF_MARGIN:
			return "What is the edge of a leaf like?"
		LEAF_VENATION:
			return "How do the veins run?"
	return ""


## One question's answers, in the order a page offers them: `{key, label, criteria}`.
##
## The labels are the **species tables' own** words, and the keys are derived from them, so a kind added
## to `PlantSpecies.CATEGORY_NAMES` is offered by this question the day it is added and cannot be left
## out of step. `criteria` is the fragment `PlantCatalogue.filter` is given when the answer is chosen.
static func options_of(question: StringName) -> Array[Dictionary]:
	match question:
		KIND:
			return _kind_options()
		CONIFER:
			return [
				{ "key": &"yes", "label": "a conifer - needles, or cones", "criteria": { "conifer": true } },
				{ "key": &"no", "label": "not a conifer - ordinary leaves", "criteria": { "conifer": false } },
			]
		LIGHT:
			return _light_options()
		FOOD:
			return [
				{ "key": &"yes", "label": "something you would eat", "criteria": { "edible": true } },
				{ "key": &"no", "label": "not grown to eat", "criteria": { "not_edible": true } },
			]
		WATER:
			return _water_options()
		HEIGHT:
			return _height_options()
		FLOWER:
			return _flower_options()
		BLOOM:
			return _bloom_options()
		LEAF_ARRANGEMENT, LEAF_COMPLEXITY, LEAF_SHAPE, LEAF_MARGIN, LEAF_VENATION:
			return _leaf_options(question)
	return []


## The kinds, read off `PlantSpecies.CATEGORY_NAMES` rather than written again here.
static func _kind_options() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for value: Variant in PlantSpecies.CATEGORY_NAMES.keys():
		var kind: int = int(value)
		var label: String = String(PlantSpecies.CATEGORY_NAMES[kind])
		out.append({
			"key": StringName(label.to_lower().replace(" ", "_")),
			"label": label,
			"criteria": { "category": kind },
		})
	return out


## The light levels, as a **place** a plant is standing in. A plant that takes full sun and part shade is
## kept by both answers, because `filter`'s `sun` asks whether the plant takes the bit it is offered -
## which is the question "will it live here?", and the only light question with an answer.
static func _light_options() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for bit: int in [PlantSpecies.FULL_SUN, PlantSpecies.PART_SHADE, PlantSpecies.FULL_SHADE]:
		var label: String = String(PlantSpecies.SUN_NAMES[bit])
		out.append({
			"key": StringName(label.to_lower().replace(" ", "_")),
			"label": label,
			"criteria": { "sun": bit },
		})
	return out


## How much water the ground holds, as the one water need the filter is pinned to with both bounds.
static func _water_options() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for level: int in [PlantSpecies.WATER_LOW, PlantSpecies.WATER_MEDIUM, PlantSpecies.WATER_HIGH]:
		var label: String = String(PlantSpecies.WATER_NAMES[level])
		out.append({
			"key": StringName(label.to_lower().replace(" ", "_")),
			"label": label,
			"criteria": { "water_min": level, "water_max": level },
		})
	return out


## The height bands. They **partition every size**: each band's upper bound is one centimetre below the
## next band's lower bound, so a plant falls in exactly one band and no plant can be dropped for standing
## on a boundary.
static func _height_options() -> Array[Dictionary]:
	return [
		{ "key": &"small", "label": "knee-high or less - up to 50 cm", "criteria": { "height_max_cm": 50 } },
		{
			"key": &"medium",
			"label": "waist to head height - 50 cm to 2 m",
			"criteria": { "height_min_cm": 51, "height_max_cm": 200 },
		},
		{
			"key": &"large",
			"label": "a small tree - 2 m to 8 m",
			"criteria": { "height_min_cm": 201, "height_max_cm": 800 },
		},
		{ "key": &"tall", "label": "taller than a house - over 8 m", "criteria": { "height_min_cm": 801 } },
	]


## The flower colours, read off `PlantSpecies.FLOWER_COLOURS` rather than written again here, so a colour
## added to the vocabulary is offered by the key the day it is added. The answer is a bucket, and the
## filter buckets the plant's own shade with the same function, so "pink" cannot mean two flowers.
static func _flower_options() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for name: StringName in PlantSpecies.FLOWER_COLOURS:
		out.append({
			"key": name,
			"label": String(name),
			"criteria": { "flower_colour": name },
		})
	return out


## The seasons, read off `PlantSpecies.SEASONS` rather than written again here. The answer is a season and
## not a month because that is what a person knows; the filter is what turns it into the months a plant
## would have to flower in.
static func _bloom_options() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for name: Variant in PlantSpecies.SEASONS.keys():
		var season: StringName = StringName(name)
		out.append({
			"key": season,
			"label": String(season),
			"criteria": { "bloom_season": season },
		})
	return out


## The answers to a leaf question: one per value the trait's own table knows, in that table's order, in
## the words a field guide uses.
##
## Read off `PlantSpecies.names_for` rather than written again, so a value added to a leaf's vocabulary is
## offered by the key the day it is added, and a mistyped name cannot invent a leaf nobody has.
static func _leaf_options(question: StringName) -> Array[Dictionary]:
	var names: Dictionary = PlantSpecies.names_for(question)
	var out: Array[Dictionary] = []
	for bit: Variant in names.keys():
		var value: int = int(bit)
		var criteria: Dictionary = { }
		criteria[question] = value
		out.append({
			"key": StringName(String(names[value]).to_lower().replace(" ", "_")),
			"label": String(names[value]),
			"criteria": criteria,
		})
	return out


## What one answer says, in the words a page puts on its button. Empty when either key is unknown.
static func option_text(question: StringName, option: StringName) -> String:
	if option == UNSURE:
		return UNSURE_WORDS
	var found: Dictionary = _option_for(question, option)
	return String(found.get("label", ""))


## Every answer key a question offers, in order - what a page walks when it wants the buttons rather than
## the labels.
static func option_keys(question: StringName) -> Array[StringName]:
	var out: Array[StringName] = []
	for option: Dictionary in options_of(question):
		out.append(StringName(option["key"]))
	return out


## One answer's entry, or an empty dictionary when the question or the answer is not this program's.
static func _option_for(question: StringName, option: StringName) -> Dictionary:
	for entry: Dictionary in options_of(question):
		if StringName(entry["key"]) == option:
			return entry
	return { }


# --- reading and writing the answers ------------------------------------------------------------


## A question key or an option key, from whatever a file or a page handed over.
##
## A record read back from JSON holds `String`s where this program writes `StringName`s, so both are
## taken and anything else is the empty key, which matches no question.
static func _as_key(value: Variant) -> StringName:
	if value is StringName:
		return value
	if value is String:
		return StringName(value)
	return &""


## The questions that have been answered, in the order they were answered.
static func asked(answers: Dictionary) -> Array[StringName]:
	var out: Array[StringName] = []
	for key: Variant in answers.keys():
		out.append(_as_key(key))
	return out


## The answers with one more in them. A copy, so a caller can keep the answers it had.
##
## Re-answering a question already answered **replaces** it in place rather than moving it to the end,
## which is what a dictionary does and what "take the last answer back" needs: changing one's mind about
## the light is not answering the light last.
static func with_answer(answers: Dictionary, question: StringName, option: StringName) -> Dictionary:
	var out: Dictionary = answers.duplicate()
	out[question] = option
	return out


## The answers with a question marked as one this person cannot answer: the question is answered - so it is
## not asked again - with an answer that says nothing about the plant, so the field is not narrowed by it.
##
## A named call rather than a caller passing `UNSURE` itself, because "not sure" is a rule about what may
## be asked and not merely a particular word.
static func with_unsure(answers: Dictionary, question: StringName) -> Dictionary:
	return with_answer(answers, question, UNSURE)


## The answers with the most recent one taken back, and nothing else - the undo a key needs when an
## answer turns out to have been wrong.
static func without_last(answers: Dictionary) -> Dictionary:
	var out: Dictionary = answers.duplicate()
	var keys: Array = answers.keys()
	if keys.is_empty():
		return out
	out.erase(keys[keys.size() - 1])
	return out


## The answers with one question forgotten, wherever it sits in the order.
static func without(answers: Dictionary, question: StringName) -> Dictionary:
	var out: Dictionary = answers.duplicate()
	out.erase(question)
	return out


# --- the arithmetic ----------------------------------------------------------------------------


## What the answers say, in `PlantCatalogue.filter`'s own criteria.
##
## **This is the whole of the join between a key and the one filter.** A fragment whose key the filter
## does not know would make it refuse the lot, so an answer this program does not have contributes
## nothing rather than poisoning the criteria - which is why `_option_for` is asked rather than the
## answers being trusted.
static func criteria_for(answers: Dictionary) -> Dictionary:
	var criteria: Dictionary = { }
	for key: Variant in answers.keys():
		var found: Dictionary = _option_for(_as_key(key), _as_key(answers[key]))
		if found.is_empty():
			continue
		var fragment: Dictionary = found["criteria"]
		for name: Variant in fragment.keys():
			criteria[name] = fragment[name]
	return criteria


## The plants left after every answer, best-named first - the filter's own order, which is alphabetical by
## botanical name.
static func remaining(catalogue: PlantCatalogue, answers: Dictionary) -> Array[PlantSpecies]:
	if catalogue == null:
		return []
	return catalogue.filter(criteria_for(answers))


## The leaf trait a question reads, or the empty key for a question about something every entry states.
## A leaf question's **key is its trait's name**, so this is a membership test rather than a second table.
static func trait_of(question: StringName) -> StringName:
	return question if PlantSpecies.LEAF_TRAITS.has(question) else &""


## Whether a question may be asked of the plants still in the running.
##
## Every question about a plant's habit reads something a catalogue entry always states - a kind, a light
## need, a size, whether it is grown to eat. A question about its **leaves** reads something an entry may
## know nothing about, and a plant that states nothing about a leaf **fails every answer** to a question
## about that leaf. Asking one while such a plant is still in the running would therefore eliminate it by
## a description nobody gave, and the key would confidently settle on the wrong plant.
##
## So a leaf question is asked only while every plant left states that leaf, and the **flower** questions -
## the colour and the season - only while every plant left flowers at all. That single rule is what makes a
## catalogue nobody has read leaf by leaf safe to narrow by a key, and what makes the questions that cannot
## be answered about the plants still in the running appear, disappear and come back as the field narrows.
static func askable(left: Array[PlantSpecies], question: StringName) -> bool:
	for plant: PlantSpecies in left:
		if not states_for(plant, question):
			return false
	return true


## Whether one plant states what a question is about.
##
## **Two** kinds of question need this, not one. A **leaf** question reads a trait a catalogue entry may
## never have been given. A **flower** question - the colour, the season - reads something only a plant
## that flowers has at all: a fern states no flower colour because it has no flower, and its `bloom_colour`
## is a default nobody chose. Either question asked while such a plant is still in the running would
## eliminate it by a description nobody gave, which is the wrong answer this key is arranged against.
##
## Everything else - the kind, the light, the water, the height, whether it is grown to eat, whether it is a
## conifer - is read from a field every entry states, so it is always askable.
static func states_for(plant: PlantSpecies, question: StringName) -> bool:
	var trait_name: StringName = trait_of(question)
	if not trait_name.is_empty():
		return plant.leaf_trait(trait_name) != 0
	if question == FLOWER or question == BLOOM:
		return plant.blooms()
	return true


## How much one question would tell somebody, in bits: the entropy of the split its answers make of the
## plants still in the running.
##
## An answer that would keep every plant tells nothing and contributes nothing; an answer that would keep
## none is not an answer anybody could give and is left out of the sum. Zero therefore means the question
## cannot narrow the field at all, which is exactly when a key should stop asking it - and a question that
## cannot be asked of these plants at all is the same answer.
static func split_score(left: Array[PlantSpecies], question: StringName) -> float:
	if not askable(left, question):
		return 0.0
	var total: float = float(left.size())
	if total <= 0.0:
		return 0.0
	var score: float = 0.0
	for option: Dictionary in options_of(question):
		var kept: int = _kept_by(left, option["criteria"])
		if kept <= 0:
			continue
		var share: float = float(kept) / total
		score -= share * (log(share) / log(2.0))
	return score


## The question worth asking next, or the empty key when there is nothing left to ask: one plant is
## already named, and several that no remaining question can separate are as far as this key goes.
##
## Asked of the plants still in the running and not of the answers, so a question already answered is
## never offered again and a question that has stopped being useful - every remaining plant takes every
## one of its answers - is passed over for one that still tells something.
static func next_question(catalogue: PlantCatalogue, answers: Dictionary) -> StringName:
	var left: Array[PlantSpecies] = remaining(catalogue, answers)
	if left.size() <= 1:
		return &""
	var best: StringName = &""
	var best_score: float = 0.0
	for question: StringName in QUESTIONS:
		if answers.has(question):
			continue
		var score: float = split_score(left, question)
		if score > best_score:
			best_score = score
			best = question
	return best


## The answers of a question that would still leave something, in the order the question offers them.
##
## A page shows these and nothing else: an answer that keeps none of the plants in the running is not a
## thing the plant in front of somebody can be, so offering it would be offering a way to eliminate the
## right plant by mistake.
static func live_options(catalogue: PlantCatalogue, question: StringName, answers: Dictionary) -> Array[StringName]:
	var left: Array[PlantSpecies] = remaining(catalogue, answers)
	# A question that may not be asked is not a question with no answers: it is one whose answers would
	# drop a plant nobody has described, so it offers nothing and the key asks something else.
	if not askable(left, question):
		return []
	var out: Array[StringName] = []
	for option: Dictionary in options_of(question):
		if _kept_by(left, option["criteria"]) > 0:
			out.append(StringName(option["key"]))
	return out


## How many plants would be left if this answer were chosen.
static func leaves_after(catalogue: PlantCatalogue, question: StringName, option: StringName, answers: Dictionary) -> int:
	return remaining(catalogue, with_answer(answers, question, option)).size()


## What a set of answers amounts to: how many plants are left, the question worth asking next, and the
## answers to it worth offering - everything a page needs and nothing it has to work out for itself.
##
## `matches` is capped at `MOST_SHOWN`; `count` is not, because the count is the figure that means
## something at the start of a key.
static func state(catalogue: PlantCatalogue, answers: Dictionary) -> Dictionary:
	var left: Array[PlantSpecies] = remaining(catalogue, answers)
	var question: StringName = next_question(catalogue, answers)
	var options: Array[Dictionary] = []
	if question != &"":
		for option: StringName in live_options(catalogue, question, answers):
			options.append({
				"key": option,
				"label": option_text(question, option),
				"leaves": leaves_after(catalogue, question, option, answers),
			})
	return {
		"verdict": verdict_of(left, question),
		"count": left.size(),
		"matches": left.slice(0, MOST_SHOWN),
		"question": question,
		"prompt": question_text(question),
		"options": options,
		"answers": answers.duplicate(),
		"words": words(catalogue, answers),
	}


## What a set of answers amounts to, as one of the four verdicts.
static func verdict_of(left: Array[PlantSpecies], question: StringName) -> StringName:
	if left.is_empty():
		return NONE
	if left.size() == 1:
		return IDENTIFIED
	if question == &"":
		return SEVERAL
	return ASKING


## The outcome in a person's words: what has been settled, or what to answer next, or that nothing fits.
##
## Every one of the four is a sentence rather than a number, and the two that are not working states name
## what is missing - the plants that cannot be told apart, or the answer to take back. There is no
## message here that a compiler could have written.
static func words(catalogue: PlantCatalogue, answers: Dictionary) -> String:
	var left: Array[PlantSpecies] = remaining(catalogue, answers)
	var question: StringName = next_question(catalogue, answers)
	match verdict_of(left, question):
		NONE:
			return (
				"Nothing in the plant list matches all of that. Take the last answer back, or start the key "
				+ "again."
			)
		IDENTIFIED:
			return "That is %s." % left[0].display_name()
		SEVERAL:
			return "The list cannot tell %s apart from what you have said: %s." % [
				_how_many(left.size(), "plant"),
				names_in_words(left),
			]
		ASKING:
			return "%s still fit. Next: %s" % [_how_many(left.size(), "plant"), question_text(question)]
	return ""


## A list of plants as a person would read it: the common name with the botanical name beside it.
static func names_in_words(plants: Array[PlantSpecies]) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for plant: PlantSpecies in plants.slice(0, MOST_SHOWN):
		parts.append(plant.display_name())
	if plants.size() > MOST_SHOWN:
		parts.append("%s more" % _how_many(plants.size() - MOST_SHOWN, "other"))
	return ", ".join(parts)


## A number of plants as a person would say it: "1 plant", "4 plants".
##
## Exposed because a page puts this same count on the button for an answer, and a count worded in two
## places is a count that can come to disagree with itself - the rule that keeps an area conversion in
## one place.
static func count_text(count: int) -> String:
	return _how_many(count, "plant")


## A count and its noun, with the right number of them: "1 plant", "4 plants". The `%s` is why this is
## here rather than a format string at every call site.
static func _how_many(count: int, noun: String) -> String:
	if noun == "other":
		return "%d more" % count
	return "%d %s%s" % [count, noun, "" if count == 1 else "s"]


## How many of a set of plants one answer's criteria keeps. **The filter's own `matches`** rather than a
## second reading of the same fields, so scoring a question and choosing an answer cannot come apart.
static func _kept_by(left: Array[PlantSpecies], criteria: Dictionary) -> int:
	var count: int = 0
	for plant: PlantSpecies in left:
		if PlantCatalogue.matches(plant, criteria):
			count += 1
	return count