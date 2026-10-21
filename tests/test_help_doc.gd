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
	assert(HelpDocScript.find_in(all, "zzzznotaword").is_empty(), "no topic mentions it")
	assert(HelpDocScript.find("zzzznotaword").is_empty(), "and the same over the manual itself")
	assert(HelpDocScript.find_in(all, "   ").size() == all.size(), "spaces are just an empty search")


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