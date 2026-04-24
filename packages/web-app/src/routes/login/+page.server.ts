import { fail, redirect } from '@sveltejs/kit';
import type { Actions, ServerLoad } from './$types';
import { verifyToken } from '$lib/server/auth';
import { getInternalJson, postInternalJson } from '$lib/server/api';

type AuthConfig = {
  passwordEnabled: boolean;
  oauthProviders: Array<{ id: string; label: string; type: string }>;
};

type AuthResponse = {
  token?: string;
  message?: string;
  user?: {
    id: string;
    email: string;
    name: string;
    picture?: string;
    authProvider: string;
  };
};

export const load: ServerLoad = async ({ cookies, fetch }) => {
  const idToken = cookies.get('idToken');
  if (idToken) {
    const user = await verifyToken(idToken);
    if (user) {
      throw redirect(303, '/');
    }
  }

  const authConfigResult = await getInternalJson<AuthConfig>('/api/v2/auth/config', fetch);

  return {
    authConfig: authConfigResult.ok
      ? authConfigResult.data
      : { passwordEnabled: true, oauthProviders: [] },
  };
};

export const actions: Actions = {
  login: async ({ request, cookies, fetch }) => {
    const formData = await request.formData();
    const email = String(formData.get('email') || '');
    const password = String(formData.get('password') || '');

    const result = await postInternalJson<AuthResponse>(
      '/api/v2/auth/login',
      { email, password },
      fetch,
    );

    if (!result.ok) {
      if (result.status === 403) {
        throw redirect(303, `/auth/verify-email/pending?email=${encodeURIComponent(email)}`);
      }

      return fail(result.status || 400, {
        loginError: result.error,
        registerError: null,
        registerSuccess: null,
        resendSuccess: null,
        pendingVerificationEmail: null,
      });
    }

    cookies.set('idToken', result.data.token!, { path: '/', httpOnly: false });
    throw redirect(303, '/app');
  },
  register: async ({ request, cookies, fetch }) => {
    const formData = await request.formData();
    const name = String(formData.get('name') || '');
    const email = String(formData.get('email') || '');
    const password = String(formData.get('password') || '');

    const result = await postInternalJson<AuthResponse>(
      '/api/v2/auth/register',
      { name, email, password },
      fetch,
    );

    if (!result.ok) {
      return fail(result.status || 400, {
        registerError: result.error,
        loginError: null,
        registerSuccess: null,
        resendSuccess: null,
        pendingVerificationEmail: null,
      });
    }

    cookies.delete('idToken', { path: '/' });
    throw redirect(303, `/auth/verify-email/pending?email=${encodeURIComponent(email)}`);
  },
  resendVerification: async ({ request, fetch }) => {
    const formData = await request.formData();
    const email = String(formData.get('email') || '');

    const result = await postInternalJson<{ message: string }>(
      '/api/v2/auth/resend-verification',
      { email },
      fetch,
    );

    if (!result.ok) {
      return fail(result.status || 400, {
        resendSuccess: null,
        loginError: null,
        registerError: null,
        registerSuccess: null,
        pendingVerificationEmail: email,
      });
    }

    return {
      resendSuccess: result.data.message,
      loginError: null,
      registerError: null,
      registerSuccess: null,
      pendingVerificationEmail: email,
    };
  },
};
