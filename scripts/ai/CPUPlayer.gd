# ==================================================
# ファイル名: CPUPlayer.gd
# 概要: 3段階の難易度（初級・中級・最強）に応じた思考アルゴリズムと自律行動を提供するクラスである
# ターン内マルチアクションのプランニングおよび取り合い決着（静止探索）を備える
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

# 静止探索の最大深さ（取り合い決着の探索限界）
const MAX_QUIESCENCE_DEPTH := 2

# プレイヤー番号
var player_id: int = 1
var difficulty: String = DIFFICULTY_NORMAL

# カードカウンティング管理
var card_counter: CardCounter

# MainGameへの参照
var game_ref: Node = null

# ターン内行動プランの実行キュー
var planned_action_queue: Array = []


func _init(p_player_id: int, p_difficulty: String = DIFFICULTY_NORMAL, p_game: Node = null) -> void:
	player_id = p_player_id
	difficulty = p_difficulty
	game_ref = p_game
	card_counter = CardCounter.new(1 - player_id)
	planned_action_queue.clear()


# 次の最善手を決定する（非同期またはメインループから呼ばれる）
# 返り値: {"action": "move"|"summon"|"end_turn"|"discard", ...}
func decide_next_action() -> Dictionary:
	if game_ref == null:
		return {"action": "end_turn"}

	# 手札超過モード中の場合は破棄するカードを選ぶ
	var discard_flag = game_ref.get("discard_mode")
	if (discard_flag != null and bool(discard_flag)) or game_ref.hands[player_id].size() > 5:
		planned_action_queue.clear()
		return _decide_discard_card()

	# キューに有効な予定行動が残っている場合はそれを優先実行する
	while not planned_action_queue.is_empty():
		var next_act: Dictionary = planned_action_queue.pop_front()
		if _is_action_currently_valid(next_act):
			return next_act

	# 難易度別の思考ルーチンで新たな行動またはターン計画を策定する
	match difficulty:
		DIFFICULTY_EASY:
			return _decide_action_easy()
		DIFFICULTY_NORMAL:
			return _decide_action_normal()
		DIFFICULTY_HARD:
			return _decide_action_hard()
		_:
			return _decide_action_normal()


# 行動が現在の盤面とコストで実行可能か判定する
func _is_action_currently_valid(act: Dictionary) -> bool:
	var act_type: String = str(act.get("action", ""))
	if act_type == "end_turn":
		return true

	var cur_cost: int = int(game_ref.costs[player_id])

	if act_type == "summon":
		var h_idx: int = int(act.get("hand_index", -1))
		var sq: Vector2i = act.get("square")
		var my_hand: Array = game_ref.hands[player_id]
		if h_idx < 0 or h_idx >= my_hand.size():
			return false
		var card: Dictionary = my_hand[h_idx]
		var card_cost: int = int(card.get("cost", 1))
		if cur_cost < card_cost:
			return false
		if game_ref.pieces.has(sq):
			return false
		return true

	if act_type == "move":
		if cur_cost < 1:
			return false
		var moved_flag = game_ref.get("has_moved_this_turn")
		if moved_flag != null and bool(moved_flag):
			return false
		var from_sq: Vector2i = act.get("from")
		var to_sq: Vector2i = act.get("to")
		if not game_ref.pieces.has(from_sq):
			return false
		if game_ref.has_method("can_move"):
			return game_ref.can_move(from_sq, to_sq)
		return true

	return false


# 手札超過時の破棄カードを選択する
func _decide_discard_card() -> Dictionary:
	var hand: Array = game_ref.hands[player_id]
	if hand.is_empty():
		return {"action": "end_turn"}

	var worst_idx := 0
	var min_priority := 9999.0

	for i in range(hand.size()):
		var card: Dictionary = hand[i]
		var card_name: String = str(card.get("name", ""))
		var cost: int = int(card.get("cost", 1))
		var priority: float = float(cost) * 2.0

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

	if randf() < 0.2 and candidate_actions.size() > 2:
		return {"action": "end_turn"}

	return candidate_actions[randi() % candidate_actions.size()]


# 中級ルーチン：盤面評価に基づき敵王接近・前線押し上げ・タダ取り回避の手を選択する
func _decide_action_normal() -> Dictionary:
	var opponent := 1 - player_id
	var candidate_actions := _generate_all_legal_actions()
	if candidate_actions.is_empty():
		return {"action": "end_turn"}

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

		# 自陣の王が王手される手は完全排除
		if CheckRules.is_in_check(sim_pieces, player_id):
			continue

		var score: float = BoardEvaluator.evaluate_board(
			sim_pieces,
			player_id,
			sim_costs,
			sim_reserves,
			sim_hands
		)

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

	if best_score <= current_eval and int(game_ref.costs[player_id]) <= 1:
		return {"action": "end_turn"}

	return best_action


