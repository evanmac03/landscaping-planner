extends Node
## The manual itself: that it covers what it claims to, that every subject has something written under
## it, and that searching it finds a subject by a word in it and nothing by a word that is not there.
##
## The manual is data rather than a screen, so this is the one part of the suite that can check
## documentation by reading it. What is asserted is the claim "document everything" - the subjects are
## named in one place, they are all present, each is written about, and every menu in the bar has
## something written about it - plus the search, which is the only thing about a manual that can be
## wrong without anybody noticing.

const HelpDocScript := preload("res://scripts/help_doc.gd")
const HudScript := preload("res://scripts/hud.gd")
const PlantSymbolsScript := preload("res://scripts/plant_symbols.gd")
const StatusHistoryScript := preload("res://scripts/draft/status_history.gd")

## The word each menu's subject is documented under, one per menu in the bar. A menu with nothing
## written about it fails the test below, which is what "document everything" has to mean to be worth
## saying.
const MENU_WORDS: Dictionary = {
	"File": "file",
	"Edit": "editing",
	"View": "views",
	"Draft": "tools",
	"Site": "ground",
	"Plant": "plants",
	"Water": "irrigation",
	"Light": "lighting",
	"Pipeline": "pipeline",
	"Jobs": "jobs",
	"Estimate": "estimate",
	"Present": "presenting",
	"Team": "others",
	"Help": "manual",
}


func _range(count: int) -> Array[int]:
	var out: Array[int] = []
	for index in count:
		out.append(index)
	return out


func _all_words() -> String:
	var words := ""
	for topic: Dictionary in HelpDocScript.topics():
		words += String(topic["title"]) + " " + String(topic["body"]) + " "
	return words.to_lower()


func test_the_manual_documents_exactly_the_subjects_it_names() -> void:
	# The list of subjects is the claim; the manual is what is actually written. They are two tables,
	# so this is the test that stops one of them being changed without the other.
	assert(
		HelpDocScript.titles() == HelpDocScript.SUBJECTS,
		"the manual holds one topic per subject it names, in that order"
	)


## The sections are `SUBJECTS` split up and nothing else: every subject under exactly one heading, the
## headings in reading order, and the order of the subjects itself unchanged.
##
## The contents is drawn with these, so this is the test that stops a subject being filed nowhere (and
## so never listed) or filed twice (and so listed under two headings) - the ways a table of groups goes
## wrong while the list it groups stays perfectly correct.
func test_the_sections_are_the_subjects_split_up_and_in_the_same_order() -> void:
	var filed: Array[String] = []
	var headings: Array[String] = []
	for section: Dictionary in HelpDocScript.SECTIONS:
		var heading := String(section["title"])
		assert(heading.strip_edges() == heading and heading != "", "a heading is a clean title")
		assert(not headings.has(heading), "%s is used as one heading, not two" % heading)
		headings.append(heading)
		var subjects: Array = section["topics"]
		assert(not subjects.is_empty(), "%s files something" % heading)
		for subject: Variant in subjects:
			filed.append(String(subject))
	assert(
		filed == HelpDocScript.SUBJECTS,
		"the sections are every subject the manual names, each once, in the order it is read"
	)
	assert(headings.size() > 1, "and there is more than one of them, or the contents is not grouped")


## Every cross-reference points at a subject the manual actually has, and none at itself.
##
## A link is a promise that pressing it *goes* somewhere. A name nothing answers to is a button that
## does nothing, and the page cannot tell the reader that until they have already pressed it.
func test_every_cross_reference_names_subjects_the_manual_has() -> void:
	assert(HelpDocScript.SEE_ALSO.size() > 0, "some subjects point at others")
	for key: Variant in HelpDocScript.SEE_ALSO:
		var from := String(key)
		assert(
			HelpDocScript.index_of(from) >= 0,
			"\"%s\" pointers are a subject of the manual, so there is somewhere to point from" % from
		)
		var targets: Array = HelpDocScript.SEE_ALSO[from]
		assert(not targets.is_empty(), "%s points at something" % from)
		for target: Variant in targets:
			var to := String(target)
			assert(
				HelpDocScript.index_of(to) >= 0,
				"%s points at a subject the manual has: there is no \"%s\"" % [from, to]
			)
			assert(to != from, "%s does not point at itself" % from)


