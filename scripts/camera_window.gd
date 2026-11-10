class_name CameraWindow
extends Window
## The device's camera, on a page: what it is pointed at, and a shutter.
##
## A `Window` like the other pages, for the same two reasons they are: it holds something a person reads
## and a button they press, and a `Window` owns its own input, so nothing here can take the drawing's keys.
##
## The picture comes from `CameraServer`, which on Android has been implemented since 4.5 and needs the
## camera permission; on a computer it is a webcam, where no permission is asked for. A feed is a
## `CameraTexture` rather than an image: it is *drawn*, not read, so a photograph of it is taken from what
## the page rendered - the chrome is put away for the one frame the grab happens in, which is why the
## photograph is of the plant and not of the button.
##
## Every decision about whether there is a camera at all, and what to say when there is not, is
## `CameraCapture`'s; what this page adds is the viewfinder, the shutter and the words for the states.

const CameraCaptureScript := preload("res://scripts/camera_capture.gd")
const HeldOrientationScript := preload("res://scripts/held_orientation.gd")
const PhotoStoreScript := preload("res://scripts/field_photo_store.gd")

## The window was closed by its own close button.
signal closed()
## A photograph was taken and kept. Empty when nothing was kept, and the page has said why.
signal photo_taken(kept_path: String)

## Wide enough for a viewfinder that is worth pointing at a plant, and inside a 1600 by 900 window once its
## own title bar is counted.
const SIZE := Vector2i(880, 720)
const TITLE := "Camera"

## What the shutter is introduced by, and what the page says before anything is shown.
const OPENING := "Point the camera at the plant, then press the shutter."
## How long to keep waiting for a camera that has not answered - about five seconds at sixty frames.
const WAITING_FRAMES := 300
## The widest frame worth asking a camera for: a viewfinder eight hundred pixels wide does not need a
## photograph four thousand across, and every pixel of it is drawn and read again when the shutter is pressed.
const WIDEST_WANTED := 1920

## Where a photograph is filed. Stated rather than fixed so a test can be given a folder of its own and
## leave the photographs somebody really took alone.
var folder: String = PhotoStoreScript.DIR

var _column: VBoxContainer = null
var _viewfinder: Control = null
var _caption: Label = null
var _summary: Label = null
var _shutter: Button = null
var _status: Label = null

## The feed being shown, and the textures drawing it. A feed that reports itself YCbCr-separated needs two
## - the luma and the colour - and a shader to put them back together.
var feed: CameraFeed = null
var _texture: CameraTexture = null
var _colour: CameraTexture = null
var _waiting: int = 0
## How the device says it is being held, re-read as the phone is turned. The window follows the device and the
## camera does not, so this is the whole of the disagreement between them - and it is the page's job to undo.
var _screen: int = int(DisplayServer.SCREEN_LANDSCAPE)
## How big the picture the camera hands over is, in its own pixels, before any turning. Kept because a
## rectangle cannot keep the proportions of a picture that is being turned on its own.
var _picture_size: Vector2 = Vector2.ZERO
## Whether the permission was asked for already, so the question is put once rather than every frame.
var _asked: bool = false


func _init() -> void:
	title = TITLE
	min_size = SIZE
	exclusive = false
	close_requested.connect(_on_close_requested)


func _ready() -> void:
	if _column == null:
		build()


# --- building -----------------------------------------------------------------------------------


## Build the whole window by hand. Idempotent, and callable off-tree so a test can drive the same controls
## the program shows.
func build() -> void:
	if _column != null:
		return
	_column = PageChrome.column(self, 6)

	_summary = PageChrome.text()
	_summary.name = "Summary"
	_column.add_child(_summary)

	_column.add_child(PageChrome.subheading("what the camera is showing"))
	_viewfinder = _make_viewfinder()
	_column.add_child(_viewfinder)

	_caption = PageChrome.text()
	_caption.name = "CameraCaption"
	_caption.text = ""
	_column.add_child(_caption)

	var row := PageChrome.button_row()
	_column.add_child(row)
	_shutter = PageChrome.button("Take the photograph")
	_shutter.name = "Shutter"
	_shutter.pressed.connect(_on_shutter_pressed)
	row.add_child(_shutter)
	var close_button := PageChrome.button("Close")
	close_button.name = "Close"
	close_button.pressed.connect(_on_close_requested)
	row.add_child(close_button)

	_status = PageChrome.status()
	_column.add_child(_status)
	_say(OPENING)
	_show_state()


