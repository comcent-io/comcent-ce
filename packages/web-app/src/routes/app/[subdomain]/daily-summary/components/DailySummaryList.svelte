<script lang="ts">
  import type { DailySummary } from './types';
  import DailySummaryListItem from './DailySummaryListItem.svelte';
  import Spinner from '$lib/components/Icons/Spinner.svelte';
  import EmptyState from '$lib/components/form/EmptyState.svelte';
  import PageHeader from '$lib/components/form/PageHeader.svelte';

  interface Props {
    dailySummaries?: DailySummary[];
    loading?: boolean;
    onSelectSummary: (date: string) => void;
  }

  let { dailySummaries = [], loading = false, onSelectSummary }: Props = $props();
</script>

<div>
  <PageHeader
    title="Daily Summary"
    description="An AI-written summary of each day's calls: what happened, the promises made, and how customers felt."
  />

  {#if loading}
    <div class="flex justify-center items-center h-64">
      <Spinner />
    </div>
  {:else if dailySummaries.length === 0}
    <EmptyState
      title="No daily summaries yet"
      description="A summary appears here at the end of each day your team takes calls."
    />
  {:else}
    <div
      class="overflow-hidden rounded-lg border border-gray-200 bg-white shadow dark:border-gray-700 dark:bg-gray-800"
    >
      <div class="divide-y divide-gray-200 dark:divide-gray-700">
        {#each dailySummaries as summary}
          <DailySummaryListItem {summary} onSelect={onSelectSummary} />
        {/each}
      </div>
    </div>
  {/if}
</div>
