extends Node2D
## A live pass over the **outbox**: an office raises two invoices, hands them to a ledger, posts them,
## and then calls one of them back - and the desk says what it did and what is out of place (spec §9.7,
## §14e).
##
## This is a development tool, not part of the game. It instances the **real main scene** and drives the
## **real billing page**, so the documents it hands over are the shipped ones and not fixtures: what
## lands in the folder is what a customer would have been sent.
##
## The folder it writes to is `user://demo_ledger` and the outbox file is `user://demo_outbox.json`;
## nothing in the game reads either. The HUD's own outbox is only **queued** into here - never posted -
## so the real business folder is left alone. Run `res://scenes/ledger_desk_demo.tscn`.

const MAIN := preload("res://scenes/main.tscn")
const Entity := preload("res://scripts/draft/draft_entity.gd")
const LayerSet := preload("res://scripts/draft/layer_set.gd")
const JobScript := preload("res://scripts/biz/job.gd")
const FileLedgerScript := preload("res://scripts/biz/file_ledger.gd")
const NinjaScript := preload("res://scripts/biz/invoice_ninja.gd")
const AkauntingScript := preload("res://scripts/biz/akaunting.gd")
const DeskScript := preload("res://scripts/biz/ledger_desk.gd")

const FOLDER := "user://demo_ledger"
const OUTBOX_FILE := "user://demo_outbox.json"


