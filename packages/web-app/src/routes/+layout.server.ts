import { ensureAuthenticated } from '$lib/auth';
import type { LayoutServerLoad } from './$types';

export const load: LayoutServerLoad = async ({ cookies, url }) => {
  if (!url.pathname.startsWith('/app')) return {};
  const user = await ensureAuthenticated(cookies);
  return {
    user: {
      name: user.name,
      email: user.email,
    },
  };
};
