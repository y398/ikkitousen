# ==================================================
# ファイル名: DeckCardTile.gd
# 概要: デッキ構築画面内のカードタイルUI（カード画像・枚数表示・ドラッグ＆ドロップ開始・クリックシグナル）を制御するクラスである
# ==================================================

extends Button

signal clicked(card_name: String, source_zone: String, list_type: String, source_index: int)

var card_name: String = ""
var card_data: Dictionary = {}
var image_texture: Texture2D
var source_zone: String = "pool" # pool / deck
var list_type: String = "main" # main / promotion
var source_index: int = -1
var count_text: String = ""
var tile_size: Vector2 = Vector2(96.0, 134.0)
var _drag_started: bool = false


func setup(
	p_card_name: String,
	p_card_data: Dictionary,
	p_texture: Texture2D,
	p_source_zone: String,
	p_list_type: String,
	p_source_index: int,
	p_count_text: String,
	p_tile_size: Vector2 = Vector2(96.0, 134.0)
) -> void:
	card_name = p_card_name
	card_data = p_card_data.duplicate(true)
	image_texture = p_texture
	source_zone = p_source_zone
	list_type = p_list_type
	source_index = p_source_index
	count_text = p_count_text
	tile_size = p_tile_size
	tooltip_text = _make_tooltip()


func _ready() -> void:
	var badge_height := 16.0 if not count_text.is_empty() else 0.0
	custom_minimum_size = Vector2(tile_size.x + 6.0, tile_size.y + badge_height + 8.0)
	focus_mode = Control.FOCUS_NONE
	text = ""
	clip_contents = true
	add_theme_stylebox_override("normal", _make_style(Color(0.10, 0.13, 0.19), Color(0.33, 0.39, 0.49), 1))
	add_theme_stylebox_override("hover", _make_style(Color(0.15, 0.20, 0.29), Color(0.45, 0.70, 1.0), 2))
	add_theme_stylebox_override("pressed", _make_style(Color(0.23, 0.29, 0.39), Color(1.0, 0.72, 0.20), 2))
	pressed.connect(_on_pressed)
	_build_contents()


func _make_style(background_color: Color, border_color: Color, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background_color
	style.border_color = border_color
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(4)
	style.content_margin_left = 1
	style.content_margin_top = 1
	style.content_margin_right = 1
	style.content_margin_bottom = 1
	return style


func _build_contents() -> void:
	var layout := VBoxContainer.new()
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.offset_left = 3
	layout.offset_top = 3
	layout.offset_right = -3
	layout.offset_bottom = -3
	layout.add_theme_constant_override("separation", 2)
	layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(layout)

	if image_texture != null:
		var picture := TextureRect.new()
		picture.texture = image_texture
		# 元画像の572×800等のサイズを最小サイズとして扱わず、タイル領域に合わせる。
		# これがないと画像の左上だけが拡大表示される場合がある。
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		picture.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		picture.size_flags_vertical = Control.SIZE_EXPAND_FILL
		picture.custom_minimum_size = tile_size
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layout.add_child(picture)
	else:
		var placeholder := PanelContainer.new()
		placeholder.custom_minimum_size = tile_size
		placeholder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		placeholder.size_flags_vertical = Control.SIZE_EXPAND_FILL
		placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var fallback_style := StyleBoxFlat.new()
		fallback_style.bg_color = Color(0.92, 0.89, 0.81)
		fallback_style.set_corner_radius_all(3)
		placeholder.add_theme_stylebox_override("panel", fallback_style)
		var fallback := VBoxContainer.new()
		fallback.alignment = BoxContainer.ALIGNMENT_CENTER
		fallback.add_theme_constant_override("separation", 3)
		fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
		placeholder.add_child(fallback)
		var category_label := Label.new()
		category_label.text = str(card_data.get("category", "カード"))
		category_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		category_label.add_theme_font_size_override("font_size", 10)
		category_label.add_theme_color_override("font_color", Color(0.27, 0.30, 0.36))
		fallback.add_child(category_label)
		var name_label := Label.new()
		name_label.text = card_name
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_label.add_theme_font_size_override("font_size", 15 if card_name.length() <= 2 else 11)
		name_label.add_theme_color_override("font_color", Color(0.09, 0.12, 0.18))
		fallback.add_child(name_label)
		var cost_label := Label.new()
		cost_label.text = "召%d / デッキ%d" % [int(card_data.get("cost", 0)), int(card_data.get("deckcost", 0))]
		cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cost_label.add_theme_font_size_override("font_size", 9)
		cost_label.add_theme_color_override("font_color", Color(0.27, 0.30, 0.36))
		fallback.add_child(cost_label)
		layout.add_child(placeholder)

	if not count_text.is_empty():
		var count_label := Label.new()
		count_label.text = count_text
		count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		count_label.custom_minimum_size = Vector2(0, 16)
		count_label.add_theme_font_size_override("font_size", 10)
		count_label.add_theme_color_override("font_color", Color(0.92, 0.94, 0.98))
		count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layout.add_child(count_label)


func _make_tooltip() -> String:
	var lines: PackedStringArray = PackedStringArray([
		card_name,
		"種類：%s" % str(card_data.get("category", "")),
		"召喚コスト：%d" % int(card_data.get("cost", 0)),
		"デッキコスト：%d" % int(card_data.get("deckcost", 0))
	])
	var activation_cost := int(card_data.get("activation_cost", 0))
	var attack_cost := int(card_data.get("attack_cost", 0))
	if activation_cost > 0:
		lines.append("起動コスト：%d" % activation_cost)
	if attack_cost > 0:
		lines.append("攻撃コスト：%d" % attack_cost)
	var effect_text := str(card_data.get("effect_text", ""))
	if not effect_text.is_empty():
		lines.append("効果：%s" % effect_text)
	lines.append("ドラッグで追加・削除できます。クリックでも操作できます。")
	return "\n".join(lines)

func _on_pressed() -> void:
	if _drag_started:
		return
	clicked.emit(card_name, source_zone, list_type, source_index)


func _get_drag_data(_at_position: Vector2) -> Variant:
	_drag_started = true
	var payload := {
		"card_name": card_name,
		"source_zone": source_zone,
		"list_type": list_type,
		"source_index": source_index
	}

	var preview := TextureRect.new()
	preview.custom_minimum_size = Vector2(80, 112)
	preview.size = Vector2(80, 112)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if image_texture != null:
		preview.texture = image_texture
	else:
		var preview_label := Label.new()
		preview_label.text = card_name
		preview_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		preview_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		preview_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		preview.add_child(preview_label)
	set_drag_preview(preview)
	return payload


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		_drag_started = false
