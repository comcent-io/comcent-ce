import { error, redirect } from '@sveltejs/kit';
import { getJson } from '$lib/http';
import { hasSessionToken } from '$lib/session';
import { termsToAccept, type SessionTerms } from '$lib/terms';

export type SessionUser = {
  id: string;
  email: string;
  name: string;
  picture?: string;
};

/**
 * The load for pages that need someone signed in who has accepted the
 * current terms (/app, /org, /invitation): sends everyone else to /login or
 * /terms-conditions, and gives the page the user. The API is what enforces
 * access; this only keeps people off pages they can't use.
 */
export async function loadSignedInUser(fetch: typeof globalThis.fetch) {
  if (!hasSessionToken()) redirect(303, '/login');

  const session = await getJson<{ user: SessionUser; terms: SessionTerms | null }>(
    '/api/v2/user/session',
    { fetchFn: fetch },
  );
  if (!session.ok) {
    if (session.status === 401) redirect(303, '/login');
    error(500, { message: session.error || 'Unable to validate current session' });
  }
  if (termsToAccept(session.data.terms)) redirect(303, '/terms-conditions');

  return { user: session.data.user };
}
