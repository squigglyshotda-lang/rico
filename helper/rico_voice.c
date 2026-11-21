// rico_voice: turns Orpheus SNAC codes into Rico's voice.
// Listens on 127.0.0.1:<port>. Protocol (little-endian):
//   client -> 'B' f32 pitch, f32 tempo, u8 glitch   start an utterance
//   client -> 'F' 7 x i32                          one SNAC frame (already offset-corrected)
//   client -> 'E'                                  end of utterance, flush
//   server -> 'A' u32 n, n x i16                   audio @ 24 kHz mono
//   server -> 'D'                                  utterance finished
// Usage: rico_voice <snac_decoder.onnx> <port>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <math.h>
#include "onnxruntime_c_api.h"

#ifdef _WIN32
#include <winsock2.h>
#include <windows.h>
typedef SOCKET sock_t;
#define CLOSESOCK closesocket
#else
#include <dlfcn.h>
#include <unistd.h>
#include <arpa/inet.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
typedef int sock_t;
#define CLOSESOCK close
#endif

static const OrtApi *ort;
static OrtSession *sess;
static OrtMemoryInfo *meminfo;
static char *in_names[3];
static char *out_name;

#define CHECK(x) do { OrtStatus *s_ = (x); if (s_) { fprintf(stderr, "ort: %s\n", ort->GetErrorMessage(s_)); exit(2); } } while (0)

static void load_ort(const char *model) {
	typedef const OrtApiBase *(*getbase_t)(void);
	getbase_t getbase;
#ifdef _WIN32
	HMODULE h = LoadLibraryA("onnxruntime.dll");
	if (!h) { fprintf(stderr, "no onnxruntime.dll\n"); exit(2); }
	getbase = (getbase_t)GetProcAddress(h, "OrtGetApiBase");
#else
	const char *lib = getenv("ORT_LIB");
	void *h = dlopen(lib ? lib : "libonnxruntime.so", RTLD_NOW);
	if (!h) { fprintf(stderr, "dlopen: %s\n", dlerror()); exit(2); }
	getbase = (getbase_t)dlsym(h, "OrtGetApiBase");
#endif
	ort = getbase()->GetApi(20);
	if (!ort) { fprintf(stderr, "ort api 20 missing\n"); exit(2); }
	OrtEnv *env; OrtSessionOptions *opt;
	CHECK(ort->CreateEnv(ORT_LOGGING_LEVEL_WARNING, "rico", &env));
	CHECK(ort->CreateSessionOptions(&opt));
	CHECK(ort->SetIntraOpNumThreads(opt, 2));
	CHECK(ort->SetSessionGraphOptimizationLevel(opt, ORT_ENABLE_ALL));
#ifdef _WIN32
	wchar_t wpath[1024];
	MultiByteToWideChar(CP_UTF8, 0, model, -1, wpath, 1024);
	CHECK(ort->CreateSession(env, wpath, opt, &sess));
#else
	CHECK(ort->CreateSession(env, model, opt, &sess));
#endif
	CHECK(ort->CreateCpuMemoryInfo(OrtArenaAllocator, OrtMemTypeDefault, &meminfo));
	OrtAllocator *al; CHECK(ort->GetAllocatorWithDefaultOptions(&al));
	for (int i = 0; i < 3; i++) CHECK(ort->SessionGetInputName(sess, i, al, &in_names[i]));
	CHECK(ort->SessionGetOutputName(sess, 0, al, &out_name));
}

// ---- SNAC decode of up to 4 frames -> float samples (2048 per frame)
static int decode(int32_t (*fr)[7], int n, float *out) {
	int64_t c0[4], c1[8], c2[16];
	for (int j = 0; j < n; j++) {
		int32_t *f = fr[j];
		c0[j] = f[0];
		c1[2 * j] = f[1]; c1[2 * j + 1] = f[4];
		c2[4 * j] = f[2]; c2[4 * j + 1] = f[3]; c2[4 * j + 2] = f[5]; c2[4 * j + 3] = f[6];
	}
	int64_t s0[2] = {1, n}, s1[2] = {1, 2 * n}, s2[2] = {1, 4 * n};
	OrtValue *iv[3] = {0}, *ov = NULL;
	CHECK(ort->CreateTensorWithDataAsOrtValue(meminfo, c0, sizeof(int64_t) * n, s0, 2, ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64, &iv[0]));
	CHECK(ort->CreateTensorWithDataAsOrtValue(meminfo, c1, sizeof(int64_t) * 2 * n, s1, 2, ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64, &iv[1]));
	CHECK(ort->CreateTensorWithDataAsOrtValue(meminfo, c2, sizeof(int64_t) * 4 * n, s2, 2, ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64, &iv[2]));
	const char *outs[1] = {out_name};
	CHECK(ort->Run(sess, NULL, (const char *const *)in_names, (const OrtValue *const *)iv, 3, outs, 1, &ov));
	float *data; CHECK(ort->GetTensorMutableData(ov, (void **)&data));
	OrtTensorTypeAndShapeInfo *info; size_t cnt;
	CHECK(ort->GetTensorTypeAndShape(ov, &info)); CHECK(ort->GetTensorShapeElementCount(info, &cnt));
	ort->ReleaseTensorTypeAndShapeInfo(info);
	if (cnt > (size_t)(2048 * n)) cnt = 2048 * n;
	memcpy(out, data, cnt * sizeof(float));
	for (int i = 0; i < 3; i++) ort->ReleaseValue(iv[i]);
	ort->ReleaseValue(ov);
	return (int)cnt;
}

