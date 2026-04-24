import { expect, test } from '@playwright/test';
import {
  ensureDefaultOutboundRoute,
  setNumberInboundFlowToQueue,
  waitForCallSpans,
  waitForCallStory,
} from '../utils/telephonyDb';
import { createQueueViaApi } from '../utils/telephonyApi';
import { runInboundDidCall } from '../utils/sipp';
import { allocations } from './testAllocations';

const A = allocations.queueTimeout;

test.describe.configure({ mode: 'serial' });

test(
  'Call into an empty queue is held with music until the caller hangs up',
  { tag: ['@sipp', '@queue', '@timeout'] },
  async ({ page }) => {
    test.setTimeout(180_000);

    const publicNumber = A.did;
    const customerNumber = '+14155557662';
    const queueName = 'telephony_queue_timeout';

    await ensureDefaultOutboundRoute({
      subdomain: 'acme',
      number: publicNumber,
      sipTrunkName: 'Telephony Queue Timeout',
      outboundContact: 'sipp-uas:' + A.uasPort,
      inboundIps: ['172.29.0.0/16'],
    });

    await createQueueViaApi({
      page,
      subdomain: 'acme',
      name: queueName,
      extension: '8401',
      wrapUpTime: 1,
      rejectDelayTime: 1,
      maxNoAnswers: 1,
    });
    await setNumberInboundFlowToQueue(publicNumber, queueName);

    // Caller waits 15 s (hardcoded pause in uac-basic.xml) before sending
    // BYE — long enough for FreeSwitch to route the call into the queue,
    // hold it with music while no agent is available, and produce a
    // call-level recording of the wait.
    const callerResult = await runInboundDidCall({
      customerNumber,
      didNumber: publicNumber,
      localPort: A.callerPort,
      hangupAfterMs: 60_000,
    });

    expect(callerResult.stderr).not.toContain('Failed');

    const callStory = await waitForCallStory({
      caller: customerNumber,
      callee: publicNumber,
      direction: 'inbound',
      timeoutMs: 90_000,
    });

    const spans = await waitForCallSpans(
      callStory.id,
      (rows) =>
        rows.some(
          (row) => row.type === 'RECORDING' && row.metadata?.file_name != null,
        ),
      60_000,
    );

    // No agent was ever rung — there must be no RINGING or ON_CALL span
    // whose current_party points at an agent AoR.
    const agentSpan = spans.find(
      (row) =>
        (row.type === 'RINGING' || row.type === 'ON_CALL') &&
        row.current_party?.includes('@acme.comcent.io'),
    );
    expect(agentSpan).toBeUndefined();

    // A recording must be produced — the queue's music-on-hold playback
    // is captured while the caller waits.
    const recording = spans.find(
      (row) =>
        row.type === 'RECORDING' &&
        row.metadata?.file_name != null &&
        row.metadata?.fileSize != null,
    );
    expect(recording).toBeTruthy();
    expect(Number(recording!.metadata!.fileSize ?? 0)).toBeGreaterThan(0);
  },
);
