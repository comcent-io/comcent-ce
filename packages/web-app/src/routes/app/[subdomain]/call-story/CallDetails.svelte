<script lang="ts">
  import CallStory from '$lib/components/CallStory.svelte';
  import Dialog from '$lib/components/Dialog.svelte';
  import Pill from '$lib/components/Pill.svelte';
  import Tabs from '$lib/components/Tabs.svelte';
  import { formatDateTime, formatDuration } from '$lib/format';
  import { partyName } from '$lib/party';
  import type { CallStoryFromServer } from '$lib/types/CallStoryFromServer.js';
  import Sentiment from './Sentiment.svelte';
  import Summary from './Summary.svelte';
  import Transcript from './Transcript.svelte';

  // Everything about one call in one dialog: its graph and, when the call
  // has them, the transcript, AI summary and sentiment, as tabs.
  interface Props {
    callStory: CallStoryFromServer;
    onClose: () => void;
  }

  let { callStory, onClose }: Props = $props();

  let tabs = $derived([
    { id: 'graph', label: 'Call graph' },
    ...(callStory.isTranscribed ? [{ id: 'transcript', label: 'Transcript' }] : []),
    ...(callStory.isSummarized ? [{ id: 'summary', label: 'Summary' }] : []),
    ...(callStory.isSentimentAnalyzed ? [{ id: 'sentiment', label: 'Sentiment' }] : []),
  ]);
  let current = $state('graph');

  let labels = $derived(callStory.labels ?? []);
  let description = $derived(
    [
      formatDateTime(callStory.startAt),
      callStory.direction === 'inbound' ? 'Inbound' : 'Outbound',
      formatDuration(callStory.startAt, callStory.endAt),
    ]
      .filter(Boolean)
      .join(' · '),
  );
</script>

<Dialog
  showDialog
  title="{partyName(callStory.caller)} → {partyName(callStory.callee)}"
  {description}
  className="max-w-5xl"
  {onClose}
>
  {#if labels.length > 0}
    <div class="flex flex-wrap gap-2">
      {#each labels as label (label)}
        <Pill tone="cyan">{label}</Pill>
      {/each}
    </div>
  {/if}

  <Tabs {tabs} {current} onSelect={(id) => (current = id)} />

  <div class="min-h-48">
    {#if current === 'graph'}
      <CallStory {callStory} />
    {:else if current === 'transcript'}
      <Transcript callStoryId={callStory.id} />
    {:else if current === 'summary'}
      <Summary callStoryId={callStory.id} />
    {:else if current === 'sentiment'}
      <Sentiment callStoryId={callStory.id} />
    {/if}
  </div>
</Dialog>
