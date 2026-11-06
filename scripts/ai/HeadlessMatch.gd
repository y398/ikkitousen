# ==================================================
# ファイル名: HeadlessMatch.gd
# 概要: UI描画や非同期タイマーを排しメモリ上で完全に同期動作する高速ヘッドレス自己対局エンジンである
# ==================================================

extends Node
class_name HeadlessMatch

const BoardEvaluator = preload("res://scripts/ai/BoardEvaluator.gd")
const CPUPlayer = preload("res://scripts/ai/CPUPlayer.gd")
const CardDatabase = preload("res://scripts/core/CardDatabase.gd")
const DeckLibrary = preload("res://scripts/core/DeckLibrary.gd")
const MovementRules = preload("res://scripts/rules/MovementRules.gd")
const CheckRules = preload("res://scripts/rules/CheckRules.gd")
const SummonRules = preload("res://scripts/rules/SummonRules.gd")
const WallRules = preload("res://scripts/rules/WallRules.gd")
const TrapRules = preload("res://scripts/rules/TrapRules.gd")
const AttackRules = preload("res://scripts/rules/AttackRules.gd")

# 領地マスの座標
const TERRITORY_SQUARES: Array[Vector2i] = [
	Vector2i(5, 2),
	Vector2i(5, 8)
]

const MAX_RESERVES: int = 3
const MAX_HAND_SIZE: int = 5

# ゲーム状態変数
var pieces: Dictionary = {}
var costs: Array = [0, 0]
var reserves: Array = [0, 0]
var hands: Array = [[], []]
var decks: Array = [[], []]
var turn_counts: Array = [0, 0]

var has_moved_this_turn: bool = false
var has_summoned_soldier: Array = [false, false]
var has_summoned_wall: Array = [false, false]
var has_summoned_trap: Array = [false, false]
var discard_mode: bool = false

var current_player: int = 0
var game_over: bool = false
var winner: int = -1
var total_moves: int = 0
var max_turns: int = 120
var wall_id_counter: int = 1

var cpu_players: Array = [null, null]


# 対局の初期化を行う
func setup_match(
	weights_p0: RefCounted,
	weights_p1: RefCounted,
	diff_p0: String = CPUPlayer.DIFFICULTY_HARD,
	diff_p1: String = CPUPlayer.DIFFICULTY_HARD,
	deck_names_p0: Array = [],
	deck_names_p1: Array = []
) -> void:
	pieces.clear()
	costs = [1, 0]
	reserves = [0, 0]
	hands = [[], []]
	decks = [[], []]
	turn_counts = [1, 0]

	has_moved_this_turn = false
	has_summoned_soldier = [false, false]
	has_summoned_wall = [false, false]
	has_summoned_trap = [false, false]
	discard_mode = false

	current_player = 0
	game_over = false
	winner = -1
	total_moves = 0
	wall_id_counter = 1

	# 初期配置（先手王: 9五、後手王: 1五）
	pieces[Vector2i(9, 5)] = {
		"category": "王",
		"name": "王",
		"movement_type": "king",
		"owner": 0
	}
	pieces[Vector2i(1, 5)] = {
		"category": "王",
		"name": "王",
		"movement_type": "king",
		"owner": 1
	}

	# デッキ構築
	var p0_card_names: Array = deck_names_p0 if not deck_names_p0.is_empty() else DeckLibrary._default_main_deck_one()
	var p1_card_names: Array = deck_names_p1 if not deck_names_p1.is_empty() else DeckLibrary._default_main_deck_two()

	_init_deck_for_player(0, p0_card_names)
	_init_deck_for_player(1, p1_card_names)

	# 初期手札3枚ドロー
	for _i in range(3):
		draw_card(0)
		draw_card(1)

	# CPUPlayerインスタンスの生成
	cpu_players[0] = CPUPlayer.new(0, diff_p0, self, weights_p0 as EvalWeights)
	cpu_players[1] = CPUPlayer.new(1, diff_p1, self, weights_p1 as EvalWeights)


