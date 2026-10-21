extends Node2D
## A live pass over the ledger: a plan priced, a job made, an invoice raised, and that invoice posted
## to the file backend - JSON, CSV and IIF - with the outbox recording where it went (spec §9.6, §9.7).
##
## This is a development tool, not part of the game. It instances the **real main scene** and drives the
## **real billing page** through the methods its controls call, so the document it posts is the shipped
## one and not a fixture: what lands in the folder is what a customer would have been sent.
##
## The folder it writes to is `user://demo_ledger`, and nothing in the game reads it. Run
## `res://scenes/ledger_demo.tscn`.

const MAIN := preload("res://scenes/main.tscn")
const Entity := preload("res://scripts/draft/draft_entity.gd")
const LayerSet := preload("res://scripts/draft/layer_set.gd")
const JobScript := preload("res://scripts/biz/job.gd")
const FileLedgerScript := preload("res://scripts/biz/file_ledger.gd")
const NinjaScript := preload("res://scripts/biz/invoice_ninja.gd")
const AkauntingScript := preload("res://scripts/biz/akaunting.gd")
const LedgerScript := preload("res://scripts/biz/ledger_adapter.gd")
const PaymentScript := preload("res://scripts/biz/payment.gd")
const LedgerPushScript := preload("res://scripts/biz/ledger_push.gd")


