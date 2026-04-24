# Test Audio Fixtures

Pre-recorded speech files used by telephony e2e tests to simulate a two-way conversation.

| File | Voice | Format | Used by |
|------|-------|--------|---------|
| `agent.wav` | Deepgram `aura-asteria-en` (female) | 48 kHz mono 16-bit PCM WAV | Chrome `--use-file-for-fake-audio-capture` (agent-to-customer tests) |
| `customer.pcap` | Deepgram `aura-orion-en` (male) | G.711 μ-law RTP, libpcap | `play_pcap.pl` via SIPp `<exec>` |
| `agent1.wav` | Deepgram `aura-asteria-en` (female) | 48 kHz mono 16-bit PCM WAV | Chrome fake mic for agent 1 in agent-to-agent tests |
| `agent2.wav` | Deepgram `aura-orion-en` (male) | 48 kHz mono 16-bit PCM WAV | Chrome fake mic for agent 2 in agent-to-agent tests |
| `blindTransferAgent1.wav` | Deepgram `aura-asteria-en` (female) | 48 kHz mono 16-bit PCM WAV | Chrome fake mic for first agent in blind-transfer test |
| `blindTransferAgent2.wav` | Deepgram `aura-orion-en` (male) | 48 kHz mono 16-bit PCM WAV | Chrome fake mic for second agent in blind-transfer test |

## Conversation design

The two audio files are coordinated to produce an alternating conversation
(one side speaks while the other is silent):

```
TIME    AGENT (aura-asteria-en)           CUSTOMER (aura-orion-en)
0–6s    "Hello, this is the agent…"       — silent —
6–14s   — silent —                        "Hi there, I am the customer…"
14–20s  "I understand, let me look…"      — silent —
20–24s  — trailing silence —              — silent —
```

`agent.wav` is ~24 s then Chrome loops it.
`customer.pcap` is ~17 s (leading silence + customer speech + trailing silence).

For agent-to-agent tests, `agent1.wav` and `agent2.wav` are both 20.5 s and
carry complementary turns of a short dialogue:

```
TIME      AGENT 1 (agent1.wav)                   AGENT 2 (agent2.wav)
0–5.3s    "Hi Agent Two, this is Agent One…"    — silent —
5.3–6.3s  — silent —                             — silent —
6.3–11.4s — silent —                             "Hi Agent One, yes I am…"
11.4–12.4s — silent —                            — silent —
12.4–17.5s "It is a billing issue…"              — silent —
17.5–20.5s — trailing silence —                  — trailing silence —
```

## Note on Mac Docker and play_pcap_audio

On Mac, FreeSwitch advertises `127.0.0.1` in the SDP `c=` line (because
`E2E_PUBLIC_IP=127.0.0.1` is required for browser WebRTC via port-forwarding).
SIPp's built-in `play_pcap_audio` would blindly send to `127.0.0.1` which is
sipp-uas's own loopback inside the container, never reaching FreeSwitch.

`uas-answer-pcap.xml` therefore uses `play_pcap.pl` via `<exec command>` which
sends directly to FreeSwitch's static container IP (`172.29.17.8`) using
the RTP port extracted from the received INVITE SDP via awk on the SIPp
messages log.  This works on both Mac and Linux CI.

## Regenerating

Requires a Deepgram API key in `.env` (`DEEPGRAM_API_KEY`) and Node.js.

```sh
# 1. Fetch speech segments from Deepgram TTS
DEEPGRAM_KEY=$(grep DEEPGRAM_API_KEY .env | cut -d= -f2)

curl -s -X POST "https://api.deepgram.com/v1/speak?model=aura-asteria-en&encoding=linear16&sample_rate=48000&container=wav" \
  -H "Authorization: Token $DEEPGRAM_KEY" \
  -H "Content-Type: application/json" \
  -d '{"text":"Hello, this is the agent speaking. I am calling from Acme Corporation. How can I help you today?"}' \
  -o /tmp/agent1.wav

curl -s -X POST "https://api.deepgram.com/v1/speak?model=aura-asteria-en&encoding=linear16&sample_rate=48000&container=wav" \
  -H "Authorization: Token $DEEPGRAM_KEY" \
  -H "Content-Type: application/json" \
  -d '{"text":"I understand. Let me look into your account right now and see what I can do for you."}' \
  -o /tmp/agent2.wav

curl -s -X POST "https://api.deepgram.com/v1/speak?model=aura-orion-en&encoding=linear16&sample_rate=48000&container=wav" \
  -H "Authorization: Token $DEEPGRAM_KEY" \
  -H "Content-Type: application/json" \
  -d '{"text":"Hi there, I am the customer. I am calling about my recent account activity and I need some help please."}' \
  -o /tmp/customer1.wav

# 2. Assemble with silence gaps and convert customer WAV to PCAP
node --input-type=module -e "
  import { readWavSamples, writeWavSamples, concatSamples, silenceSamples, wavToPcap }
    from './e2e/utils/audio.ts';

  const a1 = readWavSamples('/tmp/agent1.wav');
  const a2 = readWavSamples('/tmp/agent2.wav');
  const c1 = readWavSamples('/tmp/customer1.wav');

  const a1Sec = a1.samples.length / a1.sampleRate;
  const c1Sec = c1.samples.length / c1.sampleRate;

  // Agent: agent1 + gap while customer speaks + agent2 + trailing silence
  const agentSamples = concatSamples(
    a1.samples,
    silenceSamples(c1Sec + 1, 48000),
    a2.samples,
    silenceSamples(6, 48000),
  );
  writeWavSamples('e2e/telephony/audio/agent.wav', agentSamples, 48000);

  // Customer: resample 48->8kHz, leading silence while agent speaks, trailing silence
  const ratio = c1.sampleRate / 8000;
  const outLen = Math.floor(c1.samples.length / ratio);
  const c1_8k = new Int16Array(outLen);
  for (let i = 0; i < outLen; i++) {
    const src = i * ratio;
    const lo = Math.floor(src);
    const hi = Math.min(lo + 1, c1.samples.length - 1);
    c1_8k[i] = Math.round(c1.samples[lo] * (1 - (src - lo)) + c1.samples[hi] * (src - lo));
  }
  const finalCustomer = concatSamples(
    silenceSamples(a1Sec + 1, 8000),
    c1_8k,
    silenceSamples(4, 8000),
  );
  writeWavSamples('/tmp/customer-8k.wav', finalCustomer, 8000);
  wavToPcap('/tmp/customer-8k.wav', 'e2e/telephony/audio/customer.pcap');
  console.log('Done');
"
```
