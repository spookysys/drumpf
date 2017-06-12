#include <cstdint>
#include <cstdlib>
#include <cstdio>
#include <cstring>
#include <iostream>
#include <math.h>
#include <array>
#include "export/use_all.inc"
//#define USE_JK_BD_02
//#define USE_JK_BD_06

static const int block_size = 8;
static const int sample_rate = 22050;


using namespace std;

struct AdpcmSample
{
	uint16_t len;
	const uint8_t* data;
};


namespace drums
{
	struct DrumEnv
	{
		uint16_t increment;
		uint16_t initial;
	};

	struct DrumFilter
	{
		int8_t a2, a3, b1, b2, b3;
	};

	struct Drum
	{
		DrumEnv treble_env;
		DrumFilter treble_filter;
		AdpcmSample bass_sample;
	};

	enum Drums
	{
		#include "export/enums.inc"
	};

	#include "export/datas.inc"
	const Drum drums[] = {
		#include "export/structs.inc"
	};
	const char* names[] = {
		#include "export/names.inc"
	};
	const int num = sizeof(drums)/sizeof(*drums);
}


class AdpcmDecoder
{
	const uint8_t* ptr;
	const uint8_t* end;
	uint8_t subidx;
	uint8_t word;

	uint8_t getIdx()
	{
		uint8_t ret = word & 3;
		word >>= 2;
		subidx--;
		if (subidx==0) {
			subidx = 4;
			word = ((ptr+1)!=end) ? *ptr : 0;
			ptr++;
		}
		return ret;
	}

	int8_t recon_1;
	int8_t recon_2;
	int8_t modifier;
public:
	void reset()
	{
		ptr = end;
	}

	void trigger(const AdpcmSample& sample)
	{
		if (sample.data) {
			this->ptr = sample.data + 1;
			this->end = sample.data + sample.len + 1;
		} else {
			this->ptr = nullptr;
			this->end = nullptr;
		}
		if (isActive()) {
			this->word = *sample.data;
			this->subidx = 4;
		}
		this->recon_1 = 0;
		this->recon_2 = 0;
		this->modifier = 0;
	}

	bool isActive()
	{
		return ptr!=end;
	}	

	int8_t get()
	{
		uint8_t idx = getIdx();
		switch (idx) {
			case 0: break;
			case 1: 
				modifier = -modifier;
				break;
			case 2: 
				modifier = modifier ? (modifier<<1) : 1;
				break;
			case 3:
				modifier = modifier ? (modifier>>1) : -1;
				break;
		}
		int8_t prediction = recon_1 + recon_1 - recon_2;
		int8_t recon = prediction + modifier;
		this->recon_2 = this->recon_1;
		this->recon_1 = recon;
		return recon;
	}

};

template<typename T>
class MinMaxRecorder
{
	T maxval = 0;
	T minval = 0;
public:
	void operator()(T op) {
		minval = std::max(minval, op);
		maxval = std::max(maxval, op);
	}
	void dump(const char* name)
	{
		std::cout << std::string(name) << " min: " << minval << " max: " << maxval << std::endl;
	}
};

class Filter
{
	int8_t a2, a3, b1, b2, b3;
	int16_t xn_1, xn_2;
	int16_t yn_1, yn_2;
public:
	void init(const drums::DrumFilter& op) 
	{
		a2 = op.a2;
		a3 = op.a3;
		b1 = op.b1;
		b2 = op.b2;
		b3 = op.b3;
		xn_1 = 0;
		yn_1 = 0;
		xn_2 = 0;
		yn_2 = 0;
	}
	int16_t get(int16_t xx)
	{
		int16_t b1_xx = (int16_t(b1)*xx)>>8;
		int16_t b2_x1 = (int16_t(b2)*xn_1)>>8;
		int16_t b3_x2 = (int16_t(b3)*xn_2)>>7;
		int16_t a2_y1 = (int16_t(a2)*yn_1)>>6;
		int16_t a3_y2 = (int16_t(a3)*yn_2)>>7;
		int16_t yy = b1_xx + b2_x1 + b3_x2 - a2_y1 - a3_y2;

		this->xn_2 = this->xn_1;
		this->yn_2 = this->yn_1;
		this->xn_1 = xx;
		this->yn_1 = yy;

		return yy;
	}
};


static inline int8_t average(int8_t a, int8_t b, uint8_t& dither)
{
	int8_t val = (int16_t(a)+int16_t(b)+(dither&1))>>1;
	dither >>= 1;
	return val;
}

// lerp
static void lerp8(int8_t start, int8_t end, int8_t v[8])
{
	uint8_t dither = rand();
	v[0] = start;
	v[4] = average(v[0], end, dither);
	v[2] = average(v[0], v[4], dither);
	v[6] = average(v[4], end, dither);
	v[1] = average(v[0], v[2], dither);
	v[3] = average(v[2], v[4], dither);
	v[5] = average(v[4], v[6], dither);
	v[7] = average(v[6], end, dither);
}


// lerp
static void spline8(int8_t p0, int8_t p1, int8_t p2, int8_t v[8])
{
	uint8_t dither = rand();
	int8_t l0[8];
	int8_t l1[8];
	lerp8(p0, p1, l0);
	lerp8(p1, p2, l1);
	v[0] = average(l0[0], l1[0], dither);
	v[1] = average(l0[1], l1[1], dither);
	v[2] = average(l0[2], l1[2], dither);
	v[3] = average(l0[3], l1[3], dither);
	v[4] = average(l0[4], l1[4], dither);
	v[5] = average(l0[5], l1[5], dither);
	v[6] = average(l0[6], l1[6], dither);
	v[7] = average(l0[7], l1[7], dither);
}


