#include "data_link.hpp"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/dictionary.hpp>

#include <rtc/rtc.hpp>

#include <cstring>
#include <deque>
#include <mutex>
#include <vector>

using namespace godot;

namespace {
// Same channel as direct_link.gd opens in the browser: negotiated id 1,
// unordered, no retransmits (a lost packet is superseded by the next one).
constexpr uint16_t CHANNEL_ID = 1;
// A stalled game frame must not let packets pile up without bound.
constexpr size_t MAX_QUEUED = 256;

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
} // namespace

struct RallyDataLink::Shared {
	struct Event {
		std::string type, a, b;
	};
	std::mutex mutex;
	std::deque<Event> events;
	std::deque<std::vector<uint8_t>> packets;
	std::string state = "new";
	std::string channel_state = "connecting";

	void push(std::string type, std::string a = {}, std::string b = {}) {
		std::lock_guard lock(mutex);
		if (events.size() > 512) events.pop_front();
		events.push_back({std::move(type), std::move(a), std::move(b)});
	}

	void packet(const std::byte *data, size_t size) {
		std::lock_guard lock(mutex);
		if (packets.size() >= MAX_QUEUED) packets.pop_front();
		const auto *bytes = reinterpret_cast<const uint8_t *>(data);
		packets.emplace_back(bytes, bytes + size);
	}

	void set_channel(const char *value) {
		std::lock_guard lock(mutex);
		channel_state = value;
	}
};

void RallyDataLink::_bind_methods() {
	ClassDB::bind_method(D_METHOD("initialize", "ice_servers", "offer"), &RallyDataLink::initialize);
	ClassDB::bind_method(D_METHOD("set_remote_description", "type", "sdp"), &RallyDataLink::set_remote_description);
	ClassDB::bind_method(D_METHOD("add_ice_candidate", "candidate", "mid"), &RallyDataLink::add_ice_candidate);
	ClassDB::bind_method(D_METHOD("poll"), &RallyDataLink::poll);
	ClassDB::bind_method(D_METHOD("get_state"), &RallyDataLink::get_state);
	ClassDB::bind_method(D_METHOD("get_channel_state"), &RallyDataLink::get_channel_state);
	ClassDB::bind_method(D_METHOD("get_packets"), &RallyDataLink::get_packets);
	ClassDB::bind_method(D_METHOD("send", "packet"), &RallyDataLink::send);
	ClassDB::bind_method(D_METHOD("close"), &RallyDataLink::close);
}

RallyDataLink::RallyDataLink() : shared(std::make_shared<Shared>()) {}

RallyDataLink::~RallyDataLink() {
	close();
}

Error RallyDataLink::fail(const String &stage, const char *what) {
	shared->push("error", std::string(stage.utf8().get_data()) + ": " + what);
	return ERR_CANT_CREATE;
}

Error RallyDataLink::initialize(const PackedStringArray &ice_servers, bool offer) {
	if (pc) return ERR_ALREADY_IN_USE;
	try {
		rtc::Configuration config;
		for (const String &url : ice_servers) config.iceServers.emplace_back(std::string(url.utf8().get_data()));
		config.disableAutoNegotiation = true;
		pc = std::make_shared<rtc::PeerConnection>(config);
		std::weak_ptr<Shared> weak = shared;
		pc->onLocalDescription([weak](rtc::Description description) {
			auto s = weak.lock();
			if (!s) return;
			std::string sdp(description);
			// Always the DTLS client, as in RallyVoiceLink: Mbed TLS cannot
			// reassemble a fragmented ClientHello from Chrome. Answers already
			// take the active role; an offer says so too.
			if (description.type() == rtc::Description::Type::Offer) {
				for (size_t at = sdp.find("a=setup:actpass"); at != std::string::npos; at = sdp.find("a=setup:actpass", at))
					sdp.replace(at, 15, "a=setup:active");
			}
			s->push("description", description.typeString(), sdp);
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
		// Both sides create the same negotiated channel, so no in-band setup.
		rtc::DataChannelInit init;
		init.reliability.unordered = true;
		init.reliability.maxRetransmits = 0;
		init.negotiated = true;
		init.id = CHANNEL_ID;
		channel = pc->createDataChannel("fast", init);
		channel->onOpen([weak]() {
			if (auto s = weak.lock()) s->set_channel("open");
		});
		channel->onClosed([weak]() {
			if (auto s = weak.lock()) s->set_channel("closed");
		});
		channel->onMessage([weak](rtc::binary data) {
			if (auto s = weak.lock()) s->packet(data.data(), data.size());
		}, [weak](std::string text) {
			if (auto s = weak.lock()) s->packet(reinterpret_cast<const std::byte *>(text.data()), text.size());
		});
		if (offer) pc->setLocalDescription(rtc::Description::Type::Offer);
	} catch (const std::exception &e) {
		return fail("initialize", e.what());
	}
	return OK;
}

Error RallyDataLink::set_remote_description(const String &type, const String &sdp) {
	if (!pc) return ERR_UNCONFIGURED;
	try {
		rtc::Description description(std::string(sdp.utf8().get_data()), std::string(type.utf8().get_data()));
		pc->setRemoteDescription(description);
		if (description.type() == rtc::Description::Type::Offer) pc->setLocalDescription(rtc::Description::Type::Answer);
	} catch (const std::exception &e) {
		return fail("remote description", e.what());
	}
	return OK;
}

Error RallyDataLink::add_ice_candidate(const String &candidate, const String &mid) {
	if (!pc) return ERR_UNCONFIGURED;
	if (candidate.strip_edges().is_empty()) return OK; // end of candidates
	try {
		pc->addRemoteCandidate(rtc::Candidate(std::string(candidate.utf8().get_data()), std::string(mid.utf8().get_data())));
	} catch (const std::exception &e) {
		return fail("candidate", e.what());
	}
	return OK;
}

Array RallyDataLink::poll() {
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

String RallyDataLink::get_state() const {
	std::lock_guard lock(shared->mutex);
	return String(shared->state.c_str());
}

String RallyDataLink::get_channel_state() const {
	std::lock_guard lock(shared->mutex);
	return String(shared->channel_state.c_str());
}

Array RallyDataLink::get_packets() {
	std::deque<std::vector<uint8_t>> packets;
	{
		std::lock_guard lock(shared->mutex);
		packets.swap(shared->packets);
	}
	Array result;
	for (const auto &packet : packets) {
		PackedByteArray bytes;
		bytes.resize(int64_t(packet.size()));
		if (!packet.empty()) memcpy(bytes.ptrw(), packet.data(), packet.size());
		result.push_back(bytes);
	}
	return result;
}

bool RallyDataLink::send(const PackedByteArray &packet) {
	if (!channel || packet.is_empty()) return false;
	try {
		if (!channel->isOpen()) return false;
		return channel->send(reinterpret_cast<const std::byte *>(packet.ptr()), size_t(packet.size()));
	} catch (const std::exception &e) {
		fail("send", e.what());
		return false;
	}
}

void RallyDataLink::close() {
	auto connection = std::move(pc);
	auto open_channel = std::move(channel);
	if (open_channel) {
		try {
			open_channel->onOpen(nullptr);
			open_channel->onClosed(nullptr);
			open_channel->onMessage(nullptr);
			open_channel->close();
		} catch (...) {
		}
	}
	if (!connection) return;
	try {
		connection->onLocalDescription(nullptr);
		connection->onLocalCandidate(nullptr);
		connection->onStateChange(nullptr);
		connection->close();
	} catch (...) {
	}
}
