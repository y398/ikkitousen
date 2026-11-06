# ==================================================
# ファイル名: auto_optimizer.gd
# 概要: 自己対戦（HeadlessMatch）を繰り返し進化学習によって盤面評価関数の重みを自動探索・最適化するランナーである
# ==================================================

extends Node

const HeadlessMatch = preload("res://scripts/ai/HeadlessMatch.gd")
const EvalWeights = preload("res://scripts/ai/EvalWeights.gd")
const CPUPlayer = preload("res://scripts/ai/CPUPlayer.gd")

const SAVE_PATH := "res://data/ai/best_eval_weights.json"


func _ready() -> void:
	print("=== 自己対局パラメータ自動チューニング開始 ===")
	# 世代数: 4世代、各世代10局の対戦
	run_evolution_optimization(4, 10)
	get_tree().quit(0)


# 複数世代の進化探索を行い最強パラメータを特定・保存する
func run_evolution_optimization(generations: int = 4, matches_per_gen: int = 10) -> RefCounted:
	var champion := EvalWeights.new()

	# 初期のベースラインに対して直前の実験で確認された優良傾向を反映
	champion.w_pressure_normal = 1.3
	champion.w_pressure_endgame = 2.8
	champion.territory_occupy_bonus = 60.0
	champion.check_bonus_normal = 320.0

	var history: Array = []

	for gen in range(generations):
		print("\n--- 第 %d 世代 探索開始 ---" % (gen + 1))
		var challenger = champion.mutate(0.3, 0.2)

		var chal_wins := 0
		var champ_wins := 0
		var draws := 0

		for m in range(matches_per_gen):
			var match_engine := HeadlessMatch.new()
			add_child(match_engine)

			# 先手後手を交互に対戦（先手有利・後手有利のバイアスを排除）
			var is_champ_sente: bool = (m % 2 == 0)
			var w0 = champion if is_champ_sente else challenger
			var w1 = challenger if is_champ_sente else champion

			match_engine.setup_match(w0, w1, CPUPlayer.DIFFICULTY_HARD, CPUPlayer.DIFFICULTY_HARD)
			var res: Dictionary = match_engine.run_match()

			var winner: int = int(res["winner"])
			if winner == 0:
				if is_champ_sente:
					champ_wins += 1
				else:
					chal_wins += 1
			elif winner == 1:
				if is_champ_sente:
					chal_wins += 1
				else:
					champ_wins += 1
			else:
				draws += 1

			match_engine.queue_free()

		var chal_win_rate: float = float(chal_wins) / float(maxi(1, matches_per_gen))
		print("世代 %d 結果: 挑戦者勝率=%.1f%% (挑戦者 %d勝 - 王者 %d勝 - %d分)" % [
			gen + 1, chal_win_rate * 100.0, chal_wins, champ_wins, draws
		])

		var updated := false
		if chal_win_rate >= 0.6:
			print(">>> 挑戦者が王者を破り新チャンピオンに昇格！")
			champion = challenger
			updated = true
		else:
			print("王者防衛成功")

		history.append({
			"generation": gen + 1,
			"challenger_wins": chal_wins,
			"champion_wins": champ_wins,
			"draws": draws,
			"challenger_win_rate": chal_win_rate,
			"champion_updated": updated
		})

	print("\n=== 最適化完了 ===")
	_save_weights(champion, history)
	return champion


# 最良パラメータをJSONファイルとして保存する
func _save_weights(weights: RefCounted, history: Array) -> void:
	var dir := DirAccess.open("res://")
	if not dir.dir_exists("data/ai"):
		dir.make_dir_recursive("data/ai")

	var save_data := {
		"weights": weights.to_dict(),
		"history": history
	}

	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(save_data, "\t"))
		f.close()
		print("最強パラメータを保存した: %s" % SAVE_PATH)
	else:
		print("保存エラー: ファイルを開けなかった")
