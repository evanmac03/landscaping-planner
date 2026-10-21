class_name EstimateDesk
extends RefCounted
## The takeoff and the estimate, gathered into one thing the interface can hold and report on.
##
## The four business engines - the cost book, the takeoff, the estimate and the tax table - were
## built and tested before anything could reach them (spec §14 phases 0-3). They are pure: a takeoff
## is produced *from* a drawing and a book, an estimate is produced *from* a takeoff and a book, and
## neither knows that a screen exists. This class is the join, and it is deliberately thin - it holds
## the three objects, runs the two hand-offs the engines already define (`Takeoff.of_plan` and
## `Takeoff.estimate`), and answers the questions a panel asks in words.
##
## It is **not** a fifth engine and it holds no arithmetic of its own: every figure it shows comes
## from `Estimate.summary` or a line's own `line_text()`. An estimate desk that recomputed a total
## would be a second place for the rounding rule to live, and the two would drift.

const TakeoffScript := preload("res://scripts/biz/takeoff.gd")
const EstimateScript := preload("res://scripts/biz/estimate.gd")
const BookScript := preload("res://scripts/biz/cost_book.gd")
const MoneyScript := preload("res://scripts/biz/money.gd")
const TaxScript := preload("res://scripts/biz/tax.gd")
const WorkUnitScript := preload("res://scripts/biz/work_unit.gd")

## The starter book, shipped with the program. A business replaces it by writing its own to
## `CostBook.DEFAULT_PATH`, which is what `load_book` looks for first.
const SHIPPED_BOOK := "res://data/biz/costbook.json"

## Where a proposal written from here goes. A drawing lives in `user://drawings`; what a drawing was
## priced at lives beside it rather than somewhere else.
const PROPOSAL_DIR := "user://biz/proposals"

## The default tax code for a new estimate. `NONE` is a real zero-rated code and not the absence of
## one (spec §15.4), so an unstated jurisdiction is still a statement.
const DEFAULT_TAX := &"NONE"

## The drawing being measured, or null: this desk works in a scene with no drawing, and says so.
var document: DraftDocument = null
## The price list. Null until `load_book` has found one.
var book: BookScript = null
## Where the book was read from, in words, so a proposal can say which prices it used.
var book_source: String = ""
## The last measurement. Null until `take_off` has run.
var takeoff: TakeoffScript = null
## The last pricing, or null. Always the estimate that goes with `takeoff`.
var estimate: EstimateScript = null
## The lines the takeoff could not price, in sentences: an item the book does not cover is named
## rather than dropped, because a proposal that silently omits a patio is worse than no proposal.
var refused: Array[String] = []
## The planting list the takeoff counted, if one was handed in: rows of `{id, count, ...}` from
## `PlantPlacement.schedule`. Empty means "plants are drawn on the drawing, not standing in a yard".
var plant_rows: Array = []
## Which tax applies. Changing it re-prices, because the code is the estimate's *default* for a line
## and a line that was already added kept the code it was added with.
var tax_code: StringName = DEFAULT_TAX
## The customer the estimate is for: `{name, address, email}`. A proposal with nobody on it is a
## draft, and `freeze` refuses one.
var customer: Dictionary = {}


# --- what it holds -------------------------------------------------------------------------


## Point the desk at the drawing it is going to measure. The drawing is the only thing here that
## arrives from outside; everything else the desk reads or makes itself.
func bind(document_ref: DraftDocument) -> void:
	document = document_ref
	takeoff = null
	estimate = null
	refused.clear()


## Read a price list. The user's own book wins over the starter one, because a business that has
## written its own prices means them.
##
## Returns `{ok, reason, source, book}`. A book that will not load is **refused and named** rather
## than replaced by the starter one silently: pricing a job from prices nobody chose is how a
## proposal goes out wrong with everybody believing it was right.
func load_book(path: String = "") -> Dictionary:
	var wanted: Array[String] = []
	if not path.is_empty():
		wanted.append(path)
	wanted.append(BookScript.DEFAULT_PATH)
	wanted.append(SHIPPED_BOOK)
	var tried: Array[String] = []
	for candidate: String in wanted:
		if not FileAccess.file_exists(candidate):
			continue
		tried.append(candidate)
		var loaded: Dictionary = BookScript.load_from(candidate)
		if bool(loaded["ok"]):
			book = loaded["book"]
			book_source = candidate
			return {
				"ok": true,
				"reason": "",
				"source": candidate,
				"book": book,
			}
		# A file that is there and will not load is the answer: it is what the office meant to use.
		return {
			"ok": false,
			"reason": "%s: %s" % [candidate, String(loaded["reason"])],
			"source": candidate,
			"book": null,
		}
	return {
		"ok": false,
		"reason": "there is no cost book at %s" % ", ".join(PackedStringArray(tried)),
		"source": "",
		"book": null,
	}


