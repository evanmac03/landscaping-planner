extends Node
## The outbox on a page: what it shows, what its buttons do, and what it refuses to do (spec §9.7).
##
## The properties under test. **Nothing on the page takes the keyboard** beyond the typed fields, which
## is the rule every page in this project obeys. **A row carries a Post button only while the queue can
## still send it** - a delivered document has no button, because posting it again is not an action. **A
## run reports what it did**, including when it did nothing. And **the page decides nothing**: every
## line and every list is the desk's own, and the settings it shows are the backend's own declaration.

const WindowScript := preload("res://scripts/ledger_window.gd")
const DeskScript := preload("res://scripts/biz/ledger_desk.gd")
const AdapterScript := preload("res://scripts/biz/ledger_adapter.gd")
const NinjaScript := preload("res://scripts/biz/invoice_ninja.gd")
const BillingDeskScript := preload("res://scripts/biz/billing_desk.gd")
const PushScript := preload("res://scripts/biz/ledger_push.gd")
const InvoiceScript := preload("res://scripts/biz/invoice.gd")
const MoneyScript := preload("res://scripts/biz/money.gd")

const TEST_FOLDER := "user://test_ledger_window"
const CLIENT := "Wpmbk5ezJn"


# --- fixtures -----------------------------------------------------------------------------------


func _desk() -> DeskScript:
	DirAccess.make_dir_recursive_absolute(TEST_FOLDER)
	var at: DirAccess = DirAccess.open(TEST_FOLDER)
	if at != null:
		for file_name in at.get_files():
			at.remove(file_name)
	var desk: DeskScript = DeskScript.new()
	desk.chosen_adapter().set_setting(&"folder", TEST_FOLDER)
	return desk


## A page built off-tree: it needs no window server and no `_ready` to be driven, because `build()` is
## the only thing `_ready` calls.
func _page(desk: DeskScript) -> WindowScript:
	var page: WindowScript = WindowScript.new()
	page.build()
	page.bind(desk)
	return page


func _invoice(number: String = "INV-2026-0001") -> InvoiceScript:
	var invoice: InvoiceScript = InvoiceScript.new("INV-%s" % number)
	invoice.job = "J1"
	invoice.customer = {"name": "Smith", "external_id": CLIENT}
	invoice.add_line(InvoiceScript.MILESTONE_LINE, "Deposit", 1000, &"EACH",
		MoneyScript.of(53550), &"HARDSCAPE", &"HST-ON")
	assert(bool(invoice.issue("2026-06-10", 30, number)["ok"]))
	return invoice


func _answered(push: PushScript, status: int, body: Dictionary) -> bool:
	var response: Dictionary = {"status": status, "body": body}
	return push.record_response(response, AdapterScript.new().parse_common(response), "2026-06-12")


# --- the page itself ----------------------------------------------------------------------------


func test_the_page_has_the_controls_a_page_about_a_ledger_has() -> void:
	var page := _page(_desk())
	assert(page.get_node_or_null(^"Column/Summary") != null)
	assert(page.get_node_or_null(^"Column/BackendRow/BackendOption") != null)
	assert(page.get_node_or_null(^"Column/BackendRow/Saveitssettings") != null)
	assert(page.get_node_or_null(^"Column/BackendRow/Testit") != null)
	assert(page.get_node_or_null(^"Column/RunRow/Handovereverythingwaiting") != null)
	assert(page.get_node_or_null(^"Column/Rows") != null)
	assert(page.get_node_or_null(^"Column/Disagreements") != null)
	assert(page.get_node_or_null(^"Column/Problems") != null)
	assert(page.get_node_or_null(^"Column/Status") != null)
	assert(page.title == "What has been handed to a ledger")
	page.free()


func test_nothing_on_the_page_takes_the_keyboard() -> void:
	var desk := _desk()
	desk.queue_invoice(_invoice())
	var page := _page(desk)
	assert(page.buttons_are_focus_free())
	page.free()


