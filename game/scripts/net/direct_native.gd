extends RefCounted
# The direct link's peer connection on desktop and Android. It wraps
# RallyDataLink from the native/voice GDExtension (libdatachannel) in the part
# of Godot's WebRTCPeerConnection / WebRTCDataChannel API that direct_link.gd
# uses, so the link code is the same as in browser builds and native and
# browser players link to each other.
const VoiceNative = preload("res://scripts/net/voice_native.gd")

signal session_description_created(type: String, sdp: String)
signal ice_candidate_created(media: String, index: int, name: String)

# WebRTCPeerConnection.ConnectionState
const STATES = {"new": 0, "connecting": 1, "connected": 2, "disconnected": 3, "failed": 4, "closed": 5}

class Channel:
	extends RefCounted
	# WebRTCDataChannel.ChannelState: connecting, open, closing, closed.
	const READY = {"connecting": 0, "open": 1, "closed": 3}
	var owner
	var write_mode = 1
	var received: Array = []

	func get_ready_state() -> int:
		if owner == null:
			return 3
		return READY.get(owner.link.get_channel_state(), 0) if owner.link != null else 0

	func get_available_packet_count() -> int:
		return received.size()

	func get_packet() -> PackedByteArray:
		return received.pop_front() if not received.is_empty() else PackedByteArray()

	func put_packet(bytes: PackedByteArray) -> Error:
		return OK if owner != null and owner.link != null and owner.link.send(bytes) else FAILED

	func close() -> void:
		if owner != null:
			owner.close()

var link = null
var ice_servers := PackedStringArray()
var channel: Channel
var closed = false

# The library ships inside the pack and loads on first use (voice_native.gd).
static func available() -> bool:
	return VoiceNative.supported()

static func create():
	return new() if VoiceNative.load_extension() and ClassDB.class_exists("RallyDataLink") else null

func initialize(config: Dictionary) -> Error:
	for server in config.get("iceServers", []):
		for url in server.get("urls", []):
			ice_servers.append(str(url))
	return OK

func create_data_channel(_label: String, _options: Dictionary) -> Channel:
	channel = Channel.new()
	channel.owner = self
	return channel

# The native side negotiates when it knows its role: here, or on the offer.
func create_offer() -> Error:
	return _start(true)

func set_local_description(_type: String, _sdp: String) -> Error:
	return OK

func set_remote_description(type: String, sdp: String) -> Error:
	if type == "offer" and link == null and _start(false) != OK:
		return FAILED
	return link.set_remote_description(type, sdp) if link != null else ERR_UNCONFIGURED

func add_ice_candidate(media: String, _index: int, name: String) -> Error:
	return link.add_ice_candidate(name, media) if link != null else ERR_UNCONFIGURED

func _start(offer: bool) -> Error:
	if link != null or closed:
		return ERR_ALREADY_IN_USE
	link = ClassDB.instantiate("RallyDataLink")
	return link.initialize(ice_servers, offer)

func poll() -> Error:
	if link == null:
		return OK
	for event in link.poll():
		match str(event.get("type", "")):
			"description": session_description_created.emit(str(event.sdp_type), str(event.sdp))
			"candidate": ice_candidate_created.emit(str(event.mid), 0, str(event.candidate))
			"error": push_warning("Direct link: " + str(event.message))
	if channel != null:
		channel.received.append_array(link.get_packets())
	return OK

func get_connection_state() -> int:
	if closed:
		return STATES.closed
	return STATES.get(link.get_state(), 0) if link != null else 0

func close() -> void:
	closed = true
	if link != null:
		link.close()
		link = null
	# The channel and the connection refer to each other.
	if channel != null:
		channel.owner = null
