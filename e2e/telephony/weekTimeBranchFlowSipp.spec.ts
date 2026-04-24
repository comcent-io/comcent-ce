import { expect, test } from '@playwright/test';
import {
  ensureDefaultOutboundRoute,
  setNumberInboundFlowToWeekTimeDial,
  waitForInboundCallStory,
} from '../utils/telephonyDb';
import { runInboundDidToExternalFlow } from '../utils/sipp';
import { allocations } from './testAllocations';

function currentUtcDay():
  | 'mon'
  | 'tue'
  | 'wed'
  | 'thu'
  | 'fri'
  | 'sat'
  | 'sun' {
  const days: Array<'sun' | 'mon' | 'tue' | 'wed' | 'thu' | 'fri' | 'sat'> = [
    'sun',
    'mon',
    'tue',
    'wed',
    'thu',
    'fri',
    'sat',
  ];

  return days[new Date().getUTCDay()] as
    | 'mon'
    | 'tue'
    | 'wed'
    | 'thu'
    | 'fri'
    | 'sat'
    | 'sun';
}

function inactiveUtcDay():
  | 'mon'
  | 'tue'
  | 'wed'
  | 'thu'
  | 'fri'
  | 'sat'
  | 'sun' {
  const days: Array<'mon' | 'tue' | 'wed' | 'thu' | 'fri' | 'sat' | 'sun'> = [
    'mon',
    'tue',
    'wed',
    'thu',
    'fri',
    'sat',
    'sun',
  ];

  const current = currentUtcDay();
  return days.find((day) => day !== current) ?? 'mon';
}

test(
  'WeekTime node uses the active branch when the current day matches',
  { tag: ['@sipp', '@flow', '@weektime'] },
  async () => {
    test.setTimeout(180_000);

    const A = allocations.weekTimeActive;
    const publicNumber = A.did;
    const customerNumber = '+14155557654';

    await ensureDefaultOutboundRoute({
      subdomain: 'acme',
      number: publicNumber,
      sipTrunkName: 'Telephony SIPp WeekTime Active',
      outboundContact: 'sipp-uas:' + A.uasPort,
      inboundIps: ['172.29.0.0/16'],
    });

    await setNumberInboundFlowToWeekTimeDial({
      number: publicNumber,
      timezone: 'UTC',
      day: currentUtcDay(),
      trueTarget: '+14155550123',
      falseTarget: 'telephony-weektime-false-branch-should-not-run',
    });

    const { uacResult, uasResult } = await runInboundDidToExternalFlow({
      customerNumber,
      didNumber: publicNumber,
      externalTarget: '+14155550123',
      withAudio: true,
      callerPort: A.callerPort,
      externalPort: A.uasPort,
    });

    expect(uacResult.stderr).not.toContain('Failed');
    expect(uasResult.stderr).not.toContain('Failed');

    const callStory = await waitForInboundCallStory({
      caller: customerNumber,
      callee: publicNumber,
      timeoutMs: 90_000,
    });

    expect(callStory.direction).toBe('inbound');
    expect(callStory.spans).toBeGreaterThan(0);
  },
);

test(
  'WeekTime node uses the fallback branch when the configured day is inactive',
  { tag: ['@sipp', '@flow', '@weektime'] },
  async () => {
    test.setTimeout(180_000);

    const B = allocations.weekTimeFallback;
    const publicNumber = B.did;
    const customerNumber = '+14155557655';

    await ensureDefaultOutboundRoute({
      subdomain: 'acme',
      number: publicNumber,
      sipTrunkName: 'Telephony SIPp WeekTime Fallback',
      outboundContact: 'sipp-uas:' + B.uasPort,
      inboundIps: ['172.29.0.0/16'],
    });

    await setNumberInboundFlowToWeekTimeDial({
      number: publicNumber,
      timezone: 'UTC',
      day: inactiveUtcDay(),
      trueTarget: 'telephony-weektime-true-branch-should-not-run',
      falseTarget: '+14155550123',
    });

    const { uacResult, uasResult } = await runInboundDidToExternalFlow({
      customerNumber,
      didNumber: publicNumber,
      externalTarget: '+14155550123',
      withAudio: true,
      callerPort: B.callerPort,
      externalPort: B.uasPort,
    });

    expect(uacResult.stderr).not.toContain('Failed');
    expect(uasResult.stderr).not.toContain('Failed');

    const callStory = await waitForInboundCallStory({
      caller: customerNumber,
      callee: publicNumber,
      timeoutMs: 90_000,
    });

    expect(callStory.direction).toBe('inbound');
    expect(callStory.spans).toBeGreaterThan(0);
  },
);
