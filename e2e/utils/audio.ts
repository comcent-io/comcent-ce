import fs from 'node:fs';

// ---------------------------------------------------------------------------
// WAV generation (for Chrome --use-file-for-fake-audio-capture)
// ---------------------------------------------------------------------------

/**
 * Writes a mono 16-bit PCM WAV file containing a sine tone.
 * Chrome loops the file automatically, so 30 s is enough for any test call.
 *
 * @param outputPath  Absolute path to write the .wav file.
 * @param frequency   Tone frequency in Hz (default 440).
 * @param durationSec Duration in seconds (default 30).
 * @param sampleRate  Sample rate in Hz; 48 000 matches Chrome's WebRTC rate (default).
 */
export function generateSineWav(
  outputPath: string,
  {
    frequency = 440,
    durationSec = 30,
    sampleRate = 48_000,
    amplitude = 0.25,
  }: {
    frequency?: number;
    durationSec?: number;
    sampleRate?: number;
    amplitude?: number;
  } = {},
) {
  const numSamples = Math.floor(sampleRate * durationSec);
  const dataBytes = numSamples * 2; // 16-bit = 2 bytes per sample

  const buf = Buffer.alloc(44 + dataBytes);
  let o = 0;

  // RIFF header
  buf.write('RIFF', o);
  o += 4;
  buf.writeUInt32LE(36 + dataBytes, o);
  o += 4;
  buf.write('WAVE', o);
  o += 4;

  // fmt chunk
  buf.write('fmt ', o);
  o += 4;
  buf.writeUInt32LE(16, o);
  o += 4; // chunk size
  buf.writeUInt16LE(1, o);
  o += 2; // PCM
  buf.writeUInt16LE(1, o);
  o += 2; // mono
  buf.writeUInt32LE(sampleRate, o);
  o += 4;
  buf.writeUInt32LE(sampleRate * 2, o);
  o += 4; // byte rate
  buf.writeUInt16LE(2, o);
  o += 2; // block align
  buf.writeUInt16LE(16, o);
  o += 2; // bits per sample

  // data chunk
  buf.write('data', o);
  o += 4;
  buf.writeUInt32LE(dataBytes, o);
  o += 4;

  for (let i = 0; i < numSamples; i++) {
    const sample = Math.round(
      amplitude * 32_767 * Math.sin((2 * Math.PI * frequency * i) / sampleRate),
    );
    buf.writeInt16LE(sample, o);
    o += 2;
  }

  fs.writeFileSync(outputPath, buf);
}

// ---------------------------------------------------------------------------
// WAV sample-level helpers (read / write / concat for conversation design)
// ---------------------------------------------------------------------------

/**
 * Reads a 16-bit PCM WAV file into a mono Int16Array + the sample rate.
 * Stereo files are mixed to mono.
 */
export function readWavSamples(inputPath: string): {
  samples: Int16Array;
  sampleRate: number;
} {
  const wavBuf = fs.readFileSync(inputPath);
  if (
    wavBuf.toString('ascii', 0, 4) !== 'RIFF' ||
    wavBuf.toString('ascii', 8, 12) !== 'WAVE'
  ) {
    throw new Error(`${inputPath} is not a valid WAV file`);
  }

  let offset = 12;
  let sampleRate = 0;
  let channels = 0;
  let bitsPerSample = 0;
  let dataStart = 0;
  let dataLength = 0;

  while (offset < wavBuf.length - 8) {
    const chunkId = wavBuf.toString('ascii', offset, offset + 4);
    const chunkSize = wavBuf.readUInt32LE(offset + 4);
    offset += 8;
    if (chunkId === 'fmt ') {
      channels = wavBuf.readUInt16LE(offset + 2);
      sampleRate = wavBuf.readUInt32LE(offset + 4);
      bitsPerSample = wavBuf.readUInt16LE(offset + 14);
    } else if (chunkId === 'data') {
      dataStart = offset;
      // Clamp to actual buffer size in case the header length overshoots (e.g. odd-sized chunks).
      dataLength = Math.min(chunkSize, wavBuf.length - offset);
      break;
    }
    offset += chunkSize + (chunkSize % 2);
  }

  if (!sampleRate || !dataStart)
    throw new Error(`Cannot parse fmt/data in ${inputPath}`);

  const bytesPerSample = bitsPerSample / 8;
  const numSamples = Math.floor(dataLength / (bytesPerSample * channels));
  const samples = new Int16Array(numSamples);
  for (let i = 0; i < numSamples; i++) {
    let sum = 0;
    const base = dataStart + i * bytesPerSample * channels;
    for (let c = 0; c < channels; c++)
      sum += wavBuf.readInt16LE(base + c * bytesPerSample);
    samples[i] = Math.round(sum / channels);
  }
  return { samples, sampleRate };
}