# 最強ルーチン：1ターン内行動プラン化（召喚＋移動）と静止探索（取り合い解決）を統合した探索
func _decide_action_hard() -> Dictionary:
	var opponent := 1 - player_id

	# 1 即座に敵の王を取れる手があるか確認する（最優先確定手）
	var move_actions := _generate_move_actions()
	for act in move_actions:
		var to_sq: Vector2i = act.get("to")
		if game_ref.pieces.has(to_sq):
			var target: Dictionary = game_ref.pieces[to_sq]
			if str(target.get("category", "")) == "王" and int(target.get("owner", -1)) == opponent:
				return act

	# 2 ターン全体の行動プラン候補を列挙する
	# 【単独移動】【単独召喚】【召喚＋移動】【移動＋召喚】【手番終了】
	var turn_plans := _generate_turn_plans()
	if turn_plans.is_empty():
		return {"action": "end_turn"}

	var best_plan: Array = [{"action": "end_turn"}]
	var best_score: float = -9999999.0

	for plan in turn_plans:
		var sim_pieces: Dictionary = game_ref.pieces.duplicate(true)
		var sim_costs: Array = [game_ref.costs[0], game_ref.costs[1]]
		var sim_reserves: Array = [game_ref.reserves[0], game_ref.reserves[1]]
		var sim_hands: Array = [game_ref.hands[0].duplicate(true), game_ref.hands[1].duplicate(true)]

		var plan_valid := true
		for step_act in plan:
			if step_act.get("action") == "end_turn":
				continue
			if not _simulate_action(step_act, sim_pieces, sim_costs, sim_reserves, sim_hands, player_id):
				plan_valid = false
				break

		if not plan_valid:
			continue

		# 自軍王が王手されている状態のプランは完全排除
		if CheckRules.is_in_check(sim_pieces, player_id):
			continue

		# 静止探索を伴う深い局面評価を実行する（取り合い決着まで評価）
		var plan_eval: float = _quiescence_search(
			sim_pieces,
			sim_costs,
			sim_reserves,
			sim_hands,
			opponent,
			0
		)

		# 敵王に王手をかけているプランにボーナス
		if CheckRules.is_in_check(sim_pieces, opponent):
			plan_eval += 180.0

		if plan_eval > best_score:
			best_score = plan_eval
			best_plan = plan

	# 選定されたベストプランを行動キューに格納し最初の1手を返す
	planned_action_queue.clear()
	for i in range(1, best_plan.size()):
		planned_action_queue.append(best_plan[i])

	return best_plan[0] if not best_plan.is_empty() else {"action": "end_turn"}


# 1ターン全体の行動プラン候補（コンビネーション）を列挙する
func _generate_turn_plans() -> Array[Array]:
	var plans: Array[Array] = []
	var cur_cost: int = int(game_ref.costs[player_id])

	var moves := _generate_move_actions()
	var summons := _generate_summon_actions(cur_cost)

	# プラン1: パス（何もしないで手番終了）
	plans.append([{"action": "end_turn"}])

	# プラン2: 単独移動
	if cur_cost >= 1:
		for m in moves:
			plans.append([m, {"action": "end_turn"}])

	# プラン3: 単独召喚
	for s in summons:
		plans.append([s, {"action": "end_turn"}])

	# プラン4: 召喚 ＋ 移動のコンビネーション（残コスト >= 1）
	for s in summons:
		var s_cost: int = int(CardDatabase.get_card(str(s.get("card_name", ""))).get("cost", 1))
		if cur_cost - s_cost >= 1:
			# 召喚後の盤面をシミュレートして移動候補を探索
			for m in moves:
				# 召喚したマスからそのターンは移動不可ルールを遵守
				if m.get("from") == s.get("square"):
					continue
				plans.append([s, m, {"action": "end_turn"}])

	# プラン5: 移動 ＋ 召喚のコンビネーション（移動後に召喚）
	if cur_cost >= 2:
		for m in moves:
			for s in summons:
				var s_cost: int = int(CardDatabase.get_card(str(s.get("card_name", ""))).get("cost", 1))
				if cur_cost - 1 >= s_cost:
					plans.append([m, s, {"action": "end_turn"}])

	return plans


