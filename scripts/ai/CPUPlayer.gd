# ==================================================
# ファイル名: CPUPlayer.gd
# 概要: 3段階の難易度（初級・中級・最強）に応じた思考アルゴリズムと自律行動を提供するクラスである
# ==================================================

extends RefCounted

const BoardEvaluator = preload("res://scripts/ai/BoardEvaluator.gd")
const CardCounter = preload("res://scripts/ai/CardCounter.gd")
const MovementRules = preload("res://scripts/rules/MovementRules.gd")
const CheckRules = preload("res://scripts/rules/CheckRules.gd")
const SummonRules = preload("res://scripts/rules/SummonRules.gd")
const WallRules = preload("res://scripts/rules/WallRules.gd")
const TrapRules = preload("res://scripts/rules/TrapRules.gd")
const AttackRules = preload("res://scripts/rules/AttackRules.gd")
const CardDatabase = preload("res://scripts/core/CardDatabase.gd")

# 難易度定数
const DIFFICULTY_EASY := "easy"
const DIFFICULTY_NORMAL := "normal"
const DIFFICULTY_HARD := "hard"

# プレイヤー番号
var player_id: int = 1
var difficulty: String = DIFFICULTY_NORMAL

# カードカウンティング管理
var card_counter: CardCounter

# MainGameへの参照
var game_ref: Node = null


func _init(p_player_id: int, p_difficulty: String = DIFFICULTY_NORMAL, p_game: Node = null) -> void:
	player_id = p_player_id
	difficulty = p_difficulty
	game_ref = p_game
	card_counter = CardCounter.new(1 - player_id)


# 次の最善手を決定する（非同期またはメインループから呼ばれる）
# 返り値: {"action": "move"|"summon"|"end_turn"|"discard", ...}
func decide_next_action() -> Dictionary:
	if game_ref == null:
		return {"action": "end_turn"}

	# 手札超過モード中の場合は破棄するカードを選ぶ
	var discard_flag = game_ref.get("discard_mode")
	if (discard_flag != null and bool(discard_flag)) or game_ref.hands[player_id].size() > 5:
		return _decide_discard_card()

	# 難易度別の思考ルーチン
	match difficulty:
		DIFFICULTY_EASY:
			return _decide_action_easy()
		DIFFICULTY_NORMAL:
			return _decide_action_normal()
		DIFFICULTY_HARD:
			return _decide_action_hard()
		_:
			return _decide_action_normal()


# 手札超過時の破棄カードを選択する
func _decide_discard_card() -> Dictionary:
	var hand: Array = game_ref.hands[player_id]
	if hand.is_empty():
		return {"action": "end_turn"}

	# 最もコストが高いか現状使えないカードを優先して破棄する
	var worst_idx := 0
	var min_priority := 9999.0

	for i in range(hand.size()):
		var card: Dictionary = hand[i]
		var card_name: String = str(card.get("name", ""))
		var cost: int = int(card.get("cost", 1))
		var priority: float = float(cost) * 2.0

		# 王将や即戦力は捨てない
		if card_name in ["金", "飛", "角"]:
			priority += 50.0

		if priority < min_priority:
			min_priority = priority
			worst_idx = i

	return {
		"action": "discard",
		"hand_index": worst_idx
	}


# 初級ルーチン：ランダム性を持たせつつ王手や駒取りを行う
func _decide_action_easy() -> Dictionary:
	var candidate_actions := _generate_all_legal_actions()
	if candidate_actions.is_empty():
		return {"action": "end_turn"}

	# 駒取りができる手を優先する
	var capture_actions: Array[Dictionary] = []
	for act in candidate_actions:
		if act.get("action") == "move":
			var to_sq: Vector2i = act.get("to")
			if game_ref.pieces.has(to_sq):
				var target: Dictionary = game_ref.pieces[to_sq]
				if int(target.get("owner", -1)) != player_id:
					capture_actions.append(act)

	if not capture_actions.is_empty() and randf() < 0.7:
		return capture_actions[randi() % capture_actions.size()]

	# 一定確率でターンを終了する（消極的な手番）
	if randf() < 0.2 and candidate_actions.size() > 2:
		return {"action": "end_turn"}

	# ランダムな合法手を実行する
	return candidate_actions[randi() % candidate_actions.size()]


