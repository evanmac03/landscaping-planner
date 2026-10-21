extends Node
## The file backend: JSON, CSV and IIF, and the "always works" ledger (spec §9.6).
##
## Three properties are under test. **An invoice leaves three files and one row**, and the row book does
## not gain a second row when the same document is written again - the file name is the key. **Nothing
## here works money out**: every figure is read from the document the invoice produced, which is why
## the column foots to the printed subtotal by construction. And **the IIF nets to zero**, with the
## transaction carrying the total and the splits summing to its negative, which is what makes it an
## import a bookkeeper's system accepts rather than a text file that looks like one.

const FileLedgerScript := preload("res://scripts/biz/file_ledger.gd")
const LedgerScript := preload("res://scripts/biz/ledger_adapter.gd")
const InvoiceScript := preload("res://scripts/biz/invoice.gd")
const PaymentScript := preload("res://scripts/biz/payment.gd")
const MoneyScript := preload("res://scripts/biz/money.gd")


func _folder(tag: String) -> String:
	var path: String = "user://ledger_test/%s" % tag
	var dir: DirAccess = DirAccess.open(path)
	if dir != null:
		for entry: String in dir.get_files():
			dir.remove(entry)
	# Removed as well as emptied, so a test that asserts the folder is *made* is testing this run and
	# not the leftovers of the last one.
	if DirAccess.dir_exists_absolute(path):
		DirAccess.remove_absolute(path)
	return path


func _ledger(tag: String) -> FileLedgerScript:
	return FileLedgerScript.new(_folder(tag))


func _invoice(tax_code: StringName = &"NONE", retainage_cents: int = 0) -> InvoiceScript:
	var invoice: InvoiceScript = InvoiceScript.new("INV1")
	invoice.job = "J1"
	invoice.customer = {"name": "Smith, back garden"}
	invoice.add_amount(InvoiceScript.MILESTONE_LINE, "Deposit", MoneyScript.of(50000), &"HARDSCAPE", tax_code)
	if retainage_cents > 0:
		invoice.set_retainage(MoneyScript.of(retainage_cents))
	assert(bool(invoice.issue("2026-06-10", 30, "INV-2026-0001")["ok"]))
	return invoice


