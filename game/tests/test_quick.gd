extends SceneTree
func _init():
	var Q = load("res://scripts/quick.gd").new()
	Q.rates = {"EUR": 1.0, "GBP": 0.85, "USD": 1.08, "JPY": 160.0}
	Q.rates_date = Time.get_date_string_from_system()
	for q in ["2+2", "12*(3+4)", "2^10", "sqrt(144)", "10 x 3", "1200/7", "42", "-3", "15% of 80", "5 km in miles", "180 cm to ft", "100 f in c", "70 kg in lb", "2 gb in mb", "50 usd in gbp", "£20 to eur", "20 pounds in dollars", "1 l in pints", "hello world", "godot", "3 min in seconds", "1000000*3"]:
		print(q, "  =>  ", Q.answer(q))
	for q in ["time in tokyo", "what's the time in new york?", "3pm london in tokyo", "15:30 in la", "9am in st lucia"]:
		print(q, "  =>  ", Q.time_query(q))
	quit()
