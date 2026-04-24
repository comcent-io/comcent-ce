import { expect, test, type Page } from '@playwright/test';
import {
  ensureDefaultOutboundRoute,
  ensureMemberInOrg,
  getCallStoryEvents,
  setNumberInboundFlowToQueue,
  waitForCallStory,
  waitForCallSpans,
  waitForFreeSwitchReady,
} from '../utils/telephonyDb';
import { addQueueMemberViaApi, createQueueViaApi } from '../utils/telephonyApi';
import {
  registerSipAgentInline,
  runInboundDidCall,
  runSipp,
  stopSippProcesses,
  unregisterSipAgentInline,
} from '../utils/sipp';
import { allocations } from './testAllocations';

const Q1 = allocations.queueStressQ1;
const Q2 = allocations.queueStressQ2;
const visualQueueStress = process.env.VISUAL_QUEUE_STRESS === '1';

test.describe.configure({ mode: 'serial' });

type AgentSpec = {
  username: string;
  email: string;
  sipPassword: string;
  service: 'sipp-agent-a' | 'sipp-agent-b';
  port: number;
  behavior?: 'answer' | 'reject' | 'ring_forever';
  maxCalls?: number;
};

async function registerAgents(agents: AgentSpec[]) {
  for (const agent of agents) {
    let lastError: unknown = null;

    for (let attempt = 1; attempt <= 3; attempt += 1) {
      try {
        const result = await registerSipAgentInline({
          username: agent.username,
          password: agent.sipPassword,
          service: agent.service,
          port: agent.port,
          timeoutMs: 45_000,
        });
        expect(result.exitCode).toBe(0);
        lastError = null;
        break;
      } catch (error) {
        lastError = error;

        if (attempt < 3) {
          await new Promise((resolve) => setTimeout(resolve, 750));
          continue;
        }
      }
    }

    if (lastError) {
      throw lastError;
    }
  }
}

async function unregisterAgents(agents: AgentSpec[]) {
  await Promise.allSettled(
    agents.map((agent) =>
      unregisterSipAgentInline({
        username: agent.username,
        password: agent.sipPassword,
        service: agent.service,
        port: agent.port,
        timeoutMs: 8_000,
      }),
    ),
  );
}

function runAgentScenario(agent: AgentSpec) {
  const scenario =
    agent.behavior === 'reject'
      ? 'uas-reject.xml'
      : agent.behavior === 'ring_forever'
        ? 'uas-ring-forever.xml'
        : visualQueueStress
          ? 'uas-answer-slow.xml'
          : 'uas-answer-remote-bye.xml';

  const timeoutMs =
    agent.behavior === 'answer'
      ? Math.max(240_000, (agent.maxCalls ?? 1) * 60_000)
      : 120_000;

  return runSipp({
    scenario,
    service: agent.service,
    extraArgs: [
      '-p',
      String(agent.port),
      '-t',
      'u1',
      '-m',
      String(agent.maxCalls ?? 1),
    ],
    timeoutMs,
    allowNonZeroExit: true,
    resetProcesses: false,
  });
}

function agentAor(agent: AgentSpec) {
  return `${agent.username}@acme.comcent.io`;
}

function createAgentFactory(suffix: string, portOffset = 0) {
  const nextPortByService: Record<'sipp-agent-a' | 'sipp-agent-b', number> = {
    'sipp-agent-a': Q1.agentAPort + portOffset,
    'sipp-agent-b': Q2.agentBPort + portOffset,
  };

  return (
    role: string,
    index: number,
    service: 'sipp-agent-a' | 'sipp-agent-b',
    behavior: AgentSpec['behavior'] = 'answer',
  ): AgentSpec => {
    const username = `${role}${String(index + 1).padStart(2, '0')}${suffix}`;
    const title = role.replace(
      /(^|_)([a-z])/g,
      (_, prefix: string, letter: string) => `${prefix}${letter.toUpperCase()}`,
    );

    const port = nextPortByService[service];
    nextPortByService[service] += 1;

    return {
      username,
      email: `test.user+${username}@example.com`,
      sipPassword: `${title}${suffix}@1902`,
      service,
      port,
      behavior,
      maxCalls: behavior === 'answer' ? 999 : behavior === 'reject' ? 6 : 1,
    };
  };
}

