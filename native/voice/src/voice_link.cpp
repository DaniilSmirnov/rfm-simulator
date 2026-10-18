#include "voice_link.hpp"

#include "radio_dsp.hpp"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/dictionary.hpp>

#include <rtc/rtc.hpp>

#include <algorithm>
#include <chrono>
#include <deque>
#include <mutex>
#include <random>

using namespace godot;

namespace {
// Matches the browser's Opus line; no stereo, in-band FEC for the jitter buffer.
const char *OPUS_PROFILE = "minptime=10;useinbandfec=1";
constexpr int DEFAULT_OPUS_PT = 111;

int64_t now_usec() {
	return std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now().time_since_epoch()).count();
}

uint16_t be16(const uint8_t *p) { return uint16_t(p[0] << 8 | p[1]); }

const char *state_name(rtc::PeerConnection::State state) {
	switch (state) {
		case rtc::PeerConnection::State::New: return "new";
		case rtc::PeerConnection::State::Connecting: return "connecting";
		case rtc::PeerConnection::State::Connected: return "connected";
		case rtc::PeerConnection::State::Disconnected: return "disconnected";
		case rtc::PeerConnection::State::Failed: return "failed";
		case rtc::PeerConnection::State::Closed: return "closed";
	}
	return "unknown";
}

int opus_payload_type(const rtc::Description::Media &media) {
	for (int pt : media.payloadTypes()) {
		const auto *map = media.rtpMap(pt);
		if (!map) continue;
		std::string format = map->format;
		std::transform(format.begin(), format.end(), format.begin(), ::tolower);
		if (format == "opus") return pt;
	}
	return -1;
}
} // namespace

struct RallyVoiceLink::Shared {
	struct Event {
		std::string type, a, b;
	};
	std::mutex mutex;
	std::deque<Event> events;
	std::string state = "new";
	int payload_type = DEFAULT_OPUS_PT;
	rally::Receiver receiver;

	void push(std::string type, std::string a = {}, std::string b = {}) {
		std::lock_guard lock(mutex);
		if (events.size() > 512) events.pop_front();
		events.push_back({std::move(type), std::move(a), std::move(b)});
	}

	// One RTP packet (header parsed here: the stock depacketizer ignores CSRC
	// sizes and padding).
	void rtp(const rtc::binary &packet) {
		const auto *p = reinterpret_cast<const uint8_t *>(packet.data());
		const size_t size = packet.size();
		if (size < 12 || (p[0] >> 6) != 2) return;
		const int pt = p[1] & 0x7F;
		if (pt >= 72 && pt <= 76) return; // RTCP sharing the port
		size_t offset = 12 + 4 * size_t(p[0] & 0x0F);
		if (p[0] & 0x10) {
			if (size < offset + 4) return;
			offset += 4 + 4 * size_t(be16(p + offset + 2));
		}
		size_t end = size;
		if (p[0] & 0x20) {
			const size_t padding = p[size - 1];
			if (padding > end) return;
			end -= padding;
		}
		if (offset >= end) return;
		std::lock_guard lock(mutex);
		if (pt != payload_type) return;
		receiver.push(be16(p + 2), p + offset, int(end - offset));
	}
};

void RallyVoiceLink::_bind_methods() {
	ClassDB::bind_method(D_METHOD("initialize", "ice_servers", "offer"), &RallyVoiceLink::initialize);
	ClassDB::bind_method(D_METHOD("set_remote_description", "type", "sdp"), &RallyVoiceLink::set_remote_description);
	ClassDB::bind_method(D_METHOD("add_ice_candidate", "candidate", "mid"), &RallyVoiceLink::add_ice_candidate);
	ClassDB::bind_method(D_METHOD("poll"), &RallyVoiceLink::poll);
	ClassDB::bind_method(D_METHOD("get_state"), &RallyVoiceLink::get_state);
	ClassDB::bind_method(D_METHOD("send_packet", "packet"), &RallyVoiceLink::send_packet);
	ClassDB::bind_method(D_METHOD("pull", "frames", "mix_rate", "volume", "cutoff", "noise"), &RallyVoiceLink::pull);
	ClassDB::bind_method(D_METHOD("get_buffered_ms"), &RallyVoiceLink::get_buffered_ms);
	ClassDB::bind_method(D_METHOD("get_received_packets"), &RallyVoiceLink::get_received_packets);
	ClassDB::bind_method(D_METHOD("close"), &RallyVoiceLink::close);
}

