import { error, redirect } from '@sveltejs/kit';
import { verifyToken } from '$lib/server/auth';
import type { AuthSessionUser } from '$lib/server/types/AuthSessionUser';
import { getAuthedJson } from '$lib/server/api';

export type AuthenticatedUser = AuthSessionUser & { idToken: string };

export async function ensureAuthenticated(cookies: any): Promise<AuthenticatedUser> {
  const idToken = cookies.get('idToken');
  if (!idToken) throw redirect(303, '/login');
  const user = await verifyToken(idToken);
  if (!user) throw redirect(303, '/login');

  const session = await getAuthedJson<{ user: { hasAgreedToTos: boolean } }>(
    '/api/v2/user/session',
    idToken,
  );
  if (!session.ok) {
    if (session.status === 401) throw redirect(303, '/login');
    throw error(500, { message: session.error || 'Unable to validate current session' });
  }
  if (!session.data.user?.hasAgreedToTos) throw redirect(303, '/terms-conditions');

  return {
    ...user,
    idToken,
  };
}

export async function ensureIsOrgMember(user: AuthenticatedUser, orgSubdomain: string) {
  const access = await getAuthedJson<{ access: { role: 'ADMIN' | 'MEMBER' } }>(
    `/api/v2/${orgSubdomain}/me/access`,
    user.idToken,
  );

  if (!access.ok) throw redirect(303, '/org');
  return access.data.access;
}

export async function ensureIsOrgMemberWithRole(
  user: AuthenticatedUser,
  orgSubdomain: string,
  role: 'ADMIN' | 'MEMBER' = 'ADMIN',
) {
  const access = await ensureIsOrgMember(user, orgSubdomain);
  if (access.role !== role) throw redirect(303, `/app/${orgSubdomain}`);
  return access;
}
