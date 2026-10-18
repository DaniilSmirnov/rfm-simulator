#pragma once
// Audio helpers shared by the encoder and the links: a streaming linear
// resampler, RBJ biquads and the receive side (Opus decode + jitter buffer +
// radio colouring). Pure C++, no Godot types, so it is easy to reason about
// from libdatachannel's threads.
#include <cstdint>
#include <deque>
#include <vector>

struct OpusDecoder;

namespace rally {

constexpr int OPUS_RATE = 48000;
constexpr int OPUS_FRAME = 960; // 20 ms

// Pushes samples at one rate and emits them at another.
class StreamResampler {
public:
	void reset();
	void process(const float *in, int count, double in_rate, double out_rate, std::vector<float> &out);

private:
	double t = 0.0;
	float prev = 0.0f;
	bool primed = false;
};

class Biquad {
public:
	void lowpass(double rate, double freq, double q = 0.707);
	void highpass(double rate, double freq, double q = 0.707);
	void bandpass(double rate, double freq, double q);
	float process(float x);

private:
	void set(double b0, double b1, double b2, double a0, double a1, double a2);
	double b0 = 1, b1 = 0, b2 = 0, a1 = 0, a2 = 0;
	double z1 = 0, z2 = 0;
};

// One remote speaker: Opus packets in (any thread), radio-coloured PCM out.
class Receiver {
public:
	Receiver();
	~Receiver();
	Receiver(const Receiver &) = delete;
	Receiver &operator=(const Receiver &) = delete;

	// RTP sequence number and Opus payload of one packet.
	void push(uint16_t seq, const uint8_t *payload, int size);
	// `frames` stereo-equal samples at `rate` into out (interleaved L/R).
	void pull(int frames, int rate, float volume, float cutoff, float noise, float *out);
	int buffered_ms() const;
	uint64_t packets() const { return packet_count; }

private:
	void append(const float *pcm, int count);
	void configure(int rate, float cutoff);

	OpusDecoder *decoder = nullptr;
	std::deque<float> ring;
	bool have_seq = false;
	uint16_t last_seq = 0;
	bool playing = false;
	double frac = 0.0;
	uint64_t packet_count = 0;
	// Output-side state.
	int out_rate = 0;
	float out_cutoff = 0.0f;
	Biquad highpass, lowpass, hiss;
	float gain = 0.0f, noise_gain = 0.0f;
	uint32_t noise_seed = 0x2545F491u;
};

} // namespace rally
