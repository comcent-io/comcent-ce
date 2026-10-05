<script lang="ts">
  import { marked } from 'marked';
  import FormSection from '$lib/components/form/FormSection.svelte';
  import { processContent } from './utils';

  interface Props {
    executiveSummary: string;
  }

  let { executiveSummary }: Props = $props();

  let processedContent = $derived(processContent(executiveSummary));
</script>

<FormSection
  title="Executive summary"
  description="What happened on the day's calls, written by AI."
  className="w-full lg:w-3/4"
>
  {#if processedContent && processedContent.trim().length > 0}
    <!-- The summary is Markdown: paragraphs, lists and bold. -->
    <div
      class="text-base leading-relaxed text-gray-800 dark:text-gray-100 [&_li]:mb-1 [&_ol]:list-decimal [&_ol]:ps-5 [&_p]:mb-3 [&_strong]:font-semibold [&_strong]:text-gray-900 dark:[&_strong]:text-white [&_ul]:list-disc [&_ul]:ps-5"
    >
      {@html marked.parse(processedContent)}
    </div>
  {:else if executiveSummary}
    <p class="whitespace-pre-wrap text-base leading-relaxed text-gray-800 dark:text-gray-100">
      {executiveSummary}
    </p>
  {:else}
    <p class="text-sm text-gray-500 dark:text-gray-400">No summary for this day.</p>
  {/if}
</FormSection>