# プレイヤーのデッキを構築してシャッフルする
func _init_deck_for_player(player: int, card_names: Array) -> void:
	decks[player].clear()
	for c_name in card_names:
		var card: Dictionary = CardDatabase.get_card(str(c_name))
		if card.is_empty():
			continue
		card["name"] = str(c_name)
		card["owner"] = player
		decks[player].append(card)
	decks[player].shuffle()


# カードを1枚引く
func draw_card(player: int) -> void:
	if decks[player].is_empty():
		return
	var card: Dictionary = decks[player].pop_back()
	hands[player].append(card)


# 未使用コストを備蓄へ移す
func bank_unused_cost(player: int) -> void:
	var unused: int = costs[player]
	var capacity: int = maxi(0, MAX_RESERVES - reserves[player])
	var banked: int = mini(unused, capacity)
	reserves[player] += banked
	costs[player] = 0


# コストを支払う（現在コスト優先、不足分は備蓄から支払う）
func spend_cost(player: int, amount: int) -> bool:
	var total_avail: int = costs[player] + reserves[player]
	if total_avail < amount:
		return false

	var from_cost: int = mini(costs[player], amount)
	var from_res: int = amount - from_cost

	costs[player] -= from_cost
	reserves[player] -= from_res
	return true


# コストを回復する（基本2 + 領地マスボーナス）
func recover_cost(player: int) -> void:
	turn_counts[player] += 1
	var recovery: int = 2

	# 領地マス（2五・8五）の占拠ボーナス
	for t_sq in TERRITORY_SQUARES:
		if pieces.has(t_sq):
			var p: Dictionary = pieces[t_sq]
			if int(p.get("owner", -1)) == player:
				var cat: String = str(p.get("category", ""))
				if cat in ["兵", "成", "王"]:
					recovery += 1

	costs[player] = recovery


# 駒の移動が可能か判定する
func can_move(from_sq: Vector2i, to_sq: Vector2i) -> bool:
	if not pieces.has(from_sq):
		return false
	var piece: Dictionary = pieces[from_sq]
	if int(piece.get("owner", -1)) != current_player:
		return false
	if pieces.has(to_sq) and int(pieces[to_sq].get("owner", -1)) == current_player:
		return false

	# 駒の利き形状判定
	if not MovementRules.can_move_shape(from_sq, to_sq, piece):
		return false

	# 壁による遮断判定
	if WallRules.blocks_path(pieces, from_sq, to_sq):
		return false

	# 直線大駒の経路遮断判定
	if not CheckRules._path_is_clear(pieces, from_sq, to_sq):
		return false

	return true


# 1局の対戦を同期実行して結果を返す
func run_match() -> Dictionary:
	var reason := "max_turns_reached"

	while not game_over and (turn_counts[0] + turn_counts[1]) < max_turns:
		# ターン開始処理（先手1ターン目はセットアップでコスト1設定済みのためスキップ）
		if total_moves > 0 or current_player != 0:
			recover_cost(current_player)
			draw_card(current_player)

		has_moved_this_turn = false
		has_summoned_soldier[current_player] = false
		has_summoned_wall[current_player] = false
		has_summoned_trap[current_player] = false

		# ターン内行動ループ（1ターン最大15アクションで無限ループ防止）
		var action_count := 0
		var max_actions_per_turn := 15

		while action_count < max_actions_per_turn and not game_over:
			action_count += 1
			total_moves += 1

			var act: Dictionary = cpu_players[current_player].decide_next_action()
			var act_type: String = str(act.get("action", "end_turn"))

			if act_type == "end_turn":
				break

			var success := _apply_action(act)
			if not success:
				# 実行不能手の場合は手番終了
				break

			# 王が捕獲されているかチェック
			if _check_king_captured():
				reason = "king_captured"
				break

		if game_over:
			break

		# ターン終了処理
		_finish_turn()

	# ターン数超過時の勝敗判定（評価関数による判定）
	if not game_over:
		var final_score_p0: float = BoardEvaluator.evaluate_board(pieces, 0, costs, reserves, hands)
		if absf(final_score_p0) > 30.0:
			winner = 0 if final_score_p0 > 0 else 1
			reason = "adjudication_score"
		else:
			winner = -1
			reason = "draw"

	return {
		"winner": winner,
		"turns": turn_counts[0] + turn_counts[1],
		"total_moves": total_moves,
		"reason": reason
	}


