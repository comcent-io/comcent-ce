<script lang="ts">
  import AudioPlayer from './AudioPlayer.svelte';

  interface AudioRecording {
    url: string;
    fileName: string;
    currentParty: string;
  }

  export let recordings: AudioRecording[] = [];
</script>

<div
  class="bg-slate-100 dark:bg-gray-800 rounded-lg shadow-sm border border-slate-400 dark:border-gray-700 p-4 mb-4"
>
  <div class="flex items-center space-x-2 mb-3">
    <div class="bg-indigo-600 rounded-lg p-2 shadow-md">
      <svg class="w-4 h-4 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path
          stroke-linecap="round"
          stroke-linejoin="round"
          stroke-width="2"
          d="M9 19V6l12-3v13M9 19c0 1.105-1.343 2-3 2s-3-.895-3-2 1.343-2 3-2 3 .895 3 2zm12-3c0 1.105-1.343 2-3 2s-3-.895-3-2 1.343-2 3-2 3 .895 3 2zM9 10l12-3"
        ></path>
      </svg>
    </div>
    <h3 class="text-sm font-bold text-gray-900 dark:text-white">Call Recordings</h3>
    {#if recordings.length > 0}
      <span class="text-xs text-slate-500 dark:text-slate-400">
        ({recordings.length}
        {recordings.length === 1 ? 'recording' : 'recordings'})
      </span>
    {/if}
  </div>

  {#if recordings.length > 0}
    <div class="space-y-3">
      {#each recordings as recording}
        <AudioPlayer url={recording.url} currentParty={recording.currentParty} />
      {/each}
    </div>
  {:else}
    <div class="p-6 text-center bg-slate-100 dark:bg-gray-800 rounded-lg">
      <div class="bg-slate-200 dark:bg-gray-700 rounded-full p-4 mb-3 shadow-inner inline-block">
        <svg
          class="w-8 h-8 text-slate-400 dark:text-slate-500"
          fill="none"
          stroke="currentColor"
          viewBox="0 0 24 24"
        >
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M9 19V6l12-3v13M9 19c0 1.105-1.343 2-3 2s-3-.895-3-2 1.343-2 3-2 3 .895 3 2zm12-3c0 1.105-1.343 2-3 2s-3-.895-3-2 1.343-2 3-2 3 .895 3 2zM9 10l12-3"
          ></path>
        </svg>
      </div>
      <p class="text-sm font-semibold text-gray-900 dark:text-white mb-1">
        No Recordings Available
      </p>
      <p class="text-xs text-slate-500 dark:text-slate-400">
        No audio recordings found for this call
      </p>
    </div>
  {/if}
</div>
