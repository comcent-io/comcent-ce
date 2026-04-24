<script lang="ts">
  import TranscriptBubble from '$lib/components/TranscriptBubble.svelte';

  interface TranscriptChat {
    currentParty: string;
    message: string;
  }

  export let transcriptData: { transcriptChat?: TranscriptChat[] } | null = null;

  function getDisplayName(currentParty: string): string {
    if (currentParty.startsWith('+')) return currentParty;
    return currentParty.split('@')[0].split('_')[0];
  }

  $: hasTranscript =
    transcriptData &&
    transcriptData.transcriptChat &&
    Array.isArray(transcriptData.transcriptChat) &&
    transcriptData.transcriptChat.length > 0;
</script>

<div
  class="bg-slate-100 dark:bg-gray-800 rounded-lg shadow-sm border border-slate-400 dark:border-gray-700 overflow-hidden"
>
  <div
    class="bg-slate-200 dark:bg-gray-700 px-4 py-3 border-b border-slate-400 dark:border-gray-600"
  >
    <div class="flex items-center space-x-2">
      <div class="bg-emerald-600 rounded-lg p-2 shadow-md">
        <svg class="w-4 h-4 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M8 10h.01M12 10h.01M16 10h.01M9 16H5a2 2 0 01-2-2V6a2 2 0 012-2h14a2 2 0 012 2v8a2 2 0 01-2 2h-5l-5 5v-5z"
          ></path>
        </svg>
      </div>
      <h3 class="text-sm font-bold text-gray-900 dark:text-white">Conversation Transcript</h3>
    </div>
  </div>

  {#if hasTranscript && transcriptData?.transcriptChat}
    <div
      class="p-3 max-h-[280px] overflow-y-auto space-y-0.5 custom-scrollbar bg-slate-200 dark:bg-gray-800"
    >
      {#each transcriptData.transcriptChat as chat}
        <TranscriptBubble name={getDisplayName(chat.currentParty)} message={chat.message} />
      {/each}
    </div>
  {:else}
    <div
      class="flex flex-col items-center justify-center p-8 text-center bg-slate-200 dark:bg-gray-800"
    >
      <div class="bg-slate-200 dark:bg-gray-700 rounded-full p-4 mb-3 shadow-inner">
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
            d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z"
          ></path>
        </svg>
      </div>
      <p class="text-sm font-semibold text-gray-900 dark:text-white mb-1">
        No Transcript Available
      </p>
      <p class="text-xs text-slate-500 dark:text-slate-400">This call was not transcribed</p>
    </div>
  {/if}
</div>

<style>
  .custom-scrollbar::-webkit-scrollbar {
    width: 6px;
  }

  .custom-scrollbar::-webkit-scrollbar-track {
    background: transparent;
  }

  .custom-scrollbar::-webkit-scrollbar-thumb {
    background: #cbd5e1;
    border-radius: 3px;
  }

  .custom-scrollbar::-webkit-scrollbar-thumb:hover {
    background: #94a3b8;
  }

  :global(.dark) .custom-scrollbar::-webkit-scrollbar-thumb {
    background: #475569;
  }

  :global(.dark) .custom-scrollbar::-webkit-scrollbar-thumb:hover {
    background: #64748b;
  }
</style>
