extends RefCounted

const SAVE_PATH := "user://deck_save.json"
const FORMAT_VERSION := 3
const CardDatabase = preload("res://scripts/core/CardDatabase.gd")
const DeckRules = preload("res://scripts/core/DeckRules.gd")

# 保存ファイルがまだない場合に使用する、対局可能な初期デッキを2組用意する。
# デッキ構築画面から編集・保存すれば、通常の保存デッキとして扱われる。
static func _default_main_deck_one() -> Array:
	var cards: Array = []
	for _i in range(6):
		cards.append("歩")
	for card_name in ["香", "桂", "竹束", "落とし穴", "銀", "金", "弓手"]:
		cards.append(card_name)
		cards.append(card_name)
	return cards

static func _default_main_deck_two() -> Array:
	var cards: Array = []
	for _i in range(6):
		cards.append("歩")
	for card_name in ["香", "桂", "馬防柵", "落とし穴", "竹束", "弓手", "伏兵"]:
		cards.append(card_name)
		cards.append(card_name)
	return cards

static func default_decks() -> Dictionary:
	return {
		"deck_1": {
			"name": "デッキ1",
			"main_deck": _default_main_deck_one(),
			"promotion_deck": ["と金", "と銀", "成香", "成桂", "成弓"]
		},
		"deck_2": {
			"name": "デッキ2",
			"main_deck": _default_main_deck_two(),
			"promotion_deck": ["と金", "成香", "成桂", "馬", "龍"]
		}
	}

