<script lang="ts">
  import type { LayoutData } from './$types';
  import DialerWidget from '$lib/components/DialerWidget/DialerWidget.svelte';
  import { browser } from '$app/environment';
  import { publicAppBaseUrl, publicSipUserRootDomain, publicSipWsUrl } from '$lib/publicConfig';
  import { page } from '$app/state';
  import { routeParam } from '$lib/routeParam';
  import SideBarLink from './SideBarLink.svelte';
  import SideBarGroup from './SideBarGroup.svelte';
  import { Toaster } from '$lib/toast';
  import CloseMenuIcon from '$lib/components/Icons/CloseMenuIcon.svelte';
  import MenuBurgerIcon from '$lib/components/Icons/MenuBurgerIcon.svelte';
  import UserAvatar from '$lib/components/UserAvatar.svelte';
  import SideBarIcon from './SideBarIcon.svelte';
  import { clickOutside } from '$lib/clickOutside';
  import { afterNavigate, goto } from '$app/navigation';
  import { onMount, tick } from 'svelte';
  import { getIdTokenFromCookie } from '$lib/getIdTokenFromCookie';
  import { logout } from '$lib/session';

  interface Props {
    data: LayoutData;
    children?: import('svelte').Snippet;
  }

  let { data, children }: Props = $props();

  let isUserMenuOpen = $state(false);
  let isMinScreenSidebarOpen = $state(false);
  let walletBalance = 0;
  let fetchingBalance = false;
  let showWalletBalance = false;
  const subdomain = routeParam('subdomain');
  let selectedOrganization = $state(subdomain);
  // svelte-ignore state_referenced_locally
  let showLowBalanceAlert = data.showLowBalanceAlert;
  let showSwitchOrgMenu = $state(false);
  let dialerWidget: any = $state(null);
  const authToken = browser ? getIdTokenFromCookie() || '' : '';

  onMount(async () => {
    await tick();
    window.dialerWidget = dialerWidget;
  });

  // The user menu closes once a link in it has taken you somewhere
  // (closing it in the link's own click handler could cancel the click).
  afterNavigate(() => {
    isUserMenuOpen = false;
  });

  function closeLowBalanceWarning() {
    showLowBalanceAlert = false;
  }

  async function toggleWalletBalance() {
    if (!showWalletBalance) {
      await getWalletBalance();
    }
    showWalletBalance = !showWalletBalance;
  }

  async function getWalletBalance() {
    try {
      fetchingBalance = true;
      const response = await fetch(`/api/v2/${page.params.subdomain}/billing/balance`);
      if (!response.ok) {
        console.error('Failed to get wallet balance.');
        return 0;
      } else {
        const data = await response.json();
        walletBalance = data.walletBalance;
      }
    } catch (error) {
      return 0;
    } finally {
      fetchingBalance = false;
    }
  }

  function handleSelectChange() {
    showSwitchOrgMenu = false;
    goto(`/app/${selectedOrganization}`, { invalidateAll: true });
  }

  let origin: string | null = $state(null);
  if (browser) {
    origin = window.location.origin;
  }
  const configuredAppBaseUrl = publicAppBaseUrl;
  const configuredSipWsUrl = publicSipWsUrl;
</script>

