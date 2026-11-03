# ==================================================
# ファイル名: P2PRoomLobby.gd
# 概要: WebRTC手動シグナリングによるP2Pルームマッチ接続・デッキ交換・対局開始を行うロビー画面である
# ==================================================

extends Control

const DeckLibrary = preload("res://scripts/core/DeckLibrary.gd")
const DeckRules = preload("res://scripts/core/DeckRules.gd")

const TITLE_SCENE_PATH := "res://scenes/TitleScreen.tscn"
const GAME_SCENE_PATH := "res://scenes/MatchGame.tscn"

const BG_COLOR := Color(0.055, 0.075, 0.12)
const PANEL_COLOR := Color(0.085, 0.11, 0.17)
const ACCENT_COLOR := Color(0.84, 0.65, 0.30)
const TEXT_COLOR := Color(0.94, 0.95, 0.98)
const MUTED_COLOR := Color(0.68, 0.73, 0.81)

var deck_library: Dictionary = {}
var selected_deck_id: String = "deck_1"
var my_profile: Dictionary = {}
var opponent_profile: Dictionary = {}

var deck_selector: OptionButton
var status_label: Label
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

var is_deck_handshake_done: bool = false
var is_opponent_ready: bool = false
var is_local_ready: bool = false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var loaded := DeckLibrary.load_library()
	deck_library = loaded.get("decks", DeckLibrary.default_decks())
	selected_deck_id = str(loaded.get("last_selected_deck_id", "deck_1"))
	if not deck_library.has(selected_deck_id):
		selected_deck_id = DeckLibrary.ordered_deck_ids(deck_library)[0]
	my_profile = deck_library[selected_deck_id]

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
	scroll.offset_left = 60.0
	scroll.offset_top = 70.0
	scroll.offset_right = -60.0
	scroll.offset_bottom = -20.0
	add_child(scroll)

	# 戻るボタン（スクロール領域より前面に配置してタッチイベントを確実に受ける）
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
	title.text = "P2P ルームマッチ（手動シグナリング）"
	title.add_theme_font_size_override("font_size", 24)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root_vbox.add_child(title)

	var desc := Label.new()
	desc.text = "サーバーを介さず、接続コードをDiscord等のチャットに貼り合って直接通信対局を行う方式である"
	desc.add_theme_font_size_override("font_size", 13)
	desc.add_theme_color_override("font_color", MUTED_COLOR)
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root_vbox.add_child(desc)

	# 1. デッキ選択
	var deck_panel := PanelContainer.new()
	root_vbox.add_child(deck_panel)
	var deck_vbox := VBoxContainer.new()
	deck_vbox.add_theme_constant_override("separation", 8)
	deck_panel.add_child(deck_vbox)

	var deck_label := Label.new()
	deck_label.text = "1. 使用する自分のデッキを選択"
	deck_label.add_theme_font_size_override("font_size", 16)
	deck_label.add_theme_color_override("font_color", ACCENT_COLOR)
	deck_vbox.add_child(deck_label)

	deck_selector = OptionButton.new()
	deck_selector.custom_minimum_size.y = 38
	for deck_id in DeckLibrary.ordered_deck_ids(deck_library):
		var profile: Dictionary = deck_library[deck_id]
		deck_selector.add_item(str(profile.get("name", deck_id)))
		deck_selector.set_item_metadata(deck_selector.item_count - 1, deck_id)
	deck_selector.item_selected.connect(_on_deck_selected)
	deck_vbox.add_child(deck_selector)

	# 2. 役割選択ボタン
	var role_box := HBoxContainer.new()
	role_box.add_theme_constant_override("separation", 16)
	root_vbox.add_child(role_box)

	host_button = Button.new()
	host_button.text = "部屋を作る (ホスト・先手)"
	host_button.custom_minimum_size = Vector2(0, 48)
	host_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_button(host_button, false)
	host_button.pressed.connect(_on_start_host_pressed)
	role_box.add_child(host_button)

	guest_button = Button.new()
	guest_button.text = "部屋に入る (ゲスト・後手)"
	guest_button.custom_minimum_size = Vector2(0, 48)
	guest_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_button(guest_button, false)
	guest_button.pressed.connect(_on_start_guest_pressed)
	role_box.add_child(guest_button)

	# 3. ホスト用パネル
	host_container = VBoxContainer.new()
	host_container.visible = false
	host_container.add_theme_constant_override("separation", 10)
	root_vbox.add_child(host_container)

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

	# 貼り付けボタン（タッチ操作・ブラウザ連携）
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
	host_connect_button.text = "アンサーを適用して対局を開始する"
	host_connect_button.custom_minimum_size.y = 46
	_style_button(host_connect_button, true)
	host_connect_button.pressed.connect(_on_host_apply_answer_pressed)
	host_container.add_child(host_connect_button)

	# 4. ゲスト用パネル
	guest_container = VBoxContainer.new()
	guest_container.visible = false
	guest_container.add_theme_constant_override("separation", 10)
	root_vbox.add_child(guest_container)

	var guest_step1_lbl := Label.new()
	guest_step1_lbl.text = "Step 1: ホストから受け取ったオファーコードを貼り付ける"
	guest_step1_lbl.add_theme_color_override("font_color", ACCENT_COLOR)
	guest_container.add_child(guest_step1_lbl)

	# 貼り付けボタン（タッチ操作・ブラウザ連携）
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

	# ステータス表示
	status_label = Label.new()
	status_label.text = "デッキを選択し、「部屋を作る」または「部屋に入る」を選択してください"
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_color_override("font_color", ACCENT_COLOR)
	root_vbox.add_child(status_label)


