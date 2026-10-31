# ==================================================
# ファイル名: P2PNetwork.gd
# 概要: WebRTCを使用したP2P通信（手動シグナリング・DataChannelによるデータ送受信）を管理するネットワーククラスである
# ==================================================

extends Node

signal session_code_ready(role_type: String, code: String)
signal connection_established
signal connection_closed
signal message_received(message: Dictionary)
signal log_updated(text: String)
signal connection_error(error_message: String)

const STUN_SERVER := "stun:stun.l.google.com:19302"

enum Role {
	NONE,
	HOST,
	GUEST
}

var peer: WebRTCPeerConnection
var data_channel: WebRTCDataChannel
var current_role: Role = Role.NONE
var local_candidates: Array[Dictionary] = []
var pending_remote_candidates: Array[Dictionary] = []
var candidate_collection_timer: Timer
var is_collecting_candidates: bool = false
var local_session_type: String = ""
var local_sdp: String = ""
var is_connected_peer: bool = false

# 対局セッション同期用プロパティ
var is_p2p_match: bool = false
var local_player_id: int = 0 # 0: 先手(ホスト), 1: 後手(ゲスト)
var shared_random_seed: int = 0
var host_deck_profile: Dictionary = {}
var guest_deck_profile: Dictionary = {}


func _ready() -> void:
	candidate_collection_timer = Timer.new()
	candidate_collection_timer.one_shot = true
	candidate_collection_timer.wait_time = 1.0
	candidate_collection_timer.timeout.connect(_on_candidate_collection_timeout)
	add_child(candidate_collection_timer)


func _process(_delta: float) -> void:
	if peer != null:
		peer.poll()

	if data_channel != null and data_channel.get_ready_state() == WebRTCDataChannel.STATE_OPEN:
		if not is_connected_peer:
			is_connected_peer = true
			log_updated.emit("P2P接続が確立された")
			connection_established.emit()

		while data_channel.get_available_packet_count() > 0:
			var packet := data_channel.get_packet()
			var json_string := packet.get_string_from_utf8()
			var parsed: Variant = JSON.parse_string(json_string)
			if parsed is Dictionary:
				message_received.emit(parsed)
			else:
				log_updated.emit("受信パケットのJSONパースに失敗した: " + json_string)
	elif is_connected_peer:
		if data_channel == null or data_channel.get_ready_state() == WebRTCDataChannel.STATE_CLOSED:
			is_connected_peer = false
			log_updated.emit("P2P接続が切断された")
			connection_closed.emit()


# ホストとして初期化し、Offerコードの生成を開始する
func start_host() -> bool:
	_cleanup()
	current_role = Role.HOST
	if not _setup_peer():
		return false

	data_channel = peer.create_data_channel("game_channel", {"ordered": true})
	if data_channel == null:
		connection_error.emit("DataChannelの作成に失敗した（デスクトップ実行にはwebrtc GDExtensionが必要である）")
		return false
	data_channel.write_mode = WebRTCDataChannel.WRITE_MODE_TEXT

	var error: Error = peer.create_offer()
	if error != OK:
		connection_error.emit("Offerの生成に失敗した（エラーコード: %d）" % error)
		return false

	log_updated.emit("ホストを初期化し、接続コードを生成中である")
	return true


# ゲストとして初期化し、ホストのOfferコードを読み込む準備をする
func start_guest() -> bool:
	_cleanup()
	current_role = Role.GUEST
	if not _setup_peer():
		return false

	log_updated.emit("ゲストとして初期化完了した")
	return true


func _setup_peer() -> bool:
	peer = WebRTCPeerConnection.new()
	var config := {
		"iceServers": [
			{"urls": [STUN_SERVER]}
		]
	}
	var error: Error = peer.initialize(config)
	if error != OK:
		connection_error.emit("WebRTCの初期化に失敗した（エラーコード: %d）" % error)
		return false

	peer.session_description_created.connect(_on_session_description_created)
	peer.ice_candidate_created.connect(_on_ice_candidate_created)
	peer.data_channel_received.connect(_on_data_channel_received)
	return true


func _on_data_channel_received(channel: WebRTCDataChannel) -> void:
	if channel == null:
		return
	data_channel = channel
	data_channel.write_mode = WebRTCDataChannel.WRITE_MODE_TEXT
	log_updated.emit("データ通信チャンネルを受信した")


