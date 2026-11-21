class_name PlannerHud
extends CanvasLayer
## The planner's heads-up display: the menu bar, which view you are in and the controls that change it,
## the drawing palette, the panels that are always on screen, and the drafting aids on the overlay layer.
##
## The chrome here is not the same shape on every device. A row of controls, a palette and a window are laid
## out for a desk, where the room is wide and a fingertip is a cursor; a device answered with a finger is
## given the row a thumb has to hit in and the size a thumb has to read, so what a desk draws exactly as the
## scene did can be a different arrangement there. `PhoneHud` holds the arithmetic and the door,
## `size_for_a_finger` is where this HUD asks for it, and `_put_away_what_the_top_bar_cannot_hold` is the one
## part of the top bar that a room too narrow for it gives up.

const DraftToolScript := preload("res://scripts/draft/draft_tool.gd")
const SelectScript := preload("res://scripts/draft/draft_select.gd")
const DraftControllerScript := preload("res://scripts/draft/draft_controller.gd")
const SimplifyReportScript := preload("res://scripts/draft/simplify_report.gd")
const PresenceScript := preload("res://scripts/presence.gd")
const StartChoicesScript := preload("res://scripts/start_choices.gd")
const StartWindowScript := preload("res://scripts/pages/start_window.gd")
const StartDrawingScript := preload("res://scripts/start_drawing.gd")
const StartDrawingWindowScript := preload("res://scripts/pages/start_drawing_window.gd")
## What is on the screen, said out loud, on a build that may be driven from another computer: the figures a
## driver would otherwise have to read off a screenshot.
const HudProbeScript := preload("res://scripts/hud_probe.gd")
const ChromeStyleScript := preload("res://scripts/chrome_style.gd")
const BoardPanelScript := preload("res://scripts/board_panel.gd")
const CameraWindowScript := preload("res://scripts/pages/camera_window.gd")
const OrientationChoiceScript := preload("res://scripts/orientation_choice.gd")
## The reader's own choice of how big the words are drawn, where the platform states none.
const ReadingSizeScript := preload("res://scripts/reading_size.gd")

## How much space sits between two parts of a hint line, so a line reads as groups of words rather than
## as one run of them.
const HINT_GAP := "     "

const EDIT_HINTS := "Left-drag: move a plant     "
## The key that swaps the two overhead views is written as a token and filled in
## from the input map: it is the one key in these lines that gets rebound, and a
## hint naming a key that no longer switches anything is the same class of lie as a
## legend entry that does nothing.
const VIEW_KEY_TOKEN := "%VIEW%"
const HINTS_2D := EDIT_HINTS + "Right-drag: pan     Wheel: zoom     W A S D: pan     F: fit     %VIEW%: 3D view     G: ground"
const HINTS_3D := EDIT_HINTS + "Right-drag: pan     Wheel: zoom     W A S D: pan     F: fit     %VIEW%: 2D plan     G: ground"
const HINTS_GROUND := "W A S D: walk     Shift: run     Mouse: look     Arrows: look     Esc: free cursor     G: back to overhead"
## The ground view's line on a device answered with a finger: **the two gestures that really drive it**,
## because there is no keyboard there and no captured mouse, and a phone told "Mouse: look" has been told
## nothing at all. Chosen by `shows_touch_controls()` - the same reading that decides whether the thumb pad
## is built - so the line and the controls it names arrive and leave together.
const HINTS_GROUND_ON_A_FINGER := "Left thumb: walk     Right thumb: drag"
## The overhead views' line on a device answered with a finger. There is no wheel to turn there and no W A S D
## to press, and a phone told "Wheel: zoom" has been told nothing at all; what a finger really drives is the
## pair `ViewController.touch_command` reads - a pinch, which is a zoom about the fingers, and two fingers
## dragged together, which is a pan - together with the tool in hand, which is the same words a desk gets.
## Fitting the garden is a tap on the menu bar's own Fit button and is not named here, because the bar is one
## thumb's width from this line and a key is not. Chosen by `shows_touch_controls()`, the same reading that
## decides whether the thumb pad is built and whether the ground view's line is swapped, so every line a
## device is shown arrives and leaves with the controls it names.
const HINTS_OVERHEAD_ON_A_FINGER := EDIT_HINTS + "Two fingers: pan     Pinch: zoom"

## Where this program's own offers are written, and the files they live in: the drawing tools
## beside the tool that draws them, the editing commands beside the controller that runs them, and
## the sizes a still can be asked for beside the quality tiers. These three names are the same
## arrays rather than copies of them, so the legend, the palette, the menu and the help all read
## one table and none of them can describe a different tool from the one the key selects.
const DRAFTING_TOOLS: Array = DraftToolScript.DRAFTING_TOOLS
const EDIT_TOOLS: Array = DraftControllerScript.EDIT_TOOLS
const STILL_SIZES: Array = TierScript.STILL_SIZES


## The keys that are not a tool, in the order a hand meets them: what to do when
## the shape is right, and what to do when it is not.
const DRAFTING_COMMANDS: Array = [
	[&"draft_finish", "finish"],
	[&"draft_close", "close"],
	[&"draft_undo_point", "drop a point"],
	[&"draft_cancel", "cancel / close page"],
	[&"draft_undo", "undo"],
	[&"draft_redo", "redo"],
	[&"draft_plot", "plot"],
	[&"draft_dimension_style", "dimension standard"],
]

## How each of those keys reads beside the tool it answers: on the line at the foot of the screen, and in
## the box beside the plan. Shorter than the reference's wording for the same action, because these share a
## line with the tool's own prompt - "cancel / close page" is the reference's, where there is a row to
## itself.
##
## The *action* is the same action, and the key itself is read from the binding in both places, so the two
## cannot disagree about which key does it.
const HAND_KEY_WORDS := {
	&"draft_finish": "finish",
	&"draft_close": "close",
	&"draft_undo_point": "drop a point",
	&"draft_cancel": "cancel",
	&"draft_undo": "undo",
	&"draft_redo": "redo",
}

## Key names worth shortening so a legend line stays a line.
##
## `Period` is here because the angular dimension is bound to that key and Godot reads it back as the
## word rather than as the character: a legend row saying "Period angular dim" is both wider and harder
## to read than the key a person actually presses, which is a full stop.
const SHORT_KEY_NAMES := { "Escape": "Esc", "Return": "Enter", "Period": "." }

## How many entries share a line before the legend wraps.
const DRAFTING_TOOLS_PER_ROW := 5
const DRAFTING_COMMANDS_PER_ROW := 4
## The editing commands get their own line count. Eight of them still share one legend
## line, which is what the panel has room for: the panel is sized for six lines of text and
## a seventh would run off it, so a wider line is the cheaper of the two ways to say the
## same thing. The drawing tools' five across would have pushed the edits onto that seventh
## line, which is why the edits carry their own count rather than reusing the tools'.
const EDIT_TOOLS_PER_ROW := 8
const DRAFTING_ROW_GAP := "    "

## The keys that are neither a drawing tool nor an edit: the two pages a plan is made for and the
## ground's three tools.
##
## They are in the reference and not in the corner legend, and the reason is room rather than rank: the
## legend has six lines and is full, while the reference is the page a person opens to look a key up.
## Three across, so the six of them are two lines there.
const ELSEWHERE_KEYS: Array = [
	[&"plant_order", "order the plants"],
	[&"present_sun_study", "the sun and the shadows"],
	[&"grade_spot", "spot a level"],
	[&"grade_contour", "draw a contour"],
	[&"grade_slope", "draw a slope arrow"],
	[&"page_help", "what this page is about"],
]
const ELSEWHERE_PER_ROW := 3


## The client presentation: the budgets it can be shown at, and the sizes a proposal
## still is rendered at. Both are read from the tables that act on them rather than
## written here, so the picker cannot offer a tier or a size that does not exist.
const TierScript := preload("res://scripts/vis/presentation_tier.gd")
const DirectorScript := preload("res://scripts/vis/presentation_director.gd")
const PaintedPlanScript := preload("res://scripts/vis/painted_plan.gd")
## The garden as a model file. A picture of the yard is one thing and the yard is another: what a
## builder, a contractor or the next designer wants is the thing itself, and this is what writes it out.
const YardExporterScript := preload("res://scripts/vis/yard_exporter.gd")
const SunStudyScript := preload("res://scripts/vis/sun_study.gd")
## The study of the sun rather than the sun itself: `SunStudy` says where the sun is at one moment,
## `SunReport` says what a *list* of moments and a stated height come to. The page is a screen.
const SunReportScript := preload("res://scripts/vis/sun_report.gd")
const SunWindowScript := preload("res://scripts/pages/sun_window.gd")
const WalkWindowScript := preload("res://scripts/pages/walk_window.gd")
const SnapWindowScript := preload("res://scripts/pages/snap_window.gd")
const StatusWindowScript := preload("res://scripts/pages/status_window.gd")
const PageChromeScript := preload("res://scripts/pages/page_chrome.gd")
const PageLayoutScript := preload("res://scripts/pages/page_layout.gd")
const DrawnSurfacesScript := preload("res://scripts/drawn_surfaces.gd")
const PageHelpScript := preload("res://scripts/pages/page_help.gd")
const PlotScaleScript := preload("res://scripts/draft/plot_scale.gd")
const StoreScript := preload("res://scripts/draft/drawing_store.gd")
const SiteReportScript := preload("res://scripts/site_report.gd")
const SurveyFileScript := preload("res://scripts/draft/survey_file.gd")
const PlantLabelsScript := preload("res://scripts/plants/plant_labels.gd")

@export var view_controller: ViewController
## The presentation director. Absent in a scene that has no presentation, in which
## case the panel is not built at all rather than built full of dead buttons.
@export var presentation: DirectorScript
## The painted plan. Absent in a scene that cannot paint one, in which case the key
## does nothing rather than reporting a failure for a feature that is not there.
@export var painted_plan: PaintedPlanScript

@onready var mode_label: Label = %ModeLabel
## The bar's own decoration: the program's name, and the rule that was there only to divide it from the
## view's name. Two of the three things in the top bar that are there to look at rather than to use, and so
## two of the three the row gives up when the room cannot hold it - the third is the view's name, put away
## with these under `_put_away_what_the_top_bar_cannot_hold`.
@onready var app_label: Label = %AppLabel
@onready var bar_separator: VSeparator = %Sep
@onready var toggle_button: Button = %ToggleButton
@onready var ground_button: Button = %GroundButton
@onready var fit_button: Button = %FitButton
@onready var hints_label: Label = %HintsLabel
@onready var overlay: HudOverlay = %Overlay
@onready var draft_hints: PanelContainer = %DraftHints
@onready var draft_hints_label: Label = %DraftHintsLabel
@onready var palette: PanelContainer = %Palette
## The drawing palette's own controls, built by `_build_palette` out of the drawing and the keys. It is one
## member and it is the scene's node: a second name standing beside it, left null, is how this HUD came to
## build no palette at all while every check still passed.
@onready var palette_column: PalettePanelScript = %PaletteColumn
@onready var presentation_panel: PanelContainer = %Presentation
@onready var presentation_column: VBoxContainer = %PresentationColumn
@onready var painted_sheet: Control = %PaintedSheet
@onready var painted_picture: TextureRect = %Sheet
@onready var painted_caption: Label = %Caption
@onready var painted_actions: HBoxContainer = %PaintedActions
## The working furniture, found by path rather than by name: these two are old
## enough that giving them unique names would be a scene change for no reason.
@onready var top_bar: PanelContainer = get_node_or_null(^"Root/TopBar")
@onready var hints: PanelContainer = get_node_or_null(^"Root/Hints")
## The menu bar. In the scene, because where it sits among the top bar's controls is a layout
## decision; its menus are built in code from `menu_plan()`, because what is in them is derived
## from the tables that already describe those commands.
@onready var menu_bar: MenuBar = %MenuBar
## The furniture a finger gets and a desk does not: the row of controls that stands inside the top bar where
## the fourteen menus stand, and the dock along the foot of the screen. Both are in the scene and hidden, so a
## desk draws exactly what it always drew; `get_node_or_null` rather than `%` because a HUD built from a scene
## that has not been through this file's own scene file still has to load.
@onready var touch_row: HBoxContainer = get_node_or_null(^"Root/TopBar/Row/TouchRow") as HBoxContainer
@onready var touch_dock: PanelContainer = get_node_or_null(^"Root/TouchDock") as PanelContainer
@onready var touch_strip: PanelContainer = get_node_or_null(^"Root/TouchDock/Column/ToolStrip") as PanelContainer
@onready var touch_strip_row: HBoxContainer = get_node_or_null(^"Root/TouchDock/Column/ToolStrip/StripScroll/Strip") as HBoxContainer
@onready var touch_tabs: HBoxContainer = get_node_or_null(^"Root/TouchDock/Column/Tabs") as HBoxContainer
## The sheet a finger opens instead of a full page: the plant picker standing over the board rather than
## replacing it. A page is a `Window` the whole screen wide; a sheet is a plate the drawing stays visible
## around, which is what a person choosing a plant wants - the bed they are planting is still on the screen.
@onready var touch_sheet: PanelContainer = get_node_or_null(^"Root/TouchSheet") as PanelContainer
@onready var touch_sheet_title: Label = get_node_or_null(^"Root/TouchSheet/Column/Header/Title") as Label
@onready var touch_sheet_close: Button = get_node_or_null(^"Root/TouchSheet/Column/Header/Close") as Button
@onready var touch_sheet_body: VBoxContainer = get_node_or_null(^"Root/TouchSheet/Column/Body") as VBoxContainer

## The drafting controller, when the scene has one. Held because the palette drives
## it and the legend reports on it.
var _draft: DraftControllerScript = null
## The thumb controls a phone walks and looks with, built behind everything else. Null until they are
## built, which a scene with no `Root` never does.
var _touch_pad: TouchPad = null
## Whether this machine has a touchscreen, read once: asking the display server every frame would be a
## question whose answer cannot change while the program runs.
var _touch_screen: bool = false
## Set to offer the thumb controls on a machine that has none, so a demo tool can prove them on a desktop.
var _touch_forced: bool = false
## The two buttons the gesture demo asks this HUD for by name. Doors onto `PalettePanel` rather
## than copies of it, so there is one undo button on the screen and this is it - computed rather
## than kept, because the panel holds it and the two may not be allowed to drift apart.
##
## Nothing in this file reads them: the reader is the gesture demo, which is out in `tools/` where the
## compiler cannot see it. Said out loud rather than left for a reader to wonder whether they are dead.
@warning_ignore("unused_private_class_variable")
var _undo_button: Button:
	get:
		return null if palette_column == null else palette_column.undo_button()
## And the same door for the other one.
@warning_ignore("unused_private_class_variable")
var _redo_button: Button:
	get:
		return null if palette_column == null else palette_column.redo_button()

## The controls built by _build_presentation_panel, kept so the refresh can set them.
var _present_toggle: CheckButton = null
var _tier_option: OptionButton = null
var _sun_hour: SpinBox = null
var _sun_day: SpinBox = null
var _sun_latitude: SpinBox = null
var _sun_longitude: SpinBox = null
var _sun_utc_offset: SpinBox = null
var _still_size_option: OptionButton = null
var _still_status: Label = null
## What the presentation panel was last drawn to match.
var _presentation_state: String = ""
## Whether a client presentation is running. Held here because the HUD is what
## decides which of its own furniture belongs in a presentation.
var _presenting: bool = false
## Whether the presentation panel is wanted on the screen. Held here rather than read from the node
## because a person can put it away, and the panel is otherwise on whenever the scene has a director.
## On a phone it is over a third of the width and its last rows fall off the bottom of the screen, so it
## **starts put away** there - it is the one place latitude, longitude and the zone are edited, and the
## Present menu's own row is what brings it back, which is why it may start out of the way at all.
var _presentation_panel_wanted: bool = true
## Whether the panel's start has already been decided for the device this HUD is on. It is settled where
## the chrome is first sized and never again, so that a person who brings the panel back keeps it back.
var _presentation_panel_started: bool = false

## The painted plan on screen, held rather than rendered again when it is saved:
## looking at the picture and filing it are two decisions, and the second one should
## file the picture that was looked at.
var _painted_image: Image = null
## The button that files it, kept so it can be switched off while there is nothing
## to file.
var _painted_save: Button = null

## The menu bar's entries, per popup, in the order they were added. A PopupMenu item's id is its
## index, so this is the way back from a press to the entry that describes it.
var _menu_items: Dictionary[PopupMenu, Array] = { }
## What the menu was last drawn to match, so a check every frame does not restate state that has
## not moved.
var _menu_state: String = ""
## The room the bar was last folded for, so the check that runs every frame rebuilds the bar only when
## the room actually changes rather than on every frame. Zero means no room has been worked out yet.
var _menu_room: float = 0.0
## The titles the bar is built from, so a fold that would not change them is not worth a rebuild.
var _menu_titles: Array[String] = []
## The offsets the scene drew the top bar with, remembered the first time the chrome is sized for a device.
## Infinity until then, which is a value no offset can hold.
##
## **Kept because the pass that uses it runs again on every turn.** Lifting the bar clear of a phone's own
## furniture writes the bar's offsets, so a second pass that read them back and lifted again would walk the bar
## down the screen one rotation at a time. What the lift adds to is what the scene drew.
var _bar_offsets_as_drawn: Vector2 = Vector2(INF, INF)
## The offsets the scene drew the palette with, remembered the first time the left column is placed for a
## device, and for the same reason: that pass runs again on every change of the room's shape, so a placement
## measured from its own output would walk the palette up the screen one turn at a time. Infinity until then,
## which is a value no offset can hold.
var _palette_offsets_as_drawn: Vector2 = Vector2(INF, INF)
## The key reference, built by `_build_keys_panel`: the wrapper that places the page, held so the
## one place that decides whether it is up is the panel's own `visible`.
var _keys_panel: Control = null
## The manual: what this program is and everything it does, in one page with a search box. A window
## like the other pages, and for the one reason a window exists in this HUD - it has a field to search
## it with, and a text field is the one thing the HUD may not own outside a window.
var _help_window: HelpWindow = null
## The command palette: the whole bar in one box with a field to type into. A window like the manual,
## and for the same reason - it has a field, and a text field is the one thing the HUD may not own
## outside a window. It holds none of the bar itself: what is in it is read from `menu_plan()` every
## time it opens, so a command cannot appear in one and be missing from the other.
var _command_palette: CommandPalette = null
## The site-stats page, built by `_build_site_report_panel` and shown from the Site menu.
var _site_report_panel: Control = null
## The survey import page, built by `_build_survey_panel`. A survey is read and *shown* before it
## is put on the drawing, so the page holds the survey that is waiting for an answer.
var _survey_panel: Control = null
var _pending_survey: Dictionary = { }
## The survey file chooser. A survey is a file somebody else sent, so it is read wherever it
## lives rather than out of the app's own folder.
var _survey_dialog: FileDialog = null
## Whether the line of control hints is wanted at the bottom of the screen. Held here rather than
## read from the node, because a presentation takes the hints away and has to give them back the
## way the person left them.
var _show_hints: bool = true

## The shared session, when this scene has one. Found by path rather than exported, so a scene
## without a session - every window test, and any scene that is not the planner - simply has none.
var _presence: PresenceScript = null

## The file dialogs, and the question asked before work is thrown away.
var _open_dialog: FileDialog = null
var _save_dialog: FileDialog = null
var _discard_dialog: ConfirmationDialog = null
## The auto-simplify question: what the pass would do, before it does it. The plan is held
## while the dialog is up so that confirming applies the very pass that was shown, not a
## fresh one worked out against a drawing that may have moved under it.
var _simplify_dialog: ConfirmationDialog = null
var _pending_simplify: SimplifyReportScript = null
## The recovery question: what a session that ended without saving left behind, before it goes back on
## the drawing. A question rather than an automatic restore, because both answers are reasonable and a
## restore nobody was asked about is the one thing a recovery feature must not do.
var _recovery_dialog: ConfirmationDialog = null
## The copy that is waiting, read off disk when something changes rather than on every frame: the menu
## world is built every frame and a directory listing is not something a frame may do.
var _pending_recovery: Dictionary = { }
## How long the drawing has been worked on since the last copy was kept, in seconds.
var _autosave_clock: float = 0.0
## What to do once the unsaved-changes question has been answered. Held as an id rather than as a
## Callable so that a dialog left open while something else happens cannot run a stale action out
## of a captured closure.
var _pending_action: StringName = &""
## The file an action is about, when it is about one: opening a drawing from the recent list.
var _pending_path: String = ""
## The submenu of recently opened drawings, and what it was last filled with: it is the one part
## of the bar whose *entries* change rather than only their ticks.
var _recent_popup: PopupMenu = null
var _recent_filled: String = ""

## The plant list: JSON under `user://plants`, seeded on the first run from the list the project
## ships with, for the same reason the cost book is JSON - a catalogue is four thousand entries a
## nursery mails you as a spreadsheet, not four thousand `.tres` files (spec §2.3).
const PlantCatalogueScript := preload("res://scripts/plants/plant_catalogue.gd")
const PlantBrowserScript := preload("res://scripts/plants/plant_browser.gd")
const PlantPanelScript := preload("res://scripts/plants/plant_panel.gd")
const ToolPaletteScript := preload("res://scripts/tool_palette.gd")
const PalettePanelScript = preload("res://scripts/palette_panel.gd")
const PlantSuitabilityScript := preload("res://scripts/plants/plant_suitability.gd")
const TerrainProfileScript := preload("res://scripts/terrain_profile.gd")
const ZoneMapScript := preload("res://scripts/zone_map.gd")
const GroundWindowScript := preload("res://scripts/pages/ground_window.gd")
const SheetWindowScript := preload("res://scripts/pages/sheet_window.gd")
const RevisionWindowScript := preload("res://scripts/pages/revision_window.gd")
const HelpDocScript := preload("res://scripts/help_doc.gd")
const HelpWindowScript := preload("res://scripts/pages/help_window.gd")
const CommandPaletteScript := preload("res://scripts/command_palette.gd")
const PageEscapeScript := preload("res://scripts/pages/page_escape.gd")
const AutosaveScript := preload("res://scripts/draft/autosave.gd")
const DxfFileScript := preload("res://scripts/draft/dxf_file.gd")
const OsmFileScript := preload("res://scripts/draft/osm_file.gd")
const LandXmlFileScript := preload("res://scripts/draft/landxml_file.gd")
const OsmFetchScript := preload("res://scripts/draft/osm_fetch.gd")
const OsmWindowScript := preload("res://scripts/pages/osm_window.gd")
const RasterUnderlayScript := preload("res://scripts/draft/raster_underlay.gd")
const UnderlayWindowScript := preload("res://scripts/pages/underlay_window.gd")
const GradingWindowScript := preload("res://scripts/pages/grading_window.gd")
const GradingScript := preload("res://scripts/draft/grading.gd")
const UnitsScript := preload("res://scripts/draft/units.gd")
const IrrigationScript := preload("res://scripts/draft/irrigation.gd")
const LightingScript := preload("res://scripts/draft/lighting.gd")

## The units a person may tell an imported file it is in, when the file does not say. The empty one
## means "as the file says"; the rest are names both the DXF reader and the LandXML reader know, kept
## short because this is a drop-down. One list rather than one per reader: the question is the same
## question and the answer is the same word, and two lists of the same words is how they drift.
const IMPORT_UNIT_CHOICES: Array[String] = [
	"",
	"metres",
	"feet",
	"inches",
	"millimetres",
	"centimetres",
	"yards",
	"US survey feet",
]
const EstimateWindowScript := preload("res://scripts/pages/estimate_window.gd")
const PipelineBoardScript := preload("res://scripts/pipeline_board.gd")
const ScheduleBoardScript := preload("res://scripts/schedule_board.gd")
const JobCostWindowScript := preload("res://scripts/pages/job_cost_window.gd")
const JobDeskScript := preload("res://scripts/biz/job_desk.gd")
const BillingDeskScript := preload("res://scripts/biz/billing_desk.gd")
const BillingWindowScript := preload("res://scripts/pages/billing_window.gd")
const LedgerDeskScript := preload("res://scripts/biz/ledger_desk.gd")
const LedgerWindowScript := preload("res://scripts/pages/ledger_window.gd")
const AkauntingLedgerScript := preload("res://scripts/biz/akaunting.gd")
const InvoiceNinjaLedgerScript := preload("res://scripts/biz/invoice_ninja.gd")
const CloseoutDeskScript := preload("res://scripts/biz/closeout_desk.gd")
const LayerWindowScript := preload("res://scripts/pages/layer_window.gd")
const SyncWindowScript := preload("res://scripts/pages/sync_window.gd")
const BizStoreScript := preload("res://scripts/biz/store.gd")
const BizSyncScript := preload("res://scripts/biz/sync.gd")
const BizHttpTransportScript := preload("res://scripts/biz/http_transport.gd")
const CloseoutWindowScript := preload("res://scripts/pages/closeout_window.gd")
const AnalyticsScript := preload("res://scripts/biz/analytics.gd")
const AnalyticsWindowScript := preload("res://scripts/pages/analytics_window.gd")
const PlantPlacementScript := preload("res://scripts/plants/plant_placement.gd")
const PlantSpacingScript := preload("res://scripts/plants/plant_spacing.gd")
## The nursery order: the drawing's planting list and the price list turned into what to buy, and from
## whom. The arithmetic is business arithmetic, so the module lives with the business modules; the page
## is a screen, so it does not.
const PlantOrderScript := preload("res://scripts/biz/plant_order.gd")
const PlantOrderWindowScript := preload("res://scripts/plants/plant_order_window.gd")
const FoodWindowScript := preload("res://scripts/pages/food_window.gd")
const RotationWindowScript := preload("res://scripts/pages/rotation_window.gd")
const HarvestWindowScript := preload("res://scripts/pages/harvest_window.gd")
const GrowingSeasonScript := preload("res://scripts/growing_season.gd")
const SeasonWindowScript := preload("res://scripts/pages/season_window.gd")
const FieldCaptureWindowScript := preload("res://scripts/pages/field_window.gd")
const PlantKeyWindowScript := preload("res://scripts/plants/plant_key_window.gd")
const SowingWindowScript := preload("res://scripts/pages/sowing_window.gd")
const YieldWindowScript := preload("res://scripts/pages/yield_window.gd")
const PhoneFilesScript := preload("res://scripts/phone_files.gd")
const PhoneHudScript := preload("res://scripts/phone_hud.gd")
## Which way up this window's own shape is, which is the one part of a fold's posture that can be read: see
## the file, and `_say_the_screen` below, which reports it beside the device.
const WindowPostureScript := preload("res://scripts/window_posture.gd")
## What a control a finger presses looks like in each state, and what one that cannot be pressed looks like:
## see the file. Worn by this HUD's own `Root` control here, and by every page where `PageChrome` lands it.
const TouchStyleScript := preload("res://scripts/touch_style.gd")
const STARTER_PLANT_LIST := "res://data/plants/nursery_list.json"

## The plant list once it has been read, held because it is a file: a menu that read four thousand
## species in order to write one line on itself would be a menu nobody could use.
var _plants: PlantCatalogue = null
## How many entities the palette's bed list was read from. The list is a *menu of what can be filled*
## and not the source of the outline that is filled: `_on_plant_fill_bed` reads the drawing again when
## the button is pressed, so a bed that has been moved since the list was built still fills at its new
## outline. That is what makes it safe to re-read on a count rather than every frame, which matters
## because an area row carries the outline of its entity and a HUD that allocated a ring of points per
## bed sixty times a second would be a HUD nobody could draw in.
var _beds_from_count: int = -1
## The library: the window, the browser inside it, and the two dialogs a plant list arrives and
## leaves by. The window is a `Window` rather than a panel in `Root` on purpose - it is the one
## boundary at which something in this HUD is allowed to hold the keyboard, which is what makes the
## search box typeable without taking W A S D away from the design.
var _plant_window: Window = null
var _plant_browser: PlantBrowser = null
var _plant_import_dialog: FileDialog = null
var _plant_export_dialog: FileDialog = null
## The ground: one window, because the site's conditions and the conditions of every area of the plan
## are one subject, and a menu cannot hold an area.
var _ground_window: GroundWindow = null
## The drawing's layers: every layer, what it is for, and the two things done to one from it - lock it
## or make it current. A window because it has a search box to type into.
var _layer_window: LayerWindowScript = null
## The business records' store and the engine that syncs them with the office's service. The store is
## where a field change is written; the engine holds the queue and the conflicts, and the page shows
## what it says. The one service this build offers is the HTTP transport, configured on the page.
var _sync_store: BizStoreScript = null
var _sync_engine: BizSyncScript = null
var _sync_window: SyncWindowScript = null
## The sheet setup: what this drawing goes out on, and the set of sheets it goes out as. A window
## because it is the one surface here that takes typed text - a drawing number, a title, a revision.
var _sheet_window: SheetWindow = null
## The history: what was recorded against this drawing and what each revision changed. A window for the
## same reason the sheet setup is one - a revision needs a message, and a message is typed text.
var _revision_window: RevisionWindow = null
## What the last refresh of that window was drawn from: the drawing's name, how many revisions are kept,
## how many fell off the end, and the gesture the drawing has been through. The last of those is what the
## "Done since" line is worked out from, so a window left open while a designer keeps drawing is
## refreshed as the count moves - a line that still read "nothing has been done" two gestures later
## would not be an old answer, it would be a wrong one.
var _revision_state: String = ""
## The DXF import: the chooser, the file's own text (kept, so answering "what units is it in" can read
## it again), and the page that says what was read before the drawing takes it.
var _dxf_dialog: FileDialog = null
var _dxf_panel: Control = null
var _dxf_text: String = ""
var _dxf_name: String = ""
var _dxf_units: String = ""
var _pending_dxf: Dictionary = { }
## Where the drawing goes out as a DXF. A dialog of its own rather than the import's, because the two
## commands are opposites - reading a file in and writing the drawing out - and a person who reached
## for the wrong one should not have to work it out from the file mode.
var _dxf_export_dialog: FileDialog = null
## Where the yard goes out as a model. A dialog of its own for the same reason the DXF's is: this is
## the other thing that leaves the program for somebody else's software, and it is a save rather than
## an import like every dialog above it.
var _model_export_dialog: FileDialog = null
## The LandXML import: the same three pieces the DXF import has, because it is the same act - somebody
## else's file, read into something to trace over, with the one question a file that does not say its
## units has to be asked.
var _landxml_dialog: FileDialog = null
var _landxml_panel: Control = null
var _landxml_text: String = ""
var _landxml_name: String = ""
var _landxml_units: String = ""
var _pending_landxml: Dictionary = { }
## The OpenStreetMap import: the chooser for a saved extract, the window that holds the site's
## coordinates and the radius, and the reader that can reach the network. The map is somebody else's
## data over a network, so the reading and the asking are two modules rather than one, and this is
## where the two meet.
var _osm_dialog: FileDialog = null
var _osm_window: OsmWindow = null
var _osm_fetch: OsmFetch = null
var _pending_osm: Dictionary = { }
## A picture under the drawing: the chooser for the file itself, the page that says how far it lies
## across the ground, and the record in hand of a picture that has been read and kept but is not yet
## under the drawing. The counterpart of the DXF, map and LandXML readers, for the file that has no
## linework in it to read - a scan, an aerial photograph, a rendered concept.
var _underlay_dialog: FileDialog = null
var _underlay_window: UnderlayWindow = null
var _pending_picture: Dictionary = { }
## Why the file in hand was not read. Kept apart from the record because a refusal has no record, and
## the page has to be able to say what was wrong with what somebody chose.
var _picture_refusal: String = ""
## The ground's own heights: the level in hand, the three tools that stamp it, and the check that says
## whether the drawing's levels, contours and arrows agree with each other. A window, because a level is
## typed.
var _grading_window: GradingWindowScript = null
## What the last refresh of that page was drawn from: the drawing's gesture serial and the grading
## records themselves. The page lists what the drawing holds and reports on it, so a page left open
## through an undo - which does not go past this HUD - would otherwise be showing records that are no
## longer on the drawing.
var _grading_state: String = ""
## The front door: the sheet the two doorway pages stand on, the door itself, and the begin-a-drawing page
## that replaces it once the drawing board is chosen. Built once and kept, like every other page here.
var _front_door_backdrop: ColorRect = null
var _start_window: StartWindow = null
var _start_drawing_window: StartDrawingWindow = null
## The camera, opened *over* the door rather than instead of it.
var _camera_window: CameraWindow = null
## Which way up the *board* asks the window to be. The doorway does not use it: while one of the two
## doorway pages is up the window follows the phone, which `OrientationChoice.DOORWAY` is. Read from disk
## at launch, and set here rather than read in a test that only wants to hold the doorway's decision.
var _orientation: StringName = OrientationChoiceScript.DEFAULT
## How big the words are drawn, as the reader asked for it. Read from disk where the program starts, and held
## here rather than read in a test that only wants to hold the menu's own state.
var _reading_size: StringName = ReadingSizeScript.DEFAULT
## The plants to buy: the drawing's planting list priced from the price list and written as draft
## purchase orders on the job desk. A window, because the nursery is typed.
var _plant_order_window: PlantOrderWindowScript = null
## What the last refresh of that page was drawn from: the planting rows and the desk's own counts. The
## page is about the yard and about the jobs, and either can move while it is open.
var _plant_order_state: String = ""
## When the yield page hands its household's count over, this is the plan the order page is about instead
## of the drawing's planting. Empty means the order is the drawing's own planting.
var _plant_order_plan_override: Dictionary = { }
## The food garden: what will crop in a bed, and which beds suit which crops. A window, because the
## question is what a *bed* and a *crop* come to together and a menu can hold neither.
var _food_window: FoodWindow = null
## What the last refresh of that page was drawn from: the ground's own beds and the site. Both can move
## under the page, so both are in the signature.
var _food_state: String = ""
## What to grow here next, and what grows well beside: the kitchen gardener's other question, and the
## one thing beside it that a drawing cannot answer - what grew in a bed last, which the page holds.
var _rotation_window: RotationWindow = null
## What the last refresh of that page was drawn from: the ground's own beds, by name.
var _rotation_state: String = ""
## What is ready when: the year as twelve lists of crops, one month at a time - the most direct reading
## of the one food fact the catalogue always has, a crop's harvest window.
var _harvest_window: HarvestWindow = null
## What the last refresh of that page was drawn from: the plant list's own crops and their windows.
var _harvest_state: String = ""
## How long the season is: the site's own frost dates and which food crops have time to finish
## between them. A window, because the dates are typed; and the one food page that *writes* to the
## drawing, because a frost date is a fact about the site that no drawing can supply.
var _season_window: SeasonWindow = null
## What the last refresh of that page was drawn from: which drawing is open and the season it states.
var _season_state: String = ""
## Recording what is standing on site: the one page here that writes to the survey file rather than
## reading the drawing. It is the person's door - a phone's manifest is the other one - and it is the
## reason a garden somebody walked round can be put on the plan with no phone involved at all.
var _capture_window: FieldCaptureWindowScript = null
## Naming a plant by answering questions about it: the other door onto a name, beside the photograph a
## phone can read. It reaches the catalogue rather than the drawing, like the field page, and it ends by
## arming the plant the way the library does - so naming a plant is never a third way of choosing one.
var _plant_key_window: PlantKeyWindowScript = null
## When to sow and how to keep it coming: the growing season read as a sowing calendar - a day to sow, a
## crop to sow, and the succession that repeats it. A window, because the day and the interval are
## typed; it reads the drawing's season but writes nothing, so it is the season page's reading half.
var _sowing_window: SowingWindow = null
## What the last refresh of that page was drawn from: the drawing's season and the plant list's crops.
var _sowing_state: String = ""
## How much to plant: the same plant list asked a household's question - how many plants it takes to feed
## a given number of people. A window, because the people and the spare are typed; it reads the list and
## nothing else, so it needs no drawing at all.
var _yield_window: YieldWindow = null
## What the last refresh of that page was drawn from: every crop's yield and share of one person.
var _yield_state: String = ""
## The study of the sun: a list of moments, and what the height in hand casts at each. A window,
## because the height is typed and the study is built out of the fields.
var _sun_window: SunWindowScript = null
## The walk-through: the places a client is shown, and the clock that walks the presentation camera
## through them. A window, because the walk is played from it and the camera belongs to the scene.
var _walk_window: WalkWindowScript = null
## The snapping settings: what the cursor may snap to, and the constraints that hold it straight.
## A window, because it is a page of switches rather than a line of the legend, which is full.
var _snap_window: SnapWindowScript = null
## What the last refresh of that page was drawn from: the site the study is of, and the size of the
## study. The page holds the list, so a refresh that rebound it every frame would be the page arguing
## with the hand that is building it.
var _sun_state: String = ""
## What the drawing has said, kept: the page that reads back the answers the status line has moved on
## from. It owns nothing - the history is the drawing's own, kept by the controller.
var _status_window: StatusWindowScript = null
## The study being rendered, one still at a time: the moments, the name each still takes, and how far
## the walk has got. A small state machine rather than a loop that awaits, because the director renders
## in real frames and reports by signal, so the next moment is started by the previous one landing.
var _sun_render_moments: Array = []
var _sun_render_names: Array[String] = []
var _sun_render_index: int = 0
var _sun_render_written: int = 0
var _sun_render_refused: int = 0
## Whether a still this HUD asked for is in flight, so a still the panel's own button asked for is not
## counted as one of the study's.
var _sun_render_waiting: bool = false
## The takeoff and the estimate: one window, because the three tables it holds - what the plan
## measures, what that prices at, and the price list it came from - are one job.
var _estimate_window: EstimateWindow = null
## The sales pipeline: the board of leads. Business data rather than drawing data, so it is here in
## every scene, not only the ones with a plan open.
var _pipeline_board: PipelineBoard = null
## The jobs and the crews and their days: the desk that holds them, and the board that shows them.
## Business data like the pipeline, so it is here in every scene too, and a job is made from an
## estimate - which is why the estimate window is the door to it.
var _job_desk: JobDesk = null
var _schedule_board: ScheduleBoard = null
## What a job has cost: the budget, what is committed and what has actually been spent. The third
## window onto the same desk, and the one that answers the question the desk's line only hints at.
var _cost_window: JobCostWindow = null
## What has been billed: the schedules a job is billed by, the invoices that went out and the money
## that came in. The fourth window onto the same desk, and the one the cost report deliberately leaves
## alone - §8.4's billed figure is a number somebody states, and §9's is a document (§9).
var _billing_ledger: BillingDesk = null
var _billing_window: BillingWindow = null
## The outbox: what has been handed to a ledger, and what each ledger said about it. Pointed at the
## billing desk, because what an office hands over is the documents that desk holds.
var _ledger_desk: LedgerDesk = null
var _ledger_window: LedgerWindow = null
## Finishing the job: the punch list, the day the garden was handed over and the warranty that runs
## from it. The fifth window onto the same desk - and the last thing about a job, which is why it is
## the last entry in the Jobs menu.
var _closeout_desk: CloseoutDesk = null
var _closeout_window: CloseoutWindow = null
## The report: the figures of §10 over the three desks above. It holds nothing of its own - every
## figure is recomputed from the records for the window and the moment it is asked about - so there is
## nothing here to keep in step with the desks, only a page that reads it again.
var _analytics_report: Analytics = null
var _analytics_window: AnalyticsWindow = null
## The species the last choice armed, so "place it again" has something to place.
var _plant_chosen: StringName = &""
## The plants section of the palette, thrown in under the drawing tools. The library is where a
## catalogue of four thousand is searched; this is where the one plant you already know you want is
## reached, one click, without a window, a menu or a key in the way.
var _plant_panel: PlantPanel = null
## Hatching a region: the page over the drawing and the panel of choices in it. A page rather than a
## window, like the survey report, because it opens over the drawing it is about and must not take
## the keyboard away from it.
var _hatch_page: Control = null
var _hatch_panel: HatchPanel = null
## Watering an area: the page over the drawing and the panel of choices in it, built the way the hatch
## page is and for the same reason.
var _water_page: Control = null
var _water_panel: IrrigationPanel = null
## Lighting an area: the page over the drawing and the panel of choices in it, built the way the water
## page is and for the same reason.
var _light_page: Control = null
var _light_panel: LightingPanel = null


func _ready() -> void:
	if view_controller == null:
		push_error("PlannerHud: view_controller must be assigned.")
		return
	# Godot accepts the window manager's close request on its own, so the flag is lowered here - where
	# the question about unsaved work lives - and `_notification` below answers it. Two things make
	# that safe: a scene with no HUD keeps the default and still closes, and the guard fails open, so
	# a drawing with work to lose but no dialog to ask with is quit rather than held.
	#
	# Not in the editor's embedded game, which has no close button of its own: holding the request
	# there is documented not to cooperate with the editor, and there is nothing to catch.
	if not Engine.is_embedded_in_editor():
		get_tree().auto_accept_quit = false
	# What a press looks like, and what a control that cannot be pressed looks like - the two things a thumb
	# has no other way of being told, since a finger has no hover to light a control up before it lands.
	#
	# It goes on this HUD's own `Root` control, which is the one carrier the board has. A theme lookup walks
	# up the tree from each control and settles on the first theme it meets, but a `CanvasLayer` **stops that
	# walk** - measured, and it is where this was first put: `get_tree().root` reaches nothing inside this
	# layer. The pages are the other carrier, and they are not this function's business: a page is a `Window`
	# beside `Root`, and `PageChrome` hands it the same style where the page lands.
	TouchStyleScript.apply_to(get_node_or_null(^"Root"))
	# Whether the thumb controls are worth offering is the same question the layout is sized by, asked the
	# same way: a finger *and* a density that says the row a desk was drawn with is too small to hit.
	# `DisplayServer.is_touchscreen_available()` alone was the wrong signal - a touchscreen laptop wants its
	# desk-sized controls, and the density is the thing that tells the two apart.
	# This answer is an early best guess and no more: a window that has not laid out yet does not answer for
	# the device it will be drawn on, so `_size_the_chrome_for_the_device` asks the same question again where
	# the chrome is really sized. On a computer the two answers agree, and nothing is touched either way.
	_touch_screen = PhoneHudScript.on_a_finger_here()
	view_controller.view_mode_changed.connect(_on_view_mode_changed)
	# A page is a position, not an anchor, so a page that is up through a change of the room's shape has to
	# be put back where it belongs: on a phone that is a turn, on a desk a resize or the editor's own pane.
	# The change watched is the viewport's, because that is the room a page is placed in.
	get_viewport().size_changed.connect(_the_canvas_changed_shape)
	view_controller.transition_started.connect(_on_transition_started)
	view_controller.transition_finished.connect(_on_transition_finished)
	toggle_button.pressed.connect(view_controller.toggle_overhead)
	ground_button.pressed.connect(view_controller.toggle_ground)
	fit_button.pressed.connect(view_controller.fit_plan_to_yard)
	# The box beside the plan is written by `_refresh_hints` with the line at the foot of it, from the tool
	# in hand: one writer for both, so arming a tool cannot leave the box describing the tool before it.
	_build_palette()
	_build_touch_pad()
	# The other half of the touch furniture: the row that stands where the menus stand and the dock along the
	# foot. Built after the palette, because every control the dock offers is a control the palette already made.
	_build_touch_furniture()
	_build_plant_panel()
	_build_presentation_panel()
	_build_painted_actions()
	# This HUD's own chrome is fitted to the device once everything it is made of exists - the menu bar, the
	# panels, the hint lines, the scale bar - and deferred for the same reason the palette is: a control built
	# during `_ready` is measured before the window has laid out, and the scale read then is not the scale the
	# finished window draws at. It runs after the palette's own pass, which is queued inside `_build_palette`,
	# so the palette is already at its size by the time this walks over it and the two agree rather than
	# taking turns.
	#
	# The device question is asked *there* rather than handed in here, and that is the whole of the method:
	# `call_deferred` reads its arguments where it is written, so passing the `_touch_screen` read a few lines
	# above would carry a reading taken before the window laid out into a pass whose entire point is to run
	# after it has.
	_size_the_chrome_for_the_device.call_deferred()
	# A session is a sibling of this HUD in the planner scene and absent everywhere else. Found
	# here rather than exported so no test scene has to remember to provide one.
	_presence = get_node_or_null(^"../Presence") as PresenceScript
	if _presence != null:
		_presence.changed.connect(_on_presence_changed)
	_build_menu_bar()
	_build_keys_panel()
	_build_help_window()
	_build_command_palette()
	_build_file_dialogs()
	_build_recovery_dialog()
	_build_plant_library()
	_build_ground_window()
	_build_layer_window()
	_build_site_report_panel()
	_build_survey_panel()
	_build_hatch_panel()
	_build_irrigation_panel()
	_build_lighting_panel()
	_build_sheet_window()
	_build_revision_window()
	_build_dxf_panel()
	_build_landxml_panel()
	_build_osm_window()
	_build_underlay_window()
	_build_grading_window()
	_build_plant_order_window()
	# The food garden: the same drawing and the same list as the menu above, asked the other question
	# a garden is for - where the food will actually crop.
	_build_food_window()
	_build_rotation_window()
	_build_harvest_window()
	_build_season_window()
	_build_sowing_window()
	_build_yield_window()
	_build_estimate_window()
	_build_pipeline_board()
	_build_job_desk()
	_build_schedule_board()
	_build_cost_window()
	_build_billing_ledger()
	_build_billing_window()
	_build_ledger_desk()
	_build_ledger_window()
	_build_sync_engine()
	_build_sync_window()
	_build_closeout_desk()
	_build_closeout_window()
	_build_analytics_report()
	_build_analytics_window()
	# The sun's study: a window, because the height it reports about is typed into it.
	_build_sun_window()
	# The walk-through: a window, because the walk is played from it and it holds the clock.
	_build_walk_window()
	# Snapping: a window, because the settings are switches and the legend has no room for them.
	_build_snap_window()
	# What the drawing has said: read-only, and built here so the page is in `pages_in_windows()`
	# before the Escape pass runs over it.
	_build_status_window()
	# The painted plan reports by signal, so the panel is a caption rather than a
	# function that blocks the frame the key was pressed in.
	if painted_plan != null:
		painted_plan.painted.connect(_on_painted)
		painted_plan.paint_failed.connect(_on_paint_failed)
	_on_view_mode_changed(view_controller.mode)
	# What a session that ended without saving left behind, read once here rather than on every frame:
	# the File menu reports on it, and the menu is built from a snapshot that has to stay cheap.
	_refresh_pending_recovery()
	# The pages that live in a `Window` take the keyboard into their own viewport, so the Escape ladder
	# below cannot reach them: each one is given a node of its own that can. Built after every page, so
	# the list is complete by the time it is read.
	_let_escape_close_pages()
	# Last, so it covers the buttons the palette and the presentation panel just
	# built as well as the ones in the scene: a button that holds the keyboard takes
	# the drawing keys with it.
	release_keyboard_focus(self)
	# The front door, built last so its sheet stands over every button the palette and the panels just
	# made. It stands only when there is nothing behind it - a launch with a drawing already open is not
	# asked, and neither is one that opens onto recovered work.
	_orientation = OrientationChoiceScript.stored()
	# The reader's own choice of how big the words are. Read here, and handed to the one place that works a
	# size out, so that a question about the size of a word never becomes a question about a file. It is read
	# before anything is fitted, which is why it sits here: every fitting pass below is deferred past `_ready`.
	_reading_size = ReadingSizeScript.load_kept()
	PhoneHudScript.use_reading_scale(ReadingSizeScript.factor())
	_build_start_window()
	if _draft != null and StartChoicesScript.should_show(_draft.drawing_path, _draft.dirty):
		open_the_front_door()
	# What is on the screen, said out loud, for anything driving this program from another computer. A debug build
	# only. The launch block is said here, once the door and every other page have been built; every block after it
	# is asked for by `_notice_the_pages_changing`, on the frame rather than by a signal.
	_the_screen_said()


# --- what is on the screen, for anything driving this from another computer -------------------------

## Set to keep a second report from stacking up behind a first.
var _saying_the_screen: bool = false

## The pages that were up when the screen was last said, and whether anything has been said at all. This is what
## asks for a new block, and it is written **when a block is said** rather than when a change is noticed, so a
## change arriving while a block is being taken is said by a later frame rather than lost.
var _screen_as_said: PackedStringArray = PackedStringArray()
var _has_said_the_screen: bool = false

## How long the top bar is given to stop folding before the probe reads the screen. The fold runs on every
## frame and takes about twenty of them to settle (measured on the phone: 14 titles, 10, 9, while its room went
## 927, 920, 871), so this is a ceiling on the wait rather than a delay - the wait ends the moment the fold has
## nothing left to rebuild.
const MENU_BAR_SETTLING_FRAMES := 60


## What the pages standing on the screen look like now: each one's name and the rectangle it is drawn in - and only
## the ones that are *up*, since a page hidden behind the board is not on the screen and must not be said.
func _the_pages_up() -> PackedStringArray:
	var up := PackedStringArray()
	# **A HUD that is not in a tree has no screen to walk.** The guard is here rather than at each caller because this
	# is the state a block is compared against: one caller is the launch block, taken while the door is still being
	# built, and a test holds the rule about the view without a scene at all.
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return up
	for window: Window in viewport.get_embedded_subwindows():
		if not window.visible:
			continue
		# The page's rectangle through the probe's own reader, which is the one the block's `page` line is written
		# with: the state watched here and the rectangle said there cannot then be two different readings.
		up.append("%s %s" % [PageLayoutScript.page_name(window), str(HudProbeScript.window_rect(window))])
	return up


## The view the screen is in now, in the program's own words: the top bar's mode label, which is the very label the
## block's `row` line publishes and the very words `HudProbe.read_view_line` reads back.
##
## **A view change published no block until this was added**, and that cost a diagnosis. Measured on the A16W on
## 2026-11-17: the newest block said `3D OVERHEAD` while the glass plainly showed the 2D plan, and a tool that
## trusted the block pressed the view toggle the wrong way and turned the board into what it had just left. The
## label is read rather than the controller's own mode, deliberately: what a person is shown and what a reader reads
## back are then the same words, so a second naming of the view cannot appear between them.
func _the_view_up() -> String:
	if mode_label == null:
		return ""
	return mode_label.text


## **Everything the screen's own block is about**: the pages standing on it, and the view it is in. One reading, taken
## both by the ask below and by the record in `_the_screen_said`, so what is watched and what is written cannot be
## two different things.
## The room a page lands in, as this HUD asks its own viewport for it - **one expression, one owner**, because the
## block and the state a block is compared against must not be able to read two different rooms.
func _the_room() -> Vector2i:
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return Vector2i.ZERO
	return Vector2i(viewport.get_visible_rect().size)


## **Everything the screen's own block is about**: the pages standing on it, the view it is in, and the room they are
## all in. One reading, taken both by the ask above and by the record in `_the_screen_said`, so what is watched and
## what is written cannot be two different things.
##
## **The room belongs in it because a turn changes nothing else.** A rotation publishes no page event and no view
## change, so without this a phone turned on its side left the newest block describing the way up it used to be - and
## every instrument that judges a rectangle against the band a device keeps would then be comparing a lying screen
## with a standing band. Measured on the A16W on 2026-11-17, the device's own setting is not the answer either:
## `settings get system user_rotation` read **0** with auto-rotate **on** while the program reported `shape=lying`.
func _the_screen_now() -> PackedStringArray:
	var now: PackedStringArray = _the_pages_up()
	now.append("view %s" % _the_view_up())
	now.append("room %s" % str(_the_room()))
	return now


## Say what is on the screen when the screen differs from the screen the last block was about - a debug build only.
##
## **One rule, asked of the screen rather than told by the pages**, and the reason is a fault measured on the A16W
## on 2026-11-14. The block used to be published from signals connected in `_ready` to the pages that existed
## *then*: a page built later - the begin-a-drawing page, the camera's - was never connected, so **its leaving was
## invisible**. A BACK that the glass plainly showed had put the page away printed nothing to logcat at all, while
## the door's own hide (its page built in `_ready`) did print one - so a driver reading the newest block was still
## told a page was standing in front of the board, and there is no way to tell that from a BACK that failed.
##
## A rule that watches the *screen* cannot miss a page however it was built, and it says a page arriving and a page
## being put away as the single thing they are: the screen changed. It also asks one question rather than three
## signals, so a press that puts one page away and opens another says one block and not two.
##
## **And the view is part of what the screen is, not of what the pages are.** A view change moves no page, so it
## published no block at all until it was added here - and a block's own `ModeLabel` words could then be several turns
## old: measured on the A16W, the newest block said `3D OVERHEAD` while the glass plainly showed the 2D plan, and a
## tool that trusted it pressed the view toggle the wrong way. What is compared is `_the_screen_now`: the pages up,
## and the view's own words.
func _notice_the_pages_changing() -> void:
	if not HudProbeScript.on():
		return
	var now: PackedStringArray = _the_screen_now()
	if _has_said_the_screen and now == _screen_as_said:
		return
	_the_screen_said()


## Say what is on the screen, once the layout has settled rather than the moment a page lands.
##
## The settling figure is `PageLayout`'s own, and for its own reason: a container resizes its children on the
## frame after its own size changes, and a wrapped line re-wraps on the frame after that, so a control's
## rectangle is only true two frames on. Frames are *awaited* rather than deferred, because a deferred call
## runs before the layout does and would report a page where it used to be.
##
## **And once the top bar has stopped folding.** The fold runs on every frame and takes about twenty of them to
## settle - measured on the phone, the bar went from fourteen titles to ten to nine while its room went 927, 920,
## 871 and what it needed 1375, 920, 781 - so a reading taken two frames after a page appears catches the bar
## mid-rebuild. That is not a small error: it reported the bar **19 px past the edge of a screen it was about to
## fit**, and the fault was in the reading rather than in the bar. Waiting for the fold to say it has nothing left
## to do costs a few frames once, and it is the difference between naming a defect and naming a moment.
func _the_screen_said() -> void:
	if not HudProbeScript.on() or _saying_the_screen or not is_inside_tree():
		return
	_saying_the_screen = true
	for i: int in PageLayoutScript.SETTLING_FRAMES:
		await get_tree().process_frame
	# **Whether the fold still wants to rebuild, not whether the room has stopped changing.** The fold runs on
	# every frame and the two numbers feed each other - the bar's own minimum is part of the room the fold is
	# given - so the room can hold still for two frames in the middle of a fold that is not finished, which is
	# exactly what it did: a reading taken by watching the room caught the bar at ten titles and reported it
	# asking for 1052 px of a 349 px room, while the fold went on to two titles and 272 px and fitted. What is
	# asked here is the fold's own question - would the plan for this room put different titles up than the ones
	# standing - and the wait ends the moment it would not.
	for i: int in MENU_BAR_SETTLING_FRAMES:
		await get_tree().process_frame
		if _the_fold_has_settled():
			break
	_saying_the_screen = false
	# Recorded before the block is built, so what is remembered as said is the screen this block is about. A change
	# arriving while the block is being built is therefore still a change on the next frame.
	_screen_as_said = _the_screen_now()
	_has_said_the_screen = true
	_say_the_screen()


## Every surface that is drawn on the screen, for the one comparison this HUD could not make before: a page -
## or the title bar hanging above one - standing in the same rows as the HUD's own furniture.
##
## It measures nothing itself. The words are the probe's own walk of this HUD's tree, the top bar stands in for
## the menu titles (Godot's `MenuBar` draws those itself and no node carries them), and every page that is up
## arrives as itself and its own bar through the probe - which is also where the pixels are composed, so all of
## them are in the one space a screenshot is counted in.
func drawn_surfaces() -> Array:
	var board: Control = get_node_or_null(^"Root") as Control
	var surfaces: Array = HudProbeScript.words_in(board)
	if top_bar != null:
		surfaces.append(DrawnSurfacesScript.top_bar("the top bar", Rect2i(HudProbeScript.screen_rect(top_bar))))
	for window: Window in get_viewport().get_embedded_subwindows():
		if window.visible:
			surfaces.append_array(HudProbeScript.page_surfaces(window))
	return surfaces


## The block itself: where this device was answered from, the room, the two lines a person reads at the foot
## of the screen, the board's own controls, and every page that is up - in that order, because a driver has
## to be able to tell which of them is standing over which.
func _say_the_screen() -> void:
	var lines := PackedStringArray()
	# The room, read once: it is the viewport's own visible rectangle, which is both what a page lands in and
	# what this window's shape is worked out from.
	var room: Vector2i = _the_room()
	lines.append_array(
		HudProbeScript.device_lines(
			shows_touch_controls(),
			PhoneHudScript.zooming_here(),
			PhoneHudScript.dpi(),
			PhoneHudScript.canvas_scale(get_window()),
			room,
			# The strip no page may be placed in, handed on as the module that states it now has it: this is
			# the figure a phone is read by, and it is worth printing beside the room because the two ways up
			# a phone can be held disagree about it by a factor of five.
			PageChromeScript.reserved_above,
			# **The stated display, not a second reading of the desk's.** `native` is the figure a person compares
			# the room against, and `PhoneHud.screen_here` is the one place a screen is read: a phone-shaped
			# window on a desk is a 1080 by 2340 glass whatever monitor is showing it (measured 2026-11-18, where
			# this line still said 2560 by 1600 beside a room of the A16W's own size).
			PhoneHudScript.screen_here(),
			DisplayServer.is_touchscreen_available(),
			WindowPostureScript.of(room),
			hints_label.text if hints_label != null else "",
			draft_hints_label.text if draft_hints_label != null else "",
		)
	)
	lines.append_array(HudProbeScript.row_lines(menu_bar.get_parent() as Control, "the top bar", menu_bar_room()))
	# **A tap line carries the control's number in this block**, counted from one and carried across the parts: the
	# board's controls are numbered here and a page's carry on from the board's count where the pages are walked,
	# near the foot of this function. The count is threaded rather than worked out twice - a second walk of the
	# controls could number a control the lines do not name.
	var number: int = 1
	var board_taps: PackedStringArray = HudProbeScript.tap_lines(self, "the board", number)
	lines.append_array(board_taps)
	number += HudProbeScript.taps_in(board_taps)
	# Then the two questions nothing here could answer until now. Every other figure in this block measures a
	# control against *another control*; neither of these did. One asks whether a control is drawn past the edge
	# of the screen - which nothing can be done about from inside the program, and the phone's own view buttons
	# were drawn wholly off it - and the other asks whether a tap on a button would reach it, which is what a
	# driver wants to know when a click does nothing.
	lines.append_array(HudProbeScript.offscreen_lines(get_node_or_null(^"Root"), "the board"))
	lines.append_array(
		HudProbeScript.reach_lines(get_node_or_null(^"Root"), get_viewport().get_embedded_subwindows(), "the board")
	)
	# Then the two the phone needs and the desk does not. What a finger would be asked to hit is only a question
	# while a finger is the thing being served - the desk's own 31 px buttons are right for a mouse - and a whole
	# page placed past the edge of the room is the class the phone's camera page belonged to, which no check on
	# the controls inside a page can reach.
	if shows_touch_controls():
		var finger_scale: float = PhoneHudScript.canvas_scale(get_window())
		var finger_density: float = PhoneHudScript.dpi()
		# The floor the device itself states for a target, rather than this project's desk-sized one: a phone
		# at 450 dpi wants a 5.5 mm row, about 107 px of the layout. **The probe states it, not the HUD**,
		# because a floor has to be in the same space as the rectangles it judges and only the probe knows
		# which space that is: handed over in layout pixels it compared 107 with 97 and called every button
		# on the screen ten pixels short.
		var finger_least: int = HudProbeScript.finger_floor(get_node_or_null(^"Root"))
		lines.append_array(HudProbeScript.small_lines(get_node_or_null(^"Root"), "the board", finger_least))
		lines.append_array(HudProbeScript.close_lines(get_node_or_null(^"Root"), "the board"))
		lines.append_array(HudProbeScript.unsafe_lines(get_node_or_null(^"Root"), "the board"))
		lines.append_array(HudProbeScript.middle_lines(get_node_or_null(^"Root"), "the board"))
		lines.append_array(
			HudProbeScript.tiny_lines(get_node_or_null(^"Root"), "the board", finger_scale, finger_density)
		)
		for window: Window in get_viewport().get_embedded_subwindows():
			if window.visible:
				var finger_page: String = PageLayoutScript.page_name(window)
				lines.append_array(HudProbeScript.small_lines(window, finger_page, finger_least))
				lines.append_array(HudProbeScript.close_lines(window, finger_page))
				lines.append_array(HudProbeScript.unsafe_lines(window, finger_page))
				lines.append_array(HudProbeScript.middle_lines(window, finger_page))
				lines.append_array(HudProbeScript.tiny_lines(window, finger_page, finger_scale, finger_density))
	lines.append_array(HudProbeScript.page_edge_lines(get_viewport().get_embedded_subwindows()))
	# Then the one thing a rectangle cannot say: whether a box is being *scrolled*, and whether the room to
	# have made it bigger was there all along. A picture cannot tell a box that scrolls from one that clipped
	# - both look like a box - and only the control's own bar knows which of the two it is.
	lines.append_array(HudProbeScript.crowded_lines(get_node_or_null(^"Root"), "the board"))
	# And what the words themselves say wrong: a note to the author, a message a compiler would write, a
	# sentence where a name belongs. A rectangle is honest about its size and says nothing at all about the
	# text in it, and this is the half of "is it showing right" that no measurement reaches.
	lines.append_array(HudProbeScript.words_lines(get_node_or_null(^"Root"), "the board"))
	# And whether the words fit the box they are drawn in, which is the half of "is it showing right" that a
	# rectangle cannot reach: the phone's own foot line showed "Pinch: zoo" where the program wrote "Pinch:
	# zoom", and a box too short for its caption looks exactly like a box that fits it.
	lines.append_array(HudProbeScript.clipped_lines(get_node_or_null(^"Root"), "the board"))
	for window: Window in get_viewport().get_embedded_subwindows():
		if window.visible:
			var a_pages_own: PackedStringArray = HudProbeScript.page_lines(window, number)
			lines.append_array(a_pages_own)
			number += HudProbeScript.taps_in(a_pages_own)
			lines.append_array(HudProbeScript.crowded_lines(window, PageLayoutScript.page_name(window)))
			lines.append_array(HudProbeScript.offscreen_lines(window, PageLayoutScript.page_name(window)))
			lines.append_array(HudProbeScript.words_lines(window, PageLayoutScript.page_name(window)))
			lines.append_array(HudProbeScript.clipped_lines(window, PageLayoutScript.page_name(window)))
	# What the glass says about the one rectangle no layout knows: a page's title bar is drawn by Godot above
	# the page and a phone draws it taller than the theme says, so it is read here and printed beside the
	# theme's own answer. Only where there is a screen to read it off: a headless run has no framebuffer - the
	# dummy renderer has no texture to copy and asking for one logs an engine error, which is enough to fail a
	# test run - and a drawing is no less true for the lack of a picture of it. `HudProbe._a_real_screen` is the
	# one place that answers whether there is a screen, and it is the same answer the probe's own absolute-pixel
	# lines need. The framebuffer is read once and shared, because a debug build can afford one copy of the
	# screen and not one per page.
	var glass: Image = null
	if HudProbeScript._a_real_screen():
		glass = get_viewport().get_texture().get_image()
	for window: Window in get_viewport().get_embedded_subwindows():
		if window.visible:
			lines.append_array(HudProbeScript.drawn_bar_lines(window, glass))
	# Last, and the reason this block is read at all: what is *drawn* against what may not share rows with it.
	# Neither the HUD layout check nor the page measurement could see a page's own title bar over the menu
	# titles, and both were green while a person could see it - this is that comparison, from rectangles three
	# other measurements already produced.
	lines.append_array(HudProbeScript.meeting_lines(drawn_surfaces()))
	HudProbeScript.publish(lines)


func _process(delta: float) -> void:
	# Ahead of the guard, because keeping a copy is about the drawing rather than about the view: a
	# scene with no view controller still has work in it that is worth not losing.
	_tick_autosave(delta)
	# **Whether the pages up have changed, which is what asks for a probe block.** Asked on the frame rather than
	# told by a signal, and asked here rather than further down because everything below can return early: a reading
	# that only happens while some other question is being asked is a reading that goes missing.
	_notice_the_pages_changing()
	# Likewise ahead of the guard: the ground's heights belong to the drawing, not to the view, and a
	# page that is open while the drawing changes under it has to keep up.
	_tick_grading_window()
	# And the same for the plants to buy: the yard and the job desk both move under that page.
	_tick_plant_order_window()
	# And the same for the food garden: a bed's light is stated on the drawing, and the site a crop is
	# checked against moves with the presentation.
	_tick_food_window()
	# And the beds the rotation page offers: a bed stated on the drawing while that page is up is a bed
	# it should offer.
	_tick_rotation_window()
	# And the harvest calendar: it reads the plant list, which does not change under an open page except
	# when a list is imported, so its tick is almost always a no-op and costs almost nothing.
	_tick_harvest_window()
	# And the growing season: it lives on the drawing, so a drawing opened behind the page, or an undo
	# that puts older frost dates back, has to reach it.
	_tick_season_window()
	# And when to sow: it reads the same drawing's season, so the same move - a drawing opened or an
	# undo - has to reach it too.
	_tick_sowing_window()
	# And how much to plant: it reads the plant list, which does not change under an open page except when
	# a list is imported, so its tick is almost always a no-op and costs almost nothing.
	_tick_yield_window()
	# And the same for the sun: the study's own site lives on the drawing, and an undo can put another
	# one back under a page that is open.
	_tick_sun_window()
	# And the same for what has been said: the page is a view of the drawing's own history, and it says
	# it is showing the newest answer, so it has to be showing it.
	_tick_status_window()
	if view_controller == null:
		return
	var viewport_height: float = get_viewport().get_visible_rect().size.y
	# Both overhead views share one zoom, so one conversion serves them both.
	overlay.set_pixels_per_metre(ViewMath.pixels_per_metre(viewport_height, view_controller.plan_size))
	# Arming the tools happens on a key press inside the view controller, which has
	# no signal for it, and it is one bool: reading it is cheaper than routing it.
	# The legend and the palette both go away on the ground, where the tools do
	# nothing at all.
	var overhead: bool = view_controller.mode != ViewController.ViewMode.GROUND
	# A presentation, or the painted plan, is a view of the garden rather than a working view, so none
	# of the working furniture is on screen in either one. Two exceptions: the presentation panel holds
	# the switch that ends a presentation, and the painted sheet carries its own Close.
	var painted: bool = painted_sheet != null and painted_sheet.visible
	var working: bool = not _presenting and not painted
	draft_hints.visible = working and overhead and view_controller.is_drafting()
	# The thumb controls belong to the ground view alone: in the overhead views the mouse is the pointer,
	# and a stick on the glass there would be a second way to move a view that already has a better one.
	if _touch_pad != null:
		_touch_pad.visible = working and not overhead and shows_touch_controls()
	# **On a device answered with a finger the two columns a desk draws give way to the two bars a thumb
	# reaches.** The vertical palette beside the plan and the fourteen menus across the top are both the shape a
	# mouse and a wide room make; a phone gets the dock along its foot and four controls where the menus stood.
	# `_show_the_touch_furniture` is the one place that says which of the two arrangements is up, so the answer
	# is stated once rather than worked out again by everything that draws near it.
	var on_a_finger: bool = shows_touch_controls()
	if palette.get_child_count() > 0:
		palette.visible = working and overhead and not on_a_finger
		_refresh_palette()
		_refresh_plant_panel()
	if top_bar != null:
		top_bar.visible = working
	_show_the_touch_furniture(working and overhead)
	if overlay != null:
		overlay.visible = working
	# The panel is the one piece of this furniture a *person* owns as well as the view: the Present menu puts
	# it away. So the frame asks the one owner rather than working the answer out again - the line that stood
	# here read `presentation != null and not painted`, never looked at the flag, and re-showed the panel on the
	# frame after the menu row had put it away. That is how a row with its own test came to do nothing at all.
	_refresh_presentation_panel()
	_apply_hints_visibility()
	# The line at the foot of the screen follows what is in hand, which changes on a key press the HUD
	# does not hear about, so it is written here rather than only when the view changes.
	_refresh_hints()
	# A presentation is a view of the garden rather than of the drawing, so the
	# painted sheet goes away with the rest of the drawing's furniture.
	if _presenting and painted_sheet.visible:
		close_painted()
	_refresh_presentation()
	# A session carries which drawing this peer has open and where they are pointing, so it is told
	# both before the bar is refreshed - the one line about the session reads the session's own facts.
	if _presence != null and _presence.is_on():
		_presence.watch(_drawing_label(), get_viewport().get_mouse_position())
	_refresh_menus()
	if is_hatch_panel_open():
		_refresh_hatch_panel()
	if is_water_panel_open():
		_refresh_water_panel()
	if is_light_panel_open():
		_refresh_light_panel()
	# The history joins the undo history, so what it says about a drawing changes as that drawing is
	# worked on - which is why it is polled while it is up rather than refreshed only when it is acted
	# on. Its own signature is what stops a window nobody is drawing into from rebuilding itself.
	if is_revision_window_open():
		_refresh_revision_window()


func _on_view_mode_changed(new_mode: ViewController.ViewMode) -> void:
	var overhead: bool = new_mode != ViewController.ViewMode.GROUND
	var flat: bool = new_mode == ViewController.ViewMode.PLAN_2D
	if flat:
		mode_label.text = "2D PLAN"
		mode_label.add_theme_color_override("font_color", Color(0.6, 0.85, 0.52))
	elif overhead:
		mode_label.text = "3D OVERHEAD"
		mode_label.add_theme_color_override("font_color", Color(0.62, 0.78, 0.95))
	else:
		mode_label.text = "GROUND VIEW"
		mode_label.add_theme_color_override("font_color", Color(0.85, 0.78, 0.5))
	var switch_key := _key_label(&"toggle_view")
	toggle_button.text = "3D view  (%s)" % switch_key if flat else "2D plan  (%s)" % switch_key
	toggle_button.visible = overhead
	fit_button.visible = overhead
	ground_button.text = "Ground view  (G)" if overhead else "Back to overhead  (G)"
	_refresh_hints()
	overlay.set_mode(new_mode)


## The control hints for a view, with the key that swaps the overhead views filled
## in from the input map.
static func _hints_for(view_mode: int, on_a_finger: bool = false) -> String:
	if view_mode == ViewController.ViewMode.GROUND:
		return HINTS_GROUND_ON_A_FINGER if on_a_finger else HINTS_GROUND
	# The two overhead views are told apart on a desk by the key that swaps them, and a finger has no key: what
	# is left there is the tool in hand and the two gestures, which are the same in both views.
	if on_a_finger:
		return HINTS_OVERHEAD_ON_A_FINGER
	var template := HINTS_2D \
			if view_mode == ViewController.ViewMode.PLAN_2D else HINTS_3D
	return template.replace(VIEW_KEY_TOKEN, _key_label(&"toggle_view"))


## The keys that answer the tool in hand, each read from the binding it really is.
##
## Only the keys the tool in hand **honours** are offered. A line takes two picks and is finished by the
## second of them: it has no last point to drop and no shape to close, so offering it those keys would be
## the legend-that-lies defect in miniature - and this is the line a person reads with their hand already
## busy, which is the worst place to be told about a key that does nothing.
##
## `DraftTool.is_ring` is the tool's own answer to "does this collect points until it is told to stop" -
## the polyline, and the contour, which is a polyline that lands on a grading layer - and it is what makes
## finishing, closing and dropping a point mean anything at all. A measurement is the other tool that
## finishes by key rather than by a pick, because its answer is the pair it has already taken.
static func hand_keys(tool_kind: int, editing: bool) -> String:
	var keys: Array[String] = []
	if not editing and DraftToolScript.is_ring(tool_kind):
		keys.append(_hand_key(&"draft_finish"))
		keys.append(_hand_key(&"draft_close"))
		keys.append(_hand_key(&"draft_undo_point"))
	elif not editing and tool_kind == DraftToolScript.Kind.MEASURE:
		keys.append(_hand_key(&"draft_finish"))
	keys.append(_hand_key(&"draft_cancel"))
	var words := PackedStringArray()
	for key: String in keys:
		if key != "":
			words.append(key)
	return HINT_GAP.join(words)


## One key of that row: the binding that is really on it, and the word for what it does. An action bound
## to nothing is left out rather than printed with a blank key, which is how the legend does it too.
static func _hand_key(action: StringName) -> String:
	var key := _key_label(action)
	if key == "":
		return ""
	return "%s: %s" % [key, HAND_KEY_WORDS.get(action, "")]


## The line at the foot of the screen while the drawing tools are in hand: what the tool is waiting for,
## and the keys that answer it.
static func hand_hints(prompt: String, keys: String) -> String:
	return prompt if keys == "" else "%s%s%s" % [prompt, HINT_GAP, keys]


## The longest line the foot of the screen can be asked to carry, for the check that measures the panel
## against it.
##
## The prompt is asked of a tool driven through every point count it can be in, so a tool that grows a
## wordier prompt is measured the day it does rather than the day somebody notices the line running past
## the edge of its panel. An editing command cannot beat this: every one of them answers to Escape alone,
## where a polyline carries three keys, and the longest of their prompts is shorter than this one.
static func worst_hint_line() -> String:
	var worst := ""
	for pair: Array in DRAFTING_TOOLS:
		var kind: int = pair[2]
		for steps: int in 5:
			var tool: DraftToolScript = DraftToolScript.new()
			tool.begin(kind)
			for i: int in steps:
				tool.click(Vector2(float(i), 0.0))
			var line := hand_hints(
				"%s  ·  %s" % [DraftToolScript.label_for(kind), tool.status()],
				hand_keys(kind, false),
			)
			if line.length() > worst.length():
				worst = line
	return worst


## The plate's own height at the moment the left column was last placed. Held so that a plate which has grown -
## a line that wrapped, a font a device asked for, a turn of the phone - is noticed and the column placed again.
## It starts at `INF`, which no rectangle ever equals, so the first frame places it.
var _plate_height_as_placed: float = INF

## Write the line at the foot of the screen and the box beside the plan: what the tool in hand is waiting
## for with the keys that answer it, while the drawing tools are in hand - and the controls of the view when
## none is, with the box saying nothing at all.
##
## One writer for both, called from the view change and from the frame, so a tool being armed, an edit
## landing and a view being switched cannot leave two different answers on the screen. Each text is assigned
## only when it has changed, because writing to a `Label` re-computes what it needs and the frame offers
## sixty chances a second to do it for nothing.


func _refresh_hints() -> void:
	if hints_label == null or view_controller == null:
		return
	var wanted: String = _hints_for(view_controller.mode, shows_touch_controls())
	var box := ""
	# The tools do nothing on the ground, where the corner line is the way back out of it.
	if _draft != null and _draft.drawing and view_controller.mode != ViewController.ViewMode.GROUND:
		wanted = hand_hints(_draft.prompt(), hand_keys(_draft.current_tool(), _draft.is_editing()))
		box = _draft_box_text()
	if hints_label.text != wanted:
		hints_label.text = wanted
	if draft_hints_label != null and draft_hints_label.text != box:
		draft_hints_label.text = box
	# **The palette's foot is taken from the plate's own top, so the column is placed again whenever the plate's
	# height changes - whatever changed it.** Anything that makes the line wrap does it: a wordier prompt, a
	# device's rows, a turn of the phone.
	#
	# It is **not** enough to ask when the *text* changes, which is what this first did. The words are assigned
	# before the plate has been laid out again, so a placement asked for at that moment reads the height the
	# plate is about to leave, and the palette stays where the shorter line had put it - measured on the A16W,
	# where the foot line wrapped from one row onto three and the palette's own box came to stand over the
	# plate's words, drawing `Layer` and the list's group headers across them.
	#
	# The height is read here because this runs every frame, and the deferred placement lands after the layout
	# that changed it, so what it reads is the plate as it will be drawn.
	if _the_plate_moved(hints.size.y):
		place_the_left_column_for_a_device.call_deferred()


## Whether the plate at the foot has moved since the left column was last placed, and take its new height in. The
## placement is asked for on the frames this answers `true` and no others, so the sixty frames a second that find
## the same line in hand cost one comparison each.
##
## Being a question about the plate's *height* rather than about its words is the point of the rule: the plate
## stands where it stands because of what a device asked for, how the text wrapped and which view is up as well as
## the prompt, and every one of those moves it. Asked on the height, one rule answers for all of them.
func _the_plate_moved(plate_height: float) -> bool:
	var moved := not is_equal_approx(plate_height, _plate_height_as_placed)
	_plate_height_as_placed = plate_height
	return moved


## The box beside the plan for the thing in hand: the tool, or the editing command, whichever it is.
##
## The editing command comes first because a command in hand is not a tool in hand - a trim is one gesture
## measured against everything else on the sheet, and its own sentence is the controller's to write.
func _draft_box_text() -> String:
	if _draft == null:
		return ""
	if _draft.is_editing():
		var edit: int = _draft.current_edit()
		return tool_box_text(
			DraftControllerScript.edit_label(edit),
			_arming_key(edit, true),
			DraftControllerScript.edit_description(edit),
			hand_keys(DraftToolScript.Kind.SELECT, true),
		)
	var kind: int = _draft.current_tool()
	return tool_box_text(
		DraftToolScript.label_for(kind),
		_arming_key(kind, false),
		DraftToolScript.description(kind),
		hand_keys(kind, false),
	)


func _on_transition_started(_to_ground: bool) -> void:
	overlay.set_transitioning(true)


func _on_transition_finished(_to_ground: bool) -> void:
	overlay.set_transitioning(false)


# --- the drafting legend --------------------------------------------------------------

## How many rows the box beside the plan may have, which is what the panel beside the drawing has room for.
## Four is what it takes: the tool's name, what it is for, the keys that answer it, and the two that take a
## drawing act back. A tool that needs a fifth has outgrown the panel rather than the box, and the check
## that measures the panel against the worst box is where that is noticed.
const DRAFT_BOX_ROWS := 4


## The box beside the plan while a tool is in hand, as rows rather than as one string so that a test can
## hold each half of it to the table it came from.
##
## **This box used to hold the whole key reference**, and the reason it does not any more is the correction
## this project keeps making: every entry it listed - ten tools, eight editing commands, the plot key, the
## standard key - was a button in the palette standing beside it, wearing the same key. A box that repeats
## the palette is a second copy of a list, and a second copy is what the program spends its effort
## avoiding. What a person cannot get anywhere else is what the tool in hand is *for*, so that is what the
## box says: the tool's name and the key that armed it, one sentence about what it does, the keys that
## answer it, and the two that take a drawing act back.
##
## The full reference has not gone anywhere. It is the Keys page, `drafting_rows` below, which is where a
## list of every key belongs - and it is where the coverage test looks for every bound key, so a key cannot
## quietly stop being described by moving out of this box.
static func tool_box_rows(tool_name: String, key: String, description: String, keys: String) -> Array[String]:
	var rows: Array[String] = []
	rows.append(tool_name if key == "" else "%s   (%s)" % [tool_name, key])
	if description != "":
		rows.append(description)
	if keys != "":
		rows.append(keys)
	var back := undo_redo_keys()
	if back != "":
		rows.append(back)
	return rows


## The same, as one block of text for a label.
static func tool_box_text(tool_name: String, key: String, description: String, keys: String) -> String:
	return "\n".join(PackedStringArray(tool_box_rows(tool_name, key, description, keys)))


## The two keys that take a drawing act back, read from their bindings like every other key on the screen.
##
## They are in the box rather than in the palette's reach alone because the palette has them as *buttons*,
## and a person who has learned to undo from the keyboard is not looking for a button.
static func undo_redo_keys() -> String:
	var words := PackedStringArray()
	for action: StringName in [&"draft_undo", &"draft_redo"]:
		var key := _key_label(action)
		if key != "":
			words.append("%s %s" % [key, HAND_KEY_WORDS.get(action, "")])
	return DRAFTING_ROW_GAP.join(words)


## The worst the box can be: the box with the widest row of any tool or editing command, for the check that
## measures the panel against it.
##
## The check has to measure the *worst* case rather than what happens to be on the screen. The box is empty
## until a tool is in hand, and a box measured while nothing is armed would pass on the day the longest tool
## grew a wordier sentence. Every kind is asked, the three grading tools and the select tool included, and
## the widest single *row* is what decides - a row is the thing that runs past the edge of a panel.
static func worst_tool_box() -> String:
	var worst := ""
	var widest := 0
	for value: int in DraftToolScript.Kind.values():
		var kind: int = value
		var box := tool_box_text(
			DraftToolScript.label_for(kind),
			_arming_key(kind, false),
			DraftToolScript.description(kind),
			hand_keys(kind, false),
		)
		var width := _widest_row(box)
		if width > widest:
			widest = width
			worst = box
	for value: int in DraftControllerScript.EditKind.values():
		var edit: int = value
		if edit == DraftControllerScript.EditKind.NONE:
			continue
		var edit_box := tool_box_text(
			DraftControllerScript.edit_label(edit),
			_arming_key(edit, true),
			DraftControllerScript.edit_description(edit),
			hand_keys(DraftToolScript.Kind.SELECT, true),
		)
		var edit_width := _widest_row(edit_box)
		if edit_width > widest:
			widest = edit_width
			worst = edit_box
	return worst


## How wide the widest row of a box is, which is what a panel has to have room for.
static func _widest_row(box: String) -> int:
	var widest := 0
	for row: String in box.split("\n"):
		widest = maxi(widest, row.length())
	return widest


## The key that arms a tool or an editing command, found by the *kind* it puts in hand rather than by
## matching a name against a name. A tool nothing arms a key for - the select tool - reads as its name
## alone rather than with a blank pair of brackets beside it.
static func _arming_key(kind: int, editing: bool) -> String:
	if editing:
		for pair: Array in EDIT_TOOLS:
			if int(pair[2]) == kind:
				return _key_label(pair[0])
		return ""
	return _key_label(DraftToolScript.arming_action(kind))


## The key reference, line by line: every tool, every editing command and every other key the drawing
## needs, for the Keys page. Kept as lines rather than as one string so that a test can check every entry
## against the binding it claims, which is the only way a reference stays true.
##
## It is deliberately not what the box beside the plan shows any more. A reference is a page a person opens
## to look a key up, and a box in the middle of the drawing is not that: it is read at a glance, with a hand
## already busy, which is the place for the tool in hand rather than for all of them.
static func drafting_rows() -> Array[String]:
	var rows: Array[String] = []
	rows.append("%s leaves the drawing tools" % _key_label(&"draft_mode"))
	rows.append_array(_wrap(_entries(DRAFTING_TOOLS), DRAFTING_TOOLS_PER_ROW))
	rows.append_array(_wrap(_entries(DRAFTING_COMMANDS), DRAFTING_COMMANDS_PER_ROW))
	rows.append_array(_wrap(_entries(EDIT_TOOLS), EDIT_TOOLS_PER_ROW))
	return rows


## The same, as one block of text for a label.
static func drafting_hints() -> String:
	return "\n".join(PackedStringArray(drafting_rows()))


## Action-and-wording pairs as the legend prints them. An action bound to nothing
## is left out rather than printed with a blank key, so an unbound tool is a
## missing line instead of a line saying nothing.
static func _entries(pairs: Array) -> Array[String]:
	var out: Array[String] = []
	for pair: Array in pairs:
		var key := _key_label(pair[0])
		if key == "":
			continue
		out.append("%s %s" % [key, pair[1]])
	return out


static func _wrap(entries: Array[String], per_row: int) -> Array[String]:
	var rows: Array[String] = []
	for start in range(0, entries.size(), per_row):
		rows.append(DRAFTING_ROW_GAP.join(PackedStringArray(entries.slice(start, start + per_row))))
	return rows


## The key an action is bound to, or "" when it is bound to nothing.
##
## The *first* event an action lists is the one it is introduced by, so the order of
## an action's events is what decides which key gets advertised.
##
## Modifiers are included, so Ctrl+Z does not print as a bare Z, which would be a
## different command. The name comes from the event rather than from a table here,
## so the legend follows a rebinding.
static func _key_label(action: StringName) -> String:
	if not InputMap.has_action(action):
		return ""
	for event: InputEvent in InputMap.action_get_events(action):
		var key := event as InputEventKey
		if key == null:
			continue
		# An action binds by physical keycode or by keycode depending on how it was
		# authored, and which one is set differs between the number keys and the
		# named ones, so both have to be looked at.
		var code := key.physical_keycode if key.physical_keycode != 0 else key.keycode
		if code == 0:
			continue
		var rendered := OS.get_keycode_string(code)
		var shortened: String = SHORT_KEY_NAMES.get(rendered, rendered)
		return ("Ctrl+" + shortened) if key.ctrl_pressed else shortened
	return ""

# --- the drawing palette --------------------------------------------------------------


## Whether the thumb controls are offered at all: on a device with a touchscreen, or when something has
## forced them on so that a desktop can look at them.
func shows_touch_controls() -> bool:
	return _touch_screen or _touch_forced


## Offer the thumb controls on a machine without a touchscreen. For the demo tool and for seeing the ground
## view's controls without a phone in hand; nothing in the program calls it.
func force_touch_controls(on: bool) -> void:
	_touch_forced = on


## The thumb controls, built in code and put behind everything else the HUD draws.
##
## Behind is the whole trick: every panel keeps its own touches, so a button that is on screen still works
## and only the empty part of the screen - most of it, at ground level - belongs to the pad.
func _build_touch_pad() -> void:
	var root := get_node_or_null(^"Root")
	if root == null or _touch_pad != null:
		return
	_touch_pad = TouchPad.new()
	_touch_pad.name = "TouchPad"
	_touch_pad.view_controller = view_controller
	root.add_child(_touch_pad)
	root.move_child(_touch_pad, 0)


## Build the palette, hand it the drawing and the keys, and fit it to the device.
##
## The controls themselves are `PalettePanel`'s: they are nine near-identical buttons and a handful of
## rows, every one of them derived from the tables the legend already uses, so a scene file would be a
## third copy of that list to keep in step. Built there, the palette is described once and its buttons
## exist because the tools do.
##
## What is left here is the two things that are this HUD's business rather than a panel's: handing over
## the drawing the palette reports on and the words this program writes for the keys, and asking the
## device whether the palette has to be fitted for a finger at all.
##
## The fit is deferred for the reason its own door keeps: these buttons are made during this HUD's
## `_ready` and the window has not been laid out at that moment, so a size asked for then is not the
## size the finished window draws at.
func _build_palette() -> void:
	_draft = view_controller.draft_controller()
	if _draft == null or palette_column == null:
		return
	# Every choice the panel reports is this HUD's to act on, and is connected here rather than inside
	# the panel, because what a tool *does* is the drawing's business and the panel owns none of it.
	palette_column.armed.connect(_on_arm_toggled)
	palette_column.tool_chosen.connect(_on_tool_pressed)
	palette_column.edit_chosen.connect(_on_edit_pressed)
	palette_column.command_chosen.connect(_on_palette_command)
	palette_column.layer_chosen.connect(_on_layer_chosen)
	palette_column.lock_chosen.connect(_on_lock_chosen)
	palette_column.build(_draft, _palette_keys())
	_refresh_palette()
	_size_palette_for_a_finger.call_deferred()


## The words this program writes for the keys the palette's buttons name, gathered once as it is built.
##
## Read from the bar's own table rather than listed a second time: every action the menu holds is looked
## up, and an action nothing is bound to comes back empty, which is what its button then says. That is
## the honest answer rather than a key this file invented.
func _palette_keys() -> Dictionary:
	var keys: Dictionary = { }
	keys[&"draft_mode"] = _key_label(&"draft_mode")
	for entry: Dictionary in menu_entries():
		var action: StringName = StringName(entry.get("action", &""))
		if action != &"":
			keys[action] = _key_label(action)
	return keys


## Run one of the palette's commands through the menu entry it stands for.
##
## A palette button reports the *action* it stands for and never a `Callable`, so a command cannot come
## to mean one thing in the bar and another in the palette beside the drawing. This is the join: the
## bar's own table is asked which entry owns that action, and `run_entry` runs it - the same door the
## menu and the command palette already share.
func run_the_action(action: StringName) -> bool:
	for entry: Dictionary in menu_entries():
		if StringName(entry.get("action", &"")) == action:
			return run_entry(entry)
	return false


## One of the drawing palette's commands, reported by the action the menu bar knows it by. The command
## palette has a handler of its own: that one takes a row off the list it filled, and this one takes an
## action, which is what lets a button beside the drawing run the bar's own entry rather than a copy of it.
func _on_palette_command(action: StringName) -> void:
	run_the_action(action)


## Fit this HUD's own chrome to the device, and leave a computer's exactly as the scene drew it.
##
## The palette is fitted by its own pass below, because the palette also has to re-flow its rows around the
## words it draws; this is everything else this HUD draws for itself - the menu bar and its menus, the
## panels, the hint lines, the scale bar. A page is left alone: a page answers for its own controls in the
## one place a page is shown, and `PageChrome` is that place.
##
## `draw_up` is the device answer taken as an argument rather than read here, the same door
## `PhoneHud.apply_if` keeps, so that a test can hold what a desk would be given. On a computer nothing is
## touched - not reset to the size a desk has, *left exactly as it was*.
## Fit this HUD's own chrome to the device, reading the device *now*.
##
## The reading is taken here rather than in `_ready` for the reason this whole pass is deferred: a window
## that has not laid out yet does not answer for the device it will be drawn on. Measured on the phone - the
## one instrument for this - the palette came out thumb-sized while the foot of the screen told that same
## thumb about a mouse wheel and W A S D, because `_size_palette_for_a_finger` asks the device where it draws
## and `_touch_screen` had been read a moment earlier, in `_ready`. The answer is kept on `_touch_screen`
## because `shows_touch_controls()` is the single question everything else asks - the hint lines, the thumb
## pad, the doors a demonstration opens - and the foot is written again here so that the two cannot disagree.
func _size_the_chrome_for_the_device() -> void:
	_touch_screen = PhoneHudScript.on_a_finger_here()
	size_for_a_finger(_touch_screen)
	# **Everything worked out from the room is stated in the one door below**, and that door is also the one a
	# turn goes through - which is the whole point of it. The bar's lift clear of the device's own band, the
	# strip no page may use, and the palette's own ground are all readings of the room, and stating them here
	# alone left a phone turned after launch keeping the chrome the room before the turn had asked for.
	# Measured on the A16W: the block taken lying down asks for nothing and the one taken standing shows the
	# three view buttons **81 px inside the band the camera keeps**, their middles inside it - the very fault
	# `lift_the_top_bar_by` exists to stop, on the one shape that was never re-asked. The order is that door's,
	# and it matters: the bar is lifted before the strip is read off its foot, and both before a page is placed
	# by them.
	_the_canvas_changed_shape()
	# The palette's two ends are held between the bar above it and the hint plate below it, on the frame after
	# this one: the fonts were changed a moment ago, so neither the bar's foot nor the plate's top stands where
	# the finished layout will put it, and a control asked for a size it has not laid out yet answers the size
	# it had before. The desk's own numbers are the floor, so a desk keeps exactly the rectangle it drew.
	place_the_left_column_for_a_device.call_deferred()
	# The dock is placed from the room and the band the device keeps along its foot, so it is read here where
	# the room is really known, and again on the frame after - a panel asked for its size before it has laid out
	# answers the size it had before, which is the same reason the palette's own placement is deferred.
	_place_the_touch_dock.call_deferred()
	# The six panels that stand over the board are moved by the same reading and put back by it too, so a desk
	# that was shown a finger's arrangement - which the layout check does, and then lets go of - is left exactly
	# as the scene drew it rather than holding a phone's panels.
	#
	# **Asked for again after it was withdrawn, because the reading could not yet name the fault.** Anchoring a
	# wrapper to a band and putting the child *in* the band are two different acts, and a report that has only
	# the child's rectangle cannot say which of them failed - `hud_layout_check` now prints the wrapper's band
	# beside the panel inside it, so the next reading decides it. If the wrapper is a band and the child is not in
	# it, the child needs a container that places its children, which is `BoardPanel` and nothing the engine
	# ships; if the wrapper was never banded at all, the fault is in `settle_a_panel_on_the_foot`.
	_place_the_overlay_panels.call_deferred()
	start_the_presentation_panel_for(_touch_screen)
	_refresh_hints()


## State the foot of this HUD's own top bar - the strip no page may be placed in - from the bar's own
## rectangle, and answer whether that foot has moved.
##
## **This is asked every frame, and asking it once was a fault measured on a phone.** The bar is not the size
## it is fitted at when the moment arrives: it is built and folded over the first dozen frames, so its foot moves
## under a page that was placed before it settled. Measured on the SM-A166W, the foot reads **357** on the block
## taken as this HUD starts and **247** on every block taken afterwards - the same 247 upright and lying, because
## it is the bar's own height and not the room's. The front door is shown as this HUD starts, so it was placed by
## the 357; and in landscape the begin-a-drawing page drew its own title bar straight over the menu titles.
##
## The room is what decides when a page is placed, so the two have to move together: this says when the bar's
## foot moved, and `_refresh_menus` puts the pages up back by the door a change of the room's shape already
## uses. The bar's *rectangle* is read rather than the offset the scene gives it, for the reason stated where
## the strip is first asked: a phone's bar is taller than a desk's and the scene's number is only the desk's.
func _state_the_strip_the_pages_may_not_use() -> bool:
	if top_bar == null:
		return false
	var foot: int = maxi(roundi(top_bar.get_global_rect().end.y), 0)
	if foot == PageChromeScript.reserved_above:
		return false
	PageChromeScript.reserved_above = foot
	return true


## Lift the top bar clear of whatever the device keeps for itself along the top of the screen - the status bar,
## the camera cutout, a rounded corner - and put it back exactly where the scene drew it where there is nothing
## to clear.
##
## The palette's own **left and right** offsets, remembered for the same reason `_palette_offsets_as_drawn` is, and
## kept as a second pair rather than a wider first one: that one is handed to `offsets_for_the_left_column`, whose
## answer is about the column's *height*, so widening it would put a horizontal number into an argument about a
## vertical one. Declared here, beside the one function that reads it.
var _palette_sides_as_drawn: Vector2 = Vector2(INF, INF)


## **This was the last thing on the screen standing in that band.** Measured on the A16W held upright, the three
## view buttons and the menus sat 81 px inside the strip the device keeps, with their middles at y 67, so a tap on
## `Fit` was answered by the system instead of by the program. Everything else had already learned it: a page's
## contents are lifted by `PageChrome.content_room_in`, a page is placed inside the insets, and a page's title bar
## is kept below this bar - the bar itself was the one thing that never asked.
##
## **Where a band is kept, the plate runs to the screen's own top and only its row is lifted.** The plate covers
## the band the camera sits in, so the bar reads as one pane running off the top of the glass, and the row of
## menus inside it is pushed clear. The plate given there is `ChromeStyle`'s, which is the one place a chrome
## plate is styled; where there is no band to clear the override is taken away and the bar is the bar the scene
## drew, to the pixel. A computer never moves at all, because `PhoneHud.cutout_top` answers zero for a screen
## with no safe area and for anything not served a finger.
func lift_the_top_bar_clear_of_the_device() -> void:
	var viewport: Viewport = get_viewport()
	var room: Vector2i = Vector2i(viewport.get_visible_rect().size) if viewport != null else Vector2i.ZERO
	lift_the_top_bar_by(PhoneHudScript.cutout_top(room))


## The measuring half, with the inset stated rather than read, so a test can hold what a phone would be told
## without being one - the same door `fit_the_chrome_for_a_finger` is.
##
## The inset is in the layout's own pixels, which is the space the bar's offsets are in: the room handed over is
## the viewport's, and `PhoneHud.cutout_here` answers in the units of the room it was asked about.
func lift_the_top_bar_by(inset: int) -> void:
	if top_bar == null:
		return
	if _bar_offsets_as_drawn.x == INF:
		_bar_offsets_as_drawn = Vector2(top_bar.offset_top, top_bar.offset_bottom)
	# **The plate the scene drew is remembered whole**, not only its margin: the plate that replaces it is derived
	# from it, so its paper, its corners and its insets are read off the one statement of them - and after the
	# override is set `get_theme_stylebox` answers the new plate rather than the scene's, which is why it is kept.
	if not top_bar.has_meta(&"plate_as_drawn"):
		top_bar.set_meta(&"plate_as_drawn", top_bar.get_theme_stylebox(&"panel"))
	var plate_as_drawn: StyleBox = top_bar.get_meta(&"plate_as_drawn")
	var down: float = float(maxi(inset, 0))
	var lifted: bool = down > 0.0
	# **The plate runs to the top of the screen and only its row is lifted.** Measured on the A16W, lifting the
	# plate as well left 212 px of bare sheet above the first button, which is what a person sees as a bar that is
	# not at the top. Where the device keeps a band along the top - a phone's camera cutout - the plate's own top
	# is the screen's own top, so the band is covered by the bar rather than by bare board and the row inside is
	# pushed clear of it.
	top_bar.offset_top = 0.0 if lifted else _bar_offsets_as_drawn.x
	top_bar.offset_bottom = _bar_offsets_as_drawn.y + down
	# The row is moved by the plate's own **content margin**, not by an offset: a `PanelContainer` lays its child
	# out itself, so an offset set on the child is overwritten by the next layout. The distance is the scene's own
	# margin, plus the distance the plate's top has just moved up, plus what the device keeps.
	if lifted:
		top_bar.add_theme_stylebox_override(
			&"panel",
			ChromeStyleScript.bar_plate(
				plate_as_drawn,
				plate_as_drawn.content_margin_top + _bar_offsets_as_drawn.x + down,
			),
		)
		top_bar.set_meta(&"row_lifted", true)
	elif top_bar.has_meta(&"row_lifted"):
		# **Nothing to clear, so the scene's own plate is handed back rather than left replaced** - a desk, or a
		# device that has stopped keeping a band: the override this pass put there is taken away, which is the whole
		# of what it did, and the bar is the bar the scene drew again.
		top_bar.remove_theme_stylebox_override(&"panel")
		top_bar.remove_meta(&"row_lifted")


## Give the plates at the foot of the screen the ground the device keeps there, and put them back exactly where the
## scene drew them where there is nothing to clear.
##
## **This is the one band the program is told rather than reads.** Godot's safe area is the display cutout and
## nothing more, so `screen_get_usable_rect` answers the whole screen over the A16W's **42 px** of nav bar - a band
## the phone's own report names (`overrideNonDecorFrame=[0,100][1080,2298]`) and the program cannot ask it for.
## `PhoneHud` states it for the devices this project has measured and answers zero for every other, so a desk and a
## phone nobody has put on this desk are both left exactly as the scene drew them.
func give_the_foot_line_clear_of_the_device() -> void:
	var viewport: Viewport = get_viewport()
	var room: Vector2i = Vector2i(viewport.get_visible_rect().size) if viewport != null else Vector2i.ZERO
	give_the_foot_line(PhoneHudScript.kept_foot(room))


## The measuring half, with the band stated rather than read, so a test can hold what a phone would be told
## without being one - the same door `lift_the_top_bar_by` is.
##
## **Both plates move, because both are the foot line**: `Hints` is what a working board reads and `DraftHints`
## what a tool in hand reads, and the two trade places in the same rows. **The scene's own offset is remembered and
## the band taken off it**, rather than a new offset written, because the desk's own numbers are the floor - which
## is what lets the band be handed back to the pixel on a device that turns out to keep nothing. Nothing here is
## styled, so unlike the bar there is no plate to hand back as well.
func give_the_foot_line(band: int) -> void:
	if hints == null and draft_hints == null:
		return
	var up: float = float(maxi(band, 0))
	for plate: PanelContainer in [hints, draft_hints]:
		if plate == null:
			continue
		if not plate.has_meta(&"foot_as_drawn"):
			plate.set_meta(&"foot_as_drawn", plate.offset_bottom)
		plate.offset_bottom = float(plate.get_meta(&"foot_as_drawn")) - up


## The gap the scene already keeps between the top bar's foot and the palette, and between the palette's foot
## and the hint plate: the bar's offsets end at 62 and the palette's begin at 70, the palette's end at 838 and
## the plate's begins at 846. Stated once, because the pass below has to keep the same gap when it moves
## either end, and only the scene's own numbers may say how big it is.
const PALETTE_GAP := 8.0


## The palette's top and bottom offsets, from the room above it and the room below it.
##
## Pure, and the whole of the placement: `place_the_left_column_for_a_device` reads the four numbers off the
## things themselves and this decides what to do with them, so what a phone would be told can be held by a
## test without being one - the split `PhoneHud.cutout_top` and `lift_the_top_bar_by` already keep.
##
## Both ends are **floors rather than assignments**. The top may only come down from where the scene drew it
## and the foot may only come up, so a desk - whose bar and plate both still agree with the scene's own
## numbers - is given exactly the offsets it was drawn with, to the pixel. The last line keeps one row of the
## palette standing even where the bar and the plate leave less room than that, because a palette squeezed to
## nothing is not a thing anyone can use, and the plate meeting it is the lesser of the two faults.
static func offsets_for_the_left_column(
	bar_foot: float,
	plate_top: float,
	drawn: Vector2,
	room: float,
	least: float,
) -> Vector2:
	var top: float = maxf(drawn.x, bar_foot + PALETTE_GAP)
	var foot: float = minf(drawn.y, plate_top - PALETTE_GAP - room)
	return Vector2(top, maxf(foot, top + least - room))


## Hold the palette between the two things it may not be drawn over: the top bar above it and the hint plate
## below it.
##
## The scene draws the palette's top at 70 and its foot 62 px above the canvas's foot, and both numbers are
## right for a desk - where the bar's foot is 62 and the plate is one line 42 px tall. **Both grow on a
## phone**, and neither was read back: the bar's buttons are a finger tall, so its foot is far below 70, and
## the plate's words wrap onto three lines at the phone's type, so its top is far above the palette's foot.
## Measured on the A16W held upright, the palette was drawn *over* the menu bar's own titles - so `File` and
## `View` could not be pressed at all - and the wrapped plate was drawn over the palette's last rows. **No
## instrument named either one**: a HUD plate meeting another has no candidate in `DrawnSurfaces`, and
## `hud_layout_check` measures a desk's type, where both numbers still agree.
##
## Each end is read off the thing itself rather than restated - the bar's foot from its own rectangle, after
## the lift that clears the device's own band, and the plate's top from its own, after its label has wrapped.
## The offsets the scene drew are **remembered once**, for the reason `_bar_offsets_as_drawn` is: this runs
## again on every change of the room's shape, and a placement measured from its own output would walk the
## palette up the screen one turn at a time.
##
## Called by the frame after that pass, because the fonts were changed a moment before it.
func place_the_left_column_for_a_device() -> void:
	if palette == null or top_bar == null or hints == null:
		return
	if _palette_offsets_as_drawn.x == INF:
		_palette_offsets_as_drawn = Vector2(palette.offset_top, palette.offset_bottom)
	# **The ground the device keeps at the left**, which this column was never given: a phone held sideways puts its
	# camera on the left, and measured on the A16W lying down the palette stood at x=16 while the device keeps the
	# first 100 px of the screen - so six of its controls each reached 55 px into that band and a thumb aimed at a
	# tool met the system instead. Read off `cutout_here`, the one reader of the band, and kept in its own pair for
	# the reason above. A desk's insets are all zero, so the scene's offsets come back to the pixel.
	if _palette_sides_as_drawn.x == INF:
		_palette_sides_as_drawn = Vector2(palette.offset_left, palette.offset_right)
	var band: Vector4i = PhoneHudScript.cutout_here(Vector2i(palette.get_parent_area_size()))
	var across: float = float(maxi(band.x, 0))
	palette.offset_left = _palette_sides_as_drawn.x + across
	palette.offset_right = _palette_sides_as_drawn.y + across
	# All three are siblings under `Root`, so a neighbour's own rectangle is already in the space the
	# palette's offsets are measured in, and the palette's parent area is the room they are measured against.
	var bar_foot: float = top_bar.position.y + top_bar.size.y
	var plate_top: float = hints.position.y
	var room: float = palette.get_parent_area_size().y
	var least: float = PhoneHudScript.row_height(PhoneHudScript.canvas_scale(get_window()), PhoneHudScript.dpi())
	var placed: Vector2 = offsets_for_the_left_column(bar_foot, plate_top, _palette_offsets_as_drawn, room, least)
	palette.offset_top = placed.x
	palette.offset_bottom = placed.y


# --- the furniture a finger gets instead of a desk's -----------------------------------------------------

## The tabs a phone's dock carries, left to right.
##
## **Every one of them is a door to something that already exists**, which is what keeps a dock from becoming a
## second place a tool is offered. `Draw` and `Dim` are the one `DraftTool.DRAFTING_TOOLS` list split where that
## list already splits - the six shapes and the measure first, the four dimensions after - `Edit` is
## `DraftController.EDIT_TOOLS`, `Plants` opens the library that already stands beside the palette, and `More`
## opens the drawer. `More` is not a menu of its own: a bar too narrow for fourteen menus already gathers the
## tail of them under a `More`, and this is that same gathering reached from the thumb's end of the screen.
## The phone's furniture's own three tables. Each is an **alias to the one value** `TouchFurniture` holds and not
## a copy of it, and they are named here because callers read them off *this* script by name: `test_touch_hud.gd`
## through `HudScript.TOUCH_TABS`, and `tools/console.gd` through this file's own constant map. No type is stated
## on them, because a constant given one cannot take its value from another script's constant.
const TouchFurnitureScript := preload("res://scripts/touch_furniture.gd")
const TOUCH_TABS = TouchFurnitureScript.TOUCH_TABS
const DIMENSION_KINDS = TouchFurnitureScript.DIMENSION_KINDS
const SHEET_OF_THE_ROOM = TouchFurnitureScript.SHEET_OF_THE_ROOM

## The tab in hand, by its name in `TOUCH_TABS`. Empty until one is pressed.
var _touch_tab: String = ""
## The drawer: the whole plan as one popup of one submenu per menu, made the first time somebody asks for it.
var _touch_drawer: PopupMenu = null


## Build the two pieces of furniture a finger gets and a desk does not: the row of controls that stands inside
## the top bar where the fourteen menus stand, and the dock along the foot of the screen.
##
## It builds nothing on a computer, and the two plates it wears are the scene's own look drawn again by
## `ChromeStyle` - a colour and a corner radius written here would be the drift that file exists to prevent.
func _build_touch_furniture() -> void:
	if touch_row == null or touch_dock == null or touch_tabs == null or touch_strip == null:
		return
	_build_the_touch_row()
	_build_the_touch_tabs()
	_apply_the_touch_plates()
	if touch_sheet_close != null and not touch_sheet_close.pressed.is_connected(_close_the_touch_sheet):
		touch_sheet_close.pressed.connect(_close_the_touch_sheet)


## The four controls the top bar carries on a phone, where a desk carries fourteen menus: the drawer, the layer
## the next shape is drawn on, the view, and the command palette.
##
## They are **words rather than the glyphs the shape of this furniture suggests**, and that is measured rather
## than chosen: this engine draws no glyph the theme's own font does not hold, and the two that read best on
## paper - a hamburger and a magnifier - are in none of the fonts a build carries. A button wearing an empty box
## says nothing at all, so each of these says what it does.
func _build_the_touch_row() -> void:
	if touch_row.get_child_count() > 0:
		return
	touch_row.add_child(_a_touch_button("Menu", "Everything the menus hold", _show_the_touch_drawer))
	touch_row.add_child(_a_touch_button("Layer", "The layer the next shape is drawn on", _show_the_layer_choices))
	touch_row.add_child(_a_touch_button("View", "The 2D plan, the 3D view and the ground", _turn_the_view))
	touch_row.add_child(_a_touch_button("Find", "Find a command by its name", toggle_command_palette))


## One button of the touch furniture, sized by the same two floors every other control on a device is sized by.
##
## **The height is `PhoneHud.row_height`, read rather than restated**, so a control built here and a palette
## fitted there cannot come out at two different heights on one screen. A button taller than its own row is what
## puts a control's middle inside a band the device keeps, which is a fault this project has measured twice.
func _a_touch_button(words: String, tooltip: String, door: Callable) -> Button:
	var button := Button.new()
	button.text = words
	button.tooltip_text = tooltip
	button.pressed.connect(door)
	# The focus is off every button the HUD draws, and for the reason the palette's own note keeps: Godot hands
	# Tab to focus navigation the moment a Control holds it, and a focused button swallows the keys a drawing
	# tool is driven by.
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(0.0, _touch_row_height())
	button.add_theme_font_size_override("font_size", _touch_type_size())
	return button


## A row's height on this device, in the room's own pixels.
func _touch_row_height() -> float:
	return PhoneHudScript.row_height(PhoneHudScript.canvas_scale(get_window()), PhoneHudScript.dpi())


## The size words are drawn at on this device: the millimetre floor `PhoneHud` states, never a number chosen here.
func _touch_type_size() -> int:
	return PhoneHudScript.font_size(PhoneHudScript.canvas_scale(get_window()), PhoneHudScript.dpi())


## The dock's tabs, one per name in `TOUCH_TABS`, each as wide a share of the row as the rest.
func _build_the_touch_tabs() -> void:
	if touch_tabs.get_child_count() > 0:
		return
	for tab: String in TOUCH_TABS:
		var button: Button = _a_touch_button(tab, _touch_tab_tooltip(tab), _press_a_touch_tab.bind(tab))
		button.toggle_mode = true
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		touch_tabs.add_child(button)


## What each tab opens, in the words a person reads on the glass.
func _touch_tab_tooltip(tab: String) -> String:
	match tab:
		"Draw":
			return "The shapes a plan is drawn with"
		"Dim":
			return "The dimensions a plan is measured with"
		"Edit":
			return "Change what is already drawn"
		"Plants":
			return "The plant library"
	return "The rest of the menu"


## **Show the two plates through `ChromeStyle`, off the plate the scene drew.** The bar's own look is read from
## `top_bar`, which is the one control in the scene wearing it, so the dock and the strip are the same pane as
## the bar rather than three panes three people styled. The dock is drawn wide and flat, so its corners are
## round at the top and square at the foot and its rule runs along the top edge alone; the strip floats, so it
## keeps every corner and the whole rule. On a desk the plates are still replaced - the look is identical, and a
## control that is never shown costs nothing.
func _apply_the_touch_plates() -> void:
	if top_bar == null:
		return
	var drawn: StyleBox = top_bar.get_theme_stylebox(&"panel")
	if touch_dock != null:
		touch_dock.add_theme_stylebox_override(&"panel", ChromeStyleScript.dock_plate(drawn, 0.0))
	if touch_strip != null:
		touch_strip.add_theme_stylebox_override(&"panel", ChromeStyleScript.floating_plate(drawn))
	# The sheet wears the plate for the panels anchored to the foot as well: one look, asked of the one function
	# that derives it from the bar's own. The six panels take theirs in `_place_the_overlay_panels`, which is
	# where their placement lives and which runs after they have been built.
	var along_the_foot: StyleBox = _a_dock_plate()
	if touch_sheet != null and along_the_foot != null:
		touch_sheet.add_theme_stylebox_override(&"panel", along_the_foot)


## Say which of the two arrangements is up: the dock and the row of controls, or the palette and the menus.
##
## `working` is the question the frame has already asked - whether the drawing's own furniture belongs on the
## screen at all - so a presentation and a painted sheet put this away with everything else.
func _show_the_touch_furniture(working: bool) -> void:
	var on_a_finger: bool = shows_touch_controls()
	if touch_row != null:
		touch_row.visible = on_a_finger and working
	# The menus stand exactly where they always did on a desk; on a finger the drawer is the same plan reached
	# from a button a thumb can hit, so the bar itself is not drawn twice.
	if menu_bar != null:
		menu_bar.visible = not on_a_finger
	if touch_dock != null:
		touch_dock.visible = on_a_finger and working
	# A sheet is part of the drawing's furniture rather than a page of its own, so a presentation or a painted
	# sheet puts it away with the rest - and whatever it borrowed is handed straight back when that happens.
	if touch_sheet != null and touch_sheet.visible and not (on_a_finger and working):
		_close_the_touch_sheet()


## Put the dock along the foot of the screen, above whatever the device keeps there for itself.
##
## The band is the one the devices this project has measured keep along their foot - the swipe that goes back,
## which the engine does not report as a safe area - and it is read off `PhoneHud` rather than stated here. On a
## desk every number is zero and the scene's own offsets come back unchanged, which is the same floor
## `offsets_for_the_left_column` keeps for the palette.
##
## The rect is stated **zero-height** and grows upward, because `grow_vertical` is the beginning: a panel's
## height is its own contents' and not a number written into a file for one screen.
func _place_the_touch_dock() -> void:
	if touch_dock == null or not shows_touch_controls():
		return
	var room: Vector2i = Vector2i(touch_dock.get_parent_area_size())
	var margin: float = float(
		PhoneHudScript.edge_margin(PhoneHudScript.canvas_scale(get_window()), PhoneHudScript.dpi())
	)
	var foot: float = float(PhoneHudScript.kept_foot(room))
	# **Two things the dock may not be drawn over, and the second is the one that was missed.** The first is the
	# band the device keeps along its foot - the swipe that goes back, which the engine does not report as a safe
	# area and which `PhoneHud` states instead. The second is the **line of hints**, which at a finger's type
	# wraps onto three lines and stands far higher up the screen than a desk's one-line plate does: a dock placed
	# above the device's band alone was drawn straight over the words a person is reading.
	#
	# This is the same fault `place_the_left_column_for_a_device` was written for, found on the other piece of
	# furniture and by the same instrument - a check that asks whether the panel stands *between* the bar's foot
	# and the foot line's top. Both ends are floors for the reason that placement keeps: a desk's own numbers are
	# already inside them and come back to the pixel.
	var from_the_foot: float = maxf(foot + margin, float(room.y) - _the_top_of_the_foot_line() + PALETTE_GAP)
	touch_dock.offset_left = margin
	touch_dock.offset_right = -margin
	touch_dock.offset_bottom = -from_the_foot
	touch_dock.offset_top = touch_dock.offset_bottom
	_place_the_touch_sheet.call_deferred()


## The top of the line of hints, in the room's own pixels: what is standing at the foot of the screen that the
## dock and the sheet may not be drawn over.
##
## Read off the plate's own rectangle rather than from the offsets the scene gave it, because that plate is
## exactly what moves when the type grows - the scene's 846 is right for a desk's one line of words and wrong by
## most of a screen for a phone's three.
##
## Zero when there is no plate to read, which is the honest answer for a hidden one: a plate that is not drawn
## cannot be drawn over, and a stale rectangle from a plate that was put away would hold this furniture up the
## screen for no reason at all.
func _the_top_of_the_foot_line() -> float:
	if hints == null or not hints.visible:
		return 0.0
	var where: Rect2 = hints.get_global_rect()
	return maxf(where.position.y, 0.0)


## Stand the sheet above the dock's own row rather than over it, so the tabs stay reachable while it is open -
## a sheet that covered its own door would be a panel with no way back to the board.
##
## **The dock's height is its own contents', so it is read rather than assumed**, and this is asked on the frame
## after the dock was placed for the reason every fitting here is deferred: a control asked for its size before
## it has laid out answers the size it had before. A sheet placed from a guess would either cover the tabs or
## leave a gap the width of a row.
##
## Its own height is a share of the room and not its contents' minimum: a sheet is the board with a panel over
## part of it, so it is *sized* to the room - a sheet that grew to its contents would cover the drawing it
## exists to leave visible.
func _place_the_touch_sheet() -> void:
	if touch_sheet == null or touch_dock == null or not shows_touch_controls():
		return
	var room: Vector2i = Vector2i(touch_sheet.get_parent_area_size())
	var margin: float = float(
		PhoneHudScript.edge_margin(PhoneHudScript.canvas_scale(get_window()), PhoneHudScript.dpi())
	)
	# Above the dock as the dock really stands - its own offsets, read rather than worked out a second time -
	# so the two cannot come to overlap: the dock has already been held clear of the foot line, and the sheet
	# inherits that clearance by standing on the dock's own top.
	var above_the_dock: float = absf(touch_dock.offset_bottom) + maxf(touch_dock.size.y, _touch_row_height())
	var tall: float = maxf(float(room.y) * SHEET_OF_THE_ROOM, 2.0 * _touch_row_height())
	touch_sheet.offset_left = margin
	touch_sheet.offset_right = -margin
	touch_sheet.offset_bottom = -above_the_dock
	touch_sheet.offset_top = -(above_the_dock + tall)


## The plate a panel wears on a finger: the dock's own look, drawn by the one place that states it.
##
## A sheet anchored to the foot has no visible foot edge, so it is round where a person sees it against the board
## and square where it runs off the glass, with its rule along the top edge alone. Every panel that stands there
## wears this, and it is `ChromeStyle`'s plate rather than a second one written here.
func _a_dock_plate() -> StyleBox:
	if top_bar == null:
		return null
	return ChromeStyleScript.dock_plate(top_bar.get_theme_stylebox(&"panel"), 0.0)


## The six panels that stand over the board, as the wrappers the HUD itself built.
##
## **Named by the HUD's own members rather than by a path.** A list of node paths would go stale the moment one
## was renamed, and a panel that was never built - the ones that need a drawing, in a HUD with none - is simply
## skipped rather than being a missing node to work around.
func _the_overlay_panels() -> Array[Control]:
	var out: Array[Control] = []
	for wrapper: Control in [_keys_panel, _site_report_panel, _dxf_panel, _hatch_page, _water_page, _light_page]:
		if wrapper != null:
			out.append(wrapper)
	return out


## One panel's wrapper anchored as a band along the foot of the screen, from the room's height and the three
## numbers the caller has read. Pure, and the whole of the placement: `_place_the_overlay_panels` reads the room
## and the device's own figures off the things themselves and this decides what to do with them, so what a phone
## would be told can be held by a test without being one - the same split `offsets_for_the_left_column` keeps.
##
## The wrapper is a `BoardPanel`, which puts the page in the band at the page's own size rather than stretching it
## to the room,
## which is what keeps a short panel short and a tall one from running past the top of the screen.
static func settle_a_panel_on_the_foot(wrapper: Control, margin: float, clear_of_the_foot: float, tall: float) -> void:
	if wrapper == null:
		return
	# The preset first and the offsets after, because a preset is allowed to move the offsets it is applied to
	# and numbers written before it would be overwritten.
	wrapper.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	wrapper.offset_left = margin
	wrapper.offset_right = -margin
	wrapper.offset_bottom = -clear_of_the_foot
	wrapper.offset_top = -(clear_of_the_foot + tall)
	# **And the child has to be asked to lay itself out again, or the band holds nothing.** Moving the anchors
	# resizes the wrapper, and a container that has not been told sorts nothing - so the band came out exactly
	# where it was meant to be and the panel inside it stayed where the *desk* had put it: measured, a weak
	# `205..610` band with its 257 px page at `603..870`, 398 px down it, which is 398 px down a 405 px band and
	# its desk position to the pixel. **A container the engine ships centres its child and carries no lever to be
	# asked harder** - `queue_sort` was tried and changed nothing - so the child is put in the band by
	# `BoardPanel`, which is this project's own node and does the placing on a rectangle it works out itself.
	var board: BoardPanel = wrapper as BoardPanel
	if board != null:
		board.along_the_foot = true
		board.place_the_page()


## Stand the six panels along the foot of the screen on a finger, where a desk centres them over the board.
##
## **It is called from `_size_the_chrome_for_the_device` and it works: the band holds its panel.** Two readings
## took it there, and both are worth keeping because the fault moved. The band itself was right from the first
## attempt - `SiteReportPanel`'s wrapper stood at `205..610` - and its 257 px page stayed at `603..870`, which is
## 398 px down a 405 px band and the panel's *desk* position to the pixel. Asking the wrapper's own container to
## sort itself again (`queue_sort`) said the same, and the reason is that the node was a `CenterContainer`: it
## centres a child in whatever room it has and carries no alignment to ask for anything else, **and no container
## the engine ships places a child where it is told**. So the wrapper is now `BoardPanel`, which computes the
## rectangle itself - and the same reading then gave `SiteReportPanel` its page at `343..610` and `DxfPanel` at
## `241..610`: a foot on the band's own foot, which is what a sheet along the foot means.
##
## **The four long panels are still refused the band.** They want 4189, 1518, 1518 and 941 px of a 405 px band at
## a finger's type, and what they need is the scroller `PageChrome` already gives an over-tall page - the same
## answer this program has for anything taller than the room it stands in. That is a piece of work of its own and
## they keep the desk's own placement until it is done.
##
## **The board stays visible, which is the whole point of the change.** A desk's room is wide, and a panel 520 px
## across leaves plenty of drawing either side of it; a phone's room is a hand's width, so the same panel centred
## lands squarely over the middle of the work - the one place a person is looking. Anchored to the foot it takes
## the strip at the bottom of the screen instead, which a thumb covers anyway.
##
## Nothing new has to be pressed to put one away: **every one of these six was already built with its own Close
## button**, so the header a sheet needs is the header it has. This states where they stand and what they wear,
## not how they are worked.
##
## **A panel too tall for the band is refused the band by name and left where the desk draws it.** Four of the six
## are longer than the screen at a finger's type, and a `CenterContainer` centres its child - so a taller-than-band
## panel would be centred *in the band* and land off the top of the screen, worse than the middle of the board it
## sits over now. Those four still want the scroller every over-tall page already gets from `PageChrome`.
##
## A desk is put back exactly as the scene left it - the full-rect wrapper and the plate the scene's own bar
## carries - because a tool that states a finger and then releases it (the layout check does) must not leave the
## desk holding a phone's arrangement.
func _place_the_overlay_panels() -> void:
	var on_a_finger: bool = shows_touch_controls()
	for wrapper: Control in _the_overlay_panels():
		var page: Control = wrapper.get_node_or_null(^"Page") as Control
		if on_a_finger:
			var room: Vector2i = Vector2i(wrapper.get_parent_area_size())
			var margin: float = float(
				PhoneHudScript.edge_margin(PhoneHudScript.canvas_scale(get_window()), PhoneHudScript.dpi())
			)
			var foot: float = float(PhoneHudScript.kept_foot(room))
			if touch_dock != null:
				# Above the dock rather than above the room's own foot: a panel opened from the dock that stood
				# over the dock's tabs would take away the one control that opened it.
				foot = absf(touch_dock.offset_bottom) + maxf(touch_dock.size.y, _touch_row_height())
			var tall: float = maxf(float(room.y) * SHEET_OF_THE_ROOM, 2.0 * _touch_row_height())
			# **Whether a panel can be a sheet is asked of the module that owns the question**, not worked out
			# here: `PageLayout.wanted_contents` is how tall the contents of a page's column come to, with the
			# gaps between them and any hidden row left out - the very figure `hud_layout_check` prints when it
			# says a column wants so many pixels in the box it has. A number worked out a second time here could
			# disagree with the line a person reads in the audit.
			#
			# **Only a panel that fits the band is given it.** Four of these six are far taller than the screen at
			# a finger's type - the keys reference and the water and light panels are lists - and `BoardPanel`
			# stands its page at the page's own size, so a taller-than-band panel would have its top pushed off
			# the band and land off the top of the screen. Measured at this desk room on a finger: `KeysPanel`
			# wants 4189 px against a 405 px band, `WaterPanel` and `LightPanel` 1518, and `HatchPanel` 941 -
			# while `SiteReportPanel` and `DxfPanel` fit, and are banded.
			#
			# A panel that cannot be a sheet is left exactly as the desk draws it, and what it still wants is the
			# scroller every over-tall *page* already gets from `PageChrome` - the same answer this program has
			# for anything taller than the room it stands in.
			var column: Control = null
			if page != null:
				column = page.get_node_or_null(PageChromeScript.COLUMN_NAME) as Control
			var wants: float = PageLayoutScript.wanted_contents(column).y if column != null else INF
			if wants <= tall:
				settle_a_panel_on_the_foot(wrapper, margin, foot + PALETTE_GAP, tall)
				var plate: StyleBox = _a_dock_plate()
				if plate != null:
					page.add_theme_stylebox_override(&"panel", plate)
			else:
				wrapper.set_anchors_preset(Control.PRESET_FULL_RECT)
				# The desk's own arrangement, laid out again for the reason the band is: what was moved has to be
				# told, or the panel keeps the place the finger's band gave it after the desk has taken it back.
				var off_the_band: BoardPanel = wrapper as BoardPanel
				if off_the_band != null:
					off_the_band.along_the_foot = false
					off_the_band.place_the_page()
		else:
			wrapper.set_anchors_preset(Control.PRESET_FULL_RECT)
			if page != null and top_bar != null:
				page.add_theme_stylebox_override(&"panel", top_bar.get_theme_stylebox(&"panel"))


## One tab was pressed.
##
## **Two of the five tabs are doors rather than groups**, and they are opened without touching the strip: the
## plant picker opens as a sheet over the board, and `More` is the drawer. The three that are groups **put the
## palette's own buttons back before taking the ones they want**, so a tool is one button in one place at a time
## and switching tabs cannot leave a group stranded in the strip.
##
## **A second press on the tab in hand puts the strip away.** A group is a thing a thumb opens and closes, and
## the room above the dock belongs to the board whenever nothing is being chosen - which is most of the time.
func _press_a_touch_tab(tab: String) -> void:
	var putting_it_away: bool = tab == _touch_tab and touch_strip != null and touch_strip.visible
	if tab == "Plants":
		_touch_tab = tab
		_mark_the_touch_tab()
		_open_the_plant_sheet()
		return
	if tab == "More":
		_touch_tab = tab
		_mark_the_touch_tab()
		_show_the_touch_drawer()
		return
	if putting_it_away:
		_touch_tab = ""
		if touch_strip != null:
			touch_strip.visible = false
		_put_the_touch_tools_back()
		_mark_the_touch_tab()
		return
	_touch_tab = tab
	_mark_the_touch_tab()
	_put_the_touch_tools_back()
	var wanted: Array[Button] = _touch_tools_for(tab)
	if touch_strip == null or touch_strip_row == null:
		return
	touch_strip.visible = not wanted.is_empty()
	for button: Button in wanted:
		button.reparent(touch_strip_row, false)
	_fit_the_touch_strip.call_deferred()


## Say which tab is in hand, on the tabs themselves.
##
## A toggle button that is down is the whole of what a person is told about which group the strip is showing,
## and nothing else on the screen says it: the strip's own buttons carry no group name, because a tool's name is
## its own. The tabs are told here rather than left to the engine's own toggling, so the row cannot come to show
## two tabs down - which is what a press the engine toggled while this file cleared a different one would do.
func _mark_the_touch_tab() -> void:
	if touch_tabs == null:
		return
	for child: Node in touch_tabs.get_children():
		if child is Button:
			var button: Button = child as Button
			button.button_pressed = button.text == _touch_tab


## The buttons one group tab shows: the palette's own, filtered - never a second list of tools.
func _touch_tools_for(tab: String) -> Array[Button]:
	var out: Array[Button] = []
	if palette_column == null:
		return out
	var tools: Array[Button] = palette_column.tool_buttons()
	if tab == "Edit":
		return palette_column.edit_buttons()
	# Which of them a tab wants is the dimension split, and it is stated once in the furniture's own module:
	# asked for the indices, so the buttons stay this file's to name.
	for index: int in TouchFurnitureScript.tool_indices_for_a_tab(tab):
		out.append(tools[index])
	return out


## Open the sheet: a plate over the board's foot, titled and closable, holding whatever a tab put in it.
##
## **A sheet rather than a page.** A page is a `Window` the width of the screen, and it is where a person goes to
## do something; a sheet stands over part of the board, which is what choosing a plant wants - the bed being
## planted stays on the screen while the picker is in hand. Opening one puts the strip away, because the two
## share the room above the dock and a strip left standing under a sheet is furniture with nothing to do.
func _open_the_touch_sheet(title: String) -> void:
	if touch_sheet == null:
		return
	_put_the_touch_tools_back()
	if touch_strip != null:
		touch_strip.visible = false
	if touch_sheet_title != null:
		touch_sheet_title.text = title
	touch_sheet.visible = true
	_place_the_touch_sheet.call_deferred()


## Close the sheet and hand back whatever it borrowed.
func _close_the_touch_sheet() -> void:
	if touch_sheet == null or not touch_sheet.visible:
		return
	touch_sheet.visible = false
	_return_what_the_sheet_borrowed()
	# The tab that opened it is no longer holding anything, so it comes up with the sheet: a tab left down over
	# an empty stretch of board would say a group is being shown when nothing is.
	if _touch_tab == "Plants":
		_touch_tab = ""
		_mark_the_touch_tab()


## **The sheet borrows; it does not copy.** The plant picker is `PalettePanel`'s own panel - the very one a desk
## has standing beside the plan - moved in for as long as the sheet is up and handed back when it closes.
##
## A second picker built for a phone would be a second catalogue to keep in step with the first, which is the
## fault this project works hardest to avoid, and a plant chosen from one would reach the drawing by a different
## door than a plant chosen from the other. What the sheet adds is a place to stand, not a thing to press.
func _open_the_plant_sheet() -> void:
	_open_the_touch_sheet("Plants")
	if _plant_panel == null or touch_sheet_body == null:
		return
	if _plant_panel.get_parent() == touch_sheet_body:
		return
	_plant_panel.reparent(touch_sheet_body, false)


## Hand a borrowed panel back to the column it was built in, so a desk - and the next opening of the palette -
## finds it exactly where it belongs.
func _return_what_the_sheet_borrowed() -> void:
	if _plant_panel == null or palette_column == null:
		return
	if _plant_panel.get_parent() != palette_column:
		_plant_panel.reparent(palette_column, false)


## Return every button standing in the strip to the column it was built in.
func _put_the_touch_tools_back() -> void:
	if palette_column == null or touch_strip_row == null:
		return
	for child: Node in touch_strip_row.get_children():
		if child is Button:
			(child as Button).reparent(palette_column, false)


## Lay the strip's buttons out for a finger, on the frame after they were moved: a control asked for a size
## before it has laid out answers the size it had before, which is the reason every fitting in this file is
## deferred.
func _fit_the_touch_strip() -> void:
	if touch_strip_row == null:
		return
	ToolPaletteScript.fit_a_strip(touch_strip_row, PhoneHudScript.canvas_scale(get_window()), PhoneHudScript.dpi())


## Show the drawer: the whole plan gathered as one popup of one submenu per menu.
##
## **It is the plan through the bar's own renderer**, not a second menu written for a phone. `_build_menu` fills
## the popups and keeps the entries, so an entry added to the plan arrives here and in the bar in one edit, an
## entry whose need this scene cannot meet is shown switched off by the same rule, and its tick is set by the
## same pass that sets the bar's own. What is built here is one level of nesting, which is a *gathering* of the
## plan rather than another statement of it.
func _show_the_touch_drawer() -> void:
	if _touch_drawer == null:
		_touch_drawer = _a_drawer()
		add_child(_touch_drawer)
	_where_the_drawer_stands(_touch_drawer)
	_touch_drawer.popup()


## The drawer's popup, built from the plan itself.
func _a_drawer() -> PopupMenu:
	var drawer := PopupMenu.new()
	drawer.name = "TouchDrawer"
	_build_menu(drawer, touch_drawer_plan(menu_plan()))
	return drawer


## The plan gathered for the drawer: **one submenu per menu**, named by the menu's own title and holding the
## menu's own items.
##
## Static and pure, so what the drawer offers can be held against what the bar offers without a popup, a scene
## or a device - which is the question that matters about it. Nothing here words a command, names a method or
## decides a need: it is a *gathering*, and every one of those things is still read off the plan by the bar's
## own renderer when the popup is filled.
## The menu plan gathered as the drawer's own submenus - a **door** onto the furniture module, kept under this
## name because `tests/test_touch_hud.gd` reaches for it here and reads it off this script.
static func touch_drawer_plan(plan: Array[Dictionary]) -> Array[Dictionary]:
	return TouchFurnitureScript.drawer_plan(plan)


## Put the drawer under the button that opened it, and fit its words to the finger that will press them - the
## bar's own menus keep the same fitting for the same reason.
func _where_the_drawer_stands(drawer: PopupMenu) -> void:
	# The row if it is there and the bar otherwise, written as its own assignment rather than as a ternary:
	# the two are siblings with no common ancestor below `Control`, and GDScript refuses a conditional whose
	# values it cannot reconcile - which is a parse error, not a warning.
	var anchor: Control = top_bar
	if touch_row != null:
		anchor = touch_row
	if anchor != null:
		var where: Rect2 = anchor.get_global_rect()
		drawer.position = Vector2i((where.position + Vector2(0.0, where.size.y)).round())
	if shows_touch_controls():
		PhoneHudScript.fit_the_chrome_for_a_finger(
			drawer,
			PhoneHudScript.canvas_scale(get_window()),
			PhoneHudScript.dpi(),
		)


## The layers the next shape can be drawn on, offered as a popup.
##
## The names are the palette's own list and the choice goes to **the same door the palette's own signal
## reaches**, so a layer chosen from here and one chosen from the column are one act and not two.
func _show_the_layer_choices() -> void:
	if palette_column == null:
		return
	var names: Array[StringName] = palette_column.layer_names()
	if names.is_empty():
		return
	var chooser := PopupMenu.new()
	chooser.name = "TouchLayers"
	for layer_name: StringName in names:
		chooser.add_item(String(layer_name))
	chooser.id_pressed.connect(_choose_a_layer_from.bind(chooser, names))
	chooser.close_requested.connect(chooser.queue_free)
	add_child(chooser)
	_where_the_drawer_stands(chooser)
	chooser.popup()


## A layer was chosen, by the index of the name in the list the popup was filled from.
func _choose_a_layer_from(index: int, chooser: PopupMenu, names: Array[StringName]) -> void:
	chooser.queue_free()
	if index >= 0 and index < names.size():
		_on_layer_chosen(names[index])


## The one view control the top bar carries on a finger: the same door the desk's own button presses.
func _turn_the_view() -> void:
	if view_controller != null:
		view_controller.toggle_overhead()


func size_for_a_finger(draw_up: bool) -> int:
	if not draw_up:
		return 0
	var fitted: int = fit_the_chrome_for_a_finger(PhoneHudScript.canvas_scale(get_window()), PhoneHudScript.dpi())
	_put_away_what_the_top_bar_cannot_hold()
	return fitted


## The measuring half of `size_for_a_finger`, with the scale and the density stated rather than read, so a
## test can hold what a phone would be told without being one.
func fit_the_chrome_for_a_finger(drawn_at: float, density: float) -> int:
	return PhoneHudScript.fit_the_chrome_for_a_finger(self, drawn_at, density)


## Put away what the top bar holds that is not a door, which is what a room too narrow for the bar has to be
## able to do.
##
## The bar is one row: the menu bar, the program's name, a rule, the view's name, and the three view controls.
## At a phone's legible size that row is far wider than the screen, and an `HBoxContainer` does not shrink any
## of them to fit - it lays them out at their own minimums and lets the row run off the edge. **Measured on
## the phone, the three view buttons came out at x = 1860 on a 1080-wide screen**: drawn where nothing can
## reach them, and on a device with no keyboard they are the *only* way to the 2D, 3D and ground views.
##
## So the row gives up what a bar can afford to lose, and the rule it follows is which of its parts are
## **doors**: the menus, which fold into one `More`; the three view controls; and nothing else. The program's
## name is not a door - the launcher, the doorway and the sheet's own title block all say it already - and
## neither is the rule that existed only to divide it, nor the view's name, which the view controls say
## themselves: the button reads "2D plan (Q)" from the 3D view, "3D view (Q)" from the plan, and "Back to
## overhead (G)" from the ground. Those three are what this puts away.
##
## Measured twice, because the first version of this was nearly right and not right: with only the name and
## the rule gone, the row still came to **1294 px of a 1161 px room**, and the last button's frame ran 133 px
## past the edge - reachable by its centre, which is not the same as drawn. A phone is the instrument for that
## second reading, and the probe above is how it was taken.
##
## The bar then folds as it was always meant to: with the decoration gone the room formula in `menu_bar_room`
## has a figure it can work with, where before everything else in the row was wider than the screen, the room
## came out zero, and `menu_fold_point` read zero as "no room was worked out" and switched the fold off - all
## fourteen titles were drawn and the buttons were pushed off the edge behind them.
##
## A computer is not touched, and is not restored either: this runs only under `size_for_a_finger(true)`, so
## the row a desk draws is the row the scene drew.
func _put_away_what_the_top_bar_cannot_hold() -> void:
	if app_label != null:
		app_label.visible = false
	if bar_separator != null:
		bar_separator.visible = false
	if mode_label != null:
		mode_label.visible = false


## Fit the palette to the device and re-flow its rows around the words it draws.
##
## Deferred rather than done where the buttons are built, because a button is made during this HUD's
## `_ready` and the window has not been laid out at that moment: asked then, it reported a scale of
## 3.6 where the finished window uses 1.35, which would have made every row *smaller* than the
## desk's own. A frame later the window can answer - and on a computer every answer is "leave it
## as it is", because `on_a_finger_here()` below is what decides whether any of this runs.
##
## Whether to fit is this HUD's business and is asked here; what the fitting *is* belongs to
## `ToolPalette`, which is handed the panel, the column and the device's own scale and density.
##
## The two re-flows follow by a frame, for the reason `ToolPalette.reflow_the_tool_row` keeps: a
## control asked for a size it has not laid out yet answers the size it had before, and the fonts
## were changed a moment ago. Measured in one pass they were all a frame behind, and the panel came
## out 180 px too narrow.
func _size_palette_for_a_finger() -> void:
	if palette_column == null:
		return
	if not PhoneHudScript.on_a_finger_here():
		return
	ToolPaletteScript.fit(palette_column, PhoneHudScript.canvas_scale(get_window()), PhoneHudScript.dpi())
	_reflow_the_tool_row.call_deferred()
	_reflow_the_edit_row.call_deferred()


func _reflow_the_tool_row() -> void:
	ToolPaletteScript.reflow_the_tool_row(palette, palette_column, palette_column.tool_buttons())


func _reflow_the_edit_row() -> void:
	ToolPaletteScript.reflow_the_edit_row(palette, palette_column, palette_column.edit_buttons())
	_grow_palette_to_its_contents.call_deferred()


## Widen the panel to hold the column it carries, on the frame after the re-flow that made it wider.
func _grow_palette_to_its_contents() -> void:
	ToolPaletteScript.grow_to_its_contents(palette, palette_column)


## Match the palette to the controller.
##
## The panel decides what to draw from the drawing it reads and a signature it keeps; what is worked
## out here is the two facts that are this HUD's rather than a palette's - whether the layer in hand is
## locked, and what the undo and redo buttons would act on, which is a sentence about the drawing.
##
## This is called every frame, and the panel does nothing at all when its signature has not moved.
func _refresh_palette() -> void:
	if palette_column == null:
		return
	# The two gesture labels are part of what the panel's signature holds because they are what those
	# tooltips say: without them a tooltip would keep naming the gesture that was in hand when the
	# palette last redrew, which is exactly the confusion the labels exist to remove.
	var undo: String = _gesture_tooltip("Undo", _undo_label(), &"draft_undo")
	var redo: String = _gesture_tooltip("Redo", _redo_label(), &"draft_redo")
	palette_column.refresh(_is_layer_locked(), undo, redo)


## The gesture an undo would undo, in words, or empty when there is none - or when there is no drawing
## to ask, which a HUD built without one has to survive.
func _undo_label() -> String:
	if _draft == null or _draft.document == null:
		return ""
	return _draft.document.undo_label()


func _redo_label() -> String:
	if _draft == null or _draft.document == null:
		return ""
	return _draft.document.redo_label()


## What an undo or redo button says about itself: the verb, the gesture it would act on, and the key.
## "nothing to undo" rather than a bare verb when the history has run out, because a button that cannot
## say why it would do nothing is a button that looks broken rather than finished.
static func _gesture_tooltip(verb: String, gesture: String, action: StringName) -> String:
	var words := "%s %s" % [verb, gesture] if not gesture.is_empty() else "nothing to %s" % verb.to_lower()
	var key := _key_label(action)
	return "%s (%s)" % [words, key] if key != "" else words


func _on_arm_toggled(pressed: bool) -> void:
	if _draft != null:
		_draft.set_drawing(pressed)


func _on_tool_pressed(kind: int) -> void:
	if _draft != null:
		_draft.arm(kind)


func _on_edit_pressed(kind: int) -> void:
	arm_edit_command(kind)


## The layer the panel reports, by name. The name is the panel's: it built its drop-down from the
## drawing's own layer choices, so this turns nothing back into anything.
func _on_layer_chosen(layer_name: StringName) -> void:
	if _draft != null:
		_draft.set_layer(layer_name)


## Whether the layer the drawing is on is locked. False with nothing to draw on, so a HUD with
## no drawing shows an unlocked, unpressable check box rather than failing.
func _is_layer_locked() -> bool:
	if _draft == null or _draft.document == null:
		return false
	return _draft.document.is_layer_locked(_draft.current_layer())


## Lock or unlock the layer in hand. The lock belongs to the layer rather than to this button, and
## it is recorded as one undo step like any other change to the drawing - a lock somebody tripped
## over is a change they may want back.
##
## Public because the decision is worth testing without a built palette, and because one door for
## locking a layer is the same discipline as one door for editing one.
func set_layer_locked(locked: bool) -> void:
	if _draft == null or _draft.document == null:
		return
	# Named `layer_name` rather than `layer`: the Hud is a CanvasLayer, so a local called `layer`
	# would shadow the canvas layer the HUD itself is drawn on.
	var layer_name: StringName = _draft.current_layer()
	var words: String = "locking %s" % layer_name if locked else "unlocking %s" % layer_name
	_draft.document.begin_gesture(words)
	_draft.document.layers.set_locked(layer_name, locked)
	_draft.document.changed.emit()


## The lock the panel reports. The panel reads its own button rather than the signal's argument, for
## the reason it gives: the refresh writes that box, and reading the argument would let a refresh
## arriving mid-click report a lock it had just drawn - the bug the silent setter exists to avoid.
func _on_lock_chosen(locked: bool) -> void:
	set_layer_locked(locked)


## What one tool button says: the tool on the first line, the key that does the same
## thing on the second, so the palette teaches the shortcut while it is being used.
static func palette_label(pair: Array) -> String:
	return PalettePanelScript.label(pair, _key_label(pair[0]))


## The same, for one of the editing commands.
static func edit_palette_label(pair: Array) -> String:
	return PalettePanelScript.label(pair, _key_label(pair[0]))


## Keep the HUD out of the keyboard focus chain.
##
## Godot hands Tab to focus navigation as soon as a Control holds it, and a focused
## Button swallows the keys the drawing tools are driven by: the moment the palette was
## clicked, Tab stopped reaching the view switch and Enter started pressing the button
## that had focus rather than finishing the shape. Nothing in the HUD is typed into, so
## nothing in it should hold the keyboard, and every key belongs to the drawing.
static func release_keyboard_focus(root: Node) -> void:
	for found: Node in root.find_children("*", "Button", true, false):
		# A Button inside a Window is a *dialog's* own - Save, Cancel, Keep editing - and a modal
		# dialog is meant to hold the keyboard while it is up. Taking its buttons out of the focus
		# chain too left the dialog unable to focus the one it opens on: it appeared, and the
		# engine logged "This control can't grab focus" at the moment of popping up.
		if _inside_window(found):
			continue
		(found as Button).focus_mode = Control.FOCUS_NONE


## Whether a node lives inside a Window - a dialog rather than the HUD's own furniture.
static func _inside_window(node: Node) -> bool:
	var walk: Node = node
	while walk != null:
		if walk is Window:
			return true
		walk = walk.get_parent()
	return false

# --- the client presentation ----------------------------------------------------------


## The presentation panel: start a client presentation, choose what it is rendered at,
## aim the sun, and render a proposal still.
##
## Built in code rather than in the scene, for the same reason the palette's buttons
## are: every control here is derived from a table (`PresentationTier.LOOKS` and
## `STILL_SIZES`), so a scene file would be a second copy of those tables to keep in
## step with the first.
##
## A scene with no director gets no panel at all, rather than a panel full of dead
## buttons: this is the one GUI in the project that may legitimately not exist.
func _build_presentation_panel() -> void:
	if presentation == null or presentation_column == null:
		# A scene with no director gets no panel at all. The one owner of the panel's visibility is asked
		# here rather than a second assignment written: with no presentation it answers `false` for exactly
		# the reason the owner already states, and there is then nowhere a stale answer can be hiding.
		_refresh_presentation_panel()
		return

	var heading := Label.new()
	heading.text = "Presentation"
	presentation_column.add_child(heading)

	_present_toggle = CheckButton.new()
	_present_toggle.name = "PresentationToggle"
	_present_toggle.text = "Client presentation"
	_present_toggle.tooltip_text = (
		"Walk a client through the garden: right-drag to orbit, wheel to dolly, "
		+ "middle-drag to pan. The working tools are put away."
	)
	_present_toggle.toggled.connect(_on_presentation_toggled)
	presentation_column.add_child(_present_toggle)

	var tier_row := HBoxContainer.new()
	tier_row.name = "TierRow"
	var tier_caption := Label.new()
	tier_caption.text = "Quality"
	tier_row.add_child(tier_caption)
	_tier_option = OptionButton.new()
	_tier_option.name = "TierOption"
	_tier_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tier_option.tooltip_text = "What the renderer is allowed to spend"
	for tier in TierScript.CHOICES:
		_tier_option.add_item(TierScript.name_of(tier))
	_tier_option.item_selected.connect(_on_tier_selected)
	tier_row.add_child(_tier_option)
	presentation_column.add_child(tier_row)

	presentation_column.add_child(HSeparator.new())

	var sun_caption := Label.new()
	sun_caption.text = "Sun"
	presentation_column.add_child(sun_caption)
	# The site and the moment, one field to a row. Labelled rather than suffix-only, because
	# two of these five numbers are degrees, two are hours and the latitude and the longitude
	# would otherwise be told apart by position alone.
	var sun_grid := GridContainer.new()
	sun_grid.name = "SunGrid"
	sun_grid.columns = 2
	# A tenth of a degree of latitude, so the site's own latitude survives being put in
	# the box: at half a degree the panel would silently move the garden 5 km north. Half a
	# degree of longitude is two minutes of solar time, which is fine for a longitude.
	_sun_hour = _spin(
		"SunHour",
		0.0,
		24.0,
		0.5,
		" h",
		16.0,
		"Clock time at the site. The sun's own noon is up to sixteen minutes off the clock's.",
	)
	_sun_day = _spin("SunDay", 1.0, 366.0, 1.0, " d", 172.0, "Day of the year. 172 is the solstice.")
	_sun_latitude = _spin(
		"SunLatitude",
		-90.0,
		90.0,
		0.1,
		"°",
		45.0,
		"Degrees north, so negative is south. The number that makes a shadow study mean anything.",
	)
	_sun_longitude = _spin(
		"SunLongitude",
		-180.0,
		180.0,
		0.5,
		"°",
		-75.0,
		"Degrees east, so negative is west. Four minutes of solar time to a degree: this is what makes a clock time the site's sky rather than the sky at Greenwich.",
	)
	# A quarter hour, because the world's zones are not all whole hours apart.
	_sun_utc_offset = _spin(
		"SunUtcOffset",
		-12.0,
		14.0,
		0.25,
		" h",
		-5.0,
		"Hours from UTC in force at the site. Daylight saving belongs here rather than in a rule, since a rule is right in one country and wrong in the next: in summer this is an hour ahead of standard time, which is why every sunrise reads an hour later.",
	)
	_add_sun_field(sun_grid, "Hour", _sun_hour)
	_add_sun_field(sun_grid, "Day", _sun_day)
	_add_sun_field(sun_grid, "Latitude", _sun_latitude)
	_add_sun_field(sun_grid, "Longitude", _sun_longitude)
	_add_sun_field(sun_grid, "UTC offset", _sun_utc_offset)
	presentation_column.add_child(sun_grid)

	var sun_buttons := HBoxContainer.new()
	sun_buttons.name = "SunButtons"
	var apply_button := Button.new()
	apply_button.name = "ApplySun"
	apply_button.text = "Apply the sun"
	apply_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	apply_button.pressed.connect(_on_apply_sun)
	sun_buttons.add_child(apply_button)
	var frame_button := Button.new()
	frame_button.name = "FrameYard"
	frame_button.text = "Frame the garden"
	frame_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame_button.tooltip_text = "Pull the camera back until the whole garden fits"
	frame_button.pressed.connect(_on_frame_yard)
	sun_buttons.add_child(frame_button)
	presentation_column.add_child(sun_buttons)

	# The site is a fact about the drawing, so the panel offers to make it one. Without
	# this the five fields would be a study of somewhere else that is thrown away the
	# moment the drawing is reloaded.
	var save_site_button := Button.new()
	save_site_button.name = "SaveSite"
	save_site_button.text = "Save the site to the drawing"
	save_site_button.tooltip_text = "Keep this latitude, longitude and offset with the plan"
	save_site_button.pressed.connect(_on_save_site)
	presentation_column.add_child(save_site_button)

	presentation_column.add_child(HSeparator.new())

	var still_row := HBoxContainer.new()
	still_row.name = "StillRow"
	var still_caption := Label.new()
	still_caption.text = "Still"
	still_row.add_child(still_caption)
	_still_size_option = OptionButton.new()
	_still_size_option.name = "StillSize"
	_still_size_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_still_size_option.tooltip_text = "The size of the image a proposal gets"
	for choice: Array in STILL_SIZES:
		_still_size_option.add_item(String(choice[0]))
	still_row.add_child(_still_size_option)
	var render_button := Button.new()
	render_button.name = "RenderStill"
	render_button.text = "Render"
	render_button.tooltip_text = "Render the current view at that size and write it out"
	render_button.pressed.connect(_on_render_still)
	still_row.add_child(render_button)
	presentation_column.add_child(still_row)

	_still_status = Label.new()
	_still_status.name = "StillStatus"
	_still_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_still_status.custom_minimum_size = Vector2(280.0, 0.0)
	presentation_column.add_child(_still_status)

	# The director reports what it did; the HUD is what takes its own furniture out of
	# the picture, because the furniture is the HUD's.
	presentation.presentation_changed.connect(_on_presentation_changed)
	presentation.note.connect(_on_presentation_note)
	presentation.still_beginning.connect(_on_still_beginning)
	presentation.still_written.connect(_on_still_written)
	presentation.still_failed.connect(_on_still_failed)

	# Start from what the scene actually holds, so the form describes the garden rather
	# than a default. The sun's own values are set by `_refresh_presentation()`, which is
	# the one place that reads the presenter: the site's latitude arrives from the drawing
	# when the *presenter* is ready, and the presenter is later in the scene than this
	# panel is.
	_refresh_presentation()


## One labelled spin box for the sun row. Returns the box; the caller puts it in the row,
## because a helper that both made a control and parented it would have two owners for
## one child.
func _spin(
	node_name: String,
	low: float,
	high: float,
	step: float,
	suffix: String,
	initial: float,
	tip: String,
) -> SpinBox:
	var box := SpinBox.new()
	box.name = node_name
	box.min_value = low
	box.max_value = high
	box.step = step
	box.value = initial
	box.suffix = suffix
	box.tooltip_text = tip
	# A spin box is typed into, so it is the one control in the HUD that has to be able
	# to hold the keyboard; `release_keyboard_focus` only touches buttons.
	box.custom_minimum_size = Vector2(64.0, 0.0)
	return box


## One labelled field of the sun grid. The label is the control that keeps five numbers
## legible: a suffix carries units but not meaning, and two of these boxes hold degrees.
func _add_sun_field(grid: GridContainer, text: String, box: SpinBox) -> void:
	var label := Label.new()
	label.name = text.replace(" ", "") + "Label"
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(label)
	grid.add_child(box)


## Match the panel to the director, when something other than this panel changed it.
##
## Driven by a signature rather than by a signal, like the palette: the director is
## changed from a key, a click and a script, and a signature cannot miss one of them
## the way a forgotten connection would.
func _refresh_presentation() -> void:
	if _present_toggle == null or presentation == null:
		return
	# The sun's settings are part of the state this panel describes, and not only the
	# tier. The site reaches the presenter from the drawing when the presenter is ready —
	# later than this panel — so a signature that ignored the sun would leave the form
	# showing a default the scene does not use, and *Apply* would then push that default
	# back over the site's own latitude, longitude and offset.
	var state := "%s|%d|%.2f|%.2f|%.2f|%d|%.2f" % [
		str(presentation.is_active()),
		presentation.tier,
		presentation.latitude,
		presentation.longitude,
		presentation.utc_offset_hours,
		presentation.day_of_year,
		presentation.hour,
	]
	if state == _presentation_state:
		return
	_presentation_state = state
	_sun_hour.value = presentation.hour
	_sun_day.value = float(presentation.day_of_year)
	_sun_latitude.value = presentation.latitude
	_sun_longitude.value = presentation.longitude
	_sun_utc_offset.value = presentation.utc_offset_hours
	# By the silent setters: setting a button the ordinary way fires the handler, which
	# would then call `begin()` on a presentation that is already running.
	_present_toggle.set_pressed_no_signal(presentation.is_active())
	var selected: int = TierScript.CHOICES.find(presentation.tier)
	if selected >= 0:
		_tier_option.selected = selected


## Put the working furniture away for a presentation, or bring it back.
##
## This is the HUD's own business: the director says when a presentation begins, and
## what is working furniture is decided here, by the code that made it.
func set_presenting(on: bool) -> void:
	_presenting = on
	if on:
		# The key reference is working furniture: a client is being shown the garden, not the
		# shortcut list.
		close_keys()
	if top_bar != null:
		top_bar.visible = not on
	# The hints come back the way they were left, which is why their visibility is decided in one
	# place from a flag rather than set directly here and in the menu.
	_apply_hints_visibility()
	# The scale bar and the north point are sheet furniture, and a client is being
	# shown the garden rather than the drawing.
	if overlay != null:
		overlay.visible = not on
	# The palette and the key legend read `_presenting` every frame, so they put
	# themselves away rather than being set here: one place per control decides whether
	# it is visible.


func _on_presentation_toggled(pressed: bool) -> void:
	if presentation == null:
		return
	if not pressed:
		presentation.end()
		return
	# It could not start: put the switch back rather than leave it claiming something is
	# running that is not.
	if not presentation.begin(presentation.tier):
		_present_toggle.set_pressed_no_signal(false)


func _on_presentation_changed(active: bool) -> void:
	set_presenting(active)
	if active:
		_still_status.text = "presentation running"
	else:
		_still_status.text = ""


func _on_presentation_note(text: String) -> void:
	if _still_status != null:
		_still_status.text = text


func _on_tier_selected(index: int) -> void:
	if presentation == null or index < 0 or index >= TierScript.CHOICES.size():
		return
	presentation.set_tier(TierScript.CHOICES[index])


func _on_apply_sun() -> void:
	if presentation == null:
		return
	# The site and the moment, together: the presenter turns the clock time into the
	# site's own sky, which is where the longitude and the offset earn their place.
	presentation.apply_sun(
		SunStudyScript.site(float(_sun_latitude.value), float(_sun_longitude.value), float(_sun_utc_offset.value)),
		SunStudyScript.moment(int(_sun_day.value), float(_sun_hour.value)),
	)


## Keep the site with the drawing rather than only in this presentation. A drawing fact, so
## it is undoable like any other, and the presenter says what happened either way.
func _on_save_site() -> void:
	if presentation != null:
		presentation.save_site()


func _on_frame_yard() -> void:
	if presentation != null:
		presentation.frame_yard()


func _on_render_still() -> void:
	if presentation == null:
		return
	var size: Vector2i = selected_still_size()
	_still_status.text = "rendering %d x %d..." % [size.x, size.y]
	# Not awaited. The render waits for real frames and answers by signal, so this
	# panel stays a status line instead of blocking the frame it was pressed in.
	presentation.render_still(size)


## The size the still picker is on, as a pixel pair.
func selected_still_size() -> Vector2i:
	var index: int = _still_size_option.selected if _still_size_option != null else 0
	if index < 0 or index >= STILL_SIZES.size():
		index = 0
	return STILL_SIZES[index][1]


func _on_still_beginning() -> void:
	# The whole HUD, not just the working parts: a proposal image is of the garden, and
	# the panel holding the Render button would be in the corner of it.
	visible = false


func _on_still_written(path: String) -> void:
	visible = true
	if _still_status != null:
		_still_status.text = "wrote %s" % path.get_file()
	# A study renders one still per moment and starts the next from this one landing, so the file has
	# to be checked against the moment in hand: a still the panel's own button asked for in between is
	# not a step of the study.
	if _sun_still_is_ours(path):
		_sun_still_landed(true)


func _on_still_failed(reason: String) -> void:
	visible = true
	if _still_status != null:
		_still_status.text = "no still: %s" % reason
	# A failure in the middle of a study does not stop it: the rest of the moments are still worth
	# rendering, and the walk's own sentence counts what it could not do.
	if _sun_render_waiting:
		_sun_still_landed(false)

# --- the painted plan -----------------------------------------------------------------


## The two buttons under a painted plan: file it, or put it away.
##
## Built in code for the same reason the palette's buttons are: they are two
## decisions about one picture, and a scene file holding them would be a second place
## to change when there is only ever one.
func _build_painted_actions() -> void:
	if painted_actions == null:
		return
	_painted_save = Button.new()
	_painted_save.name = "SavePaintedStill"
	_painted_save.text = "Save a still"
	_painted_save.tooltip_text = "Write this picture into the proposals folder, with its record"
	_painted_save.disabled = true
	_painted_save.pressed.connect(_on_save_painted)
	painted_actions.add_child(_painted_save)
	var close_button := Button.new()
	close_button.name = "ClosePaintedSheet"
	close_button.text = "Close"
	close_button.pressed.connect(close_painted)
	painted_actions.add_child(close_button)


## Show the painted plan, painting it first if there is nothing to show.
##
## Painting again on every key press rather than caching: a designer presses this
## after changing the drawing, and a cached picture would be a picture of the plan as
## it used to be.
func open_painted() -> void:
	if painted_plan == null or painted_sheet == null:
		return
	if painted_sheet.visible:
		close_painted()
		return
	# A presentation is a view of the garden rather than of the drawing, so the
	# drawing does not open over it.
	if _presenting:
		return
	_painted_image = null
	if _painted_save != null:
		_painted_save.disabled = true
	painted_picture.texture = null
	var reason: String = painted_plan.refusal()
	if reason != "":
		# The answer to "show me the painted plan" is a sentence when there is no
		# plan to paint, and the sheet is where the answer is read.
		painted_caption.text = reason
		painted_sheet.visible = true
		return
	painted_caption.text = "painting..."
	painted_sheet.visible = true
	# Not awaited: the render waits for real frames, and the result arrives by
	# signal. The status line is this label, which is already saying so.
	painted_plan.render()


func close_painted() -> void:
	if painted_sheet != null:
		painted_sheet.visible = false


func _on_painted(image: Image, report: Dictionary) -> void:
	_painted_image = image
	if painted_picture != null:
		painted_picture.texture = ImageTexture.create_from_image(image)
	if painted_caption != null:
		painted_caption.text = painted_caption_text(report)
	if _painted_save != null:
		_painted_save.disabled = false


func _on_paint_failed(reason: String) -> void:
	_painted_image = null
	if painted_picture != null:
		painted_picture.texture = null
	if painted_caption != null:
		painted_caption.text = reason
	if _painted_save != null:
		_painted_save.disabled = true


func _on_save_painted() -> void:
	if painted_plan == null or _painted_image == null:
		return
	# The button is switched off while there is nothing to file, so an empty save here
	# is a state that cannot be reached - but the file is written by a function that
	# can fail, and a failure has somewhere to be read.
	var path: String = painted_plan.save(_painted_image)
	if path != "" and painted_caption != null:
		painted_caption.text = "wrote %s" % path.get_file()


## What a painted plan says about itself: the sheet, the scale, the pixels, and how
## much of the drawing reached the paper. Static so a test can hold the promise that
## the caption names the scale the drawing was painted at.
static func painted_caption_text(report: Dictionary) -> String:
	var pixels: Array = report.get("pixels", [0, 0])
	var mm: Array = report.get("mm", [0.0, 0.0])
	return "Painted plan   %.0f x %.0f mm at 1:%s   %d x %d px   %d washed areas, %d planted" % [
		float(mm[0]),
		float(mm[1]),
		String.num(float(report.get("plot_scale", 100.0)), 4),
		int(pixels[0]),
		int(pixels[1]),
		int(report.get("regions", 0)),
		int(report.get("props", 0)),
	]


## The keys that belong to the HUD's own surfaces rather than to the drawing: the file commands, the
## palette, the plant library, and the painted plan's own key.
##
## Handled here rather than in the view controller because each of them is the HUD's own surface - the
## file it is about to write, the box it opens, the sheet it shows - and one feature in one place is
## what keeps a key that opens something from being a key that cannot close it: Escape is answered for
## by `escape_puts_away`, which is the same ladder every page this node draws is on.
func _unhandled_input(event: InputEvent) -> void:
	# Escape reaches the HUD before the drawing does, so it is asked first whether it has a surface to
	# put away: a page that is up is what the person is looking at, and cancelling the shape *behind*
	# it is the one thing they cannot mean. Nothing up, nothing answered, and the drawing's own cancel
	# gets the key exactly as it always did.
	if event.is_action_pressed(&"draft_cancel") and escape_puts_away():
		get_viewport().set_input_as_handled()
		return
	# The file commands, while none of our dialogs is up: a dialog has its own keys, and a second
	# Ctrl+S behind an open Save dialog would open another one.
	if not _file_dialog_open():
		if event.is_action_pressed(&"file_new"):
			_menu_new_drawing({ })
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed(&"file_open"):
			_menu_open_drawing({ })
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed(&"file_save"):
			_menu_save_drawing({ })
			get_viewport().set_input_as_handled()
			return
		# The palette, on the same footing as the file commands and behind the same guard: it is a
		# way to reach *any* command, including the ones that open a dialog, and a second palette
		# behind an open Save dialog could open another one.
		if event.is_action_pressed(&"command_palette"):
			toggle_command_palette()
			get_viewport().set_input_as_handled()
			return
		# The plant library, on the same footing: a plant browser is reached for constantly while
		# planting a bed, and a menu is a slow way to get to something you use every minute.
		if event.is_action_pressed(&"plant_library"):
			if _plant_window != null and _plant_window.visible:
				close_plant_browser()
			else:
				open_plant_browser()
			get_viewport().set_input_as_handled()
			return
		# The manual, about the page in front of you, on the same footing: the question "what is this page
		# asking me" is asked *while looking at the page*, so the answer is one key away rather than a
		# search away in a list of thirty-two headings.
		if event.is_action_pressed(&"page_help"):
			open_page_help()
			get_viewport().set_input_as_handled()
			return
		# The commands that had no key: the nursery order, the sun and the shadows, and the ground's
		# three tools. Each one runs the menu entry that advertises it, so the key, the menu line and
		# the page's own button are one act rather than three.
		if event.is_action_pressed(&"plant_order"):
			_menu_plant_order_window({ })
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed(&"present_sun_study"):
			_menu_sun_window({ })
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed(&"grade_spot"):
			_menu_grade_spot({ })
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed(&"grade_contour"):
			_menu_grade_contour({ })
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed(&"grade_slope"):
			_menu_grade_slope({ })
			get_viewport().set_input_as_handled()
			return
	if painted_plan == null:
		return
	if event.is_action_pressed(&"vis_painted"):
		open_painted()
		get_viewport().set_input_as_handled()
		return


## Put away whatever page is in front, the way Escape does, and say whether there was one.
##
## One ladder in the order a person takes the layers off, so the one key that means "out of this"
## means it on every surface this HUD owns. Until now the keys panel and the painted sheet did this
## between them, which left the other seven pages reachable only by their own Close button or by the
## menu that opened them - the same act, taught twice and missing nine times.
##
## The pages that live in a `Window` are deliberately not here: a focused window takes the keyboard
## into its own viewport, so this node never sees an Escape meant for one. Those pages answer for
## themselves, and the file dialogs are `Popup`s, which Godot already closes on the same key.
func escape_puts_away() -> bool:
	# The sheet first: while it is up, the drawing behind it is not what the person is looking at.
	# Only the sheet is checked, because it can only be shown by a scene that can paint one.
	if painted_sheet != null and painted_sheet.visible:
		close_painted()
		return true
	if is_keys_open():
		close_keys()
		return true
	# The seven pages this HUD draws itself, newest first. Written out rather than walked, because
	# each one's door is its own function and a table of method names would be a second list of them.
	for page: Array in [
		[is_site_report_open(), close_site_report],
		[is_survey_panel_open(), close_survey_panel],
		[is_dxf_panel_open(), close_dxf_panel],
		[is_landxml_panel_open(), close_landxml_panel],
		[is_hatch_panel_open(), close_hatch_panel],
		[is_water_panel_open(), close_water_panel],
		[is_light_panel_open(), close_light_panel],
	]:
		if bool(page[0]):
			(page[1] as Callable).call()
			return true
	return false


## Every page this HUD opens that lives in a `Window`, in one place.
##
## A test reads this list against the `Window` members the HUD declares, so a page added to the HUD and
## forgotten here - which would be a page Escape silently stopped working on - is caught by the suite
## rather than by a person pressing a key that does nothing.
func pages_in_windows() -> Array[Window]:
	var pages: Array[Window] = [
		_help_window,
		_plant_window,
		_command_palette,
		_ground_window,
		_layer_window,
		_sheet_window,
		_revision_window,
		_osm_window,
		_underlay_window,
		_grading_window,
		_plant_order_window,
		_food_window,
		_rotation_window,
		_harvest_window,
		_season_window,
		_capture_window,
		_plant_key_window,
		_sowing_window,
		_yield_window,
		_sun_window,
		_walk_window,
		_snap_window,
		_status_window,
		_estimate_window,
		_pipeline_board,
		_schedule_board,
		_cost_window,
		_billing_window,
		_ledger_window,
		_sync_window,
		_closeout_window,
		_analytics_window,
	]
	return pages


## Give every page in a `Window` a node of its own that answers Escape.
##
## A page in a `Window` takes the keyboard into its own viewport: measured live in
## `tools/page_escape_demo.gd`, where a real Escape reached a node put inside the page and reached a
## node beside this HUD not at all. So the key has to be answered from inside each page, and the only
## thing that can be put there is a node - one per page, made once, whether or not the page is up.
##
## The doorway's pages are walked here beside the rest, and for the same reason: a door is a page in a
## `Window`, and a door left standing after Escape is a page the key cannot put away. That was the state
## of the front door - measured on the desk, a real Escape on a launch with the door up left it standing,
## because the only list it was not on was this one. The three doorway pages are built when they are first
## opened rather than at launch, so each `_build_*` door calls this again once its page exists; `attach` is
## idempotent, so the later pass over a page adds nothing to it.
func _let_escape_close_pages() -> void:
	for page: Window in _pages_that_can_be_up():
		PageEscapeScript.attach(page)

# --- the menu bar ---------------------------------------------------------------------
#
# A menu across the top of the window: the things a program of this kind always offers, plus the
# two things this one is actually made of - the drawing tools and the client presentation.
#
# Every entry does something, and the ones that stand for a key say which key. The keys come from
# the input map rather than from a table here, so a rebinding moves the menu with the legend.

const MenuBarPlanScript := preload("res://scripts/menu_bar_plan.gd")


## The doors onto the bar's own table, which lives in `menu_bar_plan.gd`: what the bar is made
## of is one thing, and it is written once. These hand back the table's own answers rather than a
## second copy of them, so a menu exists in exactly one place and nothing outside this file has had
## to move. What stays here is how the bar is measured, how each entry is drawn, and which entry is
## on in the scene this HUD is in.
const NEEDS_NOTHING := MenuBarPlanScript.NEEDS_NOTHING
const NEEDS_DRAFT := MenuBarPlanScript.NEEDS_DRAFT
const NEEDS_PRESENTATION := MenuBarPlanScript.NEEDS_PRESENTATION
const NEEDS_PRESENCE := MenuBarPlanScript.NEEDS_PRESENCE
const NEEDS_CAN_TURN := MenuBarPlanScript.NEEDS_CAN_TURN
const NEEDS_A_FINGER := MenuBarPlanScript.NEEDS_A_FINGER
const KNOWN_NEEDS: Array[StringName] = MenuBarPlanScript.KNOWN_NEEDS


static func menu_plan() -> Array[Dictionary]:
	return MenuBarPlanScript.menu_plan()


static func file_items() -> Array[Dictionary]:
	return MenuBarPlanScript.file_items()


static func sheet_items() -> Array[Dictionary]:
	return MenuBarPlanScript.sheet_items()


static func scale_items() -> Array[Dictionary]:
	return MenuBarPlanScript.scale_items()


static func edit_items() -> Array[Dictionary]:
	return MenuBarPlanScript.edit_items()


static func dimension_style_items() -> Array[Dictionary]:
	return MenuBarPlanScript.dimension_style_items()


static func view_items() -> Array[Dictionary]:
	return MenuBarPlanScript.view_items()


static func orientation_items() -> Array[Dictionary]:
	return MenuBarPlanScript.orientation_items()


static func reading_size_items() -> Array[Dictionary]:
	return MenuBarPlanScript.reading_size_items()


static func draft_items() -> Array[Dictionary]:
	return MenuBarPlanScript.draft_items()


static func present_items() -> Array[Dictionary]:
	return MenuBarPlanScript.present_items()


static func tier_items() -> Array[Dictionary]:
	return MenuBarPlanScript.tier_items()


static func still_size_items() -> Array[Dictionary]:
	return MenuBarPlanScript.still_size_items()


static func site_items() -> Array[Dictionary]:
	return MenuBarPlanScript.site_items()


static func pipeline_items() -> Array[Dictionary]:
	return MenuBarPlanScript.pipeline_items()


static func jobs_items() -> Array[Dictionary]:
	return MenuBarPlanScript.jobs_items()


static func estimate_items() -> Array[Dictionary]:
	return MenuBarPlanScript.estimate_items()


static func plant_items() -> Array[Dictionary]:
	return MenuBarPlanScript.plant_items()


static func water_items() -> Array[Dictionary]:
	return MenuBarPlanScript.water_items()


static func light_items() -> Array[Dictionary]:
	return MenuBarPlanScript.light_items()


static func help_items() -> Array[Dictionary]:
	return MenuBarPlanScript.help_items()


static func team_items() -> Array[Dictionary]:
	return MenuBarPlanScript.team_items()


static func items_for(title: String) -> Array[Dictionary]:
	return MenuBarPlanScript.items_for(title)


static func menu_entries() -> Array[Dictionary]:
	return MenuBarPlanScript.menu_entries()


static func tool_label(pair: Array) -> String:
	return MenuBarPlanScript.tool_label(pair)


static func edit_tool_label(pair: Array) -> String:
	return MenuBarPlanScript.edit_tool_label(pair)


## What an entry says: its label, and the key that does the same thing when there is one.
##
## The key is written into the text rather than set as the item's accelerator. An accelerator is a
## second binding, and it fires *as well as* the input action: pressing P would plot the sheet
## twice, which is the kind of bug a menu makes easy and a legend cannot.
static func menu_label(entry: Dictionary) -> String:
	var label := String(entry.get("label", ""))
	var key := _key_label(StringName(entry.get("action", &"")))
	return label if key == "" else "%s    %s" % [label, key]


## Whether a checkable entry is on, decided from a snapshot of everything the bar reports on.
##
## Static and pure so the rule can be read and tested without a scene: which of these is on is the
## half of a menu that is easy to get wrong and impossible to see.
static func is_checked(state: StringName, value: Variant, world: Dictionary) -> bool:
	match state:
		&"mode":
			return int(world.get("mode", -1)) == int(value)
		&"drawing":
			return bool(world.get("drawing", false))
		&"tool":
			# A tool is shown as chosen only while the tools are out, which is the same rule the
			# palette follows: a menu highlighting a tool while the tools are put away would be
			# describing a mode that is not on. An editing command in hand is not a drawing tool.
			return bool(world.get("drawing", false)) and int(world.get("edit", 0)) == 0 \
					and int(world.get("tool", -1)) == int(value)
		&"edit":
			# Likewise, an editing command is only shown as in hand while the tools are out and
			# nothing else is drawing.
			return bool(world.get("drawing", false)) and int(world.get("edit", -1)) == int(value)
		&"dimension_style":
			return StringName(world.get("dimension_style", &"")) == StringName(value)
		&"select_mode":
			# The mode is only the mode while the select tool is actually out, for the same reason
			# a drawing tool is only shown as chosen while the tools are out: a menu claiming a
			# band is in hand when nothing is would be describing a mode that is not on.
			return bool(world.get("drawing", false)) \
					and int(world.get("tool", -1)) == int(DraftToolScript.Kind.SELECT) \
					and StringName(world.get("select_mode", &"")) == StringName(value)
		&"sheet":
			return String(world.get("sheet", "")) == String(value)
		&"scale":
			return is_equal_approx(float(world.get("plot_scale", 0.0)), float(value))
		&"presenting":
			return bool(world.get("presenting", false))
		&"tier":
			return int(world.get("tier", -1)) == int(value)
		&"still_size":
			return int(world.get("still_size", -1)) == int(value)
		&"keys_panel":
			return bool(world.get("keys_panel", false))
		&"presentation_panel":
			# On unless it has been put away: the panel is on whenever the scene has a director.
			return bool(world.get("presentation_panel", true))
		&"hints":
			return bool(world.get("hints", true))
		&"site":
			return bool(world.get("site", false))
		&"orientation":
			return StringName(world.get("orientation", &"")) == StringName(value)
		&"reading_size":
			return StringName(world.get("reading_size", &"")) == StringName(value)
	return false


## Everything the bar reports on, as one snapshot. The checks are drawn from this rather than from
## the controls, so the menu describes the state rather than a button that happens to agree with it.
func menu_world() -> Dictionary:
	var world: Dictionary = {
		"mode": int(view_controller.mode) if view_controller != null else -1,
		"drawing": _draft != null and _draft.drawing,
		"tool": int(_draft.current_tool()) if _draft != null else -1,
		"edit": int(_draft.current_edit()) if _draft != null else -1,
		"select_mode": StringName(_draft.selection_mode()) if _draft != null else &"",
		"dimension_style": StringName(_draft.dimension_style_name) if _draft != null else &"",
		"sheet": String(_draft.sheet) if _draft != null else "",
		"plot_scale": float(_draft.plot_scale) if _draft != null else 0.0,
		"presenting": presentation != null and presentation.is_active(),
		"tier": int(presentation.tier) if presentation != null else -1,
		"still_size": int(_still_size_option.selected) if _still_size_option != null else -1,
		"keys_panel": is_keys_open(),
		"presentation_panel": _presentation_panel_wanted,
		"hints": _show_hints,
		# Whether the garden the program ships with is standing under the drawing - the tick beside "Show
		# the site". On the signature because the whole bar is rebuilt when it changes, so showing the
		# site moves the tick without the menu knowing the site exists.
		"site": view_controller != null and view_controller.is_site_shown(),
		# The board's own kept answer, which the tick beside each orientation choice reads - and on the
		# signature because it changes the moment a choice is made.
		"orientation": _orientation,
		# The reader's own word size, which the tick beside each of the three reading sizes reads.
		"reading_size": _reading_size,
		# What the File menu reports on: which drawing is open, whether it has been saved, and
		# what was open before. The recent list is in here so that the signature notices when it
		# changes - the one thing about the bar that is entries rather than ticks.
		"dirty": _draft != null and _draft.dirty,
		"drawing_path": String(_draft.drawing_path) if _draft != null else "",
		"drawing_state": _draft.drawing_state_text() if _draft != null else "",
		"recent": ", ".join(PackedStringArray(_draft.recent_drawings())) if _draft != null else "",
		# What a session that ended without saving left behind. Read off a dictionary refreshed when it
		# can have changed rather than off the disk, because this snapshot is taken on the way to every
		# menu refresh. The description is in here as well as the flag, so that a copy replaced by a
		# newer one moves the line instead of leaving a stale sentence on it.
		"recovery": not _pending_recovery.is_empty(),
		"recovery_text": AutosaveScript.describe(_pending_recovery) if not _pending_recovery.is_empty() else "",
		# The plant list is in the signature only once it has been read - this snapshot is taken on
		# every state change, and it must not be the thing that reads four thousand species. What a
		# click would plant and how many are planted are cheap, and they are what moves.
		"plants": _plants.describe() if _plants != null else "",
		"planting": String(view_controller.planting_species) if view_controller != null else "",
		"planted": view_controller.planted_count() if view_controller != null else 0,
		# What the ground is stated to be, which is what every plant verdict is judged against: the
		# whole point of a ring that changes when a plant is dropped two metres to the left. One line
		# now rather than a radio state per attribute: the ground is edited in its own window, and the
		# menu reports what came of it.
		"ground": _ground_text(),
		# The ground's own heights, in the controller's words, with the check's disagreement counted on
		# the line. Cheap: it reads sizes and asks the check, and the check is a handful of comparisons.
		"grading": _grading_text(),
		# Where the money stands. Cheap: it reads the estimate's own count and total and nothing else,
		# so the signature can hold it without this snapshot becoming the thing that prices a plan.
		"estimate": _estimate_text(),
		# The open pipeline, in the board's own words. Like the estimate, cheap: it reads a count and
		# two totals and nothing else.
		"pipeline": _pipeline_text(),
		# The crew, the jobs and the board's own count of the clashes. Cheap like the two above: it
		# reads sizes and asks the schedule for its conflicts, and holds no arithmetic.
		"jobs": _jobs_text(),
		# The shared session: whether one is open, and who is in it. Cheap, and it is the one part
		# of the bar that changes because somebody else did something.
		"session": _presence_text(),
		"session_on": _presence != null and _presence.is_on(),
		# The sun's study in hand, in the site's own words plus its size. Cheap: it formats two
		# numbers and the site, and it is on the signature because the page's study changes without
		# the drawing changing at all.
		"sun": _sun_text(),
	}
	return world


## The drawing's own record of what the ground is like, or null in a scene with no drawing. The
## ground belongs to the document, so it travels in the file with the design it describes and moves
## with the undo stack like everything else on it.
func _ground_map() -> ZoneMapScript:
	if _draft == null:
		return null
	var document: DraftDocument = _draft.document
	if document == null:
		return null
	return document.environment


## What the ground is stated to be, in one line, for the Site menu to say rather than to imply.
func _ground_text() -> String:
	var map: ZoneMapScript = _ground_map()
	if map == null:
		return "there is no drawing to say what the ground is like"
	return map.describe()


## What the Site menu's own line says about the ground's heights: the controller's one-line summary of
## the levels, contours and arrows, and - when there is one - the fact that the check disagrees with
## something on the drawing.
##
## The count is on the line rather than only inside the page, for the reason the clashes are on the Jobs
## menu's line: a drawing that contradicts itself about its own heights should say so without being
## opened. It is worded here rather than in the module because it is about the *menu*, and a module that
## knew how a menu words a count would be a module that knows about menus.
func _grading_text() -> String:
	if _draft == null or _draft.document == null:
		return "there is no drawing to grade"
	var words: String = _draft.grading_summary()
	var findings: Array = _draft.grading_report().get("findings", [])
	if findings.is_empty():
		return words
	return "%s - %s" % [words, "%d the check disagrees with" % findings.size()]


## What the Water menu's own line says: the controller's one-line summary of the zones and the budget
## beside it, so a designer can read the supply and the zones without opening the page.
func _water_text() -> String:
	if _draft == null or _draft.document == null:
		return "there is no drawing to water"
	var budget: String = _draft.irrigation_summary()
	return "%s. %s" % [budget, _water_budget_text()]


## The supply's own line, as the panel writes it, so the menu and the page never disagree about what
## the source gives.
func _water_budget_text() -> String:
	if _draft == null:
		return "no supply stated"
	var supply: Dictionary = _draft.irrigation_supply()
	if not IrrigationScript.has_supply(supply):
		return "no supply stated: nothing is laid out until one is"
	return "supply: %s" % IrrigationScript.supply_words(supply)


## What the Light menu's own line says: the controller's one-line summary of the circuits and the
## transformer beside it, so a designer can read the capacity and the circuits without opening the page.
func _light_text() -> String:
	if _draft == null or _draft.document == null:
		return "there is no drawing to light"
	var budget: String = _draft.lighting_summary()
	return "%s. %s" % [budget, _light_budget_text()]


## The transformer's own line, as the panel writes it, so the menu and the page never disagree about
## what the transformer gives.
func _light_budget_text() -> String:
	if _draft == null:
		return "no transformer stated"
	var transformer: Dictionary = _draft.lighting_transformer()
	if not LightingScript.has_transformer(transformer):
		return "no transformer stated: nothing is laid out until one is"
	return "transformer: %s" % LightingScript.transformer_words(transformer)


## The name the folded menus are gathered under.
const MORE_TITLE := "More"
## How many menus have to be folded away before folding is worth doing at all. A fold that leaves one or
## two behind the More menu saves a few pixels and costs a person the hunt for a menu they knew the place
## of, so the bar stays tight instead.
const MIN_FOLDED_MENUS := 3


## Build the menus from the plan.
##
## In code rather than in the scene for the same reason the palette is: the entries are derived
## from tables that already exist, and a scene file holding forty copies of them would be forty
## places to keep in step.
func _build_menu_bar() -> void:
	if menu_bar == null:
		return
	# A menu bar holds the keyboard like any other Control, and the keys belong to the drawing.
	menu_bar.focus_mode = Control.FOCUS_NONE
	_menu_room = menu_bar_room()
	_fill_menu_bar(menu_bar_plan(_menu_room))


## One bar's worth of menus from a plan. Separate from `_build_menu_bar` because the bar can be built more
## than once: a window that shrinks past what fourteen menus want rebuilds it with the tail folded.
func _fill_menu_bar(plan: Array[Dictionary]) -> void:
	_menu_titles.clear()
	for menu: Dictionary in plan:
		var popup := PopupMenu.new()
		popup.name = String(menu["title"])
		popup.title = String(menu["title"])
		menu_bar.add_child(popup)
		_build_menu(popup, menu["items"])
		_menu_titles.append(String(menu["title"]))
	_hide_unavailable_menus()
	_refresh_menus()


## Rebuild the bar when the room it has no longer draws the same menus, and do nothing at all otherwise -
## this is called on every frame, so the cheap comparison comes first.
func _fold_menu_bar_to_fit() -> void:
	if menu_bar == null:
		return
	# **A drawer does not fold.** On a device answered with a finger the menus are not drawn at all - the four
	# controls of `TouchRow` stand in their place and the plan is reached through the drawer - so the fold has
	# nothing to fit and nothing to say. Left running it would fold a bar nobody sees, for a room it does not
	# stand in, and print a `MENUBAR` line about it: a reading, published, of furniture that is not on the
	# screen. That is worse than a missing reading, because the tools that read this line would believe it.
	if shows_touch_controls():
		return
	var room: float = menu_bar_room()
	if is_equal_approx(room, _menu_room):
		return
	# What the phone needs to say out loud, because the numbers on a 1080-wide screen cannot be worked out
	# from a desk: the room the bar was given, what the bar itself says it needs, the row it sits in, and
	# how many titles are on it. A debug build may say this; a release build says nothing.
	if OS.is_debug_build():
		# The line's own shape is the table's, not this file's, so that the reader a tool uses and the writer here
		# can never disagree about it - the round trip is held down by a test beside the fold's arithmetic.
		print(
			MenuBarPlanScript.menubar_line(
				room,
				menu_bar.get_combined_minimum_size().x,
				(menu_bar.get_parent() as Control).size.x,
				get_viewport().get_visible_rect().size.x if get_viewport() != null else -1.0,
				_menu_titles.size(),
			)
		)
	# The room is remembered *before* the bar is rebuilt: the rebuild ends by asking for a refresh, and a
	# refresh that found the room still unrecorded would rebuild the bar again and again.
	_menu_room = room
	if _the_fold_has_settled():
		return
	_rebuild_menu_bar(menu_bar_plan(room))


## Take the bar down and put it back up from a new plan. The popups are the HUD's own children, so they
## are freed outright rather than left for the frame's end: the rebuild is about to make new ones under
## the same names, and two menus of one name is a bug waiting for the first lookup.
func _rebuild_menu_bar(plan: Array[Dictionary]) -> void:
	for child: Node in menu_bar.get_children():
		menu_bar.remove_child(child)
		child.free()
	_menu_items.clear()
	# The recent-drawings popup is the one child kept by reference - it is the set whose entries change
	# rather than only their ticks - so the held one is dropped here rather than left pointing at a freed
	# node the next save to the store would write into.
	_recent_popup = null
	_recent_filled = ""
	_fill_menu_bar(plan)
	# The popups this has just made are new, and new popups are a desk's size: see the one place that fits
	# the bar's own menus.
	_fit_the_menu_bars_words()


## Fit the bar's own menus to the finger that will open them, after a rebuild has made new ones.
##
## **The second writer of one fact, and the one that was winning.** `size_for_a_finger` fits this HUD's whole
## chrome once - the menus a `MenuBar` owns among them, because that walk reads internal children - but the
## fold that decides how many titles fit runs on **every frame**, and a change in the room takes the bar down
## and puts it back up with **new** popups. Those arrive at the size a desk draws them, and nothing fitted
## them a second time.
##
## Measured on the SM-A166W, opening File and Edit on the board: the rows came out **44.5 px, 2.51 mm**,
## against this program's 5.5 mm thumb floor, with words about two thirds the size of the rest of the bar's
## own text. The room changes after the fitting pass as a matter of course - the bar settles from fourteen
## titles down to two while its row is being measured, and the *turn* from the portrait door to the landscape
## board changes the room again - so a rebuild always landed after the fit.
##
## On a computer this is nothing at all: `shows_touch_controls()` is false, so the bar a desk draws is the bar
## the scene drew, and no popup is ever given an override it could lose.
func _fit_the_menu_bars_words() -> void:
	if menu_bar == null or not shows_touch_controls():
		return
	PhoneHudScript.fit_the_chrome_for_a_finger(
		menu_bar,
		PhoneHudScript.canvas_scale(get_window()),
		PhoneHudScript.dpi(),
	)


## The room the bar has to work with, which is what is left of the row it sits in once everything else in
## that row has taken the minimum it needs - the view and presentation controls are in the same row as
## the menus, so the row's own width is not the bar's.
##
## Before the first layout the row has no width yet, so the viewport is asked instead: the row spans the
## bar it is in. Zero means neither is known, and a bar with no known room is not folded - no room worked
## out is not the same as no room.
func menu_bar_room() -> float:
	if menu_bar == null:
		return 0.0
	var row: Control = menu_bar.get_parent() as Control
	if row == null:
		return 0.0
	var others: float = row.get_combined_minimum_size().x - menu_bar.get_combined_minimum_size().x
	var across: float = row.size.x
	var shown: float = 0.0
	var viewport: Viewport = get_viewport()
	if viewport != null:
		shown = viewport.get_visible_rect().size.x
	return bar_room(across, others, shown)


## The room a bar has, from the row it sits in, what the rest of that row needs, and what the screen
## shows - the arithmetic of `menu_bar_room` on its own so it can be held to the numbers.
##
## Two clamps, and the phone is why both are here. **`others` is never negative**: a row whose own minimum
## comes out smaller than the bar's would otherwise subtract a negative and hand the bar more room than
## the row has, so nothing folded and fourteen menus were drawn clipped at both ends on a 1080-wide
## screen. And **the answer is never wider than the screen**: a row can be laid out wider than the canvas
## it is drawn in, and the room the bar has is what a person can actually see.
##
## Nothing changes on a desk, where both numbers are already inside these bounds.
static func bar_room(across: float, others: float, shown: float) -> float:
	if across <= 0.0 or (shown > 0.0 and across > shown):
		across = shown
	if across <= 0.0:
		return 0.0
	return maxf(0.0, across - maxf(0.0, others))


## The bar's view of the plan: the whole plan when the room takes it, and the tail of it gathered under
## one More menu when it does not.
##
## The plan itself is never changed. It is what the palette lists and what `items_for` answers with, so a
## folded bar is a *view* of it - the commands are all still there, in one place, however the bar draws
## them.
## The titles the top bar would carry in a room this wide, in the order it would draw them.
##
## The one place that turns a plan into titles, so that "what the bar would put up" and "what the bar has up" can
## be compared without either side wording the plan a second way.
func _wanted_menu_titles(available: float) -> Array[String]:
	var titles: Array[String] = []
	for menu: Dictionary in menu_bar_plan(available):
		titles.append(String(menu["title"]))
	return titles


## Whether the top bar has finished folding: the plan for the room it has now would put up the same titles as the
## ones already standing.
##
## **This is the fold's own question, and it is asked in one place.** The fold runs on every frame and the bar is
## rebuilt only when the answer changes, so this is both the early return that keeps the rebuild off every frame
## and the signal `_the_screen_said` waits on before the probe reads the screen. Asking it by watching the room
## instead does not work, and that is measured: the room and the bar's own minimum feed each other - the bar's
## minimum is part of the room the fold is given - so the room sits still for two frames in the middle of a fold
## that is not finished. A reading taken that way caught the bar at ten titles and reported it asking for 1052 px
## of a 349 px room, while the fold went on to two titles and 272 px and fitted. The fault was in the reading.
func _the_fold_has_settled() -> bool:
	return _wanted_menu_titles(menu_bar_room()) == _menu_titles


func menu_bar_plan(available: float) -> Array[Dictionary]:
	var plan: Array[Dictionary] = menu_plan()
	var fold: int = menu_fold_count(plan, available)
	if fold >= plan.size():
		return plan
	var out: Array[Dictionary] = []
	for i: int in fold:
		out.append(plan[i])
	var more: Array[Dictionary] = []
	for i: int in range(fold, plan.size()):
		var menu: Dictionary = plan[i]
		# The menu's name becomes a titled separator, so a command under More still says which menu it
		# lives in rather than arriving with no place at all.
		more.append({ "kind": &"separator", "id": "more.%d" % i, "label": String(menu["title"]) })
		for item: Dictionary in Array(menu.get("items", [])):
			more.append(item)
	out.append({ "title": MORE_TITLE, "items": more })
	return out


## How many menus the bar can show before the rest have to fold. The whole plan is the answer when it all
## fits, and when it cannot be worked out at all - a bar with nothing to measure with is left exactly as
## it is rather than folded on a guess.
func menu_fold_count(plan: Array[Dictionary], available: float) -> int:
	if available <= 0.0:
		return plan.size()
	var words: Array[String] = []
	for menu: Dictionary in plan:
		words.append(String(menu["title"]))
	words.append(MORE_TITLE)
	var widths: Array[float] = menu_title_widths(words)
	if widths.size() != words.size():
		return plan.size()
	var titles: Array[float] = widths.slice(0, plan.size())
	return menu_fold_point(titles, available, widths[widths.size() - 1])


## How much room each title wants, measured on the font the bar draws its titles with - plus the button
## that will be drawn around it, which is not nothing.
##
## **A menu is a button around a title, not the title alone.** The button's own padding and the bar's
## separation between children are room the fold has to pay for, and measuring the glyphs alone is what
## made a phone declare that fourteen menus fitted in the 661 px it had when the bar they made needed 757:
## nothing folded, and the row was drawn wider than the 1444 px screen and clipped at both ends. The
## measurement prints its own numbers from a debug build (`MENUBAR room=... bar_min=... shown=...`).
##
## An empty result is a refusal, not a row of zeroes: a bar whose titles cannot be measured must not be
## folded, because every title measuring nothing would fold every menu into the More menu. A wrong theme
## name therefore costs the fold, which is a tight bar rather than a bar with no menus in it.
func menu_title_widths(words: Array[String]) -> Array[float]:
	var widths: Array[float] = []
	var bar: MenuBar = menu_bar
	var borrowed := false
	if bar == null:
		bar = MenuBar.new()
		borrowed = true
	var font: Font = bar.get_theme_font("font")
	var point_size: int = bar.get_theme_font_size("font_size")
	if font != null and point_size > 0:
		var around: float = menu_button_chrome(bar)
		for title: String in words:
			widths.append(around + font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, point_size).x)
	if borrowed:
		bar.free()
	return widths


## What one menu costs beyond the letters of its title: the style box the button draws, and the space the
## bar puts between two of them. Asked of a real `MenuBar` rather than written down as a number, so a
## theme that changes its padding changes this too.
static func menu_button_chrome(bar: Control) -> float:
	if bar == null:
		return 0.0
	var around: float = 0.0
	var style: StyleBox = bar.get_theme_stylebox("normal")
	if style != null:
		around += style.get_minimum_size().x
	around += float(bar.get_theme_constant("h_separation"))
	return around


## How many of a row of titles fit in the room, once the More menu's own title has been paid for.
##
## The menus keep the order a person learned them in, so it is the **tail** that folds rather than
## whichever titles happen to be widest - the bar reads the same way at every width, with fewer names on
## the right-hand end.
static func menu_fold_point(widths: Array[float], available: float, more_width: float) -> int:
	var total: float = 0.0
	for width: float in widths:
		total += width
	if available <= 0.0 or total <= available:
		return widths.size()
	var kept: int = 0
	var running: float = more_width
	while kept < widths.size() and running + widths[kept] <= available:
		running += widths[kept]
		kept += 1
	if widths.size() - kept < MIN_FOLDED_MENUS:
		return widths.size()
	return kept


## One menu's items, including any submenus, filling `_menu_items` as it goes: an item's id is its
## index, so the index of the entry in this array is the id the popup will report.
func _build_menu(popup: PopupMenu, items: Array) -> void:
	var entries: Array[Dictionary] = []
	for raw: Dictionary in items:
		var entry: Dictionary = raw
		var kind: StringName = entry.get("kind", &"command")
		if kind == &"separator":
			# A separator may carry the name of the menu it divides, which is what the folded bar's single
			# More menu uses to say where each group of commands came from.
			popup.add_separator(String(entry.get("label", "")))
		elif kind == &"submenu":
			var child := PopupMenu.new()
			child.name = String(entry["id"]).replace(".", "_") + "Menu"
			child.title = String(entry["label"])
			popup.add_child(child)
			_build_menu(child, entry["items"])
			popup.add_submenu_item(String(entry["label"]), child.name)
			# The recent drawings are the one set whose *entries* grow and shrink, so the menu
			# that holds them is kept rather than found again every time it changes.
			if String(entry["id"]) == "file.recent":
				_recent_popup = child
		else:
			var label := menu_label(entry)
			var wanted: bool = _menu_needs_met(StringName(entry.get("needs", NEEDS_NOTHING)))
			if kind == &"radio":
				popup.add_radio_check_item(label)
			elif kind == &"check":
				popup.add_check_item(label)
			else:
				popup.add_item(label)
			if kind == &"info":
				# A line that says something: never pressable, and never a method.
				popup.set_item_disabled(entries.size(), true)
			if not wanted:
				# Visible but switched off, so the menu still says what the program does in a
				# scene that cannot do it.
				popup.set_item_disabled(entries.size(), true)
		entries.append(entry)
	_menu_items[popup] = entries
	popup.id_pressed.connect(_on_menu_item_pressed.bind(popup))


## Whether what an entry needs is in this scene.
func _menu_needs_met(needs: StringName) -> bool:
	match needs:
		NEEDS_DRAFT:
			return _draft != null
		NEEDS_PRESENTATION:
			return presentation != null
		NEEDS_PRESENCE:
			return _presence != null
	return true


## A menu whose whole subject is absent is not shown at all: a list of ten drawing tools in a
## scene with no drawing is not a menu, and every entry in it would be dead. The same rule the
## palette and the presentation panel are built by.
func _hide_unavailable_menus() -> void:
	if menu_bar == null:
		return
	for index in menu_bar.get_menu_count():
		var title: String = menu_bar.get_menu_title(index)
		if title == "Draft":
			menu_bar.set_menu_hidden(index, _draft == null)
		elif title == "Water":
			# A zone is a set of heads on the drawing, so a scene with no drawing has nothing to water.
			menu_bar.set_menu_hidden(index, _draft == null)
		elif title == "Light":
			# A circuit is a set of fixtures on the drawing, so a scene with no drawing has nothing to light.
			menu_bar.set_menu_hidden(index, _draft == null)
		elif title == "Site":
			# The ground lives on the drawing, so a scene with no drawing has no ground to state.
			menu_bar.set_menu_hidden(index, _ground_map() == null)
		elif title == "Estimate":
			# A takeoff measures a drawing, so a scene with none has nothing to take off.
			menu_bar.set_menu_hidden(index, _draft == null or _draft.document == null)
		elif title == "Present":
			menu_bar.set_menu_hidden(index, presentation == null)
		elif title == "Team":
			# A session is a node in the planner scene, so a scene without one has nothing to share.
			menu_bar.set_menu_hidden(index, _presence == null)


## Match the checks to the state, from the snapshot.
##
## Driven by a signature rather than by signals, like the palette and the presentation panel: the
## state a menu shows is changed from a key, a click, a menu entry and a script, and a signature
## cannot miss one of them the way a forgotten connection would.
func _refresh_menus() -> void:
	if menu_bar == null or _menu_items.is_empty():
		return
	# The bar can be narrower than fourteen menus want, and this is where that is noticed: this function
	# is already called every frame, with its own state guard underneath so that the common case costs a
	# string comparison and nothing else. `_fold_menu_bar_to_fit` does the same for the room.
	_fold_menu_bar_to_fit()
	# The bar has just been folded for this room, so its foot is where the fold has left it: a page placed by
	# the foot it had before that is a page drawn over the menu titles. Stating it here and putting the pages
	# up back by the same door keeps "every page lands below the bar" true of the bar as it now stands.
	if _state_the_strip_the_pages_may_not_use():
		_the_canvas_changed_shape()
	var world: Dictionary = menu_world()
	var state: String = str(world)
	if state == _menu_state:
		return
	_menu_state = state
	for popup: PopupMenu in _menu_items.keys():
		var entries: Array = _menu_items[popup]
		for index in entries.size():
			var entry: Dictionary = entries[index]
			var kind: StringName = entry.get("kind", &"command")
			if kind == &"radio" or kind == &"check":
				popup.set_item_checked(
					index,
					is_checked(StringName(entry.get("state", &"")), entry.get("value", null), world),
				)
			# An entry that only means something in some states says which, and is shown switched
			# off rather than doing nothing when the state is not on: Save with nothing to save.
			var available := StringName(entry.get("enabled_when", &""))
			if available != &"" and kind != &"info":
				popup.set_item_disabled(index, not is_enabled(available, world))
	_refresh_file_menu()
	_refresh_plant_menu()
	_refresh_site_menu()
	_refresh_water_menu()
	_refresh_light_menu()
	_refresh_estimate_menu()
	_refresh_pipeline_menu()
	_refresh_jobs_menu()
	_refresh_team_menu()
	_refresh_present_menu()


## An entry was chosen. The entry knows which method runs it, so there is no second list of ids
## here to fall out of step with the first - and the palette's own box comes through the same door,
## so a command cannot mean one thing from its menu and another from the list of the same commands.
func _on_menu_item_pressed(id: int, popup: PopupMenu) -> void:
	var entries: Array = _menu_items.get(popup, [])
	if id < 0 or id >= entries.size():
		return
	run_entry(entries[id])

# --- what each entry does -------------------------------------------------------------


## Plot the sheet, the way the palette button and the menu both mean it: with the yard's planting
## list on it, because the planting schedule is what a planting plan is plotted for, and a plan
## whose list has to be typed out again by hand is the job this app exists to remove.
##
## One door for both, so the button and the menu cannot plot two different sheets.
func _plot_sheet() -> void:
	if _draft != null:
		_draft.plot(_planting_rows())


func _menu_plot(_entry: Dictionary) -> void:
	_plot_sheet()


func _menu_quit(_entry: Dictionary) -> void:
	quit_requested()


## Quitting, from the menu or from the window's own close button: one door, so the second way out of
## the program cannot be the one that forgets to ask. The drawing lives in memory until it is written,
## and the window's close button is the way out nobody gets a second chance at.
func quit_requested() -> void:
	_guard_unsaved(&"quit")


## The window is being closed: the same question `File > Quit` asks, answered the same way.
##
## Godot would otherwise accept the request on its own, which is why `_ready` lowers
## `auto_accept_quit` - see the note there for why that is only done for a real window rather than in
## the editor's embedded game.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		quit_requested()
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST:
		back_puts_away()


## How long after one Back press another notification is still the same press.
##
## **Measured, on the SM-A166W (Android 16): 354 ms between the two notifications of a single press** - not the
## one to fifteen milliseconds `godotengine/godot#123454` reports on other hardware, which is why the first
## version of this guard was too narrow and let the second notification through. So the window is a second:
## wider than any gap the engine has been seen to leave, and shorter than the time it takes a person to see a
## page close and decide to press Back again - which is the same cadence Android's own "press back again to
## exit" uses. It is stated rather than measured so a test can hold the rule.
const BACK_REPEAT_GAP_MS := 1000

## When the last Back press was answered, so the engine's own repeat of it can be told from a second press.
var _last_back_ms: int = -BACK_REPEAT_GAP_MS


## Whether a Back notification arriving now is the engine saying the same press a second time.
static func is_a_repeat_of_the_last_back(now_ms: int, last_ms: int) -> bool:
	return now_ms - last_ms < BACK_REPEAT_GAP_MS


## What the phone's Back gesture means: out of whatever is in front, and only then out of the program.
##
## It is Escape's ladder with one thing put in front of it. A page in a `Window` takes the keyboard into
## its own viewport, so the ladder beside it can never answer for one - but a Back gesture arrives as a
## notification rather than as a key, and a notification reaches this node whatever holds the focus. The
## page is closed by emitting `close_requested`, which is the door its own frame and its own Close button
## already use, so Back and the cross cannot drift apart.
##
## Nothing in front means the ladder, and nothing left to put away means leaving - through
## `quit_requested`, so a drawing with unsaved work is asked about rather than thrown away by a brushed
## thumb. That is also why the program's own `quit_on_go_back` is lowered: left to the operating system,
## Back is a quit nobody is asked about.
##
## **One press is one act, and on this platform the engine says otherwise.** Godot 4.7.2 at `targetSdk 36`
## delivers `NOTIFICATION_WM_GO_BACK_REQUEST` **twice** for a single press: measured on the SM-A166W (Android
## 16), two notifications a few milliseconds apart, which is `godotengine/godot#123454` - for API 36 the engine
## intercepts Back through Android's `OnBackInvokedCallback`, and two senders report the same event. A ladder
## that takes one thing off per press therefore took two: with the front door up, the first put the door away
## and the second found nothing in front and left the program. The ladder was measured doing exactly that
## (`back now=9798 front=StartWindow`, then `back now=10152 front=<null>` 354 ms later). A notification
## arriving within `BACK_REPEAT_GAP_MS` of the last one is that same press, and is not answered again.
func back_puts_away() -> void:
	var now: int = Time.get_ticks_msec()
	if is_a_repeat_of_the_last_back(now, _last_back_ms):
		return
	_last_back_ms = now
	var page: Window = page_in_front()
	if page != null:
		page.close_requested.emit()
		return
	if escape_puts_away():
		return
	quit_requested()

# --- the drawing on disk --------------------------------------------------------------


## Whether an entry is available in this state, for the entries that come and go with the state
## rather than with the scene. Save is one - there is nothing to save until something has changed -
## and leaving the shared session is the other: there is no session to leave until one is open.
static func is_enabled(state: StringName, world: Dictionary) -> bool:
	match state:
		&"dirty":
			return bool(world.get("dirty", false))
		&"recovery":
			# There is nothing to recover until a session that ended without saving has left something,
			# which is the same rule Save follows: an entry that means nothing right now is shown
			# switched off rather than doing nothing when it is pressed.
			return bool(world.get("recovery", false))
		&"session_on":
			return bool(world.get("session_on", false))
		&"can_turn":
			# A desktop's window cannot be asked which way up to be, so the three orientation choices are
			# shown switched off there. Asked once here rather than by each entry, because it is one fact
			# about the machine.
			return OrientationChoiceScript.can_turn_here()
		&"finger":
			# A reading size multiplies the fitting done on a device answered with a finger, and a computer
			# is never fitted at all: its panels are the ones this program was drawn for. Asked once here,
			# for the same reason `can_turn` is.
			return PhoneHudScript.on_a_finger_here()
	return true


## The file dialogs: where a drawing comes from and where it goes.
##
## Built in code, like the rest of this file's furniture, and pointed at the drawings folder
## rather than at the filesystem at large: a drawing lives in `user://drawings`, and a dialog that
## opens anywhere invites somebody to file their drawing where the recent list cannot follow.
func _build_file_dialogs() -> void:
	# Parented to the HUD - the CanvasLayer - and not to `Root`, which is a Control with
	# `focus_mode` off so that nothing in the HUD can take the keyboard away from the drawing.
	# Godot 4.7 inherits focus behaviour down the tree, so a dialog under `Root` could not focus
	# its own file-name field: it opened, and could not be typed into. A CanvasLayer passes no
	# focus behaviour on, and the dialog's field gets the keyboard for as long as it is up.
	_open_dialog = FileDialog.new()
	_open_dialog.name = "OpenDrawing"
	_open_dialog.title = "Open a drawing"
	_open_dialog.access = FileDialog.ACCESS_USERDATA
	_open_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_open_dialog.current_dir = StoreScript.DIR
	_open_dialog.filters = PackedStringArray(["*.json ; Drawings"])
	_open_dialog.file_selected.connect(_on_open_chosen)
	add_child(_open_dialog)

	_save_dialog = FileDialog.new()
	_save_dialog.name = "SaveDrawing"
	_save_dialog.title = "Save the drawing"
	_save_dialog.access = FileDialog.ACCESS_USERDATA
	_save_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_save_dialog.current_dir = StoreScript.DIR
	_save_dialog.filters = PackedStringArray(["*.json ; Drawings"])
	_save_dialog.file_selected.connect(_on_save_as_chosen)
	add_child(_save_dialog)

	# A survey is a file somebody else sent, so this one reads the whole filesystem rather than
	# the app's own folder, and it takes the plain tables a surveyor actually sends.
	_survey_dialog = FileDialog.new()
	_survey_dialog.name = "ImportSurvey"
	_survey_dialog.title = "Import a survey"
	_survey_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_survey_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_survey_dialog.filters = PackedStringArray(["*.txt, *.csv, *.tsv, *.met ; Survey files"])
	_survey_dialog.file_selected.connect(_on_survey_chosen)
	add_child(_survey_dialog)

	# A DXF is the other half of "somebody else drew this": a surveyor's or an architect's CAD file,
	# which reads the whole filesystem for the same reason the survey one does.
	_dxf_dialog = FileDialog.new()
	_dxf_dialog.name = "ImportDxf"
	_dxf_dialog.title = "Import a DXF underlay"
	_dxf_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_dxf_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_dxf_dialog.filters = PackedStringArray(["*.dxf ; DXF drawings"])
	_dxf_dialog.file_selected.connect(_on_dxf_chosen)
	add_child(_dxf_dialog)

	# The way out, where the imports are the ways in. It reaches the filesystem rather than `user://`
	# because the whole point of a DXF is that somebody else's program opens it, and that program is
	# not looking inside this one's data folder.
	_dxf_export_dialog = FileDialog.new()
	_dxf_export_dialog.name = "ExportDxf"
	_dxf_export_dialog.title = "Save the drawing as a DXF"
	_dxf_export_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_dxf_export_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_dxf_export_dialog.current_file = "drawing.dxf"
	_dxf_export_dialog.filters = PackedStringArray(["*.dxf ; DXF drawings"])
	_dxf_export_dialog.file_selected.connect(_on_dxf_export_chosen)
	add_child(_dxf_export_dialog)

	# And the yard as a model. Two formats rather than one, and the dialog says what the difference is
	# where the choice is made: a filter is the closest thing a file dialog has to a sentence, and "one
	# file" against "pictures named rather than carried" is the whole of what a person needs to decide.
	# The binary one comes first, and is the one a name without an extension gets.
	_model_export_dialog = FileDialog.new()
	_model_export_dialog.name = "ExportModel"
	_model_export_dialog.title = "Save the yard as a 3D model"
	_model_export_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_model_export_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_model_export_dialog.current_file = "yard.glb"
	_model_export_dialog.filters = PackedStringArray(
		[
			"*.glb ; Binary glTF, one file with its pictures inside it",
			"*.gltf ; glTF text, with its pictures named rather than carried",
		]
	)
	_model_export_dialog.file_selected.connect(_on_model_export_chosen)
	add_child(_model_export_dialog)

	# And a LandXML plat is the third shape of the same thing: a file somebody else's software wrote,
	# holding the site rather than a drawing of it. It reads the whole filesystem for the same reason.
	_landxml_dialog = FileDialog.new()
	_landxml_dialog.name = "ImportLandXml"
	_landxml_dialog.title = "Import a LandXML plat"
	_landxml_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_landxml_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_landxml_dialog.filters = PackedStringArray(["*.xml ; LandXML plats"])
	_landxml_dialog.file_selected.connect(_on_landxml_chosen)
	add_child(_landxml_dialog)

	# A saved Overpass response: the offline half of the map import, for a site somebody looked at on a
	# machine that could reach the network. JSON only, because that is the one form the reader reads
	# and a dialog that offers a form it will refuse is a dialog that lies.
	_osm_dialog = FileDialog.new()
	_osm_dialog.name = "OsmDialog"
	_osm_dialog.title = "Open a saved map"
	_osm_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_osm_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_osm_dialog.filters = PackedStringArray(["*.json ; OpenStreetMap responses"])
	_osm_dialog.file_selected.connect(_on_osm_chosen)
	add_child(_osm_dialog)

	# And a picture: a scan, a photograph, a consultant's rendered plan. The one import that reads a
	# file with no linework in it, so the one that is copied into the app's own folder rather than read
	# into entities - the filter offers exactly the formats the reader can measure (see
	# `RasterUnderlay`), because a dialog offering a format that will be refused is a dialog that lies.
	_underlay_dialog = FileDialog.new()
	_underlay_dialog.name = "ImportPicture"
	_underlay_dialog.title = "Put a picture under the drawing"
	_underlay_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_underlay_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_underlay_dialog.filters = PackedStringArray([RasterUnderlayScript.dialog_filter()])
	_underlay_dialog.file_selected.connect(_on_underlay_chosen)
	add_child(_underlay_dialog)

	# Every door above that reaches files the person owns is handed to the phone's own picker where the
	# device has one, and `prepare()` decides that and nothing else: on a computer it returns without
	# touching a thing. Android gives a program permission to one document at a time and the picker is
	# how a document is handed over, so a door that reaches outside is the picker's business. The two
	# dialogs that stay inside `user://` are deliberately not in this list - a drawing is written to a
	# temporary file and renamed into place, and a hand-over cannot rename anything.
	for door: FileDialog in [
		_survey_dialog,
		_dxf_dialog,
		_dxf_export_dialog,
		_model_export_dialog,
		_landxml_dialog,
		_osm_dialog,
		_underlay_dialog,
	]:
		PhoneFilesScript.prepare(door)

	_discard_dialog = ConfirmationDialog.new()
	_discard_dialog.name = "DiscardChanges"
	_discard_dialog.title = "Unsaved changes"
	# Two buttons, and neither of them is "save": the way to save is one click away in the menu
	# that raised this, and a dialog that can write files is a dialog that can write the wrong
	# one. What it asks is only whether the changes may be let go.
	_discard_dialog.ok_button_text = "Discard"
	_discard_dialog.cancel_button_text = "Keep editing"
	_discard_dialog.confirmed.connect(_on_discard_confirmed)
	_discard_dialog.canceled.connect(_on_discard_cancelled)
	add_child(_discard_dialog)

	# Auto-simplify asks first, because it is the one drafting command that changes many shapes
	# at once and takes something away from each of them. What it shows is the pass's own
	# report, so the number of shapes and the number of refusals are the pass's numbers rather
	# than a second count that could disagree with it.
	_simplify_dialog = ConfirmationDialog.new()
	_simplify_dialog.name = "SimplifyDrawing"
	_simplify_dialog.title = "Simplify"
	_simplify_dialog.ok_button_text = "Simplify"
	_simplify_dialog.cancel_button_text = "Cancel"
	_simplify_dialog.confirmed.connect(_on_simplify_confirmed)
	_simplify_dialog.canceled.connect(_on_simplify_cancelled)
	add_child(_simplify_dialog)


func _file_dialog_open() -> bool:
	return (_open_dialog != null and _open_dialog.visible) \
			or (_save_dialog != null and _save_dialog.visible) \
			or (_discard_dialog != null and _discard_dialog.visible) \
			or (_recovery_dialog != null and _recovery_dialog.visible) \
			or (_underlay_dialog != null and _underlay_dialog.visible)


## Ask before throwing work away, then do what was asked for.
##
## The action is held as an id rather than as a Callable: a question can sit open while the scene
## moves on, and a captured closure would then run against a world that is no longer there.
func _guard_unsaved(next: StringName) -> void:
	if _draft == null or not _draft.dirty or _discard_dialog == null:
		_run_pending(next)
		return
	_pending_action = next
	_discard_dialog.dialog_text = "%s\n\nDiscard the changes?" % _draft.drawing_state_text()
	_ask(_discard_dialog)


## Show one of the program's own questions so that a finger can read it and press it.
##
## A `ConfirmationDialog` is a `Window`, and no pass touched it: `PhoneHud.fit_the_chrome_for_a_finger` fits the
## chrome and a `PopupMenu` and nothing else that is a window, and a *page* is fitted by `PageChrome` when it is
## shown, which a question never goes through. Measured on the A16W, the unsaved-changes question was drawn at
## the desk's 16 px with its buttons 50 px tall while everything around it was a finger's - five `tiny`/`small`
## lines, on the one screen whose whole job is to be read before anything is thrown away - and it was placed at
## whatever size its own contents happened to want rather than inside the room.
##
## So a question is fitted through the one walk that fits a window's controls - its `dialog_text` and its two
## buttons, which is every word the probe could name - and then placed by `popup_centered_clamped`, the door the
## command palette places itself by, which centres it and keeps it on the screen. The walk answers zero on a
## computer, so a desk is neither touched nor restored.
##
## **Its title bar is deliberately left as the theme drew it.** A page's title is grown and is *meant* to hang
## above the page's own panel, onto the sheet one of the doorway pages stands on; a question has no sheet behind
## it, so growing the bar pushed its title out of the filled band it had been legible in and onto the bright
## board, where the theme's own light ink could not be read - measured on the glass beside the page's, which
## reads only because the sheet is dark. The theme's own bar keeps the title inside the fill, and there a person
## can read it.
func _ask(question: ConfirmationDialog) -> void:
	if question == null:
		return
	# **A question is fitted before it is shown, and its row is asked for through the frame rather than through
	# a minimum.** A `ConfirmationDialog`'s own two buttons are the engine's, and it takes their
	# `custom_minimum_size` away the moment the dialog is shown: measured on the desk with the phone's own
	# numbers handed in, `(107.078, 107.078)` before `popup_centered_clamped()` and `(0, 0)` after it, with the
	# font override surviving. Measured on the A16W held upright, the probe named what that leaves -
	# `Button "Keep editing" is 254 x 64, 33 px short of the 97 a finger wants` - a fault the landscape-only
	# measurement never showed, because the row is the same 97 px of screen either way up while being 60 layout
	# px lying down against 107 upright. So the row is given where the engine cannot take it back, through the
	# button's own frame (`PhoneHud.give_a_dialogs_own_button_the_row`).
	#
	# **The fit stays before the popup, and it has to.** A dialog is placed by the size its contents ask for, so
	# placing it first sizes it for buttons that have not grown yet and squeezes them back down; asking it to
	# take its size again afterwards was tried and is worse - `reset_size` walks the window into the room's
	# corner, and the A16W measured the `Discard` button standing 95 px into the band the device keeps.
	if shows_touch_controls():
		fit_a_question_for_a_finger(question, PhoneHudScript.canvas_scale(get_window()), PhoneHudScript.dpi())
	question.popup_centered_clamped()


## The measuring half of `_ask`, with the device stated rather than read, so that a test can hold what a phone
## would be told without being one - the same door `fit_the_chrome_for_a_finger` is for the chrome.
func fit_a_question_for_a_finger(question: ConfirmationDialog, drawn_at: float, density: float) -> int:
	return PhoneHudScript.fit_the_chrome_for_a_finger(question, drawn_at, density)


func _on_discard_confirmed() -> void:
	var next := _pending_action
	_pending_action = &""
	_run_pending(next)


func _on_discard_cancelled() -> void:
	# Closing the question decides nothing, so the action is dropped rather than left armed for
	# whatever the next click happens to be.
	_pending_action = &""
	_pending_path = ""


## Ask what auto-simplify would do before it does it. A pass that changes nothing still opens
## the question: "nothing to simplify" is an answer a person asked for, and a menu item that
## silently does nothing looks broken.
func _menu_simplify(_entry: Dictionary) -> void:
	if _draft == null or _simplify_dialog == null:
		return
	_pending_simplify = _draft.plan_simplify()
	_simplify_dialog.dialog_text = _pending_simplify.describe()
	_ask(_simplify_dialog)


func _on_simplify_confirmed() -> void:
	if _draft == null or _pending_simplify == null:
		return
	_draft.apply_simplify(_pending_simplify)
	_pending_simplify = null


func _on_simplify_cancelled() -> void:
	# The plan was worked out against a drawing that has since been left alone, so it is
	# dropped rather than kept for a second question.
	_pending_simplify = null


func _run_pending(next: StringName) -> void:
	match next:
		&"new":
			if _draft != null:
				_draft.new_drawing()
			# A new drawing has a new history - its own, empty one - so a window already showing the old
			# drawing's revisions is showing something that is no longer true.
			_refresh_revision_window()
			# A new drawing also has no unsaved work in it, and what was left behind by an earlier
			# session is read off the disk rather than guessed at.
			_refresh_pending_recovery()
		&"open":
			if _pending_path.is_empty():
				open_drawing_dialog()
			else:
				var path: String = _pending_path
				_pending_path = ""
				if _draft != null:
					_draft.open_drawing(path)
				_refresh_revision_window()
				_refresh_pending_recovery()
		&"quit":
			get_tree().quit()


func open_drawing_dialog() -> void:
	if _open_dialog == null:
		return
	_open_dialog.current_dir = StoreScript.DIR
	_open_dialog.popup_centered_ratio(0.7)


## The Save As dialog, offered a name. The project's own name to begin with, because a drawing of
## a garden is much more often called what the garden is called than it is called "untitled".
func save_drawing_dialog() -> void:
	if _save_dialog == null or _draft == null:
		return
	_save_dialog.current_dir = StoreScript.DIR
	# Not `name`: this is a CanvasLayer, and `name` is the node's own.
	var file_name := StoreScript.display_name(_draft.drawing_path)
	if file_name.is_empty():
		file_name = StoreScript.sanitise(_draft.project_name)
	_save_dialog.current_file = file_name + StoreScript.EXTENSION
	_save_dialog.popup_centered_ratio(0.7)


func _on_open_chosen(path: String) -> void:
	_pending_path = ""
	if _draft != null:
		_draft.open_drawing(path)
	# The history came with the drawing, so a window already showing the last drawing's revisions is
	# showing something that is no longer true.
	_refresh_revision_window()
	# Saving and opening both change what is waiting: opening the file a copy belonged to says the file
	# is what was wanted.
	_refresh_pending_recovery()
	release_keyboard_focus(self)


func _on_save_as_chosen(path: String) -> void:
	if _draft == null:
		return
	# A name typed without the extension is given one rather than trusted: a drawing the Open
	# dialog cannot see is a drawing that cannot be opened again.
	var target := path if path.ends_with(StoreScript.EXTENSION) else path + StoreScript.EXTENSION
	_draft.save_drawing(target)
	# The copy was of work that is now on disk, so it is not a rescue any more.
	_refresh_pending_recovery()
	release_keyboard_focus(self)


func _menu_new_drawing(_entry: Dictionary) -> void:
	_guard_unsaved(&"new")


func _menu_open_drawing(_entry: Dictionary) -> void:
	_pending_path = ""
	_guard_unsaved(&"open")


func _menu_open_recent(entry: Dictionary) -> void:
	_pending_path = str(entry.get("value", ""))
	_guard_unsaved(&"open")


func _menu_save_drawing(_entry: Dictionary) -> void:
	if _draft == null:
		return
	# A drawing with no name yet is what Save As is for, and Save standing in for it is what a
	# person expects: the alternative is being told the drawing has no name on the one command
	# that exists to give it one.
	if _draft.drawing_path.is_empty():
		save_drawing_dialog()
		return
	_draft.save_drawing()
	# Likewise whatever is waiting: the copy of the drawing just saved is not a rescue any more.
	_refresh_pending_recovery()


func _menu_save_drawing_as(_entry: Dictionary) -> void:
	save_drawing_dialog()

# --- a copy kept in case the program stops --------------------------------------------


## The question asked before work a session that ended without saving left behind goes back on the
## drawing.
##
## **Recover** puts it back, **Discard it** throws it away, and closing the window - or pressing **Not
## now** - decides nothing and leaves the copy where it is. Three answers rather than the usual two,
## because a dialog's cancel button and its close button are the same signal: a stray Escape must not
## be the one act that destroys the only copy of somebody's work.
func _build_recovery_dialog() -> void:
	_recovery_dialog = ConfirmationDialog.new()
	_recovery_dialog.name = "RecoverUnsaved"
	_recovery_dialog.title = "Recover unsaved work"
	_recovery_dialog.ok_button_text = "Recover"
	_recovery_dialog.cancel_button_text = "Not now"
	_recovery_dialog.confirmed.connect(_on_recovery_confirmed)
	_recovery_dialog.custom_action.connect(_on_recovery_action)
	_recovery_dialog.add_button("Discard it", true, "discard")
	add_child(_recovery_dialog)


## Keep a copy of the drawing while it has changes the file does not hold, at most once every half
## minute.
##
## Reads `_draft` rather than a signal, because the question it asks - has this drawing unsaved
## changes - is one field, and asking it is cheaper than routing a notification for every edit. Both
## halves of the decision are the store's: `is_due` owns the interval, and the store refuses an empty
## drawing so that a copy of nothing is never offered back.
func _tick_autosave(delta: float) -> void:
	if _draft == null:
		return
	_autosave_clock += delta
	if not AutosaveScript.is_due(_draft.dirty, _autosave_clock):
		return
	_autosave_clock = 0.0
	var kept: Dictionary = _draft.keep_a_copy()
	if bool(kept["ok"]):
		# The copy just written is of the drawing on the screen, so it is nothing to offer back - but it
		# *replaces* a copy of the same name, and a copy a session that never saved left behind has to
		# stop being offered the moment it is gone.
		_refresh_pending_recovery()


## Read what is waiting off disk.
##
## Called where it can have changed - startup, a copy being written, a drawing being saved, opened or
## thrown away, and the question being answered - and never from `menu_world`, which is built on the
## way to *every* menu refresh: a directory listing is not something a frame may do.
func _refresh_pending_recovery() -> void:
	_pending_recovery = _draft.pending_recovery() if _draft != null else { }


## The one line the File menu adds when a session that ended without saving left work behind. Empty in
## the ordinary case, so the line reads as it always did.
func _recovery_notice() -> String:
	if _pending_recovery.is_empty():
		return ""
	return "unsaved work from an earlier session"


## What the File menu's top line says: which drawing is open and whether the screen and the file
## agree, plus the one thing that line has to say when nobody is looking for it - that a session which
## ended without saving left work behind.
func _drawing_state_with_recovery() -> String:
	var words: String = _draft.drawing_state_text()
	var notice: String = _recovery_notice()
	if not notice.is_empty():
		words += "  |  %s" % notice
	return words


func _menu_recover_unsaved(_entry: Dictionary) -> void:
	if _pending_recovery.is_empty():
		_refresh_pending_recovery()
	if _pending_recovery.is_empty() or _recovery_dialog == null:
		return
	_recovery_dialog.dialog_text = (
		"A copy of a drawing was kept by a session that ended without saving it.\n\n%s\n\nPut it back?"
		% AutosaveScript.describe(_pending_recovery)
	)
	_ask(_recovery_dialog)


func _on_recovery_confirmed() -> void:
	if _draft != null:
		_draft.recover_pending()
	_refresh_pending_recovery()
	# The history came with the drawing, so a window already showing the last drawing's revisions is
	# showing something that is no longer true.
	_refresh_revision_window()
	release_keyboard_focus(self)


func _on_recovery_action(action: StringName) -> void:
	if action != &"discard":
		return
	_discard_the_recovery()


## Say no to the copy. It is removed rather than merely passed over, because a question a person has
## answered must not be asked again on the next launch.
func _discard_the_recovery() -> void:
	if _draft != null:
		_draft.discard_pending()
	_refresh_pending_recovery()
	release_keyboard_focus(self)


## The two parts of the File menu that are live: the line naming the drawing, and the list of what
## was opened recently. Everything else in the bar is a fixed set of entries whose ticks move.
func _refresh_file_menu() -> void:
	if _draft == null:
		return
	var named := _find_item(&"file.info")
	if not named.is_empty():
		var popup: PopupMenu = named[0]
		popup.set_item_text(int(named[1]), _drawing_state_with_recovery())
	var recent := ", ".join(PackedStringArray(_draft.recent_drawings()))
	if recent != _recent_filled:
		_recent_filled = recent
		_fill_recent_menu()


## One item of the bar, by id, as `[popup, index, entry]`, or nothing when it is not there.
func _find_item(id: StringName) -> Array:
	for popup: PopupMenu in _menu_items.keys():
		var entries: Array = _menu_items[popup]
		for index in entries.size():
			if StringName(entries[index].get("id", &"")) == id:
				return [popup, index, entries[index]]
	return []


## Refill the list of recently opened drawings.
##
## The one part of the bar whose *entries* are not fixed: a recent list built once at startup
## would never show a drawing that has just been saved, and one that was never pruned would offer
## files that are no longer there. The drawings themselves come from the store, which drops a
## remembered drawing the moment it stops existing.
func _fill_recent_menu() -> void:
	if _recent_popup == null or _draft == null:
		return
	_recent_popup.clear()
	var entries: Array[Dictionary] = []
	var paths: Array[String] = _draft.recent_drawings()
	if paths.is_empty():
		_recent_popup.add_item("nothing yet")
		_recent_popup.set_item_disabled(0, true)
		entries.append(
			{
				"kind": &"info",
				"id": &"file.recent.none",
				"label": "nothing yet",
				"action": &"",
				"needs": NEEDS_NOTHING,
				"value": null,
			}
		)
	else:
		for path in paths:
			# Not `name`: this is a CanvasLayer, and `name` is the node's own.
			var file_name := StoreScript.display_name(path)
			_recent_popup.add_item(file_name)
			entries.append(
				{
					"kind": &"command",
					"id": StringName("file.recent." + file_name),
					"label": file_name,
					"action": &"",
					"method": &"_menu_open_recent",
					"needs": NEEDS_DRAFT,
					"value": path,
				}
			)
	_menu_items[_recent_popup] = entries


## Both of these write through to the set's current sheet, so choosing A4 from the menu and choosing it
## in the sheet window are the same act rather than two numbers that drift apart.
func _menu_set_sheet(entry: Dictionary) -> void:
	if _draft != null:
		_draft.set_sheet_size(String(entry["value"]))
		if is_sheet_window_open():
			_refresh_sheet_window()


func _menu_set_scale(entry: Dictionary) -> void:
	if _draft != null:
		_draft.set_plot_scale(float(entry["value"]))
		if is_sheet_window_open():
			_refresh_sheet_window()


func _menu_undo(_entry: Dictionary) -> void:
	if _draft != null:
		_draft.undo()


func _menu_redo(_entry: Dictionary) -> void:
	if _draft != null:
		_draft.redo()


func _menu_drop_point(_entry: Dictionary) -> void:
	if _draft != null:
		_draft.undo_point()


func _menu_cancel_shape(_entry: Dictionary) -> void:
	if _draft != null:
		_draft.cancel()


func _menu_finish(_entry: Dictionary) -> void:
	if _draft != null:
		_draft.finish()


func _menu_close_shape(_entry: Dictionary) -> void:
	if _draft != null:
		_draft.finish_closed()


func _menu_set_dimension_style(entry: Dictionary) -> void:
	if _draft != null:
		_draft.set_dimension_style(StringName(entry["value"]))


func _menu_cycle_dimension_style(_entry: Dictionary) -> void:
	if _draft != null:
		_draft.cycle_dimension_style()


func _menu_toggle_drawing(_entry: Dictionary) -> void:
	if _draft != null:
		_draft.set_drawing(not _draft.drawing)


func _menu_arm_tool(entry: Dictionary) -> void:
	if _draft != null:
		@warning_ignore("int_as_enum_without_cast")
		_draft.arm(int(entry["value"]))


## Take an editing command from the menu or a palette button. It is a mode of the
## drawing tools, so it puts planting away the same way a keyboard press does.
func arm_edit_command(kind: int) -> void:
	if _draft == null:
		return
	if view_controller != null and view_controller.is_planting():
		view_controller.stop_planting()
	@warning_ignore("int_as_enum_without_cast")
	_draft.arm_edit(kind)


func _menu_arm_edit(entry: Dictionary) -> void:
	arm_edit_command(int(entry["value"]))


## Choose which way round the selection band catches things, and put it in hand.
##
## Choosing a mode is choosing the tool: a mode with no band out is a preference
## nobody can see, and the plant in hand has to be dropped first or a click would
## mean two things at once.
func _menu_select_mode(entry: Dictionary) -> void:
	if _draft == null:
		return
	if view_controller != null and view_controller.is_planting():
		view_controller.stop_planting()
	_draft.arm_select(StringName(entry["value"]))


## Bring the flat 2D plan forward. A drawing that has just been started - new, opened, or the example -
## is read as the empty sheet it is rather than as the furnished overhead view that stood behind the
## doorway, which is the difference between "a new drawing" and "an example somebody loaded".
func _show_the_plan() -> void:
	if view_controller != null:
		view_controller.show_mode(ViewController.ViewMode.PLAN_2D)


func _menu_show_mode(entry: Dictionary) -> void:
	if view_controller != null:
		@warning_ignore("int_as_enum_without_cast")
		view_controller.show_mode(int(entry["value"]))


func _menu_fit(_entry: Dictionary) -> void:
	if view_controller != null:
		view_controller.fit_plan_to_yard()


func _menu_painted(_entry: Dictionary) -> void:
	open_painted()


## Show or put away the garden the program ships with, under the drawing on the page.
func _menu_toggle_site(_entry: Dictionary) -> void:
	if view_controller != null:
		view_controller.set_site_shown(not view_controller.is_site_shown())


## Lay the example garden out on the sheet, and bring its site forward with it: the example *is* the
## shipped garden, so drawing it without the site would be showing half of what was asked for.
func _menu_example_garden(_entry: Dictionary) -> void:
	draw_the_example()
	_show_the_plan()


## The camera, from inside the drawing.
func _menu_take_a_photograph(_entry: Dictionary) -> void:
	open_camera_window()


func _menu_toggle_hints(_entry: Dictionary) -> void:
	_show_hints = not _show_hints
	_apply_hints_visibility()


## Choose which way up the board is asked to stand. What the window is actually asked for goes through
## `the_shape_for_the_window`, so a choice made while a doorway page is up does not pin the door: the door
## follows the phone until a drawing begins, and that is the one rule the two halves share. The answer is
## kept, so the next run opens the way this one was left.
func _menu_set_orientation(entry: Dictionary) -> void:
	var choice: StringName = StringName(entry.get("value", OrientationChoiceScript.DEFAULT))
	if choice == _orientation:
		return
	_orientation = choice
	OrientationChoiceScript.remember(choice)
	# A choice is the one moment the window is asked for something a person has just said, so it is said out
	# loud too - the reading beside the hold, which is exactly where the 4-versus-6 fault hides.
	var shape: StringName = the_shape_for_the_window()
	_say_what_the_window_was_asked_for(&"chosen", shape)
	OrientationChoiceScript.apply(shape)


## Take a reading size: the sizes the program draws at are `PhoneHud`'s, so the answer is handed to it and
## everything is fitted again rather than each control being resized where the choice was made.
##
## The board is fitted at once. A page that is open is fitted with it, and fitting a page twice is drawing the
## same page bigger rather than growing it twice - a page's own words are grown from the size the page laid
## them out at, which is remembered on the control. On a computer nothing happens at all: a desk is never
## fitted, and the menu does not offer these three there.
func _menu_set_reading_size(entry: Dictionary) -> void:
	var choice: StringName = StringName(entry.get("value", ReadingSizeScript.DEFAULT))
	if choice == _reading_size:
		return
	_reading_size = choice
	ReadingSizeScript.choose(choice)
	PhoneHudScript.use_reading_scale(ReadingSizeScript.factor())
	_size_palette_for_a_finger.call_deferred()
	_size_the_chrome_for_the_device.call_deferred()
	for window: Window in get_viewport().get_embedded_subwindows():
		if window.visible:
			PageChrome.size_for_a_finger(window)


func _menu_toggle_presentation(_entry: Dictionary) -> void:
	if presentation == null:
		return
	if presentation.is_active():
		presentation.end()
		return
	presentation.begin(presentation.tier)


func _menu_set_tier(entry: Dictionary) -> void:
	if presentation != null:
		presentation.set_tier(int(entry["value"]))


func _menu_frame_yard(_entry: Dictionary) -> void:
	if presentation != null:
		presentation.frame_yard()


func _menu_set_still_size(entry: Dictionary) -> void:
	if _still_size_option != null:
		_still_size_option.selected = int(entry["value"])


func _menu_render_still(_entry: Dictionary) -> void:
	_on_render_still()


func _menu_save_site(_entry: Dictionary) -> void:
	if presentation != null:
		presentation.save_site()


func _menu_keys(_entry: Dictionary) -> void:
	if is_keys_open():
		close_keys()
	else:
		open_keys()


## Show the manual. Nothing is asked of the drawing, so this works in any scene this HUD is in.
func _menu_help(_entry: Dictionary) -> void:
	open_help_window()


## The manual, opened at what the page in front of you is asking. `_menu_help` opens it at the top, which
## is the right thing for someone who wants to browse; this is the right thing for someone who has a page
## open and does not know what it wants from them, which is the question a manual is actually asked.
func _menu_page_help(_entry: Dictionary) -> void:
	open_page_help()


## The page a person is looking at: the last one the HUD has up.
##
## `_pages_that_can_be_up` is the list a change of the window's shape already walks, so a page added to the
## HUD is answerable here without being added to a second list - and a second list is exactly the thing that
## would fall behind. It is deliberately wider than `pages_in_windows`, and that width is the whole point:
## the doorway's pages are the ones a person meets first, so a launch that has just stood the front door up
## has that door as the page in front of everything. Leaving them out was not harmless - the phone's Back
## gesture asks this question, and finding nothing it went on to leave the program rather than put the door
## away (measured on the SM-A166W, and the fault this fixes).
func page_in_front() -> Window:
	var pages: Array[Window] = _pages_that_can_be_up()
	for i: int in range(pages.size() - 1, -1, -1):
		var page: Window = pages[i]
		if page != null and page.visible:
			return page
	return null


## The manual subject that answers what the page in front of you is asking, or an empty string when there
## is none - in which case `page_help_refusal` says why, in the words a person reads.
func page_help_subject() -> String:
	var page: Window = page_in_front()
	if page == null:
		return ""
	return PageHelpScript.subject_for(PageLayoutScript.page_name(page))


## Why there is nothing to show, or an empty string when there is. The two functions answer the question
## between them, and neither has to be checked for the other's answer.
##
## The refusals are worth reading: a page the manual has not reached says *what that page is about*, so
## the person holding the gap can see what is missing rather than only that something is.
func page_help_refusal() -> String:
	var page: Window = page_in_front()
	if page == null:
		return "no page is open: this asks the manual about the page in front of you"
	var asked: String = PageLayoutScript.page_name(page)
	if PageHelpScript.has_a_way_to_the_manual(asked):
		return ""
	if PageHelpScript.WITHOUT_NEED.has(asked):
		return String(PageHelpScript.WITHOUT_NEED[asked])
	if PageHelpScript.NOT_YET_WRITTEN.has(asked):
		return "the manual has not reached \"%s\" yet: %s" % [asked, String(PageHelpScript.NOT_YET_WRITTEN[asked])]
	return "the manual has nothing about \"%s\"" % asked


## Show the manual at what the page in front of you is asking. Returns whether it opened, and says why
## when it did not - the drawing's status line is where this HUD says things, so it goes there.
func open_page_help() -> bool:
	var subject: String = page_help_subject()
	if subject.is_empty():
		if _draft != null:
			_draft.last_message = page_help_refusal()
		return false
	open_help_window()
	if _help_window == null:
		return false
	if not _help_window.select_topic(subject):
		if _draft != null:
			_draft.last_message = "the manual has no subject called \"%s\"" % subject
		return false
	if _draft != null:
		_draft.last_message = "the manual, on \"%s\"" % subject
	return true

# --- the key reference ----------------------------------------------------------------


## The keys, in one place.
##
## Every line is a string that already exists - the hint lines the HUD shows, and the drafting
## legend built from the tool tables - so this panel cannot disagree with the corner of the screen
## it is quoting. It is built in code for that reason: it is a view of three tables, not a fourth
## copy of them.
func _build_keys_panel() -> void:
	var root := get_node_or_null(^"Root")
	if root == null:
		return
	var wrapper := BoardPanelScript.new()
	wrapper.name = "KeysPanel"
	wrapper.set_anchors_preset(Control.PRESET_FULL_RECT)
	# The wrapper is only a placement; the panel inside it takes the clicks, so the drawing
	# underneath is not blocked by an invisible full-screen control.
	wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrapper.visible = false

	var panel := PanelContainer.new()
	panel.name = "Page"
	panel.custom_minimum_size = Vector2(700.0, 0.0)
	if top_bar != null:
		# The same furniture as every other box on the screen, borrowed rather than copied: one
		# panel style, so a change to it changes all of them.
		panel.add_theme_stylebox_override("panel", top_bar.get_theme_stylebox("panel"))
	var column := VBoxContainer.new()
	column.name = "Column"
	panel.add_child(column)

	var heading := Label.new()
	heading.name = "Heading"
	heading.text = "Keys"
	column.add_child(heading)

	var body := Label.new()
	body.name = "KeysText"
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.text = keys_text()
	column.add_child(body)

	var footer := Label.new()
	footer.name = "Footer"
	footer.add_theme_font_size_override("font_size", 12)
	footer.text = keys_footer()
	column.add_child(footer)

	var close_button := Button.new()
	close_button.name = "CloseKeys"
	close_button.text = "Close"
	close_button.pressed.connect(close_keys)
	column.add_child(close_button)

	wrapper.add_child(panel)
	_keys_panel = wrapper
	root.add_child(wrapper)


## The pages of the reference, from the strings the HUD already shows.
func keys_text() -> String:
	var rows: Array[String] = []
	rows.append("Top-down and overhead")
	rows.append("    " + _hints_for(ViewController.ViewMode.PLAN_2D))
	# The overhead views on a touchscreen, quoted from the constant the foot of the screen uses, for the same
	# reason the ground view's is quoted rather than restated: the reference and the phone cannot drift apart.
	rows.append("Top-down and overhead, on a touchscreen")
	rows.append("    " + HINTS_OVERHEAD_ON_A_FINGER)
	rows.append("Ground view")
	rows.append("    " + HINTS_GROUND)
	# The same view on a touchscreen, quoted from the constant the foot of the screen uses, so the reference
	# and the phone cannot drift apart - and a person reading the keys on a desk still learns what a thumb
	# would be offered.
	rows.append("Ground view, on a touchscreen")
	rows.append("    " + HINTS_GROUND_ON_A_FINGER)
	rows.append("Drawing")
	rows.append_array(drafting_rows())
	rows.append("Elsewhere")
	rows.append_array(_wrap(_entries(ELSEWHERE_KEYS), ELSEWHERE_PER_ROW))
	return "\n".join(PackedStringArray(rows))


## What the reference says about the program itself.
func keys_footer() -> String:
	return "landscaping planner    Godot %s    sheets are written to user://sheets, stills to user://proposals" % String(
		Engine.get_version_info()["string"]
	)


func is_keys_open() -> bool:
	return _keys_panel != null and _keys_panel.visible


func open_keys() -> void:
	if _keys_panel != null:
		_keys_panel.visible = true


func close_keys() -> void:
	if _keys_panel != null:
		_keys_panel.visible = false


# --- the manual --------------------------------------------------------------------------
#
# The manual is one page: the contents of `HelpDoc` beside the text of whichever subject is chosen,
# with a box to search it by. A `Window` for the reason every other page here is one - a text field
# is the one thing this HUD may not own outside a window.
#
# The keys are the one subject the manual does not carry as prose. They are built by `keys_text()`,
# which is the same string the key reference shows, so the manual cannot name a key that does nothing
# - the half worth deriving is derived, and there is no fourth copy of the bindings to drift.

## The subject the keys live under, appended to the manual's own topics.
const KEYS_TOPIC := "Keys"
## The heading the keys are listed under. The manual's own sections come from `HelpDoc`; this one is
## the HUD's, because the keys topic is the HUD's - it is derived from the key tables, not written out
## as prose, so it is not a subject of the manual and has no section in the manual's own table.
const KEYS_SECTION := "Reference"


## Build the manual's window by hand, so the window the designer opens is the window this file has
## already wired to the menu. Built before it is ever shown, because a window that builds itself on
## its first `_ready` shows an empty frame for one frame.
func _build_help_window() -> void:
	if _help_window != null:
		return
	_help_window = HelpWindowScript.new()
	_help_window.name = "HelpWindow"
	add_child(_help_window)
	_help_window.hide()


## The topics the manual shows: everything it documents, and then the keys - appended rather than
## written into it, because the keys come from the tables that actually drive the program.
func help_topics() -> Array[Dictionary]:
	var topics: Array[Dictionary] = HelpDocScript.topics()
	# Filed under its own heading: the keys are the one subject the manual does not carry as prose, and
	# left unsectioned they would sit under the last section of the manual and read as part of it.
	topics.append({ "title": KEYS_TOPIC, "body": keys_text(), "section": KEYS_SECTION })
	return topics


## Point the manual at what it is to show. Kept apart from showing the window itself so that the
## filling can be driven without a window server, which is how the suite checks it.
func _fill_help_window() -> void:
	if _help_window == null:
		return
	_help_window.set_topics(help_topics())


func open_help_window() -> void:
	if _help_window == null:
		return
	_fill_help_window()
	# Opening is the page's own business, and the page's own business is `PageChrome`: the page hands itself
	# to that one door, which fits its floor to the room it lands in, sizes its controls for a finger, grows
	# its words for the screen and puts the keyboard in the search box. Until 2026-11-14 this page worked its
	# own floor out and popped itself up instead, which is why the manual was the one page a phone drew in the
	# desk's 16 px type - five lines at 16 px where the screen needs 30, found by `tools/phone_touch_sweep.gd`.
	_help_window.open()
	# A window holds the keyboard while it is up, which is what a window is for; the moment it closes
	# the drawing keys belong to the drawing again.
	release_keyboard_focus(self)


func close_help_window() -> void:
	if _help_window != null:
		_help_window.hide()


func is_help_window_open() -> bool:
	return _help_window != null and _help_window.visible

# --- the command palette --------------------------------------------------------------
#
# The whole bar in one box with a field to type into: the way to reach a command whose name you know
# and whose menu you do not, and the only way to reach one whose key has been forgotten. It is the
# same subject as the manual - "how do I do this here" - which is why the two sit together in Help.
#
# It holds no list of its own. The rows come from `menu_plan()`, the bar's one source, and each row
# carries the entry it stands for, so a command runs through the same door from the palette as from
# its menu (`run_entry`). A palette with its own list of commands would be a second menu bar, and the
# two would drift the first time one of them gained an entry.


## Build the palette by hand, so the box the designer opens is the box this file has already wired to
## the bar. Built before it is ever shown, because a window that builds itself on its first `_ready`
## shows an empty frame for one frame.
func _build_command_palette() -> void:
	if _command_palette != null:
		return
	_command_palette = CommandPaletteScript.new()
	_command_palette.name = "CommandPalette"
	add_child(_command_palette)
	_command_palette.chosen.connect(_on_command_chosen)
	_command_palette.hide()


## Every command the bar holds, as a row the palette can show and run.
##
## Read fresh every time rather than kept, because what the bar holds is derived from tables that
## change with the drawing: a palette holding this morning's list would offer commands that are not
## in the drawing open now.
##
## The punctuation is left out. A separator does nothing, an "info" line is a sentence rather than a
## command, and a submenu heading is a name for a set of commands rather than one of them - but the
## commands *inside* a submenu are commands, and they are here, because a palette that could not
## reach the plot scales would be a box with a hole in it.
func command_rows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry: Dictionary in menu_entries():
		var kind: StringName = entry.get("kind", &"command")
		if kind == &"separator" or kind == &"info" or kind == &"submenu":
			continue
		var needed: bool = _menu_needs_met(StringName(entry.get("needs", NEEDS_NOTHING)))
		var gated: StringName = StringName(entry.get("enabled_when", &""))
		var enabled: bool = gated == &"" or is_enabled(gated, menu_world())
		out.append(command_row(entry, needed, enabled))
	return out


## One row: what the command is called, the key that also does it, the menu it lives under, and
## whether it can run here - with the reason when it cannot.
##
## The two questions are handed in rather than worked out here so that the row is a pure function of
## them: whether a scene satisfies an entry is the bar's business (`_menu_needs_met`, `is_enabled`),
## and this decides only what the row *says* about it.
static func command_row(entry: Dictionary, needed: bool, enabled: bool) -> Dictionary:
	var why: String = ""
	if not needed:
		why = needs_words(StringName(entry.get("needs", NEEDS_NOTHING)))
	elif not enabled:
		why = gated_words(StringName(entry.get("enabled_when", &"")))
	return {
		"id": String(entry.get("id", "")),
		"label": String(entry.get("label", "")),
		"key": _key_label(StringName(entry.get("action", &""))),
		"menu": String(entry.get("menu", "")),
		"method": StringName(entry.get("method", &"")),
		"entry": entry,
		"available": why == "",
		"why": why,
	}


## What a command needs that this scene has not got, in words rather than in the name of the need.
static func needs_words(needs: StringName) -> String:
	match needs:
		NEEDS_DRAFT:
			return "there is no drawing open"
		NEEDS_PRESENTATION:
			return "the presentation is not in this scene"
		NEEDS_PRESENCE:
			return "there is no shared session"
	return "it cannot be done in this scene"


## Why a command that is only sometimes available is not available now. The same two states the bar
## greys out for, and the same words: a palette and a menu describing the same entry differently
## would be two answers to one question.
static func gated_words(state: StringName) -> String:
	match state:
		&"dirty":
			return "nothing has changed since it was saved"
		&"session_on":
			return "no session is open"
	return "it cannot be done just now"


## Run a menu entry through the method it names.
##
## The one door the bar and the palette both use, so a command cannot do one thing from its menu and
## another from the box that lists the same command. Returns whether anything ran, because an entry
## naming a method that is not here is a menu item that looks like it works.
func run_entry(entry: Dictionary) -> bool:
	var method := StringName(entry.get("method", &""))
	if method == &"" or not has_method(String(method)):
		return false
	_remember_command(String(entry.get("id", "")))
	call(String(method), entry)
	# Choosing a command can leave a Control holding the keyboard that the drawing keys belong to.
	# This is the same release the HUD does at startup.
	release_keyboard_focus(self)
	return true


## How many commands the palette offers first.
const RECENT_COMMANDS := 8

## The commands run most recently, newest first: what `Ctrl+P` and Enter repeats.
##
## Kept here rather than in the palette, which holds no list of its own - it is handed this order the
## same way it is handed the bar. Recorded at `run_entry`, which is the one door every menu line and
## every row of the palette goes through, so a command cannot be run without being remembered and there
## is no second place for the two to disagree.
var _recent_commands: Array[String] = []


func _remember_command(id: String) -> void:
	if id == "":
		return
	_recent_commands.erase(id)
	_recent_commands.push_front(id)
	if _recent_commands.size() > RECENT_COMMANDS:
		_recent_commands.resize(RECENT_COMMANDS)


## The commands run most recently, newest first.
func recent_commands() -> Array[String]:
	var out: Array[String] = []
	out.assign(_recent_commands)
	return out


## Show the palette, with the bar read again as it opens: a command that has appeared, gone or become
## possible since the last time is exactly what a box like this is for.
func open_command_palette() -> void:
	if _command_palette == null:
		return
	_command_palette.set_commands(command_rows())
	_command_palette.set_recents(recent_commands())
	_command_palette.open()


func close_command_palette() -> void:
	if _command_palette != null:
		_command_palette.close_palette()


func is_command_palette_open() -> bool:
	return _command_palette != null and _command_palette.visible


## The key's one act. A palette is a box you open and close, not one you can open twice.
func toggle_command_palette() -> void:
	if is_command_palette_open():
		close_command_palette()
	else:
		open_command_palette()


## Fill the palette without putting it on the screen, which is how the suite checks it with no window
## server behind it: the filling and the showing are kept apart for exactly this reason.
func _fill_command_palette() -> void:
	if _command_palette != null:
		_command_palette.set_commands(command_rows())
		_command_palette.set_recents(recent_commands())


## A command was chosen from the palette. Run through the bar's own door, and then let the bar catch
## up: a command that moved the drawing leaves the ticks and the lines that describe the drawing
## describing the drawing before it.
func _on_command_chosen(row: Dictionary) -> void:
	var entry: Dictionary = row.get("entry", { })
	if run_entry(entry):
		_refresh_menus()


func _menu_command_palette(_entry: Dictionary) -> void:
	open_command_palette()

# --- the site report ------------------------------------------------------------------


## The site-stats page: what the drawing covers, measured by layer.
##
## Built in code for the same reason the keys panel is: it is a view of the drawing, and a
## scene copy of it would be a fourth thing to keep in step. The body is refilled every time
## the page is opened, because the drawing it reports on changes under it.
func _build_site_report_panel() -> void:
	var root := get_node_or_null(^"Root")
	if root == null:
		return
	var wrapper := BoardPanelScript.new()
	wrapper.name = "SiteReportPanel"
	wrapper.set_anchors_preset(Control.PRESET_FULL_RECT)
	wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrapper.visible = false

	var panel := PanelContainer.new()
	panel.name = "Page"
	panel.custom_minimum_size = Vector2(620.0, 0.0)
	if top_bar != null:
		panel.add_theme_stylebox_override("panel", top_bar.get_theme_stylebox("panel"))
	var column := VBoxContainer.new()
	column.name = "Column"
	panel.add_child(column)

	var heading := Label.new()
	heading.name = "Heading"
	heading.text = "Site statistics"
	column.add_child(heading)

	var body := Label.new()
	body.name = "ReportText"
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(body)

	var close_button := Button.new()
	close_button.name = "CloseReport"
	close_button.text = "Close"
	close_button.pressed.connect(close_site_report)
	column.add_child(close_button)

	wrapper.add_child(panel)
	_site_report_panel = wrapper
	root.add_child(wrapper)


func is_site_report_open() -> bool:
	return _site_report_panel != null and _site_report_panel.visible


## What the page says. Read fresh each time, so it reports the drawing as it is now.
func site_report_text() -> String:
	if _draft == null:
		return "there is no drawing open"
	var report := SiteReportScript.of_plan(_draft.document, _planting_rows())
	return report.text()


func open_site_report() -> void:
	if _site_report_panel == null:
		return
	var body := _site_report_panel.get_node_or_null(^"Page/Column/ReportText")
	if body is Label:
		(body as Label).text = site_report_text()
	_site_report_panel.visible = true


func close_site_report() -> void:
	if _site_report_panel != null:
		_site_report_panel.visible = false

# --- importing a survey ---------------------------------------------------------------


## Built in code like the site-stats page, and for the same reason: it is a view of a file, and a
## scene copy of it would be a second place the wording lives. It is a `Control` rather than a
## `Window` because it opens *over* the drawing it is about, and because a page that does not take
## the keyboard cannot swallow the drawing's own keys.
func _build_survey_panel() -> void:
	var root := get_node_or_null(^"Root")
	if root == null:
		return
	var wrapper := BoardPanelScript.new()
	wrapper.name = "SurveyPanel"
	wrapper.set_anchors_preset(Control.PRESET_FULL_RECT)
	wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrapper.visible = false

	var panel := PanelContainer.new()
	panel.name = "Page"
	panel.custom_minimum_size = Vector2(640.0, 0.0)
	if top_bar != null:
		panel.add_theme_stylebox_override("panel", top_bar.get_theme_stylebox("panel"))
	var column := VBoxContainer.new()
	column.name = "Column"
	panel.add_child(column)

	var heading := Label.new()
	heading.name = "Heading"
	heading.text = "Import a survey"
	column.add_child(heading)

	var body := Label.new()
	body.name = "SurveyText"
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(body)

	var buttons := HBoxContainer.new()
	buttons.name = "Buttons"
	var import_button := Button.new()
	import_button.name = "ImportSurvey"
	import_button.text = "Put it on the drawing"
	import_button.pressed.connect(confirm_survey_import)
	buttons.add_child(import_button)
	var close_button := Button.new()
	close_button.name = "CloseSurvey"
	close_button.text = "Cancel"
	close_button.pressed.connect(close_survey_panel)
	buttons.add_child(close_button)
	column.add_child(buttons)

	wrapper.add_child(panel)
	_survey_panel = wrapper
	root.add_child(wrapper)


func is_survey_panel_open() -> bool:
	return _survey_panel != null and _survey_panel.visible


## What the page says: what was read, then every check the survey engine made, then the survey's
## own notes. A person accepts an import by reading this and nothing else.
func survey_report_text() -> String:
	if _pending_survey.is_empty():
		return "no survey has been read"
	var lines: Array[String] = []
	lines.append(SurveyFileScript.describe(_pending_survey))
	if not String(_pending_survey.get("source", "")).is_empty():
		lines.append(String(_pending_survey["source"]))
	lines.append("")
	for line: String in SurveyFileScript.report_lines(_pending_survey):
		lines.append(line)
	return "\n".join(PackedStringArray(lines))


## Whether the survey on the page may be put on the drawing. A survey that fails a check is
## shown, not hidden: refusing silently would leave somebody looking at a file they cannot read
## and a drawing that will not take it.
func survey_import_enabled() -> bool:
	return SurveyFileScript.is_sound(_pending_survey)


func open_survey_panel(parsed: Dictionary) -> void:
	if _survey_panel == null:
		return
	_pending_survey = parsed
	var body := _survey_panel.get_node_or_null(^"Page/Column/SurveyText")
	if body is Label:
		(body as Label).text = survey_report_text()
	var answer := _survey_panel.get_node_or_null(^"Page/Column/Buttons/ImportSurvey")
	if answer is Button:
		(answer as Button).disabled = not survey_import_enabled()
	_survey_panel.visible = true


func close_survey_panel() -> void:
	if _survey_panel != null:
		_survey_panel.visible = false
	_pending_survey = { }


## Put the survey that was read on the drawing. The page stays up until the drawing has taken it,
## so a refused import is answered by the same page that asked.
func confirm_survey_import() -> void:
	if _draft == null or _pending_survey.is_empty():
		return
	var taken: Dictionary = _draft.import_survey(_pending_survey)
	if bool(taken.get("ok", false)):
		close_survey_panel()

## The survey file chooser. It starts in the app's own surveys folder when there is one - the
## place a survey that was dropped in for this drawing lives - and anywhere on the disk otherwise,
## because a survey is a file somebody else sent.
# --- the DXF underlay -----------------------------------------------------------------


## The page a DXF is read onto: what is in the file, where each of its layers' geometry will land,
## and - when the file does not say - the question this reader refuses to guess at.
func _build_dxf_panel() -> void:
	var root := get_node_or_null(^"Root")
	if root == null:
		return
	var wrapper := BoardPanelScript.new()
	wrapper.name = "DxfPanel"
	wrapper.set_anchors_preset(Control.PRESET_FULL_RECT)
	wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrapper.visible = false

	var panel := PanelContainer.new()
	panel.name = "Page"
	panel.custom_minimum_size = Vector2(680.0, 0.0)
	if top_bar != null:
		panel.add_theme_stylebox_override("panel", top_bar.get_theme_stylebox("panel"))
	var column := VBoxContainer.new()
	column.name = "Column"
	panel.add_child(column)

	var heading := Label.new()
	heading.name = "Heading"
	heading.text = "Import a DXF"
	column.add_child(heading)

	var body := Label.new()
	body.name = "DxfText"
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(body)

	# The one question a DXF cannot be read without. A file that states its units never needs this,
	# so the row stays disabled and says why rather than hiding - a control that is there and cannot be
	# used is a control that explains itself.
	var units_row := HBoxContainer.new()
	units_row.name = "UnitsRow"
	var units_caption := Label.new()
	units_caption.text = "Units"
	units_row.add_child(units_caption)
	var units_choice := OptionButton.new()
	units_choice.name = "DxfUnits"
	# Not `name`: this is a CanvasLayer, and `name` is the node's own property.
	for unit_name: String in IMPORT_UNIT_CHOICES:
		units_choice.add_item(unit_name if not unit_name.is_empty() else "as the file says")
		units_choice.set_item_metadata(units_choice.item_count - 1, unit_name)
	units_choice.item_selected.connect(
		func(index: int) -> void:
			choose_dxf_units(String(units_choice.get_item_metadata(index))),
	)
	units_row.add_child(units_choice)
	column.add_child(units_row)

	var buttons := HBoxContainer.new()
	buttons.name = "Buttons"
	var import_button := Button.new()
	import_button.name = "ImportDxf"
	import_button.text = "Put it on the drawing"
	import_button.pressed.connect(confirm_dxf_import)
	buttons.add_child(import_button)
	var close_button := Button.new()
	close_button.name = "CloseDxf"
	close_button.text = "Cancel"
	close_button.pressed.connect(close_dxf_panel)
	buttons.add_child(close_button)
	column.add_child(buttons)

	wrapper.add_child(panel)
	_dxf_panel = wrapper
	root.add_child(wrapper)


func is_dxf_panel_open() -> bool:
	return _dxf_panel != null and _dxf_panel.visible


## What the page says: what is in the file, where its layers' geometry will go, and what the reader
## noticed. A person accepts an import by reading this and nothing else.
func dxf_report_text() -> String:
	var lines: Array[String] = []
	if not _dxf_name.is_empty():
		lines.append(_dxf_name)
	if _pending_dxf.is_empty():
		lines.append("no DXF has been read")
		return "\n".join(PackedStringArray(lines))
	for line: String in DxfFileScript.report_lines(_pending_dxf):
		lines.append(line)
	return "\n".join(PackedStringArray(lines))


## Whether what was read may go on the drawing. A refused file is *shown* rather than hidden, because
## the usual reason is the one question it can still answer.
func dxf_import_enabled() -> bool:
	return _draft != null and _draft.document != null and DxfFileScript.is_usable(_pending_dxf)


## Read the file in hand again, with the units a person chose. Called on open and whenever the choice
## changes: the answer is part of reading the file, not a second step after it.
func _read_pending_dxf() -> Dictionary:
	var options := { "underlay": true }
	if not _dxf_units.is_empty():
		options["units"] = _dxf_units
	var plan := DxfFileScript.read_text(_dxf_text, options)
	if bool(plan["ok"]):
		plan["source"] = _dxf_name
	return plan


func open_dxf_panel() -> void:
	_pending_dxf = _read_pending_dxf()
	if _dxf_panel == null:
		return
	var body := _dxf_panel.get_node_or_null(^"Page/Column/DxfText")
	if body is Label:
		(body as Label).text = dxf_report_text()
	# The units row is live only while the file's own answer is missing, which is the only time an
	# answer from a person is what the file needs.
	var choice := _dxf_panel.get_node_or_null(^"Page/Column/UnitsRow/DxfUnits")
	if choice is OptionButton:
		var option := choice as OptionButton
		var needed := int(_pending_dxf.get("insunits", 0)) == 0
		option.disabled = not needed
		option.tooltip_text = ("this file does not say what its units are"
			if needed
			else "the file states its own units")
	var answer := _dxf_panel.get_node_or_null(^"Page/Column/Buttons/ImportDxf")
	if answer is Button:
		(answer as Button).disabled = not dxf_import_enabled()
	_dxf_panel.visible = true


func close_dxf_panel() -> void:
	if _dxf_panel != null:
		_dxf_panel.visible = false
	_pending_dxf = { }
	_dxf_text = ""
	_dxf_name = ""
	_dxf_units = ""


## What the units drop-down does: answer the question, then read the file again with the answer.
##
## The drop-down is also told what was chosen, so the page cannot read the file with one answer while
## showing another - which is what it did the first time it was looked at. `select()` does not emit
## `item_selected`, so this cannot come back round.
func choose_dxf_units(units: String) -> void:
	_dxf_units = units
	var choice := (_dxf_panel.get_node_or_null(^"Page/Column/UnitsRow/DxfUnits") if _dxf_panel != null else null)
	if choice is OptionButton:
		var option := choice as OptionButton
		for index in option.item_count:
			if String(option.get_item_metadata(index)) == units:
				option.select(index)
				break
	open_dxf_panel()


## What the units drop-down is currently showing, for a run that wants to see that it agrees with what
## the file was read as.
func dxf_units_text() -> String:
	var choice := (_dxf_panel.get_node_or_null(^"Page/Column/UnitsRow/DxfUnits") if _dxf_panel != null else null)
	if choice is OptionButton:
		var option := choice as OptionButton
		if option.item_count > 0:
			return option.get_item_text(maxi(option.selected, 0))
	return ""


## Put what was read on the drawing. The page stays up until the drawing has taken it, so a refused
## import is answered by the same page that asked.
func confirm_dxf_import() -> void:
	if _draft == null or _pending_dxf.is_empty():
		return
	var taken: Dictionary = _draft.import_dxf(_pending_dxf)
	if bool(taken.get("ok", false)):
		close_dxf_panel()


## The DXF chooser. Anywhere on the disk, because a surveyor's file is a file somebody else sent.
func open_dxf_dialog() -> void:
	if _dxf_dialog != null:
		_dxf_dialog.popup_centered_ratio(0.7)


## A DXF was chosen: read it, then show what was read. The file is kept as text rather than read once,
## because a file that does not say its units has to be read again with the answer.
func _on_dxf_chosen(path: String) -> void:
	release_keyboard_focus(self)
	_dxf_units = ""
	_dxf_name = path.get_file()
	_dxf_text = ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file != null:
		_dxf_text = file.get_as_text()
		file.close()
	if _dxf_text.is_empty():
		open_dxf_panel()
		return
	open_dxf_panel()


func _menu_import_dxf(_entry: Dictionary) -> void:
	open_dxf_dialog()


## Writing the drawing out as a DXF, from the File menu.
##
## The menu only opens the door and the controller writes the file, so the reporting happens in one
## place: `last_message` is the status line a person reads and the sentence `Edit > What just
## happened...` keeps, and `DxfWriter.describe` already names anything the export had to leave out.
func _menu_save_dxf(_entry: Dictionary) -> void:
	if _dxf_export_dialog != null:
		_dxf_export_dialog.popup_centered_ratio(0.7)


## The file a person chose to write to.
##
## The extension is added rather than trusted to the dialog's filter, because a name typed as
## `garden-plan` is a DXF written to a file nothing on the machine will open, and the person who typed
## it has no way to tell that from one that worked.
func _on_dxf_export_chosen(path: String) -> void:
	if _draft == null:
		return
	var target: String = path if path.ends_with(".dxf") else path + ".dxf"
	_draft.export_dxf(target)
	release_keyboard_focus(self)


## Writing the yard out as a model, from the File menu.
##
## The menu only opens the door and the exporter writes the file. The reporting goes on the drawing's
## status line rather than onto a page of its own, because that is where every other thing this
## program says about what it has just done goes - a DXF, a plot, an import - and the yard is the
## drawing in three dimensions, so it is the same sentence in the same place. `last_message` is also
## what `Edit > What just happened...` keeps, so a model that went out is still findable afterwards.
func _menu_save_model(_entry: Dictionary) -> void:
	if _model_export_dialog != null:
		_model_export_dialog.popup_centered_ratio(0.7)


## The file a person chose to write to.
##
## The extension is added rather than trusted to the dialog's filter, and the one that is added is the
## **binary** one: a `.gltf` names its pictures instead of carrying them (see `YardExporter`), so a
## name typed with no extension gets the format that takes everything with it. A person who wants the
## text file says so by typing `.gltf`, which is a decision rather than a default.
func _on_model_export_chosen(path: String) -> void:
	var target: String = path
	if YardExporterScript.format_for(target).is_empty():
		target += "." + YardExporterScript.GLB
	var report: Dictionary = YardExporterScript.export_scene(self, target)
	if _draft != null:
		_draft.last_message = YardExporterScript.describe(report)
	release_keyboard_focus(self)

# --- the LandXML plat ------------------------------------------------------------------


## The page a LandXML plat is read onto: what is in the file, where each kind of feature's geometry
## will land, and - when the file does not say - the question this reader refuses to guess at.
##
## Built the way the DXF page is built, because it answers the same two questions - what did you read,
## and may it go on the drawing - and because a person who has imported one of these has imported the
## other.
func _build_landxml_panel() -> void:
	var root := get_node_or_null(^"Root")
	if root == null:
		return
	var wrapper := BoardPanelScript.new()
	wrapper.name = "LandXmlPanel"
	wrapper.set_anchors_preset(Control.PRESET_FULL_RECT)
	wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrapper.visible = false

	var panel := PanelContainer.new()
	panel.name = "Page"
	panel.custom_minimum_size = Vector2(680.0, 0.0)
	if top_bar != null:
		panel.add_theme_stylebox_override("panel", top_bar.get_theme_stylebox("panel"))
	var column := VBoxContainer.new()
	column.name = "Column"
	panel.add_child(column)

	var heading := Label.new()
	heading.name = "Heading"
	heading.text = "Import a LandXML plat"
	column.add_child(heading)

	var body := Label.new()
	body.name = "LandXmlText"
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(body)

	# The one question a plat cannot be read without, when it does not answer it itself.
	var units_row := HBoxContainer.new()
	units_row.name = "UnitsRow"
	var units_caption := Label.new()
	units_caption.text = "Units"
	units_row.add_child(units_caption)
	var units_choice := OptionButton.new()
	units_choice.name = "LandXmlUnits"
	# Not `name`: this is a CanvasLayer, and `name` is the node's own property.
	for unit_name: String in IMPORT_UNIT_CHOICES:
		units_choice.add_item(unit_name if not unit_name.is_empty() else "as the file says")
		units_choice.set_item_metadata(units_choice.item_count - 1, unit_name)
	units_choice.item_selected.connect(
		func(index: int) -> void:
			choose_landxml_units(String(units_choice.get_item_metadata(index))),
	)
	units_row.add_child(units_choice)
	column.add_child(units_row)

	var buttons := HBoxContainer.new()
	buttons.name = "Buttons"
	var import_button := Button.new()
	import_button.name = "ImportLandXml"
	import_button.text = "Put it on the drawing"
	import_button.pressed.connect(confirm_landxml_import)
	buttons.add_child(import_button)
	var close_button := Button.new()
	close_button.name = "CloseLandXml"
	close_button.text = "Cancel"
	close_button.pressed.connect(close_landxml_panel)
	buttons.add_child(close_button)
	column.add_child(buttons)

	wrapper.add_child(panel)
	_landxml_panel = wrapper
	root.add_child(wrapper)


func is_landxml_panel_open() -> bool:
	return _landxml_panel != null and _landxml_panel.visible


## What the page says: what is in the plat, where each kind of feature's geometry will go, and what
## the reader noticed. A person accepts an import by reading this and nothing else.
func landxml_report_text() -> String:
	var lines: Array[String] = []
	if not _landxml_name.is_empty():
		lines.append(_landxml_name)
	if _pending_landxml.is_empty():
		lines.append("no LandXML plat has been read")
		return "\n".join(PackedStringArray(lines))
	for line: String in LandXmlFileScript.report_lines(_pending_landxml):
		lines.append(line)
	return "\n".join(PackedStringArray(lines))


## Whether what was read may go on the drawing. A refused file is *shown* rather than hidden, because
## the usual reason is the one question it can still answer.
func landxml_import_enabled() -> bool:
	return (_draft != null and _draft.document != null and LandXmlFileScript.is_usable(_pending_landxml))


## Read the plat in hand again, with the units a person chose. Called on open and whenever the choice
## changes: the answer is part of reading the file, not a second step after it.
func _read_pending_landxml() -> Dictionary:
	var options := { "underlay": true }
	if not _landxml_units.is_empty():
		options["units"] = _landxml_units
	var plan := LandXmlFileScript.read_text(_landxml_text, options)
	if bool(plan["ok"]):
		plan["source"] = _landxml_name
	return plan


func open_landxml_panel() -> void:
	_pending_landxml = _read_pending_landxml()
	if _landxml_panel == null:
		return
	var body := _landxml_panel.get_node_or_null(^"Page/Column/LandXmlText")
	if body is Label:
		(body as Label).text = landxml_report_text()
	# The units row is live only while the file's own answer is missing. A plat that names its linear
	# unit is not asked about, for the reason the DXF page gives: answering for a file that already
	# answered is how a drawing gets halved by accident.
	var choice := _landxml_panel.get_node_or_null(^"Page/Column/UnitsRow/LandXmlUnits")
	if choice is OptionButton:
		var option := choice as OptionButton
		var needed := String(_pending_landxml.get("declared_unit", "")).is_empty()
		option.disabled = not needed
		option.tooltip_text = ("this plat does not say what its units are"
			if needed
			else "the file states its own units")
	var answer := _landxml_panel.get_node_or_null(^"Page/Column/Buttons/ImportLandXml")
	if answer is Button:
		(answer as Button).disabled = not landxml_import_enabled()
	_landxml_panel.visible = true


func close_landxml_panel() -> void:
	if _landxml_panel != null:
		_landxml_panel.visible = false
	_pending_landxml = { }
	_landxml_text = ""
	_landxml_name = ""
	_landxml_units = ""


## What the units drop-down does: answer the question, then read the file again with the answer. The
## drop-down is also told what was chosen, so the page cannot read the file with one answer while
## showing another - `select()` does not emit `item_selected`, so this cannot come back round.
func choose_landxml_units(units: String) -> void:
	_landxml_units = units
	if _landxml_panel != null:
		var choice := _landxml_panel.get_node_or_null(^"Page/Column/UnitsRow/LandXmlUnits")
		if choice is OptionButton:
			var option := choice as OptionButton
			for index in option.item_count:
				if String(option.get_item_metadata(index)) == units:
					option.select(index)
					break
	open_landxml_panel()


## What the units drop-down is currently showing, for a run that wants to see that it agrees with what
## the file was read as.
func landxml_units_text() -> String:
	if _landxml_panel != null:
		var choice := _landxml_panel.get_node_or_null(^"Page/Column/UnitsRow/LandXmlUnits")
		if choice is OptionButton:
			var option := choice as OptionButton
			if option.item_count > 0:
				return option.get_item_text(maxi(option.selected, 0))
	return ""


## Put what was read on the drawing. The page stays up until the drawing has taken it, so a refused
## import is answered by the same page that asked.
func confirm_landxml_import() -> void:
	if _draft == null or _pending_landxml.is_empty():
		return
	var taken: Dictionary = _draft.import_landxml(_pending_landxml)
	if bool(taken.get("ok", false)):
		close_landxml_panel()


## The plat chooser. Anywhere on the disk, because a plat is a file somebody else's software wrote.
func open_landxml_dialog() -> void:
	if _landxml_dialog != null:
		_landxml_dialog.popup_centered_ratio(0.7)


## A plat was chosen: read it, then show what was read. The file is kept as text rather than read once,
## because a file that does not say its units has to be read again with the answer.
func _on_landxml_chosen(path: String) -> void:
	release_keyboard_focus(self)
	_landxml_units = ""
	_landxml_name = path.get_file()
	_landxml_text = ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file != null:
		_landxml_text = file.get_as_text()
		file.close()
	open_landxml_panel()


func _menu_import_landxml(_entry: Dictionary) -> void:
	open_landxml_dialog()

# --- the site map from OpenStreetMap -------------------------------------------------


## Build the map window and wire every one of its intents. The window draws nothing, reads nothing and
## asks nothing of the network: it announces what a person did and this is the place that answers, so
## the coordinates a fetch was made with and the coordinates a report was read at cannot disagree.
func _build_osm_window() -> void:
	if _osm_window != null:
		return
	_osm_window = OsmWindowScript.new()
	_osm_window.name = "OsmWindow"
	_osm_window.fetch_requested.connect(_on_osm_fetch)
	_osm_window.open_file_requested.connect(open_osm_map_dialog)
	_osm_window.import_requested.connect(confirm_osm_import)
	_osm_window.closed.connect(close_osm_window)
	add_child(_osm_window)
	_osm_window.build()
	# The one node in this HUD that reaches the network, kept beside the window it serves.
	_osm_fetch = OsmFetchScript.new()
	_osm_fetch.name = "OsmFetch"
	add_child(_osm_fetch)
	# Not shown until it is asked for, the same as every other page in this HUD: a map window that
	# appeared the moment the program started would be the drawing buried under a form nobody opened.
	_osm_window.hide()


## Open the map window on the drawing's own site. A site is already a fact about the drawing - the sun
## study reads the same two numbers - so the common case is a person opening this and pressing Fetch.
func open_osm_window() -> void:
	_build_osm_window()
	if _osm_window == null:
		return
	_fill_osm_window()
	PageChromeScript.show_centred(_osm_window)


## Point the window at the drawing's own site and show whatever is in hand. Kept apart from showing
## the window itself so the filling can be driven without a window server, which is how the suite
## checks it - `popup_centered` needs a screen and a test does not have one.
func _fill_osm_window() -> void:
	if _osm_window == null:
		return
	if _draft != null and _draft.document != null:
		_osm_window.show_site(_draft.document.site_latitude, _draft.document.site_longitude)
	_osm_window.show_report(osm_report_text())
	_osm_window.set_import_enabled(osm_import_enabled())
	_osm_window.say("")


## Close it and forget the map in hand, the same way the DXF page does: a page that has been closed
## and reopened says "no map has been read" rather than showing one that is no longer on screen.
func close_osm_window() -> void:
	if _osm_window != null and _osm_window.visible:
		_osm_window.hide()
	_pending_osm = { }


func is_osm_window_open() -> bool:
	return _osm_window != null and _osm_window.visible


## The place the form is showing, or the drawing's own site when there is no window - so a saved map
## read from a file dialog is read at the same centre as one fetched from the network.
func _osm_centre() -> Dictionary:
	if _osm_window != null:
		return _osm_window.centre()
	if _draft != null and _draft.document != null:
		return _draft.document.site()
	return { }


func _osm_radius() -> float:
	if _osm_window != null:
		return _osm_window.radius_m()
	return OsmFetchScript.DEFAULT_RADIUS_M


## What the window says: the file it came from, if any, and everything the reader noticed.
func osm_report_text() -> String:
	if _pending_osm.is_empty():
		return "no map has been read"
	var lines: Array[String] = []
	if not String(_pending_osm.get("source", "")).is_empty():
		lines.append(String(_pending_osm["source"]))
	for line: String in OsmFileScript.report_lines(_pending_osm):
		lines.append(line)
	return "\n".join(PackedStringArray(lines))


## Whether what was read may go on the drawing. A refused map is *shown* rather than hidden, because
## the usual reason is one a person can fix: a coordinate that is not a place, or a name that is not a
## file.
func osm_import_enabled() -> bool:
	return _draft != null and _draft.document != null and OsmFileScript.is_usable(_pending_osm)


## Ask OpenStreetMap for the map around the site the form shows, and read what it answers.
##
## Awaited, because a network answer is not a thing a frame can wait for: the status line says what is
## happening, and the report replaces it when it arrives.
func _on_osm_fetch(centre: Dictionary, radius_m: float) -> void:
	_build_osm_window()
	if _osm_fetch == null:
		return
	if _osm_window != null:
		_osm_window.say("asking OpenStreetMap...")
	var plan: Dictionary = await _osm_fetch.fetch(centre, radius_m)
	_pending_osm = plan
	if _osm_window == null:
		return
	_osm_window.show_report(osm_report_text())
	_osm_window.set_import_enabled(osm_import_enabled())
	_osm_window.say(("the map was not read"
			if not bool(plan.get("ok", false))
			else OsmFileScript.describe(plan)))


## The chooser for a map already saved on disk. Anywhere on the disk, because it is a file somebody
## exported rather than one this program wrote where it can follow it.
func open_osm_map_dialog() -> void:
	if _osm_dialog != null:
		_osm_dialog.popup_centered_ratio(0.7)


## A saved map was chosen: read it at the centre and the radius the window is showing, then show what
## was read. Nothing reaches the drawing until the report has been shown.
func _on_osm_chosen(path: String) -> void:
	release_keyboard_focus(self)
	_pending_osm = OsmFetchScript.read_saved(path, _osm_centre(), _osm_radius())
	if _osm_window == null:
		return
	_osm_window.show_report(osm_report_text())
	_osm_window.set_import_enabled(osm_import_enabled())
	_osm_window.say(
		("the map was not read"
			if not bool(_pending_osm.get("ok", false))
			else OsmFileScript.describe(_pending_osm))
	)


## Put what was read on the drawing. The window stays up until the drawing has taken it, so a refused
## import is answered by the same page that asked.
func confirm_osm_import() -> void:
	if _draft == null or _pending_osm.is_empty():
		return
	var taken: Dictionary = _draft.import_osm(_pending_osm)
	if bool(taken.get("ok", false)):
		close_osm_window()


func _menu_import_osm(_entry: Dictionary) -> void:
	open_osm_window()

# --- a picture under the drawing -------------------------------------------------------


## Build the page and wire every one of its intents. The page draws nothing, reads nothing and copies
## nothing: it announces what a person did, and this is the place that answers with the module that
## reads the file and the controller that owns the drawing - the arrangement the map window has, and
## for the same reason.
func _build_underlay_window() -> void:
	if _underlay_window != null:
		return
	_underlay_window = UnderlayWindowScript.new()
	_underlay_window.name = "UnderlayWindow"
	_underlay_window.choose_file_requested.connect(open_underlay_dialog)
	_underlay_window.place_requested.connect(place_the_picture)
	_underlay_window.apply_requested.connect(apply_to_the_picture)
	_underlay_window.remove_requested.connect(take_the_picture_off)
	_underlay_window.closed.connect(close_underlay_window)
	add_child(_underlay_window)
	_underlay_window.build()
	# Not shown until it is asked for, like every other page here: a form nobody opened must not be
	# sitting over the drawing.
	_underlay_window.hide()


func open_underlay_window() -> void:
	_build_underlay_window()
	if _underlay_window == null:
		return
	_fill_underlay_window()
	PageChromeScript.show_centred(_underlay_window)


## Close it and forget the picture in hand, the way the DXF page and the map window do: a page that has
## been closed and opened again says "no picture chosen" rather than offering the one it was showing.
func close_underlay_window() -> void:
	if _underlay_window != null and _underlay_window.visible:
		_underlay_window.hide()
	_pending_picture = { }
	_picture_refusal = ""


func is_underlay_window_open() -> bool:
	return _underlay_window != null and _underlay_window.visible


## Point the page at the drawing in hand: its units, the size a picture should start at, and everything
## already underneath it.
##
## Kept apart from *showing* the page so the filling can be driven without a window server, which is how
## the suite checks it - `popup_centered` needs a screen and a test does not have one.
func _fill_underlay_window() -> void:
	_build_underlay_window()
	if _underlay_window == null:
		return
	_underlay_window.set_units(_drawing_units())
	_underlay_window.set_suggested_width(_picture_suggested_width())
	_refresh_underlay_window()


## Put what is in hand on the page, without showing the page.
func _refresh_underlay_window() -> void:
	if _underlay_window == null:
		return
	_underlay_window.show_file(_picture_words())
	_underlay_window.show_report(_picture_report_text())
	_underlay_window.show_underlays(_picture_rows())
	if not _pending_picture.is_empty():
		# The width comes *after* the list, because a picture already chosen in the list would
		# otherwise put its own width in the field - and a newly read file is what is being placed.
		_underlay_window.set_suggested_width(float(_pending_picture.get("width_m", 0.0)))
	_underlay_window.say("")


## The drawing's own units, or the metre default when there is no drawing: a page with no document
## behind it must still be able to say what it is measuring in.
func _drawing_units() -> UnitsScript:
	if _draft != null and _draft.document != null:
		return _draft.document.units
	return UnitsScript.new()


## How far across the ground a picture should start at: the drawing's own extent, so the common case -
## a scan of this site and a design drawn on it - lands at about the size it already is. A drawing with
## nothing on it yet gets a plain width, because tracing a scan onto an empty sheet is exactly what
## somebody does on the first day.
func _picture_suggested_width() -> float:
	if _draft != null and _draft.document != null:
		var box: Rect2 = _draft.document.bounds()
		if box.size != Vector2.ZERO:
			return maxf(box.size.x, box.size.y)
	return RasterUnderlayScript.SUGGESTED_WIDTH


## What to call the picture in hand on the page, or "" when none has been read - which is also how the
## page is told to switch its button off.
func _picture_words() -> String:
	if _pending_picture.is_empty():
		return ""
	return String(_pending_picture.get("name", "picture"))


## What the page says about the picture in hand: why the file was refused, or what was read and where
## the copy is. A refused file is *shown* with its reason rather than hidden, because the usual cause
## is one a person can fix - a text file picked by mistake, or a photograph that is not one.
func _picture_report_text() -> String:
	if not _picture_refusal.is_empty():
		return _picture_refusal
	if _pending_picture.is_empty():
		return "no picture has been read"
	var lines: Array[String] = []
	for line: String in RasterUnderlayScript.report_lines(_pending_picture):
		lines.append(line)
	return "\n".join(PackedStringArray(lines))


## The pictures already under the drawing, as the list on the page shows them.
func _picture_rows() -> Array[Dictionary]:
	if _draft == null:
		var none: Array[Dictionary] = []
		return none
	return _draft.underlay_rows()


## The chooser for the picture itself. Anywhere on the disk, because a scan is a file somebody sent
## rather than one this program wrote where it can follow it - the same reason the survey chooser reads
## the whole filesystem.
func open_underlay_dialog() -> void:
	if _underlay_dialog != null:
		_underlay_dialog.popup_centered_ratio(0.7)


## A picture was chosen: read its header, keep a copy beside the drawing, then show what was read.
## Nothing reaches the drawing until the page's own button is pressed, and **nothing is copied at all**
## unless the file really is a picture - so a folder of tracing aids cannot collect files this app
## cannot draw.
func _on_underlay_chosen(path: String) -> void:
	release_keyboard_focus(self)
	_build_underlay_window()
	if _underlay_window == null:
		return
	var kept: Dictionary = RasterUnderlayScript.keep(path)
	if not bool(kept.get("ok", false)):
		_pending_picture = { }
		_picture_refusal = String(kept.get("reason", "the picture could not be read"))
		_refresh_underlay_window()
		return
	_picture_refusal = ""
	_pending_picture = RasterUnderlayScript.from_kept(kept, _picture_suggested_width())
	if _pending_picture.is_empty():
		_picture_refusal = "the picture could not be measured, so it cannot be laid at a size"
	_refresh_underlay_window()
	_underlay_window.say(
		(
			"the picture was not read"
			if not _picture_refusal.is_empty()
			else RasterUnderlayScript.describe(_pending_picture, _drawing_units())
		)
	)


## Put what was read under the drawing, with the numbers the page is showing. The page stays up while
## the drawing takes it, so a refusal is answered by the page that asked.
func place_the_picture() -> void:
	if _draft == null or _underlay_window == null or _pending_picture.is_empty():
		return
	var taken: Dictionary = _draft.take_on_picture(
		_pending_picture,
		{
			"width_m": _underlay_window.width_m(),
			"rotation_deg": _underlay_window.rotation_deg(),
			"opacity": _underlay_window.opacity(),
		},
	)
	if not bool(taken.get("ok", false)):
		_underlay_window.say(String(taken.get("reason", "the picture could not be taken on")))
		return
	_pending_picture = { }
	_underlay_window.set_suggested_width(_picture_suggested_width())
	_refresh_underlay_window()
	_underlay_window.say(_draft.last_message)


## Put the numbers the page is showing on a picture that is already under the drawing.
func apply_to_the_picture() -> void:
	if _draft == null or _underlay_window == null:
		return
	var id := _underlay_window.chosen_id()
	if id == 0:
		return
	var changed: Dictionary = _draft.change_underlay(
		id,
		{
			"width_m": _underlay_window.width_m(),
			"rotation_deg": _underlay_window.rotation_deg(),
			"opacity": _underlay_window.opacity(),
		},
	)
	if not bool(changed.get("ok", false)):
		_underlay_window.say(String(changed.get("reason", "the picture could not be changed")))
		return
	_refresh_underlay_window()
	_underlay_window.say(
		(_draft.last_message
			if bool(changed.get("changed", false))
			else "the picture already lies like that")
	)


## Take the chosen picture out from under the drawing.
func take_the_picture_off() -> void:
	if _draft == null or _underlay_window == null:
		return
	var id := _underlay_window.chosen_id()
	if id == 0:
		return
	if not _draft.remove_underlay(id):
		_underlay_window.say("there is no picture %d under this drawing" % id)
		return
	_refresh_underlay_window()
	_underlay_window.say(_draft.last_message)


func _menu_import_picture(_entry: Dictionary) -> void:
	open_underlay_window()

# --- the ground's own heights ----------------------------------------------------------
#
# The page, and nothing else: the levels, the contours and the arrows are the controller's, the
# arithmetic is the module's, and this is the place that joins a person's press to both. It draws
# nothing and works nothing out, for the reason the picture page does not read a file.
#
# The level and the fall are in hand on the *controller* rather than on the page, because a number in
# hand has to survive the page stepping out of the way so a tool can be used.


## Build the page and wire every one of its intents.
func _build_grading_window() -> void:
	if _grading_window != null:
		return
	_grading_window = GradingWindowScript.new()
	_grading_window.name = "GradingWindow"
	_grading_window.level_requested.connect(state_grading_level)
	_grading_window.fall_requested.connect(state_grading_fall)
	_grading_window.tool_requested.connect(arm_grading_tool)
	_grading_window.change_requested.connect(change_grading_level)
	_grading_window.remove_requested.connect(remove_grading_record)
	_grading_window.closed.connect(close_grading_window)
	add_child(_grading_window)
	_grading_window.build()
	_grading_window.hide()


func open_grading_window() -> void:
	_build_grading_window()
	if _grading_window == null:
		return
	_fill_grading_window()
	PageChromeScript.show_centred(_grading_window)
	# A window holds the keyboard while it is up, which is what a field to type into needs; the moment
	# it closes the drawing keys belong to the drawing again.
	release_keyboard_focus(self)


## Close it. The level and the fall in hand stay: they belong to the controller, so a page that has
## been closed and opened again still has the level the designer put in it.
func close_grading_window() -> void:
	if _grading_window != null and _grading_window.visible:
		_grading_window.hide()


func is_grading_window_open() -> bool:
	return _grading_window != null and _grading_window.visible


## Point the page at the drawing in hand: the two numbers in hand, the records, and the check. Kept
## apart from *showing* the page so the filling can be driven without a window server, which is how the
## suite checks it - `popup_centered` needs a screen and a test does not have one.
func _fill_grading_window() -> void:
	_build_grading_window()
	if _grading_window == null:
		return
	if _draft != null:
		_grading_window.set_level(_draft.grading_level)
		_grading_window.set_fall(_draft.grading_fall_percent)
	_grading_window.say("")
	_grading_state = ""
	_refresh_grading_window()


## Put what the drawing holds on the page, without touching the two fields: the fields are what a person
## is *typing*, and a refresh that overwrote them mid-word would be the page arguing with the hand.
func _refresh_grading_window() -> void:
	if _grading_window == null or _draft == null:
		return
	var state := "%d|%d" % [_draft.document.gesture_serial(), hash(_draft.document.grading)]
	if state == _grading_state:
		return
	_grading_state = state
	_grading_window.show_records(_grading_rows())
	_grading_window.set_report(_draft.grading_report())


## The page while it is up: the drawing can change behind it - an undo most of all, which does not come
## past this HUD - so it is read again whenever the drawing's grading has moved.
func _tick_grading_window() -> void:
	if _grading_window == null or not _grading_window.visible:
		return
	_refresh_grading_window()


## The records the page lists, or none in a scene with no drawing.
func _grading_rows() -> Array[Dictionary]:
	if _draft == null:
		var none: Array[Dictionary] = []
		return none
	return _draft.grading_rows()

# --- what the page's own controls asked for ---------------------------------------------


func state_grading_level(level: float) -> void:
	if _draft == null or _grading_window == null:
		return
	_draft.set_grading_level(level)
	_grading_window.say(_draft.last_message)


func state_grading_fall(percent: float) -> void:
	if _draft == null or _grading_window == null:
		return
	_draft.set_grading_fall(percent)
	_grading_window.say(_draft.last_message)


## A tool was asked for: the page steps out of the way and the tool is armed with the level or the fall
## in hand. The number is already the controller's by then, so nothing is lost by the page going away -
## and a window left standing over the plan would be a page between the person and the thing they are
## drawing on.
func arm_grading_tool(kind: String) -> void:
	if _grading_window == null:
		return
	# A scene with no drawing still gets an answer rather than silence: a button that cannot do anything
	# explains itself, here as much as anywhere else.
	var armed: Dictionary = { "ok": false, "reason": "there is no drawing to grade" }
	if _draft != null:
		armed = _draft.begin_grading(kind)
	if not bool(armed.get("ok", false)):
		_grading_window.say(String(armed.get("reason", "that tool could not be armed")))
		return
	close_grading_window()
	_refresh_menus()


func change_grading_level(kind: String, id: int, level: float) -> void:
	if _draft == null or _grading_window == null:
		return
	var changed: Dictionary = _draft.set_grading_level_of(kind, id, level)
	_grading_window.say(_draft.last_message)
	if not bool(changed.get("ok", false)):
		_grading_window.say(String(changed.get("reason", _draft.last_message)))
	_grading_state = ""
	_refresh_grading_window()
	_refresh_menus()


func remove_grading_record(kind: String, id: int) -> void:
	if _draft == null or _grading_window == null:
		return
	var removed: Dictionary = _draft.remove_grading(kind, id)
	if not bool(removed.get("ok", false)):
		_grading_window.say(String(removed.get("reason", "that record could not be taken off")))
		return
	_grading_window.say(_draft.last_message)
	_grading_state = ""
	_refresh_grading_window()
	_refresh_menus()


func _menu_grading_window(_entry: Dictionary) -> void:
	open_grading_window()


## The three ground tools, each on its own key as well as on its own button.
##
## They go through `arm_grading_tool`, which is what the page's buttons go through too, so the key and
## the button cannot end up doing different things - and arming a tool closes the page, the same way it
## does when the button is pressed.
func _menu_grade_spot(_entry: Dictionary) -> void:
	arm_grading_tool(GradingScript.SPOT)


func _menu_grade_contour(_entry: Dictionary) -> void:
	arm_grading_tool(GradingScript.CONTOUR)


func _menu_grade_slope(_entry: Dictionary) -> void:
	arm_grading_tool(GradingScript.SLOPE)


## Report on the drawing's own heights: whether the levels, the contours and the arrows agree with each
## other. The answer arrives on the page it belongs to, the way the planting's check arrives in the
## library - a report nobody can see is not a report.
func _menu_check_grading(_entry: Dictionary) -> void:
	if _draft == null or _draft.document == null:
		return
	var findings: Array = _draft.grading_report().get("findings", [])
	open_grading_window()
	if findings.is_empty():
		_grading_window.say("the grading agrees with itself")
		return
	_grading_window.say("%d the check disagrees with: %s" % [findings.size(), String(findings[0])])


func open_survey_dialog() -> void:
	if _survey_dialog == null:
		return
	var home := "user://surveys"
	if DirAccess.dir_exists_absolute(home):
		_survey_dialog.current_dir = ProjectSettings.globalize_path(home)
	_survey_dialog.popup_centered_ratio(0.7)


## A survey file was chosen: read it, then show what was read. Nothing reaches the drawing until
## the report has been shown and accepted (docs/drafting-subsystem-spec.md REQ 6.2.1).
##
## The file is read in the drawing's own units, because the checks word the parcel's area as they are
## made and a report is a thing about *this* sheet: reading a plat of six thousand square feet onto an
## imperial drawing and being told about 557.42 m2 is a sentence about a drawing nobody is looking at.
func _on_survey_chosen(path: String) -> void:
	release_keyboard_focus(self)
	var parsed := SurveyFileScript.of_file(path, _survey_read_options())
	if not bool(parsed.get("ok", false)):
		if _draft != null:
			_draft.note(String(parsed.get("reason", "the survey could not be read")))
		return
	open_survey_panel(parsed)


## The units a survey's report is worded in: the drawing's own. A survey read with no drawing to hang
## it on - which the File menu does not offer, since importing one needs a drawing - is read in metres
## by the reader's own default.
func _survey_read_options() -> Dictionary:
	if _draft == null or _draft.document == null:
		return { }
	return { "display_units": _draft.document.units }


## Show the line of hints or not, remembering that a presentation and the painted sheet take them away
## as well. Called every frame, so the one flag plus the two modes is the whole rule.
func _apply_hints_visibility() -> void:
	if hints != null:
		var painted: bool = painted_sheet != null and painted_sheet.visible
		hints.visible = _show_hints and not _presenting and not painted

# --- the sun and the shadows --------------------------------------------------------------
#
# The presentation panel states the site and aims the sun at one moment: it is a *view* control, and
# what it is aiming is a viewing fact. This is the study of that sun - a list of moments, and what the
# height in hand casts at each - which is a question a client asks ("will it be in shade by four",
# "will it be in shade in June") rather than a camera position.
#
# The arithmetic is `SunReport`'s and the page is `SunWindow`'s. What is left here is the three joins:
# the site the page is pointed at, the sun it aims, and the stills it renders.


## Build the page and wire every one of its intents.
func _build_sun_window() -> void:
	if _sun_window != null:
		return
	_sun_window = SunWindowScript.new()
	_sun_window.name = "SunWindow"
	_sun_window.apply_requested.connect(apply_sun_moment)
	_sun_window.render_requested.connect(render_sun_study)
	_sun_window.closed.connect(_on_sun_window_closed)
	add_child(_sun_window)
	_sun_window.build()
	_sun_window.hide()


func open_sun_window() -> void:
	_build_sun_window()
	if _sun_window == null:
		return
	_fill_sun_window()
	PageChromeScript.show_centred(_sun_window)
	# A page with a height to type into holds the keyboard while it is up, the way the grading page
	# does; the drawing keys belong to the drawing again the moment it closes.
	release_keyboard_focus(self)


func close_sun_window() -> void:
	if _sun_window != null and _sun_window.visible:
		_sun_window.hide()


func is_sun_window_open() -> bool:
	return _sun_window != null and _sun_window.visible


## Point the page at the presentation's own site and the drawing's own units, and give it a study to
## start from when it has none. Kept apart from *showing* the page so the filling can be driven with no
## window server, which is how the suite checks it.
##
## The study is only seeded when there is none: a page that had been closed with a study in hand and
## opened again should come back to that study rather than to a June day.
func _fill_sun_window() -> void:
	_build_sun_window()
	if _sun_window == null:
		return
	_sun_window.set_units(_drawing_units())
	_sun_window.bind(_sun_site())
	_sun_state = ""
	_refresh_sun_window()
	if _sun_window.moment_count() == 0:
		_sun_window.use_preset(&"june_day")
	_sun_window.say(_sun_window.opening_words())
	_refresh_menus()


## The site the study is of: the presentation's own fields, which are the ones the panel edits and the
## ones the drawing keeps. With no presentation in the scene there is no site, and the page says so
## rather than studying a latitude nobody stated.
func _sun_site() -> Dictionary:
	if presentation == null:
		return { }
	return presentation.current_site()


## The page while it is up: the site can move behind it - somebody editing the panel's fields, or a
## drawing loaded with another site in it - so it is read again whenever the site has moved. The
## *study* is not read again: it is the page's own, and rebinding it would throw away what a person is
## in the middle of building.
func _tick_sun_window() -> void:
	if _sun_window == null or not _sun_window.visible:
		return
	var state := str(_sun_site())
	if state == _sun_state:
		return
	_sun_state = state
	_sun_window.bind(_sun_site())
	_refresh_menus()


func _refresh_sun_window() -> void:
	if _sun_window == null:
		return
	_sun_state = str(_sun_site())


## Aim the presentation's sun at one moment of the study, and say on the page what came of it.
##
## The presentation says whether it could rather than this: a moment whose sun is below the horizon, or
## whose sun is on it, is refused there by name rather than clamped to something. Returns false the same
## way, for a caller with no page to read.
func apply_sun_moment(moment: Dictionary) -> bool:
	if presentation == null:
		if _sun_window != null:
			_sun_window.say("there is no presentation to aim")
		return false
	var aimed: bool = presentation.apply_sun(_sun_site(), moment)
	if _sun_window != null:
		if aimed:
			_sun_window.say("the sun is at %s" % SunReportScript.moment_words(moment))
		else:
			_sun_window.say("the sun was not moved at %s" % SunReportScript.moment_words(moment))
	_refresh_menus()
	return aimed


## Render one still per moment of the study, named for the moment each shows.
##
## One at a time and signal-driven: a rendering walk that awaited a loop would block the frame it was
## pressed in, and the director already answers by signal. The sun is aimed before each shot, because
## a still of the garden is a still of the garden *at that moment*.
##
## Returns what it is going to do, so a caller - or a test - can see the plan without a renderer.
func render_sun_study(moments: Array) -> Dictionary:
	if presentation == null:
		return _refuse_sun_render("there is no presentation to render from")
	if moments.is_empty():
		return _refuse_sun_render("no moment of this study has the sun up, so there is nothing to render")
	_sun_render_moments = moments.duplicate()
	_sun_render_names = SunReportScript.still_names(moments)
	_sun_render_index = 0
	_sun_render_written = 0
	_sun_render_refused = 0
	_sun_render_waiting = false
	_render_next_sun_still()
	return { "ok": true, "reason": "", "names": _sun_render_names }


func _refuse_sun_render(reason: String) -> Dictionary:
	if _sun_window != null:
		_sun_window.say(reason)
	var none: Array[String] = []
	return { "ok": false, "reason": reason, "names": none }


## The next still of the walk, or the end of it. A moment whose sun cannot be aimed - which the page's
## own `renderable_moments` should already have kept out - is counted as refused rather than rendered,
## so the end of the walk can say how many of the study's moments it managed.
func _render_next_sun_still() -> void:
	if presentation == null or _sun_render_index >= _sun_render_moments.size():
		_finish_sun_render()
		return
	var moment: Dictionary = _sun_render_moments[_sun_render_index]
	if not presentation.apply_sun(_sun_site(), moment):
		_sun_render_refused += 1
		_sun_render_index += 1
		_render_next_sun_still()
		return
	_sun_render_waiting = true
	presentation.render_still(selected_still_size(), _sun_render_names[_sun_render_index])


## Whether a still that has just landed is one of this study's: it is, when the walk is waiting and the
## file is the one the moment in hand was to be called. A still the panel's own button asked for while a
## study was being rendered is therefore left alone rather than counted.
func _sun_still_is_ours(path: String) -> bool:
	if not _sun_render_waiting:
		return false
	if _sun_render_index >= _sun_render_names.size():
		return false
	return path.contains(_sun_render_names[_sun_render_index])


func _sun_still_landed(rendered: bool) -> void:
	_sun_render_waiting = false
	if rendered:
		_sun_render_written += 1
	else:
		_sun_render_refused += 1
	_sun_render_index += 1
	_render_next_sun_still()


func _finish_sun_render() -> void:
	_sun_render_waiting = false
	if _sun_window == null:
		return
	if _sun_render_written == 0 and _sun_render_refused == 0:
		return
	var words := "%d still%s written" % [_sun_render_written, "" if _sun_render_written == 1 else "s"]
	if _sun_render_refused > 0:
		words += ", %d moment%s could not be rendered" \
				% [_sun_render_refused, "" if _sun_render_refused == 1 else "s"]
	_sun_window.say(words)


## What the Present menu's own line says about the sun: the site it is of, and how big the study in
## hand is. The count of what has the sun up is on the line because a study of six June hours is a
## different study from one of six December ones, and the two read the same until they are rendered.
func _sun_text() -> String:
	if presentation == null:
		return "there is no presentation to study the sun from"
	var site: String = presentation.site_text()
	var count: int = _sun_window.moment_count() if _sun_window != null else 0
	if count == 0:
		return "%s: no moments chosen yet" % site
	var up: int = _sun_window.renderable_moments().size()
	return "%s: %d moment%s, %d with the sun up" \
			% [site, count, "" if count == 1 else "s", up]


func _refresh_present_menu() -> void:
	var info := _find_item(&"present.sun_info")
	if not info.is_empty():
		var popup: PopupMenu = info[0]
		popup.set_item_text(int(info[1]), _sun_text())


## The presentation panel's own doors, and the menu row that uses them. Public because a test presses
## what the menu row presses, the same way `open_keys` and `close_keys` are.
func is_presentation_panel_wanted() -> bool:
	return _presentation_panel_wanted


func set_presentation_panel_wanted(wanted: bool) -> void:
	_presentation_panel_wanted = wanted
	_refresh_presentation_panel()


## Whether the panel belongs on the screen: a scene with a director has one, unless the person has put
## it away or the painted sheet is covering everything. The one place that decides, so the frame's
## refresh and the menu row cannot come to disagree about it.
func _refresh_presentation_panel() -> void:
	if presentation_panel == null:
		return
	presentation_panel.visible = presentation != null and _presentation_panel_wanted \
			and not (painted_sheet != null and painted_sheet.visible)


func _menu_presentation_panel(_entry: Dictionary) -> void:
	set_presentation_panel_wanted(not _presentation_panel_wanted)


## What the panel's own door starts as on the device this HUD was answered as: put away on a phone, and
## exactly as the scene drew it on a computer.
##
## A **start**, never a settlement. A person who brings the panel back on a phone keeps it back, which is
## why this runs where the chrome is first sized and refuses to run a second time: the pass that sizes the
## chrome can be asked again, and a pass that put the panel away every time would take it out of the hands
## of whoever had just opened it.
##
## The device is taken as an argument for the reason `PhoneHud.apply_if` takes it - so that a test can hold
## what a desk and what a phone would be given without being either - and the reading itself stays in the
## one place it is made, `_size_the_chrome_for_the_device`.
func start_the_presentation_panel_for(finger: bool) -> void:
	if _presentation_panel_started:
		return
	_presentation_panel_started = true
	if finger:
		set_presentation_panel_wanted(false)


func _menu_sun_window(_entry: Dictionary) -> void:
	open_sun_window()


func _on_sun_window_closed() -> void:
	_refresh_menus()

# --- the walk-through -----------------------------------------------------------------------


func _menu_walk_window(_entry: Dictionary) -> void:
	open_walk_window()


func _on_walk_window_closed() -> void:
	_refresh_menus()


## Build the page and wire what it asks for. The walk moves the presentation camera, so the page is
## only useful where there is a presentation - which is what `NEEDS_PRESENTATION` says of the menu
## entry that reaches it.
func _build_walk_window() -> void:
	if _walk_window != null:
		return
	_walk_window = WalkWindowScript.new()
	_walk_window.name = "WalkWindow"
	_walk_window.closed.connect(_on_walk_window_closed)
	_walk_window.walk_changed.connect(_refresh_menus)
	add_child(_walk_window)
	_walk_window.build()
	_walk_window.hide()


func open_walk_window() -> void:
	_build_walk_window()
	if _walk_window == null:
		return
	_fill_walk_window()
	PageChromeScript.show_centred(_walk_window)
	# The walk is played from the page, so it holds the drawing's keys while it is up, the way the
	# grading page does; the drawing keys belong to the drawing again the moment it closes.
	release_keyboard_focus(self)


func close_walk_window() -> void:
	if _walk_window != null and _walk_window.visible:
		_walk_window.hide()


func is_walk_window_open() -> bool:
	return _walk_window != null and _walk_window.visible


## Point the page at the presentation, so the walk takes that camera over the garden on the drawing.
func _fill_walk_window() -> void:
	_build_walk_window()
	if _walk_window == null:
		return
	_walk_window.bind(presentation)
	_refresh_menus()

# --- snapping -----------------------------------------------------------------------


func _menu_snap_window(_entry: Dictionary) -> void:
	open_snap_window()


func _on_snap_window_closed() -> void:
	_refresh_menus()


## Build the page. The settings live on the drafting controller, so the page is only useful where
## there is one - which is what the Draft menu's own presence already says.
func _build_snap_window() -> void:
	if _snap_window != null:
		return
	_snap_window = SnapWindowScript.new()
	_snap_window.name = "SnapWindow"
	_snap_window.closed.connect(_on_snap_window_closed)
	add_child(_snap_window)
	_snap_window.build()
	_snap_window.hide()


func open_snap_window() -> void:
	_build_snap_window()
	if _snap_window == null:
		return
	_fill_snap_window()
	PageChromeScript.show_centred(_snap_window)
	# The page's switches take the drawing's keys while it is up, the way the grading page does.
	release_keyboard_focus(self)


func close_snap_window() -> void:
	if _snap_window != null and _snap_window.visible:
		_snap_window.hide()


func is_snap_window_open() -> bool:
	return _snap_window != null and _snap_window.visible


## Point the page at the drawing's own controller, so its switches are the drawing's settings rather
## than a copy the page would have to keep in step.
func _fill_snap_window() -> void:
	_build_snap_window()
	if _snap_window == null:
		return
	_snap_window.bind(_draft)
	_refresh_menus()

# --- what the drawing has said --------------------------------------------------------------
#
# The status line under the plan is one line: it says what the drawing just did, and the next thing
# written over it is gone. Every one of those answers is kept by the drawing itself
# (`DraftController.said`), fed by the one setter every message passes through; the page is the only
# thing here, and it reads the history without writing anything back.


## Build the page and wire its only intent.
func _build_status_window() -> void:
	if _status_window != null:
		return
	_status_window = StatusWindowScript.new()
	_status_window.name = "StatusWindow"
	_status_window.closed.connect(_on_status_window_closed)
	add_child(_status_window)
	_status_window.build()
	_status_window.hide()


func open_status_window() -> void:
	_build_status_window()
	if _status_window == null:
		return
	_fill_status_window()
	PageChromeScript.show_centred(_status_window)
	release_keyboard_focus(self)


func close_status_window() -> void:
	if _status_window != null and _status_window.visible:
		_status_window.hide()


func is_status_window_open() -> bool:
	return _status_window != null and _status_window.visible


## Hand the page the drawing's own history and let it write its rows. Kept apart from *showing* the page
## so the filling can be driven with no window server, which is how the suite checks it.
func _fill_status_window() -> void:
	_build_status_window()
	if _status_window == null:
		return
	_status_window.set_history(_said_history())
	_status_window.say(_status_window.opening_words())
	_refresh_menus()


## The drawing's history, or nothing when there is no drawing in the scene - a page opened in a scene
## with no drawing says so rather than inventing one.
func _said_history() -> StatusHistory:
	if _draft == null:
		return null
	return _draft.said


## The page while it is up: the drawing carries on saying things behind it, so it is rewritten whenever
## the newest answer or the number of them has moved. Nothing is written to the drawing from here.
func _tick_status_window() -> void:
	if _status_window == null or not _status_window.visible:
		return
	_status_window.show_lines()


func _on_status_window_closed() -> void:
	_refresh_menus()


func _menu_said(_entry: Dictionary) -> void:
	open_status_window()

# --- hatching a region ---------------------------------------------------------------------


## The page that hatches a region. Built in code like the survey report, and a `Control` rather than a
## `Window` for the same two reasons: it opens over the drawing it is about, and it must not take the
## keyboard away from it.
func _build_hatch_panel() -> void:
	var root := get_node_or_null(^"Root")
	if root == null:
		return
	var wrapper := BoardPanelScript.new()
	wrapper.name = "HatchPanel"
	wrapper.set_anchors_preset(Control.PRESET_FULL_RECT)
	wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrapper.visible = false

	var page := PanelContainer.new()
	page.name = "Page"
	page.custom_minimum_size = Vector2(520.0, 0.0)
	if top_bar != null:
		page.add_theme_stylebox_override("panel", top_bar.get_theme_stylebox("panel"))
	var column := VBoxContainer.new()
	column.name = "Column"
	page.add_child(column)

	var heading := Label.new()
	heading.name = "Heading"
	heading.text = "Hatch a region"
	column.add_child(heading)

	var panel := HatchPanel.new()
	panel.name = "HatchChoices"
	panel.fill_requested.connect(_on_hatch_fill)
	panel.close_requested.connect(close_hatch_panel)
	column.add_child(panel)
	panel.build()

	wrapper.add_child(page)
	_hatch_page = wrapper
	_hatch_panel = panel
	root.add_child(wrapper)


func is_hatch_panel_open() -> bool:
	return _hatch_page != null and _hatch_page.visible


## What the page says about the drawing: the regions it offers, and what the last fill did.
func hatch_status_text() -> String:
	if _hatch_panel == null:
		return ""
	return _hatch_panel.status_text()


func open_hatch_panel() -> void:
	if _hatch_page == null or _hatch_panel == null:
		return
	_refresh_hatch_panel()
	_hatch_page.visible = true


func close_hatch_panel() -> void:
	if _hatch_page != null:
		_hatch_page.visible = false
	if _hatch_panel != null:
		_hatch_panel.say("")


## The regions the drawing encloses, re-read every frame the page is open: a bed is drawn, moved and
## deleted while the plan is made, and a page listing the beds of a minute ago would fill the wrong
## one.
func _refresh_hatch_panel() -> void:
	if _hatch_panel == null or _draft == null:
		return
	_hatch_panel.set_regions(_draft.hatch_regions())


## Hatch the region the panel named, and report what happened on the panel's own line.
func _on_hatch_fill(entity_id: int, options: Dictionary) -> void:
	if _draft == null or _hatch_panel == null:
		return
	var filled: Dictionary = _draft.fill_entity(entity_id, options)
	_hatch_panel.say(String(filled.get("message", filled.get("reason", ""))))
	_refresh_hatch_panel()


func _menu_hatch_region(_entry: Dictionary) -> void:
	open_hatch_panel()

# --- watering an area ----------------------------------------------------------------------


## The page that waters an area. Built in code like the hatch page, and a `Control` rather than a
## `Window` for the same two reasons: it opens over the drawing it is about, and it must not take the
## keyboard away from it.
func _build_irrigation_panel() -> void:
	var root := get_node_or_null(^"Root")
	if root == null:
		return
	var wrapper := BoardPanelScript.new()
	wrapper.name = "WaterPanel"
	wrapper.set_anchors_preset(Control.PRESET_FULL_RECT)
	wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrapper.visible = false

	var page := PanelContainer.new()
	page.name = "Page"
	page.custom_minimum_size = Vector2(520.0, 0.0)
	if top_bar != null:
		page.add_theme_stylebox_override("panel", top_bar.get_theme_stylebox("panel"))
	var column := VBoxContainer.new()
	column.name = "Column"
	page.add_child(column)

	var heading := Label.new()
	heading.name = "Heading"
	heading.text = "Water an area"
	column.add_child(heading)

	var panel := IrrigationPanel.new()
	panel.name = "WaterChoices"
	panel.supply_requested.connect(_on_water_supply)
	panel.water_requested.connect(_on_water_area)
	panel.remove_requested.connect(_on_water_remove)
	panel.close_requested.connect(close_water_panel)
	column.add_child(panel)
	panel.build()

	wrapper.add_child(page)
	_water_page = wrapper
	_water_panel = panel
	root.add_child(wrapper)


func is_water_panel_open() -> bool:
	return _water_page != null and _water_page.visible


## What the page says about the drawing: the areas it offers, the supply, and the zones already laid
## out.
func water_status_text() -> String:
	if _water_panel == null:
		return ""
	var parts: Array[String] = [_water_panel.budget_text(), _water_panel.status_text()]
	return " ".join(parts)


func open_water_panel() -> void:
	if _water_page == null or _water_panel == null:
		return
	_refresh_water_panel()
	_water_page.visible = true


func close_water_panel() -> void:
	if _water_page != null:
		_water_page.visible = false
	if _water_panel != null:
		_water_panel.say("")


## The areas and the zones the drawing has, re-read every frame the page is open: a bed is drawn,
## moved and deleted while the plan is made, and a page listing the beds of a minute ago would water
## the wrong one. The supply is read too, so a supply stated by a script shows up here.
func _refresh_water_panel() -> void:
	if _water_panel == null or _draft == null:
		return
	_water_panel.set_areas(_draft.waterable_areas())
	_water_panel.set_supply(_draft.irrigation_supply())
	_water_panel.set_zones(_draft.irrigation_rows())


## State the supply the panel shows, and report what happened on the panel's own line.
func _on_water_supply(flow: float, pressure: float) -> void:
	if _draft == null or _water_panel == null:
		return
	var stated: Dictionary = _draft.set_irrigation_supply(flow, pressure)
	_water_panel.say(String(stated.get("message", stated.get("reason", ""))))
	_refresh_water_panel()


## Water the area the panel named, and report what happened on the panel's own line.
func _on_water_area(region_key: String, kind: String, spacing: float, staggered: bool) -> void:
	if _draft == null or _water_panel == null:
		return
	var ring := PackedVector2Array()
	for row: Dictionary in _draft.waterable_areas():
		if String(row.get("key", "")) == region_key:
			ring = row.get("outline", PackedVector2Array())
			break
	if ring.size() < 3:
		_water_panel.say("that area is not there any more")
		_refresh_water_panel()
		return
	var watered: Dictionary = _draft.water_area(ring, kind, spacing, staggered)
	_water_panel.say(String(watered.get("message", watered.get("reason", ""))))
	_refresh_water_panel()


## Take the zone the panel named off the drawing, heads and all, and report it.
func _on_water_remove(number: int) -> void:
	if _draft == null or _water_panel == null:
		return
	var taken: Dictionary = _draft.remove_zone(number)
	_water_panel.say(String(taken.get("message", taken.get("reason", ""))))
	_refresh_water_panel()


func _menu_water_panel(_entry: Dictionary) -> void:
	open_water_panel()

# --- lighting an area ----------------------------------------------------------------------


## The page that lights an area. Built in code like the water page, and a `Control` rather than a
## `Window` for the same two reasons: it opens over the drawing it is about, and it must not take the
## keyboard away from it.
func _build_lighting_panel() -> void:
	var root := get_node_or_null(^"Root")
	if root == null:
		return
	var wrapper := BoardPanelScript.new()
	wrapper.name = "LightPanel"
	wrapper.set_anchors_preset(Control.PRESET_FULL_RECT)
	wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrapper.visible = false

	var page := PanelContainer.new()
	page.name = "Page"
	page.custom_minimum_size = Vector2(520.0, 0.0)
	if top_bar != null:
		page.add_theme_stylebox_override("panel", top_bar.get_theme_stylebox("panel"))
	var column := VBoxContainer.new()
	column.name = "Column"
	page.add_child(column)

	var heading := Label.new()
	heading.name = "Heading"
	heading.text = "Light an area"
	column.add_child(heading)

	var panel := LightingPanel.new()
	panel.name = "LightChoices"
	panel.transformer_requested.connect(_on_light_transformer)
	panel.light_requested.connect(_on_light_area)
	panel.remove_requested.connect(_on_light_remove)
	panel.close_requested.connect(close_light_panel)
	column.add_child(panel)
	panel.build()

	wrapper.add_child(page)
	_light_page = wrapper
	_light_panel = panel
	root.add_child(wrapper)


func is_light_panel_open() -> bool:
	return _light_page != null and _light_page.visible


## What the page says about the drawing: the areas it offers, the transformer, and the circuits already
## laid out.
func light_status_text() -> String:
	if _light_panel == null:
		return ""
	var parts: Array[String] = [_light_panel.budget_text(), _light_panel.status_text()]
	return " ".join(parts)


func open_light_panel() -> void:
	if _light_page == null or _light_panel == null:
		return
	_refresh_light_panel()
	_light_page.visible = true


func close_light_panel() -> void:
	if _light_page != null:
		_light_page.visible = false
	if _light_panel != null:
		_light_panel.say("")


## The areas and the circuits the drawing has, re-read every frame the page is open: a bed is drawn,
## moved and deleted while the plan is made, and a page listing the beds of a minute ago would light
## the wrong one. The transformer is read too, so one stated by a script shows up here.
func _refresh_light_panel() -> void:
	if _light_panel == null or _draft == null:
		return
	_light_panel.set_areas(_draft.lightable_areas())
	_light_panel.set_transformer(_draft.lighting_transformer())
	_light_panel.set_circuits(_draft.lighting_rows())


## State the transformer the panel shows, and report what happened on the panel's own line.
func _on_light_transformer(va: float, volts: float) -> void:
	if _draft == null or _light_panel == null:
		return
	var stated: Dictionary = _draft.set_lighting_transformer(va, volts)
	_light_panel.say(String(stated.get("message", stated.get("reason", ""))))
	_refresh_light_panel()


## Light the area the panel named, and report what happened on the panel's own line.
func _on_light_area(region_key: String, kind: String, spacing: float, staggered: bool) -> void:
	if _draft == null or _light_panel == null:
		return
	var ring := PackedVector2Array()
	for row: Dictionary in _draft.lightable_areas():
		if String(row.get("key", "")) == region_key:
			ring = row.get("outline", PackedVector2Array())
			break
	if ring.size() < 3:
		_light_panel.say("that area is not there any more")
		_refresh_light_panel()
		return
	var lit: Dictionary = _draft.light_area(ring, kind, spacing, staggered)
	_light_panel.say(String(lit.get("message", lit.get("reason", ""))))
	_refresh_light_panel()


## Take the circuit the panel named off the drawing, fixtures and all, and report it.
func _on_light_remove(number: int) -> void:
	if _draft == null or _light_panel == null:
		return
	var taken: Dictionary = _draft.remove_circuit(number)
	_light_panel.say(String(taken.get("message", taken.get("reason", ""))))
	_refresh_light_panel()


func _menu_light_panel(_entry: Dictionary) -> void:
	open_light_panel()

# --- the plant list -----------------------------------------------------------------------


## The library: a window, the browser in it, and the two dialogs a plant list arrives and leaves by.
##
## A `Window` rather than a panel in `Root`, and that is the whole reason it can have a search box:
## `Root` is built focus-free so that nothing in this HUD can take the drawing keys away, and the one
## exception this project allows is a modal window (spec REQ 8.7). Inside this window the controls
## own the keyboard; outside it, nothing has changed.
func _build_plant_library() -> void:
	_plant_window = Window.new()
	_plant_window.name = "PlantLibrary"
	_plant_window.title = "Plant library"
	_plant_window.exclusive = false
	# **The size it declares for itself**, which is the floor `PageChrome.show_centred` starts a page from - not a
	# `popup_centered` argument, which was what this door used and is why the plant library was the one page a
	# finger was never fitted. Measured by `tools/phone_touch_sweep.gd` at a phone's own 450 dpi, 2026-11-14: every
	# control on this page 41 px where a finger wants 97, 84 pairs of them 6-7 px apart, and 74 lines drawn at 16 px
	# where the screen needs 30 - the desk's numbers, whole, on a phone.
	_plant_window.min_size = Vector2i(1080, 680)
	_plant_window.close_requested.connect(close_plant_browser)
	add_child(_plant_window)

	_plant_browser = PlantBrowserScript.new()
	_plant_browser.name = "Browser"
	_plant_browser.set_anchors_preset(Control.PRESET_FULL_RECT)
	_plant_browser.plant_chosen.connect(_on_plant_chosen)
	_plant_browser.import_requested.connect(_on_plant_import_requested)
	_plant_browser.export_requested.connect(_on_plant_export_requested)
	_plant_window.add_child(_plant_browser)

	# Imported from wherever the file is - a nursery's list arrives as a download, not as something
	# already filed in this program's folder - and exported into `user://plants`, where the list the
	# program reads lives.
	_plant_import_dialog = FileDialog.new()
	_plant_import_dialog.name = "ImportPlantList"
	_plant_import_dialog.title = "Import a plant list"
	_plant_import_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_plant_import_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_plant_import_dialog.filters = PackedStringArray(["*.json ; Plant lists"])
	_plant_import_dialog.file_selected.connect(_on_plant_import_chosen)
	add_child(_plant_import_dialog)
	PhoneFilesScript.prepare(_plant_import_dialog)

	_plant_export_dialog = FileDialog.new()
	_plant_export_dialog.name = "ExportPlantList"
	_plant_export_dialog.title = "Export the plant list"
	_plant_export_dialog.access = FileDialog.ACCESS_USERDATA
	_plant_export_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_plant_export_dialog.current_dir = PlantCatalogueScript.DEFAULT_PATH.get_base_dir()
	_plant_export_dialog.current_file = "plant-list.json"
	_plant_export_dialog.filters = PackedStringArray(["*.json ; Plant lists"])
	_plant_export_dialog.file_selected.connect(_on_plant_export_chosen)
	add_child(_plant_export_dialog)

	# Not shown until it is asked for. A window is shown by showing it, and a library that appeared
	# the moment the program started would be a program that opens with somebody else's plant list
	# over the drawing.
	_plant_window.hide()


## The plants section of the palette: the catalogue as a list under the drawing tools.
##
## The library answers "which plant is right for this spot" - four thousand species, filters, a search
## box, a detail pane. It is a window, and it has to be, because it has a text field in it and a text
## field is the one thing this HUD may not own outside a modal window. This answers the other
## question, which is "put that one down again", and it answers it where the designer is already
## looking. Between them a bed is a dozen clicks rather than a dozen trips through a window.
func _build_plant_panel() -> void:
	if palette_column == null or _plant_panel != null:
		return
	var panel: PlantPanel = PlantPanelScript.new()
	panel.name = "Plants"
	# Built before it is added, and built by hand: the panel's `_ready` would build it with a default
	# label, and the key this project writes into every label comes from the input map.
	panel.build("Library...  (%s)" % _key_label(&"plant_library"))
	panel.bind(plant_list())
	panel.plant_chosen.connect(_on_plant_panel_chosen)
	panel.library_requested.connect(open_plant_browser)
	panel.stop_requested.connect(_on_plant_panel_stop)
	panel.fill_requested.connect(_on_plant_fill_bed)
	palette_column.add_child(panel)
	_plant_panel = panel


## Choosing from the palette arms the plant and changes nothing else: the library closes on a choice
## because the choice was made to get back to the plan, and here there is nothing to close.
func _on_plant_panel_chosen(species_id: StringName) -> void:
	_arm_planting(species_id)


func _on_plant_panel_stop() -> void:
	if view_controller != null:
		view_controller.stop_planting()

# --- filling a bed ---------------------------------------------------------------------------


## The beds a planting can go in: the areas the drawing encloses, narrowed by `PlantSpacing` to the beds
## and the planting already there.
##
## Read from the drawing rather than kept, because a bed is drawn, moved and deleted with the drawing
## tools: a list built once would offer beds that are no longer there and miss the one just drawn.
func _planting_beds() -> Array[Dictionary]:
	if _draft == null or _draft.document == null:
		return []
	return PlantSpacingScript.bed_areas(_draft.document)


## Fill a bed with the plant the palette has chosen: the whole point of the arithmetic being in one
## module is that this is the only place that plants a bed, and it plants it by asking for the points
## and putting an ordinary plant on each of them.
##
## The report goes to the palette's own status line rather than to the plan's, because the plan's line
## is rewritten every frame by the planting verdict while a plant is in hand - a message written there
## would be on screen for a single frame.
func _on_plant_fill_bed(bed_key: String, spacing: float, arrangement: String) -> void:
	if _plant_panel == null:
		return
	var species_id: StringName = _plant_panel.selected_id()
	if species_id.is_empty():
		_plant_panel.say("Choose a plant to fill a bed with")
		return
	var bed: Dictionary = { }
	for row: Dictionary in _planting_beds():
		if String(row.get("key", "")) == bed_key:
			bed = row
	if bed.is_empty():
		# The bed was in the drop-down and the drawing has moved on since: say so rather than filling
		# whichever bed is now first, which would be planting somewhere nobody pointed at.
		_plant_panel.say("That bed is not on the drawing any more")
		return
	var yard: Node = view_controller.yard if view_controller != null else null
	var report: Dictionary = PlantSpacingScript.fill(
		plant_list(),
		yard,
		species_id,
		bed["outline"],
		{ "spacing": spacing, "arrangement": arrangement },
	)
	_plant_panel.say(PlantSpacingScript.report_words(report))
	if not bool(report["ok"]):
		return
	# A filled bed is a planting: the plan reads the yard again, the picker's cache is dropped, and the
	# count the menu reports moves with it - the same three things a single placement does.
	if view_controller != null:
		view_controller.refresh_after_planting()
	_refresh_plant_panel()
	_refresh_menus()


## Match the plants section to the controller. Bound to whatever the list is now, because an import
## replaces the catalogue itself and a panel still listing the plants from this morning would look
## like an import that failed. The expensive part - the rows - is only rebuilt when the catalogue or
## the tag changes; a plant count is a label.
func _refresh_plant_panel() -> void:
	if _plant_panel == null:
		return
	var catalogue: PlantCatalogue = plant_list()
	if _plant_panel.catalogue != catalogue:
		_plant_panel.bind(catalogue)
	# The beds the drawing encloses, offered beside the plants. Read when the drawing has a different
	# number of things on it rather than every frame, for the reason the bed list's own field gives.
	if _draft != null and _draft.document != null:
		var entities: int = _draft.document.count()
		if entities != _beds_from_count:
			_beds_from_count = entities
			_plant_panel.set_beds(PlantSpacingScript.bed_areas(_draft.document))
	var in_hand: StringName = &""
	var standing: int = 0
	if view_controller != null:
		in_hand = view_controller.planting_species
		standing = view_controller.planted_count()
	_plant_panel.refresh(in_hand, standing)


## The plant list, read once and kept.
##
## The first run has no catalogue of its own, so the list the project ships with is the list - read
## from `res://` and held in memory until something changes it, at which point it is written to
## `user://`. A shipped list stays a shipped list, and a catalogue somebody has edited is theirs.
func plant_list() -> PlantCatalogue:
	if _plants != null:
		return _plants
	var read: Dictionary = PlantCatalogueScript.load_from(PlantCatalogueScript.DEFAULT_PATH)
	if bool(read["ok"]):
		_plants = read["catalogue"]
	else:
		var seeded: Dictionary = PlantCatalogueScript.load_from(STARTER_PLANT_LIST)
		_plants = seeded["catalogue"] if bool(seeded["ok"]) else PlantCatalogueScript.make()
	# A person's own collections live in their own file and are read on top of the catalogue, which
	# is what keeps them out of the way of an import that replaces the catalogue wholesale.
	_plants.load_collections()
	return _plants


## What the Plant menu says on itself: what the list is, and what a click would put down.
func plant_state_text() -> String:
	var catalogue: PlantCatalogue = plant_list()
	if view_controller != null and view_controller.is_planting():
		var species: PlantSpecies = catalogue.get_species(view_controller.planting_species)
		if species != null:
			return "planting %s" % species.display_name()
	var planted: int = view_controller.planted_count() if view_controller != null else 0
	var words: String = "%d species, %d planted" % [catalogue.count(), planted]
	var problems: Array[String] = catalogue.problems()
	if not problems.is_empty():
		words += "  -  %d entries need attention" % problems.size()
	return words


func open_plant_browser() -> void:
	if _plant_window == null:
		return
	_refresh_plant_browser()
	# **Through the one door a page is shown by**, and not `popup_centered` as this did until 2026-11-14. The door
	# does four things to a page that a bare pop-up does not: it sizes the buttons for a finger, grows the page's
	# words for the screen, insets its contents so a thumb has room, and lands it clear of its own title bar and a
	# phone's cutout. This was one of three doors that skipped all four, so on a phone the plant library was a page
	# of 41 px controls in 16 px type - 67 short, 84 close and 74 tiny, read by `tools/phone_touch_sweep.gd` at a
	# phone's own 450 dpi. The size above is unchanged: 1080 by 680 is what it declared here, and it is what the
	# door places it at.
	PageChromeScript.show_centred(_plant_window)
	if _plant_browser != null:
		_plant_browser.focus_search()


func close_plant_browser() -> void:
	if _plant_window != null:
		_plant_window.hide()


## The nursery order: the drawing's planting list priced from the price list, written as draft purchase
## orders on the job desk. The fifth window onto the desk, and the only one that starts from the plan.
##
## It owns nothing - the plan is `PlantOrder`'s arithmetic over the planting rows and the book, the page
## is a screen, and the orders are the desk's - so all this file does is hand each of the three to the
## next one.
func _build_plant_order_window() -> void:
	if _plant_order_window != null:
		return
	_plant_order_window = PlantOrderWindowScript.new()
	_plant_order_window.name = "PlantOrderWindow"
	add_child(_plant_order_window)
	_plant_order_window.build()
	# The page announces the job and the nursery and does nothing else. Writing the order is this
	# file's errand, because the desk and the planting rows are both here.
	_plant_order_window.order_requested.connect(_on_plant_order_requested)
	_plant_order_window.closed.connect(close_plant_order_window)
	_plant_order_window.hide()


## The menu's door: the drawing's own planting. It forgets anything the yield page handed over, because
## "order the plants for this drawing" is a question about the drawing and not about a household.
func open_plant_order_window() -> void:
	_forget_handed_plan()
	_show_plant_order_window()


## Forget a plan a household handed over, so the order page is about the drawing's planting again.
func _forget_handed_plan() -> void:
	_plant_order_plan_override = { }


## Show the order page on the plan it is pointed at, whether that is the drawing's planting or a count a
## household worked out. Built and filled without a screen, so the suite drives the same page.
func _show_plant_order_window() -> void:
	_build_plant_order_window()
	if _plant_order_window == null:
		return
	_fill_plant_order_window()
	PageChromeScript.show_centred(_plant_order_window)
	release_keyboard_focus(self)


func close_plant_order_window() -> void:
	if _plant_order_window != null:
		_plant_order_window.hide()


func is_plant_order_window_open() -> bool:
	return _plant_order_window != null and _plant_order_window.visible


## Point the page at the desk and hand it what the drawing plants. Built and filled without a screen, so
## the test suite drives the same controls the program shows - `popup_centered` needs a screen and a test
## has none.
func _fill_plant_order_window() -> void:
	_build_plant_order_window()
	if _plant_order_window == null:
		return
	if _job_desk == null:
		_build_job_desk()
	_plant_order_window.bind(_job_desk)
	_plant_order_window.set_plan(plant_order_plan())
	_plant_order_state = _plant_order_signature()


## The page while it is up. The planting and the desk can both move under it - a plant put down in the
## yard, an order issued on another page - so it is read again whenever either has.
func _tick_plant_order_window() -> void:
	if _plant_order_window == null or not _plant_order_window.visible:
		return
	var state := _plant_order_signature()
	if state == _plant_order_state:
		return
	_plant_order_state = state
	_fill_plant_order_window()


## What the last refresh was drawn from: the planting rows themselves and the desk's own counts. The
## price list is deliberately not in it - a page left open does not have to keep up with a book somebody
## is editing on another screen.
func _plant_order_signature() -> String:
	var jobs := 0
	var orders := 0
	if _job_desk != null:
		jobs = _job_desk.jobs.size()
		orders = _job_desk.purchase_orders.size()
	# A plan handed over by the yield page is a fixed number of plants until it is handed over again, so its
	# size is enough to notice a re-hand-off - and the drawing's planting is what the page keeps up with the
	# rest of the time.
	if not _plant_order_plan_override.is_empty():
		var handed: int = (_plant_order_plan_override.get("lines", []) as Array).size()
		return "handed|%d|%d|%d" % [handed, jobs, orders]
	return "drawing|%d|%d|%d" % [hash(_planting_rows()), jobs, orders]


## The plan: the drawing's planting, priced from the price list, one line per kind of plant - or the count
## the yield page handed over, already priced, if there is one.
func plant_order_plan() -> Dictionary:
	if not _plant_order_plan_override.is_empty():
		return _plant_order_plan_override
	return PlantOrderScript.plan(_planting_rows(), _plant_order_book())


## The price list the plants are bought at: the one the estimator is using, so the order and the proposal
## cannot be priced from two different books. The book's own search order - the business's own file
## first, the shipped starter list only if there is none - is `load_book`'s, and is not repeated here.
func _plant_order_book() -> CostBook:
	if _estimate_window == null or _estimate_window.desk == null:
		return null
	if _estimate_window.desk.book == null:
		_estimate_window.desk.load_book()
	return _estimate_window.desk.book


## Write the orders: one draft purchase order per nursery, one line per kind of plant.
##
## Reachable without a page, so the write can be tested on its own. **Nothing is issued here**: ordering
## is a decision the office takes where orders are managed, and a page that wrote and issued in one press
## would commit a job to money from a list nobody had read.
func write_plant_order(job_id: String, supplier: String) -> Dictionary:
	if _job_desk == null:
		_build_job_desk()
	var written: Dictionary = PlantOrderScript.write_orders(_job_desk, job_id, plant_order_plan(), supplier)
	if bool(written["ok"]):
		_plant_order_state = _plant_order_signature()
		# What the job has committed has moved, so the cost page and the menu lines are stale.
		_on_cost_changed()
	return written


## The page asked for the order to be written: write it and say where it went.
func _on_plant_order_requested(job_id: String, supplier: String) -> void:
	var written: Dictionary = write_plant_order(job_id, supplier)
	if _plant_order_window == null:
		return
	if bool(written["ok"]):
		_plant_order_window.say(
			"written, and waiting to be issued: %s" % PlantOrderScript.orders_words(written["orders"])
		)
	else:
		_plant_order_window.say(String(written["reason"]))


func _menu_plant_order_window(_entry: Dictionary) -> void:
	open_plant_order_window()


## The yield page handed its household's count over: price those rows from the same book the drawing's
## planting is priced from, point the order page at the result, and show it. Everything up to the screen
## is `_show_yield_order`, which needs no window server, so the suite can drive the join.
func _on_yield_order_requested(rows: Array) -> void:
	_show_yield_order(rows)
	if _plant_order_window != null:
		PageChromeScript.show_centred(_plant_order_window)
	release_keyboard_focus(self)
	if _yield_window != null:
		_yield_window.say("handed %d kind%s to the nursery order" % [rows.size(), "" if rows.size() == 1 else "s"])


## Point the order page at the rows a household's count comes to, priced, and fill it - without showing
## it. Returns the plan handed over, so the join can be checked with no screen.
func _show_yield_order(rows: Array) -> Dictionary:
	_plant_order_plan_override = PlantOrderScript.plan(rows, _plant_order_book())
	_fill_plant_order_window()
	return _plant_order_plan_override

# --- the food garden -------------------------------------------------------------------------
#
# The other question the same drawing and the same plant list are for: not what a plant wants, but
# whether the food a person means to eat will actually crop where they mean to put it. It owns nothing
# - `CropSun` is the arithmetic, the ground map is the document's, the site is the presentation's, and
# the plant list is the one the Plant menu already counts - so all this file does is hand each of the
# three to the page.


func _build_food_window() -> void:
	if _food_window != null:
		return
	_food_window = FoodWindowScript.new()
	_food_window.name = "FoodWindow"
	add_child(_food_window)
	_food_window.build()
	_food_window.closed.connect(_on_food_window_closed)
	_food_window.hide()


func open_food_window() -> void:
	_build_food_window()
	if _food_window == null:
		return
	_fill_food_window()
	PageChromeScript.show_centred(_food_window)
	release_keyboard_focus(self)


func close_food_window() -> void:
	if _food_window != null:
		_food_window.hide()


func is_food_window_open() -> bool:
	return _food_window != null and _food_window.visible


## Point the page at the plant list, the drawing's own beds and the site. Built and filled without a
## screen, so the suite drives the same page the program shows - `popup_centered` needs a screen and a
## test has none.
func _fill_food_window() -> void:
	_build_food_window()
	if _food_window == null:
		return
	_food_window.bind(plant_list(), food_places(), _sun_site())
	_food_state = _food_signature()
	_refresh_menus()


## The beds the page offers: the site's own conditions, then every area the ground map knows, each
## merged over the site's - so a bed stated part shade in a full-sun garden reads as part shade, and
## the keys it does not state follow the garden rather than reading as unstated.
##
## A scene with no drawing has no ground, and the page is told so rather than handed a bed nobody
## stated. The *rows* are not read here: `ZoneMap.zones` holds one entry per area, and the page lists
## the crops, not the ground.
func food_places() -> Array:
	var places: Array = []
	var map: ZoneMapScript = _ground_map()
	if map == null:
		return places
	places.append({ "name": "the whole site", "profile": map.base.copy(), "summary": map.base.describe() })
	for raw: Variant in map.zones:
		var zone: Variant = raw
		var stated: TerrainProfile = zone.profile
		var profile: TerrainProfile = stated.merged_over(map.base)
		places.append({ "name": String(zone.name), "profile": profile, "summary": profile.describe() })
	return places


## The page while it is up: the ground and the site can both move under it - a bed restated in the
## ground window, a drawing loaded with another site - so it is read again whenever either has. The
## *plant list* is deliberately not read again: it is a file, and a page left open does not have to
## keep up with a list somebody is editing on another screen.
func _tick_food_window() -> void:
	if _food_window == null or not _food_window.visible:
		return
	var state := _food_signature()
	if state == _food_state:
		return
	_food_state = state
	_fill_food_window()


## What the last refresh was drawn from: the beds, each described in its own words, and the site. The
## beds are compared by the words the page shows rather than by their geometry, because the words are
## what a restated bed changes.
func _food_signature() -> String:
	var parts: PackedStringArray = PackedStringArray()
	for place: Dictionary in food_places():
		parts.append("%s=%s" % [String(place.get("name", "")), String(place.get("summary", ""))])
	parts.append(str(_sun_site()))
	return "|".join(parts)


func _menu_food_window(_entry: Dictionary) -> void:
	open_food_window()


func _on_food_window_closed() -> void:
	_refresh_menus()

# --- what to grow here next -------------------------------------------------------------------
#
# The kitchen gardener's other question, asked of the same beds: not what will crop, but what should
# follow what and what grows well beside. It owns nothing either - `CropRotation` is the arithmetic,
# the beds are the drawing's ground, the plant list is the Plant menu's - and the one thing it keeps
# that nothing else can is *what grew in a bed last*, which the document was never told and which the
# page holds while it is up.


func _build_rotation_window() -> void:
	if _rotation_window != null:
		return
	_rotation_window = RotationWindowScript.new()
	_rotation_window.name = "RotationWindow"
	add_child(_rotation_window)
	_rotation_window.build()
	_rotation_window.closed.connect(_on_rotation_window_closed)
	_rotation_window.hide()


func open_rotation_window() -> void:
	_build_rotation_window()
	if _rotation_window == null:
		return
	_fill_rotation_window()
	PageChromeScript.show_centred(_rotation_window)
	release_keyboard_focus(self)


func close_rotation_window() -> void:
	if _rotation_window != null:
		_rotation_window.hide()


func is_rotation_window_open() -> bool:
	return _rotation_window != null and _rotation_window.visible


## Point the page at the plant list and the ground's own beds. Built and filled without a screen, so
## the suite drives the same page the program shows. The stated history starts empty, which is right:
## the beds it was about are being replaced.
func _fill_rotation_window() -> void:
	_build_rotation_window()
	if _rotation_window == null:
		return
	_rotation_window.bind(plant_list(), rotation_places())
	_rotation_state = _rotation_signature()
	_refresh_menus()


## The beds the rotation page offers: the ground's own areas, by name and by what they are. A bed is a
## bed whether it is being checked for sun or for rotation, so these are the same places the food page
## is handed - it is only that this page needs a bed to have an identity, not a light level.
func rotation_places() -> Array:
	var places: Array = []
	var map: ZoneMapScript = _ground_map()
	if map == null:
		return places
	places.append({ "name": "the whole site", "summary": map.base.describe() })
	for raw: Variant in map.zones:
		var zone: Variant = raw
		var profile: TerrainProfile = zone.profile.merged_over(map.base)
		places.append({ "name": String(zone.name), "summary": profile.describe() })
	return places


## The page while it is up: a bed stated on the drawing behind it is a bed it should offer, so the bed
## set is read again whenever it has changed. Only the beds are handed over - the history the page
## holds is kept, because a bed being added elsewhere does not unstate what grew in another.
func _tick_rotation_window() -> void:
	if _rotation_window == null or not _rotation_window.visible:
		return
	var state := _rotation_signature()
	if state == _rotation_state:
		return
	_rotation_state = state
	_rotation_window.set_places(rotation_places())


## What the last refresh was drawn from: the beds by name. A bed restated in the ground window has the
## same name, which is the point - rotation is about a bed and its history, not about its light.
func _rotation_signature() -> String:
	var parts: PackedStringArray = PackedStringArray()
	for place: Dictionary in rotation_places():
		parts.append(String(place.get("name", "")))
	return "|".join(parts)


func _menu_rotation_window(_entry: Dictionary) -> void:
	open_rotation_window()


func _on_rotation_window_closed() -> void:
	_refresh_menus()

# --- what is ready when -----------------------------------------------------------------------
#
# The third reading of the same kitchen garden, and the plainest: not where a crop will grow or what
# should follow it, but *when* it is cut. It reads one thing - the plant list's own harvest windows -
# and owns nothing, not even a bed: a harvest time is a fact about the crop, not about the ground, so
# the page needs no drawing. An import that changes the list is the only thing it ever has to keep up
# with, which is why its tick is a no-op the rest of the time.


func _build_harvest_window() -> void:
	if _harvest_window != null:
		return
	_harvest_window = HarvestWindowScript.new()
	_harvest_window.name = "HarvestWindow"
	add_child(_harvest_window)
	_harvest_window.build()
	_harvest_window.closed.connect(_on_harvest_window_closed)
	_harvest_window.hide()


func open_harvest_window() -> void:
	_build_harvest_window()
	if _harvest_window == null:
		return
	_fill_harvest_window()
	PageChromeScript.show_centred(_harvest_window)
	release_keyboard_focus(self)


func close_harvest_window() -> void:
	if _harvest_window != null:
		_harvest_window.hide()


func is_harvest_window_open() -> bool:
	return _harvest_window != null and _harvest_window.visible


## Point the page at the plant list. Built and filled without a screen, so the suite drives the same
## page the program shows - `popup_centered` needs a screen and a test has none.
func _fill_harvest_window() -> void:
	_build_harvest_window()
	if _harvest_window == null:
		return
	_harvest_window.bind(plant_list())
	_harvest_state = _harvest_signature()
	_refresh_menus()


## The page while it is up. Unlike the food and rotation pages, nothing on the drawing can change what
## it shows: it reads the plant list and nothing else, so it is read again only when that list does.
func _tick_harvest_window() -> void:
	if _harvest_window == null or not _harvest_window.visible:
		return
	var state := _harvest_signature()
	if state == _harvest_state:
		return
	_harvest_state = state
	_harvest_window.bind(plant_list())


## What the last refresh was drawn from: every crop and the window it is ready in. The list is a file
## read once and held, so this walks what is already in memory; two lists with the same crops and the
## same windows show the same calendar, which is exactly when a refresh is not needed.
func _harvest_signature() -> String:
	var catalogue: PlantCatalogue = plant_list()
	if catalogue == null:
		return ""
	var parts: PackedStringArray = PackedStringArray()
	for plant: PlantSpecies in catalogue.all():
		parts.append("%s:%d" % [String(plant.id), plant.harvest_months])
	return "|".join(parts)


func _menu_harvest_window(_entry: Dictionary) -> void:
	open_harvest_window()


func _on_harvest_window_closed() -> void:
	_refresh_menus()

# --- when to sow -------------------------------------------------------------------------------
#
# The growing season read as a calendar: a day to sow on, a crop to sow, and the succession of sowings
# that keeps it coming. It reads two things - the drawing's frost dates and the plant list's times to
# maturity - and writes nothing, so it is the season page's reading half: the season page states the
# season, and this spends it. It needs the drawing because the season lives there.


func _build_sowing_window() -> void:
	if _sowing_window != null:
		return
	_sowing_window = SowingWindowScript.new()
	_sowing_window.name = "SowingWindow"
	add_child(_sowing_window)
	_sowing_window.build()
	_sowing_window.closed.connect(_on_sowing_window_closed)
	_sowing_window.hide()


func open_sowing_window() -> void:
	_build_sowing_window()
	if _sowing_window == null:
		return
	if _draft == null or _draft.document == null:
		return
	_fill_sowing_window()
	PageChromeScript.show_centred(_sowing_window)
	release_keyboard_focus(self)


func close_sowing_window() -> void:
	if _sowing_window != null:
		_sowing_window.hide()


func is_sowing_window_open() -> bool:
	return _sowing_window != null and _sowing_window.visible


## Point the page at the drawing's season and the plant list. Built and filled without a screen, so the
## suite drives the same page the program shows - `popup_centered` needs a screen and a test has none.
func _fill_sowing_window() -> void:
	_build_sowing_window()
	if _sowing_window == null:
		return
	_sowing_window.bind(plant_list(), _draft.document if _draft != null else null)
	_sowing_state = _sowing_signature()
	_refresh_menus()


## The page while it is up: the drawing's season can move behind it - another window, or an undo that
## puts older frost dates back - so the season it sows into is read again whenever the drawing or its
## dates move, or the plant list is imported again. The day in hand is not touched: it is the person's.
func _tick_sowing_window() -> void:
	if _sowing_window == null or not _sowing_window.visible:
		return
	var state := _sowing_signature()
	if state == _sowing_state:
		return
	_sowing_state = state
	_sowing_window.set_document(_draft.document if _draft != null else null)
	_sowing_window.set_catalogue(plant_list())


## What the last refresh was drawn from: the drawing's season and the plant list's crops. Both the
## drawing's own identity and the list's crops are in it, because a *different* drawing that states the
## same season is still a different season to sow into, and an imported list changes what will ripen.
func _sowing_signature() -> String:
	return "%s|%s" % [_season_signature(), _harvest_signature()]


func _menu_sowing_window(_entry: Dictionary) -> void:
	open_sowing_window()


func _on_sowing_window_closed() -> void:
	_refresh_menus()

# --- how much to plant -------------------------------------------------------------------------
#
# The kitchen garden's last reading: not where a crop will grow or when it ripens, but how many of it a
# household needs. It reads the plant list and nothing else - how much a plant gives is a fact about the
# plant and how many people are eating is a fact about a household, neither of which was ever told to a
# drawing - so it needs no drawing, like the harvest calendar.


func _build_yield_window() -> void:
	if _yield_window != null:
		return
	_yield_window = YieldWindowScript.new()
	_yield_window.name = "YieldWindow"
	add_child(_yield_window)
	_yield_window.build()
	_yield_window.closed.connect(_on_yield_window_closed)
	# The page works out a count and hands it over; turning that count into a nursery order is this file's
	# errand, because the plant list, the price list and the job desk are all here.
	_yield_window.order_requested.connect(_on_yield_order_requested)
	_yield_window.hide()


func open_yield_window() -> void:
	_build_yield_window()
	if _yield_window == null:
		return
	_fill_yield_window()
	PageChromeScript.show_centred(_yield_window)
	release_keyboard_focus(self)


func close_yield_window() -> void:
	if _yield_window != null:
		_yield_window.hide()


func is_yield_window_open() -> bool:
	return _yield_window != null and _yield_window.visible


## Point the page at the plant list. Built and filled without a screen, so the suite drives the same page
## the program shows - `popup_centered` needs a screen and a test has none.
func _fill_yield_window() -> void:
	_build_yield_window()
	if _yield_window == null:
		return
	_yield_window.bind(plant_list())
	_yield_state = _yield_signature()
	_refresh_menus()


## The page while it is up: the plant list is the only thing that can change what it shows, so it is read
## again only when an import changes the list - its tick is a no-op the rest of the time.
func _tick_yield_window() -> void:
	if _yield_window == null or not _yield_window.visible:
		return
	var state := _yield_signature()
	if state == _yield_state:
		return
	_yield_state = state
	_yield_window.set_catalogue(plant_list())


## What the last refresh was drawn from: every crop and the two facts the plan needs. A list that changed
## a yield or a share shows a different plan, which is exactly when a refresh is needed.
func _yield_signature() -> String:
	var catalogue: PlantCatalogue = plant_list()
	if catalogue == null:
		return ""
	var parts: PackedStringArray = PackedStringArray()
	for plant: PlantSpecies in catalogue.all():
		parts.append("%s:%d:%d" % [String(plant.id), plant.yield_per_plant_g, plant.need_per_person_g])
	return "|".join(parts)


func _menu_yield_window(_entry: Dictionary) -> void:
	open_yield_window()


func _on_yield_window_closed() -> void:
	_refresh_menus()

# --- the growing season -------------------------------------------------------------------------
#
# The site's own frost dates, and what they mean for the food list. Every other food page reads the
# drawing; this one writes to it, because a frost date is the one input the drawing cannot supply -
# the same shape the sun study has with its casting height, except this one is a fact about the site
# and so is kept on the drawing rather than on a page.


func _build_season_window() -> void:
	if _season_window != null:
		return
	_season_window = SeasonWindowScript.new()
	_season_window.name = "SeasonWindow"
	add_child(_season_window)
	_season_window.build()
	_season_window.season_changed.connect(_on_season_changed)
	_season_window.closed.connect(_on_season_window_closed)
	_season_window.hide()


func open_season_window() -> void:
	_build_season_window()
	if _season_window == null:
		return
	if _draft == null or _draft.document == null:
		return
	_fill_season_window()
	PageChromeScript.show_centred(_season_window)
	release_keyboard_focus(self)


func close_season_window() -> void:
	if _season_window != null:
		_season_window.hide()


func is_season_window_open() -> bool:
	return _season_window != null and _season_window.visible


## Point the page at the drawing and the plant list. Built and filled without a screen, so the suite
## drives the same page the program shows - `popup_centered` needs a screen and a test has none.
func _fill_season_window() -> void:
	_build_season_window()
	if _season_window == null:
		return
	_season_window.set_document(_draft.document if _draft != null else null)
	_season_window.set_catalogue(plant_list())
	_season_state = _season_signature()
	_refresh_menus()


## The page while it is up: the drawing can be replaced behind it - a file opened, an undo that puts
## an older state back - so the season it shows is read again whenever the drawing or its dates move.
## The *fields* are not touched: what a person is about to fill in is theirs, and the page keeps it.
func _tick_season_window() -> void:
	if _season_window == null or not _season_window.visible:
		return
	var state := _season_signature()
	if state == _season_state:
		return
	_season_state = state
	_season_window.set_document(_draft.document if _draft != null else null)
	_season_window.set_catalogue(plant_list())


## What the last refresh was drawn from: which drawing is open and the season it states. The drawing
## is named by its instance rather than by its site, so a *different* drawing that happens to state
## the same season is still read again - the page is about a drawing, not about a pair of numbers.
func _season_signature() -> String:
	if _draft == null or _draft.document == null:
		return "no drawing"
	var document: DraftDocument = _draft.document
	return "%d:%d:%d" % [document.get_instance_id(), document.season_last_frost, document.season_first_frost]


## What the Site menu says about the season, in one line. Lower-cased at the front because a menu
## entry is a line of a menu and not a sentence paragraph.
func _season_text() -> String:
	var document: DraftDocument = _draft.document if _draft != null else null
	if document == null:
		return "there is no drawing to state a growing season on"
	var words := GrowingSeasonScript.season_text(document.season_last_frost, document.season_first_frost)
	if words.is_empty():
		return "the growing season is not stated"
	return words.substr(0, 1).to_lower() + words.substr(1)


func _menu_season_window(_entry: Dictionary) -> void:
	open_season_window()


## The season changed on the drawing: the Site menu's line about it is stale.
func _on_season_changed() -> void:
	_refresh_menus()

# --- recording what is on site -------------------------------------------------------------------


func _menu_capture_window(_entry: Dictionary) -> void:
	open_capture_window()


func _on_capture_window_closed() -> void:
	_refresh_menus()


## Build the page. Unlike the other Site pages it is not built *from* the drawing - it writes to the
## survey file, not to the document - but it needs a drawing to be open at all, because a capture is a
## plant at a place on this site and the drawing is what this site is.
func _build_capture_window() -> void:
	if _capture_window != null:
		return
	_capture_window = FieldCaptureWindowScript.new()
	_capture_window.name = "CaptureWindow"
	add_child(_capture_window)
	_capture_window.build()
	_capture_window.closed.connect(_on_capture_window_closed)
	_capture_window.camera_changed.connect(_on_capture_camera_changed)
	_capture_window.key_requested.connect(_on_capture_key_requested)
	_capture_window.hide()


func open_capture_window() -> void:
	_build_capture_window()
	if _capture_window == null:
		return
	if _draft == null or _draft.document == null:
		return
	_fill_capture_window()
	PageChromeScript.show_centred(_capture_window)
	release_keyboard_focus(self)


func close_capture_window() -> void:
	if _capture_window != null and _capture_window.visible:
		_capture_window.request_close()


## Hand the page the one plant list, so a capture is checked against the catalogue the browser shows,
## and let it keep the survey path it already defaults to - the file `SurveyWatcher` watches.
func _fill_capture_window() -> void:
	_build_capture_window()
	if _capture_window == null:
		return
	_capture_window.bind(plant_list())
	_refresh_menus()


func is_capture_window_open() -> bool:
	return _capture_window != null and _capture_window.visible


func _on_season_window_closed() -> void:
	_refresh_menus()


## The takeoff and the estimate: the window, and what the menu says about it.
##
## The window owns the desk (the drawing, the cost book, the takeoff and the estimate), and this file
## owns the window. The menu reads the desk for its one line and never prices anything itself: the
## numbers on it come from the estimate, which is the only thing that has any arithmetic.
func _build_estimate_window() -> void:
	if _estimate_window != null:
		return
	_estimate_window = EstimateWindowScript.new()
	_estimate_window.name = "EstimateWindow"
	add_child(_estimate_window)
	_estimate_window.estimate_changed.connect(_on_estimate_changed)
	# A proposal that has gone and come back won is a job, so the window hands the estimate to this
	# file, which gives it to the desk. The window keeps no jobs of its own.
	_estimate_window.job_started.connect(_on_job_started)
	_estimate_window.hide()


## Open it, pointed at the drawing that is open now and at the planting standing in the yard.
##
## The plants are handed in as a list rather than left to the drawing, because a plant placed in the
## 3D view is a prop and a circle drawn on the planting layer is how that prop is drawn: with a list,
## the takeoff counts the props and leaves the symbols out, and a garden is never billed twice.
func open_estimate_window() -> void:
	if _estimate_window == null or _draft == null or _draft.document == null:
		return
	_estimate_window.bind(_draft.document, _planting_rows())
	PageChromeScript.show_centred(_estimate_window)
	# A window holds the keyboard while it is up, which is what a window is for; the moment it closes
	# the drawing keys belong to the drawing again.
	release_keyboard_focus(self)


func is_estimate_window_open() -> bool:
	return _estimate_window != null and _estimate_window.visible


## The yard's planting list, in the rows the takeoff counts from, or empty in a scene with no yard.
func _planting_rows() -> Array:
	if view_controller == null or view_controller.yard == null:
		return []
	return PlantPlacementScript.schedule(plant_list(), view_controller.yard)


## What the Estimate menu says on itself: where the job stands, in the estimate's own words.
func _estimate_text() -> String:
	if _estimate_window == null or _estimate_window.desk == null:
		return "the estimator is not here"
	return _estimate_window.desk.describe()


## The estimate moved: taking off a plan prices it, so a saturated menu line is now stale.
func _on_estimate_changed() -> void:
	_refresh_menus()


func _menu_estimate_window(_entry: Dictionary) -> void:
	open_estimate_window()


## Take off the plan from the menu, and open the window it happens in: a result somebody cannot see
## is a result they will run again.
func _menu_take_off(_entry: Dictionary) -> void:
	open_estimate_window()
	if _estimate_window != null:
		_estimate_window.take_off()


func _menu_check_numbers(_entry: Dictionary) -> void:
	open_estimate_window()
	if _estimate_window != null:
		_estimate_window.check_numbers()


## The sales pipeline: the board of leads. A `Window` like the estimate and the ground window, and
## for the same reason - it has fields to type into, and a `Window` owns its own input, so nothing in
## it can take the drawing keys. Built by hand rather than left to its own `_ready`, so the window the
## designer opens is the one this file has already wired to the menu.
func _build_pipeline_board() -> void:
	if _pipeline_board != null:
		return
	_pipeline_board = PipelineBoardScript.new()
	_pipeline_board.name = "PipelineBoard"
	add_child(_pipeline_board)
	# Build it here rather than leave it to its own `_ready`: the HUD reads the board's own words for
	# its menu line the moment the board exists, and a board that was only built once it was shown
	# would have nothing to say until somebody opened it.
	_pipeline_board.build()
	_pipeline_board.pipeline_changed.connect(_on_pipeline_changed)
	_pipeline_board.hide()


## Open the board. Unlike the estimate it needs no drawing: a pipeline is business data, and there is
## nowhere in it that a plan is measured.
func open_pipeline_board() -> void:
	if _pipeline_board == null:
		_build_pipeline_board()
	if _pipeline_board == null:
		return
	_pipeline_board.refresh()
	PageChromeScript.show_centred(_pipeline_board)
	# A window holds the keyboard while it is up; the moment it closes the drawing keys belong to the
	# drawing again.
	release_keyboard_focus(self)


func is_pipeline_board_open() -> bool:
	return _pipeline_board != null and _pipeline_board.visible


## What the Pipeline menu says on itself: the open pipeline, in the board's own words.
func _pipeline_text() -> String:
	if _pipeline_board == null:
		return "no open leads"
	return _pipeline_board.summary_text()


## A card moved or a lead was added: the menu line about the pipeline is now stale, and so is the
## report if it is open, because the figures about leads are the pipeline's own.
func _on_pipeline_changed() -> void:
	_refresh_analytics()
	_refresh_menus()


func _menu_pipeline_board(_entry: Dictionary) -> void:
	open_pipeline_board()


func _refresh_pipeline_menu() -> void:
	var named := _find_item(&"pipeline.info")
	if not named.is_empty():
		var popup: PopupMenu = named[0]
		popup.set_item_text(int(named[1]), _pipeline_text())

# --- the jobs and the crews --------------------------------------------------------------------


## The desk: the crews, the jobs and their days. Built by hand rather than left to its own `_ready`,
## so the desk the window is pointed at is the desk this file already wired to the menus.
##
## It is here in every scene because a crew and a job are business data and not drawing data. That is
## also why the desk is not rebuilt when the drawing changes: `make_job_from` records the estimate
## revision the job was contracted from, so a job made from one drawing is not confused by the next.
func _build_job_desk() -> void:
	if _job_desk != null:
		return
	_job_desk = JobDeskScript.new()


## The board: crews down the side, days across the top. Laid out like the pipeline board and for the
## same reasons - a `Window`, built by hand, and everything in it focus-free but the typed fields.
func _build_schedule_board() -> void:
	if _schedule_board != null:
		return
	if _job_desk == null:
		_build_job_desk()
	_schedule_board = ScheduleBoardScript.new()
	_schedule_board.name = "ScheduleBoard"
	add_child(_schedule_board)
	_schedule_board.build()
	_schedule_board.bind(_job_desk)
	_schedule_board.schedule_changed.connect(_on_schedule_changed)
	_schedule_board.hide()


## Open the board. Like the pipeline it needs no drawing: who works when is not on the plan.
func open_schedule_board() -> void:
	if _schedule_board == null:
		_build_schedule_board()
	if _schedule_board == null:
		return
	_schedule_board.bind(_job_desk)
	PageChromeScript.show_centred(_schedule_board)
	release_keyboard_focus(self)


func close_schedule_board() -> void:
	if _schedule_board != null:
		_schedule_board.hide()


func is_schedule_board_open() -> bool:
	return _schedule_board != null and _schedule_board.visible


## What the Jobs menu says on itself: the desk's own words, including its count of the clashes, and -
## once anything has actually been billed, or once the ledger has something wrong with it - what the
## ledger says, because an outstanding balance is the one number an office should not have to open a
## window to see. And, once anything has been handed over or wants a person, what the outbox says: a
## document that did not arrive is the other thing an office must not have to open a window to find out.
##
## A schedule that has been started and has billed nothing yet says **nothing** here: "0 invoices,
## $0.00 billed" is noise on the one line a person reads from across the room. The outbox says nothing
## for the same reason, unless it has something waiting or something stranded.
func _jobs_text() -> String:
	if _job_desk == null:
		return "no crews and no jobs yet"
	var line: String = _job_desk.describe()
	if (_billing_ledger != null and not (_billing_ledger.invoices.is_empty() and _billing_ledger.issues() == 0)):
		line = "%s, %s" % [line, _billing_ledger.describe()]
	if _ledger_desk != null and (_ledger_desk.count() > 0 or _ledger_desk.issues() > 0):
		line = "%s, %s" % [line, _ledger_desk.describe()]
	# A punch list and a warranty, once a job has either. A job nobody has started finishing says
	# nothing here, for the same reason a schedule with no invoices does.
	if _closeout_desk != null and not _closeout_desk.jobs_in_closeout().is_empty():
		line = "%s, %s" % [line, _closeout_desk.describe()]
	return line


## A job was started from the estimate. The estimate window does not hold jobs; this is where the
## hand-off lands, and the desk makes the job from the estimate the window handed over.
func _on_job_started(estimate: Estimate) -> void:
	if _job_desk == null:
		_build_job_desk()
	_job_desk.make_job_from(estimate)
	if _schedule_board != null:
		_schedule_board.refresh()
	if _cost_window != null:
		_cost_window.refresh()
	if _billing_window != null:
		_billing_window.refresh()
	if _closeout_window != null:
		_closeout_window.refresh()
	_refresh_analytics()
	_refresh_menus()


## A block was booked, moved or taken off: the menu line about the desk is stale.
func _on_schedule_changed() -> void:
	_refresh_menus()


## What a job has cost: the report, the orders and the change orders. Built by hand like the other two
## for the same reason - the desk the window is pointed at is the desk this file already wired to the
## menus - and it needs no drawing, because what a job has cost is not on the plan.
func _build_cost_window() -> void:
	if _cost_window != null:
		return
	if _job_desk == null:
		_build_job_desk()
	_cost_window = JobCostWindowScript.new()
	_cost_window.name = "CostWindow"
	add_child(_cost_window)
	_cost_window.build()
	_cost_window.bind(_job_desk)
	_cost_window.cost_changed.connect(_on_cost_changed)
	_cost_window.hide()


func open_cost_window() -> void:
	if _cost_window == null:
		_build_cost_window()
	if _cost_window == null:
		return
	_cost_window.bind(_job_desk)
	PageChromeScript.show_centred(_cost_window)
	release_keyboard_focus(self)


func close_cost_window() -> void:
	if _cost_window != null:
		_cost_window.hide()


func is_cost_window_open() -> bool:
	return _cost_window != null and _cost_window.visible


## An order was issued, received or closed, or a change order was answered: the menu line about the
## desk is stale, and so is the schedule board's summary if a job's money has moved under it.
func _on_cost_changed() -> void:
	if _schedule_board != null:
		_schedule_board.refresh()
	_refresh_analytics()
	_refresh_menus()


func _menu_cost_window(_entry: Dictionary) -> void:
	open_cost_window()


## What has been billed: the schedules, the invoices and the money received. Built by hand like the
## other windows for the same reason - the ledger is pointed at the desk this file already wired to the
## menus - and it needs no drawing, because what a job has been billed is not on the plan.
func _build_billing_ledger() -> void:
	if _billing_ledger != null:
		return
	if _job_desk == null:
		_build_job_desk()
	_billing_ledger = BillingDeskScript.new()
	_billing_ledger.bind(_job_desk)


func _build_billing_window() -> void:
	if _billing_window != null:
		return
	if _billing_ledger == null:
		_build_billing_ledger()
	_billing_window = BillingWindowScript.new()
	_billing_window.name = "BillingWindow"
	add_child(_billing_window)
	_billing_window.build()
	_billing_window.bind(_billing_ledger)
	_billing_window.billing_changed.connect(_on_billing_changed)
	_billing_window.hide()


func open_billing_window() -> void:
	if _billing_window == null:
		_build_billing_window()
	if _billing_window == null:
		return
	_billing_window.bind(_billing_ledger)
	PageChromeScript.show_centred(_billing_window)
	release_keyboard_focus(self)


func close_billing_window() -> void:
	if _billing_window != null:
		_billing_window.hide()


func is_billing_window_open() -> bool:
	return _billing_window != null and _billing_window.visible


## An invoice went out or was called back, a step was billed, or money arrived: the menu line about the
## desk is stale. Nothing on the job desk has moved - §8.4's billed figure is a number somebody states
## and this is a document - so the cost page is left where it is.
##
## **An invoice that has just gone out is handed to the ledger here** (REQ-B14: the push is queued when
## the document issues). The outbox is idempotent, so this is safe on every change to what has been
## billed, and a document that cannot be built for the chosen backend is refused by name rather than
## swallowed.
func _on_billing_changed() -> void:
	queue_invoices_for_ledger()
	_refresh_analytics()
	_refresh_menus()


func _menu_billing_window(_entry: Dictionary) -> void:
	open_billing_window()


## The outbox: what has been handed to a ledger and what each ledger said about it. Built by hand like
## the other pages for the same reason - the outbox is pointed at the billing ledger this file already
## wired to the menus - and it needs no drawing, because where a document has got to is not on the plan.
##
## The file backend comes from the desk itself and always works. The two hosted ledgers are registered
## here so the page can *offer* them and the office can state their address and token where the page
## keeps settings - nothing is invented, because an unconfigured backend offers no address, and nothing
## is posted to it until it is chosen.
func _build_ledger_desk() -> void:
	if _ledger_desk != null:
		return
	if _billing_ledger == null:
		_build_billing_ledger()
	_ledger_desk = LedgerDeskScript.new()
	_ledger_desk.bind(_billing_ledger)
	_ledger_desk.add_adapter(AkauntingLedgerScript.new())
	_ledger_desk.add_adapter(InvoiceNinjaLedgerScript.new())


func _build_ledger_window() -> void:
	if _ledger_window != null:
		return
	if _ledger_desk == null:
		_build_ledger_desk()
	_ledger_window = LedgerWindowScript.new()
	_ledger_window.name = "LedgerWindow"
	add_child(_ledger_window)
	_ledger_window.build()
	_ledger_window.bind(_ledger_desk)
	_ledger_window.ledger_changed.connect(_on_ledger_changed)
	_ledger_window.hide()


func open_ledger_window() -> void:
	if _ledger_window == null:
		_build_ledger_window()
	if _ledger_window == null:
		return
	_ledger_window.bind(_ledger_desk)
	PageChromeScript.show_centred(_ledger_window)
	release_keyboard_focus(self)


func close_ledger_window() -> void:
	if _ledger_window != null:
		_ledger_window.hide()


func is_ledger_window_open() -> bool:
	return _ledger_window != null and _ledger_window.visible


## A document was handed over, or the ledger was configured: the menu line about the outbox is stale.
## Nothing on the job desk or the billing ledger has moved - a push is not a document and not money - so
## the other two pages are left where they are.
func _on_ledger_changed() -> void:
	_refresh_menus()


func _menu_ledger_window(_entry: Dictionary) -> void:
	open_ledger_window()


func _menu_sync_window(_entry: Dictionary) -> void:
	open_sync_window()


## Finishing the job: the punch list, the hand-over date and the warranty on one page. Built by hand
## like the other pages for the same reason - the desk the window is pointed at is the desk this file
## already wired to the Jobs menu - and it needs no drawing, because a punch list is not on the plan.
func _build_closeout_desk() -> void:
	if _closeout_desk != null:
		return
	if _job_desk == null:
		_build_job_desk()
	_closeout_desk = CloseoutDeskScript.new()
	_closeout_desk.bind(_job_desk)


func _build_closeout_window() -> void:
	if _closeout_window != null:
		return
	if _closeout_desk == null:
		_build_closeout_desk()
	_closeout_window = CloseoutWindowScript.new()
	_closeout_window.name = "CloseoutWindow"
	add_child(_closeout_window)
	_closeout_window.build()
	_closeout_window.bind(_closeout_desk)
	_closeout_window.closeout_changed.connect(_on_closeout_changed)
	_closeout_window.hide()


func open_closeout_window() -> void:
	if _closeout_window == null:
		_build_closeout_window()
	if _closeout_window == null:
		return
	_closeout_window.bind(_closeout_desk)
	PageChromeScript.show_centred(_closeout_window)
	release_keyboard_focus(self)


func close_closeout_window() -> void:
	if _closeout_window != null:
		_closeout_window.hide()


func is_closeout_window_open() -> bool:
	return _closeout_window != null and _closeout_window.visible


## An item was raised, checked, taken off, stated or answered, or the hand-over date or the warranty
## changed: the menu line about the desk is stale. Nothing on the other pages has moved - a punch item
## is not money - so the four pages above this one are left where they are.
func _on_closeout_changed() -> void:
	_refresh_menus()


func _menu_closeout_window(_entry: Dictionary) -> void:
	open_closeout_window()


## The figures: the pipeline's win rate, the jobs' profitability, what is owed and how busy the crew is
## (spec §10). Built by hand like the other pages - the report is pointed at the three desks this file
## already wired to the menus - and it needs no drawing, because what the business is doing is not on
## the plan.
##
## The report holds no figures: it reads the records every time it is asked, so there is nothing to keep
## in step when a lead moves or an invoice goes out. What there is to do is read the open page again,
## which is what the change handlers below do.
func _build_analytics_report() -> void:
	if _analytics_report != null:
		return
	if _pipeline_board == null:
		_build_pipeline_board()
	if _job_desk == null:
		_build_job_desk()
	if _billing_ledger == null:
		_build_billing_ledger()
	_analytics_report = AnalyticsScript.new(_pipeline_board.pipeline, _job_desk, _billing_ledger)


func _build_analytics_window() -> void:
	if _analytics_window != null:
		return
	if _analytics_report == null:
		_build_analytics_report()
	_analytics_window = AnalyticsWindowScript.new()
	_analytics_window.name = "AnalyticsWindow"
	add_child(_analytics_window)
	_analytics_window.build()
	_analytics_window.bind(_analytics_report)
	_analytics_window.report_changed.connect(_on_analytics_changed)
	_analytics_window.hide()


## Bind the report to the three desks as they stand and open the page. **The binding is redone here**
## rather than only at build time, because the pipeline board's own pipeline is what the figures about
## leads read and a HUD built before the board existed would be reading nothing.
func open_analytics_window() -> void:
	if _analytics_window == null:
		_build_analytics_window()
	if _analytics_window == null:
		return
	_analytics_window.bind(_analytics_report)
	PageChromeScript.show_centred(_analytics_window)
	release_keyboard_focus(self)


func close_analytics_window() -> void:
	if _analytics_window != null:
		_analytics_window.hide()


func is_analytics_window_open() -> bool:
	return _analytics_window != null and _analytics_window.visible


## A working day was stated on the page, which is the only thing there a person decides rather than
## reads. Its own line is on the page; the menu has nothing new to say.
func _on_analytics_changed() -> void:
	_refresh_menus()


func _menu_analytics_window(_entry: Dictionary) -> void:
	open_analytics_window()


## A record moved under the report: the page reads the records again rather than being told what
## changed, because it holds no figures of its own. Only an open page is worth reading again.
func _refresh_analytics() -> void:
	if _analytics_window != null and _analytics_window.visible:
		_analytics_window.refresh()


## Hand every invoice the office has issued over to the chosen ledger. Called as part of issuing one -
## REQ-B14 wants the push queued when the document issues rather than remembered about later - and it is
## idempotent, because a document already in the outbox is one push already.
##
## A document that could not be built for this backend is refused **by name** and kept in the desk, so it
## shows up on the menu line and on the page rather than being swallowed here.
func queue_invoices_for_ledger() -> Dictionary:
	if _ledger_desk == null:
		_build_ledger_desk()
	if _ledger_desk == null:
		return { "ok": false, "reason": "there is no outbox", "queued": 0, "refused": 0 }
	var handed: Dictionary = _ledger_desk.queue_unhanded()
	if int(handed["queued"]) > 0 or int(handed["refused"]) > 0:
		_refresh_menus()
	return handed


func _menu_schedule_board(_entry: Dictionary) -> void:
	open_schedule_board()


func _refresh_jobs_menu() -> void:
	var named := _find_item(&"jobs.info")
	if not named.is_empty():
		var popup: PopupMenu = named[0]
		popup.set_item_text(int(named[1]), _jobs_text())

# --- the shared session --------------------------------------------------------------


## What the Team menu's own line says: who is in the room, in the session's words.
func _presence_text() -> String:
	if _presence == null:
		return "no session"
	return _presence.roster_text()


func _refresh_team_menu() -> void:
	var named := _find_item(&"team.info")
	if not named.is_empty():
		var popup: PopupMenu = named[0]
		popup.set_item_text(int(named[1]), _presence_text())


## The session changed - somebody joined or left, or it opened or closed - so the line about it is
## stale. A session is the one part of the bar that moves because somebody else did something.
func _on_presence_changed() -> void:
	_refresh_team_menu()


func _menu_start_session(_entry: Dictionary) -> void:
	if _presence == null:
		return
	_presence.start(PresenceScript.DEFAULT_ROOM, PresenceScript.local_name())


func _menu_leave_session(_entry: Dictionary) -> void:
	if _presence == null:
		return
	_presence.leave()


## Which drawing this peer has open, as a short name: the file's own name when it has one, and a
## plain phrase when it is not saved yet. A colleague sees "Backyard Design" rather than a path.
func _drawing_label() -> String:
	if _draft == null:
		return ""
	var where := String(_draft.drawing_path)
	if where != "":
		return where.get_file().get_basename()
	return "an unsaved drawing"


## The ground: the site's conditions and one statement per area of the plan.
##
## A `Window` like the library, and for the same reason - it has dropdowns in it, and `Root` is built
## focus-free so that nothing in the HUD can take the drawing keys. Built by hand rather than left to
## its own `_ready`, so that the window the designer opens is the window this file has already wired
## to the menu, the drawing and the planting check.
func _build_ground_window() -> void:
	if _ground_window != null:
		return
	_ground_window = GroundWindowScript.new()
	_ground_window.name = "GroundWindow"
	add_child(_ground_window)
	_ground_window.ground_changed.connect(_on_ground_changed)
	_ground_window.check_requested.connect(_on_ground_check_requested)
	_ground_window.hide()


## Open it, pointed at the drawing that is open now.
func open_ground_window() -> void:
	if _ground_window == null:
		return
	if _draft == null or _draft.document == null:
		return
	_ground_window.document = _draft.document
	_ground_window.refresh()
	PageChromeScript.show_centred(_ground_window)
	# A window holds the keyboard while it is up, which is exactly what a window is for; the moment
	# it closes the drawing keys belong to the drawing again.
	release_keyboard_focus(self)


func close_ground_window() -> void:
	if _ground_window != null:
		_ground_window.hide()
		_ground_window.say("")


## The drawing's layers: every layer, what it is for, and the two things done to one here - lock it
## against editing, or make it the layer new shapes are drawn on.
##
## A `Window` like the library and the ground window, for the same reason - it has a search box to type
## into, and a `Window` owns its own input, so nothing here can take the drawing's keys. Built by hand
## rather than left to its own `_ready`, so the window the designer opens is the one this file has
## already wired to the menu and to the drawing.
func _build_layer_window() -> void:
	if _layer_window != null:
		return
	_layer_window = LayerWindowScript.new()
	_layer_window.name = "LayerWindow"
	add_child(_layer_window)
	_layer_window.build()
	_layer_window.layers_changed.connect(_on_layers_changed)
	_layer_window.hide()


## Open it, pointed at the drawing that is open now.
func open_layer_window() -> void:
	if _layer_window == null:
		return
	if _draft == null or _draft.document == null:
		return
	_layer_window.bind(_draft)
	PageChromeScript.show_centred(_layer_window)
	release_keyboard_focus(self)


func close_layer_window() -> void:
	if _layer_window != null:
		_layer_window.hide()


func is_layer_window_open() -> bool:
	return _layer_window != null and _layer_window.visible


## A layer was locked, unlocked or made current: the drawing is redrawn through the document the
## dialog already changed, and whatever says which layer is current is now stale.
func _on_layers_changed() -> void:
	_refresh_menus()


## The business records' store, and the engine that syncs them with the office's service. The store is
## where a field change is written and the engine holds the queue and the conflicts; the page shows what
## the engine says. The one service this build offers is the HTTP transport, which the page configures -
## nothing is invented, and a device with no token has nowhere to sync to and says so.
func _build_sync_engine() -> void:
	if _sync_engine != null:
		return
	_sync_store = BizStoreScript.new()
	_sync_engine = BizSyncScript.new(_sync_store)
	_sync_engine.use_transport(BizHttpTransportScript.new())


## The sync page: what is waiting to go out, what wants a person, and where the two copies disagree.
##
## A `Window` like the other pages, for the same reason - it has fields to type the service's address
## and token into - and built by hand so the window the designer opens is the one this file has already
## wired to the engine.
func _build_sync_window() -> void:
	if _sync_window != null:
		return
	if _sync_engine == null:
		_build_sync_engine()
	_sync_window = SyncWindowScript.new()
	_sync_window.name = "SyncWindow"
	add_child(_sync_window)
	_sync_window.build()
	_sync_window.bind(_sync_engine)
	_sync_window.sync_changed.connect(_on_sync_changed)
	_sync_window.hide()


## Open it, pointed at the engine that is in hand.
func open_sync_window() -> void:
	if _sync_window == null:
		_build_sync_window()
	if _sync_window == null:
		return
	_sync_window.bind(_sync_engine)
	PageChromeScript.show_centred(_sync_window)
	release_keyboard_focus(self)


func close_sync_window() -> void:
	if _sync_window != null:
		_sync_window.hide()


func is_sync_window_open() -> bool:
	return _sync_window != null and _sync_window.visible


## A run, a settled conflict, or the service being configured: whatever reports on the queue is stale.
func _on_sync_changed() -> void:
	_refresh_menus()

# --- the sheet setup ------------------------------------------------------------------------


## Build the sheet window and wire every one of its intents to the controller. One door for all of
## them, because the window draws nothing and plots nothing: it announces what a person did, and this
## is the place that answers, so a sheet cannot be edited by one control and plotted by another.
func _build_sheet_window() -> void:
	if _sheet_window != null:
		return
	_sheet_window = SheetWindowScript.new()
	_sheet_window.name = "SheetWindow"
	add_child(_sheet_window)
	_sheet_window.field_changed.connect(_on_sheet_field_changed)
	_sheet_window.identity_changed.connect(_on_sheet_identity_changed)
	_sheet_window.sheet_added.connect(_on_sheet_added)
	_sheet_window.sheet_removed.connect(_on_sheet_removed)
	_sheet_window.sheet_selected.connect(_on_sheet_selected)
	_sheet_window.plot_requested.connect(_on_sheet_plot)
	_sheet_window.plot_set_requested.connect(_on_sheet_plot_set)
	_sheet_window.closed.connect(close_sheet_window)
	_sheet_window.hide()


## Open it on the drawing's own set. The live paper fields are written into the current sheet first, so
## the window shows what the drawing is actually set up as rather than what the set last held.
func open_sheet_window() -> void:
	if _sheet_window == null:
		return
	if _draft == null or _draft.document == null:
		return
	_draft.save_sheet()
	_refresh_sheet_window()
	PageChromeScript.show_centred(_sheet_window)
	release_keyboard_focus(self)


func close_sheet_window() -> void:
	if _sheet_window != null:
		_sheet_window.hide()
		_sheet_window.say("")


func is_sheet_window_open() -> bool:
	return _sheet_window != null and _sheet_window.visible


## What the window says about the drawing: the sheet in the form, and what the last plot did.
func sheet_status_text() -> String:
	if _sheet_window == null:
		return ""
	return _sheet_window.status_text()


func _refresh_sheet_window() -> void:
	if _sheet_window == null or _draft == null:
		return
	_sheet_window.set_identity(_draft.project_name, _draft.sheet_date)
	_sheet_window.set_sheets(_draft.sheet_rows())


## Everything the drawing says about itself is written where it belongs before a plot, so the sheet
## window is also refreshed after an edit: the row's description and the current sheet's marker both
## change when a field does.
func _on_sheet_field_changed(index: int, field: String, value: Variant) -> void:
	if _draft == null:
		return
	if not _draft.set_sheet_field(index, field, value):
		_sheet_window.say("that is not something a sheet can be set to")
	_refresh_sheet_window()


func _on_sheet_identity_changed(field: String, value: String) -> void:
	if _draft == null:
		return
	match field:
		"project":
			_draft.project_name = value
		"date":
			_draft.sheet_date = value
	_draft.save_sheet()


func _on_sheet_added() -> void:
	if _draft == null:
		return
	var added: int = _draft.add_sheet(_draft.drawing_title)
	# The form is moved onto the new sheet *after* the rows have been rebuilt: selecting it first looks
	# right and does nothing, because the window cannot select a row it has not been told about yet - and
	# then the sheet the designer types into is the one they were on, not the one they just added.
	_refresh_sheet_window()
	if added >= 0:
		_sheet_window.select(added)


func _on_sheet_removed(index: int) -> void:
	if _draft == null:
		return
	var removed: bool = _draft.remove_sheet(index)
	_refresh_sheet_window()
	if not removed:
		_sheet_window.say(_draft.last_message)
	else:
		_sheet_window.select(mini(index, _draft.sheet_set().count() - 1))


## Choosing a sheet chooses what is being plotted next, so the drawing's own paper fields follow it.
func _on_sheet_selected(index: int) -> void:
	if _draft == null:
		return
	_draft.load_sheet(index)
	_refresh_sheet_window()


func _on_sheet_plot(index: int) -> void:
	if _draft == null:
		return
	var path: String = _draft.plot_sheet(index, _planting_rows())
	# What the plotter said, and where the sheet went: a plot is reported by its file, because the only
	# thing a person does next with a sheet is open it.
	_sheet_window.say("%s -> %s" % [_draft.last_message, path] if not path.is_empty() else _draft.last_message)


func _on_sheet_plot_set() -> void:
	if _draft == null:
		return
	var written: Array[String] = _draft.plot_set(_planting_rows())
	_sheet_window.say(_draft.last_message)
	_refresh_sheet_window()
	# The list is what says which sheets went out; a set that plotted four of five should say so.
	if not written.is_empty():
		_sheet_window.say("%s (%s)" % [_draft.last_message, String(written[written.size() - 1])])


func _menu_sheet_setup(_entry: Dictionary) -> void:
	open_sheet_window()

# --- the history of the drawing -------------------------------------------------------


func _build_revision_window() -> void:
	if _revision_window != null:
		return
	_revision_window = RevisionWindowScript.new()
	_revision_window.name = "RevisionWindow"
	add_child(_revision_window)
	_revision_window.revision_recorded.connect(_on_revision_recorded)
	_revision_window.restore_requested.connect(_on_revision_restore)
	_revision_window.closed.connect(close_revision_window)
	_revision_window.hide()


## Open it on the drawing's own history. A revision can be recorded before a drawing has ever been
## saved - the controller keeps it in memory until it is - so the window opens for an unsaved drawing
## too, and its own status line says where the history is.
func open_revision_window() -> void:
	if _revision_window == null:
		return
	if _draft == null or _draft.document == null:
		return
	_refresh_revision_window()
	PageChromeScript.show_centred(_revision_window)
	release_keyboard_focus(self)


func close_revision_window() -> void:
	if _revision_window != null:
		_revision_window.hide()
		_revision_window.say("")


func is_revision_window_open() -> bool:
	return _revision_window != null and _revision_window.visible


## What the window says about the history: how many revisions are kept, and what the last act did.
func revision_status_text() -> String:
	if _revision_window == null:
		return ""
	return _revision_window.status_text()


func _refresh_revision_window() -> void:
	if _revision_window == null or _draft == null:
		return
	var state := "%s|%d|%d|%d" % [
		StoreScript.display_name(_draft.drawing_path),
		_draft.revisions.count(),
		_draft.revisions.dropped,
		_draft.document.gesture_serial(),
	]
	if state == _revision_state:
		return
	_revision_state = state
	_revision_window.set_identity(StoreScript.display_name(_draft.drawing_path), _draft.revisions.dropped)
	_revision_window.set_revisions(_draft.revision_rows())


## A revision recorded. The window has already emptied its message box; what comes back is where it went,
## which is the one thing the person cannot see from here.
func _on_revision_recorded(message: String) -> void:
	if _draft == null:
		return
	_draft.capture_revision(message, DraftRevisionLog.system_author())
	_refresh_revision_window()
	_revision_window.select(_draft.revisions.count() - 1)
	_revision_window.say(_draft.last_message)


## A revision put back. The drawing on screen changes, so everything that draws it is told: the canvas is
## refreshed by the controller, and the menu bar's own lines about the drawing may now be stale.
func _on_revision_restore(index: int) -> void:
	if _draft == null:
		return
	var restored: bool = _draft.restore_revision(index)
	_refresh_revision_window()
	_refresh_menus()
	_revision_window.say(_draft.last_message)
	if not restored:
		_revision_window.say(_draft.last_message)


func _menu_revisions(_entry: Dictionary) -> void:
	open_revision_window()


func is_ground_window_open() -> bool:
	return _ground_window != null and _ground_window.visible


## The ground changed in the window: the Site menu's line about it is now stale, and so is the ring
## around whatever plant is in hand.
func _on_ground_changed() -> void:
	_refresh_menus()


func _on_ground_check_requested() -> void:
	_menu_check_planting({ })


## Show the coverage report. It is a reading of the drawing, so it is opened rather than
## written to a log: a report nobody can see is not a report.
func _menu_site_report(_entry: Dictionary) -> void:
	open_site_report()


## Read a surveyor's file and show what was read. The file is not put on the drawing here: a
## survey is accepted by a person who has seen its checks, not by whoever pressed a menu entry.
func _menu_import_survey(_entry: Dictionary) -> void:
	open_survey_dialog()


## Point the browser at the catalogue, reading it only if it has never been read.
##
## `refresh` rather than `bind` once it is bound, because `bind` rebuilds the tag chips: what is
## ticked is a person's filter, and reopening the library must not throw it away.
func _refresh_plant_browser() -> void:
	if _plant_browser == null:
		return
	if _plant_browser.catalogue == null:
		_plant_browser.bind(plant_list())
	else:
		_plant_browser.refresh()


func _menu_plant_library(_entry: Dictionary) -> void:
	open_plant_browser()

# --- naming a plant by answering questions --------------------------------------------------

#
# The page is the person's half of the question "what is this plant": it asks what they can see and
# narrows the list until one is left. Everything about it that is not a page - which question, which
# answers, and what an answer leaves - is `PlantKey`'s, and this file owns only the window and the one
# thing a plant named this way has in common with a plant chosen from the library: it gets armed.


func _menu_plant_key(_entry: Dictionary) -> void:
	open_plant_key_window()


## Build the page once, the first time somebody asks for it. It reaches the catalogue rather than the
## scene, so there is nothing about the drawing to hand it and nothing to rebuild when the drawing
## changes - which is why it is not in the refresh ladder the drawing's own pages are in.
func _build_plant_key_window() -> void:
	if _plant_key_window != null:
		return
	_plant_key_window = PlantKeyWindowScript.new()
	_plant_key_window.name = "PlantKeyWindow"
	add_child(_plant_key_window)
	_plant_key_window.build()
	_plant_key_window.closed.connect(_on_plant_key_window_closed)
	_plant_key_window.species_chosen.connect(_on_plant_key_chosen)
	_plant_key_window.hide()


## Open it pointed at the one plant list, and at the bed the plant is going in.
##
## The bed is what the plan says the ground is like where the drawing's cursor last was, which is why the
## key is site-aware here rather than merely a filter over the catalogue: a designer asking "what can I
## plant in this bed" is asking a question the drawing can already partly answer. A scene with no drawing
## answers an empty spot, and the page then says the key is not narrowed to anything.
func open_plant_key_window() -> void:
	_build_plant_key_window()
	if _plant_key_window == null:
		return
	_plant_key_window.bind(plant_list())
	_plant_key_window.suit_to(view_controller.ground_at_cursor() if view_controller != null else { })
	PageChromeScript.show_centred(_plant_key_window)
	release_keyboard_focus(self)


## Settle which of the plants a photograph offered it is: the key, narrowed to just those.
##
## The capture page is put away first, because the key is opened over it and two pages up at once is a
## keyboard nobody knows the owner of - and the photograph's own half of the work is finished, which is why
## the invitation lived on that page.
##
## A reading that resolved to nothing leaves the key on the whole list rather than emptying it, and the
## page's own line says so: `PlantKey.among` skips the ids this list does not have.
func _on_capture_key_requested(ids: Array[StringName]) -> void:
	close_capture_window()
	open_plant_key_window()
	if _plant_key_window != null:
		_plant_key_window.from_a_shortlist(ids, "photograph")


func close_plant_key_window() -> void:
	if _plant_key_window != null and _plant_key_window.visible:
		_plant_key_window.request_close()


func is_plant_key_window_open() -> bool:
	return _plant_key_window != null and _plant_key_window.visible


func _on_plant_key_window_closed() -> void:
	_refresh_menus()


## A plant named by working through the key is armed exactly as one chosen from the library or the
## palette is - `_arm_planting` is the one door onto that - so nothing downstream can tell which of the
## three a plant came through.
##
## When there is nowhere to plant it the page has already closed, so this is the only place left that can
## say so; a person told which plant it is and then left with nothing happening would think it had failed.
func _on_plant_key_chosen(species_id: StringName) -> void:
	if _arm_planting(species_id):
		return
	var species: PlantSpecies = plant_list().get_species(species_id)
	var named: String = species.display_name() if species != null else String(species_id)
	_plant_say("%s is named, but nothing here can be planted yet: open a drawing with a yard first." % named)


## Put the last chosen plant back in hand. With nothing chosen yet, the library is what is wanted,
## which is a better answer than a command that does nothing.
func _menu_plant_place(_entry: Dictionary) -> void:
	if _plant_chosen.is_empty():
		open_plant_browser()
		return
	_arm_planting(_plant_chosen)


func _menu_stop_planting(_entry: Dictionary) -> void:
	if view_controller != null:
		view_controller.stop_planting()


## Write what is planted onto the drawing as labels: one per species, standing at the
## middle of its group.
##
## The positions come from the plants themselves rather than from a list somebody keeps
## in step, so a label cannot describe a group that has moved. The name printed is the
## one the library shows, because a plan and a nursery list that call a plant different
## things are two documents about two gardens.
func _menu_label_plants(_entry: Dictionary) -> void:
	if _draft == null or view_controller == null:
		return
	var catalogue := plant_list()
	var plants: Array = []
	for node: Node3D in PlantPlacementScript.planted(view_controller.yard):
		var species_id := PlantPlacementScript.species_of(node)
		var species: PlantSpecies = null if catalogue == null else catalogue.get_species(species_id)
		var printed := "" if species == null else species.display_name()
		plants.append(
			{
				"species": species_id,
				"name": printed,
				"position": Vector2(node.global_position.x, node.global_position.z),
			}
		)
	var wanted := PlantLabelsScript.labels_for(plants)
	var reason := String(wanted.get("reason", ""))
	if not reason.is_empty():
		_draft.note(reason)
		return
	_draft.label_planting(wanted["labels"])

# --- what the ground is like, and what that means for the planting -----------------------


## Open the ground window: the site's conditions and one statement per area of the plan.
func _menu_ground_window(_entry: Dictionary) -> void:
	open_ground_window()


func _menu_layer_window(_entry: Dictionary) -> void:
	open_layer_window()


## Draw a ground zone: ground nothing on the plan outlines - a frost pocket, a strip of shade, a wet
## corner. It takes the polygon tool for one closed ring, and the ring becomes a zone rather than an
## entity, so the plan is untouched and the map holds the outline.
func _menu_draw_ground_zone(_entry: Dictionary) -> void:
	if _draft == null:
		return
	if view_controller != null and view_controller.is_planting():
		view_controller.stop_planting()
	_draft.begin_ground_zone()


## Ask the drawing what it already knows about the ground: a building is shade, a hard surface is hot
## and dry. Nothing else is read, because nothing else on a plan is a fact about the ground rather
## than an intention about the design - and what is not read is named in the menu, so a grey ring
## everywhere has an answer.
func _menu_read_ground(_entry: Dictionary) -> void:
	var map: ZoneMapScript = _ground_map()
	if map == null:
		return
	var document: DraftDocument = _draft.document
	var count: int = document.read_environment_from_drawing()
	if count <= 0:
		_plant_say("the drawing has no buildings or hard surfaces on it, so it says nothing about the ground")
		return
	_plant_say("read %d area%s of ground from the drawing" % [count, "" if count == 1 else "s"])
	_refresh_menus()


## Report on the planting that is already in the ground: which plants the plan's own conditions say
## are in the wrong place.
##
## The answer arrives in the library's status line because it is a list, and because the library is
## where a designer goes to do something about it. The window is opened: a report nobody can see is
## not a report, and the ring at the cursor only ever tells you about the plant in your hand.
func _menu_check_planting(_entry: Dictionary) -> void:
	var yard: Node3D = view_controller.yard if view_controller != null else null
	var report: Dictionary = PlantSuitabilityScript.audit(plant_list(), yard, _ground_map())
	var lines: Array[String] = PlantSuitabilityScript.audit_lines(report)
	var text: String = String(report["text"])
	if not lines.is_empty():
		text = "%s   %s" % [text, " | ".join(lines)]
	open_plant_browser()
	_plant_say(text)


func _menu_plant_import(_entry: Dictionary) -> void:
	if _plant_import_dialog != null:
		_plant_import_dialog.popup_centered_ratio(0.7)


func _menu_plant_export(_entry: Dictionary) -> void:
	if _plant_export_dialog != null:
		_plant_export_dialog.current_dir = PlantCatalogueScript.DEFAULT_PATH.get_base_dir()
		_plant_export_dialog.popup_centered_ratio(0.7)


## The browser's two buttons reach the same commands the menu does, through these: a menu entry
## takes the entry that was pressed and a button has no such thing to pass, so the two doors are
## kept and the work stays in one place.
func _on_plant_import_requested() -> void:
	_menu_plant_import({ })


func _on_plant_export_requested() -> void:
	_menu_plant_export({ })


## Choosing a plant arms it and closes the library: the very next click is on the plan, which is
## where the plant was going. It stays armed afterwards, so a bed is a dozen clicks rather than a
## dozen trips back here.
func _on_plant_chosen(species_id: StringName) -> void:
	if not _arm_planting(species_id):
		return
	close_plant_browser()


func _arm_planting(species_id: StringName) -> bool:
	if view_controller == null or not view_controller.arm_planting(plant_list(), species_id):
		return false
	_plant_chosen = species_id
	# Planting happens on the plan, and a click in the ground view is not a click on the plan.
	if view_controller.mode == ViewController.ViewMode.GROUND:
		view_controller.show_mode(ViewController.ViewMode.PLAN_2D)
	return true


func _on_plant_import_chosen(path: String) -> void:
	var catalogue: PlantCatalogue = plant_list()
	var report: Dictionary = catalogue.import_json(path, false)
	if not bool(report["ok"]):
		_plant_say(String(report["reason"]))
		return
	# The catalogue a person has just added to is the catalogue from now on, so it is written: an
	# import that lived only in memory would be gone the next time the program opened.
	var written: Dictionary = catalogue.save_to()
	if not bool(written["ok"]):
		_plant_say(String(written["reason"]))
		return
	var refused: Array = report["refused"]
	var words: String = "imported %d new, %d replaced" % [int(report["added"]), int(report["replaced"])]
	if not refused.is_empty():
		words += ", %d refused" % refused.size()
	_refresh_plant_browser()
	open_plant_browser()
	_plant_say(words)
	release_keyboard_focus(self)


func _on_plant_export_chosen(path: String) -> void:
	var target: String = path if path.ends_with(".json") else path + ".json"
	var written: Dictionary = plant_list().export_json(target)
	if not bool(written["ok"]):
		_plant_say(String(written["reason"]))
		return
	# The species only: a collection is one person's list of plants, and a list sent to a nursery is
	# the plants themselves.
	open_plant_browser()
	_plant_say("wrote %d species to %s" % [int(written["count"]), target])
	release_keyboard_focus(self)


func _plant_say(text: String) -> void:
	if _plant_browser != null:
		_plant_browser.set_status(text)


## The live part of the Site menu: the line describing what the ground is stated to be. The radios
## need nothing here - the snapshot drives those - but a sentence derived from a map has to be
## written out, in the same way the File menu writes out which drawing is open.
func _refresh_site_menu() -> void:
	var named := _find_item(&"site.ground")
	if not named.is_empty():
		var popup: PopupMenu = named[0]
		popup.set_item_text(int(named[1]), _ground_text())
	var graded := _find_item(&"site.grading")
	if not graded.is_empty():
		var graded_popup: PopupMenu = graded[0]
		graded_popup.set_item_text(int(graded[1]), _grading_text())
	var season := _find_item(&"site.season")
	if not season.is_empty():
		var season_popup: PopupMenu = season[0]
		season_popup.set_item_text(int(season[1]), _season_text())


## The live part of the Water menu: the line saying what this drawing is watered by.
func _refresh_water_menu() -> void:
	var named := _find_item(&"water.info")
	if not named.is_empty():
		var popup: PopupMenu = named[0]
		popup.set_item_text(int(named[1]), _water_text())


## The live part of the Light menu: the line saying what this drawing is lit by.
func _refresh_light_menu() -> void:
	var named := _find_item(&"light.info")
	if not named.is_empty():
		var popup: PopupMenu = named[0]
		popup.set_item_text(int(named[1]), _light_text())


## The live part of the Estimate menu: the line saying what has been measured and what it comes to.
func _refresh_estimate_menu() -> void:
	var named := _find_item(&"estimate.info")
	if not named.is_empty():
		var popup: PopupMenu = named[0]
		popup.set_item_text(int(named[1]), _estimate_text())


## The two live parts of the Plant menu: the line describing the list, and the one entry that only
## means something while a plant is in hand.
func _refresh_plant_menu() -> void:
	var named := _find_item(&"plant.info")
	if not named.is_empty():
		var popup: PopupMenu = named[0]
		popup.set_item_text(int(named[1]), plant_state_text())
	var stop := _find_item(&"plant.stop")
	if not stop.is_empty():
		var stop_popup: PopupMenu = stop[0]
		stop_popup.set_item_disabled(int(stop[1]), view_controller == null or not view_controller.is_planting())

# --- the front door -------------------------------------------------------------------------------


## Build the doorway and the pages the doorway owns.
##
## The sheet is a rectangle over everything the design suite owns - the furnished yard, the tool palette and
## the panels - because a person who has not yet said what they came here to do should be looking at the
## choice and not at a garden that looks like somebody else loaded it. The door and the begin-a-drawing page
## are `Window`s like every other page here, so each owns its own keyboard and takes none of the drawing's.
func _build_start_window() -> void:
	if _start_window != null:
		return
	# The sheet is drawn only when there is a `Root` to hang it on: a bare HUD built off-tree - which is
	# how the suite holds the doorway's decisions - has no canvas and no drawing board to hide.
	var root: Control = get_node_or_null(^"Root") as Control
	if root != null:
		_build_door_screen(root)

	_start_window = StartWindowScript.new()
	_start_window.name = "StartWindow"
	_start_window.chosen.connect(_on_start_chosen)
	_start_window.closed.connect(_on_start_window_closed)
	add_child(_start_window)
	_start_window.build()
	_start_window.hide()
	# The door is built here, when it is first opened, rather than at launch - so the Escape pass has to be
	# run again now that there is a page for it to put a closer inside.
	_let_escape_close_pages()


## The opaque sheet the two doorway pages stand on: a rectangle over everything the design suite owns, so
## a person who has not yet said what they came here to do is looking at the choice rather than at a garden
## that appears to have been loaded for them.
func _build_door_screen(root: Control) -> void:
	if _front_door_backdrop != null:
		return
	_front_door_backdrop = ColorRect.new()
	_front_door_backdrop.name = "StartBackdrop"
	_front_door_backdrop.color = StartChoicesScript.SCREEN
	_front_door_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_front_door_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_front_door_backdrop.visible = false
	root.add_child(_front_door_backdrop)


## Stand the door, over its sheet. Used at a launch that has nothing behind it and by anything that wants
## the doorway back - the camera being closed onto it, most of all.
func open_the_front_door() -> void:
	_build_start_window()
	if _start_window == null:
		return
	PageChromeScript.show_centred(_start_window)
	_sync_door_screen()
	release_keyboard_focus(self)


func is_front_door_open() -> bool:
	return _start_window != null and _start_window.visible


## A choice was taken on the door: the drawing board asks how the drawing begins, and the camera opens over
## the door. Neither is a mode - each shows a page, and the drawing board is the same either way.
func _on_start_chosen(id: StringName) -> void:
	if id == StartChoicesScript.CAMERA:
		open_camera_window()
		return
	if id == StartChoicesScript.DESIGN:
		open_start_drawing_window()
		return


func _on_start_window_closed() -> void:
	_sync_door_screen()
	_refresh_menus()


## The sheet stands exactly while one of the two doorway pages is up - the door or the begin page - so the
## furnished board behind is hidden for the whole doorway and revealed the moment the last page goes.
func _sync_door_screen() -> void:
	if _front_door_backdrop != null:
		_front_door_backdrop.visible = is_the_doorway_up()
	# The window's shape is asked for again whenever the doorway comes or goes: the doorway follows the
	# phone and the board keeps its own answer, so the two minutes either side of this call want two
	# different things. On a desk nothing is asked, because nothing would happen.
	var shape: StringName = the_shape_for_the_window()
	_say_what_the_window_was_asked_for(&"doorway", shape)
	OrientationChoiceScript.apply(shape)


## Say what the window is being asked for, where a person driving the phone can read it:
## `adb logcat -s godot | grep ORIENT`. The wording is `OrientationChoice.report_words`'s, so what is printed
## and what a test holds cannot come apart; whether to say it at all is `HudProbe.on()`'s, which is the one
## owner of the build question and has no switch of its own here.
func _say_what_the_window_was_asked_for(why: StringName, shape: StringName) -> void:
	if not HudProbeScript.on():
		return
	print(
		OrientationChoiceScript.report_words(why, shape, is_the_doorway_up(), OrientationChoiceScript.can_turn_here())
	)


## Build the begin-a-drawing page: the four honest ways to start, offered once the board is chosen.
func _build_start_drawing_window() -> void:
	if _start_drawing_window != null:
		return
	_start_drawing_window = StartDrawingWindowScript.new()
	_start_drawing_window.name = "StartDrawingWindow"
	_start_drawing_window.chosen.connect(_on_start_drawing_chosen)
	_start_drawing_window.recent_chosen.connect(_on_start_drawing_recent)
	_start_drawing_window.closed.connect(_on_start_drawing_closed)
	add_child(_start_drawing_window)
	_start_drawing_window.build()
	_start_drawing_window.hide()
	# Built late like the front door, so the Escape pass runs again over the page there is now.
	_let_escape_close_pages()


func open_start_drawing_window() -> void:
	_build_start_drawing_window()
	if _start_drawing_window == null:
		return
	# **The recent list has to be built as the array it is declared to be.** A ternary whose arms are an untyped
	# `[]` and a typed `Array[String]` gives an *untyped* `Array`, and assigning that to `Array[String]` fails at run
	# time - the value stays empty and the page lists nothing. Found by `tools/phone_touch_sweep.gd`'s first run,
	# 2026-11-14, as a runtime error beside the sweep's own report; it had been there since the door was built, and
	# an error nobody can see in a page that simply looks empty is the quietest kind.
	var paths: Array[String] = []
	if _draft != null:
		paths = _draft.recent_drawings()
	_start_drawing_window.bind_recent(paths)
	PageChromeScript.show_centred(_start_drawing_window)
	_sync_door_screen()
	release_keyboard_focus(self)


func is_start_drawing_window_open() -> bool:
	return _start_drawing_window != null and _start_drawing_window.visible


## Whether **either** doorway page is standing over the board: the front door, or the begin-a-drawing page it
## opens when the drawing board is chosen. One question, because they are one thing to anything outside - the
## sheet behind them covers the same board either way - and the pair was written out twice before this.
func is_the_doorway_up() -> bool:
	return is_front_door_open() or is_start_drawing_window_open()


## A way to begin was taken. Each runs the same handler its File menu entry runs, so New here and
## File > New drawing are one action rather than two that can drift apart.
func _on_start_drawing_chosen(id: StringName) -> void:
	if id == StartDrawingScript.NEW:
		_menu_new_drawing({ })
	elif id == StartDrawingScript.OPEN:
		_menu_open_drawing({ })
	elif id == StartDrawingScript.EXAMPLE:
		draw_the_example()
	# Whichever way was taken, the flat plan comes forward: the board behind the doorway was the furnished
	# overhead view, and a drawing just begun should be read as a sheet rather than as that.
	_show_the_plan()
	_sync_door_screen()


## A remembered drawing was chosen by its path, which is the same door File > Open recent uses.
func _on_start_drawing_recent(path: String) -> void:
	_pending_path = path
	_guard_unsaved(&"open")
	_sync_door_screen()


func _on_start_drawing_closed() -> void:
	_sync_door_screen()
	_refresh_menus()


## Build the camera page. It stands over the door rather than replacing it, so a photograph taken from the
## doorway can be closed and another taken, and the door is still there to lead into the drawing.
func _build_camera_window() -> void:
	if _camera_window != null:
		return
	_camera_window = CameraWindowScript.new()
	_camera_window.name = "CameraWindow"
	_camera_window.closed.connect(_on_camera_window_closed)
	add_child(_camera_window)
	_camera_window.build()
	_camera_window.hide()
	# Built late like the two doors, so the Escape pass runs again over the page there is now.
	_let_escape_close_pages()


func open_camera_window() -> void:
	_build_camera_window()
	if _camera_window == null:
		return
	# What is behind the camera is known before the page is shown, because the way out is named for it.
	_camera_window.show_over(behind_the_camera())
	_camera_window.open()
	_place_the_camera()
	_sync_door_screen()
	release_keyboard_focus(self)


## What the camera is standing over, so its way out names the thing a person goes back to. The doorway is
## asked rather than a drawing being looked for: the camera opens from the door as well as from a drawing,
## and the door is the one reading that already knows which of the two is standing.
func behind_the_camera() -> StringName:
	if the_doorway_is_up():
		return CameraWindowScript.BEHIND_THE_DOOR
	return CameraWindowScript.BEHIND_A_DRAWING


## Put the camera page where it belongs: over the whole room on a phone, where the viewfinder is the thing
## being aimed, and centred like every other page on a desk.
##
## One door for the placing, so that opening the camera and having the room change shape under it cannot put
## it in two different places - which is how a page ends up half a title bar off the top of a phone.
func _place_the_camera() -> void:
	if _camera_window == null:
		return
	# The page's own door, rather than the answer worked out again here: how a camera wants to be placed is
	# the camera's to say, and the capture page opens the same page through the same one.
	CameraWindowScript.place(_camera_window)


func close_camera_window() -> void:
	if _camera_window != null and _camera_window.visible:
		_camera_window.request_close()


## Whether a camera is standing up, whichever of the two doors onto one opened it.
##
## There is one camera page and two doors onto it: the HUD's own, and the one the capture page keeps. The
## window follows the phone while a camera is up, so this question has to be true of both. Asking it of one
## instance is how a phone held upright over a wide board got a landscape viewfinder from the other door.
func is_camera_window_open() -> bool:
	if _camera_window != null and _camera_window.visible:
		return true
	return _capture_window != null and _capture_window.camera_is_open()


func _on_camera_window_closed() -> void:
	_sync_door_screen()
	_refresh_menus()


## The capture page's camera has come or gone, so what the window is asked for is asked again: the phone
## follows itself while a camera is up, and the drawing's own answer is asked for again afterwards.
func _on_capture_camera_changed(_open: bool) -> void:
	_sync_door_screen()


## Draw the example garden onto the drawing in hand, through the controller's own door onto it.
func draw_the_example() -> void:
	if _draft == null:
		return
	_draft.draw_the_example()
	# The example *is* the shipped garden, so its site comes back with it - the one thing besides the
	# View menu's own tick that shows the scenery.
	if view_controller != null:
		view_controller.set_site_shown(true)

# --- which way up the window is ------------------------------------------------------------------


## Whether a doorway page is up: the front door or the begin-a-drawing page it leads to. These are the two
## pages that stand on the doorway sheet before there is a drawing, and the window follows the phone while
## either is up rather than sitting on the board's own wide answer.
func the_doorway_is_up() -> bool:
	return is_front_door_open() or is_start_drawing_window_open()


## What the window should be asked for: the hold of a page that is not a plan while one of those is up, and
## the board's kept answer the rest of the time. The one answer is handed in, so a phone is asked for its
## shape once rather than twice in the same breath.
##
## The camera counts with the doorway's two pages. None of the three is a plan drawn along a wide screen, and
## the camera is the one where it shows most: a viewfinder held the way a wide board is held is a picture of a
## plant lying on its side, which is what a phone held upright over a landscape board used to get.
func the_shape_for_the_window() -> StringName:
	return OrientationChoiceScript.for_the_window(the_doorway_is_up() or is_camera_window_open(), _orientation)


## The pages a change of the window's shape has to put back where they belong: every page in a `Window`, and
## the doorway's pages beside them - the front door answers its own Escape and so is not in
## `pages_in_windows`, but it still stands on the same room and still has to be re-placed when it changes.
func _pages_that_can_be_up() -> Array[Window]:
	var pages: Array[Window] = pages_in_windows()
	for door: Window in [_start_window, _start_drawing_window, _camera_window]:
		if door != null:
			pages.append(door)
	return pages


## Which of those pages are actually up, so a change of shape reaches only what is standing.
func _pages_that_are_up() -> Array[Window]:
	var up: Array[Window] = []
	for page: Window in _pages_that_can_be_up():
		if page != null and page.visible:
			up.append(page)
	return up


## The room has changed shape: state the chrome that is worked out from it, then put every page still up back
## where it belongs. `show_centred` is a position rather than an anchor, so without this a page that is up
## through a turn (or a resize, or the editor's pane changing size) keeps the place it was given for the old
## room. Only the place is asked for again - not a second keyboard, and not a second finger-sizing.
##
## **The chrome is sized from the room too, and this is the one door that says so - startup and a turn alike.**
## The bar's lift clear of the device's own band is a reading of the room, and it used to be taken once, as this
## HUD started: measured on the A16W, the block taken lying down asks for nothing and the one taken standing
## shows the three view buttons **81 px inside the band the camera keeps**, their middles inside it - the very
## fault `lift_the_top_bar_by` exists to stop, on the one shape that was never re-asked. The strip no page may
## use and the palette's own ground both hang off the bar's foot, so they are re-stated here as well, in the one
## order that cannot disagree with itself: the bar is lifted, the foot line is given the ground the device keeps
## below it, the strip is read off the bar's new foot, and then the pages are placed by it. **The foot line comes
## before the palette** because the column's foot is held off the plate's top: a plate moved after the column
## was placed would leave the last of its rows standing in the band the plate had just cleared.
##
## The palette's left ground goes through its one door, deferred, because the placement must land *after* the
## layout that changed. The band arrives when the phone turns or the layout is rebuilt rather than when the
## foot plate moves, which is why calling that door only from the plate's own trigger missed it entirely
## (measured 2026-11-18: the palette stood 55 px inside the camera band on a build that contained the fix).
func _the_canvas_changed_shape() -> void:
	lift_the_top_bar_clear_of_the_device()
	give_the_foot_line_clear_of_the_device()
	_state_the_strip_the_pages_may_not_use()
	place_the_left_column_for_a_device.call_deferred()
	for page: Window in _pages_that_are_up():
		# The camera fills the room on a phone rather than sitting in the middle of it, so it is put back
		# through its own door: a viewfinder re-placed as a centred page would shrink the moment the phone
		# was turned under it.
		if page == _camera_window:
			_place_the_camera()
			continue
		if page == _capture_window and _capture_window.camera_is_open():
			# The capture page's camera is not itself one of the pages walked here, because a camera that has
			# to take the whole room hangs where the room is rather than inside a page - no walk of this HUD's
			# children finds it. So the page is put back and its camera is placed through the same one door.
			PageChromeScript.placed_again(page)
			CameraWindowScript.place(_capture_window.camera_window())
			continue
		PageChromeScript.placed_again(page)
