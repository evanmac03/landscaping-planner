class_name Money
extends RefCounted
## An amount in minor units, and the currency it is in.
##
## Integer, because money has to be exact in ways a float is not, whatever width that float is:
## 0.1 has no exact representation, so a column of line amounts accumulates representation error
## as it sums; a printed column must foot to the printed subtotal to the cent; a tax component must
## reproduce the authority's own worked example; and a credit note must be the exact mirror of the
## charge it reverses to the cent. A count of minor units with **one** documented rounding
## (`round_div`) gives all four, and gives the same answer on any build.
##
## (The first version of this comment argued that this build's floats were 32-bit, which would have
## put the ceiling at $167,772.16 and made the case much stronger. It was **tested and is false**:
## `1e8 + 1.0 == 1e8` is false here, so GDScript floats are 64-bit and hold cents exactly to about
## $90 trillion. The reason to count cents is that the arithmetic must be auditable and reversible,
## not that the float is too small - and a specification that argued otherwise would have been
## reasoning from a premise its own subject matter could refute.)
##
## The field is named `cents` for the small unit rather than for any one currency: it is a cent
## for a currency with two decimals and a whole yen for one with none, and `EXPONENTS` is what
## decides how it prints.

## Minor units per major unit. A currency that appears here with the wrong exponent is a
## rounding bug in every invoice that prints it.
const EXPONENTS := {"CAD": 2, "USD": 2, "EUR": 2, "GBP": 2, "AUD": 2, "JPY": 0, "KRW": 0}

## Symbols for printing on a document with a company address above it. CAD, USD and AUD all
## print as "$", which is why anything that travels - JSON, an API body, a filename - carries
## the ISO code instead (`format_iso`).
const SYMBOLS := {"CAD": "$", "USD": "$", "EUR": "€", "GBP": "£", "AUD": "$", "JPY": "¥", "KRW": "₩"}

## The invalid amount: what an unreadable price becomes. It is **contagious**, like a NaN, so a
## bad line poisons the total it feeds and the estimate refuses to foot - rather than quietly
## pricing something at nothing, which is how a typo becomes a free patio.
const INVALID_CENTS := -9223372036854775808

## The longest run of digits this will read as a whole amount: fifteen, so that the
## multiplication by the currency's unit cannot overflow a 64-bit int. Beyond that the text is
## not a price, it is a paste accident.
const MAX_WHOLE_DIGITS := 15

var cents: int = 0
var currency: StringName = &"CAD"


func _init(amount_cents: int = 0, code: StringName = &"CAD") -> void:
	cents = amount_cents
	currency = code


static func _script() -> GDScript:
	return load("res://scripts/biz/money.gd") as GDScript


static func of(amount_cents: int, code: StringName = &"CAD") -> Money:
	return _script().new(amount_cents, code) as Money


static func zero(code: StringName = &"CAD") -> Money:
	return of(0, code)


static func invalid(code: StringName = &"CAD") -> Money:
	return of(INVALID_CENTS, code)


## From a whole number of major units: 250000 dollars becomes 25,000,000 cents.
static func from_major(major: int, code: StringName = &"CAD") -> Money:
	return of(major * _unit(code), code)


static func _unit(code: StringName) -> int:
	var exponent: int = int(EXPONENTS.get(String(code), 2))
	var unit: int = 1
	for index in exponent:
		unit *= 10
	return unit


static func exponent_of(code: StringName) -> int:
	return int(EXPONENTS.get(String(code), 2))


# --- reading and writing ---------------------------------------------------------------


