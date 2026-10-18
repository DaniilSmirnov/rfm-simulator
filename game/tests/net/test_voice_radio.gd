extends "res://tests/harness.gd"
# The radio flag travels in the player state like the other pose flags, and a
# build without browser voice keeps the radio switched off.
const NetProtocol = preload("res://scripts/net/net_protocol.gd")
const VoiceChat = preload("res://scripts/net/voice_chat.gd")
const VoiceNative = preload("res://scripts/net/voice_native.gd")
const Props = preload("res://scripts/core/props.gd")
const CharacterRig = preload("res://scripts/people/character_rig.gd")
const PeerView = preload("res://scripts/net/peer_view.gd")
const RadioModel = preload("res://scripts/people/radio_model.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var base = {"pos": [0, 0, 0], "car": [1, 1, 1], "heading": 0, "yaw": 0, "pitch": 0, "in_car": false}
	check(NetProtocol.clean_state(base).radio == false, "the radio is off unless the state says so")
	check(NetProtocol.clean_state(base.merged({"radio": true})).radio == true, "a member on air keeps the radio flag")
	check(NetProtocol.clean_state(base.merged({"radio": true, "in_car": true})).radio == true, "talking from a car still shows who is on air")
	check(NetProtocol.clean_state(base.merged({"radio": "yes"})).radio == false, "only a boolean switches the radio on")
	var quiet = NetProtocol.compact_state(NetProtocol.clean_state(base))
	check(not quiet.has("radio"), "the direct link leaves the default radio flag out")
	var loud = NetProtocol.compact_state(NetProtocol.clean_state(base.merged({"radio": true})))
	check(loud.get("radio") == true and NetProtocol.expand_state(loud).radio == true, "the direct link carries the radio flag")
	check(NetProtocol.expand_state(quiet).radio == false, "a guest reads a missing radio flag as off")
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/net_protocol.json"))
	check(data.has("voice") and int(data.voice.max_signal_bytes) > 0 and int(data.voice.signals_per_10s) > 0, "voice signaling has its own limits")
	await radio_animation()
	var voice = VoiceChat.new()
	root.add_child(voice)
	await process_frame
	check(voice.supported == VoiceNative.supported(), "native builds offer the radio exactly when the native library ships")
	check(not voice.available(), "the radio is hidden until the room joins it")
	if not voice.supported:
		voice.join()
		voice.sync_members(["a", "b"])
		voice.on_signal("a", {"space": "voice", "kind": "offer"})
		voice.leave()
		check(not voice.joined and not voice.on_air(), "without a backend joining and leaving are no-ops")
	voice.free()
	finish()

# A member on air raises the radio in about 0.2 s, its light on; it goes down
# after, and never shows in a car or with the hands full.
func radio_animation() -> void:
	var avatar = Props.player_avatar(0)
	root.add_child(avatar)
	var arm = CharacterRig.hand(avatar)
	var held = Node3D.new()
	avatar.add_child(held)
	held.hide()
	var peer = {"radio": RadioModel.attach_to_hand(arm, CharacterRig.grip()), "radio_lift": 0.0, "held_box": held, "can": arm.get_node("BeerCan"), "skewer": arm.get_node("Skewer")}
	var talking = {"radio": true, "in_car": false}
	peer.can.show()
	var hands = PeerView._animate_radio(peer, talking, 0.1, false, {"arms": "drink", "lift": 1.0})
	check(hands.arms == "radio" and is_equal_approx(hands.lift, 0.5) and peer.radio.visible, "the radio is halfway up after 0.1 s")
	check(not peer.can.visible, "the radio takes over from a drink")
	PeerView._animate_radio(peer, talking, 0.15, false, {})
	check(is_equal_approx(peer.radio_lift, 1.0) and RadioModel.on_air(peer.radio), "the radio reaches the mouth with its light on")
	hands = PeerView._animate_radio(peer, {"radio": false, "in_car": false}, 0.1, false, {"arms": "", "lift": 0.0})
	check(hands.arms == "radio" and peer.radio_lift < 0.6 and not RadioModel.on_air(peer.radio), "releasing the key lowers the radio and turns the light off")
	PeerView._animate_radio(peer, {"radio": false, "in_car": false}, 0.2, false, {})
	check(not peer.radio.visible, "the lowered radio is put away")
	PeerView._animate_radio(peer, {"radio": true, "in_car": true}, 0.3, false, {})
	check(not peer.radio.visible, "no radio in hand inside a car")
	held.show()
	hands = PeerView._animate_radio(peer, talking, 0.3, false, {"arms": "", "lift": 0.0})
	check(not peer.radio.visible and hands.arms == "", "full hands keep the radio away")
	avatar.queue_free()