# 中級ルーチン：盤面評価に基づき敵王接近・前線押し上げ・タダ取り回避の手を選択する
func _decide_action_normal() -> Dictionary:
	var candidate_actions := _generate_all_legal_actions()
	if candidate_actions.is_empty():
		return {"action": "end_turn"}

	var opponent := 1 - player_id

	# 1 即座に敵の王を取れる手があるか確認する
	for act in candidate_actions:
		if act.get("action") == "move":
			var to_sq: Vector2i = act.get("to")
			if game_ref.pieces.has(to_sq):
				var target: Dictionary = game_ref.pieces[to_sq]
				if str(target.get("category", "")) == "王" and int(target.get("owner", -1)) == opponent:
					return act

	var best_action: Dictionary = {"action": "end_turn"}
	var current_eval: float = BoardEvaluator.evaluate_board(
		game_ref.pieces,
		player_id,
		game_ref.costs,
		game_ref.reserves,
		game_ref.hands
	)
	var best_score: float = -999999.0

	for act in candidate_actions:
		var sim_pieces: Dictionary = game_ref.pieces.duplicate(true)
		var sim_costs: Array = [game_ref.costs[0], game_ref.costs[1]]
		var sim_reserves: Array = [game_ref.reserves[0], game_ref.reserves[1]]
		var sim_hands: Array = [game_ref.hands[0].duplicate(true), game_ref.hands[1].duplicate(true)]

		var valid := _simulate_action(act, sim_pieces, sim_costs, sim_reserves, sim_hands, player_id)
		if not valid:
			continue

		var score: float = BoardEvaluator.evaluate_board(
			sim_pieces,
			player_id,
			sim_costs,
			sim_reserves,
			sim_hands
		)

		# 自陣の王が王手される手は完全排除
		if CheckRules.is_in_check(sim_pieces, player_id):
			score -= 5000.0

		# 移動先で相手にタダ取りされる手へのペナルティ
		if act.get("action") == "move":
			var to_sq: Vector2i = act.get("to")
			if CheckRules.is_square_attacked(sim_pieces, to_sq, opponent):
				if not CheckRules.is_square_attacked(sim_pieces, to_sq, player_id):
					var piece_name: String = str(sim_pieces[to_sq].get("name", ""))
					var piece_val: float = float(BoardEvaluator.PIECE_VALUES.get(piece_name, 20))
					score -= piece_val * 1.5

		if score > best_score:
			best_score = score
			best_action = act

	# 現在よりスコアが伸びずコスト備蓄が有利な場合はターン終了
	if best_score <= current_eval and int(game_ref.costs[player_id]) <= 1:
		return {"action": "end_turn"}

	return best_action


# 最強ルーチン：即勝ち判定・王手包囲・相手の最強反撃を読む2手先Minimax探索
func _decide_action_hard() -> Dictionary:
	var candidate_actions := _generate_all_legal_actions()
	if candidate_actions.is_empty():
		return {"action": "end_turn"}

	var opponent := 1 - player_id

	# 1 即座に敵の王を取れる手があるか確認する（最優先確定手）
	for act in candidate_actions:
		if act.get("action") == "move":
			var to_sq: Vector2i = act.get("to")
			if game_ref.pieces.has(to_sq):
				var target: Dictionary = game_ref.pieces[to_sq]
				if str(target.get("category", "")) == "王" and int(target.get("owner", -1)) == opponent:
					return act

	var best_action: Dictionary = {"action": "end_turn"}
	var best_score: float = -9999999.0

	# 相手の次ターン最大コストを計算
	var opp_max_cost := card_counter.calculate_opponent_next_turn_max_cost(
		int(game_ref.turn_counts[opponent]),
		int(game_ref.reserves[opponent])
	)

	for act in candidate_actions:
		var sim_pieces: Dictionary = game_ref.pieces.duplicate(true)
		var sim_costs: Array = [game_ref.costs[0], game_ref.costs[1]]
		var sim_reserves: Array = [game_ref.reserves[0], game_ref.reserves[1]]
		var sim_hands: Array = [game_ref.hands[0].duplicate(true), game_ref.hands[1].duplicate(true)]

		var valid := _simulate_action(act, sim_pieces, sim_costs, sim_reserves, sim_hands, player_id)
		if not valid:
			continue

		# 自陣の王が王手される手は完全排除
		if CheckRules.is_in_check(sim_pieces, player_id):
			continue

		# 敵王に王手をかけているか
		var is_checking_opponent: bool = CheckRules.is_in_check(sim_pieces, opponent)

		# 2手先探索: 相手が打ち得る最強の反撃手（Min局面）をシミュレートする
		var opp_counter_eval := _evaluate_opponent_best_response(
			sim_pieces,
			sim_costs,
			sim_reserves,
			sim_hands,
			opponent,
			opp_max_cost
		)

		var move_score: float = opp_counter_eval

		# 王手時の大幅ボーナス（詰み探索促進）
		if is_checking_opponent:
			move_score += 150.0

		if move_score > best_score:
			best_score = move_score
			best_action = act

	return best_action


