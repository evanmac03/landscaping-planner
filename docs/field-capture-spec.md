# The field capture: what is on site, brought back into the drawing

Somebody stands in a garden with a phone. They photograph a shrub, say what they think it is,
pace out how wide it is, and write down that the bed is dry. That visit is the beginning of every
job this program prices, and until this specification it arrived as a memory and a camera roll.

This is the record of how it arrives as data instead: one capture per plant, one manifest per
visit, one photograph per capture, and a measurement where somebody took one. Nothing in it needs
a network, and nothing in it needs a model to be installed.

## 1. The shape of it, and why each part is where it is

| part | file | what it holds |
| --- | --- | --- |
| the record | `scripts/field_capture.gd` | one plant seen on site: where it is, what it was called, what was photographed, how big it was |
| the photograph | `scripts/field_photo_store.gd` | a picture kept under a name made from its own bytes |
| the file | `scripts/io/field_manifest_exporter.gd` | a visit as a manifest, written atomically and read back |
| the import | `scripts/survey_watcher.gd` | the manifest noticed, its plants placed, its names filed |
| the choice | `scripts/plant_id_choice.gd` | the four ways a photograph can be read, and what the chosen one still needs |
| the request | `scripts/plant_id_llm.gd` | the request a model is asked, and the reading of its answer |
| the seam | `scripts/plant_identifier.gd` | the pipeline that runs the chosen way, and the one path into a record |
| the page | `scripts/field_window.gd` | the window a person uses on this machine to record a capture |
| the door | `scripts/hud.gd` | Site > Record what is on site... |
| the output | `scripts/vis/proposal_page.gd` | the photographs on a proposal page, captioned in words |

Four of those are pure: no scene, no node, no file. The page and the door are the only two that
need a running program, which is why the whole subsystem is testable without one.

## 2. One capture, and the two ways it can be true

A capture is a Dictionary, not a class instance, because it is written to JSON and read back and a
round-tripped record cannot be compared with `==` anyway. `FieldCapture` is the set of functions
that make and check one:

* `unidentified(position, photo_path, note, part)` - somebody saw a plant and could not name it.
* `identify(raw_taxon, confidence, catalogue, ...)` - a name was offered, and this says whether the
  catalogue accepts it. It answers `{ok, reason, capture}` and the capture is `identified` only when
  the resolver's own floor was met.
* `from_record(feature)` - a record read back out of a manifest, with every key given a default so
  a manifest written by an older tool still reads.
* `validate(capture)` - what a manifest has to satisfy before it is imported.
* `words(capture, catalogue)` - the one place a capture is turned into a sentence. A proposal
  caption, a page's status line and a missing-photograph sentence all come from here.
* `size_of(capture, species)` - how big the plant is, and where that number came from.

**A name below the floor is not a name.** `PlantIDResolver` has `CONFIDENCE_EXACT` and
`CONFIDENCE_FUZZY`, and a capture under them is *unidentified*: it keeps the words that were
offered in `raw_taxon`, and it is never silently rounded to the nearest species. A survey is a
record of what somebody saw, including what they could not name.

**A zero means not stated.** `measured_height_m` and `measured_spread_m` are zero when nobody
measured, and `size_of` then answers with the catalogue's own figure and says so. A plant that was
never measured must not be printed as one that measured zero.

## 3. The photograph is named by its own bytes

`FieldPhotoStore.add(source, folder)` keeps a picture under `user://field_photos/<16 hex>.<ext>`,,
where the hex is the first sixteen characters of the file's SHA-256 and the extension follows from
the format its header declares rather than the name it arrived under. So:

* the same photograph arriving from two phones is one file, and `duplicate` is true;
* two different photographs can never collide;
* a JPEG called `.png` is kept as `jpg`, because the header decides.

It does **not** decide what a picture is. `RasterUnderlay.sniff` is the one reader in this program
that establishes a file's format from its header, and this class delegates to it and repeats its
refusal sentence, so the two doors tell a person the same thing about the same file.

`for_page(captures, catalogue)` is the join to the proposal: it loads each capture's photograph,
captions it with `FieldCapture.words` plus the part photographed, and returns every photograph it
could open plus a sentence for every one it could not. How many fit on the page is the page's
question, not the store's, so there is one cap in the program.

## 4. The manifest, and the one writer

`FieldManifestExporter` is the only thing that writes a survey file. `export_manifest` writes to a
temporary file and renames it into place, so a save that fails never leaves a shorter file where
the real one was - and `save_to_file` and `export_survey`, the two doors that wrote in place, are
gone rather than left beside the safe one.