func test_the_page_opens_saying_what_to_do_with_it() -> void:
	var empty := _page(_desk())
	assert(empty.status_text() == "Nothing has been handed to a ledger yet: an invoice raised on the "
		+ "billing page can be.", empty.status_text())
	empty.free()
	var waiting: DeskScript = _desk()
	waiting.queue_invoice(_invoice())
	var full := _page(waiting)
	assert(full.status_text().contains("Post what is waiting"), full.status_text())
	full.free()


func test_the_page_says_which_ledger_still_needs_told_where_it_is() -> void:
	var desk := _desk()
	desk.add_adapter(NinjaScript.new())
	desk.choose("invoice_ninja")
	var page := _page(desk)
	assert(page.status_text().contains("still needs told where it is"), page.status_text())
	assert(page.status_text().contains("API token"), page.status_text())
	assert(page.backend_text().contains("needs an Invoice Ninja API token"), page.backend_text())
	assert(page.backend_text().contains("(needs configuring)") == false)
	page.free()


func test_a_page_with_no_ledger_is_empty_rather_than_broken() -> void:
	var page: WindowScript = WindowScript.new()
	page.build()
	page.bind(null)
	assert(page.summary_text() == "nothing has been handed to a ledger")
	assert(page.row_texts().is_empty())
	assert(page.problem_texts().is_empty())
	assert(page.disagreement_text() == "the outbox and the office's own records agree")
	# A null desk becomes an empty one rather than a page with nothing to show, so the page describes the
	# ledger that desk has - the file backend, the one that always works.
	assert(page.backend_text().begins_with("a folder of files"), page.backend_text())
	page.free()
	# And a desk whose chosen ledger has gone is named as such rather than crashing the page.
	var half: DeskScript = _desk()
	half.chosen = ""
	var other: WindowScript = WindowScript.new()
	other.build()
	other.bind(half)
	assert(other.backend_text() == "no ledger is chosen")
	assert(other.status_text() == "Pick the ledger documents should be handed to.", other.status_text())
	other.free()


# --- which ledger --------------------------------------------------------------------------------


func test_the_backend_picker_lists_the_desks_own_backends() -> void:
	var desk := _desk()
	desk.add_adapter(NinjaScript.new("https://ninja.example.test", "token"))
	var page := _page(desk)
	var picker: OptionButton = page.get_node(^"Column/BackendRow/BackendOption")
	assert(picker.item_count == 2)
	assert(picker.get_item_text(0).begins_with("file"), picker.get_item_text(0))
	assert(picker.get_item_text(1).begins_with("invoice_ninja"), picker.get_item_text(1))
	assert(page.selected_backend() == "file")
	assert(page.backend_text().contains("a folder of files"), page.backend_text())
	page.free()


func test_a_backend_that_needs_configuring_says_so_in_the_picker() -> void:
	var desk := _desk()
	desk.add_adapter(NinjaScript.new())
	var page := _page(desk)
	var picker: OptionButton = page.get_node(^"Column/BackendRow/BackendOption")
	assert(picker.get_item_text(1).ends_with("(needs configuring)"), picker.get_item_text(1))
	page.free()


func test_choosing_a_backend_on_the_page_is_choosing_it_on_the_desk() -> void:
	var desk := _desk()
	desk.add_adapter(NinjaScript.new("https://ninja.example.test", "token"))
	var page := _page(desk)
	# The dropdown only shows what the desk decided; the desk is what it means.
	assert(page.select_backend("invoice_ninja"))
	assert(desk.chosen == "invoice_ninja")
	assert(page.selected_backend() == "invoice_ninja")
	assert(not page.select_backend("nothing"))
	assert(desk.chosen == "invoice_ninja")
	page.free()