func test_every_subject_is_a_clean_title_with_a_body_under_it() -> void:
	var seen: Array[String] = []
	for subject: String in HelpDocScript.SUBJECTS:
		assert(subject.strip_edges() == subject and subject != "", "a subject is a clean title: %s" % subject)
		assert(not seen.has(subject), "%s is written about once" % subject)
		seen.append(subject)
		var body := HelpDocScript.body_for(subject)
		assert(body.length() > 120, "%s has something written about it" % subject)
		assert(not body.begins_with("\n"), "%s does not open on a blank line" % subject)
		assert(not body.ends_with("\n"), "%s does not end on a blank line" % subject)


## The shape a subject has to be: **one** subject, made of paragraphs a person can read.
##
## This is the guard for the failure none of the others could see. "Food: what will crop here" was
## doing the work of six subjects - the light check, the rotation, the calendar, the sowing, the yield
## and the hand-off to the nursery order, 4,798 characters of it - while the business half of the
## program had long since been split into four. Nothing failed: every fact in that body was true, every
## guard above passed, and the menu it names still exists. What was wrong was only that nobody would
## read it - and a reader looking for the sowing was told the manual does not mention it, because
## "yield", "sow", "succession" and "companion" were all buried in one subject's prose.
##
## The two numbers are the manual's own rather than invented: its longest paragraph is 592 characters
## ("What this program is") and its longest body is 2,034 ("Drawing: the tools"). Past these a subject
## has stopped being a subject and started being a chapter, and the fix is the one that was applied to
## the food garden - split it and name the pieces in `SUBJECTS` and `SECTIONS`.
const LONGEST_PARAGRAPH := 700
const LONGEST_BODY := 3000


func test_no_subject_is_a_wall_of_prose() -> void:
	var longest := 0
	for subject: String in HelpDocScript.SUBJECTS:
		var body := HelpDocScript.body_for(subject)
		assert(
			body.length() <= LONGEST_BODY,
			(
				"%s is %d characters, so it is more than one subject: split it into the subjects it covers "
				+ "and add them to SUBJECTS and SECTIONS"
			) % [subject, body.length()]
		)
		# A paragraph is a line. The manual writes one paragraph per line, separated by blank lines, and
		# a row of a table is a line too - both are read at a glance or not at all.
		for line: String in Array(body.split("\n")):
			if line.strip_edges() == "":
				continue
			longest = maxi(longest, line.length())
			assert(
				line.length() <= LONGEST_PARAGRAPH,
				(
					"%s has a %d-character line, which is two paragraphs run together: break it"
				) % [subject, line.length()]
			)
	# Teeth: a guard that measured nothing would pass in silence, which is exactly how the food garden
	# got to 4,798 characters in the first place.
	assert(
		longest > 400,
		"the guard measured the manual's real paragraphs rather than an empty one: longest %d" % longest
	)


func test_every_menu_in_the_bar_has_something_written_about_it() -> void:
	var words := _all_words()
	var titles: Array[String] = []
	for menu: Dictionary in HudScript.menu_plan():
		titles.append(String(menu["title"]))
	assert(titles.size() > 0, "the bar has menus")
	for title: String in titles:
		assert(MENU_WORDS.has(title), "%s has a subject named for it in this test" % title)
		var word := String(MENU_WORDS[title])
		assert(words.contains(word), "%s is documented: nothing in the manual says %s" % [title, word])


