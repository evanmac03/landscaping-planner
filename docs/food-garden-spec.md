# The food garden

A planting plan says what goes in the ground. This is the arithmetic of whether the ground will feed
anybody: whether a crop gets the sun it needs, what may follow what, what is ready in a month, how long
the season is, when to sow, and how many plants it takes to feed a household.

It is a module in the same sense the irrigation and the lighting are: a set of questions a kitchen
gardener really asks, each answered from facts the plant list and the drawing already hold, and each
refusing by name rather than guessing. Nothing here draws. A crop is a species the catalogue already
has, a bed is ground somebody described, and the season is two dates kept with the drawing.

## 1. What already exists, and what this adds

The plant list already carries the edible half of a species, and until this module nothing read it:

* `edible_parts` - which bits of the plant are eaten, as bits of a set (leaf, fruit, root, bulb, stem,
flower, seed). Zero means the catalogue does not say, which is not the same as saying inedible.
* `harvest_months`, and `bloom_months` beside it - sets of months, and **circular** sets at that,
because a leek stands through the winter and a bloom from November to March is one run across the
new year.
* `maturity_days`, `sun_hours_tenths`, `yield_per_plant_g`, `need_per_person_g` - each a rule of thumb
the catalogue either states or does not, and zero where it does not.
* `family` - the group a crop rotates with. Nine of them, and it exists for one question.
* `harvest_text()`, `crop_text()`, `months_run_text()` - a species' own crop facts in words.

Around it, and unchanged by this module: `PlantSuitability` answers whether a plant belongs where it is
going, over five stated properties, of which light is one bit. The ground window describes beds and
their conditions. The drawing holds the placements, the bed outlines, the site's latitude and its frost
dates. `PlantOrder` prices a plan of species and counts, and the takeoff prices what is drawn.

What is added here is the kitchen garden's own arithmetic - six models and six pages:

| Model | The question it answers |
|---|---|
| `CropSun` | will this crop get the sun it needs, where it is going |
| `CropRotation` | what may follow what in a bed, and what grows well beside what |
| `HarvestCalendar` | what is ready in a given month |
| `GrowingSeason` | how long the season is, and what has the time to finish in it |
| `SowingPlanner` | when to sow it, and how to keep it coming |
| `PlantYield` | how many plants it takes to feed a household |

## 2. Load-bearing decisions

### 2.1 A crop is the species record, not a second table

Every one of these models reads `PlantSpecies`. There is no crop table: an edible's days to harvest,
its hours of sun, its family and its yield are the fields the catalogue already keeps and the browser
already shows. A second table of crops would be a second answer to what a tomato is, and the two would
drift the first time a nursery list was imported.

The consequence to keep in mind: **what these models can say is bounded by what the list states.** A
catalogue of ornamentals with a herb corner is a catalogue whose food pages have very little to work
with, and the pages say so rather than inventing a figure.

### 2.2 A question nobody answered is skipped, not answered

The rule the whole food garden keeps, and the one most likely to be undone by a well-meaning change:

* A figure that cannot be worked out is **refused by name**, and the refusal names the input that is
missing. There is no zero standing in for an answer, because a zero is indistinguishable from a real
nought.
* Four of these models answer with a verdict, and a question that could not be asked is **unknown** -
grey, never green. A green ring for a check that never ran is the one answer this must not give.
* Same rule inside a species record: `soils`, `edible_parts`, `harvest_months`, `maturity_days` and
the rest of the numeric fields are all allowed to be zero, and zero always means *the catalogue does
not say*. An ornamental is not claiming to be inedible; it is simply not claiming.

### 2.3 A judgement and a count are different kinds of answer

`CropSun`, `CropRotation`, `GrowingSeason` and `SowingPlanner` each ask a question that is a
**judgement**, and each answers it with one of four borrowed words. `HarvestCalendar` and `PlantYield`
do not: what is ready in a month and how many plants feed four people are **facts and counts**, no more
good or bad than a date is. So those two borrow no verdict vocabulary at all and keep no reds and no
greens. A crop whose harvest window nobody recorded is not called unsuitable - it is counted apart, for
exactly that reason, so an empty month reads as *nothing is ready then* rather than as a fault.

