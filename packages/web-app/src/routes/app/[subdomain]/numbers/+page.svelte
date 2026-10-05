<script lang="ts">
  import { untrack } from 'svelte';
  import Pagination from '$lib/components/Pagination.svelte';
  import { page } from '$app/state';
  import { routeParam } from '$lib/routeParam';
  import ConfirmDialog from '$lib/components/ConfirmDialog.svelte';
  import { goto } from '$app/navigation';
  import { getJson, postJson } from '$lib/http';
  import {
    listConnections,
    statusClass,
    statusLabel,
    type ProviderConnection,
  } from '$lib/providerConnections';

  let { data } = $props();

  interface numberToBeDeletedType {
    id: string;
    name: string;
  }

  let numberToBeDeleted: numberToBeDeletedType | null = $state(null);
  let numbers: any[] = $state([]);
  let currentPage = $state(1);
  let itemsPerPage = $state(10);
  let totalPages = $state(1);
  let totalCount = $state(0);
  let isLoading = $state(false);
  let latestRequestId = 0;
  let lastFetchKey = '';

  let connections: ProviderConnection[] = $state([]);
  let connectionsLoaded = $state(false);
  // The chooser is state-aware: with a connection already present the
  // first option becomes 'import more', not 'connect an account'. Making
  // someone re-run onboarding to add a second number would defeat the point.
  let showChooser = $state(false);

  async function loadConnections() {
    const result = await listConnections(subdomain);
    connectionsLoaded = true;
    if (result.ok) connections = result.data.providerConnections;
  }

  let isDeletePopUp = $state(false);
  let errorMessage = $state('');
  const subdomain = routeParam('subdomain');

  async function fetchNumbers() {
    const requestId = ++latestRequestId;
    const searchParams = page.url.searchParams;
    const requestedCurrentPage = parseInt(searchParams.get('page') || '1', 10);
    const requestedItemsPerPage = parseInt(searchParams.get('itemsPerPage') || '10', 10);
    isLoading = true;

    const result = await getJson<{
      numbers?: any[];
      totalPages?: number;
      currentPage?: number;
      itemsPerPage?: number;
      totalCount?: number;
    }>(
      `/api/v2/${subdomain}/numbers?page=${requestedCurrentPage}&itemsPerPage=${requestedItemsPerPage}`,
    );

    if (requestId !== latestRequestId) return;

    currentPage = requestedCurrentPage;
    itemsPerPage = requestedItemsPerPage;

    if (!result.ok) {
      numbers = [];
      totalPages = 1;
      totalCount = 0;
      isLoading = false;
      errorMessage = result.error;
      return;
    }

    numbers = result.data.numbers ?? [];
    totalPages = result.data.totalPages ?? 1;
    currentPage = result.data.currentPage ?? requestedCurrentPage;
    itemsPerPage = result.data.itemsPerPage ?? requestedItemsPerPage;
    totalCount = result.data.totalCount ?? 0;
    isLoading = false;
  }

  // Refetch when the URL or the org changes. The fetch itself is untracked,
  // so the state it reads and writes does not re-run this.
  $effect(() => {
    const nextFetchKey = `${page.url.search}|${page.params.subdomain}`;
    if (nextFetchKey !== lastFetchKey) {
      lastFetchKey = nextFetchKey;
      untrack(() => {
        fetchNumbers();
        loadConnections();
      });
    }
  });

  function toggleDeletePopUp() {
    isDeletePopUp = !isDeletePopUp;
  }

  async function handleSubmit() {
    errorMessage = '';
    try {
      const response = await fetch(`/api/v2/${subdomain}/numbers/${numberToBeDeleted?.id}`, {
        method: 'DELETE',
      });
      // Parsed defensively: this endpoint always sends JSON today, but a 204 or
      // an HTML error page from something in front of it would otherwise throw
      // here and report a delete that succeeded as a failure.
      const body = await response.json().catch(() => ({}));
      if (!response.ok) throw new Error(body.error ?? response.statusText);

      // A failed provider restore is not a failed delete: the number is gone
      // from Comcent either way, but it may still be pointing at a Comcent
      // trunk in their provider account, which they need to know about.
      if (body.providerRestored === false && body.warning) errorMessage = body.warning;

      // Refetch directly rather than navigating. goto() targets the URL we are
      // already on, so the reactive guard sees no change and never refetches --
      // which is why a deleted row used to stay on screen.
      await fetchNumbers();
      await loadConnections();
    } catch (error: any) {
      errorMessage = error.message;
    } finally {
      toggleDeletePopUp();
    }
  }

  async function setOrgDefaultNumber(id: string) {
    const result = await postJson(`/api/v2/${subdomain}/numbers/${id}/set-default`, {});
    if (!result.ok) {
      errorMessage = result.error;
      return;
    }

    errorMessage = '';
    await fetchNumbers();
  }
</script>

<h3 class="text-3xl font-bold dark:text-white">Numbers</h3>