## The viewfinder itself: a texture rectangle for a feed that arrives as a picture, and a coloured
## rectangle with a shader for one that arrives as luma and colour separately.
func _make_viewfinder() -> Control:
	var a_picture: TextureRect = TextureRect.new()
	a_picture.name = "Viewfinder"
	# Filled rather than fitted: a letterboxed camera would put two black bars in every photograph, and the
	# photograph is of a plant.
	a_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	a_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	a_picture.custom_minimum_size = Vector2(0.0, 320.0)
	a_picture.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return a_picture


# --- opening and closing ------------------------------------------------------------------------


## Put the page up and start looking for a camera.
func open() -> void:
	build()
	_ask_for_the_camera()
	CameraServer.monitoring_feeds = true
	_waiting = 0
	_show_state()


## Stop looking at a camera that is nobody else's business while this page is closed: monitoring costs, and
## a feed left active is a camera left on.
func shut() -> void:
	CameraServer.monitoring_feeds = false
	if feed != null:
		feed.set_active(false)
	feed = null
	_texture = null
	_colour = null


# --- the camera itself --------------------------------------------------------------------------


## Whether this program has been allowed the camera. A computer's webcam is not gated, so there is nothing
## to be allowed there.
func permitted() -> bool:
	if not OS.has_feature("android"):
		return true
	return OS.get_granted_permissions().has(CameraCaptureScript.ANDROID_CAMERA)


## Ask for the camera, once. Android answers on its own screen, so nothing here waits for the answer: the
## page reads it again on the next frame, which is also when the feeds appear.
func _ask_for_the_camera() -> void:
	if _asked or not OS.has_feature("android") or permitted():
		return
	_asked = true
	OS.request_permission(CameraCaptureScript.ANDROID_CAMERA)


## Attach to a camera, once the device has one to attach to. False while there is nothing yet.
func attach() -> bool:
	# Nothing to attach to before the page is looking, and nothing to attach to without the permission: a
	# server that is not monitoring refuses to be asked, and a camera nobody has allowed is not switched on.
	if not permitted() or not CameraServer.monitoring_feeds:
		return false
	var feeds: Array[CameraFeed] = CameraServer.feeds()
	var positions: Array = []
	for a_feed: CameraFeed in feeds:
		positions.append(int(a_feed.get_position()))
	var index: int = CameraCaptureScript.choose(positions, int(CameraFeed.FEED_BACK))
	if index < 0:
		return false
	feed = feeds[index]
	# A feed will not start without a size chosen first, and the device offers two dozen of them.
	_choose_a_format()
	feed.set_active(true)
	_make_textures()
	_caption.text = _caption_line()
	_show_state()
	return true


## Choose the size the camera hands its pictures over at.
##
## A feed will not start without one - the engine refuses in as many words: "CameraFeed format needs to be
## set before activating", and it says the device offers two dozen formats and none is chosen. The rule is
## the largest frame no wider than a photograph is worth, so a plant arrives sharp without a four-thousand
## pixel frame being drawn every frame for a viewfinder eight hundred wide.
##
## Asking for the *shape* of the frame was tried here and does not work: `{"output": "separate"}` is honoured
## for a Linux camera stream and ignored on Android, which answers with the shape it was going to use. What
## the device hands over is therefore taken as given, and put together here when the renderer will not.
func _choose_a_format() -> void:
	if feed == null:
		return
	var offered: Array = feed.formats
	if offered.is_empty():
		return
	var best: int = 0
	var best_area: int = -1
	for i: int in offered.size():
		var said: Dictionary = offered[i] if offered[i] is Dictionary else {}
		var wide: int = int(said.get("width", 0))
		var tall: int = int(said.get("height", 0))
		var area: int = wide * tall
		if area <= 0 or wide > WIDEST_WANTED:
			continue
		if area > best_area:
			best_area = area
			best = i
	feed.set_format(best, {})
	var chosen: Dictionary = offered[best] if offered[best] is Dictionary else {}
	_picture_size = Vector2(float(chosen.get("width", 0)), float(chosen.get("height", 0)))


