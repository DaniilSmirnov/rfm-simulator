#pragma once
// Microphone -> Opus. One encoder per game: the same packets go to every link.
#include "radio_dsp.hpp"

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>

struct OpusEncoder;

namespace godot {

class RallyVoiceEncoder : public RefCounted {
	GDCLASS(RallyVoiceEncoder, RefCounted)

	OpusEncoder *encoder = nullptr;
	rally::StreamResampler resampler;
	std::vector<float> pending;
	std::vector<float> mono;
	std::vector<float> resampled;
	float level = 0.0f;

protected:
	static void _bind_methods();

public:
	RallyVoiceEncoder();
	~RallyVoiceEncoder();
	// Stereo frames at `mix_rate` (AudioEffectCapture) -> Array of 20 ms Opus packets.
	Array encode(const PackedVector2Array &frames, int mix_rate);
	// Drops buffered audio: the next press starts clean.
	void reset();
	// RMS of the last encoded frame, 0..1.
	float get_level() const { return level; }
	void set_bitrate(int bitrate);
};

} // namespace godot
