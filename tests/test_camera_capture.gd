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


## The page asks how big the room is, and never the engine which orientation it asked the phone for.
##
## That call answers with the *request* - six, follow the device, or a pinned landscape - rather than with a
## fact, so on a phone held upright the reading was neither portrait nor reverse-portrait, every branch of the
## turn fell through, and the picture was left in the sensor's landscape frame while the page was drawn
## portrait. The fault is invisible from inside the program and the page looked perfectly well; what gave it
## away was its own caption reading "held on its side" over a portrait window. A source assertion is the only
## thing here that can notice, which is why it is written as one.
func test_the_page_asks_the_room_and_never_the_orientation_it_asked_the_phone_for() -> void:
	var code: String = FileAccess.get_file_as_string("res://scripts/camera_window.gd")
	assert(not code.is_empty(), "the page is there to read")
	assert(
		not code.contains("screen_get_orientation"),
		"a request is not a reading: asking for one leaves a portrait phone's picture on its side"
	)
	assert(
		code.contains("window_get_size"),
		"it asks how big the room is instead, which is a fact"
	)


## The camera is opened over two different things - a drawing board, and the doorway a person meets before
## there is a drawing - and its way out has to be named for whichever one is behind it. "Back to the
## drawing" over a menu with two choices on it is a button that lies about where it goes, which is the one
## thing this program's words are not allowed to do.
func test_the_way_out_of_the_camera_is_named_for_what_is_behind_it() -> void:
	var over_a_drawing: String = CameraWindowScript.way_out_word(CameraWindowScript.BEHIND_A_DRAWING)
	var over_the_door: String = CameraWindowScript.way_out_word(CameraWindowScript.BEHIND_THE_DOOR)
	assert(over_a_drawing.contains("drawing"), "over a drawing it says where it goes: %s" % over_a_drawing)
	assert(
		not over_the_door.contains("drawing"),
		"and over the doorway it does not promise a drawing there is not: %s" % over_the_door
	)
	assert(
		over_a_drawing != over_the_door,
		"two things behind the camera, two different sentences"
	)
	# And the button a person actually presses carries that word, rather than the page building one of its
	# own: the page is built here and never shown, which is how every page in this program is held down.
	# Built first and told second, in the same order the HUD does it - so what is held here is that being
	# told *again* renames the button a person is looking at, which is the case that matters when the camera
	# is opened a second time from somewhere other than where it was opened the first time.
	var page := CameraWindowScript.new()
	page.build()
	page.show_over(CameraWindowScript.BEHIND_THE_DOOR)
	var way_out: Button = page.way_out_button()
	assert(way_out != null, "the page has a way out at all")
	assert(
		way_out.text == over_the_door,
		"and it is the word for what is behind: %s" % way_out.text
	)
	page.free()


## The two doors onto a camera - the HUD's own menu, and the capture page's "Take a photo..." - place it
## through the one answer, so the same page cannot take the whole room from one and sit in the middle of the
## screen from the other.
##
## This is a source assertion, and for the reason the turn test above is one: placing a page reads the real
## room and the real device, and a test has neither. On a desk the whole room and the middle of the screen
## come to the same rectangle, so a page built here could not tell the two doors apart even if it had a room
## to be placed in. What a source check *can* hold down is that there is only one door to come through.
##
## The fault it was written for was found on a phone: opened from the front door the camera filled the screen,
## and opened from the capture page it came up a small window over the survey being filled in. The same page,
## placed in two different ways by whichever button a person pressed, because the capture page was working out
## where the camera goes for itself instead of asking the camera where it belongs.
func test_both_doors_onto_a_camera_place_it_through_the_one_answer() -> void:
	var camera: String = FileAccess.get_file_as_string("res://scripts/camera_window.gd")
	assert(not camera.is_empty(), "the page is there to read")
	assert(
		camera.contains("static func place(camera: CameraWindow)"),
		"the camera keeps one door for the placing"
	)
	assert(
		camera.contains("camera.wants_the_whole_room()"),
		"and that one door is what asks the device, rather than each caller asking its own way"
	)
	var board: String = FileAccess.get_file_as_string("res://scripts/hud.gd")
	assert(
		board.contains("CameraWindowScript.place(_camera_window)"),
		"the HUD's own camera goes through it"
	)
	var field: String = FileAccess.get_file_as_string("res://scripts/field_window.gd")
	assert(
		field.contains("CameraWindowScript.place(_camera)"),
		"and so does the capture page's, which used to work it out for itself"
	)
	assert(
		not field.contains("show_centred(_camera)"),
		"nothing in the capture page places a camera on its own any more"
	)


## A camera window is never added inside a page, because a window cannot be bigger than the window it lives
## in.
##
## Godot's own documentation says so twice: an embedded window is "centered inside its embedder", and its
## size is "a ratio of embedder's size". The capture page is itself a page and it parented the camera it
## opened, so that camera could never take the whole room however the arithmetic asked - which is the fault a
## person reported from the drawing board: choosing to take a photograph should switch the program over to the
## camera, "instead of taking a photo inside the landscape design part". The camera has to live where the room
## is, not inside a form.
func test_a_camera_is_not_added_inside_a_page() -> void:
	var room := Node.new()
	var page := CameraWindowScript.new()
	var camera := CameraWindowScript.new()
	page.add_child(camera)
	assert(
		CameraWindowScript.home_for(camera, room) == room,
		"a camera sitting inside a page is given the room, not left where it cannot grow"
	)
	var loose := CameraWindowScript.new()
	assert(
		CameraWindowScript.home_for(loose, room) == room,
		"and one with no home at all gets the room as well"
	)
	var already_home := CameraWindowScript.new()
	room.add_child(already_home)
	assert(
		CameraWindowScript.home_for(already_home, page) == room,
		"while one already in the room is left where it is"
	)
	already_home.free()
	loose.free()
	camera.free()
	page.free()
	room.free()
