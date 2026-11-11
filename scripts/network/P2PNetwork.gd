# ==================================================
# ファイル名: P2PNetwork.gd
# 概要: WebRTCを使用したP2P通信（手動シグナリング・DataChannelによるデータ送受信）を管理するネットワーククラスである
# ==================================================

extends Node

signal session_code_ready(role_type: String, code: String)
signal connection_established
signal connection_closed
signal connection_reconnecting(remaining_time: float)
signal connection_reconnected
signal message_received(message: Dictionary)
signal log_updated(text: String)
signal connection_error(error_message: String)

const STUN_SERVER := "stun:stun.l.google.com:19302"

# 一時切断時の再接続待機猶予秒数（ターン制対戦向けの安全時間である）
const RECONNECT_GRACE_PERIOD: float = 8.0

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

# 再接続待機状態の管理フラグおよび残り秒数タイマー
var is_reconnecting: bool = false
var reconnect_timer: float = 0.0

# 対局セッション同期用プロパティ
var is_p2p_match: bool = false
var local_player_id: int = 0 # 0: 先手, 1: 後手
var shared_random_seed: int = 0
var host_deck_profile: Dictionary = {}
var guest_deck_profile: Dictionary = {}
var local_nickname: String = "プレイヤー"
var remote_nickname: String = "対戦相手"


func _ready() -> void:
	candidate_collection_timer = Timer.new()
	candidate_collection_timer.one_shot = true
	candidate_collection_timer.wait_time = 1.0
	candidate_collection_timer.timeout.connect(_on_candidate_collection_timeout)
	add_child(candidate_collection_timer)


func _process(delta: float) -> void:
	if peer != null:
		peer.poll()
		if is_connected_peer:
			var conn_state := peer.get_connection_state()

			# 一時切断（DISCONNECTEDまたはFAILED）の検知と猶予タイマー処理
			if conn_state == WebRTCPeerConnection.STATE_DISCONNECTED or conn_state == WebRTCPeerConnection.STATE_FAILED:
				if not is_reconnecting:
					is_reconnecting = true
					reconnect_timer = RECONNECT_GRACE_PERIOD
					log_updated.emit("P2P接続が一時切断された（再接続待機中: %.1f秒）" % reconnect_timer)
					connection_reconnecting.emit(reconnect_timer)
				else:
					reconnect_timer -= delta
					if reconnect_timer <= 0.0:
						is_connected_peer = false
						is_reconnecting = false
						reconnect_timer = 0.0
						log_updated.emit("再接続タイムアウト: P2P接続が切断された")
						connection_closed.emit()

			# 明示的な切断（CLOSED）時は即時切断とする
			elif conn_state == WebRTCPeerConnection.STATE_CLOSED:
				is_connected_peer = false
				is_reconnecting = false
				reconnect_timer = 0.0
				log_updated.emit("P2P接続が終了された")
				connection_closed.emit()

			# 再接続待機中に接続状態がCONNECTEDに復帰した場合
			elif is_reconnecting and conn_state == WebRTCPeerConnection.STATE_CONNECTED:
				if data_channel != null and data_channel.get_ready_state() == WebRTCDataChannel.STATE_OPEN:
					is_reconnecting = false
					reconnect_timer = 0.0
					log_updated.emit("P2P接続が正常に復帰した")
					connection_reconnected.emit()

	if data_channel != null and data_channel.get_ready_state() == WebRTCDataChannel.STATE_OPEN:
		if not is_connected_peer:
			is_connected_peer = true
			log_updated.emit("P2P接続が確立された")
			connection_established.emit()
		elif is_reconnecting:
			# DataChannelが開いておりpeerがCONNECTEDであれば復帰とする
			if peer != null and peer.get_connection_state() == WebRTCPeerConnection.STATE_CONNECTED:
				is_reconnecting = false
				reconnect_timer = 0.0
				log_updated.emit("P2P接続（データチャンネル）が復帰した")
				connection_reconnected.emit()

		while data_channel.get_available_packet_count() > 0:
			var packet := data_channel.get_packet()
			var json_string := packet.get_string_from_utf8()
			var parsed: Variant = JSON.parse_string(json_string)
			if parsed is Dictionary:
				message_received.emit(parsed)
			else:
				log_updated.emit("受信パケットのJSONパースに失敗した: " + json_string)
	elif is_connected_peer:
		if not is_reconnecting:
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


