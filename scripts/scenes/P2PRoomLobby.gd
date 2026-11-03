# ==================================================
# ファイル名: P2PRoomLobby.gd
# 概要: WebRTC手動シグナリングによるP2Pルームマッチ接続・ニックネーム・デッキ選択・手番決定・対局開始を行うロビー画面である
# ==================================================

extends Control

const DeckLibrary = preload("res://scripts/core/DeckLibrary.gd")
const DeckRules = preload("res://scripts/core/DeckRules.gd")

const TITLE_SCENE_PATH := "res://scenes/TitleScreen.tscn"
const GAME_SCENE_PATH := "res://scenes/MatchGame.tscn"
const PLAYER_CONFIG_PATH := "user://player_profile.json"

const BG_COLOR := Color(0.055, 0.075, 0.12)
const PANEL_COLOR := Color(0.085, 0.11, 0.17)
const ACCENT_COLOR := Color(0.84, 0.65, 0.30)
const TEXT_COLOR := Color(0.94, 0.95, 0.98)
const MUTED_COLOR := Color(0.68, 0.73, 0.81)

var deck_library: Dictionary = {}
var selected_deck_id: String = "deck_1"
var my_profile: Dictionary = {}
var opponent_profile: Dictionary = {}

# 接続前UI要素
var connection_section: VBoxContainer
var nickname_edit: LineEdit
var host_button: Button
var guest_button: Button
var host_container: VBoxContainer
var guest_container: VBoxContainer
var host_offer_edit: TextEdit
var host_answer_edit: TextEdit
var guest_offer_edit: TextEdit
var guest_answer_edit: TextEdit
var host_copy_button: Button
var host_connect_button: Button
var guest_generate_button: Button
var guest_copy_button: Button

# 接続後（対戦準備ルーム）UI要素
var room_section: VBoxContainer
var room_user_info_label: Label
var room_deck_selector: OptionButton
var room_side_selector: OptionButton
var room_side_info_label: Label
var room_my_status_label: Label
var room_opponent_status_label: Label
var room_ready_button: Button
var room_start_button: Button

var status_label: Label

var is_local_ready: bool = false
var is_opponent_ready: bool = false
var selected_side_mode: int = 0 # 0: ホスト先手, 1: ゲスト先手, 2: ランダム


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var loaded := DeckLibrary.load_library()
	deck_library = loaded.get("decks", DeckLibrary.default_decks())
	selected_deck_id = str(loaded.get("last_selected_deck_id", "deck_1"))
	if not deck_library.has(selected_deck_id):
		selected_deck_id = DeckLibrary.ordered_deck_ids(deck_library)[0]
	my_profile = deck_library[selected_deck_id]

	P2PNetwork.local_nickname = _load_nickname()

	_build_ui()
	_connect_network_signals()


func _connect_network_signals() -> void:
	P2PNetwork.session_code_ready.connect(_on_session_code_ready)
	P2PNetwork.connection_established.connect(_on_connection_established)
	P2PNetwork.connection_closed.connect(_on_connection_closed)
	P2PNetwork.message_received.connect(_on_message_received)
	P2PNetwork.log_updated.connect(_on_log_updated)
	P2PNetwork.connection_error.connect(_on_connection_error)


