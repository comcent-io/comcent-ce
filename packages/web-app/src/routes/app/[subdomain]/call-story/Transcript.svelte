<script lang="ts">
  import TranscriptBubble from '$lib/components/TranscriptBubble.svelte';
  import { onMount } from 'svelte';
  import { page } from '$app/state';

  interface Props {
    callStoryId: string;
  }

  let { callStoryId }: Props = $props();

  let transcriptData: any = $state();
  let loading = $state(true);
  let error: string | null = $state(null);

  async function fetchTranscript(callStoryId: string) {
    const response = await fetch(
      `/api/v2/${page.params.subdomain}/call-story/${callStoryId}/transcript`,
    );
    if (!response.ok) throw new Error((await response.json()).error ?? response.statusText);
    return response.json();
  }

  onMount(async () => {
    try {
      transcriptData = await fetchTranscript(callStoryId);
    } catch (err) {
      error = 'Failed to load transcript';
      console.error('Error loading transcript:', err);
    } finally {
      loading = false;
    }
  });
</script>

{#if loading}
  <p>Loading...</p>
{:else if error}
  <p>Error: {error}</p>
{:else if !transcriptData || !transcriptData.transcriptChat || !Array.isArray(transcriptData.transcriptChat)}
  <p>No transcript data available</p>
{:else}
  {#each transcriptData.transcriptChat as chat}
    <TranscriptBubble name={chat.currentParty} message={chat.message} />
  {/each}
{/if}
