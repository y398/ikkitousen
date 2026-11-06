# ==================================================
# ファイル名: BoardEvaluator.gd
# 概要: 盤面状況・駒の価値・王の安全度・利きの支配度を数値化して評価するクラスである
# ==================================================

extends RefCounted

const MovementRules = preload("res://scripts/rules/MovementRules.gd")
const CheckRules = preload("res://scripts/rules/CheckRules.gd")
const WallRules = preload("res://scripts/rules/WallRules.gd")

# 駒の基礎価値スコア
const PIECE_VALUES: Dictionary = {
	"王": 100000,
	"飛": 85,
	"龍": 110,
	"角": 75,
	"馬": 100,
	"金": 50,
	"銀": 40,
	"成銀": 55,
	"桂": 30,
	"成桂": 55,
	"香": 25,
	"成香": 55,
	"歩": 10,
	"と金": 55,
	"弓手": 45,
	"旗本": 50,
	"竹束": 20,
	"陣幕": 20,
	"馬防柵": 30,
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
	costs: Array[int],
	reserves: Array[int],
	hands: Array
) -> float:
	var opponent := 1 - evaluating_player

	# 王が取られている場合の即座判定
	var eval_king_alive := false
	var opp_king_alive := false
	for sq in pieces:
		var p: Dictionary = pieces[sq]
		if str(p.get("category", "")) == "王":
			if int(p.get("owner", -1)) == evaluating_player:
				eval_king_alive = true
			elif int(p.get("owner", -1)) == opponent:
				opp_king_alive = true

	if not eval_king_alive:
		return -999999.0
	if not opp_king_alive:
		return 999999.0

	# 1 駒の価値（マテリアル）
	var material_score := _calculate_material_score(pieces, evaluating_player)

	# 2 王の安全度（キングセーフティ）
	var king_safety_score := _calculate_king_safety(pieces, evaluating_player) - _calculate_king_safety(pieces, opponent)

	# 3 盤面の利きと支配度（モビリティ/コントロール）
	var territory_score := _calculate_board_control(pieces, evaluating_player)

	# 4 リソース（コスト・備蓄・手札）
	var resource_score := _calculate_resource_score(evaluating_player, costs, reserves, hands)

	# 総合評価の合算
	var total_score: float = material_score * 1.0 + king_safety_score * 0.8 + territory_score * 0.5 + resource_score * 0.6

	# 王手状態のボーナス/ペナルティ
	if CheckRules.is_in_check(pieces, opponent):
		total_score += 150.0
	if CheckRules.is_in_check(pieces, evaluating_player):
		total_score -= 200.0

	return total_score


# 駒の価値合計差を計算する
static func _calculate_material_score(pieces: Dictionary, evaluating_player: int) -> float:
	var score: float = 0.0
	var opponent := 1 - evaluating_player

	for sq in pieces:
		var p: Dictionary = pieces[sq]
		var owner: int = int(p.get("owner", -1))
		var name: String = str(p.get("name", ""))
		var val: float = float(PIECE_VALUES.get(name, 15))

		# 敵陣に深く侵入している駒にはボーナスを加点する
		var rank: int = sq.x
		if owner == 0 and rank <= 3:
			val += 10.0
		elif owner == 1 and rank >= 7:
			val += 10.0

		if owner == evaluating_player:
			score += val
		elif owner == opponent:
			score -= val

	return score


# 王の周囲の護衛や敵の利きから王の安全度を計算する
static func _calculate_king_safety(pieces: Dictionary, player: int) -> float:
	var king_sq := Vector2i(-1, -1)
	for sq in pieces:
		var p: Dictionary = pieces[sq]
		if str(p.get("category", "")) == "王" and int(p.get("owner", -1)) == player:
			king_sq = sq
			break

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
					safety += 18.0
			else:
				# 敵の利きが及んでいる空きマスは危険度ペナルティ
				if CheckRules.is_square_attacked(pieces, neighbor, opponent):
					safety -= 25.0
				else:
					safety += 4.0 # 安全な退路マス

	return safety


# 盤面全体の利きと中央支配度を計算する
static func _calculate_board_control(pieces: Dictionary, evaluating_player: int) -> float:
	var score: float = 0.0
	var opponent := 1 - evaluating_player

	# 中央マス（5五近辺）の支配度
	for sq in CENTER_SQUARES:
		var my_attack: bool = CheckRules.is_square_attacked(pieces, sq, evaluating_player)
		var opp_attack: bool = CheckRules.is_square_attacked(pieces, sq, opponent)
		if my_attack and not opp_attack:
			score += 12.0
		elif opp_attack and not my_attack:
			score -= 12.0

	return score


# コスト・備蓄・手札枚数のアドバンテージを計算する
static func _calculate_resource_score(
	evaluating_player: int,
	costs: Array[int],
	reserves: Array[int],
	hands: Array
) -> float:
	var opp := 1 - evaluating_player

	var my_cost: float = float(costs[evaluating_player])
	var opp_cost: float = float(costs[opp])

	var my_res: float = float(reserves[evaluating_player])
	var opp_res: float = float(reserves[opp])

	var my_hand_size: float = float(hands[evaluating_player].size()) if hands.size() > evaluating_player else 0.0
	var opp_hand_size: float = float(hands[opp].size()) if hands.size() > opp else 0.0

	var cost_diff: float = (my_cost + my_res * 1.2) - (opp_cost + opp_res * 1.2)
	var hand_diff: float = (my_hand_size - opp_hand_size) * 14.0

	return cost_diff * 8.0 + hand_diff