func _exit_tree() -> void:
	if P2PNetwork.session_code_ready.is_connected(_on_session_code_ready):
		P2PNetwork.session_code_ready.disconnect(_on_session_code_ready)
	if P2PNetwork.connection_established.is_connected(_on_connection_established):
		P2PNetwork.connection_established.disconnect(_on_connection_established)
	if P2PNetwork.connection_closed.is_connected(_on_connection_closed):
		P2PNetwork.connection_closed.disconnect(_on_connection_closed)
	if P2PNetwork.message_received.is_connected(_on_message_received):
		P2PNetwork.message_received.disconnect(_on_message_received)
	if P2PNetwork.log_updated.is_connected(_on_log_updated):
		P2PNetwork.log_updated.disconnect(_on_log_updated)
	if P2PNetwork.connection_error.is_connected(_on_connection_error):
		P2PNetwork.connection_error.disconnect(_on_connection_error)


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var top_bar := ColorRect.new()
	top_bar.color = ACCENT_COLOR
	top_bar.anchor_left = 0.0
	top_bar.anchor_right = 1.0
	top_bar.offset_bottom = 4.0
	add_child(top_bar)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 40.0
	scroll.offset_top = 70.0
	scroll.offset_right = -40.0
	scroll.offset_bottom = -20.0
	add_child(scroll)

	# 戻るボタン（前面配置）
	var back_btn := Button.new()
	back_btn.text = "← タイトルへ戻る"
	back_btn.offset_left = 20.0
	back_btn.offset_top = 16.0
	back_btn.offset_right = 170.0
	back_btn.offset_bottom = 58.0
	back_btn.custom_minimum_size = Vector2(150, 42)
	back_btn.z_index = 10
	_style_button(back_btn, false)
	back_btn.pressed.connect(_on_back_to_title_pressed)
	add_child(back_btn)

	var root_vbox := VBoxContainer.new()
	root_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_vbox.add_theme_constant_override("separation", 14)
	scroll.add_child(root_vbox)

	var title := Label.new()
	title.text = "P2P ルームマッチ"
	title.add_theme_font_size_override("font_size", 26)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root_vbox.add_child(title)

	var desc := Label.new()
	desc.text = "サーバーを介さず、接続コードをチャット等で共有して直接対局を行う方式である"
	desc.add_theme_font_size_override("font_size", 14)
	desc.add_theme_color_override("font_color", MUTED_COLOR)
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root_vbox.add_child(desc)

	# ==========================================
	# 1. 接続フェーズ（接続前UI）
	# ==========================================
	connection_section = VBoxContainer.new()
	connection_section.add_theme_constant_override("separation", 14)
	root_vbox.add_child(connection_section)

	# ニックネーム入力パネル
	var nick_panel := PanelContainer.new()
	connection_section.add_child(nick_panel)
	var nick_vbox := VBoxContainer.new()
	nick_vbox.add_theme_constant_override("separation", 6)
	nick_panel.add_child(nick_vbox)

	var nick_label := Label.new()
	nick_label.text = "あなたのニックネーム"
	nick_label.add_theme_font_size_override("font_size", 15)
	nick_label.add_theme_color_override("font_color", ACCENT_COLOR)
	nick_vbox.add_child(nick_label)

	nickname_edit = LineEdit.new()
	nickname_edit.text = P2PNetwork.local_nickname
	nickname_edit.placeholder_text = "ニックネームを入力（次回も保存される）"
	nickname_edit.custom_minimum_size.y = 42
	nickname_edit.text_changed.connect(_on_nickname_changed)
	nick_vbox.add_child(nickname_edit)

	# 部屋作成・参加ボタン
	var role_box := HBoxContainer.new()
	role_box.add_theme_constant_override("separation", 16)
	connection_section.add_child(role_box)

	host_button = Button.new()
	host_button.text = "部屋を作る (ホスト)"
	host_button.custom_minimum_size = Vector2(0, 48)
	host_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_button(host_button, false)
	host_button.pressed.connect(_on_start_host_pressed)
	role_box.add_child(host_button)

	guest_button = Button.new()
	guest_button.text = "部屋に入る (ゲスト)"
	guest_button.custom_minimum_size = Vector2(0, 48)
	guest_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_button(guest_button, false)
	guest_button.pressed.connect(_on_start_guest_pressed)
	role_box.add_child(guest_button)

	# ホスト用パネル
	host_container = VBoxContainer.new()
	host_container.visible = false
	host_container.add_theme_constant_override("separation", 10)
	connection_section.add_child(host_container)

	var host_step1_lbl := Label.new()
	host_step1_lbl.text = "Step 1: あなたの接続コード（オファー）をコピーして相手に送信する"
	host_step1_lbl.add_theme_color_override("font_color", ACCENT_COLOR)
	host_container.add_child(host_step1_lbl)

	host_offer_edit = TextEdit.new()
	host_offer_edit.custom_minimum_size.y = 80
	host_offer_edit.editable = false
	host_offer_edit.placeholder_text = "接続コード生成中..."
	host_container.add_child(host_offer_edit)

	host_copy_button = Button.new()
	host_copy_button.text = "接続コードをクリップボードにコピー"
	host_copy_button.custom_minimum_size.y = 42
	_style_button(host_copy_button, false)
	host_copy_button.pressed.connect(func(): _copy_to_clipboard(host_offer_edit.text, "オファーコード"))
	host_container.add_child(host_copy_button)

	var host_step2_lbl := Label.new()
	host_step2_lbl.text = "Step 2: 相手から返信されたアンサーコードをここに貼り付けて接続する"
	host_step2_lbl.add_theme_color_override("font_color", ACCENT_COLOR)
	host_container.add_child(host_step2_lbl)

	var host_paste_button := Button.new()
	host_paste_button.text = "[貼付] クリップボードから貼り付け"
	host_paste_button.custom_minimum_size.y = 42
	_style_button(host_paste_button, true)
	host_paste_button.pressed.connect(func(): _paste_to_target(host_answer_edit))
	host_container.add_child(host_paste_button)

	host_answer_edit = TextEdit.new()
	host_answer_edit.custom_minimum_size.y = 80
	host_answer_edit.placeholder_text = "ここに相手のアンサーコードを貼り付ける"
	host_container.add_child(host_answer_edit)

	host_connect_button = Button.new()
	host_connect_button.text = "アンサーを適用して接続する"
	host_connect_button.custom_minimum_size.y = 46
	_style_button(host_connect_button, true)
	host_connect_button.pressed.connect(_on_host_apply_answer_pressed)
	host_container.add_child(host_connect_button)

	# ゲスト用パネル
	guest_container = VBoxContainer.new()
	guest_container.visible = false
	guest_container.add_theme_constant_override("separation", 10)
	connection_section.add_child(guest_container)

	var guest_step1_lbl := Label.new()
	guest_step1_lbl.text = "Step 1: ホストから受け取ったオファーコードを貼り付ける"
	guest_step1_lbl.add_theme_color_override("font_color", ACCENT_COLOR)
	guest_container.add_child(guest_step1_lbl)

	var guest_paste_button := Button.new()
	guest_paste_button.text = "[貼付] クリップボードから貼り付け"
	guest_paste_button.custom_minimum_size.y = 42
	_style_button(guest_paste_button, true)
	guest_paste_button.pressed.connect(func(): _paste_to_target(guest_offer_edit))
	guest_container.add_child(guest_paste_button)

	guest_offer_edit = TextEdit.new()
	guest_offer_edit.custom_minimum_size.y = 80
	guest_offer_edit.placeholder_text = "ここにホストのオファーコードを貼り付ける"
	guest_container.add_child(guest_offer_edit)

	guest_generate_button = Button.new()
	guest_generate_button.text = "オファーを読み込み、返信コード（アンサー）を生成する"
	guest_generate_button.custom_minimum_size.y = 46
	_style_button(guest_generate_button, true)
	guest_generate_button.pressed.connect(_on_guest_apply_offer_pressed)
	guest_container.add_child(guest_generate_button)

	var guest_step2_lbl := Label.new()
	guest_step2_lbl.text = "Step 2: 生成されたアンサーコードをコピーしてホストに返信する"
	guest_step2_lbl.add_theme_color_override("font_color", ACCENT_COLOR)
	guest_container.add_child(guest_step2_lbl)

	guest_answer_edit = TextEdit.new()
	guest_answer_edit.custom_minimum_size.y = 80
	guest_answer_edit.editable = false
	guest_answer_edit.placeholder_text = "Step 1 完了後にここに返信コードが表示される"
	guest_container.add_child(guest_answer_edit)

	guest_copy_button = Button.new()
	guest_copy_button.text = "アンサーコードをクリップボードにコピー"
	guest_copy_button.custom_minimum_size.y = 42
	_style_button(guest_copy_button, false)
	guest_copy_button.pressed.connect(func(): _copy_to_clipboard(guest_answer_edit.text, "アンサーコード"))
	guest_container.add_child(guest_copy_button)

	# ==========================================
	# 2. 対戦準備ルーム（接続確立後UI）
	# ==========================================
	room_section = VBoxContainer.new()
	room_section.visible = false
	room_section.add_theme_constant_override("separation", 16)
	root_vbox.add_child(room_section)

	var room_card := PanelContainer.new()
	room_section.add_child(room_card)
	var room_vbox := VBoxContainer.new()
	room_vbox.add_theme_constant_override("separation", 14)
	room_card.add_child(room_vbox)

	var room_header := Label.new()
	room_header.text = "★ 接続完了 - 対戦準備ルーム"
	room_header.add_theme_font_size_override("font_size", 20)
	room_header.add_theme_color_override("font_color", ACCENT_COLOR)
	room_vbox.add_child(room_header)

	room_user_info_label = Label.new()
	room_user_info_label.text = "あなた: %s\n相手: 接続待機中..." % P2PNetwork.local_nickname
	room_user_info_label.add_theme_font_size_override("font_size", 16)
	room_vbox.add_child(room_user_info_label)

	# デッキ選択
	var deck_box := VBoxContainer.new()
	deck_box.add_theme_constant_override("separation", 6)
	room_vbox.add_child(deck_box)

	var deck_lbl := Label.new()
	deck_lbl.text = "使用デッキの選択"
	deck_lbl.add_theme_font_size_override("font_size", 15)
	deck_lbl.add_theme_color_override("font_color", ACCENT_COLOR)
	deck_box.add_child(deck_lbl)

	room_deck_selector = OptionButton.new()
	room_deck_selector.custom_minimum_size.y = 42
	for deck_id in DeckLibrary.ordered_deck_ids(deck_library):
		var profile: Dictionary = deck_library[deck_id]
		room_deck_selector.add_item(str(profile.get("name", deck_id)))
		room_deck_selector.set_item_metadata(room_deck_selector.item_count - 1, deck_id)
		if deck_id == selected_deck_id:
			room_deck_selector.select(room_deck_selector.item_count - 1)
	room_deck_selector.item_selected.connect(_on_room_deck_selected)
	deck_box.add_child(room_deck_selector)

	# 手番設定
	var side_box := VBoxContainer.new()
	side_box.add_theme_constant_override("separation", 6)
	room_vbox.add_child(side_box)

	var side_title := Label.new()
	side_title.text = "手番（先手・後手）の設定"
	side_title.add_theme_font_size_override("font_size", 15)
	side_title.add_theme_color_override("font_color", ACCENT_COLOR)
	side_box.add_child(side_title)

	room_side_selector = OptionButton.new()
	room_side_selector.custom_minimum_size.y = 42
	room_side_selector.add_item("ホストが先手 / ゲストが後手", 0)
	room_side_selector.add_item("ゲストが先手 / ホストが後手", 1)
	room_side_selector.add_item("ランダム（振り駒）", 2)
	room_side_selector.select(0)
	room_side_selector.item_selected.connect(_on_side_mode_selected)
	side_box.add_child(room_side_selector)

	room_side_info_label = Label.new()
	room_side_info_label.text = "（ホストが手番設定を変更できます）"
	room_side_info_label.add_theme_font_size_override("font_size", 13)
	room_side_info_label.add_theme_color_override("font_color", MUTED_COLOR)
	side_box.add_child(room_side_info_label)

	# 準備状態表示
	var status_box := HBoxContainer.new()
	status_box.add_theme_constant_override("separation", 20)
	room_vbox.add_child(status_box)

	room_my_status_label = Label.new()
	room_my_status_label.text = "あなた: 準備中"
	room_my_status_label.add_theme_color_override("font_color", MUTED_COLOR)
	status_box.add_child(room_my_status_label)

	room_opponent_status_label = Label.new()
	room_opponent_status_label.text = "相手: 準備中"
	room_opponent_status_label.add_theme_color_override("font_color", MUTED_COLOR)
	status_box.add_child(room_opponent_status_label)

	# 準備完了ボタン
	room_ready_button = Button.new()
	room_ready_button.text = "準備完了にする"
	room_ready_button.custom_minimum_size = Vector2(0, 50)
	_style_button(room_ready_button, true)
	room_ready_button.pressed.connect(_on_ready_button_pressed)
	room_vbox.add_child(room_ready_button)

	# ホスト専用の対局開始ボタン（双方が準備完了した際に有効化）
	room_start_button = Button.new()
	room_start_button.text = "対局を開始する"
	room_start_button.custom_minimum_size = Vector2(0, 50)
	room_start_button.visible = false
	_style_button(room_start_button, true)
	room_start_button.pressed.connect(_on_start_match_pressed)
	room_vbox.add_child(room_start_button)

	# 共通ステータス表示
	status_label = Label.new()
	status_label.text = "ニックネームを確認し、「部屋を作る」または「部屋に入る」を選択してください"
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_color_override("font_color", ACCENT_COLOR)
	root_vbox.add_child(status_label)


