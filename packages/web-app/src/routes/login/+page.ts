import { redirect } from '@sveltejs/kit';
import { getJson } from '$lib/http';
import { clearSessionToken, hasSessionToken } from '$lib/session';
import type { PageLoad } from './$types';

type AuthConfig = {
  passwordEnabled: boolean;
  bootstrapMode: boolean;
  oauthProviders: Array<{ id: string; label: string; type: string }>;
};

// The API is only reachable from the browser, so this page loads there.
export const ssr = false;

export const load: PageLoad = async ({ fetch }) => {
  // Already signed in: skip the form. A 401 means the token has expired or
  // its user is gone, so drop it rather than send it with every request.
  if (hasSessionToken()) {
    const session = await getJson('/api/v2/user/session', { fetchFn: fetch });
    if (session.ok) redirect(303, '/');
    if (session.status === 401) clearSessionToken();
  }

  const authConfigResult = await getJson<AuthConfig>('/api/v2/auth/config', { fetchFn: fetch });

  if (authConfigResult.ok && authConfigResult.data.bootstrapMode) {
    redirect(303, '/setup');
  }

  return {
    authConfig: authConfigResult.ok
      ? authConfigResult.data
      : { passwordEnabled: true, bootstrapMode: false, oauthProviders: [] },
  };
};
