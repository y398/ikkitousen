# ==================================================
# ファイル名: BoardEvaluator.gd
# 概要: 盤面状況・駒の価値・王の安全度・利きの支配度・敵王包囲圧力を数値化して評価するクラスである
# ==================================================

extends RefCounted

const MovementRules = preload("res://scripts/rules/MovementRules.gd")
const CheckRules = preload("res://scripts/rules/CheckRules.gd")
const WallRules = preload("res://scripts/rules/WallRules.gd")
const SummonRules = preload("res://scripts/rules/SummonRules.gd")

# 駒の基礎価値スコア
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


# 指定プレイヤー視点での盤面総合評価値を算出する（プラスが大きいほど有利）
static func evaluate_board(
	pieces: Dictionary,
	evaluating_player: int,
	costs: Array,
	reserves: Array,
	hands: Array
) -> float:
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
	var material_score := _calculate_material_score(pieces, evaluating_player)

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

	# 総合評価の合算
	var total_score: float = (
		material_score * 1.0
		+ attack_pressure_score * 1.1
		+ king_safety_score * 0.7
		+ territory_score * 0.6
		+ frontline_score * 0.8
		+ resource_score * 0.5
	)

	# 王手状態の大幅ボーナス/ペナルティ
	if CheckRules.is_in_check(pieces, opponent):
		total_score += 280.0
	if CheckRules.is_in_check(pieces, evaluating_player):
		total_score -= 350.0

	return total_score


# 駒の価値合計差を計算する（敵陣への侵入成りを高く評価）
static func _calculate_material_score(pieces: Dictionary, evaluating_player: int) -> float:
	var score: float = 0.0
	var opponent := 1 - evaluating_player

	for sq in pieces:
		var p: Dictionary = pieces[sq]
		var owner: int = int(p.get("owner", -1))
		var piece_name: String = str(p.get("name", ""))
		var val: float = float(PIECE_VALUES.get(piece_name, 15))

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