func _on_nickname_changed(new_text: String) -> void:
	var cleaned := new_text.strip_edges()
	if cleaned.is_empty():
		cleaned = "プレイヤー"
	P2PNetwork.local_nickname = cleaned
	_save_nickname(cleaned)


func _on_start_host_pressed() -> void:
	host_container.visible = true
	guest_container.visible = false
	host_button.disabled = true
	guest_button.disabled = true
	nickname_edit.editable = false
	_on_log_updated("ホストとして部屋を作成中である...")
	P2PNetwork.start_host()


func _on_start_guest_pressed() -> void:
	host_container.visible = false
	guest_container.visible = true
	host_button.disabled = true
	guest_button.disabled = true
	nickname_edit.editable = false
	_on_log_updated("ゲストとして待機中である ホストのオファーコードを貼り付けてください")
	P2PNetwork.start_guest()


func _on_session_code_ready(type: String, code: String) -> void:
	if type == "offer":
		host_offer_edit.text = code
		_on_log_updated("オファーコード生成完了 コードを相手に共有してください")
	elif type == "answer":
		guest_answer_edit.text = code
		_on_log_updated("アンサーコード生成完了 コードをホストに返信してください")


func _on_host_apply_answer_pressed() -> void:
	var answer_text := host_answer_edit.text.strip_edges()
	if answer_text.is_empty():
		_on_log_updated("アンサーコードを入力してください")
		return
	_on_log_updated("アンサーコードを適用中である...")
	P2PNetwork.apply_remote_code(answer_text)