## Whether there is a book to price with and a drawing to measure.
func is_ready() -> bool:
	return book != null and document != null


## The tax codes a line may carry: the shipped table plus whatever the book brought with it, in the
## order the tax table lists them so that the ordinary code is first.
func tax_codes() -> Array[StringName]:
	var out: Array[StringName] = []
	for code: StringName in TaxScript.CODES.keys():
		out.append(code)
	if book != null:
		for code: StringName in book.tax_codes.keys():
			if not out.has(code):
				out.append(code)
	return out


func tax_code_name(code: StringName) -> String:
	# The book's own code first, because a code a business added lives in its book and not in the
	# table the program ships: asking only the table would name a real code after itself.
	var entry: Dictionary = book.tax_code(code) if book != null else TaxScript.code(code)
	var label := String(entry.get("name", ""))
	return label if not label.is_empty() else String(code)


## Choose the tax. Re-prices when there is something priced, because the code is the *default* an
## estimate hands to its lines, and lines already added kept the code they were added with.
func set_tax_code(code: StringName) -> bool:
	if not tax_codes().has(code):
		return false
	tax_code = code
	if takeoff != null:
		take_off()
	return true


# --- measuring and pricing -------------------------------------------------------------------


## Measure the drawing and price what can be priced, in one step: what the button on the panel does.
##
## Returns `{ok, reason, measured, priced, refused, notes, problems}`. `ok` means the takeoff ran, not
## that everything on the drawing has a price - `refused` is where the lines that do not are named,
## and it being non-empty is the ordinary case for a plan with anything on it the book does not cover.
func take_off() -> Dictionary:
	if document == null:
		return _no_takeoff("there is no drawing to measure")
	if book == null:
		return _no_takeoff("there is no cost book to price with")
	var measured: TakeoffScript = TakeoffScript.of_plan(document, plant_rows, book)
	takeoff = measured
	var priced: Dictionary = measured.estimate(book, tax_code, book.currency)
	var offer: EstimateScript = priced["estimate"]
	offer.id = EstimateScript.new_id()
	offer.customer = customer.duplicate(true)
	estimate = offer
	refused = []
	# One fault, one sentence. The takeoff and the estimate both notice the same unpriced line, and
	# the takeoff's version of it is the fuller one ("30 plants have no species recorded, so there is
	# nothing to price them with" against "no species recorded has no cost item"), so where the
	# takeoff has already explained a line the estimate's shorter refusal is dropped rather than
	# printed beside it.
	var explained: Array[String] = []
	for line: TakeoffScript.TakeoffLine in measured.lines:
		if line.item_id.is_empty() and not line.description.is_empty():
			explained.append(line.description)
	for reason: String in priced["refused"]:
		var repeated: bool = false
		for description: String in explained:
			if reason.begins_with(description):
				repeated = true
				break
		if not repeated:
			refused.append(reason)
	# What the takeoff itself says is wrong - a line nothing in the book can price - is a refusal too,
	# in the same list, because from the panel's side "what is not priced" is one question.
	for reason: String in measured.problems:
		refused.append(reason)
	return {
		"ok": true,
		"reason": "",
		"measured": measured.lines.size(),
		"priced": offer.line_count(),
		"refused": refused.size(),
		"notes": measured.notes.size(),
		"problems": refused.size(),
	}


func _no_takeoff(reason: String) -> Dictionary:
	return {
		"ok": false, "reason": reason, "measured": 0, "priced": 0, "refused": 0,
		"notes": 0, "problems": 0,
	}


## What the takeoff left out on purpose, with the reason ("a contour is a line, and a grading volume
## needs the levels on either side of it"). Not a fault: a note. It is here because a plan with a
## contour line on it
## and no line for it in the proposal is the question every designer asks, and the answer to "why is
## nothing on my drawing in the takeoff" has to exist somewhere a person will look.
func notes() -> Array[String]:
	var out: Array[String] = []
	if takeoff == null:
		return out
	for note: String in takeoff.notes:
		out.append(note)
	return out