## Read an amount out of text, or return the invalid amount and say nothing else.
##
## Accepts an optional currency symbol or ISO code (which must agree with `code` - "USD 10.00"
## is not ten Canadian dollars, and reading it as such is how a foreign price list corrupts a
## book), an optional sign, accounting parentheses for a credit, thousands separators, and at
## most as many decimal places as the currency has. **More precision is refused rather than
## rounded**: a price list that says 0.0049 did not ask for a rounding, and the caller can round
## deliberately if that is what they meant.
static func parse(text: String, code: StringName = &"CAD") -> Money:
	var body: String = text.strip_edges()
	var negative: bool = false
	if body.length() >= 2 and body.begins_with("(") and body.ends_with(")"):
		negative = true
		body = body.substr(1, body.length() - 2).strip_edges()
	if body.begins_with("-"):
		negative = not negative
		body = body.substr(1).strip_edges()
	elif body.begins_with("+"):
		body = body.substr(1).strip_edges()
	var symbol: String = String(SYMBOLS.get(String(code), ""))
	if symbol != "" and body.begins_with(symbol):
		body = body.substr(symbol.length()).strip_edges()
	else:
		for other in SYMBOLS.values():
			if String(other) != symbol and body.begins_with(String(other)):
				return invalid(code)
		if body.length() >= 3 and body.substr(0, 3).is_valid_identifier():
			if body.substr(0, 3).to_upper() != String(code):
				return invalid(code)
			body = body.substr(3).strip_edges()
	body = body.replace(" ", "").replace("_", "").replace("'", "")
	if body.is_empty():
		return invalid(code)
	var parts: PackedStringArray = body.split(".")
	if parts.size() > 2:
		return invalid(code)
	var whole_text: String = parts[0]
	if whole_text.is_empty():
		whole_text = "0"
	# Grouping is validated *before* it is stripped, because a separator in the wrong place is a
	# typo that would otherwise be read as a plausible number: "12,34,56" is neither 1,234.56 nor
	# 123,456, and quietly choosing one of them is how a quote goes out a hundred times wrong.
	# Groups of three from the right, which is what this module writes; a price list grouped the
	# Indian way (12,34,567) is refused here and would be normalised by an importer, which is a
	# deliberate refusal rather than a guess.
	if not _grouping_ok(whole_text):
		return invalid(code)
	whole_text = whole_text.replace(",", "")
	if not whole_text.is_valid_int() or whole_text.length() > MAX_WHOLE_DIGITS:
		return invalid(code)
	var fraction_text: String = parts[1] if parts.size() > 1 else ""
	var exponent: int = exponent_of(code)
	if fraction_text.length() > exponent:
		return invalid(code)
	if not (fraction_text.is_empty() or fraction_text.is_valid_int()):
		return invalid(code)
	var unit: int = _unit(code)
	var padded: String = fraction_text + "0".repeat(exponent - fraction_text.length())
	var amount: int = int(whole_text) * unit + (int(padded) if not padded.is_empty() else 0)
	return of(-amount if negative else amount, code)


## The plain number, grouped for a table column. No currency, because the column has a header.
func format() -> String:
	if not is_valid():
		return "—"
	var unit: int = _unit(currency)
	var magnitude: int = absi(cents)
	@warning_ignore("integer_division")
	var whole: int = magnitude / unit
	var fraction: int = magnitude % unit
	var text: String = _grouped(str(whole))
	if exponent_of(currency) > 0:
		text += "." + str(fraction).lpad(exponent_of(currency), "0")
	return ("-" if cents < 0 else "") + text


## The amount as a customer reads it: "$1,234.56". The symbol is context, which is all a symbol
## can be - three currencies share this one.
func format_with_currency() -> String:
	if not is_valid():
		return "—"
	var symbol: String = String(SYMBOLS.get(String(currency), ""))
	return (symbol + format()) if not symbol.is_empty() else format_iso()


## The amount with its ISO code, for anything that travels: "CAD 1,234.56".
func format_iso() -> String:
	if not is_valid():
		return "invalid"
	return "%s %s" % [String(currency), format()]


static func _grouped(digits: String) -> String:
	var out: String = ""
	var count: int = 0
	for index in range(digits.length() - 1, -1, -1):
		out = digits[index] + out
		count += 1
		if count % 3 == 0 and index > 0:
			out = "," + out
	return out


