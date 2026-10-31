extends Resource
class_name CardData

# 基本情報
@export var card_name: String = ""
@export var category: String = ""
@export var cost: int = 0
@export var deckcost: int = 0
@export var sort_order: int = 9999
@export var max_copies: int = 2

# 移動情報
@export var movement_type: String = ""
@export var can_move_forward: bool = true
@export var can_move_backward: bool = false
@export var is_sliding: bool = false

# 壁情報
@export var wall_length: int = 1
@export var destroy_cost: int = 0
@export var blocks_knight: bool = false

# 効果・画像情報
@export var activation_cost: int = 0
@export var attack_cost: int = 0
@export var trap_effect: String = ""
@export var on_summon_effect: String = ""
@export var effect_text: String = ""
@export var promotion_card: String = ""
@export var promotion_cards: Array[String] = []
@export var promotes_from: String = ""
@export var image_path: String = ""
