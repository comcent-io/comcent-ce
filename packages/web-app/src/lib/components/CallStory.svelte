<script lang="ts">
  import { onMount } from 'svelte';
  import { JsonView } from '@zerodevx/svelte-json-view';
  import _ from 'lodash';
  import EventRow from './EventRow.svelte';
  import CallStoryUserRow from '$lib/components/CallStoryUserRow.svelte';
  import CallTimeline from '$lib/components/CallTimeline.svelte';
  import VerticalLineTimer from '$lib/components/VerticalLineTimer.svelte';
  import type { CallStoryFromServer } from '$lib/types/CallStoryFromServer';
  import moment from 'moment-timezone';
  import { scale } from '$lib/scaleStore';

  let localScale = 1;
  $: {
    scale.set(localScale);
  }

  export let callStory: CallStoryFromServer;
  let channelGroup: any; // For Debug
  let spansByUsers = {};

  // Timeline calculations
  let callDuration = 0;

  // Mouse tracking for vertical line
  let callStoryContainer: HTMLElement;
  let mousePosition = 0;
  let currentTime = 0;
  let isHovering = false;

  $: {
    if (callStory?.callSpans?.length > 0) {
      const sortedSpans = _.sortBy(callStory.callSpans, 'startAt');
      const startTime = new Date(sortedSpans[0].startAt).getTime();
      const lastSpan = sortedSpans[sortedSpans.length - 1];
      const endTime = lastSpan.endAt ? new Date(lastSpan.endAt).getTime() : new Date().getTime();
      callDuration = Math.ceil((endTime - startTime) / 1000); // Duration in seconds
    }
  }

  onMount(() => {
    const enhancedSpans = setSpanRelativeTime(callStory.callSpans);
    spansByUsers = _.groupBy(enhancedSpans, 'currentParty');
    console.log('spansByUsers', spansByUsers);
  });

  function setSpanRelativeTime(spans: any[]) {
    const sortedSpan = _.sortBy(spans, 'startAt');
    const firstTimestamp = new Date(sortedSpan[0].startAt).getTime();
    return sortedSpan.map((s) => {
      const relativeStartAt = Math.round((new Date(s.startAt).getTime() - firstTimestamp) / 1000);
      const relativeEndAt = Math.round((new Date(s.endAt).getTime() - firstTimestamp) / 1000);
      return {
        ...s,
        relativeStartAt,
        relativeEndAt,
      };
    });
  }

  function handleMouseMove(event: MouseEvent) {
    if (!callStoryContainer) return;

    const rect = callStoryContainer.getBoundingClientRect();
    const x = event.clientX - rect.left;

    // Account for the grid layout: first column is 200px, second column is the timeline area
    // Also account for grid gap (5px)
    const firstColumnWidth = 200; // matches grid-template-columns: 200px 1fr
    const gridGap = 5; // matches grid-gap: 5px

    const timelineAreaX = x - firstColumnWidth - gridGap;
    const timelineAreaWidth = rect.width - firstColumnWidth - gridGap;

    // Only process if mouse is in the timeline area (second column)
    if (timelineAreaX >= 0) {
      // Set hovering to true when in timeline area
      isHovering = true;

      // Calculate the actual width of the timeline based on call duration and scale
      const actualTimelineWidth = callDuration * localScale;
      const maxTimelineWidth = Math.min(actualTimelineWidth, timelineAreaWidth);

      // Restrict cursor movement to only the width of the spans
      const clampedX = Math.max(0, Math.min(maxTimelineWidth, timelineAreaX));

      // Calculate percentage within the actual timeline width
      const percentage = Math.max(0, Math.min(100, (clampedX / maxTimelineWidth) * 100));

      // Convert to position relative to full container width
      const fullContainerPosition = ((firstColumnWidth + gridGap + clampedX) / rect.width) * 100;

      mousePosition = fullContainerPosition;
      currentTime = Math.round((percentage / 100) * callDuration);
    } else {
      // Mouse is in the first column, hide the line
      isHovering = false;
    }
  }

  function handleMouseEnter() {
    isHovering = true;
  }

  function handleMouseLeave() {
    isHovering = false;
  }

  let debug = false;
  let showJson = false;

  let counter = 1;
  function onHeadingClick() {
    counter++;
    debug = counter % 5 === 0;
  }
