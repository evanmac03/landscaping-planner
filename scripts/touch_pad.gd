class_name TouchPad
extends Control
## The two controls a phone needs to walk the ground view: a thumb-stick on the left half of the screen for
## walking, and a drag on the right half for looking, because neither a keyboard nor a captured mouse is
## there to do either.
##
## It is put *behind* the HUD's own panels, so a button that is on screen keeps its own touches and only the
## empty part of the screen belongs to this. It is shown on a touchscreen, and in the ground view only -
## where the drawing's tools do nothing and the eye is on the garden rather than on the plan.
##
## Touches, not the mouse. On Android a touch also arrives as a mouse click, and `MOUSE_FILTER_STOP` here
## swallows both, so a thumb on the glass cannot also plant a tree behind it.

## How far a thumb travels for full walking speed, in screen pixels.
const REACH := 90.0
## How far it may wander before the walk begins at all: a finger held still on glass is never quite still.
const DEAD_ZONE := 0.12
## Pushed past the rim by this much more, the walk becomes a run.
const RUN_AT := 1.35
## The radius the stick is drawn at, so the thumb has something to aim at.
const RING_RADIUS := 56.0
const KNOB_RADIUS := 26.0
const RING_COLOUR := Color(1.0, 1.0, 1.0, 0.18)
const KNOB_COLOUR := Color(1.0, 1.0, 1.0, 0.40)

## The view whose walker this drives. Handed over by whoever builds the pad.
var view_controller: ViewController = null

## The finger walking - its index, where it landed, and where it has reached - and the finger looking.
var _stick_finger: int = -1
var _stick_anchor := Vector2.ZERO
var _stick_at := Vector2.ZERO
var _look_finger: int = -1


func _ready() -> void:
	visible = false
	# Everything the pad does not use still stops here: a touch that fell through would reach the world
	# behind it, and the world's left button plants and moves things.
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Anchors *and* offsets: the anchors alone leave a control at no size, which is a control that cannot be
	# touched - and one whose left/right halves are a division of zero.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visibility_changed.connect(_let_go)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_touch(event as InputEventScreenTouch)
		accept_event()
	elif event is InputEventScreenDrag:
		_drag(event as InputEventScreenDrag)
		accept_event()


## A finger arriving or leaving. The left half walks and the right half looks, which is the one split a
## person can learn without being told: the stick is under the thumb that holds the phone.
func _touch(touch: InputEventScreenTouch) -> void:
	if touch.pressed:
		if touch.position.x < half_width():
			if _stick_finger < 0:
				_stick_finger = touch.index
				_stick_anchor = touch.position
				_stick_at = touch.position
				_push_stick()
				queue_redraw()
		elif _look_finger < 0:
			_look_finger = touch.index
		return
	if touch.index == _stick_finger:
		_stick_finger = -1
		MoveInput.set_touch_stick(Vector2.ZERO, false)
		queue_redraw()
	elif touch.index == _look_finger:
		_look_finger = -1


## A finger moving: the walking one re-reads where it is, and the looking one turns the head by how far it
## travelled - the same arithmetic the captured mouse uses, so the two cannot disagree.
func _drag(drag: InputEventScreenDrag) -> void:
	if drag.index == _stick_finger:
		_stick_at = drag.position
		_push_stick()
		queue_redraw()
	elif drag.index == _look_finger:
		var player: PlanPlayer = walker()
		if player != null:
			player.look_by_drag(drag.relative)


## Hand the thumb's position to `MoveInput`, which is where the walker reads one number from - so the player
## never has to know whether a thumb or a key asked.
func _push_stick() -> void:
	var ratio: Vector2 = drag_stick(_stick_at - _stick_anchor, REACH, DEAD_ZONE)
	MoveInput.set_touch_stick(ratio.limit_length(1.0), ratio.length() >= RUN_AT)


## The walker this pad drives, or null in a scene that has none.
func walker() -> PlanPlayer:
	if view_controller == null:
		return null
	return view_controller.player


## Where the walking half ends. Taken from the viewport when this control has not been laid out yet - a
## touch can arrive on the frame the pad is first shown - because the answer is the same either way, and a
## division of no width would put every thumb on the looking half.
func half_width() -> float:
	var width: float = size.x if size.x > 0.0 else get_viewport_rect().size.x
	return width * 0.5


## Nothing is walking once the pad is out of sight: a thumb on the glass when the view changes is not still
## walking in the next one.
func _let_go() -> void:
	if visible:
		return
	_stick_finger = -1
	_look_finger = -1
	MoveInput.set_touch_stick(Vector2.ZERO, false)
	queue_redraw()


## The stick a thumb is asking for, from how far it is from where it landed.
##
## The offset is in screen pixels, positive to the right and down like everything else on a screen, and the
## answer is in the movement keys' own convention - x is right minus left, y is back minus forward - so a
## thumb dragged *up* walks forward. A thumb inside the dead zone asks for nothing at all, and the length
## is left unclamped so the caller can tell the rim from past it, which is where the run is.
static func drag_stick(offset: Vector2, reach: float, dead_zone: float) -> Vector2:
	if reach <= 0.0:
		return Vector2.ZERO
	var ratio: Vector2 = offset / reach
	if ratio.length() <= dead_zone:
		return Vector2.ZERO
	return ratio


func _draw() -> void:
	if _stick_finger < 0:
		return
	draw_circle(_stick_anchor, RING_RADIUS, RING_COLOUR)
	draw_circle(
		_stick_anchor + (_stick_at - _stick_anchor).limit_length(RING_RADIUS),
		KNOB_RADIUS,
		KNOB_COLOUR
	)