### 2.4 The four verdicts are borrowed, not restated

Good, tolerated, wrong, unknown - and their colours - come from `PlantSuitability`, re-exported as
constants rather than defined again. So a light verdict, a rotation verdict, a season verdict and a
sowing verdict are the same four words in the same four colours wherever they meet on a page, and there
is no translation layer that could one day decide two of them mean different things.

The ordering rule is borrowed with them: something **against** the crop outranks a gap, and a gap
outranks a thin margin. That is why a bed whose history nobody stated, with an allium already standing
beside the beans, comes back wrong rather than unknown.

### 2.5 The stated light level is turned into hours, and the site's day is the ceiling

`PlantSuitability` asks light as one bit - the plant's sun tolerance against the place's stated level.
A crop is the one kind of plant for which that bit is not enough: full sun is the letter of the
requirement, but a tomato wants six hours of it and a lettuce will crop on four, and a designer
choosing where the tomatoes go is asking an hours question.

`CropSun` joins three things and invents none of them: the **stated level** turned into an hours span
by a written-down convention (`LEVEL_HOURS` - full sun, part shade, full shade, three bands); the
crop's own `sun_hours_tenths`; and the **site's own longest day**, from the sun study, which is the
ceiling no spot can beat - a crop wanting eight hours at a latitude whose longest day is seven is not
badly sited, it is in the wrong country.

**What it does not do is measure the shade of a thing.** What a bed really gets depends on the wall
beside it and the tree over it. So the page says *this ground is stated as part shade, which is three
to six hours, and a tomato wants six*, and never claims this bed gets five point two hours.

### 2.6 The climate is two dates, and they are kept with the drawing

A gardener states a climate as two dates: the last frost of spring and the first frost of autumn.
Everything else is arithmetic on that pair - how many days the season runs, and whether a crop taking a
stated number of days from sowing to harvest has that many to spare before the frost returns.

They are kept with the drawing, beside the latitude, because they are the same kind of fact about the
same site. A drawing that states no season is not treated as a mild one: `GrowingSeason` reports
`the growing season is not stated` and every crop checked against it is **unknown**. The Site menu shows
that same sentence where the season would be, so the missing input is visible in the place a person
would set it.

### 2.7 Companion planting is convention, and the module says so

Most of what a seed packet says about what grows beside what is tradition rather than research. The
honest thing is not to throw it away and not to dress it up: the module holds a **short** table, says in
its own doc comment that it is mostly convention, and now says **per pairing** whether it is a mechanism
somebody has looked into or a thing repeated. The recommendation and its standing are not the same
claim, and a page that shows one without the other is the page this section exists to prevent.

### 2.8 A companion is read at the level it is stated: a plant before its family

The companion knowledge is in **two layers**:

* the **families** a pairing groups - a herb among the fruiting crops, an allium kept from a legume;
* the **plants** a pairing names - marigold, and fennel.

**A pairing that names a plant is read before one that names only its family.** This is one rule and it
is load-bearing: without it a table can only ever repeat what it already said about a family, and it can
never learn anything about one plant. Fennel is the case that proves the need - the family table says a
herb grows well beside a nightshade, and fennel is the herb that does not - and marigold is the case that
proves the other half, because marigold is an ornamental that rotates with nobody, belongs to no family,
and is the best-stated companion in the file. No family row could ever reach it.

Two further rules keep this from becoming a second opinion standing beside the first:

* **A pairing is read between plants somebody has named.** A subject the caller has given us only the
family of is answered by the family table and by nothing in the plant layer, so a rule about one plant
can never quietly become a rule about the whole family it sits in. This is what keeps the family API
(`companion_line`, `companion_finding`) answering exactly as it always did.
* **Where two pairings fit equally exactly, the order is decided rather than left to the file.** The
pairing that names *this* plant is read before one that merely permits it, and a warning is read
before an encouragement - the verdict's own ordering rule, where something against the crop outranks
something for it. That last is why a bean is told to keep away from fennel even though marigold goes
with it.