/**
 * Writes a mono 16-bit PCM WAV file from an Int16Array of samples.
 */
export function writeWavSamples(
  outputPath: string,
  samples: Int16Array,
  sampleRate: number,
): void {
  const dataBytes = samples.length * 2;
  const buf = Buffer.alloc(44 + dataBytes);
  let o = 0;
  buf.write('RIFF', o);
  o += 4;
  buf.writeUInt32LE(36 + dataBytes, o);
  o += 4;
  buf.write('WAVE', o);
  o += 4;
  buf.write('fmt ', o);
  o += 4;
  buf.writeUInt32LE(16, o);
  o += 4;
  buf.writeUInt16LE(1, o);
  o += 2; // PCM
  buf.writeUInt16LE(1, o);
  o += 2; // mono
  buf.writeUInt32LE(sampleRate, o);
  o += 4;
  buf.writeUInt32LE(sampleRate * 2, o);
  o += 4;
  buf.writeUInt16LE(2, o);
  o += 2;
  buf.writeUInt16LE(16, o);
  o += 2;
  buf.write('data', o);
  o += 4;
  buf.writeUInt32LE(dataBytes, o);
  o += 4;
  for (let i = 0; i < samples.length; i++) {
    buf.writeInt16LE(samples[i], o);
    o += 2;
  }
  fs.writeFileSync(outputPath, buf);
}

/**
 * Concatenates multiple Int16Arrays into one (for building conversation WAVs).
 */
export function concatSamples(...parts: Int16Array[]): Int16Array {
  const total = parts.reduce((n, p) => n + p.length, 0);
  const out = new Int16Array(total);
  let pos = 0;
  for (const p of parts) {
    out.set(p, pos);
    pos += p.length;
  }
  return out;
}

/**
 * Creates a silent Int16Array of the given duration.
 */
export function silenceSamples(
  durationSec: number,
  sampleRate: number,
): Int16Array {
  return new Int16Array(Math.floor(durationSec * sampleRate));
}

// ---------------------------------------------------------------------------
// G.711 μ-law encoding (CCITT / ANSI standard)
// ---------------------------------------------------------------------------

const MULAW_BIAS = 0x84; // 132
const MULAW_CLIP = 8_159;

function linearToMuLaw(sample: number): number {
  const sign = sample < 0 ? 0x80 : 0;
  if (sign) sample = -sample;
  if (sample > MULAW_CLIP) sample = MULAW_CLIP;

  sample += MULAW_BIAS;

  // Find exponent — highest set bit position in bits 13..7
  let exponent = 7;
  for (let mask = 0x4000; (sample & mask) === 0 && exponent > 0; mask >>= 1) {
    exponent--;
  }

  const mantissa = (sample >> (exponent + 3)) & 0x0f;
  return ~(sign | (exponent << 4) | mantissa) & 0xff;
}

// ---------------------------------------------------------------------------
// PCAP generation (for SIPp play_pcap_audio)
// ---------------------------------------------------------------------------

// SIPp reads timestamps from the PCAP to pace playback.
// Each RTP packet: 20 ms = 160 samples @ 8 kHz (standard G.711 ptime).
const G711_SAMPLE_RATE = 8_000;
const RTP_PTIME_MS = 20;
const SAMPLES_PER_PACKET = (G711_SAMPLE_RATE * RTP_PTIME_MS) / 1_000; // 160
const PACKET_INTERVAL_US = RTP_PTIME_MS * 1_000; // 20 000 µs

const ETH_HDR = 14;
const IP_HDR = 20;
const UDP_HDR = 8;
const RTP_HDR = 12;
const PAYLOAD = SAMPLES_PER_PACKET; // 160 bytes
const PKT_LEN = ETH_HDR + IP_HDR + UDP_HDR + RTP_HDR + PAYLOAD; // 214 bytes

