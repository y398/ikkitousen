# ==================================================
# ファイル名: BoardEvaluator.gd
# 概要: 盤面状況・駒の価値・王の安全度・利きの支配度・敵王包囲圧力を数値化して評価するクラスである
# ==================================================

extends RefCounted

const MovementRules = preload("res://scripts/rules/MovementRules.gd")
const CheckRules = preload("res://scripts/rules/CheckRules.gd")
const WallRules = preload("res://scripts/rules/WallRules.gd")
const SummonRules = preload("res://scripts/rules/SummonRules.gd")
const AttackRules = preload("res://scripts/rules/AttackRules.gd")
const EvalWeights = preload("res://scripts/ai/EvalWeights.gd")

# 駒の基礎価値スコア（互換性維持のための静的デフォルト辞書）
const PIECE_VALUES: Dictionary = {
	"王": 100000,
	"飛": 90,
	"龍": 125,
	"角": 80,
	"馬": 115,
	"金": 55,
	"銀": 45,
	"成銀": 60,
	"桂": 32,
	"成桂": 60,
	"香": 28,
	"成香": 60,
	"歩": 12,
	"と金": 60,
	"弓手": 48,
	"旗本": 55,
	"竹束": 18,
	"陣幕": 18,
	"馬防柵": 28,
	"落とし穴": 25,
	"伏兵": 30,
	"石落とし": 25,
	"石落し": 25
}

# 中央領域の座標一覧（4〜6段、4〜6筋）
const CENTER_SQUARES: Array[Vector2i] = [
	Vector2i(4, 4), Vector2i(4, 5), Vector2i(4, 6),
	Vector2i(5, 4), Vector2i(5, 5), Vector2i(5, 6),
	Vector2i(6, 4), Vector2i(6, 5), Vector2i(6, 6)
]

# 領地マスの座標一覧（毎ターンコスト+1ボーナスのインカム拠点）
const TERRITORY_SQUARES: Array[Vector2i] = [
	Vector2i(5, 2), # 8五
	Vector2i(5, 8)  # 2五
]

# デフォルトの重みインスタンス（キャッシュ）
static var _default_weights: EvalWeights = null


# デフォルトの重みインスタンスを取得する
static func get_default_weights() -> EvalWeights:
	if _default_weights == null:
		_default_weights = EvalWeights.new()
	return _default_weights


