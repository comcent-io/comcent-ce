<script>
  export let hold = false;
</script>

<button
  type="button"
  on:click={() => (hold = !hold)}
  class="flex-1 rounded-lg border py-2 text-xs font-semibold transition-colors focus:outline-none focus:ring-2 focus:ring-blue-300 dark:focus:ring-blue-800"
  class:active={hold}
  class:inactive={!hold}
>
  {hold ? 'Unhold' : 'Hold'}
</button>

<style lang="postcss">
  .active {
    @apply border-amber-500 bg-amber-50 text-amber-700 dark:border-amber-500 dark:bg-amber-950 dark:text-amber-300;
  }
  .inactive {
    @apply border-gray-200 bg-white text-gray-600 hover:bg-gray-50 dark:border-gray-700 dark:bg-transparent dark:text-gray-300 dark:hover:bg-gray-800;
  }
</style>
