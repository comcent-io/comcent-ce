/**
 * SIP phones behind a home router.
 *
 * The phone (sipp-nat-agent) can only reach the SBC through nat-router,
 * which forgets an idle UDP mapping after 10 s (NAT_UDP_TIMEOUT in
 * docker-compose-e2e.yaml). Once the mapping is gone, an INVITE the SBC sends
 * to the address the phone registered from is dropped at the router, so the
 * phone never rings until it registers again. The SBC pings such phones every
 * NAT_PING_INTERVAL (4 s here) to keep the mapping open, and unregisters one
 * that stops answering.
 */

import { expect, test } from '@playwright/test';
import {
  ensureDefaultOutboundRoute,
  ensureMemberInOrg,
  setNumberInboundFlowToDial,
  waitForMemberPresence,
} from '../utils/telephonyDb';
import {
  readLatestSippMessagesLog,
  routeFromService,
  runSipp,
  stopSippProcesses,
} from '../utils/sipp';
import { allocations } from './testAllocations';

const A = allocations.natKeepalive;

const SBC_IP = '172.29.17.9';
const ROUTER_LAN_IP = '10.200.0.2';
const AGENT_SERVICE = 'sipp-nat-agent';
const DOMAIN = 'acme.comcent.io';
// nat-router's NAT_UDP_TIMEOUT, plus margin.
const IDLE_PAST_NAT_TIMEOUT_MS = 15_000;

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

test.describe.configure({ mode: 'serial' });

async function natAgent(username: string, password: string, port: number) {
  await ensureMemberInOrg({
    subdomain: 'acme',
    email: `test.user+${username}@example.com`,
    name: 'NAT Keepalive Agent',
    username,
    sipPassword: password,
    presence: 'Available',
  });

  // Without this the phone could be reaching the SBC some other way, and the
  // tests would pass without proving anything about NAT.
  expect(await routeFromService(AGENT_SERVICE, SBC_IP)).toContain(
    `via ${ROUTER_LAN_IP}`,
  );

  // Registers to the SBC's public port like a real phone and stays up until
  // stopped; the out-of-call scenario answers the SBC's pings and the call.
  const run = runSipp({
    scenario: 'uac-register-hold.xml',
    service: AGENT_SERVICE,
    targetHost: SBC_IP,
    targetPort: 5060,
    csvRows: [`${username};${password};${DOMAIN};${port}`],
    extraArgs: [
      '-p',
      String(port),
      '-t',
      'u1',
      '-au',
      username,
      '-ap',
      password,
      '-auth_uri',
      DOMAIN,
      '-s',
      username,
      '-oocsf',
      '/scenarios/ooc-answer-pings-and-calls.xml',
    ],
    timeoutMs: 170_000,
    allowNonZeroExit: true,
  });

  const stop = async () => {
    await stopSippProcesses([{ service: AGENT_SERVICE, port }]);
    return run;
  };
  return { stop };
}

test(
  'a SIP phone behind NAT still rings after its idle router mapping would have expired',
  { tag: ['@sipp', '@registration', '@nat'] },
  async () => {
    test.setTimeout(180_000);

    const username = 'natkeepaliveagent';
    await ensureDefaultOutboundRoute({
      subdomain: 'acme',
      number: A.did,
      sipTrunkName: 'Telephony SIPp NAT Keepalive',
      outboundContact: 'sipp-uas:' + A.uasPort,
      inboundIps: ['172.29.0.0/16'],
    });
    await setNumberInboundFlowToDial(A.did, username);

    const agent = await natAgent(
      username,
      'NatKeepaliveAgent@1902',
      A.agentAPort,
    );
    try {
      // Let the REGISTER complete, then leave the phone idle past the
      // router's timeout.
      await sleep(3_000 + IDLE_PAST_NAT_TIMEOUT_MS);

      const caller = await runSipp({
        scenario: 'uac-basic.xml',
        targetHost: 'sbc',
        targetPort: 5060,
        csvRows: [`+14155553731;${A.did};3000`],
        extraArgs: ['-p', String(A.callerPort), '-t', 'u1'],
        timeoutMs: 120_000,
        allowNonZeroExit: true,
      });
      expect(caller.exitCode, caller.stdout + caller.stderr).toBe(0);

      // FreeSWITCH answers the caller before dialling, so the caller's 200
      // proves nothing about the phone: its own trace has to show the
      // INVITE that came through the router, and the 200 OK it answered with.
      const phoneLog = await readLatestSippMessagesLog(
        AGENT_SERVICE,
        'uac-register-hold',
      );
      expect(phoneLog, 'the phone behind NAT never got the call').toMatch(
        /^INVITE sip:/m,
      );
      // A 200 OK whose own headers (no blank line in between) say INVITE.
      expect(phoneLog).toMatch(
        /^SIP\/2\.0 200 OK\r?\n(?:[^\r\n]+\r?\n)*?CSeq: \d+ INVITE/m,
      );
    } finally {
      await agent.stop();
    }
  },
);

test(
  'a SIP phone behind NAT that stops answering pings is logged out',
  { tag: ['@sipp', '@registration', '@nat'] },
  async () => {
    test.setTimeout(120_000);

    const username = 'natgoneagent';
    const agent = await natAgent(username, 'NatGoneAgent@1902', A.agentBPort);
    // Registered, and answering pings for a while.
    await sleep(3_000 + IDLE_PAST_NAT_TIMEOUT_MS);
    await waitForMemberPresence({
      subdomain: 'acme',
      username,
      presence: 'Available',
      timeoutMs: 5_000,
    });

    // Switched off without unregistering: three missed pings (4 s apart)
    // unregister it, and the server shows the member Logged Out.
    await agent.stop();
    await waitForMemberPresence({
      subdomain: 'acme',
      username,
      presence: 'Logged Out',
      timeoutMs: 40_000,
    });
  },
);
