extends Node
## The vocabulary tool: **the names themselves, and the module each comes from.**
##
## Nothing here needs a scene except the menus, and those are read off a bar that is standing - which no test
## builds, so that section is held by running the tool and reading its answer. What can be held without a scene is
## held: the pages come from `PageIndex`, the tools from `DraftTool`'s one table, and a section with nothing to say
## says so rather than answering with an empty list.

const VocabularyScript := preload("res://tools/vocabulary.gd")
const PageIndexScript := preload("res://scripts/page_index.gd")
const DraftToolScript := preload("res://scripts/draft/draft_tool.gd")
const HudScript := preload("res://scripts/hud.gd")


## **Every page the program has is named, under the name the program reports it by** - and the list is
## `PageIndex`'s own rather than a walk of this tool's, which is the rule every one of these instruments follows.
func test_the_pages_section_is_the_page_index_its_own_list() -> void:
	var pages: Array[String] = PageIndexScript.scripts()
	assert(not pages.is_empty(), "there are pages to name at all")
	var said: String = "\n".join(VocabularyScript.page_lines())
	for path: String in pages:
		assert(said.contains(PageIndexScript.page_name(path)), "every page is named: %s" % path)


## **The tools are `DraftTool`'s own table** - its wording and the action it is bound to - so a tool cannot be
## described here as something it is not.
func test_the_tools_section_is_the_tools_own_table() -> void:
	var said: String = "\n".join(VocabularyScript.tool_lines())
	for one: Array in DraftToolScript.DRAFTING_TOOLS:
		assert(said.contains(String(one[1])), "every tool's own wording is in it: %s" % String(one[1]))
		assert(said.contains(String(one[0])), "with the action that selects it: %s" % String(one[0]))


## The keys are **the HUD's own rows**, which is the same list the Keys reference page shows.
func test_the_keys_section_is_the_huds_own_rows() -> void:
	var said: String = "\n".join(VocabularyScript.key_lines())
	for row: String in HudScript.drafting_rows():
		assert(said.contains(row), "every row the reference shows is in it: %s" % row)


## A section with nothing to say **says so** rather than printing an empty list: a list that answered with nothing
## reads exactly like one that had been forgotten.
func test_a_section_with_nothing_to_name_says_so_rather_than_saying_nothing() -> void:
	var layers: String = "\n".join(VocabularyScript.layer_lines(null))
	assert(layers.contains("no drawing is open"), layers)
	var menus: String = "\n".join(VocabularyScript.menu_lines(null))
	assert(menus.contains("no menu bar is standing"), menus)


## **The one vocabulary nothing owns is said to be unowned**, with where to read it instead - a vocabulary that
## quietly left the probe's line kinds out would read as if there were none.
func test_the_line_kinds_no_module_owns_are_said_to_be_unowned() -> void:
	var said: String = "\n".join(VocabularyScript.no_list_lines())
	assert(said.contains("probe"), said)
	assert(said.contains(":probe"), "and where to read them instead: " + said)
	assert(said.contains("--block"), "on a device as well as on the desk: " + said)
