# ==================================================
# ファイル名: DeckDropZone.gd
# 概要: デッキ構築画面でカードドラッグ時のドロップ先判定（メインデッキ・成デッキ・カードプール領域）を担当するクラスである
# ==================================================

extends PanelContainer

var deck_builder: Node
var zone_type: String = "deck" # deck / pool
var list_type: String = "main" # main / promotion


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.065, 0.08, 0.12, 0.96)
	style.border_color = Color(0.29, 0.35, 0.44)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 5
	style.content_margin_top = 5
	style.content_margin_right = 5
	style.content_margin_bottom = 5
	add_theme_stylebox_override("panel", style)


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if deck_builder == null:
		return false
	return bool(deck_builder.call("can_accept_card_drop", zone_type, list_type, data))


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if deck_builder != null:
		deck_builder.call("process_card_drop", zone_type, list_type, data)