func test_a_search_finds_a_topic_by_a_word_in_it() -> void:
	var all: Array[Dictionary] = HelpDocScript.topics()
	assert(HelpDocScript.find_in(all, "") == _range(all.size()), "an empty search finds every topic")
	var hits: Array[int] = HelpDocScript.find_in(all, "valve")
	assert(hits.size() >= 1, "the word a body carries is found")
	assert(
		hits.has(HelpDocScript.index_of("Water: irrigation")),
		"and the subject whose body carries it is one of them"
	)


func test_a_search_is_not_case_sensitive_and_finds_a_subject_by_its_title() -> void:
	var all: Array[Dictionary] = HelpDocScript.topics()
	var shouted: Array[int] = HelpDocScript.find_in(all, "TRANSFORMER")
	assert(shouted.size() >= 1, "a word is found however it is typed")
	assert(
		HelpDocScript.find_in(all, "transformer") == shouted,
		"and shouting at it finds the same topics"
	)
	var by_title: Array[int] = HelpDocScript.find_in(all, "lighting")
	assert(
		by_title.has(HelpDocScript.index_of("Light: garden lighting")),
		"a subject is found by its own title as well as by a word in its body"
	)


func test_a_search_for_nothing_real_finds_nothing_rather_than_a_near_miss() -> void:
	var all: Array[Dictionary] = HelpDocScript.topics()
	assert(HelpDocScript.find_in(all, "zzzznotaword").is_empty(), "no topic matches it")
	assert(HelpDocScript.find("zzzznotaword").is_empty(), "and the same over the manual itself")
	assert(HelpDocScript.find_in(all, "   ").size() == all.size(), "spaces are just an empty search")


func test_the_search_rule_reads_a_subject_by_its_name_first_and_by_where_it_is_filed_last() -> void:
	# One topic for each way of matching, written in an order that is *not* the answer, so a rule that
	# kept the reading order - or that stopped at the first two tiers - fails this.
	var topics: Array[Dictionary] = [
		{"title": "Something else", "body": "prose about neither", "section": "A section on water"},
		{"title": "Something else again", "body": "this one is about water", "section": "Dry ground"},
		{"title": "On water", "body": "not a word about it", "section": "Dry ground"},
		{"title": "Watering", "body": "not a word about it", "section": "Dry ground"},
	]
	var found: Array[int] = HelpDocScript.find_in(topics, "water")
	assert(
		found == [3, 2, 1, 0],
		"named for the word, then named with it, then about it, then only filed under it: got %s" % [found]
	)
	assert(found.size() == topics.size(), "and every topic is in exactly one tier")
	assert(
		HelpDocScript.find_in(topics, "  WATer ") == found,
		"the word is trimmed and the match is not case-sensitive"
	)


func test_a_subject_is_found_by_the_word_it_is_named_for_before_one_that_only_discusses_it() -> void:
	var water: Array[int] = HelpDocScript.find("water")
	assert(water.size() >= 2, "more than one subject answers to water")
	assert(
		HelpDocScript.title_at(water[0]) == "Water: irrigation",
		"the subject named for water comes first, where the reading order had it last: %s" % [water]
	)
	var food: Array[int] = HelpDocScript.find("food")
	var named: Array[int] = []
	for index: int in food:
		if HelpDocScript.title_at(index).begins_with("Food:"):
			named.append(index)
	assert(named.size() == 5, "the five food subjects are all named for the word")
	assert(
		food.slice(0, named.size()) == named,
		"and they come before the subjects that only discuss food: %s" % [food]
	)


func test_a_title_nobody_has_is_not_a_topic() -> void:
	assert(HelpDocScript.index_of("How to fly a kite") == -1, "there is no such subject")
	assert(HelpDocScript.body_for("How to fly a kite") == "", "and it has no body")
	assert(HelpDocScript.title_at(9999) == "", "past the end there is no title")
	assert(HelpDocScript.title_at(-1) == "", "and neither before the beginning")


