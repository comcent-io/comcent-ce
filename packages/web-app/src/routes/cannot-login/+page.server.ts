import type { PageServerLoad } from './$types';
import { redirect } from '@sveltejs/kit';
import { verifyToken } from '$lib/server/auth';

export const load: PageServerLoad = async ({ cookies }) => {
  const idToken = cookies.get('idToken');
  if (!idToken) {
    throw redirect(307, '/login');
  }
  const user = await verifyToken(idToken);
  if (!user) {
    throw redirect(307, '/login');
  }
  return {
    user,
  };
};
