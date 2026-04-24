<script lang="ts">
  import { onMount, createEventDispatcher } from 'svelte';

  export let subdomain: string;
  export let initialSelectedLabels: any[] = [];
  export let appliedCount: number = 0;

  const dispatch = createEventDispatcher();

  let allLabels: any[] = [];
  let selectedLabels: any[] = [...initialSelectedLabels];
  let labelSearchText = '';
  let showLabelDropdown = false;
  let loadingLabels = false;
  let filteredLabels: any[] = [];

  $: {
    filteredLabels = allLabels.filter((label) => {
      const matchesSearch = label.name.toLowerCase().includes(labelSearchText.toLowerCase());
      return matchesSearch;
    });
  }

  // Fetch organization labels
  async function fetchOrgLabels() {
    loadingLabels = true;
    try {
      const response = await fetch(`/api/v2/${subdomain}/settings/ai-analysis`);
      if (!response.ok) throw new Error((await response.json()).error ?? response.statusText);
      const data = await response.json();
      allLabels = data.labels || [];
      return allLabels;
    } catch (err) {
      console.error('Error fetching labels:', err);
      allLabels = [];
      return [];
    } finally {
      loadingLabels = false;
    }
  }

  // Toggle label selection
  function toggleLabel(label: any) {
    const labelId = label.id || label.name;
    const isSelected = selectedLabels.some((l) => {
      const id = l.id || l.name;
      return id === labelId;
    });

    if (isSelected) {
      selectedLabels = selectedLabels.filter((l) => {
        const id = l.id || l.name;
        return id !== labelId;
      });
    } else {
      selectedLabels = [...selectedLabels, label];
    }
  }

  // Check if a label is selected
  function isLabelSelected(label: any) {
    const labelId = label.id || label.name;
    return selectedLabels.some((l) => {
      const id = l.id || l.name;
      return id === labelId;
    });
  }

  // Toggle dropdown visibility
  function toggleLabelDropdown() {
    showLabelDropdown = !showLabelDropdown;
    if (showLabelDropdown) {
      labelSearchText = '';
    }
  }

  // Apply label filters - send to parent
  function applyLabelFilters() {
    showLabelDropdown = false;
    dispatch('apply', selectedLabels);
  }

  // Clear all label filters
  function clearLabelFilters() {
    selectedLabels = [];
    showLabelDropdown = false;
    dispatch('clear');
  }

  // Handle clicking outside to close dropdown
  function handleClickOutside(event: MouseEvent) {
    const target = event.target as HTMLElement;
    if (!target.closest('.label-filter-container')) {
      showLabelDropdown = false;
    }
  }

  // Public method to initialize/restore labels from URL
  export async function initializeLabels(labelIds: string[]) {
    const labels = await fetchOrgLabels();
    if (labelIds.length > 0) {
      const restoredLabels = labels.filter((label) => {
        const labelId = label.id || label.name;
        return labelIds.includes(labelId.toString());
      });
      selectedLabels = [...restoredLabels];
    }
    return selectedLabels;
  }

  onMount(() => {
    fetchOrgLabels();
    document.addEventListener('click', handleClickOutside);
    return () => {
      document.removeEventListener('click', handleClickOutside);
    };
  });
</script>

