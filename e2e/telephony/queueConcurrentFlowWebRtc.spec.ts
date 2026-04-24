import { expect, test } from '@playwright/test';
import {
  ensureDefaultOutboundRoute,
  ensureMemberInOrg,
  ensureUserAcceptedTerms,
  ensureUserEmailVerified,
  setNumberInboundFlowToQueue,
  waitForCallStory,
} from '../utils/telephonyDb';
import { addQueueMemberViaApi, createQueueViaApi } from '../utils/telephonyApi';
import { allocations } from './testAllocations';
import { runInboundDidCall } from '../utils/sipp';
import {
  answerIncomingCall,
  ensureRegisteredUser,
  hangupCurrentCall,
  installDialerObservers,
  loginAsMember,
  waitForDialerConnected,
} from '../utils/webDialer';

test.describe.configure({ mode: 'serial' });

const A = allocations.queueConcurrent;

test('Two concurrent queue calls are distributed to two available browser WebRTC agents', async ({
  browser,
  page,
}) => {
  test.setTimeout(240_000);

  const publicNumber = A.did;
  const callerOne = '+14155557664';
  const callerTwo = '+14155557665';
  const queueName = 'telephony_queue_concurrent';

  await ensureDefaultOutboundRoute({
    subdomain: 'acme',
    number: publicNumber,
    sipTrunkName: 'Telephony Queue Concurrent',
    outboundContact: 'sipp-uas:' + A.uasPort,
    inboundIps: ['172.29.0.0/16'],
  });

  const agentOne = {
    name: 'WebRTC Queue Concurrent One',
    email: 'test.user+queueconcurrentone@example.com',
    password: 'QueueConcurrentOne@1902',
    username: 'queueconcurrentone',
    sipPassword: 'QueueConcurrentOneSip@1902',
  };
  const agentTwo = {
    name: 'WebRTC Queue Concurrent Two',
    email: 'test.user+queueconcurrenttwo@example.com',
    password: 'QueueConcurrentTwo@1902',
    username: 'queueconcurrenttwo',
    sipPassword: 'QueueConcurrentTwoSip@1902',
  };

  await ensureRegisteredUser(page.request, {
    name: agentOne.name,
    email: agentOne.email,
    password: agentOne.password,
  });
  await ensureRegisteredUser(page.request, {
    name: agentTwo.name,
    email: agentTwo.email,
    password: agentTwo.password,
  });

  const firstMember = await ensureMemberInOrg({
    subdomain: 'acme',
    email: agentOne.email,
    name: agentOne.name,
    username: agentOne.username,
    sipPassword: agentOne.sipPassword,
    presence: 'Available',
  });
  const secondMember = await ensureMemberInOrg({
    subdomain: 'acme',
    email: agentTwo.email,
    name: agentTwo.name,
    username: agentTwo.username,
    sipPassword: agentTwo.sipPassword,
    presence: 'Available',
  });
  await ensureUserAcceptedTerms(agentOne.email);
  await ensureUserAcceptedTerms(agentTwo.email);
  await ensureUserEmailVerified(agentOne.email);
  await ensureUserEmailVerified(agentTwo.email);

  const queueResponse = await createQueueViaApi({
    page,
    subdomain: 'acme',
    name: queueName,
    extension: '8402',
    wrapUpTime: 1,
    rejectDelayTime: 1,
    maxNoAnswers: 1,
  });
  const queueId = queueResponse.queue.id as string;

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
  await setNumberInboundFlowToQueue(publicNumber, queueName);

  const firstSession = await loginAsMember({
    browser,
    request: page.request,
    email: agentOne.email,
    password: agentOne.password,
    subdomain: 'acme',
  });
  const secondSession = await loginAsMember({
    browser,
    request: page.request,
    email: agentTwo.email,
    password: agentTwo.password,
    subdomain: 'acme',
  });

  await installDialerObservers(firstSession.page);
  await installDialerObservers(secondSession.page);

  // Give the queue + both agent registrations time to settle through
  // the async pipeline before the customer calls arrive.
  await firstSession.page.waitForTimeout(5_000);

  const customerCallOne = runInboundDidCall({
    customerNumber: callerOne,
    didNumber: publicNumber,
    scenario: 'uac-remote-bye.xml',
    callerService: 'sipp',
    localPort: A.callerPort,
    hangupAfterMs: 60_000,
    resetProcesses: false,
  });
  const customerCallTwo = runInboundDidCall({
    customerNumber: callerTwo,
    didNumber: publicNumber,
    scenario: 'uac-remote-bye.xml',
    callerService: 'sipp',
    localPort: A.callerPort + 1,
    hangupAfterMs: 60_000,
    resetProcesses: false,
  });

  await Promise.all([
    expect(
      firstSession.page.getByRole('button', { name: 'Answer' }).first(),
    ).toBeVisible({
      timeout: 45_000,
    }),
    expect(
      secondSession.page.getByRole('button', { name: 'Answer' }).first(),
    ).toBeVisible({
      timeout: 45_000,
    }),
  ]);

  // Let both calls ring for a couple of seconds before answering so the
  // RINGING spans in the call story UI have a visible (non-zero) duration.
  await firstSession.page.waitForTimeout(2_000);

  await Promise.all([
    answerIncomingCall(firstSession.page),
    answerIncomingCall(secondSession.page),
  ]);

  await Promise.all([
    waitForDialerConnected(firstSession.page, 45_000),
    waitForDialerConnected(secondSession.page, 45_000),
  ]);

  await firstSession.page.waitForTimeout(2_000);
  await Promise.all([
    hangupCurrentCall(firstSession.page),
    hangupCurrentCall(secondSession.page),
  ]);

  const [callOneResult, callTwoResult] = await Promise.all([
    customerCallOne,
    customerCallTwo,
  ]);
  expect(callOneResult.stderr).not.toContain('Failed');
  expect(callTwoResult.stderr).not.toContain('Failed');

  const [storyOne, storyTwo] = await Promise.all([
    waitForCallStory({
      caller: callerOne,
      callee: publicNumber,
      direction: 'inbound',
      timeoutMs: 90_000,
    }),
    waitForCallStory({
      caller: callerTwo,
      callee: publicNumber,
      direction: 'inbound',
      timeoutMs: 90_000,
    }),
  ]);

  expect(storyOne.id).not.toBe(storyTwo.id);

  await firstSession.context.close();
  await secondSession.context.close();
});