func _ready() -> void:
	var main: Node = MAIN.instantiate()
	add_child(main)
	var hud: Node = main.get_node_or_null(^"Hud")
	var controller: Node = main.get_node_or_null(^"DraftController")
	if hud == null or controller == null:
		print("no HUD or no drafting controller in the main scene")
		return

	print("--- the office: a plan, a job, and two invoices ---")
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
	job.set_billing_method(JobScript.MILESTONE)
	hud.open_billing_window()
	hud._billing_window.choose_tax_code(&"HST-ON")
	hud._billing_window.begin_billing()
	hud._billing_window.set_step_fields("Deposit", "25", "10")
	hud._billing_window.add_step()
	hud._billing_window.set_step_fields("Balance", "75")
	hud._billing_window.add_step()
	var first: Dictionary = hud._billing_window.raise_invoice()
	if not bool(first["ok"]):
		print("the deposit invoice was not written: ", first["reason"])
		return
	var deposit = first["invoice"]
	print("raised ", deposit.number, " for ", deposit.total().format_with_currency())
	var second: Dictionary = hud._billing_window.raise_invoice()
	if not bool(second["ok"]):
		print("the balance invoice was not written: ", second["reason"])
		return
	var balance = second["invoice"]
	print("raised ", balance.number, " for ", balance.total().format_with_currency())

	print("--- the outbox the HUD keeps, beside the billing ledger ---")
	var handed: Dictionary = hud.queue_invoices_for_ledger()
	print("handing over everything issued: queued ", handed["queued"], ", refused ", handed["refused"])
	print("the menu line reads: ", hud._jobs_text())
	print("queueing only builds and holds: ", hud._ledger_desk.pending().size(), " waiting, ",
		hud._ledger_desk.count(), " in the outbox")
	hud.open_ledger_window()
	print("the page opens saying: ", hud._ledger_window.opening_words())
	for row: String in hud._ledger_window.row_texts():
		print("  ", row)
	print("with ", hud._ledger_window.post_count(), " post button(s), and nothing on the page takes ",
		"the keyboard: ", hud._ledger_window.buttons_are_focus_free())
	hud.close_ledger_window()

	print("--- a desk of its own, with three ledgers to post to ---")
	var desk: LedgerDesk = DeskScript.new()
	desk.bind(hud._billing_ledger)
	desk.add_adapter(FileLedgerScript.new(FOLDER))
	desk.add_adapter(NinjaScript.new("https://invoicing.co", "a-token"))
	desk.add_adapter(AkauntingScript.new(
		"https://books.example.test", "office@example.test", "a-password"
	))
	print("it can post to: ", desk.adapter_names())
	print("and it starts on ", desk.chosen_adapter().describe(), " because that one always works")
	print("choosing a ledger it does not have is refused: ", desk.choose("quickbooks"))
	print("choosing one it has: ", desk.choose(&"file"))

	print("--- handing over everything that has been issued ---")
	var queued: Dictionary = desk.queue_unhanded()
	print("queued ", queued["queued"], ", refused ", queued["refused"])
	for row: String in desk.row_texts():
		print("  ", row)
	print(desk.describe())

	print("--- the loop: send what the queue still owns, once each ---")
	var ran: Dictionary = desk.post_due()
	print("tried ", ran["tried"], ", taken ", ran["taken"], ", failed ", ran["failed"],
		", waiting ", ran["waiting"], ", wanting a person ", ran["stranded"])
	for row: String in desk.row_texts():
		print("  ", row)
	print(desk.describe())

	print("--- the files it left, one set per document ---")
	for file_name: String in _files_in(FOLDER):
		print("  ", file_name, " - ", _lines_in(FOLDER.path_join(file_name)), " line(s)")

	print("--- the loop again is nothing: a delivered document is not the queue's ---")
	var again: Dictionary = desk.post_due()
	print("tried ", again["tried"], ", waiting ", again["waiting"])

	print("--- a credential belongs in the settings, not in the outbox ---")
	deposit.customer["external_id"] = "AK-1077"
	var to_books: Dictionary = desk.queue_invoice(deposit, "akaunting")
	if not bool(to_books["ok"]):
		print("the invoice could not be built for Akaunting: ", to_books["reason"])
		return
	var held: LedgerPush = to_books["push"]
	var auth: String = String(held.request["headers"].get("Authorization", ""))
	print("in hand the push carries: ", _auth_in_words(auth))
	var as_written: Dictionary = desk.to_dict()
	for row: Dictionary in as_written["pushes"]:
		if String(row["adapter"]) == "akaunting":
			print("written down, that header reads '",
				String(row["request"]["headers"].get("Authorization", "")), "' - the document itself is ",
				"untouched: ", String(row["request"]["url"]))
	print("and nothing of the credential reaches the file: ",
		not JSON.stringify(as_written).contains("a-password"))
	print("at the moment of sending it is put back: ", desk.post(held.key)["reason"])
	print("so the queue still owns it: ", desk.describe())

	print("--- a document a ledger cannot take is refused by name ---")
	var nowhere: Dictionary = desk.queue_invoice(balance, "akaunting")
	print("Akaunting would say: ", nowhere["reason"])
	print("and nothing was queued for it: ", desk.count_for("akaunting"), " push(es)")

	print("--- a document called back after it went ---")
	if hud._billing_window.choose_invoice(balance.id):
		hud._billing_window.set_why("the customer changed the scope")
		var called_back: Dictionary = hud._billing_window.void_invoice()
		print("called back: ", called_back["ok"], " - ", hud._billing_window.status_text())
	for line: String in desk.reconcile_words():
		print("  ", line)
	print("reconciliation changes nothing: ", desk.count(), " push(es) still in the outbox")

	print("--- the outbox on disk ---")
	print("writing it: ", desk.write(OUTBOX_FILE))
	var reread: LedgerDesk = DeskScript.new()
	reread.bind(hud._billing_ledger)
	print("reading it back: ", reread.read(OUTBOX_FILE), " - ", reread.count(), " push(es), ",
		reread.summary_text())

	print("--- the desk's last words ---")
	print(desk.describe())
	print("sound? ", desk.is_sound(), "   things wanting a person: ", desk.issues())
	for said: String in desk.problems():
		print("  ", said)


## An HTTP Basic header as a person reads it, so the demo never prints a credential it did not mean to
## print alone: `Basic <base64>` becomes the user and password it was made from.
func _auth_in_words(header: String) -> String:
	var trimmed: String = header.trim_prefix("Basic ")
	if trimmed == header:
		return header
	return "Basic %s (as '%s')" % [header, Marshalls.base64_to_utf8(trimmed)]


func _files_in(folder: String) -> PackedStringArray:
	if not DirAccess.dir_exists_absolute(folder):
		return PackedStringArray()
	var names: PackedStringArray = DirAccess.get_files_at(folder)
	names.sort()
	return names


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