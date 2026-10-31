extends RefCounted

const CardDataResource = preload("res://scripts/core/CardData.gd")

# カードの基本情報とデッキ構築ルールを一元管理する。
# max_copies: -1 は同名カードの枚数制限なしを表す。
const CARD_DATA: Dictionary = {
	"歩": {
		"category": "兵",
		"sort_order": 10,
		"cost": 1,
		"deckcost": 0,
		"max_copies": -1,
		"movement_type": "pawn",
		"can_move_forward": true,
		"can_move_backward": false,
		"is_sliding": false,
		"promotion_card": "と金",
		"promotion_cards": ["と金", "と銀"]
	},
	"香": {
		"category": "兵",
		"sort_order": 20,
		"cost": 2,
		"deckcost": 1,
		"max_copies": 2,
		"movement_type": "lance",
		"can_move_forward": true,
		"can_move_backward": false,
		"is_sliding": true,
		"promotion_card": "成香"
	},
	"桂": {
		"category": "兵",
		"sort_order": 30,
		"cost": 2,
		"deckcost": 1,
		"max_copies": 2,
		"movement_type": "knight",
		"can_move_forward": true,
		"can_move_backward": false,
		"is_sliding": false,
		"promotion_card": "成桂"
	},
	"銀": {
		"category": "兵",
		"sort_order": 40,
		"cost": 3,
		"deckcost": 2,
		"max_copies": 2,
		"movement_type": "silver",
		"can_move_forward": true,
		"can_move_backward": true,
		"is_sliding": false
	},
	"金": {
		"category": "兵",
		"sort_order": 50,
		"cost": 3,
		"deckcost": 2,
		"max_copies": 2,
		"movement_type": "gold",
		"can_move_forward": true,
		"can_move_backward": true,
		"is_sliding": false
	},
	"角": {
		"category": "兵",
		"sort_order": 60,
		"cost": 4,
		"deckcost": 3,
		"max_copies": 2,
		"movement_type": "bishop",
		"can_move_forward": true,
		"can_move_backward": true,
		"is_sliding": true,
		"promotion_card": "馬"
	},
	"飛": {
		"category": "兵",
		"sort_order": 70,
		"cost": 4,
		"deckcost": 3,
		"max_copies": 2,
		"movement_type": "rook",
		"can_move_forward": true,
		"can_move_backward": true,
		"is_sliding": true,
		"promotion_card": "龍"
	},
	"旗本": {
		"category": "兵",
		"sort_order": 80,
		"cost": 2,
		"deckcost": 1,
		"max_copies": 2,
		"movement_type": "hatamoto",
		"can_move_forward": true,
		"can_move_backward": true,
		"is_sliding": false,
		"on_summon_effect": "reveal_top_card",
		"effect_text": "場に出た時、デッキの一番上を確認し兵なら手札に加え、それ以外なら元に戻す",
		"image_path": "res://assets/cards/旗本2.png"
	},
	"弓手": {
		"category": "兵",
		"sort_order": 90,
		"cost": 2,
		"deckcost": 2,
		"max_copies": 2,
		"movement_type": "archer",
		"can_move_forward": true,
		"can_move_backward": false,
		"is_sliding": false,
		"promotion_card": "成弓",
		"attack_cost": 1,
		"effect_text": "攻撃コスト1：該当マスの敵を討ち取る。",
		"image_path": "res://assets/cards/弓手.png"
	},

	# 壁：竹束
	"竹束": {
		"category": "壁",
		"sort_order": 110,
		"cost": 1,
		"deckcost": 1,
		"max_copies": 2,
		"movement_type": "none",
		"can_move_forward": false,
		"can_move_backward": false,
		"is_sliding": false,
		"wall_length": 1,
		"destroy_cost": 1,
		"blocks_knight": false
	},
	# 壁：馬防柵
	"馬防柵": {
		"category": "壁",
		"sort_order": 120,
		"cost": 3,
		"deckcost": 2,
		"max_copies": 2,
		"movement_type": "none",
		"can_move_forward": false,
		"can_move_backward": false,
		"is_sliding": false,
		"wall_length": 2,
		"destroy_cost": 3,
		"blocks_knight": true
	},
	"落とし穴": {
		"category": "罠",
		"sort_order": 130,
		"cost": 2,
		"deckcost": 1,
		"max_copies": 2,
		"movement_type": "none",
		"can_move_forward": false,
		"can_move_backward": false,
		"is_sliding": false,
		"trap_effect": "destroy_soldier"
	},
	"伏兵": {
		"category": "罠",
		"sort_order": 131,
		"cost": 2,
		"deckcost": 2,
		"max_copies": 2,
		"movement_type": "none",
		"can_move_forward": false,
		"can_move_backward": false,
		"is_sliding": false,
		"activation_cost": 1,
		"trap_effect": "ambush_three_squares",
		"effect_text": "起動コスト1：発動時、該当マスの敵駒を墓地に送ることができる",
		"image_path": "res://assets/cards/伏兵.png"
	},
	"石落とし": {
		"category": "罠",
		"sort_order": 132,
		"cost": 2,
		"deckcost": 2,
		"max_copies": 2,
		"movement_type": "none",
		"can_move_forward": false,
		"can_move_backward": false,
		"is_sliding": false,
		"activation_cost": 1,
		"trap_effect": "stone_drop_front_two",
		"effect_text": "起動コスト1：発動時、該当マスの壁を挟まずに最も手前にいる敵駒を墓地に送る。",
		"image_path": "res://assets/cards/石落し.png"
	},
	"特殊": {
		"category": "特殊",
		"sort_order": 140,
		"cost": 0,
		"deckcost": 0,
		"max_copies": 2,
		"movement_type": "none",
		"can_move_forward": false,
		"can_move_backward": false,
		"is_sliding": false
	},

	# 成カード
	"と金": {
		"category": "成",
		"sort_order": 210,
		"cost": 0,
		"deckcost": 0,
		"max_copies": 2,
		"movement_type": "gold",
		"wall_length": 1,
		"destroy_cost": 0,
		"blocks_knight": false,
		"promotes_from": "歩"
	},
	"と銀": {
		"category": "成",
		"sort_order": 215,
		"cost": 0,
		"deckcost": 0,
		"max_copies": 2,
		"movement_type": "silver",
		"wall_length": 1,
		"destroy_cost": 0,
		"blocks_knight": false,
		"promotes_from": "歩"
	},
	"成香": {
		"category": "成",
		"sort_order": 220,
		"cost": 0,
		"deckcost": 0,
		"max_copies": 2,
		"movement_type": "gold",
		"wall_length": 1,
		"destroy_cost": 0,
		"blocks_knight": false,
		"promotes_from": "香"
	},
	"成桂": {
		"category": "成",
		"sort_order": 230,
		"cost": 0,
		"deckcost": 0,
		"max_copies": 2,
		"movement_type": "gold",
		"wall_length": 1,
		"destroy_cost": 0,
		"blocks_knight": false,
		"promotes_from": "桂"
	},
	"成銀": {
		"category": "成",
		"sort_order": 240,
		"cost": 0,
		"deckcost": 0,
		"max_copies": 2,
		"movement_type": "gold",
		"wall_length": 1,
		"destroy_cost": 0,
		"blocks_knight": false,
		"promotes_from": "銀"
	},
	"成弓": {
		"category": "成",
		"sort_order": 250,
		"cost": 0,
		"deckcost": 0,
		"max_copies": 2,
		"movement_type": "promoted_archer",
		"wall_length": 1,
		"destroy_cost": 0,
		"blocks_knight": false,
		"attack_cost": 1,
		"effect_text": "攻撃コスト1：正面2マス先の敵駒を討ち取る。",
		"promotes_from": "弓手"
	},
	"馬": {
		"category": "成",
		"sort_order": 260,
		"cost": 0,
		"deckcost": 0,
		"max_copies": 2,
		"movement_type": "horse",
		"wall_length": 1,
		"destroy_cost": 0,
		"blocks_knight": false,
		"promotes_from": "角"
	},
	"龍": {
		"category": "成",
		"sort_order": 270,
		"cost": 0,
		"deckcost": 0,
		"max_copies": 2,
		"movement_type": "dragon",
		"wall_length": 1,
		"destroy_cost": 0,
		"blocks_knight": false,
		"promotes_from": "飛"
	}
}


