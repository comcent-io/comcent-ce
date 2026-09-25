import { redirect } from '@sveltejs/kit';
import { getJson } from '$lib/http';
import { hasSessionToken } from '$lib/session';
import type { PageLoad } from './$types';

// The API is only reachable from the browser, so this page loads there.
export const ssr = false;

export const load: PageLoad = async ({ fetch }) => {
  if (!hasSessionToken()) redirect(307, '/login');

  const session = await getJson<{ user: { email: string } }>('/api/v2/user/session', {
    fetchFn: fetch,
  });
  if (!session.ok) redirect(307, '/login');

  return {
    user: session.data.user,
  };
};