func test_the_page_says_what_the_backend_can_do() -> void:
	var desk := _desk()
	desk.add_adapter(NinjaScript.new("https://ninja.example.test", "token"))
	desk.choose("invoice_ninja")
	var page := _page(desk)
	# A capability is stated on the page the same way it is stated by the adapter, and what it cannot do
	# is simply absent from the list rather than promised.
	assert(page.backend_text().contains("post invoices"), page.backend_text())
	assert(page.backend_text().contains("post payments"), page.backend_text())
	assert(not page.backend_text().contains("credit"), page.backend_text())
	assert(page.backend_text().contains("0 document(s) for it in the outbox"), page.backend_text())
	page.free()


# --- the outbox ----------------------------------------------------------------------------------


func test_the_rows_on_the_page_are_the_desks_own_rows() -> void:
	var desk := _desk()
	desk.queue_invoice(_invoice("INV-2026-0001"))
	desk.queue_invoice(_invoice("INV-2026-0002"))
	var page := _page(desk)
	assert(page.row_texts() == desk.row_texts(), str(page.row_texts()))
	assert(page.row_texts()[0].contains("INV-2026-0002"), page.row_texts()[0])
	assert(page.summary_text() == "2 waiting")
	page.free()


func test_an_empty_outbox_says_so_rather_than_showing_nothing_at_all() -> void:
	var page := _page(_desk())
	assert(page.get_node(^"Column/Rows/NoRows").text == "the outbox is empty")
	assert(page.summary_text() == "nothing has been handed to a ledger")
	page.free()


func test_a_row_carries_a_post_button_only_while_the_queue_can_send_it() -> void:
	var desk := _desk()
	var waiting: Dictionary = desk.queue_invoice(_invoice("INV-2026-0001"))
	var sent: Dictionary = desk.queue_invoice(_invoice("INV-2026-0002"))
	desk.post(sent["push"].key)
	var stuck: Dictionary = desk.queue_invoice(_invoice("INV-2026-0003"))
	_answered(stuck["push"], 401, {"message": "token expired"})
	var page := _page(desk)
	# Three documents, one button: the one that is delivered is not an action to repeat, and the one the
	# queue has given up on is not fixed by pressing it again.
	assert(page.post_count() == 1, str(page.post_count()))
	assert(page.get_node(^"Column/Rows").get_child(2).has_node("Words"))
	page.free()


func test_posting_from_a_row_sends_that_document_and_says_so() -> void:
	var desk := _desk()
	var one: Dictionary = desk.queue_invoice(_invoice("INV-2026-0001"))
	desk.queue_invoice(_invoice("INV-2026-0002"))
	var page := _page(desk)
	var posted: Dictionary = page.post_one(one["push"].key)
	assert(bool(posted["ok"]), String(posted["reason"]))
	assert(page.status_text() == "handed over 1 document.", page.status_text())
	# Only that one went: the page did not help itself to the rest of the outbox.
	assert(desk.delivered().size() == 1)
	assert(desk.pending().size() == 1)
	# And the page has read the desk again, so the row it posted has no button any more.
	assert(page.post_count() == 1)
	page.free()


func test_a_post_that_did_not_go_says_what_happened() -> void:
	var desk := _desk()
	# A request the file backend cannot carry out: its transport is the disk and it writes, so a POST is
	# refused rather than silently ignored, which is what makes a failure visible at all.
	var push: PushScript = PushScript.for_document("file", AdapterScript.INVOICE_KIND,
		"INV-1", "INV-2026-0001", "key-1",
		AdapterScript.make_request(&"POST", "%s/INV-2026-0001.json" % TEST_FOLDER, {}, {"kind": "invoice"}),
		"2026-06-12")
	desk.pushes.append(push)
	var page := _page(desk)
	var posted: Dictionary = page.post_one("key-1")
	assert(not bool(posted["ok"]))
	assert(page.status_text().contains("did not go"), page.status_text())
	assert(page.status_text().contains("cannot send a POST request"), page.status_text())
	page.free()


func test_posting_a_key_that_is_not_in_the_outbox_is_refused_by_the_page() -> void:
	var page := _page(_desk())
	var posted: Dictionary = page.post_one("nothing-here")
	assert(not bool(posted["ok"]))
	assert(page.status_text().contains("nothing in the outbox"), page.status_text())
	page.free()


