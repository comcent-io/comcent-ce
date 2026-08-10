<script>
  import { createEventDispatcher } from 'svelte';

  const dispatch = createEventDispatcher();

  const dialPadNumbers = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '*', '0', '#'];
</script>

<div class="grid grid-cols-3 gap-2">
  {#each dialPadNumbers as number}
    <button
      type="button"
      class="rounded-lg bg-gray-100 py-3 text-base font-semibold text-gray-800 transition-colors hover:bg-gray-200 focus:outline-none focus:ring-2 focus:ring-blue-300 dark:bg-gray-800 dark:text-gray-100 dark:hover:bg-gray-700 dark:focus:ring-blue-800"
      on:click={() => dispatch('dialKeyPress', { number })}
    >
      {number}
    </button>
  {/each}
</div>