function buildBurstCallers(
  did: string,
  startPort: number,
  prefix: string,
  count: number,
) {
  return Array.from({ length: count }, (_, index) => ({
    caller: `+14155558${prefix}${String(index + 1).padStart(2, '0')}`,
    did,
    port: startPort + index,
  }));
}

async function runCallersInWaves(
  page: Page,
  callers: Array<{ caller: string; did: string; port: number }>,
  waveSize: number,
  waveDelayMs: number,
  hangupAfterMs = 30_000,
) {
  const runs: Array<ReturnType<typeof runInboundDidCall>> = [];

  for (let index = 0; index < callers.length; index += waveSize) {
    const wave = callers.slice(index, index + waveSize);
    runs.push(
      ...wave.map((caller, waveIndex) =>
        runInboundDidCall({
          customerNumber: caller.caller,
          didNumber: caller.did,
          scenario: 'uac-basic.xml',
          callerService: (index + waveIndex) % 2 === 0 ? 'sipp' : 'sipp-uas',
          localPort: caller.port,
          hangupAfterMs,
          resetProcesses: false,
        }),
      ),
    );

    if (index + waveSize < callers.length) {
      await page.waitForTimeout(waveDelayMs);
    }
  }

  return Promise.all(runs);
}

test(
  'Queue stress: four concurrent callers across two queues are answered using dedicated and shared SIP agents',
  { tag: ['@sipp', '@queue', '@stress'] },
  async ({ page }) => {
    test.setTimeout(360_000);

    const suffix = Date.now().toString(36).slice(-6);
    const q1Name = `stress_burst_q1_${suffix}`;
    const q2Name = `stress_burst_q2_${suffix}`;

    const q1Agents: AgentSpec[] = [
      {
        username: `stressq1a${suffix}`,
        email: `test.user+stressq1a${suffix}@example.com`,
        sipPassword: 'StressQ1A@1902',
        service: 'sipp-agent-a',
        port: Q1.agentAPort,
      },
    ];

    const q2Agents: AgentSpec[] = [
      {
        username: `stressq2a${suffix}`,
        email: `test.user+stressq2a${suffix}@example.com`,
        sipPassword: 'StressQ2A@1902',
        service: 'sipp-agent-b',
        port: Q2.agentAPort,
      },
    ];

    const sharedAgents: AgentSpec[] = [
      {
        username: `stressshareda${suffix}`,
        email: `test.user+stressshareda${suffix}@example.com`,
        sipPassword: 'StressSharedA@1902',
        service: 'sipp-agent-a',
        port: Q1.agentAPort + 2,
      },
      {
        username: `stresssharedb${suffix}`,
        email: `test.user+stresssharedb${suffix}@example.com`,
        sipPassword: 'StressSharedB@1902',
        service: 'sipp-agent-b',
        port: Q2.agentAPort + 2,
      },
      {
        username: `stresssharedreject${suffix}`,
        email: `test.user+stresssharedreject${suffix}@example.com`,
        sipPassword: 'StressSharedReject@1902',
        service: 'sipp-agent-a',
        port: Q1.agentAPort + 4,
        behavior: 'reject',
      },
    ];

    const allAgents = [...q1Agents, ...q2Agents, ...sharedAgents];

    const q1 = await createQueueViaApi({
      page,
      subdomain: 'acme',
      name: q1Name,
      extension: '8601',
      wrapUpTime: 1,
      rejectDelayTime: 1,
      maxNoAnswers: 1,
    });
    const q2 = await createQueueViaApi({
      page,
      subdomain: 'acme',
      name: q2Name,
      extension: '8602',
      wrapUpTime: 1,
      rejectDelayTime: 1,
      maxNoAnswers: 1,
    });

    for (const agent of [...q1Agents, ...sharedAgents]) {
      const member = await ensureMemberInOrg({
        subdomain: 'acme',
        email: agent.email,
        name: agent.username,
        username: agent.username,
        sipPassword: agent.sipPassword,
        presence: 'Available',
      });
      await addQueueMemberViaApi({
        page,
        subdomain: 'acme',
        queueId: q1.queue.id,
        userId: member.userId,
      });
    }

    for (const agent of [...q2Agents, ...sharedAgents]) {
      const member = await ensureMemberInOrg({
        subdomain: 'acme',
        email: agent.email,
        name: agent.username,
        username: agent.username,
        sipPassword: agent.sipPassword,
        presence: 'Available',
      });
      await addQueueMemberViaApi({
        page,
        subdomain: 'acme',
        queueId: q2.queue.id,
        userId: member.userId,
      });
    }

    await ensureDefaultOutboundRoute({
      subdomain: 'acme',
      number: Q1.did,
      sipTrunkName: 'Stress Burst Q1 Trunk',
      outboundContact: 'sipp-uas:' + Q1.uasPort,
      inboundIps: ['172.29.0.0/16'],
    });
    await ensureDefaultOutboundRoute({
      subdomain: 'acme',
      number: Q2.did,
      sipTrunkName: 'Stress Burst Q2 Trunk',
      outboundContact: 'sipp-uas:' + Q2.uasPort,
      inboundIps: ['172.29.0.0/16'],
    });
    await setNumberInboundFlowToQueue(Q1.did, q1Name);
    await setNumberInboundFlowToQueue(Q2.did, q2Name);
    await waitForFreeSwitchReady({ timeoutMs: 90_000 });

    await registerAgents(allAgents);

    const callers = [
      { caller: '+14155558901', did: Q1.did, port: Q1.callerPort },
      { caller: '+14155558902', did: Q1.did, port: Q1.callerPort + 1 },
      { caller: '+14155558903', did: Q2.did, port: Q2.callerPort },
      { caller: '+14155558904', did: Q2.did, port: Q2.callerPort + 1 },
    ];

    const agentRuns = allAgents.map((agent) => runAgentScenario(agent));

    try {
      await page.waitForTimeout(2_000);

      const callerRuns = callers.map((caller) =>
        runInboundDidCall({
          customerNumber: caller.caller,
          didNumber: caller.did,
          scenario: 'uac-basic.xml',
          localPort: caller.port,
          hangupAfterMs: 20_000,
          resetProcesses: false,
        }),
      );

      const callerResults = await Promise.all(callerRuns);
      const agentResults = await Promise.all(agentRuns);

      callerResults.forEach((result) =>
        expect(result.stderr).not.toContain('Failed'),
      );
      agentResults.forEach((result, index) => {
        if (allAgents[index]?.behavior === 'reject') {
          expect(result.exitCode).not.toBe(0);
        } else {
          expect(result.exitCode).toBe(0);
        }
      });

      const acceptedAors = new Set(
        allAgents.filter((agent) => agent.behavior !== 'reject').map(agentAor),
      );

      for (const caller of callers) {
        const story = await waitForCallStory({
          caller: caller.caller,
          callee: caller.did,
          direction: 'inbound',
          timeoutMs: 120_000,
        });

        const spans = await waitForCallSpans(
          story.id,
          (rows) =>
            rows.some(
              (row) =>
                row.type === 'ON_CALL' &&
                row.current_party != null &&
                acceptedAors.has(row.current_party),
            ),
          60_000,
        );

        const onCallParties = spans
          .filter((row) => row.type === 'ON_CALL' && row.current_party != null)
          .map((row) => row.current_party as string);

        expect(onCallParties.some((party) => acceptedAors.has(party))).toBe(
          true,
        );
      }
    } finally {
      await unregisterAgents(allAgents);
      await stopSippProcesses(
        Array.from(new Set(allAgents.map((agent) => agent.service))),
      );
      await Promise.allSettled(agentRuns);
    }
  },
);

