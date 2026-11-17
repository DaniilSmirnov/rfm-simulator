#include "voice_encoder.hpp"

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>

#include <opus.h>

#include <algorithm>
#include <cmath>

using namespace godot;

void RallyVoiceEncoder::_bind_methods() {
	ClassDB::bind_method(D_METHOD("encode", "frames", "mix_rate"), &RallyVoiceEncoder::encode);
	ClassDB::bind_method(D_METHOD("reset"), &RallyVoiceEncoder::reset);
	ClassDB::bind_method(D_METHOD("get_level"), &RallyVoiceEncoder::get_level);
	ClassDB::bind_method(D_METHOD("set_bitrate", "bitrate"), &RallyVoiceEncoder::set_bitrate);
}

RallyVoiceEncoder::RallyVoiceEncoder() {
	int error = 0;
	encoder = opus_encoder_create(rally::OPUS_RATE, 1, OPUS_APPLICATION_VOIP, &error);
	if (error != OPUS_OK) {
		encoder = nullptr;
		return;
	}
	opus_encoder_ctl(encoder, OPUS_SET_BITRATE(24000));
	opus_encoder_ctl(encoder, OPUS_SET_INBAND_FEC(1));
	opus_encoder_ctl(encoder, OPUS_SET_PACKET_LOSS_PERC(10));
	opus_encoder_ctl(encoder, OPUS_SET_SIGNAL(OPUS_SIGNAL_VOICE));
}

RallyVoiceEncoder::~RallyVoiceEncoder() {
	if (encoder) opus_encoder_destroy(encoder);
}

void RallyVoiceEncoder::set_bitrate(int bitrate) {
	if (encoder) opus_encoder_ctl(encoder, OPUS_SET_BITRATE(bitrate));
}

void RallyVoiceEncoder::reset() {
	pending.clear();
	power_left = power_right = power_mid = 0.0;
	resampler.reset();
	level = 0.0f;
	if (encoder) opus_encoder_ctl(encoder, OPUS_RESET_STATE);
}

// Stereo -> mono. A plain (L + R) / 2 works when both channels carry the same
// voice (a mono microphone, which Godot copies to both). It fails on stereo
// inputs: a microphone wired to one channel of a stereo interface or headset
// comes out 6 dB quieter, and a stereo array whose channels are in opposite
// phase cancels itself to near silence. So when the average keeps less than
// half the power of the louder channel, that channel is sent on its own.
// The powers are smoothed over ~0.1 s so the choice does not flicker.
void RallyVoiceEncoder::downmix(const PackedVector2Array &frames) {
	const int64_t count = frames.size();
	mono.resize(count);
	const Vector2 *src = frames.ptr();
	double left = 0.0, right = 0.0, mid = 0.0;
	for (int64_t i = 0; i < count; i++) {
		const float average = (src[i].x + src[i].y) * 0.5f;
		left += double(src[i].x) * src[i].x;
		right += double(src[i].y) * src[i].y;
		mid += double(average) * average;
	}
	const double keep = 0.7;
	power_left = power_left * keep + left;
	power_right = power_right * keep + right;
	power_mid = power_mid * keep + mid;
	const double louder = std::max(power_left, power_right);
	if (louder > 0.0 && power_mid * 2.0 < louder) {
		const bool use_left = power_left >= power_right;
		for (int64_t i = 0; i < count; i++) mono[i] = use_left ? src[i].x : src[i].y;
		return;
	}
	for (int64_t i = 0; i < count; i++) mono[i] = (src[i].x + src[i].y) * 0.5f;
}

Array RallyVoiceEncoder::encode(const PackedVector2Array &frames, int mix_rate) {
	Array packets;
	if (!encoder || frames.is_empty() || mix_rate <= 0) return packets;
	downmix(frames);
	resampled.clear();
	resampler.process(mono.data(), int(mono.size()), mix_rate, rally::OPUS_RATE, resampled);
	pending.insert(pending.end(), resampled.begin(), resampled.end());
	size_t offset = 0;
	unsigned char data[1275];
	while (pending.size() - offset >= size_t(rally::OPUS_FRAME)) {
		const float *frame = pending.data() + offset;
		double sum = 0;
		for (int i = 0; i < rally::OPUS_FRAME; i++) sum += double(frame[i]) * frame[i];
		level = float(std::sqrt(sum / rally::OPUS_FRAME));
		const int bytes = opus_encode_float(encoder, frame, rally::OPUS_FRAME, data, sizeof(data));
		offset += rally::OPUS_FRAME;
		if (bytes <= 0) continue;
		PackedByteArray packet;
		packet.resize(bytes);
		memcpy(packet.ptrw(), data, bytes);
		packets.push_back(packet);
	}
	pending.erase(pending.begin(), pending.begin() + offset);
	return packets;
}