func _on_guest_apply_offer_pressed() -> void:
	var offer_text := guest_offer_edit.text.strip_edges()
	if offer_text.is_empty():
		_on_log_updated("オファーコードを入力してください")
		return
	_on_log_updated("オファーコードを適用中である...")
	P2PNetwork.apply_remote_code(offer_text)


func _on_connection_established() -> void:
	_on_log_updated("★ P2P接続が確立された 対戦準備ルームを開く...")
	connection_section.visible = false
	room_section.visible = true

	# ホストのみ手番設定を変更可能とする
	if P2PNetwork.current_role == P2PNetwork.Role.HOST:
		room_side_selector.disabled = false
		room_side_info_label.text = "手番（先手・後手）を選択してください"
		P2PNetwork.shared_random_seed = randi()
		if P2PNetwork.shared_random_seed == 0:
			P2PNetwork.shared_random_seed = 1
	else:
		room_side_selector.disabled = true
		room_side_info_label.text = "（ホストが手番を設定中である）"

	# 初回プロファイル交換（名前と初期デッキ情報）
	_send_room_profile()
	_update_room_display()


# 自身のプレイヤー情報（名前・デッキ・準備状態）を相手に送信する
func _send_room_profile() -> void:
	P2PNetwork.send_message({
		"action": "room_sync",
		"nickname": P2PNetwork.local_nickname,
		"deck_profile": my_profile,
		"is_ready": is_local_ready,
		"side_mode": selected_side_mode
	})


