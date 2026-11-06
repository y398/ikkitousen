# ==================================================
# ファイル名: CardCounter.gd
# 概要: 公開情報から相手の使用済みカードを追跡し未公開カードと次手コストを推論するクラスである
# ==================================================

extends RefCounted

const CardDatabase = preload("res://scripts/core/CardDatabase.gd")

# 標準的な各カードのデッキ内想定上限数
const ESTIMATED_MAX_COPIES: Dictionary = {
	"歩": 3,
	"香": 2,
	"桂": 2,
	"銀": 2,
	"金": 2,
	"角": 2,
	"飛": 2,
	"弓手": 2,
	"旗本": 1,
	"竹束": 2,
	"陣幕": 1,
	"馬防柵": 2,
	"落とし穴": 2,
	"伏兵": 1,
	"石落とし": 1
}

# 追跡対象のプレイヤーID
var target_player: int = -1

# 相手の使用済み（公開された）カードのカウント
var played_cards: Dictionary = {}

# 墓地に送られたカード
var graveyard_cards: Array[String] = []


func _init(player_id: int) -> void:
	target_player = player_id
	played_cards.clear()
	graveyard_cards.clear()


# カードが盤面に召喚・発動された際に記録する
func record_card_played(card_name: String) -> void:
	if card_name.is_empty():
		return
	played_cards[card_name] = int(played_cards.get(card_name, 0)) + 1


# カードが墓地に送られた・破棄された際に記録する
func record_card_discarded_or_destroyed(card_name: String) -> void:
	if card_name.is_empty():
		return
	graveyard_cards.append(card_name)


# 相手の次ターン最大使用可能コストを計算する
# 基本回復（先手2〜3、後手3）+ 現在の備蓄（最大3）
func calculate_opponent_next_turn_max_cost(
	current_turn_count: int,
	target_player_reserves: int
) -> int:
	var base_recovery := 2
	if target_player == 0:
		base_recovery = 2 if current_turn_count <= 2 else 3
	else:
		base_recovery = 3
	return base_recovery + mini(target_player_reserves, 3)


# 特定のカードが相手の未公開プール（手札または山札）に残っている可能性があるか判定する
func is_card_still_available(card_name: String) -> bool:
	var max_copies: int = int(ESTIMATED_MAX_COPIES.get(card_name, 2))
	var played: int = int(played_cards.get(card_name, 0))
	return played < max_copies


# 相手の山札・手札に残存していると推測される脅威カード（大駒・攻撃駒）の残数を算出する
func get_remaining_threat_estimate() -> Dictionary:
	var result: Dictionary = {}
	for card_name in ["飛", "角", "金", "銀", "落とし穴", "伏兵"]:
		var max_copies: int = int(ESTIMATED_MAX_COPIES.get(card_name, 2))
		var played: int = int(played_cards.get(card_name, 0))
		var rem: int = maxi(0, max_copies - played)
		result[card_name] = rem
	return result

