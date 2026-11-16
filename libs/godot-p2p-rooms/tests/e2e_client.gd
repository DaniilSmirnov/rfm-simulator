extends SceneTree
# One side of the end-to-end check (tests/run-e2e.mjs): a host and a guest
# meet through the room server and talk over a real WebRTC link.
#   godot --headless --path . --script res://tests/e2e_client.gd -- --server=URL --role=host
#   godot --headless --path . --script res://tests/e2e_client.gd -- --server=URL --role=guest --room=ID
const P2PRoomsScript = preload("res://addons/p2p_rooms/p2p_rooms.gd")

var rooms
var role := ""
var room := ""
var got := {}
var step := ""
var started := 0.0


func _initialize() -> void:
	var server := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--server="): server = arg.trim_prefix("--server=")
		if arg.begins_with("--role="): role = arg.trim_prefix("--role=")
		if arg.begins_with("--room="): room = arg.trim_prefix("--room=")
	started = Time.get_ticks_msec() / 1000.0
	rooms = P2PRoomsScript.new()
	rooms.server_url = server
	# Both sides run on this machine: host candidates are enough.
	rooms.ice_servers = []
	root.add_child(rooms)
	rooms.room_failed.connect(_on_failed)
	rooms.room_joined.connect(func(id, me, host): print("JOINED ", id, " ", me, " host=", host))
	rooms.members_changed.connect(func(list): print(role.to_upper(), " MEMBERS ", list.map(func(m): return m.name)))
	rooms.message_received.connect(_on_message)
	rooms.peer_connected.connect(_on_connected)
	rooms.peer_disconnected.connect(_on_disconnected)
	rooms.room_closed.connect(func(reason): print(role.to_upper(), " CLOSED ", reason))
	# The node enters the tree on the next frame.
	_start.call_deferred()


func _start() -> void:
	if role == "host":
		rooms.room_joined.connect(func(id, _me, _host): print("ROOM ", id))
		rooms.create_room("Хост")
	else:
		# Another game's protocol number must not get in.
		step = "wrong_protocol"
		rooms.app_protocol = 999
		rooms.join_room(room, "Гость")


func _on_failed(error: String, status: int) -> void:
	if step == "wrong_protocol" and status == 409:
		print("GUEST refused with another protocol: ", error)
		step = "join"
		rooms.app_protocol = 1_000_001
		rooms.join_room(room, "Гость")
		return
	_fail("room_failed %d %s" % [status, error])


func _on_connected(peer: String) -> void:
	print(role.to_upper(), " LINK OPEN ", peer)
	if role == "guest":
		assert(peer == rooms.host_id)
		var big := PackedByteArray()
		big.resize(12000)
		big.fill(7)
		rooms.send_to_host({"ping": 1, "big": big})
		rooms.send_bytes(rooms.host_id, PackedByteArray([1, 2, 3]))
		# Unreliable packets may drop: keep sending until one comes back.
		for i in 20:
			rooms.send_to_host({"fast": i}, false)


func _on_message(peer: String, data, reliable: bool) -> void:
	if role == "host":
		if data is Dictionary and data.has("ping"):
			got.ping = data.big.size() == 12000
			rooms.send(peer, {"pong": data.ping})
		elif data is PackedByteArray:
			got.raw = data == PackedByteArray([1, 2, 3])
			rooms.send_bytes(peer, data)
		elif data is Dictionary and data.has("fast") and not reliable:
			got.fast = true
			rooms.send(peer, {"fast_back": data.fast}, false)
	else:
		if data is Dictionary and data.get("pong") == 1 and reliable: got.pong = true
		if data is PackedByteArray and data == PackedByteArray([1, 2, 3]): got.raw = true
		if data is Dictionary and data.has("fast_back") and not reliable: got.fast = true
		if got.get("pong") and got.get("raw") and got.get("fast") and step != "done":
			step = "done"
			assert(rooms.members.size() == 2)
			print("GUEST_PASS")
			rooms.leave_room()
			quit(0)


func _on_disconnected(peer: String) -> void:
	print(role.to_upper(), " LINK CLOSED ", peer)
	if role == "host":
		if got.get("ping") and got.get("raw") and got.get("fast"):
			print("HOST_PASS")
			rooms.leave_room()
			quit(0)
		else:
			_fail("guest left before all packets arrived: %s" % got)


func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() / 1000.0 - started > 40.0:
		_fail("timeout, got %s" % got)
	return false


func _fail(message: String) -> void:
	print(role.to_upper(), "_FAIL ", message)
	quit(1)
