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
var help_dialog_layer: CanvasLayer

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

	var local_button := _make_menu_button("一人用対局", "CPU対戦またはローカル2人対戦を開始する")
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
	status_label.text = "一人用対局（CPU戦/ローカル）、デッキ構築、ルームマッチを利用できます"
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_font_size_override("font_size", 13)
	status_label.add_theme_color_override("font_color", MUTED_COLOR)
	content_column.add_child(status_label)

	# 画面右上の操作ヘルプ「？」丸型ボタン
	var help_button := Button.new()
	help_button.text = "?"
	help_button.tooltip_text = "操作ヘルプ・ゲームルールを確認する"
	help_button.custom_minimum_size = Vector2(38, 38)
	help_button.focus_mode = Control.FOCUS_NONE
	help_button.add_theme_font_size_override("font_size", 18)
	help_button.anchor_left = 1.0
	help_button.anchor_top = 0.0
	help_button.anchor_right = 1.0
	help_button.anchor_bottom = 0.0
	help_button.offset_left = -56.0
	help_button.offset_top = 16.0
	help_button.offset_right = -18.0
	help_button.offset_bottom = 54.0

	var help_style := StyleBoxFlat.new()
	help_style.bg_color = Color(0.10, 0.13, 0.20)
	help_style.border_color = Color(0.75, 0.65, 0.35)
	help_style.set_border_width_all(2)
	help_style.set_corner_radius_all(19)
	help_button.add_theme_stylebox_override("normal", help_style)

	var help_hover := StyleBoxFlat.new()
	help_hover.bg_color = Color(0.16, 0.22, 0.34)
	help_hover.border_color = Color(1.0, 0.88, 0.45)
	help_hover.set_border_width_all(2)
	help_hover.set_corner_radius_all(19)
	help_button.add_theme_stylebox_override("hover", help_hover)

	help_button.pressed.connect(_show_help_dialog)
	add_child(help_button)


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


# 操作ヘルプダイアログを表示する
func _show_help_dialog() -> void:
	if help_dialog_layer != null:
		return

	help_dialog_layer = CanvasLayer.new()
	help_dialog_layer.layer = 180
	add_child(help_dialog_layer)

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.02, 0.03, 0.06, 0.82)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed:
			_hide_help_dialog()
	)
	help_dialog_layer.add_child(backdrop)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 480)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.08, 0.10, 0.16)
	panel_style.border_color = Color(0.42, 0.50, 0.65)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(10)
	panel_style.set_content_margin_all(20)
	panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	var header_hbox := HBoxContainer.new()
	vbox.add_child(header_hbox)

	var title_lbl := Label.new()
	title_lbl.text = "一騎当千 操作ヘルプ＆ゲームルール"
	title_lbl.add_theme_font_size_override("font_size", 18)
	title_lbl.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0))
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header_hbox.add_child(title_lbl)

	var close_btn := Button.new()
	close_btn.text = "閉じる (Esc)"
	close_btn.custom_minimum_size = Vector2(95, 32)
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.add_theme_font_size_override("font_size", 13)
	close_btn.pressed.connect(_hide_help_dialog)
	header_hbox.add_child(close_btn)

	var sep := HSeparator.new()
	sep.add_theme_color_override("separator", Color(0.25, 0.30, 0.40))
	vbox.add_child(sep)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	var help_text := Label.new()
	help_text.text = """【ゲームの目的】
相手の「王」を捕獲するか、遠隔攻撃で討ち取ると勝利となります。

【ターンの流れ】
1. コスト回復（毎ターン基本+2コスト、領地占領でさらに増加）
2. ドロー（山札からカードを1枚補充）
3. 行動（召喚・駒の移動・攻撃・罠起動など、コストの許す限り自由に行動可能）
4. 手番終了（未使用コストは最大3まで備蓄され、次ターン以降に利用可能）

【カードの種類】
・兵：盤面に召喚して移動・攻撃を行う駒
・成：特定の駒が敵陣進入等でパワーアップする成駒（成デッキから自動昇格）
・壁：配置マスを塞ぎ、進路や突撃を遮断する
・罠：盤面に裏向きで伏せ、敵が踏み込んだ時に効果を発動する

【基本操作】
・手札の選択：手札カードをクリック
・召喚：手札選択後、自陣のハイライトされたマスをクリック
・駒の移動：自分の駒をクリックして選択後、移動可能マスをクリック
・手番終了：画面右下の「手番終了」ボタン または [Space] キー
・選択解除：画面右下の「選択解除」ボタン または [Esc] キー

【駒の捕獲とスリーブ（裏面）】
・相手の駒を捕獲すると、自分の手札に加わり再利用できます
・アナログTCG同様、相手の手札の裏面（スリーブ）を見ることで、奪われた自陣の駒が含まれているか確認できます（自陣スリーブ色のカードが相手の手札に表示されます）"""
	help_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	help_text.add_theme_font_size_override("font_size", 13)
	help_text.add_theme_color_override("font_color", Color(0.90, 0.93, 0.98))
	scroll.add_child(help_text)


# 操作ヘルプダイアログを閉じる
func _hide_help_dialog() -> void:
	if help_dialog_layer != null:
		help_dialog_layer.queue_free()
		help_dialog_layer = null


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if help_dialog_layer != null:
			_hide_help_dialog()
			get_viewport().set_input_as_handled()
