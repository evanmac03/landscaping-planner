class_name PlannerHud
extends CanvasLayer
## The planner's heads-up display: which view you are in, what the controls do,
## and the drafting aids on the overlay layer.

const PLAN_HINTS := "Right-drag: pan     Wheel: zoom     W A S D: pan     Tab: ground view"
const GROUND_HINTS := "W A S D: walk     Shift: run     Mouse: look     Arrows: look     Esc: free cursor     Tab: plan view"

@export var view_controller: ViewController

@onready var mode_label: Label = %ModeLabel
@onready var toggle_button: Button = %ToggleButton
@onready var fit_button: Button = %FitButton
@onready var hints_label: Label = %HintsLabel
@onready var overlay: HudOverlay = %Overlay


func _ready() -> void:
	if view_controller == null:
		push_error("PlannerHud: view_controller must be assigned.")
		return
	view_controller.view_mode_changed.connect(_on_view_mode_changed)
	view_controller.transition_started.connect(_on_transition_started)
	view_controller.transition_finished.connect(_on_transition_finished)
	toggle_button.pressed.connect(view_controller.toggle_view)
	fit_button.pressed.connect(view_controller.fit_plan_to_yard)
	_on_view_mode_changed(view_controller.mode)


func _process(_delta: float) -> void:
	if view_controller == null:
		return
	var viewport_height: float = get_viewport().get_visible_rect().size.y
	overlay.set_pixels_per_metre(
		ViewMath.pixels_per_metre(viewport_height, view_controller.plan_size)
	)


func _on_view_mode_changed(new_mode: ViewController.ViewMode) -> void:
	var in_plan: bool = new_mode == ViewController.ViewMode.PLAN
	mode_label.text = "PLAN VIEW" if in_plan else "GROUND VIEW"
	mode_label.add_theme_color_override(
		"font_color",
		Color(0.6, 0.85, 0.52) if in_plan else Color(0.85, 0.78, 0.5)
	)
	toggle_button.text = "Go to ground view  (Tab)" if in_plan else "Back to plan view  (Tab)"
	fit_button.visible = in_plan
	hints_label.text = PLAN_HINTS if in_plan else GROUND_HINTS
	overlay.set_mode(new_mode)


func _on_transition_started(_to_ground: bool) -> void:
	overlay.set_transitioning(true)


func _on_transition_finished(_to_ground: bool) -> void:
	overlay.set_transitioning(false)
