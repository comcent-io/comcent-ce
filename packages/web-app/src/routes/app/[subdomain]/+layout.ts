import { error, redirect } from '@sveltejs/kit';
import { getJson } from '$lib/http';
import type { LayoutLoad } from './$types';

// Sections only admins can open. The API rejects a member's requests to these
// anyway; this sends them back to the dashboard instead of a broken page.
const ADMIN_SECTIONS = [
  'call-story',
  'members',
  'numbers',
  'sip-trunks',
  'presence',
  'settings',
  'voice-bots',
  'queues',
];

export const load: LayoutLoad = async ({ url, params, fetch, parent }) => {
  const { user } = await parent();
  const result = await getJson<{
    numbers: any[];
    memberProfile: any;
    organizations: any[];
  }>(`/api/v2/${params.subdomain}/me/context`, { fetchFn: fetch });
  if (!result.ok) {
    if (result.status === 401) throw redirect(303, '/login');
    if (
      result.status === 404 &&
      (result.data as { error?: string } | null)?.error === 'not_org_member'
    ) {
      throw redirect(303, '/org');
    }
    throw error(result.status || 500, { message: result.error });
  }

  const { numbers, memberProfile: member, organizations } = result.data;

  if (!member) {
    throw Error('Member not found');
  }

  const section = url.pathname.split('/').filter(Boolean)[2];
  if (section && ADMIN_SECTIONS.includes(section) && member.role !== 'ADMIN') {
    throw redirect(303, `/app/${params.subdomain}`);
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
