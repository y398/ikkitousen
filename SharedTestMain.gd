
extends Node2D

const CardDatabase = preload("res://CardDatabase.gd")
const MovementRules = preload("res://MovementRules.gd")
const WallRules = preload("res://WallRules.gd")
const SummonRules = preload("res://SummonRules.gd")
const TrapRules = preload("res://TrapRules.gd")
const AttackRules = preload("res://AttackRules.gd")
const CardEffects = preload("res://CardEffects.gd")
const PromotionChoiceDialog = preload("res://PromotionChoiceDialog.gd")
const CheckRules = preload("res://CheckRules.gd")
const DeckRules = preload("res://DeckRules.gd")
const DeckLibrary = preload("res://DeckLibrary.gd")

const BOARD_SIZE: int = 9
# 段番号の漢数字表記
const RANK_KANJI: Array[String] = [
	"一", "二", "三", "四", "五",
	"六", "七", "八", "九"
]
const CELL_SIZE: float = 56.0
const BOARD_ORIGIN: Vector2 = Vector2(80.0, 130.0)
# 手札カードの表示設定
const HAND_CARD_SIZE: Vector2 = Vector2(120.0, 168.0)
const HAND_CARD_GAP: float = 8.0
const HAND_CARD_ORIGIN: Vector2 = Vector2(604.0, 155.0)
const USE_TEST_SETUP: bool = false

# 画面共有テスト専用設定：起動時に自分が担当する陣営を選択する。
const SHARED_TEST_MODE: bool = true
var local_test_player: int = 0
var side_selection_complete: bool = false
var side_selection_layer: CanvasLayer
var deck_library: Dictionary = {}
var self_deck_selector: OptionButton
var opponent_deck_selector: OptionButton
var deck_selection_status_label: Label
var side_choice_buttons: Array[Button] = []

var pieces: Dictionary = {}
var hands: Array = [[], []]
var decks: Array = [[], []]
# 墓地に送られた駒を記録する（手札には戻さない）。
var graveyard: Array[Dictionary] = []
var card_texture_cache: Dictionary = {}
# 旗本などの公開情報を盤面上にも表示する。
var public_notice: String = ""

# 馬防柵の配置途中のマス
var pending_wall_square: Vector2i = Vector2i(-1, -1)

# 壁を個別に識別する番号（破壊処理で使用）
var next_wall_id: int = 1

# 動作確認用の仮デッキ。正式なカード構成ではありません。
const TEST_DECK: Array[String] = [
	"歩", "歩",
	"香", "香",
	"桂", "桂",
	"銀", "銀",
	"金", "金",
	"角", "角",
	"飛", "飛",
	"竹束", "竹束",
	"落とし穴", "落とし穴",
	"馬防柵", "馬防柵"
]
# 初期成デッキの構成（各プレイヤー5枚）
# 成デッキの構成を変える場合は、この配列を編集する
const INITIAL_PROMOTION_DECK_NAMES: Array[String] = [
	"と金", "成香", "成桂", "馬", "龍"
]

var promotion_decks: Array = [[], []]
# 保存デッキが有効な場合、対局で使う成デッキ名をここに保持する。
var active_promotion_deck_names_by_player: Array = [[], []]

# 成るかどうかの確認ダイアログ
var promotion_dialog: PromotionChoiceDialog

# 成りの判断待ちの駒とカード
var pending_promotion_square: Vector2i = Vector2i(-1, -1)
var pending_promotion_card_name: String = ""
var pending_promotion_card_names: Array[String] = []





var selected_square: Vector2i = Vector2i(-1, -1)
var current_player: int = 0
# 各プレイヤーの現在コストと備蓄
var costs: Array[int] = [0, 0]
var reserves: Array[int] = [0, 0]
var turn_counts: Array[int] = [0, 0]
var selected_hand_index: int = -1
var has_summoned_soldier: Array[bool] = [false, false]
var has_summoned_wall: Array[bool] = [false, false]
var has_summoned_trap: Array[bool] = [false, false]
var game_over: bool = false
var winner: int = -1
# 現在の手番ですでに移動したか
var has_moved_this_turn: bool = false
# 手札上限超過による破棄中か
var discard_mode: bool = false
# 画面共有テストで破棄するカードを二度入力して確認するための番号
var pending_discard_hand_number: int = 0
# 初期手札の配布中に中途半端なコスト情報を出力しないためのフラグ
var game_initialized: bool = false

# 新しい罠（伏兵・石落とし）の発動待ち状態。
var pending_special_trap_waiting_for_target: bool = false
var pending_special_trap_effect: String = ""
var pending_special_trap_mode: String = ""
var pending_special_trap_square: Vector2i = Vector2i(-1, -1)
var pending_special_trap_owner: int = -1
var pending_special_trap_name: String = ""
var pending_special_trap_candidates: Array[Vector2i] = []
var pending_special_trap_automatic: bool = false
var pending_special_trap_move_from: Vector2i = Vector2i(-1, -1)
var pending_special_trap_move_to: Vector2i = Vector2i(-1, -1)
var pending_special_trap_moving_piece: Dictionary = {}
var pending_special_trap_triggered_traps: Array[Vector2i] = []
var pending_special_trap_next_index: int = 0


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	get_window().size = Vector2i(800, 850)
	_create_title_return_button()
	var loaded_library: Dictionary = DeckLibrary.load_library()
	deck_library = loaded_library.get("decks", DeckLibrary.default_decks())
	if not bool(loaded_library.get("valid", false)):
		push_warning(str(loaded_library.get("message", "保存デッキを読み込めませんでした。")))
	_create_side_selection_overlay(str(loaded_library.get("last_selected_deck_id", "deck_1")))
	queue_redraw()


func _initialize_match_from_profiles(startup_players: Array) -> void:
	pieces.clear()
	hands = [[], []]
	decks = [[], []]
	promotion_decks = [[], []]
	graveyard.clear()
	public_notice = ""
	next_wall_id = 1
	pending_wall_square = Vector2i(-1, -1)
	selected_square = Vector2i(-1, -1)
	current_player = 0
	costs = [0, 0]
	reserves = [0, 0]
	turn_counts = [0, 0]
	selected_hand_index = -1
	has_summoned_soldier = [false, false]
	has_summoned_wall = [false, false]
	has_summoned_trap = [false, false]
	game_over = false
	winner = -1
	has_moved_this_turn = false
	discard_mode = false
	pending_discard_hand_number = 0
	game_initialized = false
	pending_special_trap_waiting_for_target = false
	pending_special_trap_effect = ""
	pending_special_trap_mode = ""
	pending_special_trap_square = Vector2i(-1, -1)
	pending_special_trap_owner = -1
	pending_special_trap_name = ""
	pending_special_trap_candidates.clear()
	pending_special_trap_automatic = false
	pending_special_trap_move_from = Vector2i(-1, -1)
	pending_special_trap_move_to = Vector2i(-1, -1)
	pending_special_trap_moving_piece.clear()
	pending_special_trap_triggered_traps.clear()
	pending_special_trap_next_index = 0
	var sente_promotion_names: Array = startup_players[0]["promotion_deck"]
	var gote_promotion_names: Array = startup_players[1]["promotion_deck"]
	active_promotion_deck_names_by_player = [sente_promotion_names.duplicate(), gote_promotion_names.duplicate()]

	# 先手の王
	pieces[Vector2i(9, 5)] = {
		"category": "王",
		"name": "王",
		"movement_type": "king",
		"owner": 0
	}

	# 後手の王
	pieces[Vector2i(1, 5)] = {
		"category": "王",
		"name": "王",
		"movement_type": "king",
		"owner": 1
	}

	# 動作確認用の駒
	if USE_TEST_SETUP:
		# 捕獲テスト用の歩
		pieces[Vector2i(8, 5)] = {
			"category": "兵",
			"name": "歩",
			"movement_type": "pawn",
			"owner": 0
		}

		pieces[Vector2i(7, 5)] = {
			"category": "兵",
			"name": "歩",
			"movement_type": "pawn",
			"owner": 1
		}

		pieces[Vector2i(2, 4)] = {
			"category": "兵",
			"name": "歩",
			"movement_type": "pawn",
			"owner": 1
		}

		# 移動テスト用の仮配置
		pieces[Vector2i(7, 1)] = {
			"name": "香",
			"owner": 0
		}

		pieces[Vector2i(7, 3)] = {
			"name": "桂",
			"owner": 0
		}

		pieces[Vector2i(6, 5)] = {
			"name": "銀",
			"owner": 0
		}

		pieces[Vector2i(7, 7)] = {
			"name": "金",
			"owner": 0
		}

		pieces[Vector2i(5, 2)] = {
			"name": "角",
			"owner": 0
		}

		pieces[Vector2i(5, 8)] = {
			"name": "飛",
			"owner": 0
		}
	# 選択されたデッキで山札を作成する。
	for player in range(2):
		var player_profile: Dictionary = startup_players[player]
		for card_name in player_profile["main_deck"]:
			var card: Dictionary = CardDatabase.get_card(str(card_name))
			if card.is_empty():
				push_error("カードデータが見つかりません: " + str(card_name))
				continue
			card["name"] = str(card_name)
			card["owner"] = player
			decks[player].append(card)
		decks[player].shuffle()

	# 初期手札を3枚配る。
	for player in range(2):
		for i in range(3):
			draw_card(player)
	costs[0] = 1
	initialize_promotion_decks()
	initialize_promotion_dialog()
	game_initialized = true


func _get_card_texture(card_name: String) -> Texture2D:
	# 読み込み済みの画像を再利用する
	if card_texture_cache.has(card_name):
		var cached = card_texture_cache[card_name]
		if cached is Texture2D:
			return cached
		return null

	# カードデータに画像パスが指定されていれば優先する
	var card: Dictionary = CardDatabase.get_card(card_name)
	var candidates: Array[String] = []

	var specified_path := str(card.get("image_path", ""))
	if not specified_path.is_empty():
		candidates.append(specified_path)

	# 指定がない場合は、カード名と同じファイル名を探す
	for extension in ["jpg", "jpeg", "png", "webp"]:
		candidates.append(
			"res://assets/cards/%s.%s" % [card_name, extension]
		)

	# 存在する画像を読み込む
	for image_path in candidates:
		if not ResourceLoader.exists(image_path):
			continue

		var loaded_resource: Resource = load(image_path)

		if loaded_resource is Texture2D:
			var texture := loaded_resource as Texture2D
			card_texture_cache[card_name] = texture
			return texture

	# 見つからなかった場合もキャッシュし、毎回探し直さない。
	# 画面共有テスト中にカード名を出力欄へ漏らさないため、ここではログを出さない。
	card_texture_cache[card_name] = null
	return null


func _draw_card_image(
	texture: Texture2D,
	target_rect: Rect2
) -> void:
	var image_size: Vector2 = texture.get_size()
	
	if image_size.x <= 0 or image_size.y <= 0:
		return
	
	var scale_factor: float = min(
		target_rect.size.x / image_size.x,
		target_rect.size.y / image_size.y
	)
	
	var drawn_size: Vector2 = image_size * scale_factor
	var drawn_position: Vector2 = target_rect.position + (
		target_rect.size - drawn_size
	) / 2.0
	
	draw_texture_rect(
		texture,
		Rect2(drawn_position, drawn_size),
		false
	)

