import { env } from '$env/dynamic/public';

const baseUrl = env.PUBLIC_BASE_URL || '';

let parsed: URL | null = null;
try {
  if (baseUrl) parsed = new URL(baseUrl);
} catch {
  parsed = null;
}

export const publicBaseUrl = baseUrl || null;

export const publicAppBaseUrl = env.PUBLIC_APP_BASE_URL || baseUrl || null;

export const publicSipUserRootDomain =
  env.PUBLIC_SIP_USER_ROOT_DOMAIN || (parsed ? parsed.hostname : '');

// SIP WS endpoint is set explicitly — the SBC binds it on a dedicated port
// (and may even use a different host than PUBLIC_BASE_URL in EE), so it isn't
// safe to derive from PUBLIC_BASE_URL.
export const publicSipWsUrl = env.PUBLIC_SIP_WS_URL || null;