# 相手の最強反撃手（Min局面）を探索し、最悪シナリオ後の評価値を返す
func _evaluate_opponent_best_response(
	pieces_after_my_move: Dictionary,
	costs_state: Array,
	reserves_state: Array,
	hands_state: Array,
	opp: int,
	opp_max_cost: int
) -> float:
	# 相手が直接王を取れるなら即負け評価
	for sq in pieces_after_my_move:
		var p: Dictionary = pieces_after_my_move[sq]
		if int(p.get("owner", -1)) != opp:
			continue
		var cat: String = str(p.get("category", ""))
		if cat != "兵" and cat != "王" and cat != "成":
			continue

		for my_sq in pieces_after_my_move:
			var target: Dictionary = pieces_after_my_move[my_sq]
			if str(target.get("category", "")) == "王" and int(target.get("owner", -1)) == player_id:
				if MovementRules.can_move_shape(sq, my_sq, p) and not WallRules.blocks_path(pieces_after_my_move, sq, my_sq) and CheckRules._path_is_clear(pieces_after_my_move, sq, my_sq):
					return -888888.0

	# 相手の代表的な反撃手（駒の捕獲手・王手・大駒前進）を抽出する
	var opp_replies: Array[Dictionary] = _generate_critical_opponent_replies(pieces_after_my_move, opp, opp_max_cost)

	# 相手に有効な反撃がない場合は現局面の評価値を採用
	if opp_replies.is_empty():
		return BoardEvaluator.evaluate_board(pieces_after_my_move, player_id, costs_state, reserves_state, hands_state)

	# 相手の最善手（自分にとって最も評価スコアが低くなる手）を求める
	var worst_score_for_me: float = 999999.0
	for r_act in opp_replies:
		var r_pieces: Dictionary = pieces_after_my_move.duplicate(true)
		var r_costs: Array = [costs_state[0], costs_state[1]]
		var r_reserves: Array = [reserves_state[0], reserves_state[1]]
		var r_hands: Array = [hands_state[0].duplicate(true), hands_state[1].duplicate(true)]

		var ok := _simulate_action(r_act, r_pieces, r_costs, r_reserves, r_hands, opp)
		if not ok:
			continue

		var r_eval: float = BoardEvaluator.evaluate_board(r_pieces, player_id, r_costs, r_reserves, r_hands)
		if r_eval < worst_score_for_me:
			worst_score_for_me = r_eval

	return worst_score_for_me


# 相手の脅威となる主要な反撃手を生成する
func _generate_critical_opponent_replies(current_pieces: Dictionary, opp: int, opp_cost: int) -> Array[Dictionary]:
	var replies: Array[Dictionary] = []

	# 1 相手の盤上駒による自軍駒の捕獲手を最優先探索
	for from_sq in current_pieces:
		var p: Dictionary = current_pieces[from_sq]
		if int(p.get("owner", -1)) != opp:
			continue
		var cat: String = str(p.get("category", ""))
		if cat != "兵" and cat != "王" and cat != "成":
			continue

		for to_sq in current_pieces:
			var target: Dictionary = current_pieces[to_sq]
			if int(target.get("owner", -1)) != player_id:
				continue
			var target_cat: String = str(target.get("category", ""))
			if target_cat == "壁":
				continue

			if MovementRules.can_move_shape(from_sq, to_sq, p) and not WallRules.blocks_path(current_pieces, from_sq, to_sq) and CheckRules._path_is_clear(current_pieces, from_sq, to_sq):
				replies.append({"action": "move", "from": from_sq, "to": to_sq})

	# 2 相手が飛車などの大駒を召喚して王手・直撃を狙える場合の警戒
	if replies.size() < 5 and opp_cost >= 3:
		var threats := card_counter.get_remaining_threat_estimate()
		if int(threats.get("飛", 0)) > 0:
			# 飛車の直撃マスを警戒候補に加える
			replies.append({"action": "threat_rook"})

	return replies


