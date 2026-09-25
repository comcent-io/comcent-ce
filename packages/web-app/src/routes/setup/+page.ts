import { redirect } from '@sveltejs/kit';
import { getJson } from '$lib/http';
import type { PageLoad } from './$types';

// The API is only reachable from the browser, so this page loads there.
export const ssr = false;

export const load: PageLoad = async ({ fetch }) => {
  const result = await getJson<{ bootstrapMode: boolean }>('/api/v2/auth/config', {
    fetchFn: fetch,
  });

  if (!result.ok || !result.data.bootstrapMode) {
    throw redirect(303, '/login');
  }
};