func test_handing_over_everything_waiting_says_what_it_did() -> void:
	var desk := _desk()
	desk.queue_invoice(_invoice("INV-2026-0001"))
	desk.queue_invoice(_invoice("INV-2026-0002"))
	var page := _page(desk)
	var run: Dictionary = page.post_all()
	assert(bool(run["ok"]), String(run["reason"]))
	assert(page.status_text() == "handed over 2 documents.", page.status_text())
	assert(desk.delivered().size() == 2)
	assert(page.summary_text() == "2 handed over")
	page.free()


## A run that sent none of them still reports, and names what stood in the way - "the button did
## nothing" is not a report.
func test_a_run_says_how_many_did_not_go_and_why() -> void:
	var desk := _desk()
	desk.queue_invoice(_invoice("INV-2026-0001"))
	var orphan: PushScript = PushScript.for_document("invoice_ninja", AdapterScript.INVOICE_KIND,
		"INV-9", "INV-2026-0009", "key-9",
		AdapterScript.make_request(&"POST", "https://ninja.example.test/api/v1/invoices", {},
			{"number": "INV-2026-0009"}),
		"2026-06-12")
	desk.pushes.append(orphan)
	var page := _page(desk)
	var run: Dictionary = page.post_all()
	assert(not bool(run["ok"]))
	assert(page.status_text().contains("handed over 1 document"), page.status_text())
	assert(page.status_text().contains("1 document did not go"), page.status_text())
	assert(page.status_text().contains("no ledger called 'invoice_ninja' is registered here"),
		page.status_text())
	assert(page.status_text().contains("1 document still waiting"), page.status_text())
	page.free()


func test_a_run_with_nothing_waiting_says_so_rather_than_doing_nothing_quietly() -> void:
	var page := _page(_desk())
	var run: Dictionary = page.post_all()
	assert(int(run["tried"]) == 0)
	assert(page.status_text() == "nothing was waiting to be handed over.", page.status_text())
	page.free()


func test_a_delivered_document_is_not_offered_again_by_the_page() -> void:
	var desk := _desk()
	desk.queue_invoice(_invoice())
	assert(bool(desk.post_due()["taken"]) == true)
	var page := _page(desk)
	assert(page.post_count() == 0)
	assert(page.run_button_disabled())
	page.free()


func test_the_post_button_belongs_to_the_row_it_is_in() -> void:
	var desk := _desk()
	desk.queue_invoice(_invoice("INV-2026-0001"))
	var second: Dictionary = desk.queue_invoice(_invoice("INV-2026-0002"))
	var page := _page(desk)
	# Rows are newest first, and each button knows which document it is about.
	var top: Node = page.get_node(^"Column/Rows").get_child(0)
	assert(top.get_node("Words").text.contains("INV-2026-0002"), top.get_node("Words").text)
	var button: Button = top.get_node("Post")
	assert(String(button.get_meta("key", "")) == second["push"].key)
	assert(page.post_count() == 2)
	page.free()


# --- the settings --------------------------------------------------------------------------------


func test_the_settings_the_page_shows_are_the_backends_own() -> void:
	var desk := _desk()
	desk.add_adapter(NinjaScript.new("https://ninja.example.test", "token-abc"))
	desk.choose("invoice_ninja")
	var page := _page(desk)
	var keys: Array[StringName] = page.setting_keys()
	assert(keys.size() == 2)
	assert(keys[0] == &"url")
	assert(keys[1] == &"token")
	var fields: Array[LineEdit] = page.setting_fields()
	assert(fields.size() == 2)
	assert(fields[0].text == "https://ninja.example.test")
	assert(fields[1].text == "token-abc")
	page.free()


func test_a_setting_the_backend_calls_secret_is_masked_on_the_page() -> void:
	var desk := _desk()
	desk.add_adapter(NinjaScript.new("https://ninja.example.test", "token-abc"))
	desk.choose("invoice_ninja")
	var page := _page(desk)
	# A page is a screen somebody walks past: the token is shown as dots and the address is not.
	assert(page.setting_is_masked(&"token"))
	assert(not page.setting_is_masked(&"url"))
	assert(not page.setting_is_masked(&"nothing"))
	page.free()