<div class="label-filter-container relative">
  <button
    type="button"
    on:click={toggleLabelDropdown}
    class="relative inline-flex items-center justify-center p-3 text-gray-700 bg-white border border-gray-300 rounded-lg hover:bg-gray-50 focus:ring-4 focus:outline-none focus:ring-blue-300 dark:bg-gray-700 dark:text-gray-300 dark:border-gray-600 dark:hover:bg-gray-600 dark:focus:ring-gray-700"
    aria-label="Filter by labels"
  >
    <!-- Filter Icon -->
    <svg
      class="w-4 h-4"
      fill="none"
      stroke="currentColor"
      viewBox="0 0 24 24"
      xmlns="http://www.w3.org/2000/svg"
    >
      <path
        stroke-linecap="round"
        stroke-linejoin="round"
        stroke-width="2"
        d="M3 4a1 1 0 011-1h16a1 1 0 011 1v2.586a1 1 0 01-.293.707l-6.414 6.414a1 1 0 00-.293.707V17l-4 4v-6.586a1 1 0 00-.293-.707L3.293 7.293A1 1 0 013 6.586V4z"
      />
    </svg>
    {#if appliedCount > 0}
      <span
        class="absolute -top-1 -right-1 inline-flex items-center justify-center w-5 h-5 text-xs font-bold text-white bg-blue-600 rounded-full dark:bg-blue-500"
      >
        {appliedCount}
      </span>
    {/if}
  </button>

  <!-- Dropdown Menu -->
  {#if showLabelDropdown}
    <div
      class="absolute z-10 mt-2 w-80 right-0 bg-white dark:bg-gray-800 border border-gray-300 dark:border-gray-600 rounded-lg shadow-lg"
    >
      <!-- Search Input -->
      <div class="p-3 border-b border-gray-200 dark:border-gray-600">
        <div class="relative">
          <div class="absolute inset-y-0 start-0 flex items-center ps-3 pointer-events-none">
            <svg
              class="w-4 h-4 text-gray-500 dark:text-gray-400"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="m21 21-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"
              />
            </svg>
          </div>
          <input
            bind:value={labelSearchText}
            type="text"
            placeholder="Search labels..."
            class="block w-full ps-10 p-2 text-sm text-gray-900 border border-gray-300 rounded-lg bg-gray-50 focus:ring-blue-500 focus:border-blue-500 dark:bg-gray-700 dark:border-gray-600 dark:placeholder-gray-400 dark:text-white dark:focus:ring-blue-500 dark:focus:border-blue-500"
          />
        </div>
      </div>

      <!-- Labels List with Checkboxes -->
      <div class="max-h-60 overflow-y-auto py-2">
        {#if loadingLabels}
          <div class="px-4 py-8 text-center">
            <div class="flex justify-center items-center">
              <div class="animate-spin rounded-full h-6 w-6 border-b-2 border-blue-700"></div>
              <span class="ml-2 text-gray-600 dark:text-gray-400 text-sm">Loading...</span>
            </div>
          </div>
        {:else if filteredLabels.length === 0}
          <div class="px-4 py-8 text-center text-gray-500 dark:text-gray-400 text-sm">
            {#if labelSearchText.trim()}
              No labels found matching "{labelSearchText}"
            {:else}
              No labels available
            {/if}
          </div>
        {:else}
          <ul>
            {#each filteredLabels as label}
              <li>
                <label
                  class="flex items-center px-4 py-2.5 hover:bg-gray-100 dark:hover:bg-gray-700 cursor-pointer transition-colors"
                >
                  <input
                    type="checkbox"
                    checked={isLabelSelected(label)}
                    on:change={() => toggleLabel(label)}
                    class="w-4 h-4 text-blue-600 bg-gray-100 border-gray-300 rounded focus:ring-blue-500 dark:focus:ring-blue-600 dark:ring-offset-gray-800 focus:ring-2 dark:bg-gray-700 dark:border-gray-600"
                  />
                  <span class="ml-3 text-sm text-gray-900 dark:text-white">{label.name}</span>
                </label>
              </li>
            {/each}
          </ul>
        {/if}
      </div>

      <!-- Footer Actions -->
      <div
        class="p-3 border-t border-gray-200 dark:border-gray-600 flex items-center justify-between gap-2"
      >
        <div class="text-xs text-gray-600 dark:text-gray-400">
          {selectedLabels.length} selected
        </div>
        <div class="flex gap-2">
          {#if selectedLabels.length > 0}
            <button
              type="button"
              on:click={clearLabelFilters}
              class="px-3 py-1.5 text-xs font-medium text-gray-700 bg-white border border-gray-300 rounded-lg hover:bg-gray-50 dark:bg-gray-700 dark:text-gray-300 dark:border-gray-600 dark:hover:bg-gray-600"
            >
              Clear
            </button>
          {/if}
          <button
            type="button"
            on:click={applyLabelFilters}
            disabled={selectedLabels.length === 0}
            class="px-3 py-1.5 text-xs font-medium text-white bg-blue-700 rounded-lg hover:bg-blue-800 disabled:bg-gray-400 disabled:cursor-not-allowed dark:bg-blue-600 dark:hover:bg-blue-700"
          >
            Apply
          </button>
        </div>
      </div>
    </div>
  {/if}
</div>
