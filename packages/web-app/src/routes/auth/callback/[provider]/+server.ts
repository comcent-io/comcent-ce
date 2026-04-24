import type { RequestHandler } from './$types';
import { redirect } from '@sveltejs/kit';
import { getInternalJson } from '$lib/server/api';

type OAuthCallbackResponse = {
  token: string;
  user: {
    id: string;
    email: string;
    name: string;
    authProvider: string;
  };
};

export const GET: RequestHandler = async ({ params, url, cookies, fetch }) => {
  const redirectUri = `${url.origin}/auth/callback/${params.provider}`;
  const callbackUrl =
    `/api/v2/auth/oauth/${params.provider}/callback?code=${encodeURIComponent(url.searchParams.get('code') || '')}` +
    `&state=${encodeURIComponent(url.searchParams.get('state') || '')}` +
    `&redirect_uri=${encodeURIComponent(redirectUri)}`;

  const result = await getInternalJson<OAuthCallbackResponse>(callbackUrl, fetch);

  if (!result.ok) {
    throw redirect(303, '/login');
  }

  cookies.set('idToken', result.data.token, { path: '/', httpOnly: false });
  throw redirect(303, '/app');
};