# セッション情報（SDPおよびCandidates）を圧縮してBase64接続コードを生成する
func encode_session_payload(session_type: String, sdp: String, candidates: Array) -> String:
	var payload := {
		"t": session_type,
		"s": sdp,
		"c": []
	}
	for cand in candidates:
		if cand is Dictionary:
			payload["c"].append({
				"m": cand.get("m", cand.get("media", "")),
				"i": cand.get("i", cand.get("index", 0)),
				"n": cand.get("n", cand.get("name", ""))
			})

	var json_text := JSON.stringify(payload)
	var raw_bytes := json_text.to_utf8_buffer()
	var compressed := raw_bytes.compress(FileAccess.COMPRESSION_DEFLATE)
	return "Z1:" + Marshalls.raw_to_base64(compressed)


# 接続コード（圧縮または旧非圧縮形式）を解析してセッション辞書を復元する
func decode_session_code(code_text: String) -> Dictionary:
	var clean_code := code_text.strip_edges()
	if clean_code.is_empty():
		return {"ok": false, "error": "接続コードが空である"}

	var json_text := ""
	if clean_code.begins_with("Z1:"):
		var raw_base64 := clean_code.substr(3)
		var compressed_bytes := Marshalls.base64_to_raw(raw_base64)
		if compressed_bytes.is_empty():
			return {"ok": false, "error": "Base64デコードに失敗した"}
		var decompressed := compressed_bytes.decompress_dynamic(1024 * 1024, FileAccess.COMPRESSION_DEFLATE)
		if decompressed.is_empty():
			decompressed = compressed_bytes.decompress(65536, FileAccess.COMPRESSION_DEFLATE)
		if decompressed.is_empty():
			return {"ok": false, "error": "接続コードの解凍に失敗した"}
		json_text = decompressed.get_string_from_utf8()
	else:
		# 旧形式（非圧縮Base64）との互換性
		json_text = Marshalls.base64_to_utf8(clean_code)

	var parsed: Variant = JSON.parse_string(json_text)
	if not (parsed is Dictionary):
		return {"ok": false, "error": "JSONパースに失敗した"}

	var payload: Dictionary = parsed
	var type: String = str(payload.get("t", payload.get("type", "")))
	var sdp: String = str(payload.get("s", payload.get("sdp", "")))
	var raw_candidates: Variant = payload.get("c", payload.get("candidates", []))

	if type.is_empty() or sdp.is_empty():
		return {"ok": false, "error": "必要な情報（type/sdp）が含まれていない"}

	var normalized_candidates: Array[Dictionary] = []
	if raw_candidates is Array:
		for c_var in raw_candidates:
			if c_var is Dictionary:
				normalized_candidates.append({
					"media": str(c_var.get("m", c_var.get("media", ""))),
					"index": int(c_var.get("i", c_var.get("index", 0))),
					"name": str(c_var.get("n", c_var.get("name", "")))
				})

	return {
		"ok": true,
		"type": type,
		"sdp": sdp,
		"candidates": normalized_candidates
	}


func _on_candidate_collection_timeout() -> void:
	is_collecting_candidates = false
	var compressed_code := encode_session_payload(local_session_type, local_sdp, local_candidates)
	log_updated.emit("%sコードの生成が完了した（圧縮コード長: %d文字）" % [
		"オファー" if local_session_type == "offer" else "アンサー",
		compressed_code.length()
	])
	session_code_ready.emit(local_session_type, compressed_code)


# 相手から受け取った接続コードを読み込んで適用する
func apply_remote_code(code_text: String) -> bool:
	var decoded := decode_session_code(code_text)
	if not bool(decoded.get("ok", false)):
		connection_error.emit(str(decoded.get("error", "接続コードの解析に失敗した")))
		return false

	var type: String = str(decoded["type"])
	var sdp: String = str(decoded["sdp"])
	var candidates: Array = decoded["candidates"]

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
	for c in candidates:
		if c is Dictionary:
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
	is_reconnecting = false
	reconnect_timer = 0.0
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
