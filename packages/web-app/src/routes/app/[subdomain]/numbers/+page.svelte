<script lang="ts">
  import { untrack } from 'svelte';
  import Pagination from '$lib/components/Pagination.svelte';
  import { page } from '$app/state';
  import { routeParam } from '$lib/routeParam';
  import ConfirmDialog from '$lib/components/ConfirmDialog.svelte';
  import Button from '$lib/components/Button.svelte';
  import ErrorMessage from '$lib/components/ErrorMessage.svelte';
  import Pill from '$lib/components/Pill.svelte';
  import Table from '$lib/components/Table.svelte';
  import EmptyState from '$lib/components/form/EmptyState.svelte';
  import PageHeader from '$lib/components/form/PageHeader.svelte';
  import SecondaryButton from '$lib/components/form/SecondaryButton.svelte';
  import { goto } from '$app/navigation';
  import { getJson, postJson } from '$lib/http';
  import {
    listConnections,
    statusLabel,
    statusTone,
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
  let isLoading = $state(true);
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

<PageHeader
  title="Numbers"
  description="The phone numbers your customers call and your team calls from. Choose where each number's calls go, and which one shows on outgoing calls."
>
  {#snippet actions()}
    <div class="relative">
      <Button
        id="add-new-no-btn"
        aria-haspopup="true"
        aria-expanded={showChooser}
        onclick={() => (showChooser = !showChooser)}
      >
        Add numbers
      </Button>

      {#if showChooser}
        {@render chooser()}
      {/if}
    </div>
  {/snippet}
</PageHeader>

{#if connectionsLoaded && connections.length > 0}
  <!-- Connections strip: which provider accounts are linked and whether they
       still work. A rejected key is why calls stop, so it belongs above the
       numbers rather than buried on a settings page. -->
  <div class="mb-4 flex flex-wrap gap-3">
    {#each connections as c}
      <div
        class="flex items-center gap-3 rounded-lg border border-gray-200 bg-white px-4 py-2 shadow-sm dark:border-gray-700 dark:bg-gray-800"
      >
        <div>
          <div class="font-medium text-gray-900 dark:text-white">{c.label}</div>
          <div class="text-xs text-gray-500 dark:text-gray-400">
            {c.provider} · {c.externalAccountSid.slice(0, 10)}…
          </div>
        </div>
        <Pill tone={statusTone(c.status)} dot>{statusLabel(c.status)}</Pill>
        {#if c.status !== 'unmanaged'}
          <a
            href={`${data.basePath}/numbers/connections/${c.id}/import`}
            class="text-sm font-medium text-cyan-700 hover:underline dark:text-cyan-400"
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

<!-- The Add numbers menu: import from a linked account, link a Twilio
     account, or set up a number on any other carrier's trunk. -->
{#snippet chooser()}
  <div
    class="absolute right-0 z-10 mt-2 w-80 overflow-hidden rounded-lg border border-gray-200 bg-white text-left shadow-lg dark:border-gray-700 dark:bg-gray-800"
  >
    {#each connections.filter((c) => c.status !== 'unmanaged') as c}
      <a
        href={`${data.basePath}/numbers/connections/${c.id}/import`}
        class="block border-b border-gray-100 px-4 py-3 hover:bg-gray-50 dark:border-gray-700 dark:hover:bg-gray-700"
      >
        <div class="font-medium text-gray-900 dark:text-white">Import from {c.label}</div>
        <div class="text-xs text-gray-500 dark:text-gray-400">
          Pick from the numbers already in this account
        </div>
      </a>
    {/each}

    <a
      href={`${data.basePath}/numbers/connect`}
      class="block border-b border-gray-100 px-4 py-3 hover:bg-gray-50 dark:border-gray-700 dark:hover:bg-gray-700"
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
{/snippet}

{#if errorMessage}
  <ErrorMessage error={{ message: errorMessage, formErrors: [] }} />
{/if}

{#if isDeletePopUp}
  <ConfirmDialog
    message={`Are you sure you want to delete the ${numberToBeDeleted?.name}?`}
    onCancel={toggleDeletePopUp}
    onConfirm={handleSubmit}
  />
{/if}

<Table
  columns={['Name', 'Number', 'SIP trunk', 'Default outgoing', { label: 'Actions', srOnly: true }]}
  loading={isLoading}
  isEmpty={numbers.length === 0}
>
  {#snippet empty()}
    <EmptyState
      title="No numbers yet"
      description="Add a number so customers can call you and your team can call out. Use Add numbers above to import from Twilio or set one up on any carrier."
    />
  {/snippet}
  {#each numbers as number (number.id)}
    <tr>
      <th scope="row" class="whitespace-nowrap font-medium text-gray-900 dark:text-white">
        {number.name}
      </th>
      <td class="whitespace-nowrap tabular-nums">{number.number}</td>
      <td>{number.sipTrunk.name}</td>
      <td>
        {#if number.isDefaultOutboundNumber}
          <Pill tone="green">Yes</Pill>
        {/if}
      </td>
      <td>
        <div class="flex items-center justify-end gap-4">
          <SecondaryButton size="sm" href={`${data.basePath}/numbers/${number.id}/edit`}>
            Edit
          </SecondaryButton>
          <SecondaryButton size="sm" onclick={() => setOrgDefaultNumber(number.id)}>
            Set As Default
          </SecondaryButton>
          <SecondaryButton
            size="sm"
            tone="danger"
            onclick={() => {
              numberToBeDeleted = number;
              toggleDeletePopUp();
            }}
          >
            Delete
          </SecondaryButton>
        </div>
      </td>
    </tr>
  {/each}
</Table>

<Pagination
  baseUrl={`${data.basePath}/numbers`}
  {totalPages}
  {currentPage}
  {itemsPerPage}
  {totalCount}
/>
