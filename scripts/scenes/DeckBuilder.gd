# ==================================================
# ファイル名: DeckBuilder.gd
# 概要: デッキ構築画面のUI制御、カードプールのドラッグ＆ドロップ、バリデーション表示およびデッキ保存・読み込みを行うシーンスクリプトである
# ==================================================

extends Control

const CardDatabase = preload("res://scripts/core/CardDatabase.gd")
const DeckRules = preload("res://scripts/core/DeckRules.gd")
const DeckLibrary = preload("res://scripts/core/DeckLibrary.gd")
const CardTileScript = preload("res://scripts/scenes/DeckCardTile.gd")
const DropZoneScript = preload("res://scripts/scenes/DeckDropZone.gd")

const DECK_SAVE_PATH := "user://deck_save.json"
const TITLE_SCENE_PATH := "res://scenes/TitleScreen.tscn"

# 右側は常に 5×4 のメインデッキと 5×1 の成デッキを表示する
# カード画像の縦横比（約0.715）に合わせたサイズ
const POOL_TILE_SIZE := Vector2(96.0, 134.0)
const DECK_TILE_SIZE := Vector2(72.0, 101.0)
const GRID_GAP := 5

var main_deck: Array[String] = []
var promotion_deck: Array[String] = []
var profiles: Dictionary = {}
var active_profile_id: String = "deck_1"
var deck_name_edit: LineEdit
var editing_mode: String = "main" # main / promotion

var profile_selector: OptionButton
var main_mode_button: Button
var promotion_mode_button: Button
var available_title: Label
var main_available_list: HFlowContainer
var promotion_available_list: HFlowContainer
var active_available_list: HFlowContainer
var pool_drop_zone: Control

var main_deck_drop_zone: Control
var main_deck_list: GridContainer
var main_summary_label: Label
var promotion_deck_drop_zone: Control
var promotion_deck_list: GridContainer
var promotion_summary_label: Label

var validation_label: Label
var save_status_label: Label
var card_texture_cache: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var loaded_library: Dictionary = DeckLibrary.load_library()
	profiles = loaded_library.get("decks", DeckLibrary.default_decks())
	active_profile_id = str(loaded_library.get("last_selected_deck_id", "deck_1"))
	if not profiles.has(active_profile_id):
		active_profile_id = DeckLibrary.ordered_deck_ids(profiles)[0]
	_build_interface()
	_refresh_profile_selector()
	_load_profile_into_editor()
	_refresh_all()
	var message := str(loaded_library.get("message", "デッキ一覧を読み込みました。"))
	if bool(loaded_library.get("using_defaults", false)):
		save_status_label.text = message + " デッキを編集し、保存してください。"
	else:
		save_status_label.text = message


func _build_interface() -> void:
	var background := ColorRect.new()
	background.color = Color(0.075, 0.09, 0.14)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var outer_margin := MarginContainer.new()
	outer_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	outer_margin.add_theme_constant_override("margin_left", 10)
	outer_margin.add_theme_constant_override("margin_top", 10)
	outer_margin.add_theme_constant_override("margin_right", 10)
	outer_margin.add_theme_constant_override("margin_bottom", 10)
	add_child(outer_margin)

	var columns := HBoxContainer.new()
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 12)
	outer_margin.add_child(columns)

	_build_left_panel(columns)
	_build_right_panel(columns)