func test_a_body_is_the_body_that_was_written() -> void:
	var at: int = HelpDocScript.index_of("Plants")
	assert(at >= 0, "there is a subject about plants")
	var all: Array[Dictionary] = HelpDocScript.topics()
	assert(HelpDocScript.body_for("Plants") == String(all[at]["body"]), "asking for it gives its own body")
	assert(HelpDocScript.title_at(at) == "Plants", "and its own title")
	assert(
		HelpDocScript.body_for("plants") == HelpDocScript.body_for("Plants"),
		"a title is looked up by its words rather than by its capital letters"
	)


func test_the_manual_says_how_much_of_it_there_is() -> void:
	var line := HelpDocScript.describe()
	assert(line.contains(str(HelpDocScript.topic_count())), "it counts its own topics")
	assert(line.contains("topics"), "and says what they are")
	assert(HelpDocScript.topic_count() >= 15, "the manual is a manual rather than a note")


## The guard the prose needed: the palette and the corner legend are built from these two tables, and
## the manual is prose, so nothing else keeps them in step. This is what would have caught the angular
## dimension and move/copy going missing from the manual.
##
## Each tool's own word must appear in the topic that lists that set - the drawing tools in the topic
## whose title contains "drawing:", the edits in "Editing shapes" - as a *word* rather than as part of
## a longer one, so "move" is satisfied by nothing but "move" and not by "moves" or "removed".
func test_every_drawing_tool_and_edit_the_program_has_is_named_in_the_manual() -> void:
	var drawing := _body_under("drawing:")
	assert(drawing != "", "the topic that lists the drawing tools is found")
	for pair: Array in HudScript.DRAFTING_TOOLS:
		assert(_has_word(drawing, String(pair[1])), "the manual names the %s tool" % pair[1])
	var editing := _body_under("editing shapes")
	assert(editing != "", "the topic that lists the editing commands is found")
	for pair: Array in HudScript.EDIT_TOOLS:
		assert(_has_word(editing, String(pair[1])), "the manual names the %s edit" % pair[1])


## The body of the one topic whose title contains `part`, or "" when there is none. Looked up by a
## stable part of the title rather than the whole of it, so rewording a title - dropping a count from
## it, say - does not quietly turn this guard into a test of an empty string.
func _body_under(part: String) -> String:
	var needle := part.to_lower()
	for topic: Dictionary in HelpDocScript.topics():
		if String(topic["title"]).to_lower().contains(needle):
			return String(topic["body"])
	return ""


## Whether `word` stands in `text` as a word of its own - bounded on each side by something that is
## not a letter, a digit or an underscore - rather than buried inside a longer one.
func _has_word(text: String, word: String) -> bool:
	var haystack := text.to_lower()
	var needle := word.to_lower()
	var from := 0
	while true:
		var at := haystack.find(needle, from)
		if at < 0:
			return false
		var before_ok := at == 0 or not _is_word_char(haystack[at - 1])
		var after := at + needle.length()
		var after_ok := after >= haystack.length() or not _is_word_char(haystack[after])
		if before_ok and after_ok:
			return true
		from = at + 1
	return false


func _is_word_char(character: String) -> bool:
	if character == "_" or character.is_valid_int():
		return true
	var code := character.to_lower().unicode_at(0)
	return code >= 97 and code <= 122


## The controls the manual names a key for that the HUD keeps no table of: the view controls, and the
## three commands whose keys are advertised in the manual's prose rather than in a legend row.
##
## The **actions** are named here and each key is read from the input map, so this is not a second copy
## of any binding - naming *which* controls matter is a judgement, and naming their keys is not.
##
## The four look controls are deliberately absent. The manual names them collectively ("the arrow keys
## look", the same collective wording the HUD's own hints line uses), so there is no per-action key in
## the prose for anything to be held against.
const KEYS_NAMED_OUTSIDE_THE_TABLES: Dictionary = {
	"The three views": [
		&"toggle_view",
		&"move_forward",
		&"move_back",
		&"move_left",
		&"move_right",
		&"sprint",
		&"toggle_ground",
		&"fit_view",
		&"vis_painted",
	],
	"Plants": [&"plant_library"],
	"Finding any command: the palette": [&"command_palette"],
	"Drawing: the tools": [&"draft_mode"],
}