</script>

<div
  class="w-full p-4 bg-white border border-gray-200 rounded-lg shadow dark:bg-gray-800 dark:border-gray-700 mb-5"
>
  <h5 class="mb-2 text-2xl font-semibold tracking-tight text-gray-900 dark:text-white">
    Call
    <button on:click={onHeadingClick} class="text-transparent">:</button>
    <span class="text-xs">{callStory.id}</span>
  </h5>

  <div class="mb-4">
    <label for="default-range" class="block mb-2 text-sm font-medium text-gray-900 dark:text-white">
      Scale ({localScale})
    </label>
    <input
      id="default-range"
      bind:value={localScale}
      type="range"
      min="1"
      max="300"
      class="w-[28%] h-2 bg-gray-200 rounded-lg appearance-none cursor-pointer dark:bg-gray-700"
    />
  </div>

  <span class="text-sm text-gray-500 dark:text-gray-400">
    {moment(callStory.startAt).calendar()}
  </span>

  <div class="text-lg text-gray-500 dark:text-gray-400">
    {callStory.caller} &rarr; {callStory.callee} ({callStory.direction})
  </div>

  {#if callStory}
    <div>
      <div class="bg-white rounded-lg dark:bg-gray-800 overflow-x-auto">
        <div
          class="mb-5 call-story pt-5 relative"
          bind:this={callStoryContainer}
          on:mousemove={handleMouseMove}
          on:mouseenter={handleMouseEnter}
          on:mouseleave={handleMouseLeave}
          role="slider"
          tabindex="0"
          aria-label="Call timeline"
          aria-valuemin="0"
          aria-valuemax={callDuration}
          aria-valuenow={currentTime}
        >
          <!-- Timeline Component positioned above spans -->
          {#if callDuration > 0}
            <div></div>
            <!-- Empty first column -->
            <div class="mb-10">
              <div class="isolate">
                <div class="relative" style="height: 50px">
                  <CallTimeline {callDuration} scale={localScale} />
                </div>
              </div>
            </div>
          {/if}

          {#each Object.entries(spansByUsers) as [username, spans]}
            <CallStoryUserRow {spans} userName={username} />
          {/each}

          <!-- Vertical Line Timer Component positioned to cover timeline and spans -->
          <div class="absolute top-0 left-0 w-full h-full pointer-events-none" style="top: 20px;">
            <VerticalLineTimer isVisible={isHovering} position={mousePosition} {currentTime} />
          </div>
        </div>

        {#if debug}
          <h6 class="text-lg font-bold dark:text-white">Debug: {callStory.id}</h6>
          {#each Object.entries(channelGroup ?? {}) as [key, callEvents]}
            <p class="text-gray-500 dark:text-gray-400">
              {key}
              {callEvents[0]?.channel}
            </p>
            <div class="call-story">
              <div></div>
              <div></div>
              <div class="relative">
                <div>
                  {#each callEvents as callEvent}
                    <EventRow {callEvent} />
                  {/each}
                </div>
              </div>
            </div>
          {/each}

          <label class="relative inline-flex items-center cursor-pointer">
            <input type="checkbox" bind:checked={showJson} class="sr-only peer" />
            <!--suppress HtmlUnknownTag -->
            <div
              class="w-11 h-6 bg-gray-200 peer-focus:outline-none peer-focus:ring-4 peer-focus:ring-blue-300 dark:peer-focus:ring-blue-800 rounded-full peer dark:bg-gray-700 peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-gray-300 after:border after:rounded-full after:h-5 after:w-5 after:transition-all dark:border-gray-600 peer-checked:bg-blue-600"
            />
            <span class="ml-3 text-sm font-medium text-gray-900 dark:text-gray-300">
              Debug: Show JSON
            </span>
          </label>
          {#if showJson}
            <div class="text-gray-500 dark:text-gray-400">
              <JsonView json={callStory} />
            </div>
          {/if}
        {/if}
      </div>
    </div>
  {/if}
</div>

<style lang="postcss">
  .call-story {
    display: grid;
    grid-template-columns: 200px 1fr;
    grid-gap: 5px;
  }
</style>