{#if connectionsLoaded && connections.length > 0}
  <!-- Connections strip: which provider accounts are linked and whether they
       still work. A rejected key is why calls stop, so it belongs above the
       numbers rather than buried on a settings page. -->
  <div class="my-4 flex flex-wrap gap-3">
    {#each connections as c}
      <div
        class="flex items-center gap-3 rounded-lg border border-gray-200 dark:border-gray-700 px-4 py-2 bg-white dark:bg-gray-800"
      >
        <div>
          <div class="font-medium text-gray-900 dark:text-white">{c.label}</div>
          <div class="text-xs text-gray-500 dark:text-gray-400">
            {c.provider} · {c.externalAccountSid.slice(0, 10)}…
          </div>
        </div>
        <span class="text-xs px-2 py-0.5 rounded {statusClass(c.status)}">
          {statusLabel(c.status)}
        </span>
        {#if c.status !== 'unmanaged'}
          <a
            href={`${data.basePath}/numbers/connections/${c.id}/import`}
            class="text-sm text-blue-700 hover:underline dark:text-blue-400"
          >
            Import more
          </a>
        {/if}
        <a
          href={`${data.basePath}/numbers/connections/${c.id}`}
          class="text-sm text-gray-600 hover:underline dark:text-gray-400"
        >
          Manage
        </a>
      </div>
    {/each}
  </div>
{/if}

<div class="my-4 relative inline-block">
  <button
    id="add-new-no-btn"
    onclick={() => (showChooser = !showChooser)}
    class="text-white bg-blue-700 hover:bg-blue-800 focus:ring-4 focus:ring-blue-300 font-medium rounded-lg text-sm px-5 py-2.5 mr-2 mb-2 dark:bg-blue-600 dark:hover:bg-blue-700 focus:outline-none dark:focus:ring-blue-800"
  >
    Add numbers
  </button>

  {#if showChooser}
    <div
      class="absolute z-10 mt-1 w-80 rounded-lg shadow-lg bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700"
    >
      {#each connections.filter((c) => c.status !== 'unmanaged') as c}
        <a
          href={`${data.basePath}/numbers/connections/${c.id}/import`}
          class="block px-4 py-3 hover:bg-gray-50 dark:hover:bg-gray-700 border-b border-gray-100 dark:border-gray-700"
        >
          <div class="font-medium text-gray-900 dark:text-white">Import from {c.label}</div>
          <div class="text-xs text-gray-500 dark:text-gray-400">
            Pick from the numbers already in this account
          </div>
        </a>
      {/each}

      <a
        href={`${data.basePath}/numbers/connect`}
        class="block px-4 py-3 hover:bg-gray-50 dark:hover:bg-gray-700 border-b border-gray-100 dark:border-gray-700"
      >
        <div class="font-medium text-gray-900 dark:text-white">
          {connections.length > 0 ? 'Connect another Twilio account' : 'Connect a Twilio account'}
        </div>
        <div class="text-xs text-gray-500 dark:text-gray-400">
          Use numbers you already own in Twilio
        </div>
      </a>

      <a
        href={`${data.basePath}/numbers/create`}
        class="block px-4 py-3 hover:bg-gray-50 dark:hover:bg-gray-700"
      >
        <div class="font-medium text-gray-900 dark:text-white">Other carrier / SIP trunk</div>
        <div class="text-xs text-gray-500 dark:text-gray-400">Configure a trunk manually</div>
      </a>
    </div>
  {/if}
</div>

{#if errorMessage}
  <div class="text-red-500 mb-4">
    {errorMessage}
  </div>
{/if}

{#if isDeletePopUp}
  <ConfirmDialog
    message={`Are you sure you want to delete the ${numberToBeDeleted?.name}?`}
    onCancel={toggleDeletePopUp}
    onConfirm={handleSubmit}
  />
{/if}

<div class="relative overflow-x-auto shadow-md sm:rounded-lg">
  <table class="w-full text-sm text-left text-gray-500 dark:text-gray-400">
    <thead class="text-xs text-gray-700 uppercase bg-gray-50 dark:bg-gray-700 dark:text-gray-400">
      <tr>
        <th scope="col" class="px-6 py-3">Name</th>
        <th scope="col" class="px-6 py-3">Number</th>
        <th scope="col" class="px-6 py-3">Trunk</th>
        <th scope="col" class="px-6 py-3">Default</th>
        <th scope="col" class="px-6 py-3">Action</th>
      </tr>
    </thead>
    <tbody>
      {#if isLoading}
        <tr class="bg-white border-b dark:bg-gray-900 dark:border-gray-700">
          <td class="px-6 py-4" colspan="5">Loading...</td>
        </tr>
      {:else}
        {#each numbers as number}
          <tr class="bg-white border-b dark:bg-gray-900 dark:border-gray-700">
            <th
              scope="row"
              class="px-6 py-4 font-medium text-gray-900 whitespace-nowrap dark:text-white"
            >
              {number.name}
            </th>
            <td class="px-6 py-4">
              {number.number}
            </td>
            <td class="px-6 py-4">
              {number.sipTrunk.name}
            </td>
            <td class="px-6 py-4">
              {number.isDefaultOutboundNumber ? 'Yes' : ''}
            </td>
            <td class="flex space-x-10 px-6 py-4">
              <a
                href={`${data.basePath}/numbers/${number.id}/edit`}
                class="font-medium text-blue-600 dark:text-blue-500 hover:underline"
              >
                Edit
              </a>

              <button
                type="button"
                onclick={() => setOrgDefaultNumber(number.id)}
                class="font-medium text-blue-600 dark:text-blue-500 hover:underline"
              >
                Set As Default
              </button>

              <button
                type="button"
                onclick={() => {
                  numberToBeDeleted = number;
                  toggleDeletePopUp();
                }}
                class="font-medium text-red-600 dark:text-red-500 hover:underline"
              >
                Delete
              </button>
            </td>
          </tr>
        {/each}
      {/if}
    </tbody>
  </table>
</div>

<Pagination
  baseUrl={`${data.basePath}/numbers`}
  {totalPages}
  {currentPage}
  {itemsPerPage}
  {totalCount}
/>
