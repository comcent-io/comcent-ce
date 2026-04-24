import { redisClient } from './redis/index.js';

function callQueueKey(subdomain: string, queueName: string) {
  return `queue:waiting:${subdomain}:${queueName}`;
}

export async function addCallToQueue(
  subdomain: string,
  queueName: string,
  callId: string,
  freeSwitchIpAddress: string,
) {
  const callDetails = {
    callId,
    freeSwitchIpAddress,
  };
  const key = callQueueKey(subdomain, queueName);
  await redisClient.rPush(key, JSON.stringify(callDetails));
}