## The layers whose work is bought by a **surface** - measured by the square metre, or by the cubic
## metre once a depth has been stated for them.
##
## These are exactly the layers a depth can be stated for, and only these: a depth is what turns an area
## into a volume, so a layer measured as a count (a planting, a run of irrigation heads) has no area to
## be deep and is not offered. This is the list a panel builds its chooser from, so the choice it offers
## is always one the takeoff can act on.
##
## A layer that **already** states a depth stays on the list, which matters more than it looks: it is
## the list's only way of showing the decision that was made, and a chooser that dropped a layer the
## moment its depth was stated would be a row that hides the depth it had just been told.
func surface_layers() -> Array[StringName]:
	var out: Array[StringName] = []
	if document == null:
		return out
	for layer: DraftLayer in document.layers.layers():
		var measure: StringName = TakeoffScript.measure_for(layer.name)
		if measure == WorkUnitScript.AREA or measure == WorkUnitScript.VOLUME:
			out.append(layer.name)
	return out


## The depth a layer's work is bought at, in millimetres, or 0 when it states none.
func layer_depth(layer_name: StringName) -> int:
	return TakeoffScript.depth_of(layer_name)


## State the depth a layer's work is bought at, and re-take-off if a takeoff has already run, so the
## number the panel is showing changes in the same gesture as the decision.
##
## A depth is a decision about the **practice's own layer** rather than about one drawing - a mulch
## layer at 75 mm is 75 mm on every garden - which is why it is set on the layer table the takeoff
## reads (`Takeoff.set_depth`) rather than stored in a document. Returns false for a layer that is not
## measured or for a depth of nothing, and then nothing has been measured again: a refusal has to leave
## the panel exactly as it found it.
func set_layer_depth(layer_name: StringName, depth_mm: int) -> bool:
	if not TakeoffScript.set_depth(layer_name, depth_mm):
		return false
	if takeoff != null:
		take_off()
	return true


## Forget a layer's depth, so its outlines are measured as the areas they are, and re-take-off when a
## takeoff has already run. The way back from `set_layer_depth`, and refused the same way: a layer that
## has no depth to forget is left alone and reports that it was.
func clear_layer_depth(layer_name: StringName) -> bool:
	if not TakeoffScript.clear_depth(layer_name):
		return false
	if takeoff != null:
		take_off()
	return true


## What is wrong with the estimate as it stands: the sentences the estimate itself produces, plus
## whether the printed lines foot to the printed subtotal (REQ AC-B6).
##
## Returns `{ok, problems, foots, refused, notes, margin}`.
func check() -> Dictionary:
	var problems: Array[String] = []
	if estimate != null:
		for reason: String in estimate.problems(book):
			problems.append(reason)
	for reason: String in refused:
		problems.append(reason)
	return {
		"ok": problems.is_empty(),
		"problems": problems,
		"foots": estimate != null and estimate.foots(),
		"refused": refused.size(),
		"notes": notes().size(),
		"margin": estimate.margin_text() if estimate != null else "",
	}


## Send it: freeze the prices, the tax and the lines into a hash, which is what makes a number on a
## proposal a promise rather than a picture of the file at the time.
##
## Returns `{ok, reason}`. A proposal with no recipient is refused rather than frozen to nobody: the
## hash records who it went to, and "sent to " is not an answer.
func send(recipient: String) -> Dictionary:
	if estimate == null:
		return {"ok": false, "reason": "there is nothing to send yet"}
	if recipient.strip_edges().is_empty():
		return {"ok": false, "reason": "a proposal needs somebody to go to"}
	if not estimate.is_sound(book):
		return {"ok": false, "reason": "it does not foot: %s" % "; ".join(estimate.problems(book))}
	if estimate.is_frozen():
		return {"ok": false, "reason": "it has already gone"}
	# The person it goes to is the customer on it: a proposal that recorded who it was sent to but
	# printed no name would be a document with a hidden field on it.
	customer["name"] = recipient
	estimate.customer = customer.duplicate(true)
	if not estimate.freeze(recipient):
		return {"ok": false, "reason": "the estimate would not freeze"}
	return {"ok": true, "reason": "", "hash": String(estimate.frozen.get("hash", ""))}


## Whether what was sent still describes what is here - the question that makes a hash worth having.
func freeze_holds() -> bool:
	return estimate != null and estimate.freeze_holds()


## Open a new revision of a frozen estimate. A draft that has not gone yet is not revised: it is
## edited.
func revision() -> Dictionary:
	if estimate == null:
		return {"ok": false, "reason": "there is nothing to revise"}
	if not estimate.is_frozen():
		return {"ok": false, "reason": "it has not gone yet, so there is nothing to revise"}
	var next: EstimateScript = estimate.new_revision()
	estimate = next
	refused.clear()
	return {"ok": true, "reason": "", "revision": next.revision}