# 指定プレイヤー視点での盤面総合評価値を算出する（プラスが大きいほど有利）
static func evaluate_board(
	pieces: Dictionary,
	evaluating_player: int,
	costs: Array,
	reserves: Array,
	hands: Array,
	weights: EvalWeights = null
) -> float:
	var w: EvalWeights = weights if weights != null else get_default_weights()
	var opponent := 1 - evaluating_player

	# 王が取られている場合の即座判定
	var eval_king_alive := false
	var opp_king_alive := false
	var eval_king_sq := Vector2i(-1, -1)
	var opp_king_sq := Vector2i(-1, -1)

	for sq in pieces:
		var p: Dictionary = pieces[sq]
		if str(p.get("category", "")) == "王":
			if int(p.get("owner", -1)) == evaluating_player:
				eval_king_alive = true
				eval_king_sq = sq
			elif int(p.get("owner", -1)) == opponent:
				opp_king_alive = true
				opp_king_sq = sq

	if not eval_king_alive:
		return -999999.0
	if not opp_king_alive:
		return 999999.0

	# 1 駒の価値（マテリアルおよび敵陣浸透ボーナス）
	var material_score := _calculate_material_score(pieces, evaluating_player, w)

	# 2 敵王への攻撃圧力と包囲度
	var attack_pressure_score := _calculate_attack_pressure(pieces, evaluating_player, opponent, eval_king_sq, opp_king_sq)

	# 3 自軍王の守備力と安全度
	var king_safety_score := _calculate_king_safety(pieces, evaluating_player, eval_king_sq) - _calculate_king_safety(pieces, opponent, opp_king_sq)

	# 4 盤面の利きと中央制圧度
	var territory_score := _calculate_board_control(pieces, evaluating_player)

	# 5 前線ラインの前進度（召喚可能エリアの広さ）
	var frontline_score := _calculate_frontline_score(pieces, evaluating_player, opponent)

	# 6 リソース（コスト・備蓄・手札、盤上展開を阻害しない適正配点）
	var resource_score := _calculate_resource_score(evaluating_player, costs, reserves, hands)

	# 7 領地マス（2五・8五）のインカム支配度（毎ターンコスト+1の戦略価値）
	var territory_income_score := _calculate_territory_square_control(pieces, evaluating_player, w)

	# 8 壁による王の防壁効果および大駒射線の遮断
	var wall_defense_score := _calculate_wall_defense_score(pieces, evaluating_player, eval_king_sq, opponent, w) - _calculate_wall_defense_score(pieces, opponent, opp_king_sq, evaluating_player, w)

	# 局面フェーズ判定（終盤・寄せ合いフェーズかどうかの判定）
	var is_endgame := _is_endgame_phase(pieces, eval_king_sq, opp_king_sq, evaluating_player, opponent)

	# 総合評価の合算（終盤は駒得や中央支配より王手速度・包囲圧力を最優先する）
	var w_material: float = w.w_material_endgame if is_endgame else w.w_material_normal
	var w_pressure: float = w.w_pressure_endgame if is_endgame else w.w_pressure_normal
	var w_safety: float = w.w_safety_endgame if is_endgame else w.w_safety_normal
	var w_territory: float = w.w_territory_endgame if is_endgame else w.w_territory_normal
	var w_frontline: float = w.w_frontline_endgame if is_endgame else w.w_frontline_normal
	var w_resource: float = w.w_resource_endgame if is_endgame else w.w_resource_normal
	var w_territory_income: float = w.w_territory_income_endgame if is_endgame else w.w_territory_income_normal
	var w_wall: float = w.w_wall_endgame if is_endgame else w.w_wall_normal

	var total_score: float = (
		material_score * w_material
		+ attack_pressure_score * w_pressure
		+ king_safety_score * w_safety
		+ territory_score * w_territory
		+ frontline_score * w_frontline
		+ resource_score * w_resource
		+ territory_income_score * w_territory_income
		+ wall_defense_score * w_wall
	)

	# 王手状態の大幅ボーナス/ペナルティ（終盤はさらに評価を激増）
	var check_bonus: float = w.check_bonus_endgame if is_endgame else w.check_bonus_normal
	var check_penalty: float = w.check_penalty_endgame if is_endgame else w.check_penalty_normal

	if CheckRules.is_in_check(pieces, opponent):
		total_score += check_bonus
	if CheckRules.is_in_check(pieces, evaluating_player):
		total_score -= check_penalty

	# 弓手・成弓の正面2マス射程判定（王への射程直撃は即死・即勝利危機として評価）
	for sq in pieces:
		var piece_data: Dictionary = pieces[sq]
		if AttackRules.is_archer(piece_data):
			var shooter_owner: int = int(piece_data.get("owner", -1))
			var target_sq: Vector2i = AttackRules.get_archer_target_square(pieces, sq, shooter_owner)
			if target_sq.x >= 1 and pieces.has(target_sq):
				var target_piece: Dictionary = pieces[target_sq]
				var t_cat: String = str(target_piece.get("category", ""))
				var t_name: String = str(target_piece.get("name", ""))
				if t_cat == "王" or t_name == "王":
					if shooter_owner == evaluating_player:
						total_score += 90000.0
					else:
						total_score -= 95000.0
				else:
					var target_val: float = float(w.piece_values.get(t_name, PIECE_VALUES.get(t_name, 20)))
					if shooter_owner == evaluating_player:
						total_score += target_val * 1.2
					else:
						total_score -= target_val * 1.3

	return total_score


# 終盤（寄せ合い・詰み争い）フェーズかどうかを判定する
static func _is_endgame_phase(
	pieces: Dictionary,
	eval_king_sq: Vector2i,
	opp_king_sq: Vector2i,
	evaluating_player: int,
	opponent: int
) -> bool:
	# いずれかが王手を受けている場合は終盤
	if CheckRules.is_in_check(pieces, evaluating_player) or CheckRules.is_in_check(pieces, opponent):
		return true

	# 敵王または自軍王の周囲2マス以内に敵駒が迫っているか判定
	for sq in pieces:
		var p: Dictionary = pieces[sq]
		var owner: int = int(p.get("owner", -1))
		var cat: String = str(p.get("category", ""))
		if cat != "兵" and cat != "成":
			continue

		if owner == evaluating_player:
			if absi(sq.x - opp_king_sq.x) + absi(sq.y - opp_king_sq.y) <= 2:
				return true
		elif owner == opponent:
			if absi(sq.x - eval_king_sq.x) + absi(sq.y - eval_king_sq.y) <= 2:
				return true

	return false


