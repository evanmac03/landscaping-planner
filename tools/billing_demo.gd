extends Node2D
## A live pass over billing: a plan priced, a job made, a milestone schedule written, an invoice raised,
## money received, and the invoice called back and issued again (spec §9).
##
## This is a development tool, not part of the game. It instances the **real main scene** and drives the
## **real billing page** through the methods its controls call, so the ledger, the schedule, the
## documents and the HUD's menu line are all the shipped ones, and it prints every step. The screenshot
## at the end is the billing page over the drawing the job was priced from.
##
## Run `res://scenes/billing_demo.tscn`.

const MAIN := preload("res://scenes/main.tscn")
const Entity := preload("res://scripts/draft/draft_entity.gd")
const LayerSet := preload("res://scripts/draft/layer_set.gd")
const JobScript := preload("res://scripts/biz/job.gd")
const InvoiceScript := preload("res://scripts/biz/invoice.gd")
const RateScript := preload("res://scripts/biz/rate.gd")


func _ready() -> void:
	var main: Node = MAIN.instantiate()
	add_child(main)
	var hud: Node = main.get_node_or_null(^"Hud")
	var controller: Node = main.get_node_or_null(^"DraftController")
	if hud == null or controller == null:
		print("no HUD or no drafting controller in the main scene")
		return

	print("--- a plan worth pricing: a patio and a bed ---")
	controller.document.add(
		Entity.make_rectangle(Vector2(0, 0), Vector2(6, 4)), LayerSet.NEW_HARDSCAPE
	)
	controller.document.add(Entity.make_circle(Vector2(20, 0), 1.5), LayerSet.NEW_PLANTING)
	print("the drawing holds ", controller.document.count(), " shapes")

	print("--- priced, sent, and made into a job ---")
	hud.open_estimate_window()
	hud._estimate_window.take_off()
	hud._estimate_window.set_recipient("Smith, back garden")
	hud._estimate_window.send_it()
	var started: Dictionary = hud._estimate_window.start_job()
	print("the hand-off was accepted: ", started["ok"])
	var job_id: String = hud._job_desk.job_ids()[0]
	var job = hud._job_desk.job(job_id)
	print("the job is ", hud._job_desk.job_label(job_id), ", a contract of ",
		job.contract_sum.format_with_currency(), ", billed by ",
		JobScript.billing_name(job.billing_method))

	print("--- the page the contract is billed from ---")
	job.set_billing_method(JobScript.MILESTONE)
	hud.open_billing_window()
	print("the page is up: ", hud.is_billing_window_open())
	print("it opens saying: ", hud._billing_window.status_text())
	print("and before a schedule exists it says: ", hud._billing_window.amount_text())

	print("--- a schedule: a deposit that is withheld against, and the balance ---")
	print("started billing: ", hud._billing_window.begin_billing())
	hud._billing_window.set_step_fields("Deposit", "25", "10")
	print("the deposit: ", hud._billing_window.add_step())
	hud._billing_window.set_step_fields("Balance", "75")
	print("the balance: ", hud._billing_window.add_step())
	for each: String in hud._billing_window.schedule_texts():
		print("  ", each)
	print("so the page offers: ", hud._billing_window.amount_text())
	print("and the row the button is on is: ", hud._billing_ledger.billable_step(job_id))

	print("--- the deposit goes out ---")
	var raised: Dictionary = hud._billing_window.raise_invoice()
	print("written: ", raised["ok"], "  and the page says: ", hud._billing_window.status_text())
	var invoice = raised["invoice"]
	print("the document: ", invoice.describe())
	print("it went out as ", invoice.number, ", due ", invoice.due_at, ", with ",
		invoice.retainage.format_with_currency(), " withheld")
	print("the line on it says: ", String(invoice.line(0)["description"]))
	print("the page now offers: ", hud._billing_window.amount_text())
	print("and billing the deposit a second time is refused: ",
		hud._billing_window.bill_step("Deposit"))

	print("--- what the invoice comes to arrives ---")
	hud._billing_window.set_payment(invoice.total().format(), "chq 1041", "cheque")
	print("recorded: ", hud._billing_window.record_payment())
	print("the page says: ", hud._billing_window.status_text())
	for each: String in hud._billing_window.payment_texts():
		print("  ", each)
	print("and the invoice now reads: ", hud._billing_window.invoice_texts()[0])

	print("--- the address was wrong: it is called back and issued again ---")
	hud._billing_window.set_why("the address was wrong")
	print("called back: ", hud._billing_window.void_invoice())
	print("the page says: ", hud._billing_window.status_text())
	print("the step is back on the schedule: ", hud._billing_window.amount_text())
	print("the document is kept, with its number: ", hud._billing_window.invoice_texts()[0])
	print("and money cannot be recorded against it: ", hud._billing_window.record_payment())
	var again: Dictionary = hud._billing_ledger.raise_invoice(
		job_id, Time.get_date_string_from_system()
	)
	print("issued again as: ", (again["invoice"] as InvoiceScript).number if bool(again["ok"])
		else String(again["reason"]))
	hud._billing_window.refresh()
	if bool(again["ok"]):
		hud._billing_window.choose_invoice((again["invoice"] as InvoiceScript).id)

	print("--- what the page reads after all of it ---")
	print(hud._billing_window.summary_text())
	print("billed ", hud._billing_ledger.invoiced_total(job_id).format_with_currency(),
		", received ", hud._billing_ledger.collected_total(job_id).format_with_currency(),
		", owed ", hud._billing_ledger.outstanding_total(job_id).format_with_currency(),
		", retained ", hud._billing_ledger.retained_total(job_id).format_with_currency())
	print("what wants looking at: ", str(hud._billing_window.problem_texts()))
	print("the claim the module exists for: ", RateScript.percent_text(250000), " of ",
		job.contract_sum.format_with_currency(), " is ",
		job.contract_sum.scale_ppm(250000).format_with_currency(),
		", and of that ", invoice.retainage.format_with_currency(), " is withheld")

	print("--- the page as a customer gets it ---")
	hud._billing_ledger.company.append("Greenline Landscapes")
	hud._billing_ledger.company.append("12 Mill Road, Annandale")
	hud._billing_ledger.contact.append("HST 12345 6789")
	print("printing it: ", hud._billing_window.print_invoice())
	print("the page says: ", hud._billing_window.status_text())

	print("--- closeout ---")
	print("released: ",
		hud._billing_ledger.release_retainage(job_id, "2026-09-01").format_with_currency())
	print("retained now: ", hud._billing_ledger.retained_total(job_id).format_with_currency())

	print("--- what is left on screen ---")
	print("the page is up: ", hud.is_billing_window_open(), ", the Jobs menu reads: ", hud._jobs_text())