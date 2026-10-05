<script lang="ts">
  import TranscriptBubble from '$lib/components/TranscriptBubble.svelte';
  import EmptyState from '$lib/components/form/EmptyState.svelte';
  import { partyName } from '$lib/party';

  interface TranscriptChat {
    currentParty: string;
    start: number;
    message: string;
  }

  interface Props {
    transcriptData?: { transcriptChat?: TranscriptChat[] } | null;
  }

  let { transcriptData = null }: Props = $props();

  let chats = $derived(
    Array.isArray(transcriptData?.transcriptChat) ? transcriptData.transcriptChat : [],
  );
</script>

{#if chats.length > 0}
  <div class="space-y-4">
    {#each chats as chat, i (i)}
      <TranscriptBubble
        name={partyName(chat.currentParty)}
        message={chat.message}
        start={chat.start}
      />
    {/each}
  </div>
{:else}
  <EmptyState
    title="No transcript"
    description="This call has no transcript, for example when nothing was said."
  />
{/if}
