class_name Contrast
extends RefCounted
## Whether words can be read against the colour behind them, which is the one thing about a caption no
## rectangle can show.
##
## The measure is the one a person's eye actually has: each channel is turned into light first - because half a
## step in a byte is not half the brightness to the eye - and then the two lights are compared. White on black
## is 21 to 1 and a colour on itself is 1 to 1. Four and a half is the least a body of text should have, and
## three the least a large heading may get away with.
##
## Only a pair where BOTH colours are known is judged. A caption drawn over the plan has no paper a program can
## read, because the paper is whatever the drawing happens to be beneath it, and inventing one would be
## inventing a fault. A see-through ink is left alone for the same reason: its real paper is the one it gets
## composited against, which is a question for the glass and not for these numbers.

## The least ratio a line of body text should have, and the least a heading may have.
const LEAST := 4.5
const LEAST_LARGE := 3.0


## How bright a colour is to the eye, between black at 0 and white at 1.
static func luminance(colour: Color) -> float:
	return 0.2126 * _light(colour.r) + 0.7152 * _light(colour.g) + 0.0722 * _light(colour.b)


## How far apart two colours are to the eye: 1 between a colour and itself, 21 between black and white.
static func ratio(ink: Color, paper: Color) -> float:
	var lighter := maxf(luminance(ink), luminance(paper))
	var darker := minf(luminance(ink), luminance(paper))
	return (lighter + 0.05) / (darker + 0.05)


## Every pair whose words a person could not read, each `{ "name", "ink", "paper", "ratio", "least" }`.
##
## An item that has no ink or no paper of its own, or an ink that is see-through, is left out rather than
## guessed at: `{ "name", "ink", "paper" }`.
static func faults(items: Array, least: float = LEAST) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for item: Dictionary in items:
		var ink: Variant = item.get("ink")
		var paper: Variant = item.get("paper")
		if not (ink is Color) or not (paper is Color):
			continue
		var ink_colour := ink as Color
		var paper_colour := paper as Color
		if ink_colour.a < 1.0 or paper_colour.a < 1.0:
			continue
		var here := ratio(ink_colour, paper_colour)
		if here >= least:
			continue
		found.append(
			{
				"name": String(item.get("name", "a caption")),
				"ink": ink_colour,
				"paper": paper_colour,
				"ratio": here,
				"least": least,
			}
		)
	return found


## The pair a person would want to fix first, which is the one that is hardest to read.
static func worst(found: Array) -> Dictionary:
	var lowest: Dictionary = { }
	for fault: Dictionary in found:
		if lowest.is_empty() or float(fault["ratio"]) < float(lowest["ratio"]):
			lowest = fault
	return lowest


## One pair as a person reads it, with both colours spelled out the way they would be typed.
static func sentence(fault: Dictionary) -> String:
	var ink := fault["ink"] as Color
	var paper := fault["paper"] as Color
	return (
		"%s is #%s on #%s, a ratio of %.2f where %.1f is wanted"
		% [fault["name"], ink.to_html(false), paper.to_html(false), fault["ratio"], fault["least"]]
	)


## One channel as light rather than as a number - the curve the eye is said to have, so that a mid grey is not
## read as half of white.
static func _light(channel: float) -> float:
	if channel <= 0.04045:
		return channel / 12.92
	return pow((channel + 0.055) / 1.055, 2.4)