func _on_room_deck_selected(index: int) -> void:
	selected_deck_id = str(room_deck_selector.get_item_metadata(index))
	my_profile = deck_library[selected_deck_id]
	_on_log_updated("デッキを変更した: %s" % str(my_profile.get("name", selected_deck_id)))
	is_local_ready = false
	_update_ready_button()
	_send_room_profile()


func _on_side_mode_selected(index: int) -> void:
	if P2PNetwork.current_role != P2PNetwork.Role.HOST:
		return
	selected_side_mode = index
	is_local_ready = false
	_update_ready_button()
	_send_room_profile()


func _on_ready_button_pressed() -> void:
	is_local_ready = not is_local_ready
	_update_ready_button()
	_send_room_profile()
	_check_both_ready()


func _update_ready_button() -> void:
	if is_local_ready:
		room_ready_button.text = "✓ 準備完了済み (解除する)"
		room_my_status_label.text = "あなた: 準備完了！"
		room_my_status_label.add_theme_color_override("font_color", Color(0.40, 0.90, 0.50))
	else:
		room_ready_button.text = "準備完了にする"
		room_my_status_label.text = "あなた: 準備中"
		room_my_status_label.add_theme_color_override("font_color", MUTED_COLOR)


func _update_room_display() -> void:
	room_user_info_label.text = "あなた: %s\n相手: %s" % [
		P2PNetwork.local_nickname,
		P2PNetwork.remote_nickname
	]

	if is_opponent_ready:
		room_opponent_status_label.text = "相手: 準備完了！"
		room_opponent_status_label.add_theme_color_override("font_color", Color(0.40, 0.90, 0.50))
	else:
		room_opponent_status_label.text = "相手: 準備中"
		room_opponent_status_label.add_theme_color_override("font_color", MUTED_COLOR)


