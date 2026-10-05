<script lang="ts">
  import { tick, untrack } from 'svelte';
  import toast from '$lib/toast';
  import Dialog from '$lib/components/Dialog.svelte';
  import ErrorMessage from '$lib/components/ErrorMessage.svelte';
  import Spinner from '$lib/components/Icons/Spinner.svelte';
  import Tabs from '$lib/components/Tabs.svelte';
  import { formatDateTime, formatDuration } from '$lib/format';
  import { partyName } from '$lib/party';
  import CallPromises from './CallPromises.svelte';
  import CallRecordings from './CallRecordings.svelte';
  import CallTranscript from './CallTranscript.svelte';

  interface Props {
    showModal?: boolean;
    callStoryId?: string;
    subdomain: string;
  }

  let { showModal = $bindable(false), callStoryId = '', subdomain }: Props = $props();

  let loading = $state(false);
  let error: string | null = $state(null);
  let callStory: any = $state(null);
  let transcriptData: any = $state(null);
  let audioRecordings: any[] = $state([]);
  let promises: any[] = $state([]);

  async function loadCallDetails() {
    if (!callStoryId) return;

    loading = true;
    error = null;
    callStory = null;
    transcriptData = null;
    audioRecordings = [];
    promises = [];

    try {
      const [callStoryResponse, transcriptResponse] = await Promise.allSettled([
        fetch(`/api/v2/${subdomain}/call-story/${callStoryId}`),
        fetch(`/api/v2/${subdomain}/call-story/${callStoryId}/transcript`),
      ]);

      if (callStoryResponse.status === 'fulfilled') {
        const csRes = callStoryResponse.value;
        if (!csRes.ok) throw new Error((await csRes.json()).error ?? csRes.statusText);
        const csData = await csRes.json();
        callStory = csData.callStory;

        // Extract promises
        if (callStory.promises) {
          promises = callStory.promises;
        }

        // Extract audio recordings
        if (callStory.callSpans) {
          const recordings = callStory.callSpans
            .filter(
              (span: any) =>
                span.type === 'RECORDING' &&
                span.metadata?.fileName &&
                span.metadata?.direction === 'both',
            )
            .map((span: any) => ({
              url: `/api/v2/${subdomain}/call-story/${callStoryId}/record/${span.metadata.fileName}`,
              fileName: span.metadata.fileName,
              currentParty: span.currentParty,
            }));

          audioRecordings = recordings;
          await tick();
        }
      } else {
        console.error('Failed to fetch call story:', callStoryResponse.reason);
      }

      if (transcriptResponse.status === 'fulfilled') {
        const trRes = transcriptResponse.value;
        if (!trRes.ok) throw new Error((await trRes.json()).error ?? trRes.statusText);
        transcriptData = await trRes.json();
      } else {
        console.error('Failed to fetch transcript:', transcriptResponse.reason);
      }

      if (!callStory) {
        error = 'Failed to load call details';
      }
    } catch (err: any) {
      console.error('Error loading call details:', err);
      error = 'Failed to load call details';
      toast.error('Failed to load call details');
    } finally {
      loading = false;
    }
  }

  function handleClose() {
    showModal = false;
    callStory = null;
    transcriptData = null;
    error = null;
    audioRecordings = [];
    promises = [];
  }

  // Load the call's details when the modal opens or shows another call.
  $effect(() => {
    if (showModal && callStoryId) {
      untrack(() => {
        current = 'promises';
        loadCallDetails();
      });
    }
  });

  // The same header as a call opened from Call Story: who called whom, then
  // when, which way and how long.
  let title = $derived(
    callStory ? `${partyName(callStory.caller)} → ${partyName(callStory.callee)}` : 'Call details',
  );
  let description = $derived(
    callStory
      ? [
          formatDateTime(callStory.startAt),
          callStory.direction === 'inbound' ? 'Inbound' : 'Outbound',
          formatDuration(callStory.startAt, callStory.endAt),
        ]
          .filter(Boolean)
          .join(' · ')
      : '',
  );

  const tabs = [
    { id: 'promises', label: 'Promises' },
    { id: 'recording', label: 'Recording' },
    { id: 'transcript', label: 'Transcript' },
  ];
  let current = $state('promises');
</script>

{#if showModal}
  <Dialog {title} {description} onClose={handleClose} showDialog={showModal} className="max-w-3xl">
    {#key callStoryId}
      {#if loading}
        <div class="flex justify-center py-10"><Spinner /></div>
      {:else if error}
        <ErrorMessage error={{ message: error, formErrors: [] }} />
      {:else if callStory}
        <Tabs {tabs} {current} onSelect={(id) => (current = id)} />

        <div class="min-h-48">
          {#if current === 'promises'}
            <CallPromises {promises} />
          {:else if current === 'recording'}
            <CallRecordings recordings={audioRecordings} />
          {:else if current === 'transcript'}
            <CallTranscript {transcriptData} />
          {/if}
        </div>
      {/if}
    {/key}
  </Dialog>
{/if}
