import { fail, redirect } from '@sveltejs/kit';
import type { Actions, ServerLoad } from './$types';
import { getInternalJson, postInternalJson } from '$lib/server/api';

type AuthConfig = {
  passwordEnabled: boolean;
  bootstrapMode: boolean;
  oauthProviders: Array<{ id: string; label: string; type: string }>;
};

type ClaimResponse = {
  token?: string;
  user?: {
    id: string;
    email: string;
    name: string;
    authProvider: string;
  };
};

export const load: ServerLoad = async ({ fetch }) => {
  const result = await getInternalJson<AuthConfig>('/api/v2/auth/config', fetch);

  if (!result.ok || !result.data.bootstrapMode) {
    throw redirect(303, '/login');
  }

  return {
    passwordEnabled: result.data.passwordEnabled,
  };
};

export const actions: Actions = {
  claim: async ({ request, cookies, fetch }) => {
    const formData = await request.formData();
    const payload = {
      name: String(formData.get('name') || ''),
      email: String(formData.get('email') || ''),
      password: String(formData.get('password') || ''),
      org_name: String(formData.get('orgName') || ''),
      subdomain: String(formData.get('subdomain') || ''),
      sip_username: String(formData.get('sipUsername') || ''),
      token: String(formData.get('token') || ''),
    };

    const result = await postInternalJson<ClaimResponse>(
      '/api/v2/auth/claim-setup',
      payload,
      fetch,
    );

    if (!result.ok) {
      return fail(result.status || 400, {
        error: result.error,
        values: {
          name: payload.name,
          email: payload.email,
          orgName: payload.org_name,
          subdomain: payload.subdomain,
          sipUsername: payload.sip_username,
        },
      });
    }

    cookies.set('idToken', result.data.token!, { path: '/', httpOnly: false });
    throw redirect(303, '/app');
  },
};
