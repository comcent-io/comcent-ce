import crypto from 'crypto';

export function generateSecureApiKey(apiKeyLength: number) {
  const apiKeyBuffer = crypto.randomBytes(apiKeyLength);
  return apiKeyBuffer.toString('hex');
}
