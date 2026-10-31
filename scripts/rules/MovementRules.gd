# ==================================================
# ファイル名: MovementRules.gd
# 概要: 歩・香・桂・銀・金・角・飛・王・馬・龍・旗本等の駒固有の移動パターンと形状判定を行うルールクラスである
# ==================================================

extends RefCounted


# 駒が移動先のマスへ動ける形かどうかを判定する
static func can_move_shape(
	from_square: Vector2i,
	to_square: Vector2i,
	piece: Dictionary
) -> bool:

	if from_square == to_square:
		return false

	var dx: int = to_square.x - from_square.x
	var dy: int = to_square.y - from_square.y

	var owner: int = int(piece.get("owner", 0))
	var forward: int = -1 if owner == 0 else 1

	# 移動方式を取得する
	var movement_type: String = str(
		piece.get("movement_type", "")
	)

	# 以前から存在する盤上の駒にも対応する
	if movement_type == "":
		movement_type = _get_movement_type(
			str(piece.get("name", ""))
		)

	match movement_type:

		"king":
			return max(abs(dx), abs(dy)) == 1

		"pawn":
			return dx == forward and dy == 0

		"lance":
			return dx * forward > 0 and dy == 0

		"knight":
			return (
				dx == 2 * forward
				and abs(dy) == 1
			)

		"silver":
			return (
				(dx == forward and abs(dy) <= 1)
				or
				(dx == -forward and abs(dy) == 1)
			)

		"gold":
			return (
				(dx == forward and abs(dy) <= 1)
				or
				(dx == 0 and abs(dy) == 1)
				or
				(dx == -forward and dy == 0)
			)

		"bishop":
			return abs(dx) == abs(dy)

		"rook":
			return (
				(dx == 0 and dy != 0)
				or
				(dy == 0 and dx != 0)
			)
		"horse":
			# 馬：角の動き＋上下左右に1マス
			return (
				(abs(dx) == abs(dy) and dx != 0)
				or (
					max(abs(dx), abs(dy)) == 1
					and (dx == 0 or dy == 0)
				)
			)

		"dragon":
			# 龍：飛の動き＋斜めに1マス
			return (
				(
					(dx == 0 and dy != 0)
					or (dy == 0 and dx != 0)
				)
				or (abs(dx) == 1 and abs(dy) == 1)
			)

		"hatamoto":
			# 旗本：正面1マスと真後ろ1マス
			return abs(dx) == 1 and dy == 0

		"archer":
			# 弓手：進行方向の左右斜め前
			return dx == forward and abs(dy) == 1

		"promoted_archer":
			# 成弓：正面1マス、左右斜め後ろ1マス
			return (dx == forward and dy == 0) or (dx == -forward and abs(dy) == 1)

		_:
			return false


# 日本語の駒名を移動方式に対応させる
static func _get_movement_type(
	piece_name: String
) -> String:

	match piece_name:
		"王", "玉":
			return "king"
		"歩":
			return "pawn"
		"香":
			return "lance"
		"桂":
			return "knight"
		"銀":
			return "silver"
		"金":
			return "gold"
		"角":
			return "bishop"
		"飛":
			return "rook"
		"と金", "と銀", "成香", "成桂", "成銀":
			return "gold"
		"馬":
			return "horse"
		"龍":
			return "dragon"
		"旗本":
			return "hatamoto"
		"弓手":
			return "archer"
		"成弓":
			return "promoted_archer"
		_:
			return ""
