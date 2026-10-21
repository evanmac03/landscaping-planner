class_name PurchaseOrder
extends RefCounted
## What was ordered, what arrived, and which of the two the money is (spec §8.3).
##
## ```
## issued   → committed cost (it is owed the moment the truck leaves, not when the invoice arrives)
## received → actual cost (a receipt is a quantity received, priced at the PO's line rate)
## closed   → neither, once invoiced and reconciled
## ```
##
## **Committed is what makes a mid-job cost report honest.** Without it a job looks profitable for the
## three weeks between the mulch arriving and the invoice being entered, and every landscape business
## has been burned by exactly that (§8.3). Committed is therefore the *outstanding* part of an issued
## order - ordered less received - and not the whole order: once the truck has arrived the cost is
## actual, and counting it twice would double it.
##
## ## Three decisions
##
## * **The state is a function of the records, not a field.** `state()` reads `issued_at`,
##   `closed_at` and the receipts. A stored enum is a second place the truth lives, and a double
##   delivery recorded without moving it is a report that quietly lies.
## * **A line's received quantity is the sum of the receipts that name it.** One place a delivery is
##   recorded, so a receipt that the line's own count does not agree with cannot exist.
## * **Receiving more or less than ordered is not an error.** The receipt says what arrived, the
##   variance is *reported*, and the order's cost uses the receipts (§8.3) - a supplier who sends 10%
##   extra does not make the paperwork wrong.

const MoneyScript := preload("res://scripts/biz/money.gd")

const DRAFT := &"DRAFT"
const ISSUED := &"ISSUED"
const PARTIAL := &"PARTIAL"
const RECEIVED := &"RECEIVED"
const CLOSED := &"CLOSED"

## String keys: a StringName literal as a const Dictionary key fails the constant-expression check.
const STATE_NAMES := {
	"DRAFT": "draft, not ordered",
	"ISSUED": "issued, nothing has arrived",
	"PARTIAL": "partly received",
	"RECEIVED": "received",
	"CLOSED": "closed and reconciled",
}

## Thousandths of a unit, the module's one quantity unit (§2.1).
const QUANTITY_MILLI := 1000

var id: String = ""
var number: String = ""
var job: String = ""
var cost_code: StringName = &""
var supplier: String = ""
## `{description, unit, ordered_milli, unit_cost}`. The **received** quantity is deliberately not a
## field here: `received_milli()` sums the receipts, so a delivery is recorded once (§8.3).
var lines: Array[Dictionary] = []
## `{at, line, quantity_milli, note, photo}` - the deliveries, in the order they arrived. It is a
## **quantity**, and the order's own line rate prices it: a receipt is not an invoice.
var receipts: Array[Dictionary] = []
var expected_at: String = ""
var issued_at: String = ""
var closed_at: String = ""
## Why it was closed, when somebody said. A closed order that nobody explained is still closed.
var closed_note: String = ""
var currency: StringName = &"CAD"
var note: String = ""


func _init(order_id: String = "") -> void:
	id = order_id


# --- the lines ---------------------------------------------------------------------------------


## Add a line. Refused for nothing to order, for a quantity of nothing, and for an unreadable rate:
## a line the cost report cannot price is a line that disappears from the commitment.
##
## The parameter is not called `ordered_milli`: a parameter that shadows a method of its own class is
## a warning in this language, and `ordered_milli(index)` is a method here.
func add_line(description: String, unit: StringName, quantity_milli: int, unit_cost: Money) -> bool:
	if description.strip_edges().is_empty():
		return false
	if quantity_milli <= 0:
		return false
	if unit_cost == null or not unit_cost.is_valid():
		return false
	lines.append({
		"description": description,
		"unit": String(unit),
		"ordered_milli": quantity_milli,
		"unit_cost": unit_cost,
	})
	return true


func line_count() -> int:
	return lines.size()


func ordered_milli(index: int) -> int:
	if index < 0 or index >= lines.size():
		return 0
	return int(lines[index]["ordered_milli"])