# すべての合法手（召喚・駒移動・壁破壊等）を生成する
func _generate_all_legal_actions() -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	if game_ref == null:
		return actions

	var current_cost: int = int(game_ref.costs[player_id])

	# 1 手札の召喚候補を生成する（前線近くの有効マスを優先）
	actions.append_array(_generate_summon_actions(current_cost))

	# 2 盤上の駒移動候補を生成する（コスト1以上が必要、かつ1ターン1回移動制限）
	var moved_flag = game_ref.get("has_moved_this_turn")
	var has_moved: bool = moved_flag != null and bool(moved_flag)
	if current_cost >= 1 and not has_moved:
		actions.append_array(_generate_move_actions())

	return actions


# 召喚の合法手を生成する（敵王への接近・前線押し上げを優先して走査）
func _generate_summon_actions(current_cost: int) -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	var hand: Array = game_ref.hands[player_id]

	# 敵王の位置を取得する
	var opp_king_sq := Vector2i(9, 5) if player_id == 1 else Vector2i(1, 5)
	for sq in game_ref.pieces:
		var p: Dictionary = game_ref.pieces[sq]
		if str(p.get("category", "")) == "王" and int(p.get("owner", -1)) != player_id:
			opp_king_sq = sq
			break

	for h_idx in range(hand.size()):
		var card: Dictionary = hand[h_idx]
		var card_cost: int = int(card.get("cost", 1))
		if card_cost > current_cost:
			continue

		var category: String = str(card.get("category", ""))

		# 1ターン内の各カテゴリ召喚回数制限チェック
		var s_soldier = game_ref.get("has_summoned_soldier")
		if category == "兵" and s_soldier != null and bool(s_soldier[player_id]):
			continue
		var s_wall = game_ref.get("has_summoned_wall")
		if category == "壁" and s_wall != null and bool(s_wall[player_id]):
			continue
		var s_trap = game_ref.get("has_summoned_trap")
		if category == "罠" and s_trap != null and bool(s_trap[player_id]):
			continue

		# 最前線から自陣側へ向かって走査する（前線配置を優先）
		var rank_range: Array = []
		if player_id == 0:
			for r in range(1, 10):
				rank_range.append(r)
		else:
			for r in range(9, 0, -1):
				rank_range.append(r)

		# 筋の走査順を敵王の筋に近い順に並べる
		var file_range: Array[int] = [1, 2, 3, 4, 5, 6, 7, 8, 9]
		file_range.sort_custom(func(a: int, b: int) -> bool:
			return absi(a - opp_king_sq.y) < absi(b - opp_king_sq.y)
		)

		for rank in rank_range:
			for file in file_range:
				var sq := Vector2i(rank, file)

				if game_ref.pieces.has(sq):
					continue

				if category == "壁":
					var card_name: String = str(card.get("name", ""))
					if card_name == "馬防柵":
						var neighbors: Array[Vector2i] = [
							Vector2i(rank + 1, file), Vector2i(rank - 1, file),
							Vector2i(rank, file + 1), Vector2i(rank, file - 1)
						]
						for n_sq in neighbors:
							if n_sq.x >= 1 and n_sq.x <= 9 and n_sq.y >= 1 and n_sq.y <= 9:
								if not game_ref.pieces.has(n_sq) and WallRules.is_valid_wall_square(game_ref.pieces, sq, player_id) and WallRules.is_valid_wall_square(game_ref.pieces, n_sq, player_id):
									actions.append({
										"action": "summon",
										"hand_index": h_idx,
										"card_name": card_name,
										"square": sq,
										"pending_wall_square": n_sq
									})
									break
					else:
						if WallRules.is_valid_wall_square(game_ref.pieces, sq, player_id):
							actions.append({
								"action": "summon",
								"hand_index": h_idx,
								"card_name": card_name,
								"square": sq,
								"pending_wall_square": Vector2i(-1, -1)
							})
				else:
					if SummonRules.is_in_summon_range(game_ref.pieces, sq, player_id):
						var err := SummonRules.get_non_wall_placement_error(game_ref.pieces, sq, player_id, category)
						if err.is_empty():
							actions.append({
								"action": "summon",
								"hand_index": h_idx,
								"card_name": str(card.get("name", "")),
								"square": sq,
								"pending_wall_square": Vector2i(-1, -1)
							})

	return actions


