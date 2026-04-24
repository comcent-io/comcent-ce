/**
 * Per-test DID numbers and SIPp port allocations.
 *
 * Every test file gets its own DID and port range so the full suite can run
 * in parallel without shared-resource conflicts.  Ports start at 6000 and
 * are spaced by 10 to leave room for sub-allocations (register port = base + 100).
 */

export type TestAllocation = {
  did: string;
  callerPort: number;
  uasPort: number;
  agentAPort: number;
  agentBPort: number;
};

function alloc(
  did: string,
  base: number,
  overrides?: Partial<TestAllocation>,
): TestAllocation {
  return {
    did,
    callerPort: base,
    uasPort: base + 1,
    agentAPort: base + 2,
    agentBPort: base + 4,
    ...overrides,
  };
}

export const allocations = {
  agentOutbound: alloc('+14155552701', 6000),
  agentToAgent: alloc('+14155552702', 6010),
  blindTransfer: alloc('+14155552703', 6020),
  holdResume: alloc('+14155552704', 6030),
  inboundDial: alloc('+14155552705', 6040),
  inboundDialGroupParallel: alloc('+14155552706', 6050),
  inboundDialGroupTimeout: alloc('+14155552724', 6310),
  inboundDialGroupCancel: alloc('+14155552725', 6320),
  inboundDirectAgentSipp: alloc('+14155552707', 6060),
  inboundDirectAgentWebRtc: alloc('+14155552708', 6070),
  inboundIpWhitelist: alloc('+14155552709', 6080),
  inboundQueueSipp: alloc('+14155552710', 6090),
  inboundQueueWebRtc: alloc('+14155552711', 6100),
  menuBranch: alloc('+14155552712', 6110),
  presence: alloc('+14155552713', 6120),
  queueConcurrent: alloc('+14155552714', 6130),
  queueFailover: alloc('+14155552715', 6140),
  queueTimeout: alloc('+14155552716', 6150),
  recordingContent: alloc('+14155552717', 6160),
  sipRegistration: alloc('+14155552718', 6170),
  trunkAuth: alloc('+14155552719', 6180),
  voiceBot: alloc('+14155552720', 6190),
  weekTimeActive: alloc('+14155552721', 6200),
  weekTimeFallback: alloc('+14155552726', 6330),
  // Queue stress tests use two queues and need wider, non-overlapping ranges
  // so large caller bursts and many SIP agents can run concurrently.
  queueStressQ1: alloc('+14155552722', 6210, {
    uasPort: 6230,
    agentAPort: 6240,
    agentBPort: 6250,
  }),
  queueStressQ2: alloc('+14155552723', 6260, {
    uasPort: 6280,
    agentAPort: 6290,
    agentBPort: 6300,
  }),
} as const;

export const ALL_TEST_DIDS = Object.values(allocations).map((a) => a.did);
