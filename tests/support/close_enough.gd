extends RefCounted
## The suite's named float comparison: how close two doubles must be, said once.
##
## A test that compares numbers writes the arithmetic out by hand today - `assert(absf(got - want) <
## 1e-9, ...)` - which is correct but says nothing about why the two numbers may differ at all, and
## invites a slack written loose enough to hide a real fault. `almost` is that comparison, named, with
## the quantity and the slack it allows both stated where the test reads.
##
## `within` is the arithmetic on its own, so the rule can be tested with no assertion and no scene.
## `almost` is the assertion built on it, and a comparison that does not hold raises the same script
## error a bare `assert()` does - which is exactly what the runner counts as a failure, so nothing
## about the verdict changes.
##
## A `Vector2` keeps using Godot's own `is_equal_approx`: one way to ask a question is this project's
## rule, and that built-in is the way for a point.

## How close two doubles must be unless a test says otherwise. The model is metres as a double, so a
## micrometre of drift is never a defect, while a figure that has moved further than this is a fault.
const CLOSE := 1e-6


## Whether two numbers agree to within `by`. Two infinities of the same sign are equal; a NaN is
## within nothing, itself included, because no arithmetic makes it so.
static func within(got: float, want: float, by: float = CLOSE) -> bool:
	return got == want or absf(got - want) <= by


## Hold the test to `got` agreeing with `want` to within `by`. `what` names the quantity, so a failure
## reads as the sentence a person would say rather than as two bare numbers.
static func almost(got: float, want: float, by: float = CLOSE, what: String = "") -> void:
	# The words are built only when there is something to say. Godot works out an `assert`'s message
	# whether or not it holds, so a fault in the message would otherwise fail a test that passed.
	if not within(got, want, by):
		assert(false, _missed(got, want, by, what))


static func _missed(got: float, want: float, by: float, what: String) -> String:
	# `%s` and not `%g`: GDScript's `%` has no `%g`, and a float read as a string is the shortest form
	# that round-trips, which is what a person wants to see anyway.
	var sentence := "%s is not %s to within %s" % [got, want, by]
	if what.is_empty():
		return sentence
	return "%s: %s" % [what, sentence]