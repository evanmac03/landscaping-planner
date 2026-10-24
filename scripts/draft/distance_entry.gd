class_name DistanceEntry
extends RefCounted
## Direct distance entry: the length, and the optional angle, a person types while a shape is in hand.
##
## A drafting program's oldest gesture: pick the first point, then instead of hunting for the second
## one with the mouse, type how far away it is. The length is in the drawing's own unit - it is read by
## `DraftUnits.parse_length`, so "12", "12.5", "3cm" and 6'6" all say what they say - and the direction
## is whichever way the cursor is pointing, which means ortho, polar and the object snaps all still
## have their say, because the cursor the direction comes from is the already-snapped one.
##
## The angle marker `<` states the direction outright: "10<45" is ten metres at forty-five degrees.
## Angles are measured the way polar tracking measures them - from the +x axis of the plan, positive
## turning towards +y, which is `atan2` of the plan's own two axes - so a typed angle and a tracked one
## can never disagree about which way ninety degrees is.
##
## **The grammar is kept bare of letters, deliberately.** Every A-Z key is a command in this program, so
## a letter typed here would either be swallowed from the palette or start a tool in the middle of a
## number. Only the characters a length and an angle are actually made of are accepted; the drawing's
## own unit means "12m" is never needed, and the trade is worth it.

const Geom := preload("res://scripts/draft/geom2d.gd")

## The characters that may be typed. A `-` is a sign on the angle only, so a feet-and-inches length is
## written 5'6" or 5 6, never 5-6.
const ACCEPTED := "0123456789.'\"<-"
## The characters a length can *begin* with. A length starts with a number: a sign, an inch mark or an
## angle can only come after one. That is what tells a number key reaching for a length apart from the
## same key reaching for the tool palette, where 1 to 9 and 0 are every tool and the dimension standard.
const STARTS := "0123456789."
const ANGLE_MARK := "<"
## What a `<` with nothing in front of it is missing. `can_type` refuses that `<` in the first place,
## so this answers for an entry that came from somewhere other than the keyboard - a restored one.
const NO_LENGTH := "a length first, then < for the angle"

## Exactly what has been typed, in the order it was typed. The whole state of the entry.
var text: String = ""


func is_empty() -> bool:
	return text.is_empty()


func clear() -> void:
	text = ""


func has_angle() -> bool:
	return text.contains(ANGLE_MARK)


## The length as typed, without the angle.
func length_text() -> String:
	var cut := text.find(ANGLE_MARK)
	return text if cut < 0 else text.substr(0, cut)


## The angle as typed, without its `<`. Empty when no angle was stated.
func angle_text() -> String:
	var cut := text.find(ANGLE_MARK)
	return "" if cut < 0 else text.substr(cut + 1)


## Whether a character is one this entry could ever hold, whatever has been typed so far.
static func accepts(character: String) -> bool:
	return character.length() == 1 and ACCEPTED.contains(character)


## Whether a character could *begin* a length - see `STARTS`.
static func starts_length(character: String) -> bool:
	return character.length() == 1 and STARTS.contains(character)


## Whether this character belongs in the entry *as it stands*. The structural rules live here rather
## than in `problem` so a keystroke that could never be meant is dropped as it is typed instead of
## being reported after Enter.
func can_type(character: String) -> bool:
	if not accepts(character):
		return false
	var part := angle_text() if has_angle() else length_text()
	if character == "-":
		# A sign belongs to the angle and to nothing else: a length is a distance, and a distance is not
		# negative.
		return text.ends_with(ANGLE_MARK)
	if character == ANGLE_MARK:
		# One angle, and it needs a length in front of it to be an angle *of* something.
		return not has_angle() and not length_text().is_empty()
	if character == "'" or character == "\"":
		# A mark marks a number, so there has to be one in front of it - in either half, since a bare
		# inch mark is as meaningless as a bare angle. One inch mark is all a length has.
		return not part.is_empty() and not part.ends_with("\"")
	if character == "." and part.contains("."):
		return false
	return true


func type(character: String) -> bool:
	if not can_type(character):
		return false
	text += character
	return true


## Drop the last character. False when there was nothing to drop, which is the caller's cue to let the
## key mean what it meant before.
func backspace() -> bool:
	if text.is_empty():
		return false
	text = text.substr(0, text.length() - 1)
	return true


## The length in model metres, in the drawing's own unit. NAN when the text is not a length.
func metres(units: DraftUnits) -> float:
	return DraftUnits.parse_length(length_text(), units.system, units.use_us_survey_foot)


func angle_degrees() -> float:
	return angle_text().to_float()


## Why the entry cannot be placed, or "" when it can. Every answer is a sentence a person can act on,
## and none of them is a zero: a length nobody typed is not a length of nothing.
func problem(units: DraftUnits) -> String:
	if is_empty():
		return "no length typed"
	if length_text().is_empty():
		return NO_LENGTH
	var span := metres(units)
	if is_nan(span):
		return "%s is not a length" % length_text()
	if span <= 0.0:
		return "a length has to be more than nothing"
	if has_angle() and not angle_text().is_valid_float():
		return "%s is not an angle" % angle_text()
	return ""


## The way the length runs: the typed angle when one was stated, otherwise the way the cursor points.
##
## `Vector2.ZERO` when there is neither - the cursor is sitting on the very point the length would run
## from, so nothing has been said about direction and a point cannot be guessed at.
func direction(from: Vector2, towards: Vector2) -> Vector2:
	if has_angle():
		return Vector2.RIGHT.rotated(deg_to_rad(angle_degrees()))
	var run := towards - from
	if run.length_squared() <= Geom.EPS:
		return Vector2.ZERO
	return run.normalized()


## The point the typed length lands on. `ZERO`-direction comes back as `from` itself; a caller is
## expected to have asked `direction` first and to refuse rather than place a point on top of the last.
func point_at(from: Vector2, towards: Vector2, units: DraftUnits) -> Vector2:
	var run := direction(from, towards)
	if run == Vector2.ZERO:
		return from
	return from + run * metres(units)


## The entry as words: the length the way the drawing words a length, and the angle when one was
## stated. When something is wrong, the complaint is the words instead - so the line on screen says
## what is wrong while the number is being typed rather than after Enter.
func describe(units: DraftUnits) -> String:
	if is_empty():
		return "no length typed"
	if length_text().is_empty():
		return NO_LENGTH
	var span := metres(units)
	if is_nan(span) or span <= 0.0:
		# The length is what is wrong, and that is worth saying at once.
		return problem(units)
	var words := units.format_length(span)
	if has_angle():
		# An angle still being written reads as what has been typed of it rather than as a complaint:
		# `6<4` is a number in the middle of being typed, and a line that called it a mistake would be
		# scolding a person for typing. Placing the point is what refuses it - see `problem`.
		var typed := angle_text()
		if typed.is_valid_float():
			words += " at %s°" % String.num(angle_degrees(), 2)
		elif typed.is_empty():
			words += " at"
		else:
			words += " at %s" % typed
	return words