func _build_left_panel(parent: HBoxContainer) -> void:
	var left_panel := VBoxContainer.new()
	left_panel.custom_minimum_size = Vector2(290, 0)
	left_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_panel.size_flags_stretch_ratio = 1.0
	left_panel.add_theme_constant_override("separation", 5)
	parent.add_child(left_panel)

	var title := Label.new()
	title.text = "デッキ構築"
	title.add_theme_font_size_override("font_size", 22)
	left_panel.add_child(title)

	# 左上の編集モード切替。右側のデッキ表示は常時固定。
	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 5)
	left_panel.add_child(mode_row)

	main_mode_button = Button.new()
	main_mode_button.text = "メインデッキ"
	main_mode_button.toggle_mode = true
	main_mode_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_mode_button.pressed.connect(_on_main_mode_pressed)
	mode_row.add_child(main_mode_button)

	promotion_mode_button = Button.new()
	promotion_mode_button.text = "成デッキ"
	promotion_mode_button.toggle_mode = true
	promotion_mode_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	promotion_mode_button.pressed.connect(_on_promotion_mode_pressed)
	mode_row.add_child(promotion_mode_button)

	var profile_row := HBoxContainer.new()
	profile_row.add_theme_constant_override("separation", 5)
	left_panel.add_child(profile_row)
	var profile_label := Label.new()
	profile_label.text = "編集するデッキ"
	profile_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	profile_row.add_child(profile_label)

	profile_selector = OptionButton.new()
	profile_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	profile_selector.item_selected.connect(_on_profile_selected)
	profile_row.add_child(profile_selector)

	var deck_name_row := HBoxContainer.new()
	deck_name_row.add_theme_constant_override("separation", 5)
	left_panel.add_child(deck_name_row)
	var deck_name_label := Label.new()
	deck_name_label.text = "デッキ名"
	deck_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	deck_name_row.add_child(deck_name_label)
	deck_name_edit = LineEdit.new()
	deck_name_edit.placeholder_text = "例：攻撃型デッキ"
	deck_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	deck_name_row.add_child(deck_name_edit)

	var deck_name_buttons_row := HBoxContainer.new()
	deck_name_buttons_row.add_theme_constant_override("separation", 5)
	left_panel.add_child(deck_name_buttons_row)
	var rename_button := Button.new()
	rename_button.text = "選択中の名前を変更"
	rename_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rename_button.pressed.connect(_rename_active_deck)
	deck_name_buttons_row.add_child(rename_button)
	var new_deck_button := Button.new()
	new_deck_button.text = "新規デッキ作成"
	new_deck_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	new_deck_button.pressed.connect(_create_new_deck)
	deck_name_buttons_row.add_child(new_deck_button)

	var file_row := HBoxContainer.new()
	file_row.add_theme_constant_override("separation", 5)
	left_panel.add_child(file_row)

	var save_button := Button.new()
	save_button.text = "全デッキを保存"
	save_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_button.pressed.connect(_save_decks)
	file_row.add_child(save_button)

	var load_button := Button.new()
	load_button.text = "保存デッキを再読込"
	load_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	load_button.pressed.connect(_load_decks)
	file_row.add_child(load_button)

	var title_button := Button.new()
	title_button.text = "タイトルへ"
	title_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_button.pressed.connect(_return_to_title)
	file_row.add_child(title_button)

	var validation_row := HBoxContainer.new()
	validation_row.add_theme_constant_override("separation", 5)
	left_panel.add_child(validation_row)
	var validate_button := Button.new()
	validate_button.text = "構築条件を検証"
	validate_button.pressed.connect(_validate_current_deck)
	validation_row.add_child(validate_button)
	validation_label = Label.new()
	validation_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	validation_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	validation_row.add_child(validation_label)

	save_status_label = Label.new()
	save_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	save_status_label.add_theme_font_size_override("font_size", 11)
	left_panel.add_child(save_status_label)

	var pool_heading := HBoxContainer.new()
	left_panel.add_child(pool_heading)
	available_title = Label.new()
	available_title.text = "所持カード一覧"
	available_title.add_theme_font_size_override("font_size", 16)
	available_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pool_heading.add_child(available_title)

	var instructions := Label.new()
	instructions.text = "クリック／ドラッグで追加。右側のカードをクリックすると削除。"
	instructions.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	instructions.add_theme_font_size_override("font_size", 10)
	instructions.modulate = Color(0.75, 0.80, 0.88)
	left_panel.add_child(instructions)

	pool_drop_zone = _make_drop_zone("pool", "main", Vector2(0, 0))
	pool_drop_zone.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pool_drop_zone.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_panel.add_child(pool_drop_zone)

	var pool_scroll := ScrollContainer.new()
	pool_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pool_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pool_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pool_drop_zone.add_child(pool_scroll)

	active_available_list = HFlowContainer.new()
	active_available_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	active_available_list.add_theme_constant_override("h_separation", 5)
	active_available_list.add_theme_constant_override("v_separation", 5)
	active_available_list.mouse_filter = Control.MOUSE_FILTER_PASS
	pool_scroll.add_child(active_available_list)


