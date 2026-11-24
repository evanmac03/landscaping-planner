class_name GuiWords
extends RefCounted
## The words the GUI is made of, and the things that are wrong with them that no rectangle can show.
##
## Every instrument here measures rectangles: whether a box is big enough, whether two overlap, whether text is
## being cut. What none of them reads is the *text* - and a caption that says `Error: invalid input`, a note to
## the author left in a button, a sentence where a name belongs, or a space at the end that pads the box are all
## faults a person sees on the first frame and no measurement can name. This is that reading.
##
## It is deliberately small and deliberately certain. A rule belongs here only when the answer is the same for
## every reader: a space at the end of a caption pads the box, `TODO` is a note to the author, a sentence where
## a name belongs sets the width of the whole row. What a *good* caption says is not here and cannot be: this
## finds the words that are wrong, and says why, in the project's own plain sentences.
##
## ## What is deliberately not a rule, and why
##
## **Capital letters in the middle of a sentence are not policed.** This program's text is full of codes,
## initialisms and names in capitals - `NONE` for a tax code, `CAD`, `UTC-5`, `L1.1`, `010-SURVEY-PROP` - and a
## rule that cannot tell a shout from a layer name names the program's own vocabulary instead of a fault. It
## was written, and it named those five and no shout at all.
##
## It measures nothing of its own and needs no scene, no node and no file, so the whole rule set is held down by
## `tests/test_gui_words.gd`; the live half - which controls are showing what - is `HudProbe`'s.

## A control whose width **is** its words and which draws a second line quite happily: a button, which the tool
## palette is built out of, two lines to a button - the name of the tool over the key that takes it.
const ONE_LINE := &"one line"

## A control that draws one row and **no more**: a menu entry, a tab, an option, a field a person types in. Its
## width is its words as well, and a broken line on one cannot be drawn at all rather than drawn lower down.
const ONE_ROW := &"one row"

## Something that lays words out and may wrap them: a caption, a paragraph, a page of prose.
const PROSE := &"prose"

## A field a person types in, or a caption that holds a value: its text is data, not a sentence.
const OTHER := &"other"

## The longest words a one-line control may carry. Measured against the real controls rather than guessed: the
## widest caption in the program is the tool line's `Polyline  ·  Specify the first point` at 42 characters, and
## the menus' longest entry is `Save the site to the drawing` at 28.
const LONGEST_ONE_LINE := 60

## Words that are a note to the author rather than something for a person.
const AUTHOR_NOTES: Array[String] = ["todo", "fixme", "xxx", "wip", "tbd", "lorem", "placeholder"]

## Words that say nothing a person can use, when they are the whole of what is written.
const HOLLOW: Array[String] = ["none", "null", "<null>", "undefined", "nan", "nil", "void", "n/a"]


## Which kind of words a control carries, which is what decides whether a sentence belongs on it.
static func kind_of(control: Control) -> StringName:
	if control is MenuBar:
		return ONE_ROW
	if control is LineEdit:
		return ONE_ROW
	if control is TabBar:
		return ONE_ROW
	if control is OptionButton:
		return ONE_ROW
	if control is BaseButton:
		return ONE_LINE
	if control is ItemList or control is Tree:
		return OTHER
	return PROSE