/**
 * Writes a libpcap file containing G.711 μ-law RTP packets encoding a sine tone.
 * SIPp's play_pcap_audio strips the Ethernet/IP/UDP headers and sends the RTP
 * payload to the remote party's address from the INVITE SDP, so the IPs/ports
 * in the PCAP are irrelevant — only the RTP payload and timestamps matter.
 *
 * @param outputPath  Absolute path to write the .pcap file.
 * @param frequency   Tone frequency in Hz (default 880).
 * @param durationSec Duration in seconds (default 30).
 * @param amplitude   Amplitude 0–1 relative to MULAW_CLIP (default 0.25).
 */
export function generateSinePcap(
  outputPath: string,
  {
    frequency = 880,
    durationSec = 30,
    amplitude = 0.25,
  }: { frequency?: number; durationSec?: number; amplitude?: number } = {},
) {
  const totalSamples = G711_SAMPLE_RATE * durationSec;
  const numPackets = Math.floor(totalSamples / SAMPLES_PER_PACKET);

  const PCAP_GLOBAL_HDR = 24;
  const PCAP_REC_HDR = 16;
  const bufSize = PCAP_GLOBAL_HDR + numPackets * (PCAP_REC_HDR + PKT_LEN);
  const buf = Buffer.alloc(bufSize);
  let o = 0;

  // ---- PCAP global header ----
  buf.writeUInt32LE(0xa1b2c3d4, o);
  o += 4; // magic (little-endian timestamps)
  buf.writeUInt16LE(2, o);
  o += 2; // major version
  buf.writeUInt16LE(4, o);
  o += 2; // minor version
  buf.writeInt32LE(0, o);
  o += 4; // UTC offset
  buf.writeUInt32LE(0, o);
  o += 4; // timestamp accuracy
  buf.writeUInt32LE(65_535, o);
  o += 4; // snaplen
  buf.writeUInt32LE(1, o);
  o += 4; // link type: Ethernet

  let seqNum = 0;
  let rtpTimestamp = 0;
  let sampleIdx = 0;
  let timeUs = 0;

  for (let p = 0; p < numPackets; p++) {
    const timeSec = Math.floor(timeUs / 1_000_000);
    const timeUsec = timeUs % 1_000_000;

    // ---- PCAP record header ----
    buf.writeUInt32LE(timeSec, o);
    o += 4;
    buf.writeUInt32LE(timeUsec, o);
    o += 4;
    buf.writeUInt32LE(PKT_LEN, o);
    o += 4; // captured length
    buf.writeUInt32LE(PKT_LEN, o);
    o += 4; // original length

    // ---- Ethernet header (DIX / Ethernet II) ----
    buf.fill(0, o, o + 6);
    o += 6; // dst MAC 00:00:00:00:00:00
    buf.fill(0, o, o + 5);
    o += 5; // src MAC 00:00:00:00:00:01 (last byte below)
    buf.writeUInt8(1, o);
    o += 1;
    buf.writeUInt16BE(0x0800, o);
    o += 2; // EtherType: IPv4

    // ---- IPv4 header ----
    const ipPayloadLen = UDP_HDR + RTP_HDR + PAYLOAD;
    buf.writeUInt8(0x45, o);
    o += 1; // version 4, IHL 5
    buf.writeUInt8(0, o);
    o += 1; // DSCP/ECN
    buf.writeUInt16BE(IP_HDR + ipPayloadLen, o);
    o += 2; // total length
    buf.writeUInt16BE(p & 0xffff, o);
    o += 2; // identification
    buf.writeUInt16BE(0x4000, o);
    o += 2; // flags: DF, no fragment offset
    buf.writeUInt8(64, o);
    o += 1; // TTL
    buf.writeUInt8(17, o);
    o += 1; // protocol: UDP
    buf.writeUInt16BE(0, o);
    o += 2; // checksum (0 = omit, SIPp doesn't validate)
    // src 127.0.0.1
    buf.writeUInt8(127, o);
    o += 1;
    buf.writeUInt8(0, o);
    o += 1;
    buf.writeUInt8(0, o);
    o += 1;
    buf.writeUInt8(1, o);
    o += 1;
    // dst 127.0.0.2
    buf.writeUInt8(127, o);
    o += 1;
    buf.writeUInt8(0, o);
    o += 1;
    buf.writeUInt8(0, o);
    o += 1;
    buf.writeUInt8(2, o);
    o += 1;

    // ---- UDP header ----
    buf.writeUInt16BE(20_000, o);
    o += 2; // src port
    buf.writeUInt16BE(20_002, o);
    o += 2; // dst port
    buf.writeUInt16BE(UDP_HDR + RTP_HDR + PAYLOAD, o);
    o += 2; // length
    buf.writeUInt16BE(0, o);
    o += 2; // checksum (0 = omit)

    // ---- RTP header ----
    buf.writeUInt8(0x80, o);
    o += 1; // V=2, P=0, X=0, CC=0
    buf.writeUInt8(0x00, o);
    o += 1; // M=0, PT=0 (PCMU / G.711 μ-law)
    buf.writeUInt16BE(seqNum & 0xffff, o);
    o += 2;
    buf.writeUInt32BE(rtpTimestamp, o);
    o += 4;
    buf.writeUInt32BE(0x12345678, o);
    o += 4; // SSRC (arbitrary)

    // ---- G.711 μ-law payload ----
    for (let s = 0; s < SAMPLES_PER_PACKET; s++) {
      const linear = Math.round(
        amplitude *
          MULAW_CLIP *
          Math.sin((2 * Math.PI * frequency * sampleIdx) / G711_SAMPLE_RATE),
      );
      buf.writeUInt8(linearToMuLaw(linear), o);
      o += 1;
      sampleIdx++;
    }

    seqNum++;
    rtpTimestamp += SAMPLES_PER_PACKET;
    timeUs += PACKET_INTERVAL_US;
  }

  fs.writeFileSync(outputPath, buf);
}