class DrumDecoder
{
	AdpcmDecoder adpcmDecoder;

	int8_t bass_0, bass_1;

	int32_t treble_amplitude;
	uint16_t treble_increment;

	Filter treble_filter;
public:

	void trigger(const drums::Drum& drum)
	{
		adpcmDecoder.trigger(drum.bass_sample);
		treble_amplitude = uint32_t(drum.treble_env.initial) << 8;
		treble_increment = drum.treble_env.increment;
		treble_filter.init(drum.treble_filter);
		bass_0 = 0;
		bass_1 = 0;
	}

	void decodeBlock(int16_t* dest)
	{
		// bass
		if (adpcmDecoder.isActive()) {
			this->bass_1 = bass_0;
			this->bass_0 = adpcmDecoder.get();
			int8_t v[block_size];
			lerp8(this->bass_1, bass_0, v);
			for (int i=0; i<block_size; i++) {
				dest[i] += v[i];
			}
		}

		// treble
		if (this->treble_amplitude > 0) {
			uint16_t amplitude = this->treble_amplitude >> 8;
			if (amplitude>0xFF) amplitude = 0xFF;
			for (int i=0; i<block_size; i++) {
				int8_t noiz = rand();
				int16_t val = treble_filter.get(noiz);
				val = (int16_t(val) * amplitude) >> 8;
				dest[i] += val;
			}			

			this->treble_amplitude -= this->treble_increment;
		}
	}
};

struct WavHeader
{
	char chunk_id_0 = 'R';
	char chunk_id_1 = 'I';
	char chunk_id_2 = 'F';
	char chunk_id_3 = 'F';
	uint32_t chunk_size = 0;
	char format_0 = 'W';
	char format_1 = 'A';
	char format_2 = 'V';
	char format_3 = 'E';
	char subchunk1_id_0 = 'f';
	char subchunk1_id_1 = 'm';
	char subchunk1_id_2 = 't';
	char subchunk1_id_3 = 0x20;
	uint32_t subchunk1_size = 16;
	uint16_t audio_format = 1; // 1 = PCM
	uint16_t num_channels = 1;
	uint32_t sample_rate = 22050; 
	uint32_t bytes_per_second = 0;
	uint16_t bytes_per_frame = 0;
	uint16_t bits_per_sample = 0;
	char subchunk2_id_0 = 'd';
	char subchunk2_id_1 = 'a';
	char subchunk2_id_2 = 't';
	char subchunk2_id_3 = 'a';
	uint32_t subchunk2_size = 0;
};


static WavHeader wav_header;
void write_wav(const char* filename, int16_t* data, int num_samples, bool only_8=false)
{
	const int bytes_per_frame = only_8 ? 1 : 2;
	wav_header.chunk_size = bytes_per_frame * num_samples + 36;
	wav_header.subchunk2_size = bytes_per_frame * num_samples - 8;
	wav_header.bytes_per_second = bytes_per_frame * wav_header.sample_rate;
	wav_header.bytes_per_frame = bytes_per_frame;
	wav_header.bits_per_sample = bytes_per_frame * 8;
	FILE* fid = fopen(filename, "wb");
	fwrite(&wav_header, 1, sizeof(WavHeader), fid);
	if (only_8) {
		int8_t* wdata = (int8_t*)malloc(num_samples);
		for (int i=0; i<num_samples; i++) {
			int16_t val = data[i];
			val += 128;
			if (val<0) val = 0;
			if (val>255) val = 255;
			wdata[i] = val;
		}
		fwrite(wdata, 1, num_samples, fid);
		free(wdata);
	} else {
		fwrite(data, 2, num_samples, fid);
	}
	fclose(fid);
}

void write_dat(const char* filename, const drums::Drum& op)
{
	uint16_t bass_data_ptr_placeholder = 0;
	FILE* fid = fopen(filename, "wb");
	fwrite(&op.treble_env, sizeof(op.treble_env), 1, fid);
	fwrite(&op.treble_filter, sizeof(op.treble_filter), 1, fid);
	fwrite(&op.bass_sample.len, sizeof(op.bass_sample.len), 1, fid);
	fwrite(&bass_data_ptr_placeholder, sizeof(bass_data_ptr_placeholder), 1, fid);
	fwrite(op.bass_sample.data, 1, op.bass_sample.len, fid);
	fclose(fid);
}


int main(int argc, char* argv[])
{
	static const int num_blocks = (sample_rate * 3) / block_size;

	std::array<int16_t, num_blocks*block_size> buffer;
	DrumDecoder decoder;

	for (int drum_i=0; drum_i<drums::num; drum_i++) {
		const drums::Drum& drum = drums::drums[drum_i];
		const char* name = drums::names[drum_i];
		for (auto& iter : buffer) iter = 0;

		// render
		decoder.trigger(drum);
		for (int block_i=0; block_i<num_blocks; block_i++) {
			decoder.decodeBlock(buffer.data() + block_i*block_size);
		}

		// save 
		{
			static char filename[256];
			char* d = filename;
			strcpy(d, "out/");
			d += strlen(d);
			strcpy(d, name);
			d += strlen(d);
			strcpy(d, ".wav");
			write_wav(filename, buffer.data(), num_blocks*block_size, true);
			strcpy(d, ".dat");
			write_dat(filename, drum);
		}
	}
}

#ifdef CRINKLE
#define WINDOWS_LEAN_AND_MEAN
#include <windows.h>
extern "C" void __stdcall mainCRTStartup()
{
	main(0, nullptr);
	ExitProcess(0);
}
#endif