func _create_title_return_button() -> void:
	# 描画より手前に表示するUIレイヤー
	var ui_layer := CanvasLayer.new()
	ui_layer.layer = 10
	add_child(ui_layer)

	# ボタン本体
	var button := Button.new()
	button.text = "タイトルへ戻る"
	button.tooltip_text = "タイトル画面に戻ります"
	button.custom_minimum_size = Vector2(150, 42)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 15)

	# 画面左上に固定
	button.anchor_left = 0.0
	button.anchor_right = 0.0
	button.anchor_top = 0.0
	button.anchor_bottom = 0.0
	button.offset_left = 16.0
	button.offset_right = 166.0
	button.offset_top = 8.0
	button.offset_bottom = 50.0

	# ボタンの色
	var normal_style := StyleBoxFlat.new()
	normal_style.bg_color = Color(0.10, 0.13, 0.19)
	normal_style.border_color = Color(0.84, 0.65, 0.30)
	normal_style.set_border_width_all(1)
	normal_style.set_corner_radius_all(6)
	button.add_theme_stylebox_override("normal", normal_style)

	var hover_style := StyleBoxFlat.new()
	hover_style.bg_color = Color(0.16, 0.20, 0.28)
	hover_style.border_color = Color(1.0, 0.78, 0.40)
	hover_style.set_border_width_all(2)
	hover_style.set_corner_radius_all(6)
	button.add_theme_stylebox_override("hover", hover_style)

	button.add_theme_color_override(
		"font_color",
		Color(0.95, 0.96, 0.99)
	)

	ui_layer.add_child(button)
	button.pressed.connect(_return_to_title)


func _return_to_title() -> void:
	var title_path := "res://TitleScreen.tscn"

	if not ResourceLoader.exists(title_path):
		push_error(
			"タイトル画面が見つかりません: " + title_path
		)
		return

	var error := get_tree().change_scene_to_file(title_path)

	if error != OK:
		push_error(
			"タイトル画面への移動に失敗しました。エラーコード: "
			+ str(error)
		)

func _side_label(player: int) -> String:
	return "先手" if player == 0 else "後手"


func _guest_test_player() -> int:
	return 1 - local_test_player


func _create_side_selection_overlay(preferred_self_deck_id: String) -> void:
	# デッキと担当陣営の両方を決めてから対局を初期化する。
	side_selection_layer = CanvasLayer.new()
	side_selection_layer.layer = 100
	add_child(side_selection_layer)

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.025, 0.035, 0.06, 0.96)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	side_selection_layer.add_child(backdrop)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_STOP
	backdrop.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(500, 450)
	center.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(margin)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 11)
	margin.add_child(layout)

	var title := Label.new()
	title.text = "使用デッキと担当陣営を選択"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	layout.add_child(title)
	var explanation := Label.new()
	explanation.text = "自分と通話相手に使うデッキを選び、その後、自分が先手か後手かを選択してください。"
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	explanation.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layout.add_child(explanation)

	self_deck_selector = _make_shared_deck_selector_row(layout, "自分のデッキ", preferred_self_deck_id)
	var ids: Array[String] = DeckLibrary.ordered_deck_ids(deck_library)
	var preferred_opponent_id := "deck_2" if ids.has("deck_2") else preferred_self_deck_id
	opponent_deck_selector = _make_shared_deck_selector_row(layout, "相手のデッキ", preferred_opponent_id)

	deck_selection_status_label = Label.new()
	deck_selection_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	deck_selection_status_label.add_theme_font_size_override("font_size", 12)
	layout.add_child(deck_selection_status_label)

	var sente_button := Button.new()
	sente_button.text = "自分が先手で遊ぶ"
	sente_button.custom_minimum_size = Vector2(0, 44)
	sente_button.pressed.connect(_on_local_side_selected.bind(0))
	layout.add_child(sente_button)
	side_choice_buttons.append(sente_button)

	var gote_button := Button.new()
	gote_button.text = "自分が後手で遊ぶ"
	gote_button.custom_minimum_size = Vector2(0, 44)
	gote_button.pressed.connect(_on_local_side_selected.bind(1))
	layout.add_child(gote_button)
	side_choice_buttons.append(gote_button)
	_on_shared_deck_selection_changed(0)


func _make_shared_deck_selector_row(parent: VBoxContainer, label_text: String, preferred_id: String) -> OptionButton:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(95, 0)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	var selector := OptionButton.new()
	selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for deck_id in DeckLibrary.ordered_deck_ids(deck_library):
		var profile: Dictionary = deck_library[deck_id]
		selector.add_item(str(profile.get("name", deck_id)))
		selector.set_item_metadata(selector.item_count - 1, deck_id)
	selector.item_selected.connect(_on_shared_deck_selection_changed)
	row.add_child(selector)
	var selected_index := 0
	for i in range(selector.item_count):
		if str(selector.get_item_metadata(i)) == preferred_id:
			selected_index = i
			break
	if selector.item_count > 0:
		selector.select(selected_index)
	return selector


func _selected_shared_deck_id(selector: OptionButton) -> String:
	if selector == null or selector.item_count <= 0 or selector.selected < 0:
		return ""
	return str(selector.get_item_metadata(selector.selected))


func _on_shared_deck_selection_changed(_index: int) -> void:
	if self_deck_selector == null or opponent_deck_selector == null or deck_selection_status_label == null:
		return
	var messages := PackedStringArray()
	var all_valid := true
	var selected := [self_deck_selector, opponent_deck_selector]
	for i in range(selected.size()):
		var deck_id := _selected_shared_deck_id(selected[i])
		var side_label := "自分" if i == 0 else "相手"
		if deck_id.is_empty() or not deck_library.has(deck_id):
			all_valid = false
			messages.append("%sのデッキを選択してください。" % side_label)
			continue
		var profile: Dictionary = deck_library[deck_id]
		var validation: Dictionary = DeckLibrary.validate_playable_profile(profile)
		if bool(validation.get("valid", false)):
			messages.append("%s：「%s」使用可能" % [side_label, str(profile.get("name", deck_id))])
		else:
			all_valid = false
			var errors := PackedStringArray()
			for error_message in validation.get("errors", []):
				errors.append(str(error_message))
			messages.append("%s：「%s」%s" % [side_label, str(profile.get("name", deck_id)), "／".join(errors)])
	deck_selection_status_label.text = "\n".join(messages)
	for button in side_choice_buttons:
		button.disabled = not all_valid


func _on_local_side_selected(player: int) -> void:
	var self_id := _selected_shared_deck_id(self_deck_selector)
	var opponent_id := _selected_shared_deck_id(opponent_deck_selector)
	if self_id.is_empty() or opponent_id.is_empty():
		return
	var self_profile: Dictionary = deck_library.get(self_id, {})
	var opponent_profile: Dictionary = deck_library.get(opponent_id, {})
	var self_validation: Dictionary = DeckLibrary.validate_playable_profile(self_profile)
	var opponent_validation: Dictionary = DeckLibrary.validate_playable_profile(opponent_profile)
	if not bool(self_validation.get("valid", false)) or not bool(opponent_validation.get("valid", false)):
		_on_shared_deck_selection_changed(0)
		return

	local_test_player = clampi(player, 0, 1)
	var player_profiles: Array = [{}, {}]
	if local_test_player == 0:
		player_profiles[0] = self_profile.duplicate(true)
		player_profiles[1] = opponent_profile.duplicate(true)
	else:
		player_profiles[0] = opponent_profile.duplicate(true)
		player_profiles[1] = self_profile.duplicate(true)
	_initialize_match_from_profiles(player_profiles)
	side_selection_complete = true
	if is_instance_valid(side_selection_layer):
		side_selection_layer.queue_free()
	side_selection_layer = null
	print("画面共有テスト：あなたは%sです。自分のデッキ：%s／相手のデッキ：%s" % [
		_side_label(local_test_player), str(self_profile.get("name", self_id)), str(opponent_profile.get("name", opponent_id))
	])
	_print_local_hand_and_cost("初期手札")
	queue_redraw()


# 色は担当陣営ではなく、ゲーム上の陣営に固定する。
# 先手の自陣（段七～九）は常に薄い青、後手の自陣（段一～三）は常に薄い赤。
# そのため、画面共有テストで担当陣営を切り替えても色の割り当ては入れ替わらない。
func _territory_tint_for_square(square: Vector2i) -> Color:
	if square.x >= 7:
		return Color(0.22, 0.48, 1.0, 0.17)
	if square.x <= 3:
		return Color(1.0, 0.25, 0.30, 0.17)
	return Color(0.0, 0.0, 0.0, 0.0)


# 画面共有テストでは、相手側を画面手前、自分側を画面奥にする。
# 自分が先手なら盤面を180度回転、自分が後手なら既定の向きを使う。
func _is_board_rotated() -> bool:
	return SHARED_TEST_MODE and local_test_player == 0


# 表示上の行・列から、ゲーム内部の論理座標（段x・筋y）へ変換する。
func _screen_cell_to_square(row: int, col: int) -> Vector2i:
	if _is_board_rotated():
		return Vector2i(BOARD_SIZE - row, col + 1)
	return Vector2i(row + 1, BOARD_SIZE - col)


# 領地マス（2五・8五）を視覚的に示す。
func _draw_territory_markers() -> void:
	var territory_squares: Array[Vector2i] = [
		Vector2i(5, 2),
		Vector2i(5, 8)
	]
	var fill_color := Color(0.94, 0.70, 0.20, 0.20)
	var edge_color := Color(0.68, 0.40, 0.08, 0.90)

	for territory_square in territory_squares:
		var territory_rect: Rect2 = square_rect(territory_square)
		draw_rect(territory_rect, fill_color, true)
		draw_rect(territory_rect, edge_color, false, 2.0)

		# 駒が置かれても判別できるよう、印はマスの右上隅に置く。
		var marker_center: Vector2 = territory_rect.position + Vector2(CELL_SIZE - 10.0, 10.0)
		draw_arc(
			marker_center,
			4.5,
			0.0,
			TAU,
			20,
			edge_color,
			1.8
		)


# 選択中の駒について、実際の移動判定を使って合法候補を集める。
func _get_movement_highlight_squares() -> Array[Vector2i]:
	var result: Array[Vector2i] = []

	if game_over or has_moved_this_turn:
		return result
	if selected_square.x < 1 or not pieces.has(selected_square):
		return result

	var moving_piece: Dictionary = pieces[selected_square]
	if int(moving_piece.get("owner", -1)) != current_player:
		return result
	if str(moving_piece.get("category", "")) == "壁":
		return result

	for rank in range(1, BOARD_SIZE + 1):
		for file_number in range(1, BOARD_SIZE + 1):
			var target_square := Vector2i(rank, file_number)
			if can_move(selected_square, target_square):
				result.append(target_square)

	return result


# 同じ筋に自分の未成の歩があるか確認（二歩防止）。
func _has_unpromoted_pawn_on_file(player: int, file_number: int) -> bool:
	for existing_square in pieces:
		var existing_piece: Dictionary = pieces[existing_square]
		if int(existing_piece.get("owner", -1)) != player:
			continue
		if str(existing_piece.get("category", "")) != "兵":
			continue
		if str(existing_piece.get("name", "")) != "歩":
			continue
		if existing_square.y == file_number:
			return true
	return false


# 選択カードについて、召喚処理と同じルールで配置可能マスを集める。
# 領地マスかどうか（座標は Vector2i(段, 筋)）
func _is_territory_square(square: Vector2i) -> bool:
	return square == Vector2i(5, 2) or square == Vector2i(5, 8)


