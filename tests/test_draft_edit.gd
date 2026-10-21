extends Node
## Tests for the editing operations on existing geometry: offset, trim, extend and
## fillet. Pure functions on entities, so no scene is needed.

const Edit := preload("res://scripts/draft/draft_edit.gd")
const Entity := preload("res://scripts/draft/draft_entity.gd")
const Geom := preload("res://scripts/draft/geom2d.gd")


func _near(a: Vector2, b: Vector2, tolerance := 0.001) -> bool:
	return a.distance_to(b) <= tolerance


# --- offset -------------------------------------------------------------------------


func test_a_line_offsets_to_the_left_of_its_direction() -> void:
	var line := Entity.make_line(Vector2(0, 0), Vector2(10, 0))
	var result := Edit.offset(line, 0.5)
	assert(result["ok"], "a line offsets")
	assert(result["entities"].size() == 1)
	var offset_line = result["entities"][0]
	# Travelling +x, the left is +y.
	assert(_near(offset_line.point(0), Vector2(0, 0.5)), "the start moved left")
	assert(_near(offset_line.point(1), Vector2(10, 0.5)), "and so did the end")
	assert(is_equal_approx(offset_line.length(), 10.0), "and it is the same length")


func test_a_circle_offsets_by_its_radius() -> void:
	var circle := Entity.make_circle(Vector2(0, 0), 2.0)
	var grown = Edit.offset(circle, 0.5)["entities"][0]
	assert(is_equal_approx(grown.params[2], 2.5), "outward grows the radius")
	var shrunk = Edit.offset(circle, -0.5)["entities"][0]
	assert(is_equal_approx(shrunk.params[2], 1.5), "inward shrinks it")


func test_an_inward_offset_past_the_radius_produces_nothing() -> void:
	var circle := Entity.make_circle(Vector2(0, 0), 2.0)
	var result := Edit.offset(circle, -3.0)
	assert(result["ok"], "it is not an error")
	assert(result["entities"].is_empty(), "it is simply nothing left")


func test_an_arc_offsets_about_the_same_centre() -> void:
	var arc := Entity.make_arc(Vector2(0, 0), 2.0, 0.0, PI * 0.5)
	var offset_arc = Edit.offset(arc, 0.5)["entities"][0]
	assert(is_equal_approx(offset_arc.params[2], 2.5), "the radius grew")
	assert(is_equal_approx(offset_arc.params[3], 0.0), "the start angle did not move")
	assert(is_equal_approx(offset_arc.params[4], PI * 0.5), "nor did the sweep")


func test_a_closed_outline_offsets_outward_and_inward() -> void:
	var square := Entity.make_polyline(
		PackedVector2Array([Vector2(0, 0), Vector2(4, 0), Vector2(4, 4), Vector2(0, 4)]), true
	)
	var bigger = Edit.offset(square, 0.5)["entities"][0]
	assert(bigger.area() > 16.0, "outward is a bigger area")
	var smaller = Edit.offset(square, -0.5)["entities"][0]
	assert(is_equal_approx(smaller.area(), 9.0), "an inset square of side 4 by 0.5 is 3 x 3")


func test_an_open_polyline_offsets_with_mitered_joins() -> void:
	var path := Entity.make_polyline(
		PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10)]), false
	)
	var offset_path = Edit.offset(path, 0.5)["entities"][0]
	var points: PackedVector2Array = offset_path.points()
	assert(points.size() == 3, "three points in, three out")
	assert(_near(points[0], Vector2(0, 0.5)), "the first point sits to the left")
	assert(_near(points[1], Vector2(9.5, 0.5)), "the join miters to the corner")
	assert(_near(points[2], Vector2(9.5, 10)), "and the last point too")


func test_an_offset_of_nothing_is_refused() -> void:
	var line := Entity.make_line(Vector2(0, 0), Vector2(10, 0))
	assert(not Edit.offset(line, 0.0)["ok"], "zero is not a distance to offset by")
	assert(not Edit.offset(null, 0.5)["ok"], "and there has to be a shape")


func test_the_pick_chooses_the_side_of_a_line() -> void:
	var line := Entity.make_line(Vector2(0, 0), Vector2(10, 0))
	assert(Edit.offset_sign(line, Vector2(5, 1)) > 0.0, "a pick to the left is positive")
	assert(Edit.offset_sign(line, Vector2(5, -1)) < 0.0, "a pick to the right is negative")


func test_the_pick_is_inside_or_outside_a_closed_shape() -> void:
	var circle := Entity.make_circle(Vector2(0, 0), 2.0)
	assert(Edit.offset_sign(circle, Vector2(0, 3)) > 0.0, "outside the circle offsets outward")
	assert(Edit.offset_sign(circle, Vector2(0, 1)) < 0.0, "inside offsets inward")
	var square := Entity.make_rectangle(Vector2(0, 0), Vector2(4, 4))
	assert(Edit.offset_sign(square, Vector2(3, 3)) > 0.0, "outside the square is positive")


# --- trim ---------------------------------------------------------------------------


