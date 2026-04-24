<script lang="ts">
  import Spinner from './Icons/Spinner.svelte';
  export let progress = false;
  export let type: 'button' | 'submit' = 'button';
  export let className = '';

  const buttonColor = {
    default:
      'relative text-white bg-blue-700 hover:bg-blue-800 focus:ring-4 focus:outline-none focus:ring-blue-300 font-medium rounded-lg text-sm w-full sm:w-auto px-5 py-2.5 text-center dark:bg-blue-600 dark:hover:bg-blue-700 dark:focus:ring-blue-800',
    danger:
      'relative focus:outline-none text-white bg-red-700 hover:bg-red-800 focus:ring-4 focus:ring-red-300 font-medium rounded-lg text-sm px-5 py-2.5 me-2 mb-2 dark:bg-red-600 dark:hover:bg-red-700 dark:focus:ring-red-900',
  };

  export let color: keyof typeof buttonColor = 'default';
</script>

<button
  {type}
  disabled={progress}
  class="{buttonColor[color]} {className}"
  {...$$restProps}
  on:click
>
  <span class={progress ? 'opacity-30' : ''}>
    <slot />
  </span>
  {#if progress}
    <span class="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2">
      <Spinner />
    </span>
  {/if}
</button>
