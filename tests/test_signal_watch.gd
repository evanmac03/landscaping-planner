extends Node
## The suite's named signal assertion.
##
## A small talker stands in for a page: it carries a signal that says a word, one that carries nothing,
## and one that carries three things. What is held down here is which firings the watch counted, what
## it kept of them, that two signals watched together do not run into each other, and that stopping
## lets go. The half that *fails* a test is the runner's to prove.

const WatchScript := preload("res://tests/support/signal_watch.gd")


class Talker:
	extends RefCounted

	signal said(word)
	signal nothing()
	signal triple(a, b, c)

	func say(word: String) -> void:
		said.emit(word)

	func say_nothing() -> void:
		nothing.emit()

	func say_three(a: int, b: int, c: int) -> void:
		triple.emit(a, b, c)


func test_a_signal_heard_once_is_heard_once() -> void:
	var talker := Talker.new()
	var watch := WatchScript.new(talker, ["said"])
	talker.say("hello")
	watch.expect_once(&"said")


func test_a_signal_that_never_fired_is_heard_never() -> void:
	var talker := Talker.new()
	var watch := WatchScript.new(talker, ["said"])
	watch.expect_never(&"said")


func test_two_firings_are_two_and_not_one() -> void:
	var talker := Talker.new()
	var watch := WatchScript.new(talker, ["said"])
	talker.say("one")
	talker.say("two")
	assert(watch.count(&"said") == 2, "two words were said")
	watch.expect_count(&"said", 2)


func test_a_firing_is_kept_with_the_word_it_carried() -> void:
	var talker := Talker.new()
	var watch := WatchScript.new(talker, ["said"])
	talker.say("hello")
	assert(watch.arguments_of(&"said") == ["hello"], "the word said is kept")


func test_a_signal_that_carries_nothing_is_heard_with_nothing() -> void:
	var talker := Talker.new()
	var watch := WatchScript.new(talker, ["nothing"])
	talker.say_nothing()
	watch.expect_once(&"nothing")
	assert(watch.arguments_of(&"nothing").is_empty(), "nothing was carried")


func test_a_signal_that_carries_three_things_keeps_all_of_them() -> void:
	var talker := Talker.new()
	var watch := WatchScript.new(talker, ["triple"])
	talker.say_three(1, 2, 3)
	assert(watch.arguments_of(&"triple") == [1, 2, 3], "all three are kept")


func test_two_signals_watched_together_do_not_run_into_each_other() -> void:
	var talker := Talker.new()
	var watch := WatchScript.new(talker, ["said", "nothing"])
	talker.say("hi")
	talker.say_nothing()
	watch.expect_once(&"said")
	watch.expect_once(&"nothing")


func test_the_last_firing_is_the_one_the_arguments_are_read_from() -> void:
	var talker := Talker.new()
	var watch := WatchScript.new(talker, ["said"])
	talker.say("first")
	talker.say("second")
	assert(watch.arguments_of(&"said") == ["second"], "the most recent word is the one kept")


func test_stopping_lets_go_of_the_signal() -> void:
	var talker := Talker.new()
	var watch := WatchScript.new(talker, ["said"])
	talker.say("one")
	watch.stop()
	talker.say("two")
	assert(watch.count(&"said") == 1, "nothing was heard after stopping")


func test_a_signal_that_was_never_watched_counts_nothing() -> void:
	var talker := Talker.new()
	var watch := WatchScript.new(talker, ["said"])
	talker.say_nothing()
	assert(watch.count(&"nothing") == 0, "a signal nobody watched is not counted")