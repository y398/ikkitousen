# ==================================================
# ファイル名: SummonRules.gd
# 概要: 兵・罠の召喚制限ライン（最前線判定）や領地マスへの配置可否などの召喚条件を判定するルールクラスである
# ==================================================

extends RefCounted


# 現在の自軍の最前線を取得する
# 先手：最も小さい段番号
# 後手：最も大きい段番号
static func get_frontline(
	pieces: Dictionary,
	player: int
) -> int:
	var frontline: int = 7 if player == 0 else 3

	for piece_square in pieces:
		var piece: Dictionary = pieces[piece_square]

		if int(piece.get("owner", -1)) != player:
			continue

		var category: String = str(piece.get("category", ""))

		# 壁と罠は前線の計算対象外
		if category == "壁" or category == "罠":
			continue

		if player == 0:
			frontline = mini(frontline, piece_square.x)
		else:
			frontline = maxi(frontline, piece_square.x)

	return frontline


# 指定マスが召喚制限ラインの範囲内か
static func is_in_summon_range(
	pieces: Dictionary,
	square: Vector2i,
	player: int
) -> bool:
	if player != 0 and player != 1:
		return false

	if square.x < 1 or square.x > 9:
		return false
	if square.y < 1 or square.y > 9:
		return false

	var frontline: int = get_frontline(pieces, player)

	if player == 0:
		return square.x >= frontline

	return square.x <= frontline


# 兵・罠を配置できない理由を返す
# 配置可能なら空文字を返す
static func get_non_wall_placement_error(
	pieces: Dictionary,
	square: Vector2i,
	player: int,
	category: String
) -> String:
	if player != 0 and player != 1:
		return "プレイヤーの指定が不正です。"

	var is_territory_square: bool = (
		square == Vector2i(5, 2)
		or square == Vector2i(5, 8)
	)

	# 罠は領地マスに配置できない
	if category == "罠" and is_territory_square:
		return "領地マスには罠を召喚できません。"

	# 領地マスも例外扱いしない。兵を含め、召喚制限ラインが到達した場合のみ配置できる。
	if not is_in_summon_range(pieces, square, player):
		return "召喚は自陣から自軍の最前線までの範囲に限られます。"

	return ""
