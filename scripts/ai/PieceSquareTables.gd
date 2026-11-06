# ==================================================
# ファイル名: PieceSquareTables.gd
# 概要: 駒種ごとの盤面9×9マス配置適性評価テーブル（PST）を管理し左右対称性・先後相対化・過学習防止クリップを提供するクラスである
# ==================================================

extends RefCounted
class_name PieceSquareTables

# 各駒種の配置ボーナス上限値（過学習・パラメータ発散防止用）
const CLIP_LIMITS: Dictionary = {
	"歩": 8.0,
	"と金": 12.0,
	"香": 12.0,
	"成香": 12.0,
	"桂": 12.0,
	"成桂": 12.0,
	"銀": 14.0,
	"成銀": 12.0,
	"金": 14.0,
	"角": 20.0,
	"馬": 20.0,
	"飛": 20.0,
	"龍": 20.0,
	"弓手": 16.0,
	"成弓": 16.0,
	"旗本": 14.0,
	"王": 25.0,
	"竹束": 10.0,
	"陣幕": 10.0,
	"馬防柵": 12.0,
	"落とし穴": 12.0,
	"伏兵": 14.0,
	"石落とし": 12.0,
	"石落し": 12.0
}

# 駒ごとのテーブルデータ（各駒 9段 × 5筋: 1〜5筋を保持し左右対称展開する）
# tables[piece_name][rank_idx][file_idx] (rank: 0..8, file: 0..4: 1筋〜5筋)
var tables: Dictionary = {}


func _init() -> void:
	_init_default_tables()


# 初期テーブルの構築（主要な駒に自然な基礎配置傾向を初期値として設定する）
func _init_default_tables() -> void:
	tables.clear()
	for p_name in CLIP_LIMITS:
		var grid: Array = []
		for _r in range(9):
			var row: Array = []
			for _f in range(5):
				row.append(0.0)
			grid.append(row)
		tables[p_name] = grid

	# 歩: 中央寄り・前進を緩やかに評価
	for r in range(1, 8):
		for f in range(5):
			var center_bonus: float = float(f) * 0.4 # 5筋（index 4）に近いほど高い
			var adv_bonus: float = float(8 - r) * 0.4
			tables["歩"][r][f] = clampf(center_bonus + adv_bonus, -8.0, 8.0)

	# 金・銀: 中央進出および敵陣接近を評価
	for r in range(0, 9):
		for f in range(5):
			var score: float = float(f) * 0.6 + float(8 - r) * 0.5
			tables["金"][r][f] = clampf(score, -14.0, 14.0)
			tables["銀"][r][f] = clampf(score, -14.0, 14.0)

	# 弓手: 3〜5段目の射撃ポジション・領地マス周辺を好む
	for r in range(2, 6):
		for f in range(5):
			tables["弓手"][r][f] = clampf(float(f) * 0.8 + 2.0, -16.0, 16.0)

	# 壁: 自軍王の前方（7〜8段目）を好む
	for r in range(6, 9):
		for f in range(5):
			tables["竹束"][r][f] = clampf(float(r - 5) * 1.5, -10.0, 10.0)
			tables["陣幕"][r][f] = clampf(float(r - 5) * 1.5, -10.0, 10.0)
			tables["馬防柵"][r][f] = clampf(float(r - 5) * 1.8, -12.0, 12.0)


# 指定マスの配置評価スコアを取得する（左右対称性・先後相対段数を自動適用）
func get_score(piece_name: String, sq: Vector2i, owner: int) -> float:
	if not tables.has(piece_name):
		return 0.0

	var rank: int = sq.x
	var file: int = sq.y
	if rank < 1 or rank > 9 or file < 1 or file > 9:
		return 0.0

	# 先後相対化（先手は下段9段目が自陣奥、後手は上段1段目が自陣奥）
	var rel_rank: int = rank if owner == 0 else (10 - rank)
	var r_idx: int = clampi(rel_rank - 1, 0, 8)

	# 左右対称性（1筋と9筋、2筋と8筋、3筋と7筋、4筋と6筋で同じ値を共有）
	var sym_file: int = mini(file, 10 - file)
	var f_idx: int = clampi(sym_file - 1, 0, 4)

	return float(tables[piece_name][r_idx][f_idx])


# ディープコピーを作成する
func clone() -> RefCounted:
	var copy = (get_script() as GDScript).new()
	copy.tables.clear()
	for p_name in tables:
		var grid: Array = []
		for r in range(9):
			var row: Array = []
			for f in range(5):
				row.append(float(tables[p_name][r][f]))
			grid.append(row)
		copy.tables[p_name] = grid
	return copy


# テーブルに変異を加えた新しいインスタンスを生成する（過学習防止クリップ適用）
func mutate(mutation_rate: float = 0.2, mutation_step: float = 1.0) -> RefCounted:
	var mutant = clone()

	for p_name in mutant.tables:
		var clip_val: float = float(CLIP_LIMITS.get(p_name, 12.0))
		var grid: Array = mutant.tables[p_name]

		for r in range(9):
			for f in range(5):
				if randf() < mutation_rate:
					var delta: float = randf_range(-mutation_step, mutation_step)
					var new_val: float = clampf(float(grid[r][f]) + delta, -clip_val, clip_val)
					grid[r][f] = new_val

	return mutant


# Dictionary形式で取得する（JSON保存用）
func to_dict() -> Dictionary:
	return {
		"tables": tables
	}


# Dictionaryから読み込む
func load_from_dict(data: Dictionary) -> void:
	if not data.has("tables") or not (data["tables"] is Dictionary):
		return

	var raw_tables: Dictionary = data["tables"]
	for p_name in raw_tables:
		var raw_grid = raw_tables[p_name]
		if not (raw_grid is Array) or raw_grid.size() != 9:
			continue

		var clip_val: float = float(CLIP_LIMITS.get(p_name, 12.0))
		var grid: Array = []
		for r in range(9):
			var row: Array = []
			var raw_row = raw_grid[r]
			if raw_row is Array and raw_row.size() == 5:
				for f in range(5):
					row.append(clampf(float(raw_row[f]), -clip_val, clip_val))
			else:
				for _f in range(5):
					row.append(0.0)
			grid.append(row)

		tables[p_name] = grid
