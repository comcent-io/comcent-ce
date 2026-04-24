<script lang="ts">
  import { createEventDispatcher, onMount } from 'svelte';
  import type { SelectedOutlet } from '../SelectedOutlet';
  import type { MenuNode } from './MenuNode';
  import { page } from '$app/stores';
  import Draggable from '../utils/Draggable.svelte';
  import Inlet from '../utils/Inlet.svelte';
  import CloseButton from '../utils/CloseButton.svelte';
  import EditButton from '../utils/EditButton.svelte';
  import AudioPlayer from './AudioPlayer.svelte';
  import { deleteS3File, extractFilenameFromS3Url } from '../utils/DeleteUploads';
  import Outlet from '../utils/Outlet.svelte';
  import MediaUploadRecord from '$lib/components/MediaUploadRecord.svelte';
  import { getPlaybackUrl } from '$lib/playback';
  import type { AudioChangePayload } from '../AudioChangedPayload';
  import { uploadRecording } from '../uploadRecording';

  const dispatch = createEventDispatcher();
  export let node: MenuNode;
  let newOutletKey = '';
  let addingOption = false;
  let errorMessage = '';
  export let selectedOutlet: SelectedOutlet | null;
  export let inletConnected = false;
  export let inletConnectable = false;

  let editData = JSON.parse(JSON.stringify(node.data));
  let editing = false;

  let audioRecordingURLs = {
    savedPromptAudioURL: '',
    savedErrorAudioURL: '',
    promptAudioURL: '',
    errorAudioURL: '',
  };

  let updatedFiles: Record<string, AudioChangePayload> = {};
  let oldFiles: Record<string, string> = {};
  let isMainContentLoaded = false;

  let changedPromptAudio: AudioChangePayload | undefined;
  let changedErrorAudio: AudioChangePayload | undefined;

  const subdomain = $page.params.subdomain;

  export async function triggerUpload() {
    if (Object.keys(updatedFiles).length > 0) {
      for (let key in updatedFiles) {
        const changedAudio = updatedFiles[key];
        const s3Url = await uploadRecording($page.params.subdomain, changedAudio);
        if (s3Url) {
          if (key === 'prompt') {
            node.data.data.promptAudio = s3Url; // Update the node data with the S3 URL
          } else {
            node.data.data.errorAudio = s3Url;
          }
          if (oldFiles[key]) {
            await deleteS3File(subdomain, oldFiles[key]);
          }
          dispatch('updated', { node: node });
        } else {
          throw Error('User is not a member of this org');
        }
      }
      editing = false;
    }
  }

  onMount(async () => {
    if (node.data.data.promptAudio?.startsWith('s3://')) {
      const fileName = extractFilenameFromS3Url(node.data.data.promptAudio);
      audioRecordingURLs.savedPromptAudioURL = getPlaybackUrl(subdomain, fileName);
    }
    if (node.data.data.errorAudio?.startsWith('s3://')) {
      const fileName = extractFilenameFromS3Url(node.data.data.errorAudio);
      audioRecordingURLs.savedErrorAudioURL = getPlaybackUrl(subdomain, fileName);
    }
    audioRecordingURLs.promptAudioURL = audioRecordingURLs.savedPromptAudioURL;
    audioRecordingURLs.errorAudioURL = audioRecordingURLs.savedErrorAudioURL;
    isMainContentLoaded = true;
  });

  function onPromptAudioChange(event: CustomEvent<AudioChangePayload>) {
    changedPromptAudio = event.detail;
  }

  function onErrorAudioChange(event: CustomEvent<AudioChangePayload>) {
    changedErrorAudio = event.detail;
  }

  function onUpdate() {
    node.data = editData;
    editing = false;
    if (changedPromptAudio) {
      updatedFiles['prompt'] = changedPromptAudio;
      oldFiles['prompt'] = node.data.data.promptAudio;
    }
    if (changedErrorAudio) {
      updatedFiles['error'] = changedErrorAudio;
      oldFiles['error'] = node.data.data.errorAudio;
    }
    dispatch('updated', { node: node });
  }

  function tryAddOutlet() {
    errorMessage = '';
    const normalizedOutletKey = newOutletKey.trim();

    if (normalizedOutletKey === '') {
      errorMessage = 'Enter the digits callers should press.';
      return;
    }

    if (!/^\d+$/.test(normalizedOutletKey)) {
      errorMessage = 'Use digits only, like 1, 2, or 12.';
      return;
    }

    if (!(normalizedOutletKey in node.data.outlets)) {
      node.data.outlets[normalizedOutletKey] = '';
      newOutletKey = '';
      addingOption = false;
      node.data.outlets = { ...node.data.outlets };
    } else {
      errorMessage = normalizedOutletKey + ' already exists.';
    }
  }

  function handleKeydown(event) {
    if (event.key === 'Enter') {
      event.preventDefault();
      tryAddOutlet();
    }
  }

  function handleDeleteOutlet(event) {
    const { outletId } = event.detail;
    delete node.data.outlets[outletId];
    node.data.outlets = { ...node.data.outlets };
  }

  function showAddOption() {
    errorMessage = '';
    addingOption = true;
  }

  function cancelAddOption() {
    addingOption = false;
    newOutletKey = '';
    errorMessage = '';
  }
