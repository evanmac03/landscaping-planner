class_name EstimateWindow
extends Window
## The takeoff and the estimate: what the plan measures, what it prices at, and what goes out.
##
## The four business engines were built and tested before anything could reach them (spec §14 phases
## 0-3). This is the reach: a `Window`, like the plant library and the ground window, because it has
## dropdowns and a field to type a customer's name into, and `Root` is built focus-free so that
## nothing in this HUD can take the drawing keys.
##
## ## Why tabs
##
## A proposal is three tables of different shapes - what the plan measures, what that is priced at,
## and the price list it was priced from - and stacking them would be a window 1300 pixels tall on a
## 900 pixel screen, which is a window whose bottom third cannot be read. So they are tabs, with the
## three things that are true of all of them (take off, check, write) above, and the one thing that
## ends the job (who it goes to, and sending it) below.
##
## ## What it does not do
##
## It does not *make* an estimate line by hand, and it does not edit a price. A price is a fact about
## a business, and the cost book is where facts about a business live; a panel that let somebody
## retype a rate inside a proposal would be a second price list, in a file nobody could find. The
## quantities are the drawing, the prices are the book, and the proposal is what the two come to.
##
## It shows the cost book rather than editing it - phase 11 of the business spec is a cost-book editor
## as a **dock**, which is where editing a table belongs, not in the window that quotes from it.

const DeskScript := preload("res://scripts/biz/estimate_desk.gd")
const BookScript := preload("res://scripts/biz/cost_book.gd")
const TaxScript := preload("res://scripts/biz/tax.gd")
const ItemScript := preload("res://scripts/biz/cost_item.gd")

## The estimate changed: take off, re-price, send or revise. The HUD's menu line about it is stale.
signal estimate_changed()
## A job was started from the estimate, and here it is. The window does not hold the job: jobs and
## crews belong to the job desk, and a window that kept its own copy would be a second place a job
## could live. So it hands the estimate over and forgets it.
signal job_started(estimate: Estimate)
## The window was closed by its own close button.
signal closed()

## Fits on a 900 pixel screen with room to spare, and measured rather than guessed: the ground
## window's first version was 640 tall and lost its bottom row of buttons off the edge.
const SIZE := Vector2i(900, 700)

## The tabs, in the order a person works: measure, price, then look up where a price came from.
const TABS: Array[String] = ["Takeoff", "Proposal", "Cost book"]

## How many lines of each table to show before the list scrolls. A list is a viewport, not a report:
## the proposal itself is written to a file, where it can be as long as it is.
const LIST_HEIGHT := 240

## The desk: the drawing, the book, the takeoff and the estimate. Owned here, and read by the HUD for
## the one line its menu says about where the job stands.
var desk: DeskScript = null

var _tabs: TabContainer = null
## Whether the book has been looked for. Read once, because a refresh must not be the thing that
## retries a failed load and overwrites the status with the same complaint.
var _book_tried: bool = false
var _plan_status: Label = null
var _takeoff_list: ItemList = null
var _takeoff_note: Label = null
## The depth row under the takeoff: which of the drawing's layers a depth is stated for, how deep, and
## the one thing a person consults - the takeoff line for it, which changes from a flat measure to a
## cubic one as soon as the depth is stated.
var _depth_row: HBoxContainer = null
var _depth_layer: OptionButton = null
var _depth_mm: SpinBox = null
var _depth_button: Button = null
## The layers offered in `_depth_layer`, in the order the items were added, because an OptionButton
## holds text and these are StringNames - `desk.surface_layers()` is the source.
var _depth_layers: Array[StringName] = []
var _line_list: ItemList = null
var _book_list: ItemList = null
var _book_note: Label = null
var _totals: Label = null
var _tax_row: HBoxContainer = null
var _tax_option: OptionButton = null
var _recipient: LineEdit = null
var _send_button: Button = null
var _revision_button: Button = null
var _start_job_button: Button = null
var _status: Label = null


func _init() -> void:
	title = "The takeoff and the estimate"
	min_size = SIZE
	exclusive = false
	close_requested.connect(_on_close_requested)


func _ready() -> void:
	if _tabs == null:
		build()


# --- building --------------------------------------------------------------------------------


