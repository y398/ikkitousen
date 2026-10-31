# ==================================================
# ファイル名: TitleScreen.gd
# 概要: ゲーム起動時のタイトル画面UI制御、対局開始・画面共有テスト・ルームマッチ（P2P）・デッキ構築画面への遷移を管理するシーンスクリプトである
# ==================================================

extends Control

# 対局シーンのファイル名が異なる場合は、インスペクターから変更する
@export_file("*.tscn") var game_scene_path: String = "res://scenes/MatchGame.tscn"
@export_file("*.tscn") var deck_builder_scene_path: String = "res://scenes/DeckBuilder.tscn"
@export_file("*.tscn") var lobby_scene_path: String = "res://scenes/P2PRoomLobby.tscn"

var content_column: VBoxContainer
var status_label: Label

const BG_COLOR := Color(0.055, 0.075, 0.12)
const PANEL_COLOR := Color(0.085, 0.11, 0.17)
const ACCENT_COLOR := Color(0.84, 0.65, 0.30)
const TEXT_COLOR := Color(0.94, 0.95, 0.98)
const MUTED_COLOR := Color(0.68, 0.73, 0.81)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_interface()
	resized.connect(_update_layout)
	_update_layout()


func _build_interface() -> void:
	var background := ColorRect.new()
	background.color = BG_COLOR
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var top_accent := ColorRect.new()
	top_accent.color = ACCENT_COLOR
	top_accent.anchor_left = 0.0
	top_accent.anchor_right = 1.0
	top_accent.offset_bottom = 5.0
	top_accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(top_accent)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	add_child(margin)

	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(center)

	content_column = VBoxContainer.new()
	content_column.add_theme_constant_override("separation", 14)
	content_column.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	center.add_child(content_column)

	var eyebrow := Label.new()
	eyebrow.text = "STRATEGY CARD GAME"
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	eyebrow.add_theme_font_size_override("font_size", 13)
	eyebrow.add_theme_color_override("font_color", ACCENT_COLOR)
	content_column.add_child(eyebrow)

	var title := Label.new()
	title.text = "一騎当千（仮）"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 42)
	title.add_theme_color_override("font_color", TEXT_COLOR)
	content_column.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "盤面を読み、カードを選び、王を守れ。"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.add_theme_font_size_override("font_size", 16)
	subtitle.add_theme_color_override("font_color", MUTED_COLOR)
	content_column.add_child(subtitle)

	var spacer := Control.new()
	spacer.custom_minimum_size.y = 10
	content_column.add_child(spacer)

	var local_button := _make_menu_button("一人用対局", "既存の対局シーンを開く")
	local_button.pressed.connect(_open_game)
	content_column.add_child(local_button)

	var deck_button := _make_menu_button("デッキ構築", "メイン用・サブ用デッキを編集する")
	deck_button.pressed.connect(_open_deck_builder)
	content_column.add_child(deck_button)

	var room_button := _make_menu_button("ルームマッチ（P2P）", "手動シグナリングによる友人とのオンライン対戦")
	room_button.pressed.connect(_open_room_lobby)
	content_column.add_child(room_button)

	var separator := HSeparator.new()
	separator.add_theme_color_override("separator", Color(0.28, 0.33, 0.42))
	content_column.add_child(separator)

	status_label = Label.new()
	status_label.text = "一人用対局、デッキ構築、ルームマッチを利用できます"
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_font_size_override("font_size", 13)
	status_label.add_theme_color_override("font_color", MUTED_COLOR)
	content_column.add_child(status_label)


func _make_menu_button(button_title: String, description: String) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(0, 66)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_ALL
	button.text = button_title
	button.tooltip_text = description
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_color_override("font_color", TEXT_COLOR)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)

	var normal_style := StyleBoxFlat.new()
	normal_style.bg_color = PANEL_COLOR
	normal_style.border_color = Color(0.25, 0.31, 0.41)
	normal_style.set_border_width_all(1)
	normal_style.set_corner_radius_all(9)
	normal_style.set_content_margin_all(12)
	button.add_theme_stylebox_override("normal", normal_style)

	var hover_style := StyleBoxFlat.new()
	hover_style.bg_color = Color(0.13, 0.17, 0.25)
	hover_style.border_color = ACCENT_COLOR
	hover_style.set_border_width_all(2)
	hover_style.set_corner_radius_all(9)
	hover_style.set_content_margin_all(12)
	button.add_theme_stylebox_override("hover", hover_style)

	var pressed_style := StyleBoxFlat.new()
	pressed_style.bg_color = Color(0.16, 0.19, 0.25)
	pressed_style.border_color = ACCENT_COLOR
	pressed_style.set_border_width_all(2)
	pressed_style.set_corner_radius_all(9)
	pressed_style.set_content_margin_all(12)
	button.add_theme_stylebox_override("pressed", pressed_style)

	var disabled_style := StyleBoxFlat.new()
	disabled_style.bg_color = Color(0.07, 0.09, 0.13)
	disabled_style.border_color = Color(0.18, 0.21, 0.27)
	disabled_style.set_border_width_all(1)
	disabled_style.set_corner_radius_all(9)
	disabled_style.set_content_margin_all(12)
	button.add_theme_stylebox_override("disabled", disabled_style)
	button.add_theme_color_override("font_disabled_color", Color(0.46, 0.49, 0.55))

	return button


func _update_layout() -> void:
	if content_column == null:
		return
	# 画面が狭い場合は余白を除いた幅に合わせ、広い場合は最大460pxに抑える
	var available_width := maxf(0.0, size.x - 56.0)
	content_column.custom_minimum_size.x = minf(460.0, available_width)


func _open_game() -> void:
	_open_scene(game_scene_path, "対局シーン")


func _open_deck_builder() -> void:
	_open_scene(deck_builder_scene_path, "デッキ構築シーン")


func _open_room_lobby() -> void:
	_open_scene(lobby_scene_path, "ルームマッチロビー")


func _open_scene(scene_path: String, scene_label: String) -> void:
	if scene_path.strip_edges().is_empty():
		status_label.text = "%sのパスが設定されていません。" % scene_label
		return
	if not ResourceLoader.exists(scene_path):
		status_label.text = "%sが見つかりません。インスペクターでパスを確認してください。\n%s" % [scene_label, scene_path]
		push_warning("%sが見つかりません: %s" % [scene_label, scene_path])
		return

	var error := get_tree().change_scene_to_file(scene_path)
	if error != OK:
		status_label.text = "%sを開けませんでした（エラーコード：%d）。" % [scene_label, error]
		push_error("%sへの移動に失敗しました。エラーコード：%d" % [scene_path, error])