# 駒移動の合法手を生成する
func _generate_move_actions() -> Array[Dictionary]:
	var actions: Array[Dictionary] = []

	for from_sq in game_ref.pieces:
		var piece: Dictionary = game_ref.pieces[from_sq]
		if int(piece.get("owner", -1)) != player_id:
			continue

		var category: String = str(piece.get("category", ""))
		if category != "兵" and category != "王" and category != "成":
			continue

		# 全81マスへの移動可能性を判定する
		for rank in range(1, 10):
			for file in range(1, 10):
				var to_sq := Vector2i(rank, file)
				if to_sq == from_sq:
					continue

				# game_refが正規のcan_move判定を持つ場合はそれを直接呼ぶ（召喚ターン移動制限や壁の捕獲禁止等を完全網羅する）
				if game_ref.has_method("can_move"):
					if not game_ref.can_move(from_sq, to_sq):
						continue
				else:
					# フォールバック判定：このターン召喚した兵は移動できない
					if category == "兵":
						var summoned_turn: int = int(piece.get("summoned_turn", -1))
						var turn_cnt = game_ref.get("turn_counts")
						if turn_cnt != null and summoned_turn == int(turn_cnt[player_id]):
							continue

					# 移動先に駒が存在する場合のチェック
					if game_ref.pieces.has(to_sq):
						var target: Dictionary = game_ref.pieces[to_sq]
						var target_cat: String = str(target.get("category", ""))
						# 壁は通常の移動・捕獲では侵入できない
						if target_cat == "壁":
							continue
						# 味方の駒があるマスには入れない
						if int(target.get("owner", -1)) == player_id:
							continue
						# 罠への侵入条件チェック
						if target_cat == "罠" and not TrapRules.can_enter_trap_square(target, piece):
							continue

					# 移動形状チェック
					if not MovementRules.can_move_shape(from_sq, to_sq, piece):
						continue

					# 壁による進路妨害チェック
					if WallRules.blocks_path(game_ref.pieces, from_sq, to_sq):
						continue

					# 直線経路の遮断チェック
					if not CheckRules._path_is_clear(game_ref.pieces, from_sq, to_sq):
						continue

				actions.append({
					"action": "move",
					"from": from_sq,
					"to": to_sq
				})

	return actions


# 仮想盤面上で手をシミュレートする
func _simulate_action(
	act: Dictionary,
	sim_pieces: Dictionary,
	sim_costs: Array,
	_sim_reserves: Array,
	sim_hands: Array,
	acting_player: int
) -> bool:
	var act_type: String = str(act.get("action", ""))

	match act_type:
		"summon":
			var h_idx: int = int(act.get("hand_index", -1))
			var sq: Vector2i = act.get("square")
			var my_hand: Array = sim_hands[acting_player]
			if h_idx < 0 or h_idx >= my_hand.size():
				return false
			var card: Dictionary = my_hand[h_idx]
			var card_cost: int = int(card.get("cost", 1))
			if int(sim_costs[acting_player]) < card_cost:
				return false

			sim_costs[acting_player] = int(sim_costs[acting_player]) - card_cost
			my_hand.remove_at(h_idx)

			# 盤面に駒を配置
			sim_pieces[sq] = {
				"name": str(card.get("name", "")),
				"category": str(card.get("category", "兵")),
				"movement_type": str(card.get("movement_type", "pawn")),
				"owner": acting_player
			}
			return true

		"move":
			var from_sq: Vector2i = act.get("from")
			var to_sq: Vector2i = act.get("to")
			if not sim_pieces.has(from_sq):
				return false
			if int(sim_costs[acting_player]) < 1:
				return false

			sim_costs[acting_player] = int(sim_costs[acting_player]) - 1
			var moving: Dictionary = sim_pieces[from_sq].duplicate(true)
			sim_pieces.erase(from_sq)

			# 成り判定（敵陣3段以内に入った場合、成れるなら成る）
			var forward_rank: int = to_sq.x
			var is_promotion_zone: bool = (acting_player == 0 and forward_rank <= 3) or (acting_player == 1 and forward_rank >= 7)
			if is_promotion_zone and str(moving.get("category", "")) == "兵":
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

			# 敵駒の捕獲判定（壁や罠は捕獲対象外）
			if sim_pieces.has(to_sq):
				var target_p: Dictionary = sim_pieces[to_sq]
				var t_cat := str(target_p.get("category", ""))
				if t_cat in ["兵", "王"]:
					var cap_card: Dictionary = target_p.duplicate(true)
					cap_card["owner"] = acting_player
					sim_hands[acting_player].append(cap_card)

			sim_pieces[to_sq] = moving
			return true

		"threat_rook":
			# 相手の飛車召喚による直撃脅威のシミュレーション
			return true

		"end_turn":
			return true

	return false