## Whether a run of digits is grouped the way this module groups them: the first group up to three,
## every group after it exactly three.
static func _grouping_ok(text: String) -> bool:
	if not text.contains(","):
		return true
	var groups: PackedStringArray = text.split(",")
	if groups.size() < 2:
		return true
	if groups[0].length() < 1 or groups[0].length() > 3:
		return false
	for index in range(1, groups.size()):
		if groups[index].length() != 3:
			return false
	return true


# --- asking about it -------------------------------------------------------------------


func is_valid() -> bool:
	return cents != INVALID_CENTS


func is_zero() -> bool:
	return is_valid() and cents == 0


func is_negative() -> bool:
	return is_valid() and cents < 0


func equals(other: Money) -> bool:
	return other != null and cents == other.cents and currency == other.currency


func to_dict() -> Dictionary:
	return {"cents": cents, "currency": String(currency)}


static func from_dict(data: Dictionary) -> Money:
	return of(int(data.get("cents", 0)), StringName(data.get("currency", "CAD")))


# --- arithmetic ------------------------------------------------------------------------


## Divide two integers, rounding half **away from zero**. The single rounding in this module.
##
## Away from zero in both directions, so a credit is the mirror of the charge it reverses: an
## invoice and its credit note sum to zero to the cent, which is AC-B4 and the reason a
## "round half to even" would be wrong here even though it is the better default for statistics.
static func rounded_div(numerator: int, denominator: int) -> int:
	if denominator == 0:
		return INVALID_CENTS
	var negative: bool = (numerator < 0) != (denominator < 0)
	var magnitude: int = absi(numerator)
	@warning_ignore("integer_division")
	var quotient: int = magnitude / absi(denominator)
	var remainder: int = magnitude % absi(denominator)
	if remainder * 2 >= absi(denominator):
		quotient += 1
	return -quotient if negative else quotient


static func round_div(numerator: int, denominator: int, code: StringName = &"CAD") -> Money:
	return of(rounded_div(numerator, denominator), code)


## The invalid amount is contagious through every operation, which is what makes it useful: one
## unreadable price refuses the total instead of disappearing into it.
func add(other: Money) -> Money:
	if not is_valid() or other == null or not other.is_valid():
		return invalid(currency)
	if other.currency != currency:
		return invalid(currency)
	return of(cents + other.cents, currency)


func sub(other: Money) -> Money:
	if other == null:
		return invalid(currency)
	return add(other.neg())


func neg() -> Money:
	if not is_valid():
		return invalid(currency)
	return of(-cents, currency)


func abs() -> Money:
	if not is_valid():
		return invalid(currency)
	return of(absi(cents), currency)


## Multiply by a whole number of units (three loads, two permits).
func times(factor: int) -> Money:
	if not is_valid():
		return invalid(currency)
	return of(cents * factor, currency)


## Scale by a rate in **parts per million**: `scale_ppm(130000)` is 13% and `scale_ppm(99750)` is
## 9.975%. Used for tax, markup, deposits and retainage, all of which are rates a business states
## as a percentage.
##
## Not basis points. A basis point is a hundredth of a percent, and Quebec's QST is 9.975% - 997.5
## basis points - so a tax table written in basis points cannot state the rate at all. The first
## version of this module used them and had to round the rate to 9975 basis points, which is
## 99.75%: a customer in Quebec would have been charged the value of the job again as tax. Parts
## per million hold every published rate in North America exactly, including the three-decimal
## ones, and refuse to invent a rate that nobody published. (Spec §15.2.)
func scale_ppm(rate: int) -> Money:
	if not is_valid():
		return invalid(currency)
	return round_div(cents * rate, 1000000, currency)


## The sum of a column. A column in two currencies is a mistake rather than a total, so it has
## no answer.
static func sum(amounts: Array, code: StringName = &"CAD") -> Money:
	var running: Money = zero(code)
	for amount in amounts:
		var value: Money = amount as Money
		if value == null:
			return invalid(code)
		running = running.add(value)
		if not running.is_valid():
			return running
	return running