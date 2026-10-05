<script lang="ts">
  import TranscriptBubble from '$lib/components/TranscriptBubble.svelte';
  import ErrorMessage from '$lib/components/ErrorMessage.svelte';
  import EmptyState from '$lib/components/form/EmptyState.svelte';
  import Spinner from '$lib/components/Icons/Spinner.svelte';
  import { partyName } from '$lib/party';
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
  <div class="flex justify-center py-10"><Spinner /></div>
{:else if error}
  <ErrorMessage error={{ message: error, formErrors: [] }} />
{:else if !transcriptData || !Array.isArray(transcriptData.transcriptChat) || transcriptData.transcriptChat.length === 0}
  <EmptyState
    title="No transcript"
    description="This call has no transcript, for example when nothing was said."
  />
{:else}
  <div class="space-y-4">
    {#each transcriptData.transcriptChat as chat}
      <TranscriptBubble
        name={partyName(chat.currentParty)}
        message={chat.message}
        start={chat.start}
      />
    {/each}
  </div>
{/if}