func _build_right_panel(parent: HBoxContainer) -> void:
	var right_panel := VBoxContainer.new()
	right_panel.custom_minimum_size = Vector2(425, 0)
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_panel.size_flags_stretch_ratio = 1.45
	right_panel.add_theme_constant_override("separation", 5)
	parent.add_child(right_panel)

	# 高さが低いウィンドウでも、右側の2つのデッキをスクロールで確認できる。
	var right_scroll := ScrollContainer.new()
	right_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right_panel.add_child(right_scroll)

	var right_content := VBoxContainer.new()
	right_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_content.add_theme_constant_override("separation", 6)
	right_scroll.add_child(right_content)

	var main_header := HBoxContainer.new()
	right_content.add_child(main_header)
	var main_title := Label.new()
	main_title.text = "メインデッキ（5列 × 4行）"
	main_title.add_theme_font_size_override("font_size", 17)
	main_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_header.add_child(main_title)
	main_summary_label = Label.new()
	main_summary_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	main_header.add_child(main_summary_label)

	main_deck_drop_zone = _make_drop_zone("deck", "main", Vector2(0, _deck_zone_min_height(4)))
	main_deck_drop_zone.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_deck_drop_zone.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	right_content.add_child(main_deck_drop_zone)
	main_deck_list = GridContainer.new()
	main_deck_list.columns = 5
	main_deck_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_deck_list.add_theme_constant_override("h_separation", GRID_GAP)
	main_deck_list.add_theme_constant_override("v_separation", GRID_GAP)
	main_deck_list.mouse_filter = Control.MOUSE_FILTER_PASS
	main_deck_drop_zone.add_child(main_deck_list)

	var promotion_header := HBoxContainer.new()
	right_content.add_child(promotion_header)
	var promotion_title := Label.new()
	promotion_title.text = "成デッキ（5列 × 1行）"
	promotion_title.add_theme_font_size_override("font_size", 17)
	promotion_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	promotion_header.add_child(promotion_title)
	promotion_summary_label = Label.new()
	promotion_summary_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	promotion_header.add_child(promotion_summary_label)

	promotion_deck_drop_zone = _make_drop_zone("deck", "promotion", Vector2(0, _deck_zone_min_height(1)))
	promotion_deck_drop_zone.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	promotion_deck_drop_zone.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	right_content.add_child(promotion_deck_drop_zone)
	promotion_deck_list = GridContainer.new()
	promotion_deck_list.columns = 5
	promotion_deck_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	promotion_deck_list.add_theme_constant_override("h_separation", GRID_GAP)
	promotion_deck_list.add_theme_constant_override("v_separation", GRID_GAP)
	promotion_deck_list.mouse_filter = Control.MOUSE_FILTER_PASS
	promotion_deck_drop_zone.add_child(promotion_deck_list)


func _deck_zone_min_height(rows: int) -> float:
	# rows はカード枚数ではなく、グリッドの行数。
	# メインデッキは4行、成デッキは1行。
	# DeckCardTile の実際の最小高さ（画像高 + 8px）と
	# DropZone の内側余白を含めて計算する。
	var tile_height: float = DECK_TILE_SIZE.y + 8.0
	return rows * tile_height + maxi(0, rows - 1) * GRID_GAP + 10.0