func _on_deck_selected(index: int) -> void:
	selected_deck_id = str(deck_selector.get_item_metadata(index))
	my_profile = deck_library[selected_deck_id]
	_on_log_updated("使用デッキを変更した: %s" % str(my_profile.get("name", selected_deck_id)))


func _on_start_host_pressed() -> void:
	host_container.visible = true
	guest_container.visible = false
	host_button.disabled = true
	guest_button.disabled = true
	deck_selector.disabled = true
	_on_log_updated("ホストとして部屋を作成中である...")
	P2PNetwork.start_host()


func _on_start_guest_pressed() -> void:
	host_container.visible = false
	guest_container.visible = true
	host_button.disabled = true
	guest_button.disabled = true
	deck_selector.disabled = true
	_on_log_updated("ゲストとして待機中である ホストのオファーコードを貼り付けてください")
	P2PNetwork.start_guest()


func _on_session_code_ready(type: String, code: String) -> void:
	if type == "offer":
		host_offer_edit.text = code
		_on_log_updated("オファーコード生成完了 コードをコピーして相手に送信してください")
	elif type == "answer":
		guest_answer_edit.text = code
		_on_log_updated("アンサーコード生成完了 コードをコピーしてホストに返信してください")


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
	_on_log_updated("★ P2P接続が確立された デッキ情報の交換を開始する...")
	is_deck_handshake_done = false
	is_opponent_ready = false
	is_local_ready = false

	# 接続確立後、お互いのデッキプロファイルを交換する
	var seed_val := randi() if P2PNetwork.current_role == P2PNetwork.Role.HOST else 0
	var payload := {
		"action": "deck_handshake",
		"sender_role": "host" if P2PNetwork.current_role == P2PNetwork.Role.HOST else "guest",
		"deck_profile": my_profile,
		"seed": seed_val
	}
	P2PNetwork.send_message(payload)


func _on_message_received(msg: Dictionary) -> void:
	var action := str(msg.get("action", ""))
	match action:
		"deck_handshake":
			_handle_deck_handshake(msg)
		"ready_to_play":
			is_opponent_ready = true
			_check_start_match()


func _handle_deck_handshake(msg: Dictionary) -> void:
	opponent_profile = msg.get("deck_profile", {})
	var validation := DeckLibrary.validate_playable_profile(opponent_profile)
	if not bool(validation.get("valid", false)):
		_on_log_updated("エラー: 相手のデッキが対局ルールを満たしていない")
		return

	var sender_role := str(msg.get("sender_role", ""))
	if sender_role == "host":
		# ゲスト側はホストの乱数シードを採用する
		P2PNetwork.shared_random_seed = int(msg.get("seed", 0))
		P2PNetwork.host_deck_profile = opponent_profile
		P2PNetwork.guest_deck_profile = my_profile
		P2PNetwork.local_player_id = 1
	else:
		P2PNetwork.shared_random_seed = randi()
		P2PNetwork.host_deck_profile = my_profile
		P2PNetwork.guest_deck_profile = opponent_profile
		P2PNetwork.local_player_id = 0

	_on_log_updated("相手のデッキ（%s）を受信・検証完了した 準備完了を送信する" % str(opponent_profile.get("name", "相手デッキ")))
	is_deck_handshake_done = true
	is_local_ready = true
	P2PNetwork.send_message({"action": "ready_to_play"})
	_check_start_match()


func _check_start_match() -> void:
	if is_local_ready and is_opponent_ready:
		_on_log_updated("双方の準備完了 対局画面へ遷移する...")
		P2PNetwork.is_p2p_match = true
		get_tree().change_scene_to_file(GAME_SCENE_PATH)


func _on_connection_closed() -> void:
	_on_log_updated("通信が切断された")


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
	# Web環境では長押しメニューが出にくいためwindow.promptで入力を受け取る
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


