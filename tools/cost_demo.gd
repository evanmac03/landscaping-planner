extends Node2D
## A live pass over job costing: a plan priced, a job made, material ordered against a budget, a
## delivery received, and a change order the customer agrees to (spec §8.2, §8.3, §8.4).
##
## This is a development tool, not part of the game. It instances the **real main scene** and drives the
## **real cost page** through the methods its controls call, so the desk, the report and the HUD's menu
## line are all the shipped ones, and it prints every step. The screenshot at the end is the cost report
## over the drawing the job was priced from.
##
## Run `res://scenes/cost_demo.tscn`.

const MAIN := preload("res://scenes/main.tscn")
const Entity := preload("res://scripts/draft/draft_entity.gd")
const LayerSet := preload("res://scripts/draft/layer_set.gd")
const MoneyScript := preload("res://scripts/biz/money.gd")


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
	print("the Jobs menu says: ", hud._jobs_text())
	var job_id: String = hud._job_desk.job_ids()[0]
	var job = hud._job_desk.job(job_id)
	var code: String = job.phase_codes()[0]
	print("the job is ", hud._job_desk.job_label(job_id), " with phases ",
		str(job.phase_codes()), " and a contract sum of ",
		job.contract_sum.format_with_currency())

	print("--- the cost report, on the job ---")
	hud.open_cost_window()
	print("the page is up: ", hud.is_cost_window_open())
	print("it opens saying: ", hud._cost_window.status_text())
	print("one row per cost code, before anything has been ordered:")
	for each: String in job.phase_codes():
		print("  ", hud._cost_window.row_text(each))
	print(hud._cost_window.total_text())
	print("what wants looking at: ", str(hud._cost_window.problem_texts()))

	print("--- what an order would commit the job to, before it goes out ---")
	var budget: MoneyScript = job.phase(code)["budget"]
	var hundreds: float = float(budget.cents) / 10000.0
	hud._cost_window.choose_code(code)
	hud._cost_window.set_order_fields(
		"Greenline Nursery", "Buxus, 2 gal", "%.0f" % ceilf(hundreds * 1.2), "100.00"
	)
	print("the page says: ", hud._cost_window.order_hint())
	var placed: Dictionary = hud._cost_window.order_material()
	print("ordered: ", placed["ok"], "  and the page says: ", hud._cost_window.status_text())
	print("the desk says: ", hud._jobs_text())

	print("--- the truck arrives, and the money moves ---")
	print("receiving: ", hud._cost_window.receive_order("PO-001"))
	print("the page says: ", hud._cost_window.status_text())
	for each: String in job.phase_codes():
		print("  ", hud._cost_window.row_text(each))
	print(hud._cost_window.total_text())
	print("invoiced and reconciled: ", hud._cost_window.close_order("PO-001"))

	print("--- the customer asks for something else ---")
	var change = hud._job_desk.make_change_order(
		job_id, &"SITE_CONDITION", "Remove a buried wall", MoneyScript.of(120000), StringName(code)
	)
	hud._job_desk.propose_change(change.id, "2026-06-20")
	hud._cost_window.refresh()
	print("the page lists it: ", str(hud._cost_window.change_texts()))
	print("the desk says: ", hud._jobs_text())
	hud._cost_window.set_approver("Smith", "signed paper photo")
	print("agreed: ", hud._cost_window.agree_change(change.id))
	print("the page says: ", hud._cost_window.status_text())
	print("the desk says: ", hud._jobs_text())

	print("--- what the page reads after all of it ---")
	for each: String in job.phase_codes():
		print("  ", hud._cost_window.row_text(each))
	print(hud._cost_window.total_text())
	print(hud._cost_window.summary_text())
	print("the rows are the report's own: ", hud._cost_window.row_count())

	print("--- what is left on screen ---")
	print("the page is up: ", hud.is_cost_window_open(), ", the Jobs menu reads: ", hud._jobs_text())