# 駒の価値合計差を計算する（敵陣への侵入成りを高く評価）
static func _calculate_material_score(pieces: Dictionary, evaluating_player: int, w: EvalWeights) -> float:
	var score: float = 0.0
	var opponent := 1 - evaluating_player

	for sq in pieces:
		var p: Dictionary = pieces[sq]
		var owner: int = int(p.get("owner", -1))
		var piece_name: String = str(p.get("name", ""))
		var val: float = float(w.piece_values.get(piece_name, PIECE_VALUES.get(piece_name, 15)))

		# 敵陣に深く侵入している駒への成りと攻撃ボーナス
		var rank: int = sq.x
		if owner == 0 and rank <= 3:
			val += 25.0
		elif owner == 1 and rank >= 7:
			val += 25.0

		if owner == evaluating_player:
			score += val
		elif owner == opponent:
			score -= val

	return score


# 敵王への接近距離・包囲の利きの強さを計算する
static func _calculate_attack_pressure(
	pieces: Dictionary,
	evaluating_player: int,
	opponent: int,
	eval_king_sq: Vector2i,
	opp_king_sq: Vector2i
) -> float:
	var pressure: float = 0.0

	# 1 自軍の各攻撃駒から敵王への接近度
	for sq in pieces:
		var p: Dictionary = pieces[sq]
		var owner: int = int(p.get("owner", -1))
		var cat: String = str(p.get("category", ""))
		if cat != "兵" and cat != "成" and cat != "王":
			continue

		var dist_to_opp_king: int = absi(sq.x - opp_king_sq.x) + absi(sq.y - opp_king_sq.y)
		var dist_to_my_king: int = absi(sq.x - eval_king_sq.x) + absi(sq.y - eval_king_sq.y)

		if owner == evaluating_player:
			# 敵王に近いほど大きな加点
			if dist_to_opp_king == 1:
				pressure += 40.0
			elif dist_to_opp_king == 2:
				pressure += 24.0
			elif dist_to_opp_king == 3:
				pressure += 15.0
			elif dist_to_opp_king == 4:
				pressure += 8.0
		elif owner == opponent:
			# 相手の駒が自軍の王に迫っている場合は危機として減点
			if dist_to_my_king == 1:
				pressure -= 45.0
			elif dist_to_my_king == 2:
				pressure -= 28.0
			elif dist_to_my_king == 3:
				pressure -= 16.0

	# 2 敵王の周囲8マスに対する利きの刺さり具合（包囲度）
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			if dx == 0 and dy == 0:
				continue
			var target_sq := Vector2i(opp_king_sq.x + dx, opp_king_sq.y + dy)
			if target_sq.x >= 1 and target_sq.x <= 9 and target_sq.y >= 1 and target_sq.y <= 9:
				if CheckRules.is_square_attacked(pieces, target_sq, evaluating_player):
					pressure += 20.0

	return pressure


# 王の周囲の護衛や敵の利きから王の安全度を計算する
static func _calculate_king_safety(pieces: Dictionary, player: int, king_sq: Vector2i) -> float:
	if king_sq == Vector2i(-1, -1):
		return -10000.0

	var safety: float = 0.0
	var opponent := 1 - player

	# 王の周囲8マスを走査する
	for dx in [-1, 0, 1]:
		for dy in [-1, 0, 1]:
			if dx == 0 and dy == 0:
				continue
			var neighbor := Vector2i(king_sq.x + dx, king_sq.y + dy)
			if neighbor.x < 1 or neighbor.x > 9 or neighbor.y < 1 or neighbor.y > 9:
				continue

			# 味方の駒や壁があれば守備力アップ
			if pieces.has(neighbor):
				var p: Dictionary = pieces[neighbor]
				if int(p.get("owner", -1)) == player:
					safety += 14.0
			else:
				# 敵の利きが及んでいる空きマスは危険度ペナルティ
				if CheckRules.is_square_attacked(pieces, neighbor, opponent):
					safety -= 22.0
				else:
					safety += 5.0 # 安全な退路マス

	return safety


# 盤面中央エリア（5五周辺）の制圧度を計算する
static func _calculate_board_control(pieces: Dictionary, evaluating_player: int) -> float:
	var score: float = 0.0
	var opponent := 1 - evaluating_player

	for sq in CENTER_SQUARES:
		var my_attack: bool = CheckRules.is_square_attacked(pieces, sq, evaluating_player)
		var opp_attack: bool = CheckRules.is_square_attacked(pieces, sq, opponent)
		if my_attack and not opp_attack:
			score += 15.0
		elif opp_attack and not my_attack:
			score -= 15.0

	return score


