<script>
  import { INITIAL_SCALE, scale } from '$lib/scaleStore';

  export let span;
  export let localScale = INITIAL_SCALE;
  scale.subscribe((value) => {
    localScale = value;
  });

  let showTooltip = false;

  const SPAN_COLORS = {
    DIAL_WAIT: '#FFF1BC',
    RINGING: '#FFB7B7',
    ON_CALL: '#64CCC5',
    HOLD: '#8C3333',
    QUEUED: '#A2FF86',
  };

  const SPAN_Z_INDEX = {
    DIAL_WAIT: 0,
    RINGING: 0,
    ON_CALL: 0,
    HOLD: 3,
    QUEUED: 1,
  };

  const SPAN_HEIGHT = {
    ON_CALL: 26,
    DIAL_WAIT: 26,
    RINGING: 26,
    DEFAULT: 18,
  };

  let height = SPAN_HEIGHT[span.type] ?? SPAN_HEIGHT.DEFAULT;
</script>

<div
  class="inline-block absolute"
  on:mouseenter={() => (showTooltip = true)}
  on:mouseleave={() => (showTooltip = false)}
  on:blur={() => (showTooltip = false)}
  on:focus={() => (showTooltip = true)}
  role="graphics-object"
  tabindex="-1"
  style="transform: translateX({span.relativeStartAt * localScale}px); width: {(span.relativeEndAt -
    span.relativeStartAt) *
    localScale}px; height: {height}px; background-color: {SPAN_COLORS[
    span.type
  ]};display: inline-block;z-index:{SPAN_Z_INDEX[span.type]}"
>
  <div
    role="tooltip"
    class="w-max absolute left-0 -bottom-1 h-8 -translate-y-5 z-10 inline-block px-3 py-1.5 text-sm font-medium text-white transition-opacity duration-300 bg-gray-900 rounded-lg shadow-sm tooltip dark:bg-gray-400"
    class:invisible={!showTooltip}
    class:opacity-0={!showTooltip}
  >
    {span.relativeEndAt - span.relativeStartAt}s {span.type}
    <div class="tooltip-arrow"></div>
  </div>
</div>