func _make_drop_zone(zone_type: String, list_type: String, minimum_size: Vector2) -> Control:
	var zone = DropZoneScript.new()
	zone.zone_type = zone_type
	zone.list_type = list_type
	zone.deck_builder = self
	zone.custom_minimum_size = minimum_size
	zone.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return zone


func _return_to_title() -> void:
	if not ResourceLoader.exists(TITLE_SCENE_PATH):
		save_status_label.text = "タイトルシーンが見つかりません：%s" % TITLE_SCENE_PATH
		return
	var error := get_tree().change_scene_to_file(TITLE_SCENE_PATH)
	if error != OK:
		save_status_label.text = "タイトル画面への移動に失敗しました（エラーコード：%d）。" % error


func _on_main_mode_pressed() -> void:
	_set_edit_mode("main")


func _on_promotion_mode_pressed() -> void:
	_set_edit_mode("promotion")


func _set_edit_mode(new_mode: String) -> void:
	if new_mode != "main" and new_mode != "promotion":
		return
	editing_mode = new_mode
	main_mode_button.button_pressed = editing_mode == "main"
	promotion_mode_button.button_pressed = editing_mode == "promotion"
	pool_drop_zone.list_type = editing_mode
	validation_label.text = ""
	_refresh_pool()
	if editing_mode == "main":
		available_title.text = "所持カード一覧（兵・壁・罠）"
	else:
		available_title.text = "所持成カード一覧"


func _on_profile_selected(index: int) -> void:
	if index < 0 or index >= profile_selector.item_count:
		return
	var next_id := str(profile_selector.get_item_metadata(index))
	if next_id.is_empty() or not profiles.has(next_id) or next_id == active_profile_id:
		return
	_store_editing_profile()
	active_profile_id = next_id
	_load_profile_into_editor()
	_refresh_all()
	save_status_label.text = "「%s」を編集中です。" % str(profiles[active_profile_id].get("name", active_profile_id))


func _refresh_profile_selector() -> void:
	if profile_selector == null:
		return
	profile_selector.clear()
	var ids: Array[String] = DeckLibrary.ordered_deck_ids(profiles)
	for deck_id in ids:
		var profile: Dictionary = profiles[deck_id]
		profile_selector.add_item(str(profile.get("name", deck_id)))
		profile_selector.set_item_metadata(profile_selector.item_count - 1, deck_id)
		if deck_id == active_profile_id:
			profile_selector.select(profile_selector.item_count - 1)


func _update_deck_name_field() -> void:
	if deck_name_edit == null:
		return
	var profile: Dictionary = profiles.get(active_profile_id, {})
	deck_name_edit.text = str(profile.get("name", ""))


func _rename_active_deck() -> void:
	var new_name := deck_name_edit.text.strip_edges()
	if new_name.is_empty():
		save_status_label.text = "デッキ名を入力してください。"
		return
	for deck_id in profiles.keys():
		if str(deck_id) != active_profile_id and str(profiles[deck_id].get("name", "")) == new_name:
			save_status_label.text = "同じ名前のデッキが既にあります。別の名前を指定してください。"
			return
	_store_editing_profile()
	profiles[active_profile_id]["name"] = new_name
	_refresh_profile_selector()
	_update_deck_name_field()
	save_status_label.text = "デッキ名を「%s」に変更しました。保存ボタンで保存してください。" % new_name


func _create_new_deck() -> void:
	_store_editing_profile()
	var new_name := deck_name_edit.text.strip_edges()
	if new_name.is_empty() or new_name == str(profiles.get(active_profile_id, {}).get("name", "")):
		new_name = "デッキ%d" % (profiles.size() + 1)
	var base_name := new_name
	var suffix := 2
	while _deck_name_exists(new_name):
		new_name = "%s %d" % [base_name, suffix]
		suffix += 1
	var number := 1
	var new_id := "deck_%d" % number
	while profiles.has(new_id):
		number += 1
		new_id = "deck_%d" % number
	profiles[new_id] = {"name": new_name, "main_deck": [], "promotion_deck": []}
	active_profile_id = new_id
	_load_profile_into_editor()
	_refresh_profile_selector()
	_refresh_all()
	_update_deck_name_field()
	save_status_label.text = "空の「%s」を作成しました。カードを追加して保存してください。" % new_name


