extends Node
## The manual's page table, held to the manual and to the pages that actually exist.
##
## Three tables say what a page is and where a person reads about it, and they are written in three
## files: `PageIndex` finds the pages, `PageHelp` says which subject answers which page, `HelpDoc` holds
## the subjects. Each is useless on its own, so this is where they are laid against each other - the one
## test that would notice a page added without anywhere to read about it.

const PageIndexScript := preload("res://scripts/page_index.gd")
const PageHelpScript := preload("res://scripts/page_help.gd")
const HelpDocScript := preload("res://scripts/help_doc.gd")


func test_every_page_points_at_a_subject_the_manual_actually_has() -> void:
	# A subject named slightly wrong - "Food: what will crop" for "Food: what will crop here" - is a door
	# that opens onto nothing, and nothing else here would catch it: the manual would still have every
	# subject, and the page would still look like it had somewhere to go.
	var subjects: Array[String] = HelpDocScript.SUBJECTS
	for page: String in PageHelpScript.SUBJECT_OF:
		var subject: String = PageHelpScript.subject_for(page)
		assert(subjects.has(subject),
			"%s points at \"%s\", which the manual does not have" % [page, subject])


func test_every_page_of_the_project_is_accounted_for() -> void:
	# The rule that keeps this table from falling behind: a page added tomorrow is either given a subject,
	# or named as one that needs none, or named as one the manual has not reached. Silence is not one of
	# the three, so a new page cannot slip through unmapped.
	var unaccounted: Array[String] = []
	for path: String in PageIndexScript.scripts():
		var page: String = PageIndexScript.page_name(path)
		if PageHelpScript.SUBJECT_OF.has(page):
			continue
		if PageHelpScript.WITHOUT_NEED.has(page) or PageHelpScript.NOT_YET_WRITTEN.has(page):
			continue
		unaccounted.append(page)
	assert(unaccounted.is_empty(),
		"these pages are in none of the three lists: %s" % ", ".join(unaccounted))


func test_a_page_that_needs_no_subject_is_a_page_that_exists() -> void:
	var known: Array[String] = []
	for path: String in PageIndexScript.scripts():
		known.append(PageIndexScript.page_name(path))
	for page: String in PageHelpScript.WITHOUT_NEED:
		assert(known.has(page), "%s is in neither the pages nor the manual: it is not a page" % page)
	for page: String in PageHelpScript.NOT_YET_WRITTEN:
		assert(known.has(page), "%s is named as a page the manual has not reached, but is not a page" % page)


func test_a_page_with_no_need_of_a_subject_is_not_also_missing_one() -> void:
	# The two lists are different claims and a page cannot be both: "this needs none" and "this needs one
	# and has not got it" are answers that contradict each other.
	for page: String in PageHelpScript.WITHOUT_NEED:
		assert(not PageHelpScript.SUBJECT_OF.has(page),
			"%s is mapped to a subject and also has no need of one" % page)
		assert(not PageHelpScript.NOT_YET_WRITTEN.has(page),
			"%s cannot both need no subject and be missing one" % page)


func test_a_page_the_manual_has_not_reached_says_what_it_is_about() -> void:
	# Each of these is a gap somebody has to close, and the entry is what tells them what is missing:
	# a page named with no reason is a page nobody can pick up.
	for page: String in PageHelpScript.NOT_YET_WRITTEN:
		var why: String = String(PageHelpScript.NOT_YET_WRITTEN[page])
		assert(not why.is_empty(), "%s is listed as undocumented and says nothing about it" % page)


func test_the_shared_show_asks_the_manual_the_same_question_this_table_answers() -> void:
	# The name a page is keyed by comes from the index and is the name the layout check reports; a page
	# renamed to `x_window2` would be a row here that matches nothing.
	for page: String in PageHelpScript.SUBJECT_OF:
		assert(page.ends_with("_window") or page == "command_palette" or page == "pipeline_board"
			or page == "schedule_board", "%s does not look like a page's script name" % page)