## The key an action is on, in the words the program itself uses for it.
##
## Read from the input map by the HUD - the HUD shortens a couple of Godot's names on the way out, so
## "Period" arrives as the full stop a hand actually presses - which means the manual is held against
## the very string the legend and the key reference print, and a rebinding moves all three together.
func _key_of(action: StringName) -> String:
	return HudScript._key_label(action)


## The line of a topic that names `name` as a word **and** carries `key` as a word of its own, or "".
##
## Both halves are words, so the rectangle's row is not satisfied by the word "rectangle" on a line that
## happens to mention 1, and a tool named "line" is not satisfied by a line that says "lines".
func _row_naming_with_key(body: String, key: String, name: String) -> String:
	for line: String in Array(body.split("\n")):
		if _has_word(line, name) and _has_word(line, key):
			return line.strip_edges()
	return ""


## The other half of the same claim about the drawing: the key the manual prints **beside** a tool is
## the key that tool is really on.
##
## The manual's tool and edit lists are the same shape as the legend's own rows - a key, a name, and what
## the tool takes - so this holds the manual against the tables the legend is built from and the input
## map underneath them. A tool moved off the number keys, or an edit moved to another letter, leaves the
## manual sending a reader to a key that does something else entirely.
##
## The guard above checks the manual *names* every tool and edit. This checks it names them with their
## **own** keys.
func test_the_key_the_manual_prints_beside_a_tool_is_the_key_it_is_really_on() -> void:
	# The bodies the tool and the edit lists live in, found by a stable part of their titles - the same
	# two the guard above uses.
	var groups: Array = [
		[_body_under("drawing:"), HudScript.DRAFTING_TOOLS, "tool"],
		[_body_under("editing shapes"), HudScript.EDIT_TOOLS, "edit"],
	]
	var checked := 0
	var expected := 0
	for group: Array in groups:
		var body := String(group[0])
		assert(body != "", "the topic that lists the %ss is found" % group[2])
		for pair: Array in group[1]:
			expected += 1
			var key := _key_of(StringName(pair[0]))
			assert(key != "", "the %s \"%s\" is on some key" % [group[2], pair[1]])
			var row := _row_naming_with_key(body, key, String(pair[1]))
			assert(
				row != "",
				(
					"the manual names the %s \"%s\" with the key it is on: no line of that topic says both "
					+ "\"%s\" and \"%s\""
				) % [group[2], pair[1], pair[1], key]
			)
			checked += 1
	assert(
		checked == expected and expected >= 18,
		"every tool and edit was checked: %d of %d" % [checked, expected]
	)


## Every key the program advertises for itself is named in the manual.
##
## The keys the program has are the four tables the legend and the key reference are built from: the
## drawing tools, the drawing commands, the editing commands, and the five keys kept for the pages
## elsewhere. Each is a command-and-key the program publishes, so a manual that describes the program
## has to carry it - and the key is read from the input map, so this is not a second copy of a binding.
##
## The word is looked for anywhere in the manual rather than in one topic, because a key is advertised
## once and mentioned where it is useful: the plot key belongs to the plotting topic and the palette's to
## the palette's, and neither belongs to a list of keys.
func test_every_key_the_program_advertises_is_named_in_the_manual() -> void:
	var words := _all_words()
	var tables := {
		"the drawing tools": HudScript.DRAFTING_TOOLS,
		"the drawing commands": HudScript.DRAFTING_COMMANDS,
		"the editing commands": HudScript.EDIT_TOOLS,
		"the keys kept for elsewhere": HudScript.ELSEWHERE_KEYS,
	}
	var checked := 0
	var expected := 0
	for table_name: String in tables:
		for pair: Array in tables[table_name]:
			expected += 1
			var key := _key_of(StringName(pair[0]))
			assert(key != "", "%s, in %s, is on some key" % [pair[1], table_name])
			checked += 1
			assert(
				_has_word(words, key),
				"the manual names the key for %s (on \"%s\", from %s): nothing in the manual says it" % [
					pair[1], key, table_name,
				]
			)
	assert(
		checked == expected and expected >= 30,
		"every advertised key was checked: %d of %d" % [checked, expected]
	)


