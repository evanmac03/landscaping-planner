class_name DraftLayer
extends RefCounted
## One layer of a drafting document: what it is for, and how it draws and plots.
##
## A layer carries the drafting conventions for everything on it, so a
## conventional drawing needs no per-entity styling. Screen appearance and plot
## appearance are separate, because a plan is authored in colour and frequently
## plotted in grey (docs/drafting-subsystem-spec.md §4.1).

## Sibling modules are reached by preload rather than by their global class name.
## The global registry is rewritten by the editor's file-system scan, so a
## reference to a freshly added script resolves sometimes and not others; preload
## is resolved by path and always works, headless included.

const LineStyleScript := preload("res://scripts/draft/line_style.gd")

var name: StringName = &"000"
## Human text: what belongs on this layer.
var purpose: String = ""
var screen_colour: Color = Color.WHITE
var plot_colour: Color = Color.BLACK
var plot_weight_mm: float = 0.25
var linetype: StringName = &"continuous"
## Non-plotting layers carry tracing aids, not the drawing (REQ 5.1.3).
var plots: bool = true
var visible: bool = true
## Locked layers stay visible but must not be selectable (REQ 5.2.2).
var locked: bool = false


## The numeric prefix, which doubles as draw order and plotting band: lower sorts
## underneath and plots first (REQ 5.1.2).
func sort_key() -> int:
	var digits := ""
	var text := String(name)
	for index in text.length():
		var character := text[index]
		if character >= "0" and character <= "9":
			digits += character
		else:
			break
	if digits.is_empty():
		return 999
	return int(digits)


## The line style this layer applies to an entity, unless the entity overrides it.
func style() -> LineStyleScript:
	var line := LineStyleScript.new()
	line.plot_weight_mm = plot_weight_mm
	line.linetype = linetype
	line.plot_colour = plot_colour
	line.screen_colour = screen_colour
	return line


## Instantiate this script by path, for the reason given in line_style.gd.
static func _new() -> DraftLayer:
	return (load("res://scripts/draft/draft_layer.gd") as GDScript).new()


func copy() -> DraftLayer:
	var other := _new()
	other.name = name
	other.purpose = purpose
	other.screen_colour = screen_colour
	other.plot_colour = plot_colour
	other.plot_weight_mm = plot_weight_mm
	other.linetype = linetype
	other.plots = plots
	other.visible = visible
	other.locked = locked
	return other