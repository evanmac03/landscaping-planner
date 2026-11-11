extends Node
## The outbox as the program reaches it: the Jobs menu line, the page, and the hand-over that happens
## as part of issuing an invoice (REQ-B14, spec §9.7).
##
## The properties under test. **An invoice that has just gone out is queued**, without anybody asking,
## and the queueing is idempotent so nothing is queued twice. **The menu line says what the outbox says**,
## and says nothing at all when there is nothing to report - "0 waiting" is noise on the one line a
## person reads from across the room. And **nothing takes the drawing's keyboard** while the page is up.

const HudScript := preload("res://scripts/hud.gd")
const LedgerDeskScript := preload("res://scripts/biz/ledger_desk.gd")
const BillingDeskScript := preload("res://scripts/biz/billing_desk.gd")
const JobDeskScript := preload("res://scripts/biz/job_desk.gd")
const InvoiceScript := preload("res://scripts/biz/invoice.gd")
const MoneyScript := preload("res://scripts/biz/money.gd")

const TEST_FOLDER := "user://test_hud_ledger"
const CLIENT := "Wpmbk5ezJn"


## A HUD built off-tree, with its outbox pointed at a throwaway folder. No `_ready`, so no windows are
## painted and no files are written: the methods a control calls are driven directly, which is what the
## menu handlers call anyway.
func _hud() -> HudScript:
	DirAccess.make_dir_recursive_absolute(TEST_FOLDER)
	var at: DirAccess = DirAccess.open(TEST_FOLDER)
	if at != null:
		for file_name in at.get_files():
			at.remove(file_name)
	var hud: HudScript = HudScript.new()
	hud._job_desk = JobDeskScript.new()
	hud._billing_ledger = BillingDeskScript.new()
	hud._billing_ledger.bind(hud._job_desk)
	hud._ledger_desk = LedgerDeskScript.new()
	hud._ledger_desk.bind(hud._billing_ledger)
	hud._ledger_desk.chosen_adapter().set_setting(&"folder", TEST_FOLDER)
	return hud


func _invoice(number: String = "INV-2026-0001") -> InvoiceScript:
	var invoice: InvoiceScript = InvoiceScript.new("INV-%s" % number)
	invoice.job = "J1"
	invoice.customer = {"name": "Smith", "external_id": CLIENT}
	invoice.add_line(InvoiceScript.MILESTONE_LINE, "Deposit", 1000, &"EACH",
		MoneyScript.of(53550), &"HARDSCAPE", &"HST-ON")
	assert(bool(invoice.issue("2026-06-10", 30, number)["ok"]))
	return invoice


# --- the menu line ------------------------------------------------------------------------------


func test_a_hud_with_no_outbox_reports_nothing_about_a_ledger() -> void:
	var hud: HudScript = HudScript.new()
	hud._job_desk = null
	assert(hud._jobs_text() == "no crews and no jobs yet")
	hud.free()


func test_an_empty_outbox_says_nothing_on_the_menu_line() -> void:
	var hud := _hud()
	# "file: nothing has been handed to a ledger" is noise on a line read from across the room.
	assert(not hud._jobs_text().contains("ledger"), hud._jobs_text())
	hud.free()


func test_a_document_waiting_is_what_the_menu_line_says() -> void:
	var hud := _hud()
	hud._billing_ledger.invoices.append(_invoice())
	hud.queue_invoices_for_ledger()
	assert(hud._ledger_desk.count() == 1)
	assert(hud._jobs_text().contains("the file ledger:"), hud._jobs_text())
	assert(hud._jobs_text().contains("1 waiting"), hud._jobs_text())
	hud.free()


func test_a_document_that_could_not_be_queued_is_on_the_menu_line_too() -> void:
	var hud := _hud()
	hud._ledger_desk.add_adapter(HudNinjaScript.new("https://ninja.example.test", "token"))
	assert(hud._ledger_desk.choose("invoice_ninja"))
	# An invoice whose customer has no id in the ledger cannot be built at all: it is refused by name, and
	# the menu line says something wants a person rather than saying nothing happened.
	hud._billing_ledger.invoices.append(_invoice("INV-2026-0001"))
	hud._billing_ledger.invoices[0].customer = {"name": "Smith"}
	var handed: Dictionary = hud.queue_invoices_for_ledger()
	assert(not bool(handed["ok"]))
	assert(int(handed["queued"]) == 0)
	assert(int(handed["refused"]) == 1)
	assert(hud._ledger_desk.count() == 0)
	assert(hud._jobs_text().contains("1 could not be handed over"), hud._jobs_text())
	hud.free()


func test_the_menu_offers_the_outbox() -> void:
	var items: Array[Dictionary] = HudScript.jobs_items()
	var found: Dictionary = {}
	for held in items:
		if String(held.get("id", "")) == "jobs.outbox":
			found = held
	assert(not found.is_empty(), "the Jobs menu has no entry for the outbox")
	assert(String(found["method"]) == "_menu_ledger_window")
	assert(String(found["label"]).contains("handed to a ledger"), String(found["label"]))
	# And it is a command rather than a line that only reports.
	assert(StringName(found["kind"]) == &"command")