func _on_message_received(msg: Dictionary) -> void:
	var action := str(msg.get("action", ""))
	match action:
		"room_sync":
			_handle_room_sync(msg)
		"start_match":
			_handle_start_match(msg)


func _handle_room_sync(msg: Dictionary) -> void:
	var rem_nick := str(msg.get("nickname", "対戦相手")).strip_edges()
	if not rem_nick.is_empty():
		P2PNetwork.remote_nickname = rem_nick
	
	if msg.has("deck_profile"):
		opponent_profile = msg.get("deck_profile", {})

	is_opponent_ready = bool(msg.get("is_ready", false))

	# ゲスト側はホストの手番設定を同期する
	if P2PNetwork.current_role == P2PNetwork.Role.GUEST and msg.has("side_mode"):
		selected_side_mode = int(msg.get("side_mode", 0))
		room_side_selector.select(selected_side_mode)

	_update_room_display()
	_check_both_ready()


func _check_both_ready() -> void:
	if P2PNetwork.current_role == P2PNetwork.Role.HOST:
		if is_local_ready and is_opponent_ready:
			room_start_button.visible = true
			room_start_button.disabled = false
			_on_log_updated("双方の準備が完了した 「対局を開始する」を押してください")
		else:
			room_start_button.visible = false
	else:
		if is_local_ready and is_opponent_ready:
			_on_log_updated("双方の準備完了 ホストの対局開始を待機中である...")


