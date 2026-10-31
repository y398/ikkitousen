extends RefCounted
const SummonRules = preload("res://scripts/rules/SummonRules.gd")


# 指定マスが壁かどうか
static func is_wall_at(
	pieces: Dictionary,
	square: Vector2i
) -> bool:
	if not pieces.has(square):
		return false

	return pieces[square].get("category", "") == "壁"


# 指定マスの壁が桂馬の跳躍を妨害するか
static func blocks_knight_at(
	pieces: Dictionary,
	square: Vector2i
) -> bool:
	if not pieces.has(square):
		return false

	var piece: Dictionary = pieces[square]

	return (
		piece.get("category", "") == "壁"
		and bool(piece.get("blocks_knight", false))
	)


# 指定したマスに壁を配置できるか判定する
static func is_valid_wall_square(
	pieces: Dictionary,
	square: Vector2i,
	player: int
) -> bool:
	# 盤面の範囲外には配置できない
	if square.x < 1 or square.x > 9:
		return false

	if square.y < 1 or square.y > 9:
		return false

	# 駒や別の壁があるマスには配置できない
	if pieces.has(square):
		return false

	# 領地マスには壁を配置できない
	var is_territory_square: bool = (
		square == Vector2i(5, 2)
		or square == Vector2i(5, 8)
	)

	if is_territory_square:
		return false

	# 自陣から自軍の前線までの範囲に限る
	return SummonRules.is_in_summon_range(
		pieces,
		square,
		player
	)


# 壁が指定されたマスの列・行を通過する移動を妨害するか
static func blocks_path(
	pieces: Dictionary,
	from_square: Vector2i,
	to_square: Vector2i
) -> bool:
	var dx: int = to_square.x - from_square.x
	var dy: int = to_square.y - from_square.y

	# 桂馬の跳躍以外は、この関数では妨害しない
	if abs(dx) != 2 or abs(dy) != 1:
		return false

	# 跳躍の中間位置にある2マスを調べる
	var middle_x: int = from_square.x + signi(dx)

	var intermediate_a := Vector2i(
		middle_x,
		from_square.y
	)
	var intermediate_b := Vector2i(
		middle_x,
		to_square.y
	)

	# 馬防柵など、桂馬を妨害する壁があれば移動を禁止
	return (
		blocks_knight_at(pieces, intermediate_a)
		or blocks_knight_at(pieces, intermediate_b)
	)


# 駒が壁を破壊できる位置にいるかを判定する
static func can_destroy_wall(
	pieces: Dictionary,
	from_square: Vector2i,
	wall_square: Vector2i,
	player: int
) -> bool:
	if from_square == wall_square:
		return false

	if not pieces.has(from_square):
		return false

	if not pieces.has(wall_square):
		return false

	var attacker: Dictionary = pieces[from_square]
	var target: Dictionary = pieces[wall_square]

	# 現在のプレイヤー自身の駒でなければ破壊できない
	if int(attacker.get("owner", -1)) != player:
		return false

	# 壁自身を使って壁を破壊することはできない
	if attacker.get("category", "") == "壁":
		return false

	# 破壊対象が壁でなければならない
	if target.get("category", "") != "壁":
		return false

	# 上下左右に隣接している必要がある
	var distance: int = (
		abs(wall_square.x - from_square.x)
		+ abs(wall_square.y - from_square.y)
	)

	return distance == 1