# ターン終了処理を実行する
func _finish_turn() -> void:
	# 手札超過（5枚超過）時の破棄処理
	while hands[current_player].size() > MAX_HAND_SIZE:
		discard_mode = true
		var discard_act: Dictionary = cpu_players[current_player].decide_next_action()
		discard_mode = false
		var h_idx: int = int(discard_act.get("hand_index", 0))
		if h_idx >= 0 and h_idx < hands[current_player].size():
			hands[current_player].remove_at(h_idx)
		else:
			hands[current_player].pop_back()

	bank_unused_cost(current_player)
	current_player = 1 - current_player


# アクションを実行して盤面に反映する
func _apply_action(act: Dictionary) -> bool:
	var act_type: String = str(act.get("action", ""))

	match act_type:
		"summon":
			return _execute_summon(act)
		"move":
			return _execute_move(act)
		"archer_attack":
			return _execute_archer_attack(act)
		"activate_trap":
			return _execute_activate_trap(act)
		_:
			return false


# 召喚を実行する
func _execute_summon(act: Dictionary) -> bool:
	var h_idx: int = int(act.get("hand_index", -1))
	var sq: Vector2i = act.get("square")
	var my_hand: Array = hands[current_player]
	if h_idx < 0 or h_idx >= my_hand.size():
		return false

	var card: Dictionary = my_hand[h_idx]
	var card_cost: int = int(card.get("cost", 1))
	var category: String = str(card.get("category", "兵"))

	if not spend_cost(current_player, card_cost):
		return false

	my_hand.remove_at(h_idx)

	# 壁カードの場合は2マス配置
	if category == "壁":
		var pending_sq: Vector2i = act.get("pending_wall_square", Vector2i(-1, -1))
		var wid: int = wall_id_counter
		wall_id_counter += 1

		pieces[sq] = {
			"name": str(card.get("name", "竹束")),
			"category": "壁",
			"owner": current_player,
			"wall_id": wid
		}
		if pending_sq.x >= 1 and not pieces.has(pending_sq):
			pieces[pending_sq] = {
				"name": str(card.get("name", "竹束")),
				"category": "壁",
				"owner": current_player,
				"wall_id": wid
			}
		has_summoned_wall[current_player] = true
	elif category == "罠":
		pieces[sq] = {
			"name": str(card.get("name", "")),
			"category": "罠",
			"owner": current_player,
			"effect_id": str(card.get("effect_id", ""))
		}
		has_summoned_trap[current_player] = true
	else:
		pieces[sq] = {
			"name": str(card.get("name", "")),
			"category": "兵",
			"movement_type": str(card.get("movement_type", "pawn")),
			"owner": current_player,
			"summoned_turn": turn_counts[current_player]
		}
		has_summoned_soldier[current_player] = true

	return true


# 移動を実行する
func _execute_move(act: Dictionary) -> bool:
	var from_sq: Vector2i = act.get("from")
	var to_sq: Vector2i = act.get("to")
	if not pieces.has(from_sq):
		return false

	if not spend_cost(current_player, 1):
		return false

	has_moved_this_turn = true
	var moving: Dictionary = pieces[from_sq].duplicate(true)
	pieces.erase(from_sq)

	# 成り判定
	var rank: int = to_sq.x
	var is_promo_zone: bool = (current_player == 0 and rank <= 3) or (current_player == 1 and rank >= 7)
	if is_promo_zone and str(moving.get("category", "")) == "兵":
		moving["category"] = "成"
		var p_name: String = str(moving.get("name", ""))
		if p_name == "歩":
			moving["name"] = "と金"
			moving["movement_type"] = "gold"
		elif p_name == "銀":
			moving["name"] = "成銀"
			moving["movement_type"] = "gold"
		elif p_name == "桂":
			moving["name"] = "成桂"
			moving["movement_type"] = "gold"
		elif p_name == "香":
			moving["name"] = "成香"
			moving["movement_type"] = "gold"
		elif p_name == "角":
			moving["name"] = "馬"
			moving["movement_type"] = "horse"
		elif p_name == "飛":
			moving["name"] = "龍"
			moving["movement_type"] = "dragon"
		elif p_name == "弓手":
			moving["name"] = "成弓"

	# 敵駒の捕獲判定
	if pieces.has(to_sq):
		var target_p: Dictionary = pieces[to_sq]
		var t_cat := str(target_p.get("category", ""))
		if t_cat in ["兵", "王"]:
			var captured_card: Dictionary = target_p.duplicate(true)
			captured_card["owner"] = current_player
			hands[current_player].append(captured_card)

	pieces[to_sq] = moving
	return true


