extends Node
## Escape on a page that lives in a `Window`.
##
## A `Window` takes the keyboard into its own viewport, so the key can only be answered from inside the
## page - measured live in `tools/page_escape_demo.gd`, which is also where "every page the HUD holds
## has one" is checked against the scene the program really builds. What is tested here is the rule the
## closer applies, which is the half that can be wrong.
##
## The page is never shown: handling the key ends in `get_viewport().set_input_as_handled()`, and an
## off-tree page has no viewport to hand it to.

const PageEscapeScript := preload("res://scripts/page_escape.gd")


func _escape() -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.physical_keycode = KEY_ESCAPE
	event.pressed = true
	return event


func _another_key() -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = KEY_Q
	event.physical_keycode = KEY_Q
	event.pressed = true
	return event


func test_escape_is_the_key_and_no_other_is() -> void:
	var page := Window.new()
	page.visible = true
	var closer := PageEscapeScript.attach(page)
	assert(closer != null, "a page is given a closer")
	assert(closer.answers(_escape()), "the key it is for is answered")
	assert(not closer.answers(_another_key()), "and nothing else is")
	page.free()


func test_a_page_that_is_not_up_answers_nothing() -> void:
	# A page that is built but not shown is not a page: the key belongs to whatever is in front.
	var page := Window.new()
	var closer := PageEscapeScript.attach(page)
	page.visible = false
	assert(not closer.answers(_escape()), "a page that is away answers nothing")
	page.visible = true
	assert(closer.answers(_escape()), "and one that is up does")
	page.free()


func test_a_closer_with_no_page_answers_nothing() -> void:
	# The reachable case: the closer is made before the page is known, or the page has been freed under
	# it. Either way the key is not this node's to take.
	var closer := PageEscapeScript.new()
	assert(not closer.answers(_escape()), "no page, no answer")
	var page := Window.new()
	closer.page = page
	page.free()
	assert(not closer.answers(_escape()), "and a page that has gone is not a page either")
	closer.free()


func test_a_page_is_given_one_closer_and_only_one() -> void:
	# A page is opened and closed many times. Two nodes listening for one key would close it twice.
	var page := Window.new()
	var first := PageEscapeScript.attach(page)
	assert(first != null, "the first attach makes one")
	assert(PageEscapeScript.attach(page) == null, "the second does nothing")
	assert(page.get_child_count() == 1, "and the page holds exactly one")
	assert(String(first.name) == "PageEscape", "named so the second attach can find it")
	page.free()


func test_a_page_that_is_not_a_page_is_not_given_one() -> void:
	assert(PageEscapeScript.attach(null) == null, "there is nothing to put a closer inside")