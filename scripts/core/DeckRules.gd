# ==================================================
# ファイル名: DeckRules.gd
# 概要: メインデッキ（20枚・デッキコスト20）および成デッキ（5枚）の構築バリデーションルールを判定するクラスである
# ==================================================

extends RefCounted

const CardDatabase = preload("res://scripts/core/CardDatabase.gd")

# メインデッキ：20枚、デッキコスト合計20、兵・壁・罠のみ
static func validate_main_deck(card_names: Array) -> Dictionary:
	var errors: Array[String] = []
	var counts: Dictionary = {}
	var total_deckcost: int = 0

	if card_names.size() != 20:
		errors.append("メインデッキは20枚である必要があります（現在%d枚）。" % card_names.size())

	for raw_name in card_names:
		var card_name := str(raw_name)
		counts[card_name] = int(counts.get(card_name, 0)) + 1
		var card: Dictionary = CardDatabase.get_card(card_name)
		if card.is_empty():
			errors.append("カードデータが見つかりません：%s" % card_name)
			continue
		var category := str(card.get("category", ""))
		if not ["兵", "壁", "罠"].has(category):
			errors.append("メインデッキに入れられないカード種別です：%s（%s）" % [card_name, category])
		total_deckcost += int(card.get("deckcost", 0))

	for raw_name in counts.keys():
		var card_name := str(raw_name)
		var card: Dictionary = CardDatabase.get_card(card_name)
		if card.is_empty():
			continue
		var max_copies := int(card.get("max_copies", 2))
		var actual_copies := int(counts[card_name])
		if max_copies >= 0 and actual_copies > max_copies:
			errors.append("同名カードの上限を超えています：%s（%d枚／上限%d枚）" % [card_name, actual_copies, max_copies])

	if total_deckcost != 20:
		errors.append("メインデッキの合計デッキコストは20である必要があります（現在%d）。" % total_deckcost)

	return {
		"valid": errors.is_empty(),
		"errors": errors,
		"card_count": card_names.size(),
		"total_cost": total_deckcost,
		"total_deckcost": total_deckcost
	}


# 成デッキ：5枚、成カードのみ。同名上限はCardDatabaseを参照する。
static func validate_promotion_deck(card_names: Array) -> Dictionary:
	var errors: Array[String] = []
	var counts: Dictionary = {}

	if card_names.size() != 5:
		errors.append("成デッキは5枚である必要があります（現在%d枚）。" % card_names.size())

	for raw_name in card_names:
		var card_name := str(raw_name)
		counts[card_name] = int(counts.get(card_name, 0)) + 1
		var card: Dictionary = CardDatabase.get_card(card_name)
		if card.is_empty():
			errors.append("カードデータが見つかりません：%s" % card_name)
			continue
		var category := str(card.get("category", ""))
		if category != "成":
			errors.append("成デッキには成カードのみ入れられます：%s（%s）" % [card_name, category])

	for raw_name in counts.keys():
		var card_name := str(raw_name)
		var card: Dictionary = CardDatabase.get_card(card_name)
		if card.is_empty():
			continue
		var max_copies := int(card.get("max_copies", 2))
		var actual_copies := int(counts[card_name])
		if max_copies >= 0 and actual_copies > max_copies:
			errors.append("成デッキの同名カード上限を超えています：%s（%d枚／上限%d枚）" % [card_name, actual_copies, max_copies])

	return {
		"valid": errors.is_empty(),
		"errors": errors,
		"card_count": card_names.size()
	}
