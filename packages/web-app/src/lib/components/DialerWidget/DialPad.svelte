<script>
  import { createEventDispatcher } from 'svelte';

  const dispatch = createEventDispatcher();

  const dialPadNumbers = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '*', '0', '#'];
</script>

<div class="grid grid-cols-3 gap-3">
  {#each dialPadNumbers as number}
    <button
      type="button"
      class="px-6 py-3.5 text-base font-medium text-white bg-blue-700 hover:bg-blue-800 focus:ring-4 focus:outline-none focus:ring-blue-300 rounded-lg text-center dark:bg-blue-600 dark:hover:bg-blue-700 dark:focus:ring-blue-800"
      on:click={() => dispatch('dialKeyPress', { number })}
    >
      {number}
    </button>
  {/each}
</div>