# 最前線ラインの前進度を評価する
static func _calculate_frontline_score(pieces: Dictionary, evaluating_player: int, opponent: int) -> float:
	var my_front := SummonRules.get_frontline(pieces, evaluating_player)
	var opp_front := SummonRules.get_frontline(pieces, opponent)

	var my_push: float = 0.0
	var opp_push: float = 0.0

	# 先手（下から上へ前進: 段数が小さくなるほど前進）
	if evaluating_player == 0:
		my_push = float(7 - my_front) * 12.0
		opp_push = float(opp_front - 3) * 12.0
	else:
		my_push = float(my_front - 3) * 12.0
		opp_push = float(7 - opp_front) * 12.0

	return my_push - opp_push


# コスト・備蓄・手札枚数のアドバンテージを計算する（盤上展開を阻害しない適正重み）
static func _calculate_resource_score(
	evaluating_player: int,
	costs: Array,
	reserves: Array,
	hands: Array
) -> float:
	var opp := 1 - evaluating_player

	var my_cost: float = float(costs[evaluating_player])
	var opp_cost: float = float(costs[opp])

	var my_res: float = float(reserves[evaluating_player])
	var opp_res: float = float(reserves[opp])

	var my_hand_size: float = float(hands[evaluating_player].size()) if hands.size() > evaluating_player else 0.0
	var opp_hand_size: float = float(hands[opp].size()) if hands.size() > opp else 0.0

	# 盤面への展開利益を阻害しないよう係数を適正に抑える
	var cost_diff: float = (my_cost + my_res * 1.1) - (opp_cost + opp_res * 1.1)
	var hand_diff: float = (my_hand_size - opp_hand_size)

	return cost_diff * 2.5 + hand_diff * 3.5


# 領地マス（2五・8五）の占拠および制圧によるインカム利益を計算する
static func _calculate_territory_square_control(pieces: Dictionary, evaluating_player: int, w: EvalWeights) -> float:
	var score: float = 0.0
	var opponent := 1 - evaluating_player

	for t_sq in TERRITORY_SQUARES:
		# 1 領地マス自体の占拠（兵・成・王がいれば毎ターンコスト+1インカム）
		if pieces.has(t_sq):
			var occupant: Dictionary = pieces[t_sq]
			var occ_owner: int = int(occupant.get("owner", -1))
			var occ_cat: String = str(occupant.get("category", ""))
			if occ_cat in ["兵", "成", "王"]:
				if occ_owner == evaluating_player:
					score += w.territory_occupy_bonus
				elif occ_owner == opponent:
					score -= w.territory_enemy_penalty
		else:
			# 2 空きマスに対する利きの支配度（進入・確保の優勢）
			var my_attack := CheckRules.is_square_attacked(pieces, t_sq, evaluating_player)
			var opp_attack := CheckRules.is_square_attacked(pieces, t_sq, opponent)
			if my_attack and not opp_attack:
				score += w.territory_attack_control
			elif opp_attack and not my_attack:
				score -= w.territory_attack_control

	return score


# 壁による王の防壁効果および敵大駒の射線遮断効果を計算する
static func _calculate_wall_defense_score(pieces: Dictionary, player: int, king_sq: Vector2i, opp: int, w: EvalWeights) -> float:
	if king_sq == Vector2i(-1, -1):
		return 0.0

	var score: float = 0.0
	var forward_step := -1 if player == 0 else 1

	# 1 王の前方1〜2マスの防壁判定（正面からの王手や突撃を遮断する盾）
	for step in [1, 2]:
		var front_sq := Vector2i(king_sq.x + step * forward_step, king_sq.y)
		if pieces.has(front_sq):
			var p: Dictionary = pieces[front_sq]
			if str(p.get("category", "")) == "壁" and int(p.get("owner", -1)) == player:
				score += w.wall_front_bonus_1 if step == 1 else w.wall_front_bonus_2

	# 2 敵の直線大駒（飛車・香車）と自軍王との間にある壁の射線遮断評価
	for sq in pieces:
		var p: Dictionary = pieces[sq]
		if int(p.get("owner", -1)) != opp:
			continue
		var m_type: String = str(p.get("movement_type", ""))
		if m_type in ["rook", "dragon", "lance"] and (sq.x == king_sq.x or sq.y == king_sq.y):
			if WallRules.blocks_path(pieces, sq, king_sq):
				score += w.wall_block_ray_bonus

	return score
