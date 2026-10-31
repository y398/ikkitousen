# ==================================================
# ファイル名: PromotionChoiceDialog.gd
# 概要: 敵陣進入時に成る成駒の選択肢ボタンおよび成らずの選択を提供する確認ダイアログクラスである
# ==================================================

extends ConfirmationDialog
## 成り先を選択肢ボタンとして直接表示するダイアログ
## 成り候補と盤面更新は MainGame.gd が管理し、このスクリプトは表示と入力だけを担当する

signal promotion_selected(card_name: String)
signal promotion_declined

const CHOICE_FONT_SIZE: int = 24
const PROMPT_FONT_SIZE: int = 24
const BUTTON_MIN_HEIGHT: float = 54.0

var prompt_label: Label
var choices_margin: MarginContainer
var choices_container: VBoxContainer
var _choice_finished: bool = false


func _ready() -> void:
	title = "成りの選択"
	min_size = Vector2i(520, 280)
	get_ok_button().hide()
	get_cancel_button().hide()

	prompt_label = get_label()
	prompt_label.add_theme_font_size_override("font_size", PROMPT_FONT_SIZE)
	prompt_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prompt_label.custom_minimum_size = Vector2(460.0, 56.0)

	# プロンプトとボタンが詰まらないよう、選択肢全体の上に余白を設ける。
	choices_margin = MarginContainer.new()
	choices_margin.name = "PromotionChoicesMargin"
	choices_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	choices_margin.add_theme_constant_override("margin_top", 60)

	choices_container = VBoxContainer.new()
	choices_container.name = "PromotionChoices"
	choices_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	choices_container.add_theme_constant_override("separation", 10)
	choices_margin.add_child(choices_container)

	var content_parent: Node = prompt_label.get_parent()
	content_parent.add_child(choices_margin)
	content_parent.move_child(choices_margin, prompt_label.get_index() + 1)

	canceled.connect(_on_window_cancelled)
	close_requested.connect(_on_window_close_requested)


func show_for_piece(piece_name: String, promotion_names: Array[String]) -> void:
	_choice_finished = false
	prompt_label.text = "%sは成ることができます。" % piece_name
	for child in choices_container.get_children():
		choices_container.remove_child(child)
		child.queue_free()

	for promotion_name in promotion_names:
		var choice_button := Button.new()
		choice_button.text = "%sに成る" % promotion_name
		choice_button.custom_minimum_size = Vector2(460.0, BUTTON_MIN_HEIGHT)
		choice_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		choice_button.add_theme_font_size_override("font_size", CHOICE_FONT_SIZE)
		choice_button.pressed.connect(_on_choice_button_pressed.bind(promotion_name))
		choices_container.add_child(choice_button)

	var decline_button := Button.new()
	decline_button.text = "成らない"
	decline_button.custom_minimum_size = Vector2(460.0, BUTTON_MIN_HEIGHT)
	decline_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	decline_button.add_theme_font_size_override("font_size", CHOICE_FONT_SIZE)
	decline_button.pressed.connect(_on_decline_button_pressed)
	choices_container.add_child(decline_button)

	# 上部の説明文・上余白・全ボタンが収まる高さを確保する。
	var dialog_height: int = 170 + (promotion_names.size() + 1) * int(BUTTON_MIN_HEIGHT + 10.0)
	popup_centered(Vector2i(540, maxi(300, dialog_height)))


func _on_choice_button_pressed(card_name: String) -> void:
	if _choice_finished:
		return
	_choice_finished = true
	hide()
	promotion_selected.emit(card_name)


func _on_decline_button_pressed() -> void:
	_finish_as_declined()


func _on_window_cancelled() -> void:
	_finish_as_declined()


func _on_window_close_requested() -> void:
	_finish_as_declined()


func _finish_as_declined() -> void:
	if _choice_finished:
		return
	_choice_finished = true
	hide()
	promotion_declined.emit()