# --- what it says ---------------------------------------------------------------------------


## Every measured quantity, in the words the takeoff writes them, with what prices it.
func takeoff_lines() -> Array[String]:
	var out: Array[String] = []
	if takeoff == null:
		return out
	for line: TakeoffScript.TakeoffLine in takeoff.lines:
		var item: CostItem = book.item(line.item_id) if book != null else null
		if item == null:
			out.append("%s  -  no price" % line.describe())
		else:
			out.append("%s  -  %s %s" % [line.describe(), item.name, item.rate_text()])
	return out


## Every priced line, as it prints on the proposal.
func estimate_lines() -> Array[String]:
	var out: Array[String] = []
	if estimate == null:
		return out
	for line: EstimateLine in estimate.lines:
		out.append(line.line_text())
	return out


## The roll-up, as a block of text. Every figure comes from `Estimate.summary`, so the block and the
## proposal cannot disagree.
func totals_text() -> String:
	if estimate == null:
		return "nothing is priced yet"
	var summary: Dictionary = estimate.summary(book)
	# "tax No tax" is what the code's own name reads like in a column, so a code that charges
	# nothing says so in the column's own words instead.
	var charged: String = tax_code_name(estimate.tax_code)
	if TaxScript.rate_ppm(estimate.tax_code) == 0:
		charged = "none charged"
	var pairs: Array = [
		["subtotal", summary["subtotal"]],
		["overhead %.3f%%" % (float(estimate.overhead_ppm) / 10000.0), summary["overhead"]],
		["profit %.3f%%" % (float(estimate.profit_ppm) / 10000.0), summary["profit"]],
		["tax %s" % charged, summary["tax"]],
		["total", summary["total"]],
		["deposit %.3f%%" % (float(estimate.deposit_ppm) / 10000.0), summary["deposit"]],
		["direct cost", summary["direct_cost"]],
		["gross margin", estimate.margin_text()],
	]
	var lines: PackedStringArray = PackedStringArray()
	for pair: Array in pairs:
		var amount: Variant = pair[1]
		var words: String = (amount as MoneyScript).format_with_currency() if amount is MoneyScript \
			else String(amount)
		lines.append("%-24s %s" % [String(pair[0]), words])
	return "\n".join(lines)


## The proposal as a person reads it - `Estimate.describe`, which is the text the PDF sheet is
## written from in phase 7.
func proposal_text() -> String:
	if estimate == null:
		return "nothing is priced yet"
	var out: PackedStringArray = PackedStringArray()
	out.append(estimate.describe(book))
	if not refused.is_empty():
		out.append("")
		out.append("not priced:")
		for reason: String in refused:
			out.append("  %s" % reason)
	return "\n".join(out)


## What the panel's heading says about where this stands, in one line: no drawing, no prices, or the
## count and the total.
func describe() -> String:
	if document == null:
		return "no drawing, so nothing to measure"
	if book == null:
		return "no cost book, so nothing to price with"
	if estimate == null:
		return "%s, and nothing taken off it yet" % book.describe()
	return "%s: %d line%s, %s" % [
		"revision %d" % estimate.revision if estimate.is_frozen() else "draft",
		estimate.line_count(), "" if estimate.line_count() == 1 else "s",
		estimate.total(book).format_with_currency(),
	]


## Write the proposal beside the drawings, atomically, the way a drawing is written.
##
## Returns `{ok, reason, path}`. A proposal is not a report to be regenerated on demand: it is what
## went to the customer, so it is a file, and it is named after the estimate it came from.
func write_proposal() -> Dictionary:
	if estimate == null:
		return {"ok": false, "reason": "there is nothing to write yet", "path": ""}
	var error: Error = DirAccess.make_dir_recursive_absolute(PROPOSAL_DIR)
	if error != OK and error != ERR_ALREADY_EXISTS:
		return {"ok": false, "reason": "the proposals folder would not open", "path": ""}
	var name: String = estimate.number if not estimate.number.is_empty() else estimate.id
	if name.is_empty():
		name = "proposal"
	var path: String = "%s/%s.txt" % [PROPOSAL_DIR, name]
	var temp: String = path + ".writing"
	var file: FileAccess = FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "reason": "the proposal would not open for writing", "path": ""}
	file.store_string(proposal_text())
	file.close()
	var dir: DirAccess = DirAccess.open(PROPOSAL_DIR)
	if dir == null or dir.rename(temp.get_file(), path.get_file()) != OK:
		return {"ok": false, "reason": "the proposal was written but would not be put in place", "path": temp}
	return {"ok": true, "reason": "", "path": path}