# 指定したカード名の情報を返す。
static func get_card(card_name: String) -> Dictionary:
	if not CARD_DATA.has(card_name):
		return {}

	var definition: Dictionary = CARD_DATA[card_name]
	var card_data = CardDataResource.new()
	card_data.card_name = card_name
	card_data.category = str(definition.get("category", ""))
	card_data.cost = int(definition.get("cost", 0))
	card_data.deckcost = int(definition.get("deckcost", 0))
	card_data.sort_order = int(definition.get("sort_order", 9999))
	card_data.max_copies = int(definition.get("max_copies", 2))
	card_data.movement_type = str(definition.get("movement_type", "none"))
	card_data.can_move_forward = bool(definition.get("can_move_forward", true))
	card_data.can_move_backward = bool(definition.get("can_move_backward", true))
	card_data.is_sliding = bool(definition.get("is_sliding", false))
	card_data.wall_length = int(definition.get("wall_length", 1))
	card_data.destroy_cost = int(definition.get("destroy_cost", 0))
	card_data.blocks_knight = bool(definition.get("blocks_knight", false))
	card_data.activation_cost = int(definition.get("activation_cost", 0))
	card_data.attack_cost = int(definition.get("attack_cost", 0))
	card_data.trap_effect = str(definition.get("trap_effect", ""))
	card_data.on_summon_effect = str(definition.get("on_summon_effect", ""))
	card_data.effect_text = str(definition.get("effect_text", ""))
	card_data.promotion_card = str(definition.get("promotion_card", ""))
	var promotion_cards: Array[String] = []
	var raw_promotion_cards: Variant = definition.get("promotion_cards", [])
	if raw_promotion_cards is Array:
		for raw_promotion_name in raw_promotion_cards:
			promotion_cards.append(str(raw_promotion_name))
	if promotion_cards.is_empty() and not card_data.promotion_card.is_empty():
		promotion_cards.append(card_data.promotion_card)
	card_data.promotion_cards = promotion_cards
	card_data.promotes_from = str(definition.get("promotes_from", ""))
	card_data.image_path = get_card_image_path(card_name)

	return {
		"name": card_data.card_name,
		"image_path": card_data.image_path,
		"category": card_data.category,
		"sort_order": card_data.sort_order,
		"cost": card_data.cost,
		"deckcost": card_data.deckcost,
		"max_copies": card_data.max_copies,
		"activation_cost": card_data.activation_cost,
		"attack_cost": card_data.attack_cost,
		"on_summon_effect": card_data.on_summon_effect,
		"effect_text": card_data.effect_text,
		"movement_type": card_data.movement_type,
		"can_move_forward": card_data.can_move_forward,
		"can_move_backward": card_data.can_move_backward,
		"is_sliding": card_data.is_sliding,
		"wall_length": card_data.wall_length,
		"destroy_cost": card_data.destroy_cost,
		"blocks_knight": card_data.blocks_knight,
		"trap_effect": card_data.trap_effect,
		"promotion_card": card_data.promotion_card,
		"promotion_cards": card_data.promotion_cards.duplicate(),
		"promotes_from": card_data.promotes_from
	}


