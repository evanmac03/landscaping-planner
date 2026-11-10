extends Node
## Whether a camera can be used here, which one to show, and where a frame lands.
##
## The four refusals below are the point of the file: they are four different things for a person to do, and
## a page that answered all four with a black rectangle would be a page nobody can use.

const CameraCaptureScript := preload("res://scripts/camera_capture.gd")
const CameraWindowScript := preload("res://scripts/camera_window.gd")
const FieldPhotoStoreScript := preload("res://scripts/field_photo_store.gd")


## A device with no camera says so, rather than showing an empty picture and letting somebody wonder.
func test_a_device_with_no_camera_says_so() -> void:
	assert(not CameraCaptureScript.usable(0, true), "no feeds is no picture")
	assert(
		CameraCaptureScript.refusal(0, true).contains("no camera"),
		"and the sentence says which of the two is missing: %s" % CameraCaptureScript.refusal(0, true)
	)


## A camera that was never allowed is a different answer, and it is the one a phone gives *before* it has
## been asked: the feeds only appear once the permission is granted, so "no camera" there is a lie.
func test_a_camera_nobody_allowed_is_about_the_permission_and_not_about_the_device() -> void:
	assert(not CameraCaptureScript.usable(0, false), "nothing may be shown")
	var said: String = CameraCaptureScript.refusal(0, false)
	assert(
		said.contains("camera") and said.contains("not been allowed"),
		"and the sentence is about the permission: %s" % said
	)
	assert(
		not said.contains("no camera"),
		"never about a device that has one: %s" % said
	)


## Allowed, and the camera has answered: this is the only state with nothing to say.
func test_a_camera_that_is_allowed_and_answering_has_nothing_to_refuse() -> void:
	assert(CameraCaptureScript.usable(2, true), "two feeds and a permission is a picture")
	assert(CameraCaptureScript.refusal(2, true) == "", "and nothing to say about it")


## The back camera is the one pointed at the plant, so it is the one shown when there is one.
func test_the_back_camera_is_chosen_and_the_first_one_when_there_is_none() -> void:
	# Two cameras, the back one second, as a phone reports them.
	assert(CameraCaptureScript.choose([1, 2], 2) == 1, "the back camera, wherever it is in the list")
	assert(CameraCaptureScript.choose([1, 2], 1) == 0, "and the front one when that is all there is")
	assert(CameraCaptureScript.choose([0], 2) == 0, "a device that does not say falls back to the first")
	assert(CameraCaptureScript.choose([], 2) == -1, "and no camera at all is no index")


## The name to put on the screen, so a person can tell which camera is showing.
func test_each_camera_has_a_word_for_it() -> void:
	assert(CameraCaptureScript.position_word(2, 2, 1) == "the back camera", "the back one")
	assert(CameraCaptureScript.position_word(1, 2, 1) == "the front camera", "the front one")
	assert(CameraCaptureScript.position_word(0, 2, 1) == "a camera", "and one that will not say")


## A frame is kept where the store can take it: the store writes its own copy from a path, so the frame
## has to be under `user://` and named as a picture.
func test_a_frame_is_written_where_the_store_can_read_it() -> void:
	assert(
		CameraCaptureScript.FRAME_PATH.begins_with("user://"),
		"nothing outside the program can take it away mid-write: %s" % CameraCaptureScript.FRAME_PATH
	)
	assert(
		CameraCaptureScript.FRAME_PATH.ends_with(".png"),
		"and the store reads it by its extension: %s" % CameraCaptureScript.FRAME_PATH
	)
	assert(
		FieldPhotoStoreScript.EXTENSION_OF_FORMAT.has("PNG"),
		"a format the store knows how to file"
	)


## A feed that carries colour alongside brightness cannot be drawn as it stands: drawing it shows the colour
## as if it were brightness, and a plant comes out a magenta cloud. The three shapes are the device's.
func test_a_feed_that_carries_colour_with_brightness_has_to_be_decoded() -> void:
	const RGB := 1
	const YCBCR := 2
	const SEPARATED := 3
	const NOIMAGE := 0
	assert(CameraCaptureScript.planes_for(RGB, RGB, YCBCR, SEPARATED) == 1, "a picture is one texture")
	assert(
		not CameraCaptureScript.needs_decoding(RGB, RGB),
		"and it is drawn as it stands, or the colours would be run through a decoder that is not needed"
	)
	assert(
		CameraCaptureScript.planes_for(YCBCR, RGB, YCBCR, SEPARATED) == 1,
		"brightness and colour together are still one texture"
	)
	assert(
		CameraCaptureScript.needs_decoding(YCBCR, RGB),
		"but they have to be put back together: this is the magenta cloud, in one line"
	)
	assert(
		CameraCaptureScript.planes_for(SEPARATED, RGB, YCBCR, SEPARATED) == 2,
		"and two textures when they arrive apart"
	)
	assert(
		CameraCaptureScript.planes_for(NOIMAGE, RGB, YCBCR, SEPARATED) == 0,
		"a camera that has not handed a picture over has nothing to draw, and is not decoded into one"
	)


