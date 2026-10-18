#include "radio_dsp.hpp"

#include <opus.h>

#include <algorithm>
#include <cmath>

namespace rally {

namespace {
constexpr double PI = 3.14159265358979323846;
// Start playing once this much audio is queued, and never keep more than the
// cap: late audio is worse than a dropped syllable on a radio.
constexpr int PREBUFFER = OPUS_RATE * 60 / 1000;
constexpr int MAX_BUFFER = OPUS_RATE * 400 / 1000;
constexpr int TRIM_TO = OPUS_RATE * 120 / 1000;
// Short gaps are concealed (FEC/PLC); longer ones are the sender releasing the key.
constexpr int MAX_CONCEALED = 3;
} // namespace

void StreamResampler::reset() {
	t = 0.0;
	prev = 0.0f;
	primed = false;
}

void StreamResampler::process(const float *in, int count, double in_rate, double out_rate, std::vector<float> &out) {
	if (count <= 0 || in_rate <= 0 || out_rate <= 0) return;
	const double step = in_rate / out_rate;
	int i = 0;
	if (!primed) {
		prev = in[0];
		primed = true;
		i = 1;
	}
	for (; i < count; i++) {
		const float s = in[i];
		while (t <= 1.0) {
			out.push_back(prev + (s - prev) * float(t));
			t += step;
		}
		t -= 1.0;
		prev = s;
	}
}

void Biquad::set(double nb0, double nb1, double nb2, double a0, double na1, double na2) {
	b0 = nb0 / a0;
	b1 = nb1 / a0;
	b2 = nb2 / a0;
	a1 = na1 / a0;
	a2 = na2 / a0;
}

void Biquad::lowpass(double rate, double freq, double q) {
	freq = std::clamp(freq, 20.0, rate * 0.45);
	const double w = 2 * PI * freq / rate, c = std::cos(w), alpha = std::sin(w) / (2 * q);
	set((1 - c) / 2, 1 - c, (1 - c) / 2, 1 + alpha, -2 * c, 1 - alpha);
}

void Biquad::highpass(double rate, double freq, double q) {
	freq = std::clamp(freq, 20.0, rate * 0.45);
	const double w = 2 * PI * freq / rate, c = std::cos(w), alpha = std::sin(w) / (2 * q);
	set((1 + c) / 2, -(1 + c), (1 + c) / 2, 1 + alpha, -2 * c, 1 - alpha);
}

void Biquad::bandpass(double rate, double freq, double q) {
	freq = std::clamp(freq, 20.0, rate * 0.45);
	const double w = 2 * PI * freq / rate, c = std::cos(w), alpha = std::sin(w) / (2 * q);
	set(alpha, 0, -alpha, 1 + alpha, -2 * c, 1 - alpha);
}

float Biquad::process(float x) {
	// Transposed direct form II.
	const double y = b0 * x + z1;
	z1 = b1 * x - a1 * y + z2;
	z2 = b2 * x - a2 * y;
	return float(y);
}

Receiver::Receiver() {
	int error = 0;
	decoder = opus_decoder_create(OPUS_RATE, 1, &error);
	if (error != OPUS_OK) decoder = nullptr;
}

Receiver::~Receiver() {
	if (decoder) opus_decoder_destroy(decoder);
}

void Receiver::append(const float *pcm, int count) {
	ring.insert(ring.end(), pcm, pcm + count);
	if (int(ring.size()) > MAX_BUFFER) ring.erase(ring.begin(), ring.begin() + (int(ring.size()) - TRIM_TO));
}

void Receiver::push(uint16_t seq, const uint8_t *payload, int size) {
	if (!decoder || size <= 0) return;
	float pcm[5760];
	if (have_seq) {
		const uint16_t gap = uint16_t(seq - last_seq);
		if (gap == 0 || gap > 0x8000) return; // duplicate or reordered late packet
		const int lost = gap - 1;
		if (lost > 0 && lost <= MAX_CONCEALED) {
			for (int k = 0; k < lost; k++) {
				// The last lost frame can be rebuilt from this packet's in-band FEC.
				const bool fec = k == lost - 1;
				const int n = opus_decode_float(decoder, fec ? payload : nullptr, fec ? size : 0, pcm, OPUS_FRAME, fec ? 1 : 0);
				if (n > 0) append(pcm, n);
			}
		}
	}
	have_seq = true;
	last_seq = seq;
	const int n = opus_decode_float(decoder, payload, size, pcm, 5760, 0);
	if (n > 0) append(pcm, n);
	packet_count++;
}

int Receiver::buffered_ms() const {
	return int(ring.size() * 1000 / OPUS_RATE);
}

void Receiver::configure(int rate, float cutoff) {
	if (rate != out_rate) {
		out_rate = rate;
		highpass.highpass(rate, 300.0);
		hiss.bandpass(rate, 2000.0, 0.8);
		out_cutoff = -1.0f;
	}
	if (std::abs(cutoff - out_cutoff) > 1.0f) {
		out_cutoff = cutoff;
		lowpass.lowpass(rate, cutoff);
	}
}

void Receiver::pull(int frames, int rate, float volume, float cutoff, float noise, float *out) {
	if (frames <= 0 || rate <= 0) return;
	configure(rate, cutoff);
	if (!playing && int(ring.size()) >= PREBUFFER) playing = true;
	const double step = double(OPUS_RATE) / rate;
	// ~10 ms smoothing so volume and hiss changes never click.
	const float k = 1.0f - std::exp(-1.0f / (0.01f * rate));
	for (int i = 0; i < frames; i++) {
		float s = 0.0f;
		if (playing) {
			if (ring.size() >= 2) {
				s = ring[0] + (ring[1] - ring[0]) * float(frac);
				frac += step;
				while (frac >= 1.0 && ring.size() >= 2) {
					ring.pop_front();
					frac -= 1.0;
				}
			} else {
				playing = false; // underrun: wait for the prebuffer again
				frac = 0.0;
			}
		}
		gain += (volume - gain) * k;
		noise_gain += (noise - noise_gain) * k;
		noise_seed = noise_seed * 1664525u + 1013904223u;
		const float white = float(int32_t(noise_seed)) / 2147483648.0f;
		const float y = lowpass.process(highpass.process(s)) * gain + hiss.process(white) * noise_gain;
		out[2 * i] = out[2 * i + 1] = std::clamp(y, -1.0f, 1.0f);
	}
}

} // namespace rally
