<script lang="ts">
  import type { DailySummary } from './types';
  import { formatDate } from '$lib/format';
  import { processContent } from './utils';

  interface Props {
    summary: DailySummary;
    onSelect: (date: string) => void;
  }

  let { summary, onSelect }: Props = $props();

  // The summary's opening words, without its Markdown, as one line.
  let preview = $derived(
    processContent(summary.executiveSummary ?? '')
      .replace(/[#*_`>]/g, '')
      .replace(/\s+/g, ' ')
      .trim(),
  );
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
  <div class="flex items-center justify-between gap-6">
    <div class="min-w-0">
      <h3 class="text-base font-semibold text-gray-900 dark:text-white">
        {formatDate(summary.date)}
      </h3>
      <p class="mt-1 truncate text-sm text-gray-500 dark:text-gray-400">
        {preview}
      </p>
    </div>
    <button
      type="button"
      class="shrink-0 text-sm text-blue-600 hover:text-blue-800 dark:text-blue-400 dark:hover:text-blue-300 font-medium"
      onclick={(e) => {
        e.preventDefault();
        onSelect(summary.date);
      }}
    >
      View Summary →
    </button>
  </div>
</div>
