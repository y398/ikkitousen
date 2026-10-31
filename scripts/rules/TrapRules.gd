# ==================================================
# ファイル名: TrapRules.gd
# 概要: 落とし穴・伏兵・石落とし等の罠カードの自動発動・手動起動判定および対象候補の算出を行うルールクラスである
# ==================================================

extends RefCounted

const SPECIAL_EFFECT_IDS: Array[String] = ["ambush_three_squares", "stone_drop_front_two"]


# 罠の効果IDを取得　古い保存データでもカード名から補完する
static func get_effect_id(trap_piece: Dictionary) -> String:
	var effect_id := str(trap_piece.get("trap_effect", ""))
	if not effect_id.is_empty():
		return effect_id
	var card_name := str(trap_piece.get("name", ""))
	match card_name:
		"落とし穴":
			return "destroy_soldier"
		"伏兵":
			return "ambush_three_squares"
		"石落とし", "石落し":
			return "stone_drop_front_two"
		_:
			return ""


static func is_special_effect(effect_id: String) -> bool:
	return SPECIAL_EFFECT_IDS.has(effect_id)


# 伏兵・石落としが墓地送りにできる相手の駒。
static func is_special_target(target_piece: Dictionary, trap_owner: int) -> bool:
	var category := str(target_piece.get("category", ""))
	var target_owner := int(target_piece.get("owner", -1))
	return category in ["兵", "王", "成"] and target_owner >= 0 and target_owner != trap_owner


# 罠が自動発動するときに踏んだ駒の種類が条件を満たすか。
# 新罠は説明どおり「兵」が来た時に発動。既存の落とし穴は従来の兵・王・成を対象にする。
static func should_auto_trigger(trap_piece: Dictionary, moving_piece: Dictionary) -> bool:
	if str(trap_piece.get("category", "")) != "罠":
		return false
	if not bool(trap_piece.get("is_face_down", false)):
		return false
	var moving_category := str(moving_piece.get("category", ""))
	var effect_id := get_effect_id(trap_piece)
	if is_special_effect(effect_id):
		return moving_category == "兵"
	return moving_category in ["兵", "王", "成"]


# 対象の罠マスへ移動してよいか。通常捕獲で罠を手札に取ることを防ぐ。
static func can_enter_trap_square(trap_piece: Dictionary, moving_piece: Dictionary) -> bool:
	return should_auto_trigger(trap_piece, moving_piece)


# 移動元から移動先までに踏む／通過する罠を近い順に返す。
# 直線・斜め移動は経路全体、桂馬などの跳躍は到着マスのみ確認する。
static func get_triggered_traps(
	pieces: Dictionary,
	from_square: Vector2i,
	to_square: Vector2i,
	_moving_piece: Dictionary,
	board_size: int = 9
) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var dx := to_square.x - from_square.x
	var dy := to_square.y - from_square.y
	var is_straight_path : bool = dx == 0 or dy == 0 or abs(dx) == abs(dy)
	var route: Array[Vector2i] = []

	if is_straight_path:
		var step := Vector2i(signi(dx), signi(dy))
		var cursor: Vector2i = from_square + step
		while true:
			route.append(cursor)
			if cursor == to_square:
				break
			cursor += step
	else:
		route.append(to_square)

	for route_square in route:
		if route_square.x < 1 or route_square.x > board_size or route_square.y < 1 or route_square.y > board_size:
			continue
		if not pieces.has(route_square):
			continue
		var route_piece: Dictionary = pieces[route_square]
		if str(route_piece.get("category", "")) != "罠":
			continue
		if not bool(route_piece.get("is_face_down", false)):
			continue
		if not result.has(route_square):
			result.append(route_square)
	return result


# 伏兵の発動時に選択できる、伏兵から見て左前・右前・後ろの敵兵／成／王。
static func get_ambush_target_squares(
	pieces: Dictionary,
	trap_square: Vector2i,
	trap_owner: int,
	ignored_square: Vector2i,
	board_size: int = 9
) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var forward_step := -1 if trap_owner == 0 else 1
	var candidate_squares: Array[Vector2i] = [
		Vector2i(trap_square.x + forward_step, trap_square.y - 1),
		Vector2i(trap_square.x + forward_step, trap_square.y + 1),
		Vector2i(trap_square.x - forward_step, trap_square.y)
	]
	for target_square in candidate_squares:
		if target_square == ignored_square:
			continue
		if target_square.x < 1 or target_square.x > board_size or target_square.y < 1 or target_square.y > board_size:
			continue
		if not pieces.has(target_square):
			continue
		if is_special_target(pieces[target_square], trap_owner):
			result.append(target_square)
	return result


# 石落としの前方1～2マスから、途中に壁がない最も近い敵駒を返す。
static func find_stone_drop_target(
	pieces: Dictionary,
	trap_square: Vector2i,
	trap_owner: int,
	ignored_square: Vector2i,
	board_size: int = 9
) -> Vector2i:
	var forward_step := -1 if trap_owner == 0 else 1
	for distance in range(1, 3):
		var target_square := Vector2i(trap_square.x + forward_step * distance, trap_square.y)
		if target_square.x < 1 or target_square.x > board_size:
			break
		if target_square == ignored_square:
			continue

		var blocked_by_wall := false
		for step_distance in range(1, distance + 1):
			var between_square := Vector2i(trap_square.x + forward_step * step_distance, trap_square.y)
			if pieces.has(between_square) and str(pieces[between_square].get("category", "")) == "壁":
				blocked_by_wall = true
				break
		if blocked_by_wall:
			break

		if pieces.has(target_square) and is_special_target(pieces[target_square], trap_owner):
			return target_square
	return Vector2i(-1, -1)


# 効果IDから、対象選択型／自動対象型というUI非依存の処理方式を返す。
static func prepare_special_activation(
	pieces: Dictionary,
	trap_square: Vector2i,
	trap_piece: Dictionary,
	trap_owner: int,
	ignored_square: Vector2i,
	board_size: int = 9
) -> Dictionary:
	match get_effect_id(trap_piece):
		"ambush_three_squares":
			return {
				"mode": "choose_target",
				"candidates": get_ambush_target_squares(pieces, trap_square, trap_owner, ignored_square, board_size),
				"target_square": Vector2i(-1, -1)
			}
		"stone_drop_front_two":
			return {
				"mode": "single_target",
				"candidates": [],
				"target_square": find_stone_drop_target(pieces, trap_square, trap_owner, ignored_square, board_size)
			}
		_:
			return {"mode": "none", "candidates": [], "target_square": Vector2i(-1, -1)}


# 既存の汎用罠（落とし穴）の判定。盤面変更は呼び出し側に任せる。
static func resolve_trap_effect(
	trap_piece: Dictionary,
	moving_piece: Dictionary
) -> Dictionary:
	if str(trap_piece.get("category", "")) != "罠":
		return {"triggered": false}
	if not should_auto_trigger(trap_piece, moving_piece):
		return {"triggered": false}

	match get_effect_id(trap_piece):
		"destroy_soldier":
			return {
				"triggered": true,
				"consume_trap": true,
				"piece_outcome": "destroy",
				"message": "落とし穴が発動しました。"
			}
		_:
			return {"triggered": false}
