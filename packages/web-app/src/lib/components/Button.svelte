<script lang="ts">
  import type { Snippet } from 'svelte';
  import type { HTMLButtonAttributes } from 'svelte/elements';
  import Spinner from './Icons/Spinner.svelte';

  const buttonColor = {
    default:
      'relative text-white bg-blue-700 hover:bg-blue-800 focus:ring-4 focus:outline-none focus:ring-blue-300 font-medium rounded-lg text-sm w-full sm:w-auto px-5 py-2.5 text-center dark:bg-blue-600 dark:hover:bg-blue-700 dark:focus:ring-blue-800',
    danger:
      'relative focus:outline-none text-white bg-red-700 hover:bg-red-800 focus:ring-4 focus:ring-red-300 font-medium rounded-lg text-sm px-5 py-2.5 me-2 mb-2 dark:bg-red-600 dark:hover:bg-red-700 dark:focus:ring-red-900',
  };

  interface Props extends Omit<HTMLButtonAttributes, 'type' | 'color'> {
    progress?: boolean;
    type?: 'button' | 'submit';
    className?: string;
    color?: keyof typeof buttonColor;
    children?: Snippet;
  }

  let {
    progress = false,
    type = 'button',
    className = '',
    color = 'default',
    children,
    ...rest
  }: Props = $props();
</script>

<button {type} disabled={progress} class="{buttonColor[color]} {className}" {...rest}>
  <span class={progress ? 'opacity-30' : ''}>
    {@render children?.()}
  </span>
  {#if progress}
    <span class="absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2">
      <Spinner />
    </span>
  {/if}
</button>
