extends RefCounted

const MovementRules = preload("res://scripts/rules/MovementRules.gd")
const WallRules = preload("res://scripts/rules/WallRules.gd")


# 指定したプレイヤーの王が王手を受けているか
static func is_in_check(
	pieces: Dictionary,
	player: int
) -> bool:
	# 対象プレイヤーの王を探す
	for square in pieces:
		var piece: Dictionary = pieces[square]

		if str(piece.get("category", "")) != "王":
			continue

		if int(piece.get("owner", -1)) != player:
			continue

		# 相手の駒が王のマスを攻撃できるか調べる
		return is_square_attacked(
			pieces,
			square,
			1 - player
		)

	# 王が見つからない場合
	return false


# 指定マスが攻撃側プレイヤーの駒に攻撃されているか
static func is_square_attacked(
	pieces: Dictionary,
	target_square: Vector2i,
	attacking_player: int
) -> bool:
	for from_square in pieces:
		var piece: Dictionary = pieces[from_square]

		if int(piece.get("owner", -1)) != attacking_player:
			continue

		var category: String = str(
			piece.get("category", "")
		)

		# 兵と王以外は攻撃駒として扱わない
		if category != "兵" and category != "王" and category != "成":
			continue

		# 駒の移動形状に合わなければ攻撃できない
		if not MovementRules.can_move_shape(
			from_square,
			target_square,
			piece
		):
			continue

		# 馬防柵が桂馬の跳躍を妨げる場合
		if WallRules.blocks_path(
			pieces,
			from_square,
			target_square
		):
			continue

		# 香・角・飛の通り道を確認
		if not _path_is_clear(
			pieces,
			from_square,
			target_square
		):
			continue

		return true

	return false


# 香・角・飛の通り道が塞がれていないか
static func _path_is_clear(
	pieces: Dictionary,
	from_square: Vector2i,
	to_square: Vector2i
) -> bool:
	var piece: Dictionary = pieces[from_square]
	var piece_name: String = str(
		piece.get("name", "")
	)

	# 直線移動をする駒以外は経路確認不要
	if piece_name not in ["香", "角", "飛","馬","龍"]:
		return true

	var dx: int = to_square.x - from_square.x
	var dy: int = to_square.y - from_square.y

	var step_x: int = signi(dx)
	var step_y: int = signi(dy)

	var pos: Vector2i = (
		from_square + Vector2i(step_x, step_y)
	)

	while pos != to_square:
		if pieces.has(pos):
			var blocking_piece: Dictionary = pieces[pos]

			# 罠は移動経路を塞がない
			if str(blocking_piece.get("category", "")) != "罠":
				return false

		pos += Vector2i(step_x, step_y)

	return true