## Where the feed's pixels go, which depends on how the device hands them over. The shapes are
## `CameraCapture`'s decision; this is the drawing of each, and the decoding where one is needed.
func _make_textures() -> void:
	if feed == null or _viewfinder == null:
		return
	var rect: TextureRect = _viewfinder as TextureRect
	if rect == null:
		return
	var datatype: int = int(feed.get_datatype())
	var planes: int = CameraCaptureScript.planes_for(
		datatype, int(CameraFeed.FEED_RGB), int(CameraFeed.FEED_YCBCR), int(CameraFeed.FEED_YCBCR_SEP)
	)
	if planes <= 0:
		# The device has listed a camera but has not handed a picture over yet. Nothing to draw, and
		# nothing to photograph, so the page asks again on the next frame rather than showing a blank square.
		feed.set_active(false)
		feed = null
		_texture = null
		_colour = null
		return
	# Plane zero, which is the picture plane of a feed that arrives as a picture and the brightness plane of
	# one that does not - the same number, answered the same way.
	_texture = _make_texture(CameraServer.FEED_Y_IMAGE)
	rect.texture = _texture
	# Whether the frame is read as the two apart is `CameraCapture`'s decision, handed this machine's own
	# answer about its renderer: on the renderer this program draws with everywhere, the engine does not put a
	# camera's brightness and colour back together, so this page does. Measured on the glass, the frame arrives
	# with the picture in red and nothing at all in green or blue, and drawn as it stands that is a crimson
	# rectangle with a legible silhouette inside it rather than a photograph of a plant.
	var apart: bool = CameraCaptureScript.reads_apart(
		RenderingServer.get_rendering_device() != null,
		datatype,
		int(CameraFeed.FEED_YCBCR_SEP)
	)
	if not apart and not CameraCaptureScript.needs_decoding(datatype, int(CameraFeed.FEED_RGB)):
		return
	if apart:
		_colour = _make_texture(CameraServer.FEED_CBCR_IMAGE)
	rect.material = _decoding_material(apart)


func _make_texture(plane: CameraServer.FeedImage) -> CameraTexture:
	var made := CameraTexture.new()
	made.camera_feed_id = feed.get_id()
	made.which_feed = plane
	made.set_camera_active(true)
	return made


## The shader that turns brightness and two colour halves back into a picture, with the 601 coefficients a
## camera feed is defined by and clamped, because a colour rebuilt from half a range can leave the gamut.
##
## Held as a constant rather than written straight into the material, because the shape of it is worth being
## able to hold down. The fault this file shipped with was a decoder that looked for the red difference in a
## channel carrying no colour at all - so every photograph came out crimson, and nothing in the suite could
## see it, because the wrong channel is a perfectly valid shader.
const DECODING_SHADER := """
shader_type canvas_item;

uniform sampler2D luma : hint_default_black;
uniform sampler2D colour : hint_default_black;
// True when one texture carries the brightness and the colour together, which is what an Android camera
// hands over; false when the two arrive in textures of their own.
uniform bool interleaved = false;
// How many quarter turns to give the picture so that it stands the way the phone is being held, and how much
// of it the rectangle shows. Both are this page's answer to the device: the sensor is bolted to the phone's
// body and the window turns with the phone, so the two are out by exactly this much.
uniform int turned = 0;
uniform vec2 showing = vec2(1.0, 1.0);

// Where in the camera's picture a part of this rectangle came from. The rectangle's own coordinate is passed
// in rather than read here, because a fragment built-in like `UV` is not available inside a helper function
// in this language - and a shader that does not parse is drawn as the feed itself, which is a crimson
// rectangle rather than a photograph and says nothing about why.
vec2 picture_uv(vec2 rect_uv) {
	vec2 across = (rect_uv - vec2(0.5)) * showing + vec2(0.5);
	if (turned == 1) {
		return vec2(across.y, 1.0 - across.x);
	}
	if (turned == 2) {
		return vec2(1.0 - across.x, 1.0 - across.y);
	}
	if (turned == 3) {
		return vec2(1.0 - across.y, across.x);
	}
	return across;
}

// Put the brightness and the two colour halves back into a picture, with the 601 coefficients a camera feed
// is defined by, clamped because a colour rebuilt from half a range can leave the gamut.
void fragment() {
	vec2 uv = picture_uv(UV);
	float brightness = texture(luma, uv).r;
	vec2 chroma;
	if (interleaved) {
		// Two pixels to one colour sample: the brightness is in red on every pixel, and the blue and red
		// differences *share the green channel*, one to a pixel, so a pair of neighbours is one sample. Read
		// that pair by the texture's own columns rather than by the screen's, because the pair belongs to the
		// camera, not to the page.
		float column = floor(uv.x / TEXTURE_PIXEL_SIZE.x);
		float odd = mod(column, 2.0);
		vec2 left = clamp(vec2(uv.x - odd * TEXTURE_PIXEL_SIZE.x, uv.y), vec2(0.0), vec2(1.0));
		vec2 right = clamp(vec2(uv.x + (1.0 - odd) * TEXTURE_PIXEL_SIZE.x, uv.y), vec2(0.0), vec2(1.0));
		chroma = vec2(texture(luma, left).g, texture(luma, right).g);
	} else {
		chroma = texture(colour, uv).rg;
	}
	float cb = chroma.x - 0.5;
	float cr = chroma.y - 0.5;
	vec3 picture = vec3(
		brightness + 1.402 * cr,
		brightness - 0.344136 * cb - 0.714136 * cr,
		brightness + 1.772 * cb
	);
	COLOR = vec4(clamp(picture, vec3(0.0), vec3(1.0)), 1.0);
}
"""


