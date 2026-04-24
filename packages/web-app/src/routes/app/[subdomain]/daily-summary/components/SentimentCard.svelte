<script lang="ts">
  import type { SentimentCounts } from './types';
  import { calculatePercentage } from './utils';

  export let sentimentCounts: SentimentCounts | null = null;

  $: totalSentiment = sentimentCounts
    ? sentimentCounts.positive + sentimentCounts.negative + sentimentCounts.neutral
    : 0;
</script>

<div
  class="bg-gray-800 dark:bg-gray-800 rounded-lg p-6 border border-gray-700 dark:border-gray-700 min-h-[250px]"
>
  <h2 class="text-xl font-bold text-white mb-4">Customer sentiment</h2>
  <div class="space-y-4">
    {#if sentimentCounts && totalSentiment > 0}
      <!-- Positive -->
      <div>
        <div class="mb-2">
          <span class="text-white text-sm font-medium">Positive</span>
        </div>
        <div class="w-full bg-gray-700 rounded-full h-2.5">
          <div
            class="bg-green-500 h-2.5 rounded-full transition-all"
            style="width: {calculatePercentage(sentimentCounts.positive, totalSentiment)}%"
          ></div>
        </div>
      </div>

      <!-- Neutral -->
      <div>
        <div class="mb-2">
          <span class="text-white text-sm font-medium">Neutral</span>
        </div>
        <div class="w-full bg-gray-700 rounded-full h-2.5">
          <div
            class="bg-gray-400 h-2.5 rounded-full transition-all"
            style="width: {calculatePercentage(sentimentCounts.neutral, totalSentiment)}%"
          ></div>
        </div>
      </div>

      <!-- Negative -->
      <div>
        <div class="mb-2">
          <span class="text-white text-sm font-medium">Negative</span>
        </div>
        <div class="w-full bg-gray-700 rounded-full h-2.5">
          <div
            class="bg-red-500 h-2.5 rounded-full transition-all"
            style="width: {calculatePercentage(sentimentCounts.negative, totalSentiment)}%"
          ></div>
        </div>
      </div>
    {:else}
      <p class="text-gray-400 italic text-sm">No sentiment data available</p>
    {/if}
  </div>
</div>