# 弓手の射撃を実行する
func _execute_archer_attack(act: Dictionary) -> bool:
	var archer_sq: Vector2i = act.get("square")
	if not pieces.has(archer_sq):
		return false
	var archer_p: Dictionary = pieces[archer_sq]
	var attack_cost: int = int(archer_p.get("attack_cost", 1))

	if not spend_cost(current_player, attack_cost):
		return false

	has_moved_this_turn = true
	var target_sq: Vector2i = AttackRules.get_archer_target_square(pieces, archer_sq, current_player)
	if target_sq.x < 1 or not pieces.has(target_sq):
		return false

	var target_p: Dictionary = pieces[target_sq]
	var t_cat := str(target_p.get("category", ""))
	var wall_id := int(target_p.get("wall_id", -1))

	# 壁の場合は連動して消去
	if t_cat == "壁" and wall_id >= 1:
		var del_sqs: Array[Vector2i] = []
		for s in pieces:
			var p: Dictionary = pieces[s]
			if str(p.get("category", "")) == "壁" and int(p.get("wall_id", -1)) == wall_id:
				del_sqs.append(s)
		for s in del_sqs:
			pieces.erase(s)
	else:
		pieces.erase(target_sq)

	return true


# 特殊罠の手動起動を実行する
func _execute_activate_trap(act: Dictionary) -> bool:
	var trap_sq: Vector2i = act.get("square")
	if not pieces.has(trap_sq):
		return false
	var trap_p: Dictionary = pieces[trap_sq]
	var act_cost: int = int(trap_p.get("activate_cost", 1))

	if not spend_cost(current_player, act_cost):
		return false

	has_moved_this_turn = true
	var eff_id := TrapRules.get_effect_id(trap_p)
	var targets: Array[Vector2i] = []

	if eff_id == "ambush_three_squares":
		targets = TrapRules.get_ambush_target_squares(pieces, trap_sq, current_player, Vector2i(-1, -1))
	elif eff_id == "stone_drop_front_two":
		var t_sq := TrapRules.find_stone_drop_target(pieces, trap_sq, current_player, Vector2i(-1, -1))
		if t_sq.x >= 1:
			targets.append(t_sq)

	if targets.is_empty():
		return false

	# 価値が最も高い対象を除去
	var best_target := targets[0]
	var max_v := -1.0
	for cand in targets:
		if pieces.has(cand):
			var p_name := str(pieces[cand].get("name", ""))
			var v: float = float(BoardEvaluator.PIECE_VALUES.get(p_name, 10))
			if v > max_v:
				max_v = v
				best_target = cand

	pieces.erase(best_target)
	pieces.erase(trap_sq)
	return true


# 王が捕獲されているかチェックする
func _check_king_captured() -> bool:
	var p0_king := false
	var p1_king := false

	for sq in pieces:
		var p: Dictionary = pieces[sq]
		if str(p.get("category", "")) == "王":
			if int(p.get("owner", -1)) == 0:
				p0_king = true
			elif int(p.get("owner", -1)) == 1:
				p1_king = true

	if not p0_king:
		game_over = true
		winner = 1
		return true
	if not p1_king:
		game_over = true
		winner = 0
		return true

	return false