func test_trimming_a_line_removes_the_piece_that_was_picked() -> void:
	var line := Entity.make_line(Vector2(0, 0), Vector2(10, 0))
	var cutter := Entity.make_line(Vector2(5, -1), Vector2(5, 1))
	var result := Edit.trim(line, Vector2(7, 0), [cutter])
	assert(result["ok"], "the line trims")
	assert(result["entities"].size() == 1, "one piece is left")
	var kept = result["entities"][0]
	assert(_near(kept.point(0), Vector2(0, 0)), "the far end is untouched")
	assert(_near(kept.point(1), Vector2(5, 0)), "and it stops at the cut")


func test_trimming_picks_the_cut_side() -> void:
	var line := Entity.make_line(Vector2(0, 0), Vector2(10, 0))
	var cutter := Entity.make_line(Vector2(5, -1), Vector2(5, 1))
	var kept = Edit.trim(line, Vector2(2, 0), [cutter])["entities"][0]
	assert(_near(kept.point(0), Vector2(5, 0)), "the kept piece starts at the cut")
	assert(_near(kept.point(1), Vector2(10, 0)), "and ends at the far end")


func test_trimming_between_two_cuts_leaves_two_lines() -> void:
	var line := Entity.make_line(Vector2(0, 0), Vector2(10, 0))
	var left := Entity.make_line(Vector2(3, -1), Vector2(3, 1))
	var right := Entity.make_line(Vector2(7, -1), Vector2(7, 1))
	var result := Edit.trim(line, Vector2(5, 0), [left, right])
	assert(result["entities"].size() == 2, "the middle went and both ends stayed")
	assert(_near(result["entities"][0].point(1), Vector2(3, 0)), "the left piece stops at 3")
	assert(_near(result["entities"][1].point(0), Vector2(7, 0)), "the right piece starts at 7")


func test_trimming_with_nothing_crossing_says_so() -> void:
	var line := Entity.make_line(Vector2(0, 0), Vector2(10, 0))
	var cutter := Entity.make_line(Vector2(3, 2), Vector2(7, 2))
	var result := Edit.trim(line, Vector2(5, 0), [cutter])
	assert(not result["ok"], "a cutter that never crosses trims nothing")
	assert(result["reason"].contains("crosses"), "and says why")
	assert(not Edit.trim(line, Vector2(5, 0), [])["ok"], "and no cutter at all is also nothing")


func test_trim_refuses_a_shape_that_is_not_a_line() -> void:
	var circle := Entity.make_circle(Vector2(0, 0), 2.0)
	assert(not Edit.trim(circle, Vector2(2, 0), [])["ok"], "trim works on a line")


# --- extend -------------------------------------------------------------------------


func test_extending_a_line_reaches_the_boundary_it_was_pointed_at() -> void:
	var line := Entity.make_line(Vector2(0, 0), Vector2(5, 0))
	var wall := Entity.make_line(Vector2(10, -1), Vector2(10, 1))
	# The pick is near the second end, so that is the end that grows.
	var result := Edit.extend(line, Vector2(4.9, 0), [wall])
	assert(result["ok"], "the line extends")
	var grown = result["entities"][0]
	assert(_near(grown.point(0), Vector2(0, 0)), "the anchored end did not move")
	assert(_near(grown.point(1), Vector2(10, 0)), "and it reached the wall")


func test_extending_grows_the_end_the_pick_is_nearest() -> void:
	var line := Entity.make_line(Vector2(0, 0), Vector2(5, 0))
	var wall := Entity.make_line(Vector2(-10, -1), Vector2(-10, 1))
	var grown = Edit.extend(line, Vector2(0.1, 0), [wall])["entities"][0]
	assert(_near(grown.point(0), Vector2(5, 0)), "the far end is now the anchor")
	assert(_near(grown.point(1), Vector2(-10, 0)), "and the near end grew backwards to the wall")


func test_extending_with_nothing_in_the_way_says_so() -> void:
	var line := Entity.make_line(Vector2(0, 0), Vector2(5, 0))
	var wall := Entity.make_line(Vector2(-10, -1), Vector2(-10, 1))
	var result := Edit.extend(line, Vector2(4.9, 0), [wall])
	assert(not result["ok"], "there is nothing beyond the far end")
	assert(result["reason"].contains("beyond"), "and it says so")


# --- fillet -------------------------------------------------------------------------


func test_a_fillet_rounds_a_right_angle() -> void:
	var a := Entity.make_line(Vector2(0, 0), Vector2(10, 0))
	var b := Entity.make_line(Vector2(0, 0), Vector2(0, 10))
	var result := Edit.fillet(a, b, 1.0, Vector2(5, 0), Vector2(0, 5))
	assert(result["ok"], "the corner rounds")
	var arc = result["arc"]
	assert(_near(Vector2(arc.params[0], arc.params[1]), Vector2(1, 1)), "the arc is centred one unit in")
	assert(is_equal_approx(arc.params[2], 1.0), "at the radius asked for")
	assert(is_equal_approx(absf(arc.params[4]), PI * 0.5), "and it is a quarter turn")


