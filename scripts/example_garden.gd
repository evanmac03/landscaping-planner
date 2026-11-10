class_name ExampleGarden
extends RefCounted
## The example garden, as geometry: the little backyard this program is worth trying on.
##
## The garden the program opens in - the lawn, the house, the patio, the beds and the trees - is a 3D scene
## (`scenes/world/yard.tscn`) and not a drawing. `File > New drawing` empties the drawing, so the plan a
## person can actually work on starts blank while the ground outside the window is furnished: the two are
## different things, and only one of them can be edited, saved, priced or plotted.
##
## This is the bridge. It is a *plan*, made of the same `DraftEntity` shapes the drawing tools make, so the
## example lands on the drawing through the drawing's own door and can then be moved, measured, planted,
## priced and thrown away like anything else. It is drawn rather than shipped as a `.json` for that reason
## and one more: a file would be a second copy of a garden that already exists in the project, and this
## project spends its effort on not having two of anything. What is here is a small layout of its own - a
## house across the top, a patio, a path, four beds and two specimen trees - not a measurement of the yard
## scene, whose sizes live in its meshes rather than in a number anybody stated.
##
## Everything is in metres, because the model is metres: the site is eighteen by fourteen.

## What the File menu calls it, and what the status line says afterwards.
const NAME := "The example garden"

## Reached by path rather than by class name: `DraftEntity`'s own note explains why - the global registry is
## rewritten by the editor's scan, so a class that has not been registered yet resolves sometimes and not
## others, and a fresh clone has no `.godot/` at all.
const EntityScript := preload("res://scripts/draft/draft_entity.gd")

## The site: a small backyard, eighteen metres across and fourteen deep.
const SITE := Vector2(18.0, 14.0)


## Every shape the example is made of, in the order a plan is drawn in: the site and the building it
## contains, then the hard landscaping, then what is planted, and the one dimension and the label last.
##
## Handed back as entities rather than added to a document here, because a document is the drawing's
## business and this file's job is only to say what the example *is* - which is what a test can hold with no
## drawing, no scene and no file anywhere.
static func parts() -> Array[DraftEntity]:
	var out: Array[DraftEntity] = []

	# The site itself: the boundary a boundary line is drawn on.
	out.append(EntityScript.make_polyline(PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(SITE.x, 0.0), Vector2(SITE.x, SITE.y), Vector2(0.0, SITE.y),
	]), true))

	# The house, across the top of the site, with the ground in front of it left clear.
	out.append(EntityScript.make_rectangle(Vector2(9.0, 11.5), Vector2(11.0, 4.0)))

	# The hard landscaping: a patio off the back of the house, and a path from the house to the lawn.
	out.append(EntityScript.make_rectangle(Vector2(14.0, 7.2), Vector2(6.0, 3.6)))
	out.append(EntityScript.make_rectangle(Vector2(4.5, 6.6), Vector2(1.2, 7.6)))

	# Four beds, at the four sizes a person would actually make them, so the plan reads as a garden someone
	# laid out rather than as a grid.
	var beds: Array[Dictionary] = [
		{"at": Vector2(2.6, 3.6), "size": Vector2(2.6, 1.4)},
		{"at": Vector2(6.4, 3.0), "size": Vector2(3.2, 1.6)},
		{"at": Vector2(10.6, 3.8), "size": Vector2(3.6, 1.8)},
		{"at": Vector2(15.0, 3.2), "size": Vector2(2.4, 1.4)},
	]
	for bed: Dictionary in beds:
		out.append(EntityScript.make_rectangle(bed["at"], bed["size"]))

	# Two specimen trees, drawn as the circle of their canopy - which is what a tree is on a plan.
	out.append(EntityScript.make_circle(Vector2(2.2, 11.0), 1.6))
	out.append(EntityScript.make_circle(Vector2(16.4, 11.4), 1.4))

	# One dimension across the site, because a plan with no measurement on it does not show what a drawing is
	# for, and one label, because a plan with no words on it does not say what it is.
	out.append(EntityScript.make_dimension(Vector2(0.0, 0.0), Vector2(SITE.x, 0.0), -1.2))
	out.append(EntityScript.make_text(Vector2(0.4, 13.2), NAME))

	return out


## The example in one line, for a status line or a menu tooltip.
static func describe() -> String:
	return "%s: %d shapes on a lawn %s by %s" % [
		NAME,
		parts().size(),
		String.num(SITE.x, 0),
		String.num(SITE.y, 0),
	]