## How much of one line has arrived: the sum of the receipts that name it.
func received_milli(index: int) -> int:
	if index < 0 or index >= lines.size():
		return 0
	var total := 0
	for entry in receipts:
		if int(entry.get("line", -1)) == index:
			total += int(entry.get("quantity_milli", 0))
	return total


func ordered_milli_total() -> int:
	var total := 0
	for index in lines.size():
		total += ordered_milli(index)
	return total


func received_milli_total() -> int:
	var total := 0
	for entry in receipts:
		total += int(entry.get("quantity_milli", 0))
	return total


## How far a line is short (positive) or over (negative): what arrived less what was ordered. Reported
## and never an error (§8.3).
func variance_milli(index: int) -> int:
	return received_milli(index) - ordered_milli(index)


# --- what the lines are worth ------------------------------------------------------------------


## One line's worth at its own rate: the quantity in thousandths times the unit rate, rounded **once**
## - the module's one rounding rule, so a reversal returns the charge to the cent (§2.1).
func _amount(quantity: int, unit_cost: Money) -> Money:
	if unit_cost == null or not unit_cost.is_valid():
		return MoneyScript.invalid(currency)
	return MoneyScript.round_div(unit_cost.cents * quantity, QUANTITY_MILLI, currency)


func line_cost(index: int) -> Money:
	if index < 0 or index >= lines.size():
		return MoneyScript.zero(currency)
	return _amount(ordered_milli(index), lines[index]["unit_cost"])


func line_received_cost(index: int) -> Money:
	if index < 0 or index >= lines.size():
		return MoneyScript.zero(currency)
	return _amount(received_milli(index), lines[index]["unit_cost"])


## What was ordered, at the line rates.
func ordered_total() -> Money:
	var amounts: Array = []
	for index in lines.size():
		amounts.append(line_cost(index))
	return MoneyScript.sum(amounts, currency)


## What has actually arrived, at the line rates - which is the order's **actual** cost (§8.3).
func received_total() -> Money:
	var amounts: Array = []
	for index in lines.size():
		amounts.append(line_received_cost(index))
	return MoneyScript.sum(amounts, currency)


# --- the three numbers, and the state ----------------------------------------------------------


func state() -> StringName:
	if not closed_at.is_empty():
		return CLOSED
	if issued_at.is_empty():
		return DRAFT
	var arrived := received_milli_total()
	if arrived <= 0:
		return ISSUED
	if arrived < ordered_milli_total():
		return PARTIAL
	return RECEIVED


func state_name() -> String:
	return String(STATE_NAMES.get(String(state()), String(state())))


func is_issued() -> bool:
	return not issued_at.is_empty() and closed_at.is_empty()


func is_closed() -> bool:
	return not closed_at.is_empty()


## The cost this order has committed and not yet had delivered: ordered less received, and never
## below nothing, because an over-delivery does not make the money owed negative. A draft commits
## nothing - nobody has ordered it - and a closed order commits nothing.
func committed() -> Money:
	if issued_at.is_empty() or not closed_at.is_empty():
		return MoneyScript.zero(currency)
	var ordered := ordered_total()
	var arrived := received_total()
	if not ordered.is_valid() or not arrived.is_valid():
		return MoneyScript.invalid(currency)
	var outstanding := ordered.sub(arrived)
	if not outstanding.is_valid():
		return outstanding
	if outstanding.cents < 0:
		return MoneyScript.zero(currency)
	return outstanding


## The cost this order has actually incurred: what has arrived, at the line rates.
func actual() -> Money:
	if issued_at.is_empty():
		return MoneyScript.zero(currency)
	return received_total()


## What a line's cost is over or under what was ordered for it, in money.
func line_variance(index: int) -> Money:
	return line_received_cost(index).sub(line_cost(index))


# --- the workflow ---------------------------------------------------------------------------


## Order it. Refused for a supplier nobody named, for nothing on it, and for a line nothing can price:
## an order that goes out without knowing who to or what for is not an order.
## Returns `{ok, reason}`.
func issue(at: String) -> Dictionary:
	if not issued_at.is_empty():
		return {"ok": false, "reason": "it has already been issued"}
	if supplier.strip_edges().is_empty():
		return {"ok": false, "reason": "a purchase order needs a supplier"}
	if lines.is_empty():
		return {"ok": false, "reason": "there is nothing on it to order"}
	if not ordered_total().is_valid():
		return {"ok": false, "reason": "a line on it cannot be priced"}
	if at.strip_edges().is_empty():
		return {"ok": false, "reason": "an issued order says when it was issued"}
	issued_at = at
	return {"ok": true, "reason": ""}