# 静止探索（Quiescence Search）：駒の取り合いや王手が落ち着くまで探索を延長する
func _quiescence_search(
	pieces_state: Dictionary,
	costs_state: Array,
	reserves_state: Array,
	hands_state: Array,
	current_side: int,
	depth: int
) -> float:
	# 相手が直接王を取れるなら即敗北
	var opp := 1 - current_side
	for sq in pieces_state:
		var p: Dictionary = pieces_state[sq]
		if int(p.get("owner", -1)) != current_side:
			continue
		var cat: String = str(p.get("category", ""))
		if cat != "兵" and cat != "王" and cat != "成":
			continue
		for opp_sq in pieces_state:
			var target: Dictionary = pieces_state[opp_sq]
			if str(target.get("category", "")) == "王" and int(target.get("owner", -1)) == opp:
				if MovementRules.can_move_shape(sq, opp_sq, p) and not WallRules.blocks_path(pieces_state, sq, opp_sq) and CheckRules._path_is_clear(pieces_state, sq, opp_sq):
					return -888888.0 if current_side != player_id else 888888.0

	# 現在局面の静止評価値（Standing Pat）
	var static_eval: float = BoardEvaluator.evaluate_board(
		pieces_state,
		player_id,
		costs_state,
		reserves_state,
		hands_state
	)

	# 深さ制限に達した場合は静止評価値を返す
	if depth >= MAX_QUIESCENCE_DEPTH:
		return static_eval

	# 捕獲手（相手の駒を取る手）のみを生成して取り合いの決着を読む
	var captures := _generate_capture_actions(pieces_state, current_side)
	if captures.is_empty():
		return static_eval

	if current_side == player_id:
		# 自軍手番（評価最大化）
		var max_score: float = static_eval
		for cap in captures:
			var next_pieces := pieces_state.duplicate(true)
			var next_costs := [costs_state[0], costs_state[1]]
			var next_reserves := [reserves_state[0], reserves_state[1]]
			var next_hands := [hands_state[0].duplicate(true), hands_state[1].duplicate(true)]

			if _simulate_action(cap, next_pieces, next_costs, next_reserves, next_hands, current_side):
				var score := _quiescence_search(next_pieces, next_costs, next_reserves, next_hands, 1 - current_side, depth + 1)
				if score > max_score:
					max_score = score
		return max_score
	else:
		# 相手手番（評価最小化・最悪反撃）
		var min_score: float = static_eval
		for cap in captures:
			var next_pieces := pieces_state.duplicate(true)
			var next_costs := [costs_state[0], costs_state[1]]
			var next_reserves := [reserves_state[0], reserves_state[1]]
			var next_hands := [hands_state[0].duplicate(true), hands_state[1].duplicate(true)]

			if _simulate_action(cap, next_pieces, next_costs, next_reserves, next_hands, current_side):
				var score := _quiescence_search(next_pieces, next_costs, next_reserves, next_hands, 1 - current_side, depth + 1)
				if score < min_score:
					min_score = score
		return min_score


# 指定盤面における指定手番の「捕獲手（駒を取る移動）」を列挙する
func _generate_capture_actions(pieces_state: Dictionary, side: int) -> Array[Dictionary]:
	var captures: Array[Dictionary] = []
	var opp := 1 - side

	for from_sq in pieces_state:
		var p: Dictionary = pieces_state[from_sq]
		if int(p.get("owner", -1)) != side:
			continue
		var cat: String = str(p.get("category", ""))
		if cat != "兵" and cat != "王" and cat != "成":
			continue

		for to_sq in pieces_state:
			var target: Dictionary = pieces_state[to_sq]
			if int(target.get("owner", -1)) != opp:
				continue
			var target_cat: String = str(target.get("category", ""))
			if target_cat == "壁":
				continue

			if MovementRules.can_move_shape(from_sq, to_sq, p) and not WallRules.blocks_path(pieces_state, from_sq, to_sq) and CheckRules._path_is_clear(pieces_state, from_sq, to_sq):
				captures.append({
					"action": "move",
					"from": from_sq,
					"to": to_sq
				})

	return captures


# すべての合法手（召喚・駒移動・壁破壊等）を生成する
func _generate_all_legal_actions() -> Array[Dictionary]:
	var actions: Array[Dictionary] = []
	if game_ref == null:
		return actions

	var current_cost: int = int(game_ref.costs[player_id])

	actions.append_array(_generate_summon_actions(current_cost))

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

				if game_ref.has_method("can_move"):
					if not game_ref.can_move(from_sq, to_sq):
						continue
				else:
					if category == "兵":
						var summoned_turn: int = int(piece.get("summoned_turn", -1))
						var turn_cnt = game_ref.get("turn_counts")
						if turn_cnt != null and summoned_turn == int(turn_cnt[player_id]):
							continue

					if game_ref.pieces.has(to_sq):
						var target: Dictionary = game_ref.pieces[to_sq]
						var target_cat: String = str(target.get("category", ""))
						if target_cat == "壁":
							continue
						if int(target.get("owner", -1)) == player_id:
							continue
						if target_cat == "罠" and not TrapRules.can_enter_trap_square(target, piece):
							continue

					if not MovementRules.can_move_shape(from_sq, to_sq, piece):
						continue
					if WallRules.blocks_path(game_ref.pieces, from_sq, to_sq):
						continue
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

			# 成り判定
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

			# 敵駒捕獲判定
			if sim_pieces.has(to_sq):
				var target_p: Dictionary = sim_pieces[to_sq]
				var t_cat := str(target_p.get("category", ""))
				if t_cat in ["兵", "王"]:
					var cap_card: Dictionary = target_p.duplicate(true)
					cap_card["owner"] = acting_player
					sim_hands[acting_player].append(cap_card)

			sim_pieces[to_sq] = moving
			return true

		"end_turn":
			return true

	return false
