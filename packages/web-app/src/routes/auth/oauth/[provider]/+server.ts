import type { RequestHandler } from './$types';
import { redirect } from '@sveltejs/kit';
import { getInternalJson } from '$lib/server/api';

type OAuthStartResponse = {
  authUrl: string;
};

export const GET: RequestHandler = async ({ params, url, fetch }) => {
  const redirectUri = `${url.origin}/auth/callback/${params.provider}`;
  const result = await getInternalJson<OAuthStartResponse>(
    `/api/v2/auth/oauth/${params.provider}/start?redirect_uri=${encodeURIComponent(redirectUri)}`,
    fetch,
  );

  if (!result.ok) {
    throw redirect(303, '/login');
  }

  throw redirect(303, result.data.authUrl);
};
