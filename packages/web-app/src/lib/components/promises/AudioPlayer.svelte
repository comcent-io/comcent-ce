<script lang="ts">
  import PartyAvatar from '$lib/components/PartyAvatar.svelte';

  interface Props {
    url: string;
    currentParty: string;
    isPlaying?: boolean;
    currentTime?: number;
    duration?: number;
  }

  let {
    url,
    currentParty,
    isPlaying = $bindable(false),
    currentTime = $bindable(0),
    duration = $bindable(0),
  }: Props = $props();

  let audioElement: HTMLAudioElement | null = $state(null);

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
  class="rounded-lg border border-gray-200 bg-gray-50 p-4 dark:border-gray-700 dark:bg-gray-900/40"
>
  <audio
    bind:this={audioElement}
    src={url}
    ontimeupdate={handleTimeUpdate}
    onloadedmetadata={handleLoadedMetadata}
    onended={handleEnded}
    class="hidden"
  ></audio>

  <!-- Speaker Info & Controls Container -->
  <div class="flex items-center justify-between gap-4">
    <!-- Left: Speaker Info -->
    <div class="flex items-center gap-3">
      <PartyAvatar party={currentParty} />
      <div>
        <p class="text-xs text-gray-500 dark:text-gray-400">Speaker</p>
        <p class="text-sm font-medium text-gray-900 dark:text-white">
          {getDisplayName(currentParty)}
        </p>
      </div>
    </div>

    <!-- Right: Player Controls -->
    <div class="flex-1 flex items-center space-x-3">
      <!-- Play/Pause Button -->
      <button
        type="button"
        aria-label={isPlaying ? 'Pause' : 'Play'}
        onclick={togglePlayPause}
        class="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-blue-700 hover:bg-blue-800 focus:outline-none focus:ring-4 focus:ring-blue-300 dark:bg-blue-600 dark:hover:bg-blue-700 dark:focus:ring-blue-800"
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
        <!-- svelte-ignore a11y_click_events_have_key_events -->
        <!-- svelte-ignore a11y_no_static_element_interactions -->
        <div
          class="group relative h-2 cursor-pointer overflow-hidden rounded-full bg-gray-200 dark:bg-gray-600"
          onclick={seekAudio}
        >
          <div
            class="h-full rounded-full bg-blue-600 transition-all duration-100 dark:bg-blue-500"
            style="width: {duration > 0 ? (currentTime / duration) * 100 : 0}%"
          ></div>
          <div
            class="absolute top-1/2 h-3.5 w-3.5 -translate-y-1/2 rounded-full border-2 border-blue-600 bg-white opacity-0 shadow-md transition-opacity group-hover:opacity-100"
            style="left: {duration > 0 ? (currentTime / duration) * 100 : 0}%"
          ></div>
        </div>
        <div class="flex justify-between text-xs tabular-nums text-gray-500 dark:text-gray-400">
          <span>{formatTime(currentTime)}</span>
          <span>{formatTime(duration)}</span>
        </div>
      </div>
    </div>
  </div>
</div>
