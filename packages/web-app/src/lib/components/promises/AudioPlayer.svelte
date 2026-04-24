<script lang="ts">
  export let url: string;
  export let currentParty: string;
  export let isPlaying: boolean = false;
  export let currentTime: number = 0;
  export let duration: number = 0;

  let audioElement: HTMLAudioElement | null = null;

  function getDisplayName(party: string): string {
    if (party.startsWith('+')) return party;
    return party.split('@')[0].split('_')[0];
  }

  function formatTime(seconds: number): string {
    const mins = Math.floor(seconds / 60);
    const secs = Math.floor(seconds % 60);
    return `${mins}:${secs.toString().padStart(2, '0')}`;
  }

  function togglePlayPause() {
    if (!audioElement) return;

    if (isPlaying) {
      audioElement.pause();
    } else {
      audioElement.play();
    }
    isPlaying = !isPlaying;
  }

  function handleTimeUpdate() {
    if (audioElement) {
      currentTime = audioElement.currentTime;
    }
  }

  function handleLoadedMetadata() {
    if (audioElement) {
      duration = audioElement.duration;
    }
  }

  function handleEnded() {
    isPlaying = false;
  }

  function seekAudio(event: MouseEvent) {
    if (!audioElement || !duration) return;

    const rect = (event.currentTarget as HTMLElement).getBoundingClientRect();
    const percentage = (event.clientX - rect.left) / rect.width;
    audioElement.currentTime = percentage * duration;
  }
</script>

<div
  class="bg-slate-200 dark:bg-gray-700 rounded-lg p-4 border border-slate-400 dark:border-gray-600 shadow-sm"
>
  <audio
    bind:this={audioElement}
    src={url}
    on:timeupdate={handleTimeUpdate}
    on:loadedmetadata={handleLoadedMetadata}
    on:ended={handleEnded}
    class="hidden"
  />

  <!-- Speaker Info & Controls Container -->
  <div class="flex items-center justify-between gap-4">
    <!-- Left: Speaker Info -->
    <div class="flex items-center space-x-3">
      <div class="bg-blue-600 rounded-full p-2.5 shadow-md">
        <svg class="w-4 h-4 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z"
          ></path>
        </svg>
      </div>
      <div>
        <p class="text-xs font-medium text-slate-500 dark:text-slate-400">Speaker</p>
        <p class="text-sm font-bold text-gray-900 dark:text-white">
          {getDisplayName(currentParty)}
        </p>
      </div>
    </div>

    <!-- Right: Player Controls -->
    <div class="flex-1 flex items-center space-x-3">
      <!-- Play/Pause Button -->
      <button
        on:click={togglePlayPause}
        class="flex-shrink-0 w-10 h-10 flex items-center justify-center bg-indigo-600 hover:bg-indigo-700 rounded-full shadow-md transition-all duration-200 transform hover:scale-105"
      >
        {#if isPlaying}
          <svg class="w-5 h-5 text-white" fill="currentColor" viewBox="0 0 24 24">
            <path d="M6 4h4v16H6V4zm8 0h4v16h-4V4z"></path>
          </svg>
        {:else}
          <svg class="w-5 h-5 text-white ml-0.5" fill="currentColor" viewBox="0 0 24 24">
            <path d="M8 5v14l11-7z"></path>
          </svg>
        {/if}
      </button>

      <!-- Progress Bar with Time -->
      <div class="flex-1 space-y-1">
        <!-- svelte-ignore a11y-click-events-have-key-events -->
        <!-- svelte-ignore a11y-no-static-element-interactions -->
        <div
          class="h-2 bg-slate-400 dark:bg-gray-600 rounded-full cursor-pointer relative overflow-hidden group"
          on:click={seekAudio}
        >
          <div
            class="h-full bg-indigo-600 rounded-full transition-all duration-100"
            style="width: {duration > 0 ? (currentTime / duration) * 100 : 0}%"
          ></div>
          <div
            class="absolute top-1/2 -translate-y-1/2 w-3.5 h-3.5 bg-white dark:bg-gray-200 rounded-full shadow-md border-2 border-indigo-600 opacity-0 group-hover:opacity-100 transition-opacity"
            style="left: {duration > 0 ? (currentTime / duration) * 100 : 0}%"
          ></div>
        </div>
        <div class="flex justify-between text-xs font-medium text-slate-600 dark:text-slate-400">
          <span>{formatTime(currentTime)}</span>
          <span>{formatTime(duration)}</span>
        </div>
      </div>
    </div>
  </div>
</div>