func test_a_fillet_trims_both_lines_to_their_tangent_points() -> void:
	var a := Entity.make_line(Vector2(0, 0), Vector2(10, 0))
	var b := Entity.make_line(Vector2(0, 0), Vector2(0, 10))
	var lines: Array = Edit.fillet(a, b, 1.0, Vector2(5, 0), Vector2(0, 5))["lines"]
	assert(lines.size() == 2, "two lines come back")
	assert(_near(lines[0].point(0), Vector2(10, 0)), "the first keeps its far end")
	assert(_near(lines[0].point(1), Vector2(1, 0)), "and stops at the tangent point")
	assert(_near(lines[1].point(0), Vector2(0, 10)), "the second keeps its far end")
	assert(_near(lines[1].point(1), Vector2(0, 1)), "and stops at its tangent point")


func test_the_picks_choose_which_wedge_is_rounded() -> void:
	var a := Entity.make_line(Vector2(-10, 0), Vector2(10, 0))
	var b := Entity.make_line(Vector2(0, -10), Vector2(0, 10))
	var below := Edit.fillet(a, b, 1.0, Vector2(5, 0), Vector2(0, -5))
	var arc = below["arc"]
	assert(_near(Vector2(arc.params[0], arc.params[1]), Vector2(1, -1)), "the arc sits in the picked wedge")


func test_a_fillet_needs_a_corner_and_a_radius() -> void:
	var a := Entity.make_line(Vector2(0, 0), Vector2(10, 0))
	var b := Entity.make_line(Vector2(0, 5), Vector2(10, 5))
	var parallel := Edit.fillet(a, b, 1.0, Vector2(2, 0), Vector2(2, 5))
	assert(not parallel["ok"], "parallel lines have no corner")
	assert(parallel["reason"].contains("parallel"), "and the reason says so")
	assert(not Edit.fillet(a, b, 0.0, Vector2(2, 0), Vector2(2, 5))["ok"], "a fillet needs a radius")


func test_a_fillet_refuses_a_pick_on_the_corner() -> void:
	var a := Entity.make_line(Vector2(0, 0), Vector2(10, 0))
	var b := Entity.make_line(Vector2(0, 0), Vector2(0, 10))
	# A pick exactly at the corner leaves the kept half undecided.
	var result := Edit.fillet(a, b, 1.0, Vector2(0, 0), Vector2(0, 5))
	assert(not result["ok"], "an ambiguous pick is refused rather than guessed")


# --- rotate -------------------------------------------------------------------------


## A turn hands back a copy, for the reason the whole module gives: editing is a replacement, and the
## caller decides how the replacement is recorded. So the shape it was asked about must be untouched.
func test_a_turn_hands_back_a_copy_and_leaves_the_original_alone() -> void:
	var line := Entity.make_line(Vector2(0, 0), Vector2(10, 0))
	var result := Edit.rotate(line, Vector2(0, 0), PI * 0.5)
	assert(result["ok"], "a line turns")
	assert(result["entities"].size() == 1, "into one shape")
	var turned = result["entities"][0]
	assert(turned != line, "it is a copy")
	assert(_near(line.point(0), Vector2(0, 0)), "the original did not move")
	assert(_near(line.point(1), Vector2(10, 0)), "either end")
	assert(_near(turned.point(0), Vector2(0, 0)), "the copy turned about the pivot it was given")
	assert(_near(turned.point(1), Vector2(0, 10)), "a quarter turn takes +x to +y")


## The angle is read the way the third click is read - from +X toward +Y - so a caller can hand over
## the bearing of a point and mean it. A whole turn is a turn, and it is not refused for being large.
func test_the_angle_is_a_bearing_from_the_positive_x_axis() -> void:
	var line := Entity.make_line(Vector2(1, 0), Vector2(2, 0))
	var pivot := Vector2(0, 0)
	# A point clicked due +y is a quarter turn; one clicked due -y is three quarters.
	var quarter = Edit.rotate(line, pivot, Vector2(0, 5).angle())["entities"][0]
	assert(_near(quarter.point(1), Vector2(0, 2)), "a click due north is a quarter turn")
	var three_quarters = Edit.rotate(line, pivot, Vector2(0, -5).angle())["entities"][0]
	assert(_near(three_quarters.point(1), Vector2(0, -2)), "a click due south is three quarters")


## A gesture that did nothing is refused rather than recorded, the way a zero offset is. Otherwise a
## turn of nothing would land on the undo stack as a step that changes nothing.
func test_turning_by_nothing_is_refused() -> void:
	var line := Entity.make_line(Vector2(0, 0), Vector2(10, 0))
	var still := Edit.rotate(line, Vector2(5, 5), 0.0)
	assert(not still["ok"], "a turn of nothing is refused")
	assert(still["reason"].contains("nothing"), "and the reason says as much")
	assert(Edit.rotate(null, Vector2(5, 5), 1.0)["reason"].contains("nothing"),
		"as is asking to turn nothing at all")