<script lang="ts">
  import { page } from '$app/state';
  import { routeParam } from '$lib/routeParam';
  import { onMount } from 'svelte';
  import Pagination from '$lib/components/Pagination.svelte';
  import LabelFilter from '$lib/components/LabelFilter.svelte';
  import Button from '$lib/components/Button.svelte';
  import ErrorMessage from '$lib/components/ErrorMessage.svelte';
  import Pill from '$lib/components/Pill.svelte';
  import SearchIcon from '$lib/components/Icons/SearchIcon.svelte';
  import Table from '$lib/components/Table.svelte';
  import EmptyState from '$lib/components/form/EmptyState.svelte';
  import Input from '$lib/components/form/Input.svelte';
  import PageHeader from '$lib/components/form/PageHeader.svelte';
  import TableRow from './TableRow.svelte';

  let searchText = $state('');
  let callStories: any[] = $state([]);
  let totalPages = $state(0);
  let currentPage = $state(1);
  let itemsPerPage = $state(10);
  let totalCount = $state(0);
  let loading = $state(false);
  let error = $state('');

  // Label filter state
  let appliedLabels: any[] = $state([]); // Labels actually applied/sent to API
  let labelFilterComponent: any = $state();

  // Function to fetch call stories from API
  async function fetchCallStories() {
    loading = true;
    error = '';

    try {
      const params: any = {
        page: currentPage,
        itemsPerPage: itemsPerPage,
      };

      if (searchText && searchText.trim()) {
        params.search = searchText.trim();
      }

      // Add applied labels to params
      if (appliedLabels.length > 0) {
        // Send label IDs as comma-separated string or array (adjust based on your backend requirements)
        params.labels = appliedLabels.map((label) => label.id || label.name).join(',');
        // Alternative: Send as array if your backend expects an array
        // params.labels = appliedLabels.map((label) => label.id || label.name);
      }

      const queryString = new URLSearchParams(
        Object.entries(params).reduce((acc, [k, v]) => ({ ...acc, [k]: String(v) }), {}),
      ).toString();
      const response = await fetch(`/api/v2/${page.params.subdomain}/call-stories?${queryString}`);
      if (!response.ok) throw new Error((await response.json()).error ?? response.statusText);

      const data = await response.json();
      callStories = data.callStories || [];
      totalPages = data.totalPages || 0;
      currentPage = data.currentPage || 1;
      itemsPerPage = data.itemsPerPage || 10;
      totalCount = data.totalCount || 0;
    } catch (err) {
      console.error('Error fetching call stories:', err);
      error = 'Failed to load call stories';
      callStories = [];
    } finally {
      loading = false;
    }
  }

  // Handle pagination changes
  function handlePageChange(newPage: number) {
    currentPage = newPage;

    // Update URL with new page
    const url = new URL(window.location.href);
    url.searchParams.set('page', newPage.toString());
    window.history.pushState({}, '', url.toString());

    fetchCallStories();
  }

  // Handle items per page changes
  function handleItemsPerPageChange(newItemsPerPage: number) {
    itemsPerPage = newItemsPerPage;
    currentPage = 1; // Reset to first page when changing items per page

    // Update URL with new items per page and reset page
    const url = new URL(window.location.href);
    url.searchParams.set('itemsPerPage', newItemsPerPage.toString());
    url.searchParams.set('page', '1');
    window.history.pushState({}, '', url.toString());

    fetchCallStories();
  }

  async function handleSearch(event: Event) {
    event.preventDefault();

    // Update URL with search parameter
    const url = new URL(window.location.href);
    if (searchText.trim()) {
      url.searchParams.set('q', searchText.trim());
    } else {
      url.searchParams.delete('q');
    }
    url.searchParams.set('page', '1'); // Reset to first page
    window.history.pushState({}, '', url.toString());

    // Reset to first page when searching
    currentPage = 1;
    fetchCallStories();
  }

  function clearSearch() {
    searchText = '';

    // Update URL to remove search parameter
    const url = new URL(window.location.href);
    url.searchParams.delete('q');
    url.searchParams.set('page', '1'); // Reset to first page
    window.history.pushState({}, '', url.toString());

    // Reset to first page and fetch without search
    currentPage = 1;
    fetchCallStories();
  }

  // Handle label filter apply event
  function handleLabelApply(labels: any[]) {
    appliedLabels = [...labels];

    // Update URL with applied labels and reset to first page
    currentPage = 1;
    const url = new URL(window.location.href);
    url.searchParams.set('page', '1');
    const labelIds = appliedLabels.map((l) => l.id || l.name).join(',');
    if (labelIds) {
      url.searchParams.set('labels', labelIds);
    } else {
      url.searchParams.delete('labels');
    }
    window.history.pushState({}, '', url.toString());
    fetchCallStories();
  }

  // Handle label filter clear event
  function handleLabelClear() {
    appliedLabels = [];

    // Update URL and reset to first page
    currentPage = 1;
    const url = new URL(window.location.href);
    url.searchParams.set('page', '1');
    url.searchParams.delete('labels');
    window.history.pushState({}, '', url.toString());
    fetchCallStories();
  }

  onMount(async () => {
    // Get initial pagination params from URL
    const urlParams = new URLSearchParams(window.location.search);
    const pageParam = parseInt(urlParams.get('page') || '1', 10);
    const itemsPerPageParam = parseInt(urlParams.get('itemsPerPage') || '10', 10);
    const searchParam = urlParams.get('q') || '';
    const labelsParam = urlParams.get('labels') || '';

    currentPage = pageParam;
    itemsPerPage = itemsPerPageParam;
    searchText = searchParam;

    // Initialize label filter component with URL params
    if (labelFilterComponent && labelsParam) {
      const labelIds = labelsParam.split(',').filter((id) => id.trim());
      const restoredLabels = await labelFilterComponent.initializeLabels(labelIds);
      appliedLabels = [...restoredLabels];
    }

    // Fetch call stories with all filters applied
    fetchCallStories();
  });