func _deck_name_exists(deck_name: String) -> bool:
	for profile in profiles.values():
		if str(profile.get("name", "")) == deck_name:
			return true
	return false


func _refresh_all() -> void:
	_refresh_main_deck()
	_refresh_promotion_deck()
	_refresh_pool()
	main_mode_button.button_pressed = editing_mode == "main"
	promotion_mode_button.button_pressed = editing_mode == "promotion"


func _refresh_pool() -> void:
	_clear_container(active_available_list)
	if editing_mode == "main":
		for card_name in CardDatabase.get_card_names_for_categories(["兵", "壁", "罠"]):
			var card: Dictionary = CardDatabase.get_card(card_name)
			if card.is_empty() or not ["兵", "壁", "罠"].has(str(card.get("category", ""))):
				continue
			var count := _count_card(main_deck, card_name)
			var max_copies := int(card.get("max_copies", 2))
			var tile = _make_card_tile(
				card_name, card, "pool", "main", -1,
				"採用 %d" % count, POOL_TILE_SIZE
			)
			tile.disabled = main_deck.size() >= 20 or (max_copies >= 0 and count >= max_copies)
			active_available_list.add_child(tile)
	else:
		for card_name in CardDatabase.get_card_names_for_categories(["成"]):
			var card: Dictionary = CardDatabase.get_card(card_name)
			if card.is_empty() or str(card.get("category", "")) != "成":
				continue
			var count := _count_card(promotion_deck, card_name)
			var max_copies := int(card.get("max_copies", 2))
			var tile = _make_card_tile(
				card_name, card, "pool", "promotion", -1,
				"採用 %d" % count, POOL_TILE_SIZE
			)
			tile.disabled = promotion_deck.size() >= 5 or (max_copies >= 0 and count >= max_copies)
			active_available_list.add_child(tile)


func _refresh_main_deck() -> void:
	_clear_container(main_deck_list)
	var display_indices := _sorted_display_indices(main_deck)
	for source_index in display_indices:
		var card_name: String = main_deck[source_index]
		var card: Dictionary = CardDatabase.get_card(card_name)
		var tile = _make_card_tile(card_name, card, "deck", "main", source_index, "", DECK_TILE_SIZE)
		main_deck_list.add_child(tile)

	# 常に20マスを維持して、5列×4行の見た目を固定する。
	for _i in range(main_deck.size(), 20):
		main_deck_list.add_child(_make_empty_slot(DECK_TILE_SIZE))

	main_summary_label.text = "%d/20枚　デッキコスト %d/20" % [main_deck.size(), _get_total_cost(main_deck)]


func _refresh_promotion_deck() -> void:
	_clear_container(promotion_deck_list)
	var display_indices := _sorted_display_indices(promotion_deck)
	for source_index in display_indices:
		var card_name: String = promotion_deck[source_index]
		var card: Dictionary = CardDatabase.get_card(card_name)
		var tile = _make_card_tile(card_name, card, "deck", "promotion", source_index, "", DECK_TILE_SIZE)
		promotion_deck_list.add_child(tile)

	# 常に5マスを維持して、5列×1行の見た目を固定する。
	for _i in range(promotion_deck.size(), 5):
		promotion_deck_list.add_child(_make_empty_slot(DECK_TILE_SIZE))

	promotion_summary_label.text = "%d/5枚" % promotion_deck.size()


