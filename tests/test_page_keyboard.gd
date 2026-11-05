extends Node
## What a page does with the keyboard once it is open.
##
## The rule this holds down is one half of a measurement and one decision. The measurement
## (`tools/page_keyboard_probe.tscn`, every row read live): a page in a `Window` **holds the keyboard
## while it is up** - the drawing's own keys never reach the viewport behind it - and gives it back when
## the page goes away. The decision from it: because the drawing cannot lose a key to a page that is
## already holding them all, every control on a page may take the keyboard, and that is decided in one
## place rather than by thirty pages each guessing.
##
## `PageChrome.takes_the_keyboard` is that place and `show_centred` is what calls it, so these tests ask
## both halves: the rule itself (what is given the keyboard, what is deliberately not, and where the rule
## stops at a page that answers for its own), and that the shared show is what puts it into effect.
##
## The pages themselves are asked as they are *built* as well as shown. A page that builds its own
## controls focus-free is not a fault - it is a page not pre-empting the rule - and the run time is what
## gives them the keyboard.

const PageChromeScript := preload("res://scripts/page_chrome.gd")
const SnapWindowScript := preload("res://scripts/snap_window.gd")
const PaletteScript := preload("res://scripts/command_palette.gd")
const HelpWindowScript := preload("res://scripts/help_window.gd")


# --- the rule ---------------------------------------------------------------------------------------


## The controls a person acts with are the ones given the keyboard, and the things a person reads or
## that only lay the page out are left exactly as they are.
func test_only_the_things_a_person_acts_with_are_given_the_keyboard() -> void:
	var page := Window.new()
	var column := PageChromeScript.column(page)
	# Built the way a page builds them: a control made for a page takes no keyboard of its own, which is
	# what leaves the rule below something to do rather than reporting what the engine would have done
	# anyway.
	var button := PageChromeScript.button("Do the thing")
	column.add_child(button)
	var check := CheckBox.new()
	check.name = "Live"
	check.focus_mode = Control.FOCUS_NONE
	column.add_child(check)
	var list := ItemList.new()
	list.name = "Rows"
	list.add_item("one")
	list.focus_mode = Control.FOCUS_NONE
	column.add_child(list)
	var caption := Label.new()
	caption.name = "Caption"
	column.add_child(caption)
	var picture := TextureRect.new()
	picture.name = "Picture"
	column.add_child(picture)
	# And the one thing on a page that is *meant* to hold the keyboard already: a field to type into.
	var field := LineEdit.new()
	field.name = "Field"
	column.add_child(field)

	var given: int = PageChromeScript.takes_the_keyboard(page)
	assert(given == 3, "the button, the checkbox and the list, and nothing else: %d" % given)
	assert(button.focus_mode == Control.FOCUS_ALL)
	assert(check.focus_mode == Control.FOCUS_ALL)
	assert(list.focus_mode == Control.FOCUS_ALL)
	assert(caption.focus_mode == Control.FOCUS_NONE, "a caption is read, not pressed")
	assert(picture.focus_mode == Control.FOCUS_NONE, "and a picture is looked at")
	assert(field.focus_mode != Control.FOCUS_NONE, "a field that already held it was left alone")

	page.free()


## A dialog inside a page owns its own keyboard: taking one of its controls out of the focus chain is
## what once left the Save dialog untypeable, so the sweep stops at every `Window`.
func test_a_dialog_inside_a_page_keeps_its_own_keyboard() -> void:
	var page := Window.new()
	var column := PageChromeScript.column(page)
	var dialog := ConfirmationDialog.new()
	dialog.name = "Ask"
	column.add_child(dialog)
	var ok := Button.new()
	ok.name = "OK"
	ok.focus_mode = Control.FOCUS_NONE
	dialog.add_child(ok)

	var given: int = PageChromeScript.takes_the_keyboard(page)
	assert(given == 0, "nothing outside the dialog either: %d" % given)
	assert(ok.focus_mode == Control.FOCUS_NONE, "a dialog's own button is not ours to re-key")

	page.free()


## A page that is not up is left exactly as it is built, so a page that rebuilds its rows while it is
## closed cannot sweep itself into a state the next show was going to decide anyway - and the two halves
## of "up" both matter: **a `Window` reports itself visible before it is ever shown**.
func test_a_page_that_is_not_up_is_left_alone_by_the_incremental_form() -> void:
	var page := Window.new()
	var column := PageChromeScript.column(page)
	var button := PageChromeScript.button("Do the thing")
	column.add_child(button)

	assert(page.visible, "a Window is visible from the moment it is made")
	assert(PageChromeScript.takes_the_keyboard_if_up(page) == 0, "but not in the tree, so not up")
	assert(button.focus_mode == Control.FOCUS_NONE)

	add_child(page)
	assert(PageChromeScript.takes_the_keyboard_if_up(page) == 1, "in the tree and on the screen")
	assert(button.focus_mode == Control.FOCUS_ALL, "so now it can be reached")

	page.free()


# --- what the shared show does with it --------------------------------------------------------------