</script>

<PageHeader
  title="Call Story"
  description="Every call your team handled, with its recording, transcript and AI insights. Open a call to see it all."
/>

{#if error}
  <ErrorMessage error={{ message: error, formErrors: [] }} />
{/if}

<form class="mb-4 flex flex-wrap items-center gap-2" onsubmit={handleSearch}>
  <label for="call-search" class="sr-only">Search calls</label>
  <div class="relative min-w-64 flex-1">
    <span
      class="pointer-events-none absolute inset-y-0 start-0 flex items-center ps-3 text-gray-500 dark:text-gray-400"
    >
      <SearchIcon />
    </span>
    <Input
      id="call-search"
      type="search"
      bind:value={searchText}
      placeholder="Search what was said, e.g. refund or invoice"
      class="ps-10"
      oninput={() => {
        // Emptying the box (or its ✕) shows every call again.
        if (!searchText) clearSearch();
      }}
    />
  </div>
  <Button type="submit">Search</Button>
  <LabelFilter
    bind:this={labelFilterComponent}
    subdomain={routeParam('subdomain')}
    appliedCount={appliedLabels.length}
    onApply={handleLabelApply}
    onClear={handleLabelClear}
  />
</form>

{#if appliedLabels.length > 0}
  <div class="mb-4 flex flex-wrap items-center gap-2">
    <span class="text-sm text-gray-500 dark:text-gray-400">Showing calls labelled</span>
    {#each appliedLabels as label (label.id || label.name)}
      <Pill tone="cyan">{label.name}</Pill>
    {/each}
  </div>
{/if}

<Table
  columns={[
    'Date & time',
    'Direction',
    'Caller',
    'Callee',
    'Duration',
    'Labels',
    { label: 'Open', srOnly: true },
  ]}
  {loading}
  isEmpty={callStories.length === 0}
>
  {#snippet empty()}
    <EmptyState
      title={searchText || appliedLabels.length > 0 ? 'No matching calls' : 'No calls yet'}
      description={searchText || appliedLabels.length > 0
        ? 'Try other words, or clear the search and label filter.'
        : 'Every call your team takes or makes shows up here once it ends.'}
    />
  {/snippet}
  {#each callStories as callStory (callStory.id)}
    <TableRow {callStory} />
  {/each}
</Table>

<Pagination
  baseUrl={`/app/${page.params.subdomain}/call-story`}
  {totalPages}
  {currentPage}
  {itemsPerPage}
  {totalCount}
  onPageChange={handlePageChange}
  onItemsPerPageChange={handleItemsPerPageChange}
/>
