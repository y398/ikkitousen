extends RefCounted

# 弓手または成弓かどうか。旧データにも対応するため名前も見る。
static func is_archer(piece: Dictionary) -> bool:
	return str(piece.get("movement_type", "")) in ["archer", "promoted_archer"] or str(piece.get("name", "")) in ["弓手", "成弓"]


# 弓手・成弓の攻撃先。正面2マス先にいる敵駒だけを返す。
# 中間のマスは「一つ飛ばし」のため、ここでは対象確認に使わない。
static func get_archer_target_square(
	pieces: Dictionary,
	archer_square: Vector2i,
	attacking_player: int,
	board_size: int = 9
) -> Vector2i:
	if not pieces.has(archer_square):
		return Vector2i(-1, -1)
	var archer: Dictionary = pieces[archer_square]
	if not is_archer(archer):
		return Vector2i(-1, -1)
	if int(archer.get("owner", -1)) != attacking_player:
		return Vector2i(-1, -1)

	var forward_step := -1 if attacking_player == 0 else 1
	var target_square := Vector2i(archer_square.x + 2 * forward_step, archer_square.y)
	if target_square.x < 1 or target_square.x > board_size:
		return Vector2i(-1, -1)
	if not pieces.has(target_square):
		return Vector2i(-1, -1)
	if int(pieces[target_square].get("owner", -1)) != 1 - attacking_player:
		return Vector2i(-1, -1)
	return target_square


static func can_attack(
	pieces: Dictionary,
	archer_square: Vector2i,
	attacking_player: int,
	board_size: int = 9
) -> bool:
	return get_archer_target_square(pieces, archer_square, attacking_player, board_size).x >= 1
