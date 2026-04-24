<script lang="ts">
  import { page } from '$app/stores';
  import { onMount } from 'svelte';
  import Pagination from '$lib/components/Pagination.svelte';
  import LabelFilter from '$lib/components/LabelFilter.svelte';
  import TableRow from './TableRow.svelte';

  let searchText = '';
  let callStories: any[] = [];
  let totalPages = 0;
  let currentPage = 1;
  let itemsPerPage = 10;
  let totalCount = 0;
  let loading = false;
  let error = '';

  // Label filter state
  let appliedLabels: any[] = []; // Labels actually applied/sent to API
  let labelFilterComponent: any;

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
      const response = await fetch(`/api/v2/${$page.params.subdomain}/call-stories?${queryString}`);
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
  function handleLabelApply(event: CustomEvent) {
    appliedLabels = [...event.detail];

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

<h3 class="text-3xl font-bold dark:text-white">Call Story</h3>

{#if error}
  <div class="bg-red-100 border border-red-400 text-red-700 px-4 py-3 rounded mb-4">
    {error}
  </div>
{/if}

<!-- Filters Container -->
<div class="max-w-7xl mx-auto mb-6 mt-2">
  <!-- Search Form with Filter Button -->
  <form class="w-full" on:submit={handleSearch}>
    <label
      for="default-search"
      class="block mb-2 text-sm font-medium text-gray-900 dark:text-white"
    >
      Search Call Stories
    </label>
    <div class="flex gap-2">
      <div class="relative flex-1">
        <div class="absolute inset-y-0 start-0 flex items-center ps-3 pointer-events-none">
          <svg
            class="w-4 h-4 text-gray-500 dark:text-gray-400"
            aria-hidden="true"
            xmlns="http://www.w3.org/2000/svg"
            fill="none"
            viewBox="0 0 20 20"
          >
            <path
              stroke="currentColor"
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="m19 19-4-4m0-7A7 7 0 1 1 1 8a7 7 0 0 1 14 0Z"
            />
          </svg>
        </div>
        <input
          bind:value={searchText}
          type="search"
          id="default-search"
          class="block w-full p-4 ps-10 text-sm text-gray-900 border border-gray-300 rounded-lg bg-gray-50 focus:ring-blue-500 focus:border-blue-500 dark:bg-gray-700 dark:border-gray-600 dark:placeholder-gray-400 dark:text-white dark:focus:ring-blue-500 dark:focus:border-blue-500"
          placeholder="Enter a keyword or phrase"
          required
        />
        <button
          class="absolute inset-y-0 end-24 flex items-center ps-3"
          type="button"
          on:click={clearSearch}
        >
          <svg
            class="w-4 h-4 text-gray-500 dark:text-gray-400"
            aria-hidden="true"
            xmlns="http://www.w3.org/2000/svg"
            fill="none"
            viewBox="0 0 24 24"
          >
            <path
              stroke="currentColor"
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M6 18 18 6m0 12L6 6"
            />
          </svg>
        </button>
        <button
          type="submit"
          class="text-white absolute end-2.5 bottom-2.5 bg-blue-700 hover:bg-blue-800 focus:ring-4 focus:outline-none focus:ring-blue-300 font-medium rounded-lg text-sm px-4 py-2 dark:bg-blue-600 dark:hover:bg-blue-700 dark:focus:ring-blue-800"
        >
          Search
        </button>
      </div>

      <!-- Label Filter Component -->
      <div class="mt-1.5">
        <LabelFilter
          bind:this={labelFilterComponent}
          subdomain={$page.params.subdomain}
          appliedCount={appliedLabels.length}
          on:apply={handleLabelApply}
          on:clear={handleLabelClear}
        />
      </div>
    </div>
  </form>

  <!-- Active Filters Display -->
  {#if appliedLabels.length > 0}
    <div class="mt-3 flex flex-wrap gap-2">
      {#each appliedLabels as label}
        <span
          class="inline-flex items-center gap-1.5 px-3 py-1 bg-blue-100 text-blue-800 rounded-full text-xs font-medium dark:bg-blue-900 dark:text-blue-200"
        >
          {label.name}
        </span>
      {/each}
    </div>
  {/if}
</div>

<div class="mt-4 relative overflow-visible shadow-md sm:rounded-lg">
  <table class="w-full text-sm text-left rtl:text-right text-gray-500 dark:text-gray-400">
    <thead class="text-xs text-gray-700 uppercase bg-gray-50 dark:bg-gray-700 dark:text-gray-400">
      <tr>
        <th scope="col" class="px-6 py-3">Date Time</th>
        <th scope="col" class="px-6 py-3">Direction</th>
        <th scope="col" class="px-6 py-3">Caller</th>
        <th scope="col" class="px-6 py-3">Callee</th>
        <th scope="col" class="px-6 py-3">Action</th>
      </tr>
    </thead>
    <tbody>
      {#if loading}
        <tr>
          <td colspan="5" class="px-6 py-8 text-center">
            <div class="flex justify-center items-center">
              <div class="animate-spin rounded-full h-8 w-8 border-b-2 border-blue-700"></div>
              <span class="ml-2 text-gray-600">Loading call stories...</span>
            </div>
          </td>
        </tr>
      {:else}
        {#each callStories as callStory}
          <TableRow {callStory} />
        {/each}
      {/if}
    </tbody>
  </table>
</div>

<Pagination
  baseUrl={`/app/${$page.params.subdomain}/call-story`}
  {totalPages}
  {currentPage}
  {itemsPerPage}
  {totalCount}
  onPageChange={handlePageChange}
  onItemsPerPageChange={handleItemsPerPageChange}
/>