func _make_empty_slot(tile_size: Vector2) -> Control:
	var slot := PanelContainer.new()
	slot.custom_minimum_size = Vector2(tile_size.x + 6.0, tile_size.y + 6.0)
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.11, 0.16, 0.42)
	style.border_color = Color(0.29, 0.34, 0.42, 0.78)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	slot.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.text = "空き"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.modulate = Color(0.46, 0.51, 0.60)
	label.add_theme_font_size_override("font_size", 10)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(label)
	return slot


func _make_card_tile(
	card_name: String,
	card: Dictionary,
	source_zone: String,
	list_type: String,
	source_index: int,
	count_text: String,
	tile_size: Vector2
):
	var texture: Texture2D = _get_card_texture(card_name)
	var tile = CardTileScript.new()
	tile.setup(card_name, card, texture, source_zone, list_type, source_index, count_text, tile_size)
	tile.clicked.connect(_on_card_tile_clicked)
	return tile


func _get_card_texture(card_name: String) -> Texture2D:
	if card_texture_cache.has(card_name):
		var cached = card_texture_cache[card_name]
		if cached is Texture2D:
			return cached
		return null

	var card: Dictionary = CardDatabase.get_card(card_name)
	var image_path := str(card.get("image_path", ""))
	if image_path.is_empty():
		card_texture_cache[card_name] = null
		return null
	if not ResourceLoader.exists(image_path):
		card_texture_cache[card_name] = null
		return null

	var loaded_resource: Resource = load(image_path)
	if loaded_resource is Texture2D:
		var texture := loaded_resource as Texture2D
		card_texture_cache[card_name] = texture
		return texture

	card_texture_cache[card_name] = null
	return null


func _sorted_display_indices(card_names: Array[String]) -> Array[int]:
	var indices: Array[int] = []
	for i in range(card_names.size()):
		indices.append(i)
	indices.sort_custom(func(a: int, b: int) -> bool:
		var card_a: Dictionary = CardDatabase.get_card(card_names[a])
		var card_b: Dictionary = CardDatabase.get_card(card_names[b])
		var order_a := int(card_a.get("sort_order", 9999))
		var order_b := int(card_b.get("sort_order", 9999))
		if order_a == order_b:
			if card_names[a] == card_names[b]:
				return a < b
			return card_names[a] < card_names[b]
		return order_a < order_b
	)
	return indices


func _on_card_tile_clicked(card_name: String, source_zone: String, list_type: String, source_index: int) -> void:
	if source_zone == "pool":
		_add_card_to_deck(card_name, list_type)
	else:
		_remove_card_from_deck(source_index, list_type)


func can_accept_card_drop(target_zone: String, target_list_type: String, data: Variant) -> bool:
	if not (data is Dictionary):
		return false
	var source_zone := str(data.get("source_zone", ""))
	var source_list_type := str(data.get("list_type", ""))
	if source_list_type != target_list_type:
		return false
	if target_zone == "deck" and source_zone == "pool":
		return true
	if target_zone == "pool" and source_zone == "deck":
		return true
	return false


func process_card_drop(target_zone: String, target_list_type: String, data: Variant) -> void:
	if not can_accept_card_drop(target_zone, target_list_type, data):
		return
	var card_name := str(data.get("card_name", ""))
	var source_zone := str(data.get("source_zone", ""))
	var source_index := int(data.get("source_index", -1))
	if target_zone == "deck" and source_zone == "pool":
		_add_card_to_deck(card_name, target_list_type)
	elif target_zone == "pool" and source_zone == "deck":
		_remove_card_from_deck(source_index, target_list_type)


func _add_card_to_deck(card_name: String, list_type: String) -> void:
	var card: Dictionary = CardDatabase.get_card(card_name)
	if card.is_empty():
		return
	var target_deck: Array[String] = main_deck if list_type == "main" else promotion_deck
	var max_cards: int = 20 if list_type == "main" else 5
	if target_deck.size() >= max_cards:
		validation_label.text = "このデッキは%d枚までです。" % max_cards
		return
	var category := str(card.get("category", ""))
	if list_type == "main" and not ["兵", "壁", "罠"].has(category):
		return
	if list_type == "promotion" and category != "成":
		return
	var max_copies := int(card.get("max_copies", 2))
	var current_copies := _count_card(target_deck, card_name)
	if max_copies >= 0 and current_copies >= max_copies:
		validation_label.text = "%sは同名上限%d枚です。" % [card_name, max_copies]
		return

	target_deck.append(card_name)
	_store_editing_profile()
	validation_label.text = ""
	if list_type == "main":
		_refresh_main_deck()
	else:
		_refresh_promotion_deck()
	_refresh_pool()


