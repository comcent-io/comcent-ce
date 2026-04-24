<script lang="ts">
  import { marked } from 'marked';
  import { processContent } from './utils';

  export let executiveSummary: string;

  $: processedContent = processContent(executiveSummary);
</script>

<div
  class="w-full lg:w-3/4 bg-gray-800 dark:bg-gray-800 rounded-lg p-6 border border-gray-700 dark:border-gray-700"
>
  <h2 class="text-xl font-bold text-white mb-4">Executive summary</h2>
  <div class="prose prose-sm prose-invert max-w-none">
    {#if processedContent && processedContent.trim().length > 0}
      <div class="text-gray-300 text-base font-medium whitespace-pre-wrap">
        {@html marked.parse(processedContent)}
      </div>
    {:else if executiveSummary}
      <div class="text-gray-300 text-base font-medium whitespace-pre-wrap">
        {executiveSummary}
      </div>
    {:else}
      <p class="text-gray-400 italic text-sm">No summary available</p>
    {/if}
  </div>
</div>
