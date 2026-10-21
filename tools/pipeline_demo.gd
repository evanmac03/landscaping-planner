extends Node2D
## A live pass over the pipeline board: leads added, cards moved between columns, and the drop into
## Lost that holds the card and asks why.
##
## This is a development tool, not part of the game. It instances the **real main scene** and drives
## the **real board** through the methods its controls call, so the model, the pipeline, the board and
## the HUD's menu line are all the shipped ones, and it prints every step. The screenshot at the end is
## the board with a lead in each column it has been moved to.
##
## Run `res://scenes/pipeline_demo.tscn`.

const MAIN := preload("res://scenes/main.tscn")


func _ready() -> void:
	var main: Node = MAIN.instantiate()
	add_child(main)
	var hud: Node = main.get_node_or_null(^"Hud")
	if hud == null:
		print("no HUD in the main scene")
		return

	print("--- opening the board ---")
	hud.open_pipeline_board()
	print("the board is up: ", hud.is_pipeline_board_open())
	var board: Node = hud._pipeline_board
	print("it opens saying: ", board.status_text())
	print("its columns are: ", board.column_titles())

	print("--- adding three leads ---")
	var smith: String = board.add_lead("Smith, back garden", 1850000, &"referral", "2026-07-01")["id"]
	var nguyen: String = board.add_lead("Nguyen, front walk", 640000, &"web", "")["id"]
	var okafor: String = board.add_lead("Okafor, patio and lighting", 2725000, &"repeat", "2026-06-15")["id"]
	print("the Lead column holds ", board.card_count(0), " card(s):")
	for line in board.card_texts(0):
		print("  ", line.replace("\n", "  "))

	print("--- moving two of them up the funnel ---")
	board.move_lead(nguyen, 2)   # Site visit
	board.move_lead(okafor, 4)   # Proposed
	print("the board says: ", board.status_text())

	print("--- a drop into Lost, which holds the card and asks why ---")
	board.move_lead(smith, 6)    # Lost - held, not made
	print("the board is asking: ", board.is_asking_for_a_reason(), " about ", board.pending_lead())
	print("its reason row is shown: ", board.is_reason_row_visible())
	print("the lead has not moved: the Lead column still holds ", board.card_count(0))
	board.set_reason("went with a cheaper quote")
	board.confirm_move(board.reason_text())
	print("after the reason, the Lost column holds ", board.card_count(6), " card(s)")

	print("--- the funnel, in the board's own words ---")
	for line in board.funnel_texts():
		print("  ", line)

	print("--- what the Pipeline menu says ---")
	print("  ", hud._pipeline_text())

	print("--- what is left on screen ---")
	print("the board is up: ", hud.is_pipeline_board_open(),
		", with ", board.card_count(4), " proposed and ", board.card_count(6), " lost")