# 領地への兵の召喚は、召喚制限ラインがその段まで到達している場合のみ許可する。
# 先手は小さい段番号ほど前進、後手は大きい段番号ほど前進。
# 最前線と同じ段も「ライン内」として扱う。
func _territory_is_within_summon_line(square: Vector2i, player: int) -> bool:
	if not _is_territory_square(square):
		return true

	var front_rank: int = BOARD_SIZE if player == 0 else 1
	var found_owned_piece := false

	for own_piece_square in pieces:
		var own_piece: Dictionary = pieces[own_piece_square]
		if int(own_piece.get("owner", -1)) != player:
			continue

		found_owned_piece = true
		if player == 0:
			front_rank = mini(front_rank, own_piece_square.x)
		else:
			front_rank = maxi(front_rank, own_piece_square.x)

	if not found_owned_piece:
		return false

	if player == 0:
		return front_rank <= square.x
	return front_rank >= square.x


func _get_summon_highlight_squares() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if game_over or discard_mode:
		return result
	if selected_hand_index < 0 or selected_hand_index >= hands[current_player].size():
		return result

	var selected_card: Dictionary = hands[current_player][selected_hand_index]
	if not is_summonable_piece(selected_card):
		return result

	var category: String = str(selected_card.get("category", ""))
	var card_name: String = str(selected_card.get("name", ""))
	var needed_cost: int = int(selected_card.get("cost", 0))
	if costs[current_player] + reserves[current_player] < needed_cost:
		return result

	match category:
		"兵":
			if has_summoned_soldier[current_player]:
				return result
		"壁":
			if has_summoned_wall[current_player]:
				return result
		"罠":
			if has_summoned_trap[current_player]:
				return result
		_:
			return result

	var wall_length: int = int(selected_card.get("wall_length", 1))
	if category == "壁" and wall_length == 2 and pending_wall_square.x >= 1:
		if not WallRules.is_valid_wall_square(pieces, pending_wall_square, current_player):
			return result

	for rank in range(1, BOARD_SIZE + 1):
		for file_number in range(1, BOARD_SIZE + 1):
			var target_square := Vector2i(rank, file_number)
			if pieces.has(target_square):
				continue

			# 領地は常時召喚可能ではない。兵だけ、召喚制限ライン到達後に候補とする。
			if category == "兵" and _is_territory_square(target_square):
				if not _territory_is_within_summon_line(target_square, current_player):
					continue

			if category == "壁":
				if wall_length == 2 and pending_wall_square.x >= 1:
					var distance: int = absi(target_square.x - pending_wall_square.x) + absi(target_square.y - pending_wall_square.y)
					if distance != 1:
						continue
				if not WallRules.is_valid_wall_square(pieces, target_square, current_player):
					continue
			else:
				var placement_error: String = SummonRules.get_non_wall_placement_error(
					pieces,
					target_square,
					current_player,
					category
				)
				if placement_error != "":
					continue
				if category == "兵" and card_name == "歩":
					if _has_unpromoted_pawn_on_file(current_player, target_square.y):
						continue

			result.append(target_square)

	return result


# 召喚可能マスを薄い緑色で強調する。
func _draw_summon_highlights() -> void:
	for target_square in _get_summon_highlight_squares():
		var target_rect: Rect2 = square_rect(target_square)
		draw_rect(target_rect, Color(0.18, 0.78, 0.34, 0.23), true)
		draw_rect(target_rect, Color(0.12, 0.58, 0.24, 0.78), false, 1.5)


# 移動先は赤い点、駒を捕獲できるマスは赤い輪で示す。
func _draw_movement_highlights() -> void:
	for target_square in _get_movement_highlight_squares():
		var target_center: Vector2 = square_rect(target_square).get_center()
		if pieces.has(target_square):
			draw_arc(
				target_center,
				12.0,
				0.0,
				TAU,
				24,
				Color(0.92, 0.10, 0.14, 0.95),
				2.5
			)
		else:
			draw_circle(target_center, 4.0, Color(0.92, 0.10, 0.14, 0.88))

func _get_archer_attack_target_square(archer_square: Vector2i) -> Vector2i:
	if game_over or has_moved_this_turn or not pieces.has(archer_square):
		return Vector2i(-1, -1)
	var archer: Dictionary = pieces[archer_square]
	var attack_cost := int(archer.get("attack_cost", 1))
	if costs[current_player] + reserves[current_player] < attack_cost:
		return Vector2i(-1, -1)
	return AttackRules.get_archer_target_square(
		pieces,
		archer_square,
		current_player,
		BOARD_SIZE
	)

func _draw_archer_attack_highlight() -> void:
	if selected_square.x < 1:
		return
	var target_square := _get_archer_attack_target_square(selected_square)
	if target_square.x < 1:
		return
	var target_rect := square_rect(target_square)
	draw_rect(target_rect, Color(1.0, 0.18, 0.10, 0.20), true)
	draw_rect(target_rect, Color(1.0, 0.20, 0.12, 0.95), false, 3.0)

func _draw() -> void:
	# 背景を濃い紺色にする
	draw_rect(
		Rect2(Vector2.ZERO, get_viewport_rect().size),
		Color(0.075, 0.09, 0.14),
		true
	)

	# 手番・勝敗表示
	var status: String = (
		"先手の手番" if current_player == 0 else "後手の手番"
	)

	if game_over:
		status = "先手の勝利！" if winner == 0 else "後手の勝利！"

	draw_string(
		ThemeDB.fallback_font,
		Vector2(180, 35),
		status,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		25,
		Color(0.95, 0.97, 1.0)
	)


	# 王手表示
	if not game_over and CheckRules.is_in_check(
		pieces,
		current_player
	):
		draw_string(
			ThemeDB.fallback_font,
			Vector2(180, 66),
			"王手！",
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			22,
			Color(1.0, 0.35, 0.35)
		)

	# 山札・コスト情報
	draw_string(
		ThemeDB.fallback_font,
		Vector2(340, 45),
		"山札：先手 %d枚 / 後手 %d枚"
		% [decks[0].size(), decks[1].size()],
		HORIZONTAL_ALIGNMENT_LEFT,
		450,
		35,
		Color(0.90, 0.93, 0.98)
	)

	draw_string(
		ThemeDB.fallback_font,
		Vector2(340, 80),
		"コスト：先手 %d（備蓄%d）/ 後手 %d（備蓄%d）"
		% [costs[0], reserves[0], costs[1], reserves[1]],
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		35,
		Color(0.90, 0.93, 0.98)
	)


	# 旗本の公開情報など、両プレイヤーに見せる通知。
	if not public_notice.is_empty():
		draw_string(
			ThemeDB.fallback_font,
			Vector2(604, 116),
			public_notice,
			HORIZONTAL_ALIGNMENT_LEFT,
			520,
			15,
			Color(1.0, 0.86, 0.48)
		)

	# 盤面
	for row in range(BOARD_SIZE):
		for col in range(BOARD_SIZE):
			var rect := Rect2(
				BOARD_ORIGIN + Vector2(
					col * CELL_SIZE,
					row * CELL_SIZE
				),
				Vector2(CELL_SIZE, CELL_SIZE)
			)

			draw_rect(rect, Color(0.94, 0.90, 0.79), true)
			var logical_square: Vector2i = _screen_cell_to_square(row, col)
			var zone_tint: Color = _territory_tint_for_square(logical_square)
			if zone_tint.a > 0.0:
				draw_rect(rect, zone_tint, true)
			draw_rect(rect, Color(0.28, 0.31, 0.36), false, 1.0)

	# 領地（2五・8五）を明示する。
	_draw_territory_markers()

	# 筋の番号
	for col in range(BOARD_SIZE):
		draw_string(
			ThemeDB.fallback_font,
			BOARD_ORIGIN + Vector2(
				col * CELL_SIZE + 25,
				-12
			),
			str(_screen_cell_to_square(0, col).y),
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			18,
			Color(0.92, 0.94, 0.98)
		)


	# 段の番号（漢数字）
	for row in range(BOARD_SIZE):
		draw_string(
			ThemeDB.fallback_font,
			BOARD_ORIGIN + Vector2(
				-25,
				row * CELL_SIZE + 36
			),
			RANK_KANJI[_screen_cell_to_square(row, 0).x - 1],
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			18,
			Color(0.92, 0.94, 0.98)
		)

	# 選択中のマス
	if selected_square.x >= 1:
		draw_rect(
			square_rect(selected_square),
			Color(0.20, 0.55, 1.0, 0.40),
			true
		)

	# 馬防柵の配置途中のマス
	if pending_wall_square.x >= 1:
		draw_rect(
			square_rect(pending_wall_square),
			Color(1.0, 0.60, 0.10, 0.50),
			true
		)

	# 選択したカードを配置できる空きマスを表示する。
	_draw_summon_highlights()

	# 駒
	for square in pieces:
		var piece: Dictionary = pieces[square]
		var center: Vector2 = square_rect(square).get_center()

		var is_hidden_trap: bool = (
			str(piece.get("category", "")) == "罠"
			and bool(piece.get("is_face_down", false))
		)

		var piece_color: Color = Color(0.12, 0.32, 0.72)

		if int(piece.get("owner", -1)) == 1:
			piece_color = Color(0.72, 0.18, 0.20)

		var display_name: String = str(
			piece.get("name", "?")
		)

		if is_hidden_trap:
			piece_color = Color(0.28, 0.30, 0.34)
			display_name = "伏"

		draw_circle(center, 20.0, piece_color)

		draw_string(
			ThemeDB.fallback_font,
			center + Vector2(-12, 7),
			display_name,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			16,
			Color.WHITE
		)

	# 選択駒の移動可能マスを駒の上に重ねて表示する。
	_draw_movement_highlights()
	_draw_archer_attack_highlight()
	_draw_special_trap_target_highlights()

	# 手札表示
	# 画面共有テストでは通話相手の手札だけを常時表示する。
	var hand_display_player: int = (
		_guest_test_player() if SHARED_TEST_MODE else current_player
	)
	var current_hand: Array = hands[hand_display_player]

	var hand_title: String
	if SHARED_TEST_MODE:
		var guest_side_name: String = _side_label(_guest_test_player())
		hand_title = "通話相手（%s）の手札（%d/5）" % [guest_side_name, current_hand.size()]
		if discard_mode and current_player == _guest_test_player():
			hand_title = "通話相手の手札超過：同じ番号を2回入力して破棄（%d枚）" % current_hand.size()
		elif discard_mode and current_player == local_test_player:
			hand_title = "あなたの手札超過：出力欄の番号を2回入力して破棄（%d枚）" % hands[local_test_player].size()
	else:
		hand_title = "%sの手札（%d/5）" % [
			"先手" if current_player == 0 else "後手",
			current_hand.size()
		]
		if discard_mode:
			hand_title = "手札超過：破棄するカードをクリックしてください（%d枚）" % [
				hands[current_player].size()
			]

	draw_string(
		ThemeDB.fallback_font,
		Vector2(604, 135),
		hand_title,
		HORIZONTAL_ALIGNMENT_LEFT,
		540,
		18,
		Color(1.0, 0.45, 0.40) if discard_mode else Color(0.95, 0.97, 1.0)
	)

	if current_hand.is_empty():
		draw_string(
			ThemeDB.fallback_font,
			Vector2(614, 200),
			"通話相手の手札がありません" if SHARED_TEST_MODE else "手札がありません",
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			18,
			Color(0.82, 0.86, 0.92)
		)

	# 手札をカード状に描画
	for hand_index in range(current_hand.size()):
		var card: Dictionary = current_hand[hand_index]
		var card_rect: Rect2 = hand_card_rect(hand_index)
		var is_selected: bool = (
			current_player == hand_display_player
			and selected_hand_index == hand_index
		)

		var border_color: Color = (
			Color(1.0, 0.68, 0.12)
			if is_selected
			else Color(0.34, 0.39, 0.48)
		)

		var card_name_for_texture: String = str(card.get("name", ""))
		var card_texture: Texture2D = _get_card_texture(card_name_for_texture)

		if card_texture != null:
			draw_rect(card_rect, Color(0.96, 0.95, 0.88), true)
			_draw_card_image(card_texture, card_rect)
			draw_rect(card_rect, border_color, false, 4.0 if is_selected else 2.0)
			continue

		# 画像がない場合は従来の文字カードを表示する。
		var card_background: Color = Color(0.96, 0.95, 0.88)
		if is_selected:
			card_background = Color(1.0, 0.95, 0.72)

		draw_rect(card_rect, card_background, true)
		draw_rect(card_rect, border_color, false, 4.0 if is_selected else 2.0)

		var category: String = str(card.get("category", ""))
		var category_color: Color = Color(0.16, 0.35, 0.72)
		if category == "壁":
			category_color = Color(0.48, 0.32, 0.18)
		elif category == "罠":
			category_color = Color(0.62, 0.20, 0.22)

		draw_rect(
			Rect2(card_rect.position, Vector2(HAND_CARD_SIZE.x, 7)),
			category_color,
			true
		)
		draw_string(
			ThemeDB.fallback_font,
			card_rect.position + Vector2(9, 30),
			category,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			16,
			Color(0.27, 0.30, 0.36)
		)
		draw_string(
			ThemeDB.fallback_font,
			card_rect.position + Vector2(6, 72),
			card_name_for_texture,
			HORIZONTAL_ALIGNMENT_CENTER,
			HAND_CARD_SIZE.x - 12,
			22 if card_name_for_texture.length() <= 2 else 18,
			Color(0.09, 0.12, 0.18)
		)
		draw_rect(
			Rect2(
				card_rect.position + Vector2(HAND_CARD_SIZE.x - 40, 12),
				Vector2(30, 25)
			),
			Color(0.12, 0.16, 0.23),
			true
		)
		draw_string(
			ThemeDB.fallback_font,
			card_rect.position + Vector2(HAND_CARD_SIZE.x - 35, 30),
			str(card.get("cost", 0)),
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			16,
			Color.WHITE
		)
		draw_string(
			ThemeDB.fallback_font,
			card_rect.position + Vector2(9, 118),
			"コスト: %d" % int(card.get("cost", 0)),
			HORIZONTAL_ALIGNMENT_LEFT,
			HAND_CARD_SIZE.x - 14,
			14,
			Color(0.27, 0.30, 0.36)
		)

	# 画面共有テストでは、通話相手の成デッキだけをゲーム画面に表示する。
	# 自分の成デッキはここに表示せず、F2で出力欄にだけ表示する。
	if SHARED_TEST_MODE:
		draw_string(
			ThemeDB.fallback_font,
			Vector2(604, 550),
			"通話相手（%s）の成デッキ：" % _side_label(_guest_test_player()) + promotion_deck_summary(_guest_test_player()),
			HORIZONTAL_ALIGNMENT_LEFT,
			540,
			14,
			Color(0.90, 0.93, 0.98)
		)
	else:
		draw_string(
			ThemeDB.fallback_font,
			Vector2(604, 550),
			"先手の成デッキ：" + promotion_deck_summary(0),
			HORIZONTAL_ALIGNMENT_LEFT,
			540,
			14,
			Color(0.90, 0.93, 0.98)
		)

		draw_string(
			ThemeDB.fallback_font,
			Vector2(604, 570),
			"後手の成デッキ：" + promotion_deck_summary(1),
			HORIZONTAL_ALIGNMENT_LEFT,
			540,
			14,
			Color(0.90, 0.93, 0.98)
		)
	draw_string(
		ThemeDB.fallback_font,
		Vector2(950, 550),
		"操作方法",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		18,
		Color(0.95, 0.97, 1.0)
	)
	
	draw_string(
		ThemeDB.fallback_font,
		Vector2(950, 580),
		"数字キー：手札を選択" if SHARED_TEST_MODE else "カードをクリック：選択",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		14,
		Color(0.82, 0.86, 0.92)
	)
	
	draw_string(
		ThemeDB.fallback_font,
		Vector2(950, 605),
		"盤面をクリック：召喚・移動",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		14,
		Color(0.82, 0.86, 0.92)
	)
	
	draw_string(
		ThemeDB.fallback_font,
		Vector2(950, 630),
		"F2：自分の成デッキを出力欄に表示" if SHARED_TEST_MODE else "Esc：取消 / Space：手番終了",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		14,
		Color(0.82, 0.86, 0.92)
	)

	draw_string(
		ThemeDB.fallback_font,
		Vector2(950, 655),
		"F：特殊罠起動 / A：弓手攻撃",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		14,
		Color(0.82, 0.86, 0.92)
	)
	