func _on_session_description_created(type: String, sdp: String) -> void:
	peer.set_local_description(type, sdp)
	local_session_type = type
	local_sdp = sdp
	local_candidates.clear()
	is_collecting_candidates = true
	# 候補の収集完了を少し待ってから1本のコードにまとめる
	candidate_collection_timer.start(1.2)


func _on_ice_candidate_created(media: String, index: int, candidate_name: String) -> void:
	local_candidates.append({
		"media": media,
		"index": index,
		"name": candidate_name
	})
	if is_collecting_candidates:
		# 候補が追加されるたびにタイマーをリセットして収集待機を延長する
		candidate_collection_timer.start(0.5)


func _on_candidate_collection_timeout() -> void:
	is_collecting_candidates = false
	var payload := {
		"type": local_session_type,
		"sdp": local_sdp,
		"candidates": local_candidates
	}
	var json_text := JSON.stringify(payload)
	var base64_code := Marshalls.utf8_to_base64(json_text)
	log_updated.emit("%sコードの生成が完了した" % ("オファー" if local_session_type == "offer" else "アンサー"))
	session_code_ready.emit(local_session_type, base64_code)


# 相手から受け取った接続コードを読み込んで適用する
func apply_remote_code(code_text: String) -> bool:
	var clean_code := code_text.strip_edges()
	if clean_code.is_empty():
		connection_error.emit("接続コードが空である")
		return false

	var json_text := Marshalls.base64_to_utf8(clean_code)
	var parsed: Variant = JSON.parse_string(json_text)
	if not (parsed is Dictionary):
		connection_error.emit("接続コードの解析に失敗した（不正な形式）")
		return false

	var payload: Dictionary = parsed
	var type: String = str(payload.get("type", ""))
	var sdp: String = str(payload.get("sdp", ""))
	var raw_candidates: Variant = payload.get("candidates", [])

	if type.is_empty() or sdp.is_empty():
		connection_error.emit("接続コードに必要な情報（type/sdp）が含まれていない")
		return false

	var error: Error = peer.set_remote_description(type, sdp)
	if error != OK:
		connection_error.emit("RemoteDescriptionの設定に失敗した（エラーコード: %d）" % error)
		return false

	# ゲスト側はオファーを受信したら自動的にアンサーを生成する
	if type == "offer" and current_role == Role.GUEST:
		var answer_error: Error = peer.create_answer()
		if answer_error != OK:
			connection_error.emit("Answerの生成に失敗した（エラーコード: %d）" % answer_error)
			return false
		log_updated.emit("オファーを適用し、アンサーを生成中である")

	# 相手側のCandidateを反映する
	if raw_candidates is Array:
		for candidate_variant in raw_candidates:
			if candidate_variant is Dictionary:
				var c: Dictionary = candidate_variant
				var media: String = str(c.get("media", ""))
				var index: int = int(c.get("index", 0))
				var c_name: String = str(c.get("name", ""))
				peer.add_ice_candidate(media, index, c_name)

	log_updated.emit("%sコードを正常に適用した" % ("オファー" if type == "offer" else "アンサー"))
	return true


# 接続相手にJSONメッセージを送信する
func send_message(dict: Dictionary) -> bool:
	if data_channel == null or data_channel.get_ready_state() != WebRTCDataChannel.STATE_OPEN:
		log_updated.emit("送信失敗: データチャンネルが開いていない")
		return false

	var json_string := JSON.stringify(dict)
	var error := data_channel.put_packet(json_string.to_utf8_buffer())
	if error != OK:
		log_updated.emit("パケット送信エラー: %d" % error)
		return false
	return true


# 接続を安全に閉じて初期化する
func close_connection() -> void:
	_cleanup()
	log_updated.emit("接続を終了した")


func _cleanup() -> void:
	is_connected_peer = false
	is_collecting_candidates = false
	if candidate_collection_timer != null:
		candidate_collection_timer.stop()
	if data_channel != null:
		data_channel.close()
		data_channel = null
	if peer != null:
		peer.close()
		peer = null
	local_candidates.clear()
	pending_remote_candidates.clear()
	local_session_type = ""
	local_sdp = ""
	current_role = Role.NONE
	is_p2p_match = false
	local_player_id = 0
	shared_random_seed = 0
	host_deck_profile.clear()
	guest_deck_profile.clear()
