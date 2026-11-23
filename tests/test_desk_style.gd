## What the desk's own words are drawn at, held where it can be checked: that a variation states the number
## `PageChrome` already owns rather than a second copy of it, that a control can ask by name, and that no label
## changed size - which is the one thing a styling pass may not do here.
##
## **The list of kinds is not trusted, it is driven.** Every one of `PageChrome`'s own builders is called and the
## kind the label ends up asking for is read back, so a builder added without a kind to match it fails here
## rather than taking the engine's default quietly.

extends Node

const DeskStyleScript := preload("res://scripts/desk_style.gd")
const PageChromeScript := preload("res://scripts/page_chrome.gd")

var _made: Array[Node] = []


## Everything a test made, given back, so the run does not report resources still in use.
func _clear() -> void:
	for node: Node in _made:
		if is_instance_valid(node):
			node.free()
	_made.clear()


## A holder in the tree wearing this program's desk style, which is what makes a name look anything up.
func _wearing_the_style() -> Control:
	var holder := Control.new()
	add_child(holder)
	_made.append(holder)
	holder.theme = DeskStyleScript.build()
	return holder


## Every number a variation states is the constant `PageChrome` states, read from there rather than restated:
## the two are asserted against each other so that a copy of `20` written into a second file fails the run.
func test_the_numbers_a_variation_states_are_page_chromes_own() -> void:
	var theme: Theme = DeskStyleScript.build()
	assert(
		theme.get_font_size(&"font_size", &"Heading") == PageChromeScript.HEADING_SIZE,
		"a title is drawn at the size the page chrome already decided",
	)
	assert(
		theme.get_font_size(&"font_size", &"Subheading") == PageChromeScript.SUBHEADING_SIZE,
		"and so is a subheading",
	)
	for kind: StringName in [&"Text", &"Caption", &"Note", &"Hint", &"Status"]:
		assert(
			theme.get_font_size(&"font_size", kind) == PageChromeScript.BODY_SIZE,
			"%s is a body line, whatever it is dimmed with" % kind,
		)


## The point of a type variation: a control says what kind of thing it is, and the look follows from the name
## rather than from a number written at the place the control was built.
func test_a_title_and_a_body_line_are_told_apart_by_their_name_alone() -> void:
	var holder: Control = _wearing_the_style()
	var title := Label.new()
	title.theme_type_variation = &"Heading"
	var body := Label.new()
	body.theme_type_variation = &"Text"
	holder.add_child(title)
	holder.add_child(body)
	assert(
		title.get_theme_font_size(&"font_size") == PageChromeScript.HEADING_SIZE,
		"a label named a heading is drawn as one",
	)
	assert(
		body.get_theme_font_size(&"font_size") == PageChromeScript.BODY_SIZE,
		"a label named a body line is drawn as one",
	)
	assert(
		title.get_theme_font_size(&"font_size") > body.get_theme_font_size(&"font_size"),
		"and the two are told apart, which is the whole of what a variation is for",
	)
	_clear()


## **The safety property this change had to keep.** A page built off the tree - which is every test in this
## project that builds one - wears no theme at all, so a size that lived only in the theme would take the
## engine's default in its place and move every page that was ever measured. It does not, because `PageChrome`
## writes the size onto the label as well; this holds that the number is the same in both places.
func test_a_label_page_chrome_builds_is_the_same_size_with_a_theme_and_without_one() -> void:
	var bare: Label = PageChromeScript.heading("Backyard Design")
	assert(
		bare.get_theme_font_size(&"font_size") == PageChromeScript.HEADING_SIZE,
		"off the tree, a title is the size the page chrome wrote onto it",
	)
	assert(
		bare.theme_type_variation == &"Heading",
		"and it carries the kind it was built as, so a theme can be asked for it",
	)
	var holder: Control = _wearing_the_style()
	holder.add_child(bare)
	assert(
		bare.get_theme_font_size(&"font_size") == PageChromeScript.HEADING_SIZE,
		"and on the tree, wearing the style, it is the same number rather than another",
	)
	_clear()


## **Every builder, driven.** The kinds are read back off real labels rather than compared with the list here,
## so a builder that names a kind this file does not state - a new `code()` line, say - is caught by this test
## rather than quietly taking the engine's default size.
func test_every_label_page_chrome_builds_asks_for_a_kind_this_states() -> void:
	var built: Array[Label] = [
		PageChromeScript.heading("Backyard Design"),
		PageChromeScript.subheading("Plants"),
		PageChromeScript.text("30 plants"),
		PageChromeScript.note("A sentence explaining what this page is for."),
		PageChromeScript.hint("Choose a bed first."),
		PageChromeScript.status("Nothing to undo."),
	]
	var labelled: HBoxContainer = PageChromeScript.labelled("Bed", LineEdit.new())
	_made.append(labelled)
	built.append(labelled.get_child(0) as Label)
	var seen: Array[StringName] = []
	for label: Label in built:
		var kind: StringName = label.theme_type_variation
		assert(kind in DeskStyleScript.KINDS, "%s asks for a kind this states" % String(label.text))
		if not kind in seen:
			seen.append(kind)
	assert(
		seen.size() == DeskStyleScript.KINDS.size(),
		"every kind this states is one a page really builds: %d of %d" % [seen.size(), DeskStyleScript.KINDS.size()],
	)
	_clear()


## The three dimmed kinds state their colour here rather than at the place the label was built, and the kinds
## drawn at full strength state **no colour at all** - writing the engine's own default in as ours would be a
## second answer to a question the theme already answers.
func test_the_three_dimmed_kinds_state_the_colour_page_chrome_dims_them_with() -> void:
	var theme: Theme = DeskStyleScript.build()
	assert(theme.get_color(&"font_color", &"Note") == PageChromeScript.NOTE_COLOR, "a note is dimmed as a note")
	assert(theme.get_color(&"font_color", &"Hint") == PageChromeScript.HINT_COLOR, "a hint as a hint")
	assert(theme.get_color(&"font_color", &"Status") == PageChromeScript.STATUS_COLOR, "a status line as one")
	for kind: StringName in [&"Heading", &"Subheading", &"Text", &"Caption"]:
		assert(
			not theme.has_color(&"font_color", kind),
			"%s is drawn at full strength and states no colour of its own" % kind,
		)