## And the keys the manual names for controls **no** table carries are the keys those controls are on.
##
## This is the half the test above cannot reach: the view controls and the two pages are advertised in
## hint lines written as sentences rather than in tables, so a rebinding of the key that swaps the
## views - the one key in the program that is most likely to move - would leave the manual telling a
## reader to press a key that no longer does anything, with nothing to notice it.
##
## Each claim is scoped to the topic that documents that control, which is what stops it being satisfied
## by a stray letter elsewhere in the manual. **Known soft spot**: "A" is also the English article, so the
## movement keys' claim cannot tell the key from the word around it; the other eleven are exact.
func test_the_keys_the_manual_names_outside_the_tables_are_the_keys_those_controls_are_on() -> void:
	var checked := 0
	for topic_title: String in KEYS_NAMED_OUTSIDE_THE_TABLES:
		var body := HelpDocScript.body_for(topic_title)
		assert(body != "", "the manual has the topic \"%s\"" % topic_title)
		for action: StringName in KEYS_NAMED_OUTSIDE_THE_TABLES[topic_title]:
			var key := _key_of(action)
			assert(key != "", "%s is on some key" % action)
			checked += 1
			assert(
				_has_word(body, key),
				"the manual names the key for %s in \"%s\": the control is on \"%s\" and that topic does not say so" % [
					action, topic_title, key,
				]
			)
	assert(checked >= 12, "the keys outside the tables were checked: %d" % checked)


## The other guard the prose needed: the manual names menu entries all through it - "Site > Read
## the ground from the drawing", "Present > Quality", "Jobs > What has been billed..." - and nothing
## else keeps those names current. A command renamed in the bar leaves the manual pointing at a menu
## entry that is no longer there, and the reader has nowhere to go.
##
## Every "Menu > " the prose writes must begin a label the bar actually has, for that menu. The two
## may differ by the tail a menu appends to explain itself ("...: levels, contours, slopes") and by
## the ellipsis a menu writes on a command that opens something - both are stripped before the
## comparison, because neither is a difference a reader would notice.
##
## The names are read out of `menu_plan()` rather than listed here, so a menu added to the bar (or
## renamed) is followed by this test rather than by a second table of menu names to keep in step.
func test_every_menu_entry_the_manual_names_is_one_the_bar_has() -> void:
	var by_menu := _menu_names_by_menu()
	var titles: Array[String] = []
	for menu: Dictionary in HudScript.menu_plan():
		titles.append(String(menu["title"]))
	var re := RegEx.new()
	assert(
		re.compile("\\b(%s) > " % "|".join(titles)) == OK,
		"the menu names make a pattern to look for"
	)
	var checked := 0
	for topic: Dictionary in HelpDocScript.topics():
		var body := String(topic["body"])
		for hit: RegExMatch in re.search_all(body):
			var menu_text := hit.get_string(1)
			var after := hit.get_end()
			var window := body.substr(after, 60)
			checked += 1
			assert(
				_starts_with_an_entry(window, by_menu[menu_text]),
				"%s is a menu with such an entry: %s writes \"%s...\"" % [
					menu_text, String(topic["title"]), window.strip_edges(),
				]
			)
	# Teeth: a pattern that stopped matching would otherwise pass in silence. The manual makes far
	# more than a handful of menu references, so a floor well under the real count is safe.
	assert(checked >= 40, "the guard found the menu references the manual makes, not none: %d" % checked)


