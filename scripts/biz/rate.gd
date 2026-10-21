class_name Rate
extends RefCounted
## A rate stated as parts per million, written and read the way a person writes a percentage.
##
## Parts per million rather than basis points, for the reason the tax table gives (spec §15.2): a
## basis point is a hundredth of a percent, and 9.975% - Quebec's QST - is 997.5 of them, so a rate
## written that way cannot state the number at all. Every published rate in North America lands
## exactly on a whole number of parts per million.
##
## It is one place because a rate is printed in three places that must agree: a milestone schedule,
## an invoice's retainage deduction, and a tax component in a report. A percentage formatted
## differently on the invoice than in the report is how a customer finds a tenth of a percent.

## A whole contract, a whole amount, no retainage withheld: 1,000,000 parts per million.
const WHOLE := 1000000

## A percent is 10,000 parts per million, and that is the divisor a printed percentage needs: it
## leaves four decimal places of a percent, so 0.001% is the finest rate this can write.
const PER_PERCENT := 10000

## What an unreadable or unpublished rate is. Not zero: a rate field nobody filled in must refuse
## rather than silently charge nothing.
const INVALID := -1


static func is_valid(ppm: int) -> bool:
	return ppm >= 0


## "75%", "9.975%", "0.5%", "0.001%", "100%". Trailing zeros are trimmed, because a rate is never
## published with them and "9.9750%" reads as a computed number being passed off as a table entry.
static func percent_text(ppm: int) -> String:
	if ppm == INVALID:
		return "—"
	var magnitude: int = absi(ppm)
	@warning_ignore("integer_division")
	var whole: int = magnitude / PER_PERCENT
	var rest: int = magnitude % PER_PERCENT
	var text: String = str(whole)
	if rest > 0:
		text += "." + str(rest).lpad(4, "0").rstrip("0")
	return ("-" if ppm < 0 else "") + text + "%"


## Read a percentage out of text: "13", "13%", "9.975%", " 0.5 %", "-2".
##
## More than four decimal places is **refused rather than rounded**, which is Money's rule for a
## price and for the same reason: a rate typed to five places was not asking for a rate to four, and
## quietly rounding it is how a retainage comes out a cent short on every invoice of the year.
static func parse_percent(text: String) -> int:
	var body: String = text.strip_edges()
	if body.ends_with("%"):
		body = body.substr(0, body.length() - 1).strip_edges()
	var negative: bool = false
	if body.begins_with("-"):
		negative = true
		body = body.substr(1).strip_edges()
	elif body.begins_with("+"):
		body = body.substr(1).strip_edges()
	if body.is_empty():
		return INVALID
	var parts: PackedStringArray = body.split(".")
	if parts.size() > 2:
		return INVALID
	var whole_text: String = parts[0].strip_edges()
	if whole_text.is_empty():
		whole_text = "0"
	if not whole_text.is_valid_int() or whole_text.length() > 6:
		return INVALID
	var fraction_text: String = parts[1].strip_edges() if parts.size() > 1 else ""
	if fraction_text.length() > 4:
		return INVALID
	if not (fraction_text.is_empty() or fraction_text.is_valid_int()):
		return INVALID
	var padded: String = fraction_text + "0".repeat(4 - fraction_text.length())
	@warning_ignore("integer_division")
	var whole: int = whole_text.to_int()
	var fraction: int = padded.to_int() if not padded.is_empty() else 0
	var ppm: int = whole * PER_PERCENT + fraction
	return -ppm if negative else ppm


## A rate as a fraction of a whole, for a column that has room for a number and not a percent.
static func fraction(ppm: int) -> float:
	return float(ppm) / float(WHOLE)


## Whether a run of text is a date this program writes: `YYYY-MM-DD`, all digits, a real month and a
## real day. One place, because a due date, an approval date and a period end are the same kind of
## string and a milestone schedule full of "June" is a schedule nobody can bill against.
static func is_date(text: String) -> bool:
	var body: String = text.strip_edges()
	if body.length() != 10:
		return false
	if body[4] != "-" or body[7] != "-":
		return false
	var year_text: String = body.substr(0, 4)
	var month_text: String = body.substr(5, 2)
	var day_text: String = body.substr(8, 2)
	if not (year_text.is_valid_int() and month_text.is_valid_int() and day_text.is_valid_int()):
		return false
	var month: int = month_text.to_int()
	if month < 1 or month > 12:
		return false
	var day: int = day_text.to_int()
	return day >= 1 and day <= _days_in_month(year_text.to_int(), month)


static func _days_in_month(year: int, month: int) -> int:
	match month:
		1, 3, 5, 7, 8, 10, 12: return 31
		4, 6, 9, 11: return 30
		2: return 29 if _is_leap(year) else 28
	return 0


static func _is_leap(year: int) -> bool:
	if year % 400 == 0:
		return true
	if year % 100 == 0:
		return false
	return year % 4 == 0