func square_rect(square: Vector2i) -> Rect2:
	var col: int
	var row: int
	if _is_board_rotated():
		col = square.y - 1
		row = BOARD_SIZE - square.x
	else:
		col = BOARD_SIZE - square.y
		row = square.x - 1

	return Rect2(
		BOARD_ORIGIN + Vector2(col * CELL_SIZE, row * CELL_SIZE),
		Vector2(CELL_SIZE, CELL_SIZE)
	)
	# 手札の各カードが表示される位置を取得する

# 手札カードの位置を取得する（1行5枚）
func hand_card_rect(hand_index: int) -> Rect2:
	const CARDS_PER_ROW := 4

	# 0～3枚目は1段目、4枚目以降は2段目
	var column: int = hand_index % CARDS_PER_ROW
	var row: int = int(hand_index / CARDS_PER_ROW)

	var card_position := Vector2(
		604.0 + column * (HAND_CARD_SIZE.x + HAND_CARD_GAP),
		155.0 + row * (HAND_CARD_SIZE.y + HAND_CARD_GAP)
	)

	return Rect2(card_position, HAND_CARD_SIZE)


func recover_cost(player: int) -> void:
	turn_counts[player] += 1

	var recovery: int = 2

	# 領地マス（2五・8五）にいる自分の兵・王1体につき+1
	for square in pieces:
		var piece: Dictionary = pieces[square]

		if int(piece.get("owner", -1)) != player:
			continue

		var category: String = str(
			piece.get("category", "")
		)

		# 兵と王を集計対象にする
		if category != "兵" and category != "王" and category != "成":
			continue

		if (
			square == Vector2i(5, 2)
			or square == Vector2i(5, 8)
		):
			recovery += 1

	# 王手を受けている側には王手ボーナス+1
	if CheckRules.is_in_check(pieces, player):
		recovery += 1
		print(
			"%sは王手ボーナスを獲得しました。"
			% ("先手" if player == 0 else "後手")
		)

	# 今回のターンで使えるコストを設定
	costs[player] = recovery

	print("%sのコスト：%d（備蓄%d）" % [
		"先手" if player == 0 else "後手",
		costs[player],
		reserves[player]
	])
# ターン終了時に余ったコストを備蓄へ移す
func bank_unused_cost(player: int) -> void:
	var unused: int = costs[player]
	var capacity: int = maxi(0, 3 - reserves[player])
	var banked: int = mini(unused, capacity)
	var discarded: int = unused - banked

	reserves[player] += banked
	costs[player] = 0

	if banked > 0:
		print("%sが未使用コスト%dを備蓄しました。" % [
			"先手" if player == 0 else "後手",
			banked
		])

	if discarded > 0:
		print("備蓄上限によりコスト%dを破棄しました。" % discarded)


# 現在のコストを優先して支払う。不足分は備蓄から支払う
func spend_cost(player: int, amount: int) -> bool:
	if amount < 0:
		return false

	if costs[player] + reserves[player] < amount:
		return false

	var current_payment: int = mini(costs[player], amount)
	costs[player] -= current_payment
	reserves[player] -= amount - current_payment

	return true
	
	# 現在の手番を終了し、相手の手番へ移る
# 手番終了処理
func end_turn() -> void:
	# 手札が5枚を超えている場合は、先に破棄する
	if hands[current_player].size() > 5:
		discard_mode = true
		pending_discard_hand_number = 0
		selected_hand_index = -1
		selected_square = Vector2i(-1, -1)
		pending_wall_square = Vector2i(-1, -1)

		print(
			"手札が上限を超えています。"
			+ "破棄するカードをクリックしてください。"
		)

		queue_redraw()
		return

	_complete_end_turn()


# 実際に手番を終了する処理
func _complete_end_turn() -> void:
	discard_mode = false
	pending_discard_hand_number = 0

	# 現在のプレイヤーの未使用コストを備蓄へ移す
	bank_unused_cost(current_player)

	# 選択状態を解除
	selected_hand_index = -1
	selected_square = Vector2i(-1, -1)
	pending_wall_square = Vector2i(-1, -1)

	# 相手に手番を渡す
	has_moved_this_turn = false
	current_player = 1 - current_player

	# 新しい手番の召喚回数をリセット
	has_summoned_soldier[current_player] = false
	has_summoned_wall[current_player] = false
	has_summoned_trap[current_player] = false

	# 次のプレイヤーのコスト回復とドロー
	recover_cost(current_player)
	draw_card(current_player)

	queue_redraw()
func draw_card(player: int) -> void:
	if decks[player].is_empty():
		print("%sの山札が空です。" % ("先手" if player == 0 else "後手"))
		if SHARED_TEST_MODE and player == local_test_player and game_initialized:
			_print_local_hand_and_cost("山札切れ")
		return

	var card: Dictionary = decks[player].pop_back()
	hands[player].append(card)

	if SHARED_TEST_MODE:
		# 対局開始前の初期配布ではログを出さず、陣営選択後から通知する。
		if game_initialized and side_selection_complete:
			if player == local_test_player:
				# 自分のドロー後は、自分の手札とコストだけを出力する。
				_print_local_hand_and_cost("ドロー後")
			else:
				# 相手の引いたカード名は、出力欄へ表示しない。
				print("通話相手（%s）がカードを1枚引きました。" % _side_label(player))
	else:
		print(
			"%sが%sを引きました。"
			% [
				"先手" if player == 0 else "後手",
				card["name"]
			]
		)


# 初期手札配布後と、自分のドロー／カード消費後にだけ出す。
# 相手の手札や成デッキは出力しない。
func _print_local_hand_and_cost(reason: String) -> void:
	if not SHARED_TEST_MODE:
		return

	print("")
	print("========== あなた（%s）：%s ==========" % [_side_label(local_test_player), reason])
	print("【手札 %d/5】" % hands[local_test_player].size())
	if hands[local_test_player].is_empty():
		print("手札はありません。")
	else:
		for i in range(hands[local_test_player].size()):
			var card: Dictionary = hands[local_test_player][i]
			print(
				"%d: %s（召喚コスト%d／デッキコスト%d）"
				% [
					i + 1,
					str(card.get("name", "?")),
					int(card.get("cost", 0)),
					int(card.get("deckcost", 0))
				]
			)
	print("【コスト】現在コスト%d／備蓄%d" % [costs[local_test_player], reserves[local_test_player]])
	print("手札選択：数字キー1～9、0は10枚目。破棄は同じ番号を2回入力。")
	print("================================================")


