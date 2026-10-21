class_name FileLedger
extends LedgerAdapter
## The ledger that is a folder (spec §9.6): JSON, CSV and IIF, and nothing to configure.
##
## It is the **default** because it always works. A business with no accounting software still needs
## an invoice to leave as a file its bookkeeper can open; a business running QuickBooks Desktop needs
## the **IIF**, which is the only door into it; and a business that does have a hosted ledger still
## gets a JSON copy of everything the program posted, which is what makes a later migration a copy
## rather than a reconciliation.
##
## An invoice leaves **three files and one row**:
##
## | file | who reads it |
## |---|---|
## | `<number>.json` | another program; the invoice document, exactly as it was posted |
## | `<number>.csv` | a spreadsheet: one row per line |
## | `<number>.iif` | QuickBooks Desktop, tab-delimited, `\r\n` |
## | `ledger.csv` | the office: one appended row per invoice, the fee book |
##
## The "request" it builds is a **file write**, not an HTTP call - `{"method": "WRITE", url: <path>}` -
## so the outbox retries and de-duplicates a file exactly as it does a POST, and the file backend is a
## ledger the whole push machinery works with rather than a special case beside it. The file name *is*
## the key: writing the same document twice lands on the same file.
##
## Nothing here works money out. Every figure is read from the request body, which came from the
## invoice's own `to_dict()` and `totals()` (§9.5), so the file and the printed page cannot disagree.

const DEFAULT_FOLDER := "user://biz/ledger"

const JSON_EXT := "json"
const CSV_EXT := "csv"
const IIF_EXT := "iif"

## The appended row-per-invoice book, and the columns of both CSVs. Named once, because a bookkeeper
## lines a spreadsheet up against these headers.
const LEDGER_FILE := "ledger.csv"
const LEDGER_HEADER := "number,date,due,customer,subtotal,tax,retainage,total,balance"
const LINE_HEADER := "number,date,customer,description,unit,quantity,rate,amount,tax_code,cost_code"

## The QuickBooks accounts an import needs, named once so a business can change them in one place. The
## splits of an invoice are the lines (negative, income), the tax (negative, a liability) and the
## retainage (positive, a liability), and they sum to the negative of the total - which is what makes
## the transaction net to zero in the ledger.
const IIF_TRNSTYPE := "INVOICE"
const IIF_RECEIVABLE := "Accounts Receivable"
const IIF_INCOME := "Income:Landscaping"
const IIF_TAX := "Current Liabilities:Sales Tax"
const IIF_RETAINAGE := "Current Liabilities:Retainage Payable"
const IIF_COLUMNS := ["TRNSTYPE", "DATE", "ACCNT", "NAME", "AMOUNT", "DOCNUM", "MEMO"]

const TAB := "\t"
const CRLF := "\r\n"

var folder: String = DEFAULT_FOLDER


func _init(directory: String = DEFAULT_FOLDER) -> void:
	folder = directory


# --- what this backend is -----------------------------------------------------------------------


func name() -> StringName:
	return &"file"


func describe() -> String:
	return "a folder of files (%s)" % folder


func capabilities() -> Dictionary:
	var out: Dictionary = super()
	out["invoices"] = true
	out["payments"] = true
	# A credit note is a document like any other here, and posting it is a file write like any other.
	out["credits"] = true
	out["customers"] = true
	# The file name is the key: a second write of the same document lands on the same file, so a retry
	# cannot duplicate anything. This is the one backend for which idempotency is not a network
	# property but a filesystem one.
	out["idempotency"] = true
	# A PDF beside the JSON is a person's job or a hosted backend's, not this one's.
	out["attachments"] = false
	return out


func settings() -> Array[Dictionary]:
	return [{"key": "folder", "name": "Folder", "secret": false}]


func setting(key: StringName) -> String:
	if key == &"folder":
		return folder
	return ""


func set_setting(key: StringName, value: String) -> bool:
	if key != &"folder":
		return false
	if value.strip_edges().is_empty():
		return false
	folder = value.strip_edges()
	return true