func test_building_the_outbox_page_gives_the_menu_something_to_open() -> void:
	var hud := _hud()
	assert(hud._ledger_window == null)
	hud._build_ledger_window()
	assert(hud._ledger_window != null)
	assert(hud._ledger_window.desk == hud._ledger_desk)
	# Built but not shown is not open: a page nobody has opened is not on the screen.
	assert(not hud.is_ledger_window_open())
	assert(hud._ledger_window.get_node_or_null(^"Scroll/Column/Rows") != null)
	assert(hud._ledger_window.get_node_or_null(^"Scroll/Column/BackendRow/BackendOption") != null)
	hud.free()


func test_the_outbox_page_offers_every_registered_backend() -> void:
	# The desk starts with the file backend and is handed the two hosted ledgers, so the office has a
	# page on which to state a hosted ledger's address and token. Until it does, the backend says it
	# needs configuring and nothing is posted to it.
	var hud: HudScript = HudScript.new()
	hud._job_desk = JobDeskScript.new()
	hud._build_ledger_desk()
	var expected: Array[String] = ["file", "akaunting", "invoice_ninja"]
	assert(hud._ledger_desk.adapter_names() == expected, str(hud._ledger_desk.adapter_names()))
	hud._build_ledger_window()
	var picker: OptionButton = hud._ledger_window.get_node(^"Scroll/Column/BackendRow/BackendOption")
	assert(picker.item_count == 3, str(picker.item_count))
	assert(hud._ledger_window.selected_backend() == "file")
	hud.free()


# --- the hand-over that happens as part of issuing ----------------------------------------------


func test_an_invoice_that_has_just_gone_out_is_queued_for_the_ledger() -> void:
	var hud := _hud()
	hud._billing_ledger.invoices.append(_invoice())
	# This is what the billing page's own signal does, so it is the real path rather than a stand-in.
	hud._on_billing_changed()
	assert(hud._ledger_desk.count() == 1)
	assert(hud._ledger_desk.pending().size() == 1)
	# And it is idempotent: another change to what has been billed hands over nothing new.
	hud._on_billing_changed()
	assert(hud._ledger_desk.count() == 1)
	hud.free()


func test_handing_over_twice_is_one_push_not_two() -> void:
	var hud := _hud()
	hud._billing_ledger.invoices.append(_invoice())
	assert(int(hud.queue_invoices_for_ledger()["queued"]) == 1)
	assert(int(hud.queue_invoices_for_ledger()["queued"]) == 0)
	assert(hud._ledger_desk.count() == 1)
	hud.free()


func test_an_invoice_that_was_never_issued_is_not_handed_over() -> void:
	var hud := _hud()
	var draft: InvoiceScript = InvoiceScript.new("INV-1")
	draft.job = "J1"
	draft.customer = {"name": "Smith", "external_id": CLIENT}
	draft.add_line(InvoiceScript.MILESTONE_LINE, "Deposit", 1000, &"EACH",
		MoneyScript.of(1000), &"HARDSCAPE", &"NONE")
	hud._billing_ledger.invoices.append(draft)
	hud._on_billing_changed()
	assert(hud._ledger_desk.count() == 0)
	hud.free()


func test_an_invoice_called_back_is_taken_off_the_outbox_it_was_never_put_in() -> void:
	var hud := _hud()
	var called_back := _invoice("INV-2026-0001")
	called_back.voided_at = "2026-07-01"
	called_back.voided_why = "the customer went elsewhere"
	hud._billing_ledger.invoices.append(called_back)
	hud._on_billing_changed()
	assert(hud._ledger_desk.count() == 0)
	hud.free()


func test_a_hud_with_no_outbox_says_so_rather_than_failing() -> void:
	var hud: HudScript = HudScript.new()
	var handed: Dictionary = hud.queue_invoices_for_ledger()
	# No job desk, no billing ledger: the method builds what it needs and reports an empty hand-over
	# rather than reaching through a null.
	assert(int(handed["queued"]) == 0)
	assert(int(handed["refused"]) == 0)
	hud.free()


func test_a_document_handed_over_through_the_page_moves_the_menu_line() -> void:
	var hud := _hud()
	hud._billing_ledger.invoices.append(_invoice())
	hud.queue_invoices_for_ledger()
	hud._build_ledger_window()
	assert(hud._jobs_text().contains("1 waiting"), hud._jobs_text())
	assert(bool(hud._ledger_window.post_all()["ok"]))
	# The page announced the change, so the line the menu shows is the line the outbox would say now.
	assert(hud._jobs_text().contains("1 handed over"), hud._jobs_text())
	assert(not hud._jobs_text().contains("waiting"), hud._jobs_text())
	hud.free()


const HudNinjaScript := preload("res://scripts/biz/invoice_ninja.gd")