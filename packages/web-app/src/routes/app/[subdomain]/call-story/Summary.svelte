<script lang="ts">
  import { onMount } from 'svelte';
  import { page } from '$app/stores';

  export let callStoryId: string;

  let summaryData: { summary: string } | null = null;

  async function fetchSummary(callStoryId: string) {
    console.log('fetching summary');
    const response = await fetch(
      `/api/v2/${$page.params.subdomain}/call-story/${callStoryId}/summary`,
    );
    if (!response.ok) throw new Error((await response.json()).error ?? response.statusText);
    return response.json();
  }

  onMount(async () => {
    summaryData = await fetchSummary(callStoryId);
  });
</script>

{#if !summaryData}
  <p>Loading...</p>
{:else}
  <p>{summaryData.summary}</p>
{/if}