func problems() -> Array[String]:
	if folder.strip_edges().is_empty():
		return ["a folder of files with no folder to write to"]
	return []


# --- building a push (pure) ---------------------------------------------------------------------


func invoice_request(invoice: Invoice, idempotency_key: String) -> Dictionary:
	var body: Dictionary = invoice_body(invoice, idempotency_key)
	var headers: Dictionary = {KEY_HEADER: idempotency_key}
	return asked(INVOICE_KIND, make_request(&"WRITE", path_for(invoice.number, JSON_EXT), headers, body))


func payment_request(payment: Payment, invoice: Invoice, idempotency_key: String,
		_external_invoice_id: String = "") -> Dictionary:
	var body: Dictionary = payment_body(payment, invoice, idempotency_key)
	var headers: Dictionary = {KEY_HEADER: idempotency_key}
	return asked(PAYMENT_KIND, make_request(&"WRITE", path_for(payment.id, JSON_EXT), headers, body))


func credit_request(credit: CreditNote, idempotency_key: String) -> Dictionary:
	var body: Dictionary = credit_body(credit, idempotency_key)
	var headers: Dictionary = {KEY_HEADER: idempotency_key}
	return asked(CREDIT_KIND, make_request(&"WRITE", path_for(credit.number, JSON_EXT), headers, body))


# --- sending it: the files ----------------------------------------------------------------------


## The file backend's transport is the disk. `WRITE` means "write the document the request carries to
## the path it names"; anything else is refused rather than silently ignored, so a mistake shows up as
## a failed push instead of a file that was never written.
func send(request: Dictionary) -> Dictionary:
	var method: String = String(request.get("method", ""))
	if method != "WRITE":
		return {"status": 0, "error": "%s cannot send a %s request" % [describe(), method], "body": {}}
	var body: Dictionary = {}
	var body_in: Variant = request.get("body", {})
	if body_in is Dictionary:
		body = body_in
	var path: String = String(request.get("url", ""))
	if not _make_folder():
		return {"status": 0, "error": "the folder %s could not be opened" % folder, "body": {}}
	if not _write_text(path, JSON.stringify(body, "\t")):
		return {"status": 0, "error": "the file %s could not be written" % path, "body": {}}
	var kind: String = String(body.get("kind", "invoice"))
	if kind == String(INVOICE_KIND):
		_write_text(path_for(String(body.get("number", "")), CSV_EXT), csv_of(body))
		_write_text(path_for(String(body.get("number", "")), IIF_EXT), iif_of(body))
		_append_summary(body)
	return {
		"status": 200,
		"headers": {},
		"body": {"id": path, "number": String(body.get("number", ""))},
	}


## The adapter's "test" button: write a marker into the folder and read it back, which answers "can
## this business post an invoice at all" without posting one.
func self_test() -> Dictionary:
	if not _make_folder():
		return {"ok": false, "reason": "the folder %s could not be opened" % folder}
	var path: String = folder.path_join("_selftest.txt")
	var stamp: String = "landscaping-planner ledger self test"
	if not _write_text(path, stamp):
		return {"ok": false, "reason": "the folder %s could not be written to" % folder}
	var read: FileAccess = FileAccess.open(path, FileAccess.READ)
	if read == null:
		return {"ok": false, "reason": "a file was written to %s but could not be read back" % folder}
	var got: String = read.get_as_text()
	read.close()
	if got != stamp:
		return {"ok": false, "reason": "a file was written to %s but read back wrong" % folder}
	return {"ok": true, "reason": "wrote and read back %s" % path}


# --- the files, as text -------------------------------------------------------------------------


