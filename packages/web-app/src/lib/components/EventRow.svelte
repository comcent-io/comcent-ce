<script>
  import { INITIAL_SCALE, scale } from '$lib/scaleStore';

  let { callEvent } = $props();
  let localScale = $state(INITIAL_SCALE);
  scale.subscribe((value) => {
    localScale = value;
  });
</script>

<div>
  <div class="inline-block" style="transform: translateX({callEvent.relativeTime * localScale}px);">
    <div style="width: 5px; height: 20px; background-color: red;display: inline-block"></div>
    <span class="text-gray-500 dark:text-gray-400">
      {callEvent.data.event}
    </span>
  </div>
</div>
