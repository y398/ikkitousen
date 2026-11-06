# ==================================================
# ファイル名: auto_optimizer.gd
# 概要: リーグ戦方式（ベースライン＋歴代王者＋デッキ多様化）により過学習を防止しながらPSTと評価値を自動学習する最適化スクリプトである
# ==================================================

extends Node

const HeadlessMatch = preload("res://scripts/ai/HeadlessMatch.gd")
const EvalWeights = preload("res://scripts/ai/EvalWeights.gd")
const CPUPlayer = preload("res://scripts/ai/CPUPlayer.gd")
const DeckLibrary = preload("res://scripts/core/DeckLibrary.gd")

const SAVE_PATH := "res://data/ai/best_eval_weights.json"

# 自動学習の即座実行フラグ（指示により待機状態とする）
@export var auto_start: bool = false


func _ready() -> void:
	if auto_start:
		print("=== 自己対局パラメータ自動チューニング開始 ===")
		run_league_optimization(4, 6, 4)
	else:
		print("=== 自己対局オプティマイザー（過学習防止リーグ方式）準備完了 ===")
		print("対戦学習を開始する場合は run_league_optimization() を呼び出すか auto_start を有効化する")
	get_tree().quit(0)


# リーグ戦方式（ベースライン＋直前王者との総合対戦）による過学習防止進化探索
func run_league_optimization(generations: int = 4, matches_vs_champ: int = 6, matches_vs_base: int = 4) -> RefCounted:
	var baseline := EvalWeights.new()
	var champion := EvalWeights.new()

	# 保存済みパラメータがあればそれを初期チャンピオンとしてロード
	if FileAccess.file_exists(SAVE_PATH):
		var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
		if f != null:
			var parsed = JSON.parse_string(f.get_as_text())
			f.close()
			if parsed is Dictionary and parsed.has("weights"):
				champion.load_from_dict(parsed["weights"])
				print("既存の最強パラメータを初期チャンピオンとしてロードした")

	var history: Array = []

	for gen in range(generations):
		print("\n--- 第 %d 世代 リーグ探索開始 ---" % (gen + 1))
		var challenger = champion.mutate(0.25, 0.2)

		var chal_wins := 0
		var opponent_wins := 0
		var draws := 0

		# 1 直前王者との対戦
		print("  [対戦 1/2] 直前チャンピオンとの対戦（%d局）" % matches_vs_champ)
		for m in range(matches_vs_champ):
			var res := _run_single_match(challenger, champion, m)
			var w: int = int(res["winner"])
			if w == 0:
				chal_wins += 1
			elif w == 1:
				opponent_wins += 1
			else:
				draws += 1

		# 2 初期汎用ベースラインとの対戦（相性特化・特定戦術過学習の防止）
		print("  [対戦 2/2] 汎用ベースラインとの対戦（%d局）" % matches_vs_base)
		for m in range(matches_vs_base):
			var res := _run_single_match(challenger, baseline, m)
			var w: int = int(res["winner"])
			if w == 0:
				chal_wins += 1
			elif w == 1:
				opponent_wins += 1
			else:
				draws += 1

		var total_effective_matches: int = chal_wins + opponent_wins
		var chal_win_rate: float = float(chal_wins) / float(maxi(1, total_effective_matches))

		print("世代 %d 総合結果: 挑戦者勝率=%.1f%% (%d勝 - %d敗 - %d分)" % [
			gen + 1, chal_win_rate * 100.0, chal_wins, opponent_wins, draws
		])

		var updated := false
		# 王者・ベースラインの両方に対して勝ち越し（勝率55%以上）で昇格
		if chal_win_rate >= 0.55 and chal_wins > opponent_wins:
			print(">>> 挑戦者が総合力で基準を突破し新チャンピオンに昇格！")
			champion = challenger
			updated = true
		else:
			print("王者防衛成功（過学習・相性劣化を抑止）")

		history.append({
			"generation": gen + 1,
			"challenger_wins": chal_wins,
			"opponent_wins": opponent_wins,
			"draws": draws,
			"challenger_win_rate": chal_win_rate,
			"champion_updated": updated
		})

	print("\n=== リーグ最適化完了 ===")
	_save_weights(champion, history)
	return champion


# 1局の対局を実行する（先後交代＋デッキ多様化）
func _run_single_match(chal_weights: RefCounted, opp_weights: RefCounted, match_idx: int) -> Dictionary:
	var match_engine := HeadlessMatch.new()
	add_child(match_engine)

	# 先手後手を交互に交代（先手有利・後手有利のバイアスを排除）
	var is_chal_sente: bool = (match_idx % 2 == 0)
	var w0 = chal_weights if is_chal_sente else opp_weights
	var w1 = opp_weights if is_chal_sente else chal_weights

	# デッキの多様化（偶数回はdeck_1 vs deck_2、奇数回はdeck_2 vs deck_1）
	var d0 = DeckLibrary._default_main_deck_one() if (match_idx % 4 < 2) else DeckLibrary._default_main_deck_two()
	var d1 = DeckLibrary._default_main_deck_two() if (match_idx % 4 < 2) else DeckLibrary._default_main_deck_one()

	match_engine.setup_match(w0, w1, CPUPlayer.DIFFICULTY_HARD, CPUPlayer.DIFFICULTY_HARD, d0, d1)
	var res: Dictionary = match_engine.run_match()

	var winner: int = int(res["winner"])
	var normalized_winner: int = -1
	if winner == 0:
		normalized_winner = 0 if is_chal_sente else 1
	elif winner == 1:
		normalized_winner = 1 if is_chal_sente else 0

	match_engine.queue_free()

	return {
		"winner": normalized_winner, # 0: 挑戦者勝ち, 1: 相手勝ち, -1: 引き分け
		"turns": res["turns"],
		"reason": res["reason"]
	}


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
