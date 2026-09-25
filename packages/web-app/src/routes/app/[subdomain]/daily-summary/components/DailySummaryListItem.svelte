<script lang="ts">
  import type { DailySummary } from './types';
  import { formatDate } from './utils';

  interface Props {
    summary: DailySummary;
    onSelect: (date: string) => void;
  }

  let { summary, onSelect }: Props = $props();
</script>

<div
  class="px-6 py-4 hover:bg-gray-50 dark:hover:bg-gray-700 transition-colors cursor-pointer"
  role="button"
  tabindex="0"
  onclick={() => onSelect(summary.date)}
  onkeydown={(e) => {
    if (e.key === 'Enter' || e.key === ' ') {
      e.preventDefault();
      onSelect(summary.date);
    }
  }}
>
  <div class="flex items-center justify-between">
    <div>
      <h3 class="text-lg font-semibold text-gray-900 dark:text-white">
        {formatDate(summary.date)}
      </h3>
    </div>
    <button
      type="button"
      class="text-blue-600 hover:text-blue-800 dark:text-blue-400 dark:hover:text-blue-300 font-medium"
      onclick={(e) => {
        e.preventDefault();
        onSelect(summary.date);
      }}
    >
      View Summary →
    </button>
  </div>
</div>
