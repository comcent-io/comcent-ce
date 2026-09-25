import { redirect } from '@sveltejs/kit';
import type { PageLoad } from './$types';

const RESEND_COOLDOWN_SECONDS = 60;

export const load: PageLoad = ({ url }) => {
  const email = String(url.searchParams.get('email') || '').trim();

  if (!email) {
    throw redirect(303, '/login');
  }

  return {
    email,
    resendCooldownSeconds: RESEND_COOLDOWN_SECONDS,
  };
};
