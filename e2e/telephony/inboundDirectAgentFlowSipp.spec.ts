import { expect, test } from '@playwright/test';
import {
  assertRecordingProduced,
  ensureDefaultOutboundRoute,
  ensureMemberInOrg,
  setNumberInboundFlowToDial,
  waitForInboundCallStoryObserved,
} from '../utils/telephonyDb';
import {
  copyFileToContainer,
  CUSTOMER_PCAP_HOST_PATH,
  registerSipAgentInline,
  runInboundDidCall,
  runSipp,
  unregisterSipAgentInline,
} from '../utils/sipp';
import { allocations } from './testAllocations';

const A = allocations.inboundDirectAgentSipp;

test.describe.configure({ mode: 'serial' });

test(
  'Inbound DID routes through Dial node to an internal registered agent username via SIPp caller',
  { tag: ['@sipp', '@routing', '@recording'] },
  async () => {
    test.setTimeout(180_000);

    const publicNumber = A.did;
    const customerNumber = '+14155553456';
    const agentUsername = 'directtelephonyagent';
    const agentSipPassword = 'DirectTelephonyAgent@1902';
    const agentEmail = 'test.user+directtelephonyagent@example.com';
    const agentService = 'sipp-agent-a';
    const agentPort = A.agentAPort;

    await ensureMemberInOrg({
      subdomain: 'acme',
      email: agentEmail,
      name: 'Direct Telephony Agent',
      username: agentUsername,
      sipPassword: agentSipPassword,
      presence: 'Available',
    });

    await ensureDefaultOutboundRoute({
      subdomain: 'acme',
      number: publicNumber,
      sipTrunkName: 'Telephony SIPp Direct Agent',
      outboundContact: 'sipp-uas:' + A.uasPort,
      inboundIps: ['172.29.0.0/16'],
    });

    await setNumberInboundFlowToDial(publicNumber, agentUsername);

    // Stage customer audio inside the agent container so the agent UAS
    // can stream real speech toward FreeSwitch once bridged.
    await copyFileToContainer(
      CUSTOMER_PCAP_HOST_PATH,
      agentService,
      '/tmp/customer-audio.pcap',
    );

    // Edge-level registration check: SIPp's uac-register-only.xml exits 0
    // only after the authenticated REGISTER's 200 OK arrives, so awaiting
    // this is the SIP-protocol-level signal that the agent is reachable.
    const registerResult = await registerSipAgentInline({
      username: agentUsername,
      password: agentSipPassword,
      service: agentService,
      port: agentPort,
    });
    expect(registerResult.exitCode).toBe(0);

    try {
      // Agent UAS — answers, plays customer PCAP, waits for the caller
      // to send BYE.
      const agentUas = runSipp({
        scenario: 'uas-answer-pcap.xml',
        service: agentService,
        extraArgs: ['-p', String(agentPort), '-t', 'u1'],
        timeoutMs: 60_000,
      });

      // Caller hardcoded to a 15 s talk window then sends BYE.  Caller
      // waits for the BYE 200 OK before exiting.
      const uacResult = await runInboundDidCall({
        customerNumber,
        didNumber: publicNumber,
        localPort: A.callerPort,
      });
      const agentResult = await agentUas;

      expect(uacResult.stderr).not.toContain('Failed');
      // uas-answer-pcap.xml only exits 0 if it observed the full
      // INVITE → 200 → ACK → BYE → 200 exchange, which proves the
      // agent received the dial-routed INVITE.
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
