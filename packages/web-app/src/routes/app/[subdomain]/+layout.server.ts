import { ensureAuthenticated } from '$lib/auth';
import { getAuthedJson } from '$lib/server/api';
import type { LayoutServerLoad } from './$types';
import { redirect } from '@sveltejs/kit';

export const load: LayoutServerLoad = async ({ cookies, params }) => {
  const user = await ensureAuthenticated(cookies);
  const result = await getAuthedJson<{
    numbers: any[];
    memberProfile: any;
    orgSettings: any;
    organizations: any[];
  }>(`/api/v2/${params.subdomain}/me/context`, user.idToken);
  if (!result.ok) {
    if (
      result.status === 404 &&
      (result.data as { error?: string } | null)?.error === 'not_org_member'
    ) {
      throw redirect(303, '/org');
    }
    throw new Error(result.error);
  }

  const { numbers, memberProfile: member, organizations } = result.data;

  if (!member) {
    throw Error('Member not found');
  }

  return {
    sipConfig: {
      username: member.username,
      sipPassword: member.sipPassword,
      subdomain: params.subdomain,
    },
    organizations,
    user,
    member: member!,
    numbers,
    basePath: `/app/${params.subdomain}`,
    // CE has no billing/wallet — always false, no redirect to recharge.
    showLowBalanceAlert: false,
    walletBalance: 0,
  };
};
