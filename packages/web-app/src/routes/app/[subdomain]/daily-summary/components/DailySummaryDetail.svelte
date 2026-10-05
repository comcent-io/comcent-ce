<script lang="ts">
  import type { SentimentCounts } from './types';
  import { formatDate } from '$lib/format';
  import ExecutiveSummaryCard from './ExecutiveSummaryCard.svelte';
  import PromisesCard from './PromisesCard.svelte';
  import SentimentCard from './SentimentCard.svelte';
  import Spinner from '$lib/components/Icons/Spinner.svelte';
  import PageHeader from '$lib/components/form/PageHeader.svelte';

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
  <PageHeader
    title="Daily Summary: {formatDate(selectedDate)}"
    description="The day's calls in a few lines, the promises made, and how customers felt."
    {onBack}
    backLabel="All days"
  />

  {#if loadingDetails}
    <div class="flex justify-center items-center h-64">
      <Spinner />
    </div>
  {:else}
    <!-- Flex Layout: Executive summary on left, Promises and Sentiment stacked on right -->
    <div class="flex flex-col items-start lg:flex-row gap-6">
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
