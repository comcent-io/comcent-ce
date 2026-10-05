<script lang="ts">
  import { onMount } from 'svelte';
  import { page } from '$app/state';
  import EmptyState from '$lib/components/form/EmptyState.svelte';
  import Spinner from '$lib/components/Icons/Spinner.svelte';

  interface Props {
    callStoryId: string;
  }

  let { callStoryId }: Props = $props();

  let summaryData: { summary: string } | null = $state(null);

  async function fetchSummary(callStoryId: string) {
    const response = await fetch(
      `/api/v2/${page.params.subdomain}/call-story/${callStoryId}/summary`,
    );
    if (!response.ok) throw new Error((await response.json()).error ?? response.statusText);
    return response.json();
  }

  onMount(async () => {
    summaryData = await fetchSummary(callStoryId);
  });
</script>

{#if !summaryData}
  <div class="flex justify-center py-10"><Spinner /></div>
{:else if !summaryData.summary}
  <EmptyState title="No summary" description="This call has no AI summary." />
{:else}
  <div
    class="rounded-lg border border-gray-200 bg-gray-50 p-5 dark:border-gray-700 dark:bg-gray-900/40"
  >
    <p class="text-xs font-semibold uppercase tracking-wide text-cyan-700 dark:text-cyan-300">
      AI summary
    </p>
    <p class="mt-2 text-base leading-relaxed text-gray-800 dark:text-gray-100">
      {summaryData.summary}
    </p>
  </div>
{/if}