func _on_start_match_pressed() -> void:
	if P2PNetwork.current_role != P2PNetwork.Role.HOST:
		return
	if not (is_local_ready and is_opponent_ready):
		return

	# 手番を決定する
	var final_sente_is_host: bool = true
	match selected_side_mode:
		0:
			final_sente_is_host = true
		1:
			final_sente_is_host = false
		2:
			final_sente_is_host = (randi() % 2 == 0)

	var match_seed := P2PNetwork.shared_random_seed
	if match_seed == 0:
		match_seed = randi()
		if match_seed == 0:
			match_seed = 1
		P2PNetwork.shared_random_seed = match_seed

	# ゲストへ対局開始パケットを送信する
	P2PNetwork.send_message({
		"action": "start_match",
		"sente_is_host": final_sente_is_host,
		"seed": match_seed,
		"host_profile": my_profile,
		"guest_profile": opponent_profile
	})

	_launch_game(final_sente_is_host, match_seed, my_profile, opponent_profile)


func _handle_start_match(msg: Dictionary) -> void:
	var final_sente_is_host: bool = bool(msg.get("sente_is_host", true))
	var match_seed: int = int(msg.get("seed", 1))
	var host_prof: Dictionary = msg.get("host_profile", opponent_profile)
	var guest_prof: Dictionary = msg.get("guest_profile", my_profile)

	_launch_game(final_sente_is_host, match_seed, host_prof, guest_prof)


func _launch_game(final_sente_is_host: bool, match_seed: int, host_prof: Dictionary, guest_prof: Dictionary) -> void:
	P2PNetwork.shared_random_seed = match_seed

	# 先手（インデックス0）と後手（インデックス1）のプロファイルを決定する
	if final_sente_is_host:
		P2PNetwork.host_deck_profile = host_prof  # 先手
		P2PNetwork.guest_deck_profile = guest_prof # 後手
		P2PNetwork.local_player_id = 0 if P2PNetwork.current_role == P2PNetwork.Role.HOST else 1
	else:
		P2PNetwork.host_deck_profile = guest_prof # 先手
		P2PNetwork.guest_deck_profile = host_prof  # 後手
		P2PNetwork.local_player_id = 1 if P2PNetwork.current_role == P2PNetwork.Role.HOST else 0

	P2PNetwork.is_p2p_match = true
	_on_log_updated("対局画面へ遷移する（あなたの手番: %s）..." % ("先手" if P2PNetwork.local_player_id == 0 else "後手"))
	get_tree().change_scene_to_file(GAME_SCENE_PATH)


func _on_connection_closed() -> void:
	_on_log_updated("通信が切断された")
	is_local_ready = false
	is_opponent_ready = false
	if room_section != null:
		room_section.visible = false
	if connection_section != null:
		connection_section.visible = true
	if host_button != null:
		host_button.disabled = false
	if guest_button != null:
		guest_button.disabled = false
	if nickname_edit != null:
		nickname_edit.editable = true


func _on_connection_error(error_msg: String) -> void:
	_on_log_updated("接続エラー: " + error_msg)


func _on_log_updated(text: String) -> void:
	print("[P2PRoomLobby] " + text)
	if status_label != null:
		status_label.text = text


func _on_back_to_title_pressed() -> void:
	P2PNetwork.close_connection()
	get_tree().change_scene_to_file(TITLE_SCENE_PATH)


# クリップボードへテキストをコピーする
func _copy_to_clipboard(text: String, label_hint: String) -> void:
	DisplayServer.clipboard_set(text)
	if OS.has_feature("web"):
		var escaped := text.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "")
		var js_code := 'navigator.clipboard.writeText("%s").catch(function(e) { console.error(e); });' % escaped
		JavaScriptBridge.eval(js_code)
	_on_log_updated("%sをクリップボードにコピーした" % label_hint)


