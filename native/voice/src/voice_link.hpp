#pragma once
// One WebRTC audio connection to another room member, speaking the same
// signaling as web/voice-chat.js so native and browser players hear each
// other. libdatachannel calls back on its own threads: callbacks only touch
// `Shared` under its mutex, and Godot drains it with poll()/pull().
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/string.hpp>

#include <cstdint>
#include <memory>

namespace rtc {
class PeerConnection;
class Track;
struct RtpPacketizationConfig;
} // namespace rtc

namespace godot {

class RallyVoiceLink : public RefCounted {
	GDCLASS(RallyVoiceLink, RefCounted)

public:
	struct Shared;

private:
	std::shared_ptr<Shared> shared;
	std::shared_ptr<rtc::PeerConnection> pc;
	std::shared_ptr<rtc::Track> track;
	std::shared_ptr<rtc::RtpPacketizationConfig> rtp;
	uint32_t ssrc = 0;
	uint32_t timestamp = 0;
	int64_t last_send_usec = 0;
	bool sending_started = false;

	void attach_track(const std::shared_ptr<rtc::Track> &target, int payload_type, bool sender);
	Error fail(const String &stage, const char *what);

protected:
	static void _bind_methods();

public:
	RallyVoiceLink();
	~RallyVoiceLink();

	// `offer` adds the audio line and starts negotiating; the other side
	// creates its line from the offer in set_remote_description().
	Error initialize(const PackedStringArray &ice_servers, bool offer);
	Error set_remote_description(const String &type, const String &sdp);
	Error add_ice_candidate(const String &candidate, const String &mid);
	// Events since the last call: {type: "description", sdp_type, sdp},
	// {type: "candidate", candidate, mid}, {type: "state", state}, {type: "error", message}.
	Array poll();
	String get_state() const;
	// One Opus packet from RallyVoiceEncoder; false until the line is open.
	bool send_packet(const PackedByteArray &packet);
	// Radio-coloured stereo frames at `mix_rate` for an AudioStreamGenerator.
	PackedVector2Array pull(int frames, int mix_rate, float volume, float cutoff, float noise);
	int get_buffered_ms() const;
	int64_t get_received_packets() const;
	void close();
};

} // namespace godot
