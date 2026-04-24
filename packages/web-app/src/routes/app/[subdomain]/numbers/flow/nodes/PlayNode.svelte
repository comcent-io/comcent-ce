<script lang="ts">
  import { createEventDispatcher, onMount } from 'svelte';
  import type { SelectedOutlet } from '../SelectedOutlet';
  import type { PlayNode } from './PlayNode';
  import { page } from '$app/stores';
  import Draggable from '../utils/Draggable.svelte';
  import Inlet from '../utils/Inlet.svelte';
  import CloseButton from '../utils/CloseButton.svelte';
  import EditButton from '../utils/EditButton.svelte';
  import AudioPlayer from './AudioPlayer.svelte';
  import { deleteS3File, extractFilenameFromS3Url } from '../utils/DeleteUploads';
  import MediaUploadRecord from '$lib/components/MediaUploadRecord.svelte';
  import { getPlaybackUrl } from '$lib/playback';
  import type { AudioChangePayload } from '../AudioChangedPayload';
  import { uploadRecording } from '../uploadRecording';

  const dispatch = createEventDispatcher();
  export let node: PlayNode;
  export let selectedOutlet: SelectedOutlet | null;
  export let inletConnected = false;
  export let inletConnectable = false;
  let editData = JSON.parse(JSON.stringify(node.data));
  let editing = false;
  let deleteFileName = '';
  let savedMediaURL = '';
  const subdomain = $page.params.subdomain;

  let changedAudio: AudioChangePayload | undefined;

  export async function triggerUpload() {
    if (changedAudio) {
      dispatch('statusChanged', { nodeId: node.data.id, status: 'uploading' });
      const s3Url = await uploadRecording($page.params.subdomain, changedAudio);
      dispatch('statusChanged', { nodeId: node.data.id, status: 'completed' });
      if (s3Url) {
        node.data = editData;
        editing = false;
        node.data.data.media = s3Url; // Update the node data with the S3 URL
        if (deleteFileName) {
          await deleteS3File(subdomain, deleteFileName);
        }
        dispatch('updated', { node: node });
      } else {
        throw Error('User is not a member of this org');
      }
    } else {
      console.log('skip uploading');
    }
  }

  onMount(async () => {
    if (node.data.data.media && node.data.data.media.startsWith('s3://')) {
      const fileName = extractFilenameFromS3Url(node.data.data.media);
      savedMediaURL = getPlaybackUrl(subdomain, fileName);
    }
  });

  function onAudioChange(e: CustomEvent) {
    changedAudio = e.detail;
  }

  function onUpdate() {
    node.data = editData;
    editing = false;
    if (changedAudio) {
      if (node.data.data.media) {
        deleteFileName = node.data.data.media;
      }
    }
    dispatch('updated', { node: node });
  }
</script>

<Draggable
  {node}
  title={node.data.type}
  class="block w-[17rem] rounded-lg border-2 border-amber-400 bg-white shadow dark:border-amber-400 dark:bg-gray-800"
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
    <div class="space-y-1 p-3">
      {#if savedMediaURL}
        <div class="flex items-center gap-2">
          <h3 class="text-sm font-medium dark:text-white">Media:</h3>
          <AudioPlayer src={savedMediaURL} />
        </div>
      {/if}
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
          <h3 class="text-xl font-semibold text-gray-900 dark:text-white">Play</h3>
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
          <p class="text-left text-lg font-medium text-white">Upload audio file / Record audio</p>

          <div class="flex items-center space-x-6">
            <!-- <p class="text-center text-lg font-medium">Upload audio file / record audio</p> Add this line just above the audio tag -->
            <MediaUploadRecord
              nodeId={node.data.id}
              audioUrl={savedMediaURL}
              on:audioChange={onAudioChange}
            />
            <!-- Separate container for the duration text with reserved space -->
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
