extends SceneTree
# Native side of scripts/test-direct-interop.mjs: two direct links through
# direct_native.gd, the adapter direct_link.gd uses on desktop and Android.
# Link "host" answers the browser's offer (browser guest -> native host), link
# "guest" offers to the browser (native guest -> browser host). Signaling goes
# over TCP, one JSON object per line. Each open channel sends one packet and
# echoes back whatever it receives.
const DirectNative = preload("res://scripts/net/direct_native.gd")

var tcp := StreamPeerTCP.new()
var buffer := ""
var links: Dictionary = {}
var channels: Dictionary = {}
var greeted: Dictionary = {}
var received: Dictionary = {}

func _initialize() -> void:
	var port = 0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--port="):
			port = int(arg.trim_prefix("--port="))
	for name in ["host", "guest"]:
		var pc = DirectNative.create()
		if pc == null:
			printerr("DIRECT_INTEROP no native extension")
			quit(2)
			return
		pc.initialize({"iceServers": []})
		channels[name] = pc.create_data_channel("fast", {"negotiated": true, "id": 1, "ordered": false, "maxRetransmits": 0})
		pc.session_description_created.connect(func(type, sdp): send({"type": "signal", "link": name, "kind": type, "sdp": sdp}))
		pc.ice_candidate_created.connect(func(media, index, candidate): send({"type": "signal", "link": name, "kind": "candidate", "mid": media, "index": index, "candidate": candidate}))
		links[name] = pc
		received[name] = []
	tcp.connect_to_host("127.0.0.1", port)

func send(message: Dictionary) -> void:
	tcp.put_data((JSON.stringify(message) + "\n").to_utf8_buffer())

func _process(_delta: float) -> bool:
	tcp.poll()
	if tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return false
	if not links.guest.link:
		links.guest.create_offer()
	var available = tcp.get_available_bytes()
	if available > 0:
		buffer += tcp.get_utf8_string(available)
	while buffer.contains("\n"):
		var line = buffer.left(buffer.find("\n"))
		buffer = buffer.substr(buffer.find("\n") + 1)
		var message = JSON.parse_string(line)
		if message is Dictionary:
			if message.type == "quit":
				for pc in links.values():
					pc.close()
				return true
			var pc = links[str(message.link)]
			if message.kind == "candidate":
				pc.add_ice_candidate(str(message.mid), int(message.index), str(message.candidate))
			else:
				pc.set_remote_description(str(message.kind), str(message.sdp))
	for name in links:
		links[name].poll()
		var channel = channels[name]
		if channel.get_ready_state() == 1 and not greeted.has(name):
			greeted[name] = true
			channel.put_packet(("native-" + name).to_utf8_buffer())
		while channel.get_available_packet_count() > 0:
			var text = channel.get_packet().get_string_from_utf8()
			received[name].append(text)
			if not text.begins_with("echo:"):
				channel.put_packet(("echo:" + text).to_utf8_buffer())
	send({"type": "report", "open": channels.keys().filter(func(n): return channels[n].get_ready_state() == 1), "received": received})
	return false