# ターゲットのエディットにクリップボードまたはプロンプト入力を反映する
func _paste_to_target(target_edit: TextEdit) -> void:
	if target_edit == null:
		return
	if OS.has_feature("web"):
		var js_code := """
			(function() {
				var pasted = window.prompt("接続コードを貼り付けてください（長押しでペースト）:") || "";
				return pasted;
			})()
		"""
		var result: Variant = JavaScriptBridge.eval(js_code)
		if result != null and not str(result).strip_edges().is_empty():
			target_edit.text = str(result).strip_edges()
			_on_log_updated("コードを貼り付けた")
			return
	var clip_text := DisplayServer.clipboard_get().strip_edges()
	if not clip_text.is_empty():
		target_edit.text = clip_text
		_on_log_updated("クリップボードから貼り付けた")
	else:
		_on_log_updated("クリップボードが空、またはアクセス許可が得られなかった")


# ボタンに統一された高コントラストなスタイルを適用する
func _style_button(btn: Button, is_accent: bool = false) -> void:
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	btn.add_theme_font_size_override("font_size", 14)

	var normal_bg := Color(0.18, 0.24, 0.35) if is_accent else Color(0.10, 0.13, 0.19)
	var border_color := ACCENT_COLOR if is_accent else Color(0.28, 0.35, 0.46)
	var text_color := Color(1.0, 1.0, 1.0) if is_accent else TEXT_COLOR

	var normal_style := StyleBoxFlat.new()
	normal_style.bg_color = normal_bg
	normal_style.border_color = border_color
	normal_style.set_border_width_all(1)
	normal_style.set_corner_radius_all(6)
	normal_style.set_content_margin_all(8)
	btn.add_theme_stylebox_override("normal", normal_style)
	btn.add_theme_color_override("font_color", text_color)

	var hover_style := StyleBoxFlat.new()
	hover_style.bg_color = normal_bg.lightened(0.12)
	hover_style.border_color = ACCENT_COLOR
	hover_style.set_border_width_all(2)
	hover_style.set_corner_radius_all(6)
	hover_style.set_content_margin_all(8)
	btn.add_theme_stylebox_override("hover", hover_style)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)

	var pressed_style := StyleBoxFlat.new()
	pressed_style.bg_color = normal_bg.darkened(0.1)
	pressed_style.border_color = ACCENT_COLOR
	pressed_style.set_border_width_all(2)
	pressed_style.set_corner_radius_all(6)
	pressed_style.set_content_margin_all(8)
	btn.add_theme_stylebox_override("pressed", pressed_style)
	btn.add_theme_color_override("font_pressed_color", Color.WHITE)

	var disabled_style := StyleBoxFlat.new()
	disabled_style.bg_color = Color(0.08, 0.09, 0.12, 0.8)
	disabled_style.border_color = Color(0.2, 0.22, 0.28)
	disabled_style.set_border_width_all(1)
	disabled_style.set_corner_radius_all(6)
	disabled_style.set_content_margin_all(8)
	btn.add_theme_stylebox_override("disabled", disabled_style)
	btn.add_theme_color_override("font_disabled_color", Color(0.55, 0.60, 0.68))


# ニックネームのロード処理である
func _load_nickname() -> String:
	if FileAccess.file_exists(PLAYER_CONFIG_PATH):
		var file := FileAccess.open(PLAYER_CONFIG_PATH, FileAccess.READ)
		if file != null:
			var text := file.get_as_text()
			var json: Variant = JSON.parse_string(text)
			if json is Dictionary and json.has("nickname"):
				return str(json["nickname"]).strip_edges()
	return "プレイヤー"


# ニックネームのセーブ処理である
func _save_nickname(nick: String) -> void:
	var file := FileAccess.open(PLAYER_CONFIG_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify({"nickname": nick}))