// ---- growable float buffer
typedef struct { float *d; int n, cap; } buf_t;
static void bpush(buf_t *b, const float *x, int n) {
	if (b->n + n > b->cap) { b->cap = (b->n + n) * 2 + 4096; b->d = realloc(b->d, b->cap * sizeof(float)); }
	memcpy(b->d + b->n, x, n * sizeof(float)); b->n += n;
}
static void bdrop(buf_t *b, int n) { if (n <= 0) return; if (n > b->n) n = b->n; memmove(b->d, b->d + n, (b->n - n) * sizeof(float)); b->n -= n; }

// ---- utterance state
#define WIN 960
#define HOP 480
#define TOL 240
static float hann[WIN];
static float pitch = 1, tempo = 1; static int glitch;
static int32_t frames[4][7]; static int nfr;       // last 4 frames
static int total_frames;
static buf_t rs_in, ws_in, ola;                     // resampler input, wsola input, overlap-add accum
static double rs_pos;                               // fractional read position in rs_in
static double ws_pos; static int ws_prev = -1;     // wsola read pos, previous grain start
static int ws_base;                                 // samples dropped from ws_in so far
static uint32_t rng = 12345;
static float frand(void) { rng = rng * 1664525u + 1013904223u; return (rng >> 8) / 16777216.0f; }

static void reset(void) {
	nfr = 0; total_frames = 0; rs_in.n = 0; ws_in.n = 0; ola.n = 0; rs_pos = 0; ws_pos = 0; ws_prev = -1; ws_base = 0;
}

static sock_t cli;
static int send_all(const void *p, int n) {
	const char *c = p;
	while (n > 0) { int k = send(cli, c, n, 0); if (k <= 0) return -1; c += k; n -= k; }
	return 0;
}
static void emit(const float *x, int n) {
	if (n <= 0) return;
	int16_t *s = malloc(n * sizeof(int16_t));
	float *tmp = NULL;
	if (glitch) { // stutters and crackle when something goes wrong
		tmp = malloc(n * 3 * sizeof(float)); int m = 0;
		for (int i = 0; i < n; i += 480) {
			int len = (i + 480 <= n) ? 480 : n - i;
			int reps = (frand() < 0.06f) ? 2 + (int)(frand() * 2) : 1;
			for (int r = 0; r < reps; r++) for (int k = 0; k < len; k++) tmp[m++] = x[i + k] * (r ? 0.8f : 1.0f);
		}
		for (int i = 0; i < m; i++) { if (frand() < 0.0015f) tmp[i] += (frand() - 0.5f) * 0.6f; tmp[i] = floorf(tmp[i] * 48.0f) / 48.0f; }
		s = realloc(s, m * sizeof(int16_t)); x = tmp; n = m;
	}
	for (int i = 0; i < n; i++) { float v = x[i] * 32767.0f; s[i] = (int16_t)(v > 32767 ? 32767 : v < -32768 ? -32768 : v); }
	char h = 'A'; uint32_t nn = n;
	send_all(&h, 1); send_all(&nn, 4); send_all(s, n * 2);
	free(s); free(tmp);
}

// WSOLA: consume ws_in at rate (input hop = HOP*rate) and produce hop-sized output blocks.
static void wsola_run(int final) {
	double rate = tempo / pitch;
	float grain[WIN];
	for (;;) {
		int c = (int)ws_pos - ws_base;
		if (c + WIN + TOL > ws_in.n) break;
		if (ws_prev >= 0 && ws_prev - ws_base + HOP + WIN > ws_in.n) break;
		int best = c;
		if (ws_prev >= 0) {
			int lo = c - TOL; if (lo < 0) lo = 0;
			int hi = c + TOL;
			const float *tgt = ws_in.d + (ws_prev - ws_base) + HOP;
			double bestv = -1e30;
			for (int k = lo; k <= hi; k += 2) {
				double acc = 0; const float *s = ws_in.d + k;
				for (int i = 0; i < WIN; i += 4) acc += s[i] * tgt[i];
				if (acc > bestv) { bestv = acc; best = k; }
			}
		}
		for (int i = 0; i < WIN; i++) grain[i] = ws_in.d[best + i] * hann[i];
		if (ola.n < WIN) { float z[WIN] = {0}; bpush(&ola, z, WIN - ola.n); }
		for (int i = 0; i < WIN; i++) ola.d[i] += grain[i];
		emit(ola.d, HOP);
		bdrop(&ola, HOP);
		{ float z[HOP] = {0}; bpush(&ola, z, HOP); }
		ws_prev = best + ws_base;
		ws_pos += HOP * rate;
		// trim consumed input, keeping enough for the previous grain's continuation
		int keep_from = (int)fmin(ws_pos - ws_base - TOL, (double)(ws_prev - ws_base)) - 4;
		if (keep_from > 8192) { bdrop(&ws_in, keep_from); ws_base += keep_from; }
	}
	if (final) emit(ola.d, HOP);
}

