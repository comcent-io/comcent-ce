import { error, redirect } from '@sveltejs/kit';
import { getJson } from '$lib/http';
import { hasSessionToken } from '$lib/session';
import type { LayoutLoad } from './$types';

type SessionUser = {
  id: string;
  email: string;
  name: string;
  picture?: string;
};

// Everything under /app reads from the API, which is only reachable from the
// browser, so these pages render there. The API is what enforces access; the
// redirects below only keep people off pages they cannot use.
export const ssr = false;

export const load: LayoutLoad = async ({ fetch }) => {
  if (!hasSessionToken()) redirect(303, '/login');

  const session = await getJson<{ user: SessionUser }>('/api/v2/user/session', {
    fetchFn: fetch,
  });
  if (!session.ok) {
    if (session.status === 401) redirect(303, '/login');
    error(500, { message: session.error || 'Unable to validate current session' });
  }

  return {
    user: session.data.user,
  };
};
