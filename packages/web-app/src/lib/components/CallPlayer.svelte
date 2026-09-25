<script lang="ts">
  import PauseIcon from '$lib/components/Icons/PauseIcon.svelte';
  import { INITIAL_SCALE, scale } from '$lib/scaleStore.js';
  import PlayIcon from '$lib/components/Icons/PlayIcon.svelte';
  import { page } from '$app/state';

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  let { callSpan }: { callSpan: any } = $props();
  let localScale = $state(INITIAL_SCALE);
  scale.subscribe((value) => {
    localScale = value;
  });

  const fullWaveHeight = 20;
  const waveIncrement = 3;

  let playing = $state(false);

  let audio: HTMLAudioElement | undefined = $state();

  function onPlayButtonClick() {
    if (playing) {
      audio?.pause();
    } else {
      audio?.play();
    }
    playing = !playing;
  }

  let currentTime = $state(0);

  function onTimeUpdate(event: Event) {
    currentTime = (event.target as HTMLAudioElement).currentTime;
  }

  function onClickSeekBar(event: Event & { currentTarget: HTMLElement }) {
    // Seeking needs a pointer position; a key press has none.
    if (!audio || !(event instanceof MouseEvent)) return;
    audio.currentTime =
      (event.clientX - event.currentTarget.getBoundingClientRect().left) / localScale;
  }

  let seekBarDown = false;

  function onMouseDownSeekBar() {
    seekBarDown = true;
  }

  function onMouseUpSeekBar() {
    seekBarDown = false;
  }

  function onMouseMoveSeekBar(event: MouseEvent & { currentTarget: HTMLElement }) {
    if (!seekBarDown) {
      return;
    }
    if (!audio) return;
    audio.currentTime =
      (event.clientX - event.currentTarget.getBoundingClientRect().left) / localScale;
  }

  // Corrected once the audio's real duration is known.
  // svelte-ignore state_referenced_locally
  let audioRelativeStartTime = $state(callSpan?.relativeStartAt ?? 0);
  function onDurationChange(event: Event) {
    const duration = (event.target as HTMLAudioElement).duration;
    if (!isNaN(duration) && duration !== Infinity && callSpan) {
      audioRelativeStartTime = callSpan.relativeEndAt - duration;
    }
  }
  let recordUrl = $derived(
    `/api/v2/${page.params.subdomain}/call-story/${callSpan.callStoryId}/record/${callSpan.metadata.fileName}`,
  );
  let playerWidth = $derived(localScale * (callSpan.relativeEndAt - audioRelativeStartTime));
  let waveData = $derived.by(() => {
    const points = [];
    for (let i = 0; i < playerWidth; i += waveIncrement) {
      const height = Math.max(5, Math.random() * fullWaveHeight);
      points.push({
        x: i,
        y: (fullWaveHeight - height) / 2,
        height: height,
        width: 2,
      });
    }
    return points;
  });
</script>

<div class="relative">
  <div
    class="relative flex"
    style=" transform: translateX({localScale * audioRelativeStartTime}px);"
  >
    <div
      class="mb-1 bg-gray-200 dark:bg-gray-700 overflow-hidden inline-block"
      style="height: {fullWaveHeight}px; width: {playerWidth}px;"
      onclick={onClickSeekBar}
      onmousedown={onMouseDownSeekBar}
      onmouseup={onMouseUpSeekBar}
      onmousemove={onMouseMoveSeekBar}
      onkeydown={onClickSeekBar}
      role="button"
      tabindex="-1"
    >
      <svg
        aria-hidden="true"
        class="w-[{playerWidth}px] md:h-[{fullWaveHeight}px]"
        viewBox="0 0 {playerWidth} {fullWaveHeight}"
        fill="none"
        xmlns="http://www.w3.org/2000/svg"
      >
        {#each waveData as point}
          <rect
            x={point.x}
            y={point.y}
            width={point.width}
            height={point.height}
            rx="1.5"
            fill="#6B7280"
            class={point.x < currentTime * localScale ? 'dark:fill-white' : 'dark:fill-gray'}
          />
        {/each}
      </svg>
      <div class="bg-red-500" style="height: 6px; width: {localScale * currentTime}px;"></div>
    </div>
    <button
      onclick={onPlayButtonClick}
      class="text-gray-900 dark:text-white font-medium rounded-full text-sm p-1 text-center inline-flex items-center"
    >
      {#if playing}
        <PauseIcon />
      {:else}
        <PlayIcon />
      {/if}
      <span class="sr-only">Icon description</span>
    </button>
    <audio
      bind:this={audio}
      src={recordUrl}
      ontimeupdate={onTimeUpdate}
      ondurationchange={onDurationChange}
    ></audio>
  </div>
</div>