## Build the whole window by hand. Idempotent, and callable off-tree so a test can drive the same
## controls the program shows.
func build() -> void:
	if _tabs != null:
		return
	desk = DeskScript.new()
	var column := VBoxContainer.new()
	column.name = "Column"
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 8)
	add_child(column)

	_plan_status = Label.new()
	_plan_status.name = "PlanStatus"
	_plan_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_plan_status.custom_minimum_size = Vector2(0, 40)
	column.add_child(_plan_status)

	var actions := HBoxContainer.new()
	actions.name = "Actions"
	actions.add_theme_constant_override("separation", 6)
	column.add_child(actions)
	actions.add_child(_button("Take off the plan", "_on_take_off"))
	actions.add_child(_button("Check the numbers", "_on_check"))
	actions.add_child(_button("Write the proposal", "_on_write_proposal"))

	_tabs = TabContainer.new()
	_tabs.name = "Tabs"
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.custom_minimum_size = Vector2(0, 330)
	column.add_child(_tabs)
	for tab_name: String in TABS:
		var page := VBoxContainer.new()
		# A `TabContainer` takes its tab's title from the child's name, so the page is named
		# exactly what the tab should say. A space inside a node name is legal; a title that did
		# not match its own page would be a tab nobody could select by name.
		page.name = tab_name
		page.add_theme_constant_override("separation", 4)
		_tabs.add_child(page)
	_build_takeoff_tab(_tabs.get_child(0) as VBoxContainer)
	_build_proposal_tab(_tabs.get_child(1) as VBoxContainer)
	_build_book_tab(_tabs.get_child(2) as VBoxContainer)

	var send_row := HBoxContainer.new()
	send_row.name = "SendRow"
	send_row.add_theme_constant_override("separation", 6)
	column.add_child(send_row)
	var for_label := Label.new()
	for_label.name = "RecipientLabel"
	for_label.text = "for"
	send_row.add_child(for_label)
	_recipient = LineEdit.new()
	_recipient.name = "Recipient"
	_recipient.placeholder_text = "the customer's name"
	_recipient.custom_minimum_size = Vector2(260, 0)
	send_row.add_child(_recipient)
	_send_button = _button("Send it", "_on_send")
	send_row.add_child(_send_button)
	_revision_button = _button("Start a revision", "_on_revision")
	send_row.add_child(_revision_button)
	# A proposal that has gone and come back won is a job, and a job is where crews, days and time
	# belong. This is the one door between the estimating half of the business and the doing half, and
	# it is here rather than in a menu because the estimate is what makes a job possible.
	_start_job_button = _button("Start a job from it", "_on_start_job")
	_start_job_button.name = "StartJob"
	send_row.add_child(_start_job_button)

	_status = Label.new()
	_status.name = "Status"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Room for three lines, which is what the longest thing here says (what sending did, and that the
	# revision which went out is still the one on the customer's desk): a label shorter than its own
	# text spills over the row above it, which is how the first version of this looked.
	_status.custom_minimum_size = Vector2(0, 62)
	column.add_child(_status)


func _build_takeoff_tab(page: VBoxContainer) -> void:
	_takeoff_note = _note("")
	page.add_child(_takeoff_note)
	_takeoff_list = _list("TakeoffLines")
	page.add_child(_takeoff_list)
	_build_depth_row(page)


## The depth row: the one fact a drawing cannot show, and the only reason a takeoff can price the
## cubic metre at all.
##
## A practice buys mulch, soil amendment and a lift of aggregate by the volume, and the depth is what
## turns an outline into that volume - so somebody has to state it, once, for a whole layer. It is
## here rather than on the layer panel because this is the window where the consequence is on screen:
## state 75 mm against a bed and the line above changes from an area to a volume - a bed of
## twenty-four square metres becomes 1.8 cubic metres - priced at whatever per-cubic-metre rate the
## book holds. The chooser offers only layers bought by a **surface**, because a depth
## cannot be stated for a count - and it keeps offering a layer that already has one, so the depth just
## stated is still on screen and can be changed.
func _build_depth_row(page: VBoxContainer) -> void:
	_depth_row = HBoxContainer.new()
	_depth_row.name = "DepthRow"
	_depth_row.add_theme_constant_override("separation", 6)
	page.add_child(_depth_row)
	var words := Label.new()
	words.name = "DepthLabel"
	words.text = "depth"
	words.custom_minimum_size = Vector2(60, 0)
	_depth_row.add_child(words)
	_depth_layer = _depth_option()
	_depth_layer.item_selected.connect(_on_depth_layer_chosen)
	_depth_row.add_child(_depth_layer)
	_depth_mm = SpinBox.new()
	_depth_mm.name = "DepthMm"
	_depth_mm.min_value = 5
	_depth_mm.max_value = 1000
	_depth_mm.step = 5
	_depth_mm.value = 75
	_depth_mm.suffix = "mm"
	_depth_mm.custom_minimum_size = Vector2(110, 0)
	_depth_mm.tooltip_text = "How deep this layer's work goes. A bed at 75 mm of mulch is 1.8 m³ of it."
	_depth_row.add_child(_depth_mm)
	_depth_button = _button("Buy by volume", "_on_depth_stated")
	_depth_button.tooltip_text = "Measure this layer's outlines as a volume: its area at this depth."
	_depth_row.add_child(_depth_button)


func _depth_option() -> OptionButton:
	var option := OptionButton.new()
	option.name = "DepthLayer"
	option.custom_minimum_size = Vector2(220, 0)
	# An OptionButton is a Button, and a Button takes the keyboard from the drawing when it is focused.
	option.focus_mode = Control.FOCUS_NONE
	return option


## Fill the depth chooser from the drawing, and say what the layer currently is.
##
## The first entry is the honest default: a layer that is already measured as a volume keeps the depth
## it was given, so opening the window twice shows the same thing rather than resetting the decision.
func _fill_depth_row() -> void:
	if _depth_row == null:
		return
	var candidates: Array[StringName] = desk.surface_layers()
	var wanted: StringName = &""
	if not _depth_layers.is_empty() and _depth_layer.selected >= 0:
		wanted = _depth_layers[_depth_layer.selected]
	_depth_layers = candidates
	_depth_layer.clear()
	if candidates.is_empty():
		_depth_layer.add_item("no layer here is bought by the square metre")
		_depth_layer.disabled = true
		_depth_mm.editable = false
		_depth_button.disabled = true
		return
	_depth_layer.disabled = false
	_depth_mm.editable = true
	_depth_button.disabled = false
	var at: int = 0
	for index in candidates.size():
		var layer_name: StringName = candidates[index]
		var depth: int = desk.layer_depth(layer_name)
		_depth_layer.add_item(
			"%s%s" % [String(layer_name), "   %d mm" % depth if depth > 0 else ""]
		)
		if layer_name == wanted:
			at = index
	_depth_layer.select(at)
	# The spin box shows the chosen layer's own depth, so the row never reads as though a layer that is
	# already bought by the cubic metre had no depth.
	var depth_here: int = desk.layer_depth(candidates[at])
	if depth_here > 0:
		_depth_mm.value = float(depth_here)
	_set_depth_button_words()


## The button says what pressing it will do, so the row reads as a sentence rather than a label and a
## verb. There is no "back to the area": a depth stated is a decision, and the way to take it back is
## the same one every other decision about a layer has - state a different depth.
func _set_depth_button_words() -> void:
	if _depth_button == null or _depth_layers.is_empty() or _depth_layer.selected < 0:
		return
	var as_volume: bool = desk.layer_depth(_depth_layers[_depth_layer.selected]) > 0
	_depth_button.text = "Change the depth" if as_volume else "Buy by volume"
	_depth_button.name = _depth_button.text.replace(" ", "")


## Choosing a different layer shows that layer's own depth, so a row that says "Change the depth" is
## never sitting under a number somebody typed for a different layer.
func _on_depth_layer_chosen(_index: int) -> void:
	if _depth_layers.is_empty() or _depth_layer.selected < 0:
		return
	var depth: int = desk.layer_depth(_depth_layers[_depth_layer.selected])
	_depth_mm.value = float(maxi(depth, 5))
	_set_depth_button_words()


## The whole feature in one gesture: state the depth of a layer, measure the drawing again, and show
## the line for that layer as a volume priced at the book's per-cubic-metre rate.
func _on_depth_stated() -> void:
	if desk == null or _depth_layers.is_empty() or _depth_layer.selected < 0:
		return
	var layer_name: StringName = _depth_layers[_depth_layer.selected]
	var depth: int = int(_depth_mm.value)
	if not desk.set_layer_depth(layer_name, depth):
		_set_status("%s is not measured as an area, so it has no depth to state." % String(layer_name))
		return
	_set_status("%s is bought by the volume: %d mm deep." % [String(layer_name), depth])
	refresh()
	# The measurement changed, so the estimate did, so the HUD's one line about where the job stands is
	# now stale - the same announcement every other edit here makes.
	estimate_changed.emit()


func _build_proposal_tab(page: VBoxContainer) -> void:
	_tax_row = HBoxContainer.new()
	_tax_row.name = "TaxRow"
	_tax_row.add_theme_constant_override("separation", 6)
	page.add_child(_tax_row)
	var tax_label := Label.new()
	tax_label.name = "TaxLabel"
	tax_label.text = "tax"
	tax_label.custom_minimum_size = Vector2(60, 0)
	_tax_row.add_child(tax_label)
	_tax_option = OptionButton.new()
	_tax_option.name = "TaxOption"
	_tax_option.custom_minimum_size = Vector2(260, 0)
	_tax_option.item_selected.connect(_on_tax_chosen)
	_tax_row.add_child(_tax_option)
	_line_list = _list("ProposalLines")
	page.add_child(_line_list)
	_totals = Label.new()
	_totals.name = "Totals"
	_totals.custom_minimum_size = Vector2(0, 150)
	page.add_child(_totals)


func _build_book_tab(page: VBoxContainer) -> void:
	_book_note = _note("")
	page.add_child(_book_note)
	_book_list = _list("BookLines")
	page.add_child(_book_list)


func _list(list_name: String) -> ItemList:
	var list := ItemList.new()
	list.name = list_name
	list.custom_minimum_size = Vector2(0, LIST_HEIGHT)
	list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.select_mode = ItemList.SELECT_SINGLE
	return list


func _note(words: String) -> Label:
	var label := Label.new()
	label.name = "Note%s" % str(words.hash())
	label.text = words
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.modulate = Color(0.75, 0.76, 0.78)
	label.add_theme_font_size_override("font_size", 11)
	return label


func _button(words: String, method: String) -> Button:
	var button := Button.new()
	button.name = words.replace(" ", "")
	button.text = words
	button.pressed.connect(Callable(self, method))
	return button


# --- showing what is there ---------------------------------------------------------------------


## Point the window at a drawing and a planting list, and read everything again.
##
## `plant_rows` is the yard's planting list (`PlantPlacement.schedule`), or empty: with rows in it the
## plants are counted as props and the planting layer's own symbols are left out of the geometry, so a
## garden is never billed twice (the double-count rule the takeoff already tests).
func bind(document: DraftDocument, plant_rows: Array = []) -> void:
	if desk == null:
		build()
	desk.bind(document)
	desk.plant_rows = plant_rows
	refresh()


## Read the book if it has not been read, then show where everything stands. Called when the window
## is opened and after anything here changes the estimate.
func refresh() -> void:
	if _tabs == null:
		return
	if desk.book == null and not _book_tried:
		_book_tried = true
		var loaded: Dictionary = desk.load_book()
		if not bool(loaded["ok"]):
			_set_status("the prices would not load: %s" % String(loaded["reason"]))
	_fill_tax()
	_fill_takeoff()
	_fill_depth_row()
	_fill_lines()
	_fill_totals()
	_fill_book()
	_fill_buttons()
	if _status.text.is_empty() or desk.estimate == null:
		_set_status(desk.describe())


func _fill_tax() -> void:
	var wanted: StringName = desk.tax_code
	if desk.estimate != null:
		wanted = desk.estimate.tax_code
	_tax_option.clear()
	var codes: Array[StringName] = desk.tax_codes()
	var at: int = 0
	for index in codes.size():
		var code: StringName = codes[index]
		_tax_option.add_item("%s    %s" % [desk.tax_code_name(code), String(code)])
		if code == wanted:
			at = index
	_tax_option.select(at)


func _fill_takeoff() -> void:
	_takeoff_list.clear()
	for words: String in desk.takeoff_lines():
		_takeoff_list.add_item(words)
	var notes: Array[String] = desk.notes()
	var told: PackedStringArray = PackedStringArray()
	if desk.takeoff == null:
		told.append(
			"Nothing has been measured yet. Taking off the plan measures every entity worth money, "
			+ "prices it from the cost book, and names the lines nothing in the book covers."
		)
	else:
		told.append(
			"%d line%s measured, %d priced. %d line%s on the drawing are not work and are named below "
			% [
				desk.takeoff.lines.size(), "" if desk.takeoff.lines.size() == 1 else "s",
				desk.estimate.line_count() if desk.estimate != null else 0,
				notes.size(), "" if notes.size() == 1 else "s",
			]
			+ "rather than dropped: a hatch or a dimension is a pattern over work measured elsewhere."
		)
	for note: String in notes:
		told.append(note)
	_takeoff_note.text = "\n".join(told)
	_takeoff_note.name = "Note%s" % str(_takeoff_note.text.hash())


func _fill_lines() -> void:
	_line_list.clear()
	for words: String in desk.estimate_lines():
		_line_list.add_item(words)
	var refused: Array[String] = desk.refused
	# The lines nothing could price are shown in the list they would have been in, so a proposal that
	# is missing a patio looks different from a drawing that has no patio. They are not lines in the
	# estimate - they are the reason it is short, and the estimate itself must not contain them.
	for words: String in refused:
		var index: int = _line_list.add_item("not priced: %s" % words)
		_line_list.set_item_disabled(index, true)
	if _line_list.item_count == 0:
		_line_list.add_item("Nothing is priced yet.")


func _fill_totals() -> void:
	_totals.text = desk.totals_text()


func _fill_book() -> void:
	_book_list.clear()
	if desk.book == null:
		_book_note.text = "There is no cost book: a drawing can be measured without one, but nothing can be priced."
		_book_note.name = "Note%s" % str(_book_note.text.hash())
		return
	for item_id: StringName in desk.book.item_ids():
		var item: CostItem = desk.book.item(item_id)
		if item == null:
			continue
		var index: int = _book_list.add_item(
			"%s  %s  [%s]" % [String(item_id), item.describe(), String(item.cost_code)]
		)
		_book_list.set_item_disabled(index, true)
	for kit_id: StringName in desk.book.kit_ids():
		var kit: CostKit = desk.book.kit(kit_id)
		if kit == null:
			continue
		var index: int = _book_list.add_item("kit  %s  %s" % [String(kit_id), kit.describe()])
		_book_list.set_item_disabled(index, true)
	_book_note.text = "%s, read from %s. This tab reads; editing a price list is the cost book dock." % [
		desk.book.describe(), desk.book_source
	]
	_book_note.name = "Note%s" % str(_book_note.text.hash())


## The buttons that can only do something sometimes say so, rather than doing nothing: a disabled
## button says why in its tooltip, which is the rule the plant panel's Place button follows.
func _fill_buttons() -> void:
	var frozen: bool = desk.estimate != null and desk.estimate.is_frozen()
	_send_button.disabled = desk.estimate == null or frozen
	_send_button.tooltip_text = "there is nothing priced to send yet" if desk.estimate == null \
		else ("it has already gone: start a revision to change it" if frozen else "")
	_revision_button.disabled = not frozen
	_revision_button.tooltip_text = "a revision is what happens to a proposal that has already gone" \
		if not frozen else ""
	_start_job_button.disabled = desk.estimate == null
	_start_job_button.tooltip_text = "nothing is priced yet, so there is nothing to make a job of" \
		if desk.estimate == null else ""
	_plan_status.text = _plan_words()


func _plan_words() -> String:
	if desk.document == null:
		return "There is no drawing open. The takeoff measures a drawing, so there is nothing here to measure."
	var parts := PackedStringArray()
	parts.append(
		"%s: %d entit%s on it" % [
			"a drawing", desk.document.count(), "y" if desk.document.count() == 1 else "ies",
		]
	)
	if desk.book != null:
		parts.append("priced from %s" % desk.book.describe())
	if desk.estimate != null:
		parts.append(desk.describe())
	else:
		parts.append("nothing has been taken off it yet")
	return ". ".join(parts) + "."


func _set_status(words: String) -> void:
	_status.text = words


# --- what the buttons do ---------------------------------------------------------------------


func _on_take_off() -> void:
	_show_take_off(desk.take_off())


## Take off the plan through the desk and say what happened. Split out from the button so a test can
## drive the same path and read the result the button only speaks.
func _show_take_off(result: Dictionary) -> void:
	if not bool(result["ok"]):
		refresh()
		_set_status("Nothing to take off: %s." % String(result["reason"]))
		return
	var told := PackedStringArray()
	told.append(
		"%d line%s measured and %d priced" % [
			int(result["measured"]), "" if int(result["measured"]) == 1 else "s", int(result["priced"]),
		]
	)
	if int(result["refused"]) > 0:
		told.append("%d not priced" % int(result["refused"]))
	if int(result["notes"]) > 0:
		told.append("%d not measured" % int(result["notes"]))
	told.append(desk.describe())
	refresh()
	_set_status("%s." % ", ".join(told))
	estimate_changed.emit()


func _on_check() -> void:
	var checked: Dictionary = desk.check()
	var told := PackedStringArray()
	if desk.estimate == null:
		told.append("nothing is priced yet")
	else:
		told.append("the lines foot to the subtotal" if bool(checked["foots"]) else "it does not foot")
		told.append("gross margin %s" % String(checked["margin"]))
	if int(checked["notes"]) > 0:
		told.append("%d line%s on the drawing are not work and are not in it" % [
			int(checked["notes"]), "" if int(checked["notes"]) == 1 else "s",
		])
	var problems: Array = checked["problems"]
	if problems.is_empty():
		_set_status("%s." % ", ".join(told))
		return
	told.append("%d thing%s to fix" % [problems.size(), "" if problems.size() == 1 else "s"])
	_set_status("%s: %s" % [", ".join(told), String(problems[0])])


func _on_write_proposal() -> void:
	var written: Dictionary = desk.write_proposal()
	if not bool(written["ok"]):
		_set_status("The proposal was not written: %s." % String(written["reason"]))
		return
	_set_status("written to %s" % String(written["path"]))


func _on_send() -> void:
	var who: String = _recipient.text.strip_edges()
	if who.is_empty():
		_set_status("A proposal needs somebody to go to: put the customer's name in the box, then send it.")
		return
	var result: Dictionary = desk.send(who)
	if not bool(result["ok"]):
		_set_status("It was not sent: %s." % String(result["reason"]))
		refresh()
		return
	refresh()
	_set_status(
		"sent to %s: the prices are held by the hash %s, and an edit now will not change what "
		% [who, String(result["hash"]).substr(0, 12)]
		+ "went out."
	)
	estimate_changed.emit()


func _on_revision() -> void:
	var result: Dictionary = desk.revision()
	if not bool(result["ok"]):
		_set_status("No revision was started: %s." % String(result["reason"]))
		return
	refresh()
	_set_status(
		"revision %d is open. The revision that went out is unchanged and still on the customer's desk."
		% int(result["revision"])
	)
	estimate_changed.emit()


func _on_tax_chosen(index: int) -> void:
	var codes: Array[StringName] = desk.tax_codes()
	if index < 0 or index >= codes.size():
		return
	if not desk.set_tax_code(codes[index]):
		return
	refresh()
	_set_status(
		"%s, charged per line on the line's own share of the price. Every line was priced again, "
		% desk.tax_code_name(codes[index])
		+ "because a line keeps the code it was added with."
	)
	estimate_changed.emit()


func _on_close_requested() -> void:
	# Both halves, the way the other pages that draw their own frame do it: emitting `closed` tells the
	# program the page is over, and the page is the one thing that actually takes itself off the screen.
	# Only emitting it left the window up for good - the X, the Close button and Escape all went through
	# here - because nothing else hides this page. Found live in `tools/page_escape_demo.gd`.
	hide()
	closed.emit()


## Start a job from the estimate as it stands, which is the button's path.
##
## Returns `{ok, reason}`. Nothing is refused for being unfrozen or unsound: a job is what the office
## does next, and the job records the revision it was contracted from, so a job made from a draft says
## so by its revision rather than being impossible.
func start_job() -> Dictionary:
	if desk.estimate == null:
		return {"ok": false, "reason": "there is nothing priced yet"}
	var offer: Estimate = desk.estimate
	var lines := offer.line_count()
	job_started.emit(offer)
	_set_status(
		"a job was started from this estimate: %d line%s, contracted at %s, revision %d. Jobs, crews "
		% [lines, "" if lines == 1 else "s", offer.price_before_tax().format_with_currency(),
			offer.revision]
		+ "and days are on the schedule board."
	)
	return {"ok": true, "reason": ""}


func _on_start_job() -> void:
	var result: Dictionary = start_job()
	if not bool(result["ok"]):
		_set_status("No job was started: %s." % String(result["reason"]))


# --- what a test reads -------------------------------------------------------------------


## Take off the plan the way the button does, and answer what the desk said - `{ok, reason,
## measured, priced, refused, notes}`.
func take_off() -> Dictionary:
	var result: Dictionary = desk.take_off()
	_show_take_off(result)
	return result


## The words at the bottom of the window.
func status_text() -> String:
	return _status.text if _status != null else ""


## What the panel says about the drawing and where the job stands.
func plan_status_text() -> String:
	return _plan_status.text if _plan_status != null else ""


func takeoff_texts() -> Array[String]:
	return _texts_of(_takeoff_list)


## The layers the depth row offers, in the order it shows them. Only layers the takeoff measures by
## the square metre, because a depth cannot be stated for a count.
func depth_choices() -> Array[StringName]:
	return _depth_layers.duplicate()


## How the depth row words each choice, which is the only place a layer's depth is shown on the panel.
func depth_texts() -> Array[String]:
	var out: Array[String] = []
	if _depth_layer == null:
		return out
	for index in _depth_layer.item_count:
		out.append(_depth_layer.get_item_text(index))
	return out


## The layer the depth row is pointed at, or empty.
func depth_choice() -> StringName:
	if _depth_layers.is_empty() or _depth_layer == null or _depth_layer.selected < 0:
		return &""
	return _depth_layers[_depth_layer.selected]


## Point the row at a layer the way choosing it does, showing that layer's own depth.
func choose_depth(layer_name: StringName) -> bool:
	for index in _depth_layers.size():
		if _depth_layers[index] == layer_name:
			_depth_layer.select(index)
			_on_depth_layer_chosen(index)
			return true
	return false


## The depth in the spin box, in millimetres.
func depth_mm() -> int:
	return int(_depth_mm.value) if _depth_mm != null else 0


func set_depth_mm(depth_mm_value: int) -> void:
	if _depth_mm != null:
		_depth_mm.value = float(depth_mm_value)


## Whether the depth row is usable at all: false for a drawing with no layer bought by the square metre.
func depth_row_enabled() -> bool:
	return _depth_button != null and not _depth_button.disabled


func line_texts() -> Array[String]:
	return _texts_of(_line_list)


func book_texts() -> Array[String]:
	return _texts_of(_book_list)


func totals_text() -> String:
	return _totals.text if _totals != null else ""


func note_texts() -> Array[String]:
	return [_takeoff_note.text, _book_note.text]


func tab_titles() -> Array[String]:
	var out: Array[String] = []
	if _tabs == null:
		return out
	for index in _tabs.get_tab_count():
		out.append(_tabs.get_tab_title(index))
	return out


func select_tab(tab_title: String) -> bool:
	for index in _tabs.get_tab_count():
		if _tabs.get_tab_title(index) == tab_title:
			_tabs.current_tab = index
			return true
	return false


func tax_texts() -> Array[String]:
	var out: Array[String] = []
	if _tax_option == null:
		return out
	for index in _tax_option.item_count:
		out.append(_tax_option.get_item_text(index))
	return out


func selected_tax() -> String:
	if _tax_option == null or _tax_option.selected < 0:
		return ""
	return String(desk.tax_codes()[_tax_option.selected])


## Choose a tax the way the dropdown does, by its code.
func choose_tax(code: StringName) -> bool:
	var codes: Array[StringName] = desk.tax_codes()
	var index: int = codes.find(code)
	if index < 0:
		return false
	_tax_option.select(index)
	_on_tax_chosen(index)
	return true


func recipient_text() -> String:
	return _recipient.text if _recipient != null else ""


func set_recipient(who: String) -> void:
	if _recipient != null:
		_recipient.text = who


func send_it() -> void:
	_on_send()


func new_revision() -> void:
	_on_revision()


func check_numbers() -> void:
	_on_check()


func write_proposal() -> void:
	_on_write_proposal()


func send_button_disabled() -> bool:
	return _send_button.disabled if _send_button != null else true


## Why the send button is switched off, in words: a disabled button that says nothing is a button
## that looks broken.
func send_hint() -> String:
	return _send_button.tooltip_text if _send_button != null else ""


func revision_button_disabled() -> bool:
	return _revision_button.disabled if _revision_button != null else true


func start_job_button_disabled() -> bool:
	return _start_job_button.disabled if _start_job_button != null else true


## Why the job button is switched off, in words.
func start_job_hint() -> String:
	return _start_job_button.tooltip_text if _start_job_button != null else ""


func _texts_of(list: ItemList) -> Array[String]:
	var out: Array[String] = []
	if list == null:
		return out
	for index in list.item_count:
		out.append(list.get_item_text(index))
	return out