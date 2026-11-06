# ==================================================
# ファイル名: self_play_runner.gd
# 概要: CPU同士の高速自己対局を連続実行し勝率と対局データを収集・集計するスクリプトである
# ==================================================

extends Node

const HeadlessMatch = preload("res://scripts/ai/HeadlessMatch.gd")
const CPUPlayer = preload("res://scripts/ai/CPUPlayer.gd")


func _ready() -> void:
	print("=== 自己対局ベンチマーク開始 ===")
	run_benchmark(10)
	get_tree().quit(0)


# 指定局数の対戦を行い結果を集計する
func run_benchmark(num_matches: int = 10) -> Dictionary:
	var base_weights := EvalWeights.new()
	# 実験用に変異を加えた候補重み（攻撃性と王手圧力、領地価値を強化）
	var experimental_weights = base_weights.clone()
	experimental_weights.w_pressure_normal *= 1.3
	experimental_weights.w_pressure_endgame *= 1.4
	experimental_weights.territory_occupy_bonus *= 1.5
	experimental_weights.check_bonus_normal *= 1.2

	var p0_wins := 0
	var p1_wins := 0
	var draws := 0
	var total_turns := 0

	var match_records: Array = []

	var start_time := Time.get_ticks_msec()

	for match_idx in range(num_matches):
		var match_engine := HeadlessMatch.new()
		add_child(match_engine)

		# 偶数戦は base_weights(先手) vs experimental_weights(後手)
		# 奇数戦は experimental_weights(先手) vs base_weights(後手)
		var is_base_sente: bool = (match_idx % 2 == 0)
		var w0 = base_weights if is_base_sente else experimental_weights
		var w1 = experimental_weights if is_base_sente else base_weights

		match_engine.setup_match(w0, w1, CPUPlayer.DIFFICULTY_HARD, CPUPlayer.DIFFICULTY_HARD)
		var result: Dictionary = match_engine.run_match()

		var winner: int = int(result["winner"])
		var turns: int = int(result["turns"])
		total_turns += turns

		var experimental_won := false
		var base_won := false

		if winner == 0:
			if is_base_sente:
				base_won = true
			else:
				experimental_won = true
		elif winner == 1:
			if is_base_sente:
				experimental_won = true
			else:
				base_won = true
		else:
			draws += 1

		if experimental_won:
			p1_wins += 1
		elif base_won:
			p0_wins += 1

		match_records.append({
			"match": match_idx + 1,
			"winner": "experimental" if experimental_won else ("base" if base_won else "draw"),
			"sente_is": "base" if is_base_sente else "experimental",
			"turns": turns,
			"reason": result["reason"]
		})

		print("対局 #%d 終了: 勝者=%s (先手=%s, 手数=%d, 理由=%s)" % [
			match_idx + 1,
			"experimental" if experimental_won else ("base" if base_won else "引き分け"),
			"base" if is_base_sente else "exp",
			turns,
			result["reason"]
		])

		match_engine.queue_free()

	var elapsed_sec: float = float(Time.get_ticks_msec() - start_time) / 1000.0
	var avg_turns: float = float(total_turns) / float(maxi(1, num_matches))

	var summary := {
		"total_matches": num_matches,
		"base_wins": p0_wins,
		"experimental_wins": p1_wins,
		"draws": draws,
		"experimental_win_rate": float(p1_wins) / float(maxi(1, num_matches)),
		"average_turns": avg_turns,
		"elapsed_seconds": elapsed_sec,
		"records": match_records
	}

	print("=== 対戦集計結果 ===")
	print("総局数: %d, 所要時間: %.2f秒 (1局平均: %.2f秒)" % [num_matches, elapsed_sec, elapsed_sec / float(maxi(1, num_matches))])
	print("Base勝: %d, Experimental勝: %d, 引分: %d" % [p0_wins, p1_wins, draws])
	print("Experimental勝率: %.1f%%, 平均手数: %.1f" % [summary["experimental_win_rate"] * 100.0, avg_turns])

	var file := FileAccess.open("user://self_play_results.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(summary, "\t"))
		file.close()

	return summary

