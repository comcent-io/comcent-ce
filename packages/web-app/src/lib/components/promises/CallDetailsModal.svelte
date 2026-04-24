<script lang="ts">
  import { tick } from 'svelte';
  import toast from 'svelte-french-toast';
  import Dialog from '$lib/components/Dialog.svelte';
  import Spinner from '$lib/components/Icons/Spinner.svelte';
  import CallInfoHeader from './CallInfoHeader.svelte';
  import CallPromises from './CallPromises.svelte';
  import CallRecordings from './CallRecordings.svelte';
  import CallTranscript from './CallTranscript.svelte';

  export let showModal: boolean = false;
  export let callStoryId: string = '';
  export let subdomain: string;

  let loading = false;
  let error: string | null = null;
  let callStory: any = null;
  let transcriptData: any = null;
  let audioRecordings: any[] = [];
  let promises: any[] = [];

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

  // Reactive statement to load data when modal opens or callStoryId changes
  $: if (showModal && callStoryId) {
    loadCallDetails();
  }
</script>

{#if showModal}
  <Dialog title="Call Details" on:close={handleClose} showDialog={showModal} className="max-w-2xl">
    {#key callStoryId}
      {#if loading}
        <div class="flex justify-center items-center h-64">
          <Spinner />
          <span class="ml-3 text-gray-600 dark:text-gray-400">Loading call details...</span>
        </div>
      {:else if error}
        <div class="text-center py-12">
          <svg
            class="mx-auto h-12 w-12 text-red-400"
            fill="none"
            stroke="currentColor"
            viewBox="0 0 24 24"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
            ></path>
          </svg>
          <h3 class="mt-2 text-sm font-medium text-gray-900 dark:text-white">Error</h3>
          <p class="mt-1 text-sm text-gray-500 dark:text-gray-400">{error}</p>
        </div>
      {:else if callStory}
        <!-- Unified Professional Call Details Container -->
        <div class="bg-slate-800 dark:bg-gray-850 rounded-xl p-6 -mx-4 -mt-4">
          <CallInfoHeader
            caller={callStory.caller}
            callee={callStory.callee}
            direction={callStory.direction}
            startAt={callStory.startAt}
          />

          <CallPromises {promises} />

          <CallRecordings recordings={audioRecordings} />

          <CallTranscript {transcriptData} />
        </div>
      {/if}
    {/key}
  </Dialog>
{/if}
