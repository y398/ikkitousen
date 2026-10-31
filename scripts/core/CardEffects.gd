# ==================================================
# ファイル名: CardEffects.gd
# 概要: 旗本などの召喚時効果（山札公開・手札獲得など）の個別処理と結果判定を行うクラスである
# ==================================================

extends RefCounted

# カード固有の効果を、対局状態を直接変更せずに判定する
# 戻り値の action を受けて main.gd 側が山札・手札を更新する
static func resolve_on_summon_effect(effect_id: String, top_card: Dictionary) -> Dictionary:
	match effect_id:
		"reveal_top_card":
			if top_card.is_empty():
				return {
					"action": "none",
					"message": "旗本の効果：山札が空のため、確認できるカードはありません。",
					"public_notice": "旗本公開：山札が空です。"
				}
			var card_name := str(top_card.get("name", "不明"))
			var category := str(top_card.get("category", ""))
			if category == "兵":
				return {
					"action": "take_top_card",
					"message": "旗本の効果：山札の一番上を公開しました。公開カード：%s（兵）。手札に加えます。" % card_name,
					"public_notice": "旗本公開：%s（兵）→手札に加えました" % card_name
				}
			return {
				"action": "leave_top_card",
				"message": "旗本の効果：山札の一番上を公開しました。公開カード：%s（%s）。山札の一番上に戻します。" % [card_name, category],
				"public_notice": "旗本公開：%s（%s）→山札の一番上に戻しました" % [card_name, category]
			}
		_:
			return {"action": "none", "message": "未対応の登場時効果です: " + effect_id, "public_notice": ""}
