/**
 * SIP registration flow tests.
 *
 * Exercises the platform's SIP REGISTER edge directly via SIPp:
 *   • valid credentials → 401 challenge → authenticated REGISTER → 200 OK
 *   • wrong password → 401 challenge → authenticated REGISTER → 401 (re-challenge, not 200)
 *   • register then unregister (Expires: 0) → 200 OK
 *
 * These run independently of the call-handling pipeline and don't depend
 * on any specific SIP proxy implementation — they assert on the SIP
 * responses the system exposes to registering user-agents.
 */

import { expect, test } from '@playwright/test';
import { ensureMemberInOrg } from '../utils/telephonyDb';
import { runSipp } from '../utils/sipp';
import { allocations } from './testAllocations';

const A = allocations.sipRegistration;

test.describe.configure({ mode: 'serial' });

// ---------------------------------------------------------------------------
// Test 1 — valid credentials: REGISTER → 401 → REGISTER+auth → 200 OK
// ---------------------------------------------------------------------------

test(
  'SIP agent can register with valid credentials',
  { tag: ['@sipp', '@registration'] },
  async () => {
    test.setTimeout(60_000);

    const username = 'kamreg-validuser';
    const sipPassword = 'KamRegValid@1902';

    await ensureMemberInOrg({
      subdomain: 'acme',
      email: `test.user+${username}@example.com`,
      name: 'Kamailio Reg Valid User',
      username,
      sipPassword,
      presence: 'Available',
    });

    const result = await runSipp({
      scenario: 'uac-register-only.xml',
      targetHost: 'sbc',
      targetPort: 5065,
      service: 'sipp',
      csvRows: [`${username};${sipPassword};acme.comcent.io;${A.callerPort}`],
      extraArgs: [
        '-p',
        String(A.callerPort),
        '-t',
        'u1',
        '-au',
        username,
        '-ap',
        sipPassword,
        '-auth_uri',
        'acme.comcent.io',
        '-s',
        username,
      ],
      timeoutMs: 30_000,
    });

    expect(result.exitCode).toBe(0);
    expect(result.stderr).not.toContain('Failed');
  },
);

// ---------------------------------------------------------------------------
// Test 2 — wrong password: REGISTER → 401 → REGISTER+wrong_digest → 403
// ---------------------------------------------------------------------------

test(
  'SIP agent registration is rejected with wrong password',
  { tag: ['@sipp', '@registration', '@security'] },
  async () => {
    test.setTimeout(60_000);

    const username = 'kamreg-badpwuser';
    const correctPassword = 'KamRegCorrect@1902';
    const wrongPassword = 'THIS_IS_WRONG';

    await ensureMemberInOrg({
      subdomain: 'acme',
      email: `test.user+${username}@example.com`,
      name: 'Kamailio Reg Bad PW User',
      username,
      sipPassword: correctPassword,
      presence: 'Available',
    });

    // Pass the wrong password via -ap so SIPp computes an invalid digest.
    const result = await runSipp({
      scenario: 'uac-register-fail-auth.xml',
      targetHost: 'sbc',
      targetPort: 5065,
      service: 'sipp',
      csvRows: [
        `${username};${wrongPassword};acme.comcent.io;${A.callerPort + 1}`,
      ],
      extraArgs: [
        '-p',
        String(A.callerPort + 1),
        '-t',
        'u1',
        '-au',
        username,
        '-ap',
        wrongPassword,
        '-auth_uri',
        'acme.comcent.io',
        '-s',
        username,
      ],
      timeoutMs: 30_000,
      // SIPp exits non-zero when the scenario ends with an unexpected response.
      // We allow a non-zero exit so we can inspect the output rather than throwing.
      allowNonZeroExit: true,
    });

    // The scenario expects another 401 on the second REGISTER (the proxy
    // re-challenges rather than admitting the call).  SIPp exits 0 only
    // when the expected response sequence completes — a non-zero exit
    // here means the proxy sent a 200 OK (i.e. accepted the wrong
    // password), which would be the regression we care about.
    expect(result.exitCode).toBe(0);
    expect(result.stderr).not.toContain('Failed');
  },
);

// ---------------------------------------------------------------------------
// Test 3 — unregistration: REGISTER → 200 OK, then REGISTER Expires:0 → 200 OK
// ---------------------------------------------------------------------------

test(
  'SIP agent can unregister cleanly',
  { tag: ['@sipp', '@registration'] },
  async () => {
    test.setTimeout(60_000);

    const username = 'kamreg-unreguser';
    const sipPassword = 'KamRegUnreg@1902';

    await ensureMemberInOrg({
      subdomain: 'acme',
      email: `test.user+${username}@example.com`,
      name: 'Kamailio Reg Unreg User',
      username,
      sipPassword,
      presence: 'Available',
    });

    // Step 1: register
    const registerResult = await runSipp({
      scenario: 'uac-register-only.xml',
      targetHost: 'sbc',
      targetPort: 5065,
      service: 'sipp',
      csvRows: [
        `${username};${sipPassword};acme.comcent.io;${A.callerPort + 2}`,
      ],
      extraArgs: [
        '-p',
        String(A.callerPort + 2),
        '-t',
        'u1',
        '-au',
        username,
        '-ap',
        sipPassword,
        '-auth_uri',
        'acme.comcent.io',
        '-s',
        username,
      ],
      timeoutMs: 30_000,
    });

    expect(registerResult.exitCode).toBe(0);
    expect(registerResult.stderr).not.toContain('Failed');

    // Step 2: unregister (Expires: 0)
    const unregisterResult = await runSipp({
      scenario: 'uac-unregister-only.xml',
      targetHost: 'sbc',
      targetPort: 5065,
      service: 'sipp',
      csvRows: [
        `${username};${sipPassword};acme.comcent.io;${A.callerPort + 2}`,
      ],
      extraArgs: [
        '-p',
        String(A.callerPort + 2),
        '-t',
        'u1',
        '-au',
        username,
        '-ap',
        sipPassword,
        '-auth_uri',
        'acme.comcent.io',
        '-s',
        username,
      ],
      timeoutMs: 30_000,
    });

    expect(unregisterResult.exitCode).toBe(0);
    expect(unregisterResult.stderr).not.toContain('Failed');
  },
);