## Everything wrong with one string, in the words it is and where it stands. Empty is the good answer, and it
## is the answer for most of the program's words - which is the point of keeping the rules tight.
static func faults(said: String, kind: StringName, where: String) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	if said.strip_edges().is_empty():
		return found
	var edges: String = said
	if edges != edges.strip_edges():
		found.append(_fault(said, where, "has space at the %s, which shifts the words and pads the box" % _edge(edges)))
	if _has_a_slip_of_two_spaces(said):
		found.append(_fault(said, where, "has two spaces together, which is a typing accident"))
	if kind == ONE_ROW and (said.contains("\n") or said.contains("\t")):
		found.append(_fault(said, where, "is broken over more than one row where only one can be drawn"))
	for word: String in AUTHOR_NOTES:
		if _has_word(said, word):
			found.append(
				_fault(said, where, "holds \"%s\", which is a note to the author and not words for a person" % word)
			)
	for word: String in HOLLOW:
		if said.strip_edges().to_lower() == word:
			found.append(_fault(said, where, "says \"%s\", which is nothing a person can use" % said.strip_edges()))
			break
	for word: String in DOCTRINE:
		if _has_word(said, word):
			found.append(_fault(said, where, "reads \"%s\", which is a message a compiler would write" % word))
			break
	if kind == ONE_LINE or kind == ONE_ROW:
		if said.length() > LONGEST_ONE_LINE:
			found.append(
				_fault(
					said,
					where,
					"is %d characters long, where one line holds %d" % [said.length(), LONGEST_ONE_LINE],
				),
			)
	if said.contains("!!") or said.contains("??") or said.contains("..") and not said.contains("..."):
		found.append(_fault(said, where, "writes its punctuation twice"))
	return found


## The words a person reads for one fault: where it stands, the text as it is, and what is wrong with it.
static func sentence(fault: Dictionary) -> String:
	return "%s  %s  -  %s" % [fault["where"], _as_words(fault["said"]), fault["why"]]


## A rule belongs here only when every reader agrees, so the anti-examples the project already sets out in
## `AGENTS.md` are the whole list: no `Error: invalid input`, and nothing a compiler would have written.
const DOCTRINE: Array[String] = ["error", "invalid", "unexpected", "exception", "cannot be null", "is null"]


static func _fault(said: String, where: String, why: String) -> Dictionary:
	return { "said": said, "where": where, "why": why }


## Which end a thing has space on, so a caption that is padded at the front is not called padded at the back.
static func _edge(said: String) -> String:
	if said.begins_with(" ") and said.ends_with(" "):
		return "front and the end"
	return "front" if said.begins_with(" ") else "end"


## Whether a word stands in a string by itself rather than inside a longer one: `TODO` is a note, and
## `TODOSomething` is a name somebody meant.
static func _has_word(said: String, word: String) -> bool:
	var lower: String = said.to_lower()
	var at: int = lower.find(word)
	while at >= 0:
		var ends_clean: bool = at + word.length() >= lower.length() or not _is_word_char(lower[at + word.length()])
		if (at == 0 or not _is_word_char(lower[at - 1])) and ends_clean:
			return true
		at = lower.find(word, at + 1)
	return false


## Whether a string has a run of **exactly two** spaces that is a slip rather than the program setting one thing
## apart from what follows.
##
## The program uses two spaces to separate a label from its reading - after a colon or a full stop - and to line
## a keyboard hint up before a bracket; three or more is a gap the line at the foot of the screen uses between
## its groups. What is left is two spaces in the middle of a phrase, which is a slip. Used runs are skipped
## rather than the whole string being let off, so a caption can set something apart and still be mistyped.
static func _has_a_slip_of_two_spaces(said: String) -> bool:
	var at: int = said.find("  ")
	while at >= 0:
		var run := 2
		while at + run < said.length() and said[at + run] == " ":
			run += 1
		if run == 2 and not _sets_apart(said, at):
			return true
		at = said.find("  ", at + run)
	return false


## Whether a run of spaces starting at `at` sets one thing apart from what follows: before a bracket, where a
## keyboard hint goes, or after a colon or a full stop, which is where the program puts a label's reading.
static func _sets_apart(said: String, at: int) -> bool:
	if at + 2 >= said.length():
		return true
	if said[at + 2] == "(":
		return true
	return at > 0 and (said[at - 1] == ":" or said[at - 1] == ".")


static func _is_word_char(one: String) -> bool:
	return (one >= "a" and one <= "z") or (one >= "0" and one <= "9")


## A fault's text as a person reads it: quoted, and cut short when the whole of it would swamp the line - the
## point of the line is which control is wrong, and a paragraph repeated in full buries that.
static func _as_words(said: String) -> String:
	var trimmed: String = said.strip_edges()
	if trimmed.length() > 48:
		return "\"%s...\"" % trimmed.substr(0, 48)
	return "\"%s\"" % trimmed
