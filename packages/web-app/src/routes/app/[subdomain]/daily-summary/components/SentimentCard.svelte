<script lang="ts">
  import FormSection from '$lib/components/form/FormSection.svelte';
  import type { SentimentCounts } from './types';
  import { calculatePercentage } from './utils';

  interface Props {
    sentimentCounts?: SentimentCounts | null;
  }

  let { sentimentCounts = null }: Props = $props();

  let totalSentiment = $derived(
    sentimentCounts
      ? sentimentCounts.positive + sentimentCounts.negative + sentimentCounts.neutral
      : 0,
  );

  let rows = $derived(
    sentimentCounts
      ? [
          { label: 'Positive', count: sentimentCounts.positive, bar: 'bg-green-500' },
          { label: 'Neutral', count: sentimentCounts.neutral, bar: 'bg-gray-400' },
          { label: 'Negative', count: sentimentCounts.negative, bar: 'bg-red-500' },
        ]
      : [],
  );
</script>

<FormSection title="Sentiment" description="How people on the day's calls came across.">
  {#if sentimentCounts && totalSentiment > 0}
    <div class="space-y-4">
      {#each rows as row (row.label)}
        <div>
          <div class="mb-1.5 flex justify-between text-sm">
            <span class="font-medium text-gray-700 dark:text-gray-300">{row.label}</span>
            <span class="tabular-nums text-gray-500 dark:text-gray-400">{row.count}</span>
          </div>
          <div class="h-2 w-full rounded-full bg-gray-200 dark:bg-gray-700">
            <div
              class="h-2 rounded-full transition-all {row.bar}"
              style="width: {calculatePercentage(row.count, totalSentiment)}%"
            ></div>
          </div>
        </div>
      {/each}
    </div>
  {:else}
    <p class="text-sm text-gray-500 dark:text-gray-400">No sentiment for this day.</p>
  {/if}
</FormSection>