# F2で表示するのは、選択したローカル側の成デッキだけ。
# 手札・コストはF2には含めず、ドロー時の出力を使う。
func _print_local_promotion_deck() -> void:
	if not SHARED_TEST_MODE:
		return

	print("")
	print("========== あなた（%s）の成デッキ ==========" % _side_label(local_test_player))
	if promotion_decks[local_test_player].is_empty():
		print("成デッキはありません。")
	else:
		for i in range(promotion_decks[local_test_player].size()):
			var promotion_card: Dictionary = promotion_decks[local_test_player][i]
			print("%d: %s" % [i + 1, str(promotion_card.get("name", "?"))])
	print("F2：自分の成デッキを再表示。")
	print("============================================")


func _hand_number_from_key(keycode: Key) -> int:
	match keycode:
		KEY_1, KEY_KP_1:
			return 1
		KEY_2, KEY_KP_2:
			return 2
		KEY_3, KEY_KP_3:
			return 3
		KEY_4, KEY_KP_4:
			return 4
		KEY_5, KEY_KP_5:
			return 5
		KEY_6, KEY_KP_6:
			return 6
		KEY_7, KEY_KP_7:
			return 7
		KEY_8, KEY_KP_8:
			return 8
		KEY_9, KEY_KP_9:
			return 9
		KEY_0, KEY_KP_0:
			return 10
		_:
			return 0


func _select_current_hand_by_number(hand_number: int) -> void:
	var hand_index: int = hand_number - 1
	var current_hand: Array = hands[current_player]

	if hand_index < 0 or hand_index >= current_hand.size():
		print("手札番号%dにカードがありません。" % hand_number)
		if discard_mode:
			pending_discard_hand_number = 0
		return

	if discard_mode:
		# 1回目は破棄候補を指定するだけ。2回目に同じ番号を入力すると破棄する。
		if pending_discard_hand_number != hand_number:
			pending_discard_hand_number = hand_number
			selected_hand_index = hand_index
			print(
				"手札番号%dを破棄候補にしました。確定するには同じ数字をもう一度入力してください。"
				% hand_number
			)
			queue_redraw()
			return

		current_hand.remove_at(hand_index)
		selected_hand_index = -1
		pending_discard_hand_number = 0

		if current_player == local_test_player:
			print("あなたは手札番号%dを破棄しました。" % hand_number)
			_print_local_hand_and_cost("破棄後")
		else:
			print("通話相手が手札番号%dのカードを破棄しました。" % hand_number)

		if current_hand.size() <= 5:
			_complete_end_turn()
		else:
			print("手札が6枚以上あります。さらに破棄するカード番号を2回入力してください。")
			queue_redraw()
		return

	# 通常時は入力した番号のカードを選択／選択解除する。
	if selected_hand_index == hand_index:
		selected_hand_index = -1
		print("手札番号%dの選択を解除しました。" % hand_number)
	else:
		selected_hand_index = hand_index
		if current_player == local_test_player:
			# カード名は選択時にも自動表示しない。必要なときにF2で確認する。
			print("あなたは手札番号%dを選択しました。" % hand_number)
		else:
			print("通話相手の手札番号%dを選択しました。" % hand_number)

	selected_square = Vector2i(-1, -1)
	pending_wall_square = Vector2i(-1, -1)
	queue_redraw()


func hand_summary(player: int) -> String:
	if SHARED_TEST_MODE and player != local_test_player:
		return "非公開"
	var counts: Dictionary = {}

	for card in hands[player]:
		var card_name: String = card["name"]
		counts[card_name] = counts.get(card_name, 0) + 1

	if counts.is_empty():
		return "なし"

	var labels: PackedStringArray = PackedStringArray()

	for card_name in counts:
		labels.append("%s×%d" % [card_name, counts[card_name]])

	return ", ".join(labels)


func is_summonable_piece(card: Dictionary) -> bool:
	var category: String = str(card.get("category", ""))
	return category in ["兵", "壁", "罠"]

func summon_piece(square: Vector2i) -> void:
	if selected_hand_index < 0:
		return

	if selected_hand_index >= hands[current_player].size():
		selected_hand_index = -1
		return

	if pieces.has(square):
		print("駒があるマスには召喚できません。")
		return

	var card: Dictionary = hands[current_player][selected_hand_index]
	var card_name: String = str(card.get("name", ""))
	var category: String = str(card.get("category", ""))
	
		# 二歩の禁止：同じ筋に自分の歩があれば、新たな歩は召喚できない
	if category == "兵" and card_name == "歩":
		for existing_square in pieces:
			var existing_piece: Dictionary = pieces[existing_square]

			if int(existing_piece.get("owner", -1)) != current_player:
				continue

			if str(existing_piece.get("category", "")) != "兵":
				continue

			if str(existing_piece.get("name", "")) != "歩":
				continue

			# Vector2iでは y が筋を表す
			if existing_square.y == square.y:
				print(
					"二歩は禁止です。この筋にはすでに自分の歩があります。"
				)
				return

	if not is_summonable_piece(card):
		print("このカードの召喚処理はまだ実装されていません：", card_name)
		return

	# カテゴリーごとの召喚上限を確認
	match category:
		"兵":
			if has_summoned_soldier[current_player]:
				print("このターンはすでに兵を召喚しています。")
				return
		"壁":
			if has_summoned_wall[current_player]:
				print("このターンはすでに壁を召喚しています。")
				return
		"罠":
			if has_summoned_trap[current_player]:
				print("このターンはすでに罠を召喚しています。")
				return

	var cost: int = int(card.get("cost", 0))
	var available_cost: int = (
		costs[current_player] + reserves[current_player]
	)

	if available_cost < cost:
		print("コストが不足しています。必要：%d、使用可能：%d" % [
			cost,
			available_cost
		])
		return

	var placement_squares: Array[Vector2i] = []
	var wall_length: int = int(card.get("wall_length", 1))

	# 壁の配置処理
	if category == "壁":
		if wall_length == 2:
			
			# 1回目のクリック：馬防柵の1マス目を仮指定
			if pending_wall_square.x == -1:
				if not WallRules.is_valid_wall_square(pieces,square, current_player):
					print("壁は自陣の空きマスにのみ配置できます。")
					return

				pending_wall_square = square

				print(
					"馬防柵の1マス目を選択しました。"
					+ "上下左右の隣接する空きマスをクリックしてください。"
				)

				queue_redraw()
				return

			# 2回目のクリック：隣接するマスを確認
			var first_square: Vector2i = pending_wall_square

			var distance: int = (
				absi(square.x - first_square.x)
				+ absi(square.y - first_square.y)
			)

			if distance != 1:
				print("馬防柵の2マス目は上下左右の隣接マスを選んでください。")
				return

			if not WallRules.is_valid_wall_square(pieces,first_square, current_player):
				print("馬防柵の1マス目が配置できません。Escでキャンセルしてください。")
				return

			if not WallRules.is_valid_wall_square(pieces,square, current_player):
				print("馬防柵の2マス目には配置できません。")
				return

			placement_squares.append(first_square)
			placement_squares.append(square)

		else:
			# 竹束など、1マス分の壁
			if not WallRules.is_valid_wall_square(pieces,square, current_player):
				print("壁は自陣の空きマスにのみ配置できます。")
				return

			placement_squares.append(square)

	else:
		# 領地への兵の召喚は、召喚制限ラインが届いている場合のみ許可。
		if category == "兵" and _is_territory_square(square):
			if not _territory_is_within_summon_line(square, current_player):
				print("領地への召喚は、召喚制限ラインがその段まで到達してから可能です。")
				return

		# 兵・罠のその他の配置条件はSummonRulesに委ねる
		var placement_error : String = (
			SummonRules.get_non_wall_placement_error(
				pieces,
				square,
				current_player,
				category
			)
		)
		if placement_error !="":
			print(placement_error)
			return
		
		placement_squares.append(square)

	# すべての配置条件を満たした場合にだけコストを支払う
	if not spend_cost(current_player, cost):
		return

	#	# 壁は2マスとも同じIDを持たせる
	var wall_id: int = -1

	if category == "壁":
		wall_id = next_wall_id
		next_wall_id += 1

	# 2マス壁の配置方向を判定
	var wall_orientation: String = "none"

	if category == "壁" and wall_length == 2:
		var first_placed_square: Vector2i = placement_squares[0]
		var second_placed_square: Vector2i = placement_squares[1]

		if first_placed_square.x == second_placed_square.x:
			wall_orientation = "horizontal"
		else:
			wall_orientation = "vertical"

	# 駒・壁のデータ
	var trap_effect_id := TrapRules.get_effect_id(card)

	var piece_data: Dictionary = {
		"category": category,
		"name": card_name,
		"cost":cost,
		"movement_type": card.get("movement_type", card_name),
		"owner": current_player,
		"wall_length": wall_length,
		"destroy_cost": int(card.get("destroy_cost", 0)),
		"blocks_knight": bool(card.get("blocks_knight", false)),
		"wall_id": wall_id,
		"wall_orientation": wall_orientation,
		"summoned_turn": turn_counts[current_player],
		"trap_effect": trap_effect_id,
		"activation_cost": int(card.get("activation_cost", 0)),
		"attack_cost": int(card.get("attack_cost", 0)),
		"on_summon_effect": str(card.get("on_summon_effect", "")),
		"effect_text": str(card.get("effect_text", "")),
		"is_face_down": category == "罠"
	}

	for placement_square in placement_squares:
		pieces[placement_square] = piece_data.duplicate(true)
	


	# 召喚回数を記録
	match category:
		"兵":
			has_summoned_soldier[current_player] = true
		"壁":
			has_summoned_wall[current_player] = true
		"罠":
			has_summoned_trap[current_player] = true

	pending_wall_square = Vector2i(-1, -1)

	hands[current_player].remove_at(selected_hand_index)
	selected_hand_index = -1

	print("%sが%sを召喚しました。" % [
		"先手" if current_player == 0 else "後手",
		card_name
	])

	if not str(card.get("on_summon_effect", "")).is_empty():
		_resolve_card_on_summon_effect(current_player, card)
	if SHARED_TEST_MODE and current_player == local_test_player:
		_print_local_hand_and_cost("召喚後")

	queue_redraw()

# 登場時効果の実行を CardEffects に委譲し、ここでは対局状態だけを更新する。

func _resolve_card_on_summon_effect(player: int, summoned_card: Dictionary) -> void:
	if player < 0 or player >= decks.size():
		return

	var effect_id := str(summoned_card.get("on_summon_effect", ""))
	if effect_id.is_empty():
		return

	var top_card: Dictionary = {}
	if not decks[player].is_empty():
		top_card = decks[player][decks[player].size() - 1]

	var result: Dictionary = CardEffects.resolve_on_summon_effect(
		effect_id,
		top_card
	)
	var message := str(result.get("message", "カード効果を処理しました。"))
	public_notice = str(result.get("public_notice", message))
	print(message)

	if str(result.get("action", "none")) == "take_top_card" and not decks[player].is_empty():
		var obtained_card: Dictionary = decks[player].pop_back()
		obtained_card["owner"] = player
		hands[player].append(obtained_card)
		print("公開カードを%sの手札に加えました。" % ("先手" if player == 0 else "後手"))

	queue_redraw()

func can_move_shape(
	from_square: Vector2i,
	to_square: Vector2i,
	piece: Dictionary
) -> bool:
	return MovementRules.can_move_shape(
		from_square,
		to_square,
		piece
	)


func is_sliding_piece(piece_name: String) -> bool:
	return piece_name in ["香", "角", "飛","馬","龍"]