// ---------------------------------------------------------------------------
// WAV → PCAP conversion (for pre-recorded speech fixtures)
// ---------------------------------------------------------------------------

/**
 * Reads a 16-bit PCM WAV file, resamples to 8 kHz mono, encodes as G.711
 * μ-law, and writes a libpcap file suitable for SIPp play_pcap_audio.
 *
 * Supports any sample rate and mono/stereo input.
 */
export function wavToPcap(inputWavPath: string, outputPcapPath: string) {
  const wavBuf = fs.readFileSync(inputWavPath);

  // ── Parse WAV header ──────────────────────────────────────────────────────
  if (
    wavBuf.toString('ascii', 0, 4) !== 'RIFF' ||
    wavBuf.toString('ascii', 8, 12) !== 'WAVE'
  ) {
    throw new Error(`${inputWavPath} is not a valid WAV file`);
  }

  let offset = 12;
  let srcSampleRate = 0;
  let srcChannels = 0;
  let srcBitsPerSample = 0;
  let dataStart = 0;
  let dataLength = 0;

  while (offset < wavBuf.length - 8) {
    const chunkId = wavBuf.toString('ascii', offset, offset + 4);
    const chunkSize = wavBuf.readUInt32LE(offset + 4);
    offset += 8;
    if (chunkId === 'fmt ') {
      srcChannels = wavBuf.readUInt16LE(offset + 2);
      srcSampleRate = wavBuf.readUInt32LE(offset + 4);
      srcBitsPerSample = wavBuf.readUInt16LE(offset + 14);
    } else if (chunkId === 'data') {
      dataStart = offset;
      dataLength = chunkSize;
      break;
    }
    offset += chunkSize + (chunkSize % 2); // word-align
  }

  if (!srcSampleRate || !dataStart) {
    throw new Error(`Could not parse fmt/data chunks in ${inputWavPath}`);
  }

  const bytesPerSample = srcBitsPerSample / 8;
  const numSrcSamples = Math.floor(dataLength / (bytesPerSample * srcChannels));

  // ── Read & mix to mono ────────────────────────────────────────────────────
  const monoSamples = new Int16Array(numSrcSamples);
  for (let i = 0; i < numSrcSamples; i++) {
    let sum = 0;
    const base = dataStart + i * bytesPerSample * srcChannels;
    for (let c = 0; c < srcChannels; c++) {
      sum += wavBuf.readInt16LE(base + c * bytesPerSample);
    }
    monoSamples[i] = Math.round(sum / srcChannels);
  }

  // ── Resample to 8 kHz (linear interpolation) ─────────────────────────────
  let pcm8k: Int16Array;
  if (srcSampleRate === G711_SAMPLE_RATE) {
    pcm8k = monoSamples;
  } else {
    const ratio = srcSampleRate / G711_SAMPLE_RATE;
    const outLen = Math.floor(numSrcSamples / ratio);
    pcm8k = new Int16Array(outLen);
    for (let i = 0; i < outLen; i++) {
      const src = i * ratio;
      const lo = Math.floor(src);
      const hi = Math.min(lo + 1, numSrcSamples - 1);
      const frac = src - lo;
      pcm8k[i] = Math.round(
        monoSamples[lo] * (1 - frac) + monoSamples[hi] * frac,
      );
    }
  }

  // ── Write PCAP with G.711 μ-law RTP packets ───────────────────────────────
  const numPackets = Math.floor(pcm8k.length / SAMPLES_PER_PACKET);
  const PCAP_GLOBAL_HDR = 24;
  const PCAP_REC_HDR = 16;
  const bufSize = PCAP_GLOBAL_HDR + numPackets * (PCAP_REC_HDR + PKT_LEN);
  const buf = Buffer.alloc(bufSize);
  let o = 0;

  buf.writeUInt32LE(0xa1b2c3d4, o);
  o += 4;
  buf.writeUInt16LE(2, o);
  o += 2;
  buf.writeUInt16LE(4, o);
  o += 2;
  buf.writeInt32LE(0, o);
  o += 4;
  buf.writeUInt32LE(0, o);
  o += 4;
  buf.writeUInt32LE(65_535, o);
  o += 4;
  buf.writeUInt32LE(1, o);
  o += 4;

  let seqNum = 0;
  let rtpTimestamp = 0;
  let timeUs = 0;

  for (let p = 0; p < numPackets; p++) {
    const timeSec = Math.floor(timeUs / 1_000_000);
    const timeUsec = timeUs % 1_000_000;

    buf.writeUInt32LE(timeSec, o);
    o += 4;
    buf.writeUInt32LE(timeUsec, o);
    o += 4;
    buf.writeUInt32LE(PKT_LEN, o);
    o += 4;
    buf.writeUInt32LE(PKT_LEN, o);
    o += 4;

    buf.fill(0, o, o + 6);
    o += 6;
    buf.fill(0, o, o + 5);
    o += 5;
    buf.writeUInt8(1, o);
    o += 1;
    buf.writeUInt16BE(0x0800, o);
    o += 2;

    const ipPayloadLen = UDP_HDR + RTP_HDR + PAYLOAD;
    buf.writeUInt8(0x45, o);
    o += 1;
    buf.writeUInt8(0, o);
    o += 1;
    buf.writeUInt16BE(IP_HDR + ipPayloadLen, o);
    o += 2;
    buf.writeUInt16BE(p & 0xffff, o);
    o += 2;
    buf.writeUInt16BE(0x4000, o);
    o += 2;
    buf.writeUInt8(64, o);
    o += 1;
    buf.writeUInt8(17, o);
    o += 1;
    buf.writeUInt16BE(0, o);
    o += 2;
    buf.writeUInt8(127, o);
    o += 1;
    buf.writeUInt8(0, o);
    o += 1;
    buf.writeUInt8(0, o);
    o += 1;
    buf.writeUInt8(1, o);
    o += 1;
    buf.writeUInt8(127, o);
    o += 1;
    buf.writeUInt8(0, o);
    o += 1;
    buf.writeUInt8(0, o);
    o += 1;
    buf.writeUInt8(2, o);
    o += 1;

    buf.writeUInt16BE(20_000, o);
    o += 2;
    buf.writeUInt16BE(20_002, o);
    o += 2;
    buf.writeUInt16BE(UDP_HDR + RTP_HDR + PAYLOAD, o);
    o += 2;
    buf.writeUInt16BE(0, o);
    o += 2;

    buf.writeUInt8(0x80, o);
    o += 1;
    buf.writeUInt8(0x00, o);
    o += 1;
    buf.writeUInt16BE(seqNum & 0xffff, o);
    o += 2;
    buf.writeUInt32BE(rtpTimestamp, o);
    o += 4;
    buf.writeUInt32BE(0x12345678, o);
    o += 4;

    const base = p * SAMPLES_PER_PACKET;
    for (let s = 0; s < SAMPLES_PER_PACKET; s++) {
      buf.writeUInt8(linearToMuLaw(pcm8k[base + s]), o);
      o += 1;
    }

    seqNum++;
    rtpTimestamp += SAMPLES_PER_PACKET;
    timeUs += PACKET_INTERVAL_US;
  }

  fs.writeFileSync(outputPcapPath, buf.subarray(0, o));
}