And a plant whose own rule asks nothing of the plant opposite - *with whatever is growing* - is answered
by that rule **alone**: its family words cannot sit beside it, because they would say the opposite of
it. Fennel's line is `should be kept from whatever is growing`, and marigold's is `grows well with
whatever is growing`.

### 2.9 Every pairing says how it is known, and where it came from

A claim with no author is the thing this project does not write. Every entry in the plant table names:

* an **outcome** - a good pairing or a warning, in the same two words the verdicts use;
* a **nature** - `NATURE_KNOWN` for a mechanism somebody has looked into and named, `NATURE_TRADITION`
for what a seed packet repeats;
* a **source**, one work or a list of them, held in `COMPANION_SOURCES` with its title and a note;
* a **why** - why the pairing is said to hold, in the source's own terms, and carrying the limit as well
as the claim.

A test holds every one of those to its table, so a pairing cannot be added without saying where it came
from. **One pairing, one entry**: two entries about the same two plants would be two answers to one
question, and the second would never be read.

The marigold entry is the model for the rest. Its roots release a compound toxic to the root-knot
nematode, which is a mechanism and is cited as one - and the same entry says plainly that it makes
marigold a **rotation rather than a neighbour**: the ground is given to the marigolds for a season and
the benefit shows the year after, which is the opposite of the folklore about planting one beside a
tomato.

### 2.10 What grew in a bed last is stated by a person, not drawn

A drawing was never told a season. *What grew here last* is a thing the person standing in the garden
knows, so `RotationWindow` keeps it, per bed, **in memory while the page is up**, and the module is handed
it rather than reading it from the document. Pretending a plan remembers a year it was never in would be
the same defect as a zero standing in for an answer.

## 3. Data models

### 3.1 The edible half of a species

| Field | Meaning | Zero means |
|---|---|---|
| `edible_parts` | bits: leaf, fruit, root, bulb, stem, flower, seed | the catalogue does not say this is food |
| `harvest_months` | bits, bit `month - 1` set, circular | no harvest window recorded |
| `maturity_days` | days from sowing to first harvest | no time to maturity stated |
| `sun_hours_tenths` | direct sun wanted, in tenths of an hour | no sun requirement stated |
| `yield_per_plant_g` | what one plant gives in a season | no yield stated |
| `need_per_person_g` | what one person eats in a season | no need stated |
| `family` | one of nine families, or `FAMILY_NONE` | the plant is not rotated |

Tenths and grams rather than floats, and whole centimetres for the sizes, for the reason the whole
catalogue is: a rule of thumb that is compared and round-tripped must come back equal to itself.

### 3.2 The families

Nine: brassica, nightshade, legume, allium, root, cucurbit, leafy, fruiting, herb. `HERB_FAMILY` is
spelled that way deliberately, because `HERB` is already the ninth **category**, and a second meaning
for one word is how two tables come to disagree about it.

### 3.3 The companion tables

Two layers, in `crop_rotation.gd`, which is the one place that answers what stands beside what:

* `COMPANION_GOOD` and `COMPANION_BAD` - unordered pairs of **families**, read as a symmetry so the
table cannot disagree with itself about which way round a pairing goes.
* `COMPANION_PLANTS` - the **named** pairings. Each side of an entry is one of four shapes:

| Side | Means |
|---|---|
| `{id: ...}` | a species in the catalogue, by id |
| `{name: ...}` | a plant by name, whether or not this list has it |
| `{family: ...}` | a group |
| `{any: true}` | whatever is growing |

`{any: true}` answers a subject that **names a plant** and never a subject that is only a family. A
`{name: ...}` rule is how a pairing about a plant this list has not got is carried rather than lost: the
day a carrot arrives, the rule about dill and carrot is already right and nobody had to remember it.

### 3.4 The site's season

The last frost day and the first frost day, kept with the drawing beside the latitude, both between 1
and 366 (a frost date is stated to the day, so a leap year is the ceiling a date is clamped to rather
than a claim about which year it is). The growing-season and sowing work is part of the drawing document,
which is at **version 11**.

