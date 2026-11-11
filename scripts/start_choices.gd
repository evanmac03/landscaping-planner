class_name StartChoices
extends RefCounted
## The front door: the two things this program is opened to do, and when the door is shown at all.
##
## This program is a drawing board and a camera, and a person arriving at it is coming to do one of those
## two things. The camera was built as a page *inside* the drawing - reached through the field survey, which
## itself needs a drawing open - and that is the right depth when the photograph belongs to a plant being
## recorded and the wrong depth for anybody who just wants to photograph a leaf. So the door stands in
## front of both, and neither is a mode: choosing either one shows a page, and what is behind the door is the
## same drawing board and the same camera either way.
##
## ## When the door is shown, and why nothing is remembered
##
## Shown when there is **nothing behind it** - a drawing that has never been saved and has had nothing done
## to it. That is the state this program opens in every time, so the door comes up on every launch, and it
## is also the rule that keeps the door out of the way the day a launch restores somebody's drawing: a
## question whose answer is already known is a question that should not be asked.
##
## No preference is stored and none is offered. A front door with a "do not ask again" tick is a front door
## that can only be switched off for good, and this one is not in the way of anybody who is already working:
## it is drawn before anything has been done, and one press is out of it.

## The choice that means the drawing board.
const DESIGN := &"design"
## The choice that means this device's camera.
const CAMERA := &"camera"

## What the page is called, and what it says before the two buttons.
const TITLE := "Landscaping Planner"
const OPENING := (
	"This program is a drawing board for a garden and a camera for the site you are standing on. "
	+ "Begin with whichever you came here to do, and reach the other from either one."
)

## What the screen is filled with while the door is up: the choice, and nothing else.
##
## The drawing board is furnished - a house, a lawn, the trees, the beds, a palette of tools and three panels
## of readings - and all of it is the design suite's room. A person who has not yet said what they came here
## to do is in the doorway, not the room, and the first version of this door got that wrong: it stood, and a
## fully furnished yard stood behind it, so the opening looked like a garden somebody else had loaded.
##
## Opaque on purpose, and that is the property worth holding: a sheet with any transparency in it is the
## garden showing through it again.
const SCREEN := Color(0.09, 0.10, 0.12)

## The two choices, in the order a person meets them: the work first, because the drawing is what this
## program is for, and the camera beside it rather than under it. Each is a page, named by the id its button
## answers with - never by a mode, because there is no mode to be in.
const CHOICES: Array[Dictionary] = [
	{
		"id": DESIGN,
		"label": "Design the garden",
		"line": "Draw the site to scale, choose the plants from the nursery list and price the work.",
	},
	{
		"id": CAMERA,
		"label": "Take a photograph",
		"line": "Point this device's camera at what is on site and keep the picture with the survey.",
	},
]


## Whether the front door is shown, given what the drawing is: where it lives, or "" when it has never been
## saved, and whether anything has been done to it that the file does not hold.
##
## Nothing stated is not the same as nothing open: an untitled drawing that somebody has drawn in is work,
## and the door must not stand in front of it.
static func should_show(drawing_path: String, dirty: bool) -> bool:
	return drawing_path.is_empty() and not dirty


## What closing the door means. The drawing board, because a dismissed page that left a person on a dark
## screen with nothing behind it would be the worst possible answer, and because the drawing is what the
## program is for.
static func dismissed() -> StringName:
	return DESIGN


## The ids of the two choices, in the order they are offered, for a test or a menu line.
static func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for choice: Dictionary in CHOICES:
		out.append(StringName(choice["id"]))
	return out