<div class="antialiased bg-gray-50 dark:bg-gray-900">
  <nav
    class="bg-white border-b border-gray-200 px-4 py-2.5 dark:bg-gray-800 dark:border-gray-700 fixed left-0 right-0 top-0 z-50"
  >
    <div class="flex flex-wrap justify-between items-center">
      <div class="flex justify-start items-center">
        <button
          class="p-2 mr-2 text-gray-600 rounded-lg cursor-pointer md:hidden hover:text-gray-900 hover:bg-gray-100 focus:bg-gray-100 dark:focus:bg-gray-700 focus:ring-2 focus:ring-gray-100 dark:focus:ring-gray-700 dark:text-gray-400 dark:hover:bg-gray-700 dark:hover:text-white"
          onclick={() => (isMinScreenSidebarOpen = !isMinScreenSidebarOpen)}
        >
          {#if isMinScreenSidebarOpen}
            <CloseMenuIcon />
          {:else}
            <MenuBurgerIcon />
          {/if}
          <span class="sr-only">Toggle sidebar</span>
        </button>
        <a href="/" class="flex items-center justify-between mr-4">
          <img
            class="dark:hidden mb-4 w-36 lg:mb-0 rounded-lg"
            src="/comcent-logo-dark.png"
            alt="comcent-logo-dark"
          />
          <img
            class="hidden dark:inline mb-4 w-36 lg:mb-0 rounded-lg"
            src="/comcent-logo-light.png"
            alt="comcent-logo-light"
          />
        </a>
      </div>
      <!-- Low-balance alert is EE-only (no wallet/billing in CE). -->

      <!-- Main content and other items remain unchanged -->

      <div class="flex items-center gap-2 lg:order-2">
        <!-- Wallet balance indicator is EE-only -->

        <div
          class="relative"
          use:clickOutside={() => {
            isUserMenuOpen = false;
          }}
        >
          <button
            type="button"
            class="flex items-center gap-2 rounded-xl p-1 text-sm font-medium text-slate-700 hover:bg-slate-100 dark:text-slate-200 dark:hover:bg-slate-700 md:pe-2"
            aria-expanded={isUserMenuOpen}
            onclick={() => (isUserMenuOpen = !isUserMenuOpen)}
          >
            <span class="sr-only">Open user menu</span>
            <UserAvatar picture={data.user.picture} name={data.user.name} email={data.user.email} />
            <span class="hidden max-w-40 truncate md:inline">{data.user.name}</span>
            <svg
              class="hidden h-4 w-4 text-slate-400 md:block"
              viewBox="0 0 20 20"
              fill="currentColor"
              aria-hidden="true"
            >
              <path
                fill-rule="evenodd"
                d="M5.23 7.21a.75.75 0 0 1 1.06.02L10 11.17l3.71-3.94a.75.75 0 1 1 1.08 1.04l-4.25 4.5a.75.75 0 0 1-1.08 0l-4.25-4.5a.75.75 0 0 1 .02-1.06Z"
                clip-rule="evenodd"
              />
            </svg>
          </button>
          {#if isUserMenuOpen}
            <div
              id="dropdown"
              class="absolute right-0 z-50 mt-2 w-64 overflow-hidden rounded-xl border border-slate-200 bg-white shadow-lg dark:border-slate-700 dark:bg-slate-800"
            >
              <div
                class="flex items-center gap-3 border-b border-slate-200 px-4 py-3 dark:border-slate-700"
              >
                <UserAvatar
                  picture={data.user.picture}
                  name={data.user.name}
                  email={data.user.email}
                />
                <div class="min-w-0">
                  <p class="truncate text-sm font-semibold text-slate-900 dark:text-white">
                    {data.user.name}
                  </p>
                  <p class="truncate text-xs text-slate-500 dark:text-slate-400">
                    {data.user.email}
                  </p>
                </div>
              </div>
              <ul class="p-1.5 text-sm">
                <li>
                  <a
                    href={`${data.basePath}/members/me`}
                    class="flex items-center gap-3 rounded-lg px-3 py-2 text-slate-700 hover:bg-slate-100 dark:text-slate-200 dark:hover:bg-slate-700"
                  >
                    <SideBarIcon name="members" class="text-slate-400" />
                    My profile
                  </a>
                </li>
              </ul>
              <div class="border-t border-slate-200 p-1.5 text-sm dark:border-slate-700">
                <button
                  type="button"
                  onclick={logout}
                  class="flex w-full items-center gap-3 rounded-lg px-3 py-2 text-left text-red-600 hover:bg-red-50 dark:text-red-400 dark:hover:bg-red-900/30"
                >
                  <svg
                    class="h-5 w-5"
                    fill="none"
                    viewBox="0 0 24 24"
                    stroke-width="1.5"
                    stroke="currentColor"
                    aria-hidden="true"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      d="M15.75 9V5.25A2.25 2.25 0 0 0 13.5 3h-6a2.25 2.25 0 0 0-2.25 2.25v13.5A2.25 2.25 0 0 0 7.5 21h6a2.25 2.25 0 0 0 2.25-2.25V15m3 0 3-3m0 0-3-3m3 3H9"
                    />
                  </svg>
                  Logout
                </button>
              </div>
            </div>
          {/if}
        </div>
      </div>
    </div>
  </nav>

  <!-- Sidebar -->

  <aside
    class="fixed top-0 left-0 z-40 w-64 h-screen pt-14 transition-transform {isMinScreenSidebarOpen
      ? ''
      : '-translate-x-full'} bg-white border-r border-slate-200 md:translate-x-0 dark:bg-slate-800 dark:border-slate-700"
    aria-label="Sidenav"
  >
    <div class="overflow-y-auto py-5 px-3 h-full">
      <ul class="space-y-1">
        <SideBarLink
          title="Dashboard"
          href={data.basePath}
          icon="dashboard"
          active={page.url.pathname === data.basePath}
        />
        <SideBarLink title="Promises" href={`${data.basePath}/promises`} icon="promises" />
        {#if data.member.role === 'ADMIN'}
          <SideBarLink title="Call Story" href={`${data.basePath}/call-story`} icon="callStory" />
          <SideBarLink title="Members" href={`${data.basePath}/members`} icon="members" />
          <SideBarLink title="Sip Trunk" href={`${data.basePath}/sip-trunks`} icon="sipTrunk" />
          <SideBarLink title="Presence" href={`${data.basePath}/presence`} icon="presence" />
          <SideBarLink
            title="Daily Summary"
            href={`${data.basePath}/daily-summary`}
            icon="dailySummary"
          />
          <SideBarLink title="Numbers" href={`${data.basePath}/numbers`} icon="numbers" />
          <SideBarLink title="Queues" href={`${data.basePath}/queues`} icon="queues" />
          <SideBarLink title="Voice Bots" href={`${data.basePath}/voice-bots`} icon="voiceBots" />
        {/if}
      </ul>
      {#if data.member.role === 'ADMIN'}
        <ul class="pt-4 mt-4 space-y-1 border-t border-slate-200 dark:border-slate-700">
          <SideBarLink
            title="Settings"
            href={`${data.basePath}/settings/webhooks`}
            icon="settings"
            active={page.url.pathname.startsWith(`${data.basePath}/settings/`)}
          />
        </ul>
        <ul class="pt-4 mt-4 border-t border-slate-200 dark:border-slate-700">
          <SideBarGroup
            title="Switch Organization"
            icon="organization"
            bind:open={showSwitchOrgMenu}
          >
            <div class="mt-2 space-y-2 px-1">
              <select
                class="block w-full rounded-xl border border-slate-300 bg-white px-3 py-2 text-sm text-slate-900 focus:border-cyan-500 focus:outline-none focus:ring-0 dark:border-slate-600 dark:bg-slate-900 dark:text-white"
                name="switchOrganization"
                id="switchOrganization"
                bind:value={selectedOrganization}
                onchange={handleSelectChange}
              >
                {#each data.organizations as organization}
                  <option value={organization.subdomain}>
                    {organization.name}
                  </option>
                {/each}
              </select>
              <a
                id="#createOrganization"
                href={'/org/create'}
                class="block w-full rounded-xl bg-slate-900 px-4 py-2 text-center text-sm font-semibold text-white hover:bg-slate-700 dark:bg-cyan-500 dark:text-slate-950 dark:hover:bg-cyan-400"
              >
                Create Organization
              </a>
            </div>
          </SideBarGroup>
        </ul>
      {/if}
    </div>
  </aside>

  <!-- pb-24 leaves room to scroll the last row of any page clear of the dialer
       widget docked in the bottom-right corner; without it the widget covers
       that row's action buttons and they cannot be clicked. -->
  <main class="p-4 md:ml-64 h-auto pt-20 pb-24">
    {@render children?.()}
  </main>

  <DialerWidget
    subdomain={data.sipConfig.subdomain}
    username={data.sipConfig.username}
    password={data.sipConfig.sipPassword}
    displayName={data.user?.name ?? 'Internal'}
    numbers={data.numbers}
    {authToken}
    {origin}
    appBaseUrl={configuredAppBaseUrl || origin}
    sipWsUrl={configuredSipWsUrl}
    sipDomain={publicSipUserRootDomain}
    bind:this={dialerWidget}
  />

  <Toaster />
</div>