func path_is_clear(from: Vector2i, to: Vector2i) -> bool:
	var name: String = str(pieces[from].get("name", ""))

	if not is_sliding_piece(name):
		return true

	var dx: int = to.x - from.x
	var dy: int = to.y - from.y

	var step_x: int = signi(dx)
	var step_y: int = signi(dy)
	var pos: Vector2i = from + Vector2i(step_x, step_y)

	while pos != to:
		if pieces.has(pos):
			var blocking_piece: Dictionary = pieces[pos]

			# 罠は移動経路を塞がない
			if str(blocking_piece.get("category", "")) == "罠":
				pos += Vector2i(step_x, step_y)
				continue

			# 罠以外の駒や壁は移動経路を塞ぐ
			return false

		pos += Vector2i(step_x, step_y)

	return true
# 隣接する壁の破壊を試みる
func try_destroy_wall(
	from_square: Vector2i,
	wall_square: Vector2i
) -> void:
	# 壁破壊は移動・攻撃・罠の手動起動と同じ行動枠を使う。
	if has_moved_this_turn:
		print("このターンはすでに移動または移動の代わりの行動を行っています。")
		return

	if not WallRules.can_destroy_wall(
		pieces,
		from_square,
		wall_square,
		current_player
	):
		print("自分の駒で上下左右に隣接する壁を選択してください。")
		return

	var wall_piece: Dictionary = pieces[wall_square]

	var destroy_cost: int = int(wall_piece.get("destroy_cost", 0))
	var available_cost: int = (
		costs[current_player] + reserves[current_player]
	)

	if available_cost < destroy_cost:
		print(
			"壁の破壊コストが不足しています。必要：%d、使用可能：%d"
			% [destroy_cost, available_cost]
		)
		return

	# 破壊コストを支払う
	if not spend_cost(current_player, destroy_cost):
		return

	var wall_name: String = str(wall_piece.get("name", "壁"))
	var wall_id: int = int(wall_piece.get("wall_id", -1))

	# 馬防柵など、複数マスを占有する壁はまとめて除去する
	var squares_to_remove: Array[Vector2i] = []

	if wall_id >= 1:
		for candidate_square in pieces:
			var candidate_piece: Dictionary = pieces[candidate_square]

			if candidate_piece.get("category", "") != "壁":
				continue

			if int(candidate_piece.get("wall_id", -1)) == wall_id:
				squares_to_remove.append(candidate_square)
	else:
		# wall_idのない旧データはクリックされたマスだけを除去
		squares_to_remove.append(wall_square)

	for remove_square in squares_to_remove:
		pieces.erase(remove_square)

	print(
		"%sが%sを破壊しました。コストを%d支払いました。"
		% [
			"先手" if current_player == 0 else "後手",
			wall_name,
			destroy_cost
		]
	)

	# 壁の破壊は移動の代わりの行動。行動枠を消費するが、
	# 手番そのものは終了せず、召喚などの残りの行動を続けられる。
	selected_square = Vector2i(-1, -1)
	has_moved_this_turn = true
	if SHARED_TEST_MODE and current_player == local_test_player:
		_print_local_hand_and_cost("壁破壊後")
	queue_redraw()

func is_knight_blocked_by_fence(
	from_square: Vector2i,
	to_square: Vector2i,
	moving_piece: Dictionary
) -> bool:
	return WallRules.blocks_path(pieces, from_square, to_square)

func can_move(from: Vector2i, to: Vector2i) -> bool:
	if from == to or not pieces.has(from):
		return false

	if to.x < 1 or to.x > BOARD_SIZE:
		return false
	if to.y < 1 or to.y > BOARD_SIZE:
		return false

	var moving_piece: Dictionary = pieces[from]
	
		# このターンに召喚した兵は移動できない
	if str(moving_piece.get("category", "")) == "兵":
		var summoned_turn: int = int(
			moving_piece.get("summoned_turn", -1)
		)

		if (
			summoned_turn == turn_counts[current_player]
			and int(moving_piece.get("owner", -1)) == current_player
		):
			return false

	if pieces.has(to):
		var target_piece: Dictionary = pieces[to]
		var target_category: String = str(
			target_piece.get("category", "")
		)

		# 壁は通常の移動や捕獲では取り除けない
		if target_category == "壁":
			return false

		# 罠は通常の捕獲対象ではない。該当する駒が踏んだ場合のみ移動先にできる。
		if target_category == "罠":
			if not TrapRules.can_enter_trap_square(target_piece, moving_piece):
				return false
		else:
			# 罠以外の味方の駒があるマスには移動できない
			if int(target_piece.get("owner", -1)) == int(
				moving_piece.get("owner", -2)
			):
				return false

	# 馬防柵が桂馬の跳躍を阻止する場合は移動できない
	if is_knight_blocked_by_fence(from, to, moving_piece):
		return false

	return (
		can_move_shape(from, to, moving_piece)
		and path_is_clear(from, to)
	)
# 各プレイヤーの成デッキを初期化する。先手・後手で別々の構成を使う。

func initialize_promotion_decks() -> void:
	for player in range(2):
		promotion_decks[player] = []
		var names_to_use: Array = INITIAL_PROMOTION_DECK_NAMES
		if player < active_promotion_deck_names_by_player.size():
			var configured_names: Variant = active_promotion_deck_names_by_player[player]
			if configured_names is Array and not configured_names.is_empty():
				names_to_use = configured_names

		for card_name in names_to_use:
			var card: Dictionary = CardDatabase.get_card(str(card_name))
			if card.is_empty():
				push_error("成カードのデータがありません: " + str(card_name))
				continue
			card["owner"] = player
			promotion_decks[player].append(card)


# 成りを確認するダイアログを初期化する
func initialize_promotion_dialog() -> void:
	promotion_dialog = PromotionChoiceDialog.new()
	promotion_dialog.promotion_selected.connect(_on_promotion_selected)
	promotion_dialog.promotion_declined.connect(_on_promotion_declined)
	add_child(promotion_dialog)


# 成デッキのカード名一覧を取得する

func promotion_deck_summary(player: int) -> String:
	var names: PackedStringArray = PackedStringArray()

	for card in promotion_decks[player]:
		names.append(str(card.get("name", "?")))

	if names.is_empty():
		return "なし"

	return "、".join(names)

# 指定したマスが相手陣かどうか
func is_enemy_territory(
	square: Vector2i,
	player: int
) -> bool:
	if player == 0:
		return square.x <= 3

	if player == 1:
		return square.x >= 7

	return false


# 成りが可能なら、確認ダイアログを表示する
func offer_promotion(
	square: Vector2i,
	piece: Dictionary
) -> void:
	if str(piece.get("category", "")) != "兵":
		return

	var player: int = int(piece.get("owner", -1))
	if player != current_player:
		return
	if not is_enemy_territory(square, player):
		return

	# カード定義から成り先候補を取得。旧形式 promotion_card も利用できる。
	var base_card: Dictionary = CardDatabase.get_card(str(piece.get("name", "")))
	var raw_candidates: Variant = base_card.get("promotion_cards", [])
	var candidate_names: Array[String] = []
	if raw_candidates is Array:
		for raw_name in raw_candidates:
			var candidate_name := str(raw_name)
			if not candidate_name.is_empty() and not candidate_names.has(candidate_name):
				candidate_names.append(candidate_name)
	if candidate_names.is_empty():
		var legacy_name := str(base_card.get("promotion_card", ""))
		if not legacy_name.is_empty():
			candidate_names.append(legacy_name)
	if candidate_names.is_empty():
		return

	# 実際に自分の成デッキに残っている成カードだけを選択肢にする。
	var available_names: Array[String] = []
	for candidate_name in candidate_names:
		for promotion_card in promotion_decks[player]:
			if str(promotion_card.get("name", "")) == candidate_name:
				available_names.append(candidate_name)
				break
	if available_names.is_empty():
		return

	pending_promotion_square = square
	pending_promotion_card_name = ""
	pending_promotion_card_names = available_names.duplicate()
	promotion_dialog.show_for_piece(str(piece.get("name", "駒")), available_names)


# UIで成り先が直接選ばれた場合。盤上への反映は既存の成り処理に委ねる。

func _on_promotion_selected(promotion_name: String) -> void:
	if not pending_promotion_card_names.has(promotion_name):
		return
	pending_promotion_card_name = promotion_name
	_on_promotion_confirmed()


# 成りを選ばなかった場合

func _on_promotion_declined() -> void:
	pending_promotion_square = Vector2i(-1, -1)
	pending_promotion_card_name = ""
	pending_promotion_card_names.clear()

	print("成らずを選択しました。")

	queue_redraw()


# 成ることを選んだ場合

func _on_promotion_confirmed() -> void:
	var square: Vector2i = pending_promotion_square

	if not pieces.has(square):
		pending_promotion_square = Vector2i(-1, -1)
		pending_promotion_card_name = ""
		pending_promotion_card_names.clear()
		return

	var original_piece: Dictionary = pieces[square]
	var player: int = int(original_piece.get("owner", -1))

	if player < 0 or player > 1:
		pending_promotion_square = Vector2i(-1, -1)
		pending_promotion_card_name = ""
		pending_promotion_card_names.clear()
		return

	var promotion_name: String = pending_promotion_card_name
	if promotion_name.is_empty() or not pending_promotion_card_names.has(promotion_name):
		pending_promotion_square = Vector2i(-1, -1)
		pending_promotion_card_name = ""
		pending_promotion_card_names.clear()
		return
	var deck_index: int = -1

	# 対応する成カードの位置を検索する
	for i in range(promotion_decks[player].size()):
		if str(
			promotion_decks[player][i].get("name", "")
		) == promotion_name:
			deck_index = i
			break

	if deck_index == -1:
		print("対応する成カードが成デッキにありません。")
		pending_promotion_square = Vector2i(-1, -1)
		pending_promotion_card_name = ""
		pending_promotion_card_names.clear()
		queue_redraw()
		return

	# 成る前の駒名を記録する。元の駒カードは、この時点では手札に戻さない。
	var original_name: String = str(
		original_piece.get("name", "")
	)

	# 成カードを成デッキから盤上へ移す
	var promoted_piece: Dictionary = (
		promotion_decks[player].pop_at(deck_index)
	)

	promoted_piece["owner"] = player
	promoted_piece["summoned_turn"] = int(
		original_piece.get("summoned_turn", -1)
	)
	promoted_piece["is_face_down"] = false
	# 成駒が捕獲されたとき、元の駒を捕獲者の手札へ加えるための情報
	promoted_piece["base_piece_name"] = original_name

	pieces[square] = promoted_piece

	print(
		"%sが%sに成りました。元の%sは手札に戻りません。"
		% [
			"先手" if player == 0 else "後手",
			promotion_name,
			original_name
		]
	)

	pending_promotion_square = Vector2i(-1, -1)
	pending_promotion_card_name = ""
	pending_promotion_card_names.clear()
	queue_redraw()

# 新しい罠の効果IDを判定する。

# 新しい罠の効果IDを判定する。
func _is_special_trap_effect(effect_id: String) -> bool:
	return TrapRules.is_special_effect(effect_id)

func _get_trap_effect_id(trap_piece: Dictionary) -> String:
	return TrapRules.get_effect_id(trap_piece)

func _is_special_trap_target(target_piece: Dictionary, trap_owner: int) -> bool:
	return TrapRules.is_special_target(target_piece, trap_owner)

func _get_traps_triggered_by_move(
	from_square: Vector2i,
	to_square: Vector2i,
	moving_piece: Dictionary
) -> Array[Vector2i]:
	return TrapRules.get_triggered_traps(
		pieces,
		from_square,
		to_square,
		moving_piece,
		BOARD_SIZE
	)