func _text(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var got: String = file.get_as_text()
	file.close()
	return got


func _lines(path: String) -> Array:
	var out: Array = []
	for entry in _text(path).split("\n"):
		if not entry.strip_edges().is_empty():
			out.append(entry)
	return out


func _rows_of(text: String) -> Array:
	var out: Array = []
	for entry in text.split("\r\n"):
		if not entry.strip_edges().is_empty():
			out.append(entry)
	return out


func _amount_in(row: String) -> String:
	return row.split("\t")[5]


# --- what this backend is -----------------------------------------------------------------------


func test_the_file_backend_needs_nothing_and_is_configured_as_it_is() -> void:
	var ledger := _ledger("config")
	assert(ledger.name() == &"file")
	assert(ledger.is_configured())
	assert(ledger.problems().is_empty())
	var caps: Dictionary = ledger.capabilities()
	assert(bool(caps["invoices"]))
	assert(bool(caps["payments"]))
	assert(bool(caps["credits"]))
	# The file name is the key, so a second write cannot duplicate a document; but a PDF beside the
	# JSON is somebody else's job.
	assert(bool(caps["idempotency"]))
	assert(not bool(caps["attachments"]))
	assert(ledger.describe().contains("config"), ledger.describe())


func test_the_folder_is_the_one_setting_it_has() -> void:
	var ledger := _ledger("setting")
	assert(ledger.settings().size() == 1)
	assert(ledger.setting(&"folder") == ledger.folder)
	assert(ledger.set_setting(&"folder", "user://elsewhere"))
	assert(ledger.folder == "user://elsewhere")
	# A field this backend does not have is refused, so a settings page cannot store a value that will
	# never be read.
	assert(not ledger.set_setting(&"token", "abc"))
	assert(not ledger.set_setting(&"folder", "   "))
	assert(ledger.setting(&"token") == "")
	var empty: FileLedgerScript = FileLedgerScript.new("")
	assert(not empty.problems().is_empty())
	assert(empty.problems()[0].contains("no folder"), empty.problems()[0])
	# A backend is configured exactly when nothing is wrong with its settings.
	assert(not empty.is_configured())


# --- building and sending -----------------------------------------------------------------------


func test_the_request_is_a_write_to_the_number_the_invoice_was_given() -> void:
	var ledger := _ledger("request")
	var invoice := _invoice()
	var key: String = ledger.key_for_invoice(invoice)
	var built: Dictionary = ledger.build_invoice_push(invoice, key)
	assert(bool(built["ok"]))
	assert(built["kind"] == LedgerScript.INVOICE_KIND)
	var request: Dictionary = built["request"]
	assert(String(request["method"]) == "WRITE")
	assert(String(request["url"]).ends_with("INV-2026-0001.json"), String(request["url"]))
	assert(String(request["url"]).begins_with("user://ledger_test/request"), String(request["url"]))
	assert(String(request["headers"][LedgerScript.KEY_HEADER]) == key)
	assert(String(request["body"]["number"]) == "INV-2026-0001")


func test_an_invoice_leaves_three_files_and_one_row() -> void:
	var ledger := _ledger("bundle")
	var invoice := _invoice()
	var built: Dictionary = ledger.build_invoice_push(invoice, ledger.key_for_invoice(invoice))
	var sent: Dictionary = ledger.send(built["request"])
	assert(int(sent["status"]) == 200, str(sent))
	assert(String(sent["body"]["number"]) == "INV-2026-0001")
	var folder: String = ledger.folder
	assert(FileAccess.file_exists(folder.path_join("INV-2026-0001.json")))
	assert(FileAccess.file_exists(folder.path_join("INV-2026-0001.csv")))
	assert(FileAccess.file_exists(folder.path_join("INV-2026-0001.iif")))
	# The font of the office's own book: a header once, then one row per invoice.
	var book: Array = _lines(folder.path_join(FileLedgerScript.LEDGER_FILE))
	assert(book.size() == 2, str(book))
	assert(book[0] == FileLedgerScript.LEDGER_HEADER)
	assert(String(book[1]).begins_with("INV-2026-0001,2026-06-10,"), String(book[1]))
	# A path read back by the adapter names the document it wrote.
	var read: Dictionary = ledger.parse_invoice_response(sent)
	assert(bool(read["ok"]))
	assert(String(read["external_id"]).ends_with("INV-2026-0001.json"))


func test_writing_the_same_document_twice_lands_on_the_same_file_and_one_row() -> void:
	var ledger := _ledger("idempotent")
	var invoice := _invoice()
	var built: Dictionary = ledger.build_invoice_push(invoice, ledger.key_for_invoice(invoice))
	assert(int(ledger.send(built["request"])["status"]) == 200)
	assert(int(ledger.send(built["request"])["status"]) == 200)
	var book: Array = _lines(ledger.folder.path_join(FileLedgerScript.LEDGER_FILE))
	assert(book.size() == 2, "a retry does not add a second row to the book: %s" % str(book))
	var dir: DirAccess = DirAccess.open(ledger.folder)
	assert(dir.get_files().size() == 4, str(dir.get_files()))


func test_the_folder_is_made_before_it_is_written_to() -> void:
	var ledger := _ledger("made")
	assert(not DirAccess.dir_exists_absolute(ledger.folder))
	var invoice := _invoice()
	var built: Dictionary = ledger.build_invoice_push(invoice, ledger.key_for_invoice(invoice))
	assert(int(ledger.send(built["request"])["status"]) == 200)
	assert(DirAccess.dir_exists_absolute(ledger.folder))


func test_a_folder_that_cannot_be_reached_fails_the_push_rather_than_pretending() -> void:
	var nowhere: FileLedgerScript = FileLedgerScript.new("")
	var invoice := _invoice()
	var built: Dictionary = nowhere.build_invoice_push(invoice, nowhere.key_for_invoice(invoice))
	var sent: Dictionary = nowhere.send(built["request"])
	assert(int(sent["status"]) == 0)
	assert(String(sent["error"]).contains("could not be opened"), String(sent["error"]))


func test_a_request_that_is_not_a_write_is_refused_rather_than_ignored() -> void:
	var ledger := _ledger("notawrite")
	var sent: Dictionary = ledger.send({"method": "POST", "url": "https://example.test", "body": {}})
	assert(int(sent["status"]) == 0)
	assert(String(sent["error"]).contains("cannot send a POST request"), String(sent["error"]))


func test_the_test_button_writes_and_reads_back() -> void:
	var ledger := _ledger("selftest")
	var tested: Dictionary = ledger.self_test()
	assert(bool(tested["ok"]), String(tested["reason"]))
	assert(String(tested["reason"]).contains("_selftest.txt"), String(tested["reason"]))
	assert(FileAccess.file_exists(ledger.folder.path_join("_selftest.txt")))
	var nowhere: FileLedgerScript = FileLedgerScript.new("")
	assert(not bool(nowhere.self_test()["ok"]))


func test_a_payment_and_a_credit_note_leave_their_own_files() -> void:
	var ledger := _ledger("others")
	var invoice := _invoice()
	var payment: PaymentScript = PaymentScript.new("PMT-0001")
	payment.invoice = "INV1"
	payment.received_at = "2026-06-20"
	payment.amount = MoneyScript.of(50000)
	var paid: Dictionary = ledger.build_payment_push(payment, invoice, ledger.key_for_payment(payment, invoice))
	assert(bool(paid["ok"]))
	assert(int(ledger.send(paid["request"])["status"]) == 200)
	assert(FileAccess.file_exists(ledger.folder.path_join("PMT-0001.json")))
	var note: CreditNote = CreditNote.new("CN1")
	note.job = "J1"
	note.set_amount(MoneyScript.of(50000))
	note.set_against("INV-2026-0001", "overbilled")
	assert(bool(note.issue("2026-06-21", "CN-2026-0001")["ok"]))
	var credited: Dictionary = ledger.build_credit_push(note, ledger.key_for_credit(note))
	assert(bool(credited["ok"]))
	assert(int(ledger.send(credited["request"])["status"]) == 200)
	var text: String = _text(ledger.folder.path_join("CN-2026-0001.json"))
	assert(text.contains("\"credit\""), text)


# --- the files, as text -------------------------------------------------------------------------


func test_the_json_is_the_document_that_was_posted_figures_and_all() -> void:
	var ledger := _ledger("json")
	var invoice := _invoice(&"HST-ON")
	var key: String = ledger.key_for_invoice(invoice)
	var built: Dictionary = ledger.build_invoice_push(invoice, key)
	assert(int(ledger.send(built["request"])["status"]) == 200)
	var parsed: Variant = JSON.parse_string(_text(ledger.folder.path_join("INV-2026-0001.json")))
	assert(parsed is Dictionary)
	var row: Dictionary = parsed
	assert(String(row["number"]) == "INV-2026-0001")
	assert(String(row["client_key"]) == key)
	assert(String(row["kind"]) == "invoice")
	# The figures are the invoice's own, read rather than recomputed: a second place for the rounding
	# rule to live is exactly what §9.5 forbids.
	assert(int(row["subtotal"]["cents"]) == invoice.subtotal().cents)
	assert(int(row["tax"]["cents"]) == invoice.tax().cents)
	assert(int(row["total"]["cents"]) == invoice.total().cents)
	assert(String(row["currency_iso"]) == "CAD")


func test_the_csv_holds_the_invoices_own_lines_and_quotes_what_has_to_be_quoted() -> void:
	var ledger := _ledger("csv")
	var invoice := _invoice()
	var built: Dictionary = ledger.build_invoice_push(invoice, ledger.key_for_invoice(invoice))
	assert(int(ledger.send(built["request"])["status"]) == 200)
	var rows: Array = _lines(ledger.folder.path_join("INV-2026-0001.csv"))
	assert(rows.size() == 2, str(rows))
	assert(rows[0] == FileLedgerScript.LINE_HEADER)
	# The customer's name has a comma in it, so the field is quoted rather than allowed to split the row.
	assert(String(rows[1]).begins_with("INV-2026-0001,2026-06-10,\"Smith, back garden\",Deposit,EACH,1,500.00,500.00,NONE,HARDSCAPE"), String(rows[1]))


func test_a_machines_amount_has_no_symbol_and_no_thousands_separator() -> void:
	assert(FileLedgerScript.plain_amount(MoneyScript.of(123456)) == "1234.56")
	assert(FileLedgerScript.plain_amount(MoneyScript.of(-123456)) == "-1234.56")
	assert(FileLedgerScript.plain_amount(MoneyScript.of(50000)) == "500.00")
	assert(FileLedgerScript.plain_amount(MoneyScript.zero()) == "0.00")
	assert(FileLedgerScript.plain_amount(MoneyScript.invalid()) == "")
	assert(FileLedgerScript.plain_quantity(InvoiceScript.QUANTITY_MILLI) == "1")
	assert(FileLedgerScript.plain_quantity(3500) == "3.5")
	assert(FileLedgerScript.plain_quantity(1500) == "1.5")
	assert(FileLedgerScript.plain_quantity(1005) == "1.005")
	assert(FileLedgerScript.plain_quantity(0) == "")


func test_a_quoted_field_survives_the_quotes_inside_it() -> void:
	assert(FileLedgerScript.csv_field("plain") == "plain")
	assert(FileLedgerScript.csv_field("Hosta, blue") == "\"Hosta, blue\"")
	assert(FileLedgerScript.csv_field("a \"quoted\" name") == "\"a \"\"quoted\"\" name\"")


func test_a_name_usable_as_a_file_name_does_not_become_a_path() -> void:
	assert(FileLedgerScript.safe_name("INV-2026-0001") == "INV-2026-0001")
	assert(FileLedgerScript.safe_name("a/b c") == "a_b_c")
	assert(FileLedgerScript.safe_name("") == "document")
	assert(FileLedgerScript.safe_name("   ") == "document")


# --- the QuickBooks import ----------------------------------------------------------------------


func test_the_iif_nets_to_zero() -> void:
	var ledger := _ledger("iif")
	var invoice := _invoice(&"HST-ON")
	var built: Dictionary = ledger.build_invoice_push(invoice, ledger.key_for_invoice(invoice))
	assert(int(ledger.send(built["request"])["status"]) == 200)
	var rows: Array = _rows_of(_text(ledger.folder.path_join("INV-2026-0001.iif")))
	var transaction_cents: int = 0
	var split_cents: int = 0
	var splits: int = 0
	for row: String in rows:
		if row.begins_with("TRNS\t"):
			transaction_cents = MoneyScript.parse(_amount_in(row)).cents
		elif row.begins_with("SPL\t"):
			split_cents += MoneyScript.parse(_amount_in(row)).cents
			splits += 1
	# Deposit 500.00 plus HST 13% = 65.00, so the transaction is 565.00, the income split is -500.00 and
	# the tax split is -65.00: they cancel, which is what makes the ledger balance.
	assert(transaction_cents == 56500, str(transaction_cents))
	assert(splits == 2, str(splits))
	assert(split_cents == -transaction_cents, "%d vs %d" % [split_cents, transaction_cents])
	assert(rows[0].begins_with("!TRNS\t"), rows[0])
	assert(rows[1].begins_with("!SPL\t"), rows[1])
	assert(rows[2] == "!ENDTRNS")
	assert(String(rows[rows.size() - 1]) == "ENDTRNS")


func test_a_retainage_is_a_positive_split_against_a_liability() -> void:
	var ledger := _ledger("retainage")
	var invoice := _invoice(&"NONE", 5000)
	var built: Dictionary = ledger.build_invoice_push(invoice, ledger.key_for_invoice(invoice))
	assert(int(ledger.send(built["request"])["status"]) == 200)
	var text: String = _text(ledger.folder.path_join("INV-2026-0001.iif"))
	# Retainage reduced what the customer owes without reducing what was earned, so it is not another
	# negative line: it is a positive split against the liability account.
	assert(text.contains(FileLedgerScript.IIF_RETAINAGE), text)
	var splits: int = 0
	var split_cents: int = 0
	for row: String in _rows_of(text):
		if row.begins_with("SPL\t"):
			splits += 1
			split_cents += MoneyScript.parse(_amount_in(row)).cents
	assert(splits == 2, str(splits))
	# Deposit 500.00, no tax, 50.00 retained: the splits are -500.00 and +50.00 against a 450.00 total.
	assert(split_cents == -45000, str(split_cents))


func test_the_iif_dates_are_the_way_an_importer_reads_them() -> void:
	assert(FileLedgerScript.iif_date("2026-06-10") == "06/10/2026")
	assert(FileLedgerScript.iif_date("2026-12-01") == "12/01/2026")
	# Left alone when it is not a date, so damage shows as damage rather than a confident wrong day.
	assert(FileLedgerScript.iif_date("not a date") == "not a date")
	assert(FileLedgerScript.iif_date("2026-06") == "2026-06")


func test_the_iif_is_tab_delimited_with_carriage_returns() -> void:
	var doc: Dictionary = {
		"number": "INV-2026-0001",
		"issued_at": "2026-06-10",
		"customer": {"name": "Smith"},
		"lines": [{"description": "Deposit", "amount": {"cents": 50000, "currency": "CAD"}}],
		"subtotal": {"cents": 50000, "currency": "CAD"},
		"tax": {"cents": 0, "currency": "CAD"},
		"retainage_total": {"cents": 0, "currency": "CAD"},
		"total": {"cents": 50000, "currency": "CAD"},
		"tax_lines": [],
	}
	var text: String = FileLedgerScript.iif_of(doc)
	assert(text.contains("\t"), "the columns are tab separated")
	assert(text.contains("\r\n"), "an importer expects carriage returns")
	assert(not text.replace("\r\n", "").contains("\n"), "no bare newline is left")
	assert(text.ends_with("\r\n"))
	# A tab in a description would split the row it is in.
	var tabbed: Dictionary = doc.duplicate(true)
	tabbed["lines"] = [{"description": "a\tb", "amount": {"cents": 100, "currency": "CAD"}}]
	assert(not FileLedgerScript.iif_of(tabbed).contains("a\tb"))