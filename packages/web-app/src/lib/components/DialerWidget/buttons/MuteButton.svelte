<script lang="ts">
  // `muted` mirrors the call's state for display; `onchange` fires only when
  // the agent clicks, never when the parent syncs `muted` from the session.
  let {
    muted = $bindable(false),
    onchange,
  }: { muted?: boolean; onchange?: (muted: boolean) => void } = $props();
</script>

<button
  type="button"
  onclick={() => {
    muted = !muted;
    onchange?.(muted);
  }}
  class="flex-1 rounded-lg border py-2 text-xs font-semibold transition-colors focus:outline-none focus:ring-2 focus:ring-blue-300 dark:focus:ring-blue-800"
  class:active={muted}
  class:inactive={!muted}
>
  {muted ? 'Unmute' : 'Mute'}
</button>

<style lang="postcss">
  .active {
    @apply border-blue-600 bg-blue-50 text-blue-700 dark:border-blue-500 dark:bg-blue-950 dark:text-blue-300;
  }
  .inactive {
    @apply border-gray-200 bg-white text-gray-600 hover:bg-gray-50 dark:border-gray-700 dark:bg-transparent dark:text-gray-300 dark:hover:bg-gray-800;
  }
</style>
