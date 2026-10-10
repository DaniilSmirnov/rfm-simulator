extends "res://tests/harness.gd"
const Budget = preload("res://scripts/navigation_budget.gd")
func _initialize():
	var counts: Array = []
	for fps in [24, 60, 144]:
		var budget = Budget.new()
		var admitted = 0
		var served: Dictionary = {}
		for frame in range(fps * 2):
			budget.advance(1.0 / fps)
			for id in range(30):
				if budget.request(id):
					admitted += 1
					served[id] = true
		check(admitted <= 50 and admitted >= 47, "planning rate independent of FPS")
		check(served.size() == 30, "FIFO prevents planner starvation")
		var tokens = budget.tokens
		budget.advance(0)
		check(budget.tokens == tokens, "pause never refills budget")
		counts.append(admitted)
	check(counts.max() - counts.min() <= 1, "same planning work across FPS")
	print("NAVIGATION BUDGET RESULT: failures=", failures, " admitted=", counts)
	finish()
