<script lang="ts">
  import { onMount } from 'svelte';
  import { page } from '$app/stores';
  export let callStoryId: string;

  const smile = {
    positive: '😊',
    negative: '😞',
    neutral: '😐',
  };

  type SentimentType = keyof typeof smile;

  let sentimentData: { sentiment: Record<string, SentimentType> } | null = null;

  async function fetchSentiment(callStoryId: string) {
    console.log('fetching sentiment');
    const response = await fetch(
      `/api/v2/${$page.params.subdomain}/call-story/${callStoryId}/sentiment`,
    );
    if (!response.ok) throw new Error((await response.json()).error ?? response.statusText);
    return response.json();
  }

  onMount(async () => {
    sentimentData = await fetchSentiment(callStoryId);
  });
</script>

{#if !sentimentData}
  <p>Loading...</p>
{:else}
  <ul class="max-w-md space-y-1 text-gray-500 list-inside dark:text-gray-400">
    {#each Object.entries(sentimentData.sentiment) as [currentParty, sentimentAnalysis]}
      <li class="flex items-center text-lg">
        <span class="text-2xl mr-4">{smile[sentimentAnalysis]}</span>
        {currentParty}
      </li>
    {/each}
  </ul>
{/if}