## The counts the prose states, held against the tables they describe.
##
## This is the drift that has already happened twice by hand - "the nine tools" once the angular
## dimension made ten, "Six commands" once move and copy made eight. A stated number is the part of
## prose most likely to go quietly stale, because a table growing by one changes no word around it.
##
## Each number is a word in the body ("the four dimension commands are annotations"), so it is looked
## for as a word, bounded like every other word here - "eight" is satisfied by nothing but "eight",
## not by "weight" or "eighteen".
func test_the_counts_the_manual_states_match_the_tables_they_describe() -> void:
	var drawing := _body_under("drawing:")
	var dimensions := _dimension_tool_count()
	assert(dimensions >= 1, "there are dimension tools to count")
	assert(
		_has_word(drawing, _count_word(dimensions)),
		"the manual says how many dimension commands there are: with %d of them it should read \"%s\""
		% [dimensions, _count_word(dimensions)]
	)

	var editing := _body_under("editing shapes")
	var edits: int = HudScript.EDIT_TOOLS.size()
	assert(
		_has_word(editing, _count_word(edits)),
		"the manual says how many editing commands there are: with %d of them it should read \"%s\""
		% [edits, _count_word(edits)]
	)

	var plants := _body_under("plants")
	var shapes: int = PlantSymbolsScript.NAMES.size()
	assert(shapes >= 1, "there are plant symbols to count")
	assert(
		_has_word(plants, _count_word(shapes)),
		"the manual says how many plant symbol shapes there are: with %d of them it should read \"%s\""
		% [shapes, _count_word(shapes)]
	)

	var said := _body_under("what the drawing has said")
	var kept: int = StatusHistoryScript.CAP
	assert(
		_has_word(said, _count_word(kept)),
		"the manual says how many answers the status history keeps: with %d it should read \"%s\""
		% [kept, _count_word(kept)]
	)


## The word for a count, in the form the prose writes one. Empty past the range a manual sentence
## uses, which is an assertion failure naming an empty word rather than a wrong one.
func _count_word(count: int) -> String:
	if count >= 0 and count < NUMBER_WORDS.size():
		return NUMBER_WORDS[count]
	if count >= 30 and count <= 90 and count % 10 == 0:
		return TENS_WORDS[count / 10]
	return ""


## Every menu entry the bar has, keyed by the menu it sits under, each as the name the manual is
## allowed to use: an entry's label with the explanation a colon introduces and the ellipsis of a
## command that opens something taken off the end.
func _menu_names_by_menu() -> Dictionary:
	var out := {}
	for entry: Dictionary in HudScript.menu_entries():
		var menu_text := String(entry.get("menu", ""))
		if not out.has(menu_text):
			out[menu_text] = []
		var entry_name := _entry_name(String(entry.get("label", "")))
		if entry_name != "":
			out[menu_text].append(entry_name)
	return out


func _entry_name(label: String) -> String:
	var name := label.strip_edges()
	var colon := name.find(":")
	if colon >= 0:
		name = name.substr(0, colon)
	# A label may also explain itself with a dash - "Quality - sharper shadows" - which the manual
	# names by its first word alone.
	for dash in [" - ", " \u2014 "]:
		var at := name.find(dash)
		if at >= 0:
			name = name.substr(0, at)
	name = name.replace("...", "")
	return name.strip_edges().to_lower()


## Whether the text following a "Menu > " begins one of that menu's entry names.
func _starts_with_an_entry(text: String, names) -> bool:
	var lowered := text.strip_edges().to_lower()
	for name: String in names:
		if name != "" and lowered.begins_with(name):
			return true
	return false


## The number of drawing tools that are a dimension command, so the manual's "the four dimension
## commands" is checked against the table rather than against a number written here.
func _dimension_tool_count() -> int:
	var count := 0
	for pair: Array in HudScript.DRAFTING_TOOLS:
		if String(pair[0]).contains("dimension"):
			count += 1
	return count


## The numbers a sentence is written with, up to the range this manual uses.
const NUMBER_WORDS: Array[String] = [
	"zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
	"eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen",
	"nineteen", "twenty",
]
const TENS_WORDS: Array[String] = [
	"", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety",
]