static func ordered_deck_ids(decks: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	for raw_id in decks.keys():
		ids.append(str(raw_id))
	ids.sort()
	return ids

static func load_library() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {
			"valid": true,
			"decks": default_decks(),
			"last_selected_deck_id": "deck_1",
			"message": "保存データがないため、初期デッキ2組を用意しました。",
			"using_defaults": true
		}

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return _load_failed("保存データを開けません（エラーコード：%d）。" % FileAccess.get_open_error())
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		return _load_failed("保存データを読み取れません。JSON形式を確認してください。")

	var save_data: Dictionary = parsed
	var version := int(save_data.get("format_version", -1))
	if version == 1:
		var legacy_profile_result := _normalize_profile(save_data, "デッキ1")
		if not bool(legacy_profile_result.get("valid", false)):
			return _load_failed("旧形式のデッキを読み込めません：%s" % str(legacy_profile_result.get("error", "")))
		var legacy_profile: Dictionary = legacy_profile_result["profile"]
		return {
			"valid": true,
			"decks": {
				"deck_1": legacy_profile,
				"deck_2": _copy_profile(legacy_profile, "デッキ2")
			},
			"last_selected_deck_id": "deck_1",
			"message": "旧形式のデッキをデッキ1・デッキ2に複製して読み込みました。",
			"using_defaults": false
		}

	if version == 2:
		var raw_profiles: Variant = save_data.get("profiles", null)
		if not (raw_profiles is Dictionary):
			return _load_failed("旧形式の保存データに profiles がありません。")
		var main_result := _normalize_profile(raw_profiles.get("main", null), "デッキ1")
		var sub_result := _normalize_profile(raw_profiles.get("sub", null), "デッキ2")
		if not bool(main_result.get("valid", false)):
			return _load_failed("旧メイン用デッキを読み込めません：%s" % str(main_result.get("error", "")))
		if not bool(sub_result.get("valid", false)):
			return _load_failed("旧サブ用デッキを読み込めません：%s" % str(sub_result.get("error", "")))
		return {
			"valid": true,
			"decks": {"deck_1": main_result["profile"], "deck_2": sub_result["profile"]},
			"last_selected_deck_id": "deck_1",
			"message": "旧形式の先手用・後手用デッキをデッキ1・デッキ2として読み込みました。",
			"using_defaults": false
		}

	if version != FORMAT_VERSION:
		return _load_failed("保存データの形式バージョンが対応していません（%d）。" % version)

	var raw_decks: Variant = save_data.get("decks", null)
	if not (raw_decks is Dictionary):
		return _load_failed("保存データに decks がありません。")

	var loaded_decks: Dictionary = {}
	for raw_id in raw_decks.keys():
		var deck_id := str(raw_id)
		var raw_profile: Variant = raw_decks[raw_id]
		var raw_name := "デッキ"
		if raw_profile is Dictionary:
			raw_name = str(raw_profile.get("name", deck_id))
		var result := _normalize_profile(raw_profile, raw_name)
		if not bool(result.get("valid", false)):
			return _load_failed("%sを読み込めません：%s" % [raw_name, str(result.get("error", ""))])
		loaded_decks[deck_id] = result["profile"]

	if loaded_decks.is_empty():
		return _load_failed("保存データにデッキが1つもありません。")
	if loaded_decks.size() == 1:
		var first_id := str(loaded_decks.keys()[0])
		var new_id := "deck_1"
		var counter := 1
		while loaded_decks.has(new_id):
			counter += 1
			new_id = "deck_%d" % counter
		loaded_decks[new_id] = _copy_profile(loaded_decks[first_id], "デッキ%d" % counter)

	var last_id := str(save_data.get("last_selected_deck_id", "deck_1"))
	if not loaded_decks.has(last_id):
		last_id = ordered_deck_ids(loaded_decks)[0]
	return {
		"valid": true,
		"decks": loaded_decks,
		"last_selected_deck_id": last_id,
		"message": "保存デッキを読み込みました。",
		"using_defaults": false
	}

static func _load_failed(message: String) -> Dictionary:
	return {
		"valid": false,
		"decks": default_decks(),
		"last_selected_deck_id": "deck_1",
		"message": message + " 初期デッキ2組を表示します。",
		"using_defaults": true
	}

static func _copy_profile(profile: Dictionary, new_name: String) -> Dictionary:
	var main_cards: Array = profile.get("main_deck", [])
	var promotion_cards: Array = profile.get("promotion_deck", [])
	return {
		"name": new_name,
		"main_deck": main_cards.duplicate(true),
		"promotion_deck": promotion_cards.duplicate(true)
	}

static func _normalize_profile(raw_profile: Variant, fallback_name: String) -> Dictionary:
	if not (raw_profile is Dictionary):
		return {"valid": false, "error": "デッキデータが辞書形式ではありません。"}
	var main_result := _normalize_card_array(raw_profile.get("main_deck", null), ["兵", "壁", "罠"], 20, "メインデッキ")
	if not bool(main_result.get("valid", false)):
		return {"valid": false, "error": str(main_result.get("error", ""))}
	var promotion_result := _normalize_card_array(raw_profile.get("promotion_deck", null), ["成"], 5, "成デッキ")
	if not bool(promotion_result.get("valid", false)):
		return {"valid": false, "error": str(promotion_result.get("error", ""))}
	var name := str(raw_profile.get("name", fallback_name)).strip_edges()
	if name.is_empty():
		name = fallback_name
	return {
		"valid": true,
		"profile": {
			"name": name,
			"main_deck": main_result["cards"],
			"promotion_deck": promotion_result["cards"]
		}
	}

static func _normalize_card_array(raw_cards: Variant, allowed_categories: Array, max_cards: int, deck_label: String) -> Dictionary:
	if not (raw_cards is Array):
		return {"valid": false, "error": "%sのカード一覧が配列ではありません。" % deck_label}
	if raw_cards.size() > max_cards:
		return {"valid": false, "error": "%sが上限の%d枚を超えています。" % [deck_label, max_cards]}
	var cards: Array[String] = []
	var counts: Dictionary = {}
	for raw_name in raw_cards:
		if typeof(raw_name) != TYPE_STRING:
			return {"valid": false, "error": "%sのカード名が文字列ではありません。" % deck_label}
		var card_name := str(raw_name)
		var card: Dictionary = CardDatabase.get_card(card_name)
		if card.is_empty():
			return {"valid": false, "error": "カードデータが見つかりません：%s" % card_name}
		if not allowed_categories.has(str(card.get("category", ""))):
			return {"valid": false, "error": "%sに入れられないカードです：%s" % [deck_label, card_name]}
		counts[card_name] = int(counts.get(card_name, 0)) + 1
		var max_copies := int(card.get("max_copies", 2))
		if max_copies >= 0 and int(counts[card_name]) > max_copies:
			return {"valid": false, "error": "同名カードの上限を超えています：%s" % card_name}
		cards.append(card_name)
	return {"valid": true, "cards": cards, "error": ""}

static func save_library(decks: Dictionary, last_selected_deck_id: String) -> Dictionary:
	if decks.size() < 2:
		return {"ok": false, "error": "デッキは最低2組必要です。"}
	var clean_decks: Dictionary = {}
	for raw_id in decks.keys():
		var deck_id := str(raw_id)
		var raw_profile: Variant = decks[raw_id]
		var fallback_name := deck_id
		if raw_profile is Dictionary:
			fallback_name = str(raw_profile.get("name", deck_id))
		var result := _normalize_profile(raw_profile, fallback_name)
		if not bool(result.get("valid", false)):
			return {"ok": false, "error": "%sを保存できません：%s" % [fallback_name, str(result.get("error", ""))]}
		clean_decks[deck_id] = result["profile"]
	if not clean_decks.has(last_selected_deck_id):
		last_selected_deck_id = ordered_deck_ids(clean_decks)[0]
	var save_data := {
		"format_version": FORMAT_VERSION,
		"last_selected_deck_id": last_selected_deck_id,
		"decks": clean_decks
	}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "保存ファイルを開けません（エラーコード：%d）。" % FileAccess.get_open_error()}
	file.store_string(JSON.stringify(save_data, "\t"))
	file.close()
	return {"ok": true, "error": ""}

static func validate_playable_profile(profile: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var main_cards: Array = profile.get("main_deck", [])
	var promotion_cards: Array = profile.get("promotion_deck", [])
	var main_result: Dictionary = DeckRules.validate_main_deck(main_cards)
	var promotion_result: Dictionary = DeckRules.validate_promotion_deck(promotion_cards)
	for error_message in main_result.get("errors", []):
		errors.append(str(error_message))
	for error_message in promotion_result.get("errors", []):
		errors.append(str(error_message))
	return {"valid": errors.is_empty(), "errors": errors}