## Record a delivery against a line. Refused for a draft (nobody has ordered it), for a closed order,
## for a line that is not there, and for a quantity of nothing. **Not** refused for a quantity larger
## than was ordered: §8.3 says the receipt says what arrived.
## Returns `{ok, reason}`.
func receive(at: String, index: int, quantity: int, receipt_note: String = "",
		photo: String = "") -> Dictionary:
	if issued_at.is_empty():
		return {"ok": false, "reason": "it has not been issued, so there is nothing to receive"}
	if not closed_at.is_empty():
		return {"ok": false, "reason": "it is closed"}
	if index < 0 or index >= lines.size():
		return {"ok": false, "reason": "there is no line %d on it" % index}
	if quantity <= 0:
		return {"ok": false, "reason": "a receipt is a quantity that arrived"}
	if at.strip_edges().is_empty():
		return {"ok": false, "reason": "a receipt says when it arrived"}
	receipts.append({
		"at": at,
		"line": index,
		"quantity_milli": quantity,
		"note": receipt_note,
		"photo": photo,
	})
	return {"ok": true, "reason": ""}


## Close it and reconcile. Refused before it is issued, and refused for an order with nothing arrived:
## closing what never came is how a commitment disappears from a report without anybody noticing.
func mark_closed(at: String, why: String = "") -> bool:
	if issued_at.is_empty():
		return false
	if not closed_at.is_empty():
		return false
	if at.strip_edges().is_empty():
		return false
	if received_milli_total() <= 0:
		return false
	closed_at = at
	closed_note = why
	return true


# --- what it says --------------------------------------------------------------------------


func line_rows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for index in lines.size():
		var held: Dictionary = lines[index]
		out.append({
			"index": index,
			"description": String(held.get("description", "")),
			"unit": String(held.get("unit", "EACH")),
			"unit_cost": held["unit_cost"],
			"ordered_milli": ordered_milli(index),
			"received_milli": received_milli(index),
			"variance_milli": variance_milli(index),
			"ordered": line_cost(index),
			"received": line_received_cost(index),
		})
	return out


## What is wrong with this order as it stands, in sentences. A **receipt older than the order** is a
## mis-keyed date and it makes every "invoiced in the period" report wrong, so it is a fault rather
## than a curiosity.
func problems() -> Array[String]:
	var out: Array[String] = []
	if id.strip_edges().is_empty():
		out.append("a purchase order needs an id")
	if issued_at.is_empty() and not receipts.is_empty():
		out.append("%s has receipts and was never issued" % _label())
	for held in lines:
		var cost = held["unit_cost"]
		if cost == null or not (cost as MoneyScript).is_valid():
			out.append("%s has a line with no readable rate" % _label())
	var first := ""
	for entry in receipts:
		var at := String(entry.get("at", ""))
		if first.is_empty() or at < first:
			first = at
	if not first.is_empty() and not issued_at.is_empty() and first < issued_at:
		out.append("%s was received on %s, before it was issued on %s" % [_label(), first, issued_at])
	if not closed_at.is_empty() and received_milli_total() < ordered_milli_total():
		out.append("%s is closed with %d of %d thousandths arrived"
			% [_label(), received_milli_total(), ordered_milli_total()])
	return out


func is_sound() -> bool:
	return problems().is_empty()


func describe() -> String:
	if number.is_empty() and supplier.is_empty():
		return "%s, draft" % _label()
	var parts := PackedStringArray()
	parts.append("%s to %s" % [_label(), supplier if not supplier.is_empty() else "nobody yet"])
	parts.append(state_name())
	parts.append("ordered %s" % ordered_total().format_with_currency())
	if not receipts.is_empty():
		parts.append("arrived %s" % received_total().format_with_currency())
	var outstanding := committed()
	if outstanding.cents > 0:
		parts.append("committed %s" % outstanding.format_with_currency())
	return "%s (%s)" % [", ".join(parts), String(cost_code)]


