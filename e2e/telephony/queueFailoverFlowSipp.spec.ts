import { expect, test } from '@playwright/test';
import {
  assertRecordingProduced,
  ensureDefaultOutboundRoute,
  ensureMemberInOrg,
  getCallSpans,
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

const A = allocations.queueFailover;

test.describe.configure({ mode: 'serial' });

test(
  'Inbound queue call fails over to another available agent after first rejection via SIPp caller',
  { tag: ['@sipp', '@queue', '@failover'] },
  async ({ page }) => {
    test.setTimeout(180_000);

    const publicNumber = A.did;
    const customerNumber = '+14155554321';
    const queueName = 'telephonyfailover';
    const queueExtension = '8102';
    const firstAgent = {
      username: 'telephonyrejectagent',
      email: 'test.user+telephonyrejectagent@example.com',
      password: 'TelephonyRejectAgent@1902',
      service: 'sipp-agent-a',
      port: A.agentAPort,
    };
    const secondAgent = {
      username: 'telephonyacceptagent',
      email: 'test.user+telephonyacceptagent@example.com',
      password: 'TelephonyAcceptAgent@1902',
      service: 'sipp-agent-b',
      port: A.agentBPort,
    };

    const firstMember = await ensureMemberInOrg({
      subdomain: 'acme',
      email: firstAgent.email,
      name: 'Telephony Reject Agent',
      username: firstAgent.username,
      sipPassword: firstAgent.password,
      presence: 'Available',
    });
    const secondMember = await ensureMemberInOrg({
      subdomain: 'acme',
      email: secondAgent.email,
      name: 'Telephony Accept Agent',
      username: secondAgent.username,
      sipPassword: secondAgent.password,
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
      userId: firstMember.userId,
    });
    await addQueueMemberViaApi({
      page,
      subdomain: 'acme',
      queueId,
      userId: secondMember.userId,
    });
    await ensureDefaultOutboundRoute({
      subdomain: 'acme',
      number: publicNumber,
      sipTrunkName: 'Telephony SIPp Queue Failover',
      outboundContact: 'sipp-uas:' + A.uasPort,
      inboundIps: ['172.29.0.0/16'],
    });
    await setNumberInboundFlowToQueue(publicNumber, queueName);

    await copyFileToContainer(
      CUSTOMER_PCAP_HOST_PATH,
      secondAgent.service,
      '/tmp/customer-audio.pcap',
    );

    const firstRegister = await registerSipAgentInline({
      username: firstAgent.username,
      password: firstAgent.password,
      service: firstAgent.service,
      port: firstAgent.port,
    });
    expect(firstRegister.exitCode).toBe(0);

    const secondRegister = await registerSipAgentInline({
      username: secondAgent.username,
      password: secondAgent.password,
      service: secondAgent.service,
      port: secondAgent.port,
    });
    expect(secondRegister.exitCode).toBe(0);

    try {
      // First agent always rejects with 486 Busy.
      const rejectingUas = runSipp({
        scenario: 'uas-reject.xml',
        service: firstAgent.service,
        extraArgs: ['-p', String(firstAgent.port), '-t', 'u1'],
        timeoutMs: 90_000,
        allowNonZeroExit: true,
      });

      // Second agent answers, plays customer PCAP, waits for caller BYE.
      const acceptingUas = runSipp({
        scenario: 'uas-answer-pcap.xml',
        service: secondAgent.service,
        extraArgs: ['-p', String(secondAgent.port), '-t', 'u1'],
        timeoutMs: 120_000,
      });

      const uacResult = await runInboundDidCall({
        customerNumber,
        didNumber: publicNumber,
        localPort: A.callerPort,
        hangupAfterMs: 60_000,
      });
      const [rejectResult, acceptResult] = await Promise.all([
        rejectingUas,
        acceptingUas,
      ]);

      expect(uacResult.stderr).not.toContain('Failed');
      // Both agents must have received their INVITEs — first rejected
      // (486/ACK exchange), second answered and bridged to BYE.
      expect(rejectResult.exitCode).toBe(0);
      expect(acceptResult.exitCode).toBe(0);

      const callStory = await waitForInboundCallStoryObserved({
        caller: customerNumber,
        callee: publicNumber,
        timeoutMs: 150_000,
      });

      expect(callStory.direction).toBe('inbound');
      expect(callStory.spans).toBeGreaterThan(0);

      const recording = await assertRecordingProduced(callStory.id, 90_000);
      expect(recording.fileName).toBeTruthy();
      expect(recording.fileSize ?? 0).toBeGreaterThan(0);

      // Failover-specific span assertions: the first agent was rung and
      // rejected (RINGING span, no ON_CALL), the second agent was rung
      // and bridged (both RINGING and ON_CALL spans).
      const spans = await getCallSpans(callStory.id);
      const firstAgentAor = `${firstAgent.username}@acme.comcent.io`;
      const secondAgentAor = `${secondAgent.username}@acme.comcent.io`;

      const firstRinging = spans.filter(
        (row) => row.type === 'RINGING' && row.current_party === firstAgentAor,
      );
      const firstOnCall = spans.filter(
        (row) => row.type === 'ON_CALL' && row.current_party === firstAgentAor,
      );
      expect(firstRinging.length).toBeGreaterThan(0);
      expect(firstOnCall.length).toBe(0);

      const secondRinging = spans.filter(
        (row) => row.type === 'RINGING' && row.current_party === secondAgentAor,
      );
      const secondOnCall = spans.filter(
        (row) => row.type === 'ON_CALL' && row.current_party === secondAgentAor,
      );
      expect(secondRinging.length).toBeGreaterThan(0);
      expect(secondOnCall.length).toBeGreaterThan(0);
    } finally {
      await unregisterSipAgentInline({
        username: firstAgent.username,
        password: firstAgent.password,
        service: firstAgent.service,
        port: firstAgent.port,
      });
      await unregisterSipAgentInline({
        username: secondAgent.username,
        password: secondAgent.password,
        service: secondAgent.service,
        port: secondAgent.port,
      });
    }
  },
);
