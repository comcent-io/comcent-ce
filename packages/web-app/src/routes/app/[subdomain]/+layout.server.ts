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