RallyVoiceLink::RallyVoiceLink() : shared(std::make_shared<Shared>()) {
	std::random_device random;
	ssrc = random();
	timestamp = random();
}

RallyVoiceLink::~RallyVoiceLink() {
	close();
}

Error RallyVoiceLink::fail(const String &stage, const char *what) {
	shared->push("error", std::string(stage.utf8().get_data()) + ": " + what);
	return ERR_CANT_CREATE;
}

Error RallyVoiceLink::initialize(const PackedStringArray &ice_servers, bool offer) {
	if (pc) return ERR_ALREADY_IN_USE;
	try {
		rtc::Configuration config;
		for (const String &url : ice_servers) config.iceServers.emplace_back(std::string(url.utf8().get_data()));
		config.disableAutoNegotiation = true;
		pc = std::make_shared<rtc::PeerConnection>(config);
		std::weak_ptr<Shared> weak = shared;
		pc->onLocalDescription([weak](rtc::Description description) {
			if (auto s = weak.lock()) s->push("description", description.typeString(), std::string(description));
		});
		pc->onLocalCandidate([weak](rtc::Candidate candidate) {
			if (auto s = weak.lock()) s->push("candidate", candidate.candidate(), candidate.mid());
		});
		pc->onStateChange([weak](rtc::PeerConnection::State state) {
			if (auto s = weak.lock()) {
				{
					std::lock_guard lock(s->mutex);
					s->state = state_name(state);
				}
				s->push("state", state_name(state));
			}
		});
		// A line the other side adds later still plays here.
		// Only lines the other side adds on its own arrive here; ours are reused.
		pc->onTrack([weak](std::shared_ptr<rtc::Track> incoming) {
			if (weak.expired()) return;
			incoming->onMessage([weak](rtc::binary data) {
				if (auto s = weak.lock()) s->rtp(data);
			}, nullptr);
		});
		if (offer) {
			rtc::Description::Audio media("audio", rtc::Description::Direction::SendRecv);
			media.addOpusCodec(DEFAULT_OPUS_PT, std::string(OPUS_PROFILE));
			media.addSSRC(ssrc, "rally-voice", "rally-voice", "rally-voice-audio");
			attach_track(pc->addTrack(media), DEFAULT_OPUS_PT, true);
			pc->setLocalDescription(rtc::Description::Type::Offer);
		}
	} catch (const std::exception &e) {
		return fail("initialize", e.what());
	}
	return OK;
}

void RallyVoiceLink::attach_track(const std::shared_ptr<rtc::Track> &target, int payload_type, bool sender) {
	track = target;
	{
		std::lock_guard lock(shared->mutex);
		shared->payload_type = payload_type;
	}
	if (sender) {
		rtp = std::make_shared<rtc::RtpPacketizationConfig>(ssrc, "rally-voice", uint8_t(payload_type), rtc::OpusRtpPacketizer::DefaultClockRate);
		auto packetizer = std::make_shared<rtc::OpusRtpPacketizer>(rtp);
		packetizer->addToChain(std::make_shared<rtc::RtcpSrReporter>(rtp));
		packetizer->addToChain(std::make_shared<rtc::RtcpReceivingSession>());
		track->setMediaHandler(packetizer);
	}
	std::weak_ptr<Shared> weak = shared;
	track->onMessage([weak](rtc::binary data) {
		if (auto s = weak.lock()) s->rtp(data);
	}, nullptr);
}