</script>

<Draggable
  {node}
  title={node.data.type}
  class="block w-[18.5rem] rounded-lg border-2 border-amber-400 bg-white shadow dark:border-amber-400 dark:bg-gray-800"
  on:dragEnd
>
  <svelte:fragment slot="headerActions">
    <EditButton on:edit={() => (editing = true)} />
    <CloseButton on:close />
  </svelte:fragment>
  <Inlet
    {selectedOutlet}
    {node}
    connected={inletConnected}
    connectable={inletConnectable}
    on:inletSelected
    on:disconnectInlet
  >
    <div class="space-y-3 p-3">
      <div
        class="rounded-lg border border-amber-200 bg-amber-50/80 p-3 text-sm text-amber-950 dark:border-amber-700 dark:bg-amber-950/40 dark:text-amber-100"
      >
        <p class="font-semibold">Menu prompt</p>
        <p class="mt-1 text-xs leading-5 text-amber-900/80 dark:text-amber-100/80">
          Play a recording like “Press 1 for sales, press 2 for support” and route each digit choice
          below.
        </p>
      </div>

      {#if node.data.data.promptAudio && isMainContentLoaded}
        <div
          class="flex items-center gap-2 rounded-lg border border-slate-200 bg-slate-50 px-3 py-2 dark:border-slate-700 dark:bg-slate-900/60"
        >
          <h3 class="text-sm font-medium dark:text-white">Prompt audio</h3>
          <AudioPlayer src={audioRecordingURLs.savedPromptAudioURL} />
        </div>
      {/if}

      {#if node.data.data.errorAudio && isMainContentLoaded}
        <div
          class="flex items-center gap-2 rounded-lg border border-slate-200 bg-slate-50 px-3 py-2 dark:border-slate-700 dark:bg-slate-900/60"
        >
          <h3 class="text-sm font-medium dark:text-white">Error audio</h3>
          <AudioPlayer src={audioRecordingURLs.savedErrorAudioURL} />
        </div>
      {/if}
    </div>
    <div class="px-3 pb-3">
      <div class="mb-3 flex items-center justify-between gap-3">
        <div>
          <h4
            class="text-sm font-semibold uppercase tracking-wide text-slate-500 dark:text-slate-300"
          >
            Digit routes
          </h4>
          <p class="mt-1 text-xs text-slate-500 dark:text-slate-400">
            Add one route for each digit or digit combination callers can press.
          </p>
        </div>
        {#if !addingOption}
          <button
            type="button"
            class="inline-flex shrink-0 items-center rounded-full border border-emerald-300 bg-emerald-50 px-3 py-1.5 text-xs font-semibold text-emerald-700 transition hover:border-emerald-400 hover:bg-emerald-100 dark:border-emerald-700 dark:bg-emerald-950/40 dark:text-emerald-200 dark:hover:bg-emerald-900/50"
            on:click={showAddOption}
          >
            Add option
          </button>
        {/if}
      </div>

      {#if addingOption}
        <div
          class="mb-3 rounded-xl border border-dashed border-emerald-300 bg-emerald-50/70 p-3 dark:border-emerald-700 dark:bg-emerald-950/30"
        >
          <label
            for={`menu-option-${node.data.id}`}
            class="block text-sm font-semibold text-slate-800 dark:text-slate-100"
          >
            Digits callers press
          </label>
          <p class="mt-1 text-xs text-slate-600 dark:text-slate-400">
            Use a single digit or a combination like <span class="font-semibold">12</span>
            . Each entry becomes its own route out.
          </p>
          <div class="mt-3 flex items-center gap-2">
            <input
              id={`menu-option-${node.data.id}`}
              class="w-full rounded-lg border border-emerald-300 bg-white px-3 py-2 text-sm text-slate-900 outline-none transition focus:border-emerald-500 focus:ring-2 focus:ring-emerald-200 dark:border-emerald-700 dark:bg-slate-950 dark:text-slate-100 dark:focus:ring-emerald-900"
              type="text"
              inputmode="numeric"
              bind:value={newOutletKey}
              on:keydown={handleKeydown}
              placeholder="1"
            />
            <button
              type="button"
              class="inline-flex shrink-0 items-center rounded-lg bg-emerald-600 px-3 py-2 text-sm font-semibold text-white transition hover:bg-emerald-700"
              on:click={tryAddOutlet}
            >
              Add
            </button>
            <button
              type="button"
              class="inline-flex shrink-0 items-center rounded-lg border border-slate-300 px-3 py-2 text-sm font-semibold text-slate-700 transition hover:bg-slate-100 dark:border-slate-600 dark:text-slate-200 dark:hover:bg-slate-800"
              on:click={cancelAddOption}
            >
              Cancel
            </button>
          </div>
          {#if errorMessage}
            <p class="mt-2 text-sm text-red-600 dark:text-red-400">{errorMessage}</p>
          {/if}
        </div>
      {/if}

      {#if Object.keys(node.data.outlets).length === 0}
        <div
          class="rounded-xl border border-dashed border-slate-300 bg-slate-50 px-4 py-5 text-sm text-slate-600 dark:border-slate-700 dark:bg-slate-900/40 dark:text-slate-400"
        >
          No digit routes yet. Add the first option to create a route callers can press.
        </div>
      {/if}

      {#each Object.entries(node.data.outlets) as [key]}
        <Outlet
          {selectedOutlet}
          nodeId={node.data.id}
          outletId={key}
          connected={Boolean(node.data.outlets[key])}
          isDeletable={true}
          class="w-full text-left"
          on:outletSelected
          on:disconnectOutlet
          on:deleteOutlet={handleDeleteOutlet}
        >
          <div class="pr-8">
            <p
              class="text-xs font-semibold uppercase tracking-wide text-slate-500 dark:text-slate-400"
            >
              Caller presses
            </p>
            <p class="mt-1 text-base font-semibold text-slate-900 dark:text-white">
              {key}
            </p>
          </div>
        </Outlet>
      {/each}
    </div>
  </Inlet>
</Draggable>

{#if editing}
  <div
    tabindex="-1"
    aria-hidden="true"
    class="fixed top-0 left-0 right-0 z-50 w-full p-4 overflow-x-hidden overflow-y-auto md:inset-0 h-[calc(100%-1rem)] max-h-full flex justify-center items-center"
  >
    <div class="relative w-full max-w-2xl max-h-full">
      <!-- Modal content -->
      <div class="relative bg-white rounded-lg shadow dark:bg-gray-700">
        <!-- Modal header -->
        <div class="flex items-start justify-between p-4 border-b rounded-t dark:border-gray-600">
          <h3 class="text-xl font-semibold text-gray-900 dark:text-white">Auto Attendant</h3>
          <button
            type="button"
            class="text-gray-400 bg-transparent hover:bg-gray-200 hover:text-gray-900 rounded-lg text-sm w-8 h-8 ml-auto inline-flex justify-center items-center dark:hover:bg-gray-600 dark:hover:text-white"
            on:click={() => (editing = false)}
          >
            <svg
              class="w-3 h-3"
              aria-hidden="true"
              xmlns="http://www.w3.org/2000/svg"
              fill="none"
              viewBox="0 0 14 14"
            >
              <path
                stroke="currentColor"
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="m1 1 6 6m0 0 6 6M7 7l6-6M7 7l-6 6"
              />
            </svg>
            <span class="sr-only">Close modal</span>
          </button>
        </div>
        <!-- Modal body -->
        <div class="p-6 space-y-6">
          <p class="text-left text-lg font-medium text-white">Prompt Audio:</p>
          <div class="flex items-center space-x-6">
            <MediaUploadRecord
              audioUrl={audioRecordingURLs.promptAudioURL}
              nodeId={node.data.id}
              on:audioChange={onPromptAudioChange}
            />
          </div>
          <p class="text-left text-lg font-medium text-white pb--2 mb--1">Error Audio:</p>
          <div class="flex items-center space-x-6">
            <!-- <p class="text-center text-lg font-medium">Upload audio file / record audio</p> Add this line just above the audio tag -->
            <MediaUploadRecord
              audioUrl={audioRecordingURLs.errorAudioURL}
              nodeId={node.data.id}
              on:audioChange={onErrorAudioChange}
            />
          </div>
          <div class="space-y-6">
            <label
              for="repeat"
              class="block mb-2 text-sm font-medium text-gray-900 dark:text-white"
            >
              Repeat Error Audio
            </label>
            <input
              type="number"
              id="repeat"
              class="bg-gray-50 border border-gray-300 text-gray-900 text-sm rounded-lg focus:ring-blue-500 focus:border-blue-500 block w-full p-2.5 dark:bg-gray-700 dark:border-gray-600 dark:placeholder-gray-400 dark:text-white dark:focus:ring-blue-500 dark:focus:border-blue-500"
              placeholder="3"
              required
              bind:value={editData.data.repeat}
            />
            <label
              for="multiDigitWaitTime"
              class="block mb-2 text-sm font-medium text-gray-900 dark:text-white"
            >
              Wait time after prompt
            </label>
            <input
              type="number"
              id="multiDigitWaitTime"
              class="bg-gray-50 border border-gray-300 text-gray-900 text-sm rounded-lg focus:ring-blue-500 focus:border-blue-500 block w-full p-2.5 dark:bg-gray-700 dark:border-gray-600 dark:placeholder-gray-400 dark:text-white dark:focus:ring-blue-500 dark:focus:border-blue-500"
              placeholder="3"
              required
              bind:value={editData.data.afterPromptWaitTime}
            />
            <label
              for="multiDigitWaitTime"
              class="block mb-2 text-sm font-medium text-gray-900 dark:text-white"
            >
              Multi Digit wait time
            </label>
            <input
              type="number"
              id="multiDigitWaitTime"
              class="bg-gray-50 border border-gray-300 text-gray-900 text-sm rounded-lg focus:ring-blue-500 focus:border-blue-500 block w-full p-2.5 dark:bg-gray-700 dark:border-gray-600 dark:placeholder-gray-400 dark:text-white dark:focus:ring-blue-500 dark:focus:border-blue-500"
              placeholder="3"
              required
              bind:value={editData.data.multiDigitWaitTime}
            />
          </div>
        </div>
        <!-- Modal footer -->
        <div
          class="flex items-center p-6 space-x-2 border-t border-gray-200 rounded-b dark:border-gray-600"
        >
          <button
            data-modal-hide="defaultModal"
            type="button"
            on:click={onUpdate}
            class="text-white bg-blue-700 hover:bg-blue-800 focus:ring-4 focus:outline-none focus:ring-blue-300 font-medium rounded-lg text-sm px-5 py-2.5 text-center dark:bg-blue-600 dark:hover:bg-blue-700 dark:focus:ring-blue-800"
          >
            Save
          </button>
          <button
            data-modal-hide="defaultModal"
            type="button"
            on:click={() => (editing = false)}
            class="text-gray-500 bg-white hover:bg-gray-100 focus:ring-4 focus:outline-none focus:ring-blue-300 rounded-lg border border-gray-200 text-sm font-medium px-5 py-2.5 hover:text-gray-900 focus:z-10 dark:bg-gray-700 dark:text-gray-300 dark:border-gray-500 dark:hover:text-white dark:hover:bg-gray-600 dark:focus:ring-gray-600"
          >
            Cancel
          </button>
        </div>
      </div>
    </div>
  </div>
{/if}

<style>
  @keyframes pulse {
    0%,
    100% {
      opacity: 1;
    }
    50% {
      opacity: 0.5;
    }
  }
</style>