## One row per line of the invoice. The rate and the amount are the invoice's own; nothing is worked
## out here, which is why the column foots to the printed subtotal by construction.
static func csv_of(document: Dictionary) -> String:
	var number: String = String(document.get("number", ""))
	var date: String = String(document.get("issued_at", ""))
	var customer: String = customer_name_of(document)
	var rows: Array[String] = [LINE_HEADER]
	for entry: Dictionary in lines_of(document):
		var rate: Money = MoneyScript.from_dict(entry.get("rate", {}))
		var amount: Money = MoneyScript.from_dict(entry.get("amount", {}))
		var fields := PackedStringArray()
		fields.append(csv_field(number))
		fields.append(csv_field(date))
		fields.append(csv_field(customer))
		fields.append(csv_field(String(entry.get("description", ""))))
		fields.append(csv_field(String(entry.get("unit", ""))))
		fields.append(csv_field(plain_quantity(int(entry.get("quantity_milli", 0)))))
		fields.append(csv_field(plain_amount(rate)))
		fields.append(csv_field(plain_amount(amount)))
		fields.append(csv_field(String(entry.get("tax_code", ""))))
		fields.append(csv_field(String(entry.get("cost_code", ""))))
		rows.append(",".join(fields))
	return "\n".join(rows) + "\n"


## The one appended row of `ledger.csv`: what the invoice came to, side by side, in the order the
## header names them.
static func summary_row_of(document: Dictionary) -> String:
	var fields := PackedStringArray()
	fields.append(csv_field(String(document.get("number", ""))))
	fields.append(csv_field(String(document.get("issued_at", ""))))
	fields.append(csv_field(String(document.get("due_at", ""))))
	fields.append(csv_field(customer_name_of(document)))
	for key: String in ["subtotal", "tax", "retainage_total", "total", "balance"]:
		fields.append(csv_field(plain_amount(MoneyScript.from_dict(document.get(key, {})))))
	return ",".join(fields)


## The QuickBooks Desktop import. Tabs, `\r\n` lines, dates as MM/DD/YYYY, and amounts with no symbol
## and no thousands separator - a spreadsheet will re-format a number, but an importer will refuse one.
##
## The transaction carries the total and the splits carry its parts, summing to the negative of the
## total so the whole thing nets to zero. The retainage split is *positive* against a liability: it
## reduced what the customer owes without reducing what was earned, which is why it is not simply
## another negative line.
static func iif_of(document: Dictionary) -> String:
	var number: String = String(document.get("number", ""))
	var date: String = iif_date(String(document.get("issued_at", "")))
	var customer: String = customer_name_of(document)
	var rows := PackedStringArray()
	rows.append(iif_header("TRNS"))
	rows.append(iif_header("SPL"))
	rows.append("!ENDTRNS")
	rows.append(iif_row("TRNS", date, IIF_RECEIVABLE, customer,
		plain_amount(MoneyScript.from_dict(document.get("total", {}))), number,
		String(document.get("note", ""))))
	for entry: Dictionary in lines_of(document):
		var amount: Money = MoneyScript.from_dict(entry.get("amount", {}))
		rows.append(iif_row("SPL", date, IIF_INCOME, customer, plain_amount(amount.neg()), number,
			String(entry.get("description", ""))))
	var tax: Money = MoneyScript.from_dict(document.get("tax", {}))
	if not tax.is_zero():
		rows.append(iif_row("SPL", date, IIF_TAX, customer, plain_amount(tax.neg()), number,
			tax_label_of(document)))
	var retainage: Money = MoneyScript.from_dict(document.get("retainage_total", {}))
	if not retainage.is_zero():
		rows.append(iif_row("SPL", date, IIF_RETAINAGE, customer, plain_amount(retainage), number,
			"Retainage withheld"))
	rows.append("ENDTRNS")
	return CRLF.join(rows) + CRLF


static func iif_header(prefix: String) -> String:
	return "!" + prefix + TAB + TAB.join(PackedStringArray(IIF_COLUMNS))


static func iif_row(kind: String, date: String, account: String, customer: String, amount: String,
		number: String, memo: String) -> String:
	var fields := PackedStringArray()
	fields.append(kind)
	fields.append(IIF_TRNSTYPE)
	fields.append(date)
	fields.append(account)
	fields.append(customer)
	fields.append(amount)
	fields.append(number)
	fields.append(memo.replace(TAB, " ").replace("\n", " "))
	return TAB.join(fields)