# エクスポート時の文字化けトラブルを防ぐための英数画像名対応表である
const CARD_IMAGE_SLUGS: Dictionary = {
	"歩": "pawn",
	"香": "lance",
	"桂": "knight",
	"銀": "silver",
	"金": "gold",
	"角": "bishop",
	"飛": "rook",
	"旗本": "hatamoto2",
	"弓手": "archer",
	"竹束": "bamboo_bundle",
	"馬防柵": "horse_barricade",
	"落とし穴": "pitfall",
	"伏兵": "ambush",
	"石落とし": "stone_drop",
	"と金": "tokin",
	"と銀": "tosilver",
	"成香": "narikyou",
	"成桂": "narikei",
	"成銀": "narigin",
	"成弓": "nariarcher",
	"馬": "horse",
	"龍": "dragon"
}


# 英数ファイル名を最優先で探し、無ければ明示指定パスや日本語ファイル名にフォールバックする
static func get_card_image_path(card_name: String) -> String:
	if not CARD_DATA.has(card_name):
		return ""
	var definition: Dictionary = CARD_DATA[card_name]
	var candidates: Array[String] = []

	# 1. 英数スラグ名の画像ファイルを最優先で候補に追加する
	if CARD_IMAGE_SLUGS.has(card_name):
		var slug: String = str(CARD_IMAGE_SLUGS[card_name])
		for extension in ["png", "webp", "jpg", "jpeg"]:
			candidates.append("res://assets/cards/%s.%s" % [slug, extension])

	# 2. 定義内の明示指定パスを追加する
	var explicit_path := str(definition.get("image_path", "")).strip_edges()
	if not explicit_path.is_empty():
		candidates.append(explicit_path)

	# 3. 日本語カード名のファイル名もフォールバックとして検索する
	for extension in ["png", "webp", "jpg", "jpeg"]:
		candidates.append("res://assets/cards/%s.%s" % [card_name, extension])

	for image_path in candidates:
		if ResourceLoader.exists(image_path):
			return image_path
	return ""


# 指定したカード種別のカード名を sort_order の昇順で返す。
# 同じ sort_order のカードは名前順に並ぶ。
static func get_card_names_for_categories(categories: Array) -> Array[String]:
	var result: Array[String] = []
	for raw_name in CARD_DATA.keys():
		var card_name := str(raw_name)
		var definition: Dictionary = CARD_DATA[card_name]
		if categories.has(str(definition.get("category", ""))):
			result.append(card_name)

	result.sort_custom(func(a: String, b: String) -> bool:
		var a_order := int(CARD_DATA[a].get("sort_order", 9999))
		var b_order := int(CARD_DATA[b].get("sort_order", 9999))
		if a_order == b_order:
			return a < b
		return a_order < b_order
	)
	return result