test(
  'Queue stress: ten callers across two queues cycle through reject and no-answer agents before connecting',
  { tag: ['@sipp', '@queue', '@stress'] },
  async ({ page }) => {
    test.setTimeout(480_000);

    const suffix = Date.now().toString(36).slice(-6);
    const q1Name = `stress_large_q1_${suffix}`;
    const q2Name = `stress_large_q2_${suffix}`;
    const makeAgent = createAgentFactory(suffix, 10);

    // Per-queue agent mix tuned to force every call through a chain of
    // bad agents before a good one picks up, so call stories show real
    // retry behavior. 3 reject + 2 ring-forever + 2 answer per queue; the
    // queue's max_no_answers is bumped to 10 below so the bad agents stay
    // in the rotation for subsequent calls instead of getting logged out
    // after their first failure.
    const q1RejectAgents = Array.from({ length: 3 }, (_, i) =>
      makeAgent(
        'stressq1reject',
        i,
        i % 2 === 0 ? 'sipp-agent-a' : 'sipp-agent-b',
        'reject',
      ),
    );
    const q1NoAnswerAgents = Array.from({ length: 2 }, (_, i) =>
      makeAgent(
        'stressq1ring',
        i,
        i % 2 === 0 ? 'sipp-agent-b' : 'sipp-agent-a',
        'ring_forever',
      ),
    );
    const q2RejectAgents = Array.from({ length: 3 }, (_, i) =>
      makeAgent(
        'stressq2reject',
        i,
        i % 2 === 0 ? 'sipp-agent-a' : 'sipp-agent-b',
        'reject',
      ),
    );
    const q2NoAnswerAgents = Array.from({ length: 2 }, (_, i) =>
      makeAgent(
        'stressq2ring',
        i,
        i % 2 === 0 ? 'sipp-agent-b' : 'sipp-agent-a',
        'ring_forever',
      ),
    );

    // 4 answer agents per queue — enough throughput to absorb 15 callers
    // within the hangup-timeout window even after every caller burns
    // ~12 s cycling through the 3 reject + 2 ring bad agents.
    const q1DedicatedAgents = Array.from({ length: 4 }, (_, index) =>
      makeAgent(
        'stressq1answer',
        index,
        index % 2 === 0 ? 'sipp-agent-a' : 'sipp-agent-b',
      ),
    );
    const q2DedicatedAgents = Array.from({ length: 4 }, (_, index) =>
      makeAgent(
        'stressq2answer',
        index,
        index % 2 === 0 ? 'sipp-agent-b' : 'sipp-agent-a',
      ),
    );

    // Aliases kept so the existing assertion block below still refers to
    // single representative reject / no-answer agents.
    const q1RejectAgent = q1RejectAgents[0];
    const q1NoAnswerAgent = q1NoAnswerAgents[0];
    const q2RejectAgent = q2RejectAgents[0];
    const q2NoAnswerAgent = q2NoAnswerAgents[0];

    const q1Agents = [
      ...q1RejectAgents,
      ...q1NoAnswerAgents,
      ...q1DedicatedAgents,
    ];
    const q2Agents = [
      ...q2RejectAgents,
      ...q2NoAnswerAgents,
      ...q2DedicatedAgents,
    ];
    const allAgents = [
      ...q1RejectAgents,
      ...q1NoAnswerAgents,
      ...q2RejectAgents,
      ...q2NoAnswerAgents,
      ...q1DedicatedAgents,
      ...q2DedicatedAgents,
    ];

    const q1 = await createQueueViaApi({
      page,
      subdomain: 'acme',
      name: q1Name,
      extension: '8611',
      // In visual mode we want agents to dwell in Wrap Up / Busy long
      // enough for someone watching the dashboard to follow transitions.
      wrapUpTime: visualQueueStress ? 6 : 1,
      rejectDelayTime: visualQueueStress ? 5 : 1,
      // High enough that bad agents keep getting tried across calls;
      // each story exercises the full retry chain instead of the first
      // rejecter being auto-logged-out after one failure.
      maxNoAnswers: 10,
    });
    const q2 = await createQueueViaApi({
      page,
      subdomain: 'acme',
      name: q2Name,
      extension: '8612',
      wrapUpTime: visualQueueStress ? 6 : 1,
      rejectDelayTime: visualQueueStress ? 5 : 1,
      maxNoAnswers: 10,
    });

    for (const agent of q1Agents) {
      const member = await ensureMemberInOrg({
        subdomain: 'acme',
        email: agent.email,
        name: agent.username,
        username: agent.username,
        sipPassword: agent.sipPassword,
        presence: 'Available',
      });
      await addQueueMemberViaApi({
        page,
        subdomain: 'acme',
        queueId: q1.queue.id,
        userId: member.userId,
      });
    }

    for (const agent of q2Agents) {
      const member = await ensureMemberInOrg({
        subdomain: 'acme',
        email: agent.email,
        name: agent.username,
        username: agent.username,
        sipPassword: agent.sipPassword,
        presence: 'Available',
      });
      await addQueueMemberViaApi({
        page,
        subdomain: 'acme',
        queueId: q2.queue.id,
        userId: member.userId,
      });
    }

    await ensureDefaultOutboundRoute({
      subdomain: 'acme',
      number: Q1.did,
      sipTrunkName: 'Stress Burst Q1 Trunk',
      outboundContact: 'sipp-uas:' + Q1.uasPort,
      inboundIps: ['172.29.0.0/16'],
    });
    await ensureDefaultOutboundRoute({
      subdomain: 'acme',
      number: Q2.did,
      sipTrunkName: 'Stress Burst Q2 Trunk',
      outboundContact: 'sipp-uas:' + Q2.uasPort,
      inboundIps: ['172.29.0.0/16'],
    });
    await setNumberInboundFlowToQueue(Q1.did, q1Name);
    await setNumberInboundFlowToQueue(Q2.did, q2Name);

    await registerAgents(allAgents);

    // 5 callers per queue. Each connected call holds for the 15 s pause
    // in uac-basic.xml; with 4 answer agents per queue there's ample
    // throughput even after callers burn ~12 s each cycling through the
    // 3 reject + 2 ring bad agents. The focus of this test shifts from
    // raw throughput to showing realistic retry chains in call stories.
    const callers = [
      ...buildBurstCallers(Q1.did, Q1.callerPort, '61', 5),
      ...buildBurstCallers(Q2.did, Q2.callerPort, '62', 5),
    ];
    const agentRuns = allAgents.map((agent) => runAgentScenario(agent));

    try {
      await page.waitForTimeout(2_000);

      // Caller hangup window widened from 30s to 60s so callers can survive
      // cycling through 3 reject + 2 ring agents (≈12 s) plus queue wait
      // before the 4 answer agents per queue become free.
      const callerResults = await runCallersInWaves(
        page,
        callers,
        visualQueueStress ? 12 : 6,
        visualQueueStress ? 750 : 4_000,
        // Visual mode: long ring (4 s) + talk (8 s) + wrap-up (6 s) = ~18 s
        // per answer-agent cycle. With 4 answer agents and 5 callers per
        // queue plus a full reject/ring retry chain, the last caller needs
        // ~120 s to survive until an answer slot opens.
        visualQueueStress ? 150_000 : 60_000,
      );

      callerResults.forEach((result) => {
        expect(result.exitCode).toBe(0);
        expect(result.stderr).not.toContain('Failed');
      });

      const acceptedAors = new Set(
        allAgents.filter((agent) => agent.behavior === 'answer').map(agentAor),
      );
      const rejectAors = new Set([q1RejectAgent, q2RejectAgent].map(agentAor));
      const noAnswerAors = new Set(
        [q1NoAnswerAgent, q2NoAnswerAgent].map(agentAor),
      );
      const rejectedAors = new Set([...rejectAors, ...noAnswerAors]);

      const stories = await Promise.all(
        callers.map((caller) =>
          waitForCallStory({
            caller: caller.caller,
            callee: caller.did,
            direction: 'inbound',
            timeoutMs: 150_000,
          }),
        ),
      );

      const spansByStory = await Promise.all(
        stories.map((story) =>
          waitForCallSpans(story.id, (rows) => rows.length > 0, 60_000),
        ),
      );

      const answeredStories = spansByStory.filter((spans) =>
        spans.some(
          (row) =>
            row.type === 'ON_CALL' &&
            row.current_party != null &&
            acceptedAors.has(row.current_party),
        ),
      );

      spansByStory.forEach((spans) => {
        const onCallParties = spans
          .filter((row) => row.type === 'ON_CALL' && row.current_party != null)
          .map((row) => row.current_party as string);

        expect(onCallParties.some((party) => rejectedAors.has(party))).toBe(
          false,
        );
      });

      expect(answeredStories.length).toBeGreaterThanOrEqual(callers.length - 3);

      const ringingParties = new Set(
        spansByStory.flatMap((spans) =>
          spans
            .filter(
              (row) =>
                row.type === 'RINGING' &&
                row.current_party != null &&
                rejectedAors.has(row.current_party),
            )
            .map((row) => row.current_party as string),
        ),
      );

      expect(ringingParties.has(agentAor(q1RejectAgent))).toBe(true);
      expect(ringingParties.has(agentAor(q2RejectAgent))).toBe(true);
      expect(ringingParties.has(agentAor(q1NoAnswerAgent))).toBe(true);
      expect(ringingParties.has(agentAor(q2NoAnswerAgent))).toBe(true);

      const uniqueAcceptedParties = new Set(
        answeredStories.flatMap((spans) =>
          spans
            .filter(
              (row) =>
                row.type === 'ON_CALL' &&
                row.current_party != null &&
                acceptedAors.has(row.current_party),
            )
            .map((row) => row.current_party as string),
        ),
      );

      // With the tighter agent mix (2 answer per queue) we only need to
      // see that both queues used their full answer-agent pool. Previous
      // value (>=10) assumed 13 dedicated + 4 shared answer agents.
      expect(uniqueAcceptedParties.size).toBeGreaterThanOrEqual(3);

      // We intentionally bumped max_no_answers to 10 so reject and ring
      // agents keep getting tried across calls — don't expect them to be
      // auto-logged-out during the test. The old logout assertion is gone.

      // --- Regression: customer hangup must stop agent ring immediately ---
      // When the customer hangs up while a ring-forever agent is mid-ring,
      // we used to leave the agent channel ringing for up to 8 s (the
      // dialer was blocked inside a synchronous `api originate` and the
      // cancel message sat in its mailbox). Assert every agent RINGING span
      // is closed and ends within a small grace of the call story's end.
      const ringEndSlackMs = 3_000;
      for (let i = 0; i < stories.length; i += 1) {
        const story = stories[i];
        const spans = spansByStory[i];
        const storyEndMs = story.end_at
          ? new Date(story.end_at).getTime()
          : null;
        expect(
          storyEndMs,
          `call story ${story.caller} has no end_at`,
        ).not.toBeNull();

        const ringingSpans = spans.filter((row) => row.type === 'RINGING');
        for (const span of ringingSpans) {
          expect(
            span.end_at,
            `RINGING span for ${span.current_party} on call ${story.caller} never closed`,
          ).not.toBeNull();

          const spanEndMs = new Date(span.end_at as Date).getTime();
          expect(
            spanEndMs - (storyEndMs as number),
            `RINGING span for ${span.current_party} on call ${story.caller} outlived customer by too long`,
          ).toBeLessThanOrEqual(ringEndSlackMs);
        }
      }

      // --- Regression: every attempt must have a closing event ---
      // Customer-hung-up-mid-ring used to leave QUEUE_ATTEMPT_STARTED without
      // a matching ANSWERED/FAILED/TIMED_OUT, because QueuedCall was stopped
      // before mark_failed could write the closing event. Assert the event
      // chain is well-formed.
      const closeTypes = new Set([
        'QUEUE_AGENT_ANSWERED',
        'QUEUE_ATTEMPT_FAILED',
        'QUEUE_ATTEMPT_TIMED_OUT',
      ]);
      for (const story of stories) {
        const events = await getCallStoryEvents(story.id);
        const openAttemptsByMember = new Map<string, number>();
        const danglingMembers: string[] = [];

        for (const ev of events) {
          const member = (ev.metadata as { member_username?: string } | null)
            ?.member_username;
          if (!member) continue;

          if (ev.type === 'QUEUE_ATTEMPT_STARTED') {
            openAttemptsByMember.set(
              member,
              (openAttemptsByMember.get(member) ?? 0) + 1,
            );
          } else if (closeTypes.has(ev.type)) {
            const prev = openAttemptsByMember.get(member) ?? 0;
            if (prev > 0) openAttemptsByMember.set(member, prev - 1);
          }
        }

        for (const [member, open] of openAttemptsByMember) {
          if (open > 0) danglingMembers.push(`${member}(x${open})`);
        }

        expect(
          danglingMembers,
          `call ${story.caller}: QUEUE_ATTEMPT_STARTED without a close for ${danglingMembers.join(
            ', ',
          )}`,
        ).toEqual([]);
      }
    } finally {
      await unregisterAgents(allAgents);
      await stopSippProcesses(
        Array.from(new Set(allAgents.map((agent) => agent.service))),
      );
      await Promise.allSettled(agentRuns);
    }
  },
);
