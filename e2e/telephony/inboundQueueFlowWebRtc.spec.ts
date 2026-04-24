import { expect, test } from '@playwright/test';
import {
  ensureDefaultOutboundRoute,
  ensureMemberInOrg,
  ensureUserAcceptedTerms,
  ensureUserEmailVerified,
  setNumberInboundFlowToQueue,
  waitForInboundCallStoryObserved,
} from '../utils/telephonyDb';
import { addQueueMemberViaApi, createQueueViaApi } from '../utils/telephonyApi';
import { allocations } from './testAllocations';
import { runInboundDidCall } from '../utils/sipp';
import {
  answerIncomingCall,
  ensureRegisteredUser,
  installDialerObservers,
  loginAsMember,
  waitForDialerConnected,
  waitForDialerHungUp,
} from '../utils/webDialer';

test.describe.configure({ mode: 'serial' });

const A = allocations.inboundQueueWebRtc;

test('Inbound DID routes through Queue node to a browser WebRTC agent', async ({
  browser,
  page,
}) => {
  test.setTimeout(180_000);

  const publicNumber = A.did;
  const customerNumber = '+14155559877';
  const queueName = 'telephonywebrtcqueue';
  const queueExtension = '8103';
  const agent = {
    name: 'WebRTC Queue Agent',
    email: 'test.user+webrtcqueueagent@example.com',
    password: 'WebRtcQueueAgent@1902',
    username: 'webrtcqueueagent',
    sipPassword: 'WebRtcQueueSip@1902',
  };

  await ensureRegisteredUser(page.request, {
    name: agent.name,
    email: agent.email,
    password: agent.password,
  });

  const { userId } = await ensureMemberInOrg({
    subdomain: 'acme',
    email: agent.email,
    name: agent.name,
    username: agent.username,
    sipPassword: agent.sipPassword,
    presence: 'Available',
  });
  await ensureUserAcceptedTerms(agent.email);
  await ensureUserEmailVerified(agent.email);

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
    sipTrunkName: 'Telephony WebRTC Queue',
    outboundContact: 'sipp-uas:' + A.uasPort,
    inboundIps: ['172.29.0.0/16'],
  });
  await setNumberInboundFlowToQueue(publicNumber, queueName);

  const { context, page: agentPage } = await loginAsMember({
    browser,
    request: page.request,
    email: agent.email,
    password: agent.password,
    subdomain: 'acme',
  });

  await installDialerObservers(agentPage);

  // Give the queue + agent registration time to settle through the
  // async pipeline before the inbound call arrives.  No internal
  // state probing — just a fixed wait.
  await agentPage.waitForTimeout(5_000);

  const callPromise = runInboundDidCall({
    customerNumber,
    didNumber: publicNumber,
    hangupAfterMs: 60_000,
    localPort: A.callerPort,
  });

  await expect(agentPage.getByRole('button', { name: 'Answer' })).toBeVisible({
    timeout: 45_000,
  });
  // Let the call ring for a couple of seconds before answering so the
  // RINGING span in the call story UI has a visible (non-zero) duration.
  await agentPage.waitForTimeout(2_000);
  await answerIncomingCall(agentPage);
  await waitForDialerConnected(agentPage, 45_000);
  await waitForDialerHungUp(agentPage, 60_000);

  const uacResult = await callPromise;
  expect(uacResult.stderr).not.toContain('Failed');

  const callStory = await waitForInboundCallStoryObserved({
    caller: customerNumber,
    callee: publicNumber,
    timeoutMs: 90_000,
  });

  expect(callStory.direction).toBe('inbound');
  expect(callStory.spans).toBeGreaterThan(0);

  await context.close();
});
