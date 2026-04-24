<script lang="ts">
  import moment from 'moment-timezone';
  import CallStory from '$lib/components/CallStory.svelte';
  import Transcript from './Transcript.svelte';
  import Summary from './Summary.svelte';
  import type { CallStoryFromServer } from '$lib/types/CallStoryFromServer.js';
  import Dialog from '$lib/components/Dialog.svelte';
  import Sentiment from './Sentiment.svelte';

  export let callStory: CallStoryFromServer;

  let showDropdown = false;

  let modalContent = '';
  let modelTitle = '';
  $: {
    if (modalContent === 'CALL_GRAPH') {
      modelTitle = 'Call Graph';
    } else if (modalContent === 'SHOW_TRANSCRIPTION') {
      modelTitle = 'Transcription';
    } else if (modalContent === 'SHOW_SUMMARY') {
      modelTitle = 'Summary';
    } else if (modalContent === 'SHOW_SENTIMENT') {
      modelTitle = 'Sentiment';
    }
  }
</script>

<tr
  class="odd:bg-white odd:dark:bg-gray-900 even:bg-gray-50 even:dark:bg-gray-800 border-b dark:border-gray-700"
>
  <td class="px-6 py-4">{moment(callStory.startAt).format('YYYY/MM/DD hh:mm a')}</td>
  <td class="px-6 py-4">{callStory.direction}</td>
  <td class="px-6 py-4">{callStory.caller}</td>
  <td class="px-6 py-4">{callStory.callee}</td>
  <td class="px-6 py-4 relative">
    <button
      class="inline-flex items-center p-2 text-sm font-medium text-center text-gray-900 bg-white rounded-lg hover:bg-gray-100 focus:ring-4 focus:outline-none dark:text-white focus:ring-gray-50 dark:bg-gray-800 dark:hover:bg-gray-700 dark:focus:ring-gray-600"
      type="button"
      on:click={() => (showDropdown = !showDropdown)}
    >
      <svg
        class="w-5 h-5"
        aria-hidden="true"
        xmlns="http://www.w3.org/2000/svg"
        fill="currentColor"
        viewBox="0 0 4 15"
      >
        <path
          d="M3.5 1.5a1.5 1.5 0 1 1-3 0 1.5 1.5 0 0 1 3 0Zm0 6.041a1.5 1.5 0 1 1-3 0 1.5 1.5 0 0 1 3 0Zm0 5.959a1.5 1.5 0 1 1-3 0 1.5 1.5 0 0 1 3 0Z"
        />
      </svg>
    </button>

    <!-- Dropdown menu -->
    {#if showDropdown}
      <div
        class="absolute z-50 bg-white divide-y divide-gray-100 rounded-lg shadow w-44 dark:bg-gray-700 dark:divide-gray-600 right-0 bottom-14"
      >
        <ul
          class="py-2 text-sm text-gray-700 dark:text-gray-200"
          aria-labelledby="dropdownMenuIconButton"
        >
          <li>
            <button
              class="block w-full px-4 py-2 hover:bg-gray-100 dark:hover:bg-gray-600 dark:hover:text-white"
              on:click={() => {
                modalContent = 'CALL_GRAPH';
                showDropdown = false;
              }}
            >
              Call Graph
            </button>
          </li>

          {#if callStory.isTranscribed}
            <button
              class="block w-full px-4 py-2 hover:bg-gray-100 dark:hover:bg-gray-600 dark:hover:text-white"
              on:click={() => {
                modalContent = 'SHOW_TRANSCRIPTION';
                showDropdown = false;
              }}
            >
              Show Transcription
            </button>
          {/if}
          {#if callStory.isSummarized}
            <button
              class="block w-full px-4 py-2 hover:bg-gray-100 dark:hover:bg-gray-600 dark:hover:text-white"
              on:click={() => {
                modalContent = 'SHOW_SUMMARY';
                showDropdown = false;
              }}
            >
              Show Summary
            </button>
          {/if}
          {#if callStory.isSentimentAnalyzed}
            <button
              class="block w-full px-4 py-2 hover:bg-gray-100 dark:hover:bg-gray-600 dark:hover:text-white"
              on:click={() => {
                modalContent = 'SHOW_SENTIMENT';
                showDropdown = false;
              }}
            >
              Show Sentiment
            </button>
          {/if}
        </ul>
      </div>
    {/if}
  </td>
</tr>

{#if modalContent === 'CALL_GRAPH'}
  <Dialog
    title={modelTitle}
    on:close={() => (modalContent = '')}
    showDialog={!!modalContent}
    className="w-full"
  >
    <CallStory {callStory} />
  </Dialog>
{:else if modalContent === 'SHOW_TRANSCRIPTION'}
  <Dialog title={modelTitle} on:close={() => (modalContent = '')} showDialog={!!modalContent}>
    <Transcript callStoryId={callStory.id} />
  </Dialog>
{:else if modalContent === 'SHOW_SUMMARY'}
  <Dialog title={modelTitle} on:close={() => (modalContent = '')} showDialog={!!modalContent}>
    <Summary callStoryId={callStory.id} />
  </Dialog>
{:else if modalContent === 'SHOW_SENTIMENT'}
  <Dialog title={modelTitle} on:close={() => (modalContent = '')} showDialog={!!modalContent}>
    <Sentiment callStoryId={callStory.id} />
  </Dialog>
{:else}
  <Dialog
    title="Something went wrong"
    on:close={() => (modalContent = '')}
    showDialog={!!modalContent}
  >
    Something went wrong
  </Dialog>
{/if}