## `2026-06-10` as a QuickBooks importer reads it: `06/10/2026`. Left alone when it is not a date, so
## a damaged file shows the damage rather than a confidently wrong day.
static func iif_date(date: String) -> String:
	var parts: PackedStringArray = date.strip_edges().split("-")
	if parts.size() != 3:
		return date
	if not parts[0].is_valid_int() or not parts[1].is_valid_int() or not parts[2].is_valid_int():
		return date
	return "%s/%s/%s" % [parts[1], parts[2], parts[0]]


# --- the small pieces ---------------------------------------------------------------------------


## A name usable as a file name without becoming unrecognisable: `INV-2026-0001` survives, and a name
## with a slash or a space in it does not become a path. Empty becomes `document`, so a file is still
## written for a document that has not been given a name yet.
static func safe_name(text: String) -> String:
	var trimmed: String = text.strip_edges()
	if trimmed.is_empty():
		return "document"
	var out: String = ""
	for index in range(trimmed.length()):
		var ch: String = trimmed[index]
		var plain: bool = (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z")
		plain = plain or (ch >= "0" and ch <= "9") or ch == "-" or ch == "_" or ch == "."
		out += ch if plain else "_"
	return out


func path_for(document_name: String, extension: String) -> String:
	return folder.path_join("%s.%s" % [safe_name(document_name), extension])


## The memo a tax split carries: the code names the invoice was charged under, because a bookkeeper
## reconciling the sales tax account needs to know which code put the money there.
static func tax_label_of(document: Dictionary) -> String:
	var codes := PackedStringArray()
	var rows: Variant = document.get("tax_lines", [])
	if rows is Array:
		for entry in (rows as Array):
			if entry is Dictionary:
				var code: String = String(entry.get("tax_code", "")).strip_edges()
				if not code.is_empty() and codes.find(code) == -1:
					codes.append(code)
	if codes.is_empty():
		return "Sales tax"
	return "Sales tax: " + ", ".join(codes)


## A field for a CSV: quoted when it has to be, with the quotes inside doubled. A description with a
## comma in it is ordinary ("Hosta, blue"), and an unquoted one would silently split the row.
static func csv_field(text: String) -> String:
	if text.contains(",") or text.contains("\"") or text.contains("\n") or text.contains("\r"):
		return "\"" + text.replace("\"", "\"\"") + "\""
	return text


func _make_folder() -> bool:
	if folder.strip_edges().is_empty():
		return false
	var made: Error = DirAccess.make_dir_recursive_absolute(folder)
	return made == OK or made == ERR_ALREADY_EXISTS


func _write_text(path: String, text: String) -> bool:
	var out: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if out == null:
		return false
	out.store_string(text)
	out.close()
	return true


## Append the invoice's own row to the office's book, writing the header first when the file is new.
##
## **A document is in the book once.** The file name is this backend's idempotency key, so a retry
## lands on the same JSON; the book has to obey the same rule or a timeout would leave a second row
## and the office would count the invoice twice.
func _append_summary(document: Dictionary) -> void:
	var path: String = folder.path_join(LEDGER_FILE)
	if _book_has(path, String(document.get("number", ""))):
		return
	var exists: bool = FileAccess.file_exists(path)
	var out: FileAccess = FileAccess.open(path, FileAccess.READ_WRITE if exists else FileAccess.WRITE)
	if out == null:
		return
	var empty: bool = out.get_length() == 0
	out.seek_end()
	if empty:
		out.store_line(LEDGER_HEADER)
	out.store_line(summary_row_of(document))
	out.close()


## Whether the book already has a row for this document.
static func _book_has(path: String, number: String) -> bool:
	if number.strip_edges().is_empty():
		return false
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var prefix: String = csv_field(number) + ","
	var found: bool = false
	for entry in file.get_as_text().split("\n"):
		if entry.begins_with(prefix):
			found = true
			break
	file.close()
	return found