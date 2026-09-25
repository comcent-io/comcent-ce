<script lang="ts">
  import type { SentimentCounts } from './types';
  import { formatDate } from './utils';
  import ExecutiveSummaryCard from './ExecutiveSummaryCard.svelte';
  import PromisesCard from './PromisesCard.svelte';
  import SentimentCard from './SentimentCard.svelte';
  import Spinner from '$lib/components/Icons/Spinner.svelte';

  interface Props {
    selectedDate: string;
    loadingDetails?: boolean;
    executiveSummary?: string;
    sentimentCounts?: SentimentCounts | null;
    totalPromisesCreated?: number;
    totalPromisesClosed?: number;
    onBack: () => void;
  }

  let {
    selectedDate,
    loadingDetails = false,
    executiveSummary = '',
    sentimentCounts = null,
    totalPromisesCreated = 0,
    totalPromisesClosed = 0,
    onBack,
  }: Props = $props();
</script>

<div>
  <button
    class="mb-6 text-blue-600 hover:text-blue-800 dark:text-blue-400 dark:hover:text-blue-300 font-medium flex items-center"
    onclick={onBack}
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