## The renderer this program draws with everywhere does not put a camera frame together for us, and does not
## say so in the frame. It was measured on a phone: the picture arrived in red with green and blue at exactly
## zero, and drawn as it stood that was a crimson rectangle rather than a photograph. So on that renderer
## every frame is read as the two apart, and on a renderer that does convert, only the split shapes need it.
func test_a_renderer_that_will_not_convert_a_camera_frame_leaves_the_whole_of_it_to_the_page() -> void:
	const RGB := 1
	const YCBCR := 2
	const SEPARATED := 3
	assert(
		CameraCaptureScript.reads_apart(false, RGB, SEPARATED),
		"with no rendering device, a feed that calls itself a picture is read apart all the same"
	)
	assert(
		CameraCaptureScript.reads_apart(false, YCBCR, SEPARATED),
		"and one that carries colour alongside brightness, for the same reason"
	)
	assert(
		not CameraCaptureScript.reads_apart(true, RGB, SEPARATED),
		"with a rendering device the engine has already put it together, and it is drawn as it stands"
	)
	assert(
		CameraCaptureScript.reads_apart(true, SEPARATED, SEPARATED),
		"and only the frame that genuinely arrives split is read apart"
	)


## The viewfinder's shader has to *compile*, and nothing else here would notice if it did not: a shader that
## fails to parse leaves Godot drawing the feed bare, which on the phone this was built for is a crimson
## rectangle rather than a photograph, and one that draws perfectly happily. That cost two device round trips
## to find, so it is held here - and it can be asked without a renderer at all, because a shader that does not
## parse has no uniforms while this one has three.
func test_the_viewfinder_shader_is_one_that_actually_compiles() -> void:
	var made := Shader.new()
	made.code = CameraWindowScript.DECODING_SHADER
	var uniforms: Array = made.get_shader_uniform_list()
	assert(
		uniforms.size() >= 5,
		"the shader parsed and declared its uniforms, or the feed is being drawn bare: %d" % uniforms.size()
	)
	var named: Array[String] = []
	for entry: Dictionary in uniforms:
		named.append(String(entry.get("name", "")))
	for wanted: String in ["luma", "colour", "interleaved", "turned", "showing"]:
		assert(named.has(wanted), "%s is a uniform of it: %s" % [wanted, str(named)])


## The live picture's rectangle is in layout pixels and the frame is in the pixels it is drawn at, so it is
## scaled - rounded out, so the picture is never smaller than the rectangle it was asked for.
func test_the_rectangle_is_scaled_from_the_layout_to_the_drawn_frame() -> void:
	var region: Rect2i = CameraCaptureScript.frame_region(Rect2(10.0, 4.0, 100.0, 50.0), 2.0)
	assert(region == Rect2i(20, 8, 200, 100), "twice the scale is twice the rectangle: %s" % str(region))
	var one: Rect2i = CameraCaptureScript.frame_region(Rect2(10.5, 4.5, 3.0, 3.0), 1.0)
	assert(one.position == Vector2i(10, 4), "and a fraction rounds out rather than in: %s" % str(one))
	assert(one.size == Vector2i(4, 4), "so nothing is lost at the edge")
	var unpainted: Rect2i = CameraCaptureScript.frame_region(Rect2(0.0, 0.0, 1.0, 1.0), 0.0)
	assert(
		unpainted.size.x >= 1 and unpainted.size.y >= 1,
		"a scale nobody could read is not an empty picture: %s" % str(unpainted)
	)


## The page says which camera is showing, and - since the fault that cost a device round trip - *how* the
## device is handing the picture over. The two shapes need different decoders, so a page that cannot say
## which one it is looking at cannot be diagnosed from a photograph of itself.
func test_the_page_says_how_the_camera_is_handing_the_picture_over() -> void:
	const RGB := 1
	const YCBCR := 2
	const SEPARATED := 3
	var said: Array[String] = []
	for datatype: int in [RGB, YCBCR, SEPARATED, 99]:
		var words: String = CameraCaptureScript.datatype_word(datatype, RGB, YCBCR, SEPARATED)
		assert(not words.is_empty(), "every shape of feed gets a sentence: %d" % datatype)
		assert(not said.has(words), "two shapes must not read the same: %s" % words)
		said.append(words)
	assert(said.size() == 4, "four shapes of feed, four sentences: %s" % str(said))


## The colour is where the camera put it. A packed feed carries the brightness in red and *both* colour
## halves in green, one to a pixel - so a decoder that reads the red difference out of blue reads a channel
## holding nothing and paints every photograph crimson. That is the fault this holds down.
func test_the_decoder_looks_for_both_colour_halves_in_the_one_channel_that_carries_them() -> void:
	var code: String = CameraWindowScript.DECODING_SHADER
	assert(
		code.contains("texture(luma, left).g") and code.contains("texture(luma, right).g"),
		"both halves are read out of green, side by side"
	)
	assert(
		not code.contains(".gb"),
		"and neither of them out of blue, which carries no colour on a packed feed"
	)
	assert(
		code.contains("TEXTURE_PIXEL_SIZE"),
		"the pair is found by the texture's own columns, not by the width it is drawn at"
	)
	assert(
		CameraWindowScript.DECODING_SHADER.contains("interleaved"),
		"and the feed that carries them apart is still decoded as it was"
	)