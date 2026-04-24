import { expect, test } from '@playwright/test';
import {
  assertRecordingProduced,
  ensureDefaultOutboundRoute,
  ensureMemberInOrg,
  setNumberInboundFlowToQueue,
  waitForInboundCallStoryObserved,
} from '../utils/telephonyDb';
import { addQueueMemberViaApi, createQueueViaApi } from '../utils/telephonyApi';
import {
  copyFileToContainer,
  CUSTOMER_PCAP_HOST_PATH,
  registerSipAgentInline,
  runInboundDidCall,
  runSipp,
  unregisterSipAgentInline,
} from '../utils/sipp';
import { allocations } from './testAllocations';

const A = allocations.inboundQueueSipp;

test.describe.configure({ mode: 'serial' });

test(
  'Inbound DID routes through Queue node to an available registered agent via SIPp caller',
  { tag: ['@sipp', '@queue'] },
  async ({ page }) => {
    test.setTimeout(180_000);

    const publicNumber = A.did;
    const customerNumber = '+14155559876';
    const queueName = 'telephonysupport';
    const queueExtension = '8101';
    const agentUsername = 'telephonyagent';
    const agentSipPassword = 'TelephonyAgent@1902';
    const agentEmail = 'test.user+telephonyagent@example.com';
    const agentService = 'sipp-agent-a';
    const agentPort = A.agentAPort;

    const { userId } = await ensureMemberInOrg({
      subdomain: 'acme',
      email: agentEmail,
      name: 'Telephony Agent',
      username: agentUsername,
      sipPassword: agentSipPassword,
      presence: 'Available',
    });

    const queueResponse = await createQueueViaApi({
      page,
      subdomain: 'acme',
      name: queueName,
      extension: queueExtension,
    });
    const queueId = queueResponse.queue.id;
    await addQueueMemberViaApi({
      page,
      subdomain: 'acme',
      queueId,
      userId,
    });
    await ensureDefaultOutboundRoute({
      subdomain: 'acme',
      number: publicNumber,
      sipTrunkName: 'Telephony SIPp Queue',
      outboundContact: 'sipp-uas:' + A.uasPort,
      inboundIps: ['172.29.0.0/16'],
    });
    await setNumberInboundFlowToQueue(publicNumber, queueName);

    await copyFileToContainer(
      CUSTOMER_PCAP_HOST_PATH,
      agentService,
      '/tmp/customer-audio.pcap',
    );

    const registerResult = await registerSipAgentInline({
      username: agentUsername,
      password: agentSipPassword,
      service: agentService,
      port: agentPort,
    });
    expect(registerResult.exitCode).toBe(0);

    try {
      // The agent UAS's exit status is the SIP-edge signal: if the
      // scenario completes (INVITE → 200 → ACK → BYE → 200), the queue
      // successfully routed the call.  No internal queue-state probe.
      const agentUas = runSipp({
        scenario: 'uas-answer-pcap.xml',
        service: agentService,
        extraArgs: ['-p', String(agentPort), '-t', 'u1'],
        timeoutMs: 60_000,
      });

      const uacResult = await runInboundDidCall({
        customerNumber,
        didNumber: publicNumber,
        localPort: A.callerPort,
        hangupAfterMs: 60_000,
      });
      const agentResult = await agentUas;

      expect(uacResult.stderr).not.toContain('Failed');
      expect(agentResult.exitCode).toBe(0);

      const callStory = await waitForInboundCallStoryObserved({
        caller: customerNumber,
        callee: publicNumber,
        timeoutMs: 90_000,
      });

      expect(callStory.direction).toBe('inbound');
      expect(callStory.spans).toBeGreaterThan(0);

      const recording = await assertRecordingProduced(callStory.id, 90_000);
      expect(recording.fileName).toBeTruthy();
      expect(recording.fileSize ?? 0).toBeGreaterThan(0);
    } finally {
      await unregisterSipAgentInline({
        username: agentUsername,
        password: agentSipPassword,
        service: agentService,
        port: agentPort,
      });
    }
  },
);
