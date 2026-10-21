class_name CrewMember
extends RefCounted
## A person who does the work: their role, their pay over time, and when they are available.
##
## **A crew member is not a user account** (spec §7.1). A person can be both, and the two are separate
## records with separate purposes: this one is about doing the work and what it costs, and the account
## is about who may sign in and what they may see. Keeping them one record would mean a labourer with
## no login could not be on a crew, and a rate change would be an account audit event.
##
## **A rate is effective-dated** (§7.1) for the reason a line's price is frozen (§2.2): a raise next
## March must not reprice the hours somebody worked last November. `rate_on(date)` is the only way to
## ask what a person costs, and it answers for a date, never "now".

const MoneyScript := preload("res://scripts/biz/money.gd")

## The four roles, as data with words, because a schedule board prints them and utilisation is
## grouped by them (§10). **String keys**, not StringName: a StringName literal as a const Dictionary
## key fails the constant-expression check in this build.
const ROLES := {
	"FOREMAN": "Foreman",
	"LEAD_HAND": "Lead hand",
	"LABOURER": "Labourer",
	"SUBCONTRACTOR": "Subcontractor",
}

## The kinds an availability entry can be. A weekly-hours entry only informs utilisation; a day off
## and a vacation both make `available_on` answer no.
const WEEKLY_HOURS := &"WEEKLY_HOURS"
const DAY_OFF := &"DAY_OFF"
const VACATION := &"VACATION"

var id: StringName = &""
var name: String = ""
var role: StringName = &"LABOURER"
## `{from, loaded_rate}` in effective-date order. A loaded rate is cost plus burden, which is what a
## job is actually charged (spec §4.11 says the time entry *records* it, too).
var rates: Array[Dictionary] = []
## Where the crew starts the day, in the drawing's model metres: the first drive leg of a route.
var home_base: Vector2 = Vector2.ZERO
## `{name, expires_at}` - a ticket or a licence, with the date it runs out.
var certifications: Array[Dictionary] = []
## `{kind, weekday, from, to, note}`. `weekday` is 0=Sunday for a day off; `from`/`to` are ISO dates
## for a vacation.
var availability: Array[Dictionary] = []


func _init(member_id: StringName = &"", member_name: String = "") -> void:
	id = member_id
	name = member_name


static func is_role(candidate: StringName) -> bool:
	return ROLES.has(String(candidate))


static func role_name(candidate: StringName) -> String:
	return String(ROLES.get(String(candidate), "Unknown role"))


static func role_list() -> Array[StringName]:
	var out: Array[StringName] = []
	for key in ROLES.keys():
		out.append(StringName(key))
	return out


# --- what a person costs, on a date ---------------------------------------------------------


## Record a rate that takes effect from a date. Refused with an empty date or an unreadable amount:
## a rate with no date cannot be asked for on a date, which is the only way it is ever used.
func add_rate(from_date: String, loaded_rate: Money) -> bool:
	if from_date.strip_edges().is_empty() or loaded_rate == null or not loaded_rate.is_valid():
		return false
	for held in rates:
		if String(held["from"]) == from_date:
			held["loaded_rate"] = loaded_rate
			return true
	rates.append({"from": from_date, "loaded_rate": loaded_rate})
	rates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["from"]) < String(b["from"]))
	return true


## What this person costs per hour on a date: the latest rate whose `from` is on or before it.
##
## An unreadable amount when there is no rate yet, so that costing a job from a person with no rate
## is refused loudly rather than priced at nothing - the same contagion a bad price has (§2.1).
func rate_on(date: String) -> Money:
	var found: Money = MoneyScript.invalid()
	if date.strip_edges().is_empty():
		return found
	for held in rates:
		if String(held["from"]) <= date:
			found = held["loaded_rate"]
	return found


func rate_rows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for held in rates:
		out.append({"from": String(held["from"]), "loaded_rate": held["loaded_rate"]})
	return out


# --- tickets and availability ----------------------------------------------------------------


func add_certification(cert_name: String, expires_at: String) -> bool:
	if cert_name.strip_edges().is_empty():
		return false
	certifications.append({"name": cert_name, "expires_at": expires_at})
	return true


## Whether a ticket is held **and still valid** on a date. An expired ticket is not a ticket: a
## certification that ran out last month must not let someone be scheduled onto that work.
func has_certification(cert_name: String, on_date: String) -> bool:
	for held in certifications:
		if String(held["name"]) != cert_name:
			continue
		var expires := String(held.get("expires_at", ""))
		if expires.is_empty() or on_date.is_empty() or expires >= on_date:
			return true
	return false


