class_name DeskStyle
## The look of the desk's own words: what a page's title, its subheadings, its body lines, its captions and its
## three dimmed kinds are drawn at.
##
## **The mechanism the phone already uses, for the half the phone never had to state.** `TouchStyle` gives a
## control a way to say it is *pressed* or *dead*; it states nothing about size, because a finger's sizes come
## from `PhoneHud`'s own arithmetic. The desk is the other way round: its sizes and its colours were decided in
## `PageChrome` and written onto each control as it was built, so **a look was stated where a control was made
## rather than where a look belongs**. This states it as a `Theme` with a **type variation** per kind -
## `Label/Heading`, `Label/Text`, `Label/Note` - which is the engine's own way of saying "this label is that
## kind of label", and a control that asks by name needs no number at all.
##
## **The numbers are read from `PageChrome` and never restated.** A heading's size is `PageChrome.HEADING_SIZE`
## wherever it is asked for, and `tests/test_desk_style.gd` asserts each variation equals its constant, so the
## two cannot drift apart. A second copy of `20` written here would be a second answer to a question that
## already has one, which is the defect this project works hardest to avoid.
##
## **No label's own geometry changes, and that is the point rather than a happy accident.** `PageChrome._label`
## keeps the size override it always wrote: a page built off the tree - which is every test - wears no theme at
## all, and would otherwise take the engine's default `16` in place of its own. So a variation and an override
## carry the same number from the same constant, in the two places a control can be reached from: the theme for
## anything asking by name, the override for a label with no theme to consult.

extends RefCounted

const PageChromeScript := preload("res://scripts/page_chrome.gd")

## The label kinds this states, each a variation of `Label`. These are the node names `PageChrome` already gives
## the labels it builds, so the kind a control asks for and the name it carries are one word rather than two -
## and `tests/test_desk_style.gd` drives every one of `PageChrome`'s own builders through this list rather than
## trusting that the list is complete.
const KINDS: Array[StringName] = [&"Heading", &"Subheading", &"Text", &"Caption", &"Note", &"Hint", &"Status"]


## The kind this states for a label kind a caller names, so a page can ask `variation_for("Heading")` rather
## than writing a name that would be a second place the vocabulary lives.
static func variation_for(kind: StringName) -> StringName:
	return kind if kind in KINDS else &"Text"


## The size a kind is drawn at, **read from the place that already owns it**.
static func size_for(kind: StringName) -> int:
	match kind:
		&"Heading":
			return PageChromeScript.HEADING_SIZE
		&"Subheading":
			return PageChromeScript.SUBHEADING_SIZE
		_:
			return PageChromeScript.BODY_SIZE


## The colour a kind is dimmed with, or a transparent one for the kinds drawn at full strength - so that
## `is_dimmed` is answered by the same function that answers what the colour is, rather than by a second list.
static func colour_for(kind: StringName) -> Color:
	match kind:
		&"Note":
			return PageChromeScript.NOTE_COLOR
		&"Hint":
			return PageChromeScript.HINT_COLOR
		&"Status":
			return PageChromeScript.STATUS_COLOR
		_:
			return Color(0.0, 0.0, 0.0, 0.0)


## Whether a kind is one of the three drawn dimmer than the rest.
static func is_dimmed(kind: StringName) -> bool:
	return colour_for(kind).a > 0.0


## The theme this program's desk words wear.
##
## Built fresh each call rather than kept in a static, for the reason `TouchStyle.build` gives: a cached
## stylesheet is the kind of thing that goes stale in a way nobody can see.
static func build() -> Theme:
	var theme := Theme.new()
	for kind: StringName in KINDS:
		theme.set_type_variation(kind, &"Label")
		theme.set_font_size(&"font_size", kind, size_for(kind))
		if is_dimmed(kind):
			theme.set_color(&"font_color", kind, colour_for(kind))
	return theme


## Put this program's desk-word style on one carrier - the HUD's own `Root` control, and every page where
## `PageChrome` lands it, which are the two carriers a `CanvasLayer` leaves reachable for the reason
## `TouchStyle` records.
##
## **Merged into the theme a carrier already wears rather than put in its place.** Those two carriers also wear
## `TouchStyle`, and one control can wear one theme: a file that assigned its own would take the phone's press
## and dead states away with it. `merge_with` adds what this states and leaves everything else exactly alone,
## so the order the two are applied in cannot matter and applying either one twice costs nothing.
##
## `true` means the node handed in is a carrier, whether it has just been given this style or already wore one.
static func apply_to(carrier: Node) -> bool:
	var worn: Theme = null
	if carrier is Control:
		worn = (carrier as Control).theme
	elif carrier is Window:
		worn = (carrier as Window).theme
	else:
		return false
	if worn == null:
		worn = Theme.new()
		if carrier is Control:
			(carrier as Control).theme = worn
		else:
			(carrier as Window).theme = worn
	worn.merge_with(build())
	return true
