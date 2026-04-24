<script lang="ts">
  import type { SentimentCounts } from './types';
  import { formatDate } from './utils';
  import ExecutiveSummaryCard from './ExecutiveSummaryCard.svelte';
  import PromisesCard from './PromisesCard.svelte';
  import SentimentCard from './SentimentCard.svelte';
  import Spinner from '$lib/components/Icons/Spinner.svelte';

  export let selectedDate: string;
  export let loadingDetails: boolean = false;
  export let executiveSummary: string = '';
  export let sentimentCounts: SentimentCounts | null = null;
  export let totalPromisesCreated: number = 0;
  export let totalPromisesClosed: number = 0;
  export let onBack: () => void;
</script>

<div>
  <button
    class="mb-6 text-blue-600 hover:text-blue-800 dark:text-blue-400 dark:hover:text-blue-300 font-medium flex items-center"
    on:click={onBack}
  >
    ← Back to List
  </button>

  <h1 class="text-3xl font-bold text-gray-900 dark:text-white mb-2">
    Daily Summary - {formatDate(selectedDate)}
  </h1>

  {#if loadingDetails}
    <div class="flex justify-center items-center h-64">
      <Spinner />
    </div>
  {:else}
    <!-- Flex Layout: Executive summary on left, Promises and Sentiment stacked on right -->
    <div class="flex flex-col lg:flex-row gap-6 mt-6">
      <!-- Executive Summary Card - Left (wider, 75% width) -->
      <ExecutiveSummaryCard {executiveSummary} />

      <!-- Right Column Container: Promises and Sentiment stacked vertically -->
      <div class="w-full lg:w-1/4 flex flex-col gap-6">
        <!-- Promises Count Card -->
        <PromisesCard {totalPromisesCreated} {totalPromisesClosed} />

        <!-- Customer Sentiment Card -->
        <SentimentCard {sentimentCounts} />
      </div>
    </div>
  {/if}
</div>
