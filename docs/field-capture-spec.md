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
| the seam | `scripts/plant_identifier.gd` | where a classifier would answer, and the refusal when none is installed |
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

`PlantIdentifier` answers one question - what is this a photograph of - and the answer installed
today is the refusal: `NOTHING_INSTALLED`, naming what a model would have to be. `installed()` is
false, `identify()` refuses, and `capture_from(identification, ...)` is the single path from a
classifier's answer to a record, routing through `FieldCapture.identify` so the confidence floors
are the same ones the rest of the program uses. A model is a change to one function, not a change
to the page, the manifest or the import.

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

## 9. The photographs on a proposal

`VisProposalPage` can carry up to three photographs beneath the still, in a strip 46 mm deep that
the drawing gives up rather than having pictures pasted over it. Each photograph is fitted at one
scale inside a slot no wider than 96 mm, and captioned in words. The PDF carries the caption; the
raster preview carries a tint where the caption will print, because drawing glyphs into an `Image`
needs a canvas item - the same split the page already makes about its title block. A page handed
more than three photographs says how many it left out.

## 10. What was rejected

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

## 11. What is not built

The identification model itself, a spoken plant name, and any upload: this is the side of the
subsystem that receives a file and records a capture on the desktop. The record, the page, the
manifest, the import and the proposal are here and tested; the classifier is a seam waiting for
one function to be written.
