#!/usr/bin/env node
/**
 * Generates a PCAP file containing RFC 2833 DTMF RTP events.
 *
 * The output PCAP is consumed by play_pcap.pl which strips the first 42 bytes
 * (Ethernet + IP + UDP headers) from each record and sends the remainder as
 * a UDP datagram to the target host:port.  So each PCAP record must contain:
 *
 *   [14-byte fake Ethernet] [20-byte fake IP] [8-byte fake UDP] [RTP payload]
 *
 * Usage:  node generate-dtmf-pcap.mjs [digit] [output]
 *         node generate-dtmf-pcap.mjs 1 dtmf-1.pcap
 */

import { writeFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const digit = process.argv[2] ?? '1';
const outputName = process.argv[3] ?? `dtmf-${digit}.pcap`;
const outputPath = resolve(dirname(fileURLToPath(import.meta.url)), outputName);

const DTMF_EVENTS = {
  '0': 0, '1': 1, '2': 2, '3': 3, '4': 4,
  '5': 5, '6': 6, '7': 7, '8': 8, '9': 9,
  '*': 10, '#': 11,
};

const event = DTMF_EVENTS[digit];
if (event === undefined) {
  console.error(`Unknown DTMF digit: ${digit}`);
  process.exit(1);
}

const SAMPLE_RATE = 8000;
const PTIME_MS = 20;
const SAMPLES_PER_PACKET = (SAMPLE_RATE * PTIME_MS) / 1000; // 160
const DTMF_DURATION_MS = 250;
const DTMF_PACKETS = Math.ceil(DTMF_DURATION_MS / PTIME_MS); // 13
const END_REPEAT = 3;
const PAYLOAD_TYPE = 101;
const SSRC = 0x12345678;
const VOLUME = 10;

// Pre-DTMF silence: send a few PCMU comfort-noise packets so FS sees
// the RTP stream before the DTMF events arrive.  Without these, FS may
// not have established the media path yet when the first event arrives.
const SILENCE_PACKETS = 25; // 500ms of silence at 20ms ptime

function buildPcapGlobalHeader() {
  const buf = Buffer.alloc(24);
  buf.writeUInt32LE(0xa1b2c3d4, 0);  // magic
  buf.writeUInt16LE(2, 4);            // major
  buf.writeUInt16LE(4, 6);            // minor
  buf.writeInt32LE(0, 8);             // thiszone
  buf.writeUInt32LE(0, 12);           // sigfigs
  buf.writeUInt32LE(65535, 16);       // snaplen
  buf.writeUInt32LE(1, 20);           // network (Ethernet)
  return buf;
}

function buildFakeHeaders() {
  // 14-byte Ethernet + 20-byte IP + 8-byte UDP = 42 bytes
  return Buffer.alloc(42);
}

function buildRtpHeader(seq, timestamp, marker, payloadType, ssrc) {
  const buf = Buffer.alloc(12);
  buf.writeUInt8(0x80, 0); // V=2, P=0, X=0, CC=0
  buf.writeUInt8((marker ? 0x80 : 0) | (payloadType & 0x7f), 1);
  buf.writeUInt16BE(seq, 2);
  buf.writeUInt32BE(timestamp, 4);
  buf.writeUInt32BE(ssrc, 8);
  return buf;
}

function buildRfc2833Payload(eventCode, endBit, volume, duration) {
  const buf = Buffer.alloc(4);
  buf.writeUInt8(eventCode, 0);
  buf.writeUInt8((endBit ? 0x80 : 0) | (volume & 0x3f), 1);
  buf.writeUInt16BE(duration, 2);
  return buf;
}

function buildPcmuSilencePayload() {
  // 160 bytes of u-law silence (0xFF = digital silence in G.711 u-law)
  return Buffer.alloc(160, 0xff);
}

function buildPcapRecord(timestamp_us, payload) {
  const fakeHeaders = buildFakeHeaders();
  const caplen = fakeHeaders.length + payload.length;
  const hdr = Buffer.alloc(16);
  const sec = Math.floor(timestamp_us / 1_000_000);
  const usec = Math.floor(timestamp_us % 1_000_000);
  hdr.writeUInt32LE(sec, 0);
  hdr.writeUInt32LE(usec, 4);
  hdr.writeUInt32LE(caplen, 8);
  hdr.writeUInt32LE(caplen, 12);
  return Buffer.concat([hdr, fakeHeaders, payload]);
}

const records = [];
let seq = 1000;
let timestamp = 0;
let pcapTime = 0; // microseconds

// Phase 1: silence packets (PCMU payload type 0) so FS locks onto the stream
for (let i = 0; i < SILENCE_PACKETS; i++) {
  const rtp = buildRtpHeader(seq++, timestamp, i === 0, 0, SSRC);
  const payload = buildPcmuSilencePayload();
  records.push(buildPcapRecord(pcapTime, Buffer.concat([rtp, payload])));
  timestamp += SAMPLES_PER_PACKET;
  pcapTime += PTIME_MS * 1000;
}

// Phase 2: DTMF start + continuation (E=0)
const dtmfStartTimestamp = timestamp;
for (let i = 0; i < DTMF_PACKETS; i++) {
  const marker = i === 0;
  const duration = (i + 1) * SAMPLES_PER_PACKET;
  const rtp = buildRtpHeader(seq++, dtmfStartTimestamp, marker, PAYLOAD_TYPE, SSRC);
  const payload = buildRfc2833Payload(event, false, VOLUME, duration);
  records.push(buildPcapRecord(pcapTime, Buffer.concat([rtp, payload])));
  pcapTime += PTIME_MS * 1000;
}

// Phase 3: DTMF end packets (E=1, same timestamp, same duration)
const finalDuration = DTMF_PACKETS * SAMPLES_PER_PACKET;
for (let i = 0; i < END_REPEAT; i++) {
  const rtp = buildRtpHeader(seq++, dtmfStartTimestamp, false, PAYLOAD_TYPE, SSRC);
  const payload = buildRfc2833Payload(event, true, VOLUME, finalDuration);
  records.push(buildPcapRecord(pcapTime, Buffer.concat([rtp, payload])));
  pcapTime += PTIME_MS * 1000;
}

const pcap = Buffer.concat([buildPcapGlobalHeader(), ...records]);
writeFileSync(outputPath, pcap);
console.log(`Wrote ${pcap.length} bytes to ${outputPath} (digit=${digit}, event=${event})`);