func _ready() -> void:
	var main: Node = MAIN.instantiate()
	add_child(main)
	var hud: Node = main.get_node_or_null(^"Hud")
	var controller: Node = main.get_node_or_null(^"DraftController")
	if hud == null or controller == null:
		print("no HUD or no drafting controller in the main scene")
		return

	print("--- a plan priced, sent, and made into a job ---")
	controller.document.add(
		Entity.make_rectangle(Vector2(0, 0), Vector2(6, 4)), LayerSet.NEW_HARDSCAPE
	)
	controller.document.add(Entity.make_circle(Vector2(20, 0), 1.5), LayerSet.NEW_PLANTING)
	hud.open_estimate_window()
	hud._estimate_window.take_off()
	hud._estimate_window.set_recipient("Smith, back garden")
	hud._estimate_window.send_it()
	var started: Dictionary = hud._estimate_window.start_job()
	print("the hand-off was accepted: ", started["ok"])
	var job_id: String = hud._job_desk.job_ids()[0]
	var job = hud._job_desk.job(job_id)
	print("the job is ", hud._job_desk.job_label(job_id), ", a contract of ",
		job.contract_sum.format_with_currency())

	print("--- an invoice for the whole contract, taxed ---")
	job.set_billing_method(JobScript.MILESTONE)
	hud.open_billing_window()
	hud._billing_window.choose_tax_code(&"HST-ON")
	print("started billing: ", hud._billing_window.begin_billing())
	hud._billing_window.set_step_fields("Deposit", "25", "10")
	print("the deposit: ", hud._billing_window.add_step())
	hud._billing_window.set_step_fields("Balance", "75")
	print("the balance: ", hud._billing_window.add_step())
	var raised: Dictionary = hud._billing_window.raise_invoice()
	print("written: ", raised["ok"], "  and the page says: ", hud._billing_window.status_text())
	if not bool(raised["ok"]):
		return
	var invoice = raised["invoice"]
	print("the document: ", invoice.describe())

	print("--- what the ledger is ---")
	var ledger = FileLedgerScript.new("user://demo_ledger")
	print(ledger.describe())
	print("it needs nothing configured: ", ledger.is_configured(), ", and can: ", ledger.capabilities())
	print("its test button: ", ledger.self_test())

	print("--- the push, built but not sent ---")
	var key: String = ledger.key_for_invoice(invoice)
	var built: Dictionary = ledger.build_invoice_push(invoice, key)
	print("built: ", built["ok"], " as a ", built["request"]["method"], " to ",
		built["request"]["url"])
	print("the key is derived from the document, so a retry sends the same one: ", key)
	var push = LedgerPushScript.for_document(
		String(ledger.name()), built["kind"], invoice.id, invoice.number, key,
		built["request"], Time.get_date_string_from_system()
	)
	print("queued: ", push.describe())

	print("--- and sent: the folder is the ledger ---")
	var response: Dictionary = ledger.send(push.request)
	var read: Dictionary = ledger.parse_invoice_response(response)
	print("the ledger answered ", response["status"], " naming ", read["external_id"])
	print("it took the document: ", push.record_response(response, read, Time.get_date_string_from_system()))
	print("the push now reads: ", push.describe())

	print("--- the files it left ---")
	for file_name: String in ["%s.json" % invoice.number, "%s.csv" % invoice.number,
			"%s.iif" % invoice.number, FileLedgerScript.LEDGER_FILE]:
		print("  ", ledger.folder.path_join(file_name), " - ",
			_lines_in(ledger.folder.path_join(file_name)), " line(s)")

	print("--- sending it again is not a second document ---")
	var again: Dictionary = ledger.send(push.request)
	print("the second send answered ", again["status"], " and the same single file holds it: ",
		FileAccess.file_exists(ledger.folder.path_join("%s.json" % invoice.number)))
	print("the office's book has one row for it: ",
		_lines_in(ledger.folder.path_join(FileLedgerScript.LEDGER_FILE)), " line(s)")

	print("--- a refusal is a person's to fix; a busy server is the queue's to try again ---")
	var refused_read: Dictionary = ledger.parse_common({"status": 401, "body": {"message": "token expired"}})
	var refused = LedgerPushScript.for_document(String(ledger.name()), built["kind"], invoice.id,
		invoice.number, "a-second-key", built["request"], Time.get_date_string_from_system())
	refused.record_response({"status": 401, "body": {}}, refused_read, Time.get_date_string_from_system())
	print("refused: ", refused.describe())
	var busy_read: Dictionary = ledger.parse_common({"status": 503, "error": "connection reset"})
	var busy = LedgerPushScript.for_document(String(ledger.name()), built["kind"], invoice.id,
		invoice.number, "a-third-key", built["request"], Time.get_date_string_from_system())
	busy.record_response({"status": 503, "error": "connection reset"}, busy_read, Time.get_date_string_from_system())
	print("busy: ", busy.describe())

	print("--- the same document against a hosted ledger ---")
	# The two hosted backends build a real request for the same invoice. Neither is claimed to do more
	# than it does, and neither can be probed yet: a probe has to be sent, and the transport that sends
	# arrives with sync. Each says so instead of a green light that verified nothing.
	var payment = PaymentScript.new("PMT-0001")
	payment.invoice = invoice.id
	payment.received_at = "2026-06-20"
	payment.amount = invoice.balance()
	payment.bank_reference = "chq 1041"
	for hosted in [
		NinjaScript.new("https://invoicing.co", "a-token"),
		AkauntingScript.new("https://books.example.test", "office@example.test", "a-password"),
	]:
		print("  ", hosted.describe())
		print("    invoices: ", hosted.can(LedgerScript.INVOICES),
			"  payments: ", hosted.can(LedgerScript.PAYMENTS),
			"  credit notes: ", hosted.can(LedgerScript.CREDITS),
			"  idempotency: ", hosted.can(LedgerScript.IDEMPOTENCY))
		print("    ", hosted.cannot_text(LedgerScript.CREDITS))
		var posting: Dictionary = hosted.build_invoice_push(invoice, hosted.key_for_invoice(invoice))
		var what: String = ""
		if bool(posting["ok"]):
			what = "post to %s" % String(posting["request"]["url"])
		else:
			what = "refuse, saying: %s" % String(posting["reason"])
		print("    it would ", what)
		var orphan: Dictionary = hosted.build_payment_push(
			payment, invoice, hosted.key_for_payment(payment, invoice)
		)
		print("    and each names the first thing a person has to record: ", orphan["reason"])
		print("    its test button: ", hosted.self_test()["reason"])


func _lines_in(path: String) -> int:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return 0
	var count: int = 0
	for entry in file.get_as_text().split("\n"):
		if not entry.strip_edges().is_empty():
			count += 1
	file.close()
	return count