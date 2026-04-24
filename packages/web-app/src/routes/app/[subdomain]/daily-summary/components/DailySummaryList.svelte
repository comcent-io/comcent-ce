<script lang="ts">
  import type { DailySummary } from './types';
  import DailySummaryListItem from './DailySummaryListItem.svelte';
  import Spinner from '$lib/components/Icons/Spinner.svelte';

  export let dailySummaries: DailySummary[] = [];
  export let loading: boolean = false;
  export let onSelectSummary: (date: string) => void;
</script>

<div>
  <h1 class="text-3xl font-bold text-gray-900 dark:text-white mb-8">Daily Summaries</h1>

  {#if loading}
    <div class="flex justify-center items-center h-64">
      <Spinner />
    </div>
  {:else if dailySummaries.length === 0}
    <div class="text-center py-12">
      <p class="text-gray-600 dark:text-gray-400">No daily summaries available.</p>
    </div>
  {:else}
    <div
      class="bg-white dark:bg-gray-800 rounded-lg shadow-sm border border-gray-200 dark:border-gray-700"
    >
      <div class="divide-y divide-gray-200 dark:divide-gray-700">
        {#each dailySummaries as summary}
          <DailySummaryListItem {summary} onSelect={onSelectSummary} />
        {/each}
      </div>
    </div>
  {/if}
</div>
