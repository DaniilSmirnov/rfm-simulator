#pragma once
// The room's direct link on desktop and Android: one WebRTC data channel to
// the host (or, on the host, to one guest), the same negotiated unordered
// channel without retransmits that browser builds open with Godot's WebRTC.
// The signaling is game/scripts/net/direct_link.gd's, relayed by the room
// server, so native and browser players link to each other. libdatachannel
// calls back on its own threads: callbacks only touch `Shared` under its
// mutex, and Godot drains it with poll()/get_packets().
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/string.hpp>

#include <memory>

namespace rtc {
class PeerConnection;
class DataChannel;
} // namespace rtc

namespace godot {

class RallyDataLink : public RefCounted {
	GDCLASS(RallyDataLink, RefCounted)

public:
	struct Shared;

private:
	std::shared_ptr<Shared> shared;
	std::shared_ptr<rtc::PeerConnection> pc;
	std::shared_ptr<rtc::DataChannel> channel;

	Error fail(const String &stage, const char *what);

protected:
	static void _bind_methods();

public:
	RallyDataLink();
	~RallyDataLink();

	// `offer` starts negotiating; the answering side calls
	// set_remote_description() with the offer instead.
	Error initialize(const PackedStringArray &ice_servers, bool offer);
	Error set_remote_description(const String &type, const String &sdp);
	Error add_ice_candidate(const String &candidate, const String &mid);
	// Events since the last call: {type: "description", sdp_type, sdp},
	// {type: "candidate", candidate, mid}, {type: "state", state}, {type: "error", message}.
	Array poll();
	String get_state() const;
	// "connecting", "open" or "closed".
	String get_channel_state() const;
	// Packets received since the last call, oldest first.
	Array get_packets();
	// One packet; false while the channel is not open.
	bool send(const PackedByteArray &packet);
	void close();
};

} // namespace godot