## The shared show is what puts the rule into effect. A page built and shown is a page a person can walk
## with Tab and press with Enter, which is the whole of the change.
func test_the_shared_show_is_what_gives_a_page_its_controls_the_keyboard() -> void:
	var page := Window.new()
	page.name = "Shown"
	var column := PageChromeScript.column(page)
	var button := PageChromeScript.button("Do the thing")
	column.add_child(button)
	var list := ItemList.new()
	list.name = "Rows"
	list.focus_mode = Control.FOCUS_NONE
	column.add_child(list)
	add_child(page)

	PageChromeScript.show_centred(page)

	assert(button.focus_mode == Control.FOCUS_ALL, "the show is what gave it the keyboard")
	assert(list.focus_mode == Control.FOCUS_ALL)
	assert(page.visible, "and the page is up, which is when a page holds the keyboard at all")

	page.free()


## A page the program really builds, built and shown the way the program shows it, is keyboard-reachable
## on every switch and button it has - not only the fields it was written with.
func test_a_real_page_can_be_walked_with_the_keyboard_once_it_is_shown() -> void:
	var page: Window = SnapWindowScript.new()
	page.build()
	var switches: Array[Node] = page.find_children("*", "CheckBox", true, false)
	var buttons: Array[Node] = page.find_children("*", "Button", true, false)
	assert(switches.size() >= 4, "the snapping page really has switches on it: %d" % switches.size())
	assert(buttons.size() >= 1, "and buttons")
	add_child(page)

	PageChromeScript.show_centred(page)

	for found: Node in switches:
		assert((found as Control).focus_mode == Control.FOCUS_ALL, "%s can be reached" % found.name)
	for found: Node in buttons:
		assert((found as Control).focus_mode == Control.FOCUS_ALL, "%s can be reached" % found.name)

	page.free()


# --- what the runner cannot ask, and where it is asked instead -------------------------------------


## Two claims about a page with the keyboard are **not** tested here, on purpose, because the runner cannot
## ask them: a key injected in the test runner does not reach the focused control inside an embedded
## `Window`. A page holds the keyboard only once the game's own window is up, which is the fact
## `tools/page_keyboard_probe.tscn` measures (`Tab nothing -> SnapToggle`). Both claims are live ones, and
## both have been settled:
##
## - **A page's own list can be walked with the arrows and picked with Enter.** The engine's `ItemList`
##   does the navigating; what this project owes it is `FOCUS_ALL`, which
##   `test_the_shared_show_is_what_gives_a_page_its_controls_the_keyboard` holds for a list, and
##   `test_a_real_page_can_be_walked_with_the_keyboard_once_it_is_shown` holds for a whole page. There is
##   nothing left for the project to do about it, which is why there is no second test.
## - **Escape with a field holding the keyboard takes two presses** - the first lets the field go, the
##   second puts the page away. `tools/page_escape_demo.tscn` reports it page by page: 16 of the 18 pages
##   close on one Escape, and exactly the two whose own focus is a field need two. **The decision is that
##   this is the behaviour that is wanted**: a field is where somebody is typing, and the press that gets
##   them out of it should not also throw the page away. `scripts/page_escape.gd` says why the closer has
##   to live inside the page at all.
##
## A test that tried to hold either one off-tree was written, failed, and was removed rather than bent to
## pass: it was measuring the runner, not the project.


# --- the pages that answer for their own ------------------------------------------------------------


## The palette and the manual are shown by their own `open()` and answer the keyboard themselves, so the
## rule leaves them exactly as they are built - including the palette's list, which must stay out of the
## focus chain because the field above it is what answers the arrows and Enter.
func test_the_pages_that_answer_for_themselves_are_left_alone() -> void:
	var palette: Window = PaletteScript.new()
	palette.build()
	assert(
		palette.commands_list().focus_mode == Control.FOCUS_NONE,
		"the palette's list is picked from, not typed into"
	)
	assert(PageChromeScript.takes_the_keyboard(palette) == 0, "so the rule does not touch the page")
	assert(
		palette.commands_list().focus_mode == Control.FOCUS_NONE,
		"and it is still out of the focus chain afterwards"
	)
	palette.free()

	var manual: Window = HelpWindowScript.new()
	manual.build()
	assert(PageChromeScript.takes_the_keyboard(manual) == 0, "the manual moves its own selection")
	var fields: Array[Node] = manual.find_children("*", "LineEdit", true, false)
	assert(not fields.is_empty(), "and the field that answers for it still has the keyboard")
	for found: Node in fields:
		assert((found as Control).focus_mode != Control.FOCUS_NONE)
	manual.free()


## The exception names files rather than node names, so what it names has to be the two pages it says: a
## path that stopped existing, or one that stopped making a page, would be an exception for nothing.
func test_the_files_the_exception_names_are_the_pages_it_means() -> void:
	for path: String in PageChromeScript.ANSWER_FOR_THEIR_OWN_KEYBOARD:
		assert(ResourceLoader.exists(path), "%s is a file this project has" % path)
		var page_script: Script = load(path) as Script
		assert(page_script != null, "%s is a script" % path)
		var page: Window = page_script.new() as Window
		assert(page != null, "%s makes a Window, which is what a page is" % path)
		page.free()