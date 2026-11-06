# ==================================================
# ファイル名: EvalWeights.gd
# 概要: 盤面評価関数の各種重みパラメータおよびPST（マス別配置テーブル）を保持し、過学習防止（アンカー制約・上下限クリップ）を伴う変異・保存を行うクラスである
# ==================================================

extends RefCounted
class_name EvalWeights

const PieceSquareTables = preload("res://scripts/ai/PieceSquareTables.gd")

# 駒の基準価値（序列崩壊・過学習防止用アンカー）
const BASE_PIECE_VALUES: Dictionary = {
	"王": 100000.0,
	"飛": 90.0,
	"龍": 125.0,
	"角": 80.0,
	"馬": 115.0,
	"金": 55.0,
	"銀": 45.0,
	"成銀": 60.0,
	"桂": 32.0,
	"成桂": 60.0,
	"香": 28.0,
	"成香": 60.0,
	"歩": 12.0,
	"と金": 60.0,
	"弓手": 48.0,
	"旗本": 55.0,
	"竹束": 18.0,
	"陣幕": 18.0,
	"馬防柵": 28.0,
	"落とし穴": 25.0,
	"伏兵": 30.0,
	"石落とし": 25.0,
	"石落し": 25.0
}

# 各重みパラメータの安全な許容範囲（過学習・極端化防止用クリップレンジ）
const WEIGHT_RANGES: Dictionary = {
	"w_material_normal": Vector2(0.3, 2.0),
	"w_pressure_normal": Vector2(0.4, 2.5),
	"w_safety_normal": Vector2(0.2, 2.0),
	"w_territory_normal": Vector2(0.1, 1.8),
	"w_frontline_normal": Vector2(0.2, 2.0),
	"w_resource_normal": Vector2(0.1, 1.5),
	"w_territory_income_normal": Vector2(0.3, 2.5),
	"w_wall_normal": Vector2(0.2, 2.0),
	"w_material_endgame": Vector2(0.2, 1.5),
	"w_pressure_endgame": Vector2(0.8, 4.0),
	"w_safety_endgame": Vector2(0.5, 3.0),
	"w_territory_endgame": Vector2(0.05, 1.0),
	"w_frontline_endgame": Vector2(0.1, 1.5),
	"w_resource_endgame": Vector2(0.05, 1.0),
	"w_territory_income_endgame": Vector2(0.1, 1.5),
	"w_wall_endgame": Vector2(0.4, 2.5),
	"check_bonus_normal": Vector2(100.0, 600.0),
	"check_penalty_normal": Vector2(100.0, 700.0),
	"check_bonus_endgame": Vector2(200.0, 900.0),
	"check_penalty_endgame": Vector2(200.0, 950.0),
	"territory_occupy_bonus": Vector2(15.0, 100.0),
	"territory_enemy_penalty": Vector2(15.0, 100.0),
	"territory_attack_control": Vector2(5.0, 35.0),
	"wall_front_bonus_1": Vector2(10.0, 60.0),
	"wall_front_bonus_2": Vector2(5.0, 45.0),
	"wall_block_ray_bonus": Vector2(10.0, 60.0)
}

# 駒の基礎価値スコア
var piece_values: Dictionary = BASE_PIECE_VALUES.duplicate(true)

# 通常フェーズ（序盤・中盤）の要素別ウェイト
var w_material_normal: float = 1.0
var w_pressure_normal: float = 1.3
var w_safety_normal: float = 0.7
var w_territory_normal: float = 0.6
var w_frontline_normal: float = 0.8
var w_resource_normal: float = 0.5
var w_territory_income_normal: float = 1.0
var w_wall_normal: float = 0.8

# 終盤フェーズの要素別ウェイト
var w_material_endgame: float = 0.7
var w_pressure_endgame: float = 2.8
var w_safety_endgame: float = 1.4
var w_territory_endgame: float = 0.3
var w_frontline_endgame: float = 0.4
var w_resource_endgame: float = 0.2
var w_territory_income_endgame: float = 0.3
var w_wall_endgame: float = 1.2

# 王手状態ボーナスおよびペナルティ
var check_bonus_normal: float = 320.0
var check_penalty_normal: float = 350.0
var check_bonus_endgame: float = 450.0
var check_penalty_endgame: float = 500.0

# 領地マス（2五・8五）のインカム評価
var territory_occupy_bonus: float = 60.0
var territory_enemy_penalty: float = 50.0
var territory_attack_control: float = 14.0

# 壁による王の防壁および大駒射線遮断
var wall_front_bonus_1: float = 32.0
var wall_front_bonus_2: float = 20.0
var wall_block_ray_bonus: float = 28.0

# マス別配置評価テーブル（Piece-Square Tables）
var pst: RefCounted = null


func _init() -> void:
	pst = PieceSquareTables.new()


