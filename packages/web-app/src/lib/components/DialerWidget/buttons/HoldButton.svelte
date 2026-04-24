<script>
  import PauseIcon from '$lib/components/Icons/PauseIcon.svelte';

  export let hold = false;
</script>

<button
  type="button"
  on:click={() => (hold = !hold)}
  class="rounded-full mr-1 text-white focus:ring-4 focus:outline-none focus:ring-blue-300 font-medium text-sm p-2.5 inline-flex justify-center items-center dark:focus:ring-blue-800"
  class:active={hold}
  class:inactive={!hold}
>
  <PauseIcon />
  <span class="sr-only">
    {#if hold}
      Un hold
    {:else}
      Hold
    {/if}
  </span>
</button>

<style lang="postcss">
  .active {
    @apply bg-blue-700 hover:bg-blue-800 dark:bg-blue-600 dark:hover:bg-blue-700;
  }
  .inactive {
    @apply bg-gray-400 hover:bg-gray-500 dark:bg-gray-400 dark:hover:bg-gray-500;
  }
</style>
