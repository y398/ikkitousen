# ==================================================
# ファイル名: EvalWeights.gd
# 概要: 盤面評価関数の各種重みパラメータを保持し調整・保存・変異を行うクラスである
# ==================================================

extends RefCounted
class_name EvalWeights

# 駒の基礎価値スコア
var piece_values: Dictionary = {
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

# 通常フェーズ（序盤・中盤）の要素別ウェイト
var w_material_normal: float = 1.0
var w_pressure_normal: float = 1.1
var w_safety_normal: float = 0.7
var w_territory_normal: float = 0.6
var w_frontline_normal: float = 0.8
var w_resource_normal: float = 0.5
var w_territory_income_normal: float = 1.0
var w_wall_normal: float = 0.8

# 終盤フェーズの要素別ウェイト
var w_material_endgame: float = 0.7
var w_pressure_endgame: float = 2.2
var w_safety_endgame: float = 1.4
var w_territory_endgame: float = 0.3
var w_frontline_endgame: float = 0.4
var w_resource_endgame: float = 0.2
var w_territory_income_endgame: float = 0.3
var w_wall_endgame: float = 1.2

# 王手状態ボーナスおよびペナルティ
var check_bonus_normal: float = 280.0
var check_penalty_normal: float = 350.0
var check_bonus_endgame: float = 450.0
var check_penalty_endgame: float = 500.0

# 領地マス（2五・8五）のインカム評価
var territory_occupy_bonus: float = 45.0
var territory_enemy_penalty: float = 50.0
var territory_attack_control: float = 14.0

# 壁による王の防壁および大駒射線遮断
var wall_front_bonus_1: float = 32.0
var wall_front_bonus_2: float = 20.0
var wall_block_ray_bonus: float = 28.0


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

	return copy


# パラメータに微小変化（変異）を加えた新しい重みインスタンスを生成する（進化学習用）
func mutate(mutation_rate: float = 0.25, mutation_scale: float = 0.2) -> RefCounted:
	var mutant = clone()

	# 駒価値の変異（王以外）
	for piece_name in mutant.piece_values:
		if piece_name == "王":
			continue
		if randf() < mutation_rate:
			var current_val: float = mutant.piece_values[piece_name]
			var delta: float = current_val * randf_range(-mutation_scale, mutation_scale)
			mutant.piece_values[piece_name] = maxf(1.0, current_val + delta)

	# 各重みパラメータの変異
	var weight_props := [
		"w_material_normal", "w_pressure_normal", "w_safety_normal", "w_territory_normal",
		"w_frontline_normal", "w_resource_normal", "w_territory_income_normal", "w_wall_normal",
		"w_material_endgame", "w_pressure_endgame", "w_safety_endgame", "w_territory_endgame",
		"w_frontline_endgame", "w_resource_endgame", "w_territory_income_endgame", "w_wall_endgame",
		"check_bonus_normal", "check_penalty_normal", "check_bonus_endgame", "check_penalty_endgame",
		"territory_occupy_bonus", "territory_enemy_penalty", "territory_attack_control",
		"wall_front_bonus_1", "wall_front_bonus_2", "wall_block_ray_bonus"
	]

	for prop in weight_props:
		if randf() < mutation_rate:
			var current_val: float = mutant.get(prop)
			var delta: float = current_val * randf_range(-mutation_scale, mutation_scale)
			mutant.set(prop, maxf(0.05, current_val + delta))

	return mutant


# パラメータをDictionary形式で取得する（JSON保存用）
func to_dict() -> Dictionary:
	return {
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


# Dictionaryからパラメータを読み込む
func load_from_dict(data: Dictionary) -> void:
	if data.has("piece_values") and data["piece_values"] is Dictionary:
		for k in data["piece_values"]:
			piece_values[k] = float(data["piece_values"][k])

	for prop in [
		"w_material_normal", "w_pressure_normal", "w_safety_normal", "w_territory_normal",
		"w_frontline_normal", "w_resource_normal", "w_territory_income_normal", "w_wall_normal",
		"w_material_endgame", "w_pressure_endgame", "w_safety_endgame", "w_territory_endgame",
		"w_frontline_endgame", "w_resource_endgame", "w_territory_income_endgame", "w_wall_endgame",
		"check_bonus_normal", "check_penalty_normal", "check_bonus_endgame", "check_penalty_endgame",
		"territory_occupy_bonus", "territory_enemy_penalty", "territory_attack_control",
		"wall_front_bonus_1", "wall_front_bonus_2", "wall_block_ray_bonus"
	]:
		if data.has(prop):
			set(prop, float(data[prop]))