# ディープコピーを作成する
func clone() -> RefCounted:
	var copy = (get_script() as GDScript).new()
	copy.piece_values = piece_values.duplicate(true)

	copy.w_material_normal = w_material_normal
	copy.w_pressure_normal = w_pressure_normal
	copy.w_safety_normal = w_safety_normal
	copy.w_territory_normal = w_territory_normal
	copy.w_frontline_normal = w_frontline_normal
	copy.w_resource_normal = w_resource_normal
	copy.w_territory_income_normal = w_territory_income_normal
	copy.w_wall_normal = w_wall_normal

	copy.w_material_endgame = w_material_endgame
	copy.w_pressure_endgame = w_pressure_endgame
	copy.w_safety_endgame = w_safety_endgame
	copy.w_territory_endgame = w_territory_endgame
	copy.w_frontline_endgame = w_frontline_endgame
	copy.w_resource_endgame = w_resource_endgame
	copy.w_territory_income_endgame = w_territory_income_endgame
	copy.w_wall_endgame = w_wall_endgame

	copy.check_bonus_normal = check_bonus_normal
	copy.check_penalty_normal = check_penalty_normal
	copy.check_bonus_endgame = check_bonus_endgame
	copy.check_penalty_endgame = check_penalty_endgame

	copy.territory_occupy_bonus = territory_occupy_bonus
	copy.territory_enemy_penalty = territory_enemy_penalty
	copy.territory_attack_control = territory_attack_control

	copy.wall_front_bonus_1 = wall_front_bonus_1
	copy.wall_front_bonus_2 = wall_front_bonus_2
	copy.wall_block_ray_bonus = wall_block_ray_bonus

	if pst != null:
		copy.pst = pst.clone()

	return copy


# パラメータに変異を加えた新しい重みインスタンスを生成する（過学習防止アンカー制約およびクリップ適用）
func mutate(mutation_rate: float = 0.25, mutation_scale: float = 0.2) -> RefCounted:
	var mutant = clone()

	# 1 駒価値の変異（基準価値の ±30% 以内にアンカーして序列崩壊を防止）
	for piece_name in mutant.piece_values:
		if piece_name == "王":
			continue
		if randf() < mutation_rate:
			var base_val: float = float(BASE_PIECE_VALUES.get(piece_name, 20.0))
			var current_val: float = mutant.piece_values[piece_name]
			var delta: float = current_val * randf_range(-mutation_scale, mutation_scale)
			var min_bound: float = base_val * 0.7
			var max_bound: float = base_val * 1.3
			mutant.piece_values[piece_name] = clampf(current_val + delta, min_bound, max_bound)

	# 駒の基本序列整合性（歩 < 銀 < 金 < 飛）を維持し過学習による序列崩壊を防止
	mutant.piece_values["歩"] = minf(float(mutant.piece_values["歩"]), float(mutant.piece_values["銀"]) - 5.0)
	mutant.piece_values["銀"] = minf(float(mutant.piece_values["銀"]), float(mutant.piece_values["金"]) - 2.0)
	mutant.piece_values["金"] = minf(float(mutant.piece_values["金"]), float(mutant.piece_values["飛"]) - 10.0)

	# 2 各重みパラメータの変異（上下限クリップレンジ内に収めて過学習防止）
	for prop in WEIGHT_RANGES:
		if randf() < mutation_rate:
			var range_vec: Vector2 = WEIGHT_RANGES[prop]
			var current_val: float = mutant.get(prop)
			var delta: float = current_val * randf_range(-mutation_scale, mutation_scale)
			mutant.set(prop, clampf(current_val + delta, range_vec.x, range_vec.y))

	# 3 マス別配置テーブル（PST）の変異
	if mutant.pst != null:
		mutant.pst = mutant.pst.mutate(mutation_rate, 1.2)

	return mutant


# パラメータをDictionary形式で取得する（JSON保存用）
func to_dict() -> Dictionary:
	var data: Dictionary = {
		"piece_values": piece_values,
		"w_material_normal": w_material_normal,
		"w_pressure_normal": w_pressure_normal,
		"w_safety_normal": w_safety_normal,
		"w_territory_normal": w_territory_normal,
		"w_frontline_normal": w_frontline_normal,
		"w_resource_normal": w_resource_normal,
		"w_territory_income_normal": w_territory_income_normal,
		"w_wall_normal": w_wall_normal,
		"w_material_endgame": w_material_endgame,
		"w_pressure_endgame": w_pressure_endgame,
		"w_safety_endgame": w_safety_endgame,
		"w_territory_endgame": w_territory_endgame,
		"w_frontline_endgame": w_frontline_endgame,
		"w_resource_endgame": w_resource_endgame,
		"w_territory_income_endgame": w_territory_income_endgame,
		"w_wall_endgame": w_wall_endgame,
		"check_bonus_normal": check_bonus_normal,
		"check_penalty_normal": check_penalty_normal,
		"check_bonus_endgame": check_bonus_endgame,
		"check_penalty_endgame": check_penalty_endgame,
		"territory_occupy_bonus": territory_occupy_bonus,
		"territory_enemy_penalty": territory_enemy_penalty,
		"territory_attack_control": territory_attack_control,
		"wall_front_bonus_1": wall_front_bonus_1,
		"wall_front_bonus_2": wall_front_bonus_2,
		"wall_block_ray_bonus": wall_block_ray_bonus
	}

	if pst != null and pst.has_method("to_dict"):
		data["pst"] = pst.to_dict()

	return data


# Dictionaryからパラメータを読み込む
func load_from_dict(data: Dictionary) -> void:
	if data.has("piece_values") and data["piece_values"] is Dictionary:
		for k in data["piece_values"]:
			var base_val: float = float(BASE_PIECE_VALUES.get(k, 20.0))
			var read_val: float = float(data["piece_values"][k])
			# 読み込み時も安全のためアンカー範囲（0.6〜1.4倍）に収める
			if k != "王":
				piece_values[k] = clampf(read_val, base_val * 0.6, base_val * 1.4)
			else:
				piece_values[k] = read_val

	for prop in WEIGHT_RANGES:
		if data.has(prop):
			var range_vec: Vector2 = WEIGHT_RANGES[prop]
			set(prop, clampf(float(data[prop]), range_vec.x, range_vec.y))

	if data.has("pst") and data["pst"] is Dictionary:
		if pst == null:
			pst = PieceSquareTables.new()
		pst.load_from_dict(data["pst"])
