class_name PageEscape
extends Node
## Escape, for the pages that live in a `Window`.
##
## A page in a `Window` takes the keyboard into its own viewport, so nothing beside it - the HUD
## included - ever sees the key. That was measured, not assumed: in `tools/page_escape_demo.gd` a real
## Escape reached a node put *inside* the page and reached a node beside the HUD not at all. So the only
## place that can answer the key is inside the page, and this node is put there by whatever opened it.
##
## It closes the page the way the page's own frame and its own Close button do - both already go through
## `close_requested` - so the key and the button cannot drift apart, and no page has to know about the
## key at all.
##
## What is deliberately *not* here: the pages the HUD draws itself (the site report, the water page and
## the rest). Those are ordinary controls, so the HUD's own Escape ladder answers for them in one place.

## The name this node is given inside a page, which is also how a second attach is told to do nothing.
const ATTACHED := &"PageEscape"

## The page this node answers for. Set before the node is added, and read only while it is in the tree.
var page: Window = null


## Put a closer inside a page, once. Returns the one it made, or `null` if the page already had one -
## so a page that is opened again does not end up with two nodes both listening for the same key.
static func attach(to_page: Window) -> PageEscape:
	if to_page == null or to_page.get_node_or_null(^"PageEscape") != null:
		return null
	var closer := PageEscape.new()
	closer.name = ATTACHED
	closer.page = to_page
	to_page.add_child(closer)
	return closer


## Whether this key is the one that closes the page.
##
## Split out from the handler so the rule can be tested without a window server: handling the key ends
## in `get_viewport().set_input_as_handled()`, and an off-tree page has no viewport to hand it to.
func answers(event: InputEvent) -> bool:
	if page == null or not is_instance_valid(page) or not page.visible:
		return false
	return event.is_action_pressed(&"draft_cancel")


func _unhandled_input(event: InputEvent) -> void:
	if not answers(event):
		return
	# Handled here rather than left to travel on: a key that closed the page and then went on to the
	# drawing behind it would cancel a shape as a side effect of putting a page away.
	get_viewport().set_input_as_handled()
	page.close_requested.emit()