`FORMAT_VERSION` is 2. Version 2 added `raw_taxon` (what the classifier or the person offered) and
`part` (which part was photographed), because a second attempt at the same plant is only a fair
comparison if the first attempt says what it was looking at. A version-1 manifest still reads, with
no upcast; a manifest from a *newer* version is refused by name, because a survey that quietly lost
records is indistinguishable from a smaller survey.

`append(site_name, features, path)` is the desk-side door: it reads what is there, adds only the
records whose identity is new, and refuses rather than replacing a file it cannot read.

**Identity is one answer, asked twice.** `identity_of(record)` is the id a record brought, or one
derived from what the record *is*. The writer asks it to tell an append that would duplicate from
one that would add; `SurveyWatcher` asks it to tell a capture it has already planted from a new one.
Two answers would plant a tree twice. A survey whose tool wrote no instance ids at all still
imports, and still imports once.

## 5. The import: a file becomes plants

`SurveyWatcher` is a `Timer` at 1.5 seconds, not a per-frame hook, and it also looks when the window
regains focus. It reads a manifest whose modified time has changed, plants each feature it has not
seen, and files each identified species into the catalogue's "Field Survey Captures" collection
where the plant browser shows it. An unidentified capture is placed by its photograph and its
position and is *not* filed: there is no species to file it as.

