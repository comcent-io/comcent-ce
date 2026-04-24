import type { Actions } from './$types';
import { redirect } from '@sveltejs/kit';

export const actions: Actions = {
  default: async ({ cookies }) => {
    cookies.delete('idToken');
    throw redirect(303, '/login');
  },
};
