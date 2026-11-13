extends Node

## A picture showing nothing: the every-byte rule, the reason it gives, and the mark a sample would step over.

const BlankPictureScript := preload("res://scripts/blank_picture.gd")

const WIDTH := 40
const HEIGHT := 30


func test_a_picture_that_is_not_there_shows_nothing() -> void:
	assert(BlankPictureScript.is_blank(null), "no picture at all")


func test_a_picture_given_no_size_shows_nothing() -> void:
	assert(BlankPictureScript.is_blank(Image.new()), "an image with no pixels in it")


func test_a_picture_of_one_colour_shows_nothing() -> void:
	var image := _field()
	assert(BlankPictureScript.is_blank(image), "one colour from corner to corner")


func test_one_pixel_different_is_a_picture_that_shows_something() -> void:
	var image := _field()
	image.set_pixel(0, 0, Color.WHITE)
	assert(not BlankPictureScript.is_blank(image), "one pixel of a different colour is something to see")


func test_a_mark_in_the_very_last_pixel_is_still_found() -> void:
	var image := _field()
	image.set_pixel(WIDTH - 1, HEIGHT - 1, Color.WHITE)
	assert(
		not BlankPictureScript.is_blank(image),
		"the last pixel is exactly what a sampled grid steps over, which is why every byte is looked at",
	)


func test_a_thin_border_around_a_flat_field_is_a_picture_that_shows_something() -> void:
	var image := _field()
	for x in WIDTH:
		image.set_pixel(x, 0, Color.WHITE)
		image.set_pixel(x, HEIGHT - 1, Color.WHITE)
	assert(not BlankPictureScript.is_blank(image), "a border two rows thick is a drawing, not a blank")


func test_a_flat_picture_is_reported_with_its_size() -> void:
	assert(
		BlankPictureScript.why(_field()) == "the picture is one colour everywhere, 40 x 30",
		BlankPictureScript.why(_field()),
	)


func test_a_picture_that_shows_something_has_no_reason_to_give() -> void:
	var image := _field()
	image.set_pixel(5, 5, Color.WHITE)
	assert(BlankPictureScript.why(image) == "", "there is nothing to say about a picture doing its job")
	assert(BlankPictureScript.why(null) == "there is no picture here at all")


func test_a_finding_is_the_name_and_the_reason() -> void:
	var found := BlankPictureScript.faults(
		[
			{ "name": "the plant key's leaf", "image": _field() },
			{ "name": "a drawing that is there", "image": _showing() },
		]
	)
	assert(found.size() == 1, "only the one with nothing in it")
	assert(
		BlankPictureScript.sentence(found[0]) == "the plant key's leaf - the picture is one colour everywhere, 40 x 30",
		BlankPictureScript.sentence(found[0]),
	)


## A flat field, which is what a picture with nothing in it looks like.
func _field() -> Image:
	var image := Image.create(WIDTH, HEIGHT, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.2, 0.25, 0.2))
	return image


func _showing() -> Image:
	var image := _field()
	image.set_pixel(3, 4, Color.WHITE)
	return image