// resample by pitch (raises pitch, speeds up), then wsola puts the speed back
static void process(const float *x, int n, int final) {
	if (fabsf(pitch - 1) < 1e-3f && fabsf(tempo - 1) < 1e-3f) { emit(x, n); return; }
	bpush(&rs_in, x, n);
	int cap = (int)(rs_in.n / pitch) + 4; float *y = malloc(cap * sizeof(float)); int m = 0;
	while (rs_pos + 1 < rs_in.n) {
		int i = (int)rs_pos; float f = (float)(rs_pos - i);
		y[m++] = rs_in.d[i] * (1 - f) + rs_in.d[i + 1] * f;
		rs_pos += pitch;
	}
	int drop = (int)rs_pos; bdrop(&rs_in, drop); rs_pos -= drop;
	bpush(&ws_in, y, m); free(y);
	if (final) { float z[WIN + TOL * 2] = {0}; bpush(&ws_in, z, WIN + TOL * 2); }
	wsola_run(final);
}

static void add_frame(int32_t *f) {
	if (nfr == 4) { memmove(frames[0], frames[1], sizeof(frames[0]) * 3); nfr = 3; }
	memcpy(frames[nfr++], f, sizeof(frames[0]));
	total_frames++;
	if (nfr < 4) return;
	float a[8192]; int got = decode(frames, 4, a);
	if (got < 8192) return;
	if (total_frames == 4) process(a, 6144, 0);   // frames 0..2
	else process(a + 4096, 2048, 0);             // newest-but-one frame
}

static void finish(void) {
	float a[8192];
	if (total_frames >= 4) { int got = decode(frames, 4, a); if (got >= 8192) process(a + 6144, 2048, 1); else process(a, 0, 1); }
	else if (nfr > 0) { int got = decode(frames, nfr, a); process(a, got, 1); }
	else process(a, 0, 1);
	char d = 'D'; send_all(&d, 1);
	reset();
}

static int recv_all(void *p, int n) {
	char *c = p;
	while (n > 0) { int k = recv(cli, c, n, 0); if (k <= 0) return -1; c += k; n -= k; }
	return 0;
}

int main(int argc, char **argv) {
	if (argc < 3) { fprintf(stderr, "usage: rico_voice decoder.onnx port\n"); return 1; }
	for (int i = 0; i < WIN; i++) hann[i] = 0.5f - 0.5f * cosf(2.0f * 3.14159265f * i / WIN);
	load_ort(argv[1]);
	{ int32_t z[7] = {0}; float a[8192]; int32_t fr[4][7]; for (int j = 0; j < 4; j++) memcpy(fr[j], z, sizeof z); decode(fr, 4, a); } // warm up
#ifdef _WIN32
	WSADATA w; WSAStartup(MAKEWORD(2, 2), &w);
#endif
	sock_t srv = socket(AF_INET, SOCK_STREAM, 0);
	int one = 1; setsockopt(srv, SOL_SOCKET, SO_REUSEADDR, (const char *)&one, sizeof one);
	struct sockaddr_in a; memset(&a, 0, sizeof a);
	a.sin_family = AF_INET; a.sin_port = htons((unsigned short)atoi(argv[2])); a.sin_addr.s_addr = htonl(0x7f000001);
	if (bind(srv, (struct sockaddr *)&a, sizeof a) != 0 || listen(srv, 1) != 0) { fprintf(stderr, "bind failed\n"); return 3; }
	printf("ready\n"); fflush(stdout);
	for (;;) {
		cli = accept(srv, NULL, NULL);
		if (cli == (sock_t)-1) continue;
		setsockopt(cli, IPPROTO_TCP, TCP_NODELAY, (const char *)&one, sizeof one);
		reset();
		for (;;) {
			char t; if (recv_all(&t, 1)) break;
			if (t == 'B') {
				float pt[2]; uint8_t g;
				if (recv_all(pt, 8) || recv_all(&g, 1)) break;
				reset(); pitch = pt[0] > 0.5f ? pt[0] : 1; tempo = pt[1] > 0.5f ? pt[1] : 1; glitch = g;
			} else if (t == 'F') {
				int32_t f[7]; if (recv_all(f, 28)) break;
				int ok = 1; for (int i = 0; i < 7; i++) if (f[i] < 0 || f[i] > 4095) ok = 0;
				if (ok) add_frame(f);
			} else if (t == 'E') {
				finish();
			} else if (t == 'Q') {
				CLOSESOCK(cli); return 0;
			}
		}
		CLOSESOCK(cli);
	}
}
