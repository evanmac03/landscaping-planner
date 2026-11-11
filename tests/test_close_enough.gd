extends Node
## The suite's named float comparison.
##
## The helper's rule is pure arithmetic on a `RefCounted`, so it is held down here with no assertion of
## its own in the way: what counts as within, what does not, and the one slack it starts from. The
## half that *fails* a test is the runner's to prove, since calling the helper wrongly here would fail
## this file rather than test it.

const CloseEnough := preload("res://tests/support/close_enough.gd")


func test_a_number_is_within_itself_with_no_slack_at_all() -> void:
	assert(CloseEnough.within(1.8, 1.8, 0.0), "a number equals itself")


func test_a_difference_at_the_edge_of_the_slack_still_counts_as_within() -> void:
	assert(CloseEnough.within(1.0, 1.001, 0.001), "the edge is inside")


func test_a_difference_past_the_slack_does_not_count_as_within() -> void:
	assert(not CloseEnough.within(1.0, 1.002, 0.001), "a hair past the edge is outside")


func test_the_same_infinity_is_within_itself_and_a_nan_is_within_nothing() -> void:
	assert(CloseEnough.within(INF, INF, 0.0), "an infinity equals the same infinity")
	assert(not CloseEnough.within(NAN, NAN, 1.0), "a nan is within nothing, itself included")


func test_the_slack_a_test_starts_from_is_a_micrometre_not_a_metre() -> void:
	assert(CloseEnough.CLOSE == 1e-6, "the default slack is stated once")


func test_the_drift_a_real_figure_shows_is_never_a_fault() -> void:
	assert(CloseEnough.within(1.8, 1.8 + 1e-9), "nine tenths of a nanometre is not a defect")


func test_almost_holds_for_two_numbers_that_agree() -> void:
	CloseEnough.almost(1.8, 1.8 + 5e-7, CloseEnough.CLOSE, "the takeoff figure")