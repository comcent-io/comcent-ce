<script>
  export let showDialPad = false;
</script>

<button
  type="button"
  on:click={() => (showDialPad = !showDialPad)}
  class="flex-1 rounded-lg border py-2 text-xs font-semibold transition-colors focus:outline-none focus:ring-2 focus:ring-blue-300 dark:focus:ring-blue-800"
  class:active={showDialPad}
  class:inactive={!showDialPad}
>
  Keypad
</button>

<style lang="postcss">
  .active {
    @apply border-blue-600 bg-blue-50 text-blue-700 dark:border-blue-500 dark:bg-blue-950 dark:text-blue-300;
  }
  .inactive {
    @apply border-gray-200 bg-white text-gray-600 hover:bg-gray-50 dark:border-gray-700 dark:bg-transparent dark:text-gray-300 dark:hover:bg-gray-800;
  }
</style>