func _process_traps_before_move(
	from_square: Vector2i,
	to_square: Vector2i,
	moving_piece: Dictionary,
	triggered_traps: Array[Vector2i],
	start_index: int
) -> bool:
	for trap_index in range(start_index, triggered_traps.size()):
		var trap_square: Vector2i = triggered_traps[trap_index]
		if not pieces.has(trap_square):
			continue

		var trap_piece: Dictionary = pieces[trap_square]
		var trap_effect := TrapRules.get_effect_id(trap_piece)

		if TrapRules.is_special_effect(trap_effect):
			if TrapRules.should_auto_trigger(trap_piece, moving_piece):
				_begin_special_trap_activation(
					trap_square,
					trap_piece,
					true,
					from_square,
					to_square,
					moving_piece,
					triggered_traps,
					trap_index + 1
				)
				return true
			continue

		# 既存の罠も、発動可否と結果はTrapRulesに判定を委ねる。
		var effect_result: Dictionary = TrapRules.resolve_trap_effect(
			trap_piece,
			moving_piece
		)
		if not bool(effect_result.get("triggered", false)):
			continue

		if bool(effect_result.get("consume_trap", false)):
			pieces.erase(trap_square)
		print(str(effect_result.get("message", "罠が発動しました。")))
		var piece_outcome := str(effect_result.get("piece_outcome", "none"))
		match piece_outcome:
			"destroy":
				pieces.erase(from_square)
				var moving_category := str(moving_piece.get("category", ""))
				var moving_name := str(moving_piece.get("name", "兵"))
				if moving_category == "王":
					game_over = true
					winner = 1 - current_player
					print("王が罠によって倒れました。")
					print("%sの勝利！" % ("先手" if winner == 0 else "後手"))
				else:
					print("%sが罠によって破壊されました。" % moving_name)
				selected_square = Vector2i(-1, -1)
				has_moved_this_turn = true
				if SHARED_TEST_MODE and current_player == local_test_player:
					_print_local_hand_and_cost("罠発動後")
				queue_redraw()
				return true
			"none":
				pass
			_:
				push_warning("未対応の罠効果です: " + piece_outcome)
	return false

func _perform_archer_attack() -> void:
	if selected_square.x < 1 or not pieces.has(selected_square):
		print("攻撃する弓手または成弓を先に選択してください。")
		return

	var archer: Dictionary = pieces[selected_square]
	if int(archer.get("owner", -1)) != current_player:
		print("自分の弓手または成弓を選択してください。")
		return
	if not AttackRules.is_archer(archer):
		print("選択中の駒は攻撃できません。弓手または成弓を選択してください。")
		return
	if has_moved_this_turn:
		print("このターンはすでに移動または移動の代わりの行動を行っています。")
		return

	var attack_cost := int(archer.get("attack_cost", 1))
	var available_cost := costs[current_player] + reserves[current_player]
	if available_cost < attack_cost:
		print("攻撃コストが不足しています。必要：%d、使用可能：%d" % [attack_cost, available_cost])
		return

	var target_square := _get_archer_attack_target_square(selected_square)
	if target_square.x < 1 or not pieces.has(target_square):
		print("正面2マス先に攻撃対象がいません。攻撃コストは消費しません。")
		return
	var target_piece: Dictionary = pieces[target_square]
	if int(target_piece.get("owner", -1)) != 1 - current_player:
		print("攻撃対象は敵の駒ではありません。")
		return
	if not spend_cost(current_player, attack_cost):
		return

	has_moved_this_turn = true
	selected_square = Vector2i(-1, -1)
	selected_hand_index = -1
	_send_enemy_piece_to_graveyard(target_square, current_player, attack_cost)
	if SHARED_TEST_MODE and current_player == local_test_player:
		_print_local_hand_and_cost("弓手攻撃後")
	queue_redraw()


func _send_enemy_piece_to_graveyard(target_square: Vector2i, attacker: int, paid_cost: int) -> void:
	if not pieces.has(target_square):
		return
	var target_piece: Dictionary = pieces[target_square]
	var target_owner := int(target_piece.get("owner", -1))
	if target_owner != 1 - attacker:
		return

	var target_name := str(target_piece.get("name", "駒"))
	var target_category := str(target_piece.get("category", ""))
	var wall_id := int(target_piece.get("wall_id", -1))
	graveyard.append(target_piece.duplicate(true))

	# 2マス構成の壁は1つの壁として扱い、両方のマスを除去する。
	if target_category == "壁" and wall_id >= 1:
		var wall_squares: Array[Vector2i] = []
		for square in pieces:
			var piece_at_square: Dictionary = pieces[square]
			if str(piece_at_square.get("category", "")) == "壁" and int(piece_at_square.get("wall_id", -1)) == wall_id:
				wall_squares.append(square)
		for square in wall_squares:
			pieces.erase(square)
	else:
		pieces.erase(target_square)

	print("%sの攻撃：%sを墓地に送りました。攻撃コスト%dを支払いました。" % ["先手" if attacker == 0 else "後手", target_name, paid_cost])
	if target_category == "王" or target_name == "王":
		game_over = true
		winner = attacker
		print("王が弓手／成弓の攻撃で墓地に送られました。")
		print("%sの勝利！" % ("先手" if winner == 0 else "後手"))


# 選択中の伏兵・石落としをFキーで手動起動する。
func _activate_selected_special_trap() -> void:
	if selected_square.x < 1 or not pieces.has(selected_square):
		return
	var trap_piece: Dictionary = pieces[selected_square]
	if str(trap_piece.get("category", "")) != "罠":
		return
	if int(trap_piece.get("owner", -1)) != current_player:
		print("自分が設置した罠だけ起動できます。")
		return
	var effect_id := _get_trap_effect_id(trap_piece)
	if not _is_special_trap_effect(effect_id):
		print("この罠は手動起動に対応していません。")
		return
	if has_moved_this_turn:
		print("このターンはすでに移動または罠の起動を行っています。")
		return

	var activation_cost := int(trap_piece.get("activation_cost", 1))
	if not spend_cost(current_player, activation_cost):
		print("罠の起動コストが不足しています。必要：%d" % activation_cost)
		return
	has_moved_this_turn = true
	var no_traps: Array[Vector2i] = []
	_begin_special_trap_activation(
		selected_square,
		trap_piece,
		false,
		Vector2i(-1, -1),
		Vector2i(-1, -1),
		{},
		no_traps,
		0
	)


func _begin_special_trap_activation(
	trap_square: Vector2i,
	trap_piece: Dictionary,
	automatic: bool,
	move_from: Vector2i,
	move_to: Vector2i,
	moving_piece: Dictionary,
	triggered_traps: Array[Vector2i],
	next_index: int
) -> void:
	var trap_snapshot: Dictionary = trap_piece.duplicate(true)
	var trap_owner := int(trap_snapshot.get("owner", -1))
	var ignored_square := move_from if automatic else Vector2i(-1, -1)
	var activation: Dictionary = TrapRules.prepare_special_activation(
		pieces,
		trap_square,
		trap_snapshot,
		trap_owner,
		ignored_square,
		BOARD_SIZE
	)
	var effect_id := TrapRules.get_effect_id(trap_snapshot)
	var mode := str(activation.get("mode", "none"))

	# Dictionary.get() returns Variant, so transfer candidates explicitly into a typed array.
	var ambush_candidates: Array[Vector2i] = []
	var raw_candidates: Variant = activation.get("candidates", [])
	if raw_candidates is Array:
		for raw_candidate in raw_candidates:
			if raw_candidate is Vector2i:
				ambush_candidates.append(raw_candidate)

	var single_target: Vector2i = Vector2i(-1, -1)
	var raw_target: Variant = activation.get("target_square", Vector2i(-1, -1))
	if raw_target is Vector2i:
		single_target = raw_target

	# 伏せ罠は一度発動したら消費される。自動発動は起動コスト不要。
	pieces.erase(trap_square)
	pending_special_trap_effect = effect_id
	pending_special_trap_mode = mode
	pending_special_trap_square = trap_square
	pending_special_trap_owner = trap_owner
	pending_special_trap_name = str(trap_snapshot.get("name", "罠"))
	pending_special_trap_candidates = ambush_candidates
	pending_special_trap_automatic = automatic
	pending_special_trap_move_from = move_from
	pending_special_trap_move_to = move_to
	pending_special_trap_moving_piece = moving_piece.duplicate(true)
	pending_special_trap_triggered_traps = triggered_traps.duplicate()
	pending_special_trap_next_index = next_index
	selected_square = Vector2i(-1, -1)
	selected_hand_index = -1
	pending_wall_square = Vector2i(-1, -1)

	print("%sが発動しました。" % str(trap_snapshot.get("name", "罠")))
	if SHARED_TEST_MODE and current_player == local_test_player:
		_print_local_hand_and_cost("罠起動後")
	match mode:
		"choose_target":
			if ambush_candidates.is_empty():
				print("墓地送りの対象がいません。")
				_finish_pending_special_trap(Vector2i(-1, -1))
			else:
				pending_special_trap_waiting_for_target = true
				print("墓地に送る敵駒をクリックしてください。見送る場合はEscを押してください。")
				queue_redraw()
		"single_target":
			if single_target.x >= 1:
				_send_piece_to_graveyard(single_target, trap_owner)
			else:
				print("対象となる敵駒はいません。")
			_finish_pending_special_trap(Vector2i(-1, -1))
		_:
			push_warning("罠の発動方式を判定できません: " + effect_id)
			_finish_pending_special_trap(Vector2i(-1, -1))


func _send_piece_to_graveyard(target_square: Vector2i, trap_owner: int) -> void:
	if not pieces.has(target_square):
		return
	var target_piece: Dictionary = pieces[target_square]
	if not _is_special_trap_target(target_piece, trap_owner):
		return
	var target_name := str(target_piece.get("name", "駒"))
	var target_owner := int(target_piece.get("owner", -1))
	var target_category := str(target_piece.get("category", ""))
	graveyard.append(target_piece.duplicate(true))
	pieces.erase(target_square)
	print("%sの%sを墓地に送りました。" % ["先手" if target_owner == 0 else "後手", target_name])

	# 王が墓地に送られた場合も、通常の王捕獲と同様に即時決着とする。
	if target_category == "王" or target_name == "王":
		game_over = true
		winner = trap_owner
		print("王が罠によって墓地に送られました。")
		print("%sの勝利！" % ("先手" if winner == 0 else "後手"))


func _handle_pending_special_trap_input(event: InputEvent) -> void:
	if event is InputEventKey:
		if not event.pressed or event.echo:
			return
		if event.keycode == KEY_ESCAPE:
			_finish_pending_special_trap(Vector2i(-1, -1))
		return

	if not (event is InputEventMouseButton):
		return
	if event.button_index != MOUSE_BUTTON_LEFT or not event.pressed:
		return

	var mouse_pos: Vector2 = to_local(event.position)
	var relative: Vector2 = mouse_pos - BOARD_ORIGIN
	if relative.x < 0.0 or relative.y < 0.0:
		return
	var col := int(relative.x / CELL_SIZE)
	var row := int(relative.y / CELL_SIZE)
	if row < 0 or row >= BOARD_SIZE or col < 0 or col >= BOARD_SIZE:
		return
	var chosen_square: Vector2i = _screen_cell_to_square(row, col)
	if pending_special_trap_candidates.has(chosen_square):
		_finish_pending_special_trap(chosen_square)


