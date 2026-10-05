import { error, redirect } from '@sveltejs/kit';
import { getJson } from '$lib/http';
import { hasSessionToken } from '$lib/session';
import { termsToAccept, type SessionTerms } from '$lib/terms';
import type { PageLoad } from './$types';

// The API is only reachable from the browser, so this page loads there.
export const ssr = false;

export const load: PageLoad = async ({ fetch }) => {
  if (!hasSessionToken()) redirect(303, '/login');

  const session = await getJson<{ terms: SessionTerms | null }>('/api/v2/user/session', {
    fetchFn: fetch,
  });
  if (!session.ok) {
    if (session.status === 401) redirect(303, '/login');
    error(500, { message: session.error || 'Unable to validate current session' });
  }

  // Nothing to accept: no terms on this deployment, or already accepted.
  const terms = termsToAccept(session.data.terms);
  if (!terms) redirect(303, '/app');

  return { terms };
};
