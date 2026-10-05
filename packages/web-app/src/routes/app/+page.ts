import type { PageLoad } from './$types';
import { redirect } from '@sveltejs/kit';
import { getJson } from '$lib/http';
import { getLastOrg, orgToOpen } from '$lib/lastOrg';

// Where signing in lands (login, sign-up, OAuth, password reset and / all
// come here): straight into the org the user was last in, else the list.
// The list itself (/org) never redirects, so it can always be reached.
export const load: PageLoad = async ({ fetch, parent }) => {
  // The layout has checked the session and the terms.
  await parent();

  const result = await getJson<{ orgs: { subdomain: string }[]; invites: unknown[] }>(
    '/api/v2/user/orgs',
    { fetchFn: fetch },
  );
  const subdomain = result.ok
    ? orgToOpen({ orgs: result.data.orgs ?? [], invites: result.data.invites ?? [] }, getLastOrg())
    : null;

  redirect(303, subdomain ? `/app/${subdomain}` : '/org');
};