## The material that turns brightness and colour back into a picture.
func _decoding_material(separated: bool) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = DECODING_SHADER
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("luma", _texture)
	material.set_shader_parameter("colour", _colour if _colour != null else _texture)
	material.set_shader_parameter("interleaved", not separated)
	_set_the_turn(material)
	return material


## What the viewfinder says it is showing: which camera, the shape the device is handing the frame over in,
## and how the phone is being held - the third because it is the one that changes while the page is open and
## because a picture that is the wrong way up is the thing this line is here to explain.
func _caption_line() -> String:
	if feed == null:
		return ""
	return "showing %s, %s, %s" % [
		CameraCaptureScript.position_word(
			int(feed.get_position()), int(CameraFeed.FEED_BACK), int(CameraFeed.FEED_FRONT)
		),
		CameraCaptureScript.datatype_word(
			int(feed.get_datatype()),
			int(CameraFeed.FEED_RGB), int(CameraFeed.FEED_YCBCR), int(CameraFeed.FEED_YCBCR_SEP)
		),
		HeldOrientationScript.words_for(
			_screen,
			int(DisplayServer.SCREEN_LANDSCAPE),
			int(DisplayServer.SCREEN_PORTRAIT),
			int(DisplayServer.SCREEN_REVERSE_LANDSCAPE),
			int(DisplayServer.SCREEN_REVERSE_PORTRAIT)
		),
	]


## How many quarter turns stand the picture the way the phone is held, asked of the device rather than
## remembered, and handed to the material along with the shape the picture has come out.
func _set_the_turn(material: ShaderMaterial) -> void:
	if material == null or feed == null:
		return
	var turns: int = HeldOrientationScript.quarter_turns(
		_screen,
		int(DisplayServer.SCREEN_LANDSCAPE),
		int(DisplayServer.SCREEN_PORTRAIT),
		int(DisplayServer.SCREEN_REVERSE_LANDSCAPE),
		int(DisplayServer.SCREEN_REVERSE_PORTRAIT)
	)
	material.set_shader_parameter("turned", turns)
	material.set_shader_parameter("showing", _showing(turns))


## How much of the picture the viewfinder covers once it has been turned, so that the rectangle is filled by
## the middle of the picture rather than by a stretched one. A rectangle cannot work this out for itself when
## the picture is being turned: its own stretch mode would fit the shape the picture has before turning.
func _showing(turns: int) -> Vector2:
	if _viewfinder == null or _picture_size.x <= 0.0 or _picture_size.y <= 0.0:
		return Vector2.ONE
	if _viewfinder.size.x <= 0.0 or _viewfinder.size.y <= 0.0:
		return Vector2.ONE
	return CameraCaptureScript.cover_scale(
		CameraCaptureScript.turned_size(_picture_size, turns), _viewfinder.size
	)


## The material the viewfinder draws through, or nothing when there is no picture yet.
func _material() -> ShaderMaterial:
	if _viewfinder == null:
		return null
	var rectangle: TextureRect = _viewfinder as TextureRect
	return null if rectangle == null else rectangle.material as ShaderMaterial


# --- the photograph -----------------------------------------------------------------------------


## Take the photograph: put the chrome away for the frame that is grabbed, so the picture is of the plant.
## Returns the path it was kept under, or "" - and the page says why - when nothing was kept.
func take_photo() -> String:
	if not ready_to_shoot():
		return ""
	var aimed_at: Rect2 = _viewfinder.get_global_rect()
	var chrome: Array[Control] = [_caption, _shutter, _status, _summary]
	for made: Control in chrome:
		if made != null:
			made.visible = false
	# The frame has to be *drawn* without the chrome before it is read, or the grab is of the page as it was
	# a frame ago - with the button on it.
	await RenderingServer.frame_post_draw
	var grabbed: Image = _grab(aimed_at)
	for made: Control in chrome:
		if made != null:
			made.visible = true
	if grabbed == null:
		_say("the frame could not be read")
		return ""
	var written: Error = grabbed.save_png(CameraCaptureScript.FRAME_PATH)
	if written != OK:
		_say("the frame could not be written: %s" % error_string(written))
		return ""
	var kept: Dictionary = PhotoStoreScript.add(CameraCaptureScript.FRAME_PATH, folder)
	if not bool(kept.get("ok", false)):
		_say(String(kept.get("reason", "the photograph could not be kept")))
		return ""
	var path: String = String(kept.get("path", ""))
	_say("kept %s" % path)
	photo_taken.emit(path)
	return path