A capture is planted where it was found **even when the drawing says the spot is wrong for it**: a survey is a
record of what is on site, and the import is not the place to overrule the person who was standing
there. What it does instead is ask `ViewController.spot_verdict` about each spot it planted in - the
same door the marker ring uses, so an import and a cursor cannot disagree about a square metre - and
report the answer in one sentence: how many suit the spot, how many are in the wrong place (naming the
first of them, in `PlantSuitability`'s own words), and how many the drawing says nothing about. Silence
is reported as silence, never as a pass.

## 6. The seam where a model would be

`PlantIdentifier` answers one question - what is this a photograph of - and there are now **four
ways it can be answered** rather than one. `PlantIdChoice` is the choice and its settings:
**off**, which is the default and the program this has always been, where a photograph is kept
and the name is typed by a person; **local**, a vision model on this machine or on the person's
own network; **online**, a service the person names; and **local shortlist, then online**, where
the first narrows the photograph to a few likely plants and the second picks between them.
`PlantIdLlm` builds the request and reads the answer, and sends nothing itself.

Three things about it are decisions rather than implementation.

**Nothing is sent until a person chooses a way.** A plant photograph can be somebody's garden,
their address and their neighbour's fence, so the default is off, and each way's own sentence says
what leaves the machine. A key is the same kind of decision: `PlantIdChoice.storable` drops it,
so it is held for the session and typed again the next one rather than written into `user://`.

**A refusal can carry a shortlist.** When the mixed way's first half works and its second cannot
be reached, the answer is not an identification - it names the plants the first half found, and
the page shows the reason and the plants together. Filing the first half's answer would put a
plant on a plan on the strength of half the work.

**The record says who said so.** `capture_from(identification, ...)` is still the single path
from a model's answer to a record, routing through `FieldCapture.identify` so the confidence
floors are the same ones the rest of the program uses, and it carries the model's name and version
onto the capture. A name a person typed is read as certain; a name a model offered is read at the
model's own confidence, and editing it makes it the person's own again. In the mixed way a record
names **both** models, because both of them answered.

**A reading is stepped by a frame, because a model may think for minutes.** Measured:
`tools/plant_id_live.tscn` presses Read the photograph against `qwen2.5vl:3b` on this machine and
counts the frames the program drew while it waited - **15.6 seconds and 26,344 frames** for one
photograph. Before this, a reading was waited for *inside* the call that asked for it, so those same
15.6 seconds drew **no frame at all**: the whole program stopped, the page and the drawing with it,
until the model had finished.

`identify_with` is therefore **nothing but the machine driven to completion** - `begin_read` in a loop
with `step_read`, exactly as `send_http` is `HttpExchange` driven to completion one level down.
`begin_read` settles readiness and encodes the photograph **once**, so the mixed way's second model is
sent the picture the first one was rather than a second reading of the same pixels. `step_read` answers
`WORKING` until a model has answered and `DONE` when there is an answer to read, and `read_result`
refuses in words while there is none, so a page cannot show a half-built record as "the model found
nothing". `waiting_on_the_wire` is what tells a caller whether it may finish a reading in the call that
asked or has to keep drawing: only a reading a socket is answering has to be waited for, so a simulated
one is driven exactly as it was before there was a frame to think about.

`PlantIdLlm` builds the request and reads the answer, and sends nothing itself. A request goes either to
`HttpExchange`, which `send_http` drives on this machine's behalf, or to a `Callable` a test has put in
`PlantIdentifier.transport`, which is why the whole pipeline, refusals and shortlists included, is held
down with no network, no key and no model. `installed()` still answers false, and still honestly: this
build carries no inference engine. A model that is *reached* is a way and its settings, and the line
under the page's dropdown is the seam's own sentence about the way in force.

**An unsure model is asked for a name, not for silence.** The rules every prompt ends with used
to say that if the photograph did not show enough to name the plant, the model should answer
with an empty list, because not knowing is a real answer and a guess is not. That is true, and it
stayed true - but the **first reading of a real photograph against a real model** showed what it
does to a small one. Asked about a clear photograph of a single boxwood, `qwen2.5vl:3b` answered
with an empty list of candidates in **0.2 seconds**, twice, without appearing to look at the
photograph at all. The same photograph and the same prompt with that one sentence changed - name
the plant it most resembles and say so with a low confidence - and the same model answered in
**2.7 seconds** with `Buxus sempervirens` at 0.9, the species this program's own list has, and
`Buxus microphylla` at 0.8 behind it. So the empty list now means the narrower thing it says - a
photograph with no plant in it - and an uncertain name travels **as** an uncertain name, because
a low confidence is already something this program knows what to do with: the floors decide, and
a name below them is kept as offered rather than thrown away.

Everything else that reading proved was already true and is now measured: the request a real
model accepts, a 768-pixel copy of a 1280-pixel photograph sent as base64, an answer wrapped in
a markdown fence and in an extra array - which the reader tolerates by design - and a record
that came out of it carrying confidence 0.9, model id `qwen2.5vl:3b` and species
`buxus-sempervirens`, with the model's second offer kept exactly as written and with no species
at all, because the list had never heard of it. `tools/plant_id_live.tscn` is that reading, and
it is the one proof of this subsystem that asks a model rather than simulating one.

## 7. A stated measurement, and what it changes

Where somebody measured the plant, the measurement is what the plan uses: `PlantPlacement.place`
takes a `size` Dictionary and substitutes the measured spread into the species' own ratio, rather
than growing a second sizing engine beside `PlantSpacing`. The node records where its size came
from in `SIZE_SOURCE_META` - `stated` or `catalogue` - so a plan can never quietly present a
guess as a measurement.

## 8. The page

Site > Record what is on site... opens `FieldCaptureWindow`: species (chosen from the game's own
list), which part was photographed, the sun and drainage bits through `BitMaskUtils`, the position,
the height and spread in metres, a photograph and a note. It refuses by name: a capture with no
species and no photograph says exactly that, and a size that is not a number says which field.
The page names the photograph folder as a member so a test never writes to the real one.

The page can also **read** the photograph. Which of the four ways it is read by is a dropdown
on the page itself, in `PlantIdChoice`'s own words, and the rows a way needs - an address, a
name, and a key that is masked - are built from `PlantIdChoice.fields_for`, so a way asks only
for what it uses and which field is a secret is decided in one place. Reading with nothing chosen
refuses by name and sends nothing at all.

**The page steps the reading rather than waiting for it.** Pressing Read the photograph *begins* a
reading and returns; the page's own frame advances it and puts the answer on the page when it lands,
which is what `reading_finished` announces. While a model is thinking the status line and the hint say
so and the button is disabled, because a second press would start a second reading over the first, and
two models thinking about one photograph is a queue nobody asked for. `identify_photo` still answers the
reading's own answer when the reading had nothing to wait for - a way that refuses before anybody is
asked, or a `transport` a test handed over - so a page driven by a test is unchanged, and it answers the
still-reading refusal when it did have something to wait for. What the last reading said is
`the_reading()`, and `is_reading()` is whether one is in flight.

## 9. The photographs on a proposal

`VisProposalPage` can carry up to three photographs beneath the still, in a strip 46 mm deep that
the drawing gives up rather than having pictures pasted over it. Each photograph is fitted at one
scale inside a slot no wider than 96 mm, and captioned in words. The PDF carries the caption; the
raster preview carries a tint where the caption will print, because drawing glyphs into an `Image`
needs a canvas item - the same split the page already makes about its title block. A page handed
more than three photographs says how many it left out.

## 10. The camera in your hand

A person standing at the plant has a camera and no file, so the page has two doors onto a
photograph rather than one: **Choose a picture...** for anything already on the device, and **Take
a photo...** for what is in front of you. The second opens `CameraWindow`, whose shutter files what
it saw through the same `FieldPhotoStore` as the first - so the two doors leave the page in one
state, and a photograph is kept once, in one folder, under one rule.

The camera is `CameraServer`'s, and three things about it are worth writing down, because each of
them is a way to get nothing worth keeping on the screen:

* **A feed will not start without a size chosen.** `CameraFeed.set_format(index, {})` comes *before*
  `set_active(true)`. Without it the engine refuses in as many words - "CameraFeed format needs to be
  set before activating" - and a picture is drawn that is not the picture. The page picks the largest
  frame no wider than 1920, so a plant arrives sharp without a four-thousand-pixel frame being drawn
  every frame and read again when the shutter is pressed.
* **`which_feed` is not a promise.** The three plane constants (`FEED_RGBA_IMAGE` and `FEED_Y_IMAGE`
  are both 0, `FEED_CBCR_IMAGE` is 1) mean what the feed's own data type says they mean, and a feed
  that carries brightness in red and colour in green and blue has to be put back together by a shader.
  Drawing it as it stands shows the colour as if it were brightness, and a plant comes out a magenta
  cloud. Which shape needs how many textures is `CameraCapture.planes_for`, decided without a device
  in sight and tested without one.
* **The permission is Android's, and it is asked for once.** `CameraCapture.ANDROID_CAMERA` is
  requested when the page opens, and a camera nobody has allowed is not switched on: the feeds are
  listed *before* the grant, so a page that attached on the first frame it saw would run a camera for
  a program that was told no. Four states are told apart rather than shown as one black square - no
  camera, no permission, allowed but not answering yet, and ready - and each says what is missing.

The shutter photographs the page rather than the feed, because a feed is drawn and not read: the
frame comes from the viewport with the chrome put away for the one frame the grab happens in, and
what is kept is the viewfinder's own rectangle - so the photograph is of the plant and not of the
button. The camera is the device's, so it is a phone's door; on a computer the same button asks for
a webcam, and says plainly when there is none.

What this program does not do is read the photograph **unless it is told which way to read it**:
a photograph is kept and sent nowhere until somebody chooses a way, and sections 6 and 12 say
what follows from that choice.

### What the camera actually handed over, and what this program has to do about it

Found by measuring on the glass rather than by reading the code, after the viewfinder came up as a crimson
rectangle with a legible silhouette inside it. On the SM-A166W, over a third of a million pixels of the drawn
frame: red 0.0162, green 0.0000, blue 0.0000. A camera cannot see a scene with exactly no green and no blue in
it, so the picture was not wrong at its edges - the *frame* was: the engine hands this feed over with the
brightness in red and the other two channels empty, and calls it `FEED_RGB` while doing it.

Three things followed, each measured rather than assumed:

- Asking the feed for a different *shape* (`set_format(index, {"output": "separate"})`) is honoured for a
  Linux camera stream and ignored on Android, which answers with the shape it was going to use anyway. The
  page no longer asks, and says in the code that it tried.
- The renderer this program draws with everywhere does not put a camera's frame together for us, and does not
  say so in the frame. `CameraCapture.reads_apart(has_rendering_device, datatype, ycbcr_separated)` is that
  rule: with no rendering device the frame is read as the camera made it - brightness in one texture, colour
  in the other - and with one, only the shapes that are genuinely split are. The machine's own answer is an
  argument to that function and never an assumption inside it, which is what lets a test on a computer that
  has both a camera and a rendering device hold the rule down.
- With that in place the same dark frame arrives with all three channels alive and every one of its pixels
  carrying colour (0.0315, 0.0121, 0.0524), where before it was one channel and two exact zeroes.

The decoder had a fault of its own, found in the same pass. For a feed that carries brightness and colour in
*one* texture, the two colour halves share the green channel, one to a pixel - the layout the engine's own
Android camera work uses - and the first version read the red difference out of blue, which carries nothing at
all on such a frame. It is `CameraWindow.DECODING_SHADER`, held as a constant so a test can read it, with
`test_the_decoder_looks_for_both_colour_halves_in_the_one_channel_that_carries_them` over it.

Still owed: the phone this was measured on was sitting in the dark, so the *colour balance* of a lit scene has
not been seen since the change. The numbers say the channels are alive and carrying colour; they do not say a
leaf is the right green. One photograph of something lit settles it, and it is the next thing to do.

### Two more things the glass taught, both of them silent from inside the program

**Applying the frame's own turn was tried and reverted, and the reason is worth keeping.**
`CameraFeed.feed_transform` is documented as "the transform applied to the camera's image", and its
*default* is `Transform2D(1, 0, 0, -1, 0, 1)` - the very mirror the SM-A166W reports, rotation zero
and determinant minus one. So the device was not asking for anything unusual: it was reporting a
default the engine already accounts for, and applying it in the viewfinder flipped a picture that was
already the right way up. It was reverted the same day, along with the cover-scaling that went with it
and `CameraCapture.turned_size` / `cover_scale`; the viewfinder is drawn with
`STRETCH_KEEP_ASPECT_COVERED` again. **A default is a value the engine may already have honoured**, so
"the device says so" is not by itself a reason to apply it - the camera said the same thing before the
change, and the picture was right then.

**A shader that does not parse is drawn as the feed itself.** On this phone that is a crimson
rectangle - the same symptom as the channel fault above, from an entirely different cause, and one that
says nothing anywhere unless it is looked for. It cost two device round trips, and both mistakes that
caused it are facts about the shading language rather than about this program: a fragment built-in
(`UV`) **is not available inside a helper function** and has to be passed in, and a bare `return;` is
not allowed in a `void` fragment function. `test_the_viewfinder_shader_is_one_that_actually_compiles`
now builds a `Shader` from `CameraWindow.DECODING_SHADER` and asks how many uniforms it declared: a
question that needs no renderer, that answers zero for a shader which failed to parse, and that would
have caught both mistakes before the first export.

**What the shutter keeps is what the viewfinder shows.** Confirmed twice in a row: with the camera
pointed at a lit desk the kept photograph matches the picture on the page, and with the lens covered
the kept photograph is the same flat dark frame the page was showing - 2,715 bytes of nobody's desk is
what the camera was looking at. The photograph is a grab of the page, so this is the one property that
matters, and it is now a measured one rather than a hoped-for one.

## 11. What was rejected

* **Depth from one photograph.** A height estimated from a single still is a number nobody measured,
  and this program's whole discipline is that a number that was not measured stays absent.
* **`node.set_meta("field_photo", path)`.** The record carries the photograph. Copying a path onto
  a scene node makes a second copy of the truth that nothing keeps in step.
* **A photograph folder with no content address.** `IMG_2043.jpg` from two phones is a survey that
  lost evidence without saying so.
* **A second magic-byte reader.** `RasterUnderlay.sniff` already answers "what is this file", and a
  second answer could disagree with it about the same file.
* **A second sizing engine.** `PlantSpacing` owns how big a plant is drawn; a measurement is an
  input to it, not a parallel calculation.
* **An API key written down beside the settings.** `user://` is a folder people copy, back up
  and hand to somebody when they ask for help, and a key that travelled with it would be spending
  their account on another machine. So a key is held for the session and typed again: what a file
  may hold is what `PlantIdChoice.storable` allows, and what a person or a log may read is
  `sanitised`, which says a key is set without saying what it is.
* **Filing the local half's answer when the online half cannot be reached.** A first look is not
  a settled identification, so the refusal carries the shortlist and the page shows the reason and
  the plants together.

## 12. What is not built

The **engine**. This program has no inference of its own: `PlantIdentifier.installed()` is
false, and there is no weights file, no runtime and no dependency here that could read a
photograph. Every way of reading one therefore reaches a model somewhere else - one on this
machine, or a service - and that is a deliberate boundary rather than a gap, because it is what
keeps the default possible at all: a program that shipped its own classifier would have shipped
a decision about what leaves the machine along with it.

What has **not been proved on the glass** is a whole reading end to end. The pipeline is held
down by a simulated transport, which proves what this program decides - the request it builds,
what it does with a shortlist, what a refusal carries - and proves nothing about whether a given
local model answers usefully, or whether a service's reply is shaped the way `PlantIdLlm` reads
it. The first person to point the page at a running model, and at a service with a real key, is
the one who finds out. The refusal sentences are written to be worth reading when they do.

And one thing the same reading found is **a fault rather than a gap**: a reading **blocks the
program** while the model thinks. `_send` waits for the answer on the clock - which is the fix
for the first fault the reading found, a loop that counted polls and gave up in milliseconds
before a vision model had finished - and it waits *inside the call*, so the window does not
draw a frame until the answer arrives. With three minutes allowed, a page that pressed Read
the photograph on a slow model would be frozen for up to three minutes: survivable in a tool
and not survivable on a phone. The evidence is the playtest harness refusing to carry on - in
its own words the main loop stopped, no frame completed in the last 51 seconds, and the code
blocking it was in `_ready` - which is why the reading was then run under an instrument with no
watchdog at all. The fix is a reading that waits **across frames** or on a thread; it is not a
smaller number of seconds.