func test_the_file_backend_has_one_setting_and_it_is_not_secret() -> void:
	var desk := _desk()
	var page := _page(desk)
	var keys: Array[StringName] = page.setting_keys()
	assert(keys.size() == 1)
	assert(keys[0] == &"folder", str(keys))
	assert(not page.setting_is_masked(&"folder"))
	page.free()


func test_the_settings_row_follows_the_backend_that_is_chosen() -> void:
	var desk := _desk()
	desk.add_adapter(NinjaScript.new("https://ninja.example.test", "token-abc"))
	var page := _page(desk)
	assert(page.setting_keys().size() == 1)
	assert(page.select_backend("invoice_ninja"))
	assert(page.setting_keys().size() == 2)
	assert(page.setting_is_masked(&"token"))
	assert(page.select_backend("file"))
	assert(page.setting_keys().size() == 1)
	page.free()


func test_saving_a_setting_reaches_the_backend() -> void:
	var desk := _desk()
	desk.add_adapter(NinjaScript.new())
	desk.choose("invoice_ninja")
	var page := _page(desk)
	assert(page.setting_keys().size() == 2)
	page.set_setting_field(&"token", "a-fresh-token")
	var saved: Dictionary = page.save_settings()
	assert(bool(saved["ok"]), String(saved["reason"]))
	assert(int(saved["saved"]) == 1)
	assert(desk.chosen_adapter().setting(&"token") == "a-fresh-token")
	assert(desk.chosen_adapter().is_configured())
	assert(page.status_text().contains("is saved"), page.status_text())
	assert(page.status_text().contains("configured"), page.status_text())
	page.free()


func test_a_setting_the_backend_will_not_take_is_named_rather_than_half_saved() -> void:
	var desk := _desk()
	var page := _page(desk)
	# The file backend refuses a blank folder, and the page says which setting it was.
	page.set_setting_field(&"folder", "   ")
	var saved: Dictionary = page.save_settings()
	assert(not bool(saved["ok"]))
	assert(int(saved["saved"]) == 0)
	assert(page.status_text().contains("would not take folder"), page.status_text())
	assert(desk.chosen_adapter().setting(&"folder") == TEST_FOLDER)
	page.free()


func test_saving_nothing_new_says_the_backend_is_as_it_stands() -> void:
	var desk := _desk()
	var page := _page(desk)
	var saved: Dictionary = page.save_settings()
	assert(bool(saved["ok"]), String(saved["reason"]))
	assert(int(saved["saved"]) == 0)
	assert(page.status_text().contains("a folder of files"), page.status_text())
	page.free()


func test_the_buttons_that_cannot_do_anything_are_dead() -> void:
	var desk := _desk()
	var page := _page(desk)
	# The file backend's one setting is still a setting, so its save button lives; with an empty outbox
	# there is nothing to hand over, so the run button does not.
	assert(not page.get_node(^"Column/BackendRow/Saveitssettings").disabled)
	assert(page.run_button_disabled())
	desk.queue_invoice(_invoice())
	page.refresh()
	assert(not page.run_button_disabled())
	page.free()


# --- the backend's own answers -------------------------------------------------------------------


func test_the_test_button_says_what_the_backend_says() -> void:
	var desk := _desk()
	var page := _page(desk)
	var tested: Dictionary = page.test_backend()
	# The file backend writes and reads back, so its own test button really does test it.
	assert(bool(tested["ok"]), String(tested["reason"]))
	assert(page.status_text().contains("wrote and read back"), page.status_text())
	page.free()


func test_the_test_button_does_not_pretend_a_hosted_ledger_was_reached() -> void:
	var desk := _desk()
	desk.add_adapter(NinjaScript.new("https://ninja.example.test", "token"))
	desk.choose("invoice_ninja")
	var page := _page(desk)
	var tested: Dictionary = page.test_backend()
	# A green light that verified nothing would be worse than no button: it says what it cannot do.
	assert(not bool(tested["ok"]))
	assert(page.status_text().contains("no transport yet"), page.status_text())
	page.free()


