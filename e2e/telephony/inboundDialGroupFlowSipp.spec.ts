import { expect, test } from '@playwright/test';
import {
  assertRecordingProduced,
  ensureDefaultOutboundRoute,
  ensureMemberInOrg,
  getCallSpans,
  setNumberInboundFlowToDialGroup,
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

const A = allocations.inboundDialGroupParallel;
const B = allocations.inboundDialGroupTimeout;
const C = allocations.inboundDialGroupCancel;

// ─────────────────────────────────────────────────────────────────────────────
// Test 1 — DialGroup rings four parallel targets, first answerer wins
// ─────────────────────────────────────────────────────────────────────────────
// Verifies at SIP-protocol edges:
//   • Agent's REGISTER succeeds (200 OK observed)
//   • Agent's UAS receives the DialGroup's INVITE (scenario completes
//     the INVITE → 486 → ACK flow and exits 0)
//   • External phone's UAS receives and bridges its INVITE
//   • Customer call produces a completed recording
// ─────────────────────────────────────────────────────────────────────────────

test(
  'Inbound DID DialGroup rings four targets in parallel and bridges the first to answer',
  { tag: ['@sipp', '@routing', '@recording'] },
  async () => {
    test.setTimeout(240_000);

    const publicNumber = A.did;
    const customerNumber = '+14155557656';
    const externalTarget = '+14155550123';
    const agent = {
      email: 'test.user+dialgroupagent@example.com',
      name: 'Dial Group Agent',
      username: 'dialgroupagent',
      sipPassword: 'DialGroupAgent@1902',
    };
    const agentService = 'sipp-agent-a';
    const agentPort = A.agentAPort;

    await ensureMemberInOrg({
      subdomain: 'acme',
      email: agent.email,
      name: agent.name,
      username: agent.username,
      sipPassword: agent.sipPassword,
      presence: 'Available',
    });

    await ensureDefaultOutboundRoute({
      subdomain: 'acme',
      number: publicNumber,
      sipTrunkName: 'Telephony SIPp Dial Group',
      outboundContact: 'sipp-uas:' + A.uasPort,
      inboundIps: ['172.29.0.0/16'],
    });

    await setNumberInboundFlowToDialGroup(publicNumber, [
      'dialgroup-missing-a', // unknown username → 404
      externalTarget, // external phone → sipp-uas answers with PCAP
      agent.username, // registered agent → will lose the race but be invited
      'dialgroup-missing-b', // unknown username → 404
    ]);

    await copyFileToContainer(
      CUSTOMER_PCAP_HOST_PATH,
      'sipp-uas',
      '/tmp/customer-audio.pcap',
    );

    // ── Edge-level registration: await the REGISTER → 200 OK exchange ──
    const registerResult = await registerSipAgentInline({
      username: agent.username,
      password: agent.sipPassword,
      service: agentService,
      port: agentPort,
    });
    expect(registerResult.exitCode).toBe(0);

    try {
      // External phone UAS — answers and plays customer PCAP.
      const externalUas = runSipp({
        scenario: 'uas-answer-pcap.xml',
        service: 'sipp-uas',
        extraArgs: ['-p', String(A.uasPort), '-t', 'u1'],
        timeoutMs: 120_000,
      });

      // Agent UAS — rejects the dial-group INVITE with 486.  Scenario
      // only exits 0 if it observes the full INVITE → 486 → ACK
      // exchange, which proves the agent did receive the INVITE.
      const agentUas = runSipp({
        scenario: 'uas-reject.xml',
        service: agentService,
        extraArgs: ['-p', String(agentPort), '-t', 'u1'],
        timeoutMs: 60_000,
        allowNonZeroExit: true,
      });

      const uacResult = await runInboundDidCall({
        customerNumber,
        didNumber: publicNumber,
        localPort: A.callerPort,
      });
      const externalResult = await externalUas;
      const agentResult = await agentUas;

      expect(uacResult.stderr).not.toContain('Failed');
      expect(externalResult.stderr).not.toContain('Failed');

      // Agent must have received the INVITE (uas-reject exits 0 only if
      // the full INVITE / 486 / ACK handshake ran).
      expect(agentResult.exitCode).toBe(0);

      const callStory = await waitForInboundCallStoryObserved({
        caller: customerNumber,
        callee: publicNumber,
        timeoutMs: 90_000,
      });

      expect(callStory.direction).toBe('inbound');
      expect(callStory.caller).toBe(customerNumber);
      expect(callStory.callee).toBe(publicNumber);

      const recording = await assertRecordingProduced(callStory.id, 90_000);
      expect(recording.fileName).toBeTruthy();
      expect(recording.fileSize ?? 0).toBeGreaterThan(0);
    } finally {
      await unregisterSipAgentInline({
        username: agent.username,
        password: agent.sipPassword,
        service: agentService,
        port: agentPort,
      });
    }
  },
);

// ─────────────────────────────────────────────────────────────────────────────
// Test 2 — DialGroup times out and the `timeout` outlet fires
// ─────────────────────────────────────────────────────────────────────────────
// A ringing-forever agent is in the DialGroup so the call gets stuck in
// ring state long enough for the 5 s timeout to elapse.  The outlet
// points to a Dial node targeting the external trunk; we verify the
// outlet fired by observing that the fallback's UAS actually received
// an INVITE (its scenario exits 0 after a successful answer/bridge).
// ─────────────────────────────────────────────────────────────────────────────

test(
  'DialGroup timeout routes the call to the configured fallback Dial node',
  { tag: ['@sipp', '@routing', '@timeout'] },
  async () => {
    test.setTimeout(240_000);

    const publicNumber = B.did;
    const customerNumber = '+14155557657';
    const fallbackTarget = '+14155550123';
    const ringingAgent = {
      email: 'test.user+dialgroupringing@example.com',
      name: 'Dial Group Ringing Agent',
      username: 'dialgroupringing',
      sipPassword: 'DialGroupRinging@1902',
    };
    const agentService = 'sipp-agent-a';
    const agentPort = B.agentAPort;

    await ensureMemberInOrg({
      subdomain: 'acme',
      email: ringingAgent.email,
      name: ringingAgent.name,
      username: ringingAgent.username,
      sipPassword: ringingAgent.sipPassword,
      presence: 'Available',
    });

    await ensureDefaultOutboundRoute({
      subdomain: 'acme',
      number: publicNumber,
      sipTrunkName: 'Telephony SIPp Dial Group Timeout',
      outboundContact: 'sipp-uas:' + B.uasPort,
      inboundIps: ['172.29.0.0/16'],
    });

    // DialGroup rings a single agent forever; on timeout (5 s) the flow
    // falls through the `timeout` outlet to a Dial node that calls the
    // external trunk → sipp-uas.
    await setNumberInboundFlowToDialGroup(
      publicNumber,
      [ringingAgent.username],
      {
        timeout: 5,
        timeoutFallbackTarget: fallbackTarget,
      },
    );

    await copyFileToContainer(
      CUSTOMER_PCAP_HOST_PATH,
      'sipp-uas',
      '/tmp/customer-audio.pcap',
    );

    const registerResult = await registerSipAgentInline({
      username: ringingAgent.username,
      password: ringingAgent.sipPassword,
      service: agentService,
      port: agentPort,
    });
    expect(registerResult.exitCode).toBe(0);

    try {
      // Fallback UAS — answers (proves the timeout outlet fired).
      const fallbackUas = runSipp({
        scenario: 'uas-answer-pcap.xml',
        service: 'sipp-uas',
        extraArgs: ['-p', String(B.uasPort), '-t', 'u1'],
        timeoutMs: 120_000,
      });

      // Primary UAS — rings forever until the DialGroup cancels it.
      const ringingUas = runSipp({
        scenario: 'uas-ring-forever.xml',
        service: agentService,
        extraArgs: ['-p', String(agentPort), '-t', 'u1'],
        timeoutMs: 60_000,
        allowNonZeroExit: true,
      });

      const uacResult = await runInboundDidCall({
        customerNumber,
        didNumber: publicNumber,
        localPort: B.callerPort,
      });
      const fallbackResult = await fallbackUas;
      const ringingResult = await ringingUas;

      expect(uacResult.stderr).not.toContain('Failed');

      // The fallback UAS exits 0 only if it received the INVITE from
      // the fallback Dial block — that proves the `timeout` outlet
      // fired and the flow advanced.
      expect(fallbackResult.exitCode).toBe(0);

      // The ringing agent must have received its INVITE (proving the
      // DialGroup actually rang it before timing out).
      expect(ringingResult.exitCode).toBe(0);

      const callStory = await waitForInboundCallStoryObserved({
        caller: customerNumber,
        callee: publicNumber,
        timeoutMs: 90_000,
      });

      expect(callStory.direction).toBe('inbound');

      // Fallback bridged successfully → completed recording.
      const recording = await assertRecordingProduced(callStory.id, 90_000);
      expect(recording.fileName).toBeTruthy();
      expect(recording.fileSize ?? 0).toBeGreaterThan(0);

      // Sanity check: the ringing agent was NOT the bridged party.
      const spans = await getCallSpans(callStory.id);
      const agentBridged = spans.some(
        (row) =>
          row.type === 'ON_CALL' &&
          row.current_party === `${ringingAgent.username}@acme.comcent.io` &&
          row.end_at !== null &&
          new Date(row.end_at).getTime() !== new Date(row.start_at).getTime(),
      );
      expect(agentBridged).toBe(false);
    } finally {
      await unregisterSipAgentInline({
        username: ringingAgent.username,
        password: ringingAgent.sipPassword,
        service: agentService,
        port: agentPort,
      });
    }
  },
);

// ─────────────────────────────────────────────────────────────────────────────
// Test 3 — DialGroup CANCELs the losing legs once one target answers
// ─────────────────────────────────────────────────────────────────────────────
// Four parallel targets:
//   • two unknown usernames (Kamailio 404s them immediately)
//   • a registered agent that rings forever and never answers
//   • an external phone that answers
// The external phone wins.  We then verify that FreeSwitch sent a CANCEL
// to the ringing agent — `uas-ring-forever.xml` only exits 0 when it has
// observed the full ring → CANCEL → 487 → ACK exchange.  The agent's
// successful exit is the SIP-edge proof that FreeSwitch detected the
// external leg's answer and explicitly tore down the still-ringing leg.
// ─────────────────────────────────────────────────────────────────────────────

test(
  'DialGroup cancels losing legs after another target answers',
  { tag: ['@sipp', '@routing', '@cancel'] },
  async () => {
    test.setTimeout(240_000);

    const publicNumber = C.did;
    const customerNumber = '+14155557658';
    const externalTarget = '+14155550123';
    const ringingAgent = {
      email: 'test.user+dialgroupcancelringing@example.com',
      name: 'Dial Group Cancel Ringing Agent',
      username: 'dialgroupcancelringing',
      sipPassword: 'DialGroupCancelRinging@1902',
    };
    const agentService = 'sipp-agent-a';
    const agentPort = C.agentAPort;

    await ensureMemberInOrg({
      subdomain: 'acme',
      email: ringingAgent.email,
      name: ringingAgent.name,
      username: ringingAgent.username,
      sipPassword: ringingAgent.sipPassword,
      presence: 'Available',
    });

    await ensureDefaultOutboundRoute({
      subdomain: 'acme',
      number: publicNumber,
      sipTrunkName: 'Telephony SIPp Dial Group Cancel',
      outboundContact: 'sipp-uas:' + C.uasPort,
      inboundIps: ['172.29.0.0/16'],
    });

    await setNumberInboundFlowToDialGroup(publicNumber, [
      'dialgroup-missing-x', // 404
      'dialgroup-missing-y', // 404
      ringingAgent.username, // rings forever — must receive CANCEL
      externalTarget, // external phone — answers and wins
    ]);

    await copyFileToContainer(
      CUSTOMER_PCAP_HOST_PATH,
      'sipp-uas',
      '/tmp/customer-audio.pcap',
    );

    const registerResult = await registerSipAgentInline({
      username: ringingAgent.username,
      password: ringingAgent.sipPassword,
      service: agentService,
      port: agentPort,
    });
    expect(registerResult.exitCode).toBe(0);

    try {
      // External phone — answers and bridges.
      const externalUas = runSipp({
        scenario: 'uas-answer-pcap.xml',
        service: 'sipp-uas',
        extraArgs: ['-p', String(C.uasPort), '-t', 'u1'],
        timeoutMs: 120_000,
      });

      // Ringing agent — must observe the full INVITE → 180 → CANCEL →
      // 487 → ACK exchange to exit 0.  That sequence proves FreeSwitch
      // detected the external leg's 200 OK and explicitly cancelled
      // this leg.
      const ringingUas = runSipp({
        scenario: 'uas-ring-forever.xml',
        service: agentService,
        extraArgs: ['-p', String(agentPort), '-t', 'u1'],
        timeoutMs: 60_000,
        allowNonZeroExit: true,
      });

      const uacResult = await runInboundDidCall({
        customerNumber,
        didNumber: publicNumber,
        localPort: C.callerPort,
      });
      const externalResult = await externalUas;
      const ringingResult = await ringingUas;

      expect(uacResult.stderr).not.toContain('Failed');
      expect(externalResult.stderr).not.toContain('Failed');

      // Ringing agent must have completed its ring → CANCEL → 487 → ACK
      // flow.  Anything other than exit 0 means CANCEL never arrived,
      // i.e. FreeSwitch failed to tear down the losing leg.
      expect(ringingResult.exitCode).toBe(0);

      const callStory = await waitForInboundCallStoryObserved({
        caller: customerNumber,
        callee: publicNumber,
        timeoutMs: 90_000,
      });

      expect(callStory.direction).toBe('inbound');
      expect(callStory.caller).toBe(customerNumber);
      expect(callStory.callee).toBe(publicNumber);

      // External leg bridged → recording produced.
      const recording = await assertRecordingProduced(callStory.id, 90_000);
      expect(recording.fileName).toBeTruthy();
      expect(recording.fileSize ?? 0).toBeGreaterThan(0);

      // Sanity check: the ringing agent was never the bridged party.
      const spans = await getCallSpans(callStory.id);
      const agentBridged = spans.some(
        (row) =>
          row.type === 'ON_CALL' &&
          row.current_party === `${ringingAgent.username}@acme.comcent.io` &&
          row.end_at !== null &&
          new Date(row.end_at).getTime() !== new Date(row.start_at).getTime(),
      );
      expect(agentBridged).toBe(false);
    } finally {
      await unregisterSipAgentInline({
        username: ringingAgent.username,
        password: ringingAgent.sipPassword,
        service: agentService,
        port: agentPort,
      });
    }
  },
);
