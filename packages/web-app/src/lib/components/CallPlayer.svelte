<script lang="ts">
  import PauseIcon from '$lib/components/Icons/PauseIcon.svelte';
  import { INITIAL_SCALE, scale } from '$lib/scaleStore.js';
  import PlayIcon from '$lib/components/Icons/PlayIcon.svelte';
  import { page } from '$app/stores';

  export let callSpan;
  let localScale = INITIAL_SCALE;
  scale.subscribe((value) => {
    localScale = value;
  });

  $: recordUrl = `/api/v2/${$page.params.subdomain}/call-story/${callSpan.callStoryId}/record/${callSpan.metadata.fileName}`;

  $: playerWidth = localScale * (callSpan.relativeEndAt - audioRelativeStartTime);

  const fullWaveHeight = 20;
  const waveIncrement = 3;
  let waveData = [];
  $: {
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
    waveData = points;
  }

  let playing = false;

  let audio;

  function onPlayButtonClick() {
    if (playing) {
      audio.pause();
    } else {
      audio.play();
    }
    playing = !playing;
  }

  let currentTime = 0;

  function onTimeUpdate(event) {
    currentTime = event.target.currentTime;
  }

  function onClickSeekBar(event) {
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

  function onMouseMoveSeekBar(event) {
    if (!seekBarDown) {
      return;
    }
    audio.currentTime =
      (event.clientX - event.currentTarget.getBoundingClientRect().left) / localScale;
  }

  let audioRelativeStartTime = callSpan?.relativeStartAt ?? 0;
  function onDurationChange(event) {
    const duration = event.target.duration;
    if (!isNaN(duration) && duration !== Infinity && callSpan) {
      audioRelativeStartTime = callSpan.relativeEndAt - duration;
    }
  }
</script>

<div class="relative">
  <div
    class="relative flex"
    style=" transform: translateX({localScale * audioRelativeStartTime}px);"
  >
    <div
      class="mb-1 bg-gray-200 dark:bg-gray-700 overflow-hidden inline-block"
      style="height: {fullWaveHeight}px; width: {playerWidth}px;"
      on:click={onClickSeekBar}
      on:mousedown={onMouseDownSeekBar}
      on:mouseup={onMouseUpSeekBar}
      on:mousemove={onMouseMoveSeekBar}
      on:keydown={onClickSeekBar}
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
      on:click={onPlayButtonClick}
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
      on:timeupdate={onTimeUpdate}
      on:durationchange={onDurationChange}
    />
  </div>
</div>