Error RallyVoiceLink::set_remote_description(const String &type, const String &sdp) {
	if (!pc) return ERR_UNCONFIGURED;
	try {
		rtc::Description description(std::string(sdp.utf8().get_data()), std::string(type.utf8().get_data()));
		if (description.type() == rtc::Description::Type::Offer && !track) {
			// Answer on the offer's audio line, with the offer's Opus payload type.
			for (int i = 0; i < description.mediaCount(); i++) {
				auto entry = description.media(i);
				auto **media = std::get_if<rtc::Description::Media *>(&entry);
				if (!media || (*media)->type() != "audio") continue;
				const int pt = opus_payload_type(**media);
				if (pt < 0) continue;
				rtc::Description::Audio local((*media)->mid(), rtc::Description::Direction::SendRecv);
				local.addOpusCodec(pt, std::string(OPUS_PROFILE));
				local.addSSRC(ssrc, "rally-voice", "rally-voice", "rally-voice-audio");
				attach_track(pc->addTrack(local), pt, true);
				break;
			}
		}
		pc->setRemoteDescription(description);
		if (description.type() == rtc::Description::Type::Offer) pc->setLocalDescription(rtc::Description::Type::Answer);
	} catch (const std::exception &e) {
		return fail("remote description", e.what());
	}
	return OK;
}

Error RallyVoiceLink::add_ice_candidate(const String &candidate, const String &mid) {
	if (!pc) return ERR_UNCONFIGURED;
	if (candidate.strip_edges().is_empty()) return OK; // end of candidates
	try {
		pc->addRemoteCandidate(rtc::Candidate(std::string(candidate.utf8().get_data()), std::string(mid.utf8().get_data())));
	} catch (const std::exception &e) {
		return fail("candidate", e.what());
	}
	return OK;
}

Array RallyVoiceLink::poll() {
	std::deque<Shared::Event> events;
	{
		std::lock_guard lock(shared->mutex);
		events.swap(shared->events);
	}
	Array result;
	for (const auto &event : events) {
		Dictionary d;
		d["type"] = String(event.type.c_str());
		if (event.type == "description") {
			d["sdp_type"] = String(event.a.c_str());
			d["sdp"] = String::utf8(event.b.c_str());
		} else if (event.type == "candidate") {
			d["candidate"] = String::utf8(event.a.c_str());
			d["mid"] = String::utf8(event.b.c_str());
		} else if (event.type == "state") {
			d["state"] = String(event.a.c_str());
		} else {
			d["message"] = String::utf8(event.a.c_str());
		}
		result.push_back(d);
	}
	return result;
}

String RallyVoiceLink::get_state() const {
	std::lock_guard lock(shared->mutex);
	return String(shared->state.c_str());
}

bool RallyVoiceLink::send_packet(const PackedByteArray &packet) {
	if (!track || !rtp || packet.is_empty()) return false;
	try {
		if (!track->isOpen()) return false;
		const int64_t now = now_usec();
		// Keep the RTP clock in step with real time across key releases, so the
		// receiver's jitter buffer sees a pause, not a burst of late audio.
		if (sending_started) {
			const int64_t elapsed = now - last_send_usec;
			const int64_t frames = elapsed > 60000 ? std::max<int64_t>(1, (elapsed + 10000) / 20000) : 1;
			timestamp += uint32_t(frames * rally::OPUS_FRAME);
		}
		sending_started = true;
		last_send_usec = now;
		rtp->timestamp = timestamp;
		return track->send(reinterpret_cast<const std::byte *>(packet.ptr()), size_t(packet.size()));
	} catch (const std::exception &e) {
		fail("send", e.what());
		return false;
	}
}

PackedVector2Array RallyVoiceLink::pull(int frames, int mix_rate, float volume, float cutoff, float noise) {
	PackedVector2Array out;
	if (frames <= 0 || mix_rate <= 0) return out;
	out.resize(frames);
	std::lock_guard lock(shared->mutex);
	shared->receiver.pull(frames, mix_rate, volume, cutoff, noise, reinterpret_cast<float *>(out.ptrw()));
	return out;
}

int RallyVoiceLink::get_buffered_ms() const {
	std::lock_guard lock(shared->mutex);
	return shared->receiver.buffered_ms();
}

int64_t RallyVoiceLink::get_received_packets() const {
	std::lock_guard lock(shared->mutex);
	return int64_t(shared->receiver.packets());
}

void RallyVoiceLink::close() {
	auto connection = std::move(pc);
	track.reset();
	rtp.reset();
	if (!connection) return;
	try {
		connection->onLocalDescription(nullptr);
		connection->onLocalCandidate(nullptr);
		connection->onTrack(nullptr);
		connection->close();
	} catch (...) {
	}
}