func _remove_card_from_deck(source_index: int, list_type: String) -> void:
	var target_deck: Array[String] = main_deck if list_type == "main" else promotion_deck
	if source_index < 0 or source_index >= target_deck.size():
		return
	target_deck.remove_at(source_index)
	_store_editing_profile()
	validation_label.text = ""
	if list_type == "main":
		_refresh_main_deck()
	else:
		_refresh_promotion_deck()
	_refresh_pool()


func _validate_current_deck() -> void:
	if editing_mode == "main":
		var result: Dictionary = DeckRules.validate_main_deck(main_deck)
		validation_label.text = _validation_result_text(result)
	else:
		var result: Dictionary = DeckRules.validate_promotion_deck(promotion_deck)
		validation_label.text = _validation_result_text(result)


func _validation_result_text(result: Dictionary) -> String:
	if bool(result.get("valid", false)):
		return "構築条件OK"
	var errors := PackedStringArray()
	for error_message in result.get("errors", []):
		errors.append(str(error_message))
	return "\n".join(errors)


func _get_total_cost(card_names: Array[String]) -> int:
	var total := 0
	for card_name in card_names:
		var card: Dictionary = CardDatabase.get_card(card_name)
		total += int(card.get("deckcost", 0))
	return total


func _count_card(card_names: Array[String], target_name: String) -> int:
	var count := 0
	for card_name in card_names:
		if card_name == target_name:
			count += 1
	return count


func _clear_container(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()


func _store_editing_profile() -> void:
	var existing: Dictionary = profiles.get(active_profile_id, {})
	profiles[active_profile_id] = {
		"name": str(existing.get("name", active_profile_id)),
		"main_deck": main_deck.duplicate(),
		"promotion_deck": promotion_deck.duplicate()
	}


func _load_profile_into_editor() -> void:
	var profile: Dictionary = profiles.get(active_profile_id, {"name": active_profile_id, "main_deck": [], "promotion_deck": []})
	main_deck.clear()
	for raw_name in profile.get("main_deck", []):
		main_deck.append(str(raw_name))
	promotion_deck.clear()
	for raw_name in profile.get("promotion_deck", []):
		promotion_deck.append(str(raw_name))
	_update_deck_name_field()


func _save_decks() -> void:
	_store_editing_profile()
	var result: Dictionary = DeckLibrary.save_library(profiles, active_profile_id)
	if not bool(result.get("ok", false)):
		save_status_label.text = "保存できませんでした：%s" % str(result.get("error", "不明なエラー"))
		return
	save_status_label.text = "%d組のデッキを保存しました。\n保存先：%s" % [profiles.size(), DECK_SAVE_PATH]


func _load_decks() -> void:
	var loaded_library: Dictionary = DeckLibrary.load_library()
	if not bool(loaded_library.get("valid", false)):
		save_status_label.text = str(loaded_library.get("message", "保存データを読み込めませんでした。"))
		return
	profiles = loaded_library.get("decks", DeckLibrary.default_decks())
	active_profile_id = str(loaded_library.get("last_selected_deck_id", "deck_1"))
	if not profiles.has(active_profile_id):
		active_profile_id = DeckLibrary.ordered_deck_ids(profiles)[0]
	_refresh_profile_selector()
	_load_profile_into_editor()
	_refresh_all()
	save_status_label.text = str(loaded_library.get("message", "保存デッキを読み込みました。"))