func _finish_pending_special_trap(chosen_square: Vector2i) -> void:
	var mode := pending_special_trap_mode
	var trap_owner := pending_special_trap_owner
	var candidates: Array[Vector2i] = pending_special_trap_candidates.duplicate()
	var automatic := pending_special_trap_automatic
	var move_from := pending_special_trap_move_from
	var move_to := pending_special_trap_move_to
	var moving_piece: Dictionary = pending_special_trap_moving_piece.duplicate(true)
	var triggered_traps: Array[Vector2i] = pending_special_trap_triggered_traps.duplicate()
	var next_index := pending_special_trap_next_index

	if mode == "choose_target":
		if chosen_square.x >= 1 and candidates.has(chosen_square) and pieces.has(chosen_square):
			var target_piece: Dictionary = pieces[chosen_square]
			if TrapRules.is_special_target(target_piece, trap_owner):
				_send_piece_to_graveyard(chosen_square, trap_owner)
			else:
				print("対象が無効になったため、墓地送りを行いませんでした。")
		else:
			print("墓地送りを見送りました。")

	pending_special_trap_waiting_for_target = false
	pending_special_trap_effect = ""
	pending_special_trap_mode = ""
	pending_special_trap_square = Vector2i(-1, -1)
	pending_special_trap_owner = -1
	pending_special_trap_name = ""
	pending_special_trap_candidates.clear()
	pending_special_trap_automatic = false
	pending_special_trap_move_from = Vector2i(-1, -1)
	pending_special_trap_move_to = Vector2i(-1, -1)
	pending_special_trap_moving_piece.clear()
	pending_special_trap_triggered_traps.clear()
	pending_special_trap_next_index = 0

	# 効果で王が墓地に送られた場合、発動のきっかけになった移動も続行しない。
	if game_over:
		selected_square = Vector2i(-1, -1)
		selected_hand_index = -1
		queue_redraw()
		return

	if automatic:
		if _process_traps_before_move(move_from, move_to, moving_piece, triggered_traps, next_index):
			queue_redraw()
			return
		_complete_piece_move(move_from, move_to, moving_piece)
	else:
		selected_square = Vector2i(-1, -1)
		selected_hand_index = -1
		queue_redraw()

func _draw_special_trap_target_highlights() -> void:
	if not pending_special_trap_waiting_for_target:
		return
	for target_square in pending_special_trap_candidates:
		var target_center: Vector2 = square_rect(target_square).get_center()
		draw_circle(target_center, 20.0, Color(1.0, 0.65, 0.08, 0.18))
		draw_arc(target_center, 18.0, 0.0, TAU, 24, Color(1.0, 0.45, 0.05, 0.98), 3.0)


# 移動元から移動先へ駒を動かし、通常の捕獲と成り判定を行う。
func _complete_piece_move(from_square: Vector2i, to_square: Vector2i, moving_piece: Dictionary) -> void:
	# 最終保険：移動先の伏兵／石落としを通常の捕獲処理へ渡さず、罠発動を優先する。
	if pieces.has(to_square):
		var destination_piece: Dictionary = pieces[to_square]
		var destination_effect := _get_trap_effect_id(destination_piece)
		if (
			str(destination_piece.get("category", "")) == "罠"
			and _is_special_trap_effect(destination_effect)
			and TrapRules.should_auto_trigger(destination_piece, moving_piece)
		):
			_begin_special_trap_activation(
				to_square,
				destination_piece,
				true,
				from_square,
				to_square,
				moving_piece,
				[],
				0
			)
			return

	if pieces.has(to_square):
		var target_piece: Dictionary = pieces[to_square]
		var target_category: String = str(target_piece.get("category", ""))
		if target_category == "罠":
			print("罠は通常の捕獲対象ではありません。")
			selected_square = Vector2i(-1, -1)
			queue_redraw()
			return

		if str(target_piece.get("name", "")) == "王":
			game_over = true
			winner = current_player
			print("%sの勝利！" % ("先手" if winner == 0 else "後手"))
		elif target_category == "成":
			var original_owner: int = int(target_piece.get("owner", -1))
			var promotion_name: String = str(target_piece.get("name", ""))
			var promotion_definition: Dictionary = CardDatabase.get_card(promotion_name)
			var base_piece_name: String = str(target_piece.get("base_piece_name", promotion_definition.get("promotes_from", "")))
			if original_owner >= 0 and original_owner <= 1:
				if not promotion_definition.is_empty():
					promotion_definition["owner"] = original_owner
					promotion_decks[original_owner].append(promotion_definition)
					print("捕獲された%sは、元の所有者の成デッキに戻りました。" % promotion_name)
				else:
					push_error("成カードのデータが見つかりません: " + promotion_name)
			var base_card: Dictionary = CardDatabase.get_card(base_piece_name)
			if not base_card.is_empty():
				base_card["owner"] = current_player
				hands[current_player].append(base_card)
				print("%sが%sを捕獲し、元の駒%sを手札に加えました。" % ["先手" if current_player == 0 else "後手", promotion_name, base_piece_name])
			else:
				push_error("成駒の元の駒データが見つかりません: " + base_piece_name)
		else:
			var captured_card: Dictionary = target_piece.duplicate(true)
			captured_card["owner"] = current_player
			hands[current_player].append(captured_card)
			print("%sが%sを捕獲し、手札に加えました。" % ["先手" if current_player == 0 else "後手", str(target_piece.get("name", "?"))])

	pieces.erase(from_square)
	pieces[to_square] = moving_piece
	selected_square = Vector2i(-1, -1)
	has_moved_this_turn = true
	if not game_over:
		offer_promotion(to_square, moving_piece)
	if SHARED_TEST_MODE and current_player == local_test_player:
		_print_local_hand_and_cost("移動後")
	queue_redraw()

func _input(event: InputEvent) -> void:
	# 画面共有テストでは、陣営を選ぶまで対局操作を受け付けない。
	if SHARED_TEST_MODE and not side_selection_complete:
		return

	# 特殊罠の対象選択中は、先に対象指定だけを処理する。
	if pending_special_trap_waiting_for_target:
		_handle_pending_special_trap_input(event)
		return

	# キーボード操作
	if event is InputEventKey:
		if not event.pressed or event.echo:
			return

		# F2：出力欄に自分の成デッキだけを表示する。
		if SHARED_TEST_MODE and event.keycode == KEY_F2:
			_print_local_promotion_deck()
			return

		if game_over:
			return

		# 画面共有テスト：数字キーで手札を選択／破棄する。
		if SHARED_TEST_MODE:
			var hand_number: int = _hand_number_from_key(event.keycode)
			if hand_number > 0:
				_select_current_hand_by_number(hand_number)
				return

		# Esc：選択をキャンセル
		if event.keycode == KEY_ESCAPE:
			var had_selection: bool = (
				selected_hand_index >= 0
				or selected_square.x != -1
			)
			selected_hand_index = -1
			selected_square = Vector2i(-1, -1)
			pending_wall_square = Vector2i(-1, -1)
			pending_discard_hand_number = 0
			if had_selection:
				print("選択をキャンセルしました。")
			else:
				print("選択中の項目はありません。")
			queue_redraw()
			return

		# Space：手番を終了する。
		if event.keycode == KEY_SPACE:
			print("%sが手番をスキップしました。" % ("先手" if current_player == 0 else "後手"))
			end_turn()
			return

		# F：伏兵・石落としを移動の代わりに起動する。
		if event.keycode == KEY_F:
			_activate_selected_special_trap()
			return

		# A：弓手・成弓で正面2マス先を攻撃する。
		if event.keycode == KEY_A:
			_perform_archer_attack()
			return
		return

	if game_over:
		return

	# ここから下は従来のマウス操作
	if not (event is InputEventMouseButton):
		return
	if event.button_index != MOUSE_BUTTON_LEFT or not event.pressed:
		return

	var pos: Vector2 = to_local(event.position)

	# 画面共有テストではカード選択は数字キーを使う。
	if not SHARED_TEST_MODE:
		for hand_index in range(hands[current_player].size()):
			var card_rect: Rect2 = hand_card_rect(hand_index)
			if not card_rect.has_point(pos):
				continue
			if discard_mode:
				var discarded_card: Dictionary = hands[current_player][hand_index]
				var discarded_name: String = str(discarded_card.get("name", "?"))
				hands[current_player].remove_at(hand_index)
				selected_hand_index = -1
				print("%sを破棄しました。手札：%d枚" % [discarded_name, hands[current_player].size()])
				if hands[current_player].size() <= 5:
					_complete_end_turn()
				else:
					print("さらに破棄するカードを選んでください。")
					queue_redraw()
				return
			if selected_hand_index == hand_index:
				selected_hand_index = -1
				print("カードの選択を解除しました。")
			else:
				selected_hand_index = hand_index
				print("召喚候補：", hands[current_player][hand_index]["name"])
			selected_square = Vector2i(-1, -1)
			pending_wall_square = Vector2i(-1, -1)
			queue_redraw()
			return

	if discard_mode:
		return

	var relative: Vector2 = pos - BOARD_ORIGIN
	if relative.x < 0 or relative.y < 0:
		return
	var col: int = int(relative.x / CELL_SIZE)
	var row: int = int(relative.y / CELL_SIZE)
	if row >= BOARD_SIZE or col >= BOARD_SIZE:
		return
	var square: Vector2i = _screen_cell_to_square(row, col)

	# 手札選択中なら空きマスへの召喚を試みる。
	if selected_hand_index >= 0:
		if pieces.has(square):
			print("駒があるマスには召喚できません。")
			return
		summon_piece(square)
		return

	# 選択中の駒で壁の破壊を試みる。
	if pieces.has(square) and str(pieces[square].get("category", "")) == "壁":
		try_destroy_wall(selected_square, square)
		return

	# 自分の駒を選択する。
	if selected_square.x == -1:
		if pieces.has(square) and int(pieces[square].get("owner", -1)) == current_player:
			if str(pieces[square].get("category", "")) == "壁":
				print("壁自体は移動できません。")
				return
			selected_square = square
			var selected_piece: Dictionary = pieces[square]
			var selected_trap_effect := TrapRules.get_effect_id(selected_piece)
			if TrapRules.is_special_effect(selected_trap_effect):
				print("選択中の%sはFキーで起動できます（起動コスト%d）。" % [str(selected_piece.get("name", "罠")), int(selected_piece.get("activation_cost", 1))])
			if AttackRules.is_archer(selected_piece):
				print("弓手／成弓はAキーで正面2マス先の敵駒を攻撃できます（攻撃コスト%d）。" % int(selected_piece.get("attack_cost", 1)))
			queue_redraw()
		return

	# 同じマスを再クリックすると選択解除。
	if square == selected_square:
		selected_square = Vector2i(-1, -1)
		queue_redraw()
		return

	# 自分の別の駒を選び直す。
	if pieces.has(square) and int(pieces[square].get("owner", -1)) == current_player:
		selected_square = square
		queue_redraw()
		return

	if has_moved_this_turn:
		print("この手番ではすでに移動または移動の代わりの行動を行っています。")
		selected_square = Vector2i(-1, -1)
		queue_redraw()
		return

	if not can_move(selected_square, square):
		print("そのマスには移動できません。")
		return
	if not spend_cost(current_player, 1):
		print("移動コストが不足しています。")
		return

	var move_from: Vector2i = selected_square
	var move_to: Vector2i = square
	var moving_piece: Dictionary = pieces[move_from].duplicate(true)
	var triggered_traps: Array[Vector2i] = _get_traps_triggered_by_move(move_from, move_to, moving_piece)
	if _process_traps_before_move(move_from, move_to, moving_piece, triggered_traps, 0):
		return
	_complete_piece_move(move_from, move_to, moving_piece)