## Whether there is a picture to take, and the page's own words for why there is not.
func ready_to_shoot() -> bool:
	if not permitted():
		_say(CameraCaptureScript.refusal(1, false))
		return false
	if _texture == null or feed == null:
		_say(CameraCaptureScript.refusal(_feed_count(), true))
		return false
	return true


## How many cameras the device has answered with, or none when nothing is being watched yet: a server that is
## not monitoring refuses to be asked, and before the page opens there is nothing to report.
func _feed_count() -> int:
	if not CameraServer.monitoring_feeds:
		return 0
	return CameraServer.get_feed_count()


## Grab the part of the rendered page the viewfinder occupies.
func _grab(aimed_at: Rect2) -> Image:
	var drawn: ViewportTexture = get_texture()
	if drawn == null:
		return null
	var whole: Image = drawn.get_image()
	if whole == null:
		return null
	var region: Rect2i = CameraCaptureScript.frame_region(aimed_at, _drawn_at())
	var inside: Rect2i = Rect2i(Vector2i.ZERO, whole.get_size())
	var overlap: Rect2i = region.intersection(inside)
	if overlap.size.x <= 0 or overlap.size.y <= 0:
		return null
	return whole.get_region(overlap)


## How many pixels one layout pixel is drawn at, which is what turns the viewfinder's rectangle into the
## part of the rendered frame to keep.
func _drawn_at() -> float:
	var shown: Vector2 = get_visible_rect().size
	if shown.x <= 0.0:
		return 1.0
	return maxf(float(size.x) / shown.x, 1.0)


# --- what it shows ------------------------------------------------------------------------------


## The shutter's state and the words for it, re-read whenever something may have changed.
func _show_state() -> void:
	if _shutter == null:
		return
	var can_shoot: bool = permitted() and _texture != null and feed != null
	_shutter.disabled = not can_shoot
	if feed != null:
		_summary.text = "The camera is showing; the shutter keeps a copy where this program keeps pictures."
	elif not permitted():
		_summary.text = CameraCaptureScript.refusal(1, false)
	elif not CameraServer.monitoring_feeds:
		# Nothing has been looked for yet, because the page has not been opened. Asking a server that is not
		# watching anything refuses out loud, and there is no true answer to give about the device yet.
		_summary.text = OPENING
	else:
		_summary.text = CameraCaptureScript.refusal(_feed_count(), true)


func status_text() -> String:
	return _status.text if _status != null else ""


func summary_text() -> String:
	return _summary.text if _summary != null else ""


func shutter_button() -> Button:
	return _shutter


func caption_text() -> String:
	return _caption.text if _caption != null else ""


func say(words: String) -> void:
	_say(words)


func _say(words: String) -> void:
	if _status != null:
		_status.text = words


# --- stepping -----------------------------------------------------------------------------------


func _process(_delta: float) -> void:
	if _column == null or not visible:
		return
	# A phone can be turned while the page is open and the window turns with it, so which way round the
	# picture has to stand is re-read rather than remembered - the one thing here that changes without
	# anything being pressed.
	var screen: int = int(DisplayServer.screen_get_orientation())
	if screen != _screen:
		_screen = screen
		_set_the_turn(_material())
		_caption.text = _caption_line()
	# A camera that has not been allowed is not switched on. Android lists its cameras before the permission
	# is granted, so a page that attached on the first frame it saw would draw the device's raw planes over a
	# program somebody had not said yes to.
	if not permitted():
		_ask_for_the_camera()
		if _shutter != null and not _shutter.disabled:
			_show_state()
		return
	if feed == null:
		if _waiting < WAITING_FRAMES:
			_waiting += 1
			if attach():
				return
			if _waiting % 30 == 0:
				_show_state()
		return
	# The picture is the feed's own business; only the shutter's readiness is re-read, and only when it could
	# have changed.
	if _shutter != null and _shutter.disabled == permitted():
		_show_state()


func _on_shutter_pressed() -> void:
	take_photo()


## Put the camera away and stop looking at it. The one place this page hides itself, so that every way out -
## the Close button, Escape through `close_requested`, the title bar's cross, or a menu - leaves the same
## state: the page gone and the device's camera no longer being watched.
func request_close() -> void:
	shut()
	hide()
	closed.emit()


func _on_close_requested() -> void:
	request_close()