# --- what does not agree ------------------------------------------------------------------------


func test_the_disagreements_the_page_shows_are_the_desks_own() -> void:
	var desk := _desk()
	var billing: BillingDeskScript = BillingDeskScript.new()
	billing.invoices.append(_invoice("INV-2026-0009"))
	desk.bind(billing)
	var page := _page(desk)
	assert(page.disagreement_texts() == desk.reconcile_words(), str(page.disagreement_texts()))
	assert(page.disagreement_text().contains("has been issued and not handed to"), page.disagreement_text())
	var label: Label = page.get_node(^"Column/Disagreements")
	assert(label.text == page.disagreement_text())
	page.free()


func test_a_page_with_nothing_out_of_place_says_so_plainly() -> void:
	var desk := _desk()
	var billing: BillingDeskScript = BillingDeskScript.new()
	billing.invoices.append(_invoice())
	desk.bind(billing)
	desk.queue_invoice(billing.invoices[0])
	var page := _page(desk)
	assert(page.disagreement_text() == "the outbox and the office's own records agree")
	page.free()


func test_the_problems_the_page_shows_are_the_desks_own() -> void:
	var desk := _desk()
	var queued: Dictionary = desk.queue_invoice(_invoice())
	_answered(queued["push"], 401, {"message": "token expired"})
	var page := _page(desk)
	assert(page.problem_texts() == desk.problems(), str(page.problem_texts()))
	assert(page.problem_texts().size() == 1)
	assert(page.problem_texts()[0].contains("will not be retried"), page.problem_texts()[0])
	var list: ItemList = page.get_node(^"Column/Problems")
	assert(list.item_count == 1)
	assert(list.is_item_disabled(0))
	page.free()


# --- telling whoever is listening -----------------------------------------------------------------


func test_a_post_announces_itself_so_the_menu_line_is_not_stale() -> void:
	var desk := _desk()
	var queued: Dictionary = desk.queue_invoice(_invoice())
	var page := _page(desk)
	var heard: Array = []
	page.ledger_changed.connect(func() -> void: heard.append(true))
	assert(bool(page.post_one(queued["push"].key)["ok"]))
	assert(heard.size() == 1, str(heard))
	page.free()


func test_saving_a_setting_announces_itself_too() -> void:
	var desk := _desk()
	desk.add_adapter(NinjaScript.new())
	desk.choose("invoice_ninja")
	var page := _page(desk)
	var heard: Array = []
	page.ledger_changed.connect(func() -> void: heard.append(true))
	assert(page.setting_keys().size() == 2)
	page.set_setting_field(&"token", "a-token")
	assert(bool(page.save_settings()["ok"]))
	assert(heard.size() == 1, str(heard))
	# Nothing changed, so nothing is announced.
	assert(int(page.save_settings()["saved"]) == 0)
	assert(heard.size() == 1, str(heard))
	page.free()


func test_closing_the_page_says_so() -> void:
	var page := _page(_desk())
	var heard: Array = []
	page.closed.connect(func() -> void: heard.append(true))
	page.close_requested.emit()
	assert(not page.visible)
	assert(heard.size() == 1)
	page.free()


func test_the_page_reads_the_desk_again_when_it_is_pointed_at_another_outbox() -> void:
	var one: DeskScript = _desk()
	one.queue_invoice(_invoice("INV-2026-0001"))
	var page := _page(one)
	assert(page.row_texts().size() == 1)
	var other: DeskScript = _desk()
	other.queue_invoice(_invoice("INV-2026-0002"))
	other.queue_invoice(_invoice("INV-2026-0003"))
	page.bind(other)
	assert(page.row_texts().size() == 2)
	assert(page.status_text().contains("Post what is waiting"), page.status_text())
	page.free()