## 4. The algorithms

### 4.1 The light check

`CropSun.check(crop, profile, site, place)` asks the crop's stated hours against the band the ground's
stated level stands for, and puts the site's longest day beside it as the ceiling. Findings come back in
the same `{key, label, wanted, found, outcome, because, brief}` shape `PlantSuitability` uses, so the two
can sit on one page. `check_at` is the same question for a crop at a point, reading the zone map.

### 4.2 The rotation check, and the company check

`CropRotation.check(crop, previous_family, beside, place)` asks two questions and returns the worst
answer:

* **The turn.** The same family shall not follow itself in the same bed - a brassica after a brassica
shares its pests and its diseases year on year. A **legume** in front of a crop is a good thing,
because beans and peas leave the ground richer than they found it. A bed whose history nobody stated
leaves the turn unchecked.
* **The company.** What is already standing beside the crop, which arrives as a list of stated families.

`rows()`, `row_texts()`, `counts()` and `describe_rows()` are the same check turned into the list a page
shows - every edible species in the catalogue against one bed, sorted by verdict and then by name so the
list is the same twice running.

### 4.3 Which companion pairing wins

`company_pair(first, second)` is the one place a precedence is decided. It scores every named pairing
that fits both subjects:

score = weight * 100 + on_subject * 10 + caution

where `weight` is how exactly the pairing states itself (a plant beats a family beats *whatever is
growing*), `on_subject` is how exactly it names **this** plant, and `caution` is 1 for a warning. The
best score wins; the family table's own answer is used when nothing in the plant layer fits. A tie is
then impossible unless the two pairings are the same pairing, which the table is not allowed to contain.

Around it: `subject_of(plant)` turns a species into the little dictionary the pairings match against;
`company_names(catalogue, subject)` lists the plants **in this list** that a pairing names with this one;
`company_line` and `company_reason` are those as the two lines a page shows; `universal_pair` finds a
plant's own *whatever is growing* rule; and `company_finding` is the same answer in the finding shape a
verdict can carry. `companion_line` and `companion_finding` are the family-only entry points, kept so a
caller that holds only families - and the tests written before this layer existed - are answered exactly
as before.

### 4.4 The harvest calendar

Pick a month and read every crop the list records as ready then, with what of each is cut.
`HarvestCalendar` needs no drawing, because when a crop is ready is a fact about the crop. It opens on
the month with the most in it rather than on a blank January; a crop with no recorded window is counted
apart; and a month with nothing ready simply says so.

### 4.5 The season

`GrowingSeason.length_days(last_frost, first_frost)` is the window, and `check` asks whether a crop's
stated days to maturity fit inside it. A finish within `TIGHT_DAYS` (14) of the frost is *tolerated*
rather than good, which is the honest word for a crop that only just makes it.

### 4.6 Sowing, and a succession

`SowingPlanner` is the season read as a calendar. The last day a crop may be sown is
`first_frost - maturity_days`; with the last frost as the earliest safe day, that pair is the crop's
**sowing window** - the one number a seed packet never prints, because it depends on where you are. A
day of sowing plus days to maturity is a day of harvest, and it either lands before the frost or not. Sow
the same crop again every few weeks - a **succession** - and the harvest moves on rather than ripening
all at once; what comes out is the list of sowing dates and the span they cover.

What it does not claim: that a seed will germinate, or that a stated day to maturity is more than a
guide. It is arithmetic on two stated facts and says so.

### 4.7 How much to plant

plants one person needs = how much a person eats / how much one plant gives

`PlantYield` joins `need_per_person_g` against `yield_per_plant_g` and adds a stated **spare** percentage
on top, because no garden gives every plant whole and the number a person plants is always a little more
than the sum. The spare is stated rather than hidden, so the answer can be checked. `order_rows` writes
the result in the row shape `PlantOrder.plan` takes, so a yield plan prices a nursery order through the
same module as the yard's own planting, with no second set of arithmetic.

## 5. The pages, and where they are reached

