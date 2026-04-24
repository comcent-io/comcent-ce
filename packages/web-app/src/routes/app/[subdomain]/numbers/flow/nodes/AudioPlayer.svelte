<script lang="ts">
  import { onDestroy } from 'svelte';

  export let src = '';
  let audio: any = null;
  let isPlaying = false;
  let isAudioInitialized = false;

  function handleButtonClick(event: any) {
    event.stopPropagation();
    togglePlay();
  }

  function togglePlay() {
    if (!isAudioInitialized) {
      audio = new Audio(src);
      isAudioInitialized = true;
      audio.addEventListener('ended', () => {
        isPlaying = false;
      });
    }
    if (isPlaying) {
      audio.pause();
    } else {
      audio.play();
    }
    isPlaying = !isPlaying;
  }

  onDestroy(() => {
    if (audio) {
      audio.pause();
      audio.currentTime = 0;
    }
  });
</script>

<button type="button" on:click={handleButtonClick} class="icon-button">
  {#if isPlaying}
    <svg
      width="25px"
      height="25px"
      viewBox="0 0 36 36"
      xmlns="http://www.w3.org/2000/svg"
      xmlns:xlink="http://www.w3.org/1999/xlink"
      aria-hidden="true"
      role="img"
      class="iconify iconify--twemoji"
      preserveAspectRatio="xMidYMid meet"
    >
      <path
        fill="#3B88C3"
        d="M36 32a4 4 0 0 1-4 4H4a4 4 0 0 1-4-4V4a4 4 0 0 1 4-4h28a4 4 0 0 1 4 4v28z"
      ></path>
      <path fill="#FFF" d="M20 7h5v22h-5zm-9 0h5v22h-5z"></path>
    </svg>
  {:else}
    <svg
      width="25px"
      height="25px"
      viewBox="0 0 36 36"
      xmlns="http://www.w3.org/2000/svg"
      xmlns:xlink="http://www.w3.org/1999/xlink"
      aria-hidden="true"
      role="img"
      class="iconify iconify--twemoji"
      preserveAspectRatio="xMidYMid meet"
    >
      <path
        fill="#3B88C3"
        d="M36 32a4 4 0 0 1-4 4H4a4 4 0 0 1-4-4V4a4 4 0 0 1 4-4h28a4 4 0 0 1 4 4v28z"
      ></path>
      <path fill="#FFF" d="M8 7l22 11L8 29z"></path>
    </svg>
  {/if}
</button>

<style>
  .icon-button {
    /* Style your button */
    background: none;
    border: none;
    cursor: pointer;
    font-size: 24px; /* Adjust the size of the emoji */
  }
</style>
