<script lang="ts">
  import type { LayoutData } from './$types';
  import DialerWidget from '$lib/components/DialerWidget/DialerWidget.svelte';
  import { browser } from '$app/environment';
  import { env } from '$env/dynamic/public';
  import { page } from '$app/stores';
  import PieIcon from '$lib/components/Icons/PieIcon.svelte';
  import SteerIcon from '$lib/components/Icons/SteerIcon.svelte';
  import SideBarLink from './SideBarLink.svelte';
  import { Toaster } from 'svelte-french-toast';
  import DollarIcon from '$lib/components/Icons/DollarIcon.svelte';
  import CloseMenuIcon from '$lib/components/Icons/CloseMenuIcon.svelte';
  import MenuBurgerIcon from '$lib/components/Icons/MenuBurgerIcon.svelte';
  import Button from '$lib/components/Button.svelte';
  import { clickOutside } from '$lib/clickOutside';
  import { goto } from '$app/navigation';
  import AngleRight from '$lib/components/Icons/AngleRight.svelte';
  import AngleDown from '$lib/components/Icons/AngleDown.svelte';
  import { onMount, tick } from 'svelte';
  import { getIdTokenFromCookie } from '$lib/getIdTokenFromCookie';

  export let data: LayoutData;

  let isUserMenuOpen = false;
  let isMinScreenSidebarOpen = false;
  let walletBalance = 0;
  let fetchingBalance = false;
  let showWalletBalance = false;
  const subdomain = $page.params.subdomain;
  let selectedOrganization = subdomain;
  let showLowBalanceAlert = data.showLowBalanceAlert;
  let showSwitchOrgMenu = false;
  let showCampaignGroups = false;
  let dialerWidget: any = null;
  let authToken = '';
  $: authToken = browser ? getIdTokenFromCookie() || '' : '';

  onMount(async () => {
    await tick();
    window.dialerWidget = dialerWidget;
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
      const response = await fetch(`/api/v2/${$page.params.subdomain}/billing/balance`);
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
    localStorage.setItem('selectedSubdomain', selectedOrganization);
  }

  let origin: string | null = null;
  if (browser) {
    origin = window.location.origin;
  }
  const configuredAppBaseUrl = env.PUBLIC_APP_BASE_URL || null;
  const configuredSipWsUrl = env.PUBLIC_SIP_WS_URL || null;
</script>

<div class="antialiased bg-gray-50 dark:bg-gray-900">
  <nav
    class="bg-white border-b border-gray-200 px-4 py-2.5 dark:bg-gray-800 dark:border-gray-700 fixed left-0 right-0 top-0 z-50"
  >
    <div class="flex flex-wrap justify-between items-center">
      <div class="flex justify-start items-center">
        <button
          class="p-2 mr-2 text-gray-600 rounded-lg cursor-pointer md:hidden hover:text-gray-900 hover:bg-gray-100 focus:bg-gray-100 dark:focus:bg-gray-700 focus:ring-2 focus:ring-gray-100 dark:focus:ring-gray-700 dark:text-gray-400 dark:hover:bg-gray-700 dark:hover:text-white"
          on:click={() => (isMinScreenSidebarOpen = !isMinScreenSidebarOpen)}
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
      {#if showLowBalanceAlert}
        <div
          class="fixed mt-1 top-0 left-1/2 transform -translate-x-1/2 bg-yellow-100 border-yellow-500 text-yellow-700 px-4 py-2 z-50 rounded-lg"
          style="width: auto; max-width: calc(100% - 2rem);"
          role="alert"
        >
          <div class="flex items-center justify-between">
            <p class="text-sm font-bold">
              Low Wallet Balance!! Please top up to continue enjoying our services.
              {#if data.member.role === 'ADMIN'}
                <a
                  href={`${data.basePath}/settings/billing/balance`}
                  class="text-blue-500 hover:text-blue-700"
                >
                  Click here to top up
                </a>
              {:else}
                Please check with your admins.
              {/if}
            </p>
            <button
              type="button"
              class="ml-4 text-yellow-500 hover:text-yellow-600 focus:outline-none focus:ring-2 focus:ring-yellow-500 rounded-lg text-sm p-1.5"
              aria-label="close"
              on:click={closeLowBalanceWarning}
            >
              <span class="text-lg">&times;</span>
            </button>
          </div>
        </div>
      {/if}

      <!-- Main content and other items remain unchanged -->

      <div class="flex items-center lg:order-2">
        {#if data.member.role === 'ADMIN'}
          <div
            use:clickOutside={() => {
              showWalletBalance = false;
            }}
          >
            <Button
              type="button"
              on:click={toggleWalletBalance}
              progress={fetchingBalance}
              class="p-2 mr-1 text-gray-500 rounded-lg hover:text-gray-900 hover:bg-gray-100 dark:text-gray-400 dark:hover:text-white dark:hover:bg-gray-700 focus:ring-4 focus:ring-gray-300 dark:focus:ring-gray-600"
            >
              <span class="sr-only">View balance</span>
              <DollarIcon />
            </Button>
          </div>
          {#if showWalletBalance}
            <div
              class="absolute top-8 right-5 overflow-hidden z-50 my-4 max-w-sm text-base list-none bg-white rounded divide-y divide-gray-100 shadow-lg dark:divide-gray-600 dark:bg-gray-700"
              id="wallet-balance-display"
            >
              <div
                class="block py-2 px-4 text-base font-medium text-center text-gray-700 bg-gray-50 dark:bg-gray-600 dark:text-gray-300"
              >
                Wallet Balance
              </div>
              <div class="flex-shrink-0">
                <div
                  class="block py-2 px-4 text-base font-medium text-center text-white bg-gray-700 rounded-full border border-white dark:border-gray-700"
                >
                  <p>USD {walletBalance}</p>
                </div>
              </div>
            </div>
          {/if}
        {/if}
        <div class="relative">
          <button
            type="button"
            class="flex mx-3 text-sm bg-gray-800 rounded-full md:mr-0 focus:ring-4 focus:ring-gray-300 dark:focus:ring-gray-600"
            aria-expanded="false"
            on:click={() => (isUserMenuOpen = !isUserMenuOpen)}
          >
            <span class="sr-only">Open user menu</span>
            <img class="w-8 h-8 rounded-full" src={data.user.picture} alt="user profile" />
          </button>
          <!-- Dropdown menu -->
          <div
            class="absolute right-1 z-50 my-4 w-56 text-base list-none bg-white rounded divide-y divide-gray-100 shadow dark:bg-gray-700 dark:divide-gray-600"
            id="dropdown"
            class:hidden={!isUserMenuOpen}
          >
            <div class="py-3 px-4">
              <span class="block text-sm font-semibold text-gray-900 dark:text-white">
                {data.user.name}
              </span>
              <span class="block text-sm text-gray-900 truncate dark:text-white">
                {data.user.email}
              </span>
            </div>
            <ul class="py-1 text-gray-700 dark:text-gray-300" aria-labelledby="dropdown">
              <li>
                <a
                  href={`${data.basePath}/members/me`}
                  class="block py-2 px-4 text-sm hover:bg-gray-100 dark:hover:bg-gray-600 dark:text-gray-400 dark:hover:text-white"
                >
                  My profile
                </a>
              </li>
            </ul>
            <ul class="py-1 text-gray-700 dark:text-gray-300" aria-labelledby="dropdown">
              <li>
                <form method="POST" action="/logout">
                  <button
                    type="submit"
                    class="block w-full text-left py-2 px-4 text-sm hover:bg-gray-100 dark:hover:bg-gray-600 dark:hover:text-white"
                  >
                    Logout
                  </button>
                </form>
              </li>
            </ul>
          </div>
        </div>
      </div>
    </div>
  </nav>

  <!-- Sidebar -->

  <aside
    class="fixed top-0 left-0 z-40 w-64 h-screen pt-14 transition-transform {isMinScreenSidebarOpen
      ? ''
      : '-translate-x-full'} bg-white border-r border-gray-200 md:translate-x-0 dark:bg-gray-800 dark:border-gray-700"
    aria-label="Sidenav"
  >
    <div class="overflow-y-auto py-5 px-3 h-full bg-white dark:bg-gray-800">
      <ul class="space-y-2">
        <SideBarLink title="Dashboard" href={`${data.basePath}`} icon={PieIcon} />
        <SideBarLink title="Promises" href={`${data.basePath}/promises`} icon={PieIcon} />
        {#if data.member.role === 'ADMIN'}
          <SideBarLink title="Call Story" href={`${data.basePath}/call-story`} icon={PieIcon} />
          <SideBarLink title="Members" href={`${data.basePath}/members`} icon={PieIcon} />
          <SideBarLink title="Sip Trunk" href={`${data.basePath}/sip-trunks`} icon={PieIcon} />
          <SideBarLink title="Presence" href={`${data.basePath}/presence`} icon={PieIcon} />
          <SideBarLink
            title="Daily Summary"
            href={`${data.basePath}/daily-summary`}
            icon={PieIcon}
          />
          <SideBarLink title="Numbers" href={`${data.basePath}/numbers`} icon={PieIcon} />
          <SideBarLink title="Queues" href={`${data.basePath}/queues`} icon={PieIcon} />
          <SideBarLink title="Voice Bots" href={`${data.basePath}/voice-bots`} icon={PieIcon} />
          <button
            class="flex w-full items-center p-2 text-base font-medium text-gray-900 rounded-lg dark:text-white hover:bg-gray-100 dark:hover:bg-gray-700 group mt-4"
            on:click={() => {
              showCampaignGroups = !showCampaignGroups;
            }}
          >
            <PieIcon />
            <span class="ml-3">Campaign</span>
            <span class="ml-20 mt-1">
              {#if showCampaignGroups}
                <AngleDown />
              {:else}
                <AngleRight />
              {/if}
            </span>
          </button>
          {#if showCampaignGroups}
            <a
              href={`${data.basePath}/campaign-groups`}
              class="flex w-full items-center p-2 text-base font-medium text-gray-900 rounded-lg dark:text-white hover:bg-gray-100 dark:hover:bg-gray-700 group ml-6"
            >
              Campaign Groups
            </a>

            <a
              href={`${data.basePath}/campaign-scripts`}
              class="flex w-full items-center p-2 text-base font-medium text-gray-900 rounded-lg dark:text-white hover:bg-gray-100 dark:hover:bg-gray-700 group ml-6"
            >
              Campaign Scripts
            </a>
          {/if}
        {/if}
      </ul>
      <ul class="pt-5 mt-5 space-y-2 border-t border-gray-200 dark:border-gray-700">
        {#if data.member.role === 'ADMIN'}
          <SideBarLink
            title="Settings"
            href={`${data.basePath}/settings/webhooks`}
            icon={SteerIcon}
          />
          <SideBarLink
            title="Billing"
            href={`${data.basePath}/settings/billing/balance`}
            icon={SteerIcon}
          />
          <SideBarLink
            title="Compliance"
            href={`${data.basePath}/settings/compliance/search`}
            icon={SteerIcon}
          />
          <hr class="dark:border-gray-700" />
          <button
            class="flex w-full items-center p-2 text-base font-medium text-gray-900 rounded-lg dark:text-white hover:bg-gray-100 dark:hover:bg-gray-700 group mt-4"
            on:click={() => {
              showSwitchOrgMenu = !showSwitchOrgMenu;
            }}
          >
            <SteerIcon />
            <span class="ml-3">Switch Organization</span>
          </button>
          <div
            class="items-center text-base font-medium text-gray-900 rounded-lg dark:text-white group"
          >
            {#if showSwitchOrgMenu}
              <select
                class="w-full bg-gray-50 border border-gray-300 text-gray-900 text-sm rounded-lg focus:ring-blue-500 focus:border-blue-500 block p-2 dark:bg-gray-700 dark:border-gray-600 dark:placeholder-gray-400 dark:text-white dark:focus:ring-blue-500 dark:focus:border-blue-500 mb-3"
                name="switchOrganization"
                id="switchOrganization"
                bind:value={selectedOrganization}
                on:change={handleSelectChange}
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
                class="text-white bg-blue-700 hover:bg-blue-800 focus:ring-4 focus:outline-none focus:ring-blue-300 font-medium rounded-lg text-sm w-full px-5 py-2.5 text-center dark:bg-blue-600 dark:hover:bg-blue-700 dark:focus:ring-blue-800 mt-2"
              >
                Create Organization
              </a>
            {/if}
          </div>
        {/if}
      </ul>
    </div>
  </aside>

  <main class="p-4 md:ml-64 h-auto pt-20">
    <slot />
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
    bind:this={dialerWidget}
  />

  <Toaster />
</div>
