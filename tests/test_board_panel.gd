extends Node
## `BoardPanel` - the wrapper a panel over the drawing is held in - and the one lever the engine's own
## `CenterContainer` does not have.
##
## Every test here builds the wrapper and its page by hand and adds neither to a scene, because the question is
## arithmetic about rectangles: where a page of a known size is put inside a room of a known size, and how big
## the wrapper says it needs to be. Nothing is measured on a screen, so the runner's own dummy display never
## comes into it - the same shape as the tests that hold `ToolPalette.fit_a_strip` and `ChromeStyle`'s plates.

const BoardPanelScript := preload("res://scripts/board_panel.gd")


func _a_wrapper(room: Vector2, page_size: Vector2) -> BoardPanel:
	var wrapper: BoardPanel = BoardPanelScript.new()
	wrapper.size = room
	var page := PanelContainer.new()
	page.name = "Page"
	page.custom_minimum_size = page_size
	wrapper.add_child(page)
	wrapper.place_the_page()
	return wrapper


func _free_it(wrapper: BoardPanel) -> void:
	wrapper.free()


## A desk centres the panel over the work: equal room above and below it.
func test_a_desk_centres_the_page_over_the_work() -> void:
	var wrapper: BoardPanel = _a_wrapper(Vector2(1600.0, 900.0), Vector2(520.0, 300.0))
	var page: Control = wrapper.the_page()
	assert(
		is_equal_approx(page.position.y, 300.0),
		"the page stands centred: %.1f above it, %.1f below" % [page.position.y, 900.0 - page.position.y - 300.0],
	)
	assert(is_equal_approx(page.position.x, 540.0), "and centred across: %.1f" % page.position.x)
	_free_it(wrapper)


## A finger stands it along the foot, with the page's own foot on the band's foot.
func test_a_finger_stands_the_page_along_the_foot() -> void:
	var wrapper: BoardPanel = _a_wrapper(Vector2(1185.0, 405.0), Vector2(700.0, 257.0))
	wrapper.along_the_foot = true
	wrapper.place_the_page()
	var page: Control = wrapper.the_page()
	assert(
		is_zero_approx(page.position.y + page.size.y - wrapper.size.y),
		(
			"the page's foot is the band's foot: page ends at %.1f, the band at %.1f"
			% [page.position.y + page.size.y, wrapper.size.y]
		),
	)
	_free_it(wrapper)


## **The lever the engine's container does not have, and the reason this class exists:** a band is the room it was
## given and not its page's idea of how tall it should be.
func test_a_band_takes_the_room_it_is_given_and_not_its_pages_minimum() -> void:
	var wrapper: BoardPanel = _a_wrapper(Vector2(1185.0, 405.0), Vector2(700.0, 4189.0))
	wrapper.along_the_foot = true
	wrapper.place_the_page()
	assert(
		wrapper.custom_minimum_size == Vector2.ZERO,
		"a band asks for no room of its own: %s" % str(wrapper.custom_minimum_size),
	)
	_free_it(wrapper)


## And a desk's wrapper still grows to its page, which is what it did before this class existed - the four long
## panels overflow the room on a desk exactly as they always have.
func test_a_desks_wrapper_still_grows_to_its_page() -> void:
	var wrapper: BoardPanel = _a_wrapper(Vector2(1600.0, 900.0), Vector2(700.0, 4189.0))
	assert(
		is_equal_approx(wrapper.custom_minimum_size.y, 4189.0),
		"the desk's wrapper asks for the page's own height: %.1f" % wrapper.custom_minimum_size.y,
	)
	_free_it(wrapper)


## A page is never stretched to the room it stands in: a panel that fits is a short panel, as a desk draws it.
func test_a_page_is_never_stretched_to_the_room() -> void:
	var wrapper: BoardPanel = _a_wrapper(Vector2(1185.0, 405.0), Vector2(700.0, 257.0))
	wrapper.along_the_foot = true
	wrapper.place_the_page()
	var page: Control = wrapper.the_page()
	assert(is_equal_approx(page.size.y, 257.0), "the page keeps its own height: %.1f" % page.size.y)
	assert(is_equal_approx(page.size.x, 700.0), "and its own width: %.1f" % page.size.x)
	_free_it(wrapper)


## A wrapper holding no page is not an error: every builder in `hud.gd` names its page "Page" and a scene that
## has been moved out from under this file says so by asking, rather than by failing.
func test_a_wrapper_with_no_page_asks_for_no_room() -> void:
	var wrapper: BoardPanel = BoardPanelScript.new()
	wrapper.size = Vector2(1185.0, 405.0)
	wrapper.place_the_page()
	assert(wrapper.custom_minimum_size == Vector2.ZERO, "nothing to place asks for nothing")
	assert(wrapper.the_page() == null, "and there is no page to find")
	_free_it(wrapper)