func _label() -> String:
	if not number.is_empty():
		return number
	if not id.is_empty():
		return id
	return "this order"


# --- the file ---------------------------------------------------------------------------------


func to_dict() -> Dictionary:
	var line_list: Array = []
	for index in lines.size():
		var held: Dictionary = lines[index]
		line_list.append({
			"description": String(held.get("description", "")),
			"unit": String(held.get("unit", "EACH")),
			"ordered_milli": int(held.get("ordered_milli", 0)),
			"unit_cost": (held["unit_cost"] as MoneyScript).to_dict(),
		})
	var receipt_list: Array = []
	for entry in receipts:
		receipt_list.append({
			"at": String(entry.get("at", "")),
			"line": int(entry.get("line", -1)),
			"quantity_milli": int(entry.get("quantity_milli", 0)),
			"note": String(entry.get("note", "")),
			"photo": String(entry.get("photo", "")),
		})
	return {
		"id": id,
		"number": number,
		"job": job,
		"cost_code": String(cost_code),
		"supplier": supplier,
		"lines": line_list,
		"receipts": receipt_list,
		"expected_at": expected_at,
		"issued_at": issued_at,
		"closed_at": closed_at,
		"closed_note": closed_note,
		"currency": String(currency),
		"note": note,
	}


## Read one back. A record with no id is **dropped**, not invented. A line with nothing on it is
## dropped, and a receipt that names a line that is not there is dropped - but a receipt that is
## merely *later* than the order is kept and reported, because it is a real delivery.
static func from_dict(data: Dictionary) -> PurchaseOrder:
	var order: PurchaseOrder = OrderScript.new(String(data.get("id", "")))
	if order.id.is_empty():
		return null
	order.number = String(data.get("number", ""))
	order.job = String(data.get("job", ""))
	order.cost_code = StringName(data.get("cost_code", ""))
	order.supplier = String(data.get("supplier", ""))
	order.currency = StringName(data.get("currency", "CAD"))
	order.expected_at = String(data.get("expected_at", ""))
	order.issued_at = String(data.get("issued_at", ""))
	order.closed_at = String(data.get("closed_at", ""))
	order.closed_note = String(data.get("closed_note", ""))
	order.note = String(data.get("note", ""))
	var line_list = data.get("lines", [])
	if line_list is Array:
		for entry in (line_list as Array):
			if not (entry is Dictionary):
				continue
			var held: Dictionary = entry
			var quantity := int(held.get("ordered_milli", 0))
			if quantity <= 0:
				continue
			# A line whose rate cannot be read is **kept with an unreadable rate**, not dropped: an
			# order that quietly loses a line reads as a smaller commitment than it is, and money.gd's
			# whole reason for an invalid amount is that one unreadable price must poison the total
			# rather than price something at nothing.
			var rate: Money = MoneyScript.invalid(order.currency)
			var rate_data = held.get("unit_cost", null)
			if rate_data is Dictionary and not (rate_data as Dictionary).is_empty():
				var read: Money = MoneyScript.from_dict(rate_data)
				if read.is_valid():
					rate = read
			order.lines.append({
				"description": String(held.get("description", "")),
				"unit": String(held.get("unit", "EACH")),
				"ordered_milli": quantity,
				"unit_cost": rate,
			})
	var receipt_list = data.get("receipts", [])
	if receipt_list is Array:
		for entry in (receipt_list as Array):
			if entry is Dictionary:
				var at := String(entry.get("at", ""))
				var index := int(entry.get("line", -1))
				var quantity := int(entry.get("quantity_milli", 0))
				if index < 0 or index >= order.lines.size() or quantity <= 0:
					continue
				order.receipts.append({
					"at": at,
					"line": index,
					"quantity_milli": quantity,
					"note": String(entry.get("note", "")),
					"photo": String(entry.get("photo", "")),
				})
	return order


const OrderScript := preload("res://scripts/biz/purchase_order.gd")