import { ensureAuthenticated } from '$lib/auth';
import { getAuthedJson } from '$lib/server/api';
import type { LayoutServerLoad } from './$types';
import { redirect } from '@sveltejs/kit';
import { convertWalletBalanceToDollars } from '$lib/server/payments/money';

export const load: LayoutServerLoad = async ({ url, cookies, params, fetch }) => {
  const user = await ensureAuthenticated(cookies);
  const result = await getAuthedJson<{
    numbers: any[];
    memberProfile: any;
    orgSettings: any;
    organizations: any[];
  }>(`/api/v2/${params.subdomain}/me/context`, user.idToken, fetch);
  if (!result.ok) {
    // Server returns 303→/org when user isn't a member of this subdomain. The
    // SSR fetch follows the redirect, which 404s because /org is a SvelteKit
    // route (not a Phoenix route). Bounce the browser to /org so it can pick
    // or create an org through the web-app.
    if (result.status === 404 || result.status === 403 || result.status === 401) {
      throw redirect(303, '/org');
    }
    throw new Error(result.error);
  }

  const { numbers, memberProfile: member, orgSettings, organizations } = result.data;

  const walletBalance = convertWalletBalanceToDollars(orgSettings!.walletBalance);
  const showLowBalanceAlert = Number(walletBalance) <= orgSettings!.alertThresholdBalance * 1000000;
  if (!member) {
    throw Error('Member not found');
  }

  if (!url.searchParams.has('redirected')) {
    if (!orgSettings!.isActive) {
      // TODO redirect to inactive page
    }
    if (orgSettings!.walletBalance <= 0) {
      if (member!.role == 'ADMIN') {
        throw redirect(302, `/app/${params.subdomain}/settings/billing/balance?redirected=true`);
      } else {
        throw redirect(302, `/app/${params.subdomain}/payments/recharge-wallet?redirected=true`);
      }
    }
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
    showLowBalanceAlert,
    walletBalance,
  };
};