| Page | Menu entry | Needs |
|---|---|---|
| `FoodWindow` | Plant > What will crop here... | the drawing - a bed's light is stated on the plan |
| `RotationWindow` | Plant > What to grow here next... | the drawing - for the bed names; the history it holds itself |
| `HarvestWindow` | Plant > What's ready when... | the plant list alone |
| `SowingWindow` | Plant > When to sow... | the drawing and the list |
| `YieldWindow` | Plant > How much to plant... | the plant list alone |
| `SeasonWindow` | Site > How long the season is... | the drawing - the season lives there |

The two that need nothing but the list are the two whose answer is a fact about the crops rather than
about the ground; the season page sits in the Site menu because it is a fact about the site, and the
Site menu also shows the season as an **info line**, so a season nobody has stated is visible in the
place a person would state it.

Every page is a `Window` that takes its model and states what it cannot work out rather than showing a
zero. `RotationWindow` states its own history per bed and says which bed's the history is; a page that
showed the same sentence twice is a page that has lost track of which line is which.

## 6. Requirements

1. A crop is a `PlantSpecies` from the catalogue. No model here keeps a second table of crops.
2. Every figure that cannot be worked out is refused by name, naming the missing input.
3. A verdict that could not be asked is `UNKNOWN`, and is never drawn in the good colour.
4. The four verdicts and their colours come from `PlantSuitability` and are not restated.
5. `CropSun` reads the ground's **stated** level and the site's longest day, and never claims to measure
the shade of a wall or a tree.
6. A season nobody stated is refused as a season, and every crop checked against it is unknown.
7. A pairing that names a plant is read before one that names only its family.
8. A pairing is read only between subjects that name a plant, so the family answer is unchanged by the
plant layer.
9. Where two pairings fit equally exactly, a warning is read before an encouragement.
10. Every named pairing carries an outcome, a nature, a why and at least one source that exists.
11. One pairing, one entry.
12. `HarvestCalendar` and `PlantYield` answer with months and counts and borrow no verdict vocabulary.
13. `PlantYield.order_rows` is the shape `PlantOrder.plan` takes.

## 7. What is built, and what is not

**Built:** the six models, the six pages, their menu entries, the two-layer companion table with its
sources, the in-app manual subjects for the food garden, and the tests below.

**Not built, and worth stating:**

* **No measurement of shade.** `CropSun` reads a stated level and a latitude. A wall's shadow is the sun
study's business, and it says as much itself.
* **No companion table for plants this list has not got.** The pairings for tomato, carrot, nasturtium
and fennel are in the file and are correct, and the catalogue is an ornamental nursery list whose only
food is a herb corner - so most of them are dormant. They are written so that they are right the day a
vegetable arrives, and until then the honest answer is that nothing in this list is named with the
crop.
* **No succession of different crops.** A succession is the same crop sown again every few weeks. What
follows what *between* crops is the rotation, which is a question about families and about a year.
* **Nothing here draws**, and nothing here writes the document: these pages are read, chosen on and
closed.

## 8. The tests, and what they hold down

| Test file | What it holds down |
|---|---|
| `test_crop_sun.gd` | the hours band, the site's ceiling, the never-green rule |
| `test_crop_rotation.gd` | the turn, the family table, and the named pairings - plant before family, a warning before an encouragement, a plant with no family, and every pairing's source |
| `test_rotation_window.gd` | the page: the history per bed, the ranked list, the company line and the reason line |
| `test_harvest_calendar.gd` | the twelve months, the busiest month, the crops counted apart |
| `test_growing_season.gd`, `test_season_window.gd` | the window, the frost dates, the page |
| `test_sowing_planner.gd`, `test_sowing_window.gd` | the sowing window, the succession, the page |
| `test_plant_yield.gd`, `test_yield_window.gd` | the counts, the spare, the hand-off to the order |
| `test_food_window.gd`, `test_plant_edible.gd` | the crop check page, and the edible fields themselves |
| `test_hud_season.gd`, `test_hud_sowing.gd`, `test_hud_yield.gd` | the menu entries that reach the pages |
