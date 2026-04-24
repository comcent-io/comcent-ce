import { redirect } from '@sveltejs/kit';
import type { PageServerLoad } from './$types';
import { postInternalJson } from '$lib/server/api';

type VerifyEmailResponse = {
  token: string;
};

export const load: PageServerLoad = async ({ params, cookies, fetch }) => {
  const result = await postInternalJson<VerifyEmailResponse>(
    '/api/v2/auth/verify-email',
    { token: params.token },
    fetch,
  );

  if (!result.ok || !result.data.token) {
    return {
      error: result.error || 'Verification link is invalid or expired.',
    };
  }

  cookies.set('idToken', result.data.token, { path: '/', httpOnly: false });
  throw redirect(303, '/app');
};