func add_availability(entry: Dictionary) -> bool:
	var kind := StringName(entry.get("kind", ""))
	if kind != WEEKLY_HOURS and kind != DAY_OFF and kind != VACATION:
		return false
	availability.append({
		"kind": String(kind),
		"weekday": int(entry.get("weekday", -1)),
		"from": String(entry.get("from", "")),
		"to": String(entry.get("to", "")),
		"note": String(entry.get("note", "")),
	})
	return true


## Whether a person can work on a date. A day off whose weekday matches, or a vacation whose window
## contains the date, means no; everything else means yes. ISO dates compare as text, which is why
## the form is fixed (§10).
func available_on(date: String) -> bool:
	var weekday := _weekday_of(date)
	for held in availability:
		var kind := String(held.get("kind", ""))
		if kind == "DAY_OFF" and int(held.get("weekday", -1)) == weekday:
			return false
		if kind == "VACATION":
			var from_date := String(held.get("from", ""))
			var to_date := String(held.get("to", ""))
			if (from_date.is_empty() or date >= from_date) and (to_date.is_empty() or date <= to_date):
				return false
	return true


## Why a person cannot work a date, in words, or empty when they can.
func unavailability(date: String) -> String:
	var weekday := _weekday_of(date)
	for held in availability:
		var kind := String(held.get("kind", ""))
		if kind == "DAY_OFF" and int(held.get("weekday", -1)) == weekday:
			return "%s is off on %s" % [name, date]
		if kind == "VACATION":
			var from_date := String(held.get("from", ""))
			var to_date := String(held.get("to", ""))
			if (from_date.is_empty() or date >= from_date) and (to_date.is_empty() or date <= to_date):
				return "%s is on vacation on %s" % [name, date]
	return ""


## Day of the week for an ISO date, 0=Sunday. 1970-01-01 was a Thursday, which is 4.
static func _weekday_of(date: String) -> int:
	var text := date.strip_edges()
	if text.length() > 10:
		text = text.substr(0, 10)
	# The shape decides readability, not the epoch seconds: 1970-01-01 parses to 0, which is a real
	# date and not a failure, so a `seconds <= 0` guard would call the epoch unreadable.
	if text.length() != 10 or not text.contains("-"):
		return -1
	var seconds := int(Time.get_unix_time_from_datetime_string(text + "T00:00:00"))
	return (floori(float(seconds) / 86400.0) + 4) % 7


# --- the file --------------------------------------------------------------------------------


func to_dict() -> Dictionary:
	var rate_list: Array = []
	for held in rates:
		rate_list.append({"from": String(held["from"]), "loaded_rate": held["loaded_rate"].to_dict()})
	var cert_list: Array = []
	for held in certifications:
		cert_list.append({
			"name": String(held.get("name", "")),
			"expires_at": String(held.get("expires_at", "")),
		})
	var avail_list: Array = []
	for held in availability:
		avail_list.append({
			"kind": String(held.get("kind", "")),
			"weekday": int(held.get("weekday", -1)),
			"from": String(held.get("from", "")),
			"to": String(held.get("to", "")),
			"note": String(held.get("note", "")),
		})
	return {
		"id": String(id),
		"name": name,
		"role": String(role),
		"rates": rate_list,
		"home_base": [home_base.x, home_base.y],
		"certifications": cert_list,
		"availability": avail_list,
	}


## A record with no id is **dropped rather than invented**: a crew member nobody can name is a
## damaged record, not a person. A role nobody has becomes LABOURER, the common case.
static func from_dict(data: Dictionary) -> CrewMember:
	var member: CrewMember = CrewScript.new(StringName(data.get("id", "")), String(data.get("name", "")))
	if String(member.id).is_empty():
		return null
	var role_in := StringName(data.get("role", "LABOURER"))
	member.role = role_in if is_role(role_in) else &"LABOURER"
	var base = data.get("home_base", [])
	if base is Array and (base as Array).size() == 2:
		member.home_base = Vector2(float(base[0]), float(base[1]))
	var rates_in = data.get("rates", [])
	if rates_in is Array:
		for entry in (rates_in as Array):
			if entry is Dictionary:
				member.rates.append({
					"from": String(entry.get("from", "")),
					"loaded_rate": MoneyScript.from_dict(entry.get("loaded_rate", {})),
				})
	var certs_in = data.get("certifications", [])
	if certs_in is Array:
		for entry in (certs_in as Array):
			if entry is Dictionary:
				member.certifications.append({
					"name": String(entry.get("name", "")),
					"expires_at": String(entry.get("expires_at", "")),
				})
	var avail_in = data.get("availability", [])
	if avail_in is Array:
		for entry in (avail_in as Array):
			if entry is Dictionary:
				member.add_availability(entry)
	return member


const CrewScript := preload("res://